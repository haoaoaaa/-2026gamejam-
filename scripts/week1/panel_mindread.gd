extends "res://scripts/week1/panel_base.gd"
## ============================================================================
##  《寻星》一周目 · 回忆段（第 5、6 关之间）—— 1089 读心术
## ============================================================================
##  刘忆让李星自己想一个三位数，然后一屏一屏往下走，四屏一关：
##
##    ① Step1Box   想一个三位数 —— 不能太特殊（百位与个位之差的绝对值 ≥ 2）
##    ② Step2Box   倒过来，用大的减小的 —— 差必是三位数，且是 99 的倍数
##                 （198 / 297 / … / 891，十位永远落在 9 上）
##    ③ Step3Box   报出差里个位或者百位上那个数 —— 哪一位都不影响（《附录2》）
##    ④ RevealBox  揭晓：小的那一位是「过去」，9 是「现在」，9 − 过去 是「未来」，
##                 收在 198 ＋ 891 ＝ 1089 的算式卡片上
##
##  过关：close_panel({"ok": true, "num": n, "rev": rev, "diff": diff,
##                     "past": past, "future": future})
##
##  【实现】四屏在同一个 build_body 里一次建好，靠 visible 切换，不销毁节点。
##  【手感】每屏的 LineEdit 出现时都把光标放进去（不然玩家直接敲键盘是"没反应"的，
##  会被当成 bug）；回车（text_submitted）与按钮都能提交；任何输入都不许卡死
##  —— ②屏连错 3 次就干脆把答案写出来。
##
##  本文件只依赖 panel_base.gd 与 PreludeUI，不读 json、不切场景。
## ============================================================================

## 合法的差恒为 99 的倍数，十位因此永远是 9：玩家报 9 就是报了「十位」。
const TENS_DIGIT := 9
## 第 ② 屏连错几次就把答案写出来（写出来之后照样要他自己填对才过，不会卡死）
const REVEAL_AT := 3
## 塔罗牌第九张 —— 隐士那一段，一字不改照抄《附录2》
const TAROT_TEXT := "隐士提着灯，一个人走在雪地里。他不是没有人同行，是他先走开了。……你现在大概也觉得，身边有很多人，但没有一个真的知道你。"
## 第 ① 屏输入框下面那行小字
const STEP1_TIP := "想好了，就把它填进框里。"


# ================================================================ 数学
# 探针会直接调这三个静态函数，所以它们不碰任何节点、不依赖 _ready。

## n 必须是 100..999 且「百位与个位之差的绝对值 ≥ 2」；否则 ok=false。
## 成立时：rev = 倒过来的数；diff = abs(n - rev)（必为三位数）；
##        past = diff 的百位与个位里较小的那个；future = 9 - past。
@warning_ignore("integer_division")
static func solve_1089(n: int) -> Dictionary:
	var out := {
		"ok": false, "num": n, "rev": 0, "diff": 0, "past": 0, "future": 0,
	}
	if n < 100 or n > 999:
		return out
	var hi := n / 100          # 百位
	var lo := n % 10           # 个位
	# 百位和个位挨得太近（含相等）时，n - rev 只剩两位数，1089 那一步就不成立了
	if absi(hi - lo) < 2:
		return out
	var rev := reverse3(n)
	var diff := absi(n - rev)
	var past := mini(diff / 100, diff % 10)
	return {
		"ok": true, "num": n, "rev": rev, "diff": diff,
		"past": past, "future": 9 - past,
	}


## 123 -> 321
@warning_ignore("integer_division")
static func reverse3(v: int) -> int:
	var hi := v / 100
	var mid := (v / 10) % 10
	var lo := v % 10
	return lo * 100 + mid * 10 + hi


## diff + reverse3(diff)，对上面所有合法 diff 恒为 1089
static func sum_1089(diff: int) -> int:
	return diff + reverse3(diff)


# ================================================================ 状态

var _screens: Array[Control] = []       # Step1Box / Step2Box / Step3Box / RevealBox
var _screen_index := -1
var _state: Dictionary = {}             # solve_1089 的结果
var _wrong_diff := 0                    # 第 ② 屏连错次数
var _done_locked := false               # 已过关，屏蔽重复提交

var _number_input: LineEdit = null
var _number_confirm: Button = null
var _step1_feedback: Label = null

var _numbers_line: Label = null         # 「你的数：123　　倒过来：321」
var _diff_input: LineEdit = null
var _diff_confirm: Button = null
var _step2_feedback: Label = null

var _digit_input: LineEdit = null
var _digit_confirm: Button = null
var _step3_feedback: Label = null

