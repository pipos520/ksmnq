extends RefCounted
class_name BattleGameNew

## ============================================================
##  BattleGameNew.gd — 核心调度器
##  回合阶段流 + 胜负判定 + 信号总线
##  不碰UI，不含AI，不解析效果
##  通过IBattleControllerNew与玩家/AI交互
## ============================================================

# ===== 阶段枚举 =====
enum Phase { NONE, DRAW, READY, MAIN, BATTLE, END, DISCARD }
enum State { PLAYING, WON, LOST, DRAW }
enum PlayerIdx { PLAYER = 0, OPPONENT = 1 }

# ===== 信号总线（UI监听这些） =====
signal phase_changed(phase: int, player_idx: int)
signal turn_changed(turn_count: int)
signal battle_ended(result: int)
signal hp_changed(is_player: bool, old_hp: int, new_hp: int, max_hp: int)
signal energy_changed(is_player: bool, old_val: int, new_val: int, max_val: int)
signal hand_changed(is_player: bool)
signal field_changed(is_player: bool)
signal grave_changed(is_player: bool)
signal deck_count_changed(is_player: bool, remaining: int)
signal banish_changed(is_player: bool)
signal action_result(action_type: String, success: bool, data: Dictionary)
signal info_message(text: String)
# 需要Controller做选择的信号
signal discard_requested(count: int, callback_id: int, reason: String)
signal deck_search_requested(cards: Array, max_select: int, callback_id: int)
signal chain_requested(callback_id: int, chainable_cards: Array)
# 特效信号
signal effect_triggered(action_type: String, value: int, is_player: bool, source_slot: int, desc: String)
signal card_effect_activated(card_name: String, effect_desc: String, action_type: String, target_id: String, value: int, target_card_name: String, source_slot: int, is_player: bool, target_slot: int, target_is_player: bool)

# ===== 玩家 =====
var player_self: BattlePlayerNew = null
var player_opp: BattlePlayerNew = null

# ===== Controller =====
var _controllers: Array = []  # [IBattleControllerNew, IBattleControllerNew]

# ===== 回合状态 =====
var current_player_idx: int = 0
var current_phase: Phase = Phase.NONE
var turn_count: int = 0
var battle_state: State = State.PLAYING
var _is_first_turn: bool = true

# ===== 子系统 =====
var _effect_system = null    # EffectSystemNew
var _trigger_system = null   # TriggerSystemNew
var _constraint_mgr = null   # ConstraintManagerNew
var _action_queue: ActionQueueNew = null

# ===== 回调映射 =====
var _discard_callbacks: Dictionary = {}
var _discard_counter: int = 0
var _search_callbacks: Dictionary = {}
var _search_counter: int = 0
var _chain_callbacks: Dictionary = {}
var _chain_counter: int = 0


# ===== 初始化 =====
func init() -> void:
	_action_queue = ActionQueueNew.new()
	_effect_system = EffectSystemNew.new()
	_effect_system.init(self)
	_trigger_system = TriggerSystemNew.new()
	_trigger_system.init(self, _effect_system)
	_constraint_mgr = ConstraintManagerNew.new()
	_constraint_mgr.init(self)

func set_controllers(player_ctrl, ai_ctrl) -> void:
	_controllers = [player_ctrl, ai_ctrl]


