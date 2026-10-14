extends "res://scripts/week1/panel_base.gd"
## ============================================================================
##  《寻星》一周目 —— B 的书桌（找不同）
## ============================================================================
##  左边是书桌实景，而且是**两张可以来回切的页面**：
##    · 「现在的样子」—— 被改动过的那一套（热区只挂在这一页上，点它才交互）；
##    · 「参照图 · 原来的摆法」—— 同一张底图、同一批道具、同样的大小与角度，
##      只有那 7 处不一样回到本位（对照《4、5关具体解谜.txt》的清单）：
##        错位：洞洞板隔层右移三格 / 书架上的摆件下移两层
##        倒放：笑脸摆件倒放（笑成了哭）
##        标记：笔记本上出现红笔的标记，旁边多出红蓝黄黑各色笔
##        不合理：日记本上那句"我不再笑了"、合照里室友的一半被折到背面
##        新物品：桌上多了一本寓言
##  两张页面逐件对照就能把 7 处找出来；切换靠画布下面那颗醒目的按钮
##  （「看原来的样子」↔「回到现在」）。
##
##  【文字不压道具】道具的说明不画在桌面上（热区按钮不再显示文字，只剩悬停高亮），
##  点中某件东西才弹出中间的「详情页」：标题 / 判定 / 说明 / 按钮都只在那一页里，
##  桌面永远是一张干净的图 —— 这也正是玩家要的"文字放在点击交互后的页面里面"。
##
##  【三条关键线索 → 密码箱位置】洞洞板隔层右移三格 / 书架上的摆件下移两层 /
##  笔记本上红笔的标记，这三条才是"密码箱到底在哪儿"的线索（见《4、5关具体解谜.txt》
##  里斜体的那三条）：红色 + 三 + 二 → 衣柜里从左往右第三件红衣服、从上往下数第二个口袋。
##  这三条找齐之后，右边才会冒出一颗「把这三条线索对一对」——
##  玩家按了它，结论才写在详情页里（不按就一直不出现，绝不提前把答案写在桌上）。
##
##  一共有 12 个可点热区（透明按钮盖在物件上，悬停会亮起来），
##  其中 7 处是"不一样的地方"：点中记一处、顶部进度 +1；找齐后右侧换成一份线索统计，
##  第 7 条（寓言集）用暗红标出来（与海龟汤有关），
##  最下面按"记下了"才 close_panel({"ok": true, "found": 7})；
##  要是玩家自己把三条线索对过，结果里还会多一条 code（密码箱的位置）。
##  另外 5 处（台灯 / 笔筒 / 眼镜 / 爱心 / 树枝）是氛围物件：只给一句短描述，
##  不算数、不加进度、可以重复点。
##
##  【注意】不要在本面板根节点上 _draw —— 基类的压暗层会把它整个盖住，
##  所以布景全部用 ColorRect / TextureRect 绝对定位在自建的画布子节点里完成。
##
##  【贴图】洞洞板 / 台灯 / 树枝三处换成了 assets/props 下的真图（其余仍是代码画的）。
##  这几张图是从外面拷进来的、没有 .import，只能走 PreludeUI.load_texture（坑 29）；
##  任何一张读不到就是 null，对应位置自动退回原来那套代码画的图形 —— 贴图只是增强，
##  面板不会因为读不到图而变空白。
##
##  【树枝为什么这么摆】branch.png 是 400x1300 的竖图，树枝本体只占左半边，
##  上下还各压着一条深色横杠。把整张图直接塞进热区，等比缩放之后树枝只剩一根细线
##  （实测在 100x26 的框里只有 8px 宽，所以看到的正是"又小又竖"）。
##  现在先按 BRANCH_CROP 裁到树枝本体，再用 Control.rotation 转 -90° 横过来摆（见 _sprite_rot）。
## ============================================================================

## 左侧"实景"画布的最小尺寸（绝对坐标布景都落在这个范围里）
const DESK_W := 500.0
const DESK_H := 330.0
## 桌面上沿：这条线以下算桌面，并自适应铺到画布底部
const DESK_TOP := 172.0
## 要找的不一样的地方一共几处
const DELTA_TOTAL := 7
## 其中"指向密码箱位置"的关键线索有几条（解谜文档里斜体的那三条）
const KEY_TOTAL := 3
## 详情页（点道具后弹出的那一页）卡片的尺寸
const DETAIL_W := 520.0
const DETAIL_H := 300.0

## 洞洞板占的版面：`_paint_board` 里那块代码画的板身就是这个矩形
const BOARD_RECT := Rect2(16.0, 6.0, 284.0, 152.0)
## 洞洞板的格子边长：隔层"右移三格"就是往右挪 3 格 = 60 像素
const BOARD_GRID := 20.0

## —— 两张页面的差异数据 ------------------------------------------------------
## 参照页画的都是"没被动过"的那一套：三层隔层等距、书架上的摆件还在最上层、
## 笑脸是正着的、笔记本和它周围干干净净、日记纸与合照上没有折痕、桌上没有寓言。
## 现状页那套就是照着原来的坐标改过的（改动点见每条的注释）。
const REF_BOARD_X := [40.0, 150.0, 260.0]
## 最左边那层隔层右移三格（一格 BOARD_GRID）—— 对照的正是后面"三"这个数字
const NOW_BOARD_X := [40.0 + 3.0 * BOARD_GRID, 150.0, 260.0]
## 书架上那个摆件（闹钟）：现状页在最下层（下移两层），参照页还在最上层
const NOW_CLOCK_RECT := Rect2(398.0, 114.0, 60.0, 34.0)
const REF_CLOCK_RECT := Rect2(418.0, 22.0, 60.0, 34.0)
## 笑脸摆件的方脸（两页同一个框，只有眼睛和嘴的上下位置不同）
const SMILE_RECT := Rect2(98.0, 118.0, 40.0, 40.0)
## 笔记本旁边那几支彩色笔（只有现状页才有：红蓝黄黑）
const COLOR_PENS := [
	Color(0.70, 0.34, 0.32), Color(0.28, 0.40, 0.72),
	Color(0.80, 0.70, 0.28), Color(0.15, 0.15, 0.18),
]

