extends Control
## ============================================================================
##  《寻星》一周目 —— 小游戏面板基类
## ============================================================================
##  面板 = 在一周目对话里"弹出来给玩家解的一关"。它由 dialogue_runtime 以
##  ["panel", id] 行创建：
##
##      var p := Control.new()
##      p.set_script(load(Week1Panels.script_for(id)))
##      p.call("setup", {"id": id})      # 必须在 add_child 之前
##      add_child(p)                     # 面板自己铺满、自己搭 UI
##
##  子类只需要覆盖这三件事：
##      func panel_title() -> String        面板标题（左上）
##      func panel_hint()  -> String        底部提示（怎么玩）
##      func build_body(body: VBoxContainer) 往里面塞你的界面
##  以及在想"这一关过了"的时候调用：
##      close_panel({"ok": true, "code": "053714"})
##  result 字典会写进 PreludeState 的 week1_result_<id> 里，供后面的台词判断。
##
##  【不要】覆盖 _ready()/_build_chrome()：铺满、压暗、标题栏、底部提示都由基类
##  统一处理，这样所有关卡的观感一致。
##
##  需要键盘操作的面板（比如迷宫）覆盖：
##      func handle_input(event: InputEvent) -> void
##  运行时会把没被 GUI 吃掉的输入转进来（仅在面板打开、且本关需要时）。
## ============================================================================

## 面板完成 / 被关闭时发一次
signal finished(result: Dictionary)

const BASE_W := 900.0
const BASE_H := 540.0
const MARGIN := 26.0

var _ctx: Dictionary = {}
var _body: Control = null
var _done := false
var _closing := false


func setup(ctx: Dictionary) -> void:
	_ctx = ctx


## 面板 id（["panel", id] 里的那个 id）
func panel_id() -> String:
	return str(_ctx.get("id", ""))


# ---------------------------------------------------------------- 子类覆盖点
func panel_title() -> String:
	return ""


func panel_hint() -> String:
	return ""


func build_body(_body_box: VBoxContainer) -> void:
	pass


## 可选：键盘/鼠标输入（只在面板打开时被调用）
func handle_input(_event: InputEvent) -> void:
	pass


## 可选：面板是否要接住键盘输入（默认 false，纯按钮面板不用管）
func wants_input() -> bool:
	return false


# ---------------------------------------------------------------- 完成 / 关闭
func is_open() -> bool:
	return not _done


func close_panel(result: Dictionary = {}) -> void:
	if _done:
		return
	_done = true
	if not result.has("id"):
		result = result.duplicate()
		result["id"] = panel_id()
	finished.emit(result)


# ---------------------------------------------------------------- 通用外壳
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 面板打开时把鼠标吃掉：底下的对话框/热区不该再响应
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_chrome()


func _build_chrome() -> void:
	var dim := ColorRect.new()
	dim.name = "PanelDim"
	dim.color = Color(0.02, 0.02, 0.03, 0.86)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var frame := PanelContainer.new()
	frame.name = "PanelFrame"
	frame.add_theme_stylebox_override("panel", PreludeUI.panel_skin(PreludeUI.C_PANEL_HI, PreludeUI.C_LINE, 8))
	add_child(frame)
	frame.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	frame.custom_minimum_size = Vector2(BASE_W, BASE_H)
	frame.offset_left = -BASE_W * 0.5
	frame.offset_right = BASE_W * 0.5
	frame.offset_top = -BASE_H * 0.5
	frame.offset_bottom = BASE_H * 0.5

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", int(MARGIN))
	margin.add_theme_constant_override("margin_right", int(MARGIN))
	margin.add_theme_constant_override("margin_top", int(MARGIN - 8.0))
	margin.add_theme_constant_override("margin_bottom", int(MARGIN - 8.0))
	frame.add_child(margin)

	var col := VBoxContainer.new()
	col.name = "PanelColumn"
	col.add_theme_constant_override("separation", 10)
	margin.add_child(col)

	var t := panel_title()
	if t != "":
		var title := Label.new()
		title.name = "PanelTitle"
		title.text = t
		title.add_theme_font_size_override("font_size", PreludeUI.FS_NAME)
		title.add_theme_color_override("font_color", PreludeUI.C_NAME)
		col.add_child(title)
		col.add_child(PreludeUI.hline(BASE_W - MARGIN * 2.0 - 8.0))

	var body := VBoxContainer.new()
	body.name = "PanelBody"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	col.add_child(body)
	_body = body

	var h := panel_hint()
	if h != "":
		var hint := Label.new()
		hint.name = "PanelHint"
		hint.text = h
		hint.add_theme_font_size_override("font_size", PreludeUI.FS_TIP)
		hint.add_theme_color_override("font_color", PreludeUI.C_INK_DIM)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		col.add_child(hint)

	build_body(body)


# ---------------------------------------------------------------- 公用小工具
## 统一风格的按钮
func make_button(text: String, accent := false) -> Button:
	var b := Button.new()
	b.text = text
	PreludeUI.apply_button_skin(b, accent)
	return b


## 统一风格的一段说明文字
func make_text(text: String, size := PreludeUI.FS_TEXT, col := PreludeUI.C_INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func make_rich(text: String, size := PreludeUI.FS_TEXT) -> RichTextLabel:
	var rtl := RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.fit_content = true
	rtl.scroll_active = false
	rtl.text = text
	rtl.add_theme_font_size_override("normal_font_size", size)
	rtl.add_theme_color_override("default_color", PreludeUI.C_INK)
	return rtl