var _reveal_past: Label = null
var _reveal_now: Label = null
var _reveal_future: Label = null
var _reveal_comfort: Label = null
var _formula_text: Label = null
var _finish_btn: Button = null


# ================================================================ 覆盖点
func panel_title() -> String:
	return "读心术 · 1089"


func panel_hint() -> String:
	return "想一个三位数 → 倒过来相减 → 报一个个位或百位"


func build_body(body: VBoxContainer) -> void:
	_screens.append(_build_step1())
	_screens.append(_build_step2())
	_screens.append(_build_step3())
	_screens.append(_build_reveal())
	for s in _screens:
		s.visible = false
		body.add_child(s)

	_show_screen(0)


# ================================================================ ① 想一个数
func _build_step1() -> Control:
	var box := _make_screen("Step1Box")

	box.add_child(make_text("刘忆说：你先在脑子里想一个三位数。别太特殊——123、456 这种太整了，随机一点。",
			PreludeUI.FS_TEXT, PreludeUI.C_INK))
	box.add_child(make_text(STEP1_TIP, PreludeUI.FS_TIP, PreludeUI.C_INK_DIM))

	var row := HBoxContainer.new()
	row.name = "Step1Row"
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)

	_number_input = _make_input("NumberInput", "想好的三位数", 3)
	_number_input.text_submitted.connect(_on_number_submitted)
	row.add_child(_number_input)

	_number_confirm = make_button("就它了", true)
	_number_confirm.name = "NumberConfirm"
	_number_confirm.pressed.connect(func() -> void: _on_number_submitted(_number_input.text))
	row.add_child(_number_confirm)

	_step1_feedback = _make_feedback("Step1Feedback")
	box.add_child(_step1_feedback)
	return box


func _on_number_submitted(text: String) -> void:
	if _done_locked or _screen_index != 0:
		return
	var raw := text.strip_edges()
	if raw == "" or not raw.is_valid_int():
		# 【坑】原来是静默 return：没点输入框就直接按「就它了」时画面上毫无反应，
		# 玩家会以为"卡住了"。现在给一句话，并把光标放回框里。
		_set_step1("先在上面那个框里填一个三位数。", false)
		return
	var solved := solve_1089(int(raw))
	if not bool(solved["ok"]):
		_set_step1("这个数太特殊了（倒过来减，只剩两位数）。换一个随机点的。", true)
		return
	_state = solved
	_number_input.editable = false
	_number_confirm.disabled = true
	_set_step1("", false)
	_show_screen(1)


func _set_step1(text: String, accent: bool) -> void:
	_set_feedback_line(_step1_feedback, text, accent)
	if _screen_index == 0:
		_focus(_number_input)


# ================================================================ ② 倒过来相减
func _build_step2() -> Control:
	var box := _make_screen("Step2Box")

	box.add_child(make_text("刘忆说：把这个数倒过来，再用大的减小的。算出来是多少？",
			PreludeUI.FS_TEXT, PreludeUI.C_INK))
	_numbers_line = make_text("", PreludeUI.FS_TEXT, PreludeUI.C_NAME)
	_numbers_line.name = "Step2Numbers"
	box.add_child(_numbers_line)

	var row := HBoxContainer.new()
	row.name = "Step2Row"
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)

	_diff_input = _make_input("DiffInput", "大数减小数", 3)
	_diff_input.text_submitted.connect(_on_diff_submitted)
	row.add_child(_diff_input)

	_diff_confirm = make_button("算好了", true)
	_diff_confirm.name = "DiffConfirm"
	_diff_confirm.pressed.connect(func() -> void: _on_diff_submitted(_diff_input.text))
	row.add_child(_diff_confirm)

	_step2_feedback = _make_feedback("Step2Feedback")
	box.add_child(_step2_feedback)
	return box


func _on_diff_submitted(text: String) -> void:
	if _done_locked or _screen_index != 1 or _state.is_empty():
		return
	var raw := text.strip_edges()
	if raw == "" or not raw.is_valid_int():
		_set_step2("先把算出来的数填进框里。", false)
		return
	if int(raw) == int(_state["diff"]):
		_diff_input.editable = false
		_diff_confirm.disabled = true
		_set_step2("", false)
		_show_screen(2)
		return
	_wrong_diff += 1
	if _wrong_diff >= REVEAL_AT:
		# 连错 3 次：把算式连同答案一起写出来。写出来之后照样要他自己把它填进去才过，
		# 但答案已经在眼前了 —— 这条路上没有卡死的可能。
		var n := int(_state["num"])
		var rev := int(_state["rev"])
		_set_step2("%d − %d = %d。" % [maxi(n, rev), mini(n, rev), int(_state["diff"])], true)
	else:
		_set_step2("再算一次。", true)


