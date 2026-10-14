extends SceneTree
## ============================================================================
##  海龟汤自检（只剩 16 题题库这一条路）
## ============================================================================
##  「自己打字问」那条大模型路径已经砍掉了，所以这里只测剩下的那条路：
##    · 面板一开就是 16 个提问按钮，没有"选一种问法"的岔路口、也没有输入框
##    · 问过的按钮变灰、同一个不重复计数、点满 10 个才解锁挑词
##    · 16 选 6：挑错清空重挑、连错 3 次摆出 SoupGiveUp、挑对摊汤底过关
##    · 对外契约：结果 dict 里带 ok / words / given_up，节点名 SoupGiveUp 不变
##
##  跑法：
##      godot --headless --path <项目> --script tools/probe_soup.gd
## ============================================================================

const PANEL_SCRIPT := "res://scripts/week1/panel_soup.gd"
const GATE := 10
const QUESTIONS_N := 16
const PICK := 6
const RIGHT := ["衣柜", "憋笑", "室友", "捉迷藏", "赢", "开心"]
const WRONG_EXTRA := ["床", "卫生间"]

var _checks := 0
var _fails := 0
var _finished: Array = []


func _initialize() -> void:
	_run()


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("  ✓ ", what)
	else:
		_fails += 1
		print("  ✗ ", what)


