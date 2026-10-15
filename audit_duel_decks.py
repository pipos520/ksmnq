# -*- coding: utf-8 -*-
# 审计决斗场 AI 卡组（local_ai_decks.json）：能量公式重算 + 超标检查
import json, re, math

GLOBAL = "Global.gd"
DECKS = "Data/local_ai_decks.json"

gd = open(GLOBAL, encoding="utf-8").read()

def strip_comment(line):
    return line.strip().startswith("#")

def parse_circuit(var_name, id_pattern, energy_key=None, mod_key=None):
    m = re.search(r"var %s := \[(.*?)\n\]" % var_name, gd, re.S)
    if not m: return {}
    body = m.group(1)
    out = {}
    for line in body.split("\n"):
        lm = re.search(r'"id":\s*"(%s)"' % id_pattern, line)
        if not lm: continue
        cid = lm.group(1)
        entry = {"commented": strip_comment(line)}
        if energy_key:
            em = re.search(r'"%s":\s*"?([\d.]+|[^",}]+)"?' % energy_key, line)
            if em:
                v = em.group(1)
                try: entry["energy"] = float(v)
                except ValueError: entry["energy"] = v.strip()
        if mod_key:
            mm = re.search(r'"%s":\s*([\d.]+)' % mod_key, line)
            if mm: entry["mod"] = float(mm.group(1))
        out[cid] = entry
    return out

TR = parse_circuit("circuit_triggers", r"TR\d+", energy_key="base_energy")
A  = parse_circuit("circuit_actions", r"A\d+", energy_key="base_energy")
T  = parse_circuit("circuit_targets", r"T\d+", mod_key="modifier")

def energy_of(cat, cid):
    return cat.get(cid, {}).get("energy", 0.0)

def calc_cost(atk, hp, effects):
    base = math.floor((atk + hp) / 2.0)
    circ = 0.0
    for e in effects:
        tr = e.get("trigger", ""); ac = e.get("action", ""); tg = e.get("target", "")
        val = e.get("value", 1)
        tr_e = energy_of(TR, tr) if tr else 0.0
        a_raw = energy_of(A, ac) if ac else 0.0
        if isinstance(a_raw, str):
            mm = re.match(r"数值×([\d.]+)", a_raw)
            a_e = float(val) * float(mm.group(1)) if mm else 0.0
        else:
            a_e = float(a_raw) if a_raw else 0.0
        t_mod = T.get(tg, {}).get("mod", 1.0) if tg else 1.0
        if tr and ac:
            g = (tr_e + a_e) * t_mod
            if g > 0: circ += g
    return max(1, math.ceil(base + circ))

data = json.load(open(DECKS, encoding="utf-8"))
print("决斗场AI卡组: %d 套 | 开始审计\n" % len(data))

all_probs = []
total_cards = 0
for dk in data:
    dd = dk.get("deck_data", {})
    dname = dd.get("name", "?")
    cards = dd.get("card_datas", [])
    d_probs = []
    seen_cards = set()  # 同一张卡重复时只报一次
    for c in cards:
        total_cards += 1
        cid = c.get("id", "?"); name = c.get("name", "?")
        atk, hp, cost = c.get("atk", 0), c.get("hp", 0), c.get("cost", 0)
        effs = c.get("effects", [])
        key = (name, cid)
        calc = calc_cost(atk, hp, effs)
        # 能量不符
        if calc != cost and key not in seen_cards:
            d_probs.append("%s[%s]: cost存储=%d 公式重算=%d %s" % (
                name, cid, cost, calc, "⚠️差1取舍?" if abs(calc-cost)<=1 else ""))
            seen_cards.add(key)
        # 超标
        if cost > 10 and key not in seen_cards:
            d_probs.append("%s[%s]: cost=%d 超上限10!" % (name, cid, cost)); seen_cards.add(key)
        if calc > 10 and key not in seen_cards:
            d_probs.append("%s[%s]: 公式能量=%d 超上限10!" % (name, cid, calc)); seen_cards.add(key)
    if d_probs:
        all_probs.append((dname, d_probs))

n_bad = len(all_probs)
n_probs = sum(len(x[1]) for x in all_probs)
print("总卡数(含重复): %d\n" % total_cards)
for dname, probs in all_probs:
    print("【%s】问题 %d 条:" % (dname, len(probs)))
    for pr in probs: print("    ", pr)
    print()
print("=== 汇总 ===")
print("问题卡组: %d/%d | 问题条目: %d" % (n_bad, len(data), n_probs))
if n_bad == 0:
    print("✅ 全部决斗场AI卡组无能量问题、无超标")