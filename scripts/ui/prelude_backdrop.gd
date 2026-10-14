extends Control
## ============================================================================
##  《寻星》前日谈 —— 手绘风场景底（纯代码绘制，零素材依赖）
## ============================================================================
##  设计目标：和 assets 里那两张灰白手绘立绘「同一种笔」，而不是照片或纯色板。
##  所以整张底只有三样东西：
##    · 一层暗色基调（分场景换色）
##    · 铅笔感的线与面（半透明白色描边、切角、排线阴影）
##    · 少量暖色强调（高窗的光、顶灯、十月末的余晖）
##  对话那套全部按 1280x720 的设计坐标画，再按窗口等比放大，因此任意分辨率都不糊。
##  俯视角走位那套是另一套坐标（房间 2400 宽 + 96 的格子），绘制逻辑放在
##  scripts/ui/prelude_room_draw.gd 里，本文件只负责转发。
##
##  【踩过的坑，别改回去】
##    · 必须用 set_anchors_and_offsets_preset：只设 anchor 不改 offset 会让画布
##      保持 0×0，而 CanvasItem 尺寸为 0 时画的东西会被自己的矩形裁掉，整屏空白。
##    · 缩放/平移只能用 draw_set_transform_matrix，不要用 draw_set_transform 做缩放：
##      Godot 4.7 / GL Compatibility 下它对 draw_polyline / draw_colored_polygon 会失效。
##    · 三角形永远能三角化成功；凹四边形会让 draw_colored_polygon 报
##      "Invalid polygon data, triangulation failed" 并刷屏。几何一律优先用三角形。
##    · 几何体一律优先用三角形。
## ============================================================================

# ---------------------------------------------------------------- 调色
# 【与立绘同一种笔】：两张立绘的线稿是明确的深色中粗线 + 灰调块面，所以场景底
# 不能只用细淡线。第一版把 C_LINE 压到 0.22 透明度，结果场景像「没画完的草稿」，
# 立绘贴上去像贴纸。这里把主线提到 0.46，并保留一条更淡的辅助线做层次。
const C_DEEP := Color(0.075, 0.078, 0.095)          # 最暗
const C_MID := Color(0.135, 0.138, 0.158)           # 中间调
const C_LIGHT := Color(0.26, 0.27, 0.30)            # 受光面
const C_LINE := Color(0.88, 0.87, 0.84, 0.46)       # 铅笔画线（主线）
const C_LINE_SOFT := Color(0.86, 0.85, 0.82, 0.16)  # 更轻的线（辅助）
const C_HATCH := Color(0.0, 0.0, 0.0, 0.26)         # 排线阴影
const C_WARM := Color(0.98, 0.82, 0.55)             # 暖光
const C_WARM_DIM := Color(0.80, 0.62, 0.42)         # 弱暖光
const C_COOL := Color(0.60, 0.70, 0.85)             # 冷光（走廊灯 / 夜色）
const C_DUSK := Color(0.85, 0.55, 0.36)             # 十月末余晖

const ROOM_DRAW_SCRIPT := "res://scripts/ui/prelude_room_draw.gd"

var _t := 0.0
var _scene := "hallway"
## 阳台门是否开着 —— 第二幕的关键伏笔（二周目第 6 关回收）
var balcony_open := true

# ---------------------------------------------------------------- 俯视角走位模式
# 对话那套用 _scene 切场景；走位那套用下面这些字段，两套互不干扰。
# 真正的绘制在 prelude_room_draw.gd，这里只保留状态并转发。
## 非空即表示「当前在画俯视角房间」
var _room: Dictionary = {}
var _r_player := Vector2(600, 520)
var _r_near: Dictionary = {}
var _r_items: Array = []
var _r_props: Array = []
var _r_popup := false
var _r_scale := 0.92
var _room_on := false
var _room_draw: RefCounted = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 必须是 *_and_offsets_* 版本：只设 anchor 不改 offset 会让画布保持 0×0，
	# 整个手绘场景就一片空白。
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)
	set_process(true)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func set_scene(key: String) -> void:
	if _scene == key:
		return
	_scene = key
	queue_redraw()


# ---------------------------------------------------------------- 俯视角房间接口
## 由 scripts/ui/room_runtime.gd 每帧调用。room 为空字典 = 退出走位模式。
func set_room(room: Dictionary, player: Vector2, near: Dictionary,
		items: Array, props: Array, popup: bool) -> void:
	_room = room
	_r_player = player
	_r_near = near
	_r_items = items
	_r_props = props
	_r_popup = popup
	_room_on = not room.is_empty()
	_r_scale = float(room.get("scale", 1.0))
	if _room_draw == null and ResourceLoader.exists(ROOM_DRAW_SCRIPT):
		_room_draw = load(ROOM_DRAW_SCRIPT).new()
	if _room_draw != null:
		_room_draw.call("set_room", room, player, near, items, props, popup, _r_scale, _t)
	queue_redraw()


