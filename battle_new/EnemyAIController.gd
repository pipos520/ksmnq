extends Node
class_name EnemyAIController

## 敌方AI控制器（3D表现层）
## BattleManager内部已有完整的AI决策逻辑（_build_ai_main_phase_queue等）
## 本控制器负责：每帧检查BM的ai_action_queue，驱动3D动画表现
## 由BattleScene3D创建并挂载，通过setup()注入依赖

# === 依赖注入 ===
var _scene: Node3D = null
var _battle_mgr = null
var _driver = null  # BattleDriver（横竖屏共用的战斗节奏驱动器）
var _cam: Camera3D = null
var _card_front_mat: StandardMaterial3D = null
var _card_back_mat: StandardMaterial3D = null
var _card_scene: Resource = null
var _enemy_slots: Array = []       # 5个敌方场地Node3D
var _enemy_hand_nodes: Array = []   # 5个敌方手牌Node3D
var _player_slots: Array = []      # 5个己方场地Node3D（攻击动画用）
var _enemy_card_nodes: Array = []  # 敌方场上卡牌视觉节点引用表（与BM.field[]一一对应）
var _player_card_nodes: Array = [] # 己方场上卡牌视觉节点引用表

# === 状态 ===
var _is_animating: bool = false     # 是否正在播放动画

# === 配置 ===
const ENEMY_SUMMON_FLY_DURATION: float = 0.6
const ENEMY_ATTACK_FLY_DURATION: float = 0.35
const ENEMY_CARD_SCALE: Vector3 = Vector3(0.4, 1.0, 0.56)
const CARD_SCENE_PATH = "res://battle_new/BattleCard3D.tscn"

# === 拖尾粒子颜色表（品质 → 颜色） ===
const TRAIL_COLORS: Dictionary = {
	"废品": Color(0.62, 0.62, 0.62, 1.0),   # 灰色 #9E9E9E
	"瑕疵": Color(0.31, 0.76, 0.97, 1.0),   # 天蓝 #4FC3F7
	"标准": Color(0.51, 0.78, 0.52, 1.0),   # 绿色 #81C784
	"卓越": Color(1.00, 0.84, 0.31, 1.0),   # 金黄 #FFD54F
	"完美": Color(0.90, 0.22, 0.21, 1.0),   # 红色 #E53935
}

var _attack_trail: GPUParticles3D = null


## 初始化，注入依赖
func setup(scene: Node3D, battle_mgr, driver, cam: Camera3D, card_front_mat: StandardMaterial3D, card_back_mat: StandardMaterial3D, enemy_slots: Array, enemy_hand_nodes: Array, player_slots: Array, enemy_card_nodes: Array, player_card_nodes: Array) -> void:
	_scene = scene
	_battle_mgr = battle_mgr
	_driver = driver
	_cam = cam
	_card_front_mat = card_front_mat
	_card_back_mat = card_back_mat
	_enemy_slots = enemy_slots
	_enemy_hand_nodes = enemy_hand_nodes
	_player_slots = player_slots
	_enemy_card_nodes = enemy_card_nodes
	_player_card_nodes = player_card_nodes
	_card_scene = load(CARD_SCENE_PATH)
	# 连接驱动器信号：本类只负责 3D 表现，节奏由 BattleDriver 统一控制
	if _driver:
		_driver.enemy_draw_animation_requested.connect(_play_enemy_draw_animation)
		_driver.enemy_summon_animation_requested.connect(_play_enemy_summon_animation)
		_driver.enemy_attack_animation_requested.connect(_play_enemy_attack_animation)


## 动画播放完成：解除自身动画状态并通知驱动器继续推进回合
func _finish_anim() -> void:
	_is_animating = false
	if _driver and _driver.has_method("report_animation_done"):
		_driver.report_animation_done()


## 敌方AI驱动已迁移至 battle_core/BattleDriver.gd（横竖屏共用同一驱动协议）
## 本控制器退化为纯 3D 表现层：由 BattleDriver 的信号触发动画，播完回调通知驱动器
## 连接方式：BattleScene3D 创建 Driver 后经 setup() 注入，内部自动连接以下信号：
##   - enemy_draw_animation_requested()          → _play_enemy_draw_animation（自发播放，不阻塞）
##   - enemy_summon_animation_requested(slot)    → _play_enemy_summon_animation（播完 _finish_anim 通知）
##   - enemy_attack_animation_requested(...)     → _play_enemy_attack_animation（撞击 report_attack_impact，播完 _finish_anim）


