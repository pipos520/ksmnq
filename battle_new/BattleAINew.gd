extends IBattleControllerNew
class_name BattleAINew

## ============================================================
##  BattleAINew.gd — AI控制器
##  实现IBattleControllerNew接口，走完全相同的操作路径
##  AI和玩家调用的都是 _game.request_play_card() 等接口
##  决策逻辑：启发式评分 + 简单优先级
## ============================================================

# ===== 游戏引用 =====
var _game: BattleGameNew = null

# ===== AI状态 =====
var _is_thinking: bool = false
var _think_delay: float = 0.5  # 思考延迟（秒）
var _think_timer: SceneTreeTimer = null

# ===== 策略参数 =====
var _aggression: float = 0.6  # 攻击性（0~1）
var _card_preference: Dictionary = {}  # card_id -> 评分偏好


# ===== 初始化 =====
func init(game: BattleGameNew) -> void:
	_game = game


# ============================================================
#  IBattleControllerNew 接口实现
# ============================================================

## 阶段进入通知
func on_phase_enter(phase: int) -> void:
	match phase:
		BattleGameNew.Phase.MAIN:
			_start_think(_do_main_phase)
		BattleGameNew.Phase.BATTLE:
			_start_think(_do_battle_phase)
		BattleGameNew.Phase.DISCARD:
			_start_think(_do_discard_phase)
		_:
			pass


## 连锁请求
func on_chain_requested(callback_id: int, chainable_cards: Array) -> void:
	_start_think(func(): _do_chain_response(callback_id, chainable_cards))


## 弃牌请求
func on_discard_requested(count: int, callback_id: int, reason: String) -> void:
	_start_think(func(): _do_discard_request(count, callback_id, reason))


## 检索请求
func on_deck_search_requested(cards: Array, max_select: int, callback_id: int) -> void:
	_start_think(func(): _do_deck_search(cards, max_select, callback_id))


## 全知视角
func get_view() -> Dictionary:
	return {
		"player_hand": _game.player_opp.hand.duplicate(),
		"player_deck_count": _game.player_opp.deck.size(),
		"enemy_hand": _game.player_self.hand.duplicate(),
		"enemy_deck_count": _game.player_self.deck.size(),
	}


# ============================================================
#  思考延迟
# ============================================================

func _start_think(callback: Callable) -> void:
	if _is_thinking:
		return
	if _game == null or not is_instance_valid(_game):
		callback.call()
		return
	_is_thinking = true
	# 使用SceneTree timer模拟思考延迟
	_think_timer = _game.get_tree().create_timer(_think_delay)
	_think_timer.timeout.connect(func():
		_is_thinking = false
		callback.call()
	)


# ============================================================
#  主要阶段决策
# ============================================================

func _do_main_phase() -> void:
	if _game.battle_state != BattleGameNew.State.PLAYING:
		return
	if _game.current_player_idx != 1:
		return
	
	var p = _game.player_opp
	var opp = _game.player_self
	
	# 1. 尝试召唤
	var summon_result = _try_summon(p, opp)
	if summon_result:
		# 召唤成功后继续思考
		_start_think(_do_main_phase)
		return
	
	# 2. 尝试发动效果
	var effect_result = _try_activate_effects(p, opp)
	if effect_result:
		_start_think(_do_main_phase)
		return
	
	# 3. 进入战斗阶段
	_game.request_enter_battle()


func _try_summon(p, opp) -> bool:
	# 找手牌中可召唤且最有价值的卡
	var best_idx = -1
	var best_score = 0.0
	var empty_slots = p.get_empty_slots()
	if empty_slots.is_empty():
		return false
	
	for i in range(p.hand.size()):
		var card = p.hand[i]
		if card.base_cost > p.energy:
			continue
		# 检查约束
		if _game._constraint_mgr and not _game._constraint_mgr.can_summon(p, card):
			continue
		var score = _evaluate_card_value(card, p, opp)
		if score > best_score:
			best_score = score
			best_idx = i
	
	if best_idx >= 0:
		# 检查是否值得召唤（基础阈值）
		if best_score < 1.0 and p.get_field_count() >= 3:
			return false  # 场上够了，低分卡不值得出
		_game.request_play_card(best_idx, empty_slots[0])
		return true
	
	return false