# ---------------------------------------------------------------- 画布坐标换算
## 以 1280x720 为设计尺寸，等比铺满窗口（居中裁切）
func _xform() -> Transform2D:
	var win := get_viewport_rect().size
	if win.x <= 0.0 or win.y <= 0.0:
		win = size
	if win.x <= 0.0 or win.y <= 0.0:
		win = Vector2(1280, 720)
	var s := maxf(win.x / 1280.0, win.y / 720.0)
	var off := (win - Vector2(1280, 720) * s) * 0.5
	return Transform2D(0.0, Vector2(s, s), 0.0, off)


func _draw() -> void:
	# 走位模式：整张画面交给房间绘制（它是自己的一套坐标，不走 1280x720 的设计框）
	if _room_on and _room_draw != null:
		_room_draw.set("_t", _t)
		_room_draw.call("draw_room", self)
		return

	draw_set_transform_matrix(_xform())

	# 基调
	draw_rect(Rect2(0, 0, 1280, 720), _base_color())

	match _scene:
		"hallway":
			_hallway()
		"classroom":
			_classroom()
		"montage":
			_montage()
		"roofline":
			_roofline()
		"dorm_corridor":
			_dorm_corridor()
		"dorm_room":
			_dorm_room()
		"black":
			pass
		_:
			_hallway()

	# 压角暗影：让画面中心更聚焦，也帮 UI 上的文字读得清
	_vignette()


func _base_color() -> Color:
	match _scene:
		"hallway":
			return Color(0.105, 0.108, 0.130)
		"classroom":
			return Color(0.086, 0.090, 0.108)
		"montage":
			return Color(0.095, 0.095, 0.115)
		"roofline":
			return Color(0.085, 0.092, 0.115)
		"dorm_corridor":
			return Color(0.150, 0.112, 0.092)
		"dorm_room":
			return Color(0.098, 0.094, 0.104)
		"black":
			return Color(0.012, 0.012, 0.016)
		_:
			return C_DEEP


# ============================================================================
#  通用零件
# ============================================================================

func _pencil(a: Vector2, b: Vector2, w := 1.4, c := C_LINE) -> void:
	draw_line(a, b, c, w, true)


func _pencil_rect(r: Rect2, w := 1.4, c := C_LINE) -> void:
	draw_rect(r, c, false, w)


func _fill_rect(r: Rect2, c: Color) -> void:
	draw_rect(r, c, true)


## 排线阴影：在矩形内画一组斜线（手绘排线的味道）
func _hatch(r: Rect2, spacing := 9.0, c := C_HATCH, w := 1.0, flip := false) -> void:
	var total := r.size.x + r.size.y
	var n := int(total / spacing)
	for i in n + 1:
		var t := float(i) * spacing
		var p1: Vector2
		var p2: Vector2
		if flip:
			p1 = Vector2(r.position.x, r.position.y + t)
			p2 = Vector2(r.position.x + t, r.position.y)
		else:
			p1 = Vector2(r.position.x + t, r.position.y)
			p2 = Vector2(r.position.x, r.position.y + t)
		# 裁到矩形内：手动夹一下，免得排线糊到画面外
		p1 = _clamp_in(p1, r)
		p2 = _clamp_in(p2, r)
		if p1.distance_to(p2) < 1.0:
			continue
		draw_line(p1, p2, c, w, true)


func _clamp_in(p: Vector2, r: Rect2) -> Vector2:
	return Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))


## 一道「光柱」（高窗打进来的光）
func _light_shaft(pts: PackedVector2Array, c: Color) -> void:
	draw_colored_polygon(pts, c)


## 天空渐变（用几条横带模拟，省掉 shader）
func _sky_bands(r: Rect2, top: Color, bottom: Color, bands := 26) -> void:
	for i in bands:
		var t := float(i) / float(bands - 1)
		var c := top.lerp(bottom, t)
		var y := r.position.y + r.size.y * t
		draw_rect(Rect2(r.position.x, y, r.size.x, r.size.y / float(bands) + 1.5), c)


func _glow(center: Vector2, radius: float, c: Color, rings := 12) -> void:
	for i in rings:
		var t := float(i) / float(rings)
		var rr := radius * (1.0 - t)
		var a := c.a * (1.0 - t) * 0.5
		draw_circle(center, rr, Color(c.r, c.g, c.b, a))


func _vignette() -> void:
	# 四条边各一层渐变暗角
	var steps := 10
	for i in steps:
		var t := float(i) / float(steps)
		var a := 0.05 * (1.0 - t)
		var inset := t * 120.0
		var col := Color(0, 0, 0, a)
		draw_rect(Rect2(0, 0, 1280, 18.0 + inset), col)
		draw_rect(Rect2(0, 720 - 18.0 - inset, 1280, 18.0 + inset), col)
		draw_rect(Rect2(0, 0, 18.0 + inset, 720), col)
		draw_rect(Rect2(1280 - 18.0 - inset, 0, 18.0 + inset, 720), col)


