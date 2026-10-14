class_name PreludeUI
extends RefCounted
## ============================================================================
##  《寻星》前日谈 —— 通用 UI 工具箱
## ============================================================================
##  设计原则（很重要，改之前先读）：
##  1. 所有节点都在代码里 new 出来并【直接持有强类型引用】，
##     不使用 %UniqueName / get_node("长/路径/字符串")，
##     从根本上避免 "Node not found" 与空引用。
##  2. 每个组件都是 Control，只在自己的 _ready 里创建子节点，
##     父级拿到实例后调用 setup 系列方法即可。
##  3. 这里的 UI 是整个前日谈共用的；一周目/二周目可以继续复用。
## ============================================================================

# ---------------------------------------------------------------- 配色常量
const C_INK      := Color(0.93, 0.91, 0.86)      # 主文字，暖白
const C_INK_DIM  := Color(0.62, 0.60, 0.56)      # 次要文字
const C_NAME     := Color(0.96, 0.80, 0.55)      # 说话人名字，暖黄
const C_ACCENT   := Color(0.70, 0.34, 0.32)      # 强调色，暗红
const C_PANEL    := Color(0.055, 0.06, 0.075, 0.86)
const C_PANEL_HI := Color(0.10, 0.11, 0.14, 0.92)
const C_CARD_BG  := Color(0.09, 0.085, 0.10, 0.95)
const C_LINE     := Color(0.85, 0.80, 0.70, 0.16)
const C_DISABLED := Color(0.42, 0.41, 0.40)

# ---------------------------------------------------------------- 字号常量
const FS_NAME := 22
const FS_TEXT := 19
const FS_CARD := 17
const FS_TIP  := 14


# ============================================================================
#  皮肤工具
# ============================================================================

## 做一张纯色贴图，用于 StyleBoxTexture —— 比 StyleBoxFlat 更稳，
## 且可以自由控制拉伸（例如只在水平方向拉伸做出"细线"效果）。
static func solid_texture(c: Color) -> ImageTexture:
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(c)
	return ImageTexture.create_from_image(img)


# ============================================================================
#  立绘背景遮罩（只抠"人物外轮廓之外的纸"）
# ============================================================================

## 已经烘好的遮罩缓存：贴图路径 → ImageTexture
static var _bg_mask_cache: Dictionary = {}


## 取立绘的"背景遮罩"。R 通道 = 1 表示"与画面四边连通的纸"，可以被抠掉；
## 0 表示人物内部（含眼镜反光、衬衫受光面、脸部高光），一律保留。
##
## 为什么要这么麻烦：canvas_item 的 shader 里没法高效判断"连通性"，
## 而"按亮度一刀切"会把人物内部的白色一起挖掉（身上破洞）。
## 所以在这里用 CPU 做一次从四边向内的 flood fill，把结果烘成贴图交给 shader。
## 读一张贴图，两种来源都认：
##   ① 被编辑器导入过的资源（有 .import）→ ResourceLoader；
##   ② 直接从外面拷进来的图（**没有 .import**，ResourceLoader.exists() 会是 false）
##      → 运行期用 Image.load_from_file 兜底。
## 【坑】只写 ① 的话，从源码跑起来时这些图会"看不见"，而编辑器里又是好的，
## 很容易误判成代码写错（坑 29 就是这个）。
static func load_texture(path: String) -> Texture2D:
	var p := path.strip_edges()
	if p == "":
		return null
	if ResourceLoader.exists(p):
		var res := ResourceLoader.load(p)
		if res is Texture2D:
			return res
	if FileAccess.file_exists(p):
		var img := Image.load_from_file(p)
		if img != null:
			return ImageTexture.create_from_image(img)
	return null


static func get_bg_mask(path: String, src: Texture2D) -> ImageTexture:
	if _bg_mask_cache.has(path):
		return _bg_mask_cache[path] as ImageTexture
	var img := src.get_image()
	if img == null:
		return null
	var m := build_bg_mask(img)
	if m == null:
		return null
	var tex := ImageTexture.create_from_image(m)
	_bg_mask_cache[path] = tex
	return tex


