extends Control
## ============================================================================
##  《寻星》前日谈 —— 俯视角走位运行时
## ============================================================================
##  玩法：玩家用 WASD / 方向键在房间里走，走到可交互物件附近时提示条浮出，
##        按空格（或点鼠标）打开"放大细节"弹窗，看完所有物件后按右下角返回对话。
##
##  设计原则（和 dialogue_runtime.gd 一致）：
##    · 所有节点在代码里 new 出来并直接持有强类型引用，不用 %UniqueName / 长路径 get_node，
##      从根本上避免 Node not found 与空引用。
##    · 【重要】"先 add_child，再 set_anchors_and_offsets_preset"必须写成
##      `node.set_anchors_and_offsets_preset(...)`（带接收者）——不带接收者时它作用于 self，
##      会把运行时自己改成 TOP_WIDE 之类，子节点反而没布局，表现为"弹窗挤成一条竖条"。
##    · 自己设死 offset 的控件：先 preset，再赋 offset。
##
##  数据来源：
##    · res://data/prelude_rooms.json —— 房间（地板可走区、固定陈设、可交互物件）
##    · 物件名与详情必须和 data/prelude_dialogue.json 里的 ["item", ...] / ["peek", ...] 完全一致
## ============================================================================

const ROOMS_PATH := "res://data/prelude_rooms.json"
const BACKDROP_SCRIPT := "res://scripts/ui/prelude_backdrop.gd"
const DIALOGUE_1 := "res://scenes/prelude/prelude_1.tscn"
const DIALOGUE_2 := "res://scenes/prelude/prelude_2.tscn"

## 有贴图就用贴图，没有就退回代码占位（出图之后放对路径即可，不改代码）
const PLAYER_TEX_CANDIDATES := [
	"res://assets/sprites/lixing_down.png",
	"res://assets/sprites/lixing.png",
]
const LIUYI_TEX_CANDIDATES := [
	"res://assets/sprites/liuyi_down.png",
	"res://assets/sprites/liuyi.png",
]

const DEFAULT_SCALE := 1.0
## 走路速度：走廊逻辑宽 2400，250 px/s 走一遍约 9.6 秒，不至于让人等得不耐烦
const WALK_SPEED := 250.0
## 人物的"身体半径"：新的俯视角人物约两格高（180 逻辑像素），
## 脚点判定要按这个尺度偏下去，否则走到物件正下方会被判成"太远"。
const PLAYER_BODY_R := 48.0

## 交互半径的宽松系数：判定距离 = reach × 这个系数。
## 【关键】距离不再是"脚点到物件中心的直线距离"，而是"脚点到**物件矩形**的距离"，
## 所以这个系数就是"在物件外多近算身边"：0.8 × reach（reach 一般是 130~160 逻辑像素，
## 也就是人物往前一格多一点）。旧版用中心距 + 脚点再往下一整个身位，
## 结果必须几乎站到物件身上才亮提示（用户反馈：「没有实现走到道具旁边进行交互」）。
const NEAR_FACTOR := 0.8
## 迟滞：已经选中的物件要走出 1.18 倍距离才会失去高亮，
## 免得两个物件的判定圈交界处提示反复闪。
const NEAR_HYST := 1.18

signal walk_finished()

var room_id := ""
var room: Dictionary = {}

var _walk_rects: Array = []      # 可走矩形（逻辑坐标）
var _items: Array = []           # 可交互物件
var _props: Array = []           # 固定陈设
var _solids: Array = []          # 挡路的陈设（脚点不能踩进去）
var _goal_item := ""             # 本房间要求的"必看物件"名（空 = 要看完所有物件）

# ---------------------------------------------------------------- 状态
var _player := Vector2(600, 520)
var _facing := Vector2(0, 1)
var _bob := 0.0
var _near: Dictionary = {}       # 当前最近的可交互物件
var _popup_item: Dictionary = {}
var _popup := false
var _act_lock := 0.0            # 收起弹窗后的输入冷却，避免一次按键反复开合
var _examine_count := 0