# ============================================================================
#  场景 1 · 教学楼走廊尽头 / 推理社门口
# ============================================================================
func _hallway() -> void:
	# 透视：走廊往右后方收（尽头在 x≈980）
	var vanish := Vector2(980, 330)

	# 地板
	draw_colored_polygon(PackedVector2Array([
		Vector2(-40, 720), Vector2(1320, 720), Vector2(vanish.x + 120, vanish.y), Vector2(vanish.x - 240, vanish.y)
	]), C_MID)
	_hatch(Rect2(0, 430, 560, 290), 11.0, Color(0, 0, 0, 0.14))

	# 右侧墙 + 一路退到尽头的门
	draw_colored_polygon(PackedVector2Array([
		Vector2(1280, 60), Vector2(1280, 720), Vector2(vanish.x + 200, vanish.y + 40), Vector2(vanish.x + 60, vanish.y - 120)
	]), C_LIGHT)
	# 一排门（近大远小）
	var door_x := 1160.0
	var door_scale := 1.0
	for i in 4:
		var dw := 150.0 * door_scale
		var dh := 300.0 * door_scale
		var dy := vanish.y - 20.0 + (1.0 - door_scale) * 120.0
		var r := Rect2(door_x - dw, dy, dw, dh)
		_fill_rect(r, Color(0.09, 0.092, 0.108))
		_pencil_rect(r, 1.4, C_LINE_SOFT)
		# 门上小窗
		_fill_rect(Rect2(r.position.x + dw * 0.18, dy + dh * 0.14, dw * 0.64, dh * 0.22), Color(0.16, 0.18, 0.22))
		_pencil_rect(Rect2(r.position.x + dw * 0.18, dy + dh * 0.14, dw * 0.64, dh * 0.22), 1.0, C_LINE_SOFT)
		door_x -= dw * 0.92
		door_scale *= 0.82

	# 尽头：推理社的门（唯一一扇开着、露光的）
	var end_door := Rect2(vanish.x - 96, vanish.y - 108, 132, 250)
	_fill_rect(end_door, Color(0.075, 0.078, 0.092))
	_pencil_rect(end_door, 1.8, C_LINE)
	# 门缝里漏出来的光
	var seam := Rect2(end_door.position.x + end_door.size.x - 14, end_door.position.y + 8, 10, end_door.size.y - 16)
	_fill_rect(seam, Color(1.0, 0.86, 0.60, 0.20))
	_glow(Vector2(seam.position.x + 5, vanish.y), 120.0, Color(1.0, 0.84, 0.56, 0.30))
	# 手写门牌
	_pencil_rect(Rect2(end_door.position.x + 22, end_door.position.y - 26, 88, 20), 1.2, Color(0.95, 0.90, 0.78, 0.55))
	_pencil(Vector2(end_door.position.x + 30, end_door.position.y - 16),
			Vector2(end_door.position.x + 100, end_door.position.y - 16), 1.0, Color(0.95, 0.90, 0.78, 0.35))

	# 左侧墙裙
	draw_colored_polygon(PackedVector2Array([
		Vector2(-40, 120), Vector2(vanish.x - 300, vanish.y - 130), Vector2(vanish.x - 300, vanish.y + 20), Vector2(-40, 600)
	]), Color(0.115, 0.118, 0.138, 1.0))
	_pencil(Vector2(-40, 600), Vector2(vanish.x - 300, vanish.y + 20), 1.6, C_LINE_SOFT)

	# 高窗 —— 光从这打进来
	var win := Rect2(120, 70, 300, 210)
	_fill_rect(win, Color(0.36, 0.33, 0.28))
	_sky_bands(win, Color(0.62, 0.55, 0.44), Color(0.30, 0.28, 0.27), 18)
	# 窗棂
	for i in 4:
		var x := win.position.x + win.size.x * (float(i) / 3.0)
		_pencil(Vector2(x, win.position.y), Vector2(x, win.end.y), 2.0, Color(0.10, 0.10, 0.12, 0.85))
	for j in 3:
		var y := win.position.y + win.size.y * (float(j) / 2.0)
		_pencil(Vector2(win.position.x, y), Vector2(win.end.x, y), 2.0, Color(0.10, 0.10, 0.12, 0.85))
	_pencil_rect(win, 3.0, Color(0.90, 0.88, 0.84, 0.30))

	# 光柱：从窗斜切到地板（缓慢呼吸）
	var breathe := 0.055 + 0.014 * sin(_t * 0.6)
	_light_shaft(PackedVector2Array([
		Vector2(win.position.x, win.position.y), Vector2(win.end.x, win.position.y),
		Vector2(win.end.x + 330, 720), Vector2(win.position.x + 96, 720)
	]), Color(1.0, 0.90, 0.70, breathe))
	# 光斑落在地板上
	_light_shaft(PackedVector2Array([
		Vector2(win.position.x + 96, 660), Vector2(win.end.x + 330, 660),
		Vector2(win.end.x + 380, 720), Vector2(win.position.x + 46, 720)
	]), Color(1.0, 0.90, 0.70, breathe * 0.8))

	# 浮尘
	_dust(Vector2(430, 380), 26)


