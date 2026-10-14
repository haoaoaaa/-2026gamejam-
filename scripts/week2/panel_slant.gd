extends "res://scripts/week1/panel_base.gd"
## ============================================================================
##  《寻星》二周目 —— 第 2 关的「具体图示」：寝室地面（剖面）
## ============================================================================
##  文档原文：「推理出地板从阳台斜向寝室门（出现具体图示）」。
##  剧本（data/week2_dialogue.json 的 s1_method）里这张卡之后接
##  ["panel", "slant"]，就把这张剖面图画出来：
##      阳台那一头高、寝室门这一头低；杯子倒了以后水顺着坡往门口走。
##
##  【本文件的坑，改之前先看】
##   1. 画图要画在**子 Control** 的 draw 信号里，不要覆盖面板自己的 _draw
##      —— 基类的压暗层是兄弟节点，会盖住面板根节点的绘制（panel_maze 同款）。
##   2. 子类不要声明 _body / _ctx / _done / _closing（基类已有）。
##   3. PreludeUI.apply_button_skin() 的形参是 Button，别把别的控件传进去。
##   4. 不要写 class_name：--script 无头模式下会报 Identifier not declared。
##   5. 面板正文只有约 812×393，图 + 一行字 + 一个按钮正好；再加东西会撑出 900×540。
##
##  本文件只依赖 panel_base.gd / PreludeUI 与 ThemeDB，不读 json、不切场景。
## ============================================================================

const FIG_W := 812.0
const FIG_H := 238.0

const C_SLAB := Color(0.20, 0.21, 0.25)          # 楼板
const C_EDGE := Color(0.46, 0.48, 0.54)          # 楼板边缘
const C_REF := Color(0.34, 0.36, 0.42, 0.85)     # 水平参考线（虚线）
const C_WATER := Color(0.38, 0.62, 0.92, 0.95)   # 那滩水
const C_INK := Color(0.80, 0.81, 0.85)
const C_DIM := Color(0.54, 0.55, 0.61)

var _figure: Control = null
var _ok_btn: Button = null


func panel_title() -> String:
	return "寝室地面（剖面）"


func panel_hint() -> String:
	return "阳台那一头高，门这一头低"


func build_body(body: VBoxContainer) -> void:
	_figure = Control.new()
	_figure.name = "SlantFigure"
	_figure.custom_minimum_size = Vector2(FIG_W, FIG_H)
	_figure.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_figure.draw.connect(_draw_figure)
	body.add_child(_figure)

	body.add_child(make_text(
		"阳台那一头高，门这一头低。水不会自己挑方向——水往低处走。",
		PreludeUI.FS_TEXT, PreludeUI.C_INK))

	_ok_btn = make_button("看明白了", true)
	_ok_btn.pressed.connect(_on_ok)
	body.add_child(_ok_btn)


func _on_ok() -> void:
	close_panel({"ok": true, "figure": "slant"})


# ---------------------------------------------------------------- 画剖面图
func _draw_figure() -> void:
	var w := _figure.size.x
	var left := 44.0
	var right := w - 66.0
	# 楼板：左高右低的一条斜板（这就是"地面是斜的"）
	var y_l := 96.0
	var y_r := 190.0
	var slab := 26.0
	_figure.draw_colored_polygon(PackedVector2Array([
		Vector2(left, y_l),
		Vector2(right, y_r),
		Vector2(right, y_r + slab),
		Vector2(left, y_l + slab),
	]), C_SLAB)
	_figure.draw_line(Vector2(left, y_l), Vector2(right, y_r), C_EDGE, 2.0)
	_figure.draw_line(Vector2(left, y_l + slab), Vector2(right, y_r + slab), C_EDGE, 1.0)

	# 水平参考线（虚线）：一眼看出右边低了多少
	_dashed(Vector2(left, y_l), Vector2(right, y_l), C_REF, 7.0, 6.0)
	# 右边的落差标注
	_figure.draw_line(Vector2(right + 22.0, y_l), Vector2(right + 22.0, y_r), C_DIM, 1.0)
	_figure.draw_line(Vector2(right + 16.0, y_l), Vector2(right + 28.0, y_l), C_DIM, 1.0)
	_figure.draw_line(Vector2(right + 16.0, y_r), Vector2(right + 28.0, y_r), C_DIM, 1.0)
	_text("低", Vector2(right + 30.0, (y_l + y_r) * 0.5 + 5.0), 15, C_DIM)
	_text("阳台 · 高", Vector2(left + 4.0, y_l - 12.0), 15, C_DIM)
	_text("寝室门 · 低", Vector2(right - 96.0, y_r + slab + 20.0), 15, C_DIM)

	# 阳台栏杆
	_figure.draw_line(Vector2(left - 26.0, y_l), Vector2(left - 26.0, y_l - 52.0), C_EDGE, 2.0)
	_figure.draw_line(Vector2(left - 34.0, y_l - 48.0), Vector2(left - 18.0, y_l - 48.0), C_EDGE, 2.0)
	_text("阳台", Vector2(left - 40.0, y_l - 62.0), 15, C_DIM)

	# 门口
	_figure.draw_rect(Rect2(right - 2.0, y_r - 46.0, 6.0, 46.0), C_EDGE, true)

	# 倒在坡上的杯子
	var mug_x := left + 300.0
	var mug_y := _y_on_slope(mug_x, left, right, y_l, y_r)
	_figure.draw_rect(Rect2(mug_x - 18.0, mug_y - 17.0, 30.0, 15.0), Color(0.62, 0.60, 0.54), true)
	_figure.draw_arc(Vector2(mug_x + 14.0, mug_y - 10.0), 8.0, -1.2, 1.2, 12, C_EDGE, 2.0)

	# 水顺着坡往下走（一串蓝色短划，越往右越稀）
	var x := mug_x + 40.0
	while x < right - 8.0:
		var y := _y_on_slope(x, left, right, y_l, y_r)
		_figure.draw_line(Vector2(x, y - 2.0), Vector2(x + 20.0, y - 2.0), C_WATER, 3.0)
		x += 34.0
	_text("水往低处走", Vector2(mug_x + 40.0, mug_y - 26.0), 15, C_WATER)


## 斜面上某点的 y（画水迹与杯子都靠它）
func _y_on_slope(x: float, left: float, right: float, y_l: float, y_r: float) -> float:
	var t := clampf((x - left) / maxf(right - left, 1.0), 0.0, 1.0)
	return lerpf(y_l, y_r, t)


func _dashed(from: Vector2, to: Vector2, col: Color, dash: float, gap: float) -> void:
	var total := from.distance_to(to)
	var dir := (to - from).normalized()
	var d := 0.0
	while d < total:
		var a := from + dir * d
		var b := from + dir * minf(d + dash, total)
		_figure.draw_line(a, b, col, 1.0)
		d += dash + gap


func _text(s: String, pos: Vector2, size: int, col: Color) -> void:
	_figure.draw_string(ThemeDB.fallback_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
