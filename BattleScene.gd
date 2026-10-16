extends Node3D

## BattleScene - 新版战斗场景（使用 battle_new/ 架构）
## 集成 BattleGameNew + UIController + AnimationPlayer

const BATTLE_CARD_SCENE = preload("res://battle_new/BattleCard3D.tscn")

# 战斗系统组件
var _game: Node = null
var _effect_system: Node = null
var _trigger_system: Node = null
var _constraint_manager: Node = null
var _ui_ctrl: Node2D = null
var _anim_player: Node2D = null

# 控制器
var _player_ctrl: Node = null
var _ai_ctrl: Node = null

# 战斗参数
var _enemy_name: String = "树苗精"
var _deck_id: String = "beginner_deck"
var _is_first_battle: bool = true

# 3D节点
var _player_field: Node3D = null
var _enemy_field: Node3D = null
var _camera: Camera3D = null

# UI层
var _ui_layer: Control = null

func _ready() -> void:
	_setup_battle_system()
	_setup_ui()
	_setup_3d_scene()
	_start_battle()

func _setup_battle_system() -> void:
	# 加载新系统组件
	var game_script = load("res://battle_new/BattleGameNew.gd")
	var effect_script = load("res://battle_new/EffectSystemNew.gd")
	var trigger_script = load("res://battle_new/TriggerSystemNew.gd")
	var constraint_script = load("res://battle_new/ConstraintManagerNew.gd")
	var ai_script = load("res://battle_new/BattleAINew.gd")
	var enemy_ai_script = load("res://battle_new/EnemyAIController.gd")
	
	# 创建游戏核心
	_game = Node.new()
	_game.set_script(game_script)
	add_child(_game)
	
	# 创建效果系统
	_effect_system = Node.new()
	_effect_system.set_script(effect_script)
	add_child(_effect_system)
	
	# 创建触发器系统
	_trigger_system = Node.new()
	_trigger_system.set_script(trigger_script)
	add_child(_trigger_system)
	
	# 创建约束管理器
	_constraint_manager = Node.new()
	_constraint_manager.set_script(constraint_script)
	add_child(_constraint_manager)
	
	# 创建玩家控制器
	_player_ctrl = Node.new()
	_player_ctrl.set_script(enemy_ai_script)
	add_child(_player_ctrl)
	
	# 创建AI控制器
	_ai_ctrl = Node.new()
	_ai_ctrl.set_script(ai_script)
	add_child(_ai_ctrl)
	
	# 初始化游戏
	_game.init()
	_game.set_controllers(_player_ctrl, _ai_ctrl)
	
	# 连接信号
	_connect_game_signals()

func _connect_game_signals() -> void:
	if _game == null:
		return
	if _game.has_signal("phase_changed"):
		_game.phase_changed.connect(_on_phase_changed)
	if _game.has_signal("turn_changed"):
		_game.turn_changed.connect(_on_turn_changed)
	if _game.has_signal("battle_ended"):
		_game.battle_ended.connect(_on_battle_ended)
	if _game.has_signal("hp_changed"):
		_game.hp_changed.connect(_on_hp_changed)
	if _game.has_signal("energy_changed"):
		_game.energy_changed.connect(_on_energy_changed)
	if _game.has_signal("hand_changed"):
		_game.hand_changed.connect(_on_hand_changed)
	if _game.has_signal("field_changed"):
		_game.field_changed.connect(_on_field_changed)
	if _game.has_signal("grave_changed"):
		_game.grave_changed.connect(_on_grave_changed)
	if _game.has_signal("action_result"):
		_game.action_result.connect(_on_action_result)
	if _game.has_signal("info_message"):
		_game.info_message.connect(_on_info_message)
	if _game.has_signal("effect_triggered"):
		_game.effect_triggered.connect(_on_effect_triggered)
	if _game.has_signal("card_effect_activated"):
		_game.card_effect_activated.connect(_on_card_effect_activated)
	if _game.has_signal("discard_requested"):
		_game.discard_requested.connect(_on_discard_requested)
	if _game.has_signal("deck_search_requested"):
		_game.deck_search_requested.connect(_on_deck_search_requested)
	if _game.has_signal("chain_requested"):
		_game.chain_requested.connect(_on_chain_requested)

