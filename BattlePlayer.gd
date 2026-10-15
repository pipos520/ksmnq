extends RefCounted
class_name BattlePlayer

# ============================================================
#  BattlePlayer.gd —— 战斗中的玩家/敌方实体
#  持有卡组、手牌、场地、墓地、英雄状态
# ============================================================

# 信号
signal hand_changed()          # 手牌变化
signal field_changed()         # 场地变化
signal grave_changed()         # 墓地变化
signal deck_count_changed()    # 卡组张数变化
signal hp_changed(old_hp: int, new_hp: int)
signal energy_changed(old_energy: int, new_energy: int)
signal card_sent_to_grave(card)  # 卡牌被送入墓地时
signal card_summoned(card, slot_index: int)  # 卡牌被召唤/特召到场上时
signal banish_changed()          # 除外区变化
signal card_banished(card)
signal revive_chance_triggered(chance: float, success: bool, slot: int)  # 复活概率检定       # 卡牌被除外时（emit时slot_index尚未清除）

# 身份标识
var is_enemy: bool = false
var player_name: String = "卡师"

# 英雄状态
var hp: int = 0       # 由 BattleManager 在创建时覆盖设置
var max_hp: int = 0   # 同上
var energy: int = 3
var max_energy: int = 5
# 英雄永久增益（装备/Buff）
var hero_atk_buff: int = 0
var hero_hp_buff: int = 0

# 卡组
var deck: BattleDeck = null

# 手牌（BattleCard数组）
var hand: Array = []

# 场地（5个卡位，BattleCard 或 null）
var field: Array = []

# 墓地（BattleCard数组）
var grave: Array = []

# 除外区（BattleCard数组）
var banished: Array = []

# 暂时夺取控制权的卡牌（用于回合结束时归还）
# 格式: [{card: BattleCard, from_player: BattlePlayer, from_slot: int, return_turn: int}]
var _taken_control: Array = []

# 最大手牌数
# var max_hand_size: int = 10  # 无手牌上限

# 最大场地卡位
var max_field_size: int = 5

# 本回合召唤次数
var normal_summon_count: int = 0
var max_normal_summon: int = 999  # 无限制

# 先手标记
var is_first_turn: bool = false

# 回合标记
var has_drawn_this_turn: bool = false


# ===== 初始化 =====

func _init():
	# 初始化场地为5个空位
	for i in range(max_field_size):
		field.append(null)


## 从卡组ID初始化（玩家用）
func init_from_deck(deck_id: String, _is_enemy: bool = false, _is_first: bool = false) -> void:
	is_enemy = _is_enemy
	is_first_turn = _is_first
	
	# 加载卡组
	deck = BattleDeck.from_deck(deck_id, true)
	
	print("[BattlePlayer] 初始化: ", player_name, " (", "敌方" if is_enemy else "己方", ") 卡组", deck.size(), "张")


## 从卡牌数据数组初始化（敌方/测试用）
func init_from_card_datas(card_datas: Array, _is_enemy: bool = false, _is_first: bool = false) -> void:
	is_enemy = _is_enemy
	is_first_turn = _is_first
	
	deck = BattleDeck.from_card_list(card_datas, true)
	
	print("[BattlePlayer] 初始化: ", player_name, " (", "敌方" if is_enemy else "己方", ") 卡组", deck.size(), "张")


## 初始抽牌（指定张数）
func init_draw(draw_count: int = 3) -> void:
	var drawn = deck.draw_multiple(draw_count)
	for card in drawn:
		hand.append(card)
	
	print("[BattlePlayer] 初始抽牌: ", draw_count, "张，手牌: ", hand.size(), "张")
	hand_changed.emit()
	deck_count_changed.emit()


# ===== 抽牌 =====

## 抽牌阶段抽牌
func draw_phase() -> BattleCard:
	is_first_turn = false
	var card = deck.draw()
	if card == null:
		print("[BattlePlayer] 卡组已空，无法抽牌！")
		deck_count_changed.emit()
		return null
	
	hand.append(card)
	has_drawn_this_turn = true
	
	print("[BattlePlayer] 抽牌: ", card.get_display_name(), " 手牌:", hand.size(), " 卡组:", deck.size())
	hand_changed.emit()
	deck_count_changed.emit()
	return card


## 强制抽牌（效果抽牌，不受先手限制）
func draw_card() -> BattleCard:
	var card = deck.draw()
	if card == null:
		deck_count_changed.emit()
		return null
	hand.append(card)
	hand_changed.emit()
	deck_count_changed.emit()
	return card


