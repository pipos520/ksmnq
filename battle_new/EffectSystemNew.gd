extends RefCounted
class_name EffectSystemNew

## ============================================================
##  EffectSystemNew.gd — 效果引擎 + 连锁系统
##  核心改进（规避旧系统8个bug）：
##    1. 状态机替代布尔flag（IDLE→BUILDING→RESOLVING）→ 规避Bug#1
##    2. 统一连锁响应接口 → 规避Bug#2
##    3. 目标快照：执行前冻结目标列表 → 规避Bug#3
##    4. 亡语传正确old_slot → 规避Bug#4
##    5. clear()强制清理 → 规避Bug#5
##    6. 留给TriggerSystemNew做注册表 → 规避Bug#6
##    7. 连锁构建用while循环而非递归 → 规避Bug#7
##    8. 严格缩进+状态机保证执行路径唯一 → 规避Bug#8
## ============================================================

# ===== 连锁状态机 =====
enum ChainState { IDLE, BUILDING, RESOLVING }
var _chain_state: ChainState = ChainState.IDLE

# ===== 连锁栈 =====
# 格式: [{owner, card, effect, slot, chain_id, negated, source_label}]
var _chain_stack: Array = []
var _chain_counter: int = 0

# ===== 游戏引用 =====
var _game = null  # BattleGameNew

# ===== 连锁回调 =====
var _chain_callback_id: int = -1

# ===== 信号 =====
signal chain_started(chain_count: int)
signal chain_link_resolved(chain_id: int)
signal chain_all_resolved()
signal chain_response_requested(callback_id: int, chainable_cards: Array)
signal effect_executed(action_id: String, value: int, is_player: bool, source_slot: int, desc: String)


# ===== 初始化 =====
func init(game) -> void:
	_game = game

# ============================================================
#  公开接口
# ============================================================

## 执行效果（主入口）：压入连锁栈 → 询问响应 → 结算
func execute_effect(owner, source_card, effect: Dictionary, source_slot: int) -> void:
	if _chain_state == ChainState.RESOLVING:
		# 结算中：直接执行，不入栈（规避Bug#1）
		_do_execute_effect(owner, source_card, effect, source_slot)
		return
	
	# 压入连锁栈
	_push_to_chain(owner, source_card, effect, source_slot, "direct")
	
	# 开始连锁构建（while循环，非递归 → 规避Bug#7）
	_start_chain_building()


## 强制直接执行效果（跳过连锁，用于系统强制效果如中毒结算）
func execute_effect_direct(owner, source_card, effect: Dictionary, source_slot: int) -> void:
	_do_execute_effect(owner, source_card, effect, source_slot)


## Controller回调：是否连锁
func respond_to_chain(accept: bool, card_data: Dictionary = {}) -> void:
	if _chain_state != ChainState.BUILDING:
		return
	
	if accept and card_data.size() > 0:
		var owner = card_data.get("owner", null)
		var card = card_data.get("card", null)
		var effect = card_data.get("effect", {})
		var slot = card_data.get("slot", -1)
		if owner and card and effect.size() > 0:
			_push_to_chain(owner, card, effect, slot, "response")
			# 继续连锁构建（while循环会处理）
			_continue_chain_building()
			return
	
	# 放弃连锁 → 进入结算
	_resolve_chain()


## 清理所有连锁状态（战斗结束时调用 → 规避Bug#5）
func clear() -> void:
	_chain_stack.clear()
	_chain_counter = 0
	_chain_state = ChainState.IDLE
	_chain_callback_id = -1


# ============================================================
#  连锁栈管理
# ============================================================

func _push_to_chain(owner, card, effect: Dictionary, slot: int, source_label: String) -> int:
	_chain_counter += 1
	var cid = _chain_counter
	_chain_stack.append({
		"owner": owner,
		"card": card,
		"effect": effect.duplicate(),
		"slot": slot,
		"chain_id": cid,
		"negated": false,
		"source": source_label
	})
	print("[EffectNew] Chain#", cid, " pushed: ", card.get_display_name() if card else "?", " (", source_label, ")")
	return cid


## 连锁构建阶段：询问对方是否连锁（while循环 → 规避Bug#7）
func _start_chain_building() -> void:
	_chain_state = ChainState.BUILDING
	_continue_chain_building()


