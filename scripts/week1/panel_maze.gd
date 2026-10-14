extends "res://scripts/week1/panel_base.gd"
## ============================================================================
##  《寻星》一周目 · 第 1 关 ·「七色镜廊」
## ============================================================================
##  照 Kerry 的《一周目第一关迷宫部分的修改内容》把原来的格子迷宫改成
##  "镜子反射解谜"：
##    · 题目 = 黑色大框 + 铅笔小格 + 七色光的发射口/接收口 + 玩家可放的镜子
##             + 题目已给的镜子（黑色，改不了）
##    · 每个黑色大框里只能放一块反射镜（框只起"限定个数和位置"的作用，
##      **不阻挡光线通过**）
##    · 反射镜只能放在铅笔画的小格里（棋盘格的一半：x+y 为偶数的那些格）
##    · 交互像扫雷：点一下出 '/'，再点变 '\'，再点回空白
##    · 某一条光路正确且完整时，可以把它显示出来
##    · 蓝色光路走出来的形状必须是 S —— 手机壁纸是蓝色，手势密码就是这笔 S
##
##  —— 出题数据（12 面镜 / 12 个黑框）由 tools/solve_maze.gd 穷举复验：全亮且蓝光为 S 的
##     摆法**只有一种**（解唯一）。改这组数据前先跑一遍求解器，别把唯一性改掉。
## ============================================================================
##
## 【踩过的坑 · 全部写在这里，改这个文件前务必读一遍】
##  1. 镜子反射的语义：折向发生在"进入镜格的那一刻"，然后**立刻按新方向走出这一格**
##     （进入格→离开格各一次）。若写成"用反射后的方向又套回当前格"，
##     光束会在同一格内无限折返，任何题目都被判成死循环。
##  2. '/' 和 '\' 的反射表写反过一次：'/' 必须把向右的光往**上**折（R→U），
##     '\' 把向右的光往**下**折（R→D）。写反会让整幅题目的光路全部反向，
##     蓝色 S 直接不成立。
##  3. 蓝色 S 的两竖必须都在同一侧、且第二面镜的出口必须让光继续往前铺：
##     若把 (1,3) 那面镜的出口写成 L，光会提前撞到左边框出去，只剩 2 个拐点（是 C 不是 S）。
##     真 S = 上横 + 左竖 + 中横 + 右竖 + 下横，4 个拐点 (1,1)/(1,3)/(5,3)/(5,5)，
##     折向依次是 L>D, D>R, R>D, D>L。
##  3b.【S 的方向】手势面板那笔 S 是"上排从右上起笔向左、沿左竖下来、中排从左向右、
##     沿右竖下来、下排从右向左"；镜廊这束蓝光必须是**同一张图**，不能是镜像的"2"字
##     （镜像的折向是 R>D, D>L, L>D, D>R）。所以蓝光的进/出口取 in(9,1)L、out(-1,5)L。
##  3c.【S 出不来 / 解不唯一的根因】蓝光的"上横"就是 y=1 那一行。旧数据把 (5,1)、(7,1)
##     给青光当镜子用，这俩正压在上横路中间，蓝光走到 (7,1) 就被折上去 —— 上横永远
##     铺不出来，S 自然出不来。而只要不封死这些镜位，光就能绕出别的路线，解也不唯一。
##     现在的做法：把预设镜所在的框做大，让 (3,1)(5,1)(7,1)(8,0)(8,2)(8,4) 这些
##     "岔路口"全部落在预设框里（玩家放不了镜），S 才被焊成唯一解。
##  4. 不要在这个面板的根节点上 _draw —— 基类的压暗层是兄弟节点，会把画的东西盖住。
##     正确做法是建一个 Control 子节点当画板（见 _board），在它的 draw 信号里画。
##  5. ColorRect 的 mouse_filter 默认是 IGNORE，不显式改成 STOP 就永远收不到 gui_input。
##     所以画板必须用 Control（不是 ColorRect），并显式 mouse_filter = STOP。
##  6. 子类别再声明 _body / _ctx / _done / _closing（基类已有，重名直接解析报错）。
##  7. const X := PackedStringArray([...]) / 复杂字典不是常量表达式，只能用 static var。
##  8. 面板高度/宽度都很紧：基类 540 − 上下边距 − 标题 − 分隔线 − 底部提示后，
##     body 只剩约 444px。所以格子只能取 42px（画板 430×346 才放得下），
##     而且【不能】再单独加一行提示 Label —— 多 24px 就会把最小高顶到 593，
##     PanelContainer 随之长高、顶出 900×540 的设计尺寸（实测帧高 671）。
##     同样地，底部 hint 是"单行不换行"的 Label，句子一长就把 900 的框撑到 928。
##  9. 通关收尾【不能】先置基类的 _done：close_panel() 第一行 `if _done: return`
##     会把自己拦住，finished 永远不发，面板卡在"已解开但关不掉"。另用 _won 防重入。
## 10. "铅笔小格"必须是棋盘格 (x+y)%2==0。曾误写成"x、y 同为奇数"，
##     于是 (2,0)/(4,2)/(6,4)/(6,6)/(7,1) 这些答案镜在界面上点不下去；
##     而逻辑探针是直接往 _placed 里塞镜的，显示 7/7 全绿、玩家却永远做不出来。
##     给画板描底色时也要用同一个判据，否则高亮格和可点格会错开一半。
## 11. 黑框是**不规则块**（FRAMES 是"框 → 格子表"），不是矩形：画轮廓要逐格判断
##     "哪几条边外面不是同一只框"（见 _draw_frame_outline），悬停高亮同理。
## 12. 【提示不能说破】Kerry 反馈"提示还直接把答案告诉观众了"。原来状态行/`_say`
##     里写着"蓝色那道光还没走出那笔 S。改改蓝光那一路。" —— 一句话同时说破了"S"
##     和"该改哪一路"。现在改成分级提示（HINTS，点一次给一级），最后一级才点出
##     "蓝色那道光的样子还不对"，全程不提 S、也不说是哪一面镜。
## ============================================================================

