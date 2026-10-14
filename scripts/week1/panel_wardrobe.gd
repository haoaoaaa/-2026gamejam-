extends "res://scripts/week1/panel_base.gd"
## ============================================================================
##  《寻星》一周目 —— 第 6 关 · 衣柜与密码盒
## ============================================================================
##  四屏一路往下走，选错只给一行反馈，不倒退：
##    ① 手绘的衣柜：柜门敞着、横杆上**从左往右挂着四件**衣服
##       → 点某一件 → 弹出这件衣服的**主视图**（摊平的外套正面）
##    ② 主视图上的三个口袋  → 左袋在左侧中下部、右上袋在右上、右下袋在右下
##       → 只有「从左往右第三件」**红外套**上的**右上袋**是对的
##       （文档原话：「对应衣柜里从左往右第三件红衣服」；
##         《问题》第 11 条：「衣柜里红色衣服应该出现在从左往右数第三个，
##         口袋应分为左袋、右上袋、右下袋，不然第4关的线索无效」
##         —— 第 4 关的「红 + 三 + 二」＝左起第三件红衣服上的第二个口袋，
##         那个口袋落在衣服的右上，所以三个口袋必须按"左 / 右上 / 右下"摆） 
##    ③ 右上袋里摸出一只六位密码盒 → 输入 053714
##    ④ 盒子开了，里面是装满手折纸星星的玻璃瓶
##
##  过关：close_panel({"ok": true, "code": "053714"})
##
##  注意：本文件只依赖 panel_base.gd 与 PreludeUI，不读 json、不切场景。
##
##  ---------------------------------------------------------------- 改版记要
##  【第 ① 屏的"文字重叠"是怎么修的 —— 别再改回去】
##  旧版第 ① 屏是「四张按钮卡片（色块 + 名字）」，名字是 Label，还是
##  `AUTOWRAP_WORD_SMART` 的 Label（make_text 默认就开自动换行），塞在
##  `MarginContainer → HBoxContainer` 里、跟着一整列 VBoxContainer 一起排版。
##  这条链上有两个雷：
##    · 固定的 ScreenHost 只有 268px 高，而那一列内容的**最小高度**是 279px
##      （见面板容器实测：Label 27 + 4×48 卡片 + 7×8 间距 + 尾巴 20），
##      最小高度一超，VBoxContainer 就压不动子节点、只能溢出，文字就顶到下一块上；
##    · 自动换行的 Label 的宽度要靠字体度量算，一旦容器把宽度压小（或字号/字体
##      一换），同一块区域里的两行文字就会各自回绕、互相压住 —— 窗口里才看得见。
##  现在第 ① 屏**没有任何 Label / Button 参与排版**：整面柜子画在一张固定尺寸的
##  子画布 `WardrobeCanvas` 上，连衣服名字都用 draw_string 画。
##  布局驱动的东西一撤，重叠的可能性从"布局问题"变成"我自己没画开"，
##  所以顺带留了两件东西兜底：
##    · `ui_text_rects()`：把手绘文字的矩形报出来，探针拿它跟所有可见
##      文字节点两两求交（tools/probe_week1.gd 里的"第①屏文字不重叠"那条）；
##    · 每个名字都算好格子（下面 CAPTION/CAPTION_H 那一组常量），
##      字号和格子宽度是配套的，改字号就得回头看 `_draw_names` 的排布。
##
##  【为什么第 ② 屏也不再是按钮列表】
##  玩家要的是"点衣服 → 弹主视图 → 在主视图上摸口袋"。主视图里的三个口袋
##  是画在衣服上的（不是排成一列的按钮），位置由 COAT_POCKETS 一组常量钉死：
##  左袋在左袖与前襟之间、偏下；右上袋在右侧偏上；右下袋在右侧偏下。
##  画口袋和点口袋用的是**同一个矩形**（_draw_pocket 直接读 COAT_POCKETS），
##  这样"看着在哪"和"点到哪"永远不会对不上。
##
##  【弹窗怎么压在面板上】覆盖层 `_detail` 是**面板根节点的子节点**，
##  在基类 _build_chrome() 之后建，所以压在整个面板之上（同 panel_desk 的做法）；
##  mouse_filter = STOP，玩家点不到底下的柜子。点错口袋不关窗、不倒退，
##  只把弹窗里那行反馈换掉，可以接着点。
## ============================================================================

## 密码盒的密码
const CODE := "053714"
## 错到第几次开始点"九本书"
const REVEAL_AT := 3
## 密码位数（密码盒上六个数字格）
const CODE_LEN := 6

## 衣柜里挂着的四件衣服：名字 → 颜色（画在柜子里的衣服就用这个色），以及不对时给出的反馈
## 【文档口径】《4、5关具体解谜》：「对应衣柜里**从左往右第三件红衣服**」
##   → 答案是左起第三件、且必须是红的（CLOTHES[2]）
## 【pockets 这个字段是干什么的】主视图（点了衣服弹出来的那一屏）按**被点的这一件**画：
##   `pockets = true` 的三件画成"摊平的外套 + 三个口袋"，围巾画成围巾、没有口袋。
##   旧版主视图写死按红外套画，所以点围巾也会看到一件外套（Kerry 报的 bug，别再写死）。
const CLOTHES: Array[Dictionary] = [
	{"name": "深色卫衣", "color": Color(0.22, 0.23, 0.28), "right": false, "pockets": true, "tip": "口袋里是空的。"},
	{"name": "校服外套", "color": Color(0.28, 0.31, 0.40), "right": false, "pockets": true, "tip": "只有一条旧发绳。"},
	{"name": "红色外套", "color": Color(0.62, 0.24, 0.26), "right": true, "pockets": true, "tip": ""},
	{"name": "围巾", "color": Color(0.42, 0.40, 0.34), "right": false, "pockets": false, "tip": "什么也没有。"},
]

## 外套上的三个口袋（下标 = POCKETS 的下标，也是 _on_pocket_pressed 的入参）。
## 【文档口径】《问题》第 11 条：「衣柜里红色衣服应该出现在从左往右数第三个，
##   口袋应分为左袋、右上袋、右下袋，不然第4关的线索无效」
##   → 只有「右上袋」（POCKETS[1]）是对的：第 4 关的「红 + 三 + 二」＝
##     左起第三件红衣服 + 衣服上数的第二个口袋，那一个口袋就落在衣服的右上。
##   所以画面上必须摆成"左 / 右上 / 右下"，不能竖着排成"上/中/下"一列。
const POCKETS: Array[String] = ["左袋", "右上袋", "右下袋"]

# ---------------------------------------------------------------- ① 画面尺寸
## 第 ① 屏那张画布的尺寸。
## 【硬约束】它必须 ≤ 旧版 ScreenHost 的 268（这里取 266），否则整块 ScreenHost
##   的最小高度会被顶到 300+，底下的 hline 与反馈行又回到"被顶出去"的老路。
const CANVAS_W := 840.0
const CANVAS_H := 266.0

## 柜体（外框 = 柜门）在画布里的位置；柜子里那圈暗色是背景板
const CABINET := Rect2(14.0, 6.0, 812.0, 254.0)
## 柜体厚度：外框画粗一点，看着像柜门
const CABINET_EDGE := 6.0
## 挂衣杆（横杆）在画布里的 y，以及两端伸出柜体的长度
const ROD_Y := 56.0
const ROD_X0 := 40.0
const ROD_X1 := 800.0
## 一件衣服占的格子：横向排开四件，格子等宽、等距
const CLOTH_W := 168.0
const CLOTH_GAP := 46.0
const CLOTH_TOP := 62.0
## 衣服下摆的 y（四件共用；围巾会自己收短）
const CLOTH_HEM := 230.0
## 衣服下面那行"第 N 件 · 名字"的格子：CAPTION_H 是格子高，字号必须配得上它
const CAPTION_Y := 234.0
const CAPTION_H := 26.0
## 手绘文字的默认字号（名字 / 数字用小一号）
const FS_DRAW := 16
const FS_DRAW_SMALL := 13