func _try_activate_effects(p, opp) -> bool:
	# 找场上有可用效果的卡
	for i in range(p.max_field_size):
		var card = p.field.get_slot(i)
		if card == null or not card.is_alive():
			continue
		if card.effect_disabled:
			continue
		for effect in card.effects:
			var parsed = Global.parse_circuit(effect)
			if not parsed.is_valid:
				continue
			var trig = parsed.get("trigger", "")
			# 只主动发动无触发条件的效果（trigger为空或TR01已触发过）
			if trig != "":
				continue
			# 约束检查
			if _game._constraint_mgr and not _game._constraint_mgr.can_activate(p, opp, card, effect, parsed):
				continue
			# 效果价值评估
			if _evaluate_effect_value(parsed, p, opp) > 0.5:
				_game._effect_system.execute_effect(p, card, effect, i)
				return true
	return false


# ============================================================
#  战斗阶段决策
# ============================================================

func _do_battle_phase() -> void:
	if _game.battle_state != BattleGameNew.State.PLAYING:
		return
	if _game.current_player_idx != 1:
		return
	
	var p = _game.player_opp
	var opp = _game.player_self
	
	# 找最佳攻击
	var best_atk = _find_best_attack(p, opp)
	if best_atk.has("action"):
		_start_think(func():
			if best_atk.action == "attack":
				_game.request_attack(best_atk.atk_slot, best_atk.def_slot)
			elif best_atk.action == "attack_hero":
				_game.request_attack_hero(best_atk.atk_slot)
			# 继续思考下一步
			_start_think(_do_battle_phase)
		)
		return
	
	# 没有可攻击的了，结束阶段
	_game.request_end_phase()


func _find_best_attack(p, opp) -> Dictionary:
	var best = {"action": "", "atk_slot": -1, "def_slot": -1, "score": -999}
	
	for atk_slot in range(p.max_field_size):
		var attacker = p.field.get_slot(atk_slot)
		if attacker == null or not attacker.can_attack():
			continue
		
		# 攻击对方卡牌
		for def_slot in range(opp.max_field_size):
			var defender = opp.field.get_slot(def_slot)
			if defender == null or not defender.is_alive():
				continue
			var score = _evaluate_attack(attacker, defender, false)
			if score > best.score:
				best = {"action": "attack", "atk_slot": atk_slot, "def_slot": def_slot, "score": score}
		
		# 直击英雄（对方无场上卡时）
		if opp.get_field_count() == 0:
			var hero_score = _evaluate_attack(attacker, null, true)
			if hero_score > best.score:
				best = {"action": "attack_hero", "atk_slot": atk_slot, "score": hero_score}
	
	return best


func _evaluate_attack(attacker, defender, is_hero: bool) -> float:
	var score = 0.0
	if is_hero:
		# 直击英雄：伤害越高越好
		score = float(attacker.current_atk) * _aggression
	else:
		# 打卡：能击杀加分，能活下来加分
		var dmg_to_def = attacker.current_atk
		var dmg_to_atk = defender.current_atk
		# 元素克制
		var atk_elem = attacker.get_effective_element()
		var def_elem = defender.get_effective_element()
		var affinity = Global.get_element_affinity(atk_elem, def_elem)
		if affinity > 1.0:
			dmg_to_def = roundi(float(dmg_to_def) * affinity)
		# 击杀对方
		if dmg_to_def >= defender.current_hp:
			score += 50.0
		else:
			score += float(dmg_to_def) * 0.5
		# 自己存活
		if dmg_to_atk < attacker.current_hp:
			score += 20.0
		else:
			score -= 30.0  # 自杀扣分
		# 攻击性调整
		score *= _aggression
	return score


# ============================================================
#  弃牌决策
# ============================================================

func _do_discard_phase() -> void:
	var p = _game.player_opp
	var need = p.hand.size() - 6
	if need > 0:
		_do_discard_request(need, -1, "end_phase")


func _do_discard_request(count: int, callback_id: int, reason: String) -> void:
	var p = _game.player_opp
	# 弃掉价值最低的卡
	var scored: Array = []
	for i in range(p.hand.size()):
		var score = _evaluate_card_value(p.hand[i], p, _game.player_self)
		scored.append({"idx": i, "score": score})
	scored.sort_custom(func(a, b): return a.score < b.score)
	
	var to_discard: Array = []
	for i in range(min(count, scored.size())):
		to_discard.append(scored[i].idx)
	
	# 执行弃牌
	for idx in to_discard:
		if idx >= 0 and idx < p.hand.size():
			var card = p.hand[idx]
			p.grave.add(card)
			p.hand.remove_at(idx)
			# 调整后续索引（因为remove_at改变了数组）
			for j in range(len(to_discard)):
				if to_discard[j] > idx:
					to_discard[j] -= 1
	p.hand_changed.emit()
	p.grave_changed.emit()
	
	# 回调
	if callback_id >= 0 and _game._discard_callbacks.has(callback_id):
		var cb = _game._discard_callbacks[callback_id]
		var cb_func = cb.get("func", null)
		if cb_func is Callable:
			cb_func.call()
		_game._discard_callbacks.erase(callback_id)
	
	print("[AINew] Discarded ", count, " cards (", reason, ")")