## 找出"人物外轮廓之外的背景"，烘成遮罩贴图交给 shader。
## 返回与传入图像同尺寸、FORMAT_RGBA8，R 通道用作遮罩：
##   R = 1 → 背景，可以清掉
##   R = 0 → 人物内部（含白色的衬衫受光面、脸、眼镜反光），一律原样保留
##
## 【判据只有一条：连通性，绝对不看亮度】这两张立绘本身带 alpha（纸是透明的，
## 四角 a=0），于是：
##   · 透明的像素                       → 背景
##   · 不透明、但**面积很小的孤岛**      → 背景（画面里漂着的小残点、纸屑）
##     （以前是"从四边 BFS 吃掉透明或很亮的连通区"，靠亮度判断"哪块是纸"）
##   · 其余不透明像素（人物本体）        → 一律原样保留
##
## 【血泪教训·Kerry 报的"内部的白色也被扣了"】这张立绘的**白色连帽衫和整张脸**
## 亮度就在 0.90~1.00，跟白纸一样亮，所以"按亮度一刀切"必然误伤：
##   · 衣服受光面与背景之间没有暗线挡着 → BFS 顺着亮区直接漏进衣服里，
##     整件白衣服被判成纸抠掉（实测 39,417 px，其中亮于 0.85 的 37,443 px）；
##   · 脸整个是纯白（luma = 1.000）→ 又被 shader 那条"内部硬阈值 interior_cut"削一刀
##     （实测 24,045 px，占人物内部 13.8%），于是脸直接没了。
## "人物身上的白"和"纸的白"在亮度上根本分不开，只能靠**连通性 / 面积**区分。
## 谁要是把亮度判据加回来，人物就会再次破洞、脸再次消失。
##
## 前提：立绘必须带 alpha 通道（背景透明）。目前两张都是四角 a=0。
## 为了让 BFS 够快，先降到 COARSE_W 宽做连通性判断（连通性是低频信息，
## 缩放不影响），再把结果按比例放回原尺寸。
static func build_bg_mask(src: Image) -> Image:
	const COARSE_W := 384
	const ALPHA_SOLID := 0.5    # alpha 高于此值算"人物实体"
	const ALPHA_BG := 0.35      # alpha 低于此值算"透明"
	const SPEC_FRAC := 0.003    # 面积小于全图这个比例的不透明孤岛 = 背景残渣
	var sw := src.get_width()
	var sh := src.get_height()
	if sw <= 2 or sh <= 2:
		return null

	# ---- 0. 降到低分辨率
	var cw := mini(COARSE_W, sw)
	var ch := maxi(2, int(round(float(sh) * float(cw) / float(sw))))
	var small := Image.create_from_data(sw, sh, false, src.get_format(), src.get_data())
	small.resize(cw, ch, Image.INTERPOLATE_BILINEAR)

	# ---- 1. 逐列的剪影跨度（用 alpha）
	var top := PackedInt32Array()
	var bot := PackedInt32Array()
	top.resize(cw)
	bot.resize(cw)
	for x in cw:
		var t := -1
		var b := -1
		for y in ch:
			if small.get_pixel(x, y).a >= ALPHA_SOLID:
				if t < 0:
					t = y
				b = y
		top[x] = t
		bot[x] = b
	# 用邻列补洞：单列偶尔取不到实体（落在纯线稿的极细处），
	# 直接跳过会让那一列整条被当成背景，剪影上出现一道口子。
	for x in cw:
		if top[x] < 0:
			for d in range(1, cw):
				if x - d >= 0 and top[x - d] >= 0:
					top[x] = top[x - d]
					bot[x] = bot[x - d]
					break
				if x + d < cw and top[x + d] >= 0:
					top[x] = top[x + d]
					bot[x] = bot[x + d]
					break

	# ---- 1.5 不透明连通块：面积太小的当"背景残渣"
	#      （画面里漂着的小点、纸屑。只看面积/连通性，不看亮度——见文件头）
	var comp := PackedInt32Array()
	comp.resize(cw * ch)
	comp.fill(-1)                 # -1 = 透明（不是人物实体）
	var comp_size := PackedInt32Array()
	var spec := PackedByteArray()
	spec.resize(cw * ch)
	for y in ch:
		for x in cw:
			var ci := y * cw + x
			if comp[ci] != -1 or small.get_pixel(x, y).a < ALPHA_SOLID:
				continue
			var cid := comp_size.size()
			comp_size.append(0)
			var q := PackedInt32Array([ci])
			comp[ci] = cid
			var qh := 0
			while qh < q.size():
				var cur := q[qh]
				qh += 1
				comp_size[cid] = comp_size[cid] + 1
				var qx := cur % cw
				var qy := cur / cw
				if qx > 0 and comp[cur - 1] == -1 and small.get_pixel(qx - 1, qy).a >= ALPHA_SOLID:
					comp[cur - 1] = cid
					q.append(cur - 1)
				if qx < cw - 1 and comp[cur + 1] == -1 and small.get_pixel(qx + 1, qy).a >= ALPHA_SOLID:
					comp[cur + 1] = cid
					q.append(cur + 1)
				if qy > 0 and comp[cur - cw] == -1 and small.get_pixel(qx, qy - 1).a >= ALPHA_SOLID:
					comp[cur - cw] = cid
					q.append(cur - cw)
				if qy < ch - 1 and comp[cur + cw] == -1 and small.get_pixel(qx, qy + 1).a >= ALPHA_SOLID:
					comp[cur + cw] = cid
					q.append(cur + cw)
	var max_spec := int(float(cw * ch) * SPEC_FRAC)
	for i in cw * ch:
		var sid := comp[i]
		if sid >= 0 and comp_size[sid] <= max_spec:
			spec[i] = 1

	# ---- 2. 标记"可通行"像素：剪影之外是背景；剪影之内只有透明或残渣才算候选
	var cand := PackedByteArray()
	cand.resize(cw * ch)
	for x in cw:
		for y in ch:
			var i := y * cw + x
			var c := small.get_pixel(x, y)
			if top[x] < 0 or y < top[x] or y > bot[x]:
				cand[i] = 1   # 剪影之外 → 背景
				continue
			# 剪影之内：**只看 alpha**。白衬衫 / 脸的高光亮度能到 1.0，
			# 拿亮度当判据会把人物一起吃掉（见文件头血泪教训）。
			cand[i] = 1 if (c.a < ALPHA_BG or spec[i] == 1) else 0

	# ---- 3. 从四边向内 BFS（暗线稿会把它挡住）
	var bg := PackedByteArray()
	bg.resize(cw * ch)
	var stack := PackedInt32Array()
	for x in cw:
		var i0 := x
		if cand[i0] == 1:
			bg[i0] = 1
			stack.append(i0)
		var bi := (ch - 1) * cw + x
		if cand[bi] == 1:
			bg[bi] = 1
			stack.append(bi)
	for y in ch:
		var li := y * cw
		if cand[li] == 1:
			bg[li] = 1
			stack.append(li)
		var ri := y * cw + (cw - 1)
		if cand[ri] == 1:
			bg[ri] = 1
			stack.append(ri)
	var head := 0
	while head < stack.size():
		var i := stack[head]
		head += 1
		var x := i % cw
		var y := i / cw
		if x > 0:
			var n := i - 1
			if cand[n] == 1 and bg[n] == 0:
				bg[n] = 1
				stack.append(n)
		if x < cw - 1:
			var n2 := i + 1
			if cand[n2] == 1 and bg[n2] == 0:
				bg[n2] = 1
				stack.append(n2)
		if y > 0:
			var n3 := i - cw
			if cand[n3] == 1 and bg[n3] == 0:
				bg[n3] = 1
				stack.append(n3)
		if y < ch - 1:
			var n4 := i + cw
			if cand[n4] == 1 and bg[n4] == 0:
				bg[n4] = 1
				stack.append(n4)

	# ---- 4. 按比例放回原尺寸
	var out := Image.create(sw, sh, false, Image.FORMAT_RGBA8)
	for y in sh:
		var cy := mini(ch - 1, y * ch / sh)
		for x in sw:
			var cx2 := mini(cw - 1, x * cw / sw)
			var on := bg[cy * cw + cx2]
			out.set_pixel(x, y, Color(1.0, 1.0, 1.0, 1.0) if on == 1 else Color(0.0, 0.0, 0.0, 1.0))
	return out


