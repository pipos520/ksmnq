extends Node

## ============================================================
##  CircuitDatabase — 纹路组件数据 + 解析/评估引擎 + 行池（Autoload）
##  包含约 90 个纹路组件（TR/C/A/T/CO）的定义和所有相关逻辑
## ============================================================

# ===== 触发器（17个）=====
var circuit_triggers := [
	{"id": "TR01", "name": "召唤成功时", "speed": 1, "once_only": true, "base_energy": 0.5, "base_load": 0.4,
		"desc": "卡牌从手牌打出到场上时触发。只触发被召唤的卡牌自身，不扫描全场。速度1，可被速度2效果连锁响应。仅触发一次。"},
	{"id": "TR06", "name": "被送去墓地时", "speed": 1, "once_only": false, "base_energy": 0.8, "base_load": 0.6,
		"desc": "卡牌从场上被送入墓地时触发。只触发被送墓的卡牌自身，不扫描全场。速度1，可被速度2效果连锁响应。每次送墓都会触发。"},
	{"id": "TR09", "name": "攻击宣言时", "speed": 1, "once_only": false, "base_energy": 1.2, "base_load": 1.0,
		"desc": "己方卡牌宣告攻击时、在攻击执行前触发。只触发攻击卡自身，不扫描全场。无论攻击卡牌还是攻击英雄都会触发。速度1，可被速度2效果连锁响应。"},
	{"id": "TR10", "name": "被攻击时", "speed": 1, "once_only": false, "base_energy": 1.0, "base_load": 0.8,
		"desc": "己方卡牌被选为攻击目标时、在攻击执行前触发。只触发被攻击的卡牌自身，不扫描全场。速度1，可被速度2效果连锁响应。"},
	{"id": "TR11", "name": "给予战斗伤害时", "speed": 1, "once_only": false, "base_energy": 1.2, "base_load": 1.0,
		"desc": "己方卡牌攻击造成伤害后触发。只触发攻击卡自身，不扫描全场。攻击卡牌需对防御方造成伤害，攻击英雄需对英雄造成伤害。速度1，可被速度2效果连锁响应。"},
	{"id": "TR12", "name": "己方回合开始时", "speed": 1, "once_only": false, "base_energy": 1.5, "base_load": 1.2,
		"desc": "己方回合的准备阶段开始时触发。扫描己方场上所有存活卡牌。速度1，可被速度2效果连锁响应。"},
	{"id": "TR13", "name": "对方回合开始时", "speed": 1, "once_only": false, "base_energy": 1.5, "base_load": 1.2,
		"desc": "对方回合的准备阶段开始时触发。扫描对方场上所有存活卡牌。速度1，可被速度2效果连锁响应。"},
	{"id": "TR14", "name": "己方回合结束时", "speed": 1, "once_only": false, "base_energy": 1.2, "base_load": 1.0,
		"desc": "己方回合的结束阶段触发。扫描己方场上所有存活卡牌。速度1，可被速度2效果连锁响应。"},
	{"id": "TR15", "name": "对方回合结束时", "speed": 1, "once_only": false, "base_energy": 1.2, "base_load": 1.0,
		"desc": "对方回合的结束阶段触发。扫描对方场上所有存活卡牌。速度1，可被速度2效果连锁响应。"},
	{"id": "TR16", "name": "对方发动效果时", "speed": 2, "once_only": false, "base_energy": 2.0, "base_load": 1.6,
		"desc": "对方发动效果（包括召唤时、攻击时、送墓时等）时触发，可连锁响应。扫描对方场上所有存活卡牌。速度2，可连锁速度1效果。"},
	{"id": "TR17", "name": "对方召唤成功时", "speed": 2, "once_only": false, "base_energy": 1.5, "base_load": 1.2,
		"desc": "对方成功召唤卡牌到场上时触发。扫描对方场上所有存活卡牌。速度2，可连锁速度1效果。"},
	{"id": "TR18", "name": "控制权转移时", "speed": 2, "once_only": false, "base_energy": 2.0, "base_load": 1.6,
		"desc": "场上任意卡牌控制权变更（夺取/归还/交换）时触发。扫描全场卡牌。速度2，可连锁速度1效果。"},
]

