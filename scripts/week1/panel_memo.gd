extends "res://scripts/week1/panel_base.gd"
## ============================================================================
##  《寻星》一周目 —— 第 2 关 · 手机备忘录（罗马数字 + 密钥 5）
## ============================================================================
##  玩家在 B 的提示下打开手机，看到"备忘 03"里并排的五个罗马数字词：
##
##      XV    VI    XXI    VI    IXX
##
##  它们换算成阿拉伯数字是 15 / 6 / 21 / 6 / 19（IXX = X + IX = 19）。
##  "密钥已经出现"指的还是上一关那个 S —— S 有五笔，所以密钥是 5；
##  每个数都减掉 5：10 / 1 / 16 / 1 / 14，再按 1=A、2=B…… 换成字母，
##  得到 JAPAN（日本）。
##
##  交互：三次提示按钮（逐次吐字，不弹窗）→ 点一张罗马数字卡片，卡片下面就会
##        显示它换算后的阿拉伯数字（方便玩家自己减 5）→ 输入框（回车或"确认"）
##        → 过关。
##  另外带一张「数字 ↔ 字母」的对照表（1=A …… 26=Z），点「对照表」按钮随时开合，
##  位置就是上面那条提示文字那一格，方便玩家自己把减完的数字读成字母。
##  【不要】在这张表里写答案、替玩家做"减 5"、或者把 JAPAN 那五个字母标出来 ——
##  它只是一张纯粹的对照表。
##  过关：close_panel({"ok": true, "word": "JAPAN"})
##
##  注意：本文件只依赖 panel_base.gd 与 PreludeUI，不读 json、不切场景。
## ============================================================================

## 备忘 03 里并排的五个"词"。注意最后一个是 IXX（= X + IX = 19），
## 是 Kerry 指定的写法，不要"顺手纠正"成 XIX。
const ROMAN_WORDS: Array[String] = ["XV", "VI", "XXI", "VI", "IXX"]
## 每个罗马数字词对应的阿拉伯数字（点卡片时显示给玩家，方便他自己算）
const ROMAN_VALUES: Array[int] = [15, 6, 21, 6, 19]

## 数字 ↔ 字母对照表：1=A、2=B …… 26=Z，一共 26 格，分两行铺开
## 【很重要】它只是一张纯粹的对照表：不写答案、不替玩家做"减 5"、
## 也不要把 JAPAN 那五个字母标成高亮 —— 换算得玩家自己来。
const TABLE_COLUMNS := 13
## 表头：一句话说清这张表"只用来对照、不给答案"，免得玩家以为它是提示
const TABLE_HEAD_TEXT := "数字 ↔ 字母对照表（1=A …… 26=Z）· 只用来对照，不给答案"
## 「对照表」开关在两种状态下的按钮文案
const TABLE_BTN_TEXT := "对照表  1=A …… 26=Z"
const TABLE_BTN_CLOSE_TEXT := "收起对照表"

## 三次提示的文本，按点击次数依次显示
const HINTS: Array[String] = [
	"这五个不是字母，是罗马数字：XV、VI、XXI、VI、IXX。",
	"换成阿拉伯数字：15、6、21、6、19。密钥在上一关 —— 上一关的 S 有五笔。",
	"每个数都减掉密钥 5：10、1、16、1、14。再按 1=A、2=B…… 换成五个字母。",
]

## 正确答案
const ANSWER := "JAPAN"
## 错到第几次开始把密钥直接说出来
const REVEAL_AT := 3

var _hint_index := 0               # 已经亮出几条提示
var _wrong_count := 0              # 答错次数
var _hint_label: Label = null      # 显示当前提示文本
var _table_card: Control = null    # 数字 ↔ 字母对照表（和提示文字共用同一格位置）
var _table_btn: Button = null      # 开合对照表的按钮
var _feedback: Label = null        # 判定反馈（对/错）
var _input: LineEdit = null
var _confirm: Button = null
## 五个罗马数字卡片，以及与之一一对应的"换算结果"标签
var _word_cards: Array[Button] = []
var _word_values: Array[Label] = []
var _word_shown: Dictionary = {}   # 卡片下标 → 已经点开（显示阿拉伯数字）
var _done_locked := false          # 已过关，屏蔽重复提交


# ---------------------------------------------------------------- 覆盖点
func panel_title() -> String:
	return "手机 · 备忘录"


func panel_hint() -> String:
	return "密钥在上一关；把五个罗马数字解开，输入那个词"


