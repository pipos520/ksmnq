extends Node2D

## BattleSceneNew - 新版战斗场景，使用 battle_new/ 架构
## 作为 BattleScene3D.gd 的替代版本

const BATTLE_CARD_SCENE = preload("res://battle_new/BattleCard3D.tscn")

var _game: BattleGameNew = null
var _player_ctrl: Node = null
var _ai_ctrl: BattleAINew = null

var _enemy_name: String = "树苗精"
var _deck_id: String = "beginner_deck"

func _ready() -> void:
	_setup_new_battle()

func _setup_new_battle() -> void:
	# 所有战斗系统都是RefCounted，直接实例化
	_game = BattleGameNew.new()
	_game.init()
	
	_ai_ctrl = BattleAINew.new()
	_ai_ctrl.init(_game)
	
	# 玩家控制器：场景自身实现IBattleControllerNew
	_game.set_controllers(self, _ai_ctrl)
	
	# 连接信号
	_game.phase_changed.connect(_on_phase_changed)
	_game.turn_changed.connect(_on_turn_changed)
	_game.battle_ended.connect(_on_battle_ended)
	_game.hp_changed.connect(_on_hp_changed)
	_game.action_result.connect(_on_action_result)
	_game.info_message.connect(_on_info_message)
	
	# 启动战斗
	var deck_id = Global.current_deck_id
	if deck_id == "":
		deck_id = _deck_id
	var enemy_data = Global.current_enemy_data
	if enemy_data.is_empty():
		enemy_data = _load_enemy_data(_enemy_name)
	_game.start_battle(deck_id, enemy_data)

func _load_enemy_data(enemy_name: String) -> Dictionary:
	var enemy = Global.get_enemy_by_plain_name(enemy_name)
	if enemy.is_empty():
		enemy = Global.get_enemy_by_name(enemy_name)
	if enemy.is_empty():
		# 使用默认敌人数据
		return {
			"id": "default_enemy",
			"name": enemy_name,
			"level": 1,
			"hp": 100,
			"max_hp": 100,
			"energy": 3,
			"max_energy": 3,
			"element": "暗",
			"desc": "默认敌人",
			"aux_drops": [],
			"deck": []
		}
	return enemy

func _on_phase_changed(phase: int, player_idx: int) -> void:
	print("[BattleSceneNew] 阶段变化: ", phase, " 玩家: ", player_idx)

func _on_turn_changed(turn: int) -> void:
	print("[BattleSceneNew] 回合变化: ", turn)

func _on_battle_ended(result: int) -> void:
	print("[BattleSceneNew] 战斗结束，结果: ", result)
	# TODO: 处理战斗结果

func _on_hp_changed(is_player: bool, old_hp: int, new_hp: int, max_hp: int) -> void:
	print("[BattleSceneNew] HP变化: ", "玩家" if is_player else "敌人", " ", old_hp, " -> ", new_hp, "/", max_hp)

func _on_action_result(action_type: String, success: bool, data: Dictionary) -> void:
	print("[BattleSceneNew] 动作结果: ", action_type, " 成功: ", success)

func _on_info_message(text: String) -> void:
	print("[BattleSceneNew] 信息: ", text)

func _exit_tree() -> void:
	pass

func on_phase_enter(phase: int) -> void:
	pass

func on_discard_requested(count: int, callback_id: int, reason: String) -> void:
	pass

func on_deck_search_requested(cards: Array, max_select: int, callback_id: int) -> void:
	pass

func on_chain_requested(callback_id: int, chainable_cards: Array) -> void:
	pass

func get_view() -> Dictionary:
	return {}