# ---------------------------------------------------------------- 节点
var _root: Control = null
var _backdrop: Control = null
var _hint: Label = null
var _help: Label = null
var _popup_layer: Control = null
var _done_btn: Button = null
var _toast: Label = null
var _toast_t := 0.0
var _notes: PreludeUI.NotesPanel = null   # 走位里也能翻笔记（Kerry：要能随时查看全部笔记）
var _notes_btn: Button = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_load_room()
	_build_ui()
	set_process(true)


## 宿主在 add_child 之前调用：指定要走的房间
func configure(p_room_id: String) -> void:
	room_id = p_room_id


# ============================================================================
#  数据
# ============================================================================

func _load_room() -> void:
	if room_id == "":
		push_error("[Walk] 没有指定房间 id")
		return
	if not FileAccess.file_exists(ROOMS_PATH):
		push_error("[Walk] 找不到房间数据：%s" % ROOMS_PATH)
		return
	var txt := FileAccess.get_file_as_string(ROOMS_PATH)
	var parsed: Variant = JSON.parse_string(txt)
	if not (parsed is Dictionary):
		push_error("[Walk] 房间数据不是合法的 JSON 对象")
		return
	var rooms: Dictionary = (parsed as Dictionary).get("rooms", {}) as Dictionary
	if not rooms.has(room_id):
		push_error("[Walk] 房间数据里没有这个房间：%s" % room_id)
		return
	room = (rooms[room_id] as Dictionary).duplicate(true)

	# 地板：新格式是墙高 + 地板行数 + 左右边界（单位＝格子），
	# 旧格式是若干个矩形 [x,y,w,h, ...]（并集），两种都支持。
	var fl: Array = room.get("floor", []) as Array
	if not fl.is_empty():
		var i := 0
		while i + 3 < fl.size():
			_walk_rects.append(Rect2(float(fl[i]), float(fl[i + 1]),
					float(fl[i + 2]), float(fl[i + 3])))
			i += 4
	else:
		var glyph := 96.0
		var wall_h := float(int(room.get("wall_rows", 3))) * glyph
		var fx := float(room.get("floor_x", 120.0))
		var fw := float(room.get("floor_w", 2160.0))
		var fh := float(int(room.get("floor_rows", 4))) * glyph
		# 可走带比地面略内缩，免得人物站到墙里或画到画面外
		_walk_rects.append(Rect2(fx + 10.0, wall_h + 8.0, fw - 20.0, fh - 16.0))

	# 固定陈设（在地面上、有厚度的东西）
	# 第 6 项可以是字符串（旧格式＝只写画法 kind），也可以是字典：
	#   {"kind": "rect", "solid": true}         → 拿自身矩形当碰撞体（略微内缩）
	#   {"kind": "rect", "solid": [x,y,w,h]}    → 拿给定矩形当碰撞体（比画面小一圈时用）
	# 【重要】默认 **不** 挡路：只有大型家具才写 solid（书架 / 柜台 / 衣柜 / 床 / 桌子），
	# 海报、便签、杯子这类小道具一律不挡路，否则人物会在细碎的地方被卡住。
	for p in (room.get("props", []) as Array):
		var pa: Array = p as Array
		var extra: Variant = pa[5] if pa.size() > 5 else null
		var kind := "rect"
		var solid: Variant = false
		if extra is Dictionary:
			var ed: Dictionary = extra
			kind = str(ed.get("kind", "rect"))
			solid = ed.get("solid", false)
		elif extra is String:
			kind = str(extra)
		_props.append({
			"x": float(pa[0]), "y": float(pa[1]),
			"w": float(pa[2]), "h": float(pa[3]),
			"label": str(pa[4]) if pa.size() > 4 else "",
			"kind": kind,
			"solid": solid,
		})

	# 嵌在墙上的东西（门 / 窗 / 柜）也交给绘制层，它是另一套画法
	# 第 6 项可选：字典，额外参数直接并进这条陈设（例如洞洞板的插板位置 shelves）
	for wl in (room.get("wall", []) as Array):
		var wa: Array = wl as Array
		if wa.size() < 3:
			continue
		var wd := {
			"kind": str(wa[0]),
			"x": float(wa[1]),
			"y": 0.0,
			"w": float(wa[2]),
			"h": float(wa[4]) if wa.size() > 4 else 168.0,
			"label": str(wa[3]) if wa.size() > 3 else "",
			"on_wall": true,
		}
		if wa.size() > 5 and wa[5] is Dictionary:
			for k in (wa[5] as Dictionary):
				wd[k] = (wa[5] as Dictionary)[k]
		_props.append(wd)

	# 挡路的陈设：只有数据里写了 solid 的大型家具（书架 / 柜台 / 衣柜 / 床 / 桌子）才挡路，
	# 人物要绕着走；海报、便签、杯子这类小道具不挡路。
	# 【说明】可交互物件（门牌、便签、地上的水渍…）**不**挡路——它们是"热区"不是障碍物，
	# 站到水渍上、贴着门牌站都是合理的；踩进桌子里就不合理了。
	for p in _props:
		var pd: Dictionary = p
		if bool(pd.get("on_wall", false)):
			continue
		var sp: Variant = pd.get("solid", false)
		if sp is bool:
			if not bool(sp):
				continue
			_solids.append(Rect2(float(pd["x"]) + 4.0, float(pd["y"]) + 6.0,
					maxf(8.0, float(pd["w"]) - 8.0), maxf(8.0, float(pd["h"]) - 6.0)))
		elif sp is Array and (sp as Array).size() >= 4:
			var sa: Array = sp
			_solids.append(Rect2(float(sa[0]), float(sa[1]),
					float(sa[2]), float(sa[3])))

	# 可交互物件：[x, y, w, h, reach, 名称, 详情, closeup路径]
	var st: Node = get_node_or_null("/root/PreludeState")
	for it in (room.get("items", []) as Array):
		var ia: Array = it as Array
		if ia.size() < 7:
			continue
		var nm := str(ia[5])
		var d := {
			"x": float(ia[0]), "y": float(ia[1]),
			"w": float(ia[2]), "h": float(ia[3]),
			"reach": float(ia[4]),
			"name": nm,
			"detail": str(ia[6]),
			"closeup": str(ia[7]) if ia.size() > 7 else "",
			"center": Vector2(float(ia[0]) + float(ia[2]) * 0.5,
					float(ia[1]) + float(ia[3]) * 0.5),
			"seen": false,
		}
		if st != null and bool(st.call("get_flag", "seen_" + nm, false)):
			d["seen"] = true
			_examine_count += 1
		_items.append(d)

	# 只要求看一件东西的房间（一周目的第 3 / 4 / 6 关）。
	# 台词里用 ["goal", 物件名] 声明的目标优先于房间自己的 goal_item——
	# 寝室这一间房一周目要用三次（书架 / 书桌 / 衣柜），目标只能由台词现给。
	_goal_item = str(room.get("goal_item", ""))
	if st != null:
		var wg := str(st.call("get_flag", "walk_goal_active", ""))
		if wg != "":
			_goal_item = wg

	# 起点
	var ps_v: Variant = room.get("player_start", null)
	if ps_v is Array and (ps_v as Array).size() >= 2:
		var pa2: Array = ps_v as Array
		_player = Vector2(float(pa2[0]), float(pa2[1]))
	else:
		_player = _floor_center()
	_player = _first_free_spot(_player)