## 常用面板皮肤：半透明深色 + 细描边 + 圆角
static func panel_skin(bg: Color = C_PANEL, border: Color = C_LINE, radius: int = 6) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 18.0
	sb.content_margin_right = 18.0
	sb.content_margin_top = 14.0
	sb.content_margin_bottom = 14.0
	return sb


## 做一条分隔细线（Control）
static func hline(w: float = 100.0, c: Color = C_LINE) -> ColorRect:
	var r := ColorRect.new()
	r.color = c
	r.custom_minimum_size = Vector2(w, 1)
	# w <= 0 视为"占满可用宽度"，用于面板内分隔线
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL if w <= 0.0 else Control.SIZE_SHRINK_BEGIN
	return r


## 统一风格的按钮皮肤
## 注意：这里逐个 new 出 StyleBoxFlat，不用 duplicate() as StyleBoxFlat，
## 避免运行时强转失败。
static func _button_skin_box(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 16.0
	sb.content_margin_right = 16.0
	sb.content_margin_top = 10.0
	sb.content_margin_bottom = 10.0
	return sb

static func apply_button_skin(b: Button, accent: bool = false) -> void:
	var bg_normal := Color(0.20, 0.12, 0.12, 0.95) if accent else Color(0.13, 0.135, 0.16, 0.92)
	var bg_hover := Color(0.32, 0.17, 0.16, 0.98) if accent else Color(0.21, 0.22, 0.26, 0.96)
	var edge := Color(0.95, 0.86, 0.66, 0.5)

	b.add_theme_stylebox_override("normal", _button_skin_box(bg_normal, C_LINE))
	b.add_theme_stylebox_override("hover", _button_skin_box(bg_hover, edge))
	b.add_theme_stylebox_override("pressed", _button_skin_box(Color(0.09, 0.10, 0.12, 0.98), edge))
	b.add_theme_stylebox_override("focus", _button_skin_box(bg_hover, edge))
	b.add_theme_stylebox_override("disabled", _button_skin_box(Color(0.09, 0.09, 0.10, 0.6), Color(0.4, 0.4, 0.4, 0.3)))
	b.add_theme_color_override("font_color", C_INK)
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	b.add_theme_color_override("font_pressed_color", C_INK_DIM)
	b.add_theme_color_override("font_disabled_color", C_DISABLED)
	b.add_theme_font_size_override("font_size", FS_TEXT)
	b.focus_mode = Control.FOCUS_ALL


# ============================================================================
#  打字机
# ============================================================================
class Typewriter:
	extends RefCounted

	const CPS := 34.0            # 每秒显示字符数
	const MIN_TOTAL := 0.25      # 即使文本很短也至少用这么久

	var _rtl: RichTextLabel = null
	var _plain: String = ""
	var _elapsed := 0.0
	var _duration := 0.0
	var _active := false

	func begin(rtl: RichTextLabel, text: String) -> void:
		_rtl = rtl
		_plain = text
		_elapsed = 0.0
		# 极短文本也不要瞬间跳出来，留一点呼吸感
		_duration = maxf(MIN_TOTAL, float(text.length()) / CPS)
		if _rtl:
			_rtl.text = text
			_rtl.visible_characters = 0
		_active = true

	func tick(delta: float) -> void:
		if not _active or _rtl == null:
			return
		_elapsed += delta
		var total := _plain.length()
		var shown := int(floor((_elapsed / _duration) * float(total)))
		if shown >= total:
			_rtl.visible_characters = -1
			_active = false
		else:
			_rtl.visible_characters = shown

	func is_typing() -> bool:
		return _active

	func skip_to_end() -> void:
		if _rtl:
			_rtl.visible_characters = -1
		_active = false


# ============================================================================
#  立绘
# ============================================================================

## 角色立绘。原图是竖版（约 1644x2480），这里统一按高度缩放并贴底。
class Portrait:
	extends Control

	var _tex: TextureRect = null
	var _placeholder: Control = null
	var _name_label: Label = null
	var _side := 1   # 1 = 站在右侧说话，-1 = 左侧
	var _mat: ShaderMaterial = null

	## 立绘合成 shader：白纸剔除 + 边缘溶解 + 轮廓边光
	const FRAME_SHADER := "res://shaders/portrait_frame.gdshader"

	func setup(tex_path: String, display_name: String, side: int = 1, target_height: float = 660.0, slot: int = 0) -> void:
		_side = side
		name = "Portrait_" + display_name
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		# 立绘容器自己铺满父级，下面的 _tex / 占位块用绝对 offset 摆位。
		# 必须用 set_anchors_and_offsets_preset()：set_anchors_preset() 不改 offset，
		# 会让这个容器保持 0 尺寸，立绘就整块看不见了。
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

		_tex = TextureRect.new()
		_tex.name = "Art"
		_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		# 关键：忽略原图尺寸，按下面设的 offset 拉伸，这样才能把 1600×2480 的
		# 大立绘缩到 660 高，而不是让 TextureRect 被原图最小尺寸撑爆。
		_tex.stretch_mode = TextureRect.STRETCH_SCALE
		_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_tex)

		# 占位（贴图缺失时显示）：一个色块 + 名字，不卡素材
		_placeholder = Control.new()
		_placeholder.name = "Placeholder"
		_placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_placeholder)
		_placeholder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

		var block := ColorRect.new()
		block.color = Color(0.16, 0.17, 0.20, 0.55)
		block.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_placeholder.add_child(block)
		block.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		block.offset_top = 120.0
		block.offset_bottom = -60.0

		_name_label = Label.new()
		_name_label.text = display_name
		_name_label.add_theme_font_size_override("font_size", 64)
		_name_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.18))
		_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_placeholder.add_child(_name_label)
		_name_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

		# 加载真实立绘（失败则保留占位）
		# 【坑】这里必须走 load_texture()：从外面拷进来的图没有 .import，
		# ResourceLoader.exists() 会是 false；只写 ResourceLoader 的话，
		# 这些图在"从源码运行"时永远显示不出来（编辑器里却一切正常）。
		var path := tex_path.strip_edges()
		var tex := PreludeUI.load_texture(path)
		if tex != null:
			_tex.texture = tex
			_placeholder.visible = false
		else:
			push_warning("[Prelude] 未找到立绘贴图：%s（已使用占位）" % path)

		# 合成材质：只抠掉"人物外轮廓之外的纸"，四周化开、轮廓加边光，
		# 和手绘场景统一。注意要先把 bg_mask 烘好塞进去——
		# 否则 shader 会按默认的 hint_default_white 处理，等于"整张都算背景"。
		if _tex.texture != null and ResourceLoader.exists(FRAME_SHADER):
			var sh: Shader = load(FRAME_SHADER)
			if sh != null:
				_mat = ShaderMaterial.new()
				_mat.shader = sh
				var mask := PreludeUI.get_bg_mask(path, _tex.texture)
				if mask != null:
					_mat.set_shader_parameter("bg_mask", mask)
				_tex.material = _mat

		# 立绘的横向位置与高度
		var vw := 1280.0
		# 【素材】原图只有李星/刘忆两张时，宽高比是固定值 ≈ 0.663。后来 Kerry 补了
		# 同学 C/D/E、班主任、宿管五张，比例各不相同（0.52 ~ 0.73），再按 0.663 拉伸
		# 就会把人拉胖/拉瘦。所以按贴图自己的宽高比算宽度。
		var aspect := 0.663
		if _tex.texture != null and _tex.texture.get_height() > 0:
			aspect = float(_tex.texture.get_width()) / float(_tex.texture.get_height())
		var cw := target_height * aspect
		# 同侧的第 N 个人往里错开一点，免得几个立绘完全重叠（只看得见最后一个）。
		# 【坑 53】96px 太窄：立绘宽约 370~440px，脑袋只错开 96px 等于还是叠在一起
		# （Kerry 报「二周目和几个同学对话的时候，右侧两个立绘重叠了」）。
		# 现在按 150px 错位，并且 height 由调用方按总人数降一档 —— 脑袋既横向拉开、
		# 又因为变矮而纵向错开，五个人同框也能看清每张脸。
		var push := float(slot) * 150.0
		if _side > 0:
			_tex.offset_left = vw - cw - 40.0 - push
			_tex.offset_right = vw - 40.0 - push
		else:
			_tex.offset_left = 40.0 + push
			_tex.offset_right = 40.0 + cw + push
		_tex.offset_top = 720.0 - target_height
		_tex.offset_bottom = 720.0

		# 占位块自己铺满整个立绘容器；不跟着 _tex 的 offset 走，
		# 否则贴图缺失时会跟着那个"按立绘宽度"的窄矩形一起变窄。
		_placeholder.offset_left = 0.0
		_placeholder.offset_right = 0.0
		_placeholder.offset_top = 0.0
		_placeholder.offset_bottom = 0.0

		# 底部渐隐，避免立绘硬切在对话框边缘
		var fade := ColorRect.new()
		fade.name = "BottomFade"
		fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fade.color = Color(0.07, 0.075, 0.09, 0.85)
		add_child(fade)
		fade.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		fade.offset_top = -170.0
		fade.offset_bottom = 0.0
		move_child(fade, 0)

	func set_dim(dimmed: bool) -> void:
		# 有 shader 时走后景变暗 + 聚焦两个参数：正在说话的那位 dim=0 / focus=1
		# （不吃边缘溶解、不吃软过渡、再提一点亮），听众 dim=0.60 / focus=0。
		if _mat != null:
			_mat.set_shader_parameter("dim", 0.60 if dimmed else 0.0)
			_mat.set_shader_parameter("focus", 0.0 if dimmed else 1.0)
			return
		var c := Color(0.60, 0.61, 0.65, 1.0) if dimmed else Color(1, 1, 1, 1)
		if _placeholder.visible:
			_placeholder.modulate = c
		else:
			_tex.modulate = c

	func has_art() -> bool:
		return _tex != null and _tex.texture != null

	## 临时覆写 shader 参数（比如第二幕开场把刘忆打亮、李星压暗）
	func set_shader_param(key: String, value: Variant) -> void:
		if _mat != null:
			_mat.set_shader_parameter(key, value)