## 缓慢漂浮的浮尘（用时间做确定性的伪随机，不用随机数保持稳定）
func _dust(center: Vector2, count: int) -> void:
	for i in count:
		var seed_a := float(i) * 12.9898
		var seed_b := float(i) * 78.233
		var dx := (fmod(abs(sin(seed_a) * 43758.5453), 1.0) - 0.5) * 620.0
		var dy := (fmod(abs(sin(seed_b) * 43758.5453), 1.0) - 0.5) * 430.0
		var drift := sin(_t * 0.35 + float(i)) * 14.0
		var p := center + Vector2(dx + drift * 0.5, dy + drift)
		var a: float = 0.10 + 0.10 * abs(sin(_t * 0.8 + float(i) * 2.1))
		draw_circle(p, 1.5, Color(1.0, 0.94, 0.82, a))


# ============================================================================
#  场景 2 · 推理社活动教室（在放电影）
# ============================================================================
func _classroom() -> void:
	# 后墙 + 黑板
	_fill_rect(Rect2(0, 0, 1280, 520), Color(0.105, 0.108, 0.126))
	var board := Rect2(150, 120, 700, 260)
	_fill_rect(board, Color(0.075, 0.088, 0.082))
	_pencil_rect(board, 3.0, Color(0.80, 0.78, 0.74, 0.18))
	# 黑板上没擦干净的旧字迹
	for i in 7:
		var y := board.position.y + 40.0 + float(i) * 30.0
		var w := 120.0 + fmod(abs(sin(float(i) * 3.7) * 43758.5), 1.0) * 300.0
		_pencil(Vector2(board.position.x + 40, y), Vector2(board.position.x + 40 + w, y), 1.2,
				Color(0.85, 0.85, 0.80, 0.07))

	# 投影幕布（挂在黑板前，画面正在放）
	var screen := Rect2(880, 120, 360, 250)
	_fill_rect(screen, Color(0.30, 0.30, 0.32))
	_sky_bands(screen, Color(0.46, 0.46, 0.48), Color(0.20, 0.20, 0.22), 14)
	_pencil_rect(screen, 2.0, Color(0.92, 0.90, 0.86, 0.22))
	# 幕布上的「审讯戏」剪影：两个人 + 一张桌子
	_fill_rect(Rect2(screen.position.x + 60, screen.position.y + 150, 240, 26), Color(0.14, 0.14, 0.16))
	_person_silhouette(Vector2(screen.position.x + 110, screen.position.y + 108), 46.0, 0.5)
	_person_silhouette(Vector2(screen.position.x + 250, screen.position.y + 112), 42.0, 0.42)
	# 投影仪光柱
	_light_shaft(PackedVector2Array([
		Vector2(470, 300), Vector2(520, 300), Vector2(900, 150), Vector2(880, 360)
	]), Color(0.80, 0.86, 1.0, 0.045))
	_glow(Vector2(1000, 400), 260.0, Color(0.70, 0.78, 0.95, 0.10))

	# 投影仪
	_fill_rect(Rect2(430, 286, 96, 34), Color(0.13, 0.13, 0.15))
	_pencil_rect(Rect2(430, 286, 96, 34), 1.4, C_LINE_SOFT)
	draw_circle(Vector2(470, 303), 9.0, Color(0.85, 0.90, 1.0, 0.55))
	_glow(Vector2(470, 303), 40.0, Color(0.85, 0.90, 1.0, 0.30))

	# 课桌（一排，近大远小）
	var dy := 470.0
	var ds := 1.0
	for row in 2:
		var dx := -60.0
		for col in 4:
			var w := 250.0 * ds
			var h := 20.0 * ds
			_fill_rect(Rect2(dx, dy, w, h), Color(0.155, 0.155, 0.175))
			_pencil_rect(Rect2(dx, dy, w, h), 1.4, C_LINE_SOFT)
			# 桌腿
			_pencil(Vector2(dx + 14, dy + h), Vector2(dx + 8, dy + h + 46.0 * ds), 2.0, C_LINE_SOFT)
			_pencil(Vector2(dx + w - 14, dy + h), Vector2(dx + w - 8, dy + h + 46.0 * ds), 2.0, C_LINE_SOFT)
			# 桌面排线
			_hatch(Rect2(dx + 8, dy + 4, w - 16, h - 8), 16.0, Color(0, 0, 0, 0.10))
			dx += w + 24.0
		dy += 96.0
		ds *= 0.90

	# 窗户（窗帘）
	var awin := Rect2(1100, 60, 150, 300)
	_fill_rect(awin, Color(0.28, 0.26, 0.24))
	_sky_bands(awin, Color(0.40, 0.34, 0.28), Color(0.18, 0.18, 0.20), 12)
	_pencil_rect(awin, 2.0, C_LINE_SOFT)
	var sway := sin(_t * 0.5) * 6.0
	draw_colored_polygon(PackedVector2Array([
		Vector2(awin.position.x - 20, 50), Vector2(awin.end.x + 20, 50),
		Vector2(awin.end.x + 20 + sway, 430), Vector2(awin.position.x - 20 + sway, 430)
	]), Color(0.20, 0.19, 0.21, 0.55))

	_dust(Vector2(760, 300), 18)


