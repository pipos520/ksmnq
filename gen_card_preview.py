from PIL import Image, ImageDraw, ImageFont
import qrcode

W, H = 480, 680

img = Image.new('RGBA', (W, H), (0, 0, 0, 0))
draw = ImageDraw.Draw(img)

# 深紫底色 + 金色边框
draw.rounded_rectangle((0, 0, W-1, H-1), radius=24, fill=(28, 18, 48, 255))
draw.rounded_rectangle((0, 0, W-1, H-1), radius=24, outline=(200, 160, 60, 255), width=4)
draw.rounded_rectangle((6, 6, W-7, H-7), radius=18, outline=(140, 110, 45, 255), width=1)

FONT_PATH = "/storage/emulated/0/Documents/ksmnqsp/assets/share/font.ttf"

# ===== 卡牌数据：青云符师 =====
card_name = "青云符师"
card_fields = ["青云派", "符法"]
card_atk = 1
card_hp = 2
card_cost = 3
card_quality = "标准"
card_element = "风"
card_desc = "青云符师，符法通灵。入场时从牌库中抽一张牌。"
card_star = 1
card_effects = ["入场：抽1张牌"]
card_aux_items = []  # 新手卡没有辅材，示例留空

# 处理品质显示
quality_display = card_quality

# 字段合并
field_text = " · ".join(card_fields) if card_fields else ""

# 元素图标（文字版）
elem_icon_map = {"火": "[火]", "水": "[水]", "风": "[风]", "暗": "[暗]", "光": "[光]", "地": "[地]", "无": ""}
elem_label = elem_icon_map.get(card_element, "")

# ----- 1. 卡名（44px，金色）-----
font_name = ImageFont.truetype(FONT_PATH, 44)
draw.text((30, 28), card_name, font=font_name, fill=(200, 160, 60, 255))

# ----- 2. 字段（22px，浅蓝灰，在卡名下面）-----
font_field = ImageFont.truetype(FONT_PATH, 22)
if field_text:
    draw.text((30, 78), field_text, font=font_field, fill=(160, 180, 220, 220))

# ----- 3. 分隔线 -----
draw.line((30, 112, W-30, 112), fill=(200, 160, 60, 128), width=1)

# ----- 4. 攻击/生命/费用 -----
font_label = ImageFont.truetype(FONT_PATH, 22)
font_val = ImageFont.truetype(FONT_PATH, 32)

draw.text((30, 124), "攻击", font=font_label, fill=(200, 80, 80, 200))
draw.text((30, 150), str(card_atk), font=font_val, fill=(220, 60, 60, 255))

draw.text((140, 124), "生命", font=font_label, fill=(80, 200, 80, 200))
draw.text((140, 150), str(card_hp), font=font_val, fill=(60, 220, 60, 255))

draw.text((250, 124), "费用", font=font_label, fill=(80, 130, 220, 200))
draw.text((250, 150), str(card_cost), font=font_val, fill=(60, 120, 220, 255))

# ----- 5. 品质 + 元素 + 星级 -----
font_qual = ImageFont.truetype(FONT_PATH, 26)
qual_text = quality_display
if elem_label:
    qual_text += "  " + elem_label
draw.text((30, 192), qual_text, font=font_qual, fill=(180, 180, 180, 255))
star_text = "*" * card_star
star_bbox = draw.textbbox((0, 0), star_text, font=font_qual)
star_w = star_bbox[2] - star_bbox[0]
draw.text((W - 30 - star_w, 192), star_text, font=font_qual, fill=(200, 180, 100, 255))

# ----- 6. 分隔线 -----
draw.line((30, 228, W-30, 228), fill=(200, 160, 60, 128), width=1)

# ----- 7. 效果标题 -----
draw.text((30, 238), "效果", font=font_label, fill=(200, 160, 60, 200))

# ----- 8. 效果描述（自动换行 + 自适应字号）-----
MAX_WIDTH = 420
TEXT_START_Y = 266
TEXT_MAX_HEIGHT = 110

def wrap_text_to_lines(text, font, max_width_px):
    lines = []
    for paragraph in text.split('\n'):
        if not paragraph:
            lines.append('')
            continue
        words = []
        current = ''
        for ch in paragraph:
            test = current + ch
            bbox = draw.textbbox((0, 0), test, font=font)
            if bbox[2] - bbox[0] <= max_width_px:
                current = test
            else:
                if current:
                    words.append(current)
                current = ch
        if current:
            words.append(current)
        lines.extend(words)
    return lines

full_effect_text = "\n".join([f"- {e}" for e in card_effects])

drawn_y = TEXT_START_Y
for size in range(26, 13, -1):
    font_eff = ImageFont.truetype(FONT_PATH, size)
    line_height = size + 6
    lines = wrap_text_to_lines(full_effect_text, font_eff, MAX_WIDTH)
    total_height = len(lines) * line_height
    if total_height <= TEXT_MAX_HEIGHT or size <= 14:
        y = TEXT_START_Y
        for line in lines:
            if line:
                draw.text((30, y), line, font=font_eff, fill=(200, 200, 200, 255))
            y += line_height
        drawn_y = y
        print(f'✅ 效果字号: {size}px, {len(lines)}行, 高{total_height}px')
        break