## 道具贴图。这几张是从外面拷进来的、**没有 .import**，
## 只能走 PreludeUI.load_texture（内部会退回 Image.load_from_file，也就是坑 29）；
## 千万别写成 ResourceLoader.exists() + ResourceLoader.load()，那会一直拿到 null。
const TEX_PEGBOARD := "res://assets/props/pegboard.png"
const TEX_LAMP := "res://assets/props/smiley_lamp.png"
const TEX_STICK := "res://assets/props/branch.png"
## 树枝贴图里"树枝本体"那一块（原图 400x1300；上下各有一条深色横杠要砍掉）
const BRANCH_CROP := Rect2(36.0, 76.0, 157.0, 1144.0)
## 树枝横过来摆的旋转角（度）
const BRANCH_ROT_DEG := -90.0
## 洞洞板是底衬，压暗一点免得抢戏；道具本身不压
const TINT_BOARD := Color(0.50, 0.50, 0.52, 1.0)
const TINT_PROP := Color(1.0, 1.0, 1.0, 1.0)

## 12 个热区。dev = 算不算"不一样的地方"；key = 算不算指向密码箱的关键线索；
## hot = 要不要在统计里标红。
const ITEMS := [
	{"id": "board", "label": "洞洞板隔层", "rect": Rect2(92, 32, 54, 84), "dev": true, "key": true,
		"text": "最左边那层洞洞板隔层，比其余两层往右挪了三格。三个洞——记住这个数。"},
	{"id": "clock", "label": "书架上的摆件", "rect": Rect2(392, 108, 76, 46), "dev": true, "key": true,
		"text": "书架上那个小摆件本来在最上一层，和那排推理小说并排。现在它往下挪了两层——又是一个数。"},
	{"id": "notebook", "label": "笔记本", "rect": Rect2(96, 234, 98, 84), "dev": true, "key": true,
		"text": "笔记本上多了一个用红笔画的爱心，没有被划掉，一看就是后来才画上去的。旁边还多了红蓝黄黑各色笔。红笔——先记住这个颜色。"},
	{"id": "smile", "label": "笑脸摆件", "rect": Rect2(92, 116, 54, 48), "dev": true,
		"text": "笑脸摆件是倒着放的。它朝上笑的时候，屋里应该只有一个人；倒过来，笑就成了哭。"},
	{"id": "diary", "label": "日记纸", "rect": Rect2(196, 264, 86, 48), "dev": true,
		"text": "『自从来到这里，我不再笑了；但我可以离开。』字迹很轻，纸角有反复折叠过的痕迹。"},
	{"id": "photo", "label": "合照", "rect": Rect2(284, 254, 82, 66), "dev": true,
		"text": "合照被折过一道，正好把室友的那一半折到背面去。折痕很旧了。"},
	{"id": "fable", "label": "寓言集", "rect": Rect2(368, 248, 72, 78), "dev": true, "hot": true,
		"text": "桌上多了一本寓言——不是这个寝室的风格，也不是刘忆的书。"},
	{"id": "lamp", "label": "台灯", "rect": Rect2(22, 174, 72, 80), "dev": false,
		"text": "灯罩内侧积了一层灰，灯管却擦得很干净。"},
	{"id": "pens", "label": "笔筒", "rect": Rect2(26, 110, 46, 54), "dev": false,
		"text": "三支中性笔，一支没水了，笔帽上留着牙印。"},
	{"id": "glasses", "label": "眼镜", "rect": Rect2(154, 128, 92, 36), "dev": false,
		"text": "镜腿断了一边，用胶带缠着。像是随手扔掉的垃圾，又被人捡了回来。"},
	{"id": "heart", "label": "爱心", "rect": Rect2(444, 262, 48, 56), "dev": false,
		"text": "一个红色的爱心摆件。不知为什么你感到你充满了决心。"},
	{"id": "stick", "label": "树枝", "rect": Rect2(312, 186, 176, 36), "dev": false,
		"text": "一根树枝，横搁在桌上，握起来意外地顺手。似乎是一件称手的兵器。"},
]

var _progress: Label = null
var _desc: RichTextLabel = null
var _done_btn: Button = null
var _reason_btn: Button = null     # 三条关键线索找齐后才冒出来的「对一对」
var _hotspots: Dictionary = {}      # id → Button
var _found: Dictionary = {}         # 已经点中的"不一样的地方" id
var _found_order: Array = []        # 找到的顺序（右侧清单按这个顺序写）
var _found_count := 0
var _key_count := 0                 # 其中关键线索已经找到几条
var _dev_items: Array = []          # ITEMS 里 dev = true 的那 7 条，按原顺序
var _code_revealed := false         # 玩家有没有自己对出密码箱的位置
# 三张道具贴图：读不到就是 null，那就整套退回代码画的图形（面板不会变空白）
var _tex_peg: Texture2D = null
var _tex_lamp: Texture2D = null
var _tex_stick: Texture2D = null
# 两张页面：同一位置、同一尺寸，同时只有一张可见（容器会自动跳过隐藏的子节点）
var _canvas_now: Control = null
var _canvas_ref: Control = null
var _page_label: Label = null
var _page_btn: Button = null
var _showing_ref := false           # false = 现在的样子；true = B 原来的摆法（参照图）
# 详情页（点道具后弹出）：说明与判定只出现在这里，桌面上一个字都不画
var _detail_layer: Control = null
var _detail_title: Label = null
var _detail_verdict: Label = null
var _detail_text: RichTextLabel = null
var _detail_scroll: ScrollContainer = null