func _person_silhouette(base: Vector2, h: float, a: float) -> void:
	var c := Color(0.10, 0.10, 0.12, a)
	draw_circle(base - Vector2(0, h * 0.78), h * 0.16, c)
	# 躯干用三角形，不要用四边形。四边形只要有一个角是凹的（叉积符号翻转），
	# Godot 的 ear-clipping 就会失败并刷屏：
	#   ERROR: Invalid polygon data, triangulation failed.
	# 三角形永远能三角化，所以这里固定三角形。
	draw_colored_polygon(PackedVector2Array([
		base + Vector2(h * 0.24, 0),
		base - Vector2(h * 0.24, 0),
		base - Vector2(0, h * 0.70)
	]), c)


# ============================================================================
#  场景 3 · 蒙太奇（借还书 / 笔记本 / 空掉的课表）
# ============================================================================
func _montage() -> void:
	# 三块「漂浮的纸」：书页 / 笔记本 / 活动表，轻微浮动
	var bob := sin(_t * 0.6) * 5.0
	var bob2 := sin(_t * 0.5 + 1.4) * 6.0
	var bob3 := sin(_t * 0.7 + 2.2) * 4.0

	# 左：摊开的书
	_page(Rect2(120, 170 + bob, 300, 380), -0.06)
	# 中：笔记本（三栏）
	_page(Rect2(500, 130 + bob2, 320, 420), 0.02)
	_note_columns(Rect2(520, 160 + bob2, 280, 360))
	# 右：活动表（格子）
	_page(Rect2(880, 210 + bob3, 280, 320), 0.07)
	_schedule_grid(Rect2(900, 240 + bob3, 240, 260))

	_glow(Vector2(640, 360), 620.0, Color(0.9, 0.86, 0.72, 0.06))


## 一张浮在暗处的纸
func _page(r: Rect2, rot: float) -> void:
	var xf := _xform() * Transform2D(rot, Vector2(1, 1), 0.0, Vector2(r.position.x + r.size.x * 0.5, r.position.y + r.size.y * 0.5))
	draw_set_transform_matrix(xf)
	var rr := Rect2(-r.size * 0.5, r.size)
	_fill_rect(rr, Color(0.85, 0.84, 0.80, 0.055))
	_pencil_rect(rr, 1.4, Color(0.90, 0.88, 0.82, 0.26))
	_hatch(rr, 14.0, Color(1.0, 1.0, 1.0, 0.014))
	draw_set_transform_matrix(_xform())


func _note_columns(r: Rect2) -> void:
	# 三栏：行为 → 情感 → 例证
	for i in 3:
		var x := r.position.x + r.size.x * (float(i) / 3.0)
		_pencil(Vector2(x, r.position.y), Vector2(x, r.end.y), 1.0, Color(0.90, 0.88, 0.82, 0.16))
	# 假字迹
	for row in 9:
		var y := r.position.y + 26.0 + float(row) * 34.0
		for i in 3:
			var x0 := r.position.x + r.size.x * (float(i) / 3.0) + 10.0
			var w := 20.0 + fmod(abs(sin(float(row * 3 + i) * 5.1) * 43758.5), 1.0) * 48.0
			_pencil(Vector2(x0, y), Vector2(x0 + w, y), 1.2, Color(0.92, 0.90, 0.84, 0.13))
	# 第三栏有几行被画了重点
	for row in [2, 5]:
		var y := r.position.y + 26.0 + float(row) * 34.0
		_pencil(Vector2(r.position.x + r.size.x * 0.68, y + 5),
				Vector2(r.position.x + r.size.x * 0.68 + 56, y + 5), 2.0, Color(0.80, 0.42, 0.38, 0.35))


func _schedule_grid(r: Rect2) -> void:
	var cols := 5
	var rows := 4
	for i in cols + 1:
		var x := r.position.x + r.size.x * (float(i) / float(cols))
		_pencil(Vector2(x, r.position.y), Vector2(x, r.end.y), 1.0, Color(0.90, 0.88, 0.82, 0.14))
	for j in rows + 1:
		var y := r.position.y + r.size.y * (float(j) / float(rows))
		_pencil(Vector2(r.position.x, y), Vector2(r.end.x, y), 1.0, Color(0.90, 0.88, 0.82, 0.14))
	# 空格子：越往后越空（呼应「空掉的课表」）
	var empties := [
		Vector2i(3, 1), Vector2i(4, 1), Vector2i(2, 2), Vector2i(3, 2),
		Vector2i(4, 2), Vector2i(1, 3), Vector2i(2, 3), Vector2i(3, 3), Vector2i(4, 3)
	]
	for e in empties:
		var cw := r.size.x / float(cols)
		var ch := r.size.y / float(rows)
		_pencil_rect(Rect2(r.position.x + cw * e.x + 4, r.position.y + ch * e.y + 4, cw - 8, ch - 8),
				1.0, Color(0.86, 0.60, 0.34, 0.22))


