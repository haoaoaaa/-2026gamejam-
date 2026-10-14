extends "res://scripts/week1/panel_base.gd"
## ============================================================================
##  《寻星》二周目 —— 第 2 关 · 密室（推理问答）
## ============================================================================
##  自白「这是人造的密室」之后，李星把问题一条条摆出来。玩家必须答对才能
##  往下一题走——答错只是重答，跳不过去（附录7 的五道题）。
##
##  5 道题，一次只显示一道（左上角写「第 n / 5 题」）：
##    · 单选（第 1~4 题）：点一下即刻判定；
##    · 双选（第 5 题）：点选只是切换选中态，按「确认」才判定，
##      两个都选中才算对。
##  答错：玩家点过的那个按钮标红 + 闪一下，给一句话，允许重选；
##  答对：反馈「……对。」，选项变灰，冒出「下一题」。
##  第 5 题答完 → 摊开「李星认定的诡计」，按「……就是这样。」过关：
##      close_panel({"ok": true})
##
##  【本文件的坑，改之前先看这几条】
##   1. RichTextLabel 没有 set_v_scroll()（4.7 报 Method not found）——
##      所以这里全部用 make_rich()：fit_content = true + scroll_active = false，
##      不需要滚动条。
##   2. PacKedStringArray(["…"]) 不是常量表达式，const 会直接编译失败；
##      要常量就用普通 Array 字面量（本文件就这么写）。
##   3. PreludeUI.apply_button_skin() 的形参是 Button，别把别的控件传进来。
##   4. 子类不要声明 _body / _ctx / _done / _closing —— 基类已经有了。
##   5. 不要写 class_name：--script 无头模式下会报 Identifier not declared。
##
##  本文件只依赖 panel_base.gd 与 PreludeUI，不读 json、不切场景。
## ============================================================================

## 五道题。answer 里存的是 options 的下标（多选题就是一组下标）。
## 选项顺序照抄附录7，不要改。
const QUESTIONS: Array[Dictionary] = [
	{
		"q": "这是密室杀人，药瓶是谁打翻的？",
		"options": ["刘忆", "凶手", "来调查的老师", "宿管阿姨"],
		"answer": [1],
		"multi": false,
		"ok": "……对。药瓶是凶手打翻的——他要的是门缝前那一线。",
		"bad": "不对。再想想药瓶为什么会翻。",
		"bad_one": {0: "刘忆自己打翻的？那这就不叫密室了。"},
	},
	{
		"q": "凶手为什么打翻药瓶？",
		"options": ["饿了", "感冒了", "伪造密室", "与刘忆争吵时打翻"],
		"answer": [2],
		"multi": false,
		"ok": "……对。他打翻药瓶，是为了造出密室。",
		"bad": "不对。他为什么要碰那个药瓶？",
	},
	{
		"q": "刘忆为什么会坠楼？",
		"options": ["不小心掉下去的", "自杀", "凶手推了一把"],
		"answer": [2],
		"multi": false,
		"ok": "……对。不是她自己掉下去的。",
		"bad": "不对。再想想她为什么会到窗边。",
		"bad_one": {0: "那凶手的手法就说不通了。"},
	},
	{
		"q": "扫帚翻倒是因为？",
		"options": ["伪造线索", "风吹的", "刘忆掉下去时撞翻的", "宿管阿姨的恶作剧"],
		"answer": [0],
		"multi": false,
		"ok": "……对。扫帚是被人摆在那儿的。",
		"bad": "不对。扫帚为什么偏偏倒在那个位置？",
	},
	{
		"q": "知道造这个密室的方法（知道地板是斜的）的人会是？",
		"options": ["李星", "刘忆", "同寝室的同学", "宿管阿姨"],
		"answer": [2, 3],
		"multi": true,
		"ok": "……对。只有同寝室的同学和宿管阿姨。",
		"bad": "不对。再想想：得过这间寝室的、动得了这间寝室的人，有谁？",
	},
]

## 答对第 5 题之后先亮的一句，再接总结卡
const SUMMARY_LEAD := "……对。只有同寝室的同学和宿管阿姨。"

