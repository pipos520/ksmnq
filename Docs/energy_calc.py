#!/usr/bin/env python3
"""严格按 CardEngraving.gd _calc_energy_cost 的能量计算公式"""
import math

# === Global.gd 组件表（base_energy / modifier / energy_adjust）===
TR = {  # 触发器 base_energy
    "TR01": 0.5, "TR06": 0.8, "TR09": 1.2, "TR10": 1.0, "TR11": 1.2,
    "TR12": 1.5, "TR13": 1.5, "TR14": 1.2, "TR15": 1.2,
    "TR16": 2.0, "TR17": 1.5, "TR18": 2.0,
}
C = {   # 条件 base_energy（注意：条件能量是负数减免）
    "C01": 0.3, "C02": 0.3, "C04": 0.3, "C06": 0.4, "C07": 0.3,
    "C08": 0.3, "C09": 0.3, "C10": 0.3, "C12": 0.3, "C16": 0.3,
}
# 动作 base_energy（数值型为"每点倍率"）
A_FIXED = {  # 固定能量
    "A03": 3.0, "A06": 3.0, "A07": 4.0, "A25": 2.5,
    "A31": 4.0, "A32": 6.0, "A33": 3.0,
}
A_MULT = {  # 每点数值能量倍率
    "A01": 0.8, "A02": 0.6, "A09": 1.5,
    "A20": 0.7, "A21": 0.5, "A23": 0.5,
}
T = {   # 目标倍率
    "T02": 1.0, "T03": 1.0, "T04": 1.8, "T05": 1.8, "T06": 2.2,
    "T10": 1.0, "T13": 1.0, "T14": 1.0, "T15": 1.0, "T16": 1.0,
}
CO_MULT = {  # 约束能量调整 = -X × 倍率
    "CO03": 0.2, "CO04": 0.8, "CO05": 0.5,
}

def effect_energy(tr=None, c=None, c_val=0, a=None, a_val=0, t=None, co=None, co_val=0):
    """单效果组能量 = (TR + C + A) × T倍率 + CO调整
    注意：C 能量为负（减免），CO 为负（减免）；A09 的数值是抽牌数"""
    if tr is None or a is None:
        return 0.0  # 无 TR 或无 A 不计能量
    e = TR[tr]
    if c:
        # 条件减免：数值型按 数值×base，字段型按 base
        if c in ("C02", "C04", "C07", "C08", "C09", "C12", "C16"):
            e -= c_val * C[c]
        else:
            e -= C[c]
    if a in A_FIXED:
        e += A_FIXED[a]
    else:
        e += a_val * A_MULT[a]
    e *= T.get(t, 1.0)
    if co:
        e -= co_val * CO_MULT[co]
    return max(0.0, e)

def card_cost(atk, hp, effects):
    """总能量 = floor((攻+命)/2) + Σ效果组能量，向上取整，最低1"""
    base = math.floor((atk + hp) / 2.0)
    circ = sum(effect_energy(**ef) for ef in effects)
    return max(1, math.ceil(base + circ))

def ef(tr, a, t, c=None, c_val=0, a_val=0, co=None, co_val=0):
    return dict(tr=tr, c=c, c_val=c_val, a=a, a_val=a_val, t=t, co=co, co_val=co_val)
