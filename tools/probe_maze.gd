extends SceneTree
## ============================================================================
##  《寻星》· 第 1 关「七色镜廊」逻辑自检（headless）
## ============================================================================
##  这一关是纯逻辑题，肉眼很难看出"这一格到底能不能放镜"，所以单独把它拎出来查：
##    ① 静态：黑框（不规则块）铺满且互不重叠、每框恰好一面答案镜、可放镜格是棋盘格
##       的一半、预设镜所在的框把岔路镜位焊死（这是"解唯一"的地基）；
##    ② 光线：拿答案镜跑一遍，七色必须全亮、蓝光必须是那笔 S（4 个拐点），
##       而且**折向与下一关手势那笔 S 同向**（镜像的"2"字折向正好相反）；
##    ③ 交互：空白铅笔格必须能放镜（Kerry 反馈"哪里能摆镜子指示不清楚"就是这里出的错）、
##       一框一镜、三下点掉、非铅笔格与预设框里的格子拒绝、预设镜动不了；
##    ④ 判定：常见错解必须明确判错（不是静默放过），答案摆法才过关；
##       分级提示文案里不出现 "S"（不能剧透）；
##    ⑤ 收尾：七色全亮 + 蓝光是 S → 面板自动关闭并写下 week1_maze_shape = "S"。
##
##  跑法：
##    godot --headless --path <项目> --script tools/probe_maze.gd
##  退出码 0 = 全绿。
## ============================================================================

const PANEL_PATH := "res://scripts/week1/panel_maze.gd"

## 手势面板那笔 S 的折向（上排向左 → 沿左竖下来 → 中排向右 → 沿右竖下来 → 下排向左）。
## 与 panel_gesture.gd 的九宫格同向；镜像的"2"字读出来是 ["R>D", "D>L", "L>D", "D>R"]。
const GESTURE_TURNS := ["L>D", "D>R", "R>D", "D>L"]

## 必须被预设框焊死的岔路镜位（不焊死，光就能绕出别的走法，"解唯一"不成立）。
## (3,1)(5,1) 在预设框 0 里；(1,5) 在预设框 1 里（不封它蓝光会一路直下再左拐，走出"钩子"）；
## (7,1)(8,0)(8,2)(8,4) 在预设框 2 里（绿光的岔路）。
const SEALED_SLOTS := [
	Vector2i(3, 1), Vector2i(5, 1), Vector2i(7, 1), Vector2i(1, 5),
	Vector2i(8, 0), Vector2i(8, 2), Vector2i(8, 4),
]

var _fails := 0
var _checks := 0
var _p = null
var _result := {}
var _closed := false


func _initialize() -> void:
	_run()


func _check(cond: bool, label: String, detail: String = "") -> void:
	_checks += 1
	if cond:
		print("  ✓ %s" % label)
	else:
		_fails += 1
		print("  ✗ %s%s" % [label, ("　［%s］" % detail) if detail != "" else ""])


func _finish() -> void:
	print("=========================================")
	print("共 %d 项检查，失败 %d 项" % [_checks, _fails])
	quit(1 if _fails > 0 else 0)


func _run() -> void:
	await process_frame
	print("========== 七色镜廊 逻辑自检 ==========")
	var st := root.get_node_or_null("PreludeState")
	if st == null:
		print("✗ 找不到 PreludeState 自动加载")
		quit(1)
		return
	st.call("reset")

	# 【坑】这里不能用 preload：panel_maze.gd 里写了自动加载 PreludeState，
	# 而 --script 模式下 preload 会在"自动加载还没登记"的时刻就把依赖链编译掉，
	# 报 `Identifier not found: PreludeState`。改成运行时 load（此时单例已就位）。
	var panel_script: Script = load(PANEL_PATH)
	if panel_script == null:
		print("✗ 加载不了 %s" % PANEL_PATH)
		quit(1)
		return
	_p = panel_script.new()
	_p.setup({"id": "maze"})
	_p.finished.connect(_on_finished)
	root.add_child(_p)
	await process_frame

	_static_checks()
	_trace_checks()
	_hint_checks()
	_input_checks()
	await _reject_checks()
	await _solve_and_win()
	_finish()


