# -*- coding: utf-8 -*-
# 修复映射 FINAL：全部用完整 override（action/target/value 一次写死），避免 swap 匹配错误
FIX = {
    # ===== A28 -> A33 禁用效果一回合（单体） =====
    "CARD_TYF_010": {"override": {"atk": 0, "hp": 0, "effects": [{"trigger": "TR01", "action": "A33", "target": "T02", "value": 1, "desc": "召唤成功时：禁用敌方单体效果一回合"}]}},
    "CARD_TYF_011": {"override": {"atk": 3, "hp": 4, "effects": [{"trigger": "TR01", "action": "A33", "target": "T02", "value": 1, "desc": "召唤成功时：禁用敌方单体效果一回合"}]}},
    "CARD_TYF_013": {"override": {"atk": 0, "hp": 0, "effects": [{"trigger": "TR01", "action": "A01", "target": "T02", "value": 2, "desc": "召唤成功时：对敌方单体造成2点伤害"}, {"trigger": "TR01", "action": "A33", "target": "T02", "value": 1, "desc": "召唤成功时：禁用敌方单体效果一回合"}]}},
    "CARD_TYF_016": {"override": {"atk": 0, "hp": 0, "effects": [{"trigger": "TR01", "action": "A01", "target": "T02", "value": 3, "desc": "召唤成功时：对敌方单体造成3点伤害"}, {"trigger": "TR01", "action": "A33", "target": "T02", "value": 1, "desc": "召唤成功时：禁用敌方单体效果一回合"}]}},
    "CARD_SYY_010": {"override": {"atk": 0, "hp": 0, "effects": [{"trigger": "TR01", "action": "A33", "target": "T02", "value": 1, "desc": "召唤成功时：禁用敌方单体效果一回合"}]}},
    "CARD_NJZ_009": {"override": {"atk": 0, "hp": 0, "effects": [{"trigger": "TR01", "action": "A01", "target": "T02", "value": 1, "desc": "召唤成功时：对敌方单体造成1点伤害"}, {"trigger": "TR01", "action": "A33", "target": "T02", "value": 1, "desc": "召唤成功时：禁用敌方单体效果一回合"}]}},
    "CARD_NJZ_014": {"override": {"atk": 0, "hp": 0, "effects": [{"trigger": "TR01", "action": "A01", "target": "T02", "value": 2, "desc": "召唤成功时：对敌方单体造成2点伤害"}, {"trigger": "TR01", "action": "A33", "target": "T02", "value": 1, "desc": "召唤成功时：禁用敌方单体效果一回合"}]}},
    "CARD_QYJ_011": {"override": {"atk": 0, "hp": 0, "effects": [{"trigger": "TR12", "action": "A33", "target": "T02", "value": 1, "desc": "己方回合开始时：禁用敌方单体效果一回合"}]}},
    "CARD_QYJ_012": {"override": {"atk": 2, "hp": 3, "effects": [{"trigger": "TR16", "action": "A33", "target": "T02", "value": 1, "desc": "对方发动效果时：禁用敌方单体效果一回合"}]}},
    "CARD_WMW_007": {"override": {"atk": 2, "hp": 2, "effects": [{"trigger": "TR01", "action": "A33", "target": "T02", "value": 1, "desc": "召唤成功时：禁用敌方单体效果一回合"}]}},
    "CARD_WMW_011": {"override": {"atk": 2, "hp": 3, "effects": [{"trigger": "TR10", "action": "A33", "target": "T02", "value": 1, "desc": "被攻击时：禁用敌方单体效果一回合"}]}},
    # ===== A16 -> A09 抽牌 =====
    "CARD_HJK_013": {"override": {"atk": 0, "hp": 0, "effects": [{"trigger": "TR01", "action": "A09", "target": "T03", "value": 1, "desc": "召唤成功时：抽1张牌（轮回引渡）"}]}},
    "CARD_HJK_016": {"override": {"atk": 0, "hp": 0, "effects": [{"trigger": "TR01", "action": "A09", "target": "T03", "value": 2, "desc": "召唤成功时：抽2张牌（轮回转世）"}]}},
    "CARD_DLG_016": {"override": {"atk": 0, "hp": 0, "effects": [{"trigger": "TR06", "action": "A09", "target": "T03", "value": 1, "desc": "被送去墓地时：抽1张牌（鲸落万物生）"}, {"trigger": "TR06", "action": "A20", "target": "T05", "value": 1, "desc": "被送去墓地时：己方全体+1攻击"}]}},
    "CARD_WMW_016": {"override": {"atk": 3, "hp": 4, "effects": [{"trigger": "TR01", "action": "A09", "target": "T03", "value": 1, "desc": "召唤成功时：抽1张牌（无名归来）"}]}},
    # ===== 超10 override（身材/效果已校准 <=10） =====
    "CARD_QP_065": {"override": {"atk": 3, "hp": 3, "effects": [{"trigger": "TR01", "action": "A32", "target": "T13", "value": 1, "desc": "召唤成功时：永久夺取对方攻击最高卡牌的控制权（需控制权异动卡数≥1）"}]}},
    "CARD_QP_066": {"override": {"atk": 3, "hp": 3, "effects": [{"trigger": "TR18", "action": "A31", "target": "T02", "value": 1, "desc": "控制权转移时：夺取敌方单体卡牌的控制权一回合"}]}},
    "CARD_DYZ_012": {"override": {"atk": 3, "hp": 3, "effects": [{"trigger": "TR01", "action": "A33", "target": "T04", "value": 1, "desc": "召唤成功时：禁用敌方全体效果一回合"}]}},
    "CARD_SYJ_015": {"override": {"atk": 4, "hp": 4, "effects": [{"trigger": "TR01", "action": "A01", "target": "T02", "value": 3, "desc": "召唤成功时：对敌方单体造成3点伤害"}, {"trigger": "TR01", "action": "A20", "target": "T05", "value": 1, "desc": "召唤成功时：己方全体+1攻击"}]}},
    "CARD_HJX_015": {"override": {"atk": 4, "hp": 4, "effects": [{"trigger": "TR10", "action": "A02", "target": "T03", "value": 2, "desc": "被攻击时：为己方单体恢复2点生命"}, {"trigger": "TR10", "action": "A21", "target": "T03", "value": 3, "desc": "被攻击时：己方单体+3生命"}]}},
    "CARD_SYLJ_018": {"override": {"atk": 4, "hp": 5, "effects": [{"trigger": "TR12", "action": "A20", "target": "T05", "value": 2, "desc": "己方回合开始时：+2攻击（己方全体）"}]}},
    "CARD_SYHS_018": {"override": {"atk": 4, "hp": 5, "effects": [{"trigger": "TR12", "action": "A20", "target": "T05", "value": 2, "desc": "己方回合开始时：+2攻击（己方全体）"}]}},
    "CARD_SYSD_018": {"override": {"atk": 4, "hp": 5, "effects": [{"trigger": "TR12", "action": "A20", "target": "T05", "value": 2, "desc": "己方回合开始时：+2攻击（己方全体）"}]}},
}
print("FIX FINAL 映射:", len(FIX), "张卡")