# ---------------------------------------------------------------- 常数
const COLS := 9
const ROWS := 7
const CELL := 42.0
const PAD := 26.0                      # 网格四周留给"发射口/接收口"的边距
## 画板 430×346。看起来比"54px 左右"偏小，但这是被面板撑高的硬约束逼出来的：
## 基类的框是 900×540（body 可用高 ≈ 444），而格子边长一大，
## 本体（标题 31 + 分隔线 1 + 状态行 47 + 画板 + 底部提示 20 + 间距）的"最小高"
## 就超过 540，PanelContainer 会长高把面板顶出设计尺寸（实测 54px 时帧高 671、
## 44px 时 593、42px 时 ≈546）。想要更大的格子，只能再缩掉状态行/提示文字，
## 或者接受面板比 900×540 高。
const BW := COLS * CELL + PAD * 2.0    # 430
const BH := ROWS * CELL + PAD * 2.0    # 346
const CYCLE := ["", "/", "\\"]         # 扫雷式循环：空 → ／ → ＼ → 空

const C_BG := Color(0.09, 0.09, 0.11, 1.0)
const C_FRAME := Color(0.72, 0.70, 0.66, 0.92)
const C_GRID := Color(0.85, 0.83, 0.76, 0.18)
const C_ANSWER_DOT := Color(0.85, 0.83, 0.76, 0.075)
const C_SLOT_RING := Color(0.85, 0.83, 0.76, 0.30)
const C_HOVER := Color(0.98, 0.86, 0.55, 0.85)
const C_HOVER_FILL := Color(0.98, 0.86, 0.55, 0.10)
const C_MIRROR := Color(0.88, 0.91, 0.95, 0.95)
const C_PRESET := Color(0.10, 0.10, 0.12, 1.0)

# 七色光：红 / 橙 / 黄 / 绿 / 青 / 蓝 / 紫
static var COLORS := ["red", "orange", "yellow", "green", "cyan", "blue", "purple"]
static var RGB := {
	"red": Color(0.96, 0.27, 0.25),
	"orange": Color(0.98, 0.58, 0.20),
	"yellow": Color(0.96, 0.87, 0.28),
	"green": Color(0.34, 0.86, 0.38),
	"cyan": Color(0.28, 0.86, 0.88),
	"blue": Color(0.28, 0.47, 0.98),
	"purple": Color(0.68, 0.40, 0.95),
}
static var LABEL := {
	"red": "红", "orange": "橙", "yellow": "黄", "green": "绿",
	"cyan": "青", "blue": "蓝", "purple": "紫",
}

# 方向：右 / 左 / 下 / 上
static var DIRS := {"R": Vector2i(1, 0), "L": Vector2i(-1, 0), "D": Vector2i(0, 1), "U": Vector2i(0, -1)}
static var HIT := {"R": Vector2i(1, 0), "L": Vector2i(-1, 0), "D": Vector2i(0, 1), "U": Vector2i(0, -1)}
static var FLIP := {
	"/": {"R": "U", "L": "D", "U": "R", "D": "L"},
	"\\": {"R": "D", "L": "U", "U": "L", "D": "R"},
}
static var ARROW := {"R": "▶", "L": "◀", "D": "▼", "U": "▲"}

