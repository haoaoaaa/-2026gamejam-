extends "res://scripts/prelude/prelude_base.gd"
## ============================================================================
##  《寻星》前日谈 · 第二幕「六楼的走廊」
## ============================================================================
##  十月末 · 6F 寝室走廊 → 刘忆开门 → 进寝室 → 三个选项 → 「我想请假一段时间」
##  伏笔：刘忆撒谎时薅刘海；开门后景的阳台门状态（开着一条缝），二周目第 6 关回收。
##  结束后显示「前日谈 完」，可回到开头。
##
##  【新链】前日谈在一周目六关之后、一周目收尾之前演，所以这一幕的出口不再是二周目：
##  按「继续」= 立起 prelude_done 标记 → 回一周目（week1_1.gd 读到标记就只播收尾
##  s6_ending，播完由它自己转二周目）。
## ============================================================================

## 一周目（前日谈演完回到它的收尾）
const WEEK1_SCENE := "res://scenes/week1/week1_1.tscn"
## 「前日谈已经演过」标记的键名，与 scripts/prelude/week1_1.gd 里的同名常量必须一致。
const PRELUDE_DONE_FLAG := "prelude_done"

func data_path() -> String:
	return "res://data/prelude_dialogue.json"


func chapter_id() -> String:
	return "act2"


func chapter_sequences() -> Array:
	return ["s0_open", "s1_room"]


func return_scene() -> String:
	return "res://scenes/prelude/prelude_2.tscn"


func _on_chapter_end() -> void:
	_build_ending()


## 收尾：留在「前日谈 完」的标题卡上，下方给「继续 · 回到第一天结尾」与「回到开头」。
## 新链的顺序是：第一天六关 → 前日谈 → 第一天收尾 → 第二天；
## 这里从前日谈回到**第一天最后那一段**（不是重播六关，也不是回到开头）。
func _build_ending() -> void:
	var layer := Control.new()
	layer.name = "Ending"
	layer.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(layer)
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 14)
	vb.modulate.a = 0.0
	layer.add_child(vb)
	vb.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	vb.offset_left = -240.0
	vb.offset_right = 240.0
	vb.offset_top = 150.0
	vb.offset_bottom = 300.0

	var btn := Button.new()
	btn.name = "GoEnding"
	btn.text = "继续 · 回到第一天结尾"
	btn.custom_minimum_size = Vector2(220, 48)
	PreludeUI.apply_button_skin(btn, true)
	btn.pressed.connect(_continue_after_prelude)
	vb.add_child(btn)

	var back := Button.new()
	back.name = "BackToStart"
	back.text = "回到开头"
	back.custom_minimum_size = Vector2(220, 40)
	PreludeUI.apply_button_skin(back, false)
	back.pressed.connect(_back_to_start)
	vb.add_child(back)

	var hint := Label.new()
	hint.text = "（前日谈 完。接下来回到第一天最后那一段——那里还有一句话没说。）"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.52, 0.51, 0.49))
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(hint)

	var tw := create_tween()
	tw.tween_property(vb, "modulate:a", 1.0, 0.8)


## 「继续」：立起 prelude_done，然后回一周目那一幕。
## 那边读到标记就只播收尾（s6_ending：["title", "第二天", "寝室里没有人"]），
## 播完由 week1_1.gd 自己转二周目 —— 所以这里不能直接跳二周目，也不能重播六关。
func _continue_after_prelude() -> void:
	PreludeState.set_flag(PRELUDE_DONE_FLAG, true)
	get_tree().change_scene_to_file(WEEK1_SCENE)


func _back_to_start() -> void:
	PreludeState.reset()
	# 存档也一起清掉：不清的话标题页会拿"前日谈 · 第 N 段"当"继续上次"，
	# 而玩家刚按的是"回到开头"。
	SaveGame.clear()
	# 【注意】reset() 会把 prelude_done 一起清掉，这正是"从头开始"要的：
	# 整条链（六关 → 前日谈 → 收尾 → 二周目）重新走一遍。
	get_tree().change_scene_to_file(WEEK1_SCENE)