# ===== 条件（12个）=====
var circuit_conditions := [
	{"id": "C01", "name": "场上存在指定字段", "params": "字段名", "base_energy": 0.3, "base_load": 1.5},
	{"id": "C02", "name": "场上怪兽数量", "params": "比较符+数值", "base_energy": 0.3, "base_load": 1.0},
	{"id": "C04", "name": "生命值比较", "params": "比较符+数值", "base_energy": 0.3, "base_load": 1.0},
	{"id": "C06", "name": "生命值差", "params": "数值", "base_energy": 0.4, "base_load": 1.2},
	{"id": "C07", "name": "手牌数", "params": "比较符+数值", "base_energy": 0.3, "base_load": 1.0},
	{"id": "C08", "name": "能量点", "params": "数值", "base_energy": 0.3, "base_load": 1.0},
	{"id": "C09", "name": "墓地卡牌数量", "params": "比较符+数值", "base_energy": 0.3, "base_load": 1.2},
	{"id": "C10", "name": "墓地存在字段卡", "params": "字段名", "base_energy": 0.3, "base_load": 1.5},
	{"id": "C12", "name": "卡组数量", "params": "比较符+数值", "base_energy": 0.3, "base_load": 1.2},
	{"id": "C16", "name": "控制权异动卡数量", "params": "比较符+数值", "base_energy": 0.3, "base_load": 1.2},
]

# ===== 动作（30个）=====
var circuit_actions := [
	{"id": "A01", "name": "效果伤害", "base_energy": "数值×0.8", "default_element": "火", "base_load": 1.8},
	{"id": "A02", "name": "恢复生命", "base_energy": "数值×0.6", "default_element": "水", "base_load": 1.5},
	{"id": "A03", "name": "破坏", "base_energy": 3.0, "default_element": "无", "base_load": 9.0},
	{"id": "A06", "name": "弹回手牌", "base_energy": 3.0, "default_element": "风", "base_load": 6.0},
	{"id": "A07", "name": "弹回卡组", "base_energy": 4.0, "default_element": "风", "base_load": 9.5},
	{"id": "A09", "name": "抽牌", "base_energy": "数值×1.5", "default_element": "风", "base_load": 2.5},
	{"id": "A20", "name": "攻击力增减(永久)", "base_energy": "数值×0.7", "default_element": "无", "base_load": 1.5},
	{"id": "A21", "name": "生命值增减(永久)", "base_energy": "数值×0.5", "default_element": "水", "base_load": 1.2},
	{"id": "A23", "name": "回合内攻命增减", "base_energy": "数值×0.5", "default_element": "无", "base_load": 1.0},
	{"id": "A25", "name": "交换攻防", "base_energy": 2.5, "default_element": "无", "base_load": 3.0},
	{"id": "A31", "name": "控制权变更·一回合", "base_energy": 4.0, "default_element": "暗", "base_load": 11.0},
	{"id": "A32", "name": "控制权变更·永久", "base_energy": 6.0, "default_element": "暗", "base_load": 13.0},
	{"id": "A33", "name": "禁用效果（一回合）", "base_energy": 3.0, "default_element": "光", "base_load": 6.0},
]

# ===== 目标（12个）=====
var circuit_targets := [
	{"id": "T02", "name": "敌方单体", "modifier": 1.0, "base_load": 0.5},
	{"id": "T03", "name": "己方单体", "modifier": 1.0, "base_load": 0.3},
	{"id": "T04", "name": "敌方全体", "modifier": 1.8, "base_load": 4.0},
	{"id": "T05", "name": "己方全体", "modifier": 1.8, "base_load": 3.0},
	{"id": "T06", "name": "全场", "modifier": 2.2, "base_load": 5.0},
	{"id": "T10", "name": "墓地", "modifier": 1.0, "base_load": 0.6},
	{"id": "T13", "name": "对方攻击最高", "modifier": 1.0, "base_load": 0.8},
	{"id": "T14", "name": "对方攻击最低", "modifier": 1.0, "base_load": 0.8},
	{"id": "T15", "name": "我方攻击最高", "modifier": 1.0, "base_load": 0.8},
	{"id": "T16", "name": "我方攻击最低", "modifier": 1.0, "base_load": 0.8},
]

# ===== 约束（16个）=====
var circuit_constraints := [
	{"id": "CO03", "name": "支付生命", "energy_adjust": "-X×0.2", "base_load": 0.8},
	{"id": "CO04", "name": "舍弃手牌", "energy_adjust": "-X×0.8", "base_load": 1.0},
	{"id": "CO05", "name": "消耗能量点", "energy_adjust": "-X×0.5", "base_load": 0.5},
]

# ===== 互斥规则 =====
var circuit_mutex := {
	"triggers": [["TR09", "TR10"],["TR12", "TR13"], ["TR14", "TR15"]],
	"conditions": [["C02", "C04"]],
	"actions": [["A06", "A07"]],
	"targets": [["T04", "T06"]],
	"constraints": [],
	"action_target_pairs": [
		["A20", "T10"], ["A21", "T10"], ["A23", "T10"], ["A25", "T10"],
		["A31", "T10"], ["A32", "T10"], ["A33", "T10"], ["A09", "T10"],
	]
}

var _circuit_map: Dictionary = {}

## 初始解锁组件
var initial_unlocked := ["TR01", "A01", "T02"]

