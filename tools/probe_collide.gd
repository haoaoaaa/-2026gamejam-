extends SceneTree
## 《寻星》家具碰撞自检
##
##   & 'E:\Godot_v4.7.2-stable_win64_console.exe' --headless --path 'E:\Godot\yongxian' --script tools/probe_collide.gd
##
## 只查三件事：
##   1. 哪些陈设挡路 —— 大件（书架 / 柜台 / 衣柜 / 床 / 书桌）挡，小道具（灯、晾衣绳、杯子）不挡；
##   2. 撞上去真的停得住（脚点不会钻进家具里）；
##   3. 贴着家具斜着走能横向滑开（不会卡死在边上）。
## 全程直接调 room_runtime 的 _try_move()，不依赖帧率，结果稳定。

const ROOMS_PATH := "res://data/prelude_rooms.json"
const RUNTIME_SCRIPT := "res://scripts/ui/room_runtime.gd"

## 每个房间期望的挡路块数（数据改了就要跟着改）
const EXPECT_SOLIDS := {
	"corridor_end": 0,     # 走廊里只有灯和墙，没有家具
	"library": 5,          # 两组书架 + 借还书台 + 还书小车 + 阅览桌
	"dorm_corridor": 0,    # 晾衣绳挂在头顶，不该挡路
	"dorm_room": 5,        # 衣柜 + 书架 + 两张书桌 + 床
	"dorm_after": 5,       # 二周目的案发现场：同一套寝室家具（衣柜 + 书架 + 两张书桌 + 床）
}

var _fails := 0
var _checks := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	print("========== 家具碰撞自检 ==========")

	print("— 挡路块数 —")
	for id in EXPECT_SOLIDS:
		var rt := _make_runtime(id)
		var n: int = (rt.get("_solids") as Array).size()
		_check(n == int(EXPECT_SOLIDS[id]),
				"%s：挡路 %d 块（期望 %d）" % [id, n, int(EXPECT_SOLIDS[id])])
		for s in (rt.get("_solids") as Array):
			var r: Rect2 = s
			print("      · Rect2(%.0f, %.0f, %.0f, %.0f)" % [r.position.x, r.position.y, r.size.x, r.size.y])
		rt.queue_free()

	print("— 小道具不挡路 —")
	var ce := _make_runtime("corridor_end")
	_check(not bool(ce.call("_blocked", Vector2(600, 160))), "走廊灯不挡路（脚点可以站在灯下面）")
	ce.queue_free()
	var dc := _make_runtime("dorm_corridor")
	_check(not bool(dc.call("_blocked", Vector2(800, 300))), "晾衣绳不挡路（人从底下走过去）")
	_check(not bool(dc.call("_blocked", Vector2(1500, 430))), "地上的水渍不挡路（可交互物件是热区，不是障碍）")
	dc.queue_free()
	var dr := _make_runtime("dorm_room")

	print("— 撞上去停得住 —")
	# 图书馆：从柜台下方一路往上顶，脚点应停在柜台下沿（y≈502）
	var lib := _make_runtime("library")
	var p := Vector2(1300, 600)
	for i in 40:
		p = lib.call("_try_move", p, Vector2(0, -12))
	_check(p.y >= 496.0 and p.y <= 508.0,
			"从柜台下方往上顶：停在 y=%.1f（期望 ≈504，柜台下沿 502）" % p.y)

	# 寝室：往上顶书桌（我的书桌碰撞块下沿 y=392，脚点停在 396）
	# 【位置变更】2026-10-14 按 Kerry「寝室太大了 / 比例不对」把寝室缩到 floor_w=1440 并重摆家具：
	#   我的书桌在 x 400..760（点心取 430，避开挡住它下面的椅子 x 520..640）。
	var q := Vector2(430, 600)
	for i in 40:
		q = dr.call("_try_move", q, Vector2(0, -12))
	_check(q.y >= 388.0 and q.y <= 400.0,
			"往上顶书桌：停在 y=%.1f（期望 ≈396，书桌下沿 392）" % q.y)

	# 寝室：往左顶衣柜（衣柜在 x 140..380，右沿 380 → 脚点停在 ≈376）
	var r2 := Vector2(700, 560)
	for i in 40:
		r2 = dr.call("_try_move", r2, Vector2(-12, 0))
	_check(r2.x >= 370.0 and r2.x <= 384.0,
			"往左顶衣柜：停在 x=%.1f（期望 ≈376，衣柜右沿 380）" % r2.x)

	print("— 贴着家具斜着走能滑开 —")
	var s := Vector2(1300, 600)
	for i in 20:
		s = lib.call("_try_move", s, Vector2(-8, -8))
	_check(s.x < 1160.0, "顶着柜台斜走：横向滑开了（x=%.1f，期望 <1160）" % s.x)
	_check(s.y >= 496.0, "…同时没有钻进柜台里（y=%.1f）" % s.y)

	print("— 出生点不许落在家具里 —")
	for id in EXPECT_SOLIDS:
		var rt2 := _make_runtime(id)
		var sp: Vector2 = rt2.get("_player")
		_check(not bool(rt2.call("_blocked", sp)),
				"%s：出生点 (%.0f, %.0f) 不在任何家具里" % [id, sp.x, sp.y])
		rt2.queue_free()

	print("=================================")
	print("共 %d 项检查，失败 %d 项" % [_checks, _fails])
	quit(1 if _fails > 0 else 0)


func _read_rooms() -> Dictionary:
	var f := FileAccess.open(ROOMS_PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		return {}
	var d: Dictionary = parsed
	return (d.get("rooms", {}) as Dictionary)


func _make_runtime(room_id: String) -> Node:
	var rt := Control.new()
	rt.set_script(load(RUNTIME_SCRIPT))
	rt.call("configure", room_id)
	root.add_child(rt)
	rt.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return rt


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("   ✓ " + what)
	else:
		_fails += 1
		print("   ✗ " + what)