# ===== 开始战斗 =====
func start_battle(deck_id: String, enemy_data: Dictionary) -> void:
	# === 创建己方 ===
	player_self = BattlePlayerNew.new()
	player_self.player_name = "卡师"
	player_self.max_energy = 3
	player_self.energy = 3
	var guild_max_hp = PlayerManager.get_guild_max_hp()
	player_self.max_hp = guild_max_hp
	if Global.current_run_player_hp > 0:
		player_self.hp = Global.current_run_player_hp
	else:
		player_self.hp = guild_max_hp
	player_self.init_from_deck(deck_id, false, true)
	
	# === 创建敌方 ===
	if enemy_data.size() > 0 and (enemy_data.get("deck", []).size() > 0 or enemy_data.get("card_datas", []).size() > 0):
		var en_name = enemy_data.get("name", "暗影法师")
		var en_hp = enemy_data.get("hp", 100)
		var en_max_hp = enemy_data.get("max_hp", 100)
		var en_energy = enemy_data.get("energy", 3)
		var en_max_energy = enemy_data.get("max_energy", 3)
		player_opp = BattlePlayerNew.new()
		player_opp.player_name = en_name
		player_opp.is_enemy = true
		player_opp.max_energy = en_max_energy
		player_opp.energy = en_energy
		player_opp.max_hp = en_max_hp
		player_opp.hp = en_hp
		var en_card_datas = enemy_data.get("card_datas", [])
		if en_card_datas.is_empty():
			for tid in enemy_data.get("deck", []):
				var tmpl = Global.get_enemy_card_template(tid)
				if tmpl.size() > 0:
					en_card_datas.append(tmpl.duplicate(true))
		player_opp.init_from_card_datas(en_card_datas, true, false)
	else:
		# 默认敌方（从卡组池随机选）
		player_opp = BattlePlayerNew.new()
		player_opp.player_name = "暗影法师"
		player_opp.is_enemy = true
		player_opp.max_energy = 3
		player_opp.energy = 3
		player_opp.max_hp = 100
		player_opp.hp = 100
		var ai_decks = Global.server_decks if Global.server_decks != null else []
		var ai_cards: Array = []
		if not ai_decks.is_empty():
			var picked = ai_decks[randi() % ai_decks.size()]
			ai_cards = picked.get("deck_data", {}).get("card_datas", [])
		if ai_cards.is_empty():
			# 回退到玩家卡组
			var all_cards = CardManager.get_all_cards()
			for cd in all_cards:
				ai_cards.append(cd.duplicate())
		player_opp.init_from_card_datas(ai_cards, true, false)
	
	# === 初始抽牌 ===
	player_self.init_draw(5)
	player_opp.init_draw(5)
	
	# === 连接信号 ===
	_connect_player_signals(player_self, false)
	_connect_player_signals(player_opp, true)
	
	# === 启动 ===
	_is_first_turn = true
	turn_count = 1
	current_player_idx = 0
	current_phase = Phase.NONE
	
	turn_changed.emit(turn_count)
	print("[BattleGameNew] ===== 战斗开始 =====")
	print("[BattleGameNew] 己方: 手牌", player_self.hand.size(), " 能量", player_self.energy, "/", player_self.max_energy)
	print("[BattleGameNew] 敌方: 手牌", player_opp.hand.size(), " 能量", player_opp.energy, "/", player_opp.max_energy)
	
	# 检查敌方是否完全无战斗力
	if player_opp.deck.is_empty() and player_opp.hand.is_empty() and player_opp.get_field_count() == 0:
		battle_state = State.WON
		battle_ended.emit(State.WON)
		return
	
	# 进入第一回合
	_enter_phase(Phase.DRAW)


# ===== 信号连接 =====
func _connect_player_signals(player: BattlePlayerNew, is_enemy: bool) -> void:
	player.hp_changed.connect(func(old, new): hp_changed.emit(not is_enemy, old, new, player.max_hp))
	player.energy_changed.connect(func(old, new): energy_changed.emit(not is_enemy, old, new, player.max_energy))
	player.hand_changed.connect(func(): hand_changed.emit(not is_enemy))
	player.field_changed.connect(func(): field_changed.emit(not is_enemy))
	player.grave_changed.connect(func(): grave_changed.emit(not is_enemy))
	player.deck_count_changed.connect(func(): deck_count_changed.emit(not is_enemy, player.deck.size()))
	player.banish_changed.connect(func(): banish_changed.emit(not is_enemy))


# ===== 阶段流 =====
func _enter_phase(phase: Phase) -> void:
	current_phase = phase
	phase_changed.emit(phase, current_player_idx)
	
	match phase:
		Phase.DRAW:
			_exec_draw()
			_enter_phase(Phase.READY)
		Phase.READY:
			_exec_ready()
			current_phase = Phase.MAIN
			phase_changed.emit(Phase.MAIN, current_player_idx)
			_yield_to_controller()
		Phase.MAIN:
			phase_changed.emit(Phase.MAIN, current_player_idx)
			_yield_to_controller()
		Phase.BATTLE:
			phase_changed.emit(Phase.BATTLE, current_player_idx)
			_yield_to_controller()
		Phase.END:
			_exec_end()
			# 手牌超限检查
			var p = _get_current_player()
			if p.hand.size() > 6:
				_enter_phase(Phase.DISCARD)
			else:
				_switch_turn()
		Phase.DISCARD:
			var p2 = _get_current_player()
			var need = p2.hand.size() - 6
			if need > 0:
				_request_discard(p2, need, "end_phase", func(): _switch_turn())
			else:
				_switch_turn()

