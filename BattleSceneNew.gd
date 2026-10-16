extends Node2D

## BattleSceneNew - 新版战斗场景，使用 battle_new/ 架构
## 作为 BattleScene3D.gd 的替代版本

const BATTLE_CARD_SCENE = preload("res://battle_new/BattleCard3D.tscn")

var _game: Node = null
var _player_ctrl: Node = null
var _ai_ctrl: Node = null

var _enemy_name: String = "树苗精"
var _deck_id: String = "beginner_deck"

func _ready() -> void:
	_setup_new_battle()

func _setup_new_battle() -> void:
	# 加载新系统组件
	var game_scene = load("res://battle_new/BattleGameNew.gd")
	var player_ctrl_script = load("res://battle_new/EnemyAIController.gd")
	var ai_ctrl_script = load("res://battle_new/BattleAINew.gd")
	
	_game = Node.new()
	_game.set_script(game_scene)
	add_child(_game)
	
	_player_ctrl = Node.new()
	_player_ctrl.set_script(player_ctrl_script)
	add_child(_player_ctrl)
	
	_ai_ctrl = Node.new()
	_ai_ctrl.set_script(ai_ctrl_script)
	add_child(_ai_ctrl)
	
	# 初始化游戏
	_game.init()
	_game.set_controllers(_player_ctrl, _ai_ctrl)
	
	# 连接信号
	_game.phase_changed.connect(_on_phase_changed)
	_game.turn_changed.connect(_on_turn_changed)
	_game.battle_ended.connect(_on_battle_ended)
	_game.hp_changed.connect(_on_hp_changed)
	_game.action_result.connect(_on_action_result)
	_game.info_message.connect(_on_info_message)
	
	# 启动战斗
	var enemy_data = _load_enemy_data(_enemy_name)
	_game.start_battle(_deck_id, enemy_data)

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
	if _game:
		_game.queue_free()