## 立绘抠图自检：把 CURRENT 的抠图结果画成一张对照图，并数出"人物本体有没有被误抠"。
##
## 跑法：
##   & 'E:\Godot_v4.7.2-stable_win64_console.exe' --headless --path 'E:\Godot\yongxian' --script tools/probe_portrait.gd
##
## 输出（项目根）：
##   _cut_李星.png 等七张 —— 对照图：红 = 人物本体被误抠（必须是 0 像素），
##   橙 = 小残渣被抠（本来就该抠），深灰 = 本来就透明的背景（不显示，不算错）。
## 判据：只看连通性/面积，不看亮度——白衬衫和脸的 luma 就是 1.0，跟纸分不开。
## 人物本体被抠掉 >0 像素时本脚本退 1。
## 只做离线数值 + 对照图，不改任何东西。
extends SceneTree

const TARGET_W := 520      # 对照图宽度（够看清，又不用等太久）
const C_BG := Color(0.14, 0.14, 0.17, 1.0)
const C_WRONG := Color(1.0, 0.0, 0.0, 1.0)      # 人物本体被误抠
const C_SPEC := Color(1.0, 0.55, 0.0, 1.0)      # 小残渣（该抠）

var _fails := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	var ui: GDScript = load("res://scripts/ui/prelude_ui.gd")
	if ui == null:
		print("!! 载入 prelude_ui.gd 失败")
		quit(1)
		return
	print("—— 立绘抠图自检 ——")
	# 七张立绘现在都是 Kerry 自己抠好的透明底成品（assets/portraits/ 下）。
	# 这个自检保证运行时的 build_bg_mask() 不会把人物本体当成背景吃掉。
	_probe(ui, "李星", "res://assets/portraits/lixing.png")
	_probe(ui, "刘忆", "res://assets/portraits/liuyi.png")
	_probe(ui, "同学C", "res://assets/portraits/student_c.png")
	_probe(ui, "同学D", "res://assets/portraits/student_d.png")
	_probe(ui, "同学E", "res://assets/portraits/student_e.png")
	_probe(ui, "班主任", "res://assets/portraits/teacher.png")
	_probe(ui, "宿管", "res://assets/portraits/warden.png")
	print("—— 失败 %d 项 ——" % _fails)
	quit(1 if _fails > 0 else 0)


func _probe(ui: GDScript, label: String, path: String) -> void:
	# 必须走 PreludeUI.load_texture()：这些图没有 .import，直接 load() 会报
	# "No loader found for resource"（坑 29）
	var tex: Texture2D = ui.load_texture(path)
	if tex == null:
		print("  !! 载入失败：%s" % path)
		_fails += 1
		return
	var src := tex.get_image()
	if src == null:
		print("  !! 取不到图像：%s" % path)
		_fails += 1
		return
	var sw := src.get_width()
	var sh := src.get_height()
	print("· %s  %dx%d" % [path, sw, sh])

	# 角点：判断背景到底是"透明"还是"白纸"
	var cs: Array = [
		src.get_pixel(2, 2), src.get_pixel(sw - 3, 2),
		src.get_pixel(2, sh - 3), src.get_pixel(sw - 3, sh - 3),
	]
	print("  四角 rgba：" + ", ".join(cs.map(func(c: Color) -> String:
		return "(%.2f,%.2f,%.2f,a=%.2f)" % [c.r, c.g, c.b, c.a])))

	# 缩到 TARGET_W 再烘遮罩（遮罩内部本来就是 384 宽算的，缩了不丢信息，但快很多）
	var small := src.duplicate() as Image
	var tw := TARGET_W
	var th := int(round(float(sh) * float(tw) / float(sw)))
	small.resize(tw, th, Image.INTERPOLATE_BILINEAR)
	var mask: Image = ui.build_bg_mask(small)
	if mask == null:
		print("  !! 遮罩生成失败")
		_fails += 1
		return

	# 不透明连通块：用来判断"被抠掉的这块到底是不是人物本体"
	var lab := _label_solids(small)
	var max_spec := int(float(int(lab["cw"]) * int(lab["ch"])) * 0.003)   # 同 prelude_ui 的 SPEC_FRAC

	var out := Image.create(tw, th, false, Image.FORMAT_RGBA8)
	var bg_px := 0
	var bg_bright := 0
	var in_px := 0
	var body_cut := 0           # ★人物本体（大块）被抠掉 → 真正的错误，必须是 0
	var body_cut_bright := 0
	var speck_cut := 0          # 小残渣被抠掉 → 本来就该抠
	var old_cut := 0            # 按旧规则(interior_cut=0.985)会被削掉的纯白像素数
	for y in th:
		for x in tw:
			var c := small.get_pixel(x, y)
			var m := mask.get_pixel(x, y).r
			var l := 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
			var a: float
			var col := Color(c.r, c.g, c.b, 1.0)
			if m > 0.5:
				a = c.a * (1.0 - smoothstep(0.45, 0.90, l))
				bg_px += 1
				if l >= 0.85:
					bg_bright += 1
				if c.a >= 0.5 and a < 0.5:
					var lcw := int(lab["cw"])
					var lch := int(lab["ch"])
					var lid: int = (lab["labels"] as PackedInt32Array)[
						mini(lch - 1, y * lch / th) * lcw + mini(lcw - 1, x * lcw / tw)]
					if lid >= 0 and int((lab["sizes"] as PackedInt32Array)[lid]) > max_spec:
						body_cut += 1
						col = C_WRONG
						if l >= 0.85:
							body_cut_bright += 1
					else:
						speck_cut += 1
						col = C_SPEC
				elif c.a < 0.35:
					col = C_BG
			else:
				a = c.a            # 新规则：人物本体原样保留，不再按亮度削
				if c.a > 0.5:
					in_px += 1
					if l >= 0.985:
						old_cut += 1
			out.set_pixel(x, y, col)
	out.save_png("res://_cut_%s.png" % label)

	print("  判为背景 %d px（其中亮于 0.85 的 %d px）" % [bg_px, bg_bright])
	print("  ★人物本体被抠掉 %d px（亮于 0.85 的 %d px）—— 必须是 0" % [body_cut, body_cut_bright])
	print("  小残渣被抠掉 %d px（本来就该抠掉）" % speck_cut)
	print("  人物本体 %d px；按旧规则(interior_cut=0.985)会被削掉的纯白 %d px" % [in_px, old_cut])
	if body_cut > 0:
		print("  !! 人物本体被误抠 → 失败")
		_fails += 1
	print("  对照图 → res://_cut_%s.png（红=人物本体被误抠，橙=残渣被抠，深灰=本来就透明）" % label)