func _setup_ui() -> void:
	# 创建UI层
	_ui_layer = Control.new()
	_ui_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_ui_layer)
	
	# 创建UI控制器
	var ui_script = load("res://battle_new/BattleUIController.gd")
	_ui_ctrl = Node2D.new()
	_ui_ctrl.set_script(ui_script)
	add_child(_ui_ctrl)
	
	# 创建动画播放器
	var anim_script = load("res://battle_new/BattleAnimationPlayer.gd")
	_anim_player = Node2D.new()
	_anim_player.set_script(anim_script)
	add_child(_anim_player)
	
	# 创建基础UI元素
	_create_basic_ui()

func _create_basic_ui() -> void:
	# 回合信息标签
	var turn_label = Label.new()
	turn_label.name = "TurnLabel"
	turn_label.text = "回合 1 - 主要阶段"
	turn_label.position = Vector2(20, 20)
	turn_label.add_theme_font_size_override("font_size", 24)
	_ui_layer.add_child(turn_label)
	
	# 阶段按钮
	var phase_btn = Button.new()
	phase_btn.name = "PhaseBtn"
	phase_btn.text = "进入战斗阶段"
	phase_btn.position = Vector2(300, 20)
	phase_btn.size = Vector2(200, 50)
	phase_btn.pressed.connect(_on_phase_btn_pressed)
	_ui_layer.add_child(phase_btn)
	
	# 返回按钮
	var back_btn = Button.new()
	back_btn.name = "BackBtn"
	back_btn.text = "返回"
	back_btn.position = Vector2(520, 20)
	back_btn.size = Vector2(100, 50)
	back_btn.pressed.connect(_on_back_btn_pressed)
	_ui_layer.add_child(back_btn)

func _setup_3d_scene() -> void:
	# 创建相机
	_camera = Camera3D.new()
	_camera.name = "Camera"
	_camera.position = Vector3(0, 15, -15)
	_camera.rotation = Vector3(-0.6, 0, 0)
	add_child(_camera)
	
	# 创建场地
	_player_field = Node3D.new()
	_player_field.name = "PlayerField"
	_player_field.position = Vector3(0, 0, 5)
	add_child(_player_field)
	
	_enemy_field = Node3D.new()
	_enemy_field.name = "EnemyField"
	_enemy_field.position = Vector3(0, 0, -5)
	add_child(_enemy_field)
	
	# 设置动画播放器的相机
	if _anim_player and _anim_player.has_method("set_camera"):
		_anim_player.set_camera(_camera)

func _start_battle() -> void:
	# 加载敌人数据
	var enemy_data = _load_enemy_data(_enemy_name)
	
	# 启动战斗
	_game.start_battle(_deck_id, enemy_data)
	
	# 更新UI
	if _ui_ctrl:
		_ui_ctrl.update_phase_info("准备阶段", 1, true)

func _load_enemy_data(enemy_name: String) -> Dictionary:
	var enemy = Global.get_enemy_by_plain_name(enemy_name)
	if enemy.is_empty():
		enemy = Global.get_enemy_by_name(enemy_name)
	if enemy.is_empty():
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

# ===== 信号回调 =====

func _on_phase_changed(phase: int, player_idx: int) -> void:
	var phase_name = _get_phase_name(phase)
	if _ui_ctrl:
		_ui_ctrl.update_phase_info(phase_name, _game.turn_count, player_idx == 0)
	_update_phase_button(phase, player_idx)

