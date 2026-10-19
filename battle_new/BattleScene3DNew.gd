extends Node3D
class_name BattleScene3DNew

## ============================================================
##  BattleScene3DNew.gd — 3D战斗场景控制器（新版）
##  对接BattleGameNew + IBattleControllerNew体系
##  纯视觉层：监听BattleGameNew信号 → 刷新3D节点
##  不含任何游戏逻辑，所有操作通过 _game.request_xxx() 发起
## ============================================================

# ===== 游戏引用 =====
var _game: BattleGameNew = null
var _ai: BattleAINew = null

# ===== 3D节点引用 =====
var _enemy_slots: Array = []   # MeshInstance3D[5]
var _player_slots: Array = []  # MeshInstance3D[5]
var _cam: Camera3D = null
var _cam_tween: Tween = null

# ===== 相机状态 =====
const CAM_POS_Z: Array[float] = [-2.0, 0.0, 2.0]
const CAM_POS_Y: float = 3.5
var _cam_state: int = 1

# ===== UI节点引用 =====
var _view_btn: Button = null
var _end_phase_btn: Button = null
var _battle_btn: Button = null
var _back_btn: Button = null
var _info_label: Label = null
var _hp_bars: Dictionary = {}  # { "player": TextureProgressBar, "enemy": TextureProgressBar }
var _energy_labels: Dictionary = {}  # { "player": Label, "enemy": Label }

# ===== 卡牌3D节点缓存 =====
# key: "p0"~"p4" / "e0"~"e4", value: { mesh, card, label }
var _card_nodes: Dictionary = {}

# ===== 玩家选择的槽位 =====
var _selected_slot: int = -1
var _selected_hand_idx: int = -1


# ============================================================
#  场景初始化
# ============================================================

func _ready() -> void:
	# 横屏
	DisplayServer.screen_set_orientation(DisplayServer.SCREEN_LANDSCAPE)
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	
	# 获取节点引用
	_cam = get_node_or_null("BattleCamera") as Camera3D
	if _cam:
		_cam.position = Vector3(0, CAM_POS_Y, CAM_POS_Z[_cam_state])
	
	_view_btn = get_node_or_null("UI/ViewBtn") as Button
	_end_phase_btn = get_node_or_null("UI/EndPhaseBtn") as Button
	_battle_btn = get_node_or_null("UI/BattleBtn") as Button
	_back_btn = get_node_or_null("UI/BackBtn") as Button
	_info_label = get_node_or_null("UI/InfoLabel") as Label
	
	# 连接按钮信号
	if _view_btn:
		_view_btn.pressed.connect(_on_view_switch)
	if _end_phase_btn:
		_end_phase_btn.pressed.connect(_on_end_phase)
	if _battle_btn:
		_battle_btn.pressed.connect(_on_enter_battle)
	if _back_btn:
		_back_btn.pressed.connect(_on_back)
	
	# 获取卡槽引用
	var enemy_field = get_node_or_null("EnemyField")
	var player_field = get_node_or_null("PlayerField")
	if enemy_field:
		for i in range(5):
			var slot = enemy_field.get_node_or_null("EnemySlot_" + str(i))
			if slot:
				_enemy_slots.append(slot)
				# 连接点击信号
				if slot is Area3D:
					slot.input_event.connect(_on_slot_input_event.bind(i, false))
	if player_field:
		for i in range(5):
			var slot = player_field.get_node_or_null("PlayerSlot_" + str(i))
			if slot:
				_player_slots.append(slot)
				if slot is Area3D:
					slot.input_event.connect(_on_slot_input_event.bind(i, true))
	
	# 初始化游戏
	_init_game()
	
	print("[BattleScene3DNew] 场景就绪，敌方卡槽=%d，己方卡槽=%d，视角=%d" % [_enemy_slots.size(), _player_slots.size(), _cam_state])


