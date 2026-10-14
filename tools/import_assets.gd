extends SceneTree
## ============================================================================
##  素材入库：把 Kerry 给的图从挂载目录搬进项目，顺手做"抠白底 + 裁边"
## ============================================================================
##  为什么要写脚本而不是直接 Copy-Item：
##    · 立绘 / 道具图都是**白底**的 jpg/webp，直接当贴图用会在深色背景上糊一块白；
##    · 图四周留白很多，不裁掉的话对话立绘会被缩得很小。
##  于是统一在这里：读原图 → （可选）把接近白色的像素抠成透明 → 裁掉四周透明边 →
##  存成 png 到 res://assets/ 下。
##
##  跑法：godot --headless --path <项目> --script tools/import_assets.gd
##  可重复执行（幂等），退出码 0 = 全部成功。
## ============================================================================

const SRC_ROOT := "C:/Users/Administrator/.dsh/attachments/v1/objects/"

var _jobs := [
	# 名字, 源文件, 目标, 是否抠白底, 是否裁边, 裁剪矩形 Vector4i(x,y,w,h)（=0 表示整张用）
	# 注：七张立绘**不在这里** —— Kerry 后来直接给了抠好的透明底成品（assets/portraits/*.png），
	#     这里再跑一遍只会把他抠好的图覆盖掉。这个脚本现在只管封面与道具。
	["封面 寻星", "22/22e2e993a36a7bb5c637a941c158d83295cc0f9003f8935cccc4b42a96e4ccae", "res://assets/cover/chase_the_star.png", false, false, Vector4i(0, 0, 0, 0)],
	# 洞洞板是"满幅照片"，整张都是内容（边框就是墙），不能抠底——一抠就只剩 4%
	["道具 洞洞板", "2d/2de8deef7726ff7002ab5a7c54d56bf71bb77e877b8dc41c6fcbefdd64096bf9", "res://assets/props/pegboard.png", false, false, Vector4i(0, 0, 0, 0)],
	# 三视图设计稿：只切"主视图"那一格，不然贴到面板上就是一张印着中文标题和尺寸线的白卡片
	["道具 U盘", "82/8201fe0b72fe38b0838e7f41d2fa8202a2e3b73f8aa1c659804c9b0c1849926a", "res://assets/props/usb_drive.png", true, true, Vector4i(360, 230, 1500, 420)],
	["道具 扑克牌", "a7/a7d3bca0ce85bde72f04d0223c35cc92a122f58a54f78c512a73cc7179c8ba14", "res://assets/props/playing_cards.png", true, true, Vector4i(110, 120, 850, 1190)],
	["道具 动物园", "7f/7f6764d8e194637c87f96875ad160f37272dc91b26623dee46be375a5b4daf69", "res://assets/props/book_zoo.png", true, true, Vector4i(0, 0, 0, 0)],
	["道具 树枝", "7d/7d4acea449e895b82819eb4f962c52a1083d3046095d6cba9c8556edcc8449e8", "res://assets/props/branch.png", true, true, Vector4i(600, 180, 400, 1300)],
	["道具 笑脸灯", "da/dac7e12c639f232f92dd0cd2e3c05f50b16abd210e622efe76a44c62879a987f", "res://assets/props/smiley_lamp.png", true, true, Vector4i(160, 440, 860, 790)],
	["道具 闹钟", "ef/efb5b2c3cab419bfb0b4c0ea10c73057e0468e266041f3e4e31c8ddfd41e8672", "res://assets/props/alarm_clock.png", true, true, Vector4i(110, 210, 880, 1100)],
]