func _on_finished(result: Dictionary) -> void:
	_closed = true
	_result = result


# ------------------------------------------------------------------ ① 静态
## 黑框现在是一串格子的数组（不规则块），不是 Rect2i。
func _frame_cells(f: Array) -> Array:
	return f


func _connected(cells: Array) -> bool:
	if cells.is_empty():
		return false
	var seen := {cells[0]: true}
	var stack: Array = [cells[0]]
	while not stack.is_empty():
		var cur: Vector2i = stack.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nb: Vector2i = cur + d
			if cells.has(nb) and not seen.has(nb):
				seen[nb] = true
				stack.append(nb)
	return seen.size() == cells.size()


## 画面上"点了能放镜"的格子：铅笔格、不是预设镜、且所在黑框里没有预设镜。
func _placeable(c: Vector2i) -> bool:
	if not _p._mirror_cell(c):
		return false
	if _p._is_preset(c):
		return false
	var fi: int = _p._frame_of.get(c, -1)
	return fi < 0 or not _p._frame_has_preset(fi)


func _static_checks() -> void:
	print("---------- ① 静态数据")
	var pencil: Array = []
	for x in _p.COLS:
		for y in _p.ROWS:
			if _p._mirror_cell(Vector2i(x, y)):
				pencil.append(Vector2i(x, y))
	_check(pencil.size() == 32, "可放镜格是棋盘格的一半（32 格）", "实际 %d" % pencil.size())
	_check(_p.SOL_MIRRORS.size() == 12, "答案镜 12 面（3 面题目给 + 9 面玩家摆）",
			"实际 %d" % _p.SOL_MIRRORS.size())

	# 黑框：铺满 63 格、互不重叠、每一块都是连通的
	_check(_p.FRAMES.size() == 12, "黑框 12 个（照画稿的不规则块）", "实际 %d" % _p.FRAMES.size())
	var cover := {}
	var overlap := 0
	var outside := 0
	var disconnected := 0
	for f: Array in _p.FRAMES:
		var cells: Array = _frame_cells(f)
		if not _connected(cells):
			disconnected += 1
		for c: Vector2i in cells:
			if not _p._inside(c):
				outside += 1
			if cover.has(c):
				overlap += 1
			cover[c] = true
	_check(overlap == 0, "黑框之间没有重叠", "重叠 %d 格" % overlap)
	_check(outside == 0, "黑框都在网格里", "越界 %d 格" % outside)
	_check(disconnected == 0, "每个黑框都是连通的一块", "断开 %d 个" % disconnected)
	_check(cover.size() == _p.COLS * _p.ROWS, "黑框铺满整个网格",
			"覆盖 %d / %d" % [cover.size(), _p.COLS * _p.ROWS])

	# 每框恰好一面答案镜，且答案镜都落在可放格上
	var bad_frame := 0
	var bad_cell := 0
	for f: Array in _p.FRAMES:
		var n := 0
		for c: Vector2i in _frame_cells(f):
			if _p.SOL_MIRRORS.has(c):
				n += 1
		if n != 1:
			bad_frame += 1
	_check(bad_frame == 0, "每个黑框里恰好一面答案镜", "异常框 %d 个" % bad_frame)
	for c in _p.SOL_MIRRORS.keys():
		if not _p._mirror_cell(c):
			bad_cell += 1
	_check(bad_cell == 0, "所有答案镜都落在可放镜格上", "越界 %d 面" % bad_cell)

	# 预设镜必须在答案里（题目白送的那三面），且都落在可放格上
	var preset_bad := 0
	for c in _p.PRESETS:
		if not _p.SOL_MIRRORS.has(c) or not _p._mirror_cell(c):
			preset_bad += 1
	_check(preset_bad == 0 and _p.PRESETS.size() == 3, "三面预设镜都在答案里",
			"异常 %d 面" % preset_bad)

	# 预设镜所在的框整块被占：那些岔路镜位玩家点不进去（解唯一的地基）
	var sealed_bad := 0
	for c: Vector2i in SEALED_SLOTS:
		var fi: int = _p._frame_of.get(c, -1)
		if fi < 0 or not _p._frame_has_preset(fi) or _placeable(c):
			sealed_bad += 1
	_check(sealed_bad == 0, "挡路的岔路镜位都被预设框焊死（%d 个）" % SEALED_SLOTS.size(),
			"漏封 %d 个" % sealed_bad)
	var free_slots := 0
	for c in pencil:
		if _placeable(c):
			free_slots += 1
	# 32 个铅笔格里，13 个落在"立着预设镜的黑框"里（3 面预设镜 + 7 个岔路镜位 +
	# 预设框里另外 3 个空铅笔格），玩家真正能摆的只有 19 格。
	_check(free_slots == 19, "玩家真正能摆镜的格子 32 - 13 = 19 格", "实际 %d" % free_slots)
	var preset_in_sol := 0
	for c in _p.PRESETS:
		if _p.SOL_MIRRORS.has(c):
			preset_in_sol += 1
	_check(preset_in_sol == 3, "三面预设镜都长在答案里", "实际 %d" % preset_in_sol)

	# 七色各一进一出
	var pair_bad := 0
	for c in _p.COLORS:
		var a: Dictionary = _p.ANSWERS.get(c, {})
		if not (a.has("in") and a.has("out") and a.has("in_dir") and a.has("out_dir")):
			pair_bad += 1
	_check(_p.COLORS.size() == 7 and pair_bad == 0, "七色各有一个进光口和一个出光口",
			"异常 %d 色" % pair_bad)


