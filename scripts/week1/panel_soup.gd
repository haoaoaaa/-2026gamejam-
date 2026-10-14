extends "res://scripts/week1/panel_base.gd"
## ============================================================================
##  《寻星》一周目 —— 第 5 关 · 海龟汤（衣柜里的捉迷藏）
## ============================================================================
##  汤面：我在寝室里是一个爱笑的人。自从来到这里，我不再笑了。
##        当我离开这里，我又能笑了。
##
##  玩法分两段，顺序不能反：
##    ① 只能问"是/不是"的问题。16 个提问按钮随便点，点过的变灰，
##       每条回答追加在下面的答录里（问：… → 刘忆：是 / 不是）。
##       问满 QUESTION_GATE 条之后，② 才解锁。
##    ② 从 16 个词里正好挑 6 个。挑满就自动判定：
##       对上 ANSWER_WORDS → 吐完整汤底、过关；不对 → 清空重挑。
##
##  过关：close_panel({"ok": true, "words": ["衣柜","憋笑","室友","捉迷藏","赢","开心"]})
##
##  注意：本文件只依赖 panel_base.gd 与 PreludeUI，不读 json、不切场景。
## ============================================================================

## 汤面
const SOUP_TEXT := "我在寝室里是一个爱笑的人。自从来到这里，我不再笑了。当我离开这里，我又能笑了。"

## 完整的汤底。**故意留成纯文本、不带 BBCode**：探针会读这个常量，而
## 标红是摊牌时现做的（见 _answer_bbcode()）。
##
## 因果按《问题.txt》第 6 条改正：不是"为了赢才憋笑"，而是**憋住了笑才没被找到**、
## 才赢下捉迷藏；"赢了、出了衣柜"是最后笑出来的原因。原来那句把因果写反了。
const SOUP_ANSWER := "我在和室友玩捉迷藏，躲进了衣柜。一笑就会被找到，所以我一直憋着。憋住了笑，才没被找到，才赢下这场捉迷藏。出了衣柜以后，我很开心，才笑出来。"

## 16 个问题与刘忆的回答（顺序照抄剧本；附录4 要求「问题乱序出现」，铺按钮时打乱一次）
const QUESTIONS: Array[Dictionary] = [
	{"q": "「这里」是寝室吗？", "a": "是"},
	{"q": "是寝室里的某个位置吗？", "a": "是"},
	{"q": "是床上吗？", "a": "不是"},
	{"q": "是衣柜里吗？", "a": "是"},
	{"q": "是卫生间吗？", "a": "不是"},
	{"q": "是书桌吗？", "a": "不是"},
	{"q": "「不笑」是必须的吗？", "a": "是"},
	{"q": "我被霸凌了吗？", "a": "不是"},
	{"q": "和室友有关吗？", "a": "是"},
	{"q": "我是在憋笑吗？", "a": "是"},
	{"q": "我是在和室友玩游戏吗？", "a": "是"},
	{"q": "是憋笑挑战吗？", "a": "不是"},
	{"q": "是捉迷藏吗？", "a": "是"},
	{"q": "我最后离开了「这里」吗？", "a": "是"},
	{"q": "离开后的笑是因为开心吗？", "a": "是"},
	{"q": "和「躲」有关吗？", "a": "是"},
]

## 16 个谜底线索词（乱序铺在格子里）
const WORDS: Array[String] = [
	"寝室", "床", "衣柜", "卫生间",
	"坑", "书桌", "憋笑", "难过",
	"开心", "不想笑", "霸凌", "室友",
	"游戏", "捉迷藏", "赢", "输",
]

## 要挑出的 6 个词
const ANSWER_WORDS: Array[String] = ["衣柜", "憋笑", "室友", "捉迷藏", "赢", "开心"]

## 附录5 的氛围道具（文书里标"出现关卡 5"的就是这两件）。
## 它们纯属彩蛋：点开给一段描述，不影响提问与挑词，也不参与判定。
const AMBIENT: Array[Dictionary] = [
	{
		"name": "品红色长条状的 U 盘",
		"text": "品红色，长条，插口上有一道磨痕，外壳没写名字。\n[color=#b3574f]（也许装着一个人的人格数据。）[/color]",
		"image": "res://assets/props/usb_drive.png",
	},
	{
		"name": "一盒花切牌",
		"text": "牌盒边角磨得起毛，里面少了两张。是室友练魔术用的那一副。\n[color=#b3574f]（她手一直很快。）[/color]",
		"image": "res://assets/props/playing_cards.png",
	},
]

