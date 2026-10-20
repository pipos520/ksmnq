class_name CardRenderPanel
extends Control

const QRCode = preload("res://assets/share/QRCode.gd")

## 卡牌分享图片渲染面板：用 CanvasItem._draw() 绘制卡面内容
## 由 CardGallery 创建 SubViewport 渲染本控件后截图保存
## ★ 高清模式：960x1360（2倍分辨率），二维码模块≥3px，可扫可放大

var card: Dictionary = {}
var qr_data: String = ""

var _font: Font = null
var _bg_tex: Texture2D = null

# 颜色常量
const GOLD := Color(200.0 / 255.0, 160.0 / 255.0, 60.0 / 255.0, 1.0)
const GOLD_DIM := Color(200.0 / 255.0, 160.0 / 255.0, 60.0 / 255.0, 0.5)
const GOLD_TITLE := Color(200.0 / 255.0, 160.0 / 255.0, 60.0 / 255.0, 0.78)
const RED := Color(220.0 / 255.0, 60.0 / 255.0, 60.0 / 255.0, 1.0)
const GREEN := Color(60.0 / 255.0, 220.0 / 255.0, 60.0 / 255.0, 1.0)
const BLUE := Color(60.0 / 255.0, 120.0 / 255.0, 220.0 / 255.0, 1.0)
const WHITE := Color(200.0 / 255.0, 200.0 / 255.0, 200.0 / 255.0, 1.0)
const FIELD_COL := Color(160.0 / 255.0, 180.0 / 255.0, 220.0 / 255.0, 0.86)
const DESC_COL := Color(160.0 / 255.0, 160.0 / 255.0, 160.0 / 255.0, 0.86)
const AUX_COL := Color(140.0 / 255.0, 180.0 / 255.0, 200.0 / 255.0, 0.86)
const RED_DIM := Color(200.0 / 255.0, 80.0 / 255.0, 80.0 / 255.0, 0.78)
const GREEN_DIM := Color(80.0 / 255.0, 200.0 / 255.0, 80.0 / 255.0, 0.78)
const BLUE_DIM := Color(80.0 / 255.0, 130.0 / 255.0, 220.0 / 255.0, 0.78)
const STAR_COL := Color(200.0 / 255.0, 180.0 / 255.0, 100.0 / 255.0, 1.0)
const BG_COL := Color(0.11, 0.07, 0.19, 1.0)
const QR_BG := Color(1.0, 1.0, 1.0, 1.0)   # 二维码白底
const QR_FG := Color(0.05, 0.03, 0.1, 1.0)  # 二维码深色模块

# 高清尺寸（2倍）
const W := 960
const H := 1360
const MAX_W := 840

const QR_AREA := 280  # 二维码区域边长（px），保证模块≥3px

func setup(c: Dictionary, q: String) -> void:
	card = c
	qr_data = q
	_font = load("res://assets/share/font_pixel.ttf")
	_bg_tex = load("res://assets/share/card_bg.png")


func _ready() -> void:
	custom_minimum_size = Vector2(W, H)
	size = Vector2(W, H)