func _continue_chain_building() -> void:
	while _chain_state == ChainState.BUILDING:
		if _chain_stack.is_empty():
			_chain_state = ChainState.IDLE
			return
		
		# 检查对方是否有可连锁的卡（TR16触发器）
		var last_link = _chain_stack[-1]
		var responder = _get_opponent_of(last_link.owner)
		var chainable = _find_chainable_cards(responder)
		
		if chainable.is_empty():
			# 没有可连锁的卡，直接结算
			_resolve_chain()
			return
		
		# 有连锁机会 → 通知Controller（统一接口 → 规避Bug#2）
		_chain_callback_id = _chain_counter
		var responder_idx = 0 if responder == _game.player_self else 1
		if _game._controllers.size() > responder_idx and _game._controllers[responder_idx] != null:
			chain_response_requested.emit(_chain_callback_id, chainable)
			_game._controllers[responder_idx].on_chain_requested(_chain_callback_id, chainable)
		else:
			# 无Controller（安全兜底）→ 直接结算
			_resolve_chain()
			return
		
		# Controller会异步回调 respond_to_chain()，退出while循环
		break


## 连锁结算（LIFO 后进先出）
func _resolve_chain() -> void:
	if _chain_stack.is_empty():
		_chain_state = ChainState.IDLE
		return
	
	_chain_state = ChainState.RESOLVING  # 状态机锁定，不再递归入栈
	chain_started.emit(_chain_stack.size())
	print("[EffectNew] ===== Chain resolve start (", _chain_stack.size(), " links) =====")
	
	# 后进先出结算
	while not _chain_stack.is_empty():
		var link = _chain_stack.pop_back()
		
		if link.negated:
			print("[EffectNew] Chain#", link.chain_id, " negated, skip")
			chain_link_resolved.emit(link.chain_id)
			continue
		
		# 执行效果（此时_chain_state=RESOLVING，不会再入栈 → 规避Bug#1）
		_do_execute_effect(link.owner, link.card, link.effect, link.slot)
		chain_link_resolved.emit(link.chain_id)
		
		# 检查胜负
		_game._check_win_condition()
		if _game.battle_state != _game.State.PLAYING:
			# 战斗结束，清理（→ 规避Bug#5）
			_chain_stack.clear()
			_chain_state = ChainState.IDLE
			chain_all_resolved.emit()
			return
	
	_chain_state = ChainState.IDLE
	chain_all_resolved.emit()
	print("[EffectNew] ===== Chain resolve done =====")


# ============================================================
#  效果执行管线（解析→条件→约束→目标→分发）
# ============================================================

func _do_execute_effect(owner, source_card, effect: Dictionary, source_slot: int) -> void:
	var parsed = Global.parse_circuit(effect)
	if not parsed.is_valid:
		print("[EffectNew] Invalid circuit, skip: ", effect)
		return
	
	var action_id = parsed.get("action", "A01")
	var target_id = parsed.get("target", "T01")
	var value = parsed.get("value", 0)
	
	var opponent = _get_opponent_of(owner)
	
	# 条件检查
	for condition in parsed.conditions:
		if not Global.check_condition(condition, owner, opponent, source_card):
			print("[EffectNew] Condition failed: ", condition)
			return
	
	# 约束检查（ConstraintManagerNew）
	if _game._constraint_mgr:
		if not _game._constraint_mgr.can_activate(owner, opponent, source_card, effect, parsed):
			print("[EffectNew] Constraint blocked: ", source_card.get_display_name() if source_card else "?")
			return
	
	var desc = Global.format_effect_description(parsed)
	var is_player = (owner == _game.player_self)
	print("[EffectNew] ", owner.player_name, " → ", source_card.get_display_name() if source_card else "?", " : ", desc)
	
	# 目标解析（快照 → 规避Bug#3：执行中场地变化不影响已选目标）
	var targets = _resolve_targets(target_id, owner, opponent, source_card, source_slot, action_id)
	if targets == null:
		print("[EffectNew] No valid target for ", target_id)
		return
	
	# 发射效果发动通知信号
	var target_info = _get_target_info(targets, target_id, is_player)
	effect_executed.emit(action_id, value, is_player, source_slot, desc)
	# BattleGameNew已定义card_effect_activated信号，直接emit
	_game.card_effect_activated.emit(
		source_card.get_display_name() if source_card else "?", desc, action_id,
		target_id, value, target_info.name, source_slot, is_player,
		target_info.slot, target_info.is_player
	)
	
	# 约束代价支付（CO04弃牌等，ConstraintManagerNew）
	var parsed_constraints = parsed
	if _game._constraint_mgr:
		_game._constraint_mgr.after_activation(owner, opponent, source_card, effect, parsed_constraints)
	_dispatch_action(owner, opponent, source_card, source_slot, action_id, target_id, targets, value, parsed, is_player)
	
	# 刷新双方场地
	_game.player_self.field_changed.emit()
	_game.player_opp.field_changed.emit()
	
	# 触发 TR16: 对方发动效果时
	_game._trigger_system.on_effect_activated(owner, source_card, effect, source_slot)


