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

# ===== 战斗系统 =====
var _game: Node = null
var _effect_system: Node = null
var _trigger_system: Node = null
var _constraint_manager: Node = null
var _player_ctrl: Node = null
var _ai_ctrl: Node = null

# ===== 战斗参数 =====
var _player_name: String = "卡师"
var _enemy_name: String = "树苗精"
var _deck_id: String = "beginner_deck"
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
	var game_script = load("res://battle_new/BattleGameNew.gd")
	var effect_script = load("res://battle_new/EffectSystemNew.gd")
	var trigger_script = load("res://battle_new/TriggerSystemNew.gd")
	var constraint_script = load("res://battle_new/ConstraintManagerNew.gd")
	var ai_script = load("res://battle_new/BattleAINew.gd")
	var enemy_ai_script = load("res://battle_new/EnemyAIController.gd")
	
	_game = Node.new()
	_game.set_script(game_script)
	add_child(_game)
	
	_effect_system = Node.new()
	_effect_system.set_script(effect_script)
	add_child(_effect_system)
	
	_trigger_system = Node.new()
	_trigger_system.set_script(trigger_script)
	add_child(_trigger_system)
	
	_constraint_manager = Node.new()
	_constraint_manager.set_script(constraint_script)
	add_child(_constraint_manager)
	
	_player_ctrl = Node.new()
	_player_ctrl.set_script(enemy_ai_script)
	add_child(_player_ctrl)
	
	_ai_ctrl = Node.new()
	_ai_ctrl.set_script(ai_script)
	add_child(_ai_ctrl)
	
	_game.init()
	_game.set_controllers(_player_ctrl, _ai_ctrl)

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

func _start_battle() -> void:
	var enemy_data = _load_enemy_data(_enemy_name)
	_game.start_battle(_deck_id, enemy_data)
	_update_all_info_labels()

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
	_phase_name = _get_phase_name(phase)
	_is_player_turn = player_idx == 0
	_update_turn_info()
	_update_phase_button(phase, player_idx)

func _on_turn_changed(turn: int) -> void:
	_turn_count = turn
	_update_turn_info()

func _on_battle_ended(result: int) -> void:
	if result == 1:
		_show_battle_result(true)
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
	if is_player and _game.player_self:
		_sync_player_hand_from_bm()

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

# ===== UI更新 =====

func _update_turn_info() -> void:
	if _turn_info_label:
		_turn_info_label.text = "回合 %d - %s" % [_turn_count, _phase_name]

func _update_phase_button(phase: int, player_idx: int) -> void:
	var phase_btn = get_node_or_null("UI/PhaseBtn") as Button
	if phase_btn:
		if player_idx == 0:
			if phase == 0:  # MAIN
				phase_btn.text = "⚔️ 进入战斗"
			elif phase == 1:  # BATTLE
				phase_btn.text = "✅ 结束回合"
			else:
				phase_btn.text = "✅ 结束回合"
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
		0: return "主要阶段"
		1: return "战斗阶段"
		2: return "结束阶段"
		_: return "未知"

# ===== 手牌同步 =====

func _sync_player_hand_from_bm() -> void:
	if _game == null or _game.player_self == null:
		return
	var hand = _game.player_self.hand
	var count = min(hand.size(), HAND_SLOT_MAX)
	_ensure_hand_slots(count)
	for i in range(HAND_SLOT_MAX):
		if i < count:
			var card = hand[i]
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
		var slot = _player_slots[i] if i < _player_slots.size() else null
		if i < field.size() and field[i]:
			_show_player_card_on_slot(i, field[i])
		else:
			_clear_player_card_on_slot(i)

func _refresh_enemy_field_display() -> void:
	if _game == null or _game.player_opponent == null:
		return
	var field = _game.player_opponent.field
	for i in range(5):
		var slot = _enemy_slots[i] if i < _enemy_slots.size() else null
		if i < field.size() and field[i]:
			_show_enemy_card_on_slot(i, field[i])
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
	if _game.phase == 0:  # MAIN -> BATTLE
		_game.request_enter_battle()
	elif _game.phase == 1:  # BATTLE -> END
		_game.request_end_phase()

func _on_back() -> void:
	get_tree().change_scene_to_file("res://Main.tscn")

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

func _exit_tree() -> void:
	if _game:
		_game.queue_free()