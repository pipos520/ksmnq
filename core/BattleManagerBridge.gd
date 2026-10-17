extends RefCounted

## BattleManagerBridge - 桥接层，包装 BattleGameNew 提供旧 BattleManager API
## 用于逐步迁移，保持现有代码无需修改

class_name BattleManagerBridge

# 信号（与旧 BattleManager 兼容）
signal phase_changed(phase, current_player_index: int)
signal turn_changed(turn_count: int)
signal battle_state_changed(state)
signal action_result(action_type: String, success: bool, data: Dictionary)
signal effect_triggered(action_type: String, value: int, is_player_side: bool, source_slot: int, desc: String)
signal deck_search_requested(cards: Array, max_select: int, callback_id: int)
signal discard_requested(count: int, callback_id: int, reason: String)
signal discard_animation_requested(callback_id: int, is_player_side: bool, discard_indices: Array)
signal chain_response_requested(callback_id: int)
signal chain_built(chain_count: int)
signal chain_resolved(link_id: int)
signal card_effect_activated(card_name: String, effect_desc: String, action_type: String, target_id: String, value: int, target_card_name: String, source_slot: int, is_player_side: bool, target_slot: int, target_is_player: bool, full_effect: Dictionary)
signal effect_line_fromto(from_slot: int, from_is_player: bool, to_slot: int, to_is_player: bool, action_type: String)
signal element_boost_triggered(boost_type: String, atk_elem: String, def_elem: String, from_value: int, to_value: int, is_player_side: bool, source_slot: int)
signal poison_tick_triggered(is_player_side: bool, source_slot: int, damage: int, stacks: int)
signal end_phase_effects_pending_discard(need_discard: int)

# 枚举（与旧 BattleManager 兼容）
enum Phase {
	NONE,
	MAIN,
	BATTLE,
	END
}

enum State {
	NONE,
	PLAYING,
	PAUSED,
	WON,
	LOST
}

# 新系统实例
var _game: Node = null
var _effect_system: Node = null
var _trigger_system: Node = null
var _constraint_manager: Node = null

# 旧系统兼容属性
var player_self: Node = null
var player_opponent: Node = null
var current_player_index: int = 0
var current_phase: int = Phase.NONE
var turn_count: int = 0
var battle_state: int = State.PLAYING
var ai_action_queue: Array = []
var ai_phase_completed: bool = false
var chain_stack: Array = []

func _init():
	pass

func initialize(game_node: Node, effect_system: Node, trigger_system: Node, constraint_manager: Node) -> void:
	_game = game_node
	_effect_system = effect_system
	_trigger_system = trigger_system
	_constraint_manager = constraint_manager
	_connect_signals()

func _connect_signals():
	if _game == null:
		return
	if _game.has_signal("phase_changed"):
		_game.phase_changed.connect(_on_phase_changed)
	if _game.has_signal("turn_changed"):
		_game.turn_changed.connect(_on_turn_changed)
	if _game.has_signal("battle_state_changed"):
		_game.battle_state_changed.connect(_on_battle_state_changed)

func _on_phase_changed(phase: int, player_index: int) -> void:
	current_phase = phase
	current_player_index = player_index
	if not phase_changed.get_connections().is_empty():
		var phase_name = "NONE"
		match phase:
			Phase.MAIN: phase_name = "MAIN"
			Phase.BATTLE: phase_name = "BATTLE"
			Phase.END: phase_name = "END"
		phase_changed.emit(phase_name, player_index)

func _on_turn_changed(turn: int) -> void:
	turn_count = turn
	if not turn_changed.get_connections().is_empty():
		turn_changed.emit(turn)

func _on_battle_state_changed(state: int) -> void:
	battle_state = state
	if not battle_state_changed.get_connections().is_empty():
		var state_name = "NONE"
		match state:
			State.PLAYING: state_name = "PLAYING"
			State.PAUSED: state_name = "PAUSED"
			State.WON: state_name = "WON"
			State.LOST: state_name = "LOST"
		battle_state_changed.emit(state_name)