# ============================================================
#  目标解析（返回目标快照数组）
# ============================================================

func _resolve_targets(target_id: String, owner, opponent, source_card, source_slot: int, action_id: String) -> Variant:
	# 返回值：
	# null = 无有效目标
	# Array = 目标卡牌列表（快照）
	# Dictionary = 目标信息（英雄等）
	
	match target_id:
		"T01":  # 自身
			if source_card == null:
				return null
			return {"type": "card", "cards": [source_card], "slot": source_slot, "owner": owner}
		"T02":  # 敌方单体（随机）
			var tc = _pick_random_field_card(opponent)
			if tc != null:
				return {"type": "card", "cards": [tc], "slot": tc.slot_index, "owner": opponent}
			elif action_id == "A01":
				# 伤害重定向到敌方英雄
				return {"type": "hero", "target_player": opponent}
			return null
		"T03":  # 己方单体（随机）
			var tc2 = _pick_random_field_card(owner)
			if tc2 != null:
				return {"type": "card", "cards": [tc2], "slot": tc2.slot_index, "owner": owner}
			elif action_id == "A02":
				return {"type": "hero", "target_player": owner}
			elif action_id == "A09":
				return {"type": "player", "target_player": owner}
			return null
		"T04":  # 敌方全体
			return {"type": "cards", "cards": _get_all_field_cards(opponent), "owner": opponent}
		"T05":  # 己方全体
			return {"type": "cards", "cards": _get_all_field_cards(owner), "owner": owner}
		"T06":  # 全场
			return {"type": "cards", "cards": _get_all_field_cards(owner) + _get_all_field_cards(opponent), "owner": null}
		"T07":  # 敌方英雄
			return {"type": "hero", "target_player": opponent}
		"T08":  # 己方英雄
			return {"type": "hero", "target_player": owner}
		"T13":  # 对方攻击最高
			var ec = _pick_extreme_card(opponent, true)
			return ec if ec != null else null
		"T14":  # 对方攻击最低
			var ec2 = _pick_extreme_card(opponent, false)
			return ec2 if ec2 != null else null
		"T15":  # 我方攻击最高
			var ec3 = _pick_extreme_card(owner, true)
			return ec3 if ec3 != null else null
		"T16":  # 我方攻击最低
			var ec4 = _pick_extreme_card(owner, false)
			return ec4 if ec4 != null else null
		_:
			# 默认：自身
			if source_card == null:
				return null
			return {"type": "card", "cards": [source_card], "slot": source_slot, "owner": owner}


# ============================================================
#  动作分发
# ============================================================

