extends Node2D

## BattleUIController - 战斗UI控制器
## 处理所有UI显示和输入交互逻辑

class_name BattleUIController

# 信号
signal hand_card_clicked(hand_idx: int)
signal hand_card_long_pressed(hand_idx: int)
signal field_slot_clicked(slot_idx: int, is_player: bool)
signal field_slot_long_pressed(slot_idx: int, is_player: bool)
signal grave_clicked(is_player: bool)
signal phase_btn_pressed()
signal back_btn_pressed()
signal view_switch_pressed()

# UI状态
var hand_cards: Array = []
var enemy_hand_slots_count: int = 0
var phase_name: String = "主要阶段"
var turn_count: int = 1
var is_player_turn: bool = true

# 选中状态
var selected_hand_index: int = -1

# UI节点引用
var hand_slots: Array = []
var field_slots_player: Array = []
var field_slots_enemy: Array = []
var grave_node_player: Node3D = null
var grave_node_enemy: Node3D = null

# 详情面板
var detail_panel: Control = null
var grave_panel: Control = null

# 弃牌UI
var discard_mode: bool = false
var discard_selected: Array = []
var discard_need: int = 0
var discard_panel: Node = null

# 教程
var tutorial_step: int = 0
var tutorial_popup: Control = null

# 奖励弹窗
var reward_popup: Control = null

func _ready() -> void:
	_setup_ui()

func _setup_ui() -> void:
	pass  # 由具体场景实现

func _process(_delta: float) -> void:
	pass  # 由具体场景实现

func _input(event: InputEvent) -> void:
	pass  # 由具体场景实现

func _unhandled_input(event: InputEvent) -> void:
	pass  # 由具体场景实现

# ===== 战斗状态更新 =====

func update_phase_info(phase_name: String, turn_count: int, is_player_turn: bool) -> void:
	self.phase_name = phase_name
	self.turn_count = turn_count
	self.is_player_turn = is_player_turn

func update_hand_cards(cards: Array) -> void:
	hand_cards = cards
	selected_hand_index = -1

func update_enemy_hand_count(count: int) -> void:
	enemy_hand_slots_count = count

# ===== 手牌交互 =====

func on_hand_clicked(hand_idx: int) -> void:
	hand_card_clicked.emit(hand_idx)

func on_hand_long_pressed(hand_idx: int) -> void:
	hand_card_long_pressed.emit(hand_idx)

func show_card_detail(data: Dictionary) -> void:
	pass  # 由具体场景实现

func close_card_detail() -> void:
	pass  # 由具体场景实现

# ===== 场地交互 =====

func on_field_clicked(slot_idx: int, is_player: bool) -> void:
	field_slot_clicked.emit(slot_idx, is_player)

func on_field_long_pressed(slot_idx: int, is_player: bool) -> void:
	field_slot_long_pressed.emit(slot_idx, is_player)

# ===== 墓地交互 =====

func on_grave_clicked(is_player: bool) -> void:
	grave_clicked.emit(is_player)

func show_grave_panel(is_player: bool) -> void:
	pass  # 由具体场景实现

func close_grave_panel() -> void:
	pass  # 由具体场景实现

# ===== 阶段按钮 =====

func on_phase_btn_pressed() -> void:
	phase_btn_pressed.emit()

func on_back_btn_pressed() -> void:
	back_btn_pressed.emit()

func on_view_switch_pressed() -> void:
	view_switch_pressed.emit()

# ===== 弃牌UI =====

func start_discard_mode(need_count: int, reason: String) -> void:
	discard_mode = true
	discard_need = need_count
	discard_selected = []

func end_discard_mode() -> void:
	discard_mode = false
	discard_selected = []

func toggle_discard_selection(hand_index: int) -> void:
	if hand_index in discard_selected:
		discard_selected.erase(hand_index)
	else:
		if discard_selected.size() < discard_need:
			discard_selected.append(hand_index)

func get_discard_selection() -> Array:
	return discard_selected

# ===== 教程 =====

func advance_tutorial_step(trigger: String) -> void:
	tutorial_step += 1

func show_tutorial_popup() -> void:
	pass  # 由具体场景实现

# ===== 奖励弹窗 =====

func show_reward_popup(gained_aux: Array) -> void:
	pass  # 由具体场景实现

func confirm_reward() -> void:
	pass  # 由具体场景实现