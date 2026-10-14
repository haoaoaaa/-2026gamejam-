extends SceneTree
## ============================================================================
##  《寻星》· 第 1 关「七色镜廊」求解器（headless）
## ============================================================================
##  用途：验证 Kerry 文档里的硬指标 ——「解唯一」，以及「蓝光走出来的必须是
##  与手势密码同向的那笔 S」。
##
##  穷举空间是**完整**的：每个黑框有三种选择（空 / 放某格 ／ / 放某格 ＼），
##  三个预设镜所在的框按其固定朝向算已占用（框里不能再加镜子），
##  镜子只能落在铅笔格 (x+y)%2==0 上。判"这一色接上了"的口径与面板
##  _is_lit() 完全一致：不闭环、同一面镜不被这束光踩两次、出口与出口方向都对应。
##
##  剪枝：某个黑框还没轮到之前，那一格里的镜子"未定"——如果某束光走到未定格，
##  就记 pending（不剪）；反之如果它已经确定的出界（不论对错）或撞进死循环，
##  后面的摆放再也改不了它，于是立刻剪掉。
##
##  跑法：
##    godot --headless --path <项目> --script tools/solve_maze.gd
##  退出码 0 = 求解器跑通（解数是否等于 1 会单独打印，供人判断）。
## ============================================================================

const PANEL_PATH := "res://scripts/week1/panel_maze.gd"
const GESTURE_TURNS := ["L>D", "D>R", "R>D", "D>L"]   # 手势密码那笔 S 的四次折向
const MAX_SHOW := 12                                  # 只展示前几个解，计数照全

var _p = null
var _frames := []            # 每个黑框的候选：{"cells": [Vector2i], "taken": bool}
var _frames_sorted := []     # 按"约束强的先来"排序后的框序号
var _placed := {}            # 玩家镜：Vector2i → "/" 或 "\\"
var _undecided := {}         # 还没轮到的框里、依然是空着的铅笔格 → 光路未定
var _count := 0
var _shown := []
var _pruned_pending := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var st := root.get_node_or_null("PreludeState")
	if st != null:
		st.call("reset")
	var s: Script = load(PANEL_PATH)
	if s == null:
		print("✗ 加载不了 %s" % PANEL_PATH)
		quit(1)
		return
	_p = s.new()
	_p.setup({"id": "maze"})
	root.add_child(_p)
	await process_frame

	_dump_answer()
	_build_frames()
	_search()
	_report()
	quit(0)


# ---------------------------------------------------------------- 答案速览
func _dump_answer() -> void:
	print("========== 七色镜廊 求解器 ==========")
	print("---------- 答案镜跑一遍（SOL_MIRRORS）")
	for c in _p.COLORS:
		var a: Dictionary = _p.ANSWERS[c]
		var r: Dictionary = _p._trace(_p.SOL_MIRRORS, a["in"] as Vector2i, a["in_dir"] as String)
		var ms: Array = []
		for m in r["mirrors"]:
			ms.append("%s%s" % [_name_of(m as Vector2i), str(_p.SOL_MIRRORS[m])])
		print("  %-7s 出口 %-8s 拐 %d 面镜 %s" % [
			c, _name_of(r["exit"] as Vector2i) + str(r["exit_dir"]),
			(r["turns"] as Array).size(), str(ms)])
	print("  蓝光折向 %s" % str(_turn_sig(_p._trace(_p.SOL_MIRRORS,
			(_p.ANSWERS["blue"]["in"] as Vector2i), (_p.ANSWERS["blue"]["in_dir"] as String)))))


func _name_of(c: Vector2i) -> String:
	return "(%d,%d)" % [c.x, c.y]


func _turn_sig(r: Dictionary) -> Array:
	var out: Array = []
	for t in r["turns"]:
		out.append("%s>%s" % [str(t[1]), str(t[2])])
	return out


# ---------------------------------------------------------------- 框与候选
func _build_frames() -> void:
	for fi in _p.FRAMES.size():
		var cells: Array = []
		var taken := false
		for c: Vector2i in _p.FRAMES[fi]:
			if _p._is_preset(c):
				taken = true          # 预设镜占着这个框，玩家不能再往里面放
			elif _p._mirror_cell(c):
				cells.append(c)
		_frames.append({"cells": cells, "taken": taken})
		_frames_sorted.append(fi)
	# 候选少的框先决策：既能早点剪枝，也方便看清是哪个框在制造多解
	_frames_sorted.sort_custom(func(a, b): return _frames[a]["cells"].size() < _frames[b]["cells"].size())
	for fi in _p.FRAMES.size():
		var f: Dictionary = _frames[fi]
		print("  框 %2d  格子 %2d  候选 %d %s" % [fi, (_p.FRAMES[fi] as Array).size(),
			0 if f["taken"] else (f["cells"] as Array).size(),
			"（预设镜占用，玩家不能放）" if f["taken"] else ""])