func _exec_draw() -> void:
	var p = _get_current_player()
	if _is_first_turn and current_player_idx == 0:
		_is_first_turn = false
		p.is_first_turn = false
		print("[BattleGameNew] 先手第一回合，跳过抽牌")
		return
	_is_first_turn = false
	var card = p.draw_phase()
	if card:
		print("[BattleGameNew] 抽牌: ", p.player_name, " → ", card.get_display_name())
	_check_win_condition()

func _exec_ready() -> void:
	var p = _get_current_player()
	var opp = _get_opponent()
	# 能量上限+1（第3回合起）
	if turn_count > 2:
		if p.max_energy < 10:
			p.max_energy += 1
	p.energy = p.max_energy
	p.energy_changed.emit(p.energy, p.max_energy)
	p.ready_phase()
	# 触发周期效果 TR12/TR13
	_trigger_system.on_turn_start(p)
	_reset_turn_constraints()
	p.cleanup_destroyed()
	print("[BattleGameNew] 准备: ", p.player_name, " 能量", p.energy, "/", p.max_energy)

func _exec_end() -> void:
	var p = _get_current_player()
	var opp = _get_opponent()
	p.return_taken_control()
	opp.return_taken_control()
	# 触发 TR14/TR15
	_trigger_system.on_turn_end(p)
	# TODO: 中毒结算（后续特性扩展）
	# _resolve_poison(p)
	p.end_phase()
	print("[BattleGameNew] 结束: ", p.player_name, " 手牌", p.hand.size(), " 墓地", p.grave.size())

func _switch_turn() -> void:
	current_player_idx = 1 if current_player_idx == 0 else 0
	turn_count += 1
	turn_changed.emit(turn_count)
	print("[BattleGameNew] ===== 第", turn_count, "回合 — ", _get_current_player().player_name, " =====")
	_enter_phase(Phase.DRAW)

func _yield_to_controller() -> void:
	# 通知当前Controller：该你操作了
	if _controllers.size() > current_player_idx and _controllers[current_player_idx] != null:
		_controllers[current_player_idx].on_phase_enter(current_phase)


# ===== Controller 调用的操作接口（AI和玩家走相同路径！）=====
func request_play_card(hand_idx: int, slot_idx: int) -> bool:
	var p = _get_current_player()
	if current_phase not in [Phase.MAIN, Phase.READY]:
		action_result.emit("summon", false, {"reason": "非主要阶段"})
		return false
	var ok = p.summon_from_hand(hand_idx, slot_idx)
	if ok:
		var card = p.field.get_slot(slot_idx)
		print("[BattleGameNew] 召唤: ", card.get_display_name(), " → 槽位", slot_idx)
		action_result.emit("summon", true, {"card": card, "slot": slot_idx, "is_enemy": p.is_enemy})
		# 召唤时效果触发
		_trigger_system.on_card_summoned(p, card, slot_idx, false)
		_check_win_condition()
	else:
		action_result.emit("summon", false, {"reason": "召唤失败"})
	return ok

func request_attack(atk_slot: int, def_slot: int) -> bool:
	var p = _get_current_player()
	var opp = _get_opponent()
	if current_phase != Phase.BATTLE:
		action_result.emit("attack", false, {"reason": "非战斗阶段"})
		return false
	var attacker = p.field.get_slot(atk_slot)
	var defender = opp.field.get_slot(def_slot)
	if attacker == null or defender == null:
		action_result.emit("attack", false, {"reason": "攻击者或防御者不存在"})
		return false
	var result = p.attack(atk_slot, defender)
	if result.success:
		print("[BattleGameNew] 攻击: ", attacker.get_display_name(), " → ", defender.get_display_name())
		action_result.emit("attack", true, result)
		# 触发攻击相关效果
		_trigger_system.on_attack_declared(p, attacker, atk_slot)
		_trigger_system.on_attack_targeted(opp, defender, def_slot)
		# 清理阵亡
		p.cleanup_destroyed()
		opp.cleanup_destroyed()
		# 触发伤害效果
		if result.get("damage_to_defender", 0) > 0:
			_trigger_system.on_battle_damage_dealt(p, attacker, atk_slot, result.damage_to_defender)
		_check_win_condition()
	else:
		action_result.emit("attack", false, result)
	return result.success

