extends SceneTree
## ============================================================================
##  《寻星》· 暂停菜单 + 设置 自检（headless）
## ============================================================================
##  Kerry 2026-10-14 这一轮新加的「Esc 暂停菜单 + 音量 / 自动播放设置」全在这条链上：
##    · GameSettings：默认值 / 写盘读回 / **手写配置**（坑 42：不能依赖 ConfigFile）
##                     / 坏行不崩也不改坏值
##    · PauseMenu：开关与 get_tree().paused 的联动 / 界面节点齐全且面板没被压成一条
##                 （progress.md 第 26 条）/ 六颗按钮与文案 / process_mode == ALWAYS
##                 （写成 WHEN_PAUSED 时游戏正常跑着 Esc 永远打不开菜单）
##                 / Esc 的两下开合 / _runtime() 的两种兜底
##    · blocks_pause 联动：dialogue_runtime（笔记 / 回看）与 room_runtime（笔记 / 弹窗）
##    · 自动播放：AUTO_ADVANCE_DELAY 的计时、autoplay 关掉后一次都不推进
##
##  ⚠ 这个探针**真的会写 user://xunxing_settings.cfg**（不然没法测读回），
##  所以开跑前先把玩家原本的设置备份下来，结束时（含失败路径）原样放回去。
##  存档 user://xunxing_save.json 也一并备份，并断言探针一个字节都没动过它。
##
##  跑法：
##      godot --headless --path <项目> --script tools/probe_pause.gd
##  退出码 0 = 全绿。
## ============================================================================

const CFG_PATH := "user://xunxing_settings.cfg"
const SAVE_PATH := "user://xunxing_save.json"
const GS_SCRIPT := "res://scripts/prelude/game_settings.gd"
const RUNTIME_SCRIPT := "res://scripts/ui/dialogue_runtime.gd"
const ROOM_SCRIPT := "res://scripts/ui/room_runtime.gd"
const WEEK1_DIALOGUE := "res://data/week1_dialogue.json"
## 抄一份常量进来做对照：探针以为的延迟必须跟脚本里的一致，否则断言等于没测
const AUTO_DELAY := 2.6

var _checks := 0
var _fails := 0
var _cfg_had := false
var _cfg_backup: PackedByteArray = PackedByteArray()
var _save_had := false
var _save_backup: PackedByteArray = PackedByteArray()
var _restored := false


func _initialize() -> void:
	_run()


func _check(ok: bool, what: String, extra := "") -> void:
	_checks += 1
	if ok:
		print("  ✓ ", what)
	else:
		_fails += 1
		print("  ✗ ", what, ("   ← " + extra) if extra != "" else "")


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _run() -> void:
	await process_frame
	print("========== 暂停菜单 / 设置 自检 ==========")
	_backup_files()

	# 两条路都行（见 HANDOFF：--script 模式里 autoload 标识符不保证存在），
	# 这里用 get_node_or_null 查；查不到就直接收摊，断言不针对空气。
	var gs := root.get_node_or_null("GameSettings")
	var pm := root.get_node_or_null("PauseMenu")
	_check(gs != null, "GameSettings 自动加载在（音量 / 自动播放就是它）")
	_check(pm != null, "PauseMenu 自动加载在")
	if gs == null or pm == null:
		_finish()
		return

	var gscm: Dictionary = (gs.get_script() as GDScript).get_script_constant_map()
	_check(str(gscm.get("CFG_PATH", "")) == CFG_PATH,
			"GameSettings 的 CFG_PATH 就是探针备份/还原的那一份",
			"脚本里写的是 %s" % str(gscm.get("CFG_PATH", "")))

	await _test_settings_default()
	await _test_settings_round_trip(gs)
	await _test_settings_handwritten()
	await _test_settings_junk()
	await _test_pause_switch(pm)
	await _test_pause_layout(pm)
	await _test_pause_buttons(pm)
	await _test_pause_process_mode(pm)
	await _test_pause_input(pm)
	await _test_runtime_lookup(pm)
	await _test_dialogue_blocks_pause(gs)
	await _test_room_blocks_pause()
	await _test_autoplay(gs)
	_test_player_files_untouched()

	_cleanup()
	_finish()


