#!/usr/bin/env python3
"""魔搭 ModelScope 生成主界面背景图（夜间+白天两套）
策略v3：让AI在白色背景上画深色花纹 → 提取深色花纹线条做alpha蒙版 → 叠加到纯色底
"""
import requests, time, json, os
from PIL import Image, ImageEnhance, ImageFilter

BASE_URL = 'https://api-inference.modelscope.cn/'
API_KEY = "ms-4e525a06-db52-4ff6-9428-54f165e7d727"
OUT_DIR = "/storage/emulated/0/Documents/ksmnqsp/assets/theme"

HEADERS = {
    "Authorization": f"Bearer {API_KEY}",
    "Content-Type": "application/json",
    "X-ModelScope-Async-Mode": "true",
}

PROMPTS = {
    "night": {
        "prompt": (
            "Seamless tileable pattern texture on pure white background. "
            "Traditional Chinese auspicious cloud motifs, geometric card suit symbols, "
            "intricate ornamental borders and corner decorations, "
            "all drawn in dark navy blue ink lines on white background, "
            "fine detailed line art, symmetrical layout, "
            "high contrast black ink on white, seamless repeating pattern, "
            "no text, no characters, no photographs, pure decorative pattern only"
        ),
        "negative": (
            "colors, gradient, realistic photo, text, characters, faces, "
            "buildings, scenery, 3D render, buttons, UI elements"
        ),
        "file": "bg_night.png",
        "base_color": (23, 20, 38, 255),       # #171426
        "pattern_color": (60, 50, 80, 255),     # 比底色稍亮的紫灰
        "pattern_alpha": 45,                     # ~18% 花纹强度
    },
    "day": {
        "prompt": (
            "Seamless tileable pattern texture on pure white background. "
            "Traditional Chinese auspicious cloud motifs, geometric card suit symbols, "
            "intricate ornamental borders and corner decorations, "
            "all drawn in warm sepia brown ink lines on white background, "
            "fine detailed line art, symmetrical layout, "
            "high contrast brown ink on white, seamless repeating pattern, "
            "no text, no characters, no photographs, pure decorative pattern only"
        ),
        "negative": (
            "colors, gradient, realistic photo, text, characters, faces, "
            "buildings, scenery, 3D render, buttons, UI elements"
        ),
        "file": "bg_day.png",
        "base_color": (242, 235, 223, 255),     # #F2EBDF
        "pattern_color": (180, 160, 130, 255),   # 比底色稍深的暖棕
        "pattern_alpha": 40,                     # ~16% 花纹强度
    },
}


def submit_task(cfg):
    for retry in range(5):
        if retry > 0:
            wait = 15 * (retry + 1)
            print(f"  限流，等待 {wait}s 后重试...")
            time.sleep(wait)

        payload = {
            "model": "Tongyi-MAI/Z-Image-Turbo",
            "prompt": cfg["prompt"],
            "negative_prompt": cfg["negative"],
            "size": "1024x1024",
        }
        resp = requests.post(
            f"{BASE_URL}v1/images/generations",
            headers=HEADERS,
            data=json.dumps(payload, ensure_ascii=False).encode('utf-8'),
            timeout=30
        )
        if resp.status_code == 200:
            task_id = resp.json().get("task_id")
            print(f"  ✅ 任务已提交: {task_id}")
            return task_id
        elif resp.status_code == 429:
            continue
        else:
            print(f"  HTTP {resp.status_code}: {resp.text[:300]}")
            return None
    print(f"  ❌ 提交失败")
    return None


def poll_task(task_id):
    for attempt in range(60):
        time.sleep(5)
        result = requests.get(
            f"{BASE_URL}v1/tasks/{task_id}",
            headers={**HEADERS, "X-ModelScope-Task-Type": "image_generation"},
            timeout=15
        )
        data = result.json()
        status = data.get("task_status", "")
        if status == "SUCCEED":
            img_url = data["output_images"][0]
            img_data = requests.get(img_url, timeout=60).content
            raw_path = os.path.join(OUT_DIR, "_raw_temp.png")
            with open(raw_path, "wb") as f:
                f.write(img_data)
            print(f"  ✅ 原图下载: {raw_path} ({len(img_data)} bytes)")
            return raw_path
        elif status == "FAILED":
            print(f"  ❌ 失败: {data.get('message', '')}")
            return None
        else:
            if attempt % 4 == 0:
                print(f"  ⏳ 轮询中... ({status})")
    print(f"  ❌ 超时")
    return None


def post_process(raw_path, cfg):
    """从白底深色花纹图提取花纹 → 叠加到纯色底"""
    raw = Image.open(raw_path).convert("RGBA")
    w, h = raw.size
    print(f"  原图尺寸: {w}x{h}")

    # 1. 转灰度
    gray = raw.convert("L")

    # 2. 反转：白底变黑（alpha=0），深色花纹变亮（alpha高）
    # 原图中白色(255)→反转后黑色(0)→alpha=0（透明）
    # 原图中黑色(0)→反转后白色(255)→alpha=高（花纹可见）
    inverted = Image.eval(gray, lambda x: 255 - x)

    # 3. 增强对比度
    enhancer = ImageEnhance.Contrast(inverted)
    inverted = enhancer.enhance(2.0)

    # 4. 轻微模糊让花纹更柔和
    inverted = inverted.filter(ImageFilter.GaussianBlur(radius=0.5))

    # 5. 创建纯色底
    base = Image.new("RGBA", (w, h), cfg["base_color"])

    # 6. 用反转后的灰度作为alpha，花纹颜色叠加
    pattern = Image.new("RGBA", (w, h))
    px_inv = inverted.load()
    px_pat = pattern.load()
    pat_color = cfg["pattern_color"]
    target_alpha = cfg["pattern_alpha"]
    for y in range(h):
        for x in range(w):
            g = px_inv[x, y]
            a = int(g / 255 * target_alpha)
            px_pat[x, y] = (pat_color[0], pat_color[1], pat_color[2], a)

    base = Image.alpha_composite(base, pattern)

    # 7. 添加细微噪点
    import random
    noise = Image.new("RGBA", (w, h))
    px_noise = noise.load()
    for y in range(h):
        for x in range(w):
            n = random.randint(-3, 3)
            px_noise[x, y] = (n + 128, n + 128, n + 128, 8)
    base = Image.alpha_composite(base, noise)

    # 8. 缩放到 1088x1920 (9:16)
    base = base.resize((1088, 1920), Image.LANCZOS)

    out_path = os.path.join(OUT_DIR, cfg["file"])
    base.save(out_path, "PNG")
    print(f"  🔧 最终: {out_path} ({base.size[0]}x{base.size[1]})")

    os.remove(raw_path)

    # 验证花纹是否有效
    verify = Image.open(out_path).convert("RGB")
    r_vals = []
    for y in range(0, 1920, 200):
        for x in range(0, 1088, 200):
            r_vals.append(verify.getpixel((x, y))[0])
    print(f"  验证: R min={min(r_vals)} max={max(r_vals)} diff={max(r_vals)-min(r_vals)}")
    return out_path


# ====== 生成 2 张背景 ======
print("=== 生成主界面背景图 v3（夜间+白天）===\n")

for theme_key in ["night", "day"]:
    cfg = PROMPTS[theme_key]
    print(f"--- {theme_key} ---")
    task_id = submit_task(cfg)
    if not task_id:
        continue
    raw_path = poll_task(task_id)
    if not raw_path:
        continue
    post_process(raw_path, cfg)
    time.sleep(3)

print("\n=== 全部完成！===")