func _floor_center() -> Vector2:
	if _walk_rects.is_empty():
		return Vector2(600, 520)
	var r: Rect2 = _walk_rects[0]
	return Vector2(r.position.x + r.size.x * 0.5, r.position.y + r.size.y * 0.62)


## 找一个不压住物件热区、也没踩进陈设里的落脚点（螺旋外扩）
func _first_free_spot(p: Vector2) -> Vector2:
	var probe := _clamp_to_floor(p)
	if _spot_ok(probe):
		return probe
	for ring in range(1, 16):
		var rad := float(ring) * 34.0
		for k in 12:
			var ang := TAU * float(k) / 12.0
			var q := _clamp_to_floor(probe + Vector2(cos(ang), sin(ang)) * rad)
			if _spot_ok(q):
				return q
	return probe


func _spot_ok(p: Vector2) -> bool:
	return not _overlaps_item(p) and not _blocked(p)


func _overlaps_item(p: Vector2) -> bool:
	for d in _items:
		var r := Rect2(float(d["x"]) - 40.0, float(d["y"]) - 30.0,
				float(d["w"]) + 80.0, float(d["h"]) + 60.0)
		if r.has_point(p):
			return true
	return false


# ============================================================================
#  走位
# ============================================================================

func _can_stand(p: Vector2) -> bool:
	for r in _walk_rects:
		if (r as Rect2).has_point(p):
			return true
	return false


