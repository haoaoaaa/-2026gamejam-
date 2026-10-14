extends Node
## ============================================================================
##  《寻星》—— 自动存档（Autoload: SaveGame）
## ============================================================================
##  玩家要的是「关掉重开能接着上次继续」，所以这里不设"手动存档点"，
##  而是在**每一步可恢复的位置**自动写一次（见 dialogue_runtime 里的 _autosave）：
##    · 每进入一段（sequence）开头
##    · 小游戏面板出结果之后
##    · 记下一条笔记之后
##  写的是 JSON（user://xunxing_save.json），内容分三块：
##    · 位置：chapter_id / scene_path / seq_index
##    · 进度：PreludeState 的 flags（含各关结果 week1_result_*）
##    · 资料：PreludeState 的 cards（笔记）与 examined（看过的物件）
##
##  为什么不存"段内的第几行"：一段里的前面那些行（["space"]/["show"]/["item"]…）
##  是在搭场景状态，跳过它们会导致读档后背景/立绘/热区全错。
##  所以恢复点是**段首**，读档最多让玩家重看一小段，但画面一定是自洽的。
##
##  【坑】探针（probe_*.gd）会在 headless 里造运行时，那里没有 current_scene，
##  拿不到场景路径。没有场景路径就没有可恢复的位置 —— 这种调用一律不写盘，
##  免得把玩家真正的存档覆盖成一份"读不回来"的档。
## ============================================================================

const SAVE_PATH := "user://xunxing_save.json"
const SAVE_VERSION := 1

## 章节 id → 给玩家看的名字（标题界面那行"继续上次"）
## 【Kerry 的一句话】「不必出现类似"一周目"之类的词 —— 你开头就写一周目
## 不就是剧透了有二周目吗」。所以这里按"第几天"来写，不写周目。
const CHAPTER_NAME := {
	"week1": "第一天",
	"week2": "第二天",
	"act1": "前日谈",
	"act2": "前日谈",
}

## 探针可以把它关掉，彻底禁止写盘
var disabled := false

## 「继续上次」被按下之后，这里存着还没被运行时领走的那份档
var _resume_pending := false
var _resume_data: Dictionary = {}


# ============================================================================
#  写
# ============================================================================

## 写一份档。scene_path 为空表示"这次调用没有可恢复的位置"，直接不写。
func write(chapter_id: String, scene_path: String, seq_index: int) -> void:
	if disabled or scene_path == "":
		return
	var payload := {
		"version": SAVE_VERSION,
		"chapter_id": chapter_id,
		"scene_path": scene_path,
		"seq_index": seq_index,
		"cards": PreludeState.cards.duplicate(),
		"flags": _flags_to_json(PreludeState.flags),
		"examined": PreludeState.examined.duplicate(),
		"history": _tail(PreludeState.history, 400),
		"saved_at": Time.get_datetime_string_from_system(false, true),
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("[SaveGame] 写不进存档：%s" % SAVE_PATH)
		return
	f.store_string(JSON.stringify(payload, "\t"))
	f.close()


## flags 里可能混进不能进 JSON 的东西（Vector / 节点引用之类），
## 写盘前统一过一遍：只留下 JSON 原生的类型。
func _flags_to_json(flags: Dictionary) -> Dictionary:
	var out := {}
	for k in flags.keys():
		var v: Variant = flags[k]
		if v is bool or v is int or v is float or v is String:
			out[str(k)] = v
		elif v is Array:
			out[str(k)] = v.duplicate()
		elif v is Dictionary:
			out[str(k)] = v.duplicate()
	return out


func _tail(arr: Array, n: int) -> Array:
	if arr.size() <= n:
		return arr.duplicate()
	return arr.slice(arr.size() - n, arr.size())


# ============================================================================
#  读
# ============================================================================

func has_save() -> bool:
	return not peek().is_empty()


## 读出存档（不做任何状态改动）；坏档 / 版本不对一律当没有
func peek() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	f.close()
	# 用 JSON.new().parse() 而不是 JSON.parse_string()：坏档时后者会往日志里
	# 打一条 ERROR，而我们本来就打算把坏档当"没有存档"，不该吓玩家一跳。
	var j := JSON.new()
	if j.parse(txt) != OK or not (j.data is Dictionary):
		return {}
	var d := j.data as Dictionary
	if int(d.get("version", 0)) != SAVE_VERSION:
		return {}
	if str(d.get("scene_path", "")) == "":
		return {}
	return d


## 标题界面那行按钮上写什么
func label() -> String:
	var d := peek()
	if d.is_empty():
		return ""
	var ch := str(d.get("chapter_id", ""))
	var name := str(CHAPTER_NAME.get(ch, ch))
	var seg := int(d.get("seq_index", 0)) + 1
	return "%s · 第 %d 段" % [name, maxi(1, seg)]


func saved_at() -> String:
	return str(peek().get("saved_at", ""))


# ============================================================================
#  继续上次
# ============================================================================

## 标题界面按「继续上次」时调用：把资料灌回 PreludeState，并记下"待领走"。
## 返回要切去的场景路径（空串表示没有可继续的档）。
func request_resume() -> String:
	var d := peek()
	if d.is_empty():
		return ""
	PreludeState.cards = (d.get("cards", []) as Array).duplicate(true)
	PreludeState.flags = (d.get("flags", {}) as Dictionary).duplicate(true)
	PreludeState.examined = (d.get("examined", []) as Array).duplicate(true)
	PreludeState.history = (d.get("history", []) as Array).duplicate(true)
	# 上一轮"走位恢复"用的临时标记不能跨存档带过来：它指向的是上一段的位置，
	# 带过来会让 runtime 以为"刚走完房间回来"，把指针推到错的地方。
	PreludeState.flags.erase("walk_resume_active")
	PreludeState.flags.erase("walk_resume_ok")
	_resume_pending = true
	_resume_data = d
	return str(d.get("scene_path", ""))


## 运行时开局来领"要跳过的段数"。只有章节对得上才认，领走即作废。
func take_resume(chapter_id: String) -> Dictionary:
	if not _resume_pending:
		return {}
	var d := _resume_data
	# 章节对不上就**原样留着**：运行时每一段都会来问一次（换章、重进都可能问），
	# 要是这一问就把"待领"状态消耗掉，玩家真进到那一段时反而续不上了。
	if str(d.get("chapter_id", "")) != chapter_id:
		return {}
	_resume_pending = false
	_resume_data = {}
	return {"seq_index": int(d.get("seq_index", 0)), "saved_at": str(d.get("saved_at", ""))}


func clear() -> void:
	_resume_pending = false
	_resume_data = {}
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
		# 兜底：globalize 在个别平台上拿不到时，用 res:// 之外的相对写法再试一次
		if FileAccess.file_exists(SAVE_PATH):
			var dir := DirAccess.open("user://")
			if dir != null:
				dir.remove("xunxing_save.json")