# ---------------------------------------------------------------- 题目数据（复验通过）
# 每色的发射口 / 接收口（都在网格边框外一格）与进入方向
static var ANSWERS := {
	"red": {"in": Vector2i(7, 7), "in_dir": "U", "out": Vector2i(9, 5), "out_dir": "R"},
	"orange": {"in": Vector2i(-1, 6), "in_dir": "R", "out": Vector2i(6, 7), "out_dir": "D"},
	"yellow": {"in": Vector2i(-1, 0), "in_dir": "R", "out": Vector2i(2, -1), "out_dir": "U"},
	"green": {"in": Vector2i(9, 4), "in_dir": "L", "out": Vector2i(4, -1), "out_dir": "U"},
	# 青光的两个口子本来在画稿上就被裁掉了（照片里看不到），只要求它"从自己的口进、从自己的口出"。
	# 现在它从右边 (9,3) 横着进来，先被自己的 (7,3) ／ 折向下，再借红光的 (7,5) ／
	# 和题目给的 (5,5) ／ 拐两下，从底部 (5,7) 落下去 —— 全程不碰蓝光那条上横 y=1。
	"cyan": {"in": Vector2i(9, 3), "in_dir": "L", "out": Vector2i(5, 7), "out_dir": "D"},
	# 【S 的根因】蓝光必须"从高位右边进、从低位左边出"，才可能走出与手势密码**同向**的那笔 S
	# （上排从右往左 → 沿左竖下来 → 中排从左往右 → 沿右竖下来 → 下排从右往左）。
	# 旧数据写成 in(-1,1)R / out(-1,5)L（同一条左边、上进下出），光只会拐出一个"钩子"，
	# 三横的走向变成 R/R/L，永远成不了 S —— Kerry 说的"目前这个没有 s 型"就是这个。
	# 画稿上蓝字的两个口子正好是左低、右高，与这里的 (9,1)L / (-1,5)L 一致。
	# 顺序一旦反向（走成 R/U/L/U/R），形状就是镜像的"数字 2"，手势密码那一关会对不上。
	"blue": {"in": Vector2i(9, 1), "in_dir": "L", "out": Vector2i(-1, 5), "out_dir": "L"},
	"purple": {"in": Vector2i(9, 0), "in_dir": "L", "out": Vector2i(6, -1), "out_dir": "U"},
}

# 答案镜子（12 面）。玩家要摆的就是这些位置，朝向摆对才算通。
# 【S 的四角】蓝色那笔 S = 上横 + 左竖 + 中横 + 右竖 + 下横，四角分别是
#   (1,1) ／（上横左端折向下）· (1,3) ＼（左竖下端折向右）
#   (5,3) ＼（中横右端折向下）· (5,5) ／（下横右端折回向左）
# 【踩过的坑】旧数据里 (5,1) ＼ 与 (7,1) ＼ 是给青光用的，可它们正压在蓝光
# 上横 y=1 的路中间 —— 蓝光从右边进来、走到 (7,1) 就被折上去了，那条上横
# 永远铺不出来，S 自然出不来（Kerry 反馈"目前这个没有 s 型"就是这个）。
# 现在 (3,1)/(5,1)/(7,1) 连同 (8,0)/(7,1) 一起落进"预设镜所在的框"——那个框
# 玩家放不了镜子 —— 蓝光的上横才是一条干净的路，青光也改走 (7,3) 那一路。
static var SOL_MIRRORS := {
	Vector2i(1, 1): "/", Vector2i(2, 0): "/", Vector2i(6, 0): "\\",
	Vector2i(1, 3): "\\", Vector2i(5, 3): "\\", Vector2i(5, 5): "/",
	Vector2i(4, 2): "\\", Vector2i(6, 2): "\\", Vector2i(6, 4): "\\",
	Vector2i(6, 6): "\\", Vector2i(7, 3): "/", Vector2i(7, 5): "/",
}

# 题目提前给玩家的 3 面黑镜（玩家改不了；它们所在的整个黑框也跟着被占住）
static var PRESETS := [Vector2i(1, 1), Vector2i(1, 3), Vector2i(6, 0)]

