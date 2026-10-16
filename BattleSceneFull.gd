extends Node3D

## BattleSceneFull - 完整版战斗场景（迁移自 BattleScene3D.gd）
## 使用 battle_new/ 新架构，但保留完整UI逻辑

const CARD_SCENE = preload("res://battle_new/BattleCard3D.tscn")

# ===== 相机控制 =====
const CAM_POS_X: float = -0.7
const CAM_POS_Z: Array[float] = [-2.0, 0.0, 2.0]
const CAM_POS_Y: float = 3.5
const CAM_BASE_SIZE: float = 4.3
const CAM_DESIGN_ASPECT: float = 16.0 / 9.0
var _cam_state: int = 2
var _cam_tween: Tween = null
var _cam: Camera3D = null
var _view_btn: Button = null

# ===== 场地节点 =====
var _enemy_slots: Array = []
var _player_slots: Array = []
var _player_card_nodes: Array = [null, null, null, null, null]
var _enemy_card_nodes: Array = [null, null, null, null, null]

# ===== 卡牌材质 =====
var _card_front_mat: StandardMaterial3D = null
var _card_back_mat: StandardMaterial3D = null
var _mat_attack_green: StandardMaterial3D = null
var _mat_attack_gray: StandardMaterial3D = null

# ===== 卡组节点 =====
var _player_deck_nodes: Array = []
var _enemy_deck_nodes: Array = []

# ===== 手牌节点 =====
var _player_hand_nodes: Array = []
var _player_hand_cards: Array = []
var _player_hand_datas: Array = []
var _enemy_hand_nodes: Array = []
var _enemy_hand_cards: Array = []

# ===== 回合信息 =====
var _turn_count: int = 1
var _is_player_turn: bool = true
var _phase_name: String = "主要阶段"
@onready var _turn_info_label: Label3D = $TurnInfoLabel

# ===== 战斗系统（全部为RefCounted，不加入场景树） =====
var _game: BattleGameNew = null
var _ai_ctrl: BattleAINew = null

# ===== 战斗参数 =====
var _player_name: String = "卡师"
var _enemy_name: String = ""
var _deck_id: String = ""
var _player_hp: int = 30
var _player_max_hp: int = 30
var _player_energy: int = 3
var _player_max_energy: int = 5
var _enemy_hp: int = 100
var _enemy_max_hp: int = 100
var _enemy_energy: int = 3
var _enemy_max_energy: int = 5

# ===== 手牌交互 =====
var _selected_hand_index: int = -1
var _hand_press_time: float = -1.0
var _hand_press_index: int = -1
var _long_press_triggered: bool = false
var _detail_panel: Control = null
const HAND_EXPAND_OFFSET: float = 0.6
const HAND_EXPAND_POS_Y: float = 0.35
const HAND_EXPAND_POS_Z: float = 0.5
const LONG_PRESS_TIME: float = 0.8

# ===== 墓地 =====
var _player_grave_node: Node3D = null
var _enemy_grave_node: Node3D = null
var _player_exile_node: Node3D = null
var _enemy_exile_node: Node3D = null

# ===== 信息栏 =====
@onready var _enemy_name_lbl: Label3D = get_node_or_null("EnemyField/InfoArea/NameLabel")
@onready var _enemy_hp_lbl: Label3D = get_node_or_null("EnemyField/InfoArea/HPLabel")
@onready var _enemy_energy_lbl: Label3D = get_node_or_null("EnemyField/InfoArea/EnergyLabel")
@onready var _player_name_lbl: Label3D = get_node_or_null("PlayerField/InfoArea/NameLabel")
@onready var _player_hp_lbl: Label3D = get_node_or_null("PlayerField/InfoArea/HPLabel")
@onready var _player_energy_lbl: Label3D = get_node_or_null("PlayerField/InfoArea/EnergyLabel")

# ===== 手牌布局常量 =====
const HAND_MIN_X: float = -2.4
const HAND_MAX_X: float = 2.4
const HAND_Z: float = 3.4
const HAND_Y: float = 0.15
const HAND_CARD_WIDTH: float = 1.0
const HAND_Z_OVERLAP: float = 0.02
const HAND_SLOT_MAX: int = 8

# ===== 弃牌UI =====
var _discard_mode: bool = false
var _discard_selected: Array = []
var _discard_need: int = 0
var _discard_callback_id: int = -1

