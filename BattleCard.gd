extends RefCounted
class_name BattleCard

# ============================================================
#  BattleCard.gd —— 战斗中的卡牌实体
#  封装卡牌数据 + 运行时状态，纯数据类（RefCounted）
# ============================================================

# 卡牌基础数据（只读，从JSON加载）
var card_id: String = ""       # 唯一ID
var card_name: String = ""     # 卡名
var fields: Array = []         # 字段
var base_cost: int = 0         # 基础费用
var base_atk: int = 0          # 基础攻击力
var base_hp: int = 0           # 基础生命值
var quality: String = ""       # 品质
var element: String = ""       # 属性
var desc: String = ""          # 描述
var star: int = 0              # 星级
var effects: Array = []        # 效果列表
var aux_items: Array = []      # 辅材数据（玩家制作的卡牌附带）

# 运行时状态（可修改）
var current_atk: int = 0       # 当前攻击力
var current_hp: int = 0        # 当前生命值
var max_hp: int = 0            # 最大生命值
var has_attacked: bool = false     # 是否已攻击过
var summoned_this_turn: bool = false  # 本回合是否刚召唤（召唤当回合不能攻击）
var is_on_field: bool = false      # 是否在场上
var slot_index: int = -1       # 场地位置索引（-1表示不在场）
var is_turned: bool = false    # 表示形式（false=攻击表示，true=守备表示）

# 临时状态标记
var temp_atk_buff: int = 0     # 本回合临时攻击力增减
var temp_hp_buff: int = 0      # 本回合临时生命值增减
var cannot_attack: bool = false # 本回合不能攻击
var is_frozen: bool = false     # 冰冻状态
var effect_disabled: bool = false # 本回合效果被禁用（A33 禁用效果）
# 新机制：中毒 / 连击
var poison_count: int = 0       # 当前中毒指示物层数（回合末扣血，跨回合持续）
var poison_per_hit: int = 0     # 每次攻击附加的中毒层数（中毒辅材效果）
var has_combo: bool = false     # 连击：一回合可攻击两次（连击辅材效果）
var combo_used: bool = false    # 连击第二刀是否已打出（每回合重置）
var original_owner = null       # 归属玩家（首次上场时的所有者，C16 判定用）
var current_owner = null        # 当前控制者（C16 判定用）
# 永久增益（装备/Buff）
var atk_buff_permanent: int = 0 # 永久攻击力加成
var hp_buff_permanent: int = 0  # 永久生命加成
var equipped_to_slot: int = -1  # 装备卡被赋予到的目标卡位（-1=英雄/未指定）

# ===== 辅材运行时标记 =====
var shield_points: int = 0                # 护盾值（蘑菇伞盖）
var indestructible_once_flag: bool = false # 免破坏1次（守护符咒）
var has_haste: bool = false               # 召唤当回合可攻击（疾风之羽）
var extra_triggers_count: int = 0         # 额外触发次数（复制魔方）
var draw_on_summon_count: int = 0         # 上场抽牌数（幸运四叶草）
var damage_reduce_amount: int = 0         # 每次受伤-1（木质纤维）
var damage_halve_flag: bool = false       # 伤害减半（铁壁护甲）
var field_sync_data: Dictionary = {}      # 同字段光环数据（共鸣之石）
var element_override: String = ""         # 元素覆盖（孢子囊/元素之核）

# ★ 原始基础值备份（用于复活时还原，避免 _apply_aux_on_load 累加）
var _original_base_atk: int = -1
var _original_base_hp: int = -1
var _original_base_cost: int = -1
var element_power_bonus: float = 0.0      # 元素强度加成
var revive_chance: float = 0.0              # 破坏时复活概率（蜥蜴尾/守护之核等）


# ===== 工厂方法：从字典创建 =====
static func from_dict(data: Dictionary) -> BattleCard:
	var card = BattleCard.new()
	card.card_id = data.get("id", "")
	card.card_name = data.get("card_name", data.get("name", "未知卡牌"))
	card.fields = data.get("fields", []).duplicate()
	card.base_cost = data.get("energy_cost", data.get("cost", 0))
	card.base_atk = data.get("attack", data.get("atk", 0))
	card.base_hp = data.get("health", data.get("hp", 0))
	card.quality = data.get("quality", "标准")
	card.element = CardManager.get_card_element(data)
	card.desc = data.get("description", data.get("desc", ""))
	card.star = data.get("star", 0)
	card.effects = data.get("effects", []).duplicate()
	card.aux_items = data.get("aux_items", []).duplicate()
	
	# 初始化运行时状态
	card.current_atk = card.base_atk
	card.current_hp = card.base_hp
	card.max_hp = card.base_hp
	
	# 应用辅材效果（基础属性加成，如atk_bonus/hp_bonus/energy_reduce）
	card._apply_aux_on_load()
	
	return card


# ===== 查询方法 =====

## 是否还活着（场上或手牌中有生命值的卡）
func is_alive() -> bool:
	return current_hp > 0