func _dispatch_action(owner, opponent, source_card, source_slot: int, action_id: String, target_id: String, targets: Variant, value: int, parsed: Dictionary, is_player: bool) -> void:
	match action_id:
		"A01":  # 伤害
			_exec_damage(owner, opponent, source_card, targets, value, is_player, source_slot)
		"A02":  # 治疗
			_exec_heal(owner, opponent, source_card, targets, value, is_player, source_slot)
		"A03":  # 破坏
			_exec_destroy(owner, opponent, targets)
		"A04":  # 除外
			_exec_banish(owner, opponent, targets)
		"A05":  # 除外墓地卡
			_exec_banish_from_grave(owner, opponent, target_id)
		"A06":  # 弹回手牌
			_exec_bounce_to_hand(owner, opponent, targets)
		"A07":  # 弹回卡组
			_exec_bounce_to_deck(owner, opponent, targets)
		"A08":  # 送入墓地
			_exec_send_to_grave(owner, opponent, targets)
		"A09":  # 抽牌
			_exec_draw(owner, opponent, source_card, targets, value)
		"A10":  # 检索字段卡
			var field_name = parsed.get("field", "")
			_exec_search_field(owner, target_id, field_name, value)
		"A11":  # 检索卡
			_exec_search_any(owner, target_id, value)
		"A12":  # 墓地回收
			_exec_recycle_grave(owner, target_id, value)
		"A13":  # 除外回收
			_exec_recycle_banish(owner, target_id, value)
		"A14":  # 卡组堆墓
			_exec_mill_deck(owner, target_id, value)
		"A15":  # 手牌特召
			_exec_special_summon_hand(owner, source_card, target_id, value)
		"A16":  # 墓地特召
			_exec_special_summon_grave(owner, target_id, value)
		"A17":  # 卡组特召
			_exec_special_summon_deck(owner, target_id, value)
		"A18":  # 除外特召
			_exec_special_summon_banish(owner, target_id, value)
		"A19":  # 召唤衍生物
			_exec_token_summon(owner, source_card)
		"A20":  # 永久ATK增益
			_exec_stat_buff(owner, source_card, targets, "atk_up", value)
		"A21":  # 永久HP增减
			if value < 0:
				_exec_damage(owner, opponent, source_card, targets, abs(value), is_player, source_slot)
			else:
				_exec_heal(owner, opponent, source_card, targets, value, is_player, source_slot)
		"A22":  # ATK+HP双增益
			_exec_stat_buff(owner, source_card, targets, "atk_up", value)
			_exec_stat_buff(owner, source_card, targets, "hp_up", value)
		"A23":  # 回合内攻命增减
			_exec_temp_stat(owner, source_card, targets, "atk", value)
		"A24":  # 全场增减
			_exec_all_field_stat(owner, opponent, target_id, value)
		"A25":  # 交换攻防
			_exec_swap_atk_hp(targets)
		"A26":  # 暂时夺取控制权
			_exec_take_control_temp(owner, opponent, targets)
		"A27":  # 永久夺取控制权
			_exec_take_control_perm(owner, opponent, targets)
		"A28":  # 无法攻击
			_exec_cannot_attack(targets)
		"A29":  # 表示形式变更
			_exec_change_form(targets)
		"A30":  # 无效效果发动并破坏
			_exec_negate_and_destroy(owner, opponent, target_id)
		"A31":  # 控制权变更·一回合
			_exec_control_change(owner, opponent, targets, true)
		"A32":  # 控制权变更·永久
			_exec_control_change(owner, opponent, targets, false)
		"A33":  # 禁用效果
			_exec_disable_effect(targets)
		_:
			print("[EffectNew] Unknown action: ", action_id)


# ============================================================
#  动作执行器
# ============================================================

func _exec_damage(owner, opponent, source_card, targets, base_value: int, is_player: bool, source_slot: int) -> void:
	var final_value = base_value
	# 元素加成
	if source_card:
		var src_elem = source_card.get_effective_element()
		var power_mult = Global.get_element_power_multiplier(src_elem, source_card.element_power_bonus, "damage")
		final_value = roundi(float(final_value) * power_mult)
	
	if targets is Dictionary:
		if targets.get("type") == "hero":
			var tp = targets.get("target_player")
			var old_hp = tp.hp
			tp.hp = max(0, tp.hp - final_value)
			tp.hp_changed.emit(old_hp, tp.hp)
			print("[EffectNew] Hero damage: ", final_value, " -> ", tp.player_name, " HP:", tp.hp)
		elif targets.get("type") == "card" or targets.get("type") == "cards":
			for card in targets.get("cards", []):
				if card and card.is_alive():
					card.take_damage(final_value)
	# 清理阵亡
	owner.cleanup_destroyed()
	opponent.cleanup_destroyed()