# ===== 效果面板 =====
var _effect_panels: Array = []

func _ready() -> void:
	DisplayServer.screen_set_orientation(DisplayServer.SCREEN_LANDSCAPE)
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	_setup_battle_system()
	_setup_ui()
	_setup_3d_nodes()
	_connect_signals()
	_start_battle()

func _setup_battle_system() -> void:
	# 所有战斗系统都是RefCounted，直接实例化，不加入场景树
	_game = BattleGameNew.new()
	_game.init()
	# AI控制器：BattleAINew也是RefCounted
	_ai_ctrl = BattleAINew.new()
	_ai_ctrl.init(_game)
	# 玩家控制器：场景自身实现IBattleControllerNew接口
	_game.set_controllers(self, _ai_ctrl)

func _setup_ui() -> void:
	_cam = get_node_or_null("BattleCamera") as Camera3D
	if _cam:
		_cam.position = Vector3(CAM_POS_X, CAM_POS_Y, CAM_POS_Z[_cam_state])
		_cam.rotation_degrees = Vector3(-90, 0, 0)
		_adjust_camera_size()
		get_viewport().size_changed.connect(_on_viewport_resized)
	
	_view_btn = get_node_or_null("UI/ViewBtn") as Button
	if _view_btn:
		_view_btn.pressed.connect(_on_view_switch)
		_view_btn.text = "📷 视角: 己方"
	
	var back_btn = get_node_or_null("UI/BackBtn") as Button
	if back_btn:
		back_btn.pressed.connect(_on_back)
	
	var phase_btn = get_node_or_null("UI/PhaseBtn") as Button
	if phase_btn:
		phase_btn.pressed.connect(_on_phase_btn_pressed)
	
	var enemy_field = get_node_or_null("EnemyField")
	var player_field = get_node_or_null("PlayerField")
	if enemy_field:
		for i in range(5):
			var slot = enemy_field.get_node_or_null("EnemySlot_" + str(i))
			if slot:
				_enemy_slots.append(slot)
	if player_field:
		for i in range(5):
			var slot = player_field.get_node_or_null("PlayerSlot_" + str(i))
			if slot:
				_player_slots.append(slot)
		_player_grave_node = player_field.get_node_or_null("GraveArea")
		_player_exile_node = player_field.get_node_or_null("ExileArea")
	if enemy_field:
		_enemy_grave_node = enemy_field.get_node_or_null("GraveArea")
		_enemy_exile_node = enemy_field.get_node_or_null("ExileArea")

func _setup_3d_nodes() -> void:
	_card_front_mat = StandardMaterial3D.new()
	var front_tex = load("res://assets/3d/card_front.png")
	if front_tex:
		_card_front_mat.albedo_texture = front_tex
	_card_front_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_card_front_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	
	_card_back_mat = StandardMaterial3D.new()
	var back_tex = load("res://assets/3d/card_back.png")
	if back_tex:
		_card_back_mat.albedo_texture = back_tex
	_card_back_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_card_back_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	
	_mat_attack_green = StandardMaterial3D.new()
	_mat_attack_green.albedo_color = Color(0.2, 0.8, 0.2, 0.5)
	_mat_attack_green.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	
	_mat_attack_gray = StandardMaterial3D.new()
	_mat_attack_gray.albedo_color = Color(0.5, 0.5, 0.5, 0.3)
	_mat_attack_gray.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

func _connect_signals() -> void:
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
	if _game.has_signal("deck_count_changed"):
		_game.deck_count_changed.connect(_on_deck_count_changed)
	if _game.has_signal("banish_changed"):
		_game.banish_changed.connect(_on_banish_changed)

func _start_battle() -> void:
	# 从 Global 获取战斗参数
	_deck_id = Global.current_deck_id
	if _deck_id == "":
		_deck_id = "deck_0"
	_enemy_name = ""
	var enemy_data = Global.current_enemy_data
	if enemy_data.size() > 0:
		_enemy_name = enemy_data.get("name", "")
	_update_all_info_labels()
	_game.start_battle(_deck_id, enemy_data)

# ===== 信号回调 =====

func _on_phase_changed(phase: int, player_idx: int) -> void:
	_phase_name = _get_phase_name(phase)
	_is_player_turn = player_idx == 0
	_update_turn_info()
	_update_phase_button(phase, player_idx)