## 解锁路径（已废弃，改用公会等级系统）
var unlock_paths := [{"condition": "首次制卡", "guild_level": 1, "unlock": ["C07", "A20", "T03"]},{"condition": "制作3张卡", "guild_level": 2, "unlock": ["C01", "A02", "A09"]},{"condition": "制作10张卡", "guild_level": 3, "unlock": ["TR12", "C02", "CO04", "C12"]},{"condition": "制作20张卡", "guild_level": 4, "unlock": ["TR14", "TR15", "C04", "A21"]},{"condition": "首张卓越品质", "guild_level": 4, "unlock": ["C10"]},{"condition": "首张完美品质", "guild_level": 6, "unlock": ["TR16"]},{"condition": "累计造成500点伤害", "guild_level": 4, "unlock": ["TR09", "TR11", "A03"]},{"condition": "累计恢复500点生命", "guild_level": 4, "unlock": ["C06", "A23", "T04"]},{"condition": "累计消耗100点能量", "guild_level": 3, "unlock": ["C08", "CO05"]},{"condition": "累计特召30次", "guild_level": 4, "unlock": ["TR06", "TR18"]},{"condition": "累计破坏20张卡", "guild_level": 4, "unlock": ["A07", "T06", "A33"]},{"condition": "通关迷雾森林", "guild_level": 5, "unlock": ["C04", "A06", "CO03", "TR10"]},{"condition": "通关火焰洞穴", "guild_level": 7, "unlock": ["TR06", "C09", "T10", "A25"]},{"condition": "完成5次公会任务", "guild_level": 3, "unlock": ["T13", "T14"]},{"condition": "完成20次公会任务", "guild_level": 5, "unlock": ["T15", "T16", "A31", "A32"]},{"condition": "通关暗影沼泽", "guild_level": 9, "unlock": ["T05"]},{"condition": "通关传说遗迹", "guild_level": 10, "unlock": ["TR17"]},{"condition": "卡牌图鉴收集50张", "guild_level": 5, "unlock": ["TR13", "C04", "C16"]},]

# ===== 触发类型枚举 =====
enum TRIGGER_TYPE {
	NONE, ON_SUMMON, ON_SPECIAL_SUMMON, ON_BATTLE_DESTROY,
	ON_GRAVE, ON_ATTACK, ON_ATTACKED, ON_DAMAGE,
	ON_TURN_START, ON_TURN_END, ON_EFFECT, ON_SUMMON_ENEMY
}

static func trigger_to_type(trigger_id: String) -> TRIGGER_TYPE:
	match trigger_id:
		"TR01": return TRIGGER_TYPE.ON_SUMMON
		"TR02": return TRIGGER_TYPE.ON_SPECIAL_SUMMON
		"TR03": return TRIGGER_TYPE.ON_SPECIAL_SUMMON
		"TR04": return TRIGGER_TYPE.ON_BATTLE_DESTROY
		"TR06": return TRIGGER_TYPE.ON_GRAVE
		"TR09": return TRIGGER_TYPE.ON_ATTACK
		"TR10": return TRIGGER_TYPE.ON_ATTACKED
		"TR11": return TRIGGER_TYPE.ON_DAMAGE
		"TR12": return TRIGGER_TYPE.ON_TURN_START
		"TR13": return TRIGGER_TYPE.ON_TURN_START
		"TR14": return TRIGGER_TYPE.ON_TURN_END
		"TR15": return TRIGGER_TYPE.ON_TURN_END
		"TR16": return TRIGGER_TYPE.ON_EFFECT
		"TR17": return TRIGGER_TYPE.ON_SUMMON_ENEMY
	return TRIGGER_TYPE.NONE


func _ready() -> void:
	_build_circuit_map()
	_build_circuit_row_template()


func _build_circuit_map() -> void:
	_circuit_map.clear()
	for item in circuit_triggers:
		_circuit_map[item["id"]] = item
	for item in circuit_conditions:
		_circuit_map[item["id"]] = item
	for item in circuit_actions:
		_circuit_map[item["id"]] = item
	for item in circuit_targets:
		_circuit_map[item["id"]] = item
	for item in circuit_constraints:
		_circuit_map[item["id"]] = item
	print("[CircuitDB] 纹路组件加载完成：共 ", _circuit_map.size(), " 个组件")
	print("[CircuitDB] 初始解锁：", initial_unlocked.size(), " 个组件")
	print("[CircuitDB] 解锁路径：", unlock_paths.size(), " 条")


# ============================================================
#  组件查询
# ============================================================

func get_all_triggers() -> Array: return circuit_triggers
func get_all_conditions() -> Array: return circuit_conditions
func get_all_actions() -> Array: return circuit_actions
func get_all_targets() -> Array: return circuit_targets
func get_all_constraints() -> Array: return circuit_constraints

func get_circuit_by_id(id: String) -> Dictionary:
	return _circuit_map.get(id, {})