# 12 个黑色大框：照 Kerry 画稿做成不规则块，铺满 9×7 的格子、互不重叠。
# 框只起"限定这一块区域里放一面镜"的作用，**不阻挡光线通过**。
# 【为什么框要长这样】每个框里恰好一面答案镜；预设镜所在的框（G0/G1/G2）里
# 剩下的铅笔格玩家一律放不了镜子 —— 蓝光上横上的 (3,1)(5,1)(7,1)、左竖下端的
# (1,5)（不封它蓝光就能从 (1,1) 一路直下到 (1,5) 再往左拐，走出来是个"钩子"
# 不是 S）、绿光岔路上的 (8,0)(8,2)(8,4) 就是靠这三只框焊死的。
# 不封掉它们，光会绕出别的路线，"解唯一"立刻不成立（实测旧框型有 16 个解）。
static var FRAMES := [
	[Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1), Vector2i(4, 1), Vector2i(5, 1)],
	[Vector2i(0, 2), Vector2i(1, 2), Vector2i(0, 3), Vector2i(1, 3), Vector2i(0, 4), Vector2i(1, 4),
			Vector2i(0, 5), Vector2i(1, 5), Vector2i(0, 6), Vector2i(1, 6)],
	[Vector2i(6, 0), Vector2i(7, 0), Vector2i(8, 0), Vector2i(6, 1), Vector2i(7, 1), Vector2i(8, 1),
			Vector2i(8, 2), Vector2i(8, 3), Vector2i(8, 4)],
	[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0), Vector2i(5, 0)],
	[Vector2i(2, 3), Vector2i(3, 3), Vector2i(4, 3), Vector2i(5, 3)],
	[Vector2i(2, 2), Vector2i(3, 2), Vector2i(4, 2), Vector2i(5, 2)],
	[Vector2i(2, 4), Vector2i(3, 4), Vector2i(4, 4), Vector2i(5, 4), Vector2i(2, 5), Vector2i(3, 5),
			Vector2i(4, 5), Vector2i(5, 5), Vector2i(2, 6), Vector2i(3, 6), Vector2i(4, 6), Vector2i(5, 6)],
	[Vector2i(6, 2), Vector2i(7, 2), Vector2i(6, 3)],
	[Vector2i(6, 4), Vector2i(7, 4), Vector2i(6, 5)],
	[Vector2i(6, 6), Vector2i(7, 6), Vector2i(8, 6)],
	[Vector2i(7, 3)],
	[Vector2i(7, 5), Vector2i(8, 5)],
]

# ---------------------------------------------------------------- 状态
var _board: Control = null
var _placed := {}          # Vector2i → "/" 或 "\\"（只含玩家摆的镜）
var _show_all := false     # 显示光路开关
var _status: Label = null
var _toggle: Button = null
# 【提示·分级】点一次给一级，最后一级才点出"蓝色那道光的样子还不对"；全程不提"S"、
# 也不说该改哪一面镜 —— 玩家自己会把它和后面手机壁纸的那笔蓝色 S 对上。
# 【坑】PackedStringArray 不是常量表达式（见文件头第 7 条），只能用 static var。
static var HINTS := [
	"有的颜色接上了，有的还没有——再看看它们的形状。",
	"每一路光都得从自己的口进、从自己的口出。",
	"一个黑框只放一面镜：框里别的格子放进去会顶掉对的那面。",
	"蓝色那道光的样子还不对。",
]
var _hint_btn: Button = null
var _hint_level := 0
var _flash_text := ""      # 最近一条提示（显示在状态行里，原本是单独一行）
# 【可玩性·2026-06 Kerry 反馈】"哪里能摆镜子指示不清楚"：
# ① 每格都画一个空心小圈（能放的格子才画），鼠标移到哪一格就把那格和它所属的黑框一起点亮；
# ② 点空白铅笔格一律能放镜（不再有"这里不是能摆镜子的地方"这种与画面对不上的拒绝）；
# ③ 七色全亮但蓝光还不是那笔 S 时，状态行明确说出来（不是暗规则）。
var _hover := Vector2i(-1, -1)
var _frame_of := {}        # Vector2i → 黑框 index（用于"一框一镜"的检查）
# 坑：不要拿基类的 _done 当"已通关"标记 —— close_panel() 里 `if _done: return`
# 会把它当成"已经关掉了"，通关收尾就再也发不出 finished。所以另开一个 _won。
var _won := false


func panel_title() -> String:
	return "七色镜廊"


func panel_hint() -> String:
	# 【坑·面板宽度】底部提示是"不换行、右对齐"的单行 Label，它的最小宽度会直接
	# 把 900 宽的框撑大（实测这句原文 565px 宽 → 帧宽 928）。参考 panel_gesture 的
	# 短提示"按顺序点亮九个点"，这里也必须压在一行短句里。
	return "每框只放一块镜　·　七色各接自己的口子"


# ---------------------------------------------------------------- 建造
func build_body(body: VBoxContainer) -> void:
	# 状态行与画板之间不留缝：面板的 900×540 就靠这点余量卡住（见 CELL 的注释）
	body.add_theme_constant_override("separation", 0)
	# 格子 → 所属黑框（黑框是不规则块，逐个格子登记）
	for i in FRAMES.size():
		for c: Vector2i in FRAMES[i]:
			_frame_of[c] = i

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	body.add_child(top)

	_status = make_text("", PreludeUI.FS_TEXT, PreludeUI.C_INK)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# 【坑·面板放不下】原设计是"状态行 + 画板 + 单独一行提示文字"，但基类框只有
	# 900×540、body 可用高 ≈ 444，多一行 24px 的 _flash 直接把最小高顶到 593，
	# PanelContainer 就会长高、顶出面板设计尺寸。于是把提示并进状态行，
	# 并且关掉自动换行（否则长提示会撑成两三行，高度又回去了）。
	_status.autowrap_mode = TextServer.AUTOWRAP_OFF
	_status.clip_text = true
	top.add_child(_status)

	_toggle = make_button("显示已亮光路", false)
	_toggle.pressed.connect(_on_toggle)
	top.add_child(_toggle)

	_hint_btn = make_button("提示", false)
	_hint_btn.pressed.connect(_on_hint)
	top.add_child(_hint_btn)

	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(center)

	# 【坑·见文件头第 4、5 条】画板必须是 Control（ColorRect 的 mouse_filter 默认 IGNORE），
	# 并且显式 STOP，否则 gui_input 永远不触发。
	_board = Control.new()
	_board.name = "MazeBoard"
	_board.mouse_filter = Control.MOUSE_FILTER_STOP
	_board.custom_minimum_size = Vector2(BW, BH)
	center.add_child(_board)
	_board.draw.connect(_on_board_draw)
	_board.gui_input.connect(_on_board_input)

	_refresh()


