extends SceneTree
## ============================================================================
##  《寻星》· 二周目端到端自检（headless，不用开游戏窗口）
## ============================================================================
##  二周目是"自白 → 现场走位 → 推理问答面板 → 教室对话 → 不在场证明面板 → 自白"
##  拼起来的，全部靠 flag 串；这里按真实流程整幕跑一遍：
##    ① 静态检查：段名 / 面板登记 / 走位房间 / peek 名字 / 背景键，以及
##       week2_1.gd 里写的段名与 json 的键是否一一对应；
##    ② 一路点到幕间：面板一开就替玩家"过关"（close_panel），
##       走位一触发就把房间里每件东西标成"看过"（这一幕要求全看），再重建场景继续；
##    ③ 收尾检查：面板顺序、走位房间、幕间、每个面板的结果 flag。
##
##  跑法：
##    godot --headless --path <项目> --script tools/probe_week2.gd
##  退出码 0 = 全绿。
## ============================================================================

const DATA := "res://data/week2_dialogue.json"
const ROOMS := "res://data/prelude_rooms.json"
const SCENE := "res://scenes/week2/week2_1.tscn"
const HOST_SCRIPT := "res://scripts/prelude/week2_1.gd"
const WEEK1_SCENE := "res://scenes/week1/week1_1.tscn"
## 二周目（前日谈已经演过）播完的去处：bridge / 结尾 CG 还没到位，先回标题页。
const TITLE_SCENE := "res://scenes/title/title.tscn"
## 「前日谈已经演过」标记：它在一周目收尾之前就立起来了，二周目据此不再回前日谈。
const PRELUDE_DONE_FLAG := "prelude_done"
const CHAPTER := "week2"
const SEQS := ["s0_scene", "s1_method", "s2_motive", "s3_classroom", "s4_alibi", "s5_cup", "s6_truth"]
const SPACES := ["hallway", "classroom", "montage", "roofline", "dorm_corridor", "dorm_room", "black"]
const WALK_ROOM := "dorm_after"
const EXPECT_PANELS := ["slant", "reason", "alibi", "circle"]
## 这一幕的走位要求"每一件都看过"，所以没有 ["goal"]；追加台词靠"走位里看过的物件"触发，
## 房里的第一件东西是药瓶 —— 回来之后第一句就该是它的追加台词。
const FIRST_PEEK := "药瓶"
## 【坑】必须用 preload 而不是全局类名：--script 模式下 .godot 里的
## global_script_class_cache 是旧的，新加的 class_name 会 "not declared"。
const WEEK1_PANELS := preload("res://scripts/week1/week1_panels.gd")
const WEEK2_PANELS := preload("res://scripts/week2/week2_panels.gd")