# ---------------------------------------------------------------- 子类覆盖点
func panel_title() -> String:
	# 玩家不知道文档里的 A/B 代号，写"刘忆"（B=刘忆）
	return "刘忆的书桌"


func panel_hint() -> String:
	return "对照参照图，点出不一样的地方"


func build_body(body: VBoxContainer) -> void:
	_dev_items = []
	for item in ITEMS:
		if bool(item["dev"]):
			_dev_items.append(item)

	# —— 顶部进度
	_progress = make_text("不一样的地方 0 / %d" % DELTA_TOTAL, PreludeUI.FS_TEXT, PreludeUI.C_NAME)
	_progress.name = "DeskProgress"
	body.add_child(_progress)

	var row := HBoxContainer.new()
	row.name = "DeskRow"
	row.add_theme_constant_override("separation", 10)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(row)

	_build_desk(row)
	_build_reader(row)
	_build_detail_layer()


# ---------------------------------------------------------------- 右边：记录区
## 记录区 = 小标题 + 可滚动的清单 + （关键线索齐了以后的）「对一对」+ 通关按钮
## 【注意】道具的长说明**不写在这里**，在中间的详情页里（这样桌面不会被文字压住）；
## 这里只留"已经找到哪几处不一样"的短清单。
func _build_reader(parent: Control) -> void:
	var panel := PanelContainer.new()
	panel.name = "DeskReader"
	panel.add_theme_stylebox_override("panel", PreludeUI.panel_skin(PreludeUI.C_PANEL, PreludeUI.C_LINE, 6))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)

	var col := VBoxContainer.new()
	col.name = "ReaderColumn"
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)

	col.add_child(make_text("记下来的", PreludeUI.FS_TIP, PreludeUI.C_INK_DIM))
	col.add_child(PreludeUI.hline(0.0, PreludeUI.C_LINE))

	var scroll := ScrollContainer.new()
	scroll.name = "ReaderScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)

	_desc = make_rich("点一点桌上的东西，说明会弹在中间的详情页里。\n\n拿不准就翻到「原来的摆法」对照。\n找到的记在这里。")
	_desc.name = "ReaderText"
	_desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_desc.custom_minimum_size = Vector2(1.0, 0.0)
	scroll.add_child(_desc)

	# 三条关键线索找齐才会出现：按了它，结论才写在详情页里
	_reason_btn = make_button("把这三条线索对一对")
	_reason_btn.name = "DeskReason"
	_reason_btn.visible = false
	_reason_btn.pressed.connect(_on_reason_pressed)
	col.add_child(_reason_btn)

	_done_btn = make_button("记下了", true)
	_done_btn.name = "DeskDone"
	_done_btn.visible = false
	_done_btn.pressed.connect(_on_done_pressed)
	col.add_child(_done_btn)


# ---------------------------------------------------------------- 左边：书桌实景（两张页面）
func _build_desk(parent: Control) -> void:
	# —— 道具贴图：这三张没有 .import，只能走 PreludeUI.load_texture（坑 29）
	_tex_peg = PreludeUI.load_texture(TEX_PEGBOARD)
	_tex_lamp = PreludeUI.load_texture(TEX_LAMP)
	_tex_stick = PreludeUI.load_texture(TEX_STICK)

	var col := VBoxContainer.new()
	col.name = "DeskColumn"
	col.add_theme_constant_override("separation", 8)
	parent.add_child(col)

	# —— 两张页面摞在同一个位置上，靠 visible 切换（隐藏的子节点不参与容器布局）
	_canvas_now = _build_page(col, "DeskCanvas", false)
	_canvas_ref = _build_page(col, "DeskRefCanvas", true)
	_canvas_ref.visible = false

	# —— 切页条：左边写清这一页是什么，右边是那颗醒目的切换按钮
	var bar := HBoxContainer.new()
	bar.name = "DeskPageBar"
	bar.add_theme_constant_override("separation", 10)
	col.add_child(bar)

	_page_label = make_text("现在的样子", PreludeUI.FS_TIP, PreludeUI.C_INK_DIM)
	_page_label.name = "DeskPageLabel"
	_page_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar.add_child(_page_label)

	_page_btn = make_button("看原来的样子", true)
	_page_btn.name = "DeskPageToggle"
	_page_btn.pressed.connect(_on_page_toggle)
	bar.add_child(_page_btn)


## 铺一页书桌：ref = true 画"原来的摆法"（参照图），false 画"现在的样子"。
## 只有"现在的样子"这一页挂热区 —— 参照图是拿来对照的，不需要点。
func _build_page(parent: Control, node_name: String, ref: bool) -> Control:
	var canvas := Control.new()
	canvas.name = node_name
	canvas.custom_minimum_size = Vector2(DESK_W, DESK_H)
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(canvas)

	_paint_scene(canvas, ref)
	if not ref:
		_build_hotspots(canvas)
	return canvas