func _refresh() -> void:
	var n := _lit_count()
	if _won:
		_status.text = "七色归位 —— 蓝色那道光，走出来的正是那笔 S。"
	elif _flash_text != "":
		_status.text = _flash_text
	elif _placed.is_empty():
		_status.text = "点带圈的铅笔格放镜子：一下 ／、两下 ＼、三下拿空"
	elif n == COLORS.size():
		# 【不能说破】七色都亮了却不是答案时，只指方向：不说破是哪一路、更不提"S"。
		# （按"解唯一"的设计，这种状态其实已经摆不出来了，这句是兜底。）
		_status.text = "七色的口子都亮了，可题目要的形状还没出来——再顺一顺那几条光路。"
	elif _show_all:
		_status.text = "亮起的口子：%d / 7　（正在显示全部光路）" % n
	else:
		_status.text = "亮起的口子：%d / 7　·　已摆镜子：%d / %d" % [
			n, _placed.size(), SOL_MIRRORS.size() - PRESETS.size()]
	_status.add_theme_color_override("font_color",
			PreludeUI.C_NAME if _flash_text != "" or _won else PreludeUI.C_INK)
	if _toggle != null:
		_toggle.text = "隐藏光路" if _show_all else "显示已亮光路"
	if _board != null:
		_board.queue_redraw()


## 状态行兼职当提示条（原来单独一行的 _flash 会把面板撑高，见 build_body 注释）
func _say(msg: String) -> void:
	_flash_text = msg
	_refresh()


# ---------------------------------------------------------------- 光线追踪
## 光束从 entry 口进入，沿 d 走；遇到镜子就 90° 折向，直到走出网格。
## 返回 {exit, exit_dir, mirrors, turns, path, looped}；path 只含网格内的格。
func _trace(placed: Dictionary, entry: Vector2i, d: String) -> Dictionary:
	# 【规矩】黑笔画的 3 面预设镜也算数（它们就是"题目提前给你的那三面"）。
	# 【坑】原来 _trace 只看传进来的 _placed，于是画面上明明立着三面黑镜、光却当它们不存在
	# —— 玩家会觉得"这镜子是假的"。现在统一在这里把预设镜并进来。
	var all := {}
	for pc in PRESETS:
		all[pc] = SOL_MIRRORS[pc]
	for k in placed.keys():
		all[k] = placed[k]
	var cur: Vector2i = entry + (DIRS[d] as Vector2i)
	var seen := {}
	var mirrors: Array = []
	var turns: Array = []
	var path: Array = []
	var looped := false
	var guard := 0
	while true:
		guard += 1
		if guard > 4096:
			looped = true
			break
		if not _inside(cur):
			break
		var key := "%d,%d,%s" % [cur.x, cur.y, d]
		if seen.has(key):
			looped = true
			break
		seen[key] = true
		path.append(cur)
		if all.has(cur):
			var nd: String = FLIP[all[cur]][d]
			mirrors.append(cur)
			turns.append([cur, d, nd])
			d = nd
		cur = cur + (DIRS[d] as Vector2i)
	return {
		"exit": cur, "exit_dir": d, "mirrors": mirrors,
		"turns": turns, "path": path, "looped": looped,
	}


## 这一色是否"从自己的口进、从自己的口出"（且镜子没被同一束光踩两次）
func _is_lit(c: String) -> bool:
	var a: Dictionary = ANSWERS[c]
	var r := _trace(_placed, a["in"] as Vector2i, a["in_dir"] as String)
	if r["looped"]:
		return false
	var ms: Array = r["mirrors"]
	if ms.size() != _uniq(ms).size():
		return false
	if (r["exit"] as Vector2i) != (a["out"] as Vector2i):
		return false
	if (r["exit_dir"] as String) != (a["out_dir"] as String):
		return false
	return true


func _lit_count() -> int:
	var n := 0
	for c in COLORS:
		if _is_lit(c):
			n += 1
	return n


func _uniq(a: Array) -> Array:
	var o: Array = []
	for x in a:
		if not o.has(x):
			o.append(x)
	return o