func _on_turn_changed(turn: int) -> void:
	_turn_count = turn
	_update_turn_info()

func _on_battle_ended(result: int) -> void:
	if result == 1:
		_handle_victory_rewards()
	elif result == 0:
		_show_battle_result(false)

func _on_hp_changed(is_player: bool, old_hp: int, new_hp: int, max_hp: int) -> void:
	if is_player:
		_player_hp = new_hp
		if _player_hp_lbl:
			_player_hp_lbl.text = "❤️ %d/%d" % [new_hp, max_hp]
	else:
		_enemy_hp = new_hp
		if _enemy_hp_lbl:
			_enemy_hp_lbl.text = "❤️ %d/%d" % [new_hp, max_hp]

func _on_energy_changed(is_player: bool, old_val: int, new_val: int, max_val: int) -> void:
	if is_player:
		_player_energy = new_val
		if _player_energy_lbl:
			_player_energy_lbl.text = "⚡ %d/%d" % [new_val, max_val]
	else:
		_enemy_energy = new_val
		if _enemy_energy_lbl:
			_enemy_energy_lbl.text = "⚡ %d/%d" % [new_val, max_val]

func _on_hand_changed(is_player: bool) -> void:
	if is_player and _game and _game.player_self:
		_sync_player_hand_from_game()

func _on_field_changed(is_player: bool) -> void:
	if is_player:
		_refresh_player_field_display()
	else:
		_refresh_enemy_field_display()

func _on_grave_changed(is_player: bool) -> void:
	pass

func _on_action_result(action_type: String, success: bool, data: Dictionary) -> void:
	if not success:
		var msg = data.get("message", "操作失败")
		if msg != "":
			_show_info_message(msg)

func _on_info_message(text: String) -> void:
	_show_info_message(text)

func _on_effect_triggered(action_type: String, value: int, is_player: bool, source_slot: int, desc: String) -> void:
	if desc != "":
		_show_float_text(desc, Vector3(0, 2, 0), Color(1, 1, 0), 1.5)

func _on_card_effect_activated(card_name: String, effect_desc: String, action_type: String, 
                               target_id: String, value: int, target_card_name: String, 
                               source_slot: int, is_player: bool, target_slot: int, target_is_player: bool) -> void:
	if effect_desc != "":
		_show_float_text(effect_desc, Vector3(0, 2.5, 0), Color(0.5, 1, 0.5), 1.5)

func _on_discard_requested(count: int, callback_id: int, reason: String) -> void:
	_discard_mode = true
	_discard_need = count
	_discard_callback_id = callback_id
	_discard_selected = []
	_show_discard_ui(reason)

func _on_deck_search_requested(cards: Array, max_select: int, callback_id: int) -> void:
	# TODO: 实现卡组检索UI
	pass

func _on_chain_requested(callback_id: int, chainable_cards: Array) -> void:
	# TODO: 实现连锁UI
	pass

func _on_deck_count_changed(is_player: bool, remaining: int) -> void:
	# TODO: 更新卡组剩余显示
	pass

func _on_banish_changed(is_player: bool) -> void:
	# TODO: 更新除外区显示
	pass

# ===== UI更新 =====

func _update_turn_info() -> void:
	if _turn_info_label:
		_turn_info_label.text = "回合 %d - %s" % [_turn_count, _phase_name]

func _update_phase_button(phase: int, player_idx: int) -> void:
	var phase_btn = get_node_or_null("UI/PhaseBtn") as Button
	if phase_btn:
		if player_idx == 0:
			# Phase enum: NONE=0, DRAW=1, READY=2, MAIN=3, BATTLE=4, END=5, DISCARD=6
			if phase == 3:  # MAIN
				phase_btn.text = "⚔️ 进入战斗"
				phase_btn.disabled = false
			elif phase == 4:  # BATTLE
				phase_btn.text = "✅ 结束回合"
				phase_btn.disabled = false
			else:
				phase_btn.text = "✅ 结束回合"
				phase_btn.disabled = false
		else:
			phase_btn.text = "敌方回合..."
			phase_btn.disabled = true