func get_mutex_by_category(cat: String) -> Array:
	return circuit_mutex.get(cat, [])

func is_action_target_mutex(action_id: String, target_id: String) -> bool:
	var pairs = circuit_mutex.get("action_target_pairs", [])
	for pair in pairs:
		if pair.size() >= 2 and pair[0] == action_id and pair[1] == target_id:
			return true
	return false

func get_initial_unlocked() -> Array:
	return initial_unlocked.duplicate()

func get_unlock_paths() -> Array:
	return unlock_paths.duplicate()

func get_target_modifier(target_id: String) -> float:
	var target_info = _circuit_map.get(target_id, {})
	return target_info.get("modifier", 1.0)

func can_chain(trigger_id: String, current_chain_speed: int) -> bool:
	var trigger_info = _circuit_map.get(trigger_id, {})
	var speed = trigger_info.get("speed", 1)
	return speed >= current_chain_speed


# ============================================================
#  效果描述生成
# ============================================================

## 从效果字典生成可读描述（兼容旧格式）
func get_effect_desc(eff: Dictionary) -> String:
	var eff_name = eff.get("name", "")
	if eff_name != "":
		eff_name = "【" + eff_name + "】"
	var trigger_id = eff.get("trigger", "")
	var action_id = eff.get("action", "")
	var target_id = eff.get("target", "T01")
	var value = eff.get("value", 0)
	var trigger_name = trigger_id
	var t_data = _circuit_map.get(trigger_id, {})
	if t_data.has("name"): trigger_name = t_data["name"]
	var action_name = action_id
	var a_data = _circuit_map.get(action_id, {})
	if a_data.has("name"): action_name = a_data["name"]
	var target_name = target_id
	var tar_data = _circuit_map.get(target_id, {})
	if tar_data.has("name"): target_name = tar_data["name"]
	var target_pre = ""
	match target_name:
		"全场": target_pre = "对所有单位"
		"敌方单体": target_pre = "敌方单体"
		"己方单体": target_pre = "己方单体"
		"自身": target_pre = "自身"
		"敌方全体": target_pre = "敌方全体"
		"己方全体": target_pre = "己方全体"
		"墓地": target_pre = "墓地"
		_: target_pre = target_name
	var parts := []
	if trigger_name == "召唤成功时":
		parts.append("入场：")
	elif trigger_name != "":
		parts.append(trigger_name + "，")
	var conds = eff.get("conditions", [])
	if conds is Array and conds.size() > 0:
		var cond_strs := []
		for cond in conds:
			if not (cond is Dictionary): continue
			var cond_id = cond.get("id", "")
			var cond_name = cond_id
			var c_data = _circuit_map.get(cond_id, {})
			if c_data.has("name"): cond_name = c_data["name"]
			var param_str = ""
			var param_type = c_data.get("params", "无")
			if param_type == "字段名":
				var field_val = cond.get("字段名", cond.get("field", ""))
				if field_val != "": param_str = "「" + field_val + "」"
			elif param_type == "比较符+数值":
				var comp = cond.get("compare", cond.get("comparison", "≥"))
				var val = cond.get("value", cond.get("数值", 0))
				param_str = " " + comp + " " + str(val)
			elif param_type == "数值":
				var val = cond.get("value", cond.get("数值", 0))
				param_str = " " + str(val)
			if param_str != "": cond_strs.append(cond_name + param_str)
			else: cond_strs.append(cond_name)
		if cond_strs.size() > 0:
			parts.append("（" + "、".join(cond_strs) + "）")
	match action_name:
		"效果伤害": parts.append("对" + target_pre + "造成" + str(value) + "点伤害")
		"恢复生命": parts.append("恢复" + target_pre + str(value) + "点生命")
		"抽牌": parts.append("抽牌" + str(value) + "张")
		"破坏": parts.append("破坏" + target_pre)
		"攻击力增减(永久)": parts.append("攻击力" + ("+" if value >= 0 else "") + str(value))
		"生命值增减(永久)": parts.append("生命值" + ("+" if value >= 0 else "") + str(value))
		"回合内攻命增减": parts.append("本回合攻命" + ("+" if value >= 0 else "") + str(value))
		"弹回手牌": parts.append("将" + target_pre + "弹回手牌")
		"弹回卡组": parts.append("将" + target_pre + "弹回卡组")
		"交换攻防": parts.append("交换攻击力与生命值")
		"手牌特召": parts.append("从手牌特殊召唤")
		"墓地特召": parts.append("从墓地特殊召唤")
		"卡组特召": parts.append("从卡组特殊召唤")
		_:
			parts.append(action_name)
			if target_name != "自身": parts.append("(" + target_name + ")")
			if value != 0: parts.append(" 数值:" + str(value))
	var cons = eff.get("constraints", [])
	if cons is Array and cons.size() > 0:
		var co_strs := []
		for co_id in cons:
			match co_id:
				"CO03": co_strs.append("支付生命×" + str(get_constraint_param(eff, "CO03", 10)))
				"CO04": co_strs.append("舍弃手牌×" + str(get_constraint_param(eff, "CO04", 1)))
				"CO12": co_strs.append("发动后受伤害×" + str(get_constraint_param(eff, "CO12", 5)))
				"CO05":
					var co_val = get_constraint_param(eff, "CO05", 500)
					co_strs.append("需能量≥" + str(co_val))
				_: co_strs.append(co_id)
		if co_strs.size() > 0:
			parts.append("（" + "、".join(co_strs) + "）")
	if parts.size() > 0:
		return eff_name + "".join(parts)
	if eff.has("desc") and eff.get("desc", "") != "":
		return eff_name + eff.get("desc", "")
	return eff_name


