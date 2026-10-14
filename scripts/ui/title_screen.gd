extends Control
## ============================================================================
##  开场画面：封面
## ============================================================================
##  为什么单独做一个场景：Kerry 给的封面本来就是 16:9（换成了最新那版 3447x1944），
##  铺满 1280x720 不会变形；开场先看它一眼，再进一周目。
##
##  【坑 29】封面是从外面拷进来的图，**没有 .import**，ResourceLoader 看不见它，
##  必须走 PreludeUI.load_texture()（它内部会退回 Image.load_from_file）。
##
##  输入：点一下 / 空格 / 回车 都开始；开始后本节点不再吃输入。
##  读不出封面也不能卡住——退回一行"寻星"，照样能开始。
##  有存档时底部多一行「继续上次（第 N 章 · …）」，点它直接从存档处接着走。
## ============================================================================

const COVER := "res://assets/cover/chase_the_star.png"
const NEXT_SCENE := "res://scenes/week1/week1_1.tscn"

var _started := false
var _has_save := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.03, 0.05)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var cover := PreludeUI.load_texture(COVER)
	if cover != null:
		var tex := TextureRect.new()
		tex.name = "Cover"
		tex.texture = cover
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		# 封面原图就是 16:9，直接铺满，不用 KEEP_ASPECT（会留黑边）
		tex.stretch_mode = TextureRect.STRETCH_SCALE
		tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(tex)
	else:
		var fallback := Label.new()
		fallback.text = "寻　星"
		fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		fallback.add_theme_font_size_override("font_size", 72)
		fallback.add_theme_color_override("font_color", Color(0.93, 0.91, 0.86))
		fallback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(fallback)

	# 底部压一层暗色，保证提示文字在亮色封面上也读得清
	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.0, 0.0, 0.42)
	shade.anchor_left = 0.0
	shade.anchor_right = 1.0
	shade.anchor_top = 1.0
	shade.anchor_bottom = 1.0
	shade.offset_top = -132.0
	shade.offset_bottom = 0.0
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	var prompt := Label.new()
	prompt.name = "Prompt"
	prompt.text = "点击 / 空格　开始"
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.add_theme_font_size_override("font_size", 26)
	prompt.add_theme_color_override("font_color", Color(0.94, 0.92, 0.88))
	prompt.anchor_left = 0.0
	prompt.anchor_right = 1.0
	prompt.anchor_top = 1.0
	prompt.anchor_bottom = 1.0
	prompt.offset_top = -92.0
	prompt.offset_bottom = -48.0
	prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(prompt)

	# 有存档的时候：给两个按钮，并且【关掉"点一下就开始"】——
	# 不然玩家想看封面随手一点，一周目的进度就没了。
	_has_save = SaveGame.has_save()
	if _has_save:
		var resume := Button.new()
		resume.name = "ResumeButton"
		resume.text = "继续上次　%s" % SaveGame.label()
		PreludeUI.apply_button_skin(resume)
		resume.anchor_left = 0.5
		resume.anchor_right = 0.5
		resume.anchor_top = 1.0
		resume.anchor_bottom = 1.0
		resume.offset_left = -230.0
		resume.offset_right = 230.0
		resume.offset_top = -196.0
		resume.offset_bottom = -144.0
		resume.pressed.connect(_resume)
		add_child(resume)

		var fresh := Button.new()
		fresh.name = "NewGameButton"
		fresh.text = "从头开始（会清掉现在的进度）"
		PreludeUI.apply_button_skin(fresh)
		fresh.anchor_left = 0.5
		fresh.anchor_right = 0.5
		fresh.anchor_top = 1.0
		fresh.anchor_bottom = 1.0
		fresh.offset_left = -230.0
		fresh.offset_right = 230.0
		fresh.offset_top = -136.0
		fresh.offset_bottom = -96.0
		fresh.pressed.connect(_start_fresh)
		add_child(fresh)

		prompt.text = "点上面的按钮继续　（存档时间 %s）" % SaveGame.saved_at()
		prompt.add_theme_font_size_override("font_size", 20)

	# 封面自己的「设置 / 退出」（Kerry 第 1 条：封面也应有退出、读档、设置）。
	# 读档＝上面那颗「继续上次」；体积小的设置与退出摆右上角，按 Esc 也能叫出完整暂停菜单。
	_build_corner_button("设置", _on_settings_pressed, -22.0, 96.0)
	_build_corner_button("退出游戏", _on_quit_pressed, -126.0, 96.0)

	# 呼吸闪烁：不引入新资源，只用 Tween 改 alpha
	var tw := create_tween().set_loops()
	tw.tween_property(prompt, "modulate:a", 0.35, 1.1).set_trans(Tween.TRANS_SINE)
	tw.tween_property(prompt, "modulate:a", 1.0, 1.1).set_trans(Tween.TRANS_SINE)


## 右上角两颗小按钮（设置 / 退出）：锚在右上，offset 用负数表示"离右边多远"。
func _build_corner_button(text: String, cb: Callable, right_offset: float, btn_width: float) -> void:
	var b := Button.new()
	b.name = "Corner_" + text
	b.text = text
	PreludeUI.apply_button_skin(b)
	b.anchor_left = 1.0
	b.anchor_right = 1.0
	b.anchor_top = 0.0
	b.anchor_bottom = 0.0
	b.offset_left = right_offset - btn_width
	b.offset_right = right_offset
	b.offset_top = 22.0
	b.offset_bottom = 62.0
	b.pressed.connect(cb)
	add_child(b)


func _on_settings_pressed() -> void:
	var pm := get_node_or_null("/root/PauseMenu")
	if pm != null and pm.has_method("open_settings"):
		pm.call("open_settings")


func _on_quit_pressed() -> void:
	get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if _started:
		return
	# 有存档时只有空格/回车算"开始"（还要再确认一次），鼠标点击一律不算
	if _has_save and event is InputEventMouseButton:
		return
	var go := false
	if event is InputEventMouseButton:
		go = (event as InputEventMouseButton).pressed
	elif event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_select"):
		go = true
	if go:
		if _has_save:
			_resume()
		else:
			_start_fresh()


## 从头开始：清掉存档与上一轮的资料，别把旧笔记/旧旗标带进新档
func _start_fresh() -> void:
	if _started:
		return
	_started = true
	SaveGame.clear()
	PreludeState.reset()
	get_tree().change_scene_to_file(NEXT_SCENE)


## 继续上次：存档系统把资料灌回 PreludeState，然后去存档那一幕
func _resume() -> void:
	if _started:
		return
	var scene := SaveGame.request_resume()
	if scene == "":
		# 存档坏了/文件被删了：退回"从头开始"，别把玩家卡在标题页
		_started = false
		_has_save = false
		_start_fresh()
		return
	_started = true
	get_tree().change_scene_to_file(scene)