# ---------------------------------------------------------------- 搜索
func _search() -> void:
	_undecided = {}
	for fi in _p.FRAMES.size():
		var f: Dictionary = _frames[fi]
		if f["taken"]:
			continue
		for c in f["cells"]:
			_undecided[c] = true
	_dfs(0)
	print("（剪枝命中：确定性失败 %d 次；前缀判定为 pending 的次数 %d）" % [_count, _pruned_pending])


func _dfs(depth: int) -> void:
	if depth == _frames_sorted.size():
		if _all_lit():
			_count += 1
			if _shown.size() < MAX_SHOW:
				_shown.append(_placed.duplicate())
		return
	var fi: int = _frames_sorted[depth]
	var f: Dictionary = _frames[fi]
	# 先把这一框里的格子从"未定"里摘掉（轮到它了）
	var cells: Array = f["cells"]
	for c in cells:
		_undecided.erase(c)
	# 选择 1：这个框空着
	if _prefix_ok():
		_dfs(depth + 1)
	# 选择 2：放一块镜（预设镜占用过的框不能放）
	if not f["taken"]:
		for c in cells:
			for s in ["/", "\\"]:
				_placed[c] = s
				if _prefix_ok():
					_dfs(depth + 1)
				_placed.erase(c)
	# 回溯：把这一框的格子重新标成未定
	for c in cells:
		_undecided[c] = true


## 任一色只要"已经确定地失败"就剪掉
func _prefix_ok() -> bool:
	for c in _p.COLORS:
		if _status(c) == "fail":
			return false
	return true


func _all_lit() -> bool:
	for c in _p.COLORS:
		if _status(c) != "lit":
			return false
	return true


## lit / fail / pending —— 与面板 _is_lit() 的口径一致
func _status(c: String) -> String:
	var a: Dictionary = _p.ANSWERS[c]
	var entry: Vector2i = a["in"]
	var d: String = a["in_dir"]
	var out: Vector2i = a["out"]
	var out_dir: String = a["out_dir"]
	var cur: Vector2i = entry + (_p.DIRS[d] as Vector2i)
	var seen := {}
	var hit := {}
	var guard := 0
	while true:
		guard += 1
		if guard > 1024:
			return "fail"
		if not _p._inside(cur):
			if cur == out and d == out_dir:
				return "lit"
			return "fail"
		if _undecided.has(cur):
			_pruned_pending += 1
			return "pending"
		var key := "%d,%d,%s" % [cur.x, cur.y, d]
		if seen.has(key):
			return "fail"                       # 死循环（面板判 looped）
		seen[key] = true
		var s: String = _mirror_at(cur)
		if s != "":
			if hit.has(cur):
				return "fail"                   # 同一面镜被这束光踩两次（面板也判 false）
			hit[cur] = true
			d = _p.FLIP[s][d]
		cur = cur + (_p.DIRS[d] as Vector2i)
	return "fail"          # 循环里必定 return，这行只是让编译器的"所有分支都返回"过关


func _mirror_at(c: Vector2i) -> String:
	if _placed.has(c):
		return _placed[c]
	if _p._is_preset(c):
		return _p.SOL_MIRRORS[c]
	return ""


# ---------------------------------------------------------------- 结果
func _report() -> void:
	print("---------- 解")
	print("解数 = %d" % _count)
	for i in _shown.size():
		var sol: Dictionary = _shown[i]
		var keys: Array = sol.keys()
		keys.sort_custom(func(a, b): return (a.y * 100 + a.x) < (b.y * 100 + b.x))
		var parts: Array = []
		for k in keys:
			parts.append("%s%s" % [_name_of(k as Vector2i), str(sol[k])])
		var tag := "（就是答案）" if _same_as_answer(sol) else ""
		print("  解 %d：%s %s" % [i + 1, " ".join(parts), tag])
	# 答案本身必须在解里，而且蓝光必须是同向的 S
	var ans_ok := false
	for sol in _shown:
		if _same_as_answer(sol):
			ans_ok = true
	_check(ans_ok or _count == 0, "答案摆法本身是一个解")
	var tb: Dictionary = _p._trace(_p.SOL_MIRRORS, _p.ANSWERS["blue"]["in"] as Vector2i,
			_p.ANSWERS["blue"]["in_dir"] as String)
	_check(_turn_sig(tb) == GESTURE_TURNS,
			"蓝光折向 = 手势 S 的折向（同向，非镜像）", str(_turn_sig(tb)))
	_check(_count == 1, "解唯一", "实际 %d 个解" % _count)


func _same_as_answer(sol: Dictionary) -> bool:
	if sol.size() != _p.SOL_MIRRORS.size() - _p.PRESETS.size():
		return false
	for k in sol.keys():
		if str(_p.SOL_MIRRORS.get(k, "")) != str(sol[k]):
			return false
	return true


var _fails := 0


func _check(cond: bool, label: String, detail: String = "") -> void:
	if cond:
		print("  ✓ %s" % label)
	else:
		_fails += 1
		print("  ✗ %s%s" % [label, ("　［%s］" % detail) if detail != "" else ""])