var _fails := 0
var _checks := 0
var _seen_panels: Array = []
var _seen_rooms: Array = []


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	print("========== 二周目 端到端自检 ==========")
	var st := root.get_node_or_null("PreludeState")
	if st == null:
		print("✗ 找不到 PreludeState 自动加载")
		quit(1)
		return

	_static_checks()

	st.call("reset")
	# 新链里二周目是在前日谈之后才播的：把 prelude_done 立起来，这一遍跑的才是主流程的状态。
	st.call("set_flag", PRELUDE_DONE_FLAG, true)
	var host: Node = await _make_host()
	var rt: Node = _runtime_of(host)
	_check(rt != null, "二周目场景（week2_1.tscn）建起来了", _runtime_debug(host) if rt == null else "")
	if rt == null:
		_finish()
		return

	# ---- 一路点到幕间
	var steps := 0
	while steps < 8000:
		steps += 1
		if bool(host.get("_intermission")):
			break
		var p: Node = _panel_of(rt)
		if p != null:
			var pid := _panel_id(p)
			var want := _panel_script(pid)
			var got := str((p.get_script() as Script).resource_path) if p.get_script() is Script else ""
			_check(got == want, "面板 %s 挂的脚本是登记表里那个" % pid, "期望 %s 实际 %s" % [want, got])
			_seen_panels.append(pid)
			# 替玩家过关：面板的 finished 会由 close_panel 发出来
			p.call("close_panel", {})
			await process_frame
			await process_frame
			_check(st.call("get_flag", "week1_result_" + pid, null) != null,
					"过关结果写进了 week1_result_%s" % pid)
			_check(_panel_of(rt) == null, "过关后面板收掉了")
			continue
		if bool(st.call("get_flag", "walk_resume_active", false)):
			await _handle_walk(st, host, rt)
			host = _cur_host()
			rt = _runtime_of(host)
			if rt == null:
				_check(false, "走位之后对话场景重建失败")
				break
			continue
		if _choice_open(rt):
			_pick_choice(rt, 0)
		else:
			rt.call("_on_advance")
		await process_frame
		await process_frame

	_check(bool(host.get("_intermission")), "整幕点到了幕间（二周目结束）", "点了 %d 步" % steps)
	_check(_seen_panels == EXPECT_PANELS, "推理问答 / 不在场证明两个面板按顺序弹过了", str(_seen_panels))
	_check(_seen_rooms == [WALK_ROOM], "唯一一次走位在案发后的寝室（dorm_after）", str(_seen_rooms))
	if rt != null:
		# 最后一段（s6_truth）播完之后 _next_sequence() 会把 _seq_index 再 +1（= 段数），
		# 然后才发 sequence_finished —— 停在「段数」上就是整幕走完了。
		_check(int(rt.get("_seq_index")) == SEQS.size(),
				"%d 段全部播完（停在段数 %d 上）" % [SEQS.size(), SEQS.size()],
				"_seq_index=%d" % int(rt.get("_seq_index")))
	for id in EXPECT_PANELS:
		_check(st.call("get_flag", "week1_result_" + id, null) != null, "%s 有完成记录" % id)

	# 新链：这一幕跑的时候前日谈已经演过，所以二周目播完是回标题页，而不是再演一遍前日谈。
	var hint := _title_text(host.get("_label"))
	_check(hint.contains("标题"), "幕间告诉玩家二周目播完回标题页", hint)
	_check(str(host.call("next_scene_after_chapter")) == TITLE_SCENE,
			"二周目播完的下一幕是标题页", str(host.call("next_scene_after_chapter")))

	_finish()


func _finish() -> void:
	print("=========================================")
	print("共 %d 项检查，失败 %d 项" % [_checks, _fails])
	quit(1 if _fails > 0 else 0)


# ---------------------------------------------------------------- 走位站点

func _handle_walk(st: Node, host: Node, rt: Node) -> void:
	var goal := str(st.call("get_flag", "walk_goal_active", ""))
	var room := str(st.call("get_flag", "walk_room", ""))
	var seq_i := int(st.call("get_flag", "walk_resume_seq", -1))
	var row_i := int(st.call("get_flag", "walk_resume_row", -1))
	var back := str(st.call("get_flag", "walk_return_scene", ""))
	_seen_rooms.append(room)
	print("  · 走位：房间 %s，目标「%s」，第 %d 段第 %d 行，回 %s" % [room, goal, seq_i, row_i, back])
	_check(room == WALK_ROOM, "走的是案发后的寝室", room)
	_check(goal == "", "这一幕要求「每一件都看过」，所以没有单独的目标物件", goal)
	_check(back.ends_with("week2_1.tscn"), "记下了回二周目这一幕的场景", back)

	# 玩家在走位里把房间里的每件东西都看了（这一幕的过关条件就是"都看过"）
	var names := _room_item_names(room)
	_check(names.size() >= 5, "案发现场的可看物件够多", str(names))
	for nm in names:
		st.call("note_examined", str(nm))

	await process_frame
	await process_frame
	_free_walk_scene()
	if is_instance_valid(host):
		root.remove_child(host)
		host.free()
	await process_frame
	await process_frame
	var h2: Node = await _make_host()
	var rt2: Node = _runtime_of(h2)
	_check(rt2 != null, "看完回来，对话场景建起来了")
	if rt2 == null:
		return
	_check(int(rt2.get("_seq_index")) == seq_i, "回来之后停在走位时那一段",
			"期望 %d 实际 %d" % [seq_i, int(rt2.get("_seq_index"))])
	_check(int(rt2.get("_row_index")) > row_i, "回来之后确实往下播了",
			"_row_index=%d（恢复点 %d）" % [int(rt2.get("_row_index")), row_i])
	_check(rt2.get("_title_layer") == null, "回来之后没有重播标题卡")
	_check(not bool(rt2.get("_free_mode")), "回来之后没有掉进「查看完毕」兜底模式")
	var want := _first_peek_line(FIRST_PEEK)
	var body := rt2.get_node_or_null("DialogueBox/Panel/VB/BodyText")
	var got := "" if body == null else str(body.get("text"))
	_check(got == want, "接着播的正是「%s」的追加台词" % FIRST_PEEK,
			"期望「%s」实际「%s」" % [want, got])