func request_attack_hero(atk_slot: int) -> bool:
	var p = _get_current_player()
	var opp = _get_opponent()
	if current_phase != Phase.BATTLE:
		action_result.emit("attack_hero", false, {"reason": "非战斗阶段"})
		return false
	var result = p.attack_hero(atk_slot, opp.hp, opp)
	if result.success:
		opp.hp = result.new_hp
		opp.hp_changed.emit(opp.hp + result.damage, opp.hp)
		print("[BattleGameNew] 直击: ", result.damage, " → ", opp.player_name, " HP:", opp.hp)
		action_result.emit("attack_hero", true, result)
		_check_win_condition()
	else:
		action_result.emit("attack_hero", false, result)
	return result.success

func request_enter_battle() -> void:
	if current_phase == Phase.MAIN:
		_enter_phase(Phase.BATTLE)

func request_end_phase() -> void:
	if current_phase in [Phase.MAIN, Phase.BATTLE]:
		_enter_phase(Phase.END)


# ===== 弃牌/检索/连锁回调 =====
func request_select_discard(indices: Array) -> void:
	# Controller选择完弃牌后回调
	var p = _get_current_player()
	for idx in indices:
		if idx >= 0 and idx < p.hand.size():
			var card = p.hand[idx]
			p.grave.add(card)
			p.hand.remove_at(idx)
			# 调整后续索引
			for j in range(indices.size()):
				if indices[j] > idx:
					indices[j] -= 1
	p.hand_changed.emit()
	p.grave_changed.emit()
	# 执行回调
	for cb_id in _discard_callbacks.keys():
		var cb = _discard_callbacks[cb_id]
		var cb_func = cb.get("func", null)
		if cb_func is Callable:
			cb_func.call()
		_discard_callbacks.erase(cb_id)
		break
	print("[BattleGameNew] 弃牌完成: ", indices.size(), "张")


func request_deck_search_result(callback_id: int, selected: Array) -> void:
	var cb = _search_callbacks.get(callback_id, {})
	var owner = cb.get("owner", null)
	var candidates = cb.get("candidates", [])
	if owner:
		for idx in selected:
			if idx >= 0 and idx < candidates.size():
				var card_to_find = candidates[idx]
				owner.deck.search_and_remove(func(c): return c == card_to_find)
				owner.hand.add(card_to_find)
		owner.hand_changed.emit()
		owner.deck_count_changed.emit()
	_search_callbacks.erase(callback_id)
	print("[BattleGameNew] 检索完成: ", selected.size(), "张")


func request_chain_respond(accept: bool) -> void:
	_effect_system.respond_to_chain(accept)

func _request_discard(player: BattlePlayerNew, count: int, reason: String, callback: Callable) -> void:
	var cb_id = _discard_counter
	_discard_counter += 1
	_discard_callbacks[cb_id] = {"func": callback, "player": player, "count": count}
	if player == player_self:
		discard_requested.emit(count, cb_id, reason)
	else:
		# AI自动弃牌（由AI Controller处理）
		if _controllers.size() > 1 and _controllers[1] != null:
			_controllers[1].on_discard_requested(count, cb_id, reason)


# ===== 辅助 =====
func _get_current_player() -> BattlePlayerNew:
	return player_self if current_player_idx == 0 else player_opp

func _get_opponent() -> BattlePlayerNew:
	return player_opp if current_player_idx == 0 else player_self

func _reset_turn_constraints() -> void:
	_constraint_mgr.reset_turn_constraints()

func _check_win_condition() -> void:
	# HP <= 0 判负
	if player_self.hp <= 0:
		battle_state = State.LOST
		battle_ended.emit(State.LOST)
		print("[BattleGameNew]  己方HP归零，败北！")
		return
	if player_opp.hp <= 0:
		battle_state = State.WON
		battle_ended.emit(State.WON)
		print("[BattleGameNew]  敌方HP归零，胜利！")
		return
	# 卡组耗尽判负（卡组+手牌+场地全空）
	var loser = null
	if player_self.deck.is_empty() and player_self.hand.is_empty() and player_self.get_field_count() == 0:
		loser = player_self
	if player_opp.deck.is_empty() and player_opp.hand.is_empty() and player_opp.get_field_count() == 0:
		loser = player_opp
	if loser != null:
		if loser == player_self:
			battle_state = State.LOST
			battle_ended.emit(State.LOST)
		else:
			battle_state = State.WON
			battle_ended.emit(State.WON)