func _clamp_to_floor(p: Vector2) -> Vector2:
	if _walk_rects.is_empty():
		return p
	for r in _walk_rects:
		if (r as Rect2).has_point(p):
			return p
	var best := p
	var best_d := 1.0e20
	for r in _walk_rects:
		var rr: Rect2 = r
		var q := Vector2(clampf(p.x, rr.position.x, rr.end.x),
				clampf(p.y, rr.position.y, rr.end.y))
		var dist := q.distance_squared_to(p)
		if dist < best_d:
			best_d = dist
			best = q
	return best


## 脚点是否踩进了挡路陈设里
func _blocked(p: Vector2) -> bool:
	for r in _solids:
		if (r as Rect2).has_point(p):
			return true
	return false


## 带着阻挡走一步：先试整体位移，撞上了再分轴滑动。
## 分轴的好处是"贴着桌子横着走"不会卡死（整体位移会被判撞、分轴能过）。
func _try_move(cur: Vector2, step: Vector2) -> Vector2:
	# 万一起点本身就落在陈设里（数据改了 / 被别的东西推进去），
	# 直接放行整体位移，免得人物被永久卡死。
	if _blocked(cur):
		return _clamp_to_floor(cur + step)
	var full := _clamp_to_floor(cur + step)
	if not _blocked(full):
		return full
	var mx := _clamp_to_floor(Vector2(cur.x + step.x, cur.y))
	if not _blocked(mx):
		return mx
	var my := _clamp_to_floor(Vector2(cur.x, cur.y + step.y))
	if not _blocked(my):
		return my
	return cur


func _update_near() -> void:
	# 【关键·已修】两处都改：
	#  1) 判定点用 _player 本身——绘制层就是把 _player 当**脚点**画的
	#     （prelude_room_draw.gd 的 _draw_actors 直接把 _player 交给 _draw_person）。
	#     旧版在这里又加了 PLAYER_BODY_R * 1.2（+57.6）往下探，等于把身位算了两遍，
	#     于是"人明明站在门牌前"却判不出身边的物件。
	#  2) 距离用"到物件**矩形**的距离"，而不是到物件中心的距离。
	#     旧版是一张 280 宽的门牌也要算中心距，站在门牌正下方反而更远。
	var foot := _player
	var cur := str(_near["name"]) if not _near.is_empty() else ""
	_near = {}
	var best: Dictionary = {}
	var best_d := 1.0e20
	for d in _items:
		var dist := _distance_to_rect(foot, d)
		var limit := float(d["reach"]) * NEAR_FACTOR
		if cur != "" and str(d["name"]) == cur:
			limit *= NEAR_HYST
		if dist <= limit and dist < best_d:
			best_d = dist
			best = d
	_near = best


## 点到物件矩形的距离（点在矩形内为 0）
func _distance_to_rect(p: Vector2, d: Dictionary) -> float:
	var x := float(d["x"])
	var y := float(d["y"])
	var q := Vector2(clampf(p.x, x, x + float(d["w"])),
			clampf(p.y, y, y + float(d["h"])))
	return p.distance_to(q)


# ============================================================================
#  UI
# ============================================================================