func _inside(c: Vector2i) -> bool:
	return c.x >= 0 and c.x < COLS and c.y >= 0 and c.y < ROWS


## 只有"铅笔小格"才能放镜子。铅笔小格是棋盘格的一半：x+y 为偶数的那些格
## （(1,1)/(1,3)/(2,0)/(6,6)/(7,1) … 这一族，与画稿上铅笔细线围出的小格一致）。
## 【坑】一度写成 `c.x % 2 == 1 and c.y % 2 == 1`（只取"双双奇数"），
## 于是 (2,0)/(4,2)/(6,4)/(6,6)/(7,1) 这些答案镜在界面上根本点不下去；
## 而逻辑探针是直接往 _placed 里塞镜的，所以显示 7/7 全绿、玩家却永远摆不出来。
func _mirror_cell(c: Vector2i) -> bool:
	return _inside(c) and (c.x + c.y) % 2 == 0


func _is_preset(c: Vector2i) -> bool:
	return PRESETS.has(c)


## 这个黑框里是不是已经立着题目给的预设镜（立着就代表"这框满了"，玩家放不进镜）。
func _frame_has_preset(fi: int) -> bool:
	for p in PRESETS:
		if _frame_of.get(p, -1) == fi:
			return true
	return false


## 蓝光走出的是不是那笔 S：拿"答案镜"跑一遍当参照，逐格比对蓝光的实际路径。
## 只有它成立，面板才会收尾（下一关的手势密码就是这笔画出来的 S）。
func _blue_is_s() -> bool:
	if not _is_lit("blue"):
		return false
	var a: Dictionary = ANSWERS["blue"]
	var want: Array = _trace(SOL_MIRRORS, a["in"] as Vector2i, a["in_dir"] as String)["path"]
	var got: Array = _trace(_placed, a["in"] as Vector2i, a["in_dir"] as String)["path"]
	return got == want


# ---------------------------------------------------------------- 自检口
# 给 tools/probe_maze.gd 读的两个口子：探针不必猜坐标，直接问面板"蓝光怎么走的"。
# 【为什么还要看折向】"逐格比对"只能证明跟答案一样；折向序列能证明它和下一关
# 手势面板的那笔 S **同向**（镜像的"2"字折向正好相反，见 panel_gesture.gd）。
## 蓝光当前实际依次经过的格子（Vector2i 数组）。
func blue_path() -> Array:
	var a: Dictionary = ANSWERS["blue"]
	return _trace(_placed, a["in"] as Vector2i, a["in_dir"] as String)["path"]


## 蓝光每一处拐弯的方向变化，形如 ["L>D", "D>R", "R>D", "D>L"]。
## 手势那笔 S 是：上排从右上起笔向左 → 沿左竖下来 → 中排从左向右 → 沿右竖下来 →
## 下排从右向左；按折向读出来就是 L>D, D>R, R>D, D>L（镜像的"2"是 R>D, D>L, L>D, D>R）。
func blue_turns() -> Array:
	var out: Array = []
	var a: Dictionary = ANSWERS["blue"]
	for t in _trace(_placed, a["in"] as Vector2i, a["in_dir"] as String)["turns"]:
		out.append("%s>%s" % [t[1], t[2]])
	return out


# ---------------------------------------------------------------- 交互
func _pos_to_cell(p: Vector2) -> Vector2i:
	return Vector2i(int(floor((p.x - PAD) / CELL)), int(floor((p.y - PAD) / CELL)))


func _cell_center(c: Vector2i) -> Vector2:
	return Vector2(PAD + (float(c.x) + 0.5) * CELL, PAD + (float(c.y) + 0.5) * CELL)


func _on_board_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var m := event as InputEventMouseMotion
		var hc := _pos_to_cell(m.position)
		if not _inside(hc):
			hc = Vector2i(-1, -1)
		if hc != _hover:
			_hover = hc
			_board.queue_redraw()
		return
	if _done or _won:
		return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var cell := _pos_to_cell(mb.position)
	if not _inside(cell):
		return
	if _is_preset(cell):
		_say("这块黑色的镜子是题目给的，动不了。")
		return
	if not _mirror_cell(cell):
		_say("只有带圈的铅笔格能卡住镜子。")
		return
	if not _placed.has(cell):
		# 【黑框规矩】一个框里只能放一块镜。预设镜所在的框已经"满了"：那三面是题目
		# 提前给的，剩下的铅笔格玩家连点都点不进去 —— 蓝光上横上的 (3,1)(5,1)(7,1)
		# 就是靠这条焊死的（不封掉它们，蓝光会被别的镜位提前折上去，S 就铺不出来）。
		var fi: int = _frame_of.get(cell, -1)
		if fi >= 0:
			if _frame_has_preset(fi):
				_say("这个框里已经立着题目给的镜子了，放不下第二块。")
				return
			for c in _placed.keys():
				if _frame_of.get(c, -2) == fi:
					_say("这个黑框里已经有镜子了，先把那块拿掉。")
					return
		_placed[cell] = "/"
	else:
		var cur_s: String = _placed[cell]
		var idx := CYCLE.find(cur_s)
		var nxt: String = CYCLE[(idx + 1) % CYCLE.size()]
		if nxt == "":
			_placed.erase(cell)
		else:
			_placed[cell] = nxt
	_flash_text = ""
	_refresh()
	if _lit_count() == COLORS.size():
		if _blue_is_s():
			_win()
		else:
			# 【不能说破】只指方向：既不说破"S"，也不说破该改哪一面镜。
			_say("七色的口子都亮了，可题目要的形状还没出来——再顺一顺那几条光路。")