## 不透明连通块标记（降到 384 宽统计）：返回 {labels, sizes, cw, ch}
## labels[i] = 连通块编号（-1 = 透明）；sizes[id] = 该块像素数
func _label_solids(img: Image) -> Dictionary:
	const CW := 384
	var w := img.get_width()
	var h := img.get_height()
	var small := img.duplicate() as Image
	var cw := mini(CW, w)
	var ch := maxi(2, int(round(float(h) * float(cw) / float(w))))
	small.resize(cw, ch, Image.INTERPOLATE_BILINEAR)
	var labels := PackedInt32Array()
	labels.resize(cw * ch)
	labels.fill(-1)
	var sizes := PackedInt32Array()
	for y in ch:
		for x in cw:
			var i := y * cw + x
			if labels[i] != -1 or small.get_pixel(x, y).a < 0.5:
				continue
			var id := sizes.size()
			sizes.append(0)
			var stack := PackedInt32Array([i])
			labels[i] = id
			var head := 0
			while head < stack.size():
				var cur := stack[head]
				head += 1
				sizes[id] = sizes[id] + 1
				var cx := cur % cw
				var cy := cur / cw
				if cx > 0 and labels[cur - 1] == -1 and small.get_pixel(cx - 1, cy).a >= 0.5:
					labels[cur - 1] = id
					stack.append(cur - 1)
				if cx < cw - 1 and labels[cur + 1] == -1 and small.get_pixel(cx + 1, cy).a >= 0.5:
					labels[cur + 1] = id
					stack.append(cur + 1)
				if cy > 0 and labels[cur - cw] == -1 and small.get_pixel(cx, cy - 1).a >= 0.5:
					labels[cur - cw] = id
					stack.append(cur - cw)
				if cy < ch - 1 and labels[cur + cw] == -1 and small.get_pixel(cx, cy + 1).a >= 0.5:
					labels[cur + cw] = id
					stack.append(cur + cw)
	var sorted_sizes := sizes.duplicate()
	sorted_sizes.sort()
	sorted_sizes.reverse()
	var total := cw * ch
	var top := PackedStringArray()
	for k in mini(6, sorted_sizes.size()):
		top.append("%d(%.2f%%)" % [sorted_sizes[k], 100.0 * float(sorted_sizes[k]) / float(total)])
	print("  不透明连通块 %d 个（384 宽统计），最大的几个：%s" % [sizes.size(), ", ".join(top)])
	return {"labels": labels, "sizes": sizes, "cw": cw, "ch": ch}