func _build_ui() -> void:
	# 0. 手绘底（同一支铅笔画的房间）
	_backdrop = Control.new()
	_backdrop.name = "RoomBackdrop"
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop.set_script(load(BACKDROP_SCRIPT))
	add_child(_backdrop)
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# 1. 靠近提示
	_hint = Label.new()
	_hint.name = "WalkHint"
	_hint.add_theme_font_size_override("font_size", PreludeUI.FS_TEXT)
	_hint.add_theme_color_override("font_color", PreludeUI.C_NAME)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.modulate.a = 0.0
	add_child(_hint)
	_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.offset_left = -320.0
	_hint.offset_right = 320.0
	_hint.offset_top = -172.0
	_hint.offset_bottom = -142.0

	# 2. 操作提示（左下角，避开右下角的按钮）
	_help = Label.new()
	_help.name = "WalkHelp"
	_help.text = "WASD / 方向键  走动          空格 / 点击  查看"
	_help.add_theme_font_size_override("font_size", PreludeUI.FS_TIP)
	_help.add_theme_color_override("font_color", PreludeUI.C_INK_DIM)
	_help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_help)
	_help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_help.offset_left = 34.0
	_help.offset_top = -34.0
	_help.offset_right = 640.0
	_help.offset_bottom = -8.0

	# 3. 场景名（左上）
	var title := Label.new()
	title.name = "WalkTitle"
	title.text = "%s   ·   %s" % [str(room.get("title", "")), str(room.get("subtitle", ""))]
	title.add_theme_font_size_override("font_size", PreludeUI.FS_TIP)
	title.add_theme_color_override("font_color", PreludeUI.C_INK_DIM)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	title.offset_left = 34.0
	title.offset_top = 26.0
	title.offset_right = 700.0
	title.offset_bottom = 56.0

	# 3.5 笔记按钮（右上角）+ 笔记面板：走位里也能随时翻看读过的全部笔记
	#     （Kerry：「把笔记系统完整，放一个按钮可以查看过去全部笔记」——
	#      以前只有对话界面能按 Tab 翻笔记，走位的时候翻不了。）
	_notes_btn = Button.new()
	_notes_btn.name = "WalkNotes"
	_notes_btn.text = "笔记  (Tab)"
	PreludeUI.apply_button_skin(_notes_btn)
	_notes_btn.add_theme_font_size_override("font_size", PreludeUI.FS_TIP)
	_notes_btn.pressed.connect(_toggle_notes)
	add_child(_notes_btn)
	_notes_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_notes_btn.offset_left = -178.0
	_notes_btn.offset_top = 22.0
	_notes_btn.offset_right = -34.0
	_notes_btn.offset_bottom = 60.0

	_notes = PreludeUI.NotesPanel.new()
	_notes.name = "WalkNotesPanel"
	_notes.z_index = 8          # 比弹窗层（默认 0）高，翻开笔记时不会被弹窗盖住
	_notes.closed.connect(_on_notes_closed)
	add_child(_notes)
	_notes.visible = false

	# 4. "看完了"按钮（右下）
	_done_btn = Button.new()
	_done_btn.name = "WalkDone"
	PreludeUI.apply_button_skin(_done_btn, true)
	_done_btn.pressed.connect(_on_done)
	add_child(_done_btn)
	_done_btn.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_done_btn.offset_left = -260.0
	_done_btn.offset_right = -34.0
	_done_btn.offset_top = -96.0
	_done_btn.offset_bottom = -52.0
	_update_done_button()

	# 5. 提示气泡（顶部）
	_toast = Label.new()
	_toast.name = "WalkToast"
	_toast.add_theme_font_size_override("font_size", PreludeUI.FS_TIP)
	_toast.add_theme_color_override("font_color", PreludeUI.C_NAME)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.modulate.a = 0.0
	add_child(_toast)
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toast.offset_left = -320.0
	_toast.offset_right = 320.0
	_toast.offset_top = 30.0
	_toast.offset_bottom = 60.0

	# 弹窗层按需创建，省掉空引用
	_popup_layer = null


func _update_done_button() -> void:
	if _done_btn == null:
		return
	# 【一周目】有些房间只要求"走到某件东西旁边看完它"（goal_item），
	# 这时按钮只认那一件，不逼玩家把屋里每样东西都点一遍。
	if _goal_item != "":
		if _goal_seen():
			_done_btn.text = "看完了"
		else:
			_done_btn.text = "看完了（先去%s看看）" % _goal_item
		return
	# 同样直接数物件表，别信计数器
	var left := 0
	for d in _items:
		if not bool((d as Dictionary).get("seen", false)):
			left += 1
	if left > 0:
		_done_btn.text = "看完了（还有 %d 件没看）" % left
	else:
		_done_btn.text = "看完了"