func build_body(body: VBoxContainer) -> void:
	_build_memo_card(body)
	body.add_child(PreludeUI.hline(0.0, Color(0.85, 0.80, 0.70, 0.16)))
	_build_hint_row(body)
	_hint_label = make_text("（点上面的「提示」，一次给一条。）", PreludeUI.FS_TEXT, PreludeUI.C_INK_DIM)
	_hint_label.custom_minimum_size = Vector2(0, 52)
	body.add_child(_hint_label)
	_build_table(body)
	body.add_child(_build_input_row())

	_feedback = make_text("", PreludeUI.FS_TEXT, PreludeUI.C_ACCENT)
	_feedback.custom_minimum_size = Vector2(0, 24)
	body.add_child(_feedback)

	# 【手感】面板一开就把光标放进输入框：不然玩家直接敲键盘是"没反应"的
	# （LineEdit 要先被点一下才拿到焦点），很容易被当成 bug。
	if _input != null:
		_input.call_deferred("grab_focus")


# ---------------------------------------------------------------- 备忘录卡片
## 手机备忘录的样子：一张深色卡片，标题「备忘 03」，正文是五个罗马数字词，
## 下面两行备注点出"这是罗马数字"和"密钥在上一关"。
func _build_memo_card(parent: Control) -> void:
	var card := PanelContainer.new()
	card.name = "MemoCard"
	card.add_theme_stylebox_override("panel", PreludeUI.panel_skin(PreludeUI.C_CARD_BG, Color(0.85, 0.80, 0.70, 0.22), 4))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(card)

	var col := VBoxContainer.new()
	col.name = "MemoColumn"
	col.add_theme_constant_override("separation", 6)
	card.add_child(col)

	var title := make_text("备忘 03", PreludeUI.FS_CARD, PreludeUI.C_NAME)
	col.add_child(title)
	col.add_child(PreludeUI.hline(0.0, Color(0.85, 0.80, 0.70, 0.14)))

	col.add_child(make_text("刘忆只留下五个词，什么说明都没写：", PreludeUI.FS_TIP, PreludeUI.C_INK_DIM))
	_build_word_row(col)
	col.add_child(make_text("刘忆说：这不是字母，是罗马数字。", PreludeUI.FS_TIP, PreludeUI.C_INK_DIM))
	col.add_child(make_text("密钥在上一关（上一关的 S 有五笔）。", PreludeUI.FS_TIP, PreludeUI.C_INK_DIM))


## 五个等宽的"词"格子：上面是罗马数字卡片（可点），下面是换算出的阿拉伯数字。
func _build_word_row(parent: Control) -> void:
	var row := HBoxContainer.new()
	row.name = "RomanRow"
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	for i in ROMAN_WORDS.size():
		var cell := VBoxContainer.new()
		cell.name = "Word%d" % i
		cell.add_theme_constant_override("separation", 2)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(cell)

		var card := Button.new()
		card.name = "WordCard%d" % i
		card.text = ROMAN_WORDS[i]
		card.tooltip_text = "点一下看看它等于几"
		card.custom_minimum_size = Vector2(0, 48)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.focus_mode = Control.FOCUS_ALL
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		card.add_theme_font_size_override("font_size", PreludeUI.FS_NAME + 4)
		_apply_word_skin(card, false)
		card.pressed.connect(_on_word_pressed.bind(i))
		cell.add_child(card)
		_word_cards.append(card)

		# 未点开时是一条短横，点开后换成这个罗马数字的阿拉伯数值
		var val := make_text("—", PreludeUI.FS_TIP, PreludeUI.C_INK_DIM)
		val.name = "WordValue%d" % i
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		val.custom_minimum_size = Vector2(0, 20)
		cell.add_child(val)
		_word_values.append(val)


## 点罗马数字卡片：在它下面显示 / 收起换算后的阿拉伯数字（就地切换，不弹窗）
func _on_word_pressed(index: int) -> void:
	if index < 0 or index >= _word_values.size():
		return
	if _word_shown.has(index):
		_word_shown.erase(index)
		_word_values[index].text = "—"
		_apply_word_skin(_word_cards[index], false)
	else:
		_word_shown[index] = true
		_word_values[index].text = str(ROMAN_VALUES[index])
		_apply_word_skin(_word_cards[index], true)