func _on_turn_changed(turn: int) -> void:
	if _ui_ctrl:
		_ui_ctrl.update_phase_info(_get_phase_name(_game.phase), turn, _game.current_player_index == 0)

func _on_battle_ended(result: int) -> void:
	# 处理战斗结束
	if result == 1:
		print("[BattleScene] 玩家胜利!")
	elif result == 0:
		print("[BattleScene] 玩家失败")

func _on_hp_changed(is_player: bool, old_hp: int, new_hp: int, max_hp: int) -> void:
	var side = "玩家" if is_player else "敌人"
	print("[BattleScene] ", side, " HP: ", old_hp, " -> ", new_hp, "/", max_hp)

func _on_energy_changed(is_player: bool, old_val: int, new_val: int, max_val: int) -> void:
	var side = "玩家" if is_player else "敌人"
	print("[BattleScene] ", side, " 能量: ", old_val, " -> ", new_val, "/", max_val)

func _on_hand_changed(is_player: bool) -> void:
	if is_player and _game.player_self:
		var cards = []
		for card in _game.player_self.hand:
			cards.append(_card_to_dict(card))
		if _ui_ctrl:
			_ui_ctrl.update_hand_cards(cards)

func _on_field_changed(is_player: bool) -> void:
	pass  # 更新场地显示

func _on_grave_changed(is_player: bool) -> void:
	pass  # 更新墓地显示

func _on_action_result(action_type: String, success: bool, data: Dictionary) -> void:
	print("[BattleScene] 动作结果: ", action_type, " 成功: ", success)

func _on_info_message(text: String) -> void:
	print("[BattleScene] ", text)

func _on_effect_triggered(action_type: String, value: int, is_player: bool, source_slot: int, desc: String) -> void:
	if _anim_player:
		_anim_player.show_effect_panel(desc, desc, Vector2(400, 300))

func _on_card_effect_activated(card_name: String, effect_desc: String, action_type: String, 
                               target_id: String, value: int, target_card_name: String, 
                               source_slot: int, is_player: bool, target_slot: int, target_is_player: bool) -> void:
	if _anim_player:
		_anim_player.show_effect_panel(card_name, effect_desc, Vector2(400, 300))

func _on_discard_requested(count: int, callback_id: int, reason: String) -> void:
	if _ui_ctrl:
		_ui_ctrl.start_discard_mode(count, reason)

func _on_deck_search_requested(cards: Array, max_select: int, callback_id: int) -> void:
	# 显示卡组检索UI

func _on_chain_requested(callback_id: int, chainable_cards: Array) -> void:
	# 显示连锁响应UI

# ===== UI回调 =====

func _on_phase_btn_pressed() -> void:
	if _game and _game.has_method("request_end_phase"):
		_game.request_end_phase()

func _on_back_btn_pressed() -> void:
	get_tree().quit()

func _update_phase_button(phase: int, player_idx: int) -> void:
	var phase_btn = _ui_layer.get_node("PhaseBtn")
	if phase_btn:
		if phase == 0 or phase == 1:  # MAIN
			phase_btn.text = "进入战斗阶段"
		elif phase == 2:  # BATTLE
			phase_btn.text = "结束回合"
		else:
			phase_btn.text = "结束回合"

func _get_phase_name(phase: int) -> String:
	match phase:
		0: return "主要阶段"
		1: return "战斗阶段"
		2: return "结束阶段"
		_: return "未知"

func _card_to_dict(card) -> Dictionary:
	if card == null:
		return {}
	return {
		"id": card.get("id", ""),
		"name": card.get("name", ""),
		"cost": card.get("cost", 0),
		"atk": card.get("atk", 0),
		"hp": card.get("hp", 0),
		"desc": card.get("desc", ""),
		"element": card.get("element", ""),
		"effects": card.get("effects", []),
		"rarity": card.get("rarity", "普通"),
		"image": card.get("image", "")
	}

func _exit_tree() -> void:
	if _game:
		_game.queue_free()