# ============================================================================
#  ① ~ ④ GameSettings
# ============================================================================

## 新建一个**不在树上**的 GameSettings 实例（_ready 不会跑），手动 load_settings()。
## 这样测的是"从零读一份配置"，不会被 autoload 里已经加载过的值污染。
func _fresh_settings() -> Node:
	var s: GDScript = load(GS_SCRIPT)
	var n: Node = s.new()
	n.call("load_settings")
	return n


func _test_settings_default() -> void:
	print("-- ① 默认值（没有配置文件时）")
	_remove_cfg()
	var n := _fresh_settings()
	_check(n != null, "能新建一个 GameSettings 实例")
	if n == null:
		return
	_check(absf(float(n.get("volume")) - 0.8) < 0.0001,
			"没有配置文件时 volume 默认 0.8", "实际 %s" % str(n.get("volume")))
	_check(bool(n.get("autoplay")) == false,
			"没有配置文件时 autoplay 默认 false", "实际 %s" % str(n.get("autoplay")))
	n.free()
	await process_frame


func _test_settings_round_trip(gs: Node) -> void:
	print("-- ② set_volume / set_autoplay 写盘 → 另起实例读回")
	gs.call("set_volume", 0.35)
	_check(absf(float(gs.get("volume")) - 0.35) < 0.0001,
			"set_volume(0.35) 改了内存里的值", "实际 %s" % str(gs.get("volume")))
	var b := _fresh_settings()
	_check(b != null and absf(float(b.get("volume")) - 0.35) < 0.001,
			"另一个实例 load_settings() 读回 0.35",
			"实际 %s" % (str(b.get("volume")) if b != null else "无实例"))
	if b != null:
		b.free()

	gs.call("set_autoplay", true)
	var c := _fresh_settings()
	_check(c != null and bool(c.get("autoplay")), "autoplay 切成 true 能读回",
			"实际 %s" % (str(c.get("autoplay")) if c != null else "无实例"))
	if c != null:
		c.free()

	gs.call("set_autoplay", false)
	var d := _fresh_settings()
	_check(d != null and not bool(d.get("autoplay")), "autoplay 再切回 false 也能读回",
			"实际 %s" % (str(d.get("autoplay")) if d != null else "无实例"))
	if d != null:
		d.free()

	gs.call("set_volume", 5.0)
	_check(absf(float(gs.get("volume")) - 1.0) < 0.0001,
			"set_volume 超范围会被夹到 1.0", "实际 %s" % str(gs.get("volume")))
	await process_frame


func _test_settings_handwritten() -> void:
	print("-- ③ 手写配置（开头 # 注释行 + 空行）自己按行解析（坑 42）")
	_write_cfg("# 《寻星》设置（手写的，开头就是注释行）\n\nvolume=0.5\nautoplay=1\n")
	var n := _fresh_settings()
	_check(n != null and absf(float(n.get("volume")) - 0.5) < 0.0001,
			"读了开头带 # 与空行的配置：volume == 0.5",
			"实际 %s" % (str(n.get("volume")) if n != null else "无实例"))
	_check(n != null and bool(n.get("autoplay")), "同一份配置里 autoplay == 1 也读到了",
			"实际 %s" % (str(n.get("autoplay")) if n != null else "无实例"))
	if n != null:
		n.free()

	# 引号可有可无、true / on 都算开（脚本里第 77、82 行的两条规则）
	_write_cfg("; 分号注释也是注释\n\nvolume=\"0.25\"\nautoplay=true\n")
	var m := _fresh_settings()
	_check(m != null and absf(float(m.get("volume")) - 0.25) < 0.0001,
			"值带引号也能读（volume=\"0.25\" → 0.25）",
			"实际 %s" % (str(m.get("volume")) if m != null else "无实例"))
	_check(m != null and bool(m.get("autoplay")), "autoplay=true 也算开",
			"实际 %s" % (str(m.get("autoplay")) if m != null else "无实例"))
	if m != null:
		m.free()
	await process_frame