## 一页的全部布景。两张页面共用这套底子，只有传进去的 ref 决定那 7 处怎么画。
func _paint_scene(canvas: Control, ref: bool) -> void:
	# —— 墙（铺满画布）+ 桌面（从 DESK_TOP 铺到画布底）
	var wall := ColorRect.new()
	wall.color = Color(0.075, 0.078, 0.088)
	wall.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(wall)
	wall.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# —— 洞洞板贴图：整块墙面的底衬，铺在纯色墙之上、其余所有布景之下
	#     （热区按钮是最后才加的，所以照样压在这张图上面，点得到）
	_sprite(canvas, BOARD_RECT, _tex_peg, TINT_BOARD)

	var desk := ColorRect.new()
	desk.color = Color(0.205, 0.148, 0.100)
	desk.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(desk)
	desk.anchor_left = 0.0
	desk.anchor_right = 1.0
	desk.anchor_top = 0.0
	desk.anchor_bottom = 1.0
	desk.offset_left = 0.0
	desk.offset_right = 0.0
	desk.offset_top = DESK_TOP
	desk.offset_bottom = 0.0
	# 桌沿高光：把"桌面"和"墙"分开
	_box(canvas, Rect2(0.0, DESK_TOP - 3.0, DESK_W, 3.0), Color(0.310, 0.225, 0.150))

	_paint_board(canvas, ref)
	_paint_shelf(canvas, ref)
	_paint_ledge(canvas, ref)
	_paint_desk_items(canvas, ref)


# ---------------------------------------------------------------- 切页
func _on_page_toggle() -> void:
	_set_page(not _showing_ref)


## 切到某一页：ref = true 看参照图（原来的摆法），false 回到现状
func _set_page(ref: bool) -> void:
	_showing_ref = ref
	if _canvas_now != null:
		_canvas_now.visible = not ref
	if _canvas_ref != null:
		_canvas_ref.visible = ref
	if _page_label != null:
		_page_label.text = "参照图 · 原来的摆法" if ref else "现在的样子"
	if _page_btn != null:
		_page_btn.text = "回到现在" if ref else "看原来的样子"


# ---------------------------------------------------------------- 详情页（点道具后弹出）
## 【为什么单独做一层】道具说明原来写在桌面上，桌面上还顶着 12 个写着物件名的按钮，
## 把道具本身盖住了。现在：点中某件东西 → 弹出一页，标题 / 判定 / 说明 / 按钮全在这页里。
## 这一层挂在面板根节点上（在基类的 PanelFrame 之后 add_child，所以压在面板之上）。
func _build_detail_layer() -> void:
	_detail_layer = Control.new()
	_detail_layer.name = "DeskDetail"
	_detail_layer.visible = false
	_detail_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_detail_layer)
	_detail_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var dim := ColorRect.new()
	dim.name = "DetailDim"
	dim.color = Color(0.02, 0.02, 0.03, 0.62)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail_layer.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var card := PanelContainer.new()
	card.name = "DeskDetailCard"
	card.add_theme_stylebox_override("panel", PreludeUI.panel_skin(PreludeUI.C_PANEL_HI, PreludeUI.C_LINE, 8))
	_detail_layer.add_child(card)
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	card.custom_minimum_size = Vector2(DETAIL_W, DETAIL_H)
	card.offset_left = -DETAIL_W * 0.5
	card.offset_right = DETAIL_W * 0.5
	card.offset_top = -DETAIL_H * 0.5
	card.offset_bottom = DETAIL_H * 0.5

	var margin := MarginContainer.new()
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
	col.add_child(_detail_title)
	col.add_child(PreludeUI.hline(DETAIL_W - 40.0, PreludeUI.C_LINE))

	_detail_verdict = make_text("", PreludeUI.FS_TIP, PreludeUI.C_INK_DIM)
	_detail_verdict.name = "DetailVerdict"
	col.add_child(_detail_verdict)

	var scroll := ScrollContainer.new()
	scroll.name = "DetailScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)
	_detail_scroll = scroll

	_detail_text = make_rich("")
	_detail_text.name = "DetailText"
	_detail_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_text.custom_minimum_size = Vector2(1.0, 0.0)
	scroll.add_child(_detail_text)

	var btns := HBoxContainer.new()
	btns.name = "DetailButtons"
	btns.add_theme_constant_override("separation", 10)
	btns.alignment = BoxContainer.ALIGNMENT_END
	col.add_child(btns)

	var cmp_btn := make_button("对照原来的样子")
	cmp_btn.name = "DetailCompare"
	cmp_btn.pressed.connect(_on_detail_compare)
	btns.add_child(cmp_btn)

	var ok_btn := make_button("知道了", true)
	ok_btn.name = "DetailOk"
	ok_btn.pressed.connect(_close_detail)
	btns.add_child(ok_btn)


## 往详情页里填一页内容并弹出来（点道具、"对线索"都走这里）
func _open_card(title: String, verdict: String, text: String, accent: bool) -> void:
	if _detail_layer == null:
		return
	_detail_title.text = title
	_detail_verdict.text = verdict
	_detail_verdict.add_theme_color_override(
		"font_color", PreludeUI.C_ACCENT if accent else PreludeUI.C_INK_DIM)
	_detail_text.text = text
	_detail_layer.visible = true
	# 上一件可能是很长的日记纸、已经翻到下面去了 —— 这一页得从头上看
	if _detail_scroll != null:
		_detail_scroll.set_deferred("scroll_vertical", 0)


## 弹出某件道具的详情页
func _open_detail(item: Dictionary, is_dev: bool, fresh: bool) -> void:
	# 判定沿用原来那套"点中即判定"的规则，这里只是把结果写出来给玩家看
	var verdict := ""
	if is_dev:
		verdict = "这是不一样的地方（%s）　已找出 %d / %d" % [
			"刚记下" if fresh else "已经记下了", _found_count, DELTA_TOTAL]
	else:
		verdict = "本来就摆在这儿，不算　已找出 %d / %d" % [_found_count, DELTA_TOTAL]
	_open_card(str(item["label"]), verdict, str(item["text"]), is_dev)


func _close_detail() -> void:
	if _detail_layer != null:
		_detail_layer.visible = false


## 详情页里的「对照原来的样子」：收起详情、翻到参照图
func _on_detail_compare() -> void:
	_close_detail()
	_set_page(true)