func start_battle(deck_id: String, enemy_name: String = "暗影法师", auto_start: bool = true) -> void:
	if _game == null:
		return
	var enemy_data = _load_enemy_data(enemy_name)
	_game.start_battle(deck_id, enemy_data)
	if auto_start and _game.has_method("start_battle_auto"):
		_game.start_battle_auto()

func _load_enemy_data(enemy_name: String) -> Dictionary:
	var enemy = Global.get_enemy_by_plain_name(enemy_name)
	if enemy.is_empty():
		enemy = Global.get_enemy_by_name(enemy_name)
	if enemy.is_empty():
		return {}
	return {
		"id": enemy.get("id", enemy_name),
		"name": enemy.get("name", enemy_name),
		"level": enemy.get("level", 1),
		"hp": enemy.get("hp", 100),
		"max_hp": enemy.get("max_hp", enemy.get("hp", 100)),
		"energy": enemy.get("energy", 3),
		"max_energy": enemy.get("max_energy", enemy.get("energy", 3)),
		"element": enemy.get("element", ""),
		"desc": enemy.get("desc", ""),
		"aux_drops": enemy.get("aux_drops", []),
		"deck": enemy.get("deck", [])
	}

func get_phase_name() -> String:
	match current_phase:
		Phase.MAIN: return "MAIN"
		Phase.BATTLE: return "BATTLE"
		Phase.END: return "END"
		_: return "NONE"

func is_player_turn() -> bool:
	return current_player_index == 0

func proceed_to_discard_after_end_effects() -> void:
	if _game and _game.has_method("proceed_to_discard_after_end_effects"):
		_game.proceed_to_discard_after_end_effects()

func advance_enemy_phase() -> void:
	if _game and _game.has_method("advance_enemy_phase"):
		_game.advance_enemy_phase()

func request_play_card(hand_idx: int, slot_idx: int) -> bool:
	if _game and _game.has_method("request_play_card"):
		return _game.request_play_card(hand_idx, slot_idx)
	return false

func request_attack(atk_slot: int, def_slot: int) -> bool:
	if _game and _game.has_method("request_attack"):
		return _game.request_attack(atk_slot, def_slot)
	return false

func request_attack_hero(atk_slot: int) -> bool:
	if _game and _game.has_method("request_attack_hero"):
		return _game.request_attack_hero(atk_slot)
	return false

func request_enter_battle() -> void:
	if _game and _game.has_method("request_enter_battle"):
		_game.request_enter_battle()

func request_end_phase() -> void:
	if _game and _game.has_method("request_end_phase"):
		_game.request_end_phase()

func request_select_discard(indices: Array) -> void:
	if _game and _game.has_method("request_select_discard"):
		_game.request_select_discard(indices)

func request_deck_search_result(callback_id: int, selected: Array) -> void:
	if _game and _game.has_method("request_deck_search_result"):
		_game.request_deck_search_result(callback_id, selected)

func request_chain_respond(accept: bool) -> void:
	if _game and _game.has_method("request_chain_respond"):
		_game.request_chain_respond(accept)

func on_player_chain_response(should_chain: bool, card_data: Dictionary = {}) -> void:
	if _game and _game.has_method("on_player_chain_response"):
		_game.on_player_chain_response(should_chain, card_data)

func _check_win_condition() -> void:
	if _game and _game.has_method("_check_win_condition"):
		_game._check_win_condition()

func print_all_status() -> void:
	if _game and _game.has_method("print_all_status"):
		_game.print_all_status()
	else:
		print("[BattleManagerBridge] 状态打印")
		print("  回合: ", turn_count, " 阶段: ", get_phase_name())
		print("  当前玩家索引: ", current_player_index)

func get_turn_info() -> String:
	return "回合 " + str(turn_count) + " " + get_phase_name()

func _teardown_battle() -> void:
	if _game and _game.has_method("_teardown_battle"):
		_game._teardown_battle()