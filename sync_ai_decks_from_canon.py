# -*- coding: utf-8 -*-
# 用 local_card_packs.json 真源刷新 local_ai_decks.json 中的卡字段（按卡名匹配）
import json, shutil, time

packs = json.load(open("Data/local_card_packs.json", encoding="utf-8"))
canon = {}
for p in packs:
    for c in p.get("pack_data", {}).get("cards", []):
        canon.setdefault(c.get("name"), c)  # 同名取首见（真源应唯一）

ts = time.strftime("%Y%m%d%H%M%S")
shutil.copy("Data/local_ai_decks.json", "Data/local_ai_decks.before_sync_%s.json" % ts)

data = json.load(open("Data/local_ai_decks.json", encoding="utf-8"))
n_sync = 0; n_missing = 0; missing = set()
for d in data:
    cds = d["deck_data"]["card_datas"]
    for i, c in enumerate(cds):
        name = c.get("name")
        if name in canon:
            nc = dict(canon[name])  # 全量替换为真源字段
            if nc != c:
                n_sync += 1
            cds[i] = nc
        else:
            n_missing += 1
            missing.add(name)

json.dump(data, open("Data/local_ai_decks.json", "w", encoding="utf-8"), ensure_ascii=False, indent=2)
print("真源卡种: %d" % len(canon))
print("同步替换卡条: %d" % n_sync)
print("真源中找不到的: %d 条（%d 种）" % (n_missing, len(missing)))
for m in sorted(missing): print("  MISSING:", m)
print("备份: Data/local_ai_decks.before_sync_%s.json" % ts)