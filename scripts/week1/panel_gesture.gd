extends "res://scripts/week1/panel_base.gd"
## ============================================================================
##  《寻星》一周目 · 第 2 关 —— 九宫格手势密码
## ============================================================================
##  玩法：3×3 九个点，按顺序点亮。正确顺序就是上一关那句话里的那个形状「S」，
##  **从上往下画**：右上 → 上中 → 左上 → 左中 → 正中 → 右中 → 右下 → 下中 → 左下
##  也就是 (2,0)(1,0)(0,0)(0,1)(1,1)(2,1)(2,2)(1,2)(0,2)——
##  在九宫格上连出来正是一个「S」（顺手把上一关的谜底再用一遍）。
##  【方向千万别搞反】起笔在**右上角**：S 的上排接的是左边那根竖线、下排接的是右边那根。
##  反过来（上排接右边、下排接左边）画出来是「2」——设计师文档里那条
##  「手势密码是s 不是2 反了」说的就是上一版画成了 2，所以这里必须保持现在这个方向。
##
##  点错 = 不是下一个该点的点：整条线清空、错误次数 +1，
##  错到 3 次就把提示升级成"S 有五笔。这个数字等下还有用。"
##
##  背景那层暗蓝是「手机壁纸」，只给气氛，**不画任何图形**。
##  【不要】再把正解描在壁纸上：这里原来按 PATTERN 铺过一层 0.30 透明度的淡蓝线，
##  等于把九个点的正确顺序直接摆在玩家眼前。玩家反馈「不要有底层淡淡的痕迹提示」，
##  正解得让玩家自己从上一关的线索（上一关的 S 有五笔）推出来。
## ============================================================================

const DOTS := 3                     # 3×3
const GAP := 96.0                   # 点与点之间 96px
const DOT := 20.0                   # 点直径 20px
const BOARD := GAP * 2.0           # 画板边长（点占满 3×3 的角，故 = GAP × 2）

const C_DOT := Color(0.26, 0.26, 0.30)          # 未点亮的点
const C_DOT_ON := Color(0.96, 0.80, 0.40)       # 已点亮的点，暖黄（同迷宫的玩家色）
const C_LINE_SKIN := Color(0.86, 0.72, 0.46, 0.72)
const C_BUMP := Color(0.62, 0.31, 0.29)         # 点错时的提示色

## 手机壁纸：只有一层暗蓝底色，纯气氛。
## 【坑】这里原来还有 C_WALL_LINE（按 PATTERN 铺出来的淡蓝线），它会把正解泄露出去，
## 已经删掉。以后要往壁纸上加装饰的话，必须与九个点、与 PATTERN 的走线完全不重合。
const C_WALL := Color(0.055, 0.105, 0.170)
const WALL_PAD := 34.0              # 壁纸比九宫格外扩一圈

## 「S」形手势，从上往下画：上排从右上起笔往左 → 左竖下来 → 中排往右 → 右竖下来 → 下排往左。
##
##   ●───●───●      上排：3 ← 2 ← 1（起笔在右上角）
##   │
##   ●───●───●      中排：4 → 5 → 6
##           │
##   ●───●───●      下排：7 ← 8 ← 9
##
## 上面的编号是"九宫格通用编号"（1=(0,0) 行优先）。上排连左竖、下排连右竖 = S；
## 反过来就是「2」。Kerry 的截图（已点亮 8/9）里画的正是那个 2，别再改回去。
const PATTERN: Array[Vector2i] = [
	Vector2i(2, 0), Vector2i(1, 0), Vector2i(0, 0),
	Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1),
	Vector2i(2, 2), Vector2i(1, 2), Vector2i(0, 2),
]

var _board: Control = null
var _line_holder: Control = null
var _step_label: Label = null
var _dots: Array[Button] = []
var _lines: Array[ColorRect] = []
var _step := 0
var _errors := 0
var _won := false
# 【坑】基类自己有一个 _closing，子类不要再声明同名变量，
# 否则解析期直接报 "already exists in parent class"，整份脚本作废。


