#!/usr/bin/env python3
"""
像素风按钮 - 铆钉渐变倒角版 - 批量生成
6张：夜间3状态 + 白天3状态
光源：左上
"""
from PIL import Image

W, H = 96, 56
CHAMFER = 6
OUT_DIR = "/storage/emulated/0/Documents/ksmnqsp/assets/theme/btn_textures"

# ---- 色阶 ----
THEMES = {
    "night": {
        "outline": (15, 30, 38),
        "highlight": (140, 180, 195),
        "base":     (95, 140, 155),
        "shadow":   (55, 90, 105),
        "deep":     (30, 55, 68),
        "rivet_hole": (10, 20, 25),
        "rivet_rim":  (40, 60, 70),
    },
    "day": {
        "outline": (80, 55, 35),
        "highlight": (220, 195, 160),
        "base":     (190, 160, 120),
        "shadow":   (150, 120, 85),
        "deep":     (115, 88, 58),
        "rivet_hole": (60, 42, 28),
        "rivet_rim":  (100, 75, 50),
    },
}

# 按下状态：整体压暗 + 偏移光源（模拟内凹）
PRESSED_DARKEN = 0.7  # 压暗到70%

def lerp(c1, c2, t):
    return tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3))

def darken(c, factor):
    return tuple(max(0, int(c[i] * factor)) for i in range(3))

def make_button(theme_key, state):
    t = THEMES[theme_key]
    # 按下状态压暗所有颜色
    if state == "pressed":
        hl  = darken(t["highlight"], PRESSED_DARKEN)
        bs  = darken(t["base"], PRESSED_DARKEN)
        sh  = darken(t["shadow"], PRESSED_DARKEN)
        dp  = darken(t["deep"], PRESSED_DARKEN)
        ol  = darken(t["outline"], PRESSED_DARKEN)
        rh  = darken(t["rivet_hole"], PRESSED_DARKEN)
        rr  = darken(t["rivet_rim"], PRESSED_DARKEN)
    elif state == "hover":
        # hover 稍微提亮
        hl  = lerp(t["highlight"], (255,255,255), 0.12)
        bs  = lerp(t["base"], (255,255,255), 0.08)
        sh  = t["shadow"]
        dp  = t["deep"]
        ol  = t["outline"]
        rh  = t["rivet_hole"]
        rr  = t["rivet_rim"]
    else:
        hl  = t["highlight"]
        bs  = t["base"]
        sh  = t["shadow"]
        dp  = t["deep"]
        ol  = t["outline"]
        rh  = t["rivet_hole"]
        rr  = t["rivet_rim"]

    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    px = img.load()

    for y in range(H):
        for x in range(W):
            # ---- 倒角圆弧 ----
            in_chamfer = False
            if x < CHAMFER and y < CHAMFER:
                dx, dy = x - CHAMFER, y - CHAMFER
                if dx*dx + dy*dy > CHAMFER*CHAMFER:
                    in_chamfer = True
            elif x >= W - CHAMFER and y < CHAMFER:
                dx, dy = x - (W-1-CHAMFER), y - CHAMFER
                if dx*dx + dy*dy > CHAMFER*CHAMFER:
                    in_chamfer = True
            elif x < CHAMFER and y >= H - CHAMFER:
                dx, dy = x - CHAMFER, y - (H-1-CHAMFER)
                if dx*dx + dy*dy > CHAMFER*CHAMFER:
                    in_chamfer = True
            elif x >= W - CHAMFER and y >= H - CHAMFER:
                dx, dy = x - (W-1-CHAMFER), y - (H-1-CHAMFER)
                if dx*dx + dy*dy > CHAMFER*CHAMFER:
                    in_chamfer = True

            if in_chamfer:
                continue

            # ---- 光源因子（对角线）----
            nx = x / (W - 1)
            ny = y / (H - 1)
            light = 1.0 - (nx * 0.5 + ny * 0.5)

            # ---- 外轮廓 ----
            is_outer = (x == 0 or x == W-1 or y == 0 or y == H-1)
            if is_outer:
                px[x, y] = (*ol, 255)
                continue

            # ---- 内边框 ----
            is_inner = (x == 1 or x == W-2 or y == 1 or y == H-2)
            if is_inner:
                c = lerp(sh, bs, light)
                px[x, y] = (*c, 255)
                continue

            # ---- 铆钉洞 ----
            rivet_r = 2
            rivet_off = 6
            rivets = [
                (rivet_off, rivet_off),
                (W-1-rivet_off, rivet_off),
                (rivet_off, H-1-rivet_off),
                (W-1-rivet_off, H-1-rivet_off),
            ]
            is_hole = False
            is_rim = False
            for (rx, ry) in rivets:
                dx, dy = x - rx, y - ry
                d2 = dx*dx + dy*dy
                if d2 <= (rivet_r - 0.5)**2:
                    is_hole = True
                    break
                elif d2 <= (rivet_r + 0.5)**2:
                    is_rim = True
                    break
            if is_hole:
                px[x, y] = (*rh, 255)
                continue
            if is_rim:
                c = lerp(rr, rh, 1.0 - light)
                px[x, y] = (*c, 255)
                continue

            # ---- 主体3级渐变 ----
            if light > 0.6:
                c = lerp(bs, hl, (light - 0.6) / 0.4)
            elif light > 0.3:
                c = lerp(sh, bs, (light - 0.3) / 0.3)
            else:
                c = lerp(dp, sh, light / 0.3)

            px[x, y] = (*c, 255)

    return img


# ====== 生成 6 张 ======
print("=== 生成像素风按钮（夜间+白天，各3状态）===\n")

for theme_key in ["night", "day"]:
    for state in ["normal", "hover", "pressed"]:
        img = make_button(theme_key, state)
        fname = f"btn_{state}_{theme_key}.png"
        out_path = f"{OUT_DIR}/{fname}"
        img.save(out_path)
        print(f"  ✅ {fname} ({img.size[0]}x{img.size[1]})")

print("\n=== 全部完成！===")