# ============================================================================
#  对话框
# ============================================================================
class DialogueBox:
	extends Control

	signal advance_requested()      # 玩家点了"继续"（点全屏 / 空格 / 回车）
	signal line_finished()          # 某一行打字结束（给"点击直接看完整句"用）

	## 对话框根的实高（像素）。改这个值就等于改对话框高度。
	const BOX_HEIGHT := 232.0

	var _panel: PanelContainer = null
	var _name_label: Label = null
	var _text: RichTextLabel = null
	var _hint: Label = null
	var _typewriter: Typewriter = null
	var _hint_time := 0.0

	func _init() -> void:
		name = "DialogueBox"
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _ready() -> void:
		_apply_layout()
		_panel = PanelContainer.new()
		_panel.name = "Panel"
		_panel.add_theme_stylebox_override("panel", PreludeUI.panel_skin(PreludeUI.C_PANEL, Color(0.85, 0.80, 0.70, 0.22), 6))
		_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_panel)
		# 对话框根的底边贴着屏幕底：留边用 "相对底边" 的负 offset 表达
		_panel.anchor_left = 0.0
		_panel.anchor_right = 1.0
		_panel.anchor_top = 1.0
		_panel.anchor_bottom = 1.0
		_panel.offset_left = 80.0
		_panel.offset_right = -80.0
		_panel.offset_top = -BOX_HEIGHT + 12.0
		_panel.offset_bottom = -26.0
		_build_contents()

	func _apply_layout() -> void:
		set_anchor(SIDE_LEFT, 0.0)
		set_anchor(SIDE_RIGHT, 1.0)
		set_anchor(SIDE_TOP, 1.0)
		set_anchor(SIDE_BOTTOM, 1.0)
		offset_left = 0.0
		offset_right = 0.0
		offset_top = -BOX_HEIGHT
		offset_bottom = 0.0

	## 对话框内部的排版：说话人 / 分隔线 / 正文 / 继续提示
	func _build_contents() -> void:
		var vbox := VBoxContainer.new()
		vbox.name = "VB"
		vbox.add_theme_constant_override("separation", 8)
		vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_panel.add_child(vbox)

		# —— 说话人
		_name_label = Label.new()
		_name_label.name = "SpeakerLabel"
		_name_label.add_theme_font_size_override("font_size", PreludeUI.FS_NAME)
		_name_label.add_theme_color_override("font_color", PreludeUI.C_NAME)
		_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(_name_label)

		var sep := PreludeUI.hline(240.0, Color(0.85, 0.80, 0.70, 0.24))
		sep.name = "NameSep"
		vbox.add_child(sep)

		# —— 正文
		_text = RichTextLabel.new()
		_text.name = "BodyText"
		_text.bbcode_enabled = true
		_text.scroll_active = false
		_text.fit_content = false
		_text.custom_minimum_size = Vector2(0, 108)
		_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_text.add_theme_font_size_override("normal_font_size", PreludeUI.FS_TEXT)
		_text.add_theme_color_override("default_color", PreludeUI.C_INK)
		_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(_text)

		# —— 继续提示
		_hint = Label.new()
		_hint.name = "Hint"
		_hint.text = "▼  点击 / 空格  继续"
		_hint.add_theme_font_size_override("font_size", PreludeUI.FS_TIP)
		_hint.add_theme_color_override("font_color", PreludeUI.C_INK_DIM)
		_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(_hint)

		_typewriter = Typewriter.new()

	func _process(delta: float) -> void:
		if _typewriter:
			_typewriter.tick(delta)
		# 提示符呼吸闪烁
		_hint_time += delta
		if _hint:
			_hint.modulate.a = 0.35 + 0.5 * absf(sin(_hint_time * 2.2))

	## 显示一行文本。
	## hide_name = true 时不画说话人标签（旁白、以及"心里"的独白都走这条路：
	## Kerry 要求画面上不出现「旁白」「（心里）」这类标签，独白靠立绘高亮告诉玩家是谁在说）。
	func show_line(speaker: String, text: String, hide_name: bool = false) -> void:
		if _name_label == null:
			return
		if hide_name or speaker.strip_edges() == "":
			_name_label.text = ""
			_name_label.visible = false
		else:
			_name_label.text = speaker
			_name_label.visible = true
			_name_label.add_theme_color_override("font_color", PreludeUI.C_NAME)
		_typewriter.begin(_text, text)

	func skip() -> void:
		if _typewriter:
			_typewriter.skip_to_end()

	func is_typing() -> bool:
		return _typewriter != null and _typewriter.is_typing()

	func set_hint_text(t: String) -> void:
		if _hint:
			_hint.text = t

	func set_hint_visible(v: bool) -> void:
		if _hint:
			_hint.visible = v