func _test_settings_junk() -> void:
	print("-- ④ 坏行不会让解析崩，也不会把值改坏")
	# 整份都是坏行：应当一份都没认出来，保持新建实例的默认值
	_write_cfg("这不是一行配置\n\n=x\n;;;;\nunknown_key=1\n")
	var n := _fresh_settings()
	_check(n != null and absf(float(n.get("volume")) - 0.8) < 0.0001 and not bool(n.get("autoplay")),
			"整份全是坏行时不崩、且保留默认 0.8 / false",
			"实际 %s / %s" % [str(n.get("volume")) if n != null else "无实例",
					str(n.get("autoplay")) if n != null else "无实例"])
	if n != null:
		n.free()

	# 好行夹着坏行：坏行只是被跳过，前面读到的值不会被改坏
	_write_cfg("# 注释\n\nvolume=0.5\nautoplay=1\n这不是一行配置\n=x\n")
	var m := _fresh_settings()
	_check(m != null and absf(float(m.get("volume")) - 0.5) < 0.0001 and bool(m.get("autoplay")),
			"好行后面跟坏行：值不受影响（0.5 / true）",
			"实际 %s / %s" % [str(m.get("volume")) if m != null else "无实例",
					str(m.get("autoplay")) if m != null else "无实例"])
	if m != null:
		m.free()

	# 乱值行：不该打断解析，后面的好值照样生效
	_write_cfg("volume=not_a_number\nautoplay=maybe\nvolume=0.5\nautoplay=1\n")
	var k := _fresh_settings()
	_check(k != null and absf(float(k.get("volume")) - 0.5) < 0.0001 and bool(k.get("autoplay")),
			"乱值行不打断解析，后面的好值生效（0.5 / true）",
			"实际 %s / %s" % [str(k.get("volume")) if k != null else "无实例",
					str(k.get("autoplay")) if k != null else "无实例"])
	if k != null:
		k.free()
	await process_frame


# ============================================================================
#  ⑤ ~ ⑩ PauseMenu
# ============================================================================

func _test_pause_switch(pm: Node) -> void:
	print("-- ⑤ 开关与 get_tree().paused 的联动")
	_check(not bool(pm.call("is_open")), "初次 is_open() == false",
			"实际 %s" % str(pm.call("is_open")))
	pm.call("open")
	await _frames(2)
	_check(bool(pm.call("is_open")), "open() 之后 is_open() == true")
	_check(paused, "open() 之后 get_tree().paused == true", "实际 %s" % str(paused))
	pm.call("close")
	await _frames(2)
	_check(not bool(pm.call("is_open")), "close() 之后 is_open() 复位")
	_check(not paused, "close() 之后 get_tree().paused 复位", "实际 %s" % str(paused))


func _test_pause_layout(pm: Node) -> void:
	print("-- ⑥ 界面节点齐全 / 面板没被压成一条（progress.md 第 26 条）")
	pm.call("open")
	await _frames(3)
	pm.call("_ensure_built")      # 再调一次，必须幂等
	await _frames(2)

	var cnt := 0
	for c in pm.get_children():
		if str(c.name) == "PauseRoot":
			cnt += 1
	_check(cnt == 1, "_ensure_built() 调两次也只有一份 PauseRoot", "实际 %d 份" % cnt)

	var proot := pm.get("_root") as Control
	_check(proot != null and str(proot.name) == "PauseRoot", "PauseRoot 是个 Control")
	if proot == null:
		pm.call("close")
		return

	var panel := proot.get_node_or_null("PausePanel") as PanelContainer
	_check(panel != null, "PauseRoot/PausePanel 在")
	for nm in ["PauseMain", "PauseSettings", "VolumeSlider", "AutoplayCheck", "PauseMsg"]:
		var n := proot.find_child(str(nm), true, false)
		_check(n != null, "在 PauseRoot/PausePanel 里按名字找得到 %s" % str(nm))
	if panel != null:
		# 【这条防的就是"没给全屏锚点 → 容器被压成一条"那个坑】
		_check(panel.size.x > 200.0 and panel.size.y > 200.0,
				"PausePanel 尺寸没被压成一条（宽高都 > 200）", "实际 %s" % str(panel.size))
	pm.call("close")
	await _frames(2)