# ===== 内部方法 =====

## 敌方抽牌动画：卡牌从敌方卡组飞到敌方手牌区
## 由 BattleDriver.enemy_draw_animation_requested 信号触发（自发播放，不阻塞驱动；
## 阶段推进由驱动器负责，此处不再调用 advance_enemy_phase）
func _play_enemy_draw_animation() -> void:
	if _battle_mgr == null:
		return
	_is_animating = true

	var enemy = _battle_mgr.player_opponent
	if not enemy:
		_is_animating = false
		return

	# 获取手牌数量，决定飞几张牌
	var hand_count = enemy.hand.size()
	# 先手第一回合跳过抽牌（BM已处理），这里只处理正常抽牌
	if hand_count == 0:
		# 没抽到牌，无需表现（推进由驱动器负责）
		_is_animating = false
		return
	
	# 抽牌动画：从卡组飞到手牌区（只飞最后抽到的那张）
	var deck_pos = Vector3(0, 0.15, -3.4)  # 敌方卡组位置
	var hand_pos = Vector3(0, 0.23, -3.4)  # 敌方手牌区中间位置
	
	# 获取卡牌数据
	var card_data: Dictionary = {}
	var card = enemy.hand[enemy.hand.size() - 1] if enemy.hand.size() > 0 else null
	if card:
		card_data = {
			"name": card.get_display_name(),
			"atk": card.current_atk,
			"hp": card.current_hp,
			"cost": card.base_cost,
			"element": card.get_effective_element(),
		}
	
	# 创建飞行卡牌（背面朝上，因为是对方的牌）
	var fly_card = _create_fly_card(deck_pos, true, card_data)
	if not fly_card:
		_is_animating = false
		return
	
	# 贝塞尔弧线飞向手牌区
	var mid_pos = (deck_pos + hand_pos) * 0.5 + Vector3(0, 1.0, 0)
	var tween = _scene.create_tween()
	tween.tween_method(func(t: float):
		if is_instance_valid(fly_card):
			var p = deck_pos.lerp(mid_pos, t).lerp(mid_pos.lerp(hand_pos, t), t)
			fly_card.global_position = p
	, 0.0, 1.0, 0.6).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	
	# 完成后清理（阶段推进由 BattleDriver 负责）
	tween.tween_callback(func():
		if is_instance_valid(fly_card):
			fly_card.queue_free()
		_is_animating = false
		print("[EnemyAI] 敌方抽牌动画完成")
	)