# ---------------------------------------------------------------- ② 主视图尺寸
## 弹窗里那张"摊平的外套正面"画布的尺寸
const COAT_W := 420.0
const COAT_H := 350.0
## 主视图里外套本体的关键坐标（衣服左右对称，中心 = COAT_W / 2）
const COAT_CENTER_X := 210.0
const COAT_SHOULDER_Y := 66.0
const COAT_NECK_X := 32.0
const COAT_WAIST_Y := 244.0
const COAT_HEM_Y := 302.0
## 两个袖子：外缘从肩点往外下走，袖口在这里收住
const COAT_SLEEVE_OUT := 84.0
const COAT_CUFF_OUT := 62.0
const COAT_CUFF_IN := 42.0
const COAT_CUFF_Y := 210.0

## 三个口袋在**主视图画布**里的矩形。
## 【为什么是这三个位置】"左袋 / 右上袋 / 右下袋"是文档钉死的说法，
##   所以左袋必须落在左半边的中下部、右上袋落在右上、右下袋落在右下，
##   三块一眼能分出"哪边、哪一格"，不能竖成一列。
##   【坑】这三个矩形同时是**命中区**（_on_coat_input 直接读它），
##   画口袋（_draw_coat）也读它 —— 改位置只改这一处，别在别处再写一套坐标。
const COAT_POCKETS: Array[Rect2] = [
	Rect2(28.0, 176.0, 78.0, 60.0),    # 左袋：左侧、中下部
	Rect2(314.0, 136.0, 78.0, 56.0),   # 右上袋：右侧偏上（正确答案）
	Rect2(314.0, 210.0, 78.0, 56.0),   # 右下袋：右侧偏下
]
## 主视图里名字/说明的行高（手绘）
const COAT_LABEL_Y := 22.0
## 弹窗卡片的尺寸（PanelContainer 的最小尺寸，居中摆放）
const DETAIL_W := 520.0
const DETAIL_H := 486.0

# ---------------------------------------------------------------- ① 颜色
const C_CABINET := Color(0.26, 0.20, 0.15)        # 柜门外框（深木色）
const C_CABINET_HI := Color(0.36, 0.28, 0.21)     # 柜门受光的那一侧
const C_CABINET_IN := Color(0.075, 0.078, 0.09)   # 柜子里面（暗）
const C_ROD := Color(0.55, 0.52, 0.46)            # 挂衣杆
const C_HANGER := Color(0.72, 0.70, 0.64)         # 衣架钩
const C_HEM_SHADOW := Color(0.0, 0.0, 0.0, 0.22)  # 衣服下摆的投影
const C_TEXT := Color(0.93, 0.91, 0.86)
const C_TEXT_DIM := Color(0.62, 0.60, 0.56)
const C_RIGHT := Color(0.96, 0.80, 0.55)          # 强调（暖黄）
const C_POCKET_LINE := Color(0.93, 0.91, 0.86, 0.55)
const C_POCKET_HOVER := Color(0.98, 0.90, 0.62, 0.95)
const C_HOVER := Color(0.98, 0.88, 0.58)          # 鼠标悬停的那件衣服

var _screen_index := 0                 # 当前是第几屏（0 起）
var _wrong_code := 0                   # 密码错了几次
var _won := false                      # 已过关，屏蔽后续输入

var _screens: Array[Control] = []      # 四屏的容器，一次全建好，只切 visible
var _screen_host: Control = null       # 四屏的共同父级（固定高度，画面不跳）
var _feedback: Label = null            # 底部那行反馈

var _code_input: LineEdit = null
var _code_confirm: Button = null
var _digits: Array[Label] = []         # 密码盒上的六个数字格

var _canvas: Control = null            # 第 ① 屏那张手绘衣柜
var _cloth_cols: Array[Rect2] = []     # 四件衣服各自的格子（= 点击命中区）
var _hover_cloth := -1                 # 鼠标悬停在哪件衣服上（-1 = 没有）
var _text_rects: Array[Rect2] = []     # 手绘文字的矩形（画布局部坐标），调试/探针用

var _detail: Control = null            # 弹窗覆盖层（挂在面板根节点上）
var _detail_canvas: Control = null     # 弹窗里那张"摊平的外套"
var _detail_title: Label = null
var _detail_feedback: Label = null
var _pick := -1                        # 当前打开的是第几件衣服（-1 = 没开）
var _hover_pocket := -1                # 鼠标悬停在主视图的哪个口袋上（-1 = 没有）


# ---------------------------------------------------------------- 覆盖点
func panel_title() -> String:
	return "衣柜"


func panel_hint() -> String:
	return "点一件衣服，翻它的口袋"


func build_body(body: VBoxContainer) -> void:
	# 四屏共用一块固定高度的台面：换屏时面板不会忽高忽低。
	# 【尺寸账】266（画布）+ 8（间距）+ 1（分隔线）+ 8（间距）+ 34（反馈行）= 317，
	# 小于面板正文的 394 —— 这条链上任何一处变高都要重新核这 317。
	_screen_host = VBoxContainer.new()
	_screen_host.name = "ScreenHost"
	_screen_host.custom_minimum_size = Vector2(0, CANVAS_H)
	_screen_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_screen_host.add_theme_constant_override("separation", 0)
	body.add_child(_screen_host)

	_cloth_cols = _cloth_columns()

	_screens.append(_build_clothes_screen())
	_screens.append(_build_pockets_screen())
	_screens.append(_build_code_screen())
	_screens.append(_build_reveal_screen())
	for s in _screens:
		s.visible = false
		_screen_host.add_child(s)
	_screens[0].visible = true

	# 弹窗覆盖层：在基类的 PanelFrame 之后 add_child，所以压在整个面板之上
	_build_detail_layer()

	body.add_child(PreludeUI.hline(0.0, Color(0.85, 0.80, 0.70, 0.16)))
	_feedback = make_text("点一件衣服，翻翻它的口袋。", PreludeUI.FS_TEXT, PreludeUI.C_INK_DIM)
	# 【坑】自动换行的 Label 宽度要靠字体度量算，容器不给宽度时它只剩 1px 宽、
	# 于是两个字就回绕成几百像素高（实测过）。这里干脆把宽度钉死，
	# 免得它去跟上面的画布抢最小高度。
	_feedback.custom_minimum_size = Vector2(CANVAS_W, 34)
	_feedback.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(_feedback)


## 换屏：只改 visible，不销毁节点——已经给过的反馈留在 _feedback 上
func _show_screen(index: int) -> void:
	if index < 0 or index >= _screens.size():
		return
	for i in _screens.size():
		_screens[i].visible = i == index
	_screen_index = index
	# 弹窗跟着换屏关掉（点对了口袋那一刻，主视图就该收起来）
	if index != 0 and _detail != null and _detail.visible:
		_detail.visible = false
	# 【手感】切到密码那一屏（第 3 屏）时把光标放进输入框：
	# 不然玩家直接敲键盘是"没反应"的（LineEdit 要先被点一下才拿到焦点）。
	if index == 2 and _code_input != null:
		_code_input.call_deferred("grab_focus")


func _set_feedback(text: String, accent := false) -> void:
	if _feedback == null:
		return
	_feedback.text = text
	_feedback.add_theme_color_override("font_color", PreludeUI.C_ACCENT if accent else PreludeUI.C_INK_DIM)