func _update_all_info_labels() -> void:
	if _player_name_lbl:
		_player_name_lbl.text = _player_name
	if _player_hp_lbl:
		_player_hp_lbl.text = "❤️ %d/%d" % [_player_hp, _player_max_hp]
	if _player_energy_lbl:
		_player_energy_lbl.text = "⚡ %d/%d" % [_player_energy, _player_max_energy]
	if _enemy_name_lbl:
		_enemy_name_lbl.text = _enemy_name
	if _enemy_hp_lbl:
		_enemy_hp_lbl.text = "❤️ %d/%d" % [_enemy_hp, _enemy_max_hp]
	if _enemy_energy_lbl:
		_enemy_energy_lbl.text = "⚡ %d/%d" % [_enemy_energy, _enemy_max_energy]

func _get_phase_name(phase: int) -> String:
	match phase:
		0: return "无"
		1: return "抽牌"
		2: return "准备"
		3: return "主要阶段"
		4: return "战斗阶段"
		5: return "结束阶段"
		6: return "弃牌阶段"
		_: return "未知"

# ===== 手牌同步 =====

func _sync_player_hand_from_game() -> void:
	if _game == null or _game.player_self == null:
		return
	var hand = _game.player_self.hand
	var count = mini(hand.size(), HAND_SLOT_MAX)
	_ensure_hand_slots(count)
	for i in range(HAND_SLOT_MAX):
		if i < count:
			var card = hand.get_card(i)
			var node = _player_hand_nodes[i]
			if node:
				node.queue_free()
			node = _create_battle_card(card, true)
			_player_hand_nodes[i] = node
			_player_hand_cards[i] = card
		else:
			_set_hand_slot_empty(i)
	_layout_player_hand(false)

func _ensure_hand_slots(need: int) -> void:
	while _player_hand_nodes.size() < need:
		_player_hand_nodes.append(null)
		_player_hand_cards.append(null)

func _set_hand_slot_empty(i: int) -> void:
	if i < _player_hand_nodes.size() and _player_hand_nodes[i]:
		_player_hand_nodes[i].queue_free()
		_player_hand_nodes[i] = null
		_player_hand_cards[i] = null

func _layout_player_hand(is_animated: bool = false) -> void:
	var count = _player_hand_nodes.size()
	var visible = 0
	for i in range(count):
		if _player_hand_nodes[i]:
			visible += 1
	if visible == 0:
		return
	var spacing = (HAND_MAX_X - HAND_MIN_X) / max(1, visible - 1) if visible > 1 else 0
	for i in range(count):
		if _player_hand_nodes[i]:
			var target_x = HAND_MIN_X + spacing * i
			var target_pos = Vector3(target_x, HAND_Y, HAND_Z)
			if is_animated:
				var tween = _player_hand_nodes[i].create_tween()
				tween.tween_property(_player_hand_nodes[i], "position", target_pos, 0.3)
			else:
				_player_hand_nodes[i].position = target_pos

func _create_battle_card(card, is_front: bool) -> Node3D:
	if card == null:
		return null
	var card_node = CARD_SCENE.instantiate()
	add_child(card_node)
	if is_front:
		card_node.set_surface_override_material(0, _card_front_mat)
		card_node.set_meta("card_data", card)
	else:
		card_node.set_surface_override_material(0, _card_back_mat)
	return card_node

# ===== 场地显示 =====

func _refresh_player_field_display() -> void:
	if _game == null or _game.player_self == null:
		return
	var field = _game.player_self.field
	for i in range(5):
		var card = field.get_slot(i)
		if card:
			_show_player_card_on_slot(i, card)
		else:
			_clear_player_card_on_slot(i)

func _refresh_enemy_field_display() -> void:
	if _game == null or _game.player_opp == null:
		return
	var field = _game.player_opp.field
	for i in range(5):
		var card = field.get_slot(i)
		if card:
			_show_enemy_card_on_slot(i, card)
		else:
			_clear_enemy_card_on_slot(i)

func _show_player_card_on_slot(slot_idx: int, card) -> void:
	if slot_idx >= _player_card_nodes.size():
		return
	if _player_card_nodes[slot_idx]:
		_player_card_nodes[slot_idx].queue_free()
	var node = _create_battle_card(card, true)
	if node:
		var slot = _player_slots[slot_idx]
		if slot:
			node.position = slot.position
		_player_card_nodes[slot_idx] = node

func _clear_player_card_on_slot(slot_idx: int) -> void:
	if slot_idx < _player_card_nodes.size() and _player_card_nodes[slot_idx]:
		_player_card_nodes[slot_idx].queue_free()
		_player_card_nodes[slot_idx] = null

