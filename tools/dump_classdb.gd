extends SceneTree
# 生成 tools/godot_classes.json —— 给 tools/check_gdscript.mjs 用：
# 它靠这份类表判断代码里的 X.new() 到底是不是 Godot 内置类。
#
# 什么时候要重跑：
#   · 换了 Godot 版本（4.7 → 4.8 …）之后
#   · check_gdscript.mjs 报「XXX.new()：既不是 Godot 内置类」但你确定那个类是引擎自带的
# 怎么跑：
#   godot --headless --path . --script tools/dump_classdb.gd
#   （跑完 tools/godot_classes.json 会更新，把它一起提交）

func _init() -> void:
	var list := ClassDB.get_class_list()
	var arr: Array = []
	for n in list:
		arr.append(String(n))
	arr.sort()
	var path := "res://tools/godot_classes.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		printerr("[dump_classdb] 写不了 %s（错误码 %d）" % [path, FileAccess.get_open_error()])
		quit(1)
		return
	f.store_string(JSON.stringify(arr, "  "))
	f.close()
	print("[dump_classdb] 已写出 %d 个 Godot 内置类 → %s" % [arr.size(), path])
	quit(0)