var _host: Node = null


func _cur_host() -> Node:
	return _host


func _make_host() -> Node:
	if is_instance_valid(_host):
		root.remove_child(_host)
		_host.free()
	_host = (load(SCENE) as PackedScene).instantiate()
	root.add_child(_host)
	if _runtime_of(_host) == null:
		await process_frame
		await process_frame
	return _host


func _runtime_of(host: Node) -> Node:
	if not is_instance_valid(host):
		return null
	var v: Variant = host.get("runtime")
	if v is Node:
		return v as Node
	return host.get_node_or_null("Runtime")


func _runtime_debug(host: Node) -> String:
	if not is_instance_valid(host):
		return "host 已释放"
	var v: Variant = host.get("runtime")
	var sc: Variant = host.get_script()
	return "children=%s runtime=%s script=%s" % [
			str(host.get_children()), str(v),
			str((sc as Script).resource_path) if sc is Script else "null"]


func _panel_of(rt: Node) -> Node:
	if rt == null:
		return null
	var p: Variant = rt.get("_panel")
	if p is Node and is_instance_valid(p as Node):
		return p as Node
	return null


func _panel_id(p: Node) -> String:
	var ctx: Variant = p.get("_ctx")
	if ctx is Dictionary:
		return str((ctx as Dictionary).get("id", ""))
	return ""


func _choice_open(rt: Node) -> bool:
	var c: Variant = rt.get("_choice")
	if c == null or not (c is Object):
		return false
	return bool((c as Object).call("is_open"))


func _pick_choice(rt: Node, index: int) -> void:
	var c: Variant = rt.get("_choice")
	if c is Object and (c as Object).has_method("_on_pressed"):
		(c as Object).call("_on_pressed", index)
	else:
		rt.call("_on_choice", index)


func _free_walk_scene() -> void:
	for c in root.get_children():
		if str(c.name) == "PreludeWalk":
			root.remove_child(c)
			c.free()


# ---------------------------------------------------------------- 登记表

func _has_panel(pid: String) -> bool:
	return WEEK1_PANELS.has_panel(pid) or WEEK2_PANELS.has_panel(pid)


func _panel_script(pid: String) -> String:
	var p := WEEK1_PANELS.script_for(pid)
	if p == "":
		p = WEEK2_PANELS.script_for(pid)
	return p


# ---------------------------------------------------------------- 静态检查