func _show_enemy_card_on_slot(slot_idx: int, card) -> void:
	if slot_idx >= _enemy_card_nodes.size():
		return
	if _enemy_card_nodes[slot_idx]:
		_enemy_card_nodes[slot_idx].queue_free()
	var node = _create_battle_card(card, true)
	if node:
		var slot = _enemy_slots[slot_idx]
		if slot:
			node.position = slot.position
		_enemy_card_nodes[slot_idx] = node

func _clear_enemy_card_on_slot(slot_idx: int) -> void:
	if slot_idx < _enemy_card_nodes.size() and _enemy_card_nodes[slot_idx]:
		_enemy_card_nodes[slot_idx].queue_free()
		_enemy_card_nodes[slot_idx] = null

# ===== 相机控制 =====

func _adjust_camera_size() -> void:
	if _cam == null:
		return
	var viewport_size = get_viewport().get_visible_rect().size
	var aspect = viewport_size.x / viewport_size.y
	var new_size = CAM_BASE_SIZE * (CAM_DESIGN_ASPECT / aspect)
	_cam.size = new_size

func _on_viewport_resized() -> void:
	_adjust_camera_size()

func _on_view_switch() -> void:
	_cam_state = (_cam_state + 1) % 3
	_switch_camera(_cam_state)
	if _view_btn:
		var states = ["敌方", "全局", "己方"]
		_view_btn.text = "📷 视角: " + states[_cam_state]

func _switch_camera(target_state: int) -> void:
	if _cam == null:
		return
	_cam_state = target_state
	if _cam_tween:
		_cam_tween.kill()
	_cam_tween = create_tween()
	_cam_tween.tween_property(_cam, "position:z", CAM_POS_Z[target_state], 0.5)

# ===== 按钮回调 =====

func _on_phase_btn_pressed() -> void:
	if _game == null:
		return
	if _game.current_phase == BattleGameNew.Phase.MAIN:
		_game.request_enter_battle()
	elif _game.current_phase == BattleGameNew.Phase.BATTLE:
		_game.request_end_phase()

func _on_back() -> void:
	get_tree().change_scene_to_file("res://Main.tscn")

# ===== 输入处理 =====

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_on_hand_touch_start(event)
		else:
			_on_hand_touch_end(event)
	elif event is InputEventScreenDrag:
		_on_hand_touch_drag(event)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed:
			_on_mouse_click(event)

func _on_hand_touch_start(event: InputEventScreenTouch) -> void:
	var pos = event.position
	if _discard_mode:
		_on_discard_click(pos)
		return
	# 检查是否点击手牌
	for i in range(_player_hand_nodes.size()):
		if _player_hand_nodes[i]:
			var card_pos = _screen_to_3d_pos(pos)
			var card_world = _player_hand_nodes[i].global_position
			var dist = Vector2(card_world.x, card_world.z).distance_to(Vector2(card_pos.x, card_pos.z))
			if dist < 0.8:
				_hand_press_time = Time.get_ticks_msec() / 1000.0
				_hand_press_index = i
				_long_press_triggered = false
				break

func _on_hand_touch_end(event: InputEventScreenTouch) -> void:
	if _hand_press_index >= 0 and not _long_press_triggered:
		var press_duration = Time.get_ticks_msec() / 1000.0 - _hand_press_time
		if press_duration < 0.5:
			_on_hand_clicked(_hand_press_index)
	_hand_press_index = -1

func _on_hand_touch_drag(_event: InputEventScreenDrag) -> void:
	pass

func _on_mouse_click(event: InputEventMouseButton) -> void:
	var pos = event.position
	if _discard_mode:
		_on_discard_click(pos)
		return

func _on_hand_clicked(hand_idx: int) -> void:
	if _game == null:
		return
	if _game.current_phase == BattleGameNew.Phase.MAIN:
		if hand_idx < _player_hand_cards.size() and _player_hand_cards[hand_idx]:
			var card = _player_hand_cards[hand_idx]
			var cost = card.base_cost if card else 0
			if _player_energy >= cost:
				# 找到第一个空槽位
				var empty_slots = _game.player_self.field.get_empty_slots()
				if empty_slots.is_empty():
					_show_info_message("场地已满！")
					return
				_game.request_play_card(hand_idx, empty_slots[0])
				_selected_hand_index = hand_idx
				_layout_player_hand(true)