## 问满这么多条才解锁"挑词"
const QUESTION_GATE := 10
## 正好挑这么多词（挑满即判定）
const PICK_COUNT := 6

var _asked: Dictionary = {}          # 问题下标 → true（问过的按钮变灰）
var _asked_count := 0
var _picked: Array[String] = []      # 当前选中的词（按点击先后）
var _words_open := false             # 挑词区是否已解锁
var _win := false                    # 已过关，屏蔽后续点击
var _given_up := false               # 是"不想了，直接看汤底"摊开的（结果里带 given_up）
var _wrong_tries := 0                # 挑词连续错了几次（挑对/放弃都不再涨）
var _give_up_btn: Button = null      # 连错 3 次才摆出来的出口按钮（名字固定 SoupGiveUp）

var _question_buttons: Array[Button] = []
var _answer_log: RichTextLabel = null
var _answer_lines: Array[String] = []
var _words_title: Label = null
var _word_buttons: Dictionary = {}    # 词 → 按钮
var _word_box: Control = null         # 整个挑词区（问满之前 visible = false）
var _counter: Label = null
var _feedback: Label = null
var _ambient_text: RichTextLabel = null          # 床边那两件小东西的描述
var _ambient_photo: TextureRect = null           # 点开那两件东西时显示的道具图
var _ambient_buttons: Array[Button] = []
var _ambient_seen: Dictionary = {}               # 下标 → true

# ---------------------------------------------------------------- 覆盖点
func panel_title() -> String:
	return "海龟汤"


func panel_hint() -> String:
	# 【提示】挑词那一步的判据不是"这六个词各自对不对"，而是"同一碗汤底能不能
	# 把它们全解释掉"。不写明这一点，玩家会拿六个各自单独成立的词去凑
	#（比如「寝室 + 难过」）。这里只讲规则、不点名是哪六个词，也不暗示"衣柜"。
	# 放在底部这一行（而不是汤面卡片里）是有意的：汤面卡片在滚动区顶部，
	# 玩家滚到下面挑词时它已经滚出屏幕了，而底部提示行永远在场。
	return "只能问是/不是；听完答案，从词里挑六个——六个词都得能在同一碗汤底里说得通"


func build_body(body: VBoxContainer) -> void:
	# 内容比 900×540 的面板高，整块塞进滚动容器，小的窗口也不会挤爆
	var scroll := ScrollContainer.new()
	scroll.name = "SoupScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)

	var col := VBoxContainer.new()
	col.name = "SoupColumn"
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 10)
	scroll.add_child(col)

	_build_soup_card(col)
	_build_ambient(col)
	_build_questions(col)
	_build_answer_log(col)
	_build_words(col)

	_feedback = make_text("", PreludeUI.FS_TEXT, PreludeUI.C_ACCENT)
	_feedback.custom_minimum_size = Vector2(0, 30)
	col.add_child(_feedback)


# ---------------------------------------------------------------- 汤面
func _build_soup_card(parent: Control) -> void:
	var card := PanelContainer.new()
	card.name = "SoupCard"
	card.add_theme_stylebox_override("panel", PreludeUI.panel_skin(PreludeUI.C_CARD_BG, Color(0.85, 0.80, 0.70, 0.22), 4))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(card)

	var col := VBoxContainer.new()
	col.name = "SoupCardColumn"
	col.add_theme_constant_override("separation", 6)
	card.add_child(col)

	col.add_child(make_text("汤面", PreludeUI.FS_CARD, PreludeUI.C_NAME))
	col.add_child(PreludeUI.hline(0.0, Color(0.85, 0.80, 0.70, 0.14)))
	col.add_child(make_text(SOUP_TEXT, PreludeUI.FS_TEXT, PreludeUI.C_INK))


# ---------------------------------------------------------------- 提问按钮
## 16 个提问按钮铺成 4×4 的格子：点哪个都行，点过的变灰、答案落进答录。
func _build_questions(parent: Control) -> void:
	var box := VBoxContainer.new()
	box.name = "PresetBox"
	box.add_theme_constant_override("separation", 6)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(box)

	box.add_child(make_text("问 刘忆（只能问是 / 不是）", PreludeUI.FS_TIP, PreludeUI.C_INK_DIM))

	var grid := GridContainer.new()
	grid.name = "QuestionGrid"
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(grid)

	# 附录4：「问题乱序出现」——每次 build 重排一次铺出去的顺序。
	# 只乱"铺的顺序"：按钮仍然挂在 _question_buttons[原下标] 上（先 resize 再按位写），
	# 点哪一颗都按 QUESTIONS[原下标] 判定 —— 既不会重复，也不会漏。
	var order: Array[int] = []
	for i in QUESTIONS.size():
		order.append(i)
	order.shuffle()
	_question_buttons.resize(QUESTIONS.size())

	for i in order:
		var btn := make_button(str(QUESTIONS[i]["q"]))
		btn.name = "Question%d" % i
		# 4 列平分 840px 的内容宽度，长问题一律截断显示
		btn.custom_minimum_size = Vector2(196, 42)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.autowrap_mode = TextServer.AUTOWRAP_OFF
		btn.clip_text = true
		btn.add_theme_font_size_override("font_size", PreludeUI.FS_TIP)
		btn.pressed.connect(_on_question_pressed.bind(i))
		grid.add_child(btn)
		_question_buttons[i] = btn