# ---------------------------------------------------------------- 三条关键线索
## 三条关键线索（隔层右移三格 / 摆件下移两层 / 红笔的标记）找齐 → 冒出「对一对」按钮。
## 【注意】找齐 7 处之后它**不许消失**：玩家完全可能先把 7 处一键点完、才回头对线索，
## 按钮一没就再也推不出密码箱的位置了（所以这里不带 _found_count 的条件）。
func _update_reason_btn() -> void:
	if _reason_btn == null:
		return
	_reason_btn.visible = _key_count >= KEY_TOTAL


## 玩家自己把三条线索对起来 —— 结论是一步步"对"出来的，不是一开始就写在桌上的
func _on_reason_pressed() -> void:
	_code_revealed = true
	var lines := PackedStringArray()
	lines.append("洞洞板隔层右移了三格　→　三")
	lines.append("书架上的摆件下移了两层　→　二")
	lines.append("笔记本上是红笔的标记　→　红")
	lines.append("")
	lines.append("[color=#%s]红 + 三 + 二 —— 密码箱在：衣柜里，从左往右数第三件红衣服，从上往下数第二个口袋。[/color]"
		% _hex(PreludeUI.C_ACCENT))
	_open_card("把这三条线索对起来看", "红色 / 三 / 二", "\n".join(lines), true)
	# 七处都找齐的话，右侧那份统计是"找齐那一刻"生成的、里面还没有密码箱这一条，
	# 这里刷新一次让它补上（还没找齐就只是更新那份短清单，不会有副作用）
	if _found_count >= DELTA_TOTAL:
		_refresh_reader()


# ---------------------------------------------------------------- 布景
## 洞洞板：板身 + 洞孔阵列 + 三层隔层（最左边那层右移三格 = 第一处不一样）
func _paint_board(canvas: Control, ref: bool) -> void:
	# 板身 + 洞孔：贴图在的时候这块版面由上面那张底衬占了，这里不再画（不然把图整个盖死）；
	# 贴图拿不到（坑 29 兜底）才回到原来的纯色板身 + 洞孔阵列。
	if _tex_peg == null:
		_box(canvas, BOARD_RECT, Color(0.170, 0.170, 0.160))
		_box(canvas, Rect2(18.0, 8.0, 280.0, 148.0), Color(0.125, 0.126, 0.118))
		for row in 8:
			for col in 15:
				_box(canvas, Rect2(30.0 + col * BOARD_GRID, 18.0 + row * BOARD_GRID, 3.0, 3.0),
					Color(0.055, 0.055, 0.052))
	# 三层隔层：本来等距（间距 110），现状页最左边那层被右移了三格
	var xs: Array = REF_BOARD_X if ref else NOW_BOARD_X
	for px in xs:
		_box(canvas, Rect2(px, 34.0, 34.0, 80.0), Color(0.320, 0.300, 0.250))
		_box(canvas, Rect2(px, 34.0, 34.0, 3.0), Color(0.430, 0.400, 0.330))


## 右侧三层书架：最上层是一排推理小说；摆件本该在最上层（第二处不一样）
func _paint_shelf(canvas: Control, ref: bool) -> void:
	var wood := Color(0.240, 0.185, 0.130)
	_box(canvas, Rect2(318.0, 8.0, 164.0, 148.0), Color(0.100, 0.088, 0.075))
	_box(canvas, Rect2(316.0, 8.0, 5.0, 148.0), wood)
	_box(canvas, Rect2(479.0, 8.0, 5.0, 148.0), wood)
	for y in [8.0, 56.0, 104.0, 149.0]:
		_box(canvas, Rect2(316.0, y, 168.0, 5.0), wood)
	var spines := [
		Color(0.52, 0.30, 0.24), Color(0.36, 0.40, 0.30), Color(0.30, 0.34, 0.44),
		Color(0.55, 0.44, 0.26), Color(0.42, 0.28, 0.34), Color(0.28, 0.36, 0.36),
		Color(0.50, 0.38, 0.30),
	]
	for i in spines.size():
		_box(canvas, Rect2(326.0 + i * 18.0, 15.0, 15.0, 39.0), spines[i])
	_box(canvas, Rect2(330.0, 86.0, 70.0, 8.0), Color(0.400, 0.300, 0.280))
	_box(canvas, Rect2(330.0, 95.0, 62.0, 7.0), Color(0.300, 0.340, 0.400))
	# 摆件：现状页下移了两层（从最上层掉到了最下层），参照页还站在最上层
	_paint_clock(canvas, REF_CLOCK_RECT if ref else NOW_CLOCK_RECT)


## 一只小摆件（闹钟）：r 是钟身（两只铃铛吊在钟身上沿、钟面在中间），换个 r 就换了个位置
func _paint_clock(canvas: Control, r: Rect2) -> void:
	_box(canvas, r, Color(0.620, 0.600, 0.540))
	_box(canvas, Rect2(r.position.x + 2.0, r.position.y - 7.0, 9.0, 8.0), Color(0.550, 0.530, 0.480))
	_box(canvas, Rect2(r.position.x + 49.0, r.position.y - 7.0, 9.0, 8.0), Color(0.550, 0.530, 0.480))
	_box(canvas, Rect2(r.position.x + 22.0, r.position.y + 10.0, 16.0, 14.0), Color(0.850, 0.830, 0.760))