func _on_discard_click(pos: Vector2) -> void:
	for i in range(_player_hand_nodes.size()):
		if _player_hand_nodes[i]:
			var card_pos = _screen_to_3d_pos(pos)
			var card_world = _player_hand_nodes[i].global_position
			var dist = Vector2(card_world.x, card_world.z).distance_to(Vector2(card_pos.x, card_pos.z))
			if dist < 0.8:
				_toggle_discard_selection(i)
				break

func _toggle_discard_selection(hand_index: int) -> void:
	if hand_index in _discard_selected:
		_discard_selected.erase(hand_index)
	else:
		if _discard_selected.size() < _discard_need:
			_discard_selected.append(hand_index)

func _screen_to_3d_pos(screen_pos: Vector2) -> Vector3:
	if _cam == null:
		return Vector3.ZERO
	var ray_origin = _cam.project_ray_origin(screen_pos)
	var ray_dir = _cam.project_ray_dir(screen_pos)
	var t = -ray_origin.y / ray_dir.y if ray_dir.y != 0 else 0
	return ray_origin + ray_dir * t

func _process(delta: float) -> void:
	if _hand_press_time >= 0 and _hand_press_index >= 0:
		var press_duration = Time.get_ticks_msec() / 1000.0 - _hand_press_time
		if press_duration > LONG_PRESS_TIME and not _long_press_triggered:
			_long_press_triggered = true
			_on_hand_long_pressed(_hand_press_index)

# ===== 弃牌UI =====

func _show_discard_ui(reason: String) -> void:
	var overlay = ColorRect.new()
	overlay.name = "DiscardOverlay"
	overlay.color = Color(0, 0, 0, 0.6)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	
	var label = Label.new()
	label.text = "需要弃置 %d 张牌\n%s\n\n点击手牌选择要弃置的牌" % [_discard_need, reason]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(label)
	
	var btn = Button.new()
	btn.text = "确认弃置"
	btn.position = Vector2(800, 900)
	btn.size = Vector2(300, 60)
	btn.pressed.connect(_on_confirm_discard)
	overlay.add_child(btn)

func _on_confirm_discard() -> void:
	if _discard_selected.size() == _discard_need:
		_game.request_select_discard(_discard_selected)
		_discard_mode = false
		_discard_selected = []
		# 移除弃牌UI
		var overlay = get_node_or_null("DiscardOverlay")
		if overlay:
			overlay.queue_free()

# ===== 飘字效果 =====

func _show_float_text(text: String, pos: Vector3, color: Color, duration: float = 1.0) -> void:
	var label = Label3D.new()
	label.text = text
	label.position = pos
	label.font_size = 64
	label.modulate = color
	add_child(label)
	var tween = create_tween()
	tween.tween_property(label, "position:y", pos.y + 2.0, duration)
	tween.parallel().tween_property(label, "modulate:a", 0.0, duration)
	tween.tween_callback(label.queue_free)

func _show_info_message(text: String) -> void:
	var overlay = CanvasLayer.new()
	overlay.name = "InfoMessage"
	overlay.layer = 100
	add_child(overlay)
	
	var panel = Panel.new()
	panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	panel.position = Vector2(700, 100)
	panel.size = Vector2(500, 80)
	overlay.add_child(panel)
	
	var label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(label)
	
	var tween = create_tween()
	tween.tween_interval(1.5)
	tween.tween_callback(func():
		if overlay:
			overlay.queue_free())

# ===== 战斗结果 =====

func _show_battle_result(win: bool) -> void:
	var overlay = ColorRect.new()
	overlay.name = "ResultOverlay"
	overlay.color = Color(0, 0, 0, 0.8)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	
	var label = Label.new()
	label.text = "🎉 胜利!" if win else "💀 失败"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(label)
	
	var btn = Button.new()
	btn.text = "返回地图"
	btn.position = Vector2(800, 900)
	btn.size = Vector2(300, 60)
	btn.pressed.connect(func():
		overlay.queue_free()
		_on_back())
	overlay.add_child(btn)

# ===== 卡牌详情面板 =====

const FONT_SIZE_DETAIL = 40
var _font_detail: Font = null