## 是否可以攻击
func can_attack() -> bool:
	if has_attacked and not (has_combo and combo_used):
		return false
	if cannot_attack or current_atk <= 0 or not is_on_field:
		return false
	# 召唤当回合不能攻击（除非有疾风效果）
	if summoned_this_turn and not has_haste:
		return false
	return true


## 是否为随从类型（保留兼容，所有卡牌现在统一处理）
func is_creature() -> bool:
	# 设计文档：卡牌不区分，所有卡都是统一类型
	return true

## 是否为法术类型（保留兼容）
func is_spell() -> bool:
	return false

## 是否为装备类型（保留兼容）
func is_equipment() -> bool:
	return false

## 计算等级（floor((攻击+生命)/2)，最低0最高12）
## 获取完整字段信息（用于显示）
func get_display_name() -> String:
	var prefix = ""
	var display_element = get_effective_element()
	if display_element == "火": prefix = ""
	elif display_element == "水": prefix = ""
	elif display_element == "风": prefix = ""
	elif display_element == "地": prefix = ""
	elif display_element == "光": prefix = ""
	elif display_element == "暗": prefix = ""
	return prefix + " " + card_name


## 获取卡牌的最终元素（考虑辅材覆盖）
func get_effective_element() -> String:
	if element_override != "":
		return element_override
	return element

## 获取战力显示文本
func get_stat_text() -> String:
	return str(current_atk) + "/" + str(current_hp)


## 获取完整信息
func get_full_info() -> String:
	var info = get_display_name() + "\n"
	info += " " + str(current_atk) + "  " + str(current_hp)
	info += " " + str(base_cost)
	info += " [" + quality + " " + element + "]\n"
	info += desc
	return info


# ===== 状态修改方法 =====

# ===== 辅材效果方法 =====

## 加载时应用的基础效果（属性加成/能量减免/元素覆盖）
func _apply_aux_on_load() -> void:
	# ★ 首次应用前备份原始 base 值，供复活时还原（避免累加）
	if _original_base_atk < 0:
		_original_base_atk = base_atk
		_original_base_hp = base_hp
		_original_base_cost = base_cost
	
	for aux in aux_items:
		var effect = aux.get("effect", {})
		if effect.is_empty():
			continue
		
		# 基础属性加成
		if effect.has("atk_bonus"):
			base_atk += effect["atk_bonus"]
		if effect.has("hp_bonus"):
			base_hp += effect["hp_bonus"]
			max_hp += effect["hp_bonus"]
		if effect.has("energy_reduce"):
			base_cost = max(1, base_cost - effect["energy_reduce"])
		
		# 元素覆盖
		if effect.has("element"):
			element_override = effect["element"]
		if effect.has("element_power"):
			element_power_bonus = effect["element_power"]
		
		# 运行时标记（非即时生效，需要召唤时处理）
		if effect.has("shield"):
			shield_points = effect["shield"]
		if effect.get("indestructible_once", false):
			indestructible_once_flag = true
		if effect.get("haste", false):
			has_haste = true
		if effect.has("extra_trigger"):
			extra_triggers_count = effect["extra_trigger"]
		if effect.has("draw_on_summon"):
			draw_on_summon_count = effect["draw_on_summon"]
		if effect.has("damage_reduce"):
			damage_reduce_amount = effect["damage_reduce"]
		if effect.get("damage_halve", false):
			damage_halve_flag = true
		if effect.has("field_sync"):
			field_sync_data = effect["field_sync"].duplicate()
		# 新机制：中毒 / 连击
		if effect.has("poison"):
			poison_per_hit = max(poison_per_hit, int(effect["poison"]))
		if effect.get("combo", false):
			has_combo = true
		if effect.has("revive_chance"):
			revive_chance = max(revive_chance, float(effect["revive_chance"]))


## 召唤时生效的效果（返回一个字典，BattleManager处理）
func get_summon_aux_effects() -> Dictionary:
	var result = {}
	if draw_on_summon_count > 0:
		result["draw"] = draw_on_summon_count
	if has_haste:
		result["haste"] = true
		has_attacked = false  # 允许当回合攻击
	recalculate_stats()
	return result


## 获取实际消耗能量（考虑能量减免辅材）
func get_actual_cost() -> int:
	return base_cost


## 受到伤害（带护盾/减伤/免破坏处理）
func take_damage(dmg: int) -> int:
	var actual_dmg = dmg
	
	# 伤害减半
	if damage_halve_flag:
		actual_dmg = max(1, actual_dmg / 2)
	
	# 伤害减免
	actual_dmg -= damage_reduce_amount
	actual_dmg = max(0, actual_dmg)
	
	# 护盾吸收
	if shield_points > 0:
		var absorbed = min(shield_points, actual_dmg)
		shield_points -= absorbed
		actual_dmg -= absorbed
		if actual_dmg <= 0:
			return 0  # 护盾完全吸收
	
	# 免破坏1次（如果伤害会致死）
	if indestructible_once_flag and current_hp - actual_dmg <= 0:
		indestructible_once_flag = false
		current_hp = 1  # 保留1血
		return 0
	
	current_hp -= actual_dmg
	return actual_dmg