# ============================================================================
#  场景 4 · 裂缝（成绩条 / 电话 / 考试失利）
# ============================================================================
func _roofline() -> void:
	# 一扇朝天的窗，外面是灰白的天
	var win := Rect2(180, 40, 860, 300)
	_sky_bands(win, Color(0.30, 0.33, 0.38), Color(0.16, 0.17, 0.20), 20)
	# 云（几条横向的软线）
	for i in 9:
		var y := win.position.y + 30.0 + float(i) * 30.0
		var a: float = 0.05 + 0.04 * abs(sin(float(i) * 1.7))
		draw_rect(Rect2(win.position.x + 40, y, win.size.x - 80, 12), Color(0.85, 0.88, 0.94, a))
	# 雨丝（缓慢下落）
	for i in 90:
		var sx := win.position.x + fmod(float(i) * 137.0, win.size.x)
		var sy := win.position.y + fmod(float(i) * 61.0 + _t * 190.0, win.size.y)
		draw_line(Vector2(sx, sy), Vector2(sx - 5, sy + 22), Color(0.80, 0.85, 0.95, 0.16), 1.0, true)
	_pencil_rect(win, 3.0, Color(0.88, 0.86, 0.82, 0.22))
	# 窗棂
	_pencil(Vector2(610, win.position.y), Vector2(610, win.end.y), 3.0, Color(0.10, 0.10, 0.12, 0.75))
	_pencil(Vector2(win.position.x, 190), Vector2(win.end.x, 190), 3.0, Color(0.10, 0.10, 0.12, 0.75))

	# 窗台
	_fill_rect(Rect2(150, 340, 920, 22), Color(0.155, 0.155, 0.175))
	_pencil_rect(Rect2(150, 340, 920, 22), 1.6, C_LINE_SOFT)

	# 前景：一张被揉过又展平的纸（成绩条）
	var paper := Rect2(230, 430, 250, 130)
	_fill_rect(paper, Color(0.82, 0.81, 0.78, 0.10))
	_pencil_rect(paper, 1.6, Color(0.90, 0.88, 0.82, 0.30))
	# 折痕
	for i in 5:
		var x := paper.position.x + 30.0 + float(i) * 44.0
		_pencil(Vector2(x, paper.position.y + 6), Vector2(x + 12, paper.end.y - 6), 1.0, Color(0.95, 0.93, 0.88, 0.09))
	# 上面的数字（假字迹）
	_pencil(Vector2(paper.position.x + 26, paper.position.y + 40),
			Vector2(paper.position.x + 96, paper.position.y + 40), 2.4, Color(0.90, 0.55, 0.45, 0.30))
	_pencil(Vector2(paper.position.x + 26, paper.position.y + 76),
			Vector2(paper.position.x + 150, paper.position.y + 76), 1.6, Color(0.92, 0.90, 0.84, 0.16))

	# 远景：窗边一个背对的人影（很小，只是「她在打电话」的信号）
	_person_silhouette(Vector2(860, 350), 150.0, 0.55)

	# 下方暗部
	draw_colored_polygon(PackedVector2Array([
		Vector2(0, 720), Vector2(1280, 720), Vector2(1280, 600), Vector2(0, 640)
	]), Color(0.055, 0.058, 0.070, 0.85))


