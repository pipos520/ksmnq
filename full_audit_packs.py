# -*- coding: utf-8 -*-
# 全量审计 local_card_packs.json：
# 1) 枚举是否使用被注释的纹路（从 Global.gd 实时解析）
# 2) 互斥规则检查（从 Global.gd circuit_mutex 解析）
# 3) 用 _calc_energy_cost 公式重算每张卡 cost，对比存储值
# 4) cost 是否超上限 10
import json, re, math, sys

GLOBAL = "Global.gd"
PACKS = "Data/local_card_packs.json"

gd = open(GLOBAL, encoding="utf-8").read()

def strip_comment(line):
    return line.strip().startswith("#")

def parse_circuit(var_name, id_pattern, energy_key=None, mod_key=None):
    """从 Global.gd 提取 var_name 数组里的组件：id -> {energy, commented}"""
    m = re.search(r"var %s := \[(.*?)\n\]" % var_name, gd, re.S)
    if not m:
        return {}
    body = m.group(1)
    out = {}
    # 按行扫描，找含 "id": "XXX" 的行
    for line in body.split("\n"):
        lm = re.search(r'"id":\s*"(%s)"' % id_pattern, line)
        if not lm:
            continue
        cid = lm.group(1)
        commented = strip_comment(line)
        entry = {"commented": commented}
        if energy_key:
            em = re.search(r'"%s":\s*"?([\d.]+|[^",}]+)"?' % energy_key, line)
            if em:
                v = em.group(1)
                try:
                    entry["energy"] = float(v)
                except ValueError:
                    entry["energy"] = v.strip()
        if mod_key:
            mm = re.search(r'"%s":\s*([\d.]+)' % mod_key, line)
            if mm:
                entry["mod"] = float(mm.group(1))
        out[cid] = entry
    return out

# 解析触发器 / 动作 / 目标 / 条件 / 约束
TR = parse_circuit("circuit_triggers", r"TR\d+", energy_key="base_energy")
A  = parse_circuit("circuit_actions", r"A\d+", energy_key="base_energy")
T  = parse_circuit("circuit_targets", r"T\d+", mod_key="modifier")
C  = parse_circuit("circuit_conditions", r"C\d+", energy_key="base_energy")
CO = parse_circuit("circuit_constraints", r"CO\d+", energy_key="energy_adjust")

def available(cat, cid):
    e = cat.get(cid)
    return e is not None and not e.get("commented", False)

def energy_of(cat, cid):
    e = cat.get(cid, {})
    return e.get("energy", 0.0)

# 解析互斥规则
def parse_mutex():
    m = re.search(r"var circuit_mutex := \{(.*?)\n\}", gd, re.S)
    if not m:
        return {"triggers": [], "actions": [], "targets": [], "action_target_pairs": []}
    body = m.group(1)
    res = {"triggers": [], "conditions": [], "actions": [], "targets": [], "action_target_pairs": []}
    for key in ["triggers", "conditions", "actions", "targets", "action_target_pairs"]:
        km = re.search(r'"%s":\s*\[(.*?)\]' % key, body, re.S)
        if not km:
            continue
        pairs = re.findall(r'\["([^"]+)",\s*"([^"]+)"\]', km.group(1))
        res[key] = pairs
    return res

MUTEX = parse_mutex()
MUTEX["action_target_pairs"] = [tuple(p) for p in MUTEX.get("action_target_pairs", [])]