# ============================================================================
#  选项菜单
# ============================================================================
class ChoiceMenu:
	extends Control

	signal chosen(index: int)

	var _box: VBoxContainer = null
	var _buttons: Array[Button] = []
	var _pending: String = ""

	func _init() -> void:
		name = "ChoiceMenu"
		# 关键：选项面板打开时吞掉所有鼠标事件，
		# 这样"点击推进"的全屏按钮不会被误触发。
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _ready() -> void:
		visible = false
		# 进树后再铺满：_init 阶段还没有父级，铺满会算成 0×0（选项就点不到了）
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var dim := ColorRect.new()
		dim.name = "Dim"
		dim.color = Color(0.03, 0.03, 0.04, 0.42)
		dim.mouse_filter = Control.MOUSE_FILTER_STOP
		add_child(dim)
		dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

		var anchor := MarginContainer.new()
		anchor.name = "Anchor"
		anchor.add_theme_constant_override("margin_left", 130)
		anchor.add_theme_constant_override("margin_right", 130)
		anchor.add_theme_constant_override("margin_top", 150)
		anchor.add_theme_constant_override("margin_bottom", 300)
		anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(anchor)
		anchor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

		_box = VBoxContainer.new()
		_box.name = "Options"
		_box.alignment = BoxContainer.ALIGNMENT_END
		_box.add_theme_constant_override("separation", 12)
		_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		anchor.add_child(_box)

	## prompt：选项上方的提示语（可空）
	func open(prompt: String, options: Array) -> void:
		_pending = prompt
		for b in _buttons:
			b.queue_free()
		_buttons.clear()

		if prompt.strip_edges() != "":
			var head := Label.new()
			head.text = prompt
			head.add_theme_font_size_override("font_size", PreludeUI.FS_TIP)
			head.add_theme_color_override("font_color", PreludeUI.C_INK_DIM)
			head.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_box.add_child(head)

		for i in options.size():
			var opt_text := str(options[i])
			var b := Button.new()
			b.text = opt_text
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			b.custom_minimum_size = Vector2(0, 48)
			PreludeUI.apply_button_skin(b)
			b.pressed.connect(_on_pressed.bind(i))
			_box.add_child(b)
			_buttons.append(b)

		visible = true
		# 延迟一帧抓焦点，保证键盘也能选
		if _buttons.size() > 0:
			_buttons[0].call_deferred("grab_focus")

	func _on_pressed(index: int) -> void:
		for b in _buttons:
			b.disabled = true
		visible = false
		chosen.emit(index)

	## 强行收起（例如剧情走到标题卡，要把选项面板收掉）
	func close() -> void:
		visible = false
		for b in _buttons:
			b.queue_free()
		_buttons.clear()

	func is_open() -> bool:
		return visible