# ---------------------------------------------------------------- 基类覆盖点
func panel_title() -> String:
	return "手势密码"


func panel_hint() -> String:
	return "按顺序点亮九个点"


func build_body(body: VBoxContainer) -> void:
	# —— 状态行：报"点到第几个 / 点错了 / 解锁了"
	_step_label = make_text("", PreludeUI.FS_TEXT, PreludeUI.C_INK_DIM)
	_step_label.name = "GestureStep"
	_step_label.custom_minimum_size = Vector2(0, 26)
	_step_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(_step_label)

	# 【坑】画板必须显式定死尺寸。Board 只是一个 Control，没有内容时
	# 最小尺寸是 0，放进 CenterContainer 会被压成 0×0，
	# 之后所有按 BOARD 算出来的绝对坐标就全歪掉了。
	var center := CenterContainer.new()
	center.name = "GestureCenter"
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(center)

	_board = Control.new()
	_board.name = "GestureBoard"
	_board.custom_minimum_size = Vector2(BOARD, BOARD)
	_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(_board)

	# —— 手机壁纸（最底层）：只有一层暗蓝底。
	# 【坑】这层以前会按 PATTERN 铺一道淡蓝的"光路"，也就是把正解描在背景上；
	# 玩家反馈「不要有底层淡淡的痕迹提示」，所以那条光路已经删掉了。
	# 现在壁纸只剩纯色打底，正解只能靠上一关的线索（S 有五笔）自己推。
	var wall := ColorRect.new()
	wall.name = "GestureWall"
	wall.color = C_WALL
	wall.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wall.offset_left = -WALL_PAD
	wall.offset_top = -WALL_PAD
	wall.offset_right = BOARD + WALL_PAD
	wall.offset_bottom = BOARD + WALL_PAD
	_board.add_child(wall)
	var wall_tag := make_text("壁纸", PreludeUI.FS_TIP, Color(0.42, 0.62, 0.86, 0.50))
	wall_tag.name = "GestureWallTag"
	# 【坑】make_text 默认开自动换行，而这个 Label 是绝对定位、没有宽度，
	# 于是「壁纸」会被拆成两行压在左上角那个点上。这里必须关掉换行。
	wall_tag.autowrap_mode = TextServer.AUTOWRAP_OFF
	wall_tag.custom_minimum_size = Vector2(40, 20)
	wall_tag.position = Vector2(-WALL_PAD + 8.0, -WALL_PAD + 3.0)
	_board.add_child(wall_tag)

	# 连线层放在点下面（后加的点会盖在它上面）
	_line_holder = Control.new()
	_line_holder.name = "GestureLines"
	_line_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_line_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_board.add_child(_line_holder)

	for y in DOTS:
		for x in DOTS:
			var b := Button.new()
			b.name = "Dot_%d_%d" % [x, y]
			b.custom_minimum_size = Vector2(DOT, DOT)
			# 【坑】用 Button 而不是 ColorRect + gui_input：ColorRect 的
			# mouse_filter 默认是 IGNORE，不显式改成 STOP 的话
			# gui_input 永远不触发，点了完全没反应。
			# Button 天生接鼠标，还能顺便给焦点/悬停反馈。
			b.offset_left = float(x) * GAP - DOT * 0.5
			b.offset_top = float(y) * GAP - DOT * 0.5
			b.offset_right = b.offset_left + DOT
			b.offset_bottom = b.offset_top + DOT
			# 纯圆点：圆角半径给到直径的一半，方块就变成圆
			var sb := StyleBoxFlat.new()
			sb.bg_color = C_DOT
			sb.set_corner_radius_all(int(DOT * 0.5))
			b.add_theme_stylebox_override("normal", sb)
			var sb_hover := sb.duplicate() as StyleBoxFlat
			sb_hover.bg_color = Color(0.40, 0.40, 0.46)
			b.add_theme_stylebox_override("hover", sb_hover)
			b.add_theme_stylebox_override("focus", sb_hover)
			b.add_theme_stylebox_override("pressed", sb_hover)
			b.pressed.connect(_on_dot_pressed.bind(Vector2i(x, y)))
			_board.add_child(b)
			_dots.append(b)

	_refresh()