# ---------------------------------------------------------------- ① 手绘衣柜
## 一件衣服在画布里的格子：四件等宽等距、横向排开，
## 所以第一个格子的左边 = 剩下的空当一半（柜体左右各有等宽留白）。
func _cloth_columns() -> Array[Rect2]:
	var inner := CABINET.position.x + CABINET_EDGE
	var inner_w := CABINET.size.x - CABINET_EDGE * 2.0
	var total := CLOTH_W * float(CLOTHES.size()) + CLOTH_GAP * float(CLOTHES.size() - 1)
	var x0 := inner + (inner_w - total) * 0.5
	var out: Array[Rect2] = []
	for i in CLOTHES.size():
		out.append(Rect2(x0 + float(i) * (CLOTH_W + CLOTH_GAP),
				CLOTH_TOP, CLOTH_W, CLOTH_HEM - CLOTH_TOP + CAPTION_H + 8.0))
	return out


func _build_clothes_screen() -> Control:
	# 外面再套一层 VBoxContainer，是为了和另外三屏的节点形状保持一致
	# （ScreenClothes 是屏容器），屏里就只有一个固定尺寸的画布。
	var box := VBoxContainer.new()
	box.name = "ScreenClothes"
	box.add_theme_constant_override("separation", 0)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_canvas = Control.new()
	_canvas.name = "WardrobeCanvas"
	_canvas.custom_minimum_size = Vector2(CANVAS_W, CANVAS_H)
	_canvas.size = Vector2(CANVAS_W, CANVAS_H)
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	# 【坑 48】画图要画在**子 Control 的 draw 信号**里，不要覆盖面板自己的 _draw：
	# 基类的压暗层是兄弟节点，会把面板根节点上画的东西整个盖住
	# （panel_desk.gd:35 / panel_maze.gd:39 / panel_slant.gd:11 都记过同一件事）。
	_canvas.draw.connect(_draw_wardrobe)
	_canvas.gui_input.connect(_on_canvas_input)
	_canvas.mouse_exited.connect(func() -> void:
		if _hover_cloth != -1:
			_hover_cloth = -1
			_canvas.queue_redraw())
	box.add_child(_canvas)
	return box


## 手绘整个衣柜：柜门 → 里面 → 挂衣杆 → 四件衣服 → 每件下面一行名字
func _draw_wardrobe() -> void:
	_text_rects.clear()
	if _canvas == null:
		return
	_draw_cabinet()
	# 先画杆，再画衣服：衣服从杆前面垂下来，钩子压在杆上
	_canvas.draw_line(Vector2(ROD_X0, ROD_Y), Vector2(ROD_X1, ROD_Y), C_ROD, 5.0)
	for i in CLOTHES.size():
		_draw_hanger(_cloth_cols[i])
		_draw_piece(_cloth_cols[i], i)
	# 名字最后画，压在留白的格子里（不与衣服重叠）
	for i in CLOTHES.size():
		_draw_names(_cloth_cols[i], i)


## 柜体：外框是柜门（深木色），里面是暗色的柜子内部
func _draw_cabinet() -> void:
	_canvas.draw_rect(CABINET, C_CABINET, true)
	_canvas.draw_rect(CABINET, C_CABINET_HI, false, 2.0)
	var cavity := Rect2(CABINET.position.x + CABINET_EDGE, CABINET.position.y + CABINET_EDGE,
			CABINET.size.x - CABINET_EDGE * 2.0, CABINET.size.y - CABINET_EDGE * 2.0)
	_canvas.draw_rect(cavity, C_CABINET_IN, true)
	# 柜门的合页：画在柜体两侧，让外框一眼看出是"门"
	for side in [CABINET.position.x + 3.0, CABINET.end.x - 3.0]:
		for y in [CABINET.position.y + 30.0, CABINET.end.y - 46.0]:
			_canvas.draw_rect(Rect2(side - 3.0, y, 6.0, 16.0), C_CABINET_HI, true)
	# 挂衣杆的两头：小小一块托板
	_canvas.draw_rect(Rect2(ROD_X0 - 8.0, ROD_Y - 7.0, 8.0, 14.0), C_CABINET_HI, true)
	_canvas.draw_rect(Rect2(ROD_X1, ROD_Y - 7.0, 8.0, 14.0), C_CABINET_HI, true)


## 衣架：一个倒 V 的钩子挂在横杆上
func _draw_hanger(col: Rect2) -> void:
	var cx := col.position.x + col.size.x * 0.5
	_canvas.draw_line(Vector2(cx, ROD_Y), Vector2(cx, ROD_Y + 10.0), C_HANGER, 2.0)
	_canvas.draw_arc(Vector2(cx, ROD_Y - 1.0), 5.0, PI, TAU, 12, C_HANGER, 2.0)


## 四件衣服各画各的形状，一眼能分清；鼠标悬停的那件镶一道亮边
func _draw_piece(col: Rect2, index: int) -> void:
	match index:
		0:
			_draw_hoodie(col)
		1:
			_draw_uniform(col)
		2:
			_draw_red_coat(col)
		_:
			_draw_scarf(col)
	if index == _hover_cloth:
		_canvas.draw_rect(Rect2(col.position.x, CLOTH_TOP - 4.0, col.size.x, CLOTH_HEM - CLOTH_TOP + 8.0),
				C_HOVER, false, 2.0)


## 一件上衣的通用剪影（肩 / 袖 / 身 / 下摆），四个部件都照这个骨架长
func _jacket_pts(cx: float, shoulder_y: float, hem_y: float, shoulder_x: float, hem_x: float) -> Dictionary:
	var body := PackedVector2Array([
		Vector2(cx - shoulder_x, shoulder_y),
		Vector2(cx + shoulder_x, shoulder_y),
		Vector2(cx + shoulder_x + 4.0, hem_y - 6.0),
		Vector2(cx + hem_x, hem_y),
		Vector2(cx - hem_x, hem_y),
		Vector2(cx - shoulder_x - 4.0, hem_y - 6.0),
	])
	var elbow_x := shoulder_x + 8.0
	var sleeve_r := PackedVector2Array([
		Vector2(cx + shoulder_x, shoulder_y - 10.0),
		Vector2(cx + shoulder_x + 30.0, shoulder_y + 8.0),
		Vector2(cx + shoulder_x + 26.0, shoulder_y + 62.0),
		Vector2(cx + shoulder_x - 2.0, shoulder_y + 56.0),
	])
	var sleeve_l := PackedVector2Array([
		Vector2(cx - shoulder_x + 2.0, shoulder_y + 56.0),
		Vector2(cx - shoulder_x - 26.0, shoulder_y + 62.0),
		Vector2(cx - shoulder_x - 30.0, shoulder_y + 8.0),
		Vector2(cx - shoulder_x, shoulder_y - 10.0),
	])
	return {"body": body, "sleeve_l": sleeve_l, "sleeve_r": sleeve_r, "elbow": elbow_x}


## 深色卫衣：带帽、前面一个大口袋，帽子是肩上一道弧
func _draw_hoodie(col: Rect2) -> void:
	var cx := col.position.x + col.size.x * 0.5
	var item := CLOTHES[0]
	var g := _jacket_pts(cx, CLOTH_TOP + 6.0, CLOTH_HEM, 52.0, 56.0)
	var col_c: Color = item["color"]
	_canvas.draw_colored_polygon(g["sleeve_l"], col_c.darkened(0.14))
	_canvas.draw_colored_polygon(g["sleeve_r"], col_c.darkened(0.14))
	_canvas.draw_colored_polygon(g["body"], col_c)
	# 帽子：颈口那一圈
	_canvas.draw_arc(Vector2(cx, CLOTH_TOP + 10.0), 30.0, PI * 0.15, PI * 0.85, 20, col_c.darkened(0.30), 4.0)
	# 帽绳
	_canvas.draw_line(Vector2(cx - 10.0, CLOTH_TOP + 22.0), Vector2(cx - 12.0, CLOTH_TOP + 46.0), C_TEXT_DIM, 1.5)
	_canvas.draw_line(Vector2(cx + 10.0, CLOTH_TOP + 22.0), Vector2(cx + 12.0, CLOTH_TOP + 46.0), C_TEXT_DIM, 1.5)
	# 前面的口袋
	_canvas.draw_rect(Rect2(cx - 34.0, CLOTH_HEM - 44.0, 68.0, 32.0), col_c.darkened(0.24), true)
	_canvas.draw_rect(Rect2(cx - 34.0, CLOTH_HEM - 44.0, 68.0, 32.0), C_HEM_SHADOW, false, 1.0)
	_finish_piece(g, col_c)


