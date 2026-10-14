extends SceneTree
## ============================================================================
##  《寻星》· 一周目端到端自检（headless，不用开游戏窗口）
## ============================================================================
##  一周目是"对话 → 小游戏面板 → 走位 → 对话"拼起来的，链条长、又全靠 flag 串，
##  所以这里把它整幕按真实流程跑一遍：
##    ① 数据层静态检查：段/面板/走位目标/房间/peek 名字是不是都对得上；
##    ② 一路点到幕间：面板一开就替玩家"过关"（close_panel），
##       走位一旦触发就检查恢复点、记下"看过目标物件"、重建场景继续；
##    ③ 结束时检查幕间文案与所有面板的结果 flag。
##
##  跑法：
##    godot --headless --path <项目> --script tools/probe_week1.gd
##  退出码 0 = 全绿。
## ============================================================================

const DATA := "res://data/week1_dialogue.json"
const ROOMS := "res://data/prelude_rooms.json"
const SCENE := "res://scenes/week1/week1_1.tscn"
const CHAPTER := "week1"
## 一周目一共 7 段：六关 + 收尾。收尾（["title", "第二天", "寝室里没有人"]）已经从
## s5_wardrobe 尾部拆成独立的 s6_ending，它要等前日谈演完才播（见 week1_1.gd 的 ENDING_SEQS）。
const SEQS := ["s0_maze", "s1_phone", "s2_books", "s3_desk", "s4_soup", "s5_wardrobe", "s6_ending"]
## 新链：一周目六关 → 前日谈（prelude_1 → prelude_2）→ 一周目收尾 → 二周目。
const PRELUDE_1 := "res://scenes/prelude/prelude_1.tscn"
const WEEK2_SCENE := "res://scenes/week2/week2_1.tscn"
## prelude_2 的出口立起这个标记，week1_1 读它决定"播六关"还是"只播收尾"。
const PRELUDE_DONE_FLAG := "prelude_done"
const ENDING_SEQS := ["s6_ending"]
const SPACES := ["hallway", "classroom", "montage", "roofline", "dorm_corridor", "dorm_room", "black"]
## 用 preload 而不是全局类名 Week1Panels：--script 模式下 .godot 里的
## global_script_class_cache 是旧的，新加的 class_name 会 "not declared"。
const WEEK1_PANELS := preload("res://scripts/week1/week1_panels.gd")
## 读心术那一关（回忆段 s4b_1089）的静态数学 solve_1089 / reverse3 / sum_1089
## 直接从面板脚本上调 —— 同一个套路：preload，不用全局类名。
const MINDREAD_SCRIPT := preload("res://scripts/week1/panel_mindread.gd")
## 一周目第一天的段表（六关之间还夹着回忆段 s4b_1089）在 week1_1.gd 里，
## 这里用常量表读它，别为了断言去改那个文件。
## 【坑】get_script_constant_map() 不是静态函数：preload 出来的常量会被当成"在类上直接调"，
## 所以走 load + as GDScript（probe_week2 也是这么读的）。
const WEEK1_1_PATH := "res://scripts/prelude/week1_1.gd"

var _fails := 0
var _checks := 0
var _seen_panels: Array = []
var _seen_walks: Array = []


func _initialize() -> void:
	_run()


