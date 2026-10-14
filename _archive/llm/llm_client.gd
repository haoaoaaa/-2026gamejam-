extends Node
## ============================================================================
##  海龟汤「自己打字问」用的最小 LLM 客户端（OpenAI 兼容 /chat/completions）
## ============================================================================
##  key 放在**项目外**的 user://llm.cfg，不会打包进游戏：
##
##      [llm]
##      base_url=https://api.deepseek.com/v1
##      api_key=sk-xxxx
##      model=deepseek-chat
##      timeout=20
##
##  没配（文件不存在 / 缺字段）→ `should_offer()` 为 false，海龟汤面板就**不会**
##  把「自己打字问」这个选项摆出来（连不上就不要出现在界面上）。
##
##  用法：
##      var c := LlmClient.new()
##      add_child(c)                       # _ready() 里读配置
##      c.answered.connect(_on_answered)   # (question, verdict, ok)
##      c.ask("是衣柜里吗？")
##
##  判定只允许三种：是 / 不是 / 无关。模型说什么都过一遍 sanitize()。
## ============================================================================

signal answered(question: String, verdict: String, ok: bool)

const CFG_PATH := "user://llm.cfg"

const VERDICT_YES := "是"
const VERDICT_NO := "不是"
const VERDICT_NA := "无关"

const SOUP_TEXT := "我在寝室里是一个爱笑的人。自从来到这里，我不再笑了。当我离开这里，我又能笑了。"
const SOUP_TRUTH := "李星在和室友刘忆玩捉迷藏。为了赢下这场游戏，她藏进了衣柜，努力憋笑；等她出了衣柜、赢了游戏，她很开心，所以又笑了。"

const SYSTEM_PROMPT := """你在一碗「海龟汤」里扮演刘忆。玩家（李星）要用是 / 不是的问题猜出汤底。

汤面：%s
真实汤底（只有你知道，绝对不许说出来）：%s

规则：
1. 玩家每次只能问一个是 / 不是问题。你只能回答三个词之一：是 / 不是 / 无关。
2. 只要能从汤底判断，就必须回答「是」或「不是」——不要因为怕剧透而回避。
3. 问题与汤底无关、不是一个是 / 否问题、或你判断不了时，回答「无关」。
4. 不要解释、不要标点、不要出现任何别的字。只输出那一个词。"""

## 探针钩子：强制认为「配好了」，这样无 key 也能测「自己打字问」这条路
static var force_offer := false

var base_url := ""
var api_key := ""
var model := ""
var timeout_sec := 20.0
var last_error := ""

## 探针钩子：设了 test_resolver（Callable(question) -> String）就不发请求
var test_resolver: Callable = Callable()

var _http: HTTPRequest = null
var _cache: Dictionary = {}     # 问过的原句 → 判定（同一句不重复花钱）
var _pending := ""
var _busy := false


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.name = "Http"
	_http.timeout = timeout_sec
	_http.request_completed.connect(_on_request_completed)
	add_child(_http)
	load_config()


# ---------------------------------------------------------------- 配置
## 读 user://llm.cfg。**故意不用 ConfigFile**：实测它对「开头有注释行」的
## 小文件会出错或整段读不出来（`parse error ... Expected value, got 'ERROR'`、
## 或 parse 成功但 section 是空的），而这个文件本来就是给玩家用记事本改的。
## 这里自己按行解析：跳过空行与 # / ; 注释，剩下的取 key=value，引号可有可无。
func load_config() -> bool:
	base_url = ""
	api_key = ""
	model = ""
	if not FileAccess.file_exists(CFG_PATH):
		return false
	var text := FileAccess.get_file_as_string(CFG_PATH)
	if text.begins_with("\uFEFF"):
		text = text.substr(1)
	for raw_line in text.split("\n"):
		var line := raw_line.strip_edges()
		if line == "" or line.begins_with("#") or line.begins_with(";"):
			continue
		if not line.contains("="):
			continue
		var eq := line.find("=")
		var key := line.substr(0, eq).strip_edges()
		var val := line.substr(eq + 1).strip_edges()
		if val.length() >= 2:
			if (val.begins_with("\"") and val.ends_with("\"")) or (val.begins_with("'") and val.ends_with("'")):
				val = val.substr(1, val.length() - 2).strip_edges()
		match key:
			"base_url":
				base_url = val
			"api_key":
				api_key = val
			"model":
				model = val
			"timeout":
				if val.is_valid_float():
					timeout_sec = float(val)
	if _http != null:
		_http.timeout = timeout_sec
	return available()


## 真的能发请求（有地址、key、模型名）
func available() -> bool:
	return base_url != "" and api_key != "" and model != ""


## 面板要不要把「自己打字问」摆出来
func should_offer() -> bool:
	return available() or force_offer or test_resolver.is_valid()


func busy() -> bool:
	return _busy


# ---------------------------------------------------------------- 提问
func ask(question: String) -> void:
	var q := question.strip_edges()
	if q == "":
		return
	if _cache.has(q):
		answered.emit(q, str(_cache[q]), true)
		return
	if _busy:
		return
	# 探针：不发网络请求，直接查表
	if test_resolver.is_valid():
		var tv := sanitize(str(test_resolver.call(q)))
		if tv == "":
			# 和真网络那条路保持一致：拿不到可用判定就算失败
			last_error = "模型没有给出可用的回答"
			answered.emit(q, "", false)
			return
		_cache[q] = tv
		answered.emit(q, tv, true)
		return
	if not available():
		last_error = "没有配置模型"
		answered.emit(q, "", false)
		return

	_busy = true
	_pending = q
	var body := {
		"model": model,
		"temperature": 0,
		"max_tokens": 8,
		"stream": false,
		"messages": [
			{"role": "system", "content": SYSTEM_PROMPT % [SOUP_TEXT, SOUP_TRUTH]},
			{"role": "user", "content": q},
		],
	}
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer " + api_key,
	])
	var url := base_url.trim_suffix("/") + "/chat/completions"
	var err := _http.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		_busy = false
		_pending = ""
		last_error = "请求发不出去（错误码 %d）" % err
		answered.emit(q, "", false)


func _on_request_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var q := _pending
	_busy = false
	_pending = ""
	if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
		last_error = "连不上模型（result=%d / HTTP %d）" % [result, code]
		answered.emit(q, "", false)
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	var text := ""
	if parsed is Dictionary and (parsed as Dictionary).has("choices"):
		var choices: Variant = (parsed as Dictionary)["choices"]
		if choices is Array and (choices as Array).size() > 0:
			var first: Variant = (choices as Array)[0]
			if first is Dictionary:
				var msg: Variant = (first as Dictionary).get("message", {})
				if msg is Dictionary:
					text = str((msg as Dictionary).get("content", ""))
	var v := sanitize(text)
	if v == "":
		last_error = "模型没有给出可用的回答"
		answered.emit(q, "", false)
		return
	_cache[q] = v
	answered.emit(q, v, true)


## 只允许 是 / 不是 / 无关，其它一律按「无关」处理。
## 顺序要紧：「不能判断 / 无法 / 无关」里也含「不」或「无」，先判它们。
static func sanitize(raw: String) -> String:
	var t := raw.strip_edges().to_lower()
	if t == "":
		return ""
	for k in ["无关", "无法", "不能", "不知道", "未知", "unknown", "irrelevant"]:
		if t.contains(k):
			return VERDICT_NA
	if t.contains("不是") or t.contains("否") or t.begins_with("no") or t == "n":
		return VERDICT_NO
	if t.contains("是") or t.begins_with("yes") or t == "y":
		return VERDICT_YES
	return VERDICT_NA