func _test_pause_buttons(pm: Node) -> void:
	print("-- ⑦ 六颗按钮与文案")
	var main := pm.get("_main_box") as VBoxContainer
	_check(main != null, "PauseMain 是 VBoxContainer")
	if main == null:
		return
	var texts: Array = []
	var non_button := 0
	for c in main.get_children():
		if c is Button:
			texts.append(str((c as Button).text))
		else:
			non_button += 1
	_check(texts.size() == 6, "PauseMain 里恰好 6 颗按钮",
			"实际 %d 颗：%s" % [texts.size(), str(texts)])
	_check(non_button == 0, "PauseMain 里除了按钮没别的控件", "另有 %d 个" % non_button)
	var want := ["继续游戏", "保存进度", "读取存档", "设置", "回到主菜单", "退出游戏"]
	_check(texts == want, "六颗按钮的文案与顺序都对", "实际 %s" % str(texts))


func _test_pause_process_mode(pm: Node) -> void:
	print("-- ⑧ process_mode 必须是 ALWAYS")
	_check(pm.process_mode == Node.PROCESS_MODE_ALWAYS,
			"process_mode == PROCESS_MODE_ALWAYS",
			"实际 %d（ALWAYS=%d，WHEN_PAUSED=%d）"
					% [pm.process_mode, Node.PROCESS_MODE_ALWAYS, Node.PROCESS_MODE_WHEN_PAUSED])
	# 真正会出事的那一半：游戏**没**暂停时也必须能收输入。
	# 写成 WHEN_PAUSED 的话 can_process() 在这里是 false → 正常运行中 Esc 永远打不开菜单。
	var was := paused
	paused = false
	_check(pm.can_process(), "游戏没暂停时 PauseMenu 依然 can_process()（WHEN_PAUSED 会挂在这里）")
	paused = true
	_check(pm.can_process(), "游戏暂停时 PauseMenu 也 can_process()（按钮点得动）")
	paused = was


func _test_pause_input(pm: Node) -> void:
	print("-- ⑨ Esc（直接构造 ui_cancel 事件喂给 _input）")
	pm.call("close")
	await _frames(2)
	_check(not bool(pm.call("is_open")), "先摆成关着的状态")

	pm.call("_input", _cancel_event())
	await _frames(2)
	_check(bool(pm.call("is_open")), "没有覆盖层时，Esc 打开暂停菜单")
	_check(paused, "打开菜单的同时游戏暂停了", "实际 paused=%s" % str(paused))

	pm.call("_input", _cancel_event())
	await _frames(2)
	_check(not bool(pm.call("is_open")), "再按一次 Esc 关掉菜单")
	_check(not paused, "关掉菜单的同时游戏恢复", "实际 paused=%s" % str(paused))


