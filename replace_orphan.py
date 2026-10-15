# -*- coding: utf-8 -*-
# 用真源"青云风刃"替换AI卡组里的孤儿卡"青云风雷引"（真源已不存在该卡）
import json
packs = json.load(open("Data/local_card_packs.json", encoding="utf-8"))
sub = None
for p in packs:
    for c in p["pack_data"]["cards"]:
        if c.get("name") == "青云风刃":
            sub = dict(c); break
    if sub: break
assert sub, "未找到青云风刃"
data = json.load(open("Data/local_ai_decks.json", encoding="utf-8"))
n = 0
for d in data:
    cds = d["deck_data"]["card_datas"]
    for i, c in enumerate(cds):
        if c.get("name") == "青云风雷引":
            cds[i] = dict(sub); n += 1
json.dump(data, open("Data/local_ai_decks.json", "w", encoding="utf-8"), ensure_ascii=False, indent=2)
print("替换风雷引 -> 青云风刃 共 %d 处" % n)