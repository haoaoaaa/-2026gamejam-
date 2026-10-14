extends SceneTree

## 把八张立绘按「游戏里的样子」（贴到深色底上）拼成一张对照图，存成 res://_pv.png。
## 用意：肉眼检查抠图质量——透明处会不会漏白、人物四周有没有灰雾、边缘有没有锯齿/噪点。
## 只读素材，不改任何东西。
##   跑法：godot --headless --path <项目> --script tools/preview_portraits.gd

const OUT := "res://_pv.png"
const OUT_ALPHA := "res://_pva.png"
const COLS := 4
const CELL_W := 310
const CELL_H := 380
const PAD := 8
const BG := Color(0.10, 0.11, 0.13)

const FILES := [
	"res://assets/portraits/lixing.png",
	"res://assets/portraits/liuyi.png",
	"res://assets/portraits/student_c.png",
	"res://assets/portraits/student_d.png",
	"res://assets/portraits/student_e.png",
	"res://assets/portraits/teacher.png",
	"res://assets/portraits/warden.png",
]


func _initialize() -> void:
	print("========== 立绘对照图 ==========")
	var rows := int(ceil(float(FILES.size()) / float(COLS)))
	var sheet := Image.create(COLS * (CELL_W + PAD) + PAD, rows * (CELL_H + PAD) + PAD, false, Image.FORMAT_RGBA8)
	sheet.fill(BG)
	var alpha_sheet := Image.create(sheet.get_width(), sheet.get_height(), false, Image.FORMAT_RGB8)
	alpha_sheet.fill(BG)
	var i := 0
	for p in FILES:
		var col := i % COLS
		var row := i / COLS
		i += 1
		var tex := PreludeUI.load_texture(p)
		if tex == null:
			print("  ✗ 取不到：", p)
			continue
		var img := tex.get_image()
		if img == null:
			print("  ✗ 没有像素：", p)
			continue
		if img.get_format() != Image.FORMAT_RGBA8:
			img.convert(Image.FORMAT_RGBA8)
		var w := int(round(float(img.get_width()) * float(CELL_H) / float(img.get_height())))
		if w > CELL_W:
			w = CELL_W
		img.resize(maxi(1, w), CELL_H, Image.INTERPOLATE_BILINEAR)
		var x := PAD + col * (CELL_W + PAD) + (CELL_W - img.get_width()) / 2
		var y := PAD + row * (CELL_H + PAD)
		sheet.blend_rect(img, Rect2i(0, 0, img.get_width(), img.get_height()), Vector2i(x, y))
		print("  · %-46s %dx%d → %dx%d" % [p, tex.get_width(), tex.get_height(), img.get_width(), img.get_height()])
		# 同时把 alpha 通道单独画成灰度：白色=不透明、黑色=透明，半透明一眼可见
		var amask := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGB8)
		for ay in img.get_height():
			for ax in img.get_width():
				var a := img.get_pixel(ax, ay).a
				amask.set_pixel(ax, ay, Color(a, a, a))
		alpha_sheet.blend_rect(amask, Rect2i(0, 0, amask.get_width(), amask.get_height()), Vector2i(x, y))
	sheet.save_png(OUT)
	alpha_sheet.save_png(OUT_ALPHA)
	print("对照图 → ", OUT, "（第 1 行：李星 / 刘忆 / 同学C / 同学D；第 2 行：同学E / 班主任 / 宿管）")
	quit()
