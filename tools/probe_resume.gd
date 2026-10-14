extends SceneTree
## ============================================================================
##  《寻星》· 走位 → 对话 恢复自检（headless，不用开游戏窗口）
## ============================================================================
##  锁死这个 bug：「走完房间回到对话，再按空格直接回到最开头」
##  根因：["free"] 不在第一段时（图书馆在 s3_montage），
##  _restore_after_walk() 里 seq_i != _seq_index 直接 return，玩家被扔回序列 0，
##  于是再按一下空格就重播「前日谈」标题卡。
##
##  做法：把整幕按真实流程走一遍 —— 一路点到第一段走位 → 记下"走位里看了什么"
##  → 重建对话场景（= 玩家点完「看完了」切回来）→ 检查恢复点 → 继续点到下一段走位 …
##  最后一路点到幕间，全程不许再重进走位 / 掉进「查看完毕」兜底。
##
##  跑法：
##    godot --headless --path <项目> --script tools/probe_resume.gd
##  退出码 0 = 全绿。
## ============================================================================

const DIALOGUE_PATH := "res://data/prelude_dialogue.json"
const PRELUDE_1 := "res://scenes/prelude/prelude_1.tscn"
const ACT1 := ["s0_open", "s1_book", "s2_cinema", "s3_montage", "s4_break"]

var _fails := 0
var _checks := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	# --script 模式下要等第一帧，root 才会正常派发子节点的 _ready
	await process_frame
	print("========== 走位 → 对话 恢复自检 ==========")
	var st := root.get_node_or_null("PreludeState")
	if st == null:
		print("✗ 找不到 PreludeState 自动加载")
		quit(1)
		return
	var sites := _find_sites()
	if sites.is_empty():
		print("✗ 没在 act1 里找到 [\"room\", …] + [\"free\"] 走位站点")
		quit(1)
		return
	print("找到 %d 个走位站点：" % sites.size())
	for s in sites:
		print("   · 第 %d 段 %s：房间 %s，[\"free\"] 在第 %d 行，已注册 peek：%s"
				% [int(s["seq"]), str(s["seq_id"]), str(s["room"]),
						int(s["free_row"]), str(s["peeks"])])

	st.call("reset")
	var host: Node = await _make_host()
	var rt: Node = _runtime_of(host)
	_check(rt != null, "对话场景建起来了", _runtime_debug(host) if rt == null else "")
	if rt == null:
		print("共 %d 项检查，失败 %d 项" % [_checks, _fails])
		quit(1)
		return

	for s in sites:
		var pair: Array = await _walk_site(st, host, s)
		host = pair[0] as Node
		rt = pair[1] as Node
		if rt == null:
			break

	if rt != null:
		var done: bool = await _drive_to_intermission(host, rt, 3000)
		_check(done, "后半程一路点下去没有再重进走位 / 掉进兜底模式")
		root.remove_child(host)
		host.free()

	print("=========================================")
	print("共 %d 项检查，失败 %d 项" % [_checks, _fails])
	quit(1 if _fails > 0 else 0)


func _check(cond: bool, label: String, detail := "") -> void:
	_checks += 1
	var tail := ("（%s）" % detail) if detail != "" else ""
	if cond:
		print("  ✓ ", label, tail)
	else:
		_fails += 1
		print("  ✗ ", label, tail)


# ---------------------------------------------------------------- 一个走位站点