# ============================================================
#  检索决策
# ============================================================

func _do_deck_search(cards: Array, max_select: int, callback_id: int) -> void:
	# AI选择价值最高的卡
	var scored: Array = []
	for i in range(cards.size()):
		var score = _evaluate_card_value(cards[i], _game.player_opp, _game.player_self)
		scored.append({"idx": i, "score": score})
	scored.sort_custom(func(a, b): return a.score > b.score)
	
	var selected: Array = []
	for i in range(min(max_select, scored.size())):
		selected.append(scored[i].idx)
	
	# 执行检索
	var cb = _game._search_callbacks.get(callback_id, {})
	var owner = cb.get("owner", null)
	if owner:
		for idx in selected:
			if idx >= 0 and idx < cards.size():
				var card_to_find = cards[idx]
				owner.deck.search_and_remove(func(c): return c == card_to_find)
				owner.hand.add(card_to_find)
		owner.hand_changed.emit()
		owner.deck_count_changed.emit()
	_game._search_callbacks.erase(callback_id)
	print("[AINew] Deck search: selected ", selected.size(), " cards")


# ============================================================
#  连锁响应决策
# ============================================================

func _do_chain_response(callback_id: int, chainable_cards: Array) -> void:
	# AI评估是否值得连锁
	if chainable_cards.is_empty():
		_game._effect_system.respond_to_chain(false)
		return
	
	# 简单策略：有连锁卡且能量足够时50%概率连锁
	var p = _game.player_opp
	var best_card = null
	var best_score = 0.0
	
	for entry in chainable_cards:
		var card = entry.card
		var parsed = Global.parse_circuit(entry.effect)
		var score = _evaluate_effect_value(parsed, p, _game.player_self)
		if score > best_score:
			best_score = score
			best_card = entry
	
	if best_card and best_score > 1.0:
		# 连锁
		_game._effect_system.respond_to_chain(true, {
			"owner": p,
			"card": best_card.card,
			"effect": best_card.effect,
			"slot": best_card.slot
		})
	else:
		# 放弃连锁
		_game._effect_system.respond_to_chain(false)


# ============================================================
#  价值评估
# ============================================================

func _evaluate_card_value(card, owner, opponent) -> float:
	var score = 0.0
	# 基础属性评分
	score += float(card.base_atk) * 0.3
	score += float(card.base_hp) * 0.3
	# 费用效率（atk+hp/cost）
	if card.base_cost > 0:
		var efficiency = float(card.base_atk + card.base_hp) / float(card.base_cost)
		score += efficiency * 0.2
	# 有效果的加分
	for effect in card.effects:
		var parsed = Global.parse_circuit(effect)
		if parsed.is_valid:
			var trig = parsed.get("trigger", "")
			if trig == "":
				score += 5.0  # 主动效果
			else:
				score += 2.0  # 被动触发
	# 辅材加分
	for aux in card.aux_items:
		score += 1.0
	return score


func _evaluate_effect_value(parsed: Dictionary, owner, opponent) -> float:
	var action_id = parsed.get("action", "A01")
	var value = parsed.get("value", 0)
	var target_id = parsed.get("target", "T01")
	
	var score = 0.0
	match action_id:
		"A01":  # 伤害
			score = float(value) * 0.5 * _aggression
		"A02":  # 治疗
			if owner.hp < owner.max_hp * 0.5:
				score = float(value) * 0.4
		"A03", "A04":  # 破坏/除外
			if target_id in ["T02", "T04"]:
				score = 15.0 * _aggression  # 对敌方
		"A09":  # 抽牌
			score = float(value) * 2.0
		"A20", "A22":  # 增益
			score = float(value) * 0.3
		"A15", "A16", "A17", "A18":  # 特召
			score = 8.0
		_:
			score = 1.0  # 其他效果默认低分
	return score