# 计算单张卡的能量 cost（复刻 CardEngraving._calc_energy_cost，未含 C/CO 参数默认 0）
def calc_cost(atk, hp, effects):
    base = math.floor((atk + hp) / 2.0)
    circ = 0.0
    for e in effects:
        tr = e.get("trigger", "")
        ac = e.get("action", "")
        tg = e.get("target", "")
        val = e.get("value", 1)
        tr_e = energy_of(TR, tr) if tr else 0.0
        a_raw = energy_of(A, ac) if ac else 0.0
        if isinstance(a_raw, str):
            # 形如 "数值×0.8"
            mm = re.match(r"数值×([\d.]+)", a_raw)
            a_e = float(val) * float(mm.group(1)) if mm else 0.0
        else:
            a_e = float(a_raw) if a_raw else 0.0
        t_mod = T.get(tg, {}).get("mod", 1.0) if tg else 1.0
        if tr and ac:
            g = (tr_e + a_e) * t_mod
            if g > 0:
                circ += g
    return max(1, math.ceil(base + circ))

# 检查互斥
def mutex_check(card):
    issues = []
    effs = card.get("effects", [])
    trs = [e.get("trigger") for e in effs if e.get("trigger")]
    acts = [e.get("action") for e in effs if e.get("action")]
    tgs = [e.get("target") for e in effs if e.get("target")]
    for key, lst in [("triggers", trs), ("actions", acts), ("targets", tgs)]:
        for pair in MUTEX.get(key, []):
            a1, a2 = pair
            if a1 in lst and a2 in lst:
                issues.append("互斥:%s×%s" % (a1, a2))
    for e in effs:
        ac = e.get("action")
        tg = e.get("target")
        if (ac, tg) in MUTEX.get("action_target_pairs", []):
            issues.append("动作×目标互斥:%s/%s" % (ac, tg))
    return issues

# 主审计
data = json.load(open(PACKS, encoding="utf-8"))
print("总卡包: %d | 开始全量审计\n" % len(data))

all_probs = []
for p in data:
    pid = p.get("pack_id", "?")
    theme = p.get("theme", "?")
    pd = p.get("pack_data", {})
    cards = pd.get("cards", [])
    p_probs = []
    for c in cards:
        cid = c.get("id", "?")
        name = c.get("name", "?")
        atk, hp, cost = c.get("atk", 0), c.get("hp", 0), c.get("cost", 0)
        effs = c.get("effects", [])
        # 1) 枚举可用性
        for e in effs:
            tr, ac, tg = e.get("trigger"), e.get("action"), e.get("target")
            if tr and not available(TR, tr):
                p_probs.append("%s[%s]: 使用被注释触发器 %s" % (name, cid, tr))
            if ac and not available(A, ac):
                p_probs.append("%s[%s]: 使用被注释动作 %s" % (name, cid, ac))
            if tg and not available(T, tg):
                p_probs.append("%s[%s]: 使用被注释目标 %s" % (name, cid, tg))
        # 2) 互斥
        for issue in mutex_check(c):
            p_probs.append("%s[%s]: %s" % (name, cid, issue))
        # 3) 能量重算
        calc = calc_cost(atk, hp, effs)
        if calc != cost:
            p_probs.append("%s[%s]: cost存储=%d 公式重算=%d %s" % (
                name, cid, cost, calc, "⚠️差1取舍?" if abs(calc-cost)<=1 else ""))
        # 4) 超上限
        if cost > 10:
            p_probs.append("%s[%s]: cost=%d 超上限10!" % (name, cid, cost))
        if calc > 10:
            p_probs.append("%s[%s]: 公式能量=%d 超上限10!" % (name, cid, calc))
    if p_probs:
        all_probs.append((theme, pid, pd.get("name", "?"), p_probs))

# 输出
n_bad_packs = len(all_probs)
n_bad_cards = sum(len(x[3]) for x in all_probs)
for theme, pid, pname, probs in all_probs:
    print("【%s】%s (%s) 问题 %d 条:" % (theme, pname, pid, len(probs)))
    for pr in probs:
        print("    ", pr)
print("\n=== 汇总 ===")
print("问题卡包: %d/%d | 问题条目: %d" % (n_bad_packs, len(data), n_bad_cards))
if n_bad_packs == 0:
    print("✅ 全部卡包无问题：无注释纹路、无互斥、能量全部正确、无超上限")