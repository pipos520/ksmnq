extends RefCounted
class_name BattlePlayerNew

## ============================================================
##  BattlePlayerNew.gd — 战斗中的玩家/敌方实体（纯数据）
##  持有卡组、手牌、场地、墓地、除外区、英雄状态
##  不依赖任何UI，不包含AI逻辑
##  手牌/场地/墓地/除外已拆分到独立管理器
## ============================================================

# ===== 信号（转发自管理器）=====
signal hand_changed()
signal field_changed()
signal grave_changed()
signal banish_changed()
signal deck_count_changed()
signal hp_changed(old_hp: int, new_hp: int)
signal energy_changed(old_val: int, new_val: int)
signal card_summoned(card: BattleCardNew, slot_index: int)
signal card_sent_to_grave(card: BattleCardNew)

# ===== 身份 =====
var is_enemy: bool = false
var player_name: String = "卡师"

# ===== 英雄状态 =====
var hp: int = 0
var max_hp: int = 0
var energy: int = 3
var max_energy: int = 5
var hero_atk_buff: int = 0
var hero_hp_buff: int = 0

# ===== 牌区（拆分管理器）=====
var deck: BattleDeckNew = null
var hand: BattleHandNew = null
var field: BattleFieldNew = null
var grave: BattleGraveNew = null
var banished: BattleBanishNew = null

# ===== 临时控制权 =====
var _taken_control: Array = []

# ===== 常量 =====
var max_field_size: int = 5
var normal_summon_count: int = 0
var max_normal_summon: int = 999
var is_first_turn: bool = false
var has_drawn_this_turn: bool = false


# ===== 初始化 =====
func _init():
	hand = BattleHandNew.new()
	field = BattleFieldNew.new()
	grave = BattleGraveNew.new()
	banished = BattleBanishNew.new()
	# 连接管理器信号转发
	hand.hand_changed.connect(func(): hand_changed.emit())
	field.field_changed.connect(func(): field_changed.emit())
	grave.grave_changed.connect(func(): grave_changed.emit())
	banished.banish_changed.connect(func(): banish_changed.emit())

func init_from_deck(deck_id: String, _is_enemy: bool = false, _is_first: bool = false) -> void:
	is_enemy = _is_enemy
	is_first_turn = _is_first
	deck = BattleDeckNew.from_deck(deck_id, true)
	print("[BattlePlayerNew] 初始化: ", player_name, " 卡组", deck.size(), "张")

func init_from_card_datas(card_datas: Array, _is_enemy: bool = false, _is_first: bool = false) -> void:
	is_enemy = _is_enemy
	is_first_turn = _is_first
	deck = BattleDeckNew.from_card_list(card_datas, true)
	print("[BattlePlayerNew] 初始化: ", player_name, " 卡组", deck.size(), "张")

func init_draw(draw_count: int = 5) -> void:
	var drawn = deck.draw_multiple(draw_count)
	for card in drawn:
		hand.add(card)
	hand_changed.emit()
	deck_count_changed.emit()


# ===== 抽牌 =====
func draw_phase() -> BattleCardNew:
	if is_first_turn:
		is_first_turn = false
		return null
	var card = deck.draw()
	if card == null:
		deck_count_changed.emit()
		return null
	hand.add(card)
	has_drawn_this_turn = true
	hand_changed.emit()
	deck_count_changed.emit()
	return card

func draw_card() -> BattleCardNew:
	var card = deck.draw()
	if card == null:
		deck_count_changed.emit()
		return null
	hand.add(card)
	hand_changed.emit()
	deck_count_changed.emit()
	return card

func draw_cards(count: int) -> Array:
	var drawn := []
	for i in range(count):
		var c = draw_card()
		if c == null:
			break
		drawn.append(c)
	return drawn


# ===== 准备阶段 =====
func ready_phase() -> void:
	energy = max_energy
	energy_changed.emit(energy, max_energy)
	for i in range(max_field_size):
		var c = field.get_slot(i)
		if c != null:
			c.reset_turn_state()
	normal_summon_count = 0
	has_drawn_this_turn = false


