# -*- coding: utf-8 -*-
# 终极修复：全部用 override 覆盖 23 张卡，然后全量重算所有卡 cost
import json, re, math, sys, datetime, shutil
sys.path.insert(0, ".")
from fix_map import FIX

PACKS = "Data/local_card_packs.json"
GLOBAL = "Global.gd"

# ---------- 备份 ----------
ts = datetime.datetime.now().strftime("%Y%m%d%H%M%S")
bak = "Data/local_card_packs.backup_pre_fix_%s.json" % ts
shutil.copyfile(PACKS, bak)
print("备份:", bak)

# ---------- 解析纹路能量 ----------
gd = open(GLOBAL, encoding="utf-8").read()
def parse_circuit(var_name, id_pattern, energy_key=None, mod_key=None):
    m = re.search(r"var %s := \[(.*?)\n\]" % var_name, gd, re.S)
    out = {}
    if not m: return out
    for line in m.group(1).split("\n"):
        lm = re.search(r'"id":\s*"(%s)"' % id_pattern, line)
        if not lm: continue
        cid = lm.group(1)
        entry = {"commented": line.strip().startswith("#")}
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
C  = parse_circuit("circuit_conditions", r"C\d+", energy_key="base_energy")
def energy_of(cat, cid): return cat.get(cid, {}).get("energy", 0.0)
def avail(cat, cid):
    e = cat.get(cid); return e is not None and not e.get("commented", False)

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
        c_e = 0.0
        if e.get("condition"):
            ce = energy_of(C, e["condition"])
            if ce: c_e = -float(ce)
        if tr and ac:
            g = (tr_e + c_e + a_e) * t_mod
            if g > 0: circ += g
    return max(1, math.ceil(base + circ))

# ---------- 应用 override ----------
data = json.load(open(PACKS, encoding="utf-8"))
n_ov = 0
for p in data:
    for c in p.get("pack_data", {}).get("cards", []):
        fix = FIX.get(c.get("id"))
        if not fix: continue
        ov = fix["override"]
        if "atk" in ov: c["atk"] = ov["atk"]
        if "hp" in ov: c["hp"] = ov["hp"]
        if "effects" in ov: c["effects"] = [dict(e) for e in ov["effects"]]
        n_ov += 1
print("override 应用:", n_ov, "张卡")

# ---------- 全量重算 cost ----------
changed = 0
for p in data:
    for c in p.get("pack_data", {}).get("cards", []):
        nc = calc_cost(c.get("atk",0), c.get("hp",0), c.get("effects", []))
        if c.get("cost") != nc:
            changed += 1
            c["cost"] = nc
print("cost 重算变更:", changed, "张卡")

# ---------- 写入 ----------
with open(PACKS, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=1)
print("已写入")

# ---------- 统计合法 ----------
TR_OK = {'TR01','TR06','TR09','TR10','TR11','TR12','TR13','TR14','TR15','TR16','TR17','TR18'}
A_OK  = {'A01','A02','A03','A06','A07','A09','A20','A21','A23','A25','A31','A32','A33'}
T_OK  = {'T02','T03','T04','T05','T06','T10','T13','T14','T15','T16'}
bad = 0
over = 0
for p in data:
    for c in p.get("pack_data", {}).get("cards", []):
        for e in c.get("effects", []):
            if e.get("trigger") not in TR_OK: print("❌", c["id"], "trigger", e.get("trigger")); bad+=1
            if e.get("action") not in A_OK: print("❌", c["id"], "action", e.get("action")); bad+=1
            if e.get("target") not in T_OK: print("❌", c["id"], "target", e.get("target")); bad+=1
        if c.get("cost",0) > 10: print("❌", c["id"], "cost超10", c["cost"]); over+=1
        if c.get("cost",0) > 10: over += 1
print("非法纹路:", bad, "| 超10:", over)
print("✅ 全部合法" if bad==0 and over==0 else "⚠️ 仍有问题")