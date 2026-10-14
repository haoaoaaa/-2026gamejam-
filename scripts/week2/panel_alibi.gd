extends "res://scripts/week1/panel_base.gd"
## ============================================================================
##  《寻星》二周目 · 第 5 关「不在场证明与动机」——可能有谁
## ============================================================================
##  玩法：五个人各一行，左边是"当时动向"（给玩家推理用的证据，直接照抄剧本），
##  右边两列是留给玩家判定的「有时间」「有动机」小方块（默认都是「无」，
##  点一下在 有/无 之间切换）。都填好后按底部「总结」：
##      · 全对 → 显示结论「有时间的没动机，有动机的没时间——谁都没法做到。」
##               并冒出「……那就不是他们。」→ close_panel({"ok": true})
##      · 有错 → 把错的格子标红 + 提示「再看一遍他们的动向。」，面板不关
##  —— 这一关的落点是玩家自己推出"谁都没法做到"，所以错就不放行。
##
##  【坑·1】extends 用字符串路径，且**不要写 class_name**：
##          --script 无头模式下 class_name 会报 Identifier ... not declared。
##  【坑·2】子类成员不能和基类重名（基类已有 _body / _ctx / _done / _closing，
##          见 panel_base.gd:36-39），否则解析期就 already exists in parent class。
##  【坑·3】不要覆盖 _ready() / _build_chrome()：铺满、压暗、900×540 面板框、
##          标题、底部提示都由基类统一搭好（panel_base.gd:90-155）。
##  【坑·4】PreludeUI.apply_button_skin(b, accent) 形参是 Button，且它会把
##          font_size 设成 FS_TEXT(19)；表格里的字要小，所以必须在
##          apply_button_skin 之后**再** add_theme_font_size_override(FS_TIP)。
##          （别把 LineEdit 之类塞进去。）
##  【坑·5】RichTextLabel 没有 set_v_scroll()（本关用普通 Label，不需要）。
##  【坑·6】ColorRect 的 mouse_filter 默认是 IGNORE——要做点击热区得设 STOP。
##          本关只用 Button，不涉及。
##  【坑·7】不要用 await 延时关闭（无头校验/连续输入下会飘），统一走
##          _exit_delay 倒计时 + _process 里 close_panel()，与 panel_reason.gd 一致。
## ============================================================================

## 五个人：name=谁（第一列）/ move=当时动向（第二列，直接展示）
##         time=到底有没有**作案时间**（判定用，不显示；动向里有人作证 = 不在场 = false）
##         motive=到底有没有动机（判定用）
## move 里括号里的半句是这一行"动机"的来由（写"没说过几句话"就是没有动机），
## 和剧本原表一致，是给玩家推理的证据。
##
## 【文案要求】玩家要判的两列是"有时间 / 有动机"，所以每一行的动向都得**读得出为什么**：
##   有时间的行 → 写清她凭什么真的抽得出时间、以及"有人作证"这句话为什么撑不住；
##   有动机的行 → 写清她因为刘忆受了什么实际损失（不只是"扣了个分"）。
##   一行最多占两行字（动向列 470px / FS_TIP 14 → 约 33 字一行）：表格的行高本来
##   就被右边那颗 40px 的方块撑着，两行不额外长高；写到三行就会把面板撑出 540。
##
## 判据必须满足剧本第 5 幕的结论「有时间的没动机，有动机的没时间——谁都没法做到」：
## 所以**不能有人同时是有时间 + 有动机**。C 与 E 的动向里都有明确的证人
## （同学作证 / 社长作证）→ 两人都是"没时间"；D、班主任的动向里没有动机 → "有时间、没动机"；
## 宿管阿姨那段时间一直在教工食堂、被师傅和班主任看见 → "没时间、有动机"。
const PEOPLE: Array[Dictionary] = [
	{
		"name": "同学 C",
		"move": "一整个下午都在教室自习，同桌和值日生都能证明她没离开过（她把刘忆当竞争对手：刘忆转来后，她再没进过前三）",
		"time": false,
		"motive": true,
	},
	{
		"name": "同学 D",
		"move": "在上活动课，操场上一百多人乱跑，老师没点名，中间有二十分钟没人留意她（她跟刘忆一直处得不错）",
		"time": true,
		"motive": false,
	},
	{
		"name": "同学 E",
		"move": "在推理社教室看小说，社长一整个下午都在旁边（她想自己造一个密室，刘忆总说她的构思不行）",
		"time": false,
		"motive": true,
	},
	{
		"name": "班主任",
		"move": "那天下午她没课，整段时间都空着：在教工食堂露了个面就回办公室，之后一个人待着，没人能替她作证。",
		"time": true,
		"motive": false,
	},
	{
		"name": "宿管阿姨",
		"move": "那天下午她一直在教工食堂打饭擦桌子，师傅和班主任都看见她没走开（前一天是她填的扣分单，两个人为这事吵过一架）",
		"time": false,
		"motive": true,
	},
]