## 校服外套：翻领 + 一排扣子，肩线压一道深色
func _draw_uniform(col: Rect2) -> void:
	var cx := col.position.x + col.size.x * 0.5
	var item := CLOTHES[1]
	var g := _jacket_pts(cx, CLOTH_TOP + 4.0, CLOTH_HEM, 56.0, 52.0)
	var col_c: Color = item["color"]
	_canvas.draw_colored_polygon(g["sleeve_l"], col_c.darkened(0.10))
	_canvas.draw_colored_polygon(g["sleeve_r"], col_c.darkened(0.10))
	_canvas.draw_colored_polygon(g["body"], col_c)
	# 翻领：两条斜线从颈口甩到胸前
	var neck_l := Vector2(cx - 22.0, CLOTH_TOP + 8.0)
	var neck_r := Vector2(cx + 22.0, CLOTH_TOP + 8.0)
	var tip := Vector2(cx, CLOTH_TOP + 58.0)
	_canvas.draw_colored_polygon(PackedVector2Array([neck_l, tip, neck_l + Vector2(-10.0, 30.0)]), col_c.lightened(0.16))
	_canvas.draw_colored_polygon(PackedVector2Array([neck_r, tip, neck_r + Vector2(10.0, 30.0)]), col_c.lightened(0.16))
	# 门襟 + 扣子
	_canvas.draw_line(Vector2(cx, CLOTH_TOP + 58.0), Vector2(cx, CLOTH_HEM - 6.0), col_c.darkened(0.34), 1.5)
	for k in 3:
		_canvas.draw_circle(Vector2(cx + 12.0, CLOTH_TOP + 74.0 + float(k) * 26.0), 3.0, C_TEXT_DIM)
	_finish_piece(g, col_c)


## 红色外套：答案那件。兜底画得比另外两件讲究一点（腰带 + 两个缝线口袋）
func _draw_red_coat(col: Rect2) -> void:
	var cx := col.position.x + col.size.x * 0.5
	var item := CLOTHES[2]
	var g := _jacket_pts(cx, CLOTH_TOP + 4.0, CLOTH_HEM, 58.0, 58.0)
	var col_c: Color = item["color"]
	_canvas.draw_colored_polygon(g["sleeve_l"], col_c.darkened(0.12))
	_canvas.draw_colored_polygon(g["sleeve_r"], col_c.darkened(0.12))
	_canvas.draw_colored_polygon(g["body"], col_c)
	# 腰带：横向一条，中间一个金属扣
	_canvas.draw_rect(Rect2(cx - 54.0, CLOTH_TOP + 104.0, 108.0, 12.0), col_c.darkened(0.34), true)
	_canvas.draw_rect(Rect2(cx - 7.0, CLOTH_TOP + 102.0, 14.0, 16.0), C_TEXT_DIM, true)
	# 两个缝线口袋（只是线条，碰到它们不算"摸口袋"——真正的口袋在主视图里）
	_canvas.draw_line(Vector2(cx - 40.0, CLOTH_TOP + 130.0), Vector2(cx - 40.0, CLOTH_TOP + 154.0), col_c.darkened(0.40), 1.5)
	_canvas.draw_line(Vector2(cx + 40.0, CLOTH_TOP + 130.0), Vector2(cx + 40.0, CLOTH_TOP + 154.0), col_c.darkened(0.40), 1.5)
	# 翻领（和校服一样的结构，但用亮一档的红）
	var neck_l := Vector2(cx - 24.0, CLOTH_TOP + 8.0)
	var neck_r := Vector2(cx + 24.0, CLOTH_TOP + 8.0)
	var tip := Vector2(cx, CLOTH_TOP + 62.0)
	_canvas.draw_colored_polygon(PackedVector2Array([neck_l, tip, neck_l + Vector2(-11.0, 32.0)]), col_c.lightened(0.20))
	_canvas.draw_colored_polygon(PackedVector2Array([neck_r, tip, neck_r + Vector2(11.0, 32.0)]), col_c.lightened(0.20))
	_canvas.draw_line(Vector2(cx, CLOTH_TOP + 62.0), Vector2(cx, CLOTH_HEM - 6.0), col_c.darkened(0.38), 2.0)
	_finish_piece(g, col_c)


## 围巾：不是外套，是一条绕在杆上的长围巾（形状故意不一样）
func _draw_scarf(col: Rect2) -> void:
	var cx := col.position.x + col.size.x * 0.5
	var item := CLOTHES[3]
	var col_c: Color = item["color"]
	var top := CLOTH_TOP + 12.0
	# 绕在杆上的那一圈
	_canvas.draw_rect(Rect2(cx - 44.0, top, 88.0, 34.0), col_c, true)
	_canvas.draw_rect(Rect2(cx - 44.0, top, 88.0, 34.0), col_c.darkened(0.30), false, 2.0)
	# 两条垂下来的穗子
	_canvas.draw_rect(Rect2(cx - 40.0, top + 34.0, 34.0, CLOTH_HEM - top - 34.0), col_c.darkened(0.10), true)
	_canvas.draw_rect(Rect2(cx + 8.0, top + 34.0, 32.0, CLOTH_HEM - top - 46.0), col_c.darkened(0.18), true)
	# 穗子末端的流苏
	for k in 4:
		var x := cx - 38.0 + float(k) * 9.0
		_canvas.draw_line(Vector2(x, CLOTH_HEM - 4.0), Vector2(x, CLOTH_HEM + 8.0), col_c.lightened(0.12), 2.0)
	for k in 4:
		var x := cx + 10.0 + float(k) * 8.0
		_canvas.draw_line(Vector2(x, CLOTH_HEM - 16.0), Vector2(x, CLOTH_HEM - 4.0), col_c.lightened(0.12), 2.0)


## 一件上衣都有的收尾：袖口/下摆的暗边 + 整体轮廓
func _finish_piece(g: Dictionary, col_c: Color) -> void:
	var edge := col_c.darkened(0.45)
	_canvas.draw_polyline(g["body"], edge, 2.0, true)
	_canvas.draw_polyline(g["sleeve_l"], edge, 2.0, true)
	_canvas.draw_polyline(g["sleeve_r"], edge, 2.0, true)
	var body: PackedVector2Array = g["body"]
	_canvas.draw_line(body[4], body[3], edge, 3.0)


## 衣服下面那行「第 N 件 · 名字」。名字的格子宽度 = CLOTH_W，字号 = FS_DRAW，
## 所以它不会跟左右两件挤在一起；画完把矩形记进 _text_rects 备查。
func _draw_names(col: Rect2, index: int) -> void:
	var item := CLOTHES[index]
	var caption := "第 %d 件 · %s" % [index + 1, str(item["name"])]
	var box := Rect2(col.position.x, CAPTION_Y, col.size.x, CAPTION_H)
	var base_y := CAPTION_Y + CAPTION_H * 0.5 + float(FS_DRAW) * 0.36
	var col_c := C_RIGHT if bool(item["right"]) else C_TEXT_DIM
	_draw_text(caption, Vector2(box.position.x, base_y), FS_DRAW, col_c,
			HORIZONTAL_ALIGNMENT_CENTER, box.size.x)
	_text_rects.append(box)