# ============================================================================
#  第二幕 · 6F 寝室走廊（十月底的余晖）
# ============================================================================
func _dorm_corridor() -> void:
	# 天花板 / 墙 / 地板三段
	_fill_rect(Rect2(0, 0, 1280, 150), Color(0.095, 0.082, 0.084))
	_fill_rect(Rect2(0, 150, 1280, 330), Color(0.185, 0.140, 0.112))
	_fill_rect(Rect2(0, 480, 1280, 240), Color(0.135, 0.108, 0.092))

	# 走廊尽头的窗户（余晖的来处）
	var endwin := Rect2(1040, 200, 200, 250)
	_fill_rect(endwin, Color(0.20, 0.16, 0.14))
	_sky_bands(endwin, Color(0.95, 0.72, 0.46), Color(0.55, 0.34, 0.26), 22)
	_pencil_rect(endwin, 3.0, Color(0.95, 0.88, 0.76, 0.28))
	_pencil(Vector2(1140, endwin.position.y), Vector2(1140, endwin.end.y), 3.0, Color(0.12, 0.09, 0.08, 0.7))
	_glow(Vector2(1140, 320), 900.0, Color(1.0, 0.70, 0.40, 0.16))

	# 长条光带洒在地板上（余晖）
	draw_colored_polygon(PackedVector2Array([
		Vector2(980, 480), Vector2(1280, 480), Vector2(1280, 720), Vector2(620, 720)
	]), Color(1.0, 0.72, 0.42, 0.09))
	# 地板上的窗格投影
	for i in 4:
		var x := 700.0 + float(i) * 150.0
		var sway := (x - 980.0) * 0.55
		_pencil(Vector2(x, 480), Vector2(x - sway, 720), 2.0, Color(0.12, 0.09, 0.08, 0.32))
	for j in 3:
		var y := 520.0 + float(j) * 66.0
		_pencil(Vector2(640 + float(j) * 60, y), Vector2(1280, y), 2.0, Color(0.12, 0.09, 0.08, 0.28))

	# 一侧的寝室门（一排，透视）
	var dx := 60.0
	var ds := 1.0
	for i in 4:
		var w := 210.0 * ds
		var h := 400.0 * ds
		var y := 200.0 + (1.0 - ds) * 200.0
		var r := Rect2(dx, y, w, h)
		_fill_rect(r, Color(0.115, 0.090, 0.078))
		_pencil_rect(r, 1.8, Color(0.92, 0.84, 0.72, 0.18))
		# 门牌
		_pencil_rect(Rect2(r.position.x + w * 0.5 - 22, y + 26.0 * ds, 44.0 * ds, 22.0 * ds), 1.2,
				Color(0.92, 0.84, 0.72, 0.30))
		# 门把手
		draw_circle(Vector2(r.position.x + w - 24.0 * ds, y + h * 0.52), 4.0 * ds, Color(0.90, 0.82, 0.66, 0.45))
		dx += w + 26.0
		ds *= 0.94

	# 晾衣绳 + 衣架（会轻轻碰响）
	_pencil(Vector2(0, 176), Vector2(1040, 150), 2.0, Color(0.95, 0.88, 0.76, 0.18))
	for i in 7:
		var t := 0.08 + float(i) * 0.12
		var p := Vector2(1040.0 * t, lerpf(176.0, 150.0, t))
		var swing := sin(_t * 1.6 + float(i) * 0.9) * 4.0
		_pencil(p, p + Vector2(0, 34), 1.6, Color(0.90, 0.84, 0.72, 0.28))
		draw_colored_polygon(PackedVector2Array([
			p + Vector2(-13 + swing, 34), p + Vector2(13 + swing, 34), p + Vector2(0, 46)
		]), Color(0.85, 0.78, 0.66, 0.22))

	# 顶部一排走廊灯
	for i in 5:
		var x := 150.0 + float(i) * 240.0
		_glow(Vector2(x, 60), 120.0, Color(1.0, 0.86, 0.62, 0.10))
		_fill_rect(Rect2(x - 34, 40, 68, 12), Color(1.0, 0.90, 0.70, 0.30))

	# 浮尘在光里
	_dust(Vector2(880, 400), 30)


