extends SceneTree
## 前日谈走位场景 · 无头自检（不进编辑器、不碰 9090 上的实例）
##
## 跑的用法：  godot --headless --path . --script tools/probe_walk.gd
## 它只做两件事，都是用户报的那两个 bug 的判据：
##   ① 镜头/人物速度：镜头跟随时，「人物在屏幕上的位置」必须恒定，
##      也就是「场景移动 = 人物移动」1:1，而不是人物飞出去。
##   ② 靠近判定：站在道具前方（脚下到道具矩形 0.8×reach 以内）要能报 near，
##      离远了不能报；高亮还要有迟滞（同一个位置，带着高亮走过去不该掉）。

const DRAW := "res://scripts/ui/prelude_room_draw.gd"
const RUNTIME := "res://scripts/ui/room_runtime.gd"

var _fails := 0
var _checks := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var rooms: Dictionary = _read_rooms()
	print("—— 前日谈走位自检 ——")
	_test_camera(rooms)
	await _test_proximity(rooms)
	await _test_popup()
	print("—— 共 %d 项，失败 %d 项 ——" % [_checks, _fails])
	quit(1 if _fails > 0 else 0)


# ── 房间数据 ──────────────────────────────────────────────────────────────
func _read_rooms() -> Dictionary:
	var f := FileAccess.open("res://data/prelude_rooms.json", FileAccess.READ)
	if f == null:
		return {}
	var data: Variant = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	var d: Dictionary = data
	if typeof(d.get("rooms")) == TYPE_DICTIONARY:
		d = d["rooms"]
	var out: Dictionary = {}
	for k in d.keys():
		if typeof(d[k]) == TYPE_DICTIONARY:
			out[String(k)] = d[k]
	return out


## 把一个房间的 items / walk_rect 用 room_runtime 的口径算出来，
## 保证自检和游戏里跑的是同一套读取逻辑。
func _make_runtime(room_id: String) -> Control:
	var rt := Control.new()
	rt.set_script(load(RUNTIME))
	rt.call("configure", room_id)
	root.add_child(rt)
	rt.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return rt


# ── ① 镜头：跟随时人物必须钉在屏幕中心 ────────────────────────────────────
func _test_camera(rooms: Dictionary) -> void:
	var room: Dictionary = rooms.get("corridor_end", {})
	if room.is_empty():
		_fail("读不到 corridor_end 房间数据")
		return
	var rt := _make_runtime("corridor_end")
	var rects: Array = rt.get("_walk_rects")
	if rects.is_empty():
		_fail("corridor_end 没有可行走区域")
		rt.queue_free()
		return
	var band: Rect2 = rects[0]
	var dr: RefCounted = load(DRAW).new()
	# 与 prelude_backdrop.set_room 一致：scale 取房间的 scale，t 随便给一个。
	# 【注意】游戏里是**每帧**先 set_room(room, _player, …) 再 draw_room()，
	# 所以镜头是按"当前这一帧的玩家位置"算的——测的时候必须逐点重设，
	# 否则测的是"玩家在起点时镜头对着哪里"，得到的是假失败。
	var room_d: Dictionary = rt.get("room")
	dr.call("set_room", room_d, Vector2(band.position.x, band.position.y),
			{}, rt.get("_items"), rt.get("_props"), false, 1.0, 0.0)
	var win := Vector2(1280, 720)
	var want_x := win.x * 0.5
	var y_at := 392.0
	# 逐点断言：屏幕 x 必须恒等于屏幕中心。
	# 【为什么这是判据】人物每走 1px，若屏幕位置也动 1px，说明"人物在屏幕上滑、
	# 场景没动"——那正是用户看到的「人物移动速度远大于场景移动速度」。
	# 1:1 跟随的意思是：人物钉在屏幕中心，动的是场景。
	var worst := 0.0
	var worst_x := 0.0
	var x := band.position.x
	while x <= band.end.x:
		var p := Vector2(x, y_at)
		dr.call("set_room", room_d, p, {}, rt.get("_items"), rt.get("_props"), false, 1.0, 0.0)
		var sp: Vector2 = (dr.call("xform", win) as Transform2D) * p
		var off: float = absf(sp.x - want_x)
		if off > worst:
			worst = off
			worst_x = x
		x += 4.0
	_check(worst <= 0.6, "镜头跟随时人物钉在屏幕中心（最大偏差 %.2fpx @ x=%.0f）" % [worst, worst_x])
	# 屏幕 y 也必须恒定（人物上下不该随着横向走动漂）
	dr.call("set_room", room_d, Vector2(band.position.x, y_at), {}, rt.get("_items"), rt.get("_props"), false, 1.0, 0.0)
	var y_sp: Vector2 = (dr.call("xform", win) as Transform2D) * Vector2(band.position.x, y_at)
	dr.call("set_room", room_d, Vector2(band.end.x, y_at), {}, rt.get("_items"), rt.get("_props"), false, 1.0, 0.0)
	var y_sp2: Vector2 = (dr.call("xform", win) as Transform2D) * Vector2(band.end.x, y_at)
	_check(absf(y_sp.y - y_sp2.y) <= 0.01, "横向走动时人物屏幕 y 不变（%.2f vs %.2f）" % [y_sp.y, y_sp2.y])
	# 两端渐隐：镜头越过房间边界时，两侧不能出现"没画东西的黑带"
	var ext: float = dr.call("_lateral_extend", win.x / float(dr.call("_view_scale", win)))
	_check(ext >= win.x * 0.5, "地面横向外扩 %.0fpx ≥ 半个屏幕宽（兜住越界的镜头）" % ext)
	print("   · 取景比例 s=%.5f  地面外扩 ext=%.0f" % [float(dr.call("_view_scale", win)), ext])
	rt.queue_free()