func _on_question_pressed(index: int) -> void:
	if _win or index < 0 or index >= QUESTIONS.size() or _asked.has(index):
		return
	_asked[index] = true
	_asked_count += 1
	var btn := _question_buttons[index]
	btn.disabled = true

	var item := QUESTIONS[index]
	_append_answer("问：%s   →   刘忆：%s" % [str(item["q"]), str(item["a"])])

	if _asked_count >= QUESTION_GATE and not _words_open:
		_open_words()


# ---------------------------------------------------------------- 答录
## 答录是一块固定高度的卡片，问答一行行往里追，追满自动滚到底。
func _build_answer_log(parent: Control) -> void:
	var panel := PanelContainer.new()
	panel.name = "AnswerLog"
	panel.add_theme_stylebox_override("panel", PreludeUI.panel_skin(PreludeUI.C_PANEL, Color(0.85, 0.80, 0.70, 0.14), 4))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(0, 122)
	parent.add_child(panel)

	_answer_log = make_rich("（还没开口。）", PreludeUI.FS_CARD)
	_answer_log.name = "AnswerText"
	_answer_log.custom_minimum_size = Vector2(0, 94)
	_answer_log.scroll_active = true
	_answer_log.scroll_following = true
	panel.add_child(_answer_log)


func _append_answer(line: String) -> void:
	_answer_lines.append(line)
	if _answer_log:
		_answer_log.text = "\n".join(_answer_lines)
		# 追到底：RichTextLabel 没有 set_v_scroll()（4.7 会报 Method not found），
		# 只能拿滚动条把 value 顶到最大；延迟一帧——这时候新内容才算完高度。
		var bar := _answer_log.get_v_scroll_bar()
		if bar != null:
			bar.call_deferred("set_value", bar.max_value)


# ---------------------------------------------------------------- 挑词
## 问满 QUESTION_GATE 条之后解锁：16 个词里正好挑 6 个。
func _build_words(parent: Control) -> void:
	var box := VBoxContainer.new()
	box.name = "WordBox"
	box.add_theme_constant_override("separation", 6)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.visible = false            # 解锁前整块藏起来
	parent.add_child(box)
	_word_box = box

	_words_title = make_text("谜底线索词 · 正好挑出 %d 个" % PICK_COUNT, PreludeUI.FS_TIP, PreludeUI.C_NAME)
	box.add_child(_words_title)

	var grid := GridContainer.new()
	grid.name = "WordGrid"
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(grid)

	for w in WORDS:
		var word := str(w)
		var btn := make_button(word)
		btn.name = "Word_" + word
		btn.custom_minimum_size = Vector2(0, 38)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", PreludeUI.FS_TIP)
		btn.pressed.connect(_on_word_pressed.bind(word))
		grid.add_child(btn)
		_word_buttons[word] = btn

	var foot := HBoxContainer.new()
	foot.name = "WordFoot"
	foot.add_theme_constant_override("separation", 10)
	box.add_child(foot)

	_counter = make_text("已选 0 / %d" % PICK_COUNT, PreludeUI.FS_TIP, PreludeUI.C_INK_DIM)
	_counter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_counter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	foot.add_child(_counter)

	var reset := make_button("重挑")
	reset.name = "ResetPicked"
	reset.add_theme_font_size_override("font_size", PreludeUI.FS_TIP)
	reset.pressed.connect(_reset_picked)
	foot.add_child(reset)


func _open_words() -> void:
	_words_open = true
	if _word_box:
		_word_box.visible = true
	if _feedback:
		_feedback.text = "问够了。现在从这十六个词里挑出 %d 个——挑满就摊牌。" % PICK_COUNT


func _on_word_pressed(word: String) -> void:
	if _win or not _words_open:
		return
	var btn := _word_buttons.get(word, null) as Button
	if btn == null:
		return
	if _picked.has(word):
		_picked.erase(word)
		_set_word_selected(btn, false)
	else:
		_picked.append(word)
		_set_word_selected(btn, true)
	_refresh_counter()
	if _picked.size() >= PICK_COUNT:
		_submit_picked()