const HINT_IDLE := "点两列小方块判断：他有没有时间，有没有动机。"
const HINT_WRONG := "再看一遍他们的动向。"
const CONCLUSION := "有时间的没动机，有动机的没时间——谁都没法做到。"
const CLOSE_DELAY := 0.45

## 每行两格：0 = 有时间，1 = 有动机
const COLS := 2

var _grid: GridContainer = null
var _feedback: Label = null
var _conclusion: Label = null
var _check_btn: Button = null
var _exit_btn: Button = null
var _toggle_btns: Array[Button] = []
var _toggle_state: Array[bool] = []
var _wrong: Dictionary = {}
var _bad_skin: StyleBoxFlat = null
var _solved := false
var _exit_delay := -1.0
var _exit_result: Dictionary = {}


# ---------------------------------------------------------------- 基类覆盖点
func panel_title() -> String:
	return "可能有谁"


func panel_hint() -> String:
	# 这里**不能**写结论（原稿写的是「有时间的没动机，有动机的没时间」，等于开面板就报答案）
	return "先看他们的动向：谁真的抽得出时间，谁又把刘忆当成了威胁"


func build_body(body: VBoxContainer) -> void:
	_bad_skin = StyleBoxFlat.new()
	_bad_skin.bg_color = Color(0.34, 0.11, 0.11, 0.96)
	_bad_skin.border_color = Color(0.88, 0.32, 0.30, 0.95)
	_bad_skin.set_border_width_all(2)
	_bad_skin.set_corner_radius_all(3)
	_bad_skin.content_margin_left = 8.0
	_bad_skin.content_margin_right = 8.0
	_bad_skin.content_margin_top = 6.0
	_bad_skin.content_margin_bottom = 6.0

	var intro := make_text("那天谁有可能动手？先把两列都填一遍。", PreludeUI.FS_TIP, PreludeUI.C_INK_DIM)
	body.add_child(intro)

	_grid = GridContainer.new()
	_grid.name = "AlibiGrid"
	_grid.columns = 1 + 1 + COLS
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 6)
	body.add_child(_grid)

	_build_header()

	for row in PEOPLE.size():
		_build_row(row)

	_feedback = make_text(HINT_IDLE, PreludeUI.FS_TIP, PreludeUI.C_INK_DIM)
	_feedback.name = "AlibiFeedback"
	_feedback.custom_minimum_size = Vector2(0, 22)
	body.add_child(_feedback)

	_conclusion = make_text(CONCLUSION, PreludeUI.FS_CARD, PreludeUI.C_NAME)
	_conclusion.name = "AlibiConclusion"
	_conclusion.visible = false
	body.add_child(_conclusion)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(spacer)

	var bottom := HBoxContainer.new()
	bottom.name = "AlibiBottom"
	bottom.alignment = BoxContainer.ALIGNMENT_END
	bottom.add_theme_constant_override("separation", 12)
	body.add_child(bottom)

	_check_btn = make_button("总结", true)
	_check_btn.pressed.connect(_on_check_pressed)
	bottom.add_child(_check_btn)

	_exit_btn = make_button("……那就不是他们。", true)
	_exit_btn.visible = false
	_exit_btn.pressed.connect(_on_exit_pressed)
	bottom.add_child(_exit_btn)

	set_process(true)


# ---------------------------------------------------------------- 搭表格
func _build_header() -> void:
	_grid.add_child(_header_cell("谁", 84.0))
	_grid.add_child(_header_cell("当时动向", 470.0))
	_grid.add_child(_header_cell("有时间", 96.0))
	_grid.add_child(_header_cell("有动机", 96.0))