func _run() -> void:
	# --script 模式下要等第一帧，root 才会正常派发子节点的 _ready
	await process_frame
	print("========== 一周目 端到端自检 ==========")
	var st := root.get_node_or_null("PreludeState")
	if st == null:
		print("✗ 找不到 PreludeState 自动加载")
		quit(1)
		return

	_static_checks()
	await _wardrobe_ui_checks()
	await _mindread_checks()

	st.call("reset")
	var host: Node = await _make_host()
	var rt: Node = _runtime_of(host)
	_check(rt != null, "一周目场景（week1_1.tscn）建起来了", _runtime_debug(host) if rt == null else "")
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
			var want := WEEK1_PANELS.script_for(pid)
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

	_check(bool(host.get("_intermission")), "整幕点到了幕间（一周目结束）", "点了 %d 步" % steps)
	# 【同步】回忆段 s4b_1089 插在 s4_soup 与 s5_wardrobe 之间，所以整幕里真的会弹 8 个面板
	# （多出来的第 7 个就是读心术）。列表跟着变长，不是放宽：少弹一个、顺序错一个都会挂。
	_check(_seen_panels == ["maze", "gesture", "memo", "bookshelf", "desk", "soup", "mindread", "wardrobe"],
			"八个面板按顺序都弹过了", str(_seen_panels))
	_check(_seen_walks == ["书架", "室友的书桌", "衣柜"],
			"三次走位分别要求走到书架 / 室友的书桌 / 衣柜", str(_seen_walks))
	for id in ["maze", "gesture", "memo", "bookshelf", "desk", "soup", "mindread", "wardrobe"]:
		_check(st.call("get_flag", "week1_result_" + id, null) != null, "%s 有完成记录" % id)

	# ---- 新链：六关播完先演前日谈，收尾留到前日谈演完再播
	var hint := _title_text(host.get("_label"))
	_check(hint.contains("前日谈"), "幕间告诉玩家六关播完接下来进前日谈", hint)
	_check(str(host.call("next_scene_after_chapter")) == PRELUDE_1,
			"一周目六关播完后的下一幕是 prelude_1.tscn", str(host.call("next_scene_after_chapter")))

	# 前日谈演完：prelude_2 的出口把标记立起来，玩家回到这一幕。这时只播收尾。
	st.call("set_flag", PRELUDE_DONE_FLAG, true)
	_check(host.call("chapter_sequences") == ENDING_SEQS,
			"前日谈演完回到一周目只播收尾（不重播六关）", str(host.call("chapter_sequences")))
	_check(str(host.call("next_scene_after_chapter")) == WEEK2_SCENE,
			"收尾播完接的是二周目", str(host.call("next_scene_after_chapter")))

	# 真的把"从前日谈回来"再走一遍：这一遍应该只有收尾那一段，不再弹面板、不再走位。
	host = await _make_host()
	rt = _runtime_of(host)
	_check(rt != null, "带着 prelude_done 再进一周目：场景建起来了", _runtime_debug(host) if rt == null else "")
	if rt != null:
		var steps2 := 0
		var title_text := ""
		while steps2 < 200:
			steps2 += 1
			if bool(host.get("_intermission")):
				break
			if rt.get("_title_layer") != null:
				title_text = _title_text(rt.get("_title_layer"))
			rt.call("_on_advance")
			await process_frame
			await process_frame
		_check(bool(host.get("_intermission")), "收尾那一段也点到了幕间", "点了 %d 步" % steps2)
		_check(title_text.contains("第二天") and title_text.contains("寝室里没有人"),
				"收尾播的是「第二天 / 寝室里没有人」那张标题卡", title_text)
		_check(_seen_panels.size() == 8, "从前的六关没有再播一遍（面板没有第 9 个）", str(_seen_panels))
		_check(_seen_walks.size() == 3, "从前的六关没有再播一遍（走位没有第 4 次）", str(_seen_walks))

	# ---- 存档 / 继续上次：跨过前日谈再回来，收尾那一段也要能"接着播"。
	# 探针里没有 current_scene（dialogue_runtime._autosave() 会直接返回），所以手写一条存盘记录，
	# 再模拟"关掉游戏重开"：清掉内存状态 → request_resume()（它会把 flags 一起灌回来）→ 重建这一幕。
	var sg := root.get_node_or_null("SaveGame")
	_check(sg != null, "找得到 SaveGame 自动加载")
	if sg != null and rt != null:
		sg.call("write", CHAPTER, SCENE, 0)
		st.call("reset")
		var back_scene := str(sg.call("request_resume"))
		_check(back_scene.ends_with("week1_1.tscn"), "「继续上次」指向一周目这一幕", back_scene)
		_check(bool(st.call("get_flag", PRELUDE_DONE_FLAG, false)),
				"存档把 %s 一起带了回来（读档后仍然只播收尾）" % PRELUDE_DONE_FLAG)
		host = await _make_host()
		rt = _runtime_of(host)
		if rt != null:
			var panels_before := _seen_panels.size()
			var steps3 := 0
			var title3 := ""
			while steps3 < 200:
				steps3 += 1
				if bool(host.get("_intermission")):
					break
				if rt.get("_title_layer") != null:
					title3 = _title_text(rt.get("_title_layer"))
				rt.call("_on_advance")
				await process_frame
				await process_frame
			_check(bool(host.get("_intermission")), "读档接着播也走到了幕间", "点了 %d 步" % steps3)
			_check(title3.contains("寝室里没有人"), "读档接着播播的是收尾那张标题卡", title3)
			_check(_seen_panels.size() == panels_before, "读档接着播没有重播六关", str(_seen_panels))
		sg.call("clear")

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
	_seen_walks.append(goal)
	print("  · 走位：房间 %s，目标「%s」，第 %d 段第 %d 行，回 %s" % [room, goal, seq_i, row_i, back])
	_check(goal != "", "这次走位声明了目标物件（[\"goal\"]）")
	_check(back.ends_with("week1_1.tscn"), "记下了回一周目这一幕的场景", back)
	_check(room == "dorm_room", "走的是寝室房间", room)

	# 玩家在走位里走到目标物件跟前看了它
	if goal != "":
		st.call("note_examined", goal)

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
	_check(rt2 != null, "点完「看完了」回来，对话场景建起来了")
	if rt2 == null:
		return
	_check(int(rt2.get("_seq_index")) == seq_i, "回来之后停在走位时那一段",
			"期望 %d 实际 %d" % [seq_i, int(rt2.get("_seq_index"))])
	_check(int(rt2.get("_row_index")) > row_i, "回来之后确实往下播了",
			"_row_index=%d（恢复点 %d）" % [int(rt2.get("_row_index")), row_i])
	_check(rt2.get("_title_layer") == null, "回来之后没有重播标题卡")
	_check(not bool(rt2.get("_free_mode")), "回来之后没有掉进「查看完毕」兜底模式")
	if goal != "":
		var want := _first_peek_line(goal)
		var body := rt2.get_node_or_null("DialogueBox/Panel/VB/BodyText")
		var got := "" if body == null else str(body.get("text"))
		_check(got == want, "接着播的正是「%s」的追加台词" % goal,
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


# ---------------------------------------------------------------- 衣柜面板几何
## 第 ① 屏的"文字重叠"：面板里的字要么是 Label（容器排版），要么是 draw_string 画的。
##  无头模式截不了图，所以改成**量矩形**——两条判据：
##    ① 第 ① 屏不该有"参与排版"的文字节点（Label / Button / LineEdit / RichTextLabel）。
##       旧版那一屏是「四张按钮卡片（色块 + 名字）」，光这一条就挂 4 个；
##       新版整面柜子画在一张固定尺寸的子画布上，是 0 个 —— 重叠的地基被抽掉了。
##    ② 所有**可见**文字块的全局矩形两两求交，必须 0 对重叠；
##       再顺手查"文字被挤爆"（最小高度/宽度 > 实际尺寸）——
##       旧版最离谱的那张卡片要 163px 高，只分到 48px，多出来的 115px 就画到
##       隔壁两件衣服的名字上去了，这才是 Kerry 说的"文字重叠"。
func _wardrobe_ui_checks(tree: SceneTree = null) -> void:
	if tree == null:
		tree = self
	var script_path := WEEK1_PANELS.script_for("wardrobe")
	# 临时对照用：设了 DSH_WARDROBE_SCRIPT 就把这套断言套到别的脚本上，
	# 拿旧布局跑一遍，证明这几条真的会失败（不然断言只是"永远绿"的摆设）。
	var override := OS.get_environment("DSH_WARDROBE_SCRIPT")
	if override != "":
		script_path = override
	_check(script_path != "", "衣柜面板在登记表里有脚本路径", script_path)
	if script_path == "" or not ResourceLoader.exists(script_path):
		return

	var host := Control.new()
	host.name = "WardrobeProbeHost"
	tree.root.add_child(host)
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var p := Control.new()
	p.name = "WardrobeProbe"
	p.set_script(load(script_path))
	p.call("setup", {"id": "wardrobe"})
	host.add_child(p)
	# 【坑】等帧要等**面板所在的那棵树**：这个函数可能被一个"只是 new 出来的"
	# 探针实例调用（tools/_probe_wardrobe_assert.gd 就这么干），那种实例的
	# process_frame 根本不会发、get_tree() 也会报 "Parameter data.tree is null"，
	# 所以树由调用方传进来，默认才是自己。
	await tree.process_frame
	await tree.process_frame

	var geo := _geometry_scan(p)

	# 判据 ①：第 ① 屏（手绘衣柜）里没有参与排版的文字节点
	var layout_nodes := -1
	if p.has_method("ui_layout_text_nodes"):
		layout_nodes = int(p.call("ui_layout_text_nodes"))
	_check(layout_nodes == 0,
			"衣柜第①屏没有参与排版的文字节点（文字重叠的地基）",
			"实测 %d 个（-1 = 面板没提供这个方法）" % layout_nodes)

	# 判据 ②：可见文字块两两不重叠
	_check(int(geo["overlaps"]) == 0,
			"衣柜界面可见文字块两两求交：0 对重叠",
			"实测 %d 对重叠 / 共 %d 个可见文字块（含手绘 %d 个）" % [
					int(geo["overlaps"]), int(geo["rects"]), int(geo["drawn"])])
	if int(geo["overlaps"]) > 0:
		for s in geo["samples"]:
			print("      · 重叠：%s" % str(s))

	# 判据 ③：没有文字被挤爆（文字画出去、压到下一块上）
	_check(int(geo["squeezed"]) == 0,
			"衣柜界面没有文字被挤爆（最小尺寸 ≤ 实际尺寸）",
			"实测 %d 个被挤爆" % int(geo["squeezed"]))
	if int(geo["squeezed"]) > 0:
		for s in geo["squeeze_samples"]:
			print("      · 挤爆：%s" % str(s))

	# ------------------------------------------------ 主视图按"被点的那一件"画
	# 【为什么补这几条】Kerry 报过「围巾的主视图居然是衣服」：旧版 `_draw_coat_view()` 里写死
	#   `var c := Color(0.62, 0.24, 0.26)`（"主视图一律按红外套画"），所以点围巾也画一件外套。
	#   下面把"按件画"钉住：颜色逐件对上 CLOTHES、围巾没有口袋（不画口袋、也没有命中区）、
	#   标题跟着被点的那一件走。
	var consts: Dictionary = {}
	if p.get_script() != null:
		consts = p.get_script().get_script_constant_map()
	var clothes: Array = consts.get("CLOTHES", [])
	_check(clothes.size() == 4, "衣柜常量表 CLOTHES 是四件", "实测 %d 件" % clothes.size())

	var color_ok := true
	var color_detail := ""
	for i in clothes.size():
		if not p.has_method("cloth_color"):
			color_ok = false
			color_detail = "面板没有 cloth_color 方法"
			break
		var got: Color = p.call("cloth_color", i)
		var want: Color = clothes[i]["color"]
		if not got.is_equal_approx(want):
			color_ok = false
			color_detail = "第 %d 件 %s ≠ %s" % [i, str(got), str(want)]
			break
	_check(color_ok, "主视图的颜色逐件读 CLOTHES（点哪件画哪件的色）", color_detail)

	if not p.has_method("garment_has_pockets"):
		_check(false, "面板提供 garment_has_pockets（主视图按件决定画不画口袋）", "没有这个方法")
	else:
		var pockets_ok := true
		var pockets_bad := ""
		for i in clothes.size():
			var want_p := bool(clothes[i].get("pockets", true))
			if bool(p.call("garment_has_pockets", i)) != want_p:
				pockets_ok = false
				pockets_bad = "第 %d 件（%s）" % [i, str(clothes[i]["name"])]
				break
		_check(pockets_ok, "三件外套有口袋 / 围巾没有口袋，与 CLOTHES.pockets 一致", pockets_bad)

		# —— 点围巾：标题说的是围巾，且没有"看不见的命中区"
		p.call("_open_cloth", 3)
		var title_node: Variant = p.get("_detail_title")
		var scarf_title := str(title_node.text) if title_node != null else ""
		_check(scarf_title.contains("围巾") and not scarf_title.contains("外套"),
				"点围巾 → 主视图标题说的是围巾（不是外套）", scarf_title)
		var scarf_hit := int(p.call("_pocket_at", Vector2(320.0, 140.0)))
		_check(scarf_hit == -1, "围巾上没有口袋可点（右侧那块命中区返回 -1）", "实测 %d" % scarf_hit)

		# —— 点第三件（红）：右上袋仍然可点（这一条守着"解谜那条路没被改坏"）
		p.call("_open_cloth", 2)
		var coat_node: Variant = p.get("_detail_title")
		var coat_title := str(coat_node.text) if coat_node != null else ""
		_check(coat_title.contains("红色外套"), "点第三件（红）→ 标题是红色外套", coat_title)
		var coat_hit := int(p.call("_pocket_at", Vector2(320.0, 140.0)))
		_check(coat_hit == 1, "红外套上右侧那块是「右上袋」（第 2 个口袋）", "实测 %d" % coat_hit)

	tree.root.remove_child(host)
	host.free()
	await tree.process_frame


## 量一遍面板里"玩家看得见的文字"：
##   · Label / Button / LineEdit / RichTextLabel 的 get_global_rect()（隐藏屏的跳过）
##   · 面板报出来的手绘文字矩形（ui_text_rects）
## 返回 rects / drawn / overlaps / squeezed / samples。
func _geometry_scan(p: Node) -> Dictionary:
	var rects: Array = []
	var names: Array = []
	var squeezed: Array = []
	_geometry_collect(p, p, rects, names, squeezed)

	var drawn := 0
	if p.has_method("ui_text_rects"):
		for r in p.call("ui_text_rects"):
			rects.append(r)
			names.append("(手绘文字)")
			drawn += 1

	var overlaps := 0
	var samples: Array = []
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			if (rects[i] as Rect2).intersects(rects[j] as Rect2):
				overlaps += 1
				if samples.size() < 5:
					samples.append("%s %s × %s %s" % [
							str(names[i]), str(rects[i]), str(names[j]), str(rects[j])])

	var squeeze_samples: Array = []
	for s in squeezed:
		if squeeze_samples.size() < 5:
			squeeze_samples.append(str(s))

	return {
		"rects": rects.size(),
		"drawn": drawn,
		"overlaps": overlaps,
		"samples": samples,
		"squeezed": squeezed.size(),
		"squeeze_samples": squeeze_samples,
	}


func _geometry_collect(n: Node, panel: Node, rects: Array, names: Array, squeezed: Array) -> void:
	if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
		return
	if _geometry_is_text(n):
		var c := n as Control
		var txt := _geometry_text(n)
		if txt.strip_edges() != "":
			rects.append(c.get_global_rect())
			names.append("%s(%s)" % [str(n.name), txt.substr(0, 10)])
			# "挤爆"：容器分给它的地方比它自己需要的还小 → 文字只能画出去
			var need := c.get_combined_minimum_size()
			if need.y > c.size.y + 0.5 or need.x > c.size.x + 0.5:
				squeezed.append("%s 需要(%d,%d) 实际(%d,%d)" % [
						str(n.name), int(need.x), int(need.y), int(c.size.x), int(c.size.y)])
	for ch in n.get_children():
		_geometry_collect(ch, panel, rects, names, squeezed)


func _geometry_is_text(n: Node) -> bool:
	return n is Label or n is Button or n is LineEdit or n is RichTextLabel


func _geometry_text(n: Node) -> String:
	if n is Label:
		return str((n as Label).text)
	if n is Button:
		return str((n as Button).text)
	if n is LineEdit:
		return str((n as LineEdit).text)
	if n is RichTextLabel:
		return str((n as RichTextLabel).text)
	return ""


# ---------------------------------------------------------------- 读心术（1089）
##  回忆段 s4b_1089「1089 读心术」是第 5、6 关之间新插的一关，两头都要量：
##    · 数学：solve_1089 / reverse3 / sum_1089 是纯函数，按表逐个核；
##    · 界面：四屏显隐切换，真的按玩家的走法点一遍（填数 → 相减 → 报数 → 揭晓 → 收尾）；
##    · 接线：登记表里有这一关、DAY_ONE_SEQS 把它夹在两关中间、json 里有且只有一条 panel 行。
func _mindread_checks(tree: SceneTree = null) -> void:
	if tree == null:
		tree = self

	# ---- ① 登记表里有这一关，脚本文件也真的在
	_check(WEEK1_PANELS.has_panel("mindread"), "读心术面板在登记表里（week1_panels.gd）")
	var script_path := WEEK1_PANELS.script_for("mindread")
	_check(script_path != "" and ResourceLoader.exists(script_path),
			"读心术面板的脚本文件确实存在", script_path)

	# ---- ② solve_1089 的数学表
	#      rev / diff / past / future 分开断言：挂了能一眼看出是哪一格错。
	var legal := {
		123: {"rev": 321, "diff": 198, "past": 1, "future": 8},
		456: {"rev": 654, "diff": 198, "past": 1, "future": 8},
		789: {"rev": 987, "diff": 198, "past": 1, "future": 8},
		591: {"rev": 195, "diff": 396, "past": 3, "future": 6},
	}
	for n in legal.keys():
		var want: Dictionary = legal[n]
		var r: Dictionary = MINDREAD_SCRIPT.solve_1089(int(n))
		var tail := str(r)
		_check(bool(r.get("ok", false)), "solve_1089(%d) 认这个数" % int(n), tail)
		_check(int(r.get("rev", -1)) == int(want["rev"]),
				"solve_1089(%d).rev = %d" % [int(n), int(want["rev"])], tail)
		_check(int(r.get("diff", -1)) == int(want["diff"]),
				"solve_1089(%d).diff = %d" % [int(n), int(want["diff"])], tail)
		_check(int(r.get("past", -1)) == int(want["past"]),
				"solve_1089(%d).past = %d" % [int(n), int(want["past"])], tail)
		_check(int(r.get("future", -1)) == int(want["future"]),
				"solve_1089(%d).future = %d" % [int(n), int(want["future"])], tail)

	# 非法的两类都要挡住：越界（99 / 1000）与「百位个位挨太近」（倒过来减只剩两位数）
	for bad in [100, 111, 191, 293, 99, 1000]:
		var rb: Dictionary = MINDREAD_SCRIPT.solve_1089(int(bad))
		_check(not bool(rb.get("ok", true)), "solve_1089(%d) 判为不合法" % int(bad), str(rb))

	# ---- ③ sum_1089 对每一个合法 diff 都恒为 1089；顺带核 reverse3
	_check(MINDREAD_SCRIPT.reverse3(123) == 321, "reverse3(123) = 321",
			str(MINDREAD_SCRIPT.reverse3(123)))
	var diffs := [198, 297, 396, 495, 594, 693, 792, 891]
	for d in diffs:
		var s: int = MINDREAD_SCRIPT.sum_1089(int(d))
		_check(s == 1089, "sum_1089(%d) = 1089" % int(d), "实测 %d" % s)

	# 把 100..999 全扫一遍：只要 solve_1089 认了，diff 就必须落在上面那八个里、
	# 十位必须是 9、加起来必须是 1089 —— 这才是「1089 的把戏」真正成立的范围。
	var sweep_ok := true
	var sweep_diff_ok := true
	for n2 in range(100, 1000):
		var rs: Dictionary = MINDREAD_SCRIPT.solve_1089(n2)
		if not bool(rs.get("ok", false)):
			continue
		var dv := int(rs["diff"])
		var rv := int(rs["rev"])
		if dv != absi(n2 - rv) or rv != MINDREAD_SCRIPT.reverse3(n2):
			sweep_ok = false
		if not diffs.has(dv) or (dv / 10) % 10 != 9 or MINDREAD_SCRIPT.sum_1089(dv) != 1089:
			sweep_diff_ok = false
	_check(sweep_ok, "100..999 里所有合法数的 rev / diff 都对得上（含 100、1000 的边界）")
	_check(sweep_diff_ok, "100..999 里所有合法数的 diff 都落在那八个里且加起来是 1089")

	# ---- ④ 章节顺序：s4b_1089 夹在 s4_soup 与 s5_wardrobe 中间
	var day_one: Array = []
	var cm: Dictionary = (load(WEEK1_1_PATH) as GDScript).get_script_constant_map()
	if cm.has("DAY_ONE_SEQS"):
		day_one = cm["DAY_ONE_SEQS"]
	var i_soup := day_one.find("s4_soup")
	var i_recall := day_one.find("s4b_1089")
	var i_wardrobe := day_one.find("s5_wardrobe")
	_check(i_recall >= 0, "week1_1.gd 的 DAY_ONE_SEQS 里有 s4b_1089", str(day_one))
	_check(i_soup >= 0 and i_recall == i_soup + 1, "s4b_1089 紧跟在 s4_soup 后面", str(day_one))
	_check(i_recall >= 0 and i_wardrobe == i_recall + 1, "s5_wardrobe 又紧跟在 s4b_1089 后面", str(day_one))

	# ---- ⑤ 对话数据：week1.s4b_1089 存在，且里面恰好一条 ["panel", "mindread"]
	var data: Variant = _read_json(DATA)
	var chap: Variant = (data as Dictionary).get(CHAPTER, null) if data is Dictionary else null
	var rows: Variant = (chap as Dictionary).get("s4b_1089", null) if chap is Dictionary else null
	_check(rows is Array, "week1.s4b_1089 在 week1_dialogue.json 里")
	var panel_rows := 0
	if rows is Array:
		for row in (rows as Array):
			if row is Array and (row as Array).size() >= 2 \
					and str((row as Array)[0]) == "panel" and str((row as Array)[1]) == "mindread":
				panel_rows += 1
	_check(panel_rows == 1, "s4b_1089 里恰好有一条 [\"panel\", \"mindread\"]", "实测 %d 条" % panel_rows)

	# ---- ⑥ 界面：真的按玩家的走法走一遍
	if script_path == "" or not ResourceLoader.exists(script_path):
		return

	var host := Control.new()
	host.name = "MindreadProbeHost"
	tree.root.add_child(host)
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var p := Control.new()
	p.name = "MindreadProbe"
	p.set_script(load(script_path))
	var got_result: Array = []
	p.connect("finished", func(result: Dictionary) -> void: got_result.append(result))
	p.call("setup", {"id": "mindread"})
	host.add_child(p)
	await tree.process_frame
	await tree.process_frame

	_check(str(p.call("panel_title")) == "读心术 · 1089", "panel_title() 是「读心术 · 1089」",
			str(p.call("panel_title")))
	_check(str(p.call("panel_hint")).contains("倒过来相减"), "panel_hint() 讲了这一关怎么玩",
			str(p.call("panel_hint")))

	var s1 := _node(p, "Step1Box") as Control
	var s2 := _node(p, "Step2Box") as Control
	var s3 := _node(p, "Step3Box") as Control
	var s4 := _node(p, "RevealBox") as Control
	_check(s1 != null and s2 != null and s3 != null and s4 != null,
			"四屏都建出来了（Step1Box / Step2Box / Step3Box / RevealBox）")
	if s1 == null or s2 == null or s3 == null or s4 == null:
		tree.root.remove_child(host)
		host.free()
		return
	_check(s1.visible and not s2.visible and not s3.visible and not s4.visible,
			"开局只看得见第 ① 屏")

	var num_input := _node(p, "NumberInput") as LineEdit
	var num_btn := _node(p, "NumberConfirm") as Button
	var s1_fb := _node(p, "Step1Feedback") as Label
	var s2_fb := _node(p, "Step2Feedback") as Label
	var s3_fb := _node(p, "Step3Feedback") as Label
	_check(num_input != null and num_input.max_length == 3, "NumberInput 在，且最多 3 位",
			"max_length=%d" % (num_input.max_length if num_input != null else -1))
	_check(num_btn != null and num_btn.text == "就它了", "NumberConfirm 写着「就它了」")
	_check(num_input != null and num_input.has_focus(),
			"第 ① 屏的 NumberInput 自动拿到了焦点（不然玩家敲键盘像没反应）")

	# 先喂一个「太特殊」的：191 的百位个位挨太近，倒过来减只剩两位数
	if num_input != null and num_btn != null:
		num_input.text = "191"
		num_btn.pressed.emit()
	await tree.process_frame
	_check(s1.visible, "填了太特殊的数还停在第 ① 屏")
	_check(s1_fb != null and str(s1_fb.text).contains("太特殊"),
			"第 ① 屏给的是「这个数太特殊了」那句", "" if s1_fb == null else str(s1_fb.text))

	# 换成 123：进第 ② 屏
	if num_input != null and num_btn != null:
		num_input.text = "123"
		num_btn.pressed.emit()
	await tree.process_frame
	await tree.process_frame
	_check(not s1.visible and s2.visible, "填 123 之后切到第 ② 屏、第 ① 屏收起来")

	var diff_input := _node(p, "DiffInput") as LineEdit
	var diff_btn := _node(p, "DiffConfirm") as Button
	var digit_input := _node(p, "DigitInput") as LineEdit
	var digit_btn := _node(p, "DigitConfirm") as Button
	var numbers_line := _node(p, "Step2Numbers") as Label
	_check(diff_input != null and diff_input.has_focus(), "第 ② 屏的 DiffInput 自动拿到了焦点")
	var numbers_text := str(numbers_line.text) if numbers_line != null else ""
	_check(numbers_text.contains("123") and numbers_text.contains("321"),
			"第 ② 屏把「你的数 / 倒过来」按玩家的输入动态写出来了", numbers_text)

	# 连错 3 次必须把答案写出来 —— 这一关不许有「卡在这儿了」的状态
	if diff_input != null and diff_btn != null:
		diff_input.text = "1"
		diff_btn.pressed.emit()
	await tree.process_frame
	_check(str(s2_fb.text if s2_fb != null else "") == "再算一次。",
			"第 ② 屏第一次算错给「再算一次。」", str(s2_fb.text if s2_fb != null else ""))
	if diff_input != null and diff_btn != null:
		diff_input.text = "999"
		diff_btn.pressed.emit()
	await tree.process_frame
	_check(s2.visible, "连错两次仍然停在第 ② 屏")
	if diff_input != null and diff_btn != null:
		diff_input.text = "250"
		diff_btn.pressed.emit()
	await tree.process_frame
	var fb3 := str(s2_fb.text if s2_fb != null else "")
	_check(fb3.contains("321") and fb3.contains("198"),
			"连错 3 次直接把算式和答案写出来（不会卡死）", fb3)

	# 填对 198：进第 ③ 屏
	if diff_input != null and diff_btn != null:
		diff_input.text = "198"
		diff_btn.pressed.emit()
	await tree.process_frame
	await tree.process_frame
	_check(not s2.visible and s3.visible, "填对 198 之后切到第 ③ 屏")
	_check(digit_input != null and digit_input.has_focus(), "第 ③ 屏的 DigitInput 自动拿到了焦点")

	# 报十位（永远是 9）不算数
	if digit_input != null and digit_btn != null:
		digit_input.text = "9"
		digit_btn.pressed.emit()
	await tree.process_frame
	var fb3b := str(s3_fb.text if s3_fb != null else "")
	_check(fb3b.contains("那是十位"), "报十位（9）被挡回去，并说明要的是个位或者百位", fb3b)

	# 报个位 1：揭晓
	if digit_input != null and digit_btn != null:
		digit_input.text = "1"
		digit_btn.pressed.emit()
	await tree.process_frame
	await tree.process_frame
	_check(not s3.visible and s4.visible, "报对了个位就切到揭晓屏（第 ④ 屏）")

	var reveal_text := _title_text(s4)
	_check(reveal_text.contains("1089"), "揭晓屏上有 1089 那张算式卡片", reveal_text)
	_check(reveal_text.contains("隐士"), "揭晓屏上有「隐士」", "")
	_check(reveal_text.contains("你的过去是 1") and reveal_text.contains("你的未来是 8"),
			"揭晓里的过去 / 未来是按差算出来的（1 / 8）", "")
	_check(reveal_text.contains("你的现在是 9"), "揭晓里的现在是 9", "")

	var finish := _node(p, "FinishButton") as Button
	_check(finish != null and finish.text == "……好吧。", "FinishButton 写着「……好吧。」")
	if finish != null:
		finish.pressed.emit()
	await tree.process_frame
	_check(got_result.size() == 1, "按「……好吧。」只发一次 finished", "发了 %d 次" % got_result.size())
	var res: Dictionary = got_result[0] if got_result.size() > 0 else {}
	_check(bool(res.get("ok", false)), "收尾结果里 ok = true", str(res))
	_check(int(res.get("diff", -1)) == 198, "收尾结果里 diff = 198", str(res))
	_check(int(res.get("past", -1)) == 1, "收尾结果里 past = 1", str(res))
	_check(int(res.get("future", -1)) == 8, "收尾结果里 future = 8", str(res))
	_check(int(res.get("num", -1)) == 123 and int(res.get("rev", -1)) == 321,
			"收尾结果里带着 num / rev", str(res))

	# 四屏内容别把 900×540 的框架顶高（框架一高就会压到屏幕边上）
	var frame := _node(p, "PanelFrame") as Control
	_check(frame != null and frame.size.y <= 540.5, "四屏内容没有把 900×540 的框架顶高",
			"框架 %s" % (str(frame.size) if frame != null else "没找到"))

	tree.root.remove_child(host)
	host.free()
	await tree.process_frame


# ---------------------------------------------------------------- 静态检查

func _static_checks() -> void:
	var data: Variant = _read_json(DATA)
	_check(data is Dictionary, "week1_dialogue.json 能解析成字典")
	if not (data is Dictionary):
		return
	var chap: Variant = (data as Dictionary).get(CHAPTER, null)
	_check(chap is Dictionary, "里有 chapter 键 %s" % CHAPTER)
	if not (chap is Dictionary):
		return
	var rooms_data: Variant = _read_json(ROOMS)
	var room_items: Dictionary = {}
	if rooms_data is Dictionary:
		var rooms: Variant = (rooms_data as Dictionary).get("rooms", {})
		if rooms is Dictionary:
			for rid in (rooms as Dictionary).keys():
				var it: Array = []
				var rv: Variant = (rooms as Dictionary)[rid]
				if rv is Dictionary and (rv as Dictionary).get("items", null) is Array:
					for it_row in ((rv as Dictionary)["items"] as Array):
						if it_row is Array and (it_row as Array).size() >= 6:
							it.append(str((it_row as Array)[5]))
				room_items[str(rid)] = it
	_check(room_items.has("dorm_room"), "prelude_rooms.json 里有 dorm_room")
	_check((chap as Dictionary).size() > 0, "chapter 里有序列")

	var panel_ids: Array = []
	var goal_names: Array = []
	for sid in SEQS:
		var rows: Variant = (chap as Dictionary).get(sid, null)
		_check(rows is Array, "序列 %s 存在" % sid)
		if not (rows is Array):
			continue
		var room_id := ""
		var peeks: Array = []
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
					_check(WEEK1_PANELS.has_panel(pid), "面板 %s 在登记表里" % pid)
					var sp := WEEK1_PANELS.script_for(pid)
					_check(sp != "" and ResourceLoader.exists(sp), "面板 %s 的脚本文件存在" % pid, sp)
				"room":
					room_id = str(a[1])
					_check(room_items.has(room_id), "房间 %s 在 prelude_rooms.json 里" % room_id)
					peeks = []
				"goal":
					var gname := str(a[1])
					goal_names.append(gname)
					_check((room_items.get(room_id, []) as Array).has(gname),
							"目标物件「%s」确实在房间 %s 的 items 里" % [gname, room_id])
				"peek":
					peeks.append(str(a[1]))
					_check((room_items.get(room_id, []) as Array).has(str(a[1])),
							"peek 物件「%s」确实在房间 %s 的 items 里" % [str(a[1]), room_id])
				"space":
					_check(SPACES.has(str(a[1])), "背景键 %s 有效" % str(a[1]))
				"title", "n", "m", "d", "card", "choice", "show", "hide", "who", "item", "free":
					pass
				_:
					_check(false, "序列 %s 第 %d 行是未知行类型 %s" % [sid, i, kind])
	_check(panel_ids == ["maze", "gesture", "memo", "bookshelf", "desk", "soup", "wardrobe"],
			"一整幕里七个面板的顺序对", str(panel_ids))
	_check(goal_names == ["书架", "室友的书桌", "衣柜"], "三次走位的目标顺序对", str(goal_names))

	# 收尾已经从 s5_wardrobe 拆到 s6_ending：它要等前日谈演完才播，
	# 所以这两段的行必须各就各位（s5 里不该再留收尾的 title 行）。
	var s5: Variant = (chap as Dictionary).get("s5_wardrobe", null)
	var s6: Variant = (chap as Dictionary).get("s6_ending", null)
	_check(not _has_kind(s5, "title"), "s5_wardrobe 里已经没有收尾的 title 行", str(_kinds(s5)))
	_check(_kinds(s6) == ["space", "hide", "title"], "s6_ending 就是那段收尾", str(_kinds(s6)))


# ---------------------------------------------------------------- 工具

## 行类型序列（["n", …] → "n"），用来断言某一段里有没有某类行。
func _kinds(rows: Variant) -> Array:
	var out: Array = []
	if rows is Array:
		for r in (rows as Array):
			if r is Array and not (r as Array).is_empty():
				out.append(str((r as Array)[0]))
	return out


func _has_kind(rows: Variant, kind: String) -> bool:
	return _kinds(rows).has(kind)


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


## 在面板里按名字找控件（读心术那一关的节点名是固定的：NumberInput / Step2Box …）。
## 找不到返回 null，调用方自己判 —— 断言挂了要能看出是"节点没建出来"还是"值不对"。
func _node(root_node: Node, node_name: String) -> Node:
	if root_node == null:
		return null
	if str(root_node.name) == node_name:
		return root_node
	for c in root_node.get_children():
		var hit := _node(c, node_name)
		if hit != null:
			return hit
	return null


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