## 总结卡：李星认定的诡计
const SUMMARY_TEXT := "凶手要的不是一个杀人的办法，是一个「没人进得来」的说法。\n\n他先知道了这间寝室的地板是斜的——阳台那一头高，门这一头低。\n他把药盒靠在门上，再一点一点地把门合上：\n药片顺着坡度挤到门缝底下，一片一片地停在那里。\n他再隔着门缝，把位置不对的药片，拨到药盒自然翻倒时该在的地方。\n门合上，锁上。第一个推开门的人，看见的就是一个没人进得来的现场。\n\n可是要造出这个密室，得先知道这间寝室的地板是斜的。\n[color=#b3574f]知道这件事的人，只有同寝室的同学和宿管阿姨。[/color]"

## 过关后让总结在屏幕上多停半拍，再把控制权交回去
const CLOSE_DELAY := 0.45

var _quiz_box: VBoxContainer = null
var _progress: Label = null
var _question_label: Label = null
var _option_grid: GridContainer = null
var _confirm_btn: Button = null
var _feedback: Label = null
var _next_btn: Button = null
var _summary_card: PanelContainer = null
var _summary_text: RichTextLabel = null

var _option_buttons: Array[Button] = []
var _picked: Array[int] = []          # 多选题里当前选中的下标
var _index := 0                       # 当前第几题（0 起）
var _multi := false                   # 当前这题是不是双选
var _locked := false                  # 这题已答对，等玩家按「下一题」
var _all_done := false                # 五题都答完，已切到总结卡

# 延时关闭：> 0 时每帧倒计时，到点 close_panel。基类没有 _process，这里可以覆盖。
var _exit_delay := -1.0
var _exit_result: Dictionary = {}


# ---------------------------------------------------------------- 基类覆盖点
func panel_title() -> String:
	return "密室"


func panel_hint() -> String:
	return "选对了才能进入下一个问题"


func build_body(body: VBoxContainer) -> void:
	_quiz_box = VBoxContainer.new()
	_quiz_box.name = "ReasonQuiz"
	_quiz_box.add_theme_constant_override("separation", 10)
	_quiz_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_quiz_box)

	_progress = make_text("", PreludeUI.FS_TIP, PreludeUI.C_INK_DIM)
	_progress.name = "ReasonProgress"
	_quiz_box.add_child(_progress)

	_question_label = make_text("", PreludeUI.FS_TEXT, PreludeUI.C_NAME)
	_question_label.name = "ReasonQuestion"
	_question_label.custom_minimum_size = Vector2(0, 34)
	_quiz_box.add_child(_question_label)

	_option_grid = GridContainer.new()
	_option_grid.name = "ReasonOptions"
	_option_grid.columns = 2
	_option_grid.add_theme_constant_override("h_separation", 10)
	_option_grid.add_theme_constant_override("v_separation", 10)
	_option_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_quiz_box.add_child(_option_grid)

	_confirm_btn = make_button("确认", true)
	_confirm_btn.name = "ReasonConfirm"
	_confirm_btn.visible = false
	_confirm_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_confirm_btn.pressed.connect(_on_confirm_pressed)
	_quiz_box.add_child(_confirm_btn)

	_feedback = make_text("", PreludeUI.FS_TEXT, PreludeUI.C_INK_DIM)
	_feedback.name = "ReasonFeedback"
	_feedback.custom_minimum_size = Vector2(0, 30)
	_quiz_box.add_child(_feedback)

	_next_btn = make_button("下一题", true)
	_next_btn.name = "ReasonNext"
	_next_btn.visible = false
	_next_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	_next_btn.pressed.connect(_on_next_pressed)
	_quiz_box.add_child(_next_btn)

	_build_summary(body)

	set_process(true)      # 给延时关闭用（基类没有 _process，这里安全）
	_show_question(0)