## 格式化效果描述（用于飘窗显示）
func format_effect_description(parsed_effect: Dictionary) -> String:
	var trigger = parsed_effect.get("trigger", "")
	var action = parsed_effect.get("action", "")
	var target = parsed_effect.get("target", "")
	var value = parsed_effect.get("value", 0)
	var field = parsed_effect.get("field", "")
	var conditions = parsed_effect.get("conditions", [])
	var constraints = parsed_effect.get("constraints", [])
	var trigger_text = ""
	match trigger:
		"TR01": trigger_text = "召唤时"
		"TR02": trigger_text = "特殊召唤时"
		"TR03": trigger_text = "从墓地特召时"
		"TR04": trigger_text = "被战斗破坏时"
		"TR06": trigger_text = "送墓时"
		"TR07": trigger_text = "被除外时"
		"TR08": trigger_text = "离场时"
		"TR09": trigger_text = "攻击时"
		"TR10": trigger_text = "被攻击时"
		"TR11": trigger_text = "战斗伤害时"
		"TR12": trigger_text = "己方回合开始"
		"TR13": trigger_text = "对方回合开始"
		"TR14": trigger_text = "己方回合结束"
		"TR15": trigger_text = "对方回合结束"
		"TR16": trigger_text = "对方发动效果时"
		"TR17": trigger_text = "对方召唤时"
		_: trigger_text = trigger
	var action_text = ""
	match action:
		"A01": action_text = "造成" + str(value) + "点伤害"
		"A02": action_text = "恢复" + str(value) + "点生命"
		"A03": action_text = "破坏"
		"A04": action_text = "除外"
		"A05": action_text = "从墓地除外"
		"A06": action_text = "弹回手牌"
		"A07": action_text = "弹回卡组"
		"A08": action_text = "送入墓地"
		"A09": action_text = "从牌库抽" + str(value) + "张牌"
		"A10": action_text = "从卡组检索1张" + field + "字段卡"
		"A11": action_text = "从卡组检索1张卡"
		"A12": action_text = "从墓地回收1张卡"
		"A13": action_text = "从除外区回收1张卡"
		"A14": action_text = "从卡组送" + str(value) + "张牌入墓地"
		"A15": action_text = "从手牌特殊召唤"
		"A16": action_text = "从墓地特殊召唤"
		"A17": action_text = "从卡组特殊召唤"
		"A18": action_text = "从除外区特殊召唤"
		"A19": action_text = "召唤衍生物"
		"A20":
			if value >= 0: action_text = "攻击力+" + str(value)
			else: action_text = "攻击力" + str(value)
		"A21":
			if value >= 0: action_text = "生命值+" + str(value)
			else: action_text = "生命值" + str(value)
		"A22": action_text = "攻命各+" + str(value)
		"A23":
			if value >= 0: action_text = "本回合攻命+" + str(value)
			else: action_text = "本回合攻命" + str(value)
		"A24": action_text = "全场攻命+" + str(value)
		"A25": action_text = "交换攻防"
		"A26": action_text = "暂时夺取控制权"
		"A27": action_text = "永久夺取控制权"
		"A28": action_text = "无法攻击"
		"A29": action_text = "变更表示形式"
		"A30": action_text = "无效效果并破坏"
		"A31": action_text = "夺取控制权（一回合）"
		"A32": action_text = "夺取控制权（永久）"
		"A33": action_text = "禁用效果（一回合）"
		_: action_text = action
	var target_text = ""
	match target:
		"T01": target_text = "自身"
		"T02": target_text = "敌方单体"
		"T03": target_text = "己方单体"
		"T04": target_text = "敌方全体"
		"T05": target_text = "己方全体"
		"T06": target_text = "全场"
		"T07": target_text = "敌方英雄"
		"T08": target_text = "己方英雄"
		"T09": target_text = "手牌"
		"T10": target_text = "墓地"
		"T11": target_text = "卡组"
		"T12": target_text = "除外区"
		"T13": target_text = "敌方攻击最高"
		"T14": target_text = "敌方攻击最低"
		"T15": target_text = "己方攻击最高"
		"T16": target_text = "己方攻击最低"
		_: target_text = target
	var prefix = ""
	for cond in conditions:
		var cid = cond.get("id", "")
		var cp = cond.get("param", cond.get("value", cond.get("数值", 0)))
		var cf = cond.get("字段名", cond.get("field", ""))
		var cc = cond.get("comparison", cond.get("compare", "≥"))
		match cid:
			"C01": prefix += "【场上需有「" + cf + "」】"
			"C02": prefix += "【场上怪兽" + cc + str(cp) + "】"
			"C04": prefix += "【生命" + cc + str(cp) + "】"
			"C06": prefix += "【生命差≥" + str(cp) + "】"
			"C07": prefix += "【手牌" + cc + str(cp) + "】"
			"C08": prefix += "【能量≥" + str(cp) + "】"
			"C09": prefix += "【墓地" + cc + str(cp) + "】"
			"C10": prefix += "【墓地需有「" + cf + "」】"
			"C12": prefix += "【卡组" + cc + str(cp) + "】"
	for cns in constraints:
		match cns:
			"CO03": prefix += "【支付生命】"
			"CO04": prefix += "【舍弃手牌】"
			"CO01": prefix += "【一回合一次】"
			"CO02": prefix += "【一局一次】"
	var eff_name = parsed_effect.get("name", "")
	var name_prefix = "【" + eff_name + "】" if eff_name != "" else ""
	if target == "T01":
		return name_prefix + prefix + trigger_text + "，" + action_text
	else:
		return name_prefix + prefix + trigger_text + "，对" + target_text + action_text