func _test_runtime_lookup(pm: Node) -> void:
	print("-- ⑩ _runtime() 的兜底与取到")
	var was_cs := current_scene

	# A. 没有 current_scene（--script 模式的常态）
	current_scene = null
	_check(pm.call("_runtime") == null, "current_scene 为 null 时 _runtime() 返回 null（不崩）")

	# B. 有 current_scene，但那个节点没有 runtime 属性
	var host := Node.new()
	host.name = "ProbeFakeScene"
	root.add_child(host)
	current_scene = host
	_check(pm.call("_runtime") == null, "场景没有 runtime 属性时 _runtime() 返回 null（不崩）")

	# C. 有 runtime 属性时能取到（否则"永远返回 null"也能骗过上面两条）
	var host_scr := GDScript.new()
	host_scr.source_code = "extends Node\n\nvar runtime: Node = null\n"
	host_scr.reload()
	var host2 := Node.new()
	host2.name = "ProbeHostScene"
	host2.set_script(host_scr)
	root.add_child(host2)
	var inner := Node.new()
	inner.name = "ProbeRuntime"
	root.add_child(inner)
	host2.set("runtime", inner)
	current_scene = host2
	_check(pm.call("_runtime") == inner, "场景有 runtime 属性时能取到它",
			"实际 %s" % str(pm.call("_runtime")))
	_check(not bool(pm.call("_blocks_pause")),
			"运行时没有 blocks_pause() 方法时，_blocks_pause() 为 false")

	# D. 运行时说"我这儿有覆盖层"时，Esc 要让给它
	var blk_scr := GDScript.new()
	blk_scr.source_code = "extends Control\n\nfunc blocks_pause() -> bool:\n\treturn true\n"
	blk_scr.reload()
	var blk := Control.new()
	blk.name = "ProbeBlockingRuntime"
	blk.set_script(blk_scr)
	root.add_child(blk)
	host2.set("runtime", blk)
	_check(bool(pm.call("_blocks_pause")), "运行时 blocks_pause() 为真时 _blocks_pause() 为真")
	pm.call("close")
	await _frames(2)
	pm.call("_input", _cancel_event())
	await _frames(2)
	_check(not bool(pm.call("is_open")), "覆盖层开着时 Esc 让给运行时，不弹暂停菜单")
	_check(not paused, "让给运行时的时候也不会顺手把游戏暂停")

	current_scene = was_cs
	pm.call("close")
	blk.queue_free()
	inner.queue_free()
	host2.queue_free()
	host.queue_free()
	await _frames(2)


# ============================================================================
#  ⑪ ⑫ blocks_pause 联动
# ============================================================================

func _test_dialogue_blocks_pause(gs: Node) -> void:
	print("-- ⑪ dialogue_runtime.blocks_pause()")
	gs.set("autoplay", false)
	var rs: GDScript = load(RUNTIME_SCRIPT)
	var rt: Control = rs.new()
	_check(rt != null, "能新建 dialogue_runtime")
	if rt == null:
		return
	_check(rt.has_method("blocks_pause") and rt.has_method("save_now"),
			"运行时这轮新增的 blocks_pause() / save_now() 都在")
	rt.call("configure", "week1", WEEK1_DIALOGUE, [])
	root.add_child(rt)
	await _frames(3)

	_check(not bool(rt.call("blocks_pause")), "没有覆盖层时 blocks_pause() == false",
			"实际 %s" % str(rt.call("blocks_pause")))
	rt.call("_toggle_notes")
	await _frames(2)
	_check(bool(rt.call("blocks_pause")), "_toggle_notes() 之后 blocks_pause() == true")
	rt.call("_open_history")
	await _frames(2)
	_check(bool(rt.call("blocks_pause")), "_open_history() 之后 blocks_pause() == true",
			"实际 %s" % str(rt.call("blocks_pause")))
	rt.call("_toggle_history")
	await _frames(2)
	_check(not bool(rt.call("blocks_pause")), "两个面板都关掉之后回到 false",
			"实际 %s" % str(rt.call("blocks_pause")))
	rt.queue_free()
	await _frames(2)