# ------------------------------------------------------------------ ② 光线
func _trace_checks() -> void:
	print("---------- ② 光线追踪（答案镜）")
	var lit := 0
	for c in _p.COLORS:
		var a: Dictionary = _p.ANSWERS[c]
		var r: Dictionary = _p._trace(_p.SOL_MIRRORS, a["in"] as Vector2i, a["in_dir"] as String)
		if r["exit"] == a["out"]:
			lit += 1
	_check(lit == 7, "七色光都从自己的出光口出去了", "亮 %d / 7" % lit)

	var blue: Dictionary = _p.ANSWERS["blue"]
	var tb: Dictionary = _p._trace(_p.SOL_MIRRORS, blue["in"] as Vector2i, blue["in_dir"] as String)
	_check((tb["turns"] as Array).size() == 4, "蓝光恰好 4 个拐点（一笔 S）",
			"实际 %d" % (tb["turns"] as Array).size())
	var rows := []
	for t in tb["turns"]:
		rows.append((t[0] as Vector2i).y)
	rows.sort()
	# 一笔 S 的五笔：上横 y=1、左下竖、中横 y=3、右下竖、下横 y=5
	# 四个拐点分别落在 (1,1)(1,3)(5,3)(5,5)，所以 y 排序后是 [1, 3, 3, 5]
	_check(rows == [1, 3, 3, 5], "蓝光四拐点落在 y = 1 / 3 / 3 / 5（五笔的 S）", "实际 %s" % str(rows))
	var turn_cells := []
	for t in tb["turns"]:
		turn_cells.append(t[0] as Vector2i)
	_check(turn_cells == [Vector2i(1, 1), Vector2i(1, 3), Vector2i(5, 3), Vector2i(5, 5)],
			"四个拐点依次是 (1,1)(1,3)(5,3)(5,5)", "实际 %s" % str(turn_cells))

	# 折向必须与下一关手势那笔 S 同向：上排向左 → 左竖向下 → 中排向右 → 右竖向下 → 下排向左。
	# 镜像的"2"字折向是 ["R>D", "D>L", "L>D", "D>R"]，这里必须挡住。
	var turns := []
	for t in tb["turns"]:
		turns.append("%s>%s" % [t[1], t[2]])
	_check(turns == GESTURE_TURNS, "蓝光折向与手势 S 同向（不是镜像的 2）", "实际 %s" % str(turns))

	# 自检口：面板导出的 blue_turns()/blue_path() 必须与 _trace 一致。
	# 注意：只留三面预设镜时，蓝光已经被那两面预设镜折了两下（["L>D", "D>R"]），
	# 但它还没走成 S —— "空手过关"要挡的是判定本身，不是"光一次都不拐"。
	_check(_p.blue_turns() != GESTURE_TURNS and _p.blue_turns().size() == 2,
			"还没摆镜时 blue_turns() 只有预设镜折的 2 下（不是 S）", str(_p.blue_turns()))
	_check(_p._blue_is_s() == false, "还没摆镜时 _blue_is_s() 是 false（不会空手过关）")