func _show_card_detail(data: Dictionary) -> void:
	if _detail_panel:
		_detail_panel.queue_free()
		_detail_panel = null
	
	if _font_detail == null:
		_font_detail = load("res://assets/share/font_pixel.ttf")
	
	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.5)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	
	var panel = Panel.new()
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.06, 0.14, 0.95)
	sb.border_width_left = 4
	sb.border_color = Color(0.976, 0.827, 0.443, 0.8)
	panel.add_theme_stylebox_override("panel", sb)
	panel.anchor_left = 0.5
	panel.anchor_top = 0.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	overlay.add_child(panel)
	
	var scroll = ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 40.0
	scroll.offset_top = 100.0
	scroll.offset_right = -40.0
	scroll.offset_bottom = -40.0
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	
	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 15)
	scroll.add_child(vbox)
	
	var name = data.get("name", data.get("card_name", "未命名"))
	var name_lbl = _make_detail_label(name, _font_detail, FONT_SIZE_DETAIL, Color(0.976, 0.827, 0.443, 1.0))
	vbox.add_child(name_lbl)
	
	var fields: Array = data.get("fields", [])
	var field_text = " · ".join(fields) if fields.size() > 0 else "无"
	vbox.add_child(_make_detail_label("字段: " + field_text, _font_detail, FONT_SIZE_DETAIL - 8, Color(0.63, 0.71, 0.86, 0.9)))
	
	var stats = HBoxContainer.new()
	stats.add_theme_constant_override("separation", 30)
	var atk = data.get("atk", data.get("attack", 0))
	var hp = data.get("hp", data.get("health", 0))
	var cost = data.get("cost", data.get("energy_cost", 0))
	stats.add_child(_make_stat_box("攻击", str(atk), Color(0.86, 0.24, 0.24, 1.0)))
	stats.add_child(_make_stat_box("生命", str(hp), Color(0.24, 0.86, 0.31, 1.0)))
	stats.add_child(_make_stat_box("费用", str(cost), Color(0.24, 0.47, 0.86, 1.0)))
	vbox.add_child(stats)
	
	var qual = data.get("quality", data.get("rarity", "普通"))
	var element = data.get("element", "")
	var elem_map := {"火": "[火]", "水": "[水]", "风": "[风]", "暗": "[暗]", "光": "[光]", "地": "[地]"}
	if element != "" and elem_map.has(element):
		qual += "  " + elem_map[element]
	var star = data.get("star", 1)
	var star_str = ""
	for i in range(star):
		star_str += "★"
	qual += "  " + star_str
	vbox.add_child(_make_detail_label(qual, _font_detail, FONT_SIZE_DETAIL - 8, Color(0.7, 0.7, 0.7, 1.0)))
	
	vbox.add_child(_make_detail_label("效果", _font_detail, FONT_SIZE_DETAIL - 8, Color(0.78, 0.63, 0.25, 1.0)))
	var effects: Array = data.get("effects", [])
	var eff_text = "无"
	if effects.size() > 0:
		var lines = []
		for e in effects:
			if e is Dictionary:
				lines.append(e.get("desc", ""))
			elif e is String:
				lines.append(e)
		eff_text = "\n".join(lines)
	vbox.add_child(_make_detail_label(eff_text, _font_detail, FONT_SIZE_DETAIL - 12, Color(0.85, 0.85, 0.85, 1.0)))
	
	var close_btn = Button.new()
	close_btn.text = "关闭"
	close_btn.position = Vector2(40, 40)
	close_btn.size = Vector2(200, 60)
	close_btn.pressed.connect(func():
		overlay.queue_free()
		_detail_panel = null)
	overlay.add_child(close_btn)
	
	overlay.gui_input.connect(func(ev):
		if ev is InputEventScreenTouch and not ev.pressed:
			overlay.queue_free()
			_detail_panel = null)
	
	_detail_panel = overlay

func _make_detail_label(text: String, font: Font, font_size: int, color: Color) -> Label:
	var label = Label.new()
	label.text = text
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	return label

func _make_stat_box(label_text: String, value: String, color: Color) -> Panel:
	var panel = Panel.new()
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.1, 0.2)
	sb.border_width_all = 2
	sb.border_color = color
	sb.corner_radius_all = 8
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(100, 80)
	
	var box = VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(box)
	
	var lbl = Label.new()
	lbl.text = label_text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 24)
	lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	box.add_child(lbl)
	
	var val = Label.new()
	val.text = value
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val.add_theme_font_size_override("font_size", 36)
	val.add_theme_color_override("font_color", color)
	box.add_child(val)
	
	return panel