## 选中态：按钮换成暗红描边 + 行首一个「·」，跟正常按钮区分开
func _set_word_selected(btn: Button, on: bool) -> void:
	var word := btn.text.replace("· ", "")
	if on:
		btn.text = "· " + word
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
		btn.text = word
		# 用同一张皮肤覆盖回普通态；悬停/按下态由 PreludeUI 的皮肤接管
		PreludeUI.apply_button_skin(btn, false)
		btn.add_theme_font_size_override("font_size", PreludeUI.FS_TIP)


func _refresh_counter() -> void:
	if _counter:
		_counter.text = "已选 %d / %d" % [_picked.size(), PICK_COUNT]


func _reset_picked() -> void:
	if _win:
		return
	for w in _picked:
		var btn := _word_buttons.get(w, null) as Button
		if btn != null:
			_set_word_selected(btn, false)
	_picked.clear()
	_refresh_counter()


func _submit_picked() -> void:
	# 挑满只是"该判定了"；对错只认全中，多一个少一个都算错
	var all_hit := _picked.size() == ANSWER_WORDS.size()
	if all_hit:
		for w in ANSWER_WORDS:
			if not _picked.has(w):
				all_hit = false
				break
	if all_hit:
		_win_soup()
		return

	# 【必须先数再清】_reset_picked() 把 _picked 清空，之后再数就永远是 0 ——
	# Kerry 说"点错没有提示、感觉很难全解对"，所以先数出这六个词里蒙对几个。
	var hits := 0
	for w in _picked:
		if ANSWER_WORDS.has(w):
			hits += 1
	_reset_picked()
	_wrong_tries += 1

	var lines: Array[String] = []
	if hits == 0:
		lines.append("不对。这六个词，一个都不在汤底里——先多问几句，把范围圈小一点。")
	else:
		lines.append("不对。这六个词里有 %d 个是汤底里真有的（还差 %d 个）。"
			% [hits, ANSWER_WORDS.size() - hits])
	if _wrong_tries == 1:
		# 第一次挑错给一句方向性的提示（探针认这句话）
		lines.append("　回去再想想：她为什么不能笑？她赢的是什么？")
	if _wrong_tries >= 2:
		lines.append("　再想想：她为什么不能笑？她赢的是什么？")
	if _wrong_tries >= 3:
		# 第三次起只给"汤底的结构"，**不点名任何词**：给了词这关就没得玩了
		lines.append("　汤底无非是：藏在哪儿、为什么不能出声、跟谁一起、在做什么、最后怎样、当时的心情。")
	if _feedback:
		_feedback.add_theme_color_override("font_color", PreludeUI.C_ACCENT)
		_feedback.text = "\n".join(lines)

	# 连错三次就把出口摆出来（Kerry：不是每个游玩的人都想要解开）
	if _wrong_tries >= 3:
		_ensure_give_up_button()


## 连错三次才出现的出口：不玩了也能把汤底看完。按钮名字固定 "SoupGiveUp"（探针按名字找它），
## 按下直接走 _win_soup(true) —— 照样禁用问题/词按钮、照样摊汤底卡，只是结果里带 given_up。
func _ensure_give_up_button() -> void:
	if _give_up_btn != null:
		return
	if _feedback == null or _feedback.get_parent() == null:
		return
	var btn := make_button("不想了，直接看汤底")
	btn.name = "SoupGiveUp"
	btn.custom_minimum_size = Vector2(0, 34)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	btn.pressed.connect(_on_give_up_pressed)
	# _feedback 是主列里最后一件东西，接在它后面就是"下方"
	_feedback.get_parent().add_child(btn)
	_give_up_btn = btn


func _on_give_up_pressed() -> void:
	if _win:
		return
	_win_soup(true)


## 摊牌时给「衣柜」上色（RichTextLabel 的 bbcode；make_rich 已经 bbcode_enabled = true）。
## 常量本身保持纯文本，上色在这里现做，别去改常量。
func _answer_bbcode() -> String:
	return SOUP_ANSWER.replace("衣柜", "[color=#c8564f]衣柜[/color]")