# ----- 9. 描述（如果有）-----
sep_after_eff = drawn_y + 6
if card_desc:
    font_desc = ImageFont.truetype(FONT_PATH, 18)
    desc_label = "描述"
    draw.text((30, sep_after_eff), desc_label, font=font_label, fill=(200, 160, 60, 180))
    desc_y = sep_after_eff + 24
    desc_lines = wrap_text_to_lines(card_desc, font_desc, MAX_WIDTH)
    for line in desc_lines:
        if line:
            draw.text((30, desc_y), line, font=font_desc, fill=(160, 160, 160, 220))
        desc_y += 24
    drawn_y = desc_y + 4
else:
    drawn_y = sep_after_eff + 6

# ----- 10. 辅材（如果有）-----
if card_aux_items:
    font_aux = ImageFont.truetype(FONT_PATH, 18)
    aux_label = "辅材"
    draw.text((30, drawn_y), aux_label, font=font_label, fill=(200, 160, 60, 180))
    aux_y = drawn_y + 24
    for aux in card_aux_items:
        aux_name = aux.get("name", "")
        aux_eff = aux.get("effect", "")
        aux_text = f"{aux_name}  {aux_eff}" if aux_eff else aux_name
        draw.text((30, aux_y), aux_text, font=font_aux, fill=(140, 180, 200, 220))
        aux_y += 24
    drawn_y = aux_y + 4
else:
    drawn_y = drawn_y + 6

# ----- 11. 分隔线 -----
sep_y = drawn_y + 6
draw.line((30, sep_y, W-30, sep_y), fill=(200, 160, 60, 128), width=1)

# ----- 12. 二维码（右下角）-----
# 构建二维码数据（压缩码格式，与 _compress_card 一致）
qr_parts = []
qr_parts.append(f"N{card_name}")
qr_parts.append(f"A{card_atk}")
qr_parts.append(f"H{card_hp}")
qr_parts.append(f"C{card_cost}")
q_map = {"标准": "1", "精良": "2", "优秀": "2", "卓越": "3", "完美": "4"}
qr_parts.append(f"Q{q_map.get(card_quality, '0')}")
e_map = {"火": "F", "水": "W", "风": "A", "暗": "D", "光": "L", "地": "E", "无": "N"}
qr_parts.append(f"E{e_map.get(card_element, 'N')}")
qr_parts.append(f"S{card_star}")
if card_fields:
    qr_parts.append(f"F{','.join(card_fields)}")
if card_desc:
    qr_parts.append(f"D{card_desc}")
if card_effects:
    qr_parts.append(f"X{';'.join(card_effects)}")
if card_aux_items:
    aux_strs = []
    for aux in card_aux_items:
        aux_strs.append(f"{aux.get('name','')}:{aux.get('effect','')}")
    qr_parts.append(f"AUX{';'.join(aux_strs)}")

qr_data = "|".join(qr_parts)

qr = qrcode.QRCode(box_size=3, border=1, error_correction=qrcode.constants.ERROR_CORRECT_M)
qr.add_data(qr_data)
qr.make(fit=True)
qr_img = qr.make_image(fill_color=(200, 160, 60), back_color=(28, 18, 48)).convert('RGBA')

qr_size = 110
qr_x = W - 30 - qr_size
qr_y = sep_y + 20

for i in range(6):
    draw.rounded_rectangle(
        (qr_x - i - 1, qr_y - i - 1, qr_x + qr_size + i + 1, qr_y + qr_size + i + 1),
        radius=4, outline=(200, 160, 60, 200 - i * 20), width=1
    )

qr_resized = qr_img.resize((qr_size, qr_size), Image.NEAREST)
img.paste(qr_resized, (qr_x, qr_y), qr_resized)

font_qr = ImageFont.truetype(FONT_PATH, 16)
scan_label = "扫码导入"
scan_bbox = draw.textbbox((0, 0), scan_label, font=font_qr)
scan_w = scan_bbox[2] - scan_bbox[0]
draw.text((qr_x + (qr_size - scan_w) / 2, qr_y + qr_size + 4), scan_label, font=font_qr, fill=(200, 160, 60, 180))

# 底部水印
watermark = "卡牌大师 - 分享"
wm_bbox = draw.textbbox((0, 0), watermark, font=font_qr)
wm_w = wm_bbox[2] - wm_bbox[0]
draw.text(((W - wm_w) / 2, H - 30), watermark, font=font_qr, fill=(200, 160, 60, 120))

img.save('/storage/emulated/0/Documents/ksmnqsp/assets/share/card_bg_sample.png')
print(f'✅ 卡牌预览图生成完成！')
print(f'二维码数据: {qr_data}')