func _run() -> void:
	print("========== 海龟汤 · 16 题题库自检 ==========")
	await process_frame

	# ---------------------------------------------------------- ① 进来就是题库
	var p := await _make_panel()
	_check((p.get("_question_buttons") as Array).size() == QUESTIONS_N, "16 个提问按钮都建出来了")

	var preset := _node(p, "PresetBox") as Control
	var grid := _node(p, "QuestionGrid") as Control
	_check(preset != null and preset.visible and grid != null and grid.get_child_count() == QUESTIONS_N,
		"进来直接看得见题库（16 个按钮就在原来岔路口的位置）")

	_check(_node(p, "AskBox") == null and _node(p, "AskInput") == null and _node(p, "AskSend") == null,
		"「自己打字问」的输入区已经删干净（AskBox / AskInput / AskSend 都不在）")
	_check(_node(p, "ModeCard") == null and _node(p, "ModePreset") == null and _node(p, "ModeAsk") == null,
		"「选一种问法」的岔路口已经删干净（ModeCard / ModePreset / ModeAsk 都不在）")
	_check(str(p.call("panel_title")) == "海龟汤", "panel_title() 还是「海龟汤」")
	_check(str(p.call("panel_hint")).contains("挑六个"), "panel_hint() 还是原来那句（讲从词里挑六个）")
	_check(int(p.get("_asked_count")) == 0 and not bool(p.get("_words_open")), "开局：一个都没问、挑词还锁着")

	# ---------------------------------------------------------- ② 点问题
	for i in GATE - 1:
		p.call("_on_question_pressed", i)
	_check(int(p.get("_asked_count")) == GATE - 1, "点了 %d 个，计数是 %d" % [GATE - 1, GATE - 1])
	_check(not bool(p.get("_words_open")), "没满 %d 个时挑词还锁着" % GATE)

	p.call("_on_question_pressed", GATE - 1)
	_check(int(p.get("_asked_count")) == GATE, "点满 %d 个" % GATE)
	_check(bool(p.get("_words_open")), "点满之后挑词解锁")
	var qbtn0 := (p.get("_question_buttons") as Array)[0] as Button
	_check(qbtn0 != null and qbtn0.disabled, "问过的按钮变灰")
	_check(str((p.get("_answer_lines") as Array)[0]).contains("刘忆："), "答录里记着「问：… → 刘忆：…」")

	# 同一个问题再点一次：既不重复计数，也不往答录里追新的一行
	var log_before: int = (p.get("_answer_lines") as Array).size()
	p.call("_on_question_pressed", 0)
	_check(int(p.get("_asked_count")) == GATE, "重复点同一个不重复计数")
	_check((p.get("_answer_lines") as Array).size() == log_before, "重复点同一个不再追一行答录")

	# 剩下的 6 题也都点得动
	for i in range(GATE, QUESTIONS_N):
		p.call("_on_question_pressed", i)
	_check(int(p.get("_asked_count")) == QUESTIONS_N, "剩下 6 题也都点得动，计数到 %d" % QUESTIONS_N)
	var all_disabled := true
	for b in p.get("_question_buttons"):
		if not (b as Button).disabled:
			all_disabled = false
	_check(all_disabled, "16 个提问按钮全变灰")

	# ---------------------------------------------------------- ③ 挑错
	_pick_wrong(p)
	_check(not bool(p.get("_win")), "第一次挑错不算过关")
	_check(str(p.get("_feedback").text).contains("回去再想想"), "第一次挑错给那句方向提示")
	_check((p.get("_picked") as Array).is_empty(), "挑错的词被清空")
	_check((p.get("_answer_lines") as Array).size() == QUESTIONS_N, "挑错不弄丢答录")
	_check(_node(p, "SoupGiveUp") == null, "连错不到 3 次不摆出口按钮")

	_pick_wrong(p)
	_check(not bool(p.get("_win")), "第二次挑错还是不算过关")
	_check(_node(p, "SoupGiveUp") == null, "连错 2 次仍然没有出口按钮")

	_pick_wrong(p)
	var give := _node(p, "SoupGiveUp") as Button
	_check(give != null, "连错 3 次才摆出出口按钮（名字固定 SoupGiveUp）")
	_check(str(p.get("_feedback").text).contains("藏在哪儿"), "第三次给的是「汤底的结构」那句")

	# ---------------------------------------------------------- ④ 挑对过关
	for w in RIGHT:
		p.call("_on_word_pressed", w)
	_check(bool(p.get("_win")), "挑对了就过关")
	_check((p.get("_picked") as Array).size() == PICK, "挑中的是 %d 个词" % PICK)
	_check(not bool(p.get("_given_up")), "挑对过关时 given_up 是 false")
	all_disabled = true
	for b in p.get("_question_buttons"):
		if not (b as Button).disabled:
			all_disabled = false
	_check(all_disabled, "过关后 16 个提问按钮全禁用")

	var rich := _node(p, "SoupAnswer") as RichTextLabel
	_check(rich != null and rich.text.contains("捉迷藏") and rich.text.contains("憋着"), "摊开了完整汤底")
	_check(str(p.call("_answer_bbcode")).contains("[color=#c8564f]衣柜[/color]"), "摊牌时「衣柜」标红")

	var ok_btn := _node(p, "SoupDone") as Button
	if ok_btn != null:
		ok_btn.pressed.emit()
	var got: Dictionary = _finished[0] if _finished.size() > 0 else {}
	_check(bool(got.get("ok", false)), "收尾结果里 ok = true")
	_check((got.get("words", []) as Array).size() == PICK, "收尾时把 %d 个词交给了运行时" % PICK)
	_check(got.has("given_up") and not bool(got.get("given_up")), "收尾结果里 given_up = false")
	_check(str(got.get("id", "")) == "soup", "收尾结果里带着面板 id")

	p.queue_free()
	await process_frame

	# ---------------------------------------------------------- ⑤ 连错 3 次后放弃
	var p2 := await _make_panel()
	for i in GATE:
		p2.call("_on_question_pressed", i)
	_pick_wrong(p2)
	_pick_wrong(p2)
	_pick_wrong(p2)
	var give2 := _node(p2, "SoupGiveUp") as Button
	if give2 != null:
		give2.pressed.emit()
	_check(bool(p2.get("_win")), "按下「不想了，直接看汤底」也算过关")
	_check(bool(p2.get("_given_up")), "放弃时 _given_up 是 true")
	_check(_node(p2, "SoupAnswer") != null, "放弃也一样摊开汤底")

	var done2 := _node(p2, "SoupDone") as Button
	if done2 != null:
		done2.pressed.emit()
	var got2: Dictionary = _finished[1] if _finished.size() > 1 else {}
	_check(bool(got2.get("ok", false)), "放弃的结果里 ok 也是 true")
	_check((got2.get("words", []) as Array).size() == PICK, "放弃也照样交出 %d 个词" % PICK)
	_check(got2.has("given_up") and bool(got2.get("given_up")), "放弃的结果里 given_up = true")

	p2.queue_free()
	await process_frame

	print("=========================================")
	print("共 %d 项检查，失败 %d 项" % [_checks, _fails])
	quit(1 if _fails > 0 else 0)


## 建一个面板（不再需要模拟"没配模型"，那条路已经没了）
func _make_panel() -> Control:
	var panel_script: GDScript = load(PANEL_SCRIPT)
	var panel: Control = panel_script.new()
	panel.finished.connect(func(result: Dictionary) -> void: _finished.append(result))
	panel.call("setup", {"id": "soup"})
	root.add_child(panel)
	await process_frame
	return panel


## 在树里按名字找节点（探针按名字认 UI，不认成员变量）
func _node(root_node: Node, wanted: String) -> Node:
	var stack: Array = [root_node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if str(n.name) == wanted:
			return n
		for c in n.get_children():
			stack.append(c)
	return null


## 故意挑一组错的六个词：4 个是对的 + 床 / 卫生间 两个不是
func _pick_wrong(panel: Control) -> void:
	for w in RIGHT.slice(0, 4):
		panel.call("_on_word_pressed", w)
	for w in WRONG_EXTRA:
		panel.call("_on_word_pressed", w)