# ============================================================
#  效果解析与评估
# ============================================================

## 解析纹路效果（新格式：TR+C+A+T+CO 或旧格式兼容）
static func parse_circuit(effect_data: Dictionary) -> Dictionary:
	var result = {
		"trigger": "", "conditions": [], "action": "", "target": "",
		"constraints": [], "value": 0, "field": "", "is_valid": false,
		"raw_data": effect_data
	}
	if effect_data.has("trigger") and effect_data.has("action"):
		result.trigger = effect_data.get("trigger", "")
		result.action = effect_data.get("action", "")
		result.target = effect_data.get("target", "")
		result.value = effect_data.get("value", 0)
		result.field = effect_data.get("field", "")
		result.conditions = effect_data.get("conditions", [])
		result.constraints = effect_data.get("constraints", [])
		result["name"] = effect_data.get("name", "")
		result.is_valid = true
		return result
	var old_type = effect_data.get("type", "instant")
	var old_effect = effect_data.get("effect", "")
	var old_value = effect_data.get("value", 0)
	var old_target = effect_data.get("target", "self")
	result.trigger = "TR01"
	result.value = old_value
	result.target = ""
	var old_trigger = effect_data.get("trigger", "")
	var old_phase = effect_data.get("phase", "")
	if old_trigger == "on_summon": result.trigger = "TR01"
	elif old_trigger == "on_destroy": result.trigger = "TR04"
	elif old_phase == "start_of_turn": result.trigger = "TR12"
	elif old_phase == "end_of_turn": result.trigger = "TR14"
	else: result.trigger = "TR01"
	var action_map = {
		"damage": "A01", "heal_self": "A02", "heal": "A02",
		"draw": "A09", "summon": "A19", "debuff": "A20",
		"atk_up": "A20", "hp_up": "A21",
	}
	result.action = action_map.get(old_effect, "A01")
	var target_map = {
		"self": "T01", "hero": "T08", "enemy": "T02",
		"enemy_hero": "T07", "enemy_all": "T04", "enemy_single": "T02",
		"all_enemies": "T04", "friendly": "T03", "ally": "T03",
	}
	result.target = target_map.get(old_target, "T01")
	result.is_valid = true
	return result


static func _norm_field(f: String) -> String:
	return f.replace("　", " ").strip_edges()

static func _card_has_field(ck, field: String) -> bool:
	var nf = _norm_field(field)
	if nf == "": return false
	for f in ck.fields:
		if f is String and _norm_field(f) == nf:
			return true
	return false

static func _compare_num(count, compare_str: String, param) -> bool:
	var v: float = float(count)
	var p: float = float(param)
	match compare_str:
		">", "＞": return v > p
		"≥", ">=", "＞=": return v >= p
		"≤", "<=", "＜=": return v <= p
		"<", "＜": return v < p
		"=", "==", "＝": return v == p
		"!=", "≠": return v != p
	return false


