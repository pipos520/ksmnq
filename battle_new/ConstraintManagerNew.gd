extends RefCounted
class_name ConstraintManagerNew

## ============================================================
##  ConstraintManagerNew.gd — 约束检查 + 代价支付
##  CO01~CO16全覆盖，统一前置检查+后置处理
##  前置检查: can_activate() → 返回bool
##  后置处理: after_activation() → 执行代价（扣血/弃牌/除外等）
## ============================================================

# ===== 游戏引用 =====
var _game = null       # BattleGameNew

# ===== 一回合一次（CO01） =====
var _used_once_per_turn: Dictionary = {}  # card_id -> bool

# ===== 一局一次（CO02） =====
var _used_once_per_game: Dictionary = {}  # card_id -> bool

# ===== 效果发动次数计数（CO14用） =====
var _effect_count: int = 0


# ===== 初始化 =====
func init(game) -> void:
	_game = game


## 清空回合相关约束（回合开始时调用）
func reset_turn_constraints() -> void:
	_used_once_per_turn.clear()
	_effect_count = 0


## 完全清理（战斗结束时调用）
func clear() -> void:
	_used_once_per_turn.clear()
	_used_once_per_game.clear()
	_effect_count = 0


# ============================================================
#  前置检查：效果是否允许发动
# ============================================================

## 检查约束是否允许发动效果
## 返回: true=允许, false=阻止
func can_activate(owner, opponent, card, effect: Dictionary, parsed: Dictionary) -> bool:
	for constraint_id in parsed.constraints:
		match constraint_id:
			"CO01":  # 一回合一次
				var cid = card.card_id
				if _used_once_per_turn.get(cid, false):
					print("[ConstraintNew] CO01 一回合一次: ", card.get_display_name(), " 本回合已用过")
					return false
			"CO02":  # 一局一次
				var cid2 = card.card_id
				if _used_once_per_game.get(cid2, false):
					print("[ConstraintNew] CO02 一局一次: ", card.get_display_name(), " 本局已用过")
					return false
			"CO03":  # 支付生命（前置检查：HP是否足够）
				var hp_cost = Global.get_constraint_param(effect, "CO03", 10)
				if owner.hp < hp_cost:
					print("[ConstraintNew] CO03 支付生命: 生命不足, 需要", hp_cost, " 当前", owner.hp)
					return false
			"CO04":  # 舍弃手牌（前置检查：手牌是否足够）
				var discard_count = Global.get_constraint_param(effect, "CO04", 1)
				if owner.hand.size() < discard_count:
					print("[ConstraintNew] CO04 舍弃手牌: 手牌不足, 需要", discard_count, " 当前", owner.hand.size())
					return false
			"CO05":  # 消耗能量点（前置检查：能量是否足够）
				var energy_cost = Global.get_constraint_param(effect, "CO05", 1)
				if owner.energy < energy_cost:
					print("[ConstraintNew] CO05 消耗能量: 能量不足, 需要", energy_cost, " 当前", owner.energy)
					return false
			"CO08":  # 场上有N张以上卡
				var min_count = Global.get_constraint_param(effect, "CO08", 1)
				if owner.get_field_count() < min_count:
					return false
			"CO09":  # 对方场上有N张以上卡
				var min_count2 = Global.get_constraint_param(effect, "CO09", 1)
				if opponent.get_field_count() < min_count2:
					return false
			"CO10":  # 己方HP低于N
				var min_hp = Global.get_constraint_param(effect, "CO10", 50)
				if owner.hp > min_hp:
					return false
			"CO11":  # 己方能量达到N
				var min_energy = Global.get_constraint_param(effect, "CO11", 3)
				if owner.energy < min_energy:
					return false
			"CO14":  # 本回合效果发动次数限制
				var max_uses = Global.get_constraint_param(effect, "CO14", 1)
				if _effect_count >= max_uses:
					return false
			"CO15":  # 仅对克制属性生效
				var check_elem = Global.get_constraint_param_str(effect, "CO15", "")
				if check_elem != "":
					var card_elem = card.get_effective_element()
					var affinity = Global.get_element_affinity(card_elem, check_elem)
					if affinity <= 1.0:
						return false
			"CO16":  # 仅对被克制属性生效
				var check_elem2 = Global.get_constraint_param_str(effect, "CO16", "")
				if check_elem2 != "":
					var card_elem2 = card.get_effective_element()
					var affinity2 = Global.get_element_affinity(check_elem2, card_elem2)
					if affinity2 <= 1.0:
						return false
	return true


# ============================================================
#  后置处理：效果发动后执行代价
# ============================================================