func _static_checks() -> void:
	var inst: Node = (load(HOST_SCRIPT) as GDScript).new()
	_check(inst.data_path() == DATA, "week2_1.gd 指向的对话数据就是 week2_dialogue.json", inst.data_path())
	_check(inst.chapter_id() == CHAPTER, "week2_1.gd 的章节 id 是 %s" % CHAPTER, inst.chapter_id())
	var seqs: Array = inst.chapter_sequences()
	_check(seqs == SEQS, "week2_1.gd 的段名与自检里写的一致", str(seqs))
	inst.free()

	# 章节链（新）：一周目六关 → 前日谈（prelude_1 → prelude_2）→ 一周目收尾（s6_ending）
	#               → 二周目 → 标题页。
	# 前日谈演过（prelude_done）之后，二周目播完不再接前日谈（否则前日谈会演两遍，
	# 而 prelude_2 的出口又会把玩家送回一周目收尾 → 二周目 → 前日谈，成环）。
	var w1: Dictionary = (load("res://scripts/prelude/week1_1.gd") as GDScript).get_script_constant_map()
	var w2: Dictionary = (load(HOST_SCRIPT) as GDScript).get_script_constant_map()
	_check(_is_scene(w1.get("WEEK2_SCENE", "")), "一周目（收尾播完）接的是二周目",
			str(w1.get("WEEK2_SCENE", "")))
	_check(_is_scene(w1.get("PRELUDE_1_SCENE", "")), "一周目六关播完接的是前日谈",
			str(w1.get("PRELUDE_1_SCENE", "")))
	_check(_is_scene(w2.get("TITLE_SCENE", "")), "二周目播完（前日谈已演过）回标题页",
			str(w2.get("TITLE_SCENE", "")))
	_check(_is_scene(w2.get("PRELUDE_1_SCENE", "")), "老存档（前日谈还没演）从二周目续上仍接前日谈",
			str(w2.get("PRELUDE_1_SCENE", "")))

	var w2_inst: Node = (load(HOST_SCRIPT) as GDScript).new()
	var st2 := root.get_node_or_null("PreludeState")
	if st2 != null:
		st2.call("set_flag", PRELUDE_DONE_FLAG, false)
		_check(str(w2_inst.call("next_scene_after_chapter")) == str(w2.get("PRELUDE_1_SCENE", "")),
				"前日谈没演过 → 二周目播完接前日谈（旧行为保留）",
				str(w2_inst.call("next_scene_after_chapter")))
		st2.call("set_flag", PRELUDE_DONE_FLAG, true)
		_check(str(w2_inst.call("next_scene_after_chapter")) == str(w2.get("TITLE_SCENE", "")),
				"前日谈演过 → 二周目播完回标题页",
				str(w2_inst.call("next_scene_after_chapter")))
		st2.call("set_flag", PRELUDE_DONE_FLAG, false)
	w2_inst.free()

	var p2_src := FileAccess.get_file_as_string("res://scripts/prelude/prelude_2.gd")
	_check(p2_src.contains(WEEK1_SCENE), "前日谈演完能回到一周目（prelude_2 里指向 week1_1.tscn）")
	_check(p2_src.contains(PRELUDE_DONE_FLAG),
			"前日谈的出口会立起 %s（一周目据此只播收尾）" % PRELUDE_DONE_FLAG)
	_check(not p2_src.contains("week2_1.tscn"), "前日谈演完不再直接跳二周目（改回一周目收尾）")
	_check(p2_src.contains("PreludeState.reset()"), "「回到开头」仍然清掉状态（重开一遍是干净的）")

	var data: Variant = _read_json(DATA)
	_check(data is Dictionary, "week2_dialogue.json 能解析成字典")
	if not (data is Dictionary):
		return
	var chap: Variant = (data as Dictionary).get(CHAPTER, null)
	_check(chap is Dictionary, "里有 chapter 键 %s" % CHAPTER)
	if not (chap is Dictionary):
		return
	_check((chap as Dictionary).keys() == SEQS, "json 里的段名与 week2_1.gd 一一对应",
			str((chap as Dictionary).keys()))

	var room_items := _room_items()
	_check(room_items.has(WALK_ROOM), "prelude_rooms.json 里有 %s（案发后的寝室）" % WALK_ROOM)
	_check((room_items.get(WALK_ROOM, []) as Array).size() >= 5,
			"案发现场摆的物件够多", str(room_items.get(WALK_ROOM, [])))

	var panel_ids: Array = []
	for sid in SEQS:
		var rows: Variant = (chap as Dictionary).get(sid, null)
		_check(rows is Array, "序列 %s 存在" % sid)
		if not (rows is Array):
			continue
		var room_id := ""
		for i in (rows as Array).size():
			var r: Variant = (rows as Array)[i]
			if not (r is Array) or (r as Array).is_empty():
				continue
			var a := r as Array
			var kind := str(a[0])
			match kind:
				"panel":
					var pid := str(a[1])
					panel_ids.append(pid)
					_check(_has_panel(pid), "面板 %s 在登记表里" % pid)
					var sp := _panel_script(pid)
					_check(sp != "" and ResourceLoader.exists(sp), "面板 %s 的脚本文件存在" % pid, sp)
				"room":
					room_id = str(a[1])
					_check(room_items.has(room_id), "房间 %s 在 prelude_rooms.json 里" % room_id)
				"goal":
					var gname := str(a[1])
					_check((room_items.get(room_id, []) as Array).has(gname),
							"目标物件「%s」确实在房间 %s 的 items 里" % [gname, room_id])
				"peek":
					var pname := str(a[1])
					_check((room_items.get(room_id, []) as Array).has(pname),
							"peek 物件「%s」确实在房间 %s 的 items 里" % [pname, room_id])
				"space":
					_check(SPACES.has(str(a[1])), "背景键 %s 有效" % str(a[1]))
				"title", "n", "m", "d", "card", "choice", "show", "hide", "who", "item", "free":
					pass
				_:
					_check(false, "序列 %s 第 %d 行是未知行类型 %s" % [sid, i, kind])
	_check(panel_ids == EXPECT_PANELS, "整幕里两个面板的顺序对", str(panel_ids))