## 抽多张（效果抽牌）
func draw_cards(count: int) -> Array:
	var drawn := []
	for i in range(count):
		var c = draw_card()
		if c == null:
			break
		drawn.append(c)
	return drawn


# ===== 准备阶段 =====

## 准备阶段：能量回满 + 重置卡牌状态
func ready_phase() -> void:
	# 能量回满
	energy = max_energy
	energy_changed.emit(energy, max_energy)
	
	# 重置所有场上卡牌的攻击和临时状态
	for slot_idx in range(max_field_size):
		var card = field[slot_idx]
		if card != null:
			card.reset_turn_state()
	
	# 重置本回合状态
	normal_summon_count = 0
	has_drawn_this_turn = false
	
	print("[BattlePlayer] 准备阶段: 能量=", energy, "/", max_energy, " 场上卡牌已重置")


# ===== 召唤 =====

## 从手牌召唤到场地（消耗能量）
## 所有卡牌统一处理，不分类型
func summon_from_hand(hand_index: int, slot_index: int) -> bool:
	# 检查索引范围
	if hand_index < 0 or hand_index >= hand.size():
		print("[BattlePlayer] 手牌索引无效: ", hand_index)
		return false
	
	if slot_index < 0 or slot_index >= max_field_size:
		print("[BattlePlayer] 场地索引无效: ", slot_index)
		return false
	
	var card = hand[hand_index] as BattleCard
	
	# 检查费用
	if energy < card.base_cost:
		print("[BattlePlayer] 能量不足: 需要", card.base_cost, " 当前", energy)
		return false
	
	# 检查场地是否空
	if field[slot_index] != null:
		print("[BattlePlayer] 场地", slot_index, "已有卡牌")
		return false
	
	# 执行召唤
	card.is_on_field = true
	card.slot_index = slot_index
	card.summoned_this_turn = true  # 本回合刚召唤，不能攻击
	# 归属追踪（C16 控制权异动判定用）
	if card.original_owner == null:
		card.original_owner = self
	card.current_owner = self
	
	field[slot_index] = card
	hand.remove_at(hand_index)
	
	energy -= card.base_cost
	normal_summon_count += 1
	
	print("[BattlePlayer] 召唤: ", card.get_display_name(), " → 场地", slot_index)
	print("  能量: ", energy, " 手牌:", hand.size(), " 召唤次数:", normal_summon_count)
	
	hand_changed.emit()
	field_changed.emit()
	energy_changed.emit(energy + card.base_cost, energy)
	card_summoned.emit(card, slot_index)
	
	return true