## 洞洞板下面的层板，以及搁在上面的笔筒 / 笑脸摆件 / 破眼镜
func _paint_ledge(canvas: Control, ref: bool) -> void:
	_box(canvas, Rect2(18.0, 160.0, 280.0, 7.0), Color(0.240, 0.185, 0.130))
	# 笔筒 + 三支笔
	_box(canvas, Rect2(30.0, 122.0, 38.0, 38.0), Color(0.170, 0.180, 0.210))
	_box(canvas, Rect2(36.0, 108.0, 3.0, 16.0), Color(0.550, 0.300, 0.280))
	_box(canvas, Rect2(44.0, 104.0, 3.0, 20.0), Color(0.300, 0.340, 0.420))
	_box(canvas, Rect2(52.0, 110.0, 3.0, 14.0), Color(0.700, 0.680, 0.600))
	# 笑脸摆件（第三处不一样）：现状页是倒着的，参照页才是正的
	_paint_smile(canvas, SMILE_RECT, ref)
	# 镜腿断了一边的眼镜
	_box(canvas, Rect2(162.0, 134.0, 30.0, 18.0), Color(0.340, 0.350, 0.390))
	_box(canvas, Rect2(198.0, 134.0, 30.0, 18.0), Color(0.340, 0.350, 0.390))
	_box(canvas, Rect2(192.0, 140.0, 6.0, 4.0), Color(0.300, 0.310, 0.340))
	_box(canvas, Rect2(228.0, 138.0, 16.0, 3.0), Color(0.720, 0.700, 0.620))


## 笑脸摆件：upright = true 画"正着的"（参照页），false 画"倒着的"（现状页）。
## 两张脸是同一个方框，只有眼睛和嘴的上下位置对调 —— 于是玩家一眼能看出正反（笑成了哭）。
func _paint_smile(canvas: Control, r: Rect2, upright: bool) -> void:
	_box(canvas, r, Color(0.860, 0.780, 0.340))
	var eye_y := r.position.y + (8.0 if upright else 22.0)
	var mouth_y := r.position.y + (26.0 if upright else 8.0)
	_box(canvas, Rect2(r.position.x + 8.0, eye_y, 5.0, 5.0), Color(0.100, 0.090, 0.070))
	_box(canvas, Rect2(r.position.x + 27.0, eye_y, 5.0, 5.0), Color(0.100, 0.090, 0.070))
	_box(canvas, Rect2(r.position.x + 10.0, mouth_y, 20.0, 3.0), Color(0.100, 0.090, 0.070))


## 桌面上的东西：台灯 / 树枝 / 笔记本（连着那几支彩色笔）/ 日记纸 / 合照 / 寓言 / 爱心。
## 【纸张上的记号是"现状页独有"的】红笔标记、两道折痕都是被人动过的痕迹，
## 参照页上是干净的纸 —— 对照的时候这几处最容易被看漏。
func _paint_desk_items(canvas: Control, ref: bool) -> void:
	# 台灯：贴图直接盖在"台灯"那个热区的矩形上（热区本身一个像素都没动）；
	# 贴图拿不到才退回下面这套方块。
	if _tex_lamp != null:
		_sprite(canvas, _item_rect("lamp"), _tex_lamp, TINT_PROP)
	else:
		_box(canvas, Rect2(40.0, 240.0, 34.0, 8.0), Color(0.200, 0.210, 0.240))
		_box(canvas, Rect2(55.0, 196.0, 4.0, 46.0), Color(0.240, 0.250, 0.280))
		_box(canvas, Rect2(30.0, 176.0, 54.0, 24.0), Color(0.300, 0.240, 0.160))
		_box(canvas, Rect2(34.0, 196.0, 46.0, 3.0), Color(0.860, 0.810, 0.600))
	# 神秘树枝：横过来、放大（两页一样 —— 它不是"不一样的地方"）。
	# 贴图拿不到就退回下面这套代码画的横树枝。
	if _tex_stick != null:
		_sprite_rot(canvas, _item_rect("stick"), _tex_stick, TINT_PROP, BRANCH_ROT_DEG, BRANCH_CROP)
	else:
		_box(canvas, Rect2(316.0, 202.0, 168.0, 8.0), Color(0.430, 0.340, 0.220))
		_box(canvas, Rect2(344.0, 192.0, 5.0, 12.0), Color(0.430, 0.340, 0.220))
		_box(canvas, Rect2(438.0, 206.0, 5.0, 14.0), Color(0.430, 0.340, 0.220))
	# 笔记本（第四处不一样：现状页上有红笔的标记，旁边还多出红蓝黄黑各色笔）
	_box(canvas, Rect2(104.0, 264.0, 84.0, 48.0), Color(0.720, 0.680, 0.580))
	_box(canvas, Rect2(100.0, 262.0, 8.0, 52.0), Color(0.450, 0.300, 0.220))
	if not ref:
		# 笔记本右下角那个「后来才画上去的红爱心」：只有现状页才有（对照页没有），
		# 摆成两颗圆瓣 + 一个尖，一眼能认出是爱心——《问题》第 10 条。
		_box(canvas, Rect2(168.0, 294.0, 6.0, 5.0), PreludeUI.C_ACCENT)
		_box(canvas, Rect2(176.0, 294.0, 6.0, 5.0), PreludeUI.C_ACCENT)
		_box(canvas, Rect2(169.0, 298.0, 12.0, 4.0), PreludeUI.C_ACCENT)
		_box(canvas, Rect2(172.0, 302.0, 6.0, 3.0), PreludeUI.C_ACCENT)
		_box(canvas, Rect2(174.0, 305.0, 2.0, 2.0), PreludeUI.C_ACCENT)
		for i in COLOR_PENS.size():
			_box(canvas, Rect2(106.0 + i * 22.0, 244.0, 18.0, 4.0), COLOR_PENS[i])
	# 一页日记纸（第五处不一样：现状页中间那道是反复折过的折痕）
	_box(canvas, Rect2(202.0, 270.0, 74.0, 38.0), Color(0.800, 0.780, 0.700))
	if not ref:
		_box(canvas, Rect2(238.0, 270.0, 2.0, 38.0), Color(0.660, 0.640, 0.560))
	# 合照（第六处不一样：现状页那道折痕把室友的一半折到了背面）
	_box(canvas, Rect2(290.0, 260.0, 72.0, 56.0), Color(0.300, 0.240, 0.180))
	_box(canvas, Rect2(295.0, 265.0, 62.0, 46.0), Color(0.560, 0.555, 0.520))
	if not ref:
		_box(canvas, Rect2(324.0, 265.0, 2.0, 46.0), Color(0.400, 0.400, 0.380))
	# 寓言（第七处不一样：只有现状页的桌上才有这本不属于这个寝室的书）
	if not ref:
		_box(canvas, Rect2(374.0, 254.0, 60.0, 64.0), Color(0.380, 0.220, 0.240))
		_box(canvas, Rect2(374.0, 254.0, 8.0, 64.0), Color(0.270, 0.155, 0.170))
		_box(canvas, Rect2(392.0, 272.0, 26.0, 26.0), Color(0.780, 0.720, 0.520))
	# 红色爱心摆件（两页一样）
	_box(canvas, Rect2(450.0, 268.0, 34.0, 32.0), PreludeUI.C_ACCENT)
	_box(canvas, Rect2(456.0, 300.0, 22.0, 8.0), Color(0.220, 0.170, 0.170))


