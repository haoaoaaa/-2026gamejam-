extends SceneTree
## ============================================================================
##  《寻星》· 回看 / 自动存档 / 笔记 自检（headless）
## ============================================================================
##  Kerry 这一轮要的三件事都在这条链上：
##    · 对话能反复回看（R / 滚轮向上 / 面板按钮）
##    · 关掉重开能接着上次（SaveGame 写 user://xunxing_save.json）
##    · 笔记要"完整"（对话框里点过的物件也要进 PreludeState.cards）
##
##  这里只测这条链自己的东西，不碰任何小游戏面板 —— 别的 agent 正在改那些
##  面板，探针不该因为它们改到一半而变红。
##
##  ⚠ 这个探针**真的会写 user://xunxing_save.json**（不然没法测读回），
##  所以开跑前先把玩家原本的存档备份下来，结束时原样放回去。
##
##  跑法：
##      godot --headless --path <项目> --script tools/probe_save.gd
##  退出码 0 = 全绿。
## ============================================================================

const SAVE_PATH := "user://xunxing_save.json"
const SAVE_SCRIPT := "res://scripts/prelude/save_game.gd"
const UI_SCRIPT := "res://scripts/ui/prelude_ui.gd"
const RUNTIME_SCRIPT := "res://scripts/ui/dialogue_runtime.gd"
const TITLE_SCENE := "res://scenes/title/title.tscn"
const SCENE_W1 := "res://scenes/week1/week1_1.tscn"
const CAP := 400

var _checks := 0
var _fails := 0
var _backup: PackedByteArray = PackedByteArray()
var _had_backup := false


func _initialize() -> void:
	_run()


func _check(ok: bool, what: String, extra := "") -> void:
	_checks += 1
	if ok:
		print("  ✓ ", what)
	else:
		_fails += 1
		print("  ✗ ", what, ("   ← " + extra) if extra != "" else "")


func _run() -> void:
	await process_frame
	print("========== 回看 / 自动存档 / 笔记 自检 ==========")
	_backup_save()

	var st := root.get_node_or_null("PreludeState")
	var sg := root.get_node_or_null("SaveGame")
	_check(st != null, "PreludeState 自动加载在")
	_check(sg != null, "SaveGame 自动加载在")
	if st == null or sg == null:
		_finish()
		return

	await _test_history_state(st)
	await _test_history_panel()
	await _test_save_guards(st, sg)
	await _test_round_trip(st, sg)
	await _test_bad_saves(sg)
	await _test_runtime(st, sg)
	await _test_title_screen(st, sg)

	# ---- 收尾：把现场恢复干净
	st.call("reset")
	sg.call("clear")
	_restore_save()
	_finish()


# ============================================================================
#  ① PreludeState.history
# ============================================================================

func _test_history_state(st: Node) -> void:
	print("-- ① 回看流水（PreludeState.history）")
	st.call("reset")
	_check((st.get("history") as Array).is_empty(), "reset 之后流水是空的")

	for i in 3:
		st.call("push_history", "刘忆", "第 %d 句" % i)
	var h: Array = st.get("history")
	_check(h.size() == 3, "push_history 追加了 3 条", "实际 %d" % h.size())
	var last: Dictionary = h[2] if h.size() > 2 else {}
	_check(str(last.get("who", "")) == "刘忆" and str(last.get("text", "")) == "第 2 句",
			"最后一条的人名与台词都对", str(last))

	# 旁白（没有说话人）也进流水
	st.call("push_history", "", "（旁白）")
	h = st.get("history")
	_check(str((h[h.size() - 1] as Dictionary).get("who", "x")) == "", "旁白也能进流水（who 为空）")

	st.call("reset")
	for i in CAP + 50:
		st.call("push_history", "", "行 %d" % i)
	h = st.get("history")
	_check(h.size() == CAP, "流水封顶 %d 条" % CAP, "实际 %d" % h.size())
	_check(str((h[0] as Dictionary).get("text", "")) == "行 50",
			"封顶时丢的是最老的、留最近 %d 条" % CAP,
			"首条 = %s" % str((h[0] as Dictionary).get("text", "")))
	st.call("reset")
	_check((st.get("history") as Array).is_empty(), "reset 会把流水一起清掉")
	await process_frame


# ============================================================================
#  ② HistoryPanel
# ============================================================================