## 这个房间要求的"必看物件"是否已经看过（没设 goal_item 时恒为 true）
func _goal_seen() -> bool:
	if _goal_item == "":
		return true
	for d in _items:
		var dd: Dictionary = d
		if str(dd.get("name", "")) == _goal_item:
			return bool(dd.get("seen", false))
	return true


func _toast_msg(msg: String) -> void:
	if _toast == null:
		return
	_toast.text = msg
	_toast.modulate.a = 1.0
	_toast_t = 2.2


# ============================================================================
#  每帧
# ============================================================================

func _process(delta: float) -> void:
	if _act_lock > 0.0:
		_act_lock = maxf(0.0, _act_lock - delta)
	if _backdrop != null and _backdrop.has_method("set_room"):
		_backdrop.call("set_room", room, _player, _near, _items, _props, _popup)

	if not _popup and not _notes_open():
		var dir := Vector2.ZERO
		dir.x = Input.get_action_strength("prelude_walk_right") - Input.get_action_strength("prelude_walk_left")
		dir.y = Input.get_action_strength("prelude_walk_down") - Input.get_action_strength("prelude_walk_up")
		if dir.length_squared() > 0.0001:
			dir = dir.normalized()
			_facing = dir
			_player = _try_move(_player, dir * WALK_SPEED * delta)
			_bob += delta * 9.0
		_update_near()

	if _hint != null:
		if _near.is_empty():
			_hint.modulate.a = maxf(0.0, _hint.modulate.a - 0.12)
		else:
			_hint.text = "「%s」   空格 查看" % str(_near["name"])
			_hint.modulate.a = 1.0

	if _toast != null and _toast_t > 0.0:
		_toast_t -= delta
		if _toast_t <= 0.0:
			_toast.modulate.a = 0.0


## 安全地"吃掉"这次输入。
## 【坑】按「看完了」会切场景，切换过程中本节点可能已经离树、
## get_viewport() 返回 null，直接调 set_input_as_handled() 会报
## `SCRIPT ERROR: Cannot call method 'set_input_as_handled' on a null value.`，
## 这条错误会打断场景切换，表现成"按了看完了之后卡住 / 像退出去了"。
func _eat() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	vp.set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	# 笔记翻开着：只让笔记吃输入（Tab / Esc / 空格 合上），走位与查看都停住
	if _notes_open():
		if event.is_action_pressed("prelude_notes") or event.is_action_pressed("ui_cancel") \
				or event.is_action_pressed("prelude_advance"):
			_notes.close()
			_eat()
		return
	if event.is_action_pressed("prelude_notes"):
		_toggle_notes()
		_eat()
		return
	if _popup:
		if event.is_action_pressed("prelude_walk_act") or event.is_action_pressed("prelude_advance"):
			_close_popup()
			_eat()
		elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
				and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			_close_popup()
			_eat()
		return
	# 收起弹窗后短暂锁一下：否则"按一下空格"会同一帧把弹窗又打开，
	# 玩家看到的是弹窗闪一下就没了（长按空格更是完全打不开）。
	if _act_lock > 0.0:
		return
	if event.is_action_pressed("prelude_walk_act"):
		if not _near.is_empty():
			_examine(_near)
		else:
			# 身边没东西时按空格：不要让玩家以为"按了没反应、是不是卡住了"，
			# 明确告诉他该干什么。
			_toast_msg("走到东西旁边再按空格（WASD / 方向键 走动）")
		_eat()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		if not _near.is_empty():
			_examine(_near)
			_eat()


# ============================================================================
#  查看 / 弹窗
# ============================================================================