## 手绘文字的收口：统一字体、统一登记矩形（探针会拿 _text_rects 去两两求交）
func _draw_text(text: String, pos: Vector2, size: int, col: Color,
		align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	_canvas.draw_string(ThemeDB.fallback_font, pos, text, align, width, size, col)


## 第 ① 屏的输入：左键点衣服 → 弹主视图；悬停 → 那件衣服亮一道边
func _on_canvas_input(event: InputEvent) -> void:
	if _won:
		return
	if event is InputEventMouseMotion:
		var m := event as InputEventMouseMotion
		var hit := _cloth_at(m.position)
		if hit != _hover_cloth:
			_hover_cloth = hit
			_canvas.queue_redraw()
		return
	if event is InputEventMouseButton:
		var b := event as InputEventMouseButton
		if b.pressed and b.button_index == MOUSE_BUTTON_LEFT:
			var hit := _cloth_at(b.position)
			if hit >= 0:
				_open_cloth(hit)
				_canvas.accept_event()


## 点在哪个衣服格子里（命中区就是 _cloth_cols，和画出来的格子是同一份）
func _cloth_at(p: Vector2) -> int:
	for i in _cloth_cols.size():
		var c := _cloth_cols[i]
		# 只认"衣服那一段"，不含下面那行名字
		if p.x >= c.position.x and p.x <= c.end.x and p.y >= CLOTH_TOP - 6.0 and p.y <= CLOTH_HEM + 6.0:
			return i
	return -1


# ---------------------------------------------------------------- ② 主视图弹窗
## 弹窗覆盖层：挂在面板根节点上（基类的 PanelFrame 之后 add_child，所以压在面板之上）
func _build_detail_layer() -> void:
	_detail = Control.new()
	_detail.name = "WardrobeDetail"
	_detail.visible = false
	_detail.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_detail)
	_detail.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var dim := ColorRect.new()
	dim.name = "DetailDim"
	dim.color = Color(0.02, 0.02, 0.03, 0.72)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var card := PanelContainer.new()
	card.name = "DetailCard"
	card.add_theme_stylebox_override("panel", PreludeUI.panel_skin(PreludeUI.C_PANEL_HI, PreludeUI.C_LINE, 8))
	card.custom_minimum_size = Vector2(DETAIL_W, DETAIL_H)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	_detail.add_child(card)
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	card.offset_left = -DETAIL_W * 0.5
	card.offset_right = DETAIL_W * 0.5
	card.offset_top = -DETAIL_H * 0.5
	card.offset_bottom = DETAIL_H * 0.5

	var margin := MarginContainer.new()
	margin.name = "DetailMargin"
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	card.add_child(margin)

	var col := VBoxContainer.new()
	col.name = "DetailColumn"
	col.add_theme_constant_override("separation", 8)
	margin.add_child(col)

	_detail_title = make_text("", PreludeUI.FS_NAME, PreludeUI.C_NAME)
	_detail_title.name = "DetailTitle"
	# 【坑】make_text 默认开自动换行：不给宽度它就只有 1px 宽、然后回绕成一柱长条。
	# 这里把宽度钉成卡片内宽，行数才不会失控。
	_detail_title.custom_minimum_size = Vector2(DETAIL_W - 40.0, 31)
	col.add_child(_detail_title)
	col.add_child(PreludeUI.hline(DETAIL_W - 40.0, PreludeUI.C_LINE))

	# 主视图画布：外套正面 + 三个口袋都画在这里，点击也跟着它走
	_detail_canvas = Control.new()
	_detail_canvas.name = "CoatCanvas"
	_detail_canvas.custom_minimum_size = Vector2(COAT_W, COAT_H)
	_detail_canvas.size = Vector2(COAT_W, COAT_H)
	_detail_canvas.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_detail_canvas.draw.connect(_draw_coat_view)
	_detail_canvas.gui_input.connect(_on_coat_input)
	_detail_canvas.mouse_exited.connect(func() -> void:
		if _hover_pocket != -1:
			_hover_pocket = -1
			_detail_canvas.queue_redraw())
	var center := CenterContainer.new()
	center.name = "CoatCenter"
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.add_child(_detail_canvas)
	col.add_child(center)

	_detail_feedback = make_text("手指按在哪儿，口袋就在哪儿。", PreludeUI.FS_TIP, PreludeUI.C_INK_DIM)
	_detail_feedback.name = "DetailFeedback"
	_detail_feedback.custom_minimum_size = Vector2(DETAIL_W - 40.0, 40)
	col.add_child(_detail_feedback)

	var btns := HBoxContainer.new()
	btns.name = "DetailButtons"
	btns.alignment = BoxContainer.ALIGNMENT_END
	col.add_child(btns)
	var back := make_button("退开")
	back.name = "DetailClose"
	back.pressed.connect(_close_detail)
	btns.add_child(back)


## 点开某件衣服：把主视图的标题与反馈换成这件衣服的口径
func _open_cloth(index: int) -> void:
	if _won or _screen_index != 0:
		return
	# 【坑】命中区（_cloth_cols）和衣服表（CLOTHES）是两份数据，
	# 将来谁多挂一件衣服就会越界，这里挡一手，别让弹窗去读一个不存在的下标。
	if index < 0 or index >= CLOTHES.size():
		return
	_pick = index
	_hover_pocket = -1
	var item := CLOTHES[index]
	# 标题与反馈都按"被点的这一件"说：围巾不叫"摊平的主视图"，也没有三个口袋
	if garment_has_pockets(index):
		_detail_title.text = "%s · 摊平的主视图" % str(item["name"])
		if bool(item["right"]):
			_detail_feedback.text = "里衬很厚。三个口袋：左袋、右上袋、右下袋。"
		else:
			_detail_feedback.text = "这件也翻过来看看。三个口袋还是那三个。"
	else:
		_detail_title.text = "%s · 摊开" % str(item["name"])
		_detail_feedback.text = "%s摊开了。%s" % [str(item["name"]), str(item["tip"])]
	# 点错衣服不改底部反馈里的"手感"，只在弹窗里说话；底部保留上一次的结果
	_detail_feedback.add_theme_color_override("font_color", PreludeUI.C_INK_DIM)
	_detail.visible = true
	if _detail_canvas != null:
		_detail_canvas.queue_redraw()


func _close_detail() -> void:
	if _detail != null:
		_detail.visible = false
	_pick = -1
	_hover_pocket = -1


## 主视图：**把被点的那一件**摊平画出来。
## 【坑·Kerry 报过】旧版这一屏写死 `var c := Color(0.62, 0.24, 0.26)`（"主视图一律按红外套画"），
##   所以点围巾也会看到一件外套。现在颜色读 `cloth_color(_pick)`、形状读 `garment_has_pockets(_pick)`：
##   三件外套 → `_draw_jacket_view`（外衣 + 三个口袋），围巾 → `_draw_scarf_view`（围巾、没有口袋）。
func _draw_coat_view() -> void:
	if _detail_canvas == null:
		return
	var idx := _pick if _pick >= 0 else 2
	var c := cloth_color(idx)
	var dark := c.darkened(0.40)
	var light := c.lightened(0.16)
	if garment_has_pockets(idx):
		_draw_jacket_view(idx, c, dark, light)
	else:
		_draw_scarf_view(c, dark, light)
	_draw_canvas_head(idx)


## 被点的那一件的颜色（主视图上色用它；探针可以直接问它）
func cloth_color(index: int) -> Color:
	if index < 0 or index >= CLOTHES.size():
		return Color(0.62, 0.24, 0.26)
	return CLOTHES[index]["color"]


## 这件东西上有没有口袋：三件外套有（pockets = true），围巾没有
func garment_has_pockets(index: int) -> bool:
	if index < 0 or index >= CLOTHES.size():
		return true
	return bool(CLOTHES[index].get("pockets", true))