## 恢复生命（可超过最大生命上限，永久保留）
func heal(amount: int) -> void:
	current_hp += amount
## 重新计算攻防（永久Buff + 临时Buff）
func recalculate_stats() -> void:
	current_atk = max(0, base_atk + atk_buff_permanent + temp_atk_buff)
	max_hp = max(0, base_hp + hp_buff_permanent + temp_hp_buff)
	# current_hp 保留原始值，不做上限钳制（治疗/增益可永久超出上限）
## 添加永久Buff（装备/永久增益）
func add_buff(stat: String, value: int) -> void:
	match stat:
		"atk_up":
			atk_buff_permanent += value
		"hp_up":
			hp_buff_permanent += value
			# 生命值增减同时作用当前血量（正数=回血，负数=扣血）
			current_hp += value
	recalculate_stats()
## 添加临时Buff（回合内增减，准备阶段自动重置）
func add_temp_buff(stat: String, value: int) -> void:
	match stat:
		"atk":
			temp_atk_buff += value
		"hp":
			temp_hp_buff += value
	recalculate_stats()
## 重置攻击状态（每回合准备阶段调用）
func reset_turn_state() -> void:
	has_attacked = false
	summoned_this_turn = false
	temp_atk_buff = 0
	temp_hp_buff = 0
	cannot_attack = false
	effect_disabled = false
	combo_used = false  # 连击次数每回合重置（连击能力保留）
	# 中毒指示物跨回合持续，不清零
	# 保留永久增益，重置临时攻命增减
	recalculate_stats()

## 离开场地时重置战斗状态（送墓/弹回手牌/弹回卡组时调用）
## 复活时还原基础值并重新应用辅材（防止 atk_bonus/hp_bonus 累加）
func reset_for_revive() -> void:
	if _original_base_atk >= 0:
		base_atk = _original_base_atk
		base_hp = _original_base_hp
		base_cost = _original_base_cost
		max_hp = base_hp  # max_hp 也会随 hp_bonus 加成，先重置
		# 重新应用辅材（会再次设置 base 值和 runtime 标记）
		_apply_aux_on_load()

func reset_for_leave_field() -> void:
	# 重置战斗运行时状态
	has_attacked = false
	summoned_this_turn = false
	is_on_field = false
	slot_index = -1
	is_turned = false
	temp_atk_buff = 0
	temp_hp_buff = 0
	cannot_attack = false
	is_frozen = false
	effect_disabled = false
	equipped_to_slot = -1
	# 新机制：离场清空中毒/连击，避免残留到下次登场
	poison_count = 0
	poison_per_hit = 0
	has_combo = false
	combo_used = false
	
	# 重置辅材/光环运行时状态（保留 base_atk/base_hp 的永久加成）
	shield_points = 0
	indestructible_once_flag = false
	has_haste = false
	extra_triggers_count = 0
	draw_on_summon_count = 0
	damage_reduce_amount = 0
	damage_halve_flag = false
	field_sync_data = {}
	revive_chance = 0.0
	element_override = ""
	element_power_bonus = 0.0
	
	# 重置攻击力/生命值到基础值（含永久增益）+ 全回复
	recalculate_stats()
	current_hp = max_hp
	
	# 重新应用辅材的运行时效果（这样下次召唤时 shield/haste 等再次生效）
	_apply_aux_on_load()


## 克隆自身（用于复制卡牌对象）
func clone() -> BattleCard:
	var c = BattleCard.new()
	c.card_id = card_id
	c.card_name = card_name
	c.fields = fields.duplicate()
	c.base_cost = base_cost
	c.base_atk = base_atk
	c.base_hp = base_hp
	c.quality = quality
	c.element = element
	c.desc = desc
	c.star = star
	c.effects = effects.duplicate()
	c.aux_items = aux_items.duplicate()
	c.current_atk = current_atk
	c.current_hp = current_hp
	c.max_hp = max_hp
	c.has_attacked = has_attacked
	c.is_on_field = is_on_field
	c.slot_index = slot_index
	c.is_turned = is_turned
	# 复制新机制状态
	c.poison_count = poison_count
	c.poison_per_hit = poison_per_hit
	c.has_combo = has_combo
	c.combo_used = combo_used
	# 复制辅材运行时标记
	c.shield_points = shield_points
	c.indestructible_once_flag = indestructible_once_flag
	c.has_haste = has_haste
	c.extra_triggers_count = extra_triggers_count
	c.draw_on_summon_count = draw_on_summon_count
	c.damage_reduce_amount = damage_reduce_amount
	c.damage_halve_flag = damage_halve_flag
	c.field_sync_data = field_sync_data.duplicate()
	c.element_override = element_override
	c.element_power_bonus = element_power_bonus
	c.revive_chance = revive_chance
	return c
	return c