## 将卡牌从手牌放置到场地（不消耗能量，用于特殊召唤）
func special_summon(card: BattleCard, slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= max_field_size:
		return false
	
	if field[slot_index] != null:
		return false
	
	card.is_on_field = true
	card.slot_index = slot_index
	# 归属追踪（C16 控制权异动判定用）
	if card.original_owner == null:
		card.original_owner = self
	card.current_owner = self
	field[slot_index] = card
	
	# 从手牌移除（如果在手牌中）
	var hand_idx = _find_in_hand(card)
	if hand_idx >= 0:
		hand.remove_at(hand_idx)
	
	field_changed.emit()
	hand_changed.emit()
	card_summoned.emit(card, slot_index)
	return true


# ===== 攻击 =====

## 攻击（场地卡位 → 对方场地卡位）
func attack(attacker_slot: int, defender: BattleCard) -> Dictionary:
	var attacker = field[attacker_slot]
	if attacker == null:
		return {"success": false, "reason": "没有攻击者"}
	
	if not attacker.can_attack():
		return {"success": false, "reason": "不能攻击"}
	
	# 标记已攻击
	attacker.has_attacked = true
	# 连击记刀：连击卡第一次攻击后标记combo_used，第二刀后再重置（can_attack据此放行第二刀）
	if attacker.has_combo:
		if attacker.combo_used:
			attacker.combo_used = false  # 第二刀打完，重置
		else:
			attacker.combo_used = true   # 第一刀打完，还有一刀
	# 中毒施加：攻击者带毒（poison_per_hit>0），给防御者叠加中毒指示物
	if attacker.poison_per_hit > 0:
		defender.poison_count += attacker.poison_per_hit
		print("[中毒] ", attacker.get_display_name(), " 攻击附加中毒 x", attacker.poison_per_hit, " → ", defender.get_display_name(), " 当前中毒层数:", defender.poison_count)
	
	# 互换伤害模型
	var damage_to_defender = attacker.current_atk
	var damage_to_attacker = defender.current_atk
	var original_damage = damage_to_defender  # 保存原始值用于元素飘字
	
	# 元素克制：攻击方元素克制防御方元素时，攻击伤害+20%
	var atk_elem = attacker.get_effective_element()
	var def_elem = defender.get_effective_element()
	var affinity = Global.get_element_affinity(atk_elem, def_elem)
	if affinity > 1.0:
		damage_to_defender = roundi(float(damage_to_defender) * affinity)
		print("[元素克制] ", attacker.get_display_name(), " (", atk_elem, ") 克制 ", defender.get_display_name(), " (", def_elem, ") 伤害 x", affinity)
	
	attacker.take_damage(damage_to_attacker)
	defender.take_damage(damage_to_defender)
	
	var result = {
		"success": true,
		"attacker": attacker,
		"defender": defender,
		"damage_to_defender": damage_to_defender,
		"damage_to_attacker": damage_to_attacker,
		"attacker_destroyed": not attacker.is_alive(),
		"defender_destroyed": not defender.is_alive(),
		"element_boost": {
			"type": "affinity" if affinity > 1.0 else "",
			"atk_elem": atk_elem,
			"def_elem": def_elem,
			"from_value": original_damage,
			"to_value": damage_to_defender
		}
	}
	
	print("[BattlePlayer] 攻击: ", attacker.get_display_name(), "(", attacker.current_atk, "/", attacker.current_hp, ")")
	print("  → ", defender.get_display_name(), "(", defender.current_atk, "/", defender.current_hp, ")")
	print("  伤害: 攻击者受到", damage_to_attacker, " 防御者受到", damage_to_defender)
	
	field_changed.emit()
	return result


## 直接攻击英雄
## opponent: 被攻击的对手玩家，用于检查对方场上有无卡牌（场上有卡时不能直击）
func attack_hero(attacker_slot: int, target_hp: int, opponent: BattlePlayer = null) -> Dictionary:
	var attacker = field[attacker_slot]
	if attacker == null:
		return {"success": false, "reason": "没有攻击者"}
	
	if not attacker.can_attack():
		return {"success": false, "reason": "不能攻击"}
	
	# ★ 守护规则：对方场上有存活卡牌时，不能直接攻击英雄
	if opponent != null and opponent.get_field_count() > 0:
		print("[BattlePlayer] 直击被阻挡: 对方场上有", opponent.get_field_count(), "张卡")
		return {"success": false, "reason": "对方场上有卡，不能直接攻击英雄"}
	
	attacker.has_attacked = true
	# 连击记刀（直击英雄同样享受连击）
	if attacker.has_combo:
		if attacker.combo_used:
			attacker.combo_used = false
		else:
			attacker.combo_used = true
	
	var damage = attacker.current_atk
	var new_hp = target_hp - damage
	
	print("[BattlePlayer] 直接攻击英雄: ", attacker.get_display_name(), " 造成", damage, "伤害")
	
	field_changed.emit()
	
	return {
		"success": true,
		"attacker": attacker,
		"damage": damage,
		"new_hp": new_hp
	}


# ===== 墓地 =====

## 将卡牌送入墓地
func send_to_grave(card: BattleCard) -> void:
	if card == null:
		return
	
	# ★ 复活概率检定（卡牌在场上被破坏时触发）
	if card.revive_chance > 0.0 and card.is_on_field:
		var roll_val = randf()
		var success = roll_val < card.revive_chance
		revive_chance_triggered.emit(card.revive_chance, success, card.slot_index)
		if success:
			print("[复活] ", card.get_display_name(), " 复活成功！概率:", card.revive_chance, " 骰子:", roll_val)
			# ★ 复活后还原 base 值并重新应用辅材效果（避免累加）
			card.reset_for_revive()
			card.current_hp = 1
			# 通知视觉层刷新卡牌显示（重要：复活后卡牌还在场上）
			field_changed.emit()
			return
		else:
			print("[复活] ", card.get_display_name(), " 复活失败。概率:", card.revive_chance, " 骰子:", roll_val)
	
	# 保存当前槽位索引（视觉层用它定位卡牌节点）
	var saved_slot: int = card.slot_index
	
	# 重置卡牌状态（离开场地时清空buff/标记/护盾等）
	card.reset_for_leave_field()
	
	# 注意：slot_index 暂不设-1，让信号接收方能用它定位卡牌节点
	card.is_on_field = false
	
	# 从场地移除
	for i in range(max_field_size):
		if field[i] == card:
			field[i] = null
			break
	
	grave.append(card)
	
	print("[BattlePlayer] 送墓: ", card.get_display_name())
	# emit 前恢复槽位索引，让视觉层能定位
	card.slot_index = saved_slot
	# ★ 先 emit card_sent_to_grave（视觉层要拿节点做飞行动画），再 emit field_changed（触发刷新）
	card_sent_to_grave.emit(card)
	field_changed.emit()
	grave_changed.emit()
	
	# emit 之后再清除槽位索引
	card.slot_index = -1


## 将卡牌除外（从场上/手牌/墓地→除外区）
func banish_card(card: BattleCard) -> void:
	if card == null:
		return
	
	# 保存当前槽位索引（视觉层用它定位卡牌节点）
	var saved_slot: int = card.slot_index
	
	card.reset_for_leave_field()
	
	card.is_on_field = false
	# emit 前恢复槽位索引，让视觉层能定位
	card.slot_index = saved_slot
	card_banished.emit(card)
	# emit之后再清除槽位索引
	card.slot_index = -1
	
	# 从场地移除
	for i in range(max_field_size):
		if field[i] == card:
			field[i] = null
			break
	
	# 从手牌移除
	var hand_idx = _find_in_hand(card)
	if hand_idx >= 0:
		hand.remove_at(hand_idx)
	
	# 从墓地移除
	var grave_idx = grave.find(card)
	if grave_idx >= 0:
		grave.remove_at(grave_idx)
	
	banished.append(card)
	
	print("[BattlePlayer] 除外: ", card.get_display_name())
	field_changed.emit()
	hand_changed.emit()
	grave_changed.emit()
	banish_changed.emit()


## 夺取对方场上卡牌的控制权
func take_control_of(target_card: BattleCard, from_player: BattlePlayer, target_slot: int, temporary: bool = false) -> bool:
	"""将对方场上的卡牌转移到己方场地。temporary=true时记录以便结束后归还"""
	if target_card == null:
		return false
	if from_player == null:
		return false
	
	# 从对方场地移除
	from_player.field[target_slot] = null
	
	# 找到己方空位
	var empty_slots = get_empty_slots()
	if empty_slots.is_empty():
		# 没有空位，放回对方场地
		from_player.field[target_slot] = target_card
		print("[BattlePlayer] 控制权转移失败: 己方场地已满")
		return false
	
	var my_slot = empty_slots[0]
	target_card.slot_index = my_slot
	field[my_slot] = target_card
	# 归属追踪：当前控制者更新为新拥有者（original_owner 保持不变）
	target_card.current_owner = self
	
	# 重置攻击状态（本回合不能攻击，归还在己方下回合才能攻击）
	target_card.has_attacked = true
	target_card.summoned_this_turn = true
	
	print("[BattlePlayer] 夺取控制权: ", target_card.get_display_name(), " 从 ", from_player.player_name, " → ", player_name, " 场地", my_slot)
	
	if temporary:
		_taken_control.append({
			"card": target_card,
			"from_player": from_player,
			"from_slot": target_slot,
			"my_slot": my_slot
		})
		print("[BattlePlayer] 标记为暂时控制，将在回合结束时归还")
	
	field_changed.emit()
	from_player.field_changed.emit()
	return true

## 归还暂时夺取的卡牌
func return_taken_control() -> void:
	"""回合结束时归还所有暂时夺取的卡牌"""
	if _taken_control.is_empty():
		return
	
	for entry in _taken_control:
		var card = entry.card as BattleCard
		var from_player = entry.from_player as BattlePlayer
		var from_slot = entry.from_slot
		var my_slot = entry.my_slot
		
		# 从己方场地移除
		if field[my_slot] == card:
			field[my_slot] = null
		else:
			# 卡牌可能已经被移动了，尝试查找
			var found = false
			for i in range(max_field_size):
				if field[i] == card:
					field[i] = null
					found = true
					break
			if not found:
				continue
		
		# 归还到对方场地（如果原位置空着）
		if from_player.field[from_slot] == null:
			card.slot_index = from_slot
			from_player.field[from_slot] = card
		else:
			# 原位置被占了，找空位
			var empty = from_player.get_empty_slots()
			if not empty.is_empty():
				card.slot_index = empty[0]
				from_player.field[empty[0]] = card
			else:
				# 对方场地也满了，送到墓地
				from_player.send_to_grave(card)
				continue
		
		card.has_attacked = false
		card.summoned_this_turn = false
		# 归属追踪：归还后控制者恢复为原拥有者
		card.current_owner = from_player
		print("[BattlePlayer] 归还控制权: ", card.get_display_name(), " → ", from_player.player_name)
		from_player.field_changed.emit()
	
	_taken_control.clear()
	field_changed.emit()
func cleanup_destroyed() -> void:
	for i in range(max_field_size):
		var card = field[i]
		if card != null and not card.is_alive():
			send_to_grave(card)


# ===== 英雄治疗/伤害 =====
## 治疗英雄
func heal_hero(amount: int) -> int:
	var old_hp = hp
	hp += amount
	hp_changed.emit(old_hp, hp)
	print("[BattlePlayer] 治疗英雄: ", player_name, " +", amount, " HP: ", hp, "/", max_hp)
	return hp - old_hp

## 对英雄造成伤害
func damage_hero(amount: int) -> int:
	var old_hp = hp
	hp -= amount
	hp_changed.emit(old_hp, hp)
	print("[BattlePlayer] 伤害英雄: ", player_name, " -", amount, " HP: ", hp, "/", max_hp)
	return old_hp - hp

## 获取英雄当前攻击力（装备加成）
func get_hero_attack() -> int:
	return hero_atk_buff

## 获取英雄当前最大生命
func get_hero_max_hp() -> int:
	return max_hp + hero_hp_buff

## 给英雄添加永久Buff
func add_hero_buff(stat: String, value: int) -> void:
	match stat:
		"atk_up":
			hero_atk_buff += value
		"hp_up":
			hero_hp_buff += value
	# 生命上限提升时，同步增加当前生命
	if stat == "hp_up":
		heal_hero(0)

# ===== 结束阶段 =====
## 结束阶段处理（无手牌上限，不弃牌）
func end_phase() -> void:
	hand_changed.emit()
	grave_changed.emit()


# ===== 查询方法 =====

## 获取场上存活卡牌数
func get_field_count() -> int:
	var count = 0
	for i in range(max_field_size):
		if field[i] != null and field[i].is_alive():
			count += 1
	return count


## 获取场上可攻击卡牌数
func get_attackable_count() -> int:
	var count = 0
	for i in range(max_field_size):
		if field[i] != null and field[i].can_attack():
			count += 1
	return count


## 获取手牌中可召唤的卡牌索引
func get_summonable_hand_indices() -> Array:
	var indices := []
	for i in range(hand.size()):
		var card = hand[i] as BattleCard
		if card.base_cost <= energy:
			indices.append(i)
	return indices


## 获取空场地索引
func get_empty_slots() -> Array:
	var slots := []
	for i in range(max_field_size):
		if field[i] == null:
			slots.append(i)
	return slots


## 检查手牌中是否有特定卡牌
func has_card_in_hand(card_id: String) -> bool:
	for c in hand:
		if c.card_id == card_id:
			return true
	return false


# ===== 内部方法 =====

func _find_in_hand(card: BattleCard) -> int:
	for i in range(hand.size()):
		if hand[i] == card:
			return i
	return -1


# ===== 调试 =====

func print_status() -> void:
	var side = "敌方" if is_enemy else "己方"
	print("=== ", side, "(", player_name, ") ===")
	print("HP: ", hp, "/", max_hp, " 能量: ", energy, "/", max_energy)
	print("卡组: ", deck.size(), "张  手牌: ", hand.size(), "张  墓地: ", grave.size(), "张  除外: ", banished.size(), "张")
	
	print("场地:")
	for i in range(max_field_size):
		var c = field[i]
		if c != null:
			print("  [", i, "] ", c.get_display_name(), " (", c.get_stat_text(), ") 可攻击:", c.can_attack())
		else:
			print("  [", i, "] 空")
	
	print("手牌:")
	for i in range(hand.size()):
		var c = hand[i]
		print("  [", i, "] ", c.get_display_name(), " ⚡", c.base_cost, " (", c.get_stat_text(), ")")


# ===== 序列化 =====

func serialize() -> Dictionary:
	return {
		"is_enemy": is_enemy,
		"player_name": player_name,
		"hp": hp,
		"max_hp": max_hp,
		"energy": energy,
		"max_energy": max_energy,
		"deck": deck.serialize(),
		"hand_ids": _get_hand_ids(),
		"grave_ids": _get_grave_ids(),
		"banished_ids": _get_banished_ids(),
		"field_ids": _get_field_ids(),
		"normal_summon_count": normal_summon_count,
		"is_first_turn": is_first_turn,
	}


func _get_hand_ids() -> Array:
	var ids := []
	for c in hand:
		ids.append(c.card_id)
	return ids


func _get_grave_ids() -> Array:
	var ids := []
	for c in grave:
		ids.append(c.card_id)
	return ids


func _get_banished_ids() -> Array:
	var ids := []
	for c in banished:
		ids.append(c.card_id)
	return ids


func _get_field_ids() -> Array:
	var ids := []
	for i in range(max_field_size):
		if field[i] != null:
			ids.append({"slot": i, "card_id": field[i].card_id})
		else:
			ids.append({"slot": i, "card_id": null})
	return ids