func _header_cell(text: String, w: float) -> Label:
	var l := make_text(text, PreludeUI.FS_TIP, PreludeUI.C_NAME)
	l.custom_minimum_size = Vector2(w, 0)
	return l


func _build_row(row: int) -> void:
	var p: Dictionary = PEOPLE[row]

	var name_cell := make_text(str(p["name"]), PreludeUI.FS_TIP, PreludeUI.C_INK)
	name_cell.custom_minimum_size = Vector2(84.0, 0)
	_grid.add_child(name_cell)

	var move_cell := make_text(str(p["move"]), PreludeUI.FS_TIP, PreludeUI.C_INK_DIM)
	move_cell.custom_minimum_size = Vector2(470.0, 0)
	_grid.add_child(move_cell)

	for col in COLS:
		var i := row * COLS + col
		var b := Button.new()
		b.name = "AlibiToggle%d" % i
		b.custom_minimum_size = Vector2(96.0, 28.0)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_on_toggle_pressed.bind(i))
		_grid.add_child(b)
		_toggle_btns.append(b)
		_toggle_state.append(false)
		_paint_toggle(i)


## 有/无 两态 + 标红三态，全部在这里统一重画
func _paint_toggle(i: int) -> void:
	var b := _toggle_btns[i]
	var on: bool = _toggle_state[i]
	b.text = "有" if on else "无"
	if _wrong.has(i):
		PreludeUI.apply_button_skin(b, false)
		b.add_theme_stylebox_override("normal", _bad_skin)
		b.add_theme_stylebox_override("hover", _bad_skin)
		b.add_theme_color_override("font_color", Color(0.92, 0.50, 0.46))
	elif on:
		PreludeUI.apply_button_skin(b, true)
		b.add_theme_color_override("font_color", PreludeUI.C_NAME)
	else:
		PreludeUI.apply_button_skin(b, false)
		b.add_theme_color_override("font_color", PreludeUI.C_INK_DIM)
	# 【坑·4】apply_button_skin 会把字号改成 FS_TEXT，表格里要小字必须后设
	b.add_theme_font_size_override("font_size", PreludeUI.FS_TIP)


# ---------------------------------------------------------------- 交互
func _on_toggle_pressed(i: int) -> void:
	if _solved:
		return
	_toggle_state[i] = not _toggle_state[i]
	# 一动手指就把上次的标红全清掉，让玩家从头再看
	_wrong.clear()
	for k in _toggle_btns.size():
		_paint_toggle(k)
	_feedback.add_theme_color_override("font_color", PreludeUI.C_INK_DIM)
	_feedback.text = HINT_IDLE


func _on_check_pressed() -> void:
	if _solved:
		return
	_wrong.clear()
	# 双层循环而不是 i / COLS：GDScript 的整数除法会冒 INTEGER_DIVISION 警告
	for row in PEOPLE.size():
		var p: Dictionary = PEOPLE[row]
		for col in COLS:
			var i := row * COLS + col
			var want: bool = bool(p["time"]) if col == 0 else bool(p["motive"])
			if _toggle_state[i] != want:
				_wrong[i] = true

	if not _wrong.is_empty():
		for i in _toggle_btns.size():
			_paint_toggle(i)
		_feedback.add_theme_color_override("font_color", PreludeUI.C_ACCENT)
		_feedback.text = HINT_WRONG
		return

	_solved = true
	for b in _toggle_btns:
		b.disabled = true
	_check_btn.disabled = true
	_conclusion.visible = true
	_feedback.add_theme_color_override("font_color", PreludeUI.C_NAME)
	_feedback.text = "对。就是这么回事。"
	_exit_btn.visible = true


func _on_exit_pressed() -> void:
	if _exit_delay >= 0.0:
		return
	# 【坑·7】不用 await，交给 _process 倒计时关闭
	_exit_result = {"ok": true}
	_exit_delay = CLOSE_DELAY
	_exit_btn.disabled = true


func _process(delta: float) -> void:
	if _exit_delay < 0.0:
		return
	_exit_delay -= delta
	if _exit_delay <= 0.0:
		_exit_delay = -1.0
		close_panel(_exit_result)
