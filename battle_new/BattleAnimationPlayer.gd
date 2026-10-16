extends Node2D

## BattleAnimationPlayer - 战斗动画播放器
## 处理所有动画播放逻辑

class_name BattleAnimationPlayer

# 信号
signal animation_completed(animation_type: String)

# 相机控制
var camera: Camera3D = null
var camera_state: int = 2
var camera_tween: Tween = null

# 动画状态
var is_animating: bool = false

# 特效节点
var effect_panels: Array = []

# 飘字
var float_text_pool: Array = []

func _ready() -> void:
	pass

func _process(_delta: float) -> void:
	pass

# ===== 相机控制 =====

func set_camera(cam: Camera3D) -> void:
	camera = cam

func switch_camera(target_state: int) -> void:
	camera_state = target_state
	# 相机切换逻辑由具体场景实现

func restore_camera() -> void:
	# 恢复相机逻辑由具体场景实现

# ===== 卡牌动画 =====

func play_card_summon_animation(card_node: Node3D, target_pos: Vector3, delay: float = 0.0) -> void:
	pass  # 由具体场景实现

func play_card_to_grave_animation(card_node: Node3D, is_player: bool, delay: float = 0.0) -> void:
	pass  # 由具体场景实现

func play_card_to_banish_animation(card_node: Node3D, is_player: bool, delay: float = 0.0) -> void:
	pass  # 由具体场景实现

func play_attack_animation(attacker_node: Node3D, target_node: Node3D) -> void:
	pass  # 由具体场景实现

func play_damage_animation(target_node: Node3D, damage: int, is_player: bool) -> void:
	pass  # 由具体场景实现

func play_heal_animation(target_node: Node3D, heal: int, is_player: bool) -> void:
	pass  # 由具体场景实现

func play_destroy_animation(card_node: Node3D) -> void:
	pass  # 由具体场景实现

func play_discard_animation(card_nodes: Array, is_player: bool, callback_id: int) -> void:
	pass  # 由具体场景实现

# ===== 特效动画 =====

func play_effect_line(from_pos: Vector3, to_pos: Vector3, color: Color, duration: float = 0.3) -> void:
	pass  # 由具体场景实现

func show_effect_panel(card_name: String, effect_desc: String, pos: Vector2) -> void:
	pass  # 由具体场景实现

func remove_effect_panel(panel: Node) -> void:
	pass  # 由具体场景实现

func show_float_text(text: String, pos: Vector3, color: Color, duration: float = 1.0) -> void:
	pass  # 由具体场景实现

# ===== 场地高亮 =====

func highlight_attack_slots(slot_indices: Array, is_player: bool) -> void:
	pass  # 由具体场景实现

func clear_slot_highlights() -> void:
	pass  # 由具体场景实现

func flash_slot_border(slot_idx: int, color: Color, duration: float = 0.5) -> void:
	pass  # 由具体场景实现

# ===== 元素加成 =====

func show_element_boost(boost_type: String, atk_elem: String, def_elem: String, 
                         from_value: int, to_value: int, is_player: bool, source_slot: int) -> void:
	pass  # 由具体场景实现

# ===== 中毒动画 =====

func show_poison_tick(is_player: bool, source_slot: int, damage: int, stacks: int) -> void:
	pass  # 由具体场景实现

# ===== 工具方法 =====

func wait_for_animation_completion() -> void:
	# 等待动画完成逻辑由具体场景实现

func is_busy() -> bool:
	return is_animating

func set_busy(busy: bool) -> void:
	is_animating = busy