## 敌方召唤入场动画：直接创建真实卡牌节点从卡组飞到场地卡槽
## 由 BattleDriver.enemy_summon_animation_requested 信号触发，播完 _finish_anim 通知驱动器
func _play_enemy_summon_animation(slot_idx: int) -> void:
	if _battle_mgr == null or slot_idx < 0 or slot_idx >= _enemy_slots.size():
		_finish_anim()
		return
	_is_animating = true
	# 敌方召唤音效
	Global.play_sfx("deal_alt")

	var slot_node = _enemy_slots[slot_idx]
	if not slot_node:
		_finish_anim()
		return
	
	# 从BM获取敌方场地上的卡牌数据
	var card_data: Dictionary = {}
	var enemy = _battle_mgr.player_opponent
	if enemy and slot_idx < enemy.field.size() and enemy.field[slot_idx]:
		var card = enemy.field[slot_idx]
		card_data = {
			"name": card.get_display_name(),
			"atk": card.current_atk,
			"hp": card.current_hp,
			"cost": card.base_cost,
			"element": card.get_effective_element(),
		}
	
	# 获取敌方卡组位置作为起点
	var deck_pos = Vector3(0, 0.15, -3.4)  # 默认敌方卡组位置
	var start_pos = deck_pos + Vector3(0, 1.5, 0)  # 从上方
	var end_pos = slot_node.global_position + Vector3(0, 0.15, 0)
	var mid_pos = (start_pos + end_pos) * 0.5 + Vector3(0, 1.2, 0)  # 弧线中间抬高
	
	# 直接创建真实卡牌节点（先加到场景根做飞行动画）
	var card_node = _card_scene.instantiate() as Node3D if _card_scene else null
	if not card_node:
		# fallback: 用临时卡牌
		var fly_card = _create_fly_card(start_pos, true, card_data)
		if not fly_card:
			_is_animating = false
			return
		_fly_temp_card_to_slot(fly_card, start_pos, end_pos, mid_pos, slot_idx)
		return
	
	# 加到场景根做飞行动画
	_scene.add_child(card_node)
	card_node.global_position = start_pos
	# 不设scale，保持默认1.0（和_show_enemy_card_on_slot一致）
	# setup（先add_child再setup，确保@onready变量已初始化）
	if card_node.has_method("setup"):
		card_node.setup(card_data, _card_front_mat, _card_back_mat)
	# 先背面朝上
	if card_node.has_method("set_face_down"):
		card_node.set_face_down(_card_back_mat)
	# 提前写入引用表，防止动画期间_refresh_enemy_field_display重复创建
	if slot_idx < _enemy_card_nodes.size():
		_enemy_card_nodes[slot_idx] = card_node
	
	# 飞入动画（一次性贝塞尔弧线，无停顿）
	var tween = _scene.create_tween()
	# 全程贝塞尔：start → mid(抬高) → end，一次完成
	tween.tween_method(func(t: float):
		if is_instance_valid(card_node):
			# 二次贝塞尔曲线：B(t) = (1-t)²·P0 + 2(1-t)t·P1 + t²·P2
			var p0 = start_pos
			var p1 = mid_pos
			var p2 = end_pos
			var u = 1.0 - t
			var p = u * u * p0 + 2.0 * u * t * p1 + t * t * p2
			card_node.global_position = p
			# 到达50%时翻面
			if t >= 0.5 and card_node.has_method("set_face_up"):
				card_node.set_face_up()
	, 0.0, 1.0, ENEMY_SUMMON_FLY_DURATION).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	
	# 完成后：reparent到卡位，写入引用表，通知驱动器继续
	tween.tween_callback(func():
		if is_instance_valid(card_node) and slot_node:
			card_node.name = "EnemyCard"
			card_node.reparent(slot_node, true)
			card_node.position = Vector3(0, 0.15, 0)
			# 写入引用表
			if slot_idx < _enemy_card_nodes.size():
				_enemy_card_nodes[slot_idx] = card_node
		_finish_anim()
	)
	
	print("[EnemyAI] 敌方入场动画（真卡）: 槽位 %d" % slot_idx)


## 敌方攻击动画：敌方场上卡牌飞向己方目标，撞击后飞回
## 由 BattleDriver.enemy_attack_animation_requested 信号触发；
## 撞击瞬间回调驱动器结算伤害，播完 _finish_anim 通知驱动器
func _play_enemy_attack_animation(attacker_slot: int, target_slot: int, is_hero: bool) -> void:
	if _battle_mgr == null:
		_finish_anim()
		return
	_is_animating = true

	if attacker_slot < 0 or attacker_slot >= _enemy_slots.size():
		_finish_anim()
		return

	var attacker_node = _enemy_slots[attacker_slot]
	if not attacker_node:
		_finish_anim()
		return
	
	# 从引用表直接取卡牌节点
	var card_node = null
	if attacker_slot < _enemy_card_nodes.size():
		card_node = _enemy_card_nodes[attacker_slot]
	
	if not card_node or not is_instance_valid(card_node):
		# fallback: 没有视觉节点时用临时卡牌
		var card_data: Dictionary = {}
		var enemy = _battle_mgr.player_opponent
		if enemy and attacker_slot < enemy.field.size() and enemy.field[attacker_slot]:
			var card = enemy.field[attacker_slot]
			card_data = {
				"name": card.get_display_name(),
				"atk": card.current_atk,
				"hp": card.current_hp,
				"cost": card.base_cost,
				"element": card.get_effective_element(),
			}
		var start_pos_fb = attacker_node.global_position + Vector3(0, 0.15, 0)
		var fly_card = _create_fly_card(start_pos_fb, false, card_data)
		if not fly_card:
			_finish_anim()
			return
		_animate_fly_card_attack(fly_card, start_pos_fb, target_slot, is_hero, attacker_slot, true)
		return
	
	# 正常流程：直接移动真正的场上卡牌
	var start_pos = attacker_node.global_position + Vector3(0, 0.15, 0)
	var orig_parent = card_node.get_parent()
	
	# reparent 到场景根做全局飞行
	card_node.reparent(_scene, true)
	card_node.global_position = start_pos
	
	_animate_fly_card_attack(card_node, start_pos, target_slot, is_hero, attacker_slot, false, orig_parent)