## 主视图顶上那行小字：写着"被点的是哪一件"
func _draw_canvas_head(index: int) -> void:
	var cloth_name := "外套"
	if index >= 0 and index < CLOTHES.size():
		cloth_name = str(CLOTHES[index]["name"])
	_detail_canvas.draw_string(ThemeDB.fallback_font,
			Vector2(0.0, COAT_LABEL_Y - 2.0), "%s · 正面" % cloth_name,
			HORIZONTAL_ALIGNMENT_CENTER, COAT_W, FS_DRAW_SMALL, C_TEXT_DIM)


## 摊平的外衣正面（领口 / 两袖 / 前襟 / 下摆）+ 三个口袋
##   idx 只用来加各自的辨识物：0 深色卫衣加一顶帽子、1 校服外套加一排扣子
func _draw_jacket_view(idx: int, c: Color, dark: Color, light: Color) -> void:
	var cx := COAT_CENTER_X
	var shoulder_x := 62.0
	var hem_x := 84.0

	# —— 连帽卫衣的帽子：肩上那顶"罩子"（先画，下半截会被身子压住）
	# 【为什么不是画一道弧】用粗弧线画出来是一坨盖住肩的色块（试过），
	#   这里改成一块上窄下宽的罩子多边形 + 一道亮边，看得出是帽子又不是"糊了一块"。
	if idx == 0:
		var hood := PackedVector2Array([
			Vector2(cx - 58.0, COAT_SHOULDER_Y + 6.0),
			Vector2(cx - 40.0, COAT_SHOULDER_Y - 32.0),
			Vector2(cx, COAT_SHOULDER_Y - 42.0),
			Vector2(cx + 40.0, COAT_SHOULDER_Y - 32.0),
			Vector2(cx + 58.0, COAT_SHOULDER_Y + 6.0),
		])
		_detail_canvas.draw_colored_polygon(hood, dark)
		_detail_canvas.draw_polyline(hood, light, 2.0, true)

	# —— 两袖（先画，身子压在上面）
	var cuff_l_y := COAT_CUFF_Y
	var arm_l := PackedVector2Array([
		Vector2(cx - shoulder_x, COAT_SHOULDER_Y - 6.0),
		Vector2(cx - COAT_SLEEVE_OUT - 22.0, COAT_SHOULDER_Y + 30.0),
		Vector2(cx - COAT_CUFF_OUT - 18.0, cuff_l_y + 26.0),
		Vector2(cx - COAT_CUFF_IN - 6.0, cuff_l_y + 16.0),
	])
	var arm_r := PackedVector2Array([
		Vector2(cx + COAT_CUFF_IN + 6.0, cuff_l_y + 16.0),
		Vector2(cx + COAT_CUFF_OUT + 18.0, cuff_l_y + 26.0),
		Vector2(cx + COAT_SLEEVE_OUT + 22.0, COAT_SHOULDER_Y + 30.0),
		Vector2(cx + shoulder_x, COAT_SHOULDER_Y - 6.0),
	])
	_detail_canvas.draw_colored_polygon(arm_l, dark)
	_detail_canvas.draw_colored_polygon(arm_r, dark)
	_detail_canvas.draw_polyline(arm_l, dark.darkened(0.35), 2.0, true)
	_detail_canvas.draw_polyline(arm_r, dark.darkened(0.35), 2.0, true)
	# 袖口的收边
	_detail_canvas.draw_line(Vector2(cx - COAT_CUFF_OUT - 18.0, cuff_l_y + 26.0),
			Vector2(cx - COAT_CUFF_IN - 6.0, cuff_l_y + 16.0), light, 3.0)
	_detail_canvas.draw_line(Vector2(cx + COAT_CUFF_IN + 6.0, cuff_l_y + 16.0),
			Vector2(cx + COAT_CUFF_OUT + 18.0, cuff_l_y + 26.0), light, 3.0)

	# —— 身子（肩 → 腰 → 下摆）
	var body := PackedVector2Array([
		Vector2(cx - shoulder_x, COAT_SHOULDER_Y),
		Vector2(cx + shoulder_x, COAT_SHOULDER_Y),
		Vector2(cx + shoulder_x + 6.0, COAT_WAIST_Y),
		Vector2(cx + hem_x, COAT_HEM_Y),
		Vector2(cx - hem_x, COAT_HEM_Y),
		Vector2(cx - shoulder_x - 6.0, COAT_WAIST_Y),
	])
	_detail_canvas.draw_colored_polygon(body, c)
	_detail_canvas.draw_polyline(body, dark, 2.0, true)

	# —— 领口 + 前襟：两片翻领把 V 字领夹出来
	var neck_l := Vector2(cx - COAT_NECK_X, COAT_SHOULDER_Y + 2.0)
	var neck_r := Vector2(cx + COAT_NECK_X, COAT_SHOULDER_Y + 2.0)
	var tip := Vector2(cx, COAT_SHOULDER_Y + 78.0)
	_detail_canvas.draw_colored_polygon(PackedVector2Array([neck_l, tip, neck_l + Vector2(-14.0, 40.0)]), light)
	_detail_canvas.draw_colored_polygon(PackedVector2Array([neck_r, tip, neck_r + Vector2(14.0, 40.0)]), light)
	# 前襟（左右两片的分界）
	_detail_canvas.draw_line(tip, Vector2(cx, COAT_HEM_Y - 6.0), dark, 2.0)
	# 下摆：一道深色收边
	_detail_canvas.draw_line(Vector2(cx - hem_x, COAT_HEM_Y - 4.0), Vector2(cx + hem_x, COAT_HEM_Y - 4.0), dark, 3.0)

	# —— 校服外套的那排扣子（和卫衣、红外套区分开）
	if idx == 1:
		for i in 3:
			_detail_canvas.draw_circle(Vector2(cx, COAT_SHOULDER_Y + 96.0 + float(i) * 44.0), 5.0, light)

	# —— 三个口袋：位置读 COAT_POCKETS（和点击命中区是同一份）
	for i in COAT_POCKETS.size():
		_draw_pocket(i, COAT_POCKETS[i])


## 摊平的围巾：一条长条 + 两段带流苏的下摆，**没有口袋**
## 【为什么单独画】围巾上没有口袋，画成外套会让人以为"这一件也能摸口袋"（Kerry 报的 bug）。
func _draw_scarf_view(c: Color, dark: Color, light: Color) -> void:
	var cx := COAT_CENTER_X
	var half := 54.0
	var top := 44.0
	var split := 282.0                  # 长条分成两段下摆的 y
	var tail_end := 318.0

	# —— 主体：一条从领口垂下来的长条
	_detail_canvas.draw_colored_polygon(PackedVector2Array([
		Vector2(cx - half, top),
		Vector2(cx + half, top),
		Vector2(cx + half, split),
		Vector2(cx - half, split),
	]), c)
	# —— 领口那一段（围巾绕在脖子上的那圈）
	_detail_canvas.draw_rect(Rect2(cx - half, top, half * 2.0, 24.0), light, true)
	_detail_canvas.draw_line(Vector2(cx - half, top + 24.0), Vector2(cx + half, top + 24.0), dark, 2.0)

	# —— 两段下摆：左右各一段，右边稍长，像搭在一起
	var tail_l := PackedVector2Array([
		Vector2(cx - half, split),
		Vector2(cx - 4.0, split),
		Vector2(cx - 4.0, tail_end - 10.0),
		Vector2(cx - half + 3.0, tail_end),
	])
	var tail_r := PackedVector2Array([
		Vector2(cx + 4.0, split),
		Vector2(cx + half, split),
		Vector2(cx + half - 3.0, tail_end),
		Vector2(cx + 4.0, tail_end - 10.0),
	])
	_detail_canvas.draw_colored_polygon(tail_l, c.darkened(0.12))
	_detail_canvas.draw_colored_polygon(tail_r, c)
	_detail_canvas.draw_polyline(tail_l, dark, 2.0, true)
	_detail_canvas.draw_polyline(tail_r, dark, 2.0, true)

	# —— 流苏：两段下摆各五根
	for i in 5:
		var xl := cx - half + 6.0 + float(i) * 10.0
		var xr := cx + 6.0 + float(i) * 10.0
		_detail_canvas.draw_line(Vector2(xl, tail_end - 4.0), Vector2(xl, tail_end + 12.0), dark, 2.0)
		_detail_canvas.draw_line(Vector2(xr, tail_end - 4.0), Vector2(xr, tail_end + 12.0), dark, 2.0)

	# —— 折痕两道 + 横条纹三道：看得出是条针织围巾
	_detail_canvas.draw_line(Vector2(cx - 18.0, top + 30.0), Vector2(cx - 18.0, split - 6.0), dark, 1.5)
	_detail_canvas.draw_line(Vector2(cx + 18.0, top + 30.0), Vector2(cx + 18.0, split - 6.0), dark, 1.5)
	for i in 3:
		var stripe_y := 108.0 + float(i) * 62.0
		_detail_canvas.draw_line(Vector2(cx - half + 3.0, stripe_y), Vector2(cx + half - 3.0, stripe_y), light, 8.0)

	# —— 两条侧边
	_detail_canvas.draw_line(Vector2(cx - half, top), Vector2(cx - half, split), dark, 2.0)
	_detail_canvas.draw_line(Vector2(cx + half, top), Vector2(cx + half, split), dark, 2.0)