# ── ② 靠近判定 ────────────────────────────────────────────────────────────
func _test_proximity(rooms: Dictionary) -> void:
	var rt := _make_runtime("corridor_end")
	await process_frame
	await process_frame
	var items: Array = rt.get("_items")
	var names: Array = []
	for it in items:
		names.append(String((it as Dictionary).get("name", "")))
	if not names.has("推理社门牌"):
		_fail("corridor_end 里没有『推理社门牌』（items=%s）" % str(names))
		rt.queue_free()
		return
	print("   · corridor_end 可交互物件：%s" % str(names))
	# 站在道具正前方（脚下离道具矩形下沿 102px）→ 必须报 near。
	# 这正是旧代码失手的位置：旧代码从 _player+(0,57.6) 量到道具**中心**，
	# 这里量到中心是 198.6px > reach 150 → 明明站在门口却不给提示。
	rt.set("_player", Vector2(960, 480))
	rt.call("_update_near")
	_check(_near_name(rt) == "推理社门牌", "站在『推理社门牌』前（960,480）能给提示 → %s" % _near_name(rt))
	# 再往前走一点，仍然要给
	rt.set("_player", Vector2(960, 420))
	rt.call("_update_near")
	_check(_near_name(rt) == "推理社门牌", "贴到『推理社门牌』跟前（960,420）能给提示 → %s" % _near_name(rt))
	# 迟滞：带着高亮再退到 500（矩形下沿 122px，超出 0.8×reach=120，但在 reach×1.18=177 内）
	# → 不该掉；同样位置从"冷"的状态过去 → 不该亮。
	rt.set("_player", Vector2(960, 500))
	rt.call("_update_near")
	_check(_near_name(rt) == "推理社门牌", "带高亮退到 500 不掉（迟滞）→ %s" % _near_name(rt))
	rt.set("_near", {})
	rt.call("_update_near")
	_check(_near_name(rt) == "", "冷状态站在 500 不亮 → %s" % _near_name(rt))
	# 走远：必须灭
	rt.set("_player", Vector2(960, 700))
	rt.call("_update_near")
	_check(_near_name(rt) == "", "走远到 700 熄灭 → %s" % _near_name(rt))
	# 走到最边上（走廊尽头）也不该乱报
	rt.set("_player", Vector2(2270, 620))
	rt.call("_update_near")
	_check(_near_name(rt) == "", "走廊最右端不给假提示 → %s" % _near_name(rt))
	# 真实走位：(1300,480) 时离『活动表』(x 1420~1720, y 300~388) 还差 151px，
	# 不在 0.8×reach(160)=128 以内 → 先不亮；按住右走必须亮起来。
	# 无头下帧率不封顶（delta 极小），所以按 x 走够距离为准，不按帧数。
	rt.set("_player", Vector2(1300, 480))
	rt.set("_near", {})
	rt.call("_update_near")
	var cold := _near_name(rt)
	var hit_x := -1.0
	Input.action_press("prelude_walk_right")
	for i in 20000:
		await process_frame
		if _near_name(rt) != "":
			hit_x = float((rt.get("_player") as Vector2).x)
			break
		if float((rt.get("_player") as Vector2).x) > 1500.0:
			break
	Input.action_release("prelude_walk_right")
	# 算出来的理论触发点：sqrt((1420-x)² + 92²) ≤ 128 → x ≥ 1331
	_check(cold == "", "起点 (1300,480) 离『活动表』151px，先不亮 → %s" % cold)
	_check(hit_x >= 1325.0 and hit_x <= 1345.0,
			"按住右走，在 x=%.0f 亮起（理论 1331：站在道具旁边就能看见，不用叠在上面）" % hit_x)
	# 走动时脚下 y 不该漂：横向移动只改 x
	var y_after := float((rt.get("_player") as Vector2).y)
	_check(absf(y_after - 480.0) <= 0.01, "横向走动不改脚下 y（480 → %.2f）" % y_after)
	rt.queue_free()