## 卡片皮肤：点开（shown）时整格翻成暖黄高亮
func _apply_word_skin(card: Button, shown: bool) -> void:
	var bg := Color(0.22, 0.185, 0.115, 0.95) if shown else Color(0.13, 0.135, 0.16, 0.92)
	var edge := Color(0.96, 0.80, 0.55, 0.75) if shown else Color(0.85, 0.80, 0.70, 0.20)
	var hover := Color(0.28, 0.235, 0.145, 0.98) if shown else Color(0.19, 0.195, 0.23, 0.96)
	card.add_theme_stylebox_override("normal", _word_box(bg, edge))
	card.add_theme_stylebox_override("hover", _word_box(hover, edge))
	card.add_theme_stylebox_override("pressed", _word_box(bg, edge))
	card.add_theme_stylebox_override("focus", _word_box(hover, edge))
	card.add_theme_color_override("font_color", PreludeUI.C_NAME if shown else PreludeUI.C_INK)
	card.add_theme_color_override("font_hover_color", PreludeUI.C_NAME)
	card.add_theme_color_override("font_pressed_color", PreludeUI.C_NAME)


func _word_box(bg: Color, edge: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = edge
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 6.0
	sb.content_margin_right = 6.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	return sb


# ---------------------------------------------------------------- 提示按钮
## 一排"提示"按钮：每点一次吐一条提示语，全部点完后按钮变灰。
func _build_hint_row(parent: Control) -> void:
	var row := HBoxContainer.new()
	row.name = "HintRow"
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	var head := make_text("提示", PreludeUI.FS_TIP, PreludeUI.C_INK_DIM)
	head.custom_minimum_size = Vector2(48, 0)
	head.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(head)

	var btn := make_button("提示  1 / %d" % HINTS.size())
	btn.name = "HintButton"
	btn.pressed.connect(_on_hint_pressed.bind(btn))
	row.add_child(btn)

	# 右端放"对照表"开关：把它推到最后，和左边的提示分开，免得看成一排提示
	var spacer := Control.new()
	spacer.name = "HintSpacer"
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	_table_btn = make_button(TABLE_BTN_TEXT)
	_table_btn.name = "TableButton"
	_table_btn.tooltip_text = "数字和字母怎么对应（1=A …… 26=Z），随时可查"
	# 字体比主按钮小一号，别抢主视觉
	_table_btn.add_theme_font_size_override("font_size", PreludeUI.FS_TIP)
	_table_btn.pressed.connect(_toggle_table)
	row.add_child(_table_btn)


# ---------------------------------------------------------------- 对照表
## 数字 ↔ 字母对照表：1=A、2=B …… 26=Z，13 列 × 2 行，铺在面板底部。
## 【为什么和提示文字共用一格】这个面板的正文本来就正好填满外框（外框会长高，
## 但屏幕只有 720 高），再往下多塞一行会把面板顶到屏幕边上；所以做成开关，
## 位置就是提示文字那一格 —— 玩家随时点得开，不是一次性提示。
## 【不要】往表里加答案、加"减 5 之后是……"、或者给 JAPAN 那五个字母描边。
func _build_table(parent: Control) -> void:
	var card := PanelContainer.new()
	card.name = "AlphabetTable"
	card.add_theme_stylebox_override("panel", _word_box(Color(0.13, 0.135, 0.16, 0.92), Color(0.85, 0.80, 0.70, 0.16)))
	card.custom_minimum_size = Vector2(0, 52)
	card.visible = false
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(card)
	_table_card = card

	var col := VBoxContainer.new()
	col.name = "TableColumn"
	col.add_theme_constant_override("separation", 2)
	card.add_child(col)

	# 表头：写清它只是一张对照表。玩家容易把"对照表"当成提示，
	# 所以这句话必须留在卡里、和表格一起开关。
	var head := make_text(TABLE_HEAD_TEXT, PreludeUI.FS_TIP - 1, PreludeUI.C_INK_DIM)
	head.name = "TableHeader"
	head.autowrap_mode = TextServer.AUTOWRAP_OFF
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(head)

	var grid := GridContainer.new()
	grid.name = "TableGrid"
	grid.columns = TABLE_COLUMNS
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 2)
	# 表格只有 500 出头宽，居中对齐比靠左好看
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(grid)

	var names := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
	for n in range(1, 27):
		var cell := make_text("%d %s" % [n, names[n - 1]], PreludeUI.FS_TIP - 1, PreludeUI.C_INK_DIM)
		cell.name = "TableCell%d" % n
		# 【坑】make_text 默认开自动换行；13 列的表格里每格都会被折成两行，必须关掉
		cell.autowrap_mode = TextServer.AUTOWRAP_OFF
		cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.custom_minimum_size = Vector2(34, 16)
		grid.add_child(cell)


