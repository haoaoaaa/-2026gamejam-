extends Control
## ============================================================================
##  《寻星》前日谈 —— 俯视角走位场景的宿主
## ============================================================================
##  它只做三件事：
##    1. 从 PreludeState 取出"要走的房间"（由对话脚本的 ["room", 房间id] 写入）
##    2. 在 add_child 之前把房间名推给 room_runtime（避开父 _ready 期间子类绑定未就绪的坑）
##    3. 走位结束（room_runtime 的"看完了"）后，由 room_runtime 自己切回对话场景
## ============================================================================

const ROOM_RUNTIME_SCRIPT := "res://scripts/ui/room_runtime.gd"
const FALLBACK_SCENE := "res://scenes/prelude/prelude_1.tscn"


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var room_id := str(PreludeState.get_flag("walk_room", ""))
	if room_id == "":
		push_error("[Walk] 没有 walk_room 标记，退回对话场景")
		# 【坑 60】_ready() 里直接 change_scene_to_file 会撞上
		# "Parent node is busy adding/removing children, remove_child() can't be called
		#  at this time."（Godot 4.7，父节点正在挂子节点）→ 转场失败、卡在走位场景。
		# 延到帧末再切。
		get_tree().call_deferred("change_scene_to_file", FALLBACK_SCENE)
		return

	var rt := Control.new()
	rt.name = "RoomRuntime"
	rt.set_script(load(ROOM_RUNTIME_SCRIPT))
	# 关键：先 configure，再 add_child
	rt.call("configure", room_id)
	add_child(rt)
	# 关键：必须让它真的铺满视口。代码 new 出来的 Control 落在 (0,0) 且尺寸为 0，
	# 只靠"画的时候用视口尺寸"不够——CanvasItem 的绘制会被自身的矩形裁掉，
	# 表现为房间只画出右边一块。
	rt.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