func _exec_heal(owner, opponent, source_card, targets, base_value: int, is_player: bool, source_slot: int) -> void:
	var final_value = base_value
	if source_card:
		var src_elem = source_card.get_effective_element()
		var power_mult = Global.get_element_power_multiplier(src_elem, source_card.element_power_bonus, "heal")
		final_value = roundi(float(final_value) * power_mult)
	
	if targets is Dictionary:
		if targets.get("type") == "hero":
			var tp = targets.get("target_player")
			var old_hp = tp.hp
			tp.hp = min(tp.max_hp, tp.hp + final_value)
			tp.hp_changed.emit(old_hp, tp.hp)
		elif targets.get("type") == "card" or targets.get("type") == "cards":
			for card in targets.get("cards", []):
				if card:
					card.heal(final_value)


func _exec_destroy(owner, opponent, targets) -> void:
	if targets is Dictionary:
		for card in targets.get("cards", []):
			if card and card.is_alive():
				_send_card_to_grave(card, targets.get("owner", owner))
		owner.cleanup_destroyed()
		opponent.cleanup_destroyed()


func _exec_banish(owner, opponent, targets) -> void:
	if targets is Dictionary:
		for card in targets.get("cards", []):
			if card and card.is_alive():
				_send_card_to_banish(card, targets.get("owner", owner))
		owner.cleanup_destroyed()
		opponent.cleanup_destroyed()


func _exec_banish_from_grave(owner, opponent, target_id: String) -> void:
	var target_player = opponent if target_id in ["T02", "T04"] else owner
	if target_player.grave.size() > 0:
		var card = target_player.grave.remove_at(randi() % target_player.grave.size())
		target_player.banished.add(card)
		target_player.grave_changed.emit()
		target_player.banish_changed.emit()
		print("[EffectNew] Banish from grave: ", card.get_display_name() if card else "?")


func _exec_bounce_to_hand(owner, opponent, targets) -> void:
	if targets is Dictionary:
		for card in targets.get("cards", []):
			if card and card.is_alive():
				var card_owner = targets.get("owner", owner)
				var old_slot = card.slot_index
				_remove_card_from_field(card_owner, card)
				card.reset_for_leave_field()
				card_owner.hand.add(card)
				card_owner.hand_changed.emit()
				_game._trigger_system.on_card_bounced(card_owner, card, old_slot)
	owner.cleanup_destroyed()
	opponent.cleanup_destroyed()


func _exec_bounce_to_deck(owner, opponent, targets) -> void:
	if targets is Dictionary:
		for card in targets.get("cards", []):
			if card and card.is_alive():
				var card_owner = targets.get("owner", owner)
				var old_slot = card.slot_index
				_remove_card_from_field(card_owner, card)
				card.reset_for_leave_field()
				card_owner.deck.put_on_top(card)
				card_owner.deck_count_changed.emit()
				_game._trigger_system.on_card_bounced(card_owner, card, old_slot)
	owner.cleanup_destroyed()
	opponent.cleanup_destroyed()


func _exec_send_to_grave(owner, opponent, targets) -> void:
	if targets is Dictionary:
		for card in targets.get("cards", []):
			if card and card.is_alive():
				_send_card_to_grave(card, targets.get("owner", owner))
	owner.cleanup_destroyed()
	opponent.cleanup_destroyed()


func _exec_draw(owner, opponent, source_card, targets, count: int) -> void:
	var target_player = owner
	if targets is Dictionary and targets.get("target_player"):
		target_player = targets.get("target_player")
	var final_count = count
	# 元素加成：检查发动效果的卡牌本身（而非扫手牌）
	if source_card and source_card.get_effective_element() == "风":
		var power_mult = Global.get_element_power_multiplier("风", source_card.element_power_bonus, "draw")
		final_count = roundi(float(final_count) * power_mult)
	for i in range(final_count):
		var card = target_player.draw_phase()
		if card == null:
			break
	target_player.hand_changed.emit()
	target_player.deck_count_changed.emit()