func _test_history_panel() -> void:
	print("-- ② 回看面板（PreludeUI.HistoryPanel）")
	var ui: GDScript = load(UI_SCRIPT)
	var hp: Control = ui.HistoryPanel.new()
	root.add_child(hp)
	await process_frame
	_check(not bool(hp.call("is_open")), "初始是关着的")

	hp.call("open", [])
	await process_frame
	await process_frame
	_check(bool(hp.call("is_open")), "open 之后打开")
	_check(bool((hp.get("_empty_hint") as Label).visible), "没有台词时给一句占位提示")

	var hist := [
		{"who": "刘忆", "text": "甲"},
		{"who": "", "text": "乙"},
		{"who": "李星（心里）", "text": "丙"},
	]
	hp.call("open", hist)
	await process_frame
	await process_frame
	var list: Node = hp.get("_list")
	var rows := 0
	var last_text := ""
	var first_text := ""
	for c in list.get_children():
		if c == hp.get("_empty_hint"):
			continue
		rows += 1
		if rows == 1:
			first_text = str((c as RichTextLabel).text)
		last_text = str((c as RichTextLabel).text)
	_check(rows == 3, "三条台词摆了三行", "实际 %d" % rows)
	_check(last_text.contains("丙"), "最后一行是最后说过的那句", last_text)
	_check(last_text.contains("▶"), "最后一行（当前这句）带 ▶ 标记", last_text)
	_check(not first_text.contains("▶"), "前面的行不带 ▶ 标记", first_text)
	_check(not bool((hp.get("_empty_hint") as Label).visible), "有内容时占位提示收起来")
	_check(str((hp.get("_count_label") as Label).text).contains("3"), "抬头写了共几句",
			str((hp.get("_count_label") as Label).text))

	hp.call("scroll_by", 48.0)
	hp.call("scroll_by", -24.0)
	_check(true, "scroll_by 不炸（滚轮 / ↑↓ 走的就是它）")

	var closed_hit := [false]
	hp.closed.connect(func() -> void: closed_hit[0] = true)
	hp.call("close")
	_check(not bool(hp.call("is_open")), "close 之后关掉")
	_check(closed_hit[0], "close 会发 closed 信号")
	hp.queue_free()
	await process_frame


# ============================================================================
#  ③ 不写盘的三种情况
# ============================================================================

func _test_save_guards(st: Node, sg: Node) -> void:
	print("-- ③ 不该写盘的时候坚决不写")
	sg.call("clear")
	st.call("reset")

	sg.call("write", "week1", "", 3)
	_check(not bool(sg.call("has_save")), "没有场景路径（探针 / --script）时不写盘")

	sg.set("disabled", true)
	sg.call("write", "week1", SCENE_W1, 1)
	_check(not bool(sg.call("has_save")), "disabled = true 时不写盘")
	sg.set("disabled", false)

	sg.call("write", "week1", SCENE_W1, 1)
	_check(bool(sg.call("has_save")), "正常调用会写盘（对照组）")
	sg.call("clear")
	await process_frame


# ============================================================================
#  ④ 写 → 读回
# ============================================================================

func _test_round_trip(st: Node, sg: Node) -> void:
	print("-- ④ 存档写进去、读回来")
	st.call("reset")
	sg.call("clear")
	st.call("add_card", "笔记甲")
	st.call("note_examined", "书桌")
	st.call("set_flag", "week1_result_bookshelf", {"ok": true, "code": "053714"})
	st.call("push_history", "刘忆", "存档前那句")

	sg.call("write", "week1", SCENE_W1, 2)
	_check(bool(sg.call("has_save")), "写完之后 has_save 为真")

	var lbl := str(sg.call("label"))
	_check(lbl.contains("第一天"), "存档标题按「第几天」写：%s" % lbl, lbl)
	_check(lbl.contains("第 3 段"), "存档标题写了段号（seq_index 2 → 第 3 段）：%s" % lbl, lbl)
	_check(not lbl.contains("周目"), "存档标题不出现「周目」（Kerry：那等于剧透）", lbl)

	var d: Dictionary = sg.call("peek")
	_check(int(d.get("seq_index", -1)) == 2, "段号存对了")
	_check(str(d.get("scene_path", "")) == SCENE_W1, "场景存对了")
	_check((d.get("cards") as Array).size() == 1, "笔记存进了档")
	_check((d.get("history") as Array).size() == 1, "回看流水存进了档")
	_check((d.get("examined") as Array).has("书桌"), "看过的物件存进了档")

	# 把内存搅乱，再看能不能灌回来
	st.call("reset")
	_check((st.get("cards") as Array).is_empty(), "reset 清掉了笔记（对照组）")
	st.call("set_flag", "walk_resume_active", true)
	var scene := str(sg.call("request_resume"))
	_check(scene == SCENE_W1, "request_resume 返回要切去的场景", scene)
	_check((st.get("cards") as Array).size() == 1, "笔记灌回来了")
	_check(str((st.call("get_flag", "week1_result_bookshelf", {}) as Dictionary).get("code", "")) == "053714",
			"小游戏结果旗标灌回来了")
	_check((st.get("history") as Array).size() == 1, "回看流水灌回来了")
	_check(st.call("get_flag", "walk_resume_active", null) == null,
			"上一轮的走位恢复标记不会被带过来")

	var wrong: Dictionary = sg.call("take_resume", "week2")
	_check(wrong.is_empty(), "章节对不上的存档领不走")
	var right: Dictionary = sg.call("take_resume", "week1")
	_check(int(right.get("seq_index", -1)) == 2, "章节对得上就领到「跳到第几段」",
			str(right))
	var twice: Dictionary = sg.call("take_resume", "week1")
	_check(twice.is_empty(), "同一份续播只能领一次（领走即作废）")

	sg.call("clear")
	_check(not bool(sg.call("has_save")), "clear 之后没有存档了")
	await process_frame


