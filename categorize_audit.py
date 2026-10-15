# -*- coding: utf-8 -*-
# 归类审计结果：被注释纹路 / 超上限10 / cost不符（分差1与差≥2 / 偏高偏低）
import json, re, math
from collections import defaultdict, Counter

GLOBAL = "Global.gd"
PACKS = "Data/local_card_packs.json"
gd = open(GLOBAL, encoding="utf-8").read()

def strip_comment(line): return line.strip().startswith("#")
def parse_circuit(var_name, id_pattern, energy_key=None, mod_key=None):
    m = re.search(r"var %s := \[(.*?)\n\]" % var_name, gd, re.S)
    if not m: return {}
    out = {}
    for line in m.group(1).split("\n"):
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
def available(cat, cid):
    e = cat.get(cid); return e is not None and not e.get("commented", False)
def energy_of(cat, cid):
    e = cat.get(cid, {}); return e.get("energy", 0.0)

def calc_cost(atk, hp, effects):
    base = math.floor((atk + hp) / 2.0)
    circ = 0.0
    for e in effects:
        tr, ac, tg, val = e.get("trigger",""), e.get("action",""), e.get("target",""), e.get("value",1)
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

data = json.load(open(PACKS, encoding="utf-8"))
c_commented = []   # 被注释纹路
c_over10 = []      # 存储或公式超10
c_cost_mismatch = []  # cost不符
theme_stats = Counter()

for p in data:
    theme, pid = p.get("theme","?"), p.get("pack_id","?")
    for c in p.get("pack_data",{}).get("cards",[]):
        cid, name = c.get("id","?"), c.get("name","?")
        tag = "%s/%s/%s[%s]" % (theme, pid, name, cid)
        # 1) 被注释
        for e in c.get("effects",[]):
            for kind, cat, key in (("TR",TR,e.get("trigger")),("A",A,e.get("action")),("T",T,e.get("target"))):
                if key and not available(cat, key):
                    c_commented.append((tag, kind+key))
        # 2) 超10
        calc = calc_cost(c.get("atk",0), c.get("hp",0), c.get("effects",[]))
        stored = c.get("cost",0)
        if stored > 10 or calc > 10:
            c_over10.append((tag, "存储%d/公式%d" % (stored, calc)))
        # 3) cost 不符
        if stored != calc:
            diff = stored - calc
            c_cost_mismatch.append((tag, stored, calc, diff))

# 按主题统计
for p in data:
    theme_stats[p.get("theme","?")] += len(p.get("pack_data",{}).get("cards",[]))

print("="*70)
print("【被注释纹路】(%d 张卡/%d 处)" % (len(set(x[0].split('[')[0] for x in c_commented)), len(c_commented)))
for tag, enum in c_commented:
    print("  ", tag, "→", enum)
print()
print("【能量超10】(%d 处)" % len(c_over10))
for tag, v in c_over10:
    print("  ", tag, "→", v)
print()
print("【cost与公式不符】(%d 处)" % len(c_cost_mismatch))
diff_1 = [x for x in c_cost_mismatch if abs(x[3])==1]
diff_big = [x for x in c_cost_mismatch if abs(x[3])>=2]
print("  ─ 差1（可能是有意取舍）:%d 处" % len(diff_1))
for tag, stored, calc, diff in diff_1[:25]:
    print("    %-58s 存储%d/公式%d%s" % (tag, stored, calc, "（偏低）" if diff>0 else "（偏高）"))
if len(diff_1)>25: print("    ... 其余 %d 处" % (len(diff_1)-25))
print("  ─ 差≥2（明显不符）:%d 处" % len(diff_big))
for tag, stored, calc, diff in diff_big:
    print("    %-58s 存储%d/公式%d %s" % (tag, stored, calc, "⚠️存储偏低(卡过强)" if diff>0 else "⚠️存储偏高(卡过弱)"))
print()
print("="*70)
print("按主题统计 | 问题分布")
from collections import defaultdict as dd
prob_theme = dd(lambda: Counter())
for tag, enum in c_commented: prob_theme[tag.split('/')[0]]["被注释纹路"]+=1
for tag, v in c_over10: prob_theme[tag.split('/')[0]]["超10"]+=1
for tag, stored, calc, diff in c_cost_mismatch: prob_theme[tag.split('/')[0]]["cost不符"]+=1
for t in sorted(prob_theme):
    print("  %-6s %s" % (t, dict(prob_theme[t])))