## 检查条件是否满足
static func check_condition(condition_data: Dictionary, owner, opponent, source_card = null) -> bool:
	var condition_id = condition_data.get("id", "")
	var param = condition_data.get("param", condition_data.get("数值", condition_data.get("value", 0)))
	var field = condition_data.get("field", condition_data.get("字段名", ""))
	var compare_str = condition_data.get("compare", condition_data.get("comparison", "≥"))
	match condition_id:
		"C01":
			for i in range(owner.max_field_size):
				var card = owner.field[i]
				if card == null or card == source_card: continue
				if _card_has_field(card, field): return true
			return false
		"C02": return _compare_num(owner.get_field_count(), compare_str, param)
		"C04":
			var c04_compare = condition_data.get("compare", condition_data.get("comparison", "≥"))
			return _compare_num(owner.hp, c04_compare, param)
		"C06":
			var diff = abs(owner.hp - opponent.hp)
			return _compare_num(diff, compare_str, param)
		"C07": return _compare_num(owner.hand.size(), compare_str, param)
		"C08": return _compare_num(owner.energy, compare_str, param)
		"C09": return _compare_num(owner.grave.size(), compare_str, param)
		"C10":
			for grave_card in owner.grave:
				if _card_has_field(grave_card, field): return true
			return false
		"C11": return _compare_num(owner.grave.size(), compare_str, param)
		"C12": return _compare_num(owner.deck.size(), compare_str, param)
		"C13":
			for hand_card in owner.hand:
				if _card_has_field(hand_card, field): return true
			return false
		"C14": return true
		"C15":
			for i in range(owner.max_field_size):
				var card = owner.field[i]
				if card != null and not _card_has_field(card, field):
					return false
			return owner.get_field_count() > 0
		"C16":
			var hijack_count := 0
			for i in range(owner.max_field_size):
				var c = owner.field[i]
				if c != null and c.original_owner != null and c.current_owner != null and c.current_owner != c.original_owner:
					hijack_count += 1
			return _compare_num(hijack_count, compare_str, param)
	return false


## 获取动作的能量消耗
static func get_action_cost(action_id: String, value: int) -> float:
	match action_id:
		"A01": return float(value) * 0.8
		"A02": return float(value) * 0.6
		"A03": return 3.0
		"A04": return 4.0
		"A05": return 2.0
		"A06": return 3.0
		"A07": return 4.0
		"A08": return 2.5
		"A09": return float(value) * 1.5
		"A10": return 2.0
		"A11": return 3.0
		"A12": return 2.5
		"A13": return 3.0
		"A14": return float(value) * 1.0
		"A15": return 3.0
		"A16": return 3.5
		"A17": return 4.0
		"A18": return 4.5
		"A19": return 2.0
		"A20": return abs(value) * 0.7
		"A21": return abs(value) * 0.5
		"A22": return abs(value) * 1.0
		"A23": return abs(value) * 0.5
		"A24": return abs(value) * 1.2
		"A25": return 2.5
		"A26": return 4.0
		"A27": return 6.0
		"A28": return 2.0
		"A29": return 1.5
		"A30": return 3.5
		"A31": return 4.0
		"A32": return 6.0
		"A33": return 3.0
	return 1.0


## 检查约束是否允许发动
static func check_constraint(constraint_id: String, owner, battle_state: int, current_phase: int, player_index: int) -> bool:
	match constraint_id:
		"CO08": return player_index == 0
		"CO09": return player_index == 1
		"CO10": return current_phase == Global.Phase.MAIN
		"CO11": return current_phase == Global.Phase.BATTLE
		"CO13": return true
		"CO14": return true
		"CO15": return true
		"CO16": return true
		_: return true
	return true


## 检查纹路是否可发动（完整检查）
func can_activate_circuit(parsed_effect: Dictionary, owner, opponent, source_card, battle_state: int, current_phase: int, player_index: int) -> Dictionary:
	var result = {"allowed": false, "reason": ""}
	var action = parsed_effect.get("action", "")
	var target = parsed_effect.get("target", "")
	var conditions = parsed_effect.get("conditions", [])
	var constraints = parsed_effect.get("constraints", [])
	var action_info = _circuit_map.get(action, {})
	var target_info = _circuit_map.get(target, {})
	if action_info.is_empty() or target_info.is_empty():
		result.reason = "无效的动作或目标"
		return result
	for condition in conditions:
		var condition_id = condition.get("id", "")
		var condition_info = _circuit_map.get(condition_id, {})
		if condition_info.is_empty(): continue
		if not check_condition(condition, owner, opponent, source_card):
			result.reason = "条件不满足: " + condition_info.get("name", "")
			return result
	for constraint_id in constraints:
		var constraint_info = _circuit_map.get(constraint_id, {})
		if constraint_info.is_empty(): continue
		if not check_constraint(constraint_id, owner, battle_state, current_phase, player_index):
			result.reason = "约束不满足: " + constraint_info.get("name", "")
			return result
	result.allowed = true
	return result