func _examine(d: Dictionary) -> void:
	var first_time := not bool(d.get("seen", false))
	if first_time:
		d["seen"] = true
		_examine_count += 1
		_update_done_button()
		var st: Node = get_node_or_null("/root/PreludeState")
		if st != null:
			st.call("set_flag", "seen_" + str(d["name"]), true)
			st.call("note_examined", str(d["name"]))
			# 走位里读到的东西也要进笔记 —— 以前只记"看过"，按 Tab 一片空白
			# （Kerry：「把笔记系统完整，放一个按钮可以查看过去全部笔记」）。
			var detail := str(d.get("detail", ""))
			if detail == "":
				detail = str(d.get("text", ""))
			st.call("add_card", "%s：%s" % [str(d["name"]), detail] if detail != "" else str(d["name"]))
	_show_popup(d, first_time)


func _show_popup(d: Dictionary, first_time: bool) -> void:
	if _popup_layer != null:
		_popup_layer.queue_free()
		_popup_layer = null

	_popup_item = d
	_popup = true

	_popup_layer = Control.new()
	_popup_layer.name = "CloseupPopup"
	# 【坑】这里（连同下面的 dim）必须是 IGNORE：面板以外的地方点了要能传给
	# _unhandled_input 去关弹窗，否则提示写着"点击 / 空格 收起来"，
	# 点空白处却毫无反应（STOP 会把全屏的鼠标事件吃掉）。
	_popup_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_popup_layer)
	_popup_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# 压暗（手绘底是亮的，要压得够狠，弹窗上的字才读得清）
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.03, 0.88)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_popup_layer.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# 纸面板：贴在画面偏上的位置，避免和底部提示/按钮打架
	var panel := PanelContainer.new()
	panel.name = "CloseupPanel"
	panel.add_theme_stylebox_override("panel",
			PreludeUI.panel_skin(Color(0.070, 0.068, 0.080, 0.97),
					Color(0.88, 0.80, 0.62, 0.60), 4))
	_popup_layer.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 214.0
	panel.offset_right = -214.0
	panel.offset_top = 34.0
	panel.offset_bottom = panel.offset_top + 556.0

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	# 关键：不设 expand-fill 时 VBox 会按"最大子项的最小宽度"撑高，
	# 之前就把面板内容撑成 1248 高、文字溢出到面板外面。
	vb.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	vb.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	panel.add_child(vb)

	# 放大图：居中、留白，别顶到面板边
	var art_row := HBoxContainer.new()
	art_row.name = "CloseupArtRow"
	art_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(art_row)

	var art := TextureRect.new()
	art.name = "CloseupArt"
	art.custom_minimum_size = Vector2(0, 260)
	art.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	art.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var tex := _load_first(str(d.get("closeup", "")))
	if tex != null:
		art.texture = tex
	else:
		# 没有贴图：放一块占位（不是画图，是明确标出"这里等一张美术"）
		art.texture = _placeholder_texture(str(d["name"]))
	art_row.add_child(art)

	var name_label := Label.new()
	name_label.name = "CloseupName"
	name_label.text = str(d["name"])
	name_label.add_theme_font_size_override("font_size", PreludeUI.FS_NAME)
	name_label.add_theme_color_override("font_color", PreludeUI.C_NAME)
	vb.add_child(name_label)

	var sep := PreludeUI.hline(0.0, PreludeUI.C_LINE)
	vb.add_child(sep)

	var body := RichTextLabel.new()
	body.name = "CloseupBody"
	body.bbcode_enabled = true
	body.fit_content = true
	body.custom_minimum_size = Vector2(0, 104)
	body.add_theme_font_size_override("normal_font_size", PreludeUI.FS_TEXT)
	body.add_theme_color_override("default_color", PreludeUI.C_INK)
	body.text = str(d["detail"])
	vb.add_child(body)

	var tip := Label.new()
	tip.name = "CloseupTip"
	tip.text = "（点击 / 空格  收起来）"
	tip.add_theme_font_size_override("font_size", PreludeUI.FS_TIP)
	tip.add_theme_color_override("font_color", PreludeUI.C_INK_DIM)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vb.add_child(tip)

	if first_time:
		_toast_msg("已记下：「%s」" % str(d["name"]))

	# 弹窗打开期间把走位 UI 收起来，避免文字叠在一起
	_set_walk_ui_visible(false)

	# 淡入
	_popup_layer.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_popup_layer, "modulate:a", 1.0, 0.16)