# ---------------------------------------------------------------- 点击
func _on_dot_pressed(c: Vector2i) -> void:
	if _won:
		return
	# 点错：不是下一个该点的点 → 整条清空
	if c != PATTERN[_step]:
		_errors += 1
		_reset_chain()
		if _errors >= 3:
			_set_step_text("S 有五笔。这个数字等下还有用。", PreludeUI.C_NAME)
		else:
			_set_step_text("不对。从右上角重新开始，从上往下画。", C_BUMP)
		return

	# 点对：续上，并把这一点和前一点连起来
	var seg: ColorRect = null
	if _step > 0:
		seg = _make_line(PATTERN[_step - 1], c)
	_step += 1
	_refresh()

	if _step >= PATTERN.size():
		_win()
		return
	if seg != null:
		_pop(seg)
	if _step <= 1:
		_set_step_text("", PreludeUI.C_INK_DIM)
	else:
		_set_step_text("已点亮 %d / %d" % [_step, PATTERN.size()], PreludeUI.C_INK_DIM)


func _reset_chain() -> void:
	_step = 0
	for l in _lines:
		if is_instance_valid(l):
			l.queue_free()
	_lines.clear()
	_refresh()


# ---------------------------------------------------------------- 视觉
func _refresh() -> void:
	for i in _dots.size():
		if not is_instance_valid(_dots[i]):
			continue
		var lit := false
		for k in _step:
			if PATTERN[k] == _cell_of(i):
				lit = true
				break
		var sb := _dots[i].get_theme_stylebox("normal")
		if sb is StyleBoxFlat:
			(sb as StyleBoxFlat).bg_color = C_DOT_ON if lit else C_DOT


func _cell_of(i: int) -> Vector2i:
	return Vector2i(i % DOTS, i / DOTS)


## 在两点之间摆一个细长的 ColorRect。只支持横 / 竖（本关的手势正好只有这两向），
## 而且因为 [S] 每一笔都穿过中间那个点，所以虚线中间绕个弯也不用管。
func _make_line(a: Vector2i, b: Vector2i) -> ColorRect:
	var r := ColorRect.new()
	r.color = C_LINE_SKIN
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var thickness := 3.0
	if a.y == b.y:
		var y := float(a.y) * GAP
		r.offset_left = minf(float(a.x), float(b.x)) * GAP
		r.offset_right = maxf(float(a.x), float(b.x)) * GAP
		r.offset_top = y - thickness * 0.5
		r.offset_bottom = y + thickness * 0.5
	else:
		var x := float(a.x) * GAP
		r.offset_left = x - thickness * 0.5
		r.offset_right = x + thickness * 0.5
		r.offset_top = minf(float(a.y), float(b.y)) * GAP
		r.offset_bottom = maxf(float(a.y), float(b.y)) * GAP
	_line_holder.add_child(r)
	_lines.append(r)
	return r


## 新画出来的一笔"长出来"：从中心拉长到整段
func _pop(r: ColorRect) -> void:
	var full := r.size
	if full.x <= 0.0 or full.y <= 0.0:
		return
	var mid := r.position + full * 0.5
	r.pivot_offset = full * 0.5
	r.position = mid - full * 0.5
	r.scale = Vector2(0.08, 0.08)
	var t := create_tween()
	t.tween_property(r, "scale", Vector2.ONE, 0.10).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _set_step_text(text: String, col: Color) -> void:
	if not is_instance_valid(_step_label):
		return
	_step_label.text = text
	_step_label.add_theme_color_override("font_color", col)


# ---------------------------------------------------------------- 通关
func _win() -> void:
	_won = true
	_set_step_text("手机解锁了。", PreludeUI.C_NAME)
	# 停 0.6 秒让玩家看清那句话，再交还控制权
	await get_tree().create_timer(0.6).timeout
	PreludeState.set_flag("week1_gesture_pattern", "S")
	close_panel({"ok": true, "pattern": "S"})