# ------------------------------------------------------------------ ③ 提示
func _hint_checks() -> void:
	print("---------- ③ 分级提示（不能剧透）")
	_check(_p.HINTS.size() == 4, "提示分四级", "实际 %d" % _p.HINTS.size())
	var leak := ""
	for h in _p.HINTS:
		var s := str(h)
		if s.contains("S") or s.contains("s"):
			leak = s
	_check(leak == "", "四级提示文案里都不出现 \"S\"（不剧透那笔形状）", leak)
	_check(str(_p.HINTS[0]).find("哪") < 0 or not str(_p.HINTS[0]).contains("蓝色"),
			"第一级提示不说破是哪一路颜色", str(_p.HINTS[0]))
	# 点一下给一级：次数只增不减
	var before: int = int(_p._hint_level)
	_p._on_hint()
	_check(_p._hint_level == before + 1, "点一次\"提示\"露一级", "实际 %d" % _p._hint_level)
	_check(str(_p._status.text).contains(str(_p.HINTS[0])), "状态行显示第一级提示",
			str(_p._status.text))
	_p._on_hint()
	_check(_p._hint_level == 2, "再点一次露第二级", "实际 %d" % _p._hint_level)
	_check(str(_p._status.text).contains("2 / 4"), "第二级提示带\"2 / 4\"的级数标记",
			str(_p._status.text))
	# 提示只是文字，不该影响棋盘
	_check(_p._placed.is_empty(), "看提示不会往棋盘上放东西", "%d 面" % _p._placed.size())


# ------------------------------------------------------------------ ④ 交互
func _click(cell: Vector2i) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = _p._cell_center(cell)
	_p._on_board_input(ev)


## 点到位（空 → ／ → ＼）：want 为 "" / "/" / "\\"
func _place(cell: Vector2i, want: String) -> void:
	for i in 4:
		if str(_p._placed.get(cell, "")) == want:
			return
		_click(cell)


func _clear_board() -> void:
	for c in _p._placed.keys():
		for i in 4:
			if not _p._placed.has(c):
				break
			_click(c)