func _initialize() -> void:
	var fails := 0
	print("========== 素材入库 ==========")
	for job in _jobs:
		var label: String = job[0]
		var src := SRC_ROOT + str(job[1])
		var dst := str(job[2])
		var key := bool(job[3])
		var trim := bool(job[4])
		var crop: Vector4i = job[5]
		if not FileAccess.file_exists(dst) and not _dir_ready(dst):
			print("✗ %s：目录建不出来（%s）" % [label, dst])
			fails += 1
			continue
		var img: Image = _load_any(src)
		if img == null:
			print("✗ %s：读不到源文件 %s" % [label, src])
			fails += 1
			continue
		var before := img.get_size()
		var cropped := ""
		if crop.z > 0 and crop.w > 0:
			var rect := Rect2i(crop.x, crop.y, crop.z, crop.w)
			rect = rect.intersection(Rect2i(0, 0, img.get_width(), img.get_height()))
			if rect.size.x > 0 and rect.size.y > 0:
				img = img.get_region(rect)
				cropped = "［切 %d,%d %dx%d］" % [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
		var keyed := false
		if key and _needs_key(img):
			_key_paper(img)
			keyed = true
		if trim:
			img = _trim(img)
		var err := img.save_png(dst)
		if err != OK:
			print("✗ %s：写不进去 %s（err %d）" % [label, dst, err])
			fails += 1
			continue
		print("  ✓ %s%s%s：%dx%d → %dx%d  %s" % [label, "（抠底）" if keyed else "（原样）", cropped,
				int(before.x), int(before.y),
				int(img.get_width()), int(img.get_height()), dst])
	print("-----------------------------------------")
	print("共 %d 张，失败 %d 张" % [_jobs.size(), fails])
	quit(1 if fails > 0 else 0)


## 挂载过来的素材文件**没有扩展名**（内容是哈希名），所以 Image.load_from_file 认不出格式
## （报 Failed to load image. Error 15）。这里自己嗅探文件头再走对应的 *_from_buffer。
func _load_any(path: String) -> Image:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("打不开 %s" % path)
		return null
	var buf := f.get_buffer(f.get_length())
	f.close()
	var img := Image.new()
	var err := FAILED
	if buf.size() > 3 and buf[0] == 0xFF and buf[1] == 0xD8 and buf[2] == 0xFF:
		err = img.load_jpg_from_buffer(buf)
	elif buf.size() > 12 and buf.slice(0, 4).get_string_from_ascii() == "RIFF" \
			and buf.slice(8, 12).get_string_from_ascii() == "WEBP":
		err = img.load_webp_from_buffer(buf)
	elif buf.size() > 8 and buf[0] == 0x89 and buf[1] == 0x50:
		err = img.load_png_from_buffer(buf)
	if err != OK:
		push_error("解不开 %s（err %d）" % [path, err])
		return null
	return img


## 三视图设计稿不是单体道具图：整张纸是米白的、外面还有一圈装饰边框，
## 直接贴到面板上就是"一张印着中文标题和尺寸线的白卡片"，比代码图形更出戏。
## 这里自动把"主视图 / 正视图"那一格切出来：
##   · 逐列统计"近白像素占比"，占比 ≥ 0.985 的列算"两格之间的空隙"；
##   · 被空隙分开、宽度 ≥ 150px 的段就是一格；
##   · 取第一段（笑脸灯是"主视图"、树枝是"正视图"、闹钟是"主视图"），
##     再按该段里非背景像素的上下界收一下高度。
## 切完再走 _key_bg_flood() 时，装饰边框已经不在了，纸白就能被正常抠掉。
func _main_view_rect(img: Image) -> Rect2i:
	var w := img.get_width()
	var h := img.get_height()
	var data := img.get_data()
	var fmt := img.get_format()
	if fmt != Image.FORMAT_RGBA8 and fmt != Image.FORMAT_RGB8:
		# 统一到 8 位通道，方便按字节判断
		img.convert(Image.FORMAT_RGBA8)
		data = img.get_data()
		fmt = img.get_format()
	var stride := 3 if fmt == Image.FORMAT_RGB8 else 4
	# 逐列统计"近白占比"
	var gaps: Array[Vector2i] = []
	var run_start := -1
	for x in w:
		var light := 0
		for y in h:
			var i := (y * w + x) * stride
			if data[i] >= 235 and data[i + 1] >= 235 and data[i + 2] >= 235:
				light += 1
		var is_gap := float(light) / float(h) >= 0.985
		if is_gap and run_start < 0:
			run_start = x
		elif not is_gap and run_start >= 0:
			if x - run_start >= 4:
				gaps.append(Vector2i(run_start, x - 1))
			run_start = -1
	if run_start >= 0:
		gaps.append(Vector2i(run_start, w - 1))
	# 被空隙分开的段
	var seg_start := 0
	for g in gaps:
		if g.x - seg_start >= 150:
			return _tighten(img, seg_start, g.x - 1)
		seg_start = g.y + 1
	if w - seg_start >= 150:
		return _tighten(img, seg_start, w - 1)
	return Rect2i(0, 0, 0, 0)


## 在 [x0, x1] 这一格内，按"非背景像素"的上下界收紧高度。
func _tighten(img: Image, x0: int, x1: int) -> Rect2i:
	var w := img.get_width()
	var h := img.get_height()
	var data := img.get_data()
	var fmt := img.get_format()
	var stride := 3 if fmt == Image.FORMAT_RGB8 else 4
	var top := -1
	var bottom := -1
	for y in h:
		var solid := false
		for x in range(x0, x1 + 1):
			var i := (y * w + x) * stride
			if data[i] < 225 or data[i + 1] < 225 or data[i + 2] < 225:
				solid = true
				break
		if solid:
			if top < 0:
				top = y
			bottom = y
	if top < 0:
		top = 0
		bottom = h - 1
	return Rect2i(x0, top, x1 - x0 + 1, bottom - top + 1)


func _dir_ready(path: String) -> bool:
	var dir := path.get_base_dir()
	if DirAccess.dir_exists_absolute(dir):
		return true
	return DirAccess.make_dir_recursive_absolute(dir) == OK


## 这张图需不需要抠底？
## 【坑，踩过】一开始写的是"把所有接近白色的像素抠成透明"（亮度一刀切），
## 结果人物**内部的**白色（脸上高光、白衬衫、浅色袖口）也一起被挖掉，
## 深色背景上看就是"脸上破了个洞"。正确做法有两条：
##   · 本来就带透明背景的图（webp/png 立绘，四角 a=0）→ 原样保留、根本不抠；
##   · 整张不透明的 jpg → 走 _key_bg_flood()：**只吃从四边连通的白色**，
##     人物内部的白不连通，所以留得住。
func _needs_key(img: Image) -> bool:
	if not img.detect_alpha():
		return true
	var w := img.get_width()
	var h := img.get_height()
	var corners := [Vector2i(0, 0), Vector2i(w - 1, 0), Vector2i(0, h - 1), Vector2i(w - 1, h - 1)]
	for c in corners:
		if img.get_pixel(c.x, c.y).a > 0.5:
			return true
	return false


## 把"纸"抠掉，做成带**软边**的 alpha 遮罩（只对整张不透明的 jpg 调用）。
##
## 为什么不是"按亮度一刀切"：这几张立绘的**白衣服和整张脸**亮度都在 0.90~1.00，
## 跟纸一样亮；一刀切必然把衣服和脸一起抠掉（第一版就是这样，实机看"脸是空的"）。
## 所以判据是**连通性 + 软边**：
##   ① 从四条边向内 flood fill，只吃"和边界连成一片的浅色"（阈值 0.80，
##      放到这么松是为了吃掉 jpg 压出来的灰雾——0.92 太紧，纸边会剩一圈灰）；
##   ② 贴着纸的那 3 圈浅色像素给**部分透明**（亮度 0.96→全透，0.55→不透），
##      于是线稿的抗锯齿边自然化开，不再是一圈硬锯齿；
##   ③ 去孤立噪点（8 邻域 ≤2 个实体的像素删掉，跑两遍）；
##   ④ **把人物内部被漏掉的透明洞补回来**：从四边在 alpha<0.5 的区域里 BFS，
##      没被 BFS 到的透明像素 = 被误抠的内部（白衬衫、脸），一律恢复成不透明；
##   ⑤ alpha 走一遍 3x3 均值，边缘再柔一点。
## 兜底：如果①吃掉了 ≥80% 的画面，说明有暗线断口造成漏吃，改用 0.90 阈值重来一次。
func _key_paper(img: Image) -> void:
	if not img.detect_alpha():
		img.convert(Image.FORMAT_RGBA8)
	elif img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	var total := w * h
	var data := img.get_data()
	var lum := PackedFloat32Array()
	lum.resize(total)
	for i in total:
		var b := i * 4
		var m := data[b]
		if data[b + 1] > m:
			m = data[b + 1]
		if data[b + 2] > m:
			m = data[b + 2]
		lum[i] = float(m) / 255.0

	# ---- ① 从四边吃纸。阈值跟着"纸本身有多亮"走，而且**要非常保守**：
	#      实测量过（tools/probe_lum.gd）：纸是纯白 1.000（min 也是 1.000），
	#      而人物外套/袖子的受光面**也是 1.000**（均值 0.97~0.99），亮度上根本分不开；
	#      唯一能分开的是"连通性"——纸能从四边走到，人物身上的白被线稿兜住。
	#      所以阈值取"比纸低 0.005"（≈0.995），只吃真正的纸；漏进来的细通道
	#      由下面的 ①b 闭合补掉，绝不靠调低亮度阈值去凑。
	var border := PackedFloat32Array()
	for x in w:
		border.append(lum[x])
		border.append(lum[(h - 1) * w + x])
	for y in h:
		border.append(lum[y * w])
		border.append(lum[y * w + w - 1])
	border.sort()
	var paper_lum := border[border.size() / 2]
	var thr := clampf(paper_lum - 0.005, 0.80, 0.995)
	var paper := _flood_paper(w, h, lum, thr)
	if _count(paper) > int(float(total) * 0.80):
		paper = _flood_paper(w, h, lum, minf(thr + 0.10, 0.92))
	# ---- ①b 闭合：把细的漏光通道补掉（先膨胀 r 次再腐蚀 r 次＝形态学闭运算）
	paper = _close_paper(paper, w, h, 3)
	print("      · 纸亮度中位数 %.2f → 阈值 %.2f，吃掉 %.0f%%" % [paper_lum, thr,
			float(_count(paper)) * 100.0 / float(total)])

	# ---- ② 贴着纸的浅色 → 软边。只对**真的接近纸**（≥0.985）的像素做，
	#      人物外套那层 0.96~0.99 的受光面不能被削（那正是"身上蒙灰"的来源）。
	var alpha := PackedFloat32Array()
	alpha.resize(total)
	for i in total:
		alpha[i] = 1.0 if paper[i] == 0 else 0.0
	var frontier := PackedByteArray()
	frontier.resize(total)
	for i in total:
		frontier[i] = paper[i]
	for _pass in 3:
		var next := PackedByteArray()
		next.resize(total)
		for y in h:
			for x in w:
				var p := y * w + x
				if frontier[p] == 1:
					continue
				var touching := false
				if x > 0 and frontier[p - 1] == 1:
					touching = true
				elif x < w - 1 and frontier[p + 1] == 1:
					touching = true
				elif y > 0 and frontier[p - w] == 1:
					touching = true
				elif y < h - 1 and frontier[p + w] == 1:
					touching = true
				if touching:
					next[p] = 1
					if lum[p] >= 0.985:
						var a := (1.0 - lum[p]) / 0.015
						alpha[p] = minf(alpha[p], clampf(a, 0.0, 1.0))
		frontier = next

	# ---- ②b 啃掉 1px 的亮边：jpg 在人物外轮廓上会压出一圈 0.93~0.99 的光晕，
	#      它连在纸上、又不算纸，留在 alpha 上就是一圈灰边。只削"紧贴背景 + 很亮"的那一圈。
	for y in h:
		for x in w:
			var p := y * w + x
			if alpha[p] < 0.5 or lum[p] < 0.93:
				continue
			if (x > 0 and alpha[p - 1] < 0.5) or (x < w - 1 and alpha[p + 1] < 0.5) \
					or (y > 0 and alpha[p - w] < 0.5) or (y < h - 1 and alpha[p + w] < 0.5):
				alpha[p] = 0.0

	# ---- ③ 去孤立噪点（在 alpha 上跑两遍）
	for _pass in 2:
		var kill := PackedInt32Array()
		for y in h:
			for x in w:
				var p := y * w + x
				if alpha[p] < 0.5:
					continue
				var solid := 0
				for dy in [-1, 0, 1]:
					for dx in [-1, 0, 1]:
						if dx == 0 and dy == 0:
							continue
						var nx: int = x + dx
						var ny: int = y + dy
						if nx < 0 or ny < 0 or nx >= w or ny >= h:
							continue
						if alpha[ny * w + nx] >= 0.5:
							solid += 1
				if solid <= 2:
					kill.append(p)
		if kill.is_empty():
			break
		for p in kill:
			alpha[p] = 0.0

	# ---- ④ 补回被误抠的内部（从四边在"透明区"BFS，没走到的透明像素=内部）
	var outside := PackedByteArray()
	outside.resize(total)
	var stack := PackedInt32Array()
	for x in w:
		stack.append(x)
		stack.append((h - 1) * w + x)
	for y in h:
		stack.append(y * w)
		stack.append(y * w + w - 1)
	while not stack.is_empty():
		var p := stack[stack.size() - 1]
		stack.remove_at(stack.size() - 1)
		if outside[p] == 1 or alpha[p] >= 0.5:
			continue
		outside[p] = 1
		var x2 := p % w
		var y2 := p / w
		if x2 > 0:
			stack.append(p - 1)
		if x2 < w - 1:
			stack.append(p + 1)
		if y2 > 0:
			stack.append(p - w)
		if y2 < h - 1:
			stack.append(p + w)
	for i in total:
		if alpha[i] < 0.5 and outside[i] == 0:
			alpha[i] = 1.0

	# ---- ⑤ alpha 3x3 均值 → 边缘柔一点
	var smooth := PackedFloat32Array()
	smooth.resize(total)
	for y in h:
		for x in w:
			var sum := 0.0
			var cnt := 0
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					var nx: int = x + dx
					var ny: int = y + dy
					if nx < 0 or ny < 0 or nx >= w or ny >= h:
						continue
					sum += alpha[ny * w + nx]
					cnt += 1
			smooth[y * w + x] = sum / float(cnt)

	# ---- 写回（保留原有的更小 alpha：本来就抠好的图不会被"加回去"）
	for i in total:
		var a := int(round(smooth[i] * 255.0))
		var b := i * 4 + 3
		if a < data[b]:
			data[b] = a
	img.set_data(w, h, false, Image.FORMAT_RGBA8, data)


## 从四边 flood fill 吃"浅色且与边界连通"的像素，返回 0/1 掩码。
## 形态学闭运算（作用在"纸"的掩码上）：先把人物**膨胀** r 次再**腐蚀** r 次，
## 结果是"比 2r 像素窄的纸通道被填掉"——正是线稿缺口漏进来的那道细缝。
## 外轮廓不变（膨胀多少就腐蚀回多少），所以不会把人物吃胖。
func _close_paper(paper: PackedByteArray, w: int, h: int, r: int) -> PackedByteArray:
	var opaque := PackedByteArray()
	opaque.resize(w * h)
	for i in w * h:
		opaque[i] = 0 if paper[i] == 1 else 1
	for _i in r:
		opaque = _dilate4(opaque, w, h)
	for _i in r:
		opaque = _erode4(opaque, w, h)
	var out := PackedByteArray()
	out.resize(w * h)
	for i in w * h:
		out[i] = 0 if opaque[i] == 1 else 1
	return out


func _dilate4(mask: PackedByteArray, w: int, h: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(w * h)
	for y in h:
		for x in w:
			var p := y * w + x
			if mask[p] == 1:
				out[p] = 1
				continue
			if (x > 0 and mask[p - 1] == 1) or (x < w - 1 and mask[p + 1] == 1) \
					or (y > 0 and mask[p - w] == 1) or (y < h - 1 and mask[p + w] == 1):
				out[p] = 1
	return out


func _erode4(mask: PackedByteArray, w: int, h: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(w * h)
	for y in h:
		for x in w:
			var p := y * w + x
			if mask[p] == 0:
				continue
			if (x > 0 and mask[p - 1] == 0) or (x < w - 1 and mask[p + 1] == 0) \
					or (y > 0 and mask[p - w] == 0) or (y < h - 1 and mask[p + w] == 0):
				continue
			out[p] = 1
	return out


func _flood_paper(w: int, h: int, lum: PackedFloat32Array, thr: float) -> PackedByteArray:
	var paper := PackedByteArray()
	paper.resize(w * h)
	var stack := PackedInt32Array()
	for x in w:
		stack.append(x)
		stack.append((h - 1) * w + x)
	for y in h:
		stack.append(y * w)
		stack.append(y * w + w - 1)
	while not stack.is_empty():
		var p := stack[stack.size() - 1]
		stack.remove_at(stack.size() - 1)
		if paper[p] == 1 or lum[p] < thr:
			continue
		paper[p] = 1
		var x2 := p % w
		var y2 := p / w
		if x2 > 0:
			stack.append(p - 1)
		if x2 < w - 1:
			stack.append(p + 1)
		if y2 > 0:
			stack.append(p - w)
		if y2 < h - 1:
			stack.append(p + w)
	return paper


func _count(mask: PackedByteArray) -> int:
	var n := 0
	for v in mask:
		if v == 1:
			n += 1
	return n


## 裁掉四周的透明边（只对抠过底、或本来就带 alpha 的图有意义）。
## 同样直接读 get_data() 的 alpha 字节，避免几百万次 get_pixel。
func _trim(img: Image) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	if not img.detect_alpha():
		return img
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var data := img.get_data()
	var min_x := w
	var min_y := h
	var max_x := -1
	var max_y := -1
	for y in h:
		var row := y * w
		for x in w:
			if data[(row + x) * 4 + 3] > 8:
				min_x = mini(min_x, x)
				max_x = maxi(max_x, x)
				min_y = mini(min_y, y)
				max_y = maxi(max_y, y)
	if max_x < 0 or max_y < 0:
		return img
	var rect := Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)
	if rect.size == Vector2i(w, h):
		return img
	return img.get_region(rect)