func _on_toggle() -> void:
	_show_all = not _show_all
	_refresh()


## 【提示·分级】点一下给一级（_hint_level 只增不减，玩家想看几级看几级）。
func _on_hint() -> void:
	if _won:
		return
	if _hint_level < HINTS.size():
		_hint_level += 1
	_say("%s　（提示 %d / %d）" % [HINTS[_hint_level - 1], _hint_level, HINTS.size()])


func _win() -> void:
	# 坑：基类 close_panel() 第一行就是 `if _done: return`，所以这里【不能】先置
	# _done —— 否则延时结束后 close_panel 被自己的守卫拦下，finished 永远不发，
	# 面板会卡在"亮起 7/7 但关不掉"。防重复点由 _won 负责，_done 交给基类。
	if _won:
		return
	# 【关卡收尾的硬条件】七色都要接回自己的口子，而且蓝光必须走成那笔 S。
	# 两条都过才算过关（解唯一：全亮且蓝光是 S 的摆法只有一种）。
	if _lit_count() != COLORS.size() or not _blue_is_s():
		return
	_won = true
	_refresh()
	await get_tree().create_timer(1.1).timeout
	# 后面的手势密码要用"S = 五笔"，所以先落到 flag 上再关面板
	PreludeState.set_flag("week1_maze_shape", "S")
	close_panel({"ok": true, "shape": "S", "blue_path": blue_path()})


# ---------------------------------------------------------------- 绘制
func _on_board_draw() -> void:
	var b := _board
	b.draw_rect(Rect2(Vector2.ZERO, Vector2(BW, BH)), C_BG)
	# 能放镜子的格：淡底色 + 中心一个空心小圈。
	# 【可玩性】原来只给一层 alpha 0.045 的底色，Kerry 反馈"哪里能摆镜子指示不清楚"；
	# 现在每一格都画一个圈，能放的格子一眼可数。
	# 【坑】这里也必须用棋盘格 (x+y) 偶数，不能写成 `range(1,COLS,2)` 的双奇循环 ——
	# 那样高亮的格子和真正点得下去的格子会错开一半，(2,0) 这类镜位看着是死格子。
	for x in COLS:
		for y in ROWS:
			if (x + y) % 2 != 0:
				continue
			var cell_rect := Rect2(Vector2(PAD + x * CELL, PAD + y * CELL), Vector2(CELL, CELL))
			b.draw_rect(cell_rect, C_ANSWER_DOT)
			b.draw_circle(_cell_center(Vector2i(x, y)), 4.5, C_SLOT_RING, false, 1.4)
	# 黑色大框：照画稿是不规则块，逐格只画"自己这一侧"的边，拼起来就是框的轮廓
	for i in FRAMES.size():
		_draw_frame_outline(b, i, C_FRAME, 4.0)
	# 铅笔小格
	for i in COLS + 1:
		var x := PAD + i * CELL
		b.draw_line(Vector2(x, PAD), Vector2(x, PAD + ROWS * CELL), C_GRID, 1.0)
	for j in ROWS + 1:
		var y := PAD + j * CELL
		b.draw_line(Vector2(PAD, y), Vector2(PAD + COLS * CELL, y), C_GRID, 1.0)
	# 鼠标悬停：所属黑框整圈点亮（把"一框一镜"画出来）+ 该格高亮 + 空位上给一个 ／ 的虚影
	if _inside(_hover) and not _won:
		var hf: int = _frame_of.get(_hover, -1)
		if hf >= 0:
			_draw_frame_outline(b, hf, C_HOVER, 2.0)
		if _mirror_cell(_hover):
			b.draw_rect(Rect2(Vector2(PAD + _hover.x * CELL, PAD + _hover.y * CELL),
					Vector2(CELL, CELL)), C_HOVER_FILL)
			if not _placed.has(_hover) and not _is_preset(_hover):
				_draw_mirror(b, _hover, "/", Color(0.88, 0.91, 0.95, 0.35), 2.0)
	# 光路（画在格线与镜面之下，免得挡视线）
	for c in COLORS:
		var lit := _is_lit(c)
		if not (lit or _show_all):
			continue
		var col: Color = RGB[c]
		var r := _trace(_placed, ANSWERS[c]["in"] as Vector2i, ANSWERS[c]["in_dir"] as String)
		var path: Array = r["path"]
		if path.size() < 2:
			continue
		var pts := PackedVector2Array()
		for cell in path:
			pts.append(_cell_center(cell as Vector2i))
		var ex: Vector2i = r["exit"] as Vector2i
		var endp := Vector2(
			clampf((float(ex.x) + 0.5) * CELL + PAD, PAD, PAD + COLS * CELL),
			clampf((float(ex.y) + 0.5) * CELL + PAD, PAD, PAD + ROWS * CELL))
		pts.append(endp)
		var alpha := 0.9 if lit else 0.4
		var body := Color(col.r, col.g, col.b, alpha)
		var glow := Color(col.r, col.g, col.b, alpha * 0.22)
		b.draw_polyline(pts, glow, 11.0, true)
		b.draw_polyline(pts, body, 3.0, true)
		# 拐点上的镜子描一圈同色，表示"这面镜吃到了这束光"
		for t in r["turns"]:
			b.draw_circle(_cell_center(t[0]), 16.0, Color(col.r, col.g, col.b, alpha * 0.20), false, 2.0)
	# 镜子
	for c in _placed.keys():
		if _is_preset(c):
			continue
		_draw_mirror(b, c, _placed[c], C_MIRROR, 3.0)
	for c in PRESETS:
		_draw_mirror(b, c, SOL_MIRRORS[c], C_PRESET, 4.0)
	# 七色的发射口 / 接收口（接通的那一色才点亮，方便一眼看出还差哪几色）
	for c in COLORS:
		var lit := _is_lit(c)
		_draw_port(b, c, true, lit)
		_draw_port(b, c, false, lit)