# ============================================================================
#  记录卡（右上角弹出）
# ============================================================================
class RecordCard:
	extends Control

	signal closed()

	var _panel: PanelContainer = null
	var _title: Label = null
	var _body: RichTextLabel = null
	var _tag: Label = null
	var _tween: Tween = null
	var _showing := false

	func _init() -> void:
		name = "RecordCard"
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _ready() -> void:
		_panel = PanelContainer.new()
		_panel.name = "Panel"
		_panel.add_theme_stylebox_override("panel", PreludeUI.panel_skin(PreludeUI.C_CARD_BG, Color(0.86, 0.72, 0.46, 0.42), 4))
		_panel.mouse_filter = Control.MOUSE_FILTER_STOP
		_panel.custom_minimum_size = Vector2(400, 0)
		_panel.gui_input.connect(_on_panel_input)
		add_child(_panel)
		# 先铺满（拿到 1280×720），再按右上角定位面板
		set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		_panel.offset_left = -430.0
		_panel.offset_right = -30.0
		_panel.offset_top = 34.0
		_panel.offset_bottom = 34.0

		var vbox := VBoxContainer.new()
		vbox.name = "VB"
		vbox.add_theme_constant_override("separation", 6)
		vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_panel.add_child(vbox)

		var head := HBoxContainer.new()
		head.name = "Head"
		head.add_theme_constant_override("separation", 8)
		head.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(head)

		_title = Label.new()
		_title.name = "Title"
		_title.text = "记录卡"
		_title.add_theme_font_size_override("font_size", PreludeUI.FS_TIP)
		_title.add_theme_color_override("font_color", Color(0.90, 0.76, 0.50))
		_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head.add_child(_title)

		var spacer := Control.new()
		spacer.name = "Spacer"
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head.add_child(spacer)

		_tag = Label.new()
		_tag.name = "Tag"
		_tag.text = "点击收起"
		_tag.add_theme_font_size_override("font_size", PreludeUI.FS_TIP - 2)
		_tag.add_theme_color_override("font_color", PreludeUI.C_INK_DIM)
		_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head.add_child(_tag)

		_body = RichTextLabel.new()
		_body.name = "Body"
		_body.bbcode_enabled = true
		_body.fit_content = true
		_body.scroll_active = false
		_body.custom_minimum_size = Vector2(0, 40)
		_body.add_theme_font_size_override("normal_font_size", PreludeUI.FS_CARD)
		_body.add_theme_color_override("default_color", PreludeUI.C_INK)
		_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(_body)

		modulate.a = 0.0
		visible = false

	func show_card(index: int, text: String) -> void:
		_title.text = "记录卡 · 第 %d 张" % (index + 1)
		_body.text = text
		visible = true
		_showing = true
		if _tween and _tween.is_valid():
			_tween.kill()
		modulate.a = 0.0
		_panel.position.y = 12.0
		_tween = create_tween()
		_tween.set_parallel(true)
		_tween.tween_property(self, "modulate:a", 1.0, 0.22)
		_tween.tween_property(_panel, "position:y", 0.0, 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	func hide_card() -> void:
		if not _showing:
			return
		_showing = false
		if _tween and _tween.is_valid():
			_tween.kill()
		_tween = create_tween()
		_tween.tween_property(self, "modulate:a", 0.0, 0.18)
		_tween.tween_callback(func() -> void:
			visible = false
			closed.emit()
		)

	func is_showing() -> bool:
		return _showing

	func _on_panel_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				hide_card()
				accept_event()


# ============================================================================
#  笔记页（Tab / Esc 打开，查看已收集的记录卡）
# ============================================================================
class NotesPanel:
	extends Control

	signal closed()

	var _list: VBoxContainer = null
	var _empty_hint: Label = null

	func _init() -> void:
		name = "NotesPanel"
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _ready() -> void:
		visible = false
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var dim := ColorRect.new()
		dim.name = "Dim"
		dim.color = Color(0.02, 0.02, 0.03, 0.80)
		dim.mouse_filter = Control.MOUSE_FILTER_STOP
		add_child(dim)
		dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

		var panel := PanelContainer.new()
		panel.name = "Book"
		panel.add_theme_stylebox_override("panel", PreludeUI.panel_skin(Color(0.085, 0.082, 0.09, 0.98), Color(0.86, 0.72, 0.46, 0.30), 4))
		# 必须先给全屏锚点，否则 offset_right/bottom 为负数、PanelContainer 会被压成一条
		panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		panel.offset_left = 220.0
		panel.offset_right = -220.0
		panel.offset_top = 80.0
		panel.offset_bottom = -80.0
		add_child(panel)

		var vbox := VBoxContainer.new()
		vbox.name = "VB"
		vbox.add_theme_constant_override("separation", 10)
		panel.add_child(vbox)

		var head := HBoxContainer.new()
		head.name = "Head"
		vbox.add_child(head)

		var title := Label.new()
		title.name = "Title"
		title.text = "我的笔记  ·  行为 → 情感 → 例证"
		title.add_theme_font_size_override("font_size", 20)
		title.add_theme_color_override("font_color", Color(0.90, 0.76, 0.50))
		head.add_child(title)

		var spacer := Control.new()
		spacer.name = "Spacer"
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(spacer)

		var close_btn := Button.new()
		close_btn.name = "Close"
		close_btn.text = "合上  (Tab / Esc)"
		PreludeUI.apply_button_skin(close_btn)
		close_btn.pressed.connect(close)
		head.add_child(close_btn)

		vbox.add_child(PreludeUI.hline(0.0, Color(0.85, 0.80, 0.70, 0.22)))

		var scroll := ScrollContainer.new()
		scroll.name = "Scroll"
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		vbox.add_child(scroll)

		_list = VBoxContainer.new()
		_list.name = "List"
		_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_list.add_theme_constant_override("separation", 12)
		scroll.add_child(_list)

		_empty_hint = Label.new()
		_empty_hint.name = "EmptyHint"
		_empty_hint.text = "（还没有记下任何东西。）"
		_empty_hint.add_theme_font_size_override("font_size", PreludeUI.FS_TEXT)
		_empty_hint.add_theme_color_override("font_color", PreludeUI.C_INK_DIM)
		_empty_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(_empty_hint)

	func refresh(cards: Array) -> void:
		if _list == null:
			return
		for child in _list.get_children():
			if child == _empty_hint:
				continue
			child.queue_free()
		_empty_hint.visible = cards.is_empty()
		for i in cards.size():
			var row := PanelContainer.new()
			row.add_theme_stylebox_override("panel", PreludeUI.panel_skin(Color(0.12, 0.115, 0.13, 0.9), Color(0.85, 0.80, 0.70, 0.14), 3))
			row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

			var rb := RichTextLabel.new()
			rb.bbcode_enabled = true
			rb.fit_content = true
			rb.scroll_active = false
			rb.custom_minimum_size = Vector2(0, 34)
			rb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			rb.add_theme_font_size_override("normal_font_size", PreludeUI.FS_TEXT)
			rb.add_theme_color_override("default_color", PreludeUI.C_INK)
			rb.text = "[color=#e0c07a]%d.[/color]  %s" % [i + 1, str(cards[i])]
			row.add_child(rb)
			_list.add_child(row)

	func open(cards: Array) -> void:
		refresh(cards)
		visible = true

	func close() -> void:
		visible = false
		closed.emit()

	func is_open() -> bool:
		return visible


class HistoryPanel:
	extends Control
	## 回看：把已经显示过的台词按顺序列出来，最后一行（当前这句）高亮。
	## 玩家按 R / 滚轮向上打开；滚轮或 ↑↓ 上下翻；R / Esc / 空白处点一下合上。

	signal closed()

	var _scroll: ScrollContainer = null
	var _list: VBoxContainer = null
	var _empty_hint: Label = null
	var _count_label: Label = null

	func _init() -> void:
		name = "HistoryPanel"
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _ready() -> void:
		visible = false
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

		var dim := ColorRect.new()
		dim.name = "Dim"
		dim.color = Color(0.02, 0.02, 0.03, 0.86)
		dim.mouse_filter = Control.MOUSE_FILTER_STOP
		add_child(dim)
		dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

		var panel := PanelContainer.new()
		panel.name = "Book"
		panel.add_theme_stylebox_override("panel", PreludeUI.panel_skin(Color(0.085, 0.082, 0.09, 0.98), Color(0.86, 0.72, 0.46, 0.30), 4))
		# 同上：没有全屏锚点时 offset_right/bottom 是负数，面板会被压成"只有表头一条"
		panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		panel.offset_left = 170.0
		panel.offset_right = -170.0
		panel.offset_top = 60.0
		panel.offset_bottom = -60.0
		add_child(panel)

		var vbox := VBoxContainer.new()
		vbox.name = "VB"
		vbox.add_theme_constant_override("separation", 10)
		panel.add_child(vbox)

		var head := HBoxContainer.new()
		head.name = "Head"
		vbox.add_child(head)

		var title := Label.new()
		title.name = "Title"
		title.text = "回看  ·  说过的话"
		title.add_theme_font_size_override("font_size", 20)
		title.add_theme_color_override("font_color", Color(0.90, 0.76, 0.50))
		head.add_child(title)

		_count_label = Label.new()
		_count_label.name = "Count"
		_count_label.add_theme_font_size_override("font_size", PreludeUI.FS_TIP)
		_count_label.add_theme_color_override("font_color", PreludeUI.C_INK_DIM)
		_count_label.add_theme_constant_override("outline_size", 0)
		head.add_child(_count_label)

		var spacer := Control.new()
		spacer.name = "Spacer"
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(spacer)

		var hint := Label.new()
		hint.name = "Hint"
		hint.text = "滚轮 / ↑↓ 翻　·　"
		hint.add_theme_font_size_override("font_size", PreludeUI.FS_TIP)
		hint.add_theme_color_override("font_color", PreludeUI.C_INK_DIM)
		head.add_child(hint)

		var close_btn := Button.new()
		close_btn.name = "Close"
		close_btn.text = "合上  (R / Esc)"
		PreludeUI.apply_button_skin(close_btn)
		close_btn.pressed.connect(close)
		head.add_child(close_btn)

		vbox.add_child(PreludeUI.hline(0.0, Color(0.85, 0.80, 0.70, 0.22)))

		_scroll = ScrollContainer.new()
		_scroll.name = "Scroll"
		_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		vbox.add_child(_scroll)

		_list = VBoxContainer.new()
		_list.name = "List"
		_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_list.add_theme_constant_override("separation", 8)
		_scroll.add_child(_list)

		_empty_hint = Label.new()
		_empty_hint.name = "EmptyHint"
		_empty_hint.text = "（还没有说过什么。）"
		_empty_hint.add_theme_font_size_override("font_size", PreludeUI.FS_TEXT)
		_empty_hint.add_theme_color_override("font_color", PreludeUI.C_INK_DIM)
		_empty_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(_empty_hint)

	## history 元素形如 {"who": "刘忆", "text": "……"}，最后一条＝当前这句
	func refresh(history: Array) -> void:
		if _list == null:
			return
		for child in _list.get_children():
			if child == _empty_hint:
				continue
			child.queue_free()
		_empty_hint.visible = history.is_empty()
		_count_label.text = "  （共 %d 句）" % history.size()
		for i in history.size():
			var e: Variant = history[i]
			var who := ""
			var text := ""
			if e is Dictionary:
				who = str((e as Dictionary).get("who", ""))
				text = str((e as Dictionary).get("text", ""))
			else:
				text = str(e)
			var is_current := (i == history.size() - 1)
			var rb := RichTextLabel.new()
			rb.bbcode_enabled = true
			rb.fit_content = true
			rb.scroll_active = false
			rb.custom_minimum_size = Vector2(0, 28)
			rb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			rb.add_theme_font_size_override("normal_font_size", PreludeUI.FS_TEXT)
			rb.add_theme_color_override("default_color", PreludeUI.C_INK if is_current else Color(0.66, 0.64, 0.60))
			var mark := "[color=#e0c07a]▶[/color] " if is_current else "   "
			if who == "":
				rb.text = "%s[color=#9a968e]%s[/color]" % [mark, text]
			else:
				rb.text = "%s[color=#e0c07a]%s[/color]　%s" % [mark, who, text]
			_list.add_child(rb)

	func open(history: Array) -> void:
		refresh(history)
		visible = true
		# 打开时滚到最底：玩家多半是想看"刚才那句"
		await get_tree().process_frame
		if _scroll != null:
			_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)

	func close() -> void:
		visible = false
		closed.emit()

	func is_open() -> bool:
		return visible

	## 键盘 ↑↓ / 滚轮调用；dy>0 往下翻
	func scroll_by(dy: float) -> void:
		if _scroll == null:
			return
		_scroll.scroll_vertical += int(dy)