## 在画布上摆一块纯色矩形（绝对定位；canvas 不是容器，不会被重排）
func _box(parent: Control, r: Rect2, c: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = c
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rect)
	rect.set_anchors_preset(Control.PRESET_TOP_LEFT)
	rect.offset_left = r.position.x
	rect.offset_top = r.position.y
	rect.offset_right = r.position.x + r.size.x
	rect.offset_bottom = r.position.y + r.size.y
	return rect


## 把一张贴图按给定矩形摆到画布上（同样是绝对定位；canvas 不是容器，不会被重排）。
## expand_mode = EXPAND_IGNORE_SIZE：贴图不参与最小尺寸计算，撑不破版面、也顶不大面板；
## stretch_mode = KEEP_ASPECT_CENTERED：等比缩放到矩形内并居中，图不会被拉变形。
## 贴图是 null（读不到）就直接返回 null，由调用方决定要不要退回代码画的图形。
func _sprite(parent: Control, r: Rect2, tex: Texture2D, tint: Color) -> TextureRect:
	if tex == null:
		return null
	var t := TextureRect.new()
	t.texture = tex
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.modulate = tint
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(t)
	t.set_anchors_preset(Control.PRESET_TOP_LEFT)
	t.offset_left = r.position.x
	t.offset_top = r.position.y
	t.offset_right = r.position.x + r.size.x
	t.offset_bottom = r.position.y + r.size.y
	return t


## 把贴图**转个角度**摆进矩形 r：控件本身先按"旋转前"的竖版尺寸（宽 = r 的高、
## 高 = r 的宽）摆在 r 的正中，pivot 设在自身中心，再绕中心转 deg 度 ——
## 转完之后它的视觉范围正好就是 r。
## 【为什么非裁不可】branch.png 是 400x1300，树枝本体只占左边约 157px 宽的一条，
## 不裁的话等比缩放会把整根树枝缩成一根细线（这正是"树枝又小又竖"的来由）。
## 贴图是 null 就直接返回 null，由调用方退回代码画的横树枝。
func _sprite_rot(parent: Control, r: Rect2, tex: Texture2D, tint: Color, deg: float, crop: Rect2) -> TextureRect:
	if tex == null:
		return null
	var atlas := AtlasTexture.new()
	atlas.atlas = tex
	atlas.region = crop
	atlas.filter_clip = true

	var w := r.size.y       # 旋转前（竖着）的宽
	var h := r.size.x       # 旋转前（竖着）的高
	var cx := r.position.x + r.size.x * 0.5
	var cy := r.position.y + r.size.y * 0.5

	var t := TextureRect.new()
	t.texture = atlas
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.modulate = tint
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(t)
	t.set_anchors_preset(Control.PRESET_TOP_LEFT)
	t.offset_left = cx - w * 0.5
	t.offset_top = cy - h * 0.5
	t.offset_right = cx + w * 0.5
	t.offset_bottom = cy + h * 0.5
	t.pivot_offset = Vector2(w, h) * 0.5
	t.rotation = deg_to_rad(deg)
	return t


## 取某个热区的矩形 —— 道具贴图就盖在对应热区上，热区改了贴图跟着走
func _item_rect(id: String) -> Rect2:
	for item in ITEMS:
		if str(item["id"]) == id:
			var r: Rect2 = item["rect"]
			return r
	return Rect2()


## 按 id 取物件名（右侧清单用）
func _label_of(id: String) -> String:
	for item in ITEMS:
		if str(item["id"]) == id:
			return str(item["label"])
	return id


# ---------------------------------------------------------------- 热区
## 12 个热区：透明按钮直接盖在对应物件上，悬停亮起来。
## 【按钮上不写文字】以前每个按钮都顶着自己的名字（"台灯""树枝"…），把道具样子盖住了；
## 现在名字只留在 tooltip 里，桌面上一个字都不画。
func _build_hotspots(canvas: Control) -> void:
	for item in ITEMS:
		var r: Rect2 = item["rect"]
		var b := Button.new()
		b.name = "Hotspot_" + str(item["id"])
		b.text = ""
		b.tooltip_text = str(item["label"])
		_style_hotspot(b)
		canvas.add_child(b)
		b.set_anchors_preset(Control.PRESET_TOP_LEFT)
		b.offset_left = r.position.x
		b.offset_top = r.position.y
		b.offset_right = r.position.x + r.size.x
		b.offset_bottom = r.position.y + r.size.y
		b.pressed.connect(_on_item_pressed.bind(item))
		_hotspots[str(item["id"])] = b