func _exec_search_field(owner, target_id: String, field_name: String, value: int) -> void:
	# 从卡组中检索拥有指定字段的卡牌
	var candidates: Array = []
	for card in owner.deck.get_all_cards():
		if field_name in card.fields:
			candidates.append(card)
	if candidates.is_empty():
		print("[EffectNew] Search field: no card with field '", field_name, "'")
		return
	# 限制检索数量
	var max_select = min(value, candidates.size())
	# 通知Controller做选择（AI自动选，玩家弹窗）
	_game._search_counter += 1
	var cb_id = _game._search_counter
	_game._search_callbacks[cb_id] = {
		"owner": owner,
		"candidates": candidates,
		"max_select": max_select
	}
	var owner_idx = 0 if owner == _game.player_self else 1
	if _game._controllers.size() > owner_idx and _game._controllers[owner_idx] != null:
		_game._controllers[owner_idx].on_deck_search_requested(candidates, max_select, cb_id)
	else:
		# 无Controller，自动选前max_select张
		_search_field_auto_select(cb_id, range(max_select))


func _search_field_auto_select(cb_id: int, selected_indices: Array) -> void:
	var cb = _game._search_callbacks.get(cb_id, {})
	var owner = cb.get("owner", null)
	var candidates = cb.get("candidates", [])
	if owner == null:
		return
	for idx in selected_indices:
		if idx >= 0 and idx < candidates.size():
			var card_to_find = candidates[idx]
			owner.deck.search_and_remove(func(c): return c == card_to_find)
			owner.hand.add(card_to_find)
	owner.hand_changed.emit()
	owner.deck_count_changed.emit()
	_game._search_callbacks.erase(cb_id)
	print("[EffectNew] Search field auto-select: ", selected_indices.size(), " cards")


func _exec_search_any(owner, target_id: String, value: int) -> void:
	if owner.deck.size() == 0:
		return
	var draw_count = min(value, owner.deck.size())
	for i in range(draw_count):
		var card = owner.deck.draw()
		if card:
			owner.hand.add(card)
	owner.hand_changed.emit()
	owner.deck_count_changed.emit()
	print("[EffectNew] Search any: drew ", draw_count, " cards")


func _exec_recycle_grave(owner, target_id: String, value: int) -> void:
	var count = min(value, owner.grave.size())
	for i in range(count):
		var card = owner.grave.remove_at(randi() % owner.grave.size())
		owner.hand.add(card)
	owner.hand_changed.emit()
	owner.grave_changed.emit()
	print("[EffectNew] Recycle from grave: ", count, " cards")


func _exec_recycle_banish(owner, target_id: String, value: int) -> void:
	var count = min(value, owner.banished.size())
	for i in range(count):
		var card = owner.banished.remove_at(randi() % owner.banished.size())
		owner.hand.add(card)
	owner.hand_changed.emit()
	owner.banish_changed.emit()
	print("[EffectNew] Recycle from banish: ", count, " cards")


func _exec_mill_deck(owner, target_id: String, value: int) -> void:
	var count = min(value, owner.deck.size())
	for i in range(count):
		var card = owner.deck.draw()
		if card:
			owner.grave.add(card)
	owner.grave_changed.emit()
	owner.deck_count_changed.emit()
	print("[EffectNew] Mill deck: ", count, " cards")


func _exec_special_summon_hand(owner, source_card, target_id: String, value: int) -> void:
	var candidates: Array = []
	for card in owner.hand:
		if card.base_cost <= value:
			candidates.append(card)
	if candidates.is_empty():
		return
	var card = candidates[randi() % candidates.size()]
	var empty_slots = owner.get_empty_slots()
	if empty_slots.is_empty():
		return
	owner.special_summon(card, empty_slots[0])
	print("[EffectNew] Special summon from hand: ", card.get_display_name())


func _exec_special_summon_grave(owner, target_id: String, value: int) -> void:
	if owner.grave.is_empty():
		return
	var card = owner.grave.remove_at(randi() % owner.grave.size())
	var empty_slots = owner.get_empty_slots()
	if empty_slots.is_empty():
		owner.grave.add(card)
		return
	owner.special_summon(card, empty_slots[0])
	owner.grave_changed.emit()
	print("[EffectNew] Special summon from grave: ", card.get_display_name())