## 通用攻击飞行动画（卡牌节点可能是真卡或临时卡）
func _animate_fly_card_attack(card_node: Node, start_pos: Vector3, target_slot: int, is_hero: bool, attacker_slot: int, is_temp_card: bool, orig_parent: Node = null) -> void:
	var target_pos: Vector3
	if is_hero:
		target_pos = Vector3(0, 0.15, 3.0)
	else:
		if target_slot < 0 or target_slot >= _player_slots.size():
			_finish_anim()
			return
		var target_node = _player_slots[target_slot]
		if not target_node:
			_finish_anim()
			return
		target_pos = target_node.global_position + Vector3(0, 0.15, 0)
	
	# 保存原材质用于恢复
	var orig_mat = null
	var mesh = card_node.get_node_or_null("CardMesh") as MeshInstance3D
	if mesh:
		orig_mat = mesh.material_override
	
	# ★ 拖尾粒子（根据攻击卡牌品质）
	var quality = _get_enemy_card_quality(attacker_slot)
	_spawn_attack_trail(card_node, quality)
	
	var tween = _scene.create_tween()
	# 记录相机起始位置，用于平滑过渡
	var cam_start_pos = _cam.global_position
	# ★ 阶段1：卡牌上升（0.15s，向上抬起1.5单位）
	var rise_pos = start_pos + Vector3(0, 1.5, 0)
	tween.tween_property(card_node, "global_position", rise_pos, 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	# 相机X固定，Z跟卡牌Z，Y保持标准高度（卡牌在屏幕上下中间）
	var rise_cam_target = Vector3(_scene.CAM_POS_X, _scene.CAM_POS_Y, rise_pos.z)
	tween.parallel().tween_method(func(t: float):
		if _cam:
			_cam.global_position = cam_start_pos.lerp(rise_cam_target, t)
	, 0.0, 1.0, 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	
	# ★ 阶段2：俯冲撞击（相机X固定，Z跟卡牌Z，保持卡牌在屏幕上下中间）
	tween.tween_property(card_node, "global_position", target_pos, ENEMY_ATTACK_FLY_DURATION).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	var target_cam_pos = Vector3(_scene.CAM_POS_X, _scene.CAM_POS_Y, target_pos.z)
	tween.parallel().tween_method(func(t: float):
		if _cam:
			_cam.global_position = rise_cam_target.lerp(target_cam_pos, t)
	, 0.0, 1.0, ENEMY_ATTACK_FLY_DURATION).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	
	# 撞击：闪光 + 被攻击卡后退 + 攻击卡闪白 + 停止拖尾
	tween.tween_callback(func():
		# ★ 停止拖尾粒子
		if _attack_trail and is_instance_valid(_attack_trail):
			_attack_trail.emitting = false
		# 攻击撞击音效
		Global.play_sfx("attack_hit")
		_play_hit_flash(target_pos)
		# 攻击卡闪白
		if mesh and is_instance_valid(mesh):
			var flash = StandardMaterial3D.new()
			flash.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			flash.albedo_color = Color.WHITE
			mesh.material_override = flash
		# 被攻击卡后退
		if not is_hero and target_slot >= 0 and target_slot < _player_slots.size() and _player_slots[target_slot]:
			var target_card = _player_card_nodes[target_slot] if target_slot < _player_card_nodes.size() else null
			if not target_card or not is_instance_valid(target_card):
				target_card = _player_slots[target_slot].get_node_or_null("PlayerCard")
			if target_card and is_instance_valid(target_card):
				var orig_pos = target_card.global_position
				var push_back = orig_pos + Vector3(0, 0, 0.25)
				var shake_tween = _scene.create_tween()
				shake_tween.tween_property(target_card, "global_position", push_back, 0.08).set_ease(Tween.EASE_OUT)
				shake_tween.tween_property(target_card, "global_position", orig_pos, 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BOUNCE)
	)
	# 等shake完成
	tween.tween_interval(0.25)
	# 执行实际伤害
	tween.tween_callback(func():
		# 攻击飘窗
		if _scene and _scene.has_method("show_attack_popup"):
			var enemy = _battle_mgr.player_opponent
			if enemy and attacker_slot >= 0 and attacker_slot < enemy.field.size() and enemy.field[attacker_slot]:
				var card = enemy.field[attacker_slot]
				var atk_name = card.get_display_name()
				var atk_atk = card.current_atk
				var tgt_name = "英雄"
				if not is_hero and target_slot >= 0 and _battle_mgr.player_self and target_slot < _battle_mgr.player_self.field.size():
					var target_card_data = _battle_mgr.player_self.field[target_slot]
					if target_card_data:
						tgt_name = target_card_data.get_display_name()
				_scene.show_attack_popup(atk_name, tgt_name, atk_atk, false)
		# 撞击瞬间：通知驱动器结算伤害（由驱动器调用 BattleManager._execute_pending_enemy_attack）
		if _driver and _driver.has_method("report_attack_impact"):
			_driver.report_attack_impact()
	)
	# 恢复材质
	tween.tween_interval(0.1)
	tween.tween_callback(func():
		if mesh and is_instance_valid(mesh) and orig_mat:
			mesh.material_override = orig_mat
	)
	# 飞回（相机从追踪位置平滑回敌方视角）
	var return_cam_pos = Vector3(_scene.CAM_POS_X, _scene.CAM_POS_Y, _scene.CAM_POS_Z[0])
	tween.tween_property(card_node, "global_position", start_pos, ENEMY_ATTACK_FLY_DURATION * 0.8).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	# 相机从当前追踪位置平滑回敌方视角
	var cam_track_end = _cam.global_position
	tween.parallel().tween_method(func(t: float):
		if _cam:
			_cam.global_position = cam_track_end.lerp(return_cam_pos, t)
	, 0.0, 1.0, ENEMY_ATTACK_FLY_DURATION * 0.8).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	# 完成
	tween.tween_callback(func():
		# ★ 销毁拖尾粒子
		_remove_attack_trail()
		# 恢复相机到标准位置和默认朝向（不 look_at，避免倾斜）
		if _cam:
			_cam.global_position = Vector3(_scene.CAM_POS_X, _scene.CAM_POS_Y, _scene.CAM_POS_Z[0])
			_cam.rotation_degrees = Vector3(-90, 0, 0)
		if is_temp_card:
			if is_instance_valid(card_node):
				card_node.queue_free()
		else:
			# 真卡：reparent 回敌方卡位
			if is_instance_valid(card_node) and orig_parent:
				card_node.reparent(orig_parent, true)
				card_node.position = Vector3(0, 0.15, 0)
		_refresh_enemy_field()
		if _scene and _scene.has_method("_refresh_player_field_display"):
			_scene._refresh_player_field_display()
		_finish_anim()
	)

	var target_desc = "英雄" if is_hero else "槽位%d" % target_slot
	print("[EnemyAI] 敌方攻击动画: %d → %s" % [attacker_slot, target_desc])


## 获取敌方场上卡牌品质
func _get_enemy_card_quality(slot_idx: int) -> String:
	if _battle_mgr and _battle_mgr.player_opponent:
		var field = _battle_mgr.player_opponent.field
		if slot_idx >= 0 and slot_idx < field.size() and field[slot_idx]:
			var card = field[slot_idx]
			var q = card.quality if card.get("quality") != null else "标准"
			if q == "" or q == null:
				q = "标准"
			return q
	return "标准"


## 创建攻击拖尾粒子（火焰效果，挂载在卡牌下方）
func _spawn_attack_trail(card_node: Node, quality: String) -> void:
	_remove_attack_trail()
	var trail_color = TRAIL_COLORS.get(quality, TRAIL_COLORS["标准"])
	
	_attack_trail = GPUParticles3D.new()
	_attack_trail.name = "EnemyAttackTrail"
	_attack_trail.emitting = true
	_attack_trail.amount = 150  # 火焰粒子不需要太多
	_attack_trail.lifetime = 0.5  # 火焰持续稍长
	
	var ppm = ParticleProcessMaterial.new()
	ppm.lifetime_randomness = 0.4  # 火焰生命周期差异大
	# 拖烟轨迹：卡牌往 -Z 飞，粒子往 +Z 拖（向后）
	ppm.direction = Vector3(0, 0, 1)  # 正后方
	ppm.initial_velocity_min = 1.5  # 拖烟速度适中
	ppm.initial_velocity_max = 3.0
	ppm.spread = 25.0  # 扩散小，保持轨迹感
	ppm.gravity = Vector3(0, -0.5, 0)  # 轻微下沉（烟雾感）
	ppm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	ppm.emission_shape_scale = Vector3(0.15, 0.15, 0.1)  # 小发射区域，集中拖尾
	# 拖烟从大到小（开始大，消散小）
	ppm.scale_min = 0.03
	ppm.scale_max = 0.2
	# 颜色渐变：品质色 → 透明（火焰形状通过缩放和发射形状实现）
	var grad = Gradient.new()
	grad.add_point(0.0, trail_color)                                    # 核心：品质色（亮）
	grad.add_point(0.5, Color(trail_color.r, trail_color.g, trail_color.b, 0.8))  # 中段：稍淡
	grad.add_point(1.0, Color(trail_color.r, trail_color.g, trail_color.b, 0.0))  # 尾端：透明
	var grad_tex = GradientTexture1D.new()
	grad_tex.gradient = grad
	ppm.color_ramp = grad_tex
	_attack_trail.process_material = ppm
	
	# 粒子 mesh（用 QuadMesh 做广告牌粒子）
	var pm = QuadMesh.new()
	pm.size = Vector2(0.12, 0.12)
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)  # 白色基础色，由color_ramp控制
	mat.no_depth_test = true
	mat.render_priority = 10
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	pm.material = mat
	_attack_trail.draw_pass_1 = pm
	
	# 挂载到卡牌节点下方（火焰从卡牌底部喷出）
	card_node.add_child(_attack_trail)
	_attack_trail.position = Vector3(0, -0.2, 0)  # 卡牌下方


## 移除拖尾粒子
func _remove_attack_trail() -> void:
	if _attack_trail:
		if is_instance_valid(_attack_trail):
			_attack_trail.queue_free()
		_attack_trail = null


## fallback：临时卡牌飞入后queue_free，再刷新场地
func _fly_temp_card_to_slot(fly_card: Node3D, start_pos: Vector3, end_pos: Vector3, mid_pos: Vector3, slot_idx: int) -> void:
	var tween = _scene.create_tween()
	tween.tween_method(func(t: float):
		if is_instance_valid(fly_card):
			var p = start_pos.bezier_interpolate(end_pos, mid_pos, mid_pos, t)
			fly_card.global_position = p
	, 0.0, 0.5, ENEMY_SUMMON_FLY_DURATION * 0.5).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(func():
		if is_instance_valid(fly_card) and fly_card.has_method("set_face_up"):
			fly_card.set_face_up()
	)
	tween.tween_method(func(t: float):
		if is_instance_valid(fly_card):
			var p = start_pos.bezier_interpolate(end_pos, mid_pos, mid_pos, t)
			fly_card.global_position = p
	, 0.5, 1.0, ENEMY_SUMMON_FLY_DURATION * 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(func():
		if is_instance_valid(fly_card):
			fly_card.queue_free()
		_refresh_enemy_field()
		_finish_anim()
	)
	print("[EnemyAI] 敌方入场动画（fallback）: 槽位 %d" % slot_idx)


## 创建临时飞行卡牌
func _create_fly_card(pos: Vector3, face_down: bool, card_data: Dictionary = {}) -> Node3D:
	if not _card_scene:
		return null
	var card = _card_scene.instantiate() as Node3D
	if not card:
		return null
	_scene.add_child(card)
	card.global_position = pos
	# 不设scale，保持默认1.0
	# 设置材质和数据（先add_child再setup，确保@onready变量已初始化）
	if card.has_method("setup"):
		card.setup(card_data, _card_front_mat, _card_back_mat)
	if face_down:
		if card.has_method("set_face_down"):
			card.set_face_down(_card_back_mat)
	else:
		if card.has_method("set_face_up"):
			card.set_face_up()
	return card


## 撞击闪烁效果
func _play_hit_flash(pos: Vector3) -> void:
	var flash = MeshInstance3D.new()
	var quad = QuadMesh.new()
	quad.size = Vector2(0.5, 0.7)
	flash.mesh = quad
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.5, 0.2, 0.8)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	flash.material_override = mat
	_scene.add_child(flash)
	flash.global_position = pos
	
	var tween = _scene.create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.2)
	tween.tween_callback(func(): flash.queue_free())


## 刷新敌方场地显示
func _refresh_enemy_field() -> void:
	# 通知BattleScene3D刷新敌方场地卡牌
	if _scene and _scene.has_method("_refresh_enemy_field_display"):
		_scene._refresh_enemy_field_display()


## 是否正在播放动画
func is_animating() -> bool:
	return _is_animating