# ---------------------------------------------------------------- 附录5 的氛围道具
## 床边的小东西：两个按钮，点开各给一段描述。跟解谜完全无关，纯氛围。
func _build_ambient(parent: Control) -> void:
	var card := PanelContainer.new()
	card.name = "AmbientCard"
	card.add_theme_stylebox_override("panel", PreludeUI.panel_skin(PreludeUI.C_CARD_BG, Color(0.85, 0.80, 0.70, 0.16), 4))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(card)

	var col := VBoxContainer.new()
	col.name = "AmbientColumn"
	col.add_theme_constant_override("separation", 6)
	card.add_child(col)

	col.add_child(make_text("床边还搁着两件不相干的小东西", PreludeUI.FS_CARD, PreludeUI.C_NAME))
	col.add_child(PreludeUI.hline(0.0, Color(0.85, 0.80, 0.70, 0.12)))

	var row := HBoxContainer.new()
	row.name = "AmbientRow"
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)

	for i in AMBIENT.size():
		var btn := make_button(str(AMBIENT[i]["name"]))
		btn.name = "Ambient%d" % i
		btn.add_theme_font_size_override("font_size", PreludeUI.FS_TIP)
		btn.pressed.connect(_on_ambient_pressed.bind(i))
		row.add_child(btn)
		_ambient_buttons.append(btn)

	_ambient_text = make_rich("（点一下看看。）", PreludeUI.FS_TEXT)
	_ambient_text.name = "AmbientText"
	col.add_child(_ambient_text)

	# 点开之后在描述下面显示那张道具图（素材是抠好底的道具 PNG）。
	# 【坑 29】这些图从外面拷进来、没有 .import，必须走 PreludeUI.load_texture()。
	_ambient_photo = TextureRect.new()
	_ambient_photo.name = "AmbientPhoto"
	_ambient_photo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_ambient_photo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_ambient_photo.custom_minimum_size = Vector2(340.0, 104.0)
	_ambient_photo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_ambient_photo.visible = false
	col.add_child(_ambient_photo)


func _on_ambient_pressed(index: int) -> void:
	if index < 0 or index >= AMBIENT.size() or _ambient_text == null:
		return
	_ambient_text.text = str(AMBIENT[index]["text"])
	if _ambient_photo != null:
		var tex := PreludeUI.load_texture(str(AMBIENT[index].get("image", "")))
		if tex != null:
			_ambient_photo.texture = tex
			_ambient_photo.visible = true
	if _ambient_seen.has(index):
		return
	_ambient_seen[index] = true
	var btn := _ambient_buttons[index] as Button
	if btn != null:
		btn.text = "%s · 看过了" % str(AMBIENT[index]["name"])


# ---------------------------------------------------------------- 过关
## given_up = true 是"不想了，直接看汤底"那条路：一样算过关、一样摊汤底卡，
## 只是结果里带 given_up（运行时/剧本想知道玩家是怎么过来的）。
func _win_soup(given_up := false) -> void:
	if _win:
		return
	_win = true
	_given_up = given_up
	for b in _question_buttons:
		b.disabled = true
	if _give_up_btn != null:
		_give_up_btn.disabled = true
	for w in _word_buttons.keys():
		var btn := _word_buttons[w] as Button
		if btn:
			btn.disabled = true
	if _feedback:
		_feedback.add_theme_color_override("font_color", PreludeUI.C_NAME)
		_feedback.text = "行，汤底摊开给你看。" if given_up else "对上了。"

	# 汤底直接摊开在答录下面（这里再塞一块卡片，滚动到底就能看见）
	if _answer_log and _answer_log.get_parent() is Control:
		var host := _answer_log.get_parent() as Control
		var lid := PanelContainer.new()
		lid.name = "SoupLid"
		lid.add_theme_stylebox_override("panel", PreludeUI.panel_skin(Color(0.12, 0.10, 0.10, 0.94), Color(0.70, 0.34, 0.32, 0.55), 4))
		lid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		host.add_child(lid)

		var col := VBoxContainer.new()
		col.name = "SoupLidColumn"
		col.add_theme_constant_override("separation", 8)
		lid.add_child(col)

		col.add_child(make_text("汤底", PreludeUI.FS_CARD, PreludeUI.C_NAME))
		# 附录4 第 27 行：「出现完整汤底后，衣柜一词标红」
		var rich := make_rich(_answer_bbcode(), PreludeUI.FS_TEXT)
		rich.name = "SoupAnswer"
		col.add_child(rich)

		var ok := make_button("……原来是这样。", true)
		ok.name = "SoupDone"
		ok.size_flags_horizontal = Control.SIZE_SHRINK_END
		ok.pressed.connect(_do_close)
		col.add_child(ok)


func _do_close() -> void:
	if not _win:
		return
	var words: Array = []
	words.assign(ANSWER_WORDS)
	close_panel({"ok": true, "words": words, "given_up": _given_up})