## 热区皮肤：【道具上一个框都不画】（Kerry：找不同的时候道具上面的框不要显示）。
## 平时完全透明（鼠标能点、鼠标移上去才亮起一层很淡的暖光），
## 找过的那些才留一层更淡的暖色当记号（见 _mark_found）。
func _style_hotspot(b: Button) -> void:
	b.focus_mode = Control.FOCUS_ALL
	b.clip_text = true
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_size_override("font_size", PreludeUI.FS_TIP - 2)
	b.add_theme_color_override("font_color", Color(0.95, 0.92, 0.84, 0.72))
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))

	var sb_normal := StyleBoxEmpty.new()

	var sb_hover := StyleBoxFlat.new()
	sb_hover.bg_color = Color(0.92, 0.84, 0.62, 0.16)

	var sb_down := sb_hover.duplicate() as StyleBoxFlat
	sb_down.bg_color = Color(0.95, 0.86, 0.66, 0.30)

	b.add_theme_stylebox_override("normal", sb_normal)
	b.add_theme_stylebox_override("hover", sb_hover)
	b.add_theme_stylebox_override("pressed", sb_down)
	b.add_theme_stylebox_override("focus", sb_normal)


# ---------------------------------------------------------------- 点击处理
func _on_item_pressed(item: Dictionary) -> void:
	var id := str(item["id"])
	var is_dev := bool(item["dev"])
	var fresh := false
	if is_dev and not _found.has(id):
		_found[id] = true
		_found_order.append(id)
		_found_count += 1
		fresh = true
		if bool(item.get("key", false)):
			_key_count += 1
		_mark_found(id)
		_update_progress()
		_update_reason_btn()
	# 说明与判定进详情页；右侧只更新那份短清单（找齐了就整块换成线索统计）
	_open_detail(item, is_dev, fresh)
	_refresh_reader()


## 右侧清单：还没找齐就列"已经找到哪几处"，找齐了就换成分线索统计
func _refresh_reader() -> void:
	if _found_count >= DELTA_TOTAL:
		_show_summary()
		return
	var lines := PackedStringArray()
	lines.append("已经找出 %d / %d 处不一样" % [_found_count, DELTA_TOTAL])
	lines.append("")
	if _found_order.is_empty():
		lines.append("还没找到。")
		lines.append("")
		lines.append("翻到「原来的摆法」逐件比一比。")
	else:
		for id in _found_order:
			lines.append("· %s" % _label_of(str(id)))
		lines.append("")
		lines.append("还有 %d 处没对上。" % (DELTA_TOTAL - _found_count))
		if _key_count > 0 and _key_count < KEY_TOTAL:
			lines.append("")
			lines.append("（有三条线索是指向密码箱的，找齐了右边会多一颗按钮）")
	_desc.text = "\n".join(lines)


## 找齐 7 处 → 逐条列出来；第 7 条（寓言）标红，并在下面点出"与海龟汤有关"
func _show_summary() -> void:
	var accent := _hex(PreludeUI.C_ACCENT)
	var lines := PackedStringArray()
	lines.append("[color=#%s]线索统计 · %d 处不一样[/color]" % [accent, DELTA_TOTAL])
	lines.append("")
	var idx := 0
	for item in _dev_items:
		idx += 1
		if bool(item.get("hot", false)):
			lines.append("[color=#%s]%d. %s[/color]" % [accent, idx, str(item["text"])])
			lines.append("[color=#%s]（与海龟汤有关）[/color]" % accent)
		else:
			lines.append("%d. %s" % [idx, str(item["text"])])
		lines.append("")
	if _code_revealed:
		lines.append("[color=#%s]密码箱：衣柜里，从左往右数第三件红衣服，从上往下数第二个口袋。[/color]" % accent)
		lines.append("")
	_desc.text = "\n".join(lines)
	# 统计已经写好了，桌上的东西不能再点，免得把这份统计盖掉
	for b in _hotspots.values():
		var btn := b as Button
		if btn != null:
			btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
			btn.focus_mode = Control.FOCUS_NONE
	_update_reason_btn()
	if _done_btn != null:
		_done_btn.visible = true


func _update_progress() -> void:
	if _progress == null:
		return
	if _found_count >= DELTA_TOTAL:
		_progress.text = "不一样的地方 %d / %d —— 一处都没漏" % [_found_count, DELTA_TOTAL]
		_progress.add_theme_color_override("font_color", PreludeUI.C_ACCENT)
	else:
		_progress.text = "不一样的地方 %d / %d" % [_found_count, DELTA_TOTAL]


## 找到的地方在桌上留个记号：一层很淡的暖色。
## 【为什么不用边框】Kerry：找不同的时候道具上面的框不要显示 —— 所以记号只是"暖色的一层"，
## 不画轮廓线；名字只在 tooltip 里（"已找到 · 台灯"）。
func _mark_found(id: String) -> void:
	var b := _hotspots.get(id) as Button
	if b == null:
		return
	b.tooltip_text = "已找到 · " + str(b.tooltip_text)
	var wash := PreludeUI.C_ACCENT
	wash.a = 0.13

	var sb := StyleBoxFlat.new()
	sb.bg_color = wash

	var sb_hover := sb.duplicate() as StyleBoxFlat
	sb_hover.bg_color = Color(wash.r, wash.g, wash.b, 0.28)

	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb_hover)
	b.add_theme_stylebox_override("pressed", sb_hover)
	b.add_theme_stylebox_override("focus", sb)


func _on_done_pressed() -> void:
	var result := {"ok": true, "found": DELTA_TOTAL}
	if _code_revealed:
		result["code"] = "衣柜·左起第三件红衣服·上数第二个口袋"
	close_panel(result)


func _hex(c: Color) -> String:
	return c.to_html(false)