## 一个口袋：布片 + 缝线 + 袋口那条边；悬停时描一道亮边
func _draw_pocket(index: int, r: Rect2) -> void:
	var base := Color(0.42, 0.16, 0.17)
	if index == 1:
		base = Color(0.46, 0.18, 0.19)        # 右上袋（正确答案）稍微亮一丁点，但不做出"提示"
	var hovered := index == _hover_pocket
	_detail_canvas.draw_rect(r, base, true)
	_detail_canvas.draw_rect(r, C_POCKET_LINE if not hovered else C_POCKET_HOVER, false, 2.0 if hovered else 1.5)
	# 袋口：上面一条横边
	_detail_canvas.draw_line(Vector2(r.position.x, r.position.y), Vector2(r.end.x, r.position.y),
			C_POCKET_LINE, 3.0)
	# 袋口中间那一小截（像松紧口）
	var mid := r.position.x + r.size.x * 0.5
	_detail_canvas.draw_line(Vector2(mid - 12.0, r.position.y + 5.0), Vector2(mid + 12.0, r.position.y + 5.0),
			C_POCKET_LINE, 1.0)
	# 口袋名：画在口袋中间（小字），保证"看得出哪只是哪只"
	_detail_canvas.draw_string(ThemeDB.fallback_font,
			Vector2(r.position.x, r.position.y + r.size.y * 0.5 + float(FS_DRAW) * 0.4),
			POCKETS[index], HORIZONTAL_ALIGNMENT_CENTER, r.size.x, FS_DRAW, C_TEXT)


## 主视图的输入：左键点口袋；悬停描边
func _on_coat_input(event: InputEvent) -> void:
	if _won or _pick < 0:
		return
	if event is InputEventMouseMotion:
		var m := event as InputEventMouseMotion
		var hit := _pocket_at(m.position)
		if hit != _hover_pocket:
			_hover_pocket = hit
			_detail_canvas.queue_redraw()
		return
	if event is InputEventMouseButton:
		var b := event as InputEventMouseButton
		if b.pressed and b.button_index == MOUSE_BUTTON_LEFT:
			var hit := _pocket_at(b.position)
			if hit >= 0:
				_on_pocket_pressed(hit)
				_detail_canvas.accept_event()
			elif not garment_has_pockets(_pick):
				# 围巾上没有口袋：点哪儿都只是一行字，不推进、不关闭
				_on_no_pocket_pressed()
				_detail_canvas.accept_event()


## 点了没有口袋的那一件（围巾）
func _on_no_pocket_pressed() -> void:
	if _won or _pick < 0:
		return
	var line := "这是%s，上面没有口袋。" % str(CLOTHES[_pick]["name"])
	_detail_feedback.add_theme_color_override("font_color", PreludeUI.C_ACCENT)
	_detail_feedback.text = line
	_set_feedback(line, false)
	if _detail_canvas != null:
		_detail_canvas.queue_redraw()


## 点在哪个口袋上（命中区 = COAT_POCKETS，和画出来的是同一份）
##   没有口袋的那一件（围巾）直接返回 -1：画面上没有口袋，就不该有"看不见的命中区"。
func _pocket_at(p: Vector2) -> int:
	if not garment_has_pockets(_pick):
		return -1
	for i in COAT_POCKETS.size():
		if COAT_POCKETS[i].has_point(p):
			return i
	return -1


## 摸口袋：点对了才进第 ③ 屏，点错了只换一行字、弹窗不关（可以接着点）
## 【判定】正确 = 左起第三件（CLOTHES[2]，红的）+ 右上袋（POCKETS[1]）；
##   文档里的「红 + 三 + 二」，第二条线索就是这个口袋落在衣服右上。
func _on_pocket_pressed(index: int) -> void:
	if _won or _pick < 0:
		return
	var coat_ok := bool(CLOTHES[_pick]["right"])
	if coat_ok and index == 1:
		_detail_feedback.add_theme_color_override("font_color", PreludeUI.C_INK)
		_detail_feedback.text = "指尖碰到一块硬的东西——盒子。"
		_set_feedback("指尖碰到一块硬的东西——盒子。", false)
		_show_screen(2)
		return
	# —— 点错了：一行反馈，不倒退、不关窗
	var line := ""
	if not coat_ok:
		line = "%s的三个口袋都是空的。" % str(CLOTHES[_pick]["name"])
	else:
		line = "这个口袋里是空的。" if index == 0 else "空的。袋底只有一道缝。"
	_detail_feedback.add_theme_color_override("font_color", PreludeUI.C_ACCENT)
	_detail_feedback.text = line
	_set_feedback(line, false)
	if _detail_canvas != null:
		_detail_canvas.queue_redraw()


# ---------------------------------------------------------------- ② 旧屏位（现在只留一句提示）
## 第 ② 屏位仍然保留（面板对外还是"四屏结构"），但流程上不再停在这里：
## 口袋已经在主视图上摸过了，点对了会直接 _show_screen(2)。
## 万一将来有人把 _show_screen(1) 调出来，这一屏也不会是空白。
func _build_pockets_screen() -> Control:
	var box := VBoxContainer.new()
	box.name = "ScreenPockets"
	box.add_theme_constant_override("separation", 10)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	box.add_child(make_text("红色外套 · 三个口袋", PreludeUI.FS_TEXT, PreludeUI.C_INK))
	box.add_child(make_text("口袋里那只盒子已经摸出来了。", PreludeUI.FS_TIP, PreludeUI.C_INK_DIM))
	var next := make_button("开盒子。", true)
	next.name = "PocketDone"
	next.size_flags_horizontal = Control.SIZE_SHRINK_END
	next.pressed.connect(func() -> void: _show_screen(2))
	box.add_child(next)
	return box


