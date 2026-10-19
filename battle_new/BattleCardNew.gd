extends RefCounted
class_name BattleCardNew

## ============================================================
##  BattleCardNew.gd — 战斗中的卡牌实体（纯数据）
##  封装卡牌基础数据 + 运行时状态，不依赖任何UI
## ============================================================

# ===== 基础数据（只读，从JSON加载） =====
var card_id: String = ""
var card_name: String = ""
var fields: Array = []
var base_cost: int = 0
var base_atk: int = 0
var base_hp: int = 0
var quality: String = ""
var element: String = ""
var desc: String = ""
var star: int = 0
var effects: Array = []
var aux_items: Array = []

# ===== 运行时状态 =====
var current_atk: int = 0
var current_hp: int = 0
var max_hp: int = 0
var has_attacked: bool = false
var summoned_this_turn: bool = false
var is_on_field: bool = false
var slot_index: int = -1
var is_turned: bool = false  # false=攻击表示, true=守备表示

# ===== 临时状态 =====
var temp_atk_buff: int = 0
var temp_hp_buff: int = 0
var cannot_attack: bool = false
var is_frozen: bool = false
var effect_disabled: bool = false

# ===== 机制状态 =====
var poison_count: int = 0
var poison_per_hit: int = 0
var has_combo: bool = false
var combo_used: bool = false
var original_owner = null  # BattlePlayerNew
var current_owner = null   # BattlePlayerNew

# ===== 永久增益 =====
var atk_buff_permanent: int = 0
var hp_buff_permanent: int = 0
var equipped_to_slot: int = -1

# ===== 辅材运行时标记 =====
var shield_points: int = 0
var indestructible_once_flag: bool = false
var has_haste: bool = false
var extra_triggers_count: int = 0
var draw_on_summon_count: int = 0
var damage_reduce_amount: int = 0
var damage_halve_flag: bool = false
var field_sync_data: Dictionary = {}
var element_override: String = ""
var element_power_bonus: float = 0.0


# ===== 工厂方法 =====
static func from_dict(data: Dictionary) -> BattleCardNew:
	var card = BattleCardNew.new()
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
	
	card.current_atk = card.base_atk
	card.current_hp = card.base_hp
	card.max_hp = card.base_hp
	
	card._apply_aux_on_load()
	return card


# ===== 查询方法 =====
func is_alive() -> bool:
	return current_hp > 0

func can_attack() -> bool:
	if has_attacked and not (has_combo and not combo_used):
		return false
	if cannot_attack or current_atk <= 0 or not is_on_field:
		return false
	if summoned_this_turn and not has_haste:
		return false
	return true

func get_display_name() -> String:
	var prefix = ""
	var elem = get_effective_element()
	match elem:
		"火": prefix = ""
		"水": prefix = ""
		"风": prefix = ""
		"地": prefix = ""
		"光": prefix = ""
		"暗": prefix = ""
	return prefix + " " + card_name

func get_effective_element() -> String:
	return element_override if element_override != "" else element

func get_stat_text() -> String:
	return str(current_atk) + "/" + str(current_hp)


# ===== 状态修改 =====
func take_damage(dmg: int) -> int:
	var actual = dmg
	if damage_halve_flag:
		actual = max(1, actual / 2)
	actual -= damage_reduce_amount
	actual = max(0, actual)
	
	if shield_points > 0:
		var absorbed = min(shield_points, actual)
		shield_points -= absorbed
		actual -= absorbed
		if actual <= 0:
			return 0
	
	if indestructible_once_flag and current_hp - actual <= 0:
		indestructible_once_flag = false
		current_hp = 1
		return 0
	
	current_hp -= actual
	return actual

func heal(amount: int) -> void:
	current_hp += amount

func recalculate_stats() -> void:
	current_atk = max(0, base_atk + atk_buff_permanent + temp_atk_buff)
	max_hp = max(0, base_hp + hp_buff_permanent + temp_hp_buff)

func add_buff(stat: String, value: int) -> void:
	match stat:
		"atk_up":
			atk_buff_permanent += value
		"hp_up":
			hp_buff_permanent += value
			current_hp += value
	recalculate_stats()

func add_temp_buff(stat: String, value: int) -> void:
	match stat:
		"atk":
			temp_atk_buff += value
		"hp":
			temp_hp_buff += value
	recalculate_stats()

func reset_turn_state() -> void:
	has_attacked = false
	summoned_this_turn = false
	temp_atk_buff = 0
	temp_hp_buff = 0
	cannot_attack = false
	effect_disabled = false
	combo_used = false
	recalculate_stats()

func reset_for_leave_field() -> void:
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
	poison_count = 0
	poison_per_hit = 0
	has_combo = false
	combo_used = false
	shield_points = 0
	indestructible_once_flag = false
	has_haste = false
	extra_triggers_count = 0
	draw_on_summon_count = 0
	damage_reduce_amount = 0
	damage_halve_flag = false
	field_sync_data = {}
	element_override = ""
	element_power_bonus = 0.0
	recalculate_stats()
	current_hp = max_hp
	_apply_aux_on_load()


# ===== 辅材 =====
func _apply_aux_on_load() -> void:
	for aux in aux_items:
		var effect = aux.get("effect", {})
		if effect.is_empty():
			continue
		if effect.has("atk_bonus"):
			base_atk += effect["atk_bonus"]
		if effect.has("hp_bonus"):
			base_hp += effect["hp_bonus"]
			max_hp += effect["hp_bonus"]
		if effect.has("energy_reduce"):
			base_cost = max(1, base_cost - effect["energy_reduce"])
		if effect.has("element"):
			element_override = effect["element"]
		if effect.has("element_power"):
			element_power_bonus = effect["element_power"]
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
		if effect.has("poison"):
			poison_per_hit = max(poison_per_hit, int(effect["poison"]))
		if effect.get("combo", false):
			has_combo = true

func get_summon_aux_effects() -> Dictionary:
	var result = {}
	if draw_on_summon_count > 0:
		result["draw"] = draw_on_summon_count
	if has_haste:
		result["haste"] = true
		has_attacked = false
	recalculate_stats()
	return result


# ===== 克隆 =====
func clone() -> BattleCardNew:
	var c = BattleCardNew.new()
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
	c.poison_count = poison_count
	c.poison_per_hit = poison_per_hit
	c.has_combo = has_combo
	c.combo_used = combo_used
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
	return c