func _init_game() -> void:
	_game = BattleGameNew.new()
	_game.init()
	
	# 创建AI控制器
	_ai = BattleAINew.new()
	_ai.init(_game)
	
	# 设置Controller（玩家=self[0]由场景直接操作，AI=[1]）
	_game.set_controllers(self, _ai)
	
	# 连接信号
	_game.phase_changed.connect(_on_phase_changed)
	_game.turn_changed.connect(_on_turn_changed)
	_game.battle_ended.connect(_on_battle_ended)
	_game.hp_changed.connect(_on_hp_changed)
	_game.energy_changed.connect(_on_energy_changed)
	_game.hand_changed.connect(_on_hand_changed)
	_game.field_changed.connect(_on_field_changed)
	_game.grave_changed.connect(_on_grave_changed)
	_game.deck_count_changed.connect(_on_deck_count_changed)
	_game.banish_changed.connect(_on_banish_changed)
	_game.action_result.connect(_on_action_result)
	_game.info_message.connect(_on_info_message)
	_game.card_effect_activated.connect(_on_card_effect_activated)
	_game.discard_requested.connect(_on_discard_requested)
	_game.deck_search_requested.connect(_on_deck_search_requested)
	_game.chain_requested.connect(_on_chain_requested)
	
	# 获取战斗数据并开始
	var deck_id = Global.current_battle_deck_id if Global.get("current_battle_deck_id") else ""
	var enemy_data = Global.current_battle_enemy_data if Global.get("current_battle_enemy_data") else {}
	_game.start_battle(deck_id, enemy_data)


# ============================================================
#  信号回调（刷新3D视觉）
# ============================================================

func _on_phase_changed(phase: int, player_idx: int) -> void:
	var phase_name = ["NONE", "抽牌", "准备", "主要", "战斗", "结束", "弃牌"]
	var name_str = phase_name[phase] if phase < phase_name.size() else "?"
	var who = "己方" if player_idx == 0 else "敌方"
	_update_info("阶段: %s (%s)" % [name_str, who])
	_refresh_field()


func _on_turn_changed(turn_count: int) -> void:
	_update_info("第 %d 回合" % turn_count)


func _on_battle_ended(result: int) -> void:
	match result:
		BattleGameNew.State.WON:
			_update_info(" 胜利！")
		BattleGameNew.State.LOST:
			_update_info(" 败北！")
		BattleGameNew.State.DRAW:
			_update_info(" 平局！")
	# 3秒后返回
	get_tree().create_timer(3.0).timeout.connect(_on_back)


func _on_hp_changed(is_player: bool, old_hp: int, new_hp: int, max_hp: int) -> void:
	var key = "player" if is_player else "enemy"
	if _hp_bars.has(key):
		var bar = _hp_bars[key] as TextureProgressBar
		if bar:
			var tween = create_tween()
			tween.tween_property(bar, "value", float(new_hp) / float(max_hp) * 100.0, 0.3)
	_update_hp_display()


func _on_energy_changed(is_player: bool, old_val: int, new_val: int, max_val: int) -> void:
	var key = "player" if is_player else "enemy"
	if _energy_labels.has(key):
		var label = _energy_labels[key] as Label
		if label:
			label.text = " %d/%d" % [new_val, max_val]


func _on_hand_changed(is_player: bool) -> void:
	# 刷新手牌显示
	_refresh_hand(is_player)


func _on_field_changed(is_player: bool) -> void:
	_refresh_field()


func _on_grave_changed(is_player: bool) -> void:
	# 可以更新墓地计数显示
	pass


func _on_deck_count_changed(is_player: bool, remaining: int) -> void:
	# 更新卡组剩余显示
	pass


func _on_banish_changed(is_player: bool) -> void:
	pass


func _on_action_result(action_type: String, success: bool, data: Dictionary) -> void:
	if not success:
		var reason = data.get("reason", "失败")
		_update_info(" %s: %s" % [action_type, reason])
	_refresh_field()


func _on_info_message(text: String) -> void:
	_update_info(text)


func _on_card_effect_activated(card_name: String, effect_desc: String, action_type: String, target_id: String, value: int, target_card_name: String, source_slot: int, is_player: bool, target_slot: int, target_is_player: bool) -> void:
	_update_info(" %s: %s" % [card_name, effect_desc])
	_refresh_field()


func _on_discard_requested(count: int, callback_id: int, reason: String) -> void:
	# 玩家需要弃牌：高亮手牌，等待玩家选择
	_update_info("请弃牌 %d 张 (%s)" % [count, reason])
	# TODO: 弃牌UI交互


func _on_deck_search_requested(cards: Array, max_select: int, callback_id: int) -> void:
	# 玩家需要检索卡组：弹出选择窗口
	_update_info("请从卡组选择 %d 张卡" % max_select)
	# TODO: 检索UI交互


func _on_chain_requested(callback_id: int, chainable_cards: Array) -> void:
	# 玩家是否连锁
	_update_info("是否连锁？")
	# TODO: 连锁UI交互


# ============================================================
#  按钮回调
# ============================================================