func _exec_special_summon_deck(owner, target_id: String, value: int) -> void:
	if owner.deck.size() == 0:
		return
	var card = owner.deck.draw()
	if card == null:
		return
	var empty_slots = owner.get_empty_slots()
	if empty_slots.is_empty():
		owner.hand.add(card)
		owner.hand_changed.emit()
		return
	owner.special_summon(card, empty_slots[0])
	owner.deck_count_changed.emit()
	print("[EffectNew] Special summon from deck: ", card.get_display_name())


func _exec_special_summon_banish(owner, target_id: String, value: int) -> void:
	if owner.banished.is_empty():
		return
	var card = owner.banished.remove_at(randi() % owner.banished.size())
	var empty_slots = owner.get_empty_slots()
	if empty_slots.is_empty():
		owner.banished.add(card)
		return
	owner.special_summon(card, empty_slots[0])
	owner.banish_changed.emit()
	print("[EffectNew] Special summon from banish: ", card.get_display_name())


func _exec_token_summon(owner, source_card) -> void:
	var empty_slots = owner.get_empty_slots()
	if empty_slots.is_empty():
		return
	var token = BattleCardNew.new()
	token.card_id = "token_" + str(randi())
	token.card_name = "衍生物"
	token.base_cost = 0
	token.base_atk = 1
	token.base_hp = 1
	token.current_atk = 1
	token.current_hp = 1
	token.max_hp = 1
	token.is_on_field = true
	token.slot_index = empty_slots[0]
	token.summoned_this_turn = true
	token.original_owner = owner
	token.current_owner = owner
	owner.field[empty_slots[0]] = token
	owner.field_changed.emit()
	owner.card_summoned.emit(token, empty_slots[0])
	print("[EffectNew] Token summon -> slot ", empty_slots[0])


func _exec_stat_buff(owner, source_card, targets, stat: String, value: int) -> void:
	if targets is Dictionary:
		for card in targets.get("cards", []):
			if card and card.is_alive():
				card.add_buff(stat, value)


func _exec_temp_stat(owner, source_card, targets, stat: String, value: int) -> void:
	if targets is Dictionary:
		for card in targets.get("cards", []):
			if card and card.is_alive():
				card.add_temp_buff(stat, value)


func _exec_all_field_stat(owner, opponent, target_id: String, value: int) -> void:
	var players: Array = []
	match target_id:
		"T04": players = [opponent]
		"T05": players = [owner]
		"T06": players = [owner, opponent]
		_: players = [owner, opponent]
	for p in players:
		for i in range(p.max_field_size):
			var c = p.field.get_slot(i)
			if c and c.is_alive():
				if value >= 0:
					c.add_buff("atk_up", value)
					c.add_buff("hp_up", value)
				else:
					c.take_damage(abs(value))
		p.cleanup_destroyed()


func _exec_swap_atk_hp(targets) -> void:
	if targets is Dictionary:
		for card in targets.get("cards", []):
			if card and card.is_alive():
				var tmp = card.current_atk
				card.current_atk = card.current_hp
				card.current_hp = tmp


func _exec_take_control_temp(owner, opponent, targets) -> void:
	if targets is Dictionary:
		for card in targets.get("cards", []):
			if card and card.is_alive():
				var orig_owner = targets.get("owner", opponent)
				var slot = card.slot_index
				owner.take_control_of(card, orig_owner, slot, true)
				print("[EffectNew] Take control temp: ", card.get_display_name())


func _exec_take_control_perm(owner, opponent, targets) -> void:
	if targets is Dictionary:
		for card in targets.get("cards", []):
			if card and card.is_alive():
				var orig_owner = targets.get("owner", opponent)
				var slot = card.slot_index
				owner.take_control_of(card, orig_owner, slot, false)
				print("[EffectNew] Take control perm: ", card.get_display_name())


func _exec_cannot_attack(targets) -> void:
	if targets is Dictionary:
		for card in targets.get("cards", []):
			if card and card.is_alive():
				card.cannot_attack = true


func _exec_change_form(targets) -> void:
	if targets is Dictionary:
		for card in targets.get("cards", []):
			if card and card.is_alive():
				card.is_turned = not card.is_turned