# ---------------------------------------------------------------- 总结卡
func _build_summary(parent: Control) -> void:
	_summary_card = PanelContainer.new()
	_summary_card.name = "ReasonSummary"
	_summary_card.add_theme_stylebox_override("panel", PreludeUI.panel_skin(Color(0.12, 0.10, 0.10, 0.94), Color(0.70, 0.34, 0.32, 0.55), 6))
	_summary_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_summary_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_summary_card.visible = false
	parent.add_child(_summary_card)

	var col := VBoxContainer.new()
	col.name = "SummaryColumn"
	col.add_theme_constant_override("separation", 8)
	_summary_card.add_child(col)

	col.add_child(make_text(SUMMARY_LEAD, PreludeUI.FS_TEXT, PreludeUI.C_ACCENT))
	col.add_child(make_text("李星认定的诡计", PreludeUI.FS_CARD, PreludeUI.C_NAME))
	col.add_child(PreludeUI.hline(0.0, Color(0.85, 0.80, 0.70, 0.16)))

	_summary_text = make_rich(SUMMARY_TEXT, PreludeUI.FS_TEXT)
	_summary_text.name = "SummaryText"
	_summary_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_summary_text)

	var ok := make_button("……就是这样。", true)
	ok.name = "ReasonDone"
	ok.size_flags_horizontal = Control.SIZE_SHRINK_END
	ok.pressed.connect(_on_done_pressed)
	col.add_child(ok)


# ---------------------------------------------------------------- 出题
## 铺第 index 题：先把上一题的按钮整批换掉，再按多选/单选决定要不要显示「确认」
func _show_question(index: int) -> void:
	_index = index
	_locked = false
	_multi = bool(QUESTIONS[index].get("multi", false))
	_picked.clear()

	for child in _option_grid.get_children():
		_option_grid.remove_child(child)
		child.queue_free()
	_option_buttons.clear()

	_progress.text = "第 %d / %d 题" % [index + 1, QUESTIONS.size()]
	var q := str(QUESTIONS[index]["q"])
	_question_label.text = q if not _multi else "%s（双选：两个都选中才算对）" % q

	_feedback.text = ""
	_feedback.add_theme_color_override("font_color", PreludeUI.C_INK_DIM)
	_confirm_btn.visible = _multi
	_confirm_btn.disabled = false
	_next_btn.visible = false

	var options: Array = QUESTIONS[index]["options"]
	for i in options.size():
		var b := make_button(str(options[i]))
		b.name = "ReasonOption%d" % i
		b.custom_minimum_size = Vector2(0, 44)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_on_option_pressed.bind(i))
		_option_grid.add_child(b)
		_option_buttons.append(b)


# ---------------------------------------------------------------- 点击
func _on_option_pressed(index: int) -> void:
	if _locked or _all_done:
		return
	if index < 0 or index >= _option_buttons.size():
		return
	var btn := _option_buttons[index]

	# 双选：点一下只是在「选 / 不选」之间切换，判定留给「确认」
	if _multi:
		if _picked.has(index):
			_picked.erase(index)
			_set_option_selected(btn, false)
		else:
			_picked.append(index)
			_set_option_selected(btn, true)
		_feedback.add_theme_color_override("font_color", PreludeUI.C_INK_DIM)
		_feedback.text = "已选 %d 个。" % _picked.size()
		return

	# 单选：点一下就是一次作答，先把上一次留下的标红擦干净
	_reset_option_skins()
	_judge([index])


func _on_confirm_pressed() -> void:
	if _locked or _all_done or not _multi:
		return
	if _picked.is_empty():
		_feedback.add_theme_color_override("font_color", PreludeUI.C_INK_DIM)
		_feedback.text = "先选出你认为对的人。"
		return
	_judge(_picked.duplicate())


func _on_next_pressed() -> void:
	if not _locked or _all_done:
		return
	if _index + 1 >= QUESTIONS.size():
		_show_summary()
		return
	_show_question(_index + 1)