## 画一只黑框的轮廓：黑框是不规则块（见 FRAMES），逐格判断四条边里哪几条
## "外面不是同一只框"，只画那几条，拼起来就是它的轮廓；往框内缩 2px 免得和铅笔格线糊住。
func _draw_frame_outline(b: Control, fi: int, col: Color, w: float) -> void:
	var cells: Array = FRAMES[fi]
	var inside := {}
	for c: Vector2i in cells:
		inside[c] = true
	var ins := 2.0
	for c: Vector2i in cells:
		var x0 := PAD + float(c.x) * CELL
		var y0 := PAD + float(c.y) * CELL
		if not inside.has(c + Vector2i(0, -1)):
			b.draw_line(Vector2(x0, y0 + ins), Vector2(x0 + CELL, y0 + ins), col, w)
		if not inside.has(c + Vector2i(0, 1)):
			b.draw_line(Vector2(x0, y0 + CELL - ins), Vector2(x0 + CELL, y0 + CELL - ins), col, w)
		if not inside.has(c + Vector2i(-1, 0)):
			b.draw_line(Vector2(x0 + ins, y0), Vector2(x0 + ins, y0 + CELL), col, w)
		if not inside.has(c + Vector2i(1, 0)):
			b.draw_line(Vector2(x0 + CELL - ins, y0), Vector2(x0 + CELL - ins, y0 + CELL), col, w)


func _draw_mirror(b: Control, cell: Vector2i, s: String, col: Color, w: float) -> void:
	var k := CELL * 0.30
	var o := _cell_center(cell)
	# 【坑·画反了】屏幕坐标 y 向下：字符 "/" 是"左下 → 右上"，在 y 向下的坐标系里
	# 方向向量是 (k, -k)；"\" 是"左上 → 右下"，向量是 (k, k)。
	# 原来写成了 (k,k) 给 "/"、(k,-k) 给 "\" —— 逻辑上光按反射定律折，画面上镜子却是反的，
	# 看起来就是"光没有按镜子反射"（Kerry 反馈）。
	var d := Vector2(k, -k) if s == "/" else Vector2(k, k)
	b.draw_line(o - d, o + d, col, w, true)


func _draw_port(b: Control, c: String, is_in: bool, lit: bool) -> void:
	var a: Dictionary = ANSWERS[c]
	var e: Vector2i = (a["in"] as Vector2i) if is_in else (a["out"] as Vector2i)
	var d: String = (a["in_dir"] as String) if is_in else (a["out_dir"] as String)
	var f := Vector2(float(e.x) + 0.5, float(e.y) + 0.5) * CELL + Vector2(PAD, PAD)
	var col: Color = RGB[c]
	var txt := "%s%s" % [LABEL[c], ARROW[d]]
	var alpha := 1.0 if lit else 0.45
	b.draw_string(_font(), f + Vector2(-13, 8), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18,
			Color(col.r, col.g, col.b, alpha))


func _font() -> Font:
	return ThemeDB.fallback_font