func _walk_site(st: Node, host: Node, site: Dictionary) -> Array:
	var seq_i := int(site["seq"])
	var after_row := int(site["free_row"]) + 1
	var room := str(site["room"])
	var peeks: Array = site["peeks"]
	var rt: Node = _runtime_of(host)
	print("-----------------------------------------")
	print("第 %d 段 %s：走位房间 %s" % [seq_i, str(site["seq_id"]), room])

	# ---- 阶段 1：真的点到本段的 ["free"]，让 _start_free() 自己写恢复点
	var reached: bool = await _advance_until_resume(rt, seq_i, 800)
	_check(reached, "点到本段的 [\"free\"]，_start_free() 写下了恢复点",
			"seq=%d row=%d peek_at=%d" % [
					int(st.call("get_flag", "walk_resume_seq", -1)),
					int(st.call("get_flag", "walk_resume_row", -1)),
					int(st.call("get_flag", "walk_resume_peek", -1))])
	if not reached:
		return [host, rt]
	_check(int(st.call("get_flag", "walk_resume_seq", -1)) == seq_i,
			"恢复点记的是本段（%d）" % seq_i)
	_check(int(st.call("get_flag", "walk_resume_row", -1)) == after_row,
			"恢复点记的是 [\"free\"] 的下一行", "期望 %d" % after_row)
	_check(st.call("get_flag", "walk_resume_peeks", null) is Dictionary,
			"peek 数据表也备了份")

	# 走位期间看了东西（照真实流程记一笔）
	for nm in peeks:
		st.call("note_examined", str(nm))

	# ---- 阶段 2：模拟玩家点「看完了」：走位场景关掉、对话场景重建
	await process_frame
	await process_frame
	_free_walk_scene()
	root.remove_child(host)
	host.free()
	await process_frame
	host = await _make_host()
	rt = _runtime_of(host)
	_check(rt != null, "点完「看完了」回来，对话场景建起来了")
	if rt == null:
		return [host, null]

	var s2 := int(rt.get("_seq_index"))
	var r2 := int(rt.get("_row_index"))
	_check(s2 == seq_i, "回来之后停在走位时那一段", "期望 %d，实际 %d" % [seq_i, s2])
	_check(rt.get("_title_layer") == null, "回来之后没有重播标题卡（不是回到最开头）")
	_check(not bool(rt.get("_free_mode")), "回来之后没有掉进「查看完毕」兜底模式")
	_check(r2 > after_row, "回来之后确实播了下一条", "_row_index=%d" % r2)
	if not peeks.is_empty():
		var want := _first_line_of(str(peeks[0]))
		var body := rt.get_node_or_null("DialogueBox/Panel/VB/BodyText")
		var got := "" if body == null else str(body.get("text"))
		_check(got == want, "接着播的正是走位里新看过物件的追加台词",
				"期望「%s」实际「%s」" % [want, got])
	return [host, rt]


# ---------------------------------------------------------------- 驱动

## 建一个对话场景实例，并确保它的 _ready 已经跑过（跑过才有 runtime 节点）。
func _make_host() -> Node:
	var host: Node = (load(PRELUDE_1) as PackedScene).instantiate()
	root.add_child(host)
	if _runtime_of(host) == null:
		await process_frame
		await process_frame
	return host


## 场景基类 prelude_base.gd 把运行时节点放在 `runtime` 成员里并取名 "Runtime"，
## 两种拿法都试一遍。
func _runtime_of(host: Node) -> Node:
	var v: Variant = host.get("runtime")
	if v is Node:
		return v as Node
	return host.get_node_or_null("Runtime")


func _runtime_debug(host: Node) -> String:
	var v: Variant = host.get("runtime")
	var sc: Variant = host.get_script()
	return "children=%s runtime=%s script=%s" % [
			str(host.get_children()), str(v),
			str((sc as Script).resource_path) if sc is Script else "null"]


func _choice_open(rt: Node) -> bool:
	# _choice 在 _build_ui() 里就建好了，永远是"非 null"；
	# 真正判断有没有在选择中要看 is_open()。
	var c: Variant = rt.get("_choice")
	if c == null or not (c is Object):
		return false
	return bool((c as Object).call("is_open"))


## 模拟玩家点了选项：ChoiceMenu 的 _on_pressed() 会自己 close() 并 emit chosen，
## 直接调 _on_choice() 会漏掉 close()，is_open() 一直为真 —— 那就死循环了。
func _pick_choice(rt: Node, index: int) -> void:
	var c: Variant = rt.get("_choice")
	if c is Object and (c as Object).has_method("_on_pressed"):
		(c as Object).call("_on_pressed", index)
	else:
		rt.call("_on_choice", index)


