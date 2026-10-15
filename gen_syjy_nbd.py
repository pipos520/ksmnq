# -*- coding: utf-8 -*-
# 从设计稿txt直接解析《三约纪元》《你不对劲》卡包，追加到 local_card_packs.json
import json, datetime, re, os

PACKS_FILE = "Data/local_card_packs.json"
DESIGN_DIR = "/storage/emulated/0/Documents/卡师模拟器卡牌世界设计文档"

def parse_recipe(s):
    s = s.strip()
    if not s or s in ("白板", "—", "-"):
        return []
    out = []
    for part in re.split(r"\s*\+\s*", s):
        part = part.strip()
        # 带数值: TR01→A20(1)/T03 ; 无数值: TR01→A33/T02 (value 默认 1)
        m = re.match(r"^(TR\d+)[→](A\d+)\((\d+)\)/(T\d+)$", part)
        if not m:
            m = re.match(r"^(TR\d+)[→](A\d+)/(T\d+)$", part)
        if m:
            trigger, action, target = m.group(1), m.group(2), m.group(4 if m.lastindex == 4 else 3)
            value = int(m.group(3)) if m.lastindex == 4 else 1
            out.append({"trigger": trigger, "action": action, "value": value, "target": target})
    return out

def parse_pack_section(section, theme, pack_id, id_prefix):
    lines = [l for l in section.split("\n") if l.strip()]
    name = "?"
    for l in lines:
        m = re.match(r"^##\s*第.包「(.+)」", l.strip())
        if m:
            name = m.group(1)
    fields = [theme, name]
    rows = []
    for l in lines:
        l = l.strip()
        if not l.startswith("|"):
            continue
        cells = [c.strip() for c in l.strip("|").split("|")]
        if len(cells) < 8 or not cells[0].isdigit():
            continue
        card_name, atk_hp, cost_s, star_s, eff_desc, recipe_s, flavor = cells[1], cells[2], cells[3], cells[4], cells[5], cells[6], cells[7]
        atk_s, hp_s = atk_hp.split("/")
        atk, hp = int(atk_s), int(hp_s)
        cost, star = int(cost_s), int(star_s)
        effects = parse_recipe(recipe_s)
        rows.append({"name": card_name, "atk": atk, "hp": hp, "cost": cost,
                     "star": star, "eff_desc": eff_desc, "effects": effects,
                     "flavor": flavor})
    elems_pool = ["火", "水", "风", "地", "光", "暗"]
    cards = []
    for i, r in enumerate(rows, 1):
        cid = "%s_%03d" % (id_prefix, i)
        if r["star"] >= 3:
            q = "完美"
        elif r["star"] == 2:
            q = "卓越"
        elif r["effects"]:
            q = "精良"
        else:
            q = "标准"
        el = elems_pool[(i - 1) % len(elems_pool)]
        c = {"id": cid, "name": r["name"], "atk": r["atk"], "hp": r["hp"],
             "cost": r["cost"], "star": r["star"], "element": el, "quality": q,
             "fields": fields, "desc": r["flavor"]}
        if r["effects"]:
            for e in r["effects"]:
                e["desc"] = r["eff_desc"]
            c["effects"] = r["effects"]
        cards.append(c)
    return {"name": name, "cards": cards}

def main():
    import sys
    dry = "--dry-run" in sys.argv
    syjy_path = os.path.join(DESIGN_DIR, "三约纪元", "卡包设计_三约纪元.txt")
    nbd_path = os.path.join(DESIGN_DIR, "你不对劲", "卡包设计_你不对劲.txt")
    syjy_txt = open(syjy_path, encoding="utf-8").read()
    nbd_txt = open(nbd_path, encoding="utf-8").read()

    syjy_sections = re.split(r"\n## 第", syjy_txt)
    syjy_pack_ids = ["syjy_qw", "syjy_wf", "syjy_sg", "syjy_sy", "syjy_lj", "syjy_yl", "syjy_hs", "syjy_sd"]
    syjy_prefixes = ["CARD_SYQW", "CARD_SYWF", "CARD_SYSG", "CARD_SYSY", "CARD_SYLJ", "CARD_SYYL", "CARD_SYHS", "CARD_SYSD"]
    new_packs = []
    pack_idx = 0
    for sec in syjy_sections[1:]:
        sec = "## 第" + sec
        pid = syjy_pack_ids[pack_idx]
        parsed = parse_pack_section(sec, "三约纪元", pid, syjy_prefixes[pack_idx])
        pack = {"id": "pack_" + pid, "pack_id": pid,
                "pack_data": {"name": parsed["name"], "desc": "", "cards": parsed["cards"]},
                "theme": "三约纪元", "created_at": datetime.datetime.now().strftime("%Y-%m-%dT%H:%M:%S")}
        new_packs.append(pack)
        pack_idx += 1

    nbd_sections = re.split(r"\n## 第", nbd_txt)
    for sec in nbd_sections[1:]:
        sec = "## 第" + sec
        parsed = parse_pack_section(sec, "你不对劲", "nbd_rl", "CARD_NBD")
        pack = {"id": "pack_nbd_rl", "pack_id": "nbd_rl",
                "pack_data": {"name": parsed["name"], "desc": "", "cards": parsed["cards"]},
                "theme": "你不对劲", "created_at": datetime.datetime.now().strftime("%Y-%m-%dT%H:%M:%S")}
        new_packs.append(pack)

    for p in new_packs:
        cards = p["pack_data"]["cards"]
        n_eff = sum(1 for c in cards if c.get("effects"))
        ids = [c["id"] for c in cards]
        print("【%s】%s: %d张, 效果卡%d张, id: %s..%s" % (p["theme"], p["pack_data"]["name"], len(cards), n_eff, ids[0], ids[-1]))
    print("共生成 %d 个新卡包" % len(new_packs))

    if dry:
        print("🟡 dry-run：未写入文件")
        return

    # 追加到本地卡包文件
    data = json.load(open(PACKS_FILE, encoding="utf-8"))
    before = len(data)
    data.extend(new_packs)
    with open(PACKS_FILE, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
    print("已追加 %d 个卡包: %d -> %d" % (len(new_packs), before, len(data)))

if __name__ == "__main__":
    main()