# ============================================================================
#  ⑤ 坏档
# ============================================================================

func _test_bad_saves(sg: Node) -> void:
	print("-- ⑤ 坏档 / 旧版本档一律当没有")
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_string("{这不是 json")
	f.close()
	_check(not bool(sg.call("has_save")), "解析不了的档当没有")

	f = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 999, "scene_path": SCENE_W1, "seq_index": 0}))
	f.close()
	_check(not bool(sg.call("has_save")), "版本号对不上的档当没有")

	f = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 1, "scene_path": "", "seq_index": 0}))
	f.close()
	_check(not bool(sg.call("has_save")), "没有场景路径的档当没有")
	await process_frame


# ============================================================================
#  ⑥ 运行时接线（回看面板 + 探针不落盘）
# ============================================================================

func _test_runtime(st: Node, sg: Node) -> void:
	print("-- ⑥ 对话运行时的接线")
	st.call("reset")
	sg.call("clear")

	var rt_script: GDScript = load(RUNTIME_SCRIPT)
	var rt: Control = rt_script.new()
	# 用一段自造的小剧本，绕开所有小游戏面板（别的 agent 正在改那些）
	rt.set("chapter_id", "week1")
	rt.set("dialogue", {"t1": [["n", "测试旁白一"], ["m", "测试内心二"], ["d", "刘忆", "测试台词三"]]})
	rt.set("sequence_order", ["t1"])
	root.add_child(rt)
	# 运行时是一行一行等玩家推进的（第一行打字机效果），所以这里替玩家连敲几下，
	# 直到流水攒够三行（最多敲 12 次）
	await process_frame
	await process_frame
	for _i in 12:
		if (st.get("history") as Array).size() >= 3:
			break
		rt.call("_on_advance")
		await process_frame
		await process_frame

	var h: Array = st.get("history")
	_check(h.size() >= 3, "台词经过对话框时都记进了流水", "实际 %d" % h.size())
	if h.size() >= 3:
		_check(str((h[0] as Dictionary).get("text", "")) == "测试旁白一", "第一条是旁白",
				str(h[0]))
		_check(str((h[2] as Dictionary).get("who", "")) == "刘忆", "第三条带说话人", str(h[2]))

	_check(rt.get("_history") != null, "运行时建了回看面板")
	_check(rt.get("_history_btn") != null, "运行时建了「回看 (R)」按钮")
	rt.call("_open_history")
	await process_frame
	await process_frame
	var hp: Object = rt.get("_history")
	_check(hp != null and bool(hp.call("is_open")), "打开回看这条链路通")
	rt.call("_toggle_history")
	_check(hp != null and not bool(hp.call("is_open")), "再走一次就收起来")

	_check(not bool(sg.call("has_save")),
			"探针里没有 current_scene → 自动存档一次都没落盘（不污染真存档）")

	rt.queue_free()
	await process_frame


# ============================================================================
#  ⑦ 标题页的「继续上次」
# ============================================================================

func _test_title_screen(st: Node, sg: Node) -> void:
	print("-- ⑦ 标题页")
	st.call("reset")
	sg.call("clear")
	var pack: PackedScene = load(TITLE_SCENE)
	_check(pack != null, "标题场景能加载")
	if pack == null:
		return

	var t1: Node = pack.instantiate()
	root.add_child(t1)
	await process_frame
	_check(not bool(t1.get("_has_save")), "没有存档时不进「有存档」状态")
	_check(t1.get_node_or_null("ResumeButton") == null, "没有存档时不摆「继续上次」")
	t1.queue_free()
	await process_frame

	st.call("push_history", "刘忆", "存档前说过的一句")
	sg.call("write", "week1", SCENE_W1, 1)
	var t2: Node = pack.instantiate()
	root.add_child(t2)
	await process_frame
	_check(bool(t2.get("_has_save")), "有存档时进入「有存档」状态")
	var rb := t2.get_node_or_null("ResumeButton") as Button
	_check(rb != null, "有存档时摆出「继续上次」按钮")
	if rb != null:
		_check(rb.text.contains("第 2 段"), "按钮上写着接着从哪段开始：%s" % rb.text, rb.text)
		_check(not rb.text.contains("周目"), "按钮文案不出现「周目」", rb.text)
	_check(t2.get_node_or_null("NewGameButton") != null,
			"有存档时也有「从头开始」（避免误点一下就把进度删了）")
	t2.queue_free()
	await process_frame


# ============================================================================
#  收尾
# ============================================================================

func _backup_save() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	_had_backup = true
	_backup = FileAccess.get_file_as_bytes(SAVE_PATH)
	print("（已备份玩家现有存档：%d 字节）" % _backup.size())


func _restore_save() -> void:
	if _had_backup:
		var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		if f != null:
			f.store_buffer(_backup)
			f.close()
		print("（玩家存档已还原）")
	elif FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
		print("（探针写的档已删除）")


func _finish() -> void:
	print("=========================================")
	print("共 %d 项检查，失败 %d 项" % [_checks, _fails])
	quit(1 if _fails > 0 else 0)
