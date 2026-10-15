#!/usr/bin/env python3
"""生成卡牌分享图片：底版 + 文字 + 二维码
用法: python3 gen_card_image.py <card_json> <output_png>
"""
import sys, json, os
from PIL import Image, ImageDraw, ImageFont
import qrcode

FONT_PATH = os.path.join(os.path.dirname(__file__), "assets/share/font.ttf")
BG_PATH = os.path.join(os.path.dirname(__file__), "assets/share/card_bg.png")

def wrap_text_to_lines(draw, text, font, max_width):
    lines = []
    for para in text.split('\n'):
        if not para:
            lines.append('')
            continue
        words, cur = [], ''
        for ch in para:
            test = cur + ch
            bbox = draw.textbbox((0, 0), test, font=font)
            if bbox[2] - bbox[0] <= max_width:
                cur = test
            else:
                if cur: words.append(cur)
                cur = ch
        if cur: words.append(cur)
        lines.extend(words)
    return lines

def main():
    if len(sys.argv) < 3:
        card_data = {
            "name": "青云符师", "fields": ["青云派", "符法"],
            "atk": 1, "hp": 2, "cost": 3, "quality": "标准",
            "element": "风", "star": 1,
            "effects": [{"desc": "入场：抽1张牌"}],
            "desc": "青云符师，符法通灵。入场时从牌库中抽一张牌。",
            "aux_items": []
        }
        output = os.path.join(os.path.dirname(__file__), "assets/share/card_bg_sample.png")
    else:
        with open(sys.argv[1]) as f:
            card_data = json.load(f)
        output = sys.argv[2]

    W, H = 480, 680
    img = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # 底色+边框
    draw.rounded_rectangle((0, 0, W-1, H-1), radius=24, fill=(28, 18, 48, 255))
    draw.rounded_rectangle((0, 0, W-1, H-1), radius=24, outline=(200, 160, 60, 255), width=4)
    draw.rounded_rectangle((6, 6, W-7, H-7), radius=18, outline=(140, 110, 45, 255), width=1)

    font = ImageFont.truetype(FONT_PATH, 44)
    font_sm = ImageFont.truetype(FONT_PATH, 32)
    font_xs = ImageFont.truetype(FONT_PATH, 22)
    font_desc = ImageFont.truetype(FONT_PATH, 18)
    font_qr = ImageFont.truetype(FONT_PATH, 16)

    # 卡牌数据
    card_name = card_data.get("name", "未命名")
    fields = card_data.get("fields", [])
    atk = card_data.get("atk", 0)
    hp = card_data.get("hp", 0)
    cost = card_data.get("cost", 0)
    quality = card_data.get("quality", "普通")
    element = card_data.get("element", "无")
    star = card_data.get("star", 1)
    effects_raw = card_data.get("effects", [])
    desc = card_data.get("desc", "")
    aux_items = card_data.get("aux_items", [])

    # 提取效果描述
    effects = []
    for e in effects_raw:
        if isinstance(e, dict):
            effects.append(e.get("desc", e.get("effect", "")))
        elif isinstance(e, str):
            effects.append(e)

    MAX_WIDTH = 420

    # 1. 卡名
    draw.text((30, 28), card_name, font=font, fill=(200, 160, 60, 255))

    # 2. 字段
    field_text = " · ".join(fields) if fields else ""
    if field_text:
        draw.text((30, 78), field_text, font=font_xs, fill=(160, 180, 220, 220))

    # 3. 分隔线
    draw.line((30, 112, W-30, 112), fill=(200, 160, 60, 128), width=1)

    # 4. 攻防费
    draw.text((30, 124), "攻击", font=font_xs, fill=(200, 80, 80, 200))
    draw.text((30, 150), str(atk), font=font_sm, fill=(220, 60, 60, 255))
    draw.text((140, 124), "生命", font=font_xs, fill=(80, 200, 80, 200))
    draw.text((140, 150), str(hp), font=font_sm, fill=(60, 220, 60, 255))
    draw.text((250, 124), "费用", font=font_xs, fill=(80, 130, 220, 200))
    draw.text((250, 150), str(cost), font=font_sm, fill=(60, 120, 220, 255))

    # 5. 品质+元素+星级
    elem_map = {"火": "[火]", "水": "[水]", "风": "[风]", "暗": "[暗]", "光": "[光]", "地": "[地]", "无": ""}
    qual_text = quality + "  " + elem_map.get(element, "")
    draw.text((30, 192), qual_text, font=font_xs, fill=(180, 180, 180, 255))
    star_text = "*" * star
    star_bbox = draw.textbbox((0, 0), star_text, font=font_xs)
    draw.text((W - 30 - (star_bbox[2] - star_bbox[0]), 192), star_text, font=font_xs, fill=(200, 180, 100, 255))

    # 6. 分隔线
    draw.line((30, 228, W-30, 228), fill=(200, 160, 60, 128), width=1)

    # 7. 效果标题
    draw.text((30, 238), "效果", font=font_xs, fill=(200, 160, 60, 200))

    # 8. 效果描述（自适应字号）
    full_eff = "\n".join([f"- {e}" for e in effects])
    drawn_y = 266
    if full_eff.strip("- "):
        for size in range(26, 13, -1):
            f_eff = ImageFont.truetype(FONT_PATH, size)
            lh = size + 6
            lines = wrap_text_to_lines(draw, full_eff, f_eff, MAX_WIDTH)
            th = len(lines) * lh
            if th <= 110 or size <= 14:
                y = 266
                for line in lines:
                    if line: draw.text((30, y), line, font=f_eff, fill=(200, 200, 200, 255))
                    y += lh
                drawn_y = y
                break

    # 9. 描述
    sep = drawn_y + 6
    if desc:
        draw.text((30, sep), "描述", font=font_xs, fill=(200, 160, 60, 180))
        dy = sep + 24
        for line in wrap_text_to_lines(draw, desc, font_desc, MAX_WIDTH):
            if line: draw.text((30, dy), line, font=font_desc, fill=(160, 160, 160, 220))
            dy += 24
        drawn_y = dy + 4
    else:
        drawn_y = sep + 6

    # 10. 辅材
    if aux_items:
        draw.text((30, drawn_y), "辅材", font=font_xs, fill=(200, 160, 60, 180))
        ay = drawn_y + 24
        for aux in aux_items:
            an = aux.get("name", "")
            ae = aux.get("effect", "")
            tx = f"{an}  {ae}" if ae else an
            draw.text((30, ay), tx, font=font_desc, fill=(140, 180, 200, 220))
            ay += 24
        drawn_y = ay + 4
    else:
        drawn_y = drawn_y + 6

    # 11. 分隔线
    sep_y = drawn_y + 6
    draw.line((30, sep_y, W-30, sep_y), fill=(200, 160, 60, 128), width=1)

    # 12. 二维码
    q_parts = [f"N{card_name}", f"A{atk}", f"H{hp}", f"C{cost}"]
    q_map = {"普通": "1", "优秀": "2", "卓越": "3", "完美": "4"}
    q_parts.append(f"Q{q_map.get(quality, '0')}")
    e_map = {"火": "F", "水": "W", "风": "A", "暗": "D", "光": "L", "地": "E", "无": "N"}
    q_parts.append(f"E{e_map.get(element, 'N')}")
    q_parts.append(f"S{star}")
    if fields: q_parts.append(f"F{','.join(fields)}")
    if desc: q_parts.append(f"D{desc}")
    if effects: q_parts.append(f"X{';'.join(effects)}")
    if aux_items:
        aux_strs = [f"{a.get('name','')}:{a.get('effect','')}" for a in aux_items]
        q_parts.append(f"AUX{';'.join(aux_strs)}")

    qr_data = "|".join(q_parts)
    qr = qrcode.QRCode(box_size=3, border=1, error_correction=qrcode.constants.ERROR_CORRECT_M)
    qr.add_data(qr_data)
    qr.make(fit=True)
    qr_img = qr.make_image(fill_color=(200, 160, 60), back_color=(28, 18, 48)).convert('RGBA')

    qr_size = 110
    qr_x = W - 30 - qr_size
    qr_y = sep_y + 20
    for i in range(6):
        draw.rounded_rectangle((qr_x-i-1, qr_y-i-1, qr_x+qr_size+i+1, qr_y+qr_size+i+1),
                               radius=4, outline=(200, 160, 60, 200-i*20), width=1)
    qr_resized = qr_img.resize((qr_size, qr_size), Image.NEAREST)
    img.paste(qr_resized, (qr_x, qr_y), qr_resized)

    scan_label = "扫码导入"
    sw = draw.textbbox((0, 0), scan_label, font=font_qr)[2] - draw.textbbox((0, 0), scan_label, font=font_qr)[0]
    draw.text((qr_x + (qr_size - sw)/2, qr_y + qr_size + 4), scan_label, font=font_qr, fill=(200, 160, 60, 180))

    watermark = "卡牌大师 - 分享"
    ww = draw.textbbox((0, 0), watermark, font=font_qr)[2] - draw.textbbox((0, 0), watermark, font=font_qr)[0]
    draw.text(((W - ww)/2, H - 30), watermark, font=font_qr, fill=(200, 160, 60, 120))

    img.save(output)
    print(f"✅ 卡牌图片已生成: {output}")
    print(f"📦 二维码数据: {qr_data}")

if __name__ == "__main__":
    main()