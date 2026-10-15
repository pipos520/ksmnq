extends RefCounted
class_name TriggerSystemNew

## ============================================================
##  TriggerSystemNew.gd — 触发器注册表 + 事件分发
##  核心改进（规避旧系统Bug#6）：
##    1. 注册表机制：卡牌上场时注册触发器，不再全量扫描
##    2. 优先级队列：多张卡同时触发时按priority排序，顺序确定
##    3. 快照机制：触发时冻结目标列表（与EffectSystemNew一致）
##    4. 事件枚举：TR01~TR18全覆盖，语义清晰
## ============================================================

# ===== 触发器类型枚举 =====
enum TriggerType {
	TR01,  # 召唤时（自身上场）
	TR02,  # 特殊召唤成功时（扫描方）
	TR03,  # 从墓地特殊召唤时
	TR04,  # 被破坏时（走连锁）
	TR05,  # 被除外时
	TR06,  # 被送去墓地时（亡语，只触发自身）
	TR07,  # 被除外时（扫描方，兼容旧版）
	TR08,  # 离开场上时（弹回/除外/破坏通用）
	TR09,  # 攻击宣言时（攻击方自身）
	TR10,  # 被攻击时（防御方自身）
	TR11,  # 给予战斗伤害时（攻击方自身）
	TR12,  # 己方回合开始时（周期）
	TR13,  # 对方回合开始时（扫描对方）
	TR14,  # 己方回合结束时（周期）
	TR15,  # 对方回合结束时（扫描对方）
	TR16,  # 对方发动效果时（反制连锁）
	TR17,  # 对方召唤成功时（扫描对方）
	TR18,  # 控制权转移时（扫描双方）
}

# ===== 注册表条目 =====
# 结构: { card, trigger, effect, slot, owner, priority }
# priority: 数值越小越先触发（默认100）
var _registry: Array = []

# ===== 游戏引用 =====
var _game = null       # BattleGameNew
var _effect_sys = null  # EffectSystemNew

# ===== 触发锁（防止递归触发） =====
var _trigger_depth: int = 0
const MAX_TRIGGER_DEPTH: int = 20  # 安全上限


# ===== 初始化 =====
func init(game, effect_sys) -> void:
	_game = game
	_effect_sys = effect_sys


# ============================================================
#  注册 / 注销
# ============================================================

## 卡牌上场时注册其所有触发器
func register_card(card, owner, slot: int) -> void:
	if card == null or owner == null:
		return
	if card.effect_disabled:
		return
	for effect in card.effects:
		var parsed = Global.parse_circuit(effect)
		if not parsed.is_valid:
			continue
		var trig = parsed.get("trigger", "")
		if trig == "":
			continue
		# 优先级：周期触发器(TR12~TR15)优先级50，反制(TR16)优先级200，其余100
		var priority = 100
		if trig in ["TR12", "TR13", "TR14", "TR15"]:
			priority = 50
		elif trig == "TR16":
			priority = 200
		_registry.append({
			"card": card,
			"trigger": trig,
			"effect": effect,
			"slot": slot,
			"owner": owner,
			"priority": priority
		})
	print("[TriggerNew] Registered triggers for ", card.get_display_name(), " (", _count_card_triggers(card), " triggers)")


## 卡牌离场时注销其所有触发器
func unregister_card(card) -> void:
	var i = _registry.size() - 1
	while i >= 0:
		if _registry[i].card == card:
			_registry.remove_at(i)
		i -= 1


## 清空注册表（战斗结束时调用）
func clear() -> void:
	_registry.clear()
	_trigger_depth = 0


# ============================================================
#  事件分发（核心接口）
# ============================================================

## 扫描触发：扫描某方场上所有匹配的触发器
## trigger_id: "TR01"~"TR18"
## player: 要扫描的玩家
## context: 额外上下文（如 { "target_card": card, "old_slot": slot }）
func scan_and_trigger(trigger_id: String, player, context: Dictionary = {}) -> void:
	if _trigger_depth >= MAX_TRIGGER_DEPTH:
		print("[TriggerNew] ⚠️ Max trigger depth reached, aborting")
		return
	_trigger_depth += 1
	
	var opponent = _get_opponent_of(player)
	
	# 收集匹配的触发器（快照 → 规避Bug#3）
	var matched: Array = []
	for entry in _registry:
		if entry.owner != player:
			continue
		if entry.trigger != trigger_id:
			continue
		var card = entry.card
		if card == null or not card.is_alive():
			continue
		if card.effect_disabled:
			continue
		# 条件检查
		var parsed = Global.parse_circuit(entry.effect)
		var can_trigger = true
		for condition in parsed.conditions:
			if not Global.check_condition(condition, player, opponent, card):
				can_trigger = false
				break
		if can_trigger:
			matched.append(entry.duplicate())
	
	# 按优先级排序（数值越小越先执行）
	matched.sort_custom(func(a, b): return a.priority < b.priority)
	
	# 逐个通过EffectSystem执行（走连锁系统）
	for entry in matched:
		_effect_sys.execute_effect(entry.owner, entry.card, entry.effect, entry.slot)
	
	_trigger_depth -= 1


