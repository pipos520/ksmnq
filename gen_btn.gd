extends SceneTree
## 生成像素风按钮纹理（夜间+白天两套）

const OUT_DIR := "res://assets/theme/btn_textures/"

const NIGHT := [
	["gold",    Color("#e9a838"), Color("#f2b84d"), Color("#ba8020")],
	["red",     Color("#ff6b6b"), Color("#ff8c8c"), Color("#cc4040")],
	["blue",    Color("#6c9bcf"), Color("#8cb4dc"), Color("#486ea0")],
	["green",   Color("#5cb85c"), Color("#78d278"), Color("#3c8c3c")],
	["darkred", Color("#c0392b"), Color("#dc5041"), Color("#962319")],
	["gray",    Color("#e6e6e6"), Color("#f5f5f5"), Color("#b4b4b4")],
	["purple",  Color("#8b5cf6"), Color("#a778ff"), Color("#643cc8")],
	["orange",  Color("#f2994a"), Color("#ffb464"), Color("#c87828")],
]

const DAY := [
	["gold",    Color("#f0d9a0"), Color("#f5e0b0"), Color("#d0b870")],
	["red",     Color("#f0b0b0"), Color("#f5c0c0"), Color("#d08080")],
	["blue",    Color("#b0cce0"), Color("#c0d8e8"), Color("#80a0b8")],
	["green",   Color("#b0d8b0"), Color("#c0e0c0"), Color("#80b080")],
	["darkred", Color("#d09080"), Color("#d8a090"), Color("#b07060")],
	["gray",    Color("#f5f0e8"), Color("#faf5f0"), Color("#d0c8b8")],
	["purple",  Color("#c0a0e0"), Color("#d0b0e8"), Color("#a080c0")],
	["orange",  Color("#e8c080"), Color("#f0d090"), Color("#d0a060")],
]

const W := 48
const H := 28

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	for c in NIGHT:
		var n := c[0] as String; var b := c[1] as Color; var l := c[2] as Color; var d := c[3] as Color
		_save_png(n, _make_normal(b, d))
		_save_png(n + "_hover", _make_hover(l, d))
		_save_png(n + "_pressed", _make_pressed(d))
	for c in DAY:
		var n := c[0] as String; var b := c[1] as Color; var l := c[2] as Color; var d := c[3] as Color
		_save_png(n + "_day", _make_normal(b, d))
		_save_png(n + "_day_hover", _make_hover(l, d))
		_save_png(n + "_day_pressed", _make_pressed(d))
	print("完成！共 ", (NIGHT.size() + DAY.size()) * 3, " 张纹理")
	quit()

func _make_normal(base, dark):
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	for y in range(2, H):
		for x in range(2, W):
			img.set_pixel(x, y, Color(0, 0, 0, 0.4))
	for x in range(W):
		img.set_pixel(x, 0, Color(0.12, 0.12, 0.12))
		img.set_pixel(x, H-1, Color(0.12, 0.12, 0.12))
	for y in range(H):
		img.set_pixel(0, y, Color(0.12, 0.12, 0.12))
		img.set_pixel(W-1, y, Color(0.12, 0.12, 0.12))
	for x in range(1, W-1):
		img.set_pixel(x, 1, dark)
		img.set_pixel(x, H-2, dark)
	for y in range(1, H-1):
		img.set_pixel(1, y, dark)
		img.set_pixel(W-2, y, dark)
	img.set_pixel(1, 1, Color(0.08, 0.08, 0.08))
	img.set_pixel(2, 1, Color(0.08, 0.08, 0.08))
	img.set_pixel(1, 2, Color(0.08, 0.08, 0.08))
	img.set_pixel(W-2, 1, Color(0.08, 0.08, 0.08))
	img.set_pixel(W-3, 1, Color(0.08, 0.08, 0.08))
	img.set_pixel(W-2, 2, Color(0.08, 0.08, 0.08))
	img.set_pixel(1, H-2, Color(0.08, 0.08, 0.08))
	img.set_pixel(2, H-2, Color(0.08, 0.08, 0.08))
	img.set_pixel(1, H-3, Color(0.08, 0.08, 0.08))
	img.set_pixel(W-2, H-2, Color(0.08, 0.08, 0.08))
	img.set_pixel(W-3, H-2, Color(0.08, 0.08, 0.08))
	img.set_pixel(W-2, H-3, Color(0.08, 0.08, 0.08))
	for y in range(2, H-2):
		var fade := 1.0 - float(y - 2) / float(H - 5) * 0.2
		for x in range(2, W-2):
			var checker := 1.0 if (x + y) % 2 == 0 else 0.9
			var f := fade * checker
			img.set_pixel(x, y, Color(base.r * f, base.g * f, base.b * f))
	var hc := Color(min(1.0, base.r + 0.2), min(1.0, base.g + 0.2), min(1.0, base.b + 0.15))
	for x in range(3, W-3):
		img.set_pixel(x, 2, hc)
	var dc := Color(max(0, base.r - 0.15), max(0, base.g - 0.15), max(0, base.b - 0.1))
	for x in range(3, W-3):
		img.set_pixel(x, H-3, dc)
	return img

func _make_hover(light, dark):
	return _make_normal(light, dark)

func _make_pressed(dark):
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	for x in range(W):
		img.set_pixel(x, 0, Color(0.12, 0.12, 0.12))
		img.set_pixel(x, H-1, Color(0.12, 0.12, 0.12))
	for y in range(H):
		img.set_pixel(0, y, Color(0.12, 0.12, 0.12))
		img.set_pixel(W-1, y, Color(0.12, 0.12, 0.12))
	for x in range(1, W-1):
		img.set_pixel(x, 1, Color(0.08, 0.08, 0.08))
		img.set_pixel(x, H-2, Color(0.08, 0.08, 0.08))
	for y in range(1, H-1):
		img.set_pixel(1, y, Color(0.08, 0.08, 0.08))
		img.set_pixel(W-2, y, Color(0.08, 0.08, 0.08))
	for y in range(2, H-2):
		var fade := 1.0 - float(y - 2) / float(H - 5) * 0.15
		for x in range(2, W-2):
			var checker := 1.0 if (x + y) % 2 == 0 else 0.92
			var f := fade * checker
			img.set_pixel(x, y, Color(dark.r * f, dark.g * f, dark.b * f))
	for x in range(3, W-3):
		img.set_pixel(x, 2, Color(max(0, dark.r-0.15), max(0, dark.g-0.15), max(0, dark.b-0.1)))
	for y in range(3, H-3):
		img.set_pixel(2, y, Color(max(0, dark.r-0.15), max(0, dark.g-0.15), max(0, dark.b-0.1)))
	return img

func _save_png(name: String, img: Image) -> void:
	img.save_png(OUT_DIR + "btn_" + name + ".png")