func _on_hand_long_pressed(hand_idx: int) -> void:
	if _game == null or _game.player_self == null:
		return
	var hand = _game.player_self.hand
	if hand_idx >= 0 and hand_idx < hand.size():
		var card = hand.get_card(hand_idx)
		var data = _card_to_dict(card)
		_show_card_detail(data)

func _get_player_hand_card_data(hand_idx: int) -> Dictionary:
	if _game == null or _game.player_self == null:
		return {}
	var hand = _game.player_self.hand
	if hand_idx >= 0 and hand_idx < hand.size():
		return _card_to_dict(hand.get_card(hand_idx))
	return {}

# ===== 墓地面板 =====

func _show_grave_panel(is_player: bool) -> void:
	if _game == null:
		return
	var grave = _game.player_self.grave if is_player else _game.player_opp.grave
	var grave_count = grave.size() if grave else 0
	
	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.7)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	
	var label = Label.new()
	label.text = "🪦 墓地 (%d张)" % grave_count
	if is_player:
		label.text = "🪦 我方墓地 (%d张)" % grave_count
	else:
		label.text = "🪦 敌方墓地 (%d张)" % grave_count
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(label)
	
	var close_btn = Button.new()
	close_btn.text = "关闭"
	close_btn.position = Vector2(850, 900)
	close_btn.size = Vector2(200, 60)
	close_btn.pressed.connect(func():
		overlay.queue_free())
	overlay.add_child(close_btn)

func _on_grave_clicked(is_player: bool) -> void:
	_show_grave_panel(is_player)

func _card_to_dict(card: BattleCardNew) -> Dictionary:
	if card == null:
		return {}
	return {
		"id": card.card_id,
		"name": card.card_name,
		"cost": card.base_cost,
		"atk": card.current_atk if card.is_on_field else card.base_atk,
		"hp": card.current_hp if card.is_on_field else card.base_hp,
		"desc": card.desc,
		"element": card.element,
		"effects": card.effects,
		"rarity": card.quality,
		"fields": card.fields,
		"star": card.star
	}

# ===== 战斗奖励 =====

func _handle_victory_rewards() -> void:
	if _game == null:
		return
	var enemy_data = Global.current_enemy_data
	var aux_drops = enemy_data.get("aux_drops", [])
	
	var overlay = ColorRect.new()
	overlay.name = "RewardOverlay"
	overlay.color = Color(0, 0, 0, 0.8)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	
	var label = Label.new()
	label.text = "🎁 战斗奖励\n\n击败 %s 获得辅助物品！" % _enemy_name
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(label)
	
	var btn = Button.new()
	btn.text = "领取奖励"
	btn.position = Vector2(800, 900)
	btn.size = Vector2(300, 60)
	btn.pressed.connect(func():
		overlay.queue_free()
		_on_back())
	overlay.add_child(btn)

func _exit_tree() -> void:
	# _game是RefCounted，不需要queue_free，由GC自动回收
	pass


# ============================================================
#  IBattleControllerNew 接口实现（玩家控制器）
# ============================================================

## 阶段进入通知 — 玩家回合时更新UI高亮
func on_phase_enter(phase: int) -> void:
	# 玩家回合：更新UI，等待玩家输入
	# 不需要自动操作，玩家通过点击/拖拽来驱动游戏
	pass

## 弃牌请求 — 显示弃牌UI
func on_discard_requested(count: int, callback_id: int, reason: String) -> void:
	# 通过信号已处理，此接口为IBattleControllerNew要求
	pass

## 卡组检索请求
func on_deck_search_requested(cards: Array, max_select: int, callback_id: int) -> void:
	# TODO: 实现检索UI
	pass

## 连锁请求
func on_chain_requested(callback_id: int, chainable_cards: Array) -> void:
	# TODO: 实现连锁UI
	pass

## 获取视角 — 玩家只能看自己的手牌
func get_view() -> Dictionary:
	if _game == null or _game.player_self == null:
		return {}
	var hand_cards: Array = []
	for i in range(_game.player_self.hand.size()):
		var c = _game.player_self.hand.get_card(i)
		hand_cards.append(_card_to_dict(c))
	return {
		"player_hand": hand_cards,
		"player_deck_count": _game.player_self.deck.size() if _game.player_self.deck else 0,
	}