# ---------------------------------------------------------------- 判定
## 对：整题锁死、选项变灰、冒出「下一题」；错：点过的那几个标红闪一下。
## 【注意】标红只标"玩家点过的"，绝不碰他没点的那个——否则等于把正确答案漏给他。
func _judge(picked: Array) -> void:
	var item: Dictionary = QUESTIONS[_index]
	var answer: Array = item["answer"]

	var hit := picked.size() == answer.size()
	if hit:
		for a in answer:
			if not picked.has(a):
				hit = false
				break

	if hit:
		_pass_question()
		return

	for i in _option_buttons.size():
		var want: bool = answer.has(i)
		var got: bool = picked.has(i)
		if got and not want:
			_flash_wrong(_option_buttons[i])
		else:
			_set_option_selected(_option_buttons[i], false)
	_picked.clear()
	_feedback.add_theme_color_override("font_color", PreludeUI.C_ACCENT)

	# bad_one：针对"某个具体错选项"的定向反馈（如 Q1 选「刘忆」）。
	# 仍然只对玩家点过的选项生效，不影响答案保密性。
	var line := str(item["bad"])
	var special: Dictionary = item.get("bad_one", {})
	for i in picked:
		if special.has(i):
			line = str(special[i])
			break
	_feedback.text = line


func _pass_question() -> void:
	_locked = true
	for b in _option_buttons:
		b.disabled = true
	_confirm_btn.disabled = true
	_feedback.add_theme_color_override("font_color", PreludeUI.C_NAME)
	_feedback.text = str(QUESTIONS[_index]["ok"])

	# 最后一题答完就直接摊总结，中间不再多一次点击
	if _index + 1 >= QUESTIONS.size():
		_show_summary()
	else:
		_next_btn.visible = true


func _show_summary() -> void:
	_all_done = true
	_locked = true
	if _quiz_box != null:
		_quiz_box.visible = false
	if _summary_card != null:
		_summary_card.visible = true


# ---------------------------------------------------------------- 按钮外观
## 双选选中态：暗红底 + 行首一个「·」，和没选中的普通按钮区分开
func _set_option_selected(btn: Button, on: bool) -> void:
	var text := btn.text.replace("· ", "")
	if on:
		btn.text = "· " + text
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.30, 0.14, 0.13, 0.96)
		sb.border_color = PreludeUI.C_ACCENT
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(3)
		sb.content_margin_left = 16.0
		sb.content_margin_right = 16.0
		sb.content_margin_top = 10.0
		sb.content_margin_bottom = 10.0
		btn.add_theme_stylebox_override("normal", sb)
		btn.add_theme_color_override("font_color", Color(1.0, 0.86, 0.80))
	else:
		btn.text = text
		PreludeUI.apply_button_skin(btn, false)


## 选错的按钮：暗红描边 + 闪一下。文字里的「· 」一并去掉，免得残留选中记号。
func _flash_wrong(btn: Button) -> void:
	btn.text = btn.text.replace("· ", "")
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.28, 0.10, 0.10, 0.96)
	sb.border_color = PreludeUI.C_ACCENT
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 16.0
	sb.content_margin_right = 16.0
	sb.content_margin_top = 10.0
	sb.content_margin_bottom = 10.0
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb)
	btn.add_theme_color_override("font_color", Color(1.0, 0.80, 0.76))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 0.84, 0.80))
	# 皮肤负责"标红"，tween 负责"闪一下"——modulate 改不了皮肤，两层都要
	btn.modulate = Color(1.0, 1.0, 1.0, 1.0)
	var tw := create_tween()
	tw.tween_property(btn, "modulate", Color(1.0, 0.45, 0.42, 1.0), 0.08)
	tw.tween_property(btn, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.24)


func _reset_option_skins() -> void:
	for b in _option_buttons:
		b.text = b.text.replace("· ", "")
		PreludeUI.apply_button_skin(b, false)


# ---------------------------------------------------------------- 过关
func _on_done_pressed() -> void:
	if not _all_done or _exit_delay > 0.0 or _done:
		return
	_exit_result = {"ok": true}
	_exit_delay = CLOSE_DELAY


func _process(delta: float) -> void:
	if _exit_delay <= 0.0:
		return
	_exit_delay -= delta
	if _exit_delay <= 0.0:
		_exit_delay = -1.0
		close_panel(_exit_result)