func _test_room_blocks_pause() -> void:
	print("-- ⑫ room_runtime.blocks_pause()")
	var rs: GDScript = load(ROOM_SCRIPT)
	var rr: Control = rs.new()
	_check(rr != null, "能新建 room_runtime")
	if rr == null:
		return
	_check(rr.has_method("blocks_pause"), "room_runtime 这轮新增的 blocks_pause() 在")
	rr.call("configure", "dorm_room")
	root.add_child(rr)
	await _frames(3)

	_check(not bool(rr.call("blocks_pause")), "刚入树（笔记关着、没有弹窗）时 blocks_pause() == false",
			"实际 %s" % str(rr.call("blocks_pause")))
	rr.call("_toggle_notes")
	await _frames(2)
	_check(bool(rr.call("blocks_pause")), "笔记面板开着 → blocks_pause() == true")
	rr.call("_toggle_notes")
	await _frames(2)
	_check(not bool(rr.call("blocks_pause")), "笔记再关掉 → 回到 false",
			"实际 %s" % str(rr.call("blocks_pause")))
	rr.set("_popup", true)
	_check(bool(rr.call("blocks_pause")), "物件弹窗开着（_popup）时也是 true")
	rr.set("_popup", false)
	_check(not bool(rr.call("blocks_pause")), "弹窗收掉之后回到 false")
	rr.queue_free()
	await _frames(2)


# ============================================================================
#  ⑬ 自动播放
# ============================================================================

func _test_autoplay(gs: Node) -> void:
	print("-- ⑬ 自动播放剧情（autoplay）")
	var rs: GDScript = load(RUNTIME_SCRIPT)
	var cm: Dictionary = rs.get_script_constant_map()
	_check(absf(float(cm.get("AUTO_ADVANCE_DELAY", -1.0)) - AUTO_DELAY) < 0.0001,
			"运行时里的 AUTO_ADVANCE_DELAY == %s" % str(AUTO_DELAY),
			"实际 %s" % str(cm.get("AUTO_ADVANCE_DELAY")))

	gs.set("autoplay", false)
	var rt: Control = rs.new()
	# 自造一段小剧本，绕开真实章节里的小游戏面板（别的 agent 正在改那些）
	rt.set("chapter_id", "probe_pause")
	rt.set("dialogue", {"t1": [["n", "第一句"], ["n", "第二句"], ["n", "第三句"], ["n", "第四句"]]})
	rt.set("sequence_order", ["t1"])
	root.add_child(rt)
	await _frames(3)

	await _settle_line(rt)
	_check(bool(rt.get("_line_ready")), "走起来之后某句台词已经打完（_line_ready == true）")
	_check(int(rt.get("_row_index")) == 1, "第一句已经上屏（_row_index == 1）",
			"实际 %d" % int(rt.get("_row_index")))

	var base := int(rt.get("_row_index"))
	rt.set("_auto_timer", 0.0)
	gs.set("autoplay", true)
	# ↓ 下面这一串**不 await**：一 await 就会跑 _process 里的 _auto_advance，计时就不受控了
	rt.call("_auto_advance", 1.0)
	rt.call("_auto_advance", 1.0)
	_check(int(rt.get("_row_index")) == base,
			"累计 2.0s < %ss：前两次不推进" % str(AUTO_DELAY),
			"实际 row_index=%d（期望 %d）" % [int(rt.get("_row_index")), base])
	rt.call("_auto_advance", 1.0)
	_check(int(rt.get("_row_index")) == base + 1,
			"累计 3.0s ≥ %ss：推进了一句" % str(AUTO_DELAY),
			"实际 row_index=%d（期望 %d）" % [int(rt.get("_row_index")), base + 1])
	for _i in 7:
		rt.call("_auto_advance", 1.0)
	_check(int(rt.get("_row_index")) == base + 1,
			"十次调用只推进一步（新那句还没打完，不会连着翻页）",
			"实际 row_index=%d（期望 %d）" % [int(rt.get("_row_index")), base + 1])
	gs.set("autoplay", false)

	# 关掉之后同样的十次调用一次都不许推进
	await _settle_line(rt)
	_check(bool(rt.get("_line_ready")), "第二句也打完了（下面这十次才算数）")
	var base2 := int(rt.get("_row_index"))
	rt.set("_auto_timer", 0.0)
	for _i in 10:
		rt.call("_auto_advance", 1.0)
	_check(int(rt.get("_row_index")) == base2,
			"autoplay 关掉后，同样的十次调用一次都不推进",
			"实际 row_index=%d（期望 %d）" % [int(rt.get("_row_index")), base2])
	rt.queue_free()
	await _frames(2)