## 效果发动后处理约束代价
## 返回: 是否需要异步等待（如CO04弃牌需要等UI回调）
func after_activation(owner, opponent, card, effect: Dictionary, parsed: Dictionary) -> bool:
	# 标记已使用
	for constraint_id in parsed.constraints:
		match constraint_id:
			"CO01":  # 标记一回合一次
				_used_once_per_turn[card.card_id] = true
				print("[ConstraintNew] CO01 标记: ", card.get_display_name(), " 本回合已用")
			"CO02":  # 标记一局一次
				_used_once_per_game[card.card_id] = true
				print("[ConstraintNew] CO02 标记: ", card.get_display_name(), " 本局已用")
			"CO03":  # 支付生命
				var hp_cost = Global.get_constraint_param(effect, "CO03", 10)
				owner.hp = max(0, owner.hp - hp_cost)
				owner.hp_changed.emit(owner.hp + hp_cost, owner.hp)
				print("[ConstraintNew] CO03 支付生命: -", hp_cost, " HP(", owner.hp, "/", owner.max_hp, ")")
			"CO05":  # 消耗能量点
				var energy_cost = Global.get_constraint_param(effect, "CO05", 1)
				owner.energy = max(0, owner.energy - energy_cost)
				owner.energy_changed.emit(owner.energy + energy_cost, owner.energy)
				print("[ConstraintNew] CO05 消耗能量: -", energy_cost, " 能量(", owner.energy, "/", owner.max_energy, ")")
			"CO06":  # 发动后除外（将自身除外）
				_game._effect_system._send_card_to_banish(card, owner)
				owner.cleanup_destroyed()
				print("[ConstraintNew] CO06 发动后除外: ", card.get_display_name())
			"CO07":  # 效果后自毁（送入墓地）
				_game._effect_system._send_card_to_grave(card, owner)
				owner.cleanup_destroyed()
				print("[ConstraintNew] CO07 效果后自毁: ", card.get_display_name())
			"CO12":  # 发动后受伤害
				var damage = Global.get_constraint_param(effect, "CO12", 5)
				owner.hp = max(0, owner.hp - damage)
				owner.hp_changed.emit(owner.hp + damage, owner.hp)
				print("[ConstraintNew] CO12 发动后受伤害: -", damage, " HP(", owner.hp, "/", owner.max_hp, ")")
			"CO14":  # 效果发动次数计数
				_effect_count += 1
	
	# CO04 弃牌需要异步等待
	if parsed.constraints.has("CO04"):
		var discard_count = Global.get_constraint_param(effect, "CO04", 1)
		if discard_count > 0 and owner.hand.size() >= discard_count:
			_game._discard_counter += 1
			var cb_id = _game._discard_counter
			var owner_idx = 0 if owner == _game.player_self else 1
			_game._discard_callbacks[cb_id] = {
				"owner": owner,
				"count": discard_count,
				"reason": "CO04"
			}
			if _game._controllers.size() > owner_idx and _game._controllers[owner_idx] != null:
				_game._controllers[owner_idx].on_discard_requested(discard_count, cb_id, "CO04")
			else:
				# 无Controller，自动弃牌
				_auto_discard(cb_id)
			return true  # 需要异步等待
	
	# CO03 生命不足时自损检查
	if owner.hp <= 0:
		_game._check_win_condition()
	
	return false  # 不需要异步等待


## 自动弃牌（无Controller时调用）
func _auto_discard(cb_id: int) -> void:
	var cb = _game._discard_callbacks.get(cb_id, {})
	var owner = cb.get("owner", null)
	var count = cb.get("count", 0)
	if owner == null:
		return
	for i in range(count):
		if owner.hand.is_empty():
			break
		# 弃掉最不重要的卡（随机或最低cost）
		owner.hand.remove_at(randi() % owner.hand.size())
	owner.hand_changed.emit()
	_game._discard_callbacks.erase(cb_id)
	print("[ConstraintNew] Auto discard: ", count, " cards")


## 检查卡牌召唤约束（AI召唤前检查CO03/CO04）
func can_summon(owner, card) -> bool:
	for effect in card.effects:
		var parsed = Global.parse_circuit(effect)
		if not parsed.is_valid:
			continue
		for constraint_id in parsed.constraints:
			match constraint_id:
				"CO03":
					var hp_cost = Global.get_constraint_param(effect, "CO03", 10)
					if owner.hp < hp_cost:
						return false
				"CO04":
					var discard_count = Global.get_constraint_param(effect, "CO04", 1)
					if owner.hand.size() < discard_count:
						return false
	return true