func _set_step2(text: String, accent: bool) -> void:
	_set_feedback_line(_step2_feedback, text, accent)
	if _screen_index == 1:
		_focus(_diff_input)


## 第 ② 屏顶上那行动态数字：「你的数：123　　倒过来：321」
func _refresh_step2_numbers() -> void:
	if _numbers_line == null or _state.is_empty():
		return
	_numbers_line.text = "你的数：%d　　倒过来：%d" % [int(_state["num"]), int(_state["rev"])]


# ================================================================ ③ 报一个数
func _build_step3() -> Control:
	var box := _make_screen("Step3Box")

	box.add_child(make_text("刘忆说：这个三位数的个位、十位、百位，分别是你的过去、现在和未来。",
			PreludeUI.FS_TEXT, PreludeUI.C_INK))
	box.add_child(make_text("刘忆说：我需要一个数字当依据——把你个位或者百位上的那个数告诉我。",
			PreludeUI.FS_TEXT, PreludeUI.C_INK))

	var row := HBoxContainer.new()
	row.name = "Step3Row"
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)

	_digit_input = _make_input("DigitInput", "个位或百位", 1)
	_digit_input.text_submitted.connect(_on_digit_submitted)
	row.add_child(_digit_input)

	_digit_confirm = make_button("告诉你", true)
	_digit_confirm.name = "DigitConfirm"
	_digit_confirm.pressed.connect(func() -> void: _on_digit_submitted(_digit_input.text))
	row.add_child(_digit_confirm)

	_step3_feedback = _make_feedback("Step3Feedback")
	box.add_child(_step3_feedback)
	return box


## 个位或百位都算对 —— 按《附录2》，哪一位都不影响，最小的那一位对应「过去」。
## 报十位（永远是 9）时把那句话还给玩家。
func _on_digit_submitted(text: String) -> void:
	if _done_locked or _screen_index != 2 or _state.is_empty():
		return
	var raw := text.strip_edges()
	if raw == "" or not raw.is_valid_int():
		_set_step3("先在上面那个框里填一位数 —— 个位，或者百位。", false)
		return
	var d := int(raw)
	var diff := int(_state["diff"])
	if d == diff / 100 or d == diff % 10:
		_digit_input.editable = false
		_digit_confirm.disabled = true
		_set_step3("", false)
		_enter_reveal()
		return
	if d == TENS_DIGIT:
		_set_step3("那是十位。我要的是个位，或者百位。", true)
	else:
		_set_step3("这个数不在你的个位或百位上。再看看那几个数字。", true)


func _set_step3(text: String, accent: bool) -> void:
	_set_feedback_line(_step3_feedback, text, accent)
	if _screen_index == 2:
		_focus(_digit_input)


# ================================================================ ④ 揭晓
func _build_reveal() -> Control:
	var box := _make_screen("RevealBox")

	# 揭晓的三行字比别处稍大一号
	_reveal_past = make_text("", PreludeUI.FS_TEXT + 2, PreludeUI.C_INK)
	_reveal_past.name = "RevealPast"
	box.add_child(_reveal_past)

	_reveal_now = make_text("", PreludeUI.FS_TEXT + 2, PreludeUI.C_INK)
	_reveal_now.name = "RevealNow"
	box.add_child(_reveal_now)

	_reveal_future = make_text("", PreludeUI.FS_TEXT + 2, PreludeUI.C_NAME)
	_reveal_future.name = "RevealFuture"
	box.add_child(_reveal_future)

	box.add_child(make_text("至于你的现在——塔罗牌里的第九张，是隐士。",
			PreludeUI.FS_TEXT, PreludeUI.C_NAME))
	box.add_child(make_text(TAROT_TEXT, PreludeUI.FS_TEXT, PreludeUI.C_INK_DIM))

	_reveal_comfort = make_text("", PreludeUI.FS_TEXT, PreludeUI.C_INK)
	_reveal_comfort.name = "RevealComfort"
	box.add_child(_reveal_comfort)

	# 算式卡片：198 ＋ 891 ＝ 1089
	var card := PanelContainer.new()
	card.name = "FormulaCard"
	card.add_theme_stylebox_override("panel",
			PreludeUI.panel_skin(PreludeUI.C_CARD_BG, Color(0.85, 0.80, 0.70, 0.22), 4))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(card)

	_formula_text = make_text("", PreludeUI.FS_NAME, PreludeUI.C_NAME)
	_formula_text.name = "FormulaText"
	_formula_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(_formula_text)

	var row := HBoxContainer.new()
	row.name = "RevealRow"
	box.add_child(row)

	var spacer := Control.new()
	spacer.name = "RevealSpacer"
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	_finish_btn = make_button("……好吧。", true)
	_finish_btn.name = "FinishButton"
	_finish_btn.pressed.connect(_on_finish_pressed)
	row.add_child(_finish_btn)
	return box