func _on_view_switch() -> void:
	_cam_state = (_cam_state + 1) % 3
	var labels = ["敌方", "中", "己方"]
	if _view_btn:
		_view_btn.text = " 视角: " + labels[_cam_state]
	if _cam:
		if _cam_tween and _cam_tween.is_valid():
			_cam_tween.kill()
		_cam_tween = create_tween()
		_cam_tween.tween_property(_cam, "position:z", CAM_POS_Z[_cam_state], 0.5).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)


func _on_enter_battle() -> void:
	_game.request_enter_battle()


func _on_end_phase() -> void:
	_game.request_end_phase()


func _on_back() -> void:
	DisplayServer.screen_set_orientation(DisplayServer.SCREEN_PORTRAIT)
	DisplayServer.window_set_size(Vector2i(1080, 1920))
	if _game:
		_game._effect_system.clear()
		if _game._trigger_system:
			_game._trigger_system.clear()
		if _game._constraint_mgr:
			_game._constraint_mgr.clear()
	Global.change_scene("res://Exploration.tscn")


func _exit_tree() -> void:
	DisplayServer.screen_set_orientation(DisplayServer.SCREEN_PORTRAIT)
	DisplayServer.window_set_size(Vector2i(1080, 1920))


# ============================================================
#  槽位点击处理
# ============================================================

func _on_slot_input_event(_camera, event, _position, _normal, _shape_idx, slot_idx: int, is_player: bool) -> void:
	if not (event is InputEventMouseButton):
		return
	if not (event as InputEventMouseButton).pressed:
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	
	if not is_player:
		# 点击敌方槽位 = 选择攻击目标
		if _selected_slot >= 0 and _game.current_phase == BattleGameNew.Phase.BATTLE:
			_game.request_attack(_selected_slot, slot_idx)
			_selected_slot = -1
	else:
		# 点击己方槽位 = 选择攻击者/召唤位置
		if _game.current_phase == BattleGameNew.Phase.BATTLE:
			var card = _game.player_self.field.get_slot(slot_idx)
			if card and card.can_attack():
				_selected_slot = slot_idx
				_update_info("选择攻击目标")
		elif _game.current_phase == BattleGameNew.Phase.MAIN:
			if _selected_hand_idx >= 0 and _game.player_self.field.get_slot(slot_idx) == null:
				_game.request_play_card(_selected_hand_idx, slot_idx)
				_selected_hand_idx = -1
				_refresh_field()


# ============================================================
#  视觉刷新
# ============================================================

func _refresh_field() -> void:
	if _game == null:
		return
	# 刷新敌方场
	for i in range(min(_enemy_slots.size(), 5)):
		var card = _game.player_opp.field.get_slot(i)
		_update_slot_visual(_enemy_slots[i], card, false, i)
	# 刷新己方场
	for i in range(min(_player_slots.size(), 5)):
		var card = _game.player_self.field.get_slot(i)
		_update_slot_visual(_player_slots[i], card, true, i)


func _update_slot_visual(slot_node: Node, card, is_player: bool, slot_idx: int) -> void:
	if slot_node == null:
		return
	var mesh = slot_node as MeshInstance3D
	if mesh == null:
		# 尝试获取子Mesh
		mesh = slot_node.get_node_or_null("CardMesh") as MeshInstance3D
	if mesh == null:
		return
	
	if card == null:
		mesh.visible = false
		return
	
	mesh.visible = true
	# TODO: 根据卡牌数据更新mesh材质、文字标签等
	# 这里先确保显隐正确


func _refresh_hand(is_player: bool) -> void:
	# TODO: 刷新手牌区域3D显示
	pass


func _update_hp_display() -> void:
	# TODO: 更新HP数字显示
	pass


func _update_info(text: String) -> void:
	if _info_label:
		_info_label.text = text
	print("[BattleScene3DNew] ", text)


# ============================================================
#  玩家操作入口（可由UI按钮/手势调用）
# ============================================================

## 玩家选择手牌卡
func player_select_hand_card(hand_idx: int) -> void:
	_selected_hand_idx = hand_idx
	_update_info("选择召唤位置")


## 玩家请求攻击
func player_request_attack(atk_slot: int, def_slot: int) -> void:
	_game.request_attack(atk_slot, def_slot)


## 玩家请求直击
func player_request_attack_hero(atk_slot: int) -> void:
	_game.request_attack_hero(atk_slot)


## 玩家请求召唤
func player_request_summon(hand_idx: int, slot_idx: int) -> void:
	_game.request_play_card(hand_idx, slot_idx)


## 玩家请求进入战斗
func player_request_enter_battle() -> void:
	_game.request_enter_battle()


## 玩家请求结束阶段
func player_request_end_phase() -> void:
	_game.request_end_phase()