func _input_checks() -> void:
	print("---------- ④ 点格子")
	# (a) 空白铅笔格必须能放镜 —— 这条正是玩家反馈的问题。
	#     注意要挑"所在黑框没有预设镜"的格子：预设镜所在的框整块是题目占住的。
	var free_cell := Vector2i(-1, -1)
	for x in _p.COLS:
		for y in _p.ROWS:
			var c := Vector2i(x, y)
			if _placeable(c) and not _p.SOL_MIRRORS.has(c):
				free_cell = c
				break
		if free_cell.x >= 0:
			break
	_check(free_cell.x >= 0, "存在答案之外的空白铅笔格", "")
	_place(free_cell, "")
	_click(free_cell)
	_check(_p._placed.has(free_cell), "空白铅笔格点一下就能放镜（不再被拒）",
			"提示：%s" % _p._flash_text)
	# (b) 三下点掉：／ → ＼ → 空
	_click(free_cell)
	_check(str(_p._placed.get(free_cell, "")) == "\\", "第二下变成 ＼",
			"实际 %s" % str(_p._placed.get(free_cell, "")))
	_click(free_cell)
	_check(not _p._placed.has(free_cell), "第三下把镜子拿空")

	# (c) 非铅笔格点不动
	var half_cell := Vector2i(1, 0)
	_check(not _p._mirror_cell(half_cell), "对照格 (1,0) 确实不是可放格", "")
	_click(half_cell)
	_check(not _p._placed.has(half_cell), "非铅笔格点了不会放上镜子",
			"提示：%s" % _p._flash_text)

	# (d) 一个黑框里只能放一块
	var pair: Array = []
	for f: Array in _p.FRAMES:
		var cells: Array = []
		for c: Vector2i in _frame_cells(f):
			if _placeable(c):
				cells.append(c)
		if cells.size() >= 2:
			pair = cells
			break
	_check(pair.size() >= 2, "找到一个能验一框一镜的黑框", "")
	if pair.size() >= 2:
		_click(pair[0])
		var first_ok: bool = _p._placed.has(pair[0])
		_click(pair[1])
		_check(first_ok and _p._placed.has(pair[0]) and not _p._placed.has(pair[1]),
				"同一个黑框里放第二块镜会被拦下", "提示：%s" % _p._flash_text)
		_clear_board()
		_check(_p._placed.is_empty(), "清空后 _placed 是空的", "剩 %d 面" % _p._placed.size())

	# (e) 预设镜动不了，预设框里别的铅笔格也放不下
	_click(_p.PRESETS[0])
	_check(_p._placed.is_empty(), "点预设镜不会在其上叠一块",
			"提示：%s" % _p._flash_text)
	var sealed: Vector2i = SEALED_SLOTS[0]
	_click(sealed)
	_check(not _p._placed.has(sealed), "预设框里剩的铅笔格放不了镜（题目的框满了）",
			"提示：%s" % _p._flash_text)
	_check(str(_p._flash_text) != "", "被拒时状态行有明确反馈（不是静默）", "")


# ------------------------------------------------------------------ ⑤ 错解不能过
func _reject_checks() -> void:
	print("---------- ⑤ 常见错解必须判错")
	var answer := {}
	for c in _p.SOL_MIRRORS.keys():
		answer[c] = str(_p.SOL_MIRRORS[c])

	# 错解 A：中横那面镜摆反（＼ 变 ／）—— 蓝光会提前往上游走，从 (5,-1) 冒出去
	var wrong_a := answer.duplicate()
	wrong_a[Vector2i(5, 3)] = "/"
	await _try_wrong("错解 A：蓝光中横的镜摆反（＼ 摆成 ／）", wrong_a)

	# 错解 B：中横那面镜挪到 (3,3) —— 蓝光会一路直下从 (3,7) 冒出去
	var wrong_b := answer.duplicate()
	wrong_b.erase(Vector2i(5, 3))
	wrong_b[Vector2i(3, 3)] = "\\"
	await _try_wrong("错解 B：蓝光中横那面镜挪到 (3,3)", wrong_b)

	# 错解 C：漏掉青色的第一面镜 (7,3) —— 青色接不回自己的口
	var wrong_c := answer.duplicate()
	wrong_c.erase(Vector2i(7, 3))
	await _try_wrong("错解 C：漏掉青色的第一面镜 (7,3)", wrong_c)

	_clear_board()
	_check(_p._placed.is_empty(), "错解清空后棋盘是干净的", "剩 %d 面" % _p._placed.size())


func _apply(map: Dictionary) -> void:
	_clear_board()
	for c in map.keys():
		_place(c as Vector2i, str(map[c]))