# ---------------------------------------------------------------- 工具

func _room_items() -> Dictionary:
	var out: Dictionary = {}
	var rooms_data: Variant = _read_json(ROOMS)
	if not (rooms_data is Dictionary):
		return out
	var rooms: Variant = (rooms_data as Dictionary).get("rooms", {})
	if not (rooms is Dictionary):
		return out
	for rid in (rooms as Dictionary).keys():
		var it: Array = []
		var rv: Variant = (rooms as Dictionary)[rid]
		if rv is Dictionary and (rv as Dictionary).get("items", null) is Array:
			for it_row in ((rv as Dictionary)["items"] as Array):
				if it_row is Array and (it_row as Array).size() >= 6:
					it.append(str((it_row as Array)[5]))
		out[str(rid)] = it
	return out


func _room_item_names(room_id: String) -> Array:
	return _room_items().get(room_id, []) as Array


func _is_scene(path: Variant) -> bool:
	var p := str(path)
	return p.begins_with("res://") and p.ends_with(".tscn") and ResourceLoader.exists(p)


## 把一个节点（Label，或含 Label 的容器）上的文字都收起来，
## 用来断言"幕间提示 / 标题卡上写的到底是什么"。
func _title_text(node: Variant) -> String:
	var out: Array = []
	_collect_texts(node, out)
	return " | ".join(out)


func _collect_texts(node: Variant, out: Array) -> void:
	if not (node is Node):
		return
	var n := node as Node
	if n is Label:
		out.append((n as Label).text)
	for c in n.get_children():
		_collect_texts(c, out)


func _check(cond: bool, label: String, detail := "") -> void:
	_checks += 1
	var tail := ("（%s）" % detail) if detail != "" else ""
	if cond:
		print("  ✓ ", label, tail)
	else:
		_fails += 1
		print("  ✗ ", label, tail)


func _read_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var txt := f.get_as_text()
	f.close()
	return JSON.parse_string(txt)


func _line_text(row: Variant) -> String:
	if not (row is Array) or (row as Array).is_empty():
		return ""
	var a := row as Array
	match str(a[0]):
		"n", "m", "card":
			return str(a[1]) if a.size() >= 2 else ""
		"d":
			return str(a[2]) if a.size() >= 3 else ""
	return ""


func _first_peek_line(item_name: String) -> String:
	var data: Variant = _read_json(DATA)
	if not (data is Dictionary):
		return ""
	var chap: Variant = (data as Dictionary).get(CHAPTER, null)
	if not (chap is Dictionary):
		return ""
	for key in (chap as Dictionary).keys():
		var rows: Variant = (chap as Dictionary)[key]
		if not (rows is Array):
			continue
		for r in (rows as Array):
			if not (r is Array) or (r as Array).size() < 3:
				continue
			var a := r as Array
			if str(a[0]) != "peek" or str(a[1]) != item_name:
				continue
			if not (a[2] is Array):
				continue
			for inner in (a[2] as Array):
				var t := _line_text(inner)
				if t != "":
					return t
	return ""