func _set_walk_ui_visible(v: bool) -> void:
	if _hint != null:
		_hint.visible = v
	if _help != null:
		_help.visible = v
	if _done_btn != null:
		_done_btn.visible = v
	if _toast != null:
		_toast.visible = v
	if _notes_btn != null:
		_notes_btn.visible = v


# ---------------------------------------------------------------- 笔记

## 走位里也能翻笔记（Kerry：「放一个按钮可以查看过去全部笔记」）
func _toggle_notes() -> void:
	if _notes == null:
		return
	if _notes.is_open():
		_notes.close()
	else:
		_notes.open(PreludeState.cards)
		_set_walk_ui_visible(false)


func _notes_open() -> bool:
	return _notes != null and _notes.is_open()


## 暂停菜单（autoload PauseMenu）问的："现在有覆盖层开着吗？"
## 走位里开着笔记、或正弹着物件详情时，Esc 归我（用来关那一层），不弹暂停菜单。
func blocks_pause() -> bool:
	return _notes_open() or _popup


func _on_notes_closed() -> void:
	if not _popup:
		_set_walk_ui_visible(true)


func _close_popup() -> void:
	_popup = false
	_popup_item = {}
	_act_lock = 0.22
	if _popup_layer != null:
		_popup_layer.queue_free()
		_popup_layer = null
	_set_walk_ui_visible(true)


## 占位图：一张写着物件名的纸，明确告诉美术"这里等一张放大图"
func _placeholder_texture(label_text: String) -> Texture2D:
	var img := Image.create(640, 300, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.175, 0.170, 0.190, 1.0))
	# 边框
	for x in img.get_width():
		img.set_pixel(x, 0, Color(0.92, 0.84, 0.64, 0.85))
		img.set_pixel(x, img.get_height() - 1, Color(0.92, 0.84, 0.64, 0.85))
	for y in img.get_height():
		img.set_pixel(0, y, Color(0.92, 0.84, 0.64, 0.85))
		img.set_pixel(img.get_width() - 1, y, Color(0.92, 0.84, 0.64, 0.85))
	# 交叉对角线，一眼看出是占位
	var w := img.get_width()
	var h := img.get_height()
	for i in maxi(w, h):
		if i < w:
			img.set_pixel(i, int(float(i) * float(h) / float(w)), Color(0.84, 0.78, 0.64, 0.34))
			img.set_pixel(i, h - 1 - int(float(i) * float(h) / float(w)), Color(0.84, 0.78, 0.64, 0.34))
	return ImageTexture.create_from_image(img)


func _load_first(paths: String) -> Texture2D:
	if paths == "":
		return null
	if ResourceLoader.exists(paths):
		var res := load(paths)
		if res is Texture2D:
			return res as Texture2D
	return null


func _on_done() -> void:
	# 【一周目】只要求"必看物件"的房间：没看完那一件就先别走
	if _goal_item != "" and not _goal_seen():
		_toast_msg("先去「%s」看看（WASD / 方向键 走动，空格查看）" % _goal_item)
		return
	# 剩余件数直接从物件表里数，不用任何缓存计数器——
	# 计数器只要有一处漏加，就会出现"明明都看完了却一直说还有 4 件没看"。
	var left := 0
	for d in _items:
		if not bool((d as Dictionary).get("seen", false)):
			left += 1
	if left > 0 and _goal_item == "":
		_toast_msg("还有 %d 件没看（再走走看）" % left)
		return
	var st: Node = get_node_or_null("/root/PreludeState")
	var ch := "act1"
	var back := ""
	if st != null:
		st.call("set_flag", "walk_return", true)
		ch = str(st.call("get_flag", "walk_chapter", "act1"))
		back = str(st.call("get_flag", "walk_return_scene", ""))
	walk_finished.emit()
	if back != "":
		# 一周目：发起走位的是哪一幕就回哪一幕
		get_tree().change_scene_to_file(back)
		return
	get_tree().change_scene_to_file(DIALOGUE_2 if ch == "act2" else DIALOGUE_1)