## 按像素宽度逐字换行
func _wrap(text: String, font_size: int, max_w: float) -> Array:
	var lines := []
	var cur := ""
	for ch in text:
		var test := cur + ch
		var tw := _font.get_string_size(test, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		if tw <= max_w:
			cur = test
		else:
			if cur != "":
				lines.append(cur)
			cur = ch
	if cur != "":
		lines.append(cur)
	return lines


## 辅材效果描述（与 CardGallery._describe_aux_effect 一致）
func _describe_aux_effect(aux: Dictionary) -> String:
	var effect = aux.get("effect", {})
	if effect.is_empty():
		return ""
	var parts := []
	if effect.has("atk_bonus"):
		parts.append("攻击+" + str(effect["atk_bonus"]))
	if effect.has("hp_bonus"):
		parts.append("生命+" + str(effect["hp_bonus"]))
	if effect.has("energy_reduce"):
		parts.append("费用-" + str(effect["energy_reduce"]))
	if effect.has("element"):
		parts.append("属性→" + str(effect["element"]))
	if effect.has("element_power"):
		parts.append("元素威力+" + str(effect["element_power"] * 100) + "%")
	if effect.has("shield"):
		parts.append("护盾" + str(effect["shield"]))
	if effect.get("indestructible_once", false):
		parts.append("免毁一次")
	if effect.get("haste", false):
		parts.append("急速")
	if effect.has("extra_trigger"):
		parts.append("额外触发+" + str(effect["extra_trigger"]))
	if effect.has("draw_on_summon"):
		parts.append("召唤抽" + str(effect["draw_on_summon"]))
	if effect.has("damage_reduce"):
		parts.append("减伤" + str(effect["damage_reduce"]))
	if effect.get("damage_halve", false):
		parts.append("伤害减半")
	if effect.has("poison"):
		parts.append("中毒+" + str(effect["poison"]))
	if effect.get("combo", false):
		parts.append("连击")
	if effect.has("field_sync"):
		parts.append("场地同步")
	if parts.is_empty():
		return ""
	return "[" + " ".join(parts) + "]"


func _draw() -> void:
	# === 背景 ===
	if _bg_tex != null:
		draw_texture_rect(_bg_tex, Rect2(0, 0, W, H), false)
	else:
		draw_rect(Rect2(0, 0, W, H), BG_COL)

	# === 卡牌数据 ===
	var card_name: String = card.get("name", card.get("card_name", "未命名"))
	var fields: Array = card.get("fields", [])
	var atk: int = card.get("atk", card.get("attack", 0))
	var hp_val: int = card.get("hp", card.get("health", 0))
	var cost: int = card.get("cost", card.get("energy_cost", 0))
	var quality: String = card.get("quality", "普通")
	var element: String = CardManager.get_card_element(card)
	var star: int = card.get("star", 1)
	var effects_raw: Array = card.get("effects", [])
	var desc: String = card.get("description", card.get("desc", ""))
	var aux_items: Array = card.get("aux_items", [])

	# 提取效果描述
	var effects := []
	for e in effects_raw:
		if e is Dictionary:
			var eff_desc = Global.get_effect_desc(e)
			if eff_desc != "":
				effects.append(eff_desc)
		elif e is String:
			var comp = Global.get_circuit_by_id(e)
			if comp and comp.has("name"):
				effects.append(comp["name"])
			elif e != "":
				effects.append(e)

	var field_text := ""
	if fields.size() > 0:
		field_text = " · ".join(fields)

	var elem_map := {"火": "[火]", "水": "[水]", "风": "[风]", "暗": "[暗]", "光": "[光]", "地": "[地]", "无": ""}
	var elem_label: String = elem_map.get(element, "")

	# 1. 卡名（88px 金色）
	draw_string(_font, Vector2(60, 140), card_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 88, GOLD)

	# 2. 字段（44px）
	if field_text != "":
		draw_string(_font, Vector2(60, 200), field_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 44, FIELD_COL)

	# 3. 分隔线
	draw_line(Vector2(60, 224), Vector2(900, 224), GOLD_DIM, 2.0)

	# 4. 攻防费
	draw_string(_font, Vector2(60, 292), "攻击", HORIZONTAL_ALIGNMENT_LEFT, -1, 44, RED_DIM)
	draw_string(_font, Vector2(60, 356), str(atk), HORIZONTAL_ALIGNMENT_LEFT, -1, 64, RED)
	draw_string(_font, Vector2(280, 292), "生命", HORIZONTAL_ALIGNMENT_LEFT, -1, 44, GREEN_DIM)
	draw_string(_font, Vector2(280, 356), str(hp_val), HORIZONTAL_ALIGNMENT_LEFT, -1, 64, GREEN)
	draw_string(_font, Vector2(500, 292), "费用", HORIZONTAL_ALIGNMENT_LEFT, -1, 44, BLUE_DIM)
	draw_string(_font, Vector2(500, 356), str(cost), HORIZONTAL_ALIGNMENT_LEFT, -1, 64, BLUE)

	# 5. 品质 + 元素 + 星级
	var qual_text := quality
	if elem_label != "":
		qual_text += "  " + elem_label
	draw_string(_font, Vector2(60, 428), qual_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 44, Color(0.7, 0.7, 0.7, 1.0))
	var star_text := ""
	for i in range(star):
		star_text += "*"
	var star_w := _font.get_string_size(star_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 44).x
	draw_string(_font, Vector2(900 - star_w, 428), star_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 44, STAR_COL)

	# 6. 分隔线
	draw_line(Vector2(60, 456), Vector2(900, 456), GOLD_DIM, 2.0)

	# 7. 效果标题
	draw_string(_font, Vector2(60, 520), "效果", HORIZONTAL_ALIGNMENT_LEFT, -1, 44, GOLD_TITLE)

	# 8. 效果描述（自动换行 + 自适应字号，高清字号）
	var drawn_y := 572
	if effects.size() > 0:
		for size in range(48, 24, -1):
			var line_height := size + 12
			var all_lines := []
			for eff in effects:
				all_lines.append_array(_wrap("- " + eff, size, MAX_W))
			var total_h := all_lines.size() * line_height
			if total_h <= 220 or size <= 26:
				var y := 572
				for line in all_lines:
					draw_string(_font, Vector2(60, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, size, WHITE)
					y += line_height
				drawn_y = y
				break

	# 9. 描述
	var sep := drawn_y + 12
	if desc != "":
		draw_string(_font, Vector2(60, sep), "描述", HORIZONTAL_ALIGNMENT_LEFT, -1, 44, GOLD_TITLE)
		var dy := sep + 48
		for line in _wrap(desc, 34, MAX_W):
			draw_string(_font, Vector2(60, dy), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, DESC_COL)
			dy += 46
		drawn_y = dy + 8
	else:
		drawn_y = sep + 12

	# 10. 辅材
	if aux_items.size() > 0:
		draw_string(_font, Vector2(60, drawn_y), "辅材", HORIZONTAL_ALIGNMENT_LEFT, -1, 44, GOLD_TITLE)
		var ay := drawn_y + 48
		for aux in aux_items:
			var an: String = aux.get("name", "")
			var ae: String = _describe_aux_effect(aux)
			var tx := an + "  " + ae if ae != "" else an
			draw_string(_font, Vector2(60, ay), tx, HORIZONTAL_ALIGNMENT_LEFT, -1, 36, AUX_COL)
			ay += 48
		drawn_y = ay + 8
	else:
		drawn_y += 12

	# 11. 分隔线
	var sep_y := drawn_y + 12
	draw_line(Vector2(60, sep_y), Vector2(900, sep_y), GOLD_DIM, 2.0)

	# 12. 二维码（右下角，白底+深色模块，保证可扫可放大）
	var qr_x := W - 60 - QR_AREA
	var qr_y := sep_y + 40
	var qr_matrix: Array = QRCode.generate(qr_data)
	var qr_s := qr_matrix.size()
	var scale := int(QR_AREA / (qr_s + 4))
	if scale < 3:
		scale = 3
	var qr_draw_size := qr_s * scale
	var offset := int((QR_AREA - qr_draw_size) / 2.0)
	# 先画白底（带边框），保证与深色卡面高对比
	draw_rect(Rect2(qr_x - 4, qr_y - 4, QR_AREA + 8, QR_AREA + 8), QR_BG)
	# 再画深色模块
	for yy in range(qr_s):
		for xx in range(qr_s):
			if qr_matrix[yy][xx] == 1:
				draw_rect(Rect2(qr_x + offset + xx * scale, qr_y + offset + yy * scale, scale, scale), QR_FG)

	# 13. 扫码导入标签
	draw_string(_font, Vector2(qr_x + 14, qr_y + QR_AREA + 34), "扫码导入", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, GOLD_TITLE)

	# 14. 底部水印
	var wm := "卡牌大师 - 分享"
	var wm_w := _font.get_string_size(wm, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
	draw_string(_font, Vector2((W - wm_w) / 2.0, 1300), wm, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(200.0 / 255.0, 160.0 / 255.0, 60.0 / 255.0, 0.47))