## 检查互斥规则
static func check_mutex(parsed_effect: Dictionary) -> bool:
	return true


## 获取约束参数值（int版本）
static func get_constraint_param(effect: Dictionary, cid: String, fallback: int = 1) -> int:
	var params = effect.get("constraint_params", {})
	if params is Dictionary and params.has(cid):
		var p = params[cid]
		if p is Dictionary:
			for key in ["数值", "X", "value"]:
				if p.has(key):
					var v = p[key]
					if v is String and v.is_valid_int(): return int(v)
					if v is int or v is float: return int(v)
		elif p is int or p is float:
			return int(p)
	var v = effect.get("value", fallback)
	if v is String and v.is_valid_int():
		var iv = int(v)
		return iv if iv > 0 else fallback
	if v is int or v is float:
		var iv = int(v)
		return iv if iv > 0 else fallback
	return fallback


## 获取约束参数（字符串版本）
static func get_constraint_param_str(effect: Dictionary, cid: String, fallback: String = "") -> String:
	var params = effect.get("constraint_params", {})
	if params is Dictionary and params.has(cid):
		var p = params[cid]
		if p is Dictionary:
			for key in ["元素", "element", "field"]:
				if p.has(key): return str(p[key])
		elif p is String:
			return p
	var f = effect.get("field", fallback)
	if f is String and f != "":
		return f
	return fallback


# ============================================================
#  纹路图鉴行模板（预构建，避免每次打开重建720个节点）
# ============================================================

var circuit_row_pool: Array[Panel] = []

func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE:
		for row in circuit_row_pool:
			if is_instance_valid(row):
				row.queue_free()
		circuit_row_pool.clear()

func _build_circuit_row_template() -> void:
	var temp_container = Node.new()
	temp_container.name = "TempRowContainer"
	add_child(temp_container)
	for i in 100:
		var row_panel = Panel.new()
		row_panel.name = "RowPanel"
		var panel_style = StyleBoxFlat.new()
		panel_style.bg_color = Color(0.15, 0.15, 0.22)
		row_panel.add_theme_stylebox_override("panel", panel_style)
		row_panel.custom_minimum_size = Vector2(0, ThemeManager.ph(0.085))
		row_panel.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
		row_panel.mouse_filter = Control.MOUSE_FILTER_PASS
		var row_line = ColorRect.new()
		row_line.name = "RowLine"
		row_line.color = Color(1.0, 1.0, 1.0, 0.20)
		row_line.anchor_left = 0.0; row_line.anchor_top = 1.0
		row_line.anchor_right = 1.0; row_line.anchor_bottom = 1.0
		row_line.offset_left = 0; row_line.offset_top = -2
		row_line.offset_right = 0; row_line.offset_bottom = 0
		row_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row_panel.add_child(row_line)
		var hbox = HBoxContainer.new()
		hbox.name = "RowHBox"
		hbox.anchor_left = 0.0; hbox.anchor_top = 0.0
		hbox.anchor_right = 1.0; hbox.anchor_bottom = 1.0
		hbox.offset_left = ThemeManager.pw(0.02); hbox.offset_top = 0
		hbox.offset_right = ThemeManager.pw(-0.02); hbox.offset_bottom = 0
		hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row_panel.add_child(hbox)
		var id_label = Label.new()
		id_label.name = "IDLabel"
		id_label.add_theme_font_size_override("font_size", 40)
		id_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.8))
		id_label.custom_minimum_size = Vector2(ThemeManager.pw(0.12), 0)
		id_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hbox.add_child(id_label)
		var name_label = Label.new()
		name_label.name = "NameLabel"
		name_label.add_theme_font_size_override("font_size", 50)
		name_label.custom_minimum_size = Vector2(ThemeManager.pw(0.38), 0)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND
		hbox.add_child(name_label)
		var cat_label = Label.new()
		cat_label.name = "CatLabel"
		cat_label.add_theme_font_size_override("font_size", 45)
		cat_label.add_theme_color_override("font_color", Color(0.8, 0.7, 0.5))
		cat_label.custom_minimum_size = Vector2(ThemeManager.pw(0.18), 0)
		cat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hbox.add_child(cat_label)
		var status_label = Label.new()
		status_label.name = "StatusLabel"
		status_label.add_theme_font_size_override("font_size", 40)
		status_label.custom_minimum_size = Vector2(ThemeManager.pw(0.22), 0)
		status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		hbox.add_child(status_label)
		temp_container.add_child(row_panel)
		temp_container.remove_child(row_panel)
		circuit_row_pool.append(row_panel)
	remove_child(temp_container)
	temp_container.queue_free()
	print("[CircuitDB] 纹路图鉴行池预构建完成：共 ", circuit_row_pool.size(), " 行")
