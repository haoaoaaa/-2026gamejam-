extends "res://scripts/prelude/prelude_base.gd"
## ============================================================================
##  《寻星》前日谈 · 第一幕「书架关系」
## ============================================================================
##  场景1 走廊尽头 / 推理社门口  →  场景2 快下课时的审讯戏
##  →  场景3 蒙太奇与手写卡片      →  场景4 b 的裂缝
##  结束后显示「前日谈 · 第一幕 完」，转入 prelude_2。
## ============================================================================

func data_path() -> String:
	return "res://data/prelude_dialogue.json"


func chapter_id() -> String:
	return "act1"


func chapter_sequences() -> Array:
	return ["s0_open", "s1_book", "s2_cinema", "s3_montage", "s4_break"]


func return_scene() -> String:
	return "res://scenes/prelude/prelude_1.tscn"


func _on_chapter_end() -> void:
	if runtime != null:
		runtime.visible = false
	_show_intermission("第一幕 结束   ·   点击 / 空格  进入第二幕", _goto_prelude_2)
