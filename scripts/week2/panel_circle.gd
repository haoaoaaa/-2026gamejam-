extends "res://scripts/week1/panel_base.gd"
## ============================================================================
##  《寻星》二周目 —— 第 6 关的「具体图示」：地上的水
## ============================================================================
##  文档原文：「打翻马克杯，水在地上形成圆形 → 发现地板不是斜的」。
##  剧本（data/week2_dialogue.json 的 s5_cup）里那张卡之后接
##  ["panel", "circle"]，这里把两种可能并排画出来：
##      左边是**看到的**：水摊成一个圆（说明地面是平的）；
##      右边是**如果是斜的**：水会顺着坡流成一条。
##
##  【本文件的坑，改之前先看】
##   1. 画图要画在**子 Control** 的 draw 信号里，不要覆盖面板自己的 _draw
##      —— 基类的压暗层是兄弟节点，会盖住面板根节点的绘制。
##   2. 子类不要声明 _body / _ctx / _done / _closing（基类已有）。
##   3. draw_set_transform 改的是后续绘制的坐标系，用完必须还原，
##      否则后面画的所有东西都会跟着被拉伸/平移。
##   4. 不要写 class_name：--script 无头模式下会报 Identifier not declared。
## ============================================================================

const FIG_W := 812.0
const FIG_H := 236.0

const C_FLOOR := Color(0.18, 0.19, 0.23)         # 俯视角的地面
const C_FLOOR_EDGE := Color(0.40, 0.42, 0.48)
const C_WATER := Color(0.38, 0.62, 0.92, 0.80)
const C_WATER_EDGE := Color(0.52, 0.74, 1.0, 0.95)
const C_MUG := Color(0.62, 0.60, 0.54)
const C_DIM := Color(0.54, 0.55, 0.61)
const C_GOOD := Color(0.72, 0.82, 0.96)

var _figure: Control = null
var _ok_btn: Button = null


func panel_title() -> String:
	return "地上的水"


func panel_hint() -> String:
	return "水往低处走——可它摊成了什么形状？"


func build_body(body: VBoxContainer) -> void:
	_figure = Control.new()
	_figure.name = "CircleFigure"
	_figure.custom_minimum_size = Vector2(FIG_W, FIG_H)
	_figure.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_figure.draw.connect(_draw_figure)
	body.add_child(_figure)

	body.add_child(make_text(
		"水往低处走，本该流成一条线。可它摊成了一个圆——它就在原地。",
		PreludeUI.FS_TEXT, PreludeUI.C_INK))

	_ok_btn = make_button("……一个圆。", true)
	_ok_btn.pressed.connect(_on_ok)
	body.add_child(_ok_btn)


func _on_ok() -> void:
	close_panel({"ok": true, "figure": "circle"})


# ---------------------------------------------------------------- 画两张俯视图
func _draw_figure() -> void:
	var w := _figure.size.x
	var panel_w := w * 0.44
	var floor_h := 132.0
	var top := 34.0

	# —— 左：实际看见的（圆）
	_draw_floor(Rect2(6.0, top, panel_w, floor_h))
	var lc := Vector2(6.0 + panel_w * 0.5, top + floor_h * 0.5)
	_figure.draw_circle(lc, 40.0, C_WATER)
	_figure.draw_arc(lc, 40.0, 0.0, TAU, 48, C_WATER_EDGE, 2.0)
	_draw_mug(Vector2(lc.x - 62.0, lc.y - 34.0))
	_text("看见的：一个圆", Vector2(6.0 + 6.0, top + floor_h + 22.0), 16, C_GOOD)

	# —— 右：如果地面是斜的
	var rx := w - panel_w - 6.0
	_draw_floor(Rect2(rx, top, panel_w, floor_h))
	var rc := Vector2(rx + panel_w * 0.5, top + floor_h * 0.5)
	# 【坑】draw_set_transform 会改坐标系，画完必须还原
	_figure.draw_set_transform(rc, 0.0, Vector2(3.4, 0.85))
	_figure.draw_circle(Vector2.ZERO, 34.0, C_WATER)
	_figure.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_figure.draw_arc(rc + Vector2(107.0, 0.0), 6.0, -1.4, 1.4, 10, C_DIM, 2.0)
	_draw_mug(Vector2(rx + 26.0, rc.y - 62.0))
	_text("如果地是斜的：会流成一条", Vector2(rx + 6.0, top + floor_h + 22.0), 16, C_DIM)

	# 中间的问号
	_text("？", Vector2(w * 0.5 - 7.0, top + floor_h * 0.5 + 8.0), 26, C_DIM)


func _draw_floor(r: Rect2) -> void:
	_figure.draw_rect(r, C_FLOOR, true)
	_figure.draw_rect(r, C_FLOOR_EDGE, false, 1.0)


## 倒在地上的杯子（俯视：一个圆 + 一小段把手）
func _draw_mug(c: Vector2) -> void:
	_figure.draw_circle(c, 9.0, C_MUG)
	_figure.draw_arc(c, 9.0, 0.0, TAU, 16, C_FLOOR_EDGE, 1.0)
	_figure.draw_line(c + Vector2(9.0, 0.0), c + Vector2(19.0, 0.0), C_MUG, 3.0)


func _text(s: String, pos: Vector2, size: int, col: Color) -> void:
	_figure.draw_string(ThemeDB.fallback_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