# ── ③ 弹窗（放大细节）：能开、不吃鼠标、开着时不能走、能收 ────────────────
func _test_popup() -> void:
	var rt := _make_runtime("corridor_end")
	await process_frame
	await process_frame
	rt.set("_player", Vector2(960, 480))
	rt.call("_update_near")
	var d: Dictionary = rt.get("_near")
	_check(not d.is_empty(), "站到道具边上有 near（%s）" % str(d.get("name", "")))
	rt.call("_examine", d)
	_check(bool(rt.get("_popup")), "查看后弹窗打开（_popup=true）")
	var layer: Control = rt.get("_popup_layer")
	_check(layer != null and layer.mouse_filter == Control.MOUSE_FILTER_IGNORE,
			"弹窗整层不吃鼠标（点击才能穿透到 _unhandled_input）")
	var dim: Control = null
	if layer != null:
		for c in layer.get_children():
			if c is ColorRect:
				dim = c
				break
	_check(dim != null and dim.mouse_filter == Control.MOUSE_FILTER_IGNORE,
			"压暗层也不吃鼠标（提示写的「点击 / 空格 收起来」才真的有效）")
	# 弹窗开着时人物必须站住
	var before: Vector2 = rt.get("_player")
	Input.action_press("prelude_walk_right")
	for i in 30:
		await process_frame
	Input.action_release("prelude_walk_right")
	_check((rt.get("_player") as Vector2).is_equal_approx(before), "弹窗开着时人物不动")
	rt.call("_close_popup")
	_check(not bool(rt.get("_popup")), "收起后 _popup=false")
	_check(float(rt.get("_act_lock")) > 0.0, "收起后有 0.22s 输入冷却（避免一次按键开合两次）")
	rt.queue_free()


func _near_name(rt: Node) -> String:
	var d: Dictionary = rt.get("_near")
	if d.is_empty():
		return ""
	return String(d.get("name", ""))


func _check(ok: bool, msg: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("   %s %s" % ["✓" if ok else "✗", msg])


func _fail(msg: String) -> void:
	_checks += 1
	_fails += 1
	print("   ✗ %s" % msg)