func _try_wrong(label: String, map: Dictionary) -> void:
	_apply(map)
	var n: int = _p._lit_count()
	var is_s: bool = _p._blue_is_s()
	_check(not _p._won and not (n == _p.COLORS.size() and is_s),
			"%s：不能过关" % label, "亮 %d / 7，蓝光 S = %s" % [n, str(is_s)])
	# 【不能静默】判错时状态行要给出反馈：要么七色的口子没接齐，要么明说形状还不对
	var tip := str(_p._status.text)
	_check(tip.contains("亮起的口子") or tip.contains("形状"),
			"%s：玩家能看到为什么没过" % label, "状态行：%s" % tip)


# ------------------------------------------------------------------ ⑥ 收尾
func _solve_and_win() -> void:
	print("---------- ⑥ 摆出答案并收尾")
	var answer := {}
	for c in _p.SOL_MIRRORS.keys():
		if not _p._is_preset(c):
			answer[c] = str(_p.SOL_MIRRORS[c])
	_check(answer.size() == 9, "答案里玩家要自己摆 9 面镜", "实际 %d" % answer.size())
	_apply(answer)
	_check(_p._placed.size() == 9, "玩家侧 12 - 3 = 9 面镜都摆上了", "实际 %d" % _p._placed.size())
	_check(_p._lit_count() == 7, "七色全亮", "亮 %d / 7" % _p._lit_count())
	_check(_p._blue_is_s(), "蓝光走的正是那笔 S")
	_check(_p.blue_turns() == GESTURE_TURNS, "面板导出的 blue_turns() 与手势 S 同向",
			str(_p.blue_turns()))
	var path: Array = _p.blue_path()
	# 蓝光从右侧 y=1 进（画稿上蓝字就在右边、左边 y=5 也有一个蓝字）、从左侧 y=5 出。
	# 这里【不锁死格数】：以后画稿微调一格不该把探针弄红。硬条件只钉"端点 + 四个拐点 + 同向"，
	# 格数只做下限（一笔五画的 S 至少 5 段，至少要 15 格）。当前数据是 21 格：
	# 上横 x=8→1（8）＋左竖 y=2→3（2）＋中横 x=2→5（4）＋右竖 y=4→5（2）＋下横 x=4→0（5）。
	_check(path.size() >= 15 and path[0] == Vector2i(8, 1) and path[path.size() - 1] == Vector2i(0, 5),
			"面板导出的 blue_path() 从 (8,1) 进、从 (0,5) 出（当前数据 %d 格）" % path.size(),
			"实际 %d 格：%s…%s" % [path.size(), str(path[0]), str(path[path.size() - 1])])
	var p_turns: Array = []
	var p_rows: Array = []
	for i in range(1, path.size() - 1):
		var a: Vector2i = path[i - 1]
		var b: Vector2i = path[i]
		var c2: Vector2i = path[i + 1]
		if (b - a) != (c2 - b):
			p_turns.append(b)
			p_rows.append(b.y)
	_check(p_turns == [Vector2i(1, 1), Vector2i(1, 3), Vector2i(5, 3), Vector2i(5, 5)],
			"从导出路径里数出来的 4 个拐点就是 S 的那四个角", str(p_turns))
	_check(_p._won, "七色全亮 + 蓝光是 S → 判过关")

	# 面板会在 1.1 秒后自己关掉
	var waited := 0.0
	while not _closed and waited < 4.0:
		await process_frame
		waited += 1.0 / 60.0
	_check(_closed, "七色归位后面板自动关闭")
	_check(str(root.get_node("PreludeState").call("get_flag", "week1_maze_shape", "")) == "S",
			"写下了 week1_maze_shape = S")
	_check(bool(_result.get("ok", false)) and str(_result.get("shape", "")) == "S",
			"面板结果里带 ok + shape=S", str(_result))
	_check(_result.get("blue_path", []) == path, "面板结果里带 blue_path（下一关手势要用）",
			str(_result.get("blue_path", [])))