## 一路点，直到本段（want_seq）的 ["free"] 被触发。
func _advance_until_resume(rt: Node, want_seq: int, max_steps: int) -> bool:
	var st := root.get_node_or_null("PreludeState")
	if st == null:
		return false
	var ok := false
	var reason := "跑满 %d 步还没点到" % max_steps
	for i in max_steps:
		if bool(st.call("get_flag", "walk_resume_active", false)):
			var got := int(st.call("get_flag", "walk_resume_seq", -1))
			ok = got == want_seq
			reason = "触发的是第 %d 段的走位（想要第 %d 段）" % [got, want_seq]
			break
		if bool(rt.get("_free_mode")):
			reason = "掉进了「查看完毕」兜底模式"
			break
		if not bool(rt.get("_active")):
			reason = "运行时 _active=false（本章结束或异常）"
			break
		if int(rt.get("_seq_index")) > want_seq:
			reason = "已经越过第 %d 段（现在第 %d 段）" % [want_seq, int(rt.get("_seq_index"))]
			break
		if _choice_open(rt):
			# 中途的选项（s1/s2 各有一处）：一路选第 1 个，把流程推下去
			_pick_choice(rt, 0)
		else:
			rt.call("_on_advance")
		await process_frame
		await process_frame
	if not ok:
		print("      [debug] 没点到第 %d 段走位：%s；现在 seq=%d row=%d active=%s free=%s"
				% [want_seq, reason, int(rt.get("_seq_index")), int(rt.get("_row_index")),
						str(rt.get("_active")), str(rt.get("_free_mode"))])
	return ok


## 一路点到幕间（chapter 结束），全程盯着有没有重进走位 / 掉进兜底模式。
func _drive_to_intermission(host: Node, rt: Node, max_steps: int) -> bool:
	var st := root.get_node_or_null("PreludeState")
	if st == null:
		return false
	for i in max_steps:
		if bool(host.get("_intermission")):
			return true
		if bool(rt.get("_free_mode")):
			return false
		if bool(st.call("get_flag", "walk_resume_active", false)):
			return false
		if not bool(rt.get("_active")):
			return true
		if _choice_open(rt):
			_pick_choice(rt, 0)
		else:
			rt.call("_on_advance")
		await process_frame
		await process_frame
	return true


func _free_walk_scene() -> void:
	for c in root.get_children():
		if str(c.name) == "PreludeWalk":
			root.remove_child(c)
			c.free()


# ---------------------------------------------------------------- JSON 查询

func _read_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var txt := f.get_as_text()
	f.close()
	return JSON.parse_string(txt)


func _find_sites() -> Array:
	var data: Variant = _read_json(DIALOGUE_PATH)
	var sites: Array = []
	if not (data is Dictionary):
		return sites
	var act: Variant = (data as Dictionary).get("act1", null)
	if not (act is Dictionary):
		return sites
	for si in ACT1.size():
		var seq_id: String = ACT1[si]
		var rows: Variant = (act as Dictionary).get(seq_id, null)
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
			if kind == "room" and a.size() >= 2:
				room_id = str(a[1])
				peeks = []
			elif kind == "peek" and a.size() >= 2:
				peeks.append(str(a[1]))
			elif kind == "free" and room_id != "":
				sites.append({"seq": si, "seq_id": seq_id, "room": room_id,
						"free_row": i, "peeks": peeks})
				room_id = ""
				peeks = []
	return sites


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


func _first_line_of(item_name: String) -> String:
	var data: Variant = _read_json(DIALOGUE_PATH)
	if not (data is Dictionary):
		return ""
	var act: Variant = (data as Dictionary).get("act1", null)
	if not (act is Dictionary):
		return ""
	for key in (act as Dictionary).keys():
		var rows: Variant = (act as Dictionary)[key]
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