# ============================================================================
#  物品热区（氛围物品 / 可点击线索）
# ============================================================================
class ItemHotspot:
	extends Button

	signal inspected(item_name: String, detail: String)

	var item_name := ""
	var detail := ""
	var examined_once := false

	func setup(p_name: String, p_detail: String, rect: Rect2, label_visible: bool = true) -> void:
		item_name = p_name
		detail = p_detail
		name = "Hotspot_" + p_name
		text = p_name if label_visible else ""
		flat = true
		focus_mode = Control.FOCUS_ALL
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

		# 注意：局部变量千万不要叫 pressed —— Button.pressed 是信号，
		# 一旦被同名局部变量遮蔽，下一行的 pressed.connect(...) 就会去连一个
		# StyleBoxFlat，引擎报 "Too few arguments for connect()"，整份脚本编译失败。
		var sb_normal := StyleBoxFlat.new()
		sb_normal.bg_color = Color(0.85, 0.80, 0.70, 0.06)
		sb_normal.border_color = Color(0.85, 0.80, 0.70, 0.22)
		sb_normal.set_border_width_all(1)
		var sb_hover := sb_normal.duplicate() as StyleBoxFlat
		sb_hover.bg_color = Color(0.90, 0.82, 0.62, 0.20)
		sb_hover.border_color = Color(0.95, 0.86, 0.66, 0.75)
		var sb_pressed := sb_hover.duplicate() as StyleBoxFlat
		sb_pressed.bg_color = Color(0.95, 0.86, 0.66, 0.32)
		add_theme_stylebox_override("normal", sb_normal)
		add_theme_stylebox_override("hover", sb_hover)
		add_theme_stylebox_override("pressed", sb_pressed)
		add_theme_stylebox_override("focus", sb_hover)
		add_theme_color_override("font_color", Color(0.95, 0.92, 0.84, 0.85))
		add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
		add_theme_font_size_override("font_size", PreludeUI.FS_TIP)
		clip_text = true

		set_anchors_preset(Control.PRESET_TOP_LEFT)
		offset_left = rect.position.x
		offset_top = rect.position.y
		offset_right = rect.position.x + rect.size.x
		offset_bottom = rect.position.y + rect.size.y

		pressed.connect(_on_pressed)

	func _on_pressed() -> void:
		examined_once = true
		inspected.emit(item_name, detail)