func _enter_reveal() -> void:
	_fill_reveal()
	_show_screen(3)
	# 揭晓这一屏没有输入框，把焦点交给收尾按钮，键盘玩家按回车就能走
	if _finish_btn != null:
		_finish_btn.call_deferred("grab_focus")


func _fill_reveal() -> void:
	if _state.is_empty():
		return
	var diff := int(_state["diff"])
	var past := int(_state["past"])
	var future := int(_state["future"])
	_reveal_past.text = "你的过去是 %d。" % past
	_reveal_now.text = "你的现在是 %d。" % ((diff / 10) % 10)
	_reveal_future.text = "你的未来是 %d。" % future
	_reveal_comfort.text = "不过没关系。你的未来是 %d——比 %d 大。我能感觉到，你以后会更好。" % [future, past]
	_formula_text.text = "%d ＋ %d ＝ %d" % [diff, reverse3(diff), sum_1089(diff)]


func _on_finish_pressed() -> void:
	if _done_locked or _state.is_empty():
		return
	_done_locked = true
	_finish_btn.disabled = true
	close_panel({
		"ok": true,
		"num": int(_state["num"]),
		"rev": int(_state["rev"]),
		"diff": int(_state["diff"]),
		"past": int(_state["past"]),
		"future": int(_state["future"]),
	})


# ================================================================ 公用小工具
func _make_screen(box_name: String) -> Control:
	var box := VBoxContainer.new()
	box.name = box_name
	box.add_theme_constant_override("separation", 8)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return box


## 换屏：只改 visible，不销毁节点（玩家回头也看不到已经填过的东西，但状态还在）
func _show_screen(index: int) -> void:
	if index < 0 or index >= _screens.size():
		return
	for i in _screens.size():
		_screens[i].visible = i == index
	_screen_index = index
	if index == 1:
		_refresh_step2_numbers()
		_focus(_diff_input)
	elif index == 0:
		_focus(_number_input)
	elif index == 2:
		_focus(_digit_input)


## 【手感】输入框出现时把光标放进去，不然玩家直接敲键盘是"没反应"的
func _focus(edit: LineEdit) -> void:
	if edit == null or not edit.editable:
		return
	edit.call_deferred("grab_focus")


func _set_feedback_line(label: Label, text: String, accent: bool) -> void:
	if label == null:
		return
	label.text = text
	label.add_theme_color_override("font_color", PreludeUI.C_ACCENT if accent else PreludeUI.C_INK_DIM)


# 输入框：样式与 panel_memo / panel_wardrobe 一致，另外只收数字
func _make_input(input_name: String, placeholder: String, max_len: int) -> LineEdit:
	var e := LineEdit.new()
	e.name = input_name
	e.placeholder_text = placeholder
	e.max_length = max_len
	e.custom_minimum_size = Vector2(300, 44)
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.text_changed.connect(_on_digits_only.bind(e))
	e.add_theme_stylebox_override("normal",
			PreludeUI._button_skin_box(Color(0.10, 0.105, 0.125, 0.92), PreludeUI.C_LINE))
	e.add_theme_stylebox_override("focus",
			PreludeUI._button_skin_box(Color(0.14, 0.145, 0.17, 0.96), Color(0.95, 0.86, 0.66, 0.5)))
	e.add_theme_stylebox_override("read_only",
			PreludeUI._button_skin_box(Color(0.07, 0.07, 0.08, 0.7), Color(0.4, 0.4, 0.4, 0.3)))
	e.add_theme_color_override("font_color", PreludeUI.C_INK)
	e.add_theme_color_override("font_placeholder_color", PreludeUI.C_INK_DIM)
	e.add_theme_color_override("caret_color", PreludeUI.C_NAME)
	return e


## 输入框里只留数字（非数字当场剔掉，粘贴进来的也一样）
func _on_digits_only(text: String, edit: LineEdit) -> void:
	var cleaned := ""
	for i in text.length():
		var c := text.substr(i, 1)
		if c >= "0" and c <= "9":
			cleaned += c
	if cleaned != text:
		edit.text = cleaned
		edit.caret_column = cleaned.length()


func _make_feedback(label_name: String) -> Label:
	var l := make_text("", PreludeUI.FS_TEXT, PreludeUI.C_INK_DIM)
	l.name = label_name
	l.custom_minimum_size = Vector2(0, 24)
	return l