# ---------------------------------------------------------------- ③ 密码盒
func _build_code_screen() -> Control:
	var box := VBoxContainer.new()
	box.name = "ScreenCode"
	box.add_theme_constant_override("separation", 10)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	box.add_child(make_text("密码盒 · 六个数字", PreludeUI.FS_TEXT, PreludeUI.C_INK))

	# 六个数字格：只是把密码"画"出来，实际的输入交给下面那行
	var digit_row := HBoxContainer.new()
	digit_row.name = "DigitRow"
	digit_row.add_theme_constant_override("separation", 8)
	box.add_child(digit_row)

	for i in CODE_LEN:
		var slot := PanelContainer.new()
		slot.name = "Digit%d" % i
		slot.add_theme_stylebox_override("panel", PreludeUI.panel_skin(Color(0.08, 0.085, 0.10, 0.95), Color(0.85, 0.80, 0.70, 0.30), 3))
		slot.custom_minimum_size = Vector2(46, 54)
		digit_row.add_child(slot)

		var l := make_text("－", PreludeUI.FS_NAME, PreludeUI.C_INK_DIM)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		slot.add_child(l)
		_digits.append(l)

	box.add_child(PreludeUI.hline(0.0, Color(0.85, 0.80, 0.70, 0.14)))
	box.add_child(_build_code_input_row())
	box.add_child(make_text("这一串数字你见过。九本书里取出来的。", PreludeUI.FS_TIP, PreludeUI.C_INK_DIM))
	return box


func _build_code_input_row() -> Control:
	var row := HBoxContainer.new()
	row.name = "CodeInputRow"
	row.add_theme_constant_override("separation", 10)

	_code_input = LineEdit.new()
	_code_input.name = "CodeInput"
	_code_input.placeholder_text = "六位数字"
	_code_input.max_length = CODE_LEN
	_code_input.custom_minimum_size = Vector2(300, 44)
	_code_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# 只收数字：非数字一律当场剔掉，粘贴进来的也一样
	_code_input.text_changed.connect(_on_code_changed)
	# 注意：PreludeUI.apply_button_skin() 的形参是 Button，LineEdit 传不进去；
	# 这里借用它内部的 _button_skin_box() 给输入框套同一张皮。
	_code_input.add_theme_stylebox_override("normal", PreludeUI._button_skin_box(Color(0.10, 0.105, 0.125, 0.92), PreludeUI.C_LINE))
	_code_input.add_theme_stylebox_override("focus", PreludeUI._button_skin_box(Color(0.14, 0.145, 0.17, 0.96), Color(0.95, 0.86, 0.66, 0.5)))
	_code_input.add_theme_color_override("font_color", PreludeUI.C_INK)
	_code_input.add_theme_color_override("font_placeholder_color", PreludeUI.C_INK_DIM)
	_code_input.add_theme_color_override("caret_color", PreludeUI.C_NAME)
	_code_input.text_submitted.connect(_on_code_submitted)
	row.add_child(_code_input)

	_code_confirm = make_button("打开", true)
	_code_confirm.name = "CodeConfirm"
	_code_confirm.pressed.connect(func() -> void: _on_code_submitted(_code_input.text))
	row.add_child(_code_confirm)
	return row


## 输入框里只留数字，并同步刷新上面六个数字格
func _on_code_changed(text: String) -> void:
	var cleaned := ""
	for i in text.length():
		var c := text.substr(i, 1)
		if c >= "0" and c <= "9":
			cleaned += c
	if cleaned != text:
		_code_input.text = cleaned
		_code_input.caret_column = cleaned.length()
	for i in CODE_LEN:
		if i < cleaned.length():
			_digits[i].text = cleaned.substr(i, 1)
			_digits[i].add_theme_color_override("font_color", PreludeUI.C_INK)
		else:
			_digits[i].text = "－"
			_digits[i].add_theme_color_override("font_color", PreludeUI.C_INK_DIM)


func _on_code_submitted(text: String) -> void:
	if _won or _screen_index != 2:
		return
	var guess := text.strip_edges()
	if guess == "":
		# 【坑】原来是静默 return：没点输入框就直接按「打开」时画面上毫无反应，
		# 玩家会以为"卡住了"。现在给一句话，并把光标放进框里。
		_set_feedback("先在上面那个框里输入六位数字。", false)
		_code_input.call_deferred("grab_focus")
		return
	if guess == CODE:
		_open_box()
		return
	_wrong_code += 1
	var line := "不对。这一串数字你见过。"
	if _wrong_code >= REVEAL_AT:
		line += "九本书里取出来的六位数。"
	_set_feedback(line, true)


func _open_box() -> void:
	_won = true
	if _detail != null:
		_detail.visible = false
	if _code_input:
		_code_input.editable = false
	if _code_confirm:
		_code_confirm.disabled = true
	_show_screen(3)


# ---------------------------------------------------------------- ④ 星星瓶
func _build_reveal_screen() -> Control:
	var box := VBoxContainer.new()
	box.name = "ScreenReveal"
	box.add_theme_constant_override("separation", 8)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	box.add_child(make_text("盒子里是一只玻璃瓶。", PreludeUI.FS_TEXT, PreludeUI.C_INK))
	box.add_child(_build_star_bottle())
	box.add_child(make_text("是星星瓶。折星星的人没有写完最后一颗。", PreludeUI.FS_TEXT, PreludeUI.C_INK))

	var ok := make_button("收好它。", true)
	ok.name = "TakeBottle"
	ok.size_flags_horizontal = Control.SIZE_SHRINK_END
	ok.pressed.connect(_do_close)
	box.add_child(ok)
	return box


## 玻璃瓶：一排小方块里塞几颗手折的星星（用 ★ 表示），画个意思就行
func _build_star_bottle() -> Control:
	var bottle := PanelContainer.new()
	bottle.name = "StarBottle"
	bottle.add_theme_stylebox_override("panel", PreludeUI.panel_skin(Color(0.10, 0.12, 0.14, 0.92), Color(0.72, 0.78, 0.82, 0.35), 6))
	bottle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottle.custom_minimum_size = Vector2(0, 96)

	var inner := VBoxContainer.new()
	inner.name = "BottleInner"
	inner.add_theme_constant_override("separation", 6)
	bottle.add_child(inner)

	inner.add_child(make_text("玻璃瓶 · 手折的星星", PreludeUI.FS_TIP, PreludeUI.C_INK_DIM))

	# 三行星星：颜色深浅略有差别，像纸折的
	var star_colors := [
		Color(0.96, 0.84, 0.48),
		Color(0.90, 0.72, 0.44),
		Color(0.82, 0.86, 0.90),
	]
	for r in 3:
		var row := HBoxContainer.new()
		row.name = "StarRow%d" % r
		row.add_theme_constant_override("separation", 6)
		inner.add_child(row)
		for c in 9:
			var l := make_text("★", PreludeUI.FS_TEXT, star_colors[(r + c) % 3])
			l.custom_minimum_size = Vector2(20, 0)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			row.add_child(l)
	return bottle


func _do_close() -> void:
	if not _won:
		return
	close_panel({"ok": true, "code": CODE})


# ---------------------------------------------------------------- 调试契约
## 手绘文字的矩形（画布局部坐标），给探针的"文字不重叠"检查用。
## 面板里凡是"玩家看得见的字"都必须登记在这里，否则那条断言就形同虚设。
## 【为什么要这个】第 ① 屏的文字是 draw_string 画的，不是 Label，
## 布局系统管不到它，只能由我们自己报出矩形让探针去两两求交。
func ui_text_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	if _canvas == null or not _canvas.is_inside_tree():
		return out
	var xform := _canvas.get_global_transform()
	for r in _text_rects:
		out.append(xform * r)
	return out


## 第 ① 屏上有没有"参与排版"的文字节点（Label / Button / LineEdit / RichTextLabel）。
## 新版应该是 0 —— 这正是"文字重叠"被根治的证据：文字不再由容器排版。
func ui_layout_text_nodes() -> int:
	var c := _screens[0] if _screens.size() > 0 else null
	if c == null:
		return 0
	var n := 0
	var stack: Array[Node] = [c]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is Label or cur is Button or cur is LineEdit or cur is RichTextLabel:
			n += 1
		for ch in cur.get_children():
			stack.append(ch)
	return n
