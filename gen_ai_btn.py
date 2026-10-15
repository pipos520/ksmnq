#!/usr/bin/env python3
"""魔搭 ModelScope 生成像素风按钮素材（统一颜色，白天/夜间两套）"""
import requests, time, json, os
from PIL import Image

BASE_URL = 'https://api-inference.modelscope.cn/'
API_KEY = "ms-4e525a06-db52-4ff6-9428-54f165e7d727"
OUT_DIR = "/storage/emulated/0/Documents/ksmnqsp/assets/theme/btn_textures"

HEADERS = {
    "Authorization": f"Bearer {API_KEY}",
    "Content-Type": "application/json",
    "X-ModelScope-Async-Mode": "true",
}

def generate_button(state, theme, size="640x400"):
    """生成一张像素风按钮"""
    state_desc = {
        "normal":  "normal resting state, slightly raised with a small bottom-right drop shadow",
        "hover":   "hover state, brighter glowing, slightly raised",
        "pressed": "pressed state, darker, sunken inward, no shadow",
    }
    theme_desc = {
        "night": "deep dark navy blue background, button color is saturated golden amber",
        "day":   "warm cream beige background, button color is soft light golden amber",
    }
    
    prompt = (
        f"Pixel art style retro 16-bit RPG game UI button texture. "
        f"{theme_desc[theme]}. {state_desc[state]}. "
        f"The button has a 1px dark outer border line, a 1px darker inner border, "
        f"four tiny black decorative squares at the inner corners, "
        f"subtle checkerboard pixel texture fill inside, "
        f"vertical gradient from lighter at top to slightly darker at bottom, "
        f"a thin bright highlight strip along the very top edge, "
        f"a thin darker strip along the very bottom edge. "
        f"The button is centered on a solid plain white background. "
        f"Clean pixel art, no text, no letters, no numbers, purely graphical button."
    )
    
    print(f"  提交: btn_{state}_{theme} ...")
    
    # 重试提交
    task_id = None
    for retry in range(5):
        if retry > 0:
            wait = 15 * (retry + 1)
            print(f"  限流，等待 {wait}s 后重试...")
            time.sleep(wait)
        
        resp = requests.post(
            f"{BASE_URL}v1/images/generations",
            headers=HEADERS,
            data=json.dumps({
                "model": "Tongyi-MAI/Z-Image-Turbo",
                "prompt": prompt,
                "size": size,
            }, ensure_ascii=False).encode('utf-8'),
            timeout=30
        )
        if resp.status_code == 200:
            task_id = resp.json().get("task_id")
            break
        elif resp.status_code == 429:
            continue
        else:
            print(f"  HTTP {resp.status_code}: {resp.text[:200]}")
            return None
    
    if not task_id:
        print(f"  ❌ 提交失败（限流）")
        return None
    
    # 轮询
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
            img_data = requests.get(img_url, timeout=30).content
            raw_path = f"{OUT_DIR}/ai_btn_{state}_{theme}_raw.png"
            with open(raw_path, "wb") as f:
                f.write(img_data)
            print(f"  ✅ 原图: {raw_path} ({len(img_data)} bytes)")
            
            # 后期处理：白底变透明 + 裁剪
            final_path = post_process(raw_path, state, theme)
            return final_path
        elif status == "FAILED":
            print(f"  ❌ 失败: {data.get('message', '')}")
            return None
        else:
            if attempt % 4 == 0:
                print(f"  ⏳ 轮询中... ({status})")
    
    print(f"  ❌ 超时")
    return None


def post_process(raw_path, state, theme):
    """白底变透明 + 自动裁剪黑边/白边"""
    img = Image.open(raw_path).convert("RGBA")
    w, h = img.size
    
    # 白色变透明（容差30）
    pixels = img.load()
    for y in range(h):
        for x in range(w):
            r, g, b, a = pixels[x, y]
            if r > 225 and g > 225 and b > 225:
                pixels[x, y] = (255, 255, 255, 0)  # 透明
            elif r < 20 and g < 20 and b < 20:
                # 纯黑也变透明（去黑边）
                pixels[x, y] = (0, 0, 0, 0)
    
    # 自动裁剪透明边
    bbox = img.getbbox()
    if bbox:
        img = img.crop(bbox)
    
    # 缩放到 96x56（2倍像素风，保持比例）
    img = img.resize((96, 56), Image.NEAREST)
    
    final_path = f"{OUT_DIR}/ai_btn_{state}_{theme}.png"
    img.save(final_path)
    print(f"  🔧 后期: {final_path} ({img.size[0]}x{img.size[1]})")
    
    # 清理原图
    os.remove(raw_path)
    return final_path


# ====== 生成 6 张：3状态 × 2主题 ======
print("=== 生成像素风按钮（统一金色，白天/夜间两套）===\n")

STATES = ["normal", "hover", "pressed"]
THEMES = ["night", "day"]

for theme in THEMES:
    for state in STATES:
        result = generate_button(state, theme)
        if result:
            print(f"  → 完成: {result}\n")
        else:
            print(f"  → 失败，跳过\n")
        time.sleep(3)  # 避免限流

print("\n=== 全部完成！===")