## 单卡触发：只触发指定卡牌的指定触发器
## 用于 TR09/TR10（攻击宣言）、TR06（亡语）等只应由具体卡触发的效果
func trigger_single(trigger_id: String, owner, card, slot: int, context: Dictionary = {}) -> void:
	if _trigger_depth >= MAX_TRIGGER_DEPTH:
		print("[TriggerNew] ⚠️ Max trigger depth reached, aborting")
		return
	_trigger_depth += 1
	
	if card == null:
		_trigger_depth -= 1
		return
	if not card.is_alive() and trigger_id != "TR06" and trigger_id != "TR04":
		_trigger_depth -= 1
		return
	if card.effect_disabled:
		_trigger_depth -= 1
		return
	
	var opponent = _get_opponent_of(owner)
	
	# 直接遍历这张卡的effects（不查注册表，因为可能刚上场还没注册）
	for effect in card.effects:
		var parsed = Global.parse_circuit(effect)
		if not parsed.is_valid:
			continue
		if parsed.get("trigger", "") != trigger_id:
			continue
		# 条件检查
		var can_trigger = true
		for condition in parsed.conditions:
			if not Global.check_condition(condition, owner, opponent, card):
				can_trigger = false
				break
		if can_trigger:
			_effect_sys.execute_effect(owner, card, effect, slot)
	
	_trigger_depth -= 1


## 亡语触发：卡牌被送入墓地时触发TR06
## owner: 卡牌的持有者
## card: 被送墓的卡牌
## old_slot: 卡牌在场上时的槽位（→ 规避Bug#4）
func on_card_sent_to_grave(owner, card, old_slot: int) -> void:
	if card == null:
		return
	# TR06: 被送去墓地时（只触发自身，不扫描全场）
	trigger_single("TR06", owner, card, old_slot, {})
	# TR08: 离开场上时（扫描全场）
	scan_and_trigger("TR08", owner)
	# 注销该卡的触发器
	unregister_card(card)


## 被除外时触发
func on_card_banished(owner, card, old_slot: int) -> void:
	if card == null:
		return
	trigger_single("TR05", owner, card, old_slot)
	scan_and_trigger("TR07", owner)
	scan_and_trigger("TR08", owner)
	unregister_card(card)


## 被弹回时触发
func on_card_bounced(owner, card, old_slot: int) -> void:
	if card == null:
		return
	scan_and_trigger("TR08", owner)
	unregister_card(card)


## 召唤成功时触发
func on_card_summoned(owner, card, slot: int, is_special: bool) -> void:
	if card == null:
		return
	# 注册该卡的所有触发器
	register_card(card, owner, slot)
	# TR01: 召唤时（自身）
	trigger_single("TR01", owner, card, slot)
	if is_special:
		# TR02: 特殊召唤成功时（扫描方）
		scan_and_trigger("TR02", owner)
		# TR03: 从墓地特殊召唤（检查卡牌来源）
		trigger_single("TR03", owner, card, slot)
	# TR17: 对方召唤成功时（扫描对方场上）
	var opponent = _get_opponent_of(owner)
	scan_and_trigger("TR17", opponent)


## 攻击宣言时触发
func on_attack_declared(attacker_owner, attacker_card, attacker_slot: int) -> void:
	# TR09: 攻击方自身
	trigger_single("TR09", attacker_owner, attacker_card, attacker_slot)


## 被攻击时触发
func on_attack_targeted(defender_owner, defender_card, defender_slot: int) -> void:
	# TR10: 防御方自身
	trigger_single("TR10", defender_owner, defender_card, defender_slot)


## 给予战斗伤害时触发
func on_battle_damage_dealt(attacker_owner, attacker_card, attacker_slot: int, damage: int) -> void:
	# TR11: 攻击方自身
	trigger_single("TR11", attacker_owner, attacker_card, attacker_slot)


## 回合开始时触发
func on_turn_start(player) -> void:
	# TR12: 己方回合开始
	scan_and_trigger("TR12", player)
	# TR13: 对方回合开始（扫描对方）
	var opponent = _get_opponent_of(player)
	scan_and_trigger("TR13", opponent)


## 回合结束时触发
func on_turn_end(player) -> void:
	# TR14: 己方回合结束
	scan_and_trigger("TR14", player)
	# TR15: 对方回合结束
	var opponent = _get_opponent_of(player)
	scan_and_trigger("TR15", opponent)


## 效果发动时触发（反制连锁）
func on_effect_activated(owner, card, effect: Dictionary, slot: int) -> void:
	# TR16: 对方发动效果时（扫描对方场上）
	var opponent = _get_opponent_of(owner)
	scan_and_trigger("TR16", opponent, {"source_card": card, "source_effect": effect})


## 控制权转移时触发
func on_control_changed(owner, opponent) -> void:
	# TR18: 控制权转移时（扫描双方场上）
	scan_and_trigger("TR18", owner)
	scan_and_trigger("TR18", opponent)


# ============================================================
#  辅助方法
# ============================================================

func _get_opponent_of(player):
	return _game.player_opp if player == _game.player_self else _game.player_self

func _count_card_triggers(card) -> int:
	var count = 0
	for effect in card.effects:
		var parsed = Global.parse_circuit(effect)
		if parsed.is_valid and parsed.get("trigger", "") != "":
			count += 1
	return count

## 查找可连锁的卡牌（TR16触发器，用于EffectSystem的连锁构建）
func find_chainable_cards(player) -> Array:
	var result: Array = []
	for entry in _registry:
		if entry.owner != player:
			continue
		if entry.trigger != "TR16":
			continue
		var card = entry.card
		if card == null or not card.is_alive():
			continue
		if card.effect_disabled:
			continue
		result.append({
			"card": card,
			"effect": entry.effect,
			"slot": entry.slot,
			"owner": player
		})
	return result

## 获取注册表快照（调试用）
func get_registry_snapshot() -> Array:
	return _registry.duplicate(true)