func _exec_negate_and_destroy(owner, opponent, target_id: String) -> void:
	if not _chain_stack.is_empty():
		_chain_stack[-1].negated = true
		print("[EffectNew] Chain#", _chain_stack[-1].chain_id, " negated!")
		var negated_link = _chain_stack[-1]
		var negated_card = negated_link.get("card", null)
		var negated_owner = negated_link.get("owner", null)
		if negated_card and negated_owner:
			_send_card_to_grave(negated_card, negated_owner)
			negated_owner.cleanup_destroyed()


func _exec_control_change(owner, opponent, targets, temporary: bool) -> void:
	if targets is Dictionary:
		for card in targets.get("cards", []):
			if card and card.is_alive():
				var orig_owner = targets.get("owner", opponent)
				var slot = card.slot_index
				owner.take_control_of(card, orig_owner, slot, temporary)
				print("[EffectNew] Control change (", "temp" if temporary else "perm", "): ", card.get_display_name())


func _exec_disable_effect(targets) -> void:
	if targets is Dictionary:
		for card in targets.get("cards", []):
			if card and card.is_alive():
				card.effect_disabled = true


# ============================================================
#  辅助方法
# ============================================================

func _get_opponent_of(player):
	return _game.player_opp if player == _game.player_self else _game.player_self

func _pick_random_field_card(player):
	var alive: Array = []
	for i in range(player.max_field_size):
		var c = player.field.get_slot(i)
		if c != null and c.is_alive():
			alive.append(c)
	if alive.is_empty():
		return null
	return alive[randi() % alive.size()]

func _pick_extreme_card(player, highest: bool):
	var best = null
	for i in range(player.max_field_size):
		var c = player.field.get_slot(i)
		if c == null or not c.is_alive():
			continue
		if best == null:
			best = c
			continue
		if highest:
			if c.current_atk > best.current_atk:
				best = c
		else:
			if c.current_atk < best.current_atk:
				best = c
	if best != null:
		return {"type": "card", "cards": [best], "slot": best.slot_index, "owner": player}
	return null

func _get_all_field_cards(player) -> Array:
	var result: Array = []
	for i in range(player.max_field_size):
		var c = player.field.get_slot(i)
		if c != null and c.is_alive():
			result.append(c)
	return result

func _get_target_info(targets, target_id: String, is_player: bool) -> Dictionary:
	if targets is Dictionary:
		var t_type = targets.get("type", "")
		match t_type:
			"hero":
				var tp = targets.get("target_player")
				return {"name": tp.player_name + "(英雄)", "slot": -1, "is_player": (tp == _game.player_self)}
			"card":
				var cards = targets.get("cards", [])
				if cards.size() > 0:
					var c = cards[0]
					return {"name": c.get_display_name() if c else "?", "slot": targets.get("slot", -1), "is_player": (targets.get("owner") == _game.player_self)}
				return {"name": "?", "slot": -1, "is_player": is_player}
			"cards":
				return {"name": "全体", "slot": -1, "is_player": is_player}
			"player":
				return {"name": "己方", "slot": -1, "is_player": is_player}
	return {"name": "?", "slot": -1, "is_player": is_player}

func _send_card_to_grave(card, owner) -> void:
	# 保存old_slot在reset之前（→ 规避Bug#4）
	var old_slot = card.slot_index
	_remove_card_from_field(owner, card)
	card.reset_for_leave_field()
	owner.grave.add(card)
	owner.grave_changed.emit()
	# 亡语触发：传入正确的old_slot
	_game._trigger_system.on_card_sent_to_grave(owner, card, old_slot)

func _send_card_to_banish(card, owner) -> void:
	var old_slot = card.slot_index
	_remove_card_from_field(owner, card)
	card.reset_for_leave_field()
	owner.banished.add(card)
	owner.banish_changed.emit()
	_game._trigger_system.on_card_banished(owner, card, old_slot)

func _remove_card_from_field(owner, card) -> void:
	for i in range(owner.max_field_size):
		if owner.field.get_slot(i) == card:
			owner.field.set_slot(i, null)
			owner.field_changed.emit()
			return

func _find_chainable_cards(player) -> Array:
	# 委托给TriggerSystemNew的注册表查找（→ 规避Bug#6）
	return _game._trigger_system.find_chainable_cards(player)