## 替玩家把当前这句推完（打字机没完就 skip，完了就等 _process 自己置位）
func _settle_line(rt: Node) -> void:
	var guard := 0
	while not bool(rt.get("_line_ready")) and guard < 90:
		rt.call("_on_advance")
		await process_frame
		guard += 1


# ============================================================================
#  ⑭ 玩家的真实文件
# ============================================================================

func _test_player_files_untouched() -> void:
	print("-- ⑭ 不污染玩家的真实文件")
	_check(_same_as_backup(SAVE_PATH, _save_had, _save_backup),
			"探针没动过玩家的存档 user://xunxing_save.json（字节一致）")
	# 设置文件这一轮本来就是被探针反复读写的，只要求"收尾时能还原"，
	# 还原动作放在 _cleanup() 里（含失败路径）。


# ============================================================================
#  工具
# ============================================================================

func _cancel_event() -> InputEventAction:
	var ev := InputEventAction.new()
	ev.action = "ui_cancel"
	ev.pressed = true
	return ev


func _remove_cfg() -> void:
	if FileAccess.file_exists(CFG_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG_PATH))


func _write_cfg(text: String) -> void:
	var f := FileAccess.open(CFG_PATH, FileAccess.WRITE)
	if f == null:
		push_error("[probe] 写不了 %s" % CFG_PATH)
		return
	f.store_string(text)
	f.close()


func _same_as_backup(path: String, had: bool, backup: PackedByteArray) -> bool:
	var now := FileAccess.file_exists(path)
	if not had:
		return not now
	if not now:
		return false
	return FileAccess.get_file_as_bytes(path) == backup


# ============================================================================
#  备份 / 还原 / 收尾
# ============================================================================

func _backup_files() -> void:
	if FileAccess.file_exists(CFG_PATH):
		_cfg_had = true
		_cfg_backup = FileAccess.get_file_as_bytes(CFG_PATH)
		print("（已备份玩家现有设置：%d 字节）" % _cfg_backup.size())
	else:
		print("（玩家本来没有设置文件）")
	if FileAccess.file_exists(SAVE_PATH):
		_save_had = true
		_save_backup = FileAccess.get_file_as_bytes(SAVE_PATH)
		print("（已备份玩家现有存档：%d 字节）" % _save_backup.size())


func _restore_files() -> void:
	if _restored:
		return
	_restored = true
	# 设置
	if _cfg_had:
		var f := FileAccess.open(CFG_PATH, FileAccess.WRITE)
		if f != null:
			f.store_buffer(_cfg_backup)
			f.close()
		print("（玩家设置已还原）")
	else:
		_remove_cfg()
		print("（探针写的设置文件已删除）")
	# 存档
	if _save_had:
		if not _same_as_backup(SAVE_PATH, _save_had, _save_backup):
			var f2 := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
			if f2 != null:
				f2.store_buffer(_save_backup)
				f2.close()
			print("（玩家存档被动过，已还原）")
	else:
		if FileAccess.file_exists(SAVE_PATH):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
			print("（探针写的存档已删除）")


## 把现场恢复干净：不暂停、不占着 current_scene、没有遗留节点
func _cleanup() -> void:
	paused = false
	current_scene = null
	var pm := root.get_node_or_null("PauseMenu")
	if pm != null:
		pm.call("close")
	for n in ["ProbeFakeScene", "ProbeHostScene", "ProbeRuntime", "ProbeBlockingRuntime"]:
		var node := root.get_node_or_null(n)
		if node != null:
			root.remove_child(node)
			node.free()
	_restore_files()


func _finish() -> void:
	_restore_files()
	print("=========================================")
	print("共 %d 项检查，失败 %d 项" % [_checks, _fails])
	quit(1 if _fails > 0 else 0)