# ===== 召唤 =====
func summon_from_hand(hand_index: int, slot_index: int) -> bool:
	if hand_index < 0 or hand_index >= hand.size():
		return false
	if slot_index < 0 or slot_index >= max_field_size:
		return false
	var card = hand.get_card(hand_index) as BattleCardNew
	if energy < card.base_cost:
		return false
	if field.get_slot(slot_index) != null:
		return false
	
	card.is_on_field = true
	card.slot_index = slot_index
	card.summoned_this_turn = true
	if card.original_owner == null:
		card.original_owner = self
	card.current_owner = self
	
	field.set_slot(slot_index, card)
	hand.remove_at(hand_index)
	energy -= card.base_cost
	normal_summon_count += 1
	
	hand_changed.emit()
	field_changed.emit()
	energy_changed.emit(energy + card.base_cost, energy)
	card_summoned.emit(card, slot_index)
	return true

func special_summon(card: BattleCardNew, slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= max_field_size:
		return false
	if field.get_slot(slot_index) != null:
		return false
	card.is_on_field = true
	card.slot_index = slot_index
	if card.original_owner == null:
		card.original_owner = self
	card.current_owner = self
	field.set_slot(slot_index, card)
	var hand_idx = hand.find(card)
	if hand_idx >= 0:
		hand.remove_at(hand_idx)
	field_changed.emit()
	hand_changed.emit()
	card_summoned.emit(card, slot_index)
	return true


# ===== 攻击 =====
func attack(attacker_slot: int, defender: BattleCardNew) -> Dictionary:
	var attacker = field.get_slot(attacker_slot)
	if attacker == null or not attacker.can_attack():
		return {"success": false, "reason": "无法攻击"}
	
	attacker.has_attacked = true
	if attacker.has_combo:
		if attacker.combo_used:
			attacker.combo_used = false
		else:
			attacker.combo_used = true
	
	if attacker.poison_per_hit > 0:
		defender.poison_count += attacker.poison_per_hit
	
	var dmg_to_def = attacker.current_atk
	var dmg_to_atk = defender.current_atk
	var orig_dmg = dmg_to_def
	
	# 元素克制
	var atk_elem = attacker.get_effective_element()
	var def_elem = defender.get_effective_element()
	var affinity = Global.get_element_affinity(atk_elem, def_elem)
	if affinity > 1.0:
		dmg_to_def = roundi(float(dmg_to_def) * affinity)
	
	attacker.take_damage(dmg_to_atk)
	defender.take_damage(dmg_to_def)
	
	field_changed.emit()
	return {
		"success": true,
		"attacker": attacker,
		"defender": defender,
		"damage_to_defender": dmg_to_def,
		"damage_to_attacker": dmg_to_atk,
		"attacker_destroyed": not attacker.is_alive(),
		"defender_destroyed": not defender.is_alive(),
		"element_boost": {
			"type": "affinity" if affinity > 1.0 else "",
			"atk_elem": atk_elem,
			"def_elem": def_elem,
			"from_value": orig_dmg,
			"to_value": dmg_to_def
		}
	}

func attack_hero(attacker_slot: int, target_hp: int, opponent: BattlePlayerNew = null) -> Dictionary:
	var attacker = field.get_slot(attacker_slot)
	if attacker == null or not attacker.can_attack():
		return {"success": false, "reason": "无法攻击"}
	
	# 守护规则
	if opponent != null and opponent.field.get_field_count() > 0:
		return {"success": false, "reason": "对方场上有卡"}
	
	attacker.has_attacked = true
	if attacker.has_combo:
		if attacker.combo_used:
			attacker.combo_used = false
		else:
			attacker.combo_used = true
	
	var damage = attacker.current_atk
	field_changed.emit()
	return {
		"success": true,
		"attacker": attacker,
		"damage": damage,
		"new_hp": target_hp - damage
	}


# ===== 墓地/除外 =====
func send_to_grave(card: BattleCardNew) -> void:
	if card == null:
		return
	card.reset_for_leave_field()
	var slot_idx = field.find_card(card)
	if slot_idx >= 0:
		field.set_slot(slot_idx, null)
	grave.add(card)
	field_changed.emit()
	grave_changed.emit()
	card_sent_to_grave.emit(card)

func banish_card(card: BattleCardNew) -> void:
	if card == null:
		return
	card.reset_for_leave_field()
	var slot_idx = field.find_card(card)
	if slot_idx >= 0:
		field.set_slot(slot_idx, null)
	var hand_idx = hand.find(card)
	if hand_idx >= 0:
		hand.remove_at(hand_idx)
	for i in range(grave.size()):
		if grave.get_all()[i] == card:
			grave.remove_at(i)
			break
	banished.add(card)
	field_changed.emit()
	hand_changed.emit()
	grave_changed.emit()
	banish_changed.emit()

func cleanup_destroyed() -> void:
	for i in range(max_field_size):
		var c = field.get_slot(i)
		if c != null and not c.is_alive():
			send_to_grave(c)


# ===== 控制权 =====
func take_control_of(target_card: BattleCardNew, from_player: BattlePlayerNew, target_slot: int, temporary: bool = false) -> bool:
	if target_card == null or from_player == null:
		return false
	from_player.field.set_slot(target_slot, null)
	var empty = field.get_empty_slots()
	if empty.is_empty():
		from_player.field.set_slot(target_slot, target_card)
		return false
	var my_slot = empty[0]
	target_card.slot_index = my_slot
	field.set_slot(my_slot, target_card)
	target_card.current_owner = self
	target_card.has_attacked = true
	target_card.summoned_this_turn = true
	if temporary:
		_taken_control.append({"card": target_card, "from_player": from_player, "from_slot": target_slot, "my_slot": my_slot})
	field_changed.emit()
	from_player.field_changed.emit()
	return true

func return_taken_control() -> void:
	if _taken_control.is_empty():
		return
	for entry in _taken_control:
		var card = entry.card as BattleCardNew
		var from_p = entry.from_player as BattlePlayerNew
		var from_slot = entry.from_slot
		var my_slot = entry.my_slot
		if field.get_slot(my_slot) == card:
			field.set_slot(my_slot, null)
		else:
			for i in range(max_field_size):
				if field.get_slot(i) == card:
					field.set_slot(i, null)
					break
		if from_p.field.get_slot(from_slot) == null:
			card.slot_index = from_slot
			from_p.field.set_slot(from_slot, card)
		else:
			var empty = from_p.field.get_empty_slots()
			if not empty.is_empty():
				card.slot_index = empty[0]
				from_p.field.set_slot(empty[0], card)
			else:
				from_p.send_to_grave(card)
				continue
		card.has_attacked = false
		card.summoned_this_turn = false
		card.current_owner = from_p
		from_p.field_changed.emit()
	_taken_control.clear()
	field_changed.emit()


# ===== 英雄操作 =====
func heal_hero(amount: int) -> int:
	var old = hp
	hp += amount
	hp_changed.emit(old, hp)
	return hp - old

func damage_hero(amount: int) -> int:
	var old = hp
	hp -= amount
	hp_changed.emit(old, hp)
	return old - hp

func get_hero_attack() -> int:
	return hero_atk_buff

func get_hero_max_hp() -> int:
	return max_hp + hero_hp_buff

func add_hero_buff(stat: String, value: int) -> void:
	match stat:
		"atk_up": hero_atk_buff += value
		"hp_up":
			hero_hp_buff += value


# ===== 结束阶段 =====
func end_phase() -> void:
	hand_changed.emit()
	grave_changed.emit()


# ===== 查询（兼容旧接口）=====
func get_field_count() -> int:
	return field.get_field_count()

func get_attackable_count() -> int:
	return field.get_attackable_count()

func get_summonable_hand_indices() -> Array:
	return hand.get_summonable_indices(energy)

func get_empty_slots() -> Array:
	return field.get_empty_slots()

func has_card_in_hand(card_id: String) -> bool:
	return hand.has_card(card_id)