## 在「提示文字」和「对照表」之间来回切（两个共用正文里同一格位置）
func _toggle_table() -> void:
	if _table_card == null:
		return
	if _table_card.visible:
		_show_hint_slot()
	else:
		_table_card.visible = true
		if _hint_label != null:
			_hint_label.visible = false
		if _table_btn != null:
			_table_btn.text = TABLE_BTN_CLOSE_TEXT


## 切回「提示文字」那一格（点提示时自动调用 —— 否则对照表开着的时候点提示，
## 屏幕上什么都不会变，玩家会以为按钮坏了）
func _show_hint_slot() -> void:
	if _table_card != null:
		_table_card.visible = false
	if _hint_label != null:
		_hint_label.visible = true
	if _table_btn != null:
		_table_btn.text = TABLE_BTN_TEXT


func _on_hint_pressed(btn: Button) -> void:
	if _hint_index >= HINTS.size():
		return
	_show_hint_slot()   # 正开着对照表的话先切回提示文字，不然点了像没反应
	_hint_label.text = HINTS[_hint_index]
	_hint_index += 1
	if _hint_index >= HINTS.size():
		btn.disabled = true
		btn.text = "提示  已全部给出"
	else:
		btn.text = "提示  %d / %d" % [_hint_index + 1, HINTS.size()]


# ---------------------------------------------------------------- 输入行
func _build_input_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "InputRow"
	row.add_theme_constant_override("separation", 10)

	_input = LineEdit.new()
	_input.name = "AnswerInput"
	_input.placeholder_text = "输入解出来的词"
	_input.max_length = 16
	_input.custom_minimum_size = Vector2(320, 44)
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.add_theme_stylebox_override("normal", _input_box(Color(0.13, 0.135, 0.16, 0.92), PreludeUI.C_LINE))
	_input.add_theme_stylebox_override("focus", _input_box(Color(0.17, 0.175, 0.20, 0.96), Color(0.95, 0.86, 0.66, 0.55)))
	_input.add_theme_stylebox_override("read_only", _input_box(Color(0.09, 0.09, 0.10, 0.7), Color(0.4, 0.4, 0.4, 0.3)))
	_input.add_theme_color_override("font_color", PreludeUI.C_INK)
	_input.add_theme_color_override("font_placeholder_color", PreludeUI.C_INK_DIM)
	_input.add_theme_color_override("caret_color", PreludeUI.C_NAME)
	_input.text_submitted.connect(_on_submitted)
	row.add_child(_input)

	_confirm = make_button("确认", true)
	_confirm.name = "ConfirmButton"
	_confirm.pressed.connect(func() -> void: _on_submitted(_input.text))
	row.add_child(_confirm)
	return row


# ---------------------------------------------------------------- 判定
## 输入不区分大小写、忽略空格；答案仍是 JAPAN
func _on_submitted(text: String) -> void:
	if _done_locked:
		return
	var guess := text.strip_edges().replace(" ", "").to_upper()
	if guess == "":
		# 【坑】原来是静默 return：没点输入框就直接按「确认」时画面上毫无反应，
		# 玩家会以为"卡住了"。现在给一句话，并把光标放进框里。
		_feedback.add_theme_color_override("font_color", PreludeUI.C_INK_DIM)
		_feedback.text = "先在上面那个框里输入解出来的词。"
		_input.call_deferred("grab_focus")
		return
	if guess == ANSWER:
		_win()
		return
	_wrong_count += 1
	_feedback.add_theme_color_override("font_color", PreludeUI.C_ACCENT)
	var line := "不对。再想想密钥 —— 密钥在上一关。"
	if _wrong_count >= REVEAL_AT:
		line += "密钥是五：每个罗马数字减掉 5，再换成字母。"
	_feedback.text = line


func _win() -> void:
	_done_locked = true
	if _input:
		_input.editable = false
	if _confirm:
		_confirm.disabled = true
	_feedback.add_theme_color_override("font_color", PreludeUI.C_NAME)
	_feedback.text = "JAPAN —— 日本。"
	# 停 0.6 秒让玩家看清判定，再交出结果
	get_tree().create_timer(0.6).timeout.connect(func() -> void:
		close_panel({"ok": true, "word": ANSWER})
	)


## 输入框皮肤（LineEdit 不吃 Button 的那套皮肤，这里单独做一张）
func _input_box(bg: Color, edge: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = edge
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	return sb
