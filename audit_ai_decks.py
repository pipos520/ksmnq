# -*- coding: utf-8 -*-
# 决斗场AI卡组审计：复用 full_audit_packs.py 的解析器与 calc_cost
import json
import full_audit_packs as F

data = json.load(open("Data/local_ai_decks.json", encoding="utf-8"))
probs = []
seen = {}
total = 0
for d in data:
    dname = d["deck_data"]["name"]
    for c in d["deck_data"]["card_datas"]:
        total += 1
        name = c.get("name", "?")
        if name in seen:
            prev = seen[name]
            if c.get("cost") != prev.get("cost") or c.get("atk") != prev.get("atk") or c.get("hp") != prev.get("hp"):
                probs.append((dname, name, "同名卡数据不一致: 本套cost=%s vs 首见cost=%s" % (c.get("cost"), prev.get("cost"))))
            continue
        seen[name] = c
        stored = c.get("cost", -1)
        atk = c.get("atk", 0); hp = c.get("hp", 0)
        effs = c.get("effects", []) or []
        calc = F.calc_cost(atk, hp, effs)
        if stored != calc:
            probs.append((dname, name, "cost算错: 存储%d 应为%d (攻%d命%d 效果%d条)" % (stored, calc, atk, hp, len(effs))))
        elif calc > 10:
            probs.append((dname, name, "超标: cost=%d (攻%d命%d)" % (calc, atk, hp)))

print("=" * 50)
print("卡组数: %d | 卡条数: %d | 去重卡种: %d" % (len(data), total, len(seen)))
if probs:
    print("❌ 问题 %d 条:" % len(probs))
    for dname, name, msg in probs:
        print("  [%s] %s | %s" % (dname, name, msg))
else:
    print("✅ 全部决斗场AI卡组无能量算错、无超标")