# ============================================================================
#  第二幕 · 刘忆的寝室（关键：阳台门的状态要看得清）
# ============================================================================
func _dorm_room() -> void:
	# 房间：后墙 / 地板
	_fill_rect(Rect2(0, 0, 1280, 500), Color(0.115, 0.112, 0.124))
	_fill_rect(Rect2(0, 500, 1280, 220), Color(0.088, 0.086, 0.096))
	_pencil(Vector2(0, 500), Vector2(1280, 500), 1.6, C_LINE_SOFT)

	# ---- 阳台门（后景，居中偏右。剧情伏笔，必须清晰）
	var bd := Rect2(720, 150, 260, 350)
	# 门框
	_fill_rect(Rect2(bd.position.x - 6, bd.position.y - 6, bd.size.x + 12, bd.size.y + 12), Color(0.075, 0.073, 0.082))
	# 门内：夜色与风
	_sky_bands(bd, Color(0.20, 0.22, 0.27), Color(0.10, 0.11, 0.14), 18)
	# 外面是阳台栏杆
	for i in 6:
		var x := bd.position.x + 16.0 + float(i) * (bd.size.x - 32.0) / 5.0
		_pencil(Vector2(x, bd.position.y + bd.size.y * 0.55), Vector2(x, bd.end.y - 10), 2.0,
				Color(0.85, 0.86, 0.90, 0.20))
	_pencil(Vector2(bd.position.x + 8, bd.position.y + bd.size.y * 0.55),
			Vector2(bd.end.x - 8, bd.position.y + bd.size.y * 0.55), 2.2, Color(0.85, 0.86, 0.90, 0.24))

	# 门扇：开着 → 留一道缝；关着 → 整扇合上
	if balcony_open:
		# 半开的门扇：往左侧转出去一点，留出右边的缝
		_fill_rect(Rect2(bd.position.x - 34, bd.position.y - 2, bd.size.x * 0.5 + 34, bd.size.y + 4),
				Color(0.135, 0.132, 0.146))
		_pencil_rect(Rect2(bd.position.x - 34, bd.position.y - 2, bd.size.x * 0.5 + 34, bd.size.y + 4), 2.0,
				Color(0.90, 0.88, 0.82, 0.28))
		# 玻璃
		_fill_rect(Rect2(bd.position.x - 24, bd.position.y + 16, bd.size.x * 0.5 + 14, bd.size.y - 40),
				Color(0.30, 0.34, 0.40, 0.30))
		# 门缝（真正要看清的东西）
		var gap := Rect2(bd.position.x + bd.size.x * 0.5 - 4, bd.position.y + 6, 34, bd.size.y - 12)
		_sky_bands(gap, Color(0.26, 0.28, 0.34), Color(0.13, 0.14, 0.18), 12)
		_pencil_rect(gap, 1.6, Color(0.96, 0.92, 0.84, 0.40))
		# 缝里透出的风
		_light_shaft(PackedVector2Array([
			Vector2(gap.end.x, gap.position.y), Vector2(gap.end.x + 190, gap.position.y + 40),
			Vector2(gap.end.x + 190, gap.end.y + 90), Vector2(gap.end.x, gap.end.y)
		]), Color(0.80, 0.86, 1.0, 0.035))
	else:
		_fill_rect(Rect2(bd.position.x, bd.position.y, bd.size.x * 0.5, bd.size.y), Color(0.135, 0.132, 0.146))
		_pencil_rect(Rect2(bd.position.x, bd.position.y, bd.size.x * 0.5, bd.size.y), 2.0,
				Color(0.90, 0.88, 0.82, 0.28))
	# 门框外描
	_pencil_rect(bd, 2.6, Color(0.92, 0.90, 0.84, 0.30))

	# 窗帘（被风鼓起来）
	var swell := 14.0 + sin(_t * 0.7) * 10.0
	draw_colored_polygon(PackedVector2Array([
		Vector2(bd.position.x - 70, 120), Vector2(bd.position.x + 10, 130),
		Vector2(bd.position.x + 10 + swell, 480), Vector2(bd.position.x - 80, 500)
	]), Color(0.20, 0.19, 0.22, 0.75))
	_pencil(Vector2(bd.position.x - 70, 120), Vector2(bd.position.x - 80, 500), 1.6, Color(0.90, 0.88, 0.82, 0.16))
	# 窗帘褶皱
	for i in 4:
		var t := 0.16 + float(i) * 0.2
		_pencil(Vector2(lerpf(bd.position.x - 70, bd.position.x + 10, t), lerpf(120.0, 130.0, t)),
				Vector2(lerpf(bd.position.x - 80, bd.position.x + 10 + swell, t), lerpf(500.0, 480.0, t)),
				1.2, Color(0.95, 0.93, 0.88, 0.10))

	# 书桌（左侧）+ 台灯 + 摊开的练习册
	var desk := Rect2(60, 470, 470, 26)
	_fill_rect(desk, Color(0.165, 0.158, 0.170))
	_pencil_rect(desk, 1.6, C_LINE_SOFT)
	_pencil(Vector2(90, 496), Vector2(80, 640), 3.0, C_LINE_SOFT)
	_pencil(Vector2(500, 496), Vector2(510, 640), 3.0, C_LINE_SOFT)
	# 练习册
	_fill_rect(Rect2(120, 452, 180, 20), Color(0.80, 0.79, 0.76, 0.10))
	_pencil_rect(Rect2(120, 452, 180, 20), 1.2, Color(0.90, 0.88, 0.82, 0.24))
	# 台灯（没开）
	_pencil(Vector2(430, 470), Vector2(430, 400), 2.2, C_LINE_SOFT)
	draw_colored_polygon(PackedVector2Array([
		Vector2(400, 400), Vector2(462, 400), Vector2(448, 372), Vector2(414, 372)
	]), Color(0.18, 0.17, 0.19))
	_pencil_rect(Rect2(400, 372, 62, 28), 1.6, C_LINE_SOFT)

	# 床（右下，画面外沿）：她拍床沿让李星坐
	_fill_rect(Rect2(1030, 480, 250, 240), Color(0.145, 0.140, 0.152))
	_pencil_rect(Rect2(1030, 480, 250, 240), 1.8, C_LINE_SOFT)
	for i in 3:
		var y := 520.0 + float(i) * 40.0
		_pencil(Vector2(1040, y), Vector2(1270, y), 1.0, Color(0.90, 0.88, 0.82, 0.07))

	# 窗外的光落在房间里（冷月光，和走廊的暖余晖形成对比）
	_glow(Vector2(850, 400), 520.0, Color(0.70, 0.78, 1.0, 0.06))
	_dust(Vector2(700, 380), 16)
