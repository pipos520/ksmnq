extends Node
class_name CardDragController

## 卡牌拖拽控制器
## 管理拖拽状态、抛物线指示线、松手判定
## 由BattleScene3D创建并挂载，通过setup()注入依赖

# === 依赖注入 ===
var _scene: Node3D = null          # BattleScene3D引用
var _cam: Camera3D = null
var _player_slots: Array = []      # 5个己方场地Node3D
var _player_hand_nodes: Array = []  # 5个手牌Node3D
var _player_hand_cards: Array = []  # BattleCard3D[5]
var _player_hand_datas: Array = []  # card_data[5]
var _card_front_mat: StandardMaterial3D = null
var _field_mgr: Node = null        # FieldSlotManager引用
var _battle_mgr = null             # BattleManager引用
var _enemy_slots: Array = []       # 5个敌方场地Node3D（攻击拖拽用）
var _enemy_card_nodes: Array = []  # 敌方场上卡牌视觉节点引用表（与BM.field[]一一对应）
var _player_card_nodes: Array = [] # 己方场上卡牌视觉节点引用表

# === 拖拽状态 ===
var _is_dragging: bool = false
var _is_attack_drag: bool = false    # true=攻击拖拽(场地卡→敌方), false=召唤拖拽(手牌→场地)
var _drag_hand_index: int = -1
var _drag_slot_index: int = -1       # 攻击拖拽时，己方场地卡位索引
var _drag_line: MeshInstance3D = null  # 抛物线指示线
var _drag_line_mesh: ImmediateMesh = null
var _drag_card_mesh: MeshInstance3D = null  # 跟随手指的卡牌预览
var _drag_card_node: Node = null      # 拖拽开始时保存的卡牌节点（防hand_changed重建错位）
var _drag_card_data: Variant = null   # 拖拽开始时保存的卡牌数据
var _is_attack_animating: bool = false # 攻击动画串行锁
var _pending_player_attack: Dictionary = {}  # 玩家攻击pending（动画撞击后执行）

# === 配置 ===
const DRAG_LINE_WIDTH: float = 0.08
const DRAG_LINE_COLOR = Color(0.976, 0.827, 0.443, 0.6)
const ATTACK_LINE_COLOR = Color(1.0, 0.3, 0.3, 0.7)  # 攻击拖拽线（红色）
const DRAG_PREVIEW_SCALE: float = 0.6
const SLOT_HIGHLIGHT_COLOR = Color(0.2, 1.0, 0.3, 0.5)
const ENEMY_HIGHLIGHT_COLOR = Color(1.0, 0.2, 0.2, 0.5)  # 敌方卡位高亮（攻击目标）
const SHAKE_DURATION: float = 0.3
const SHAKE_AMPLITUDE: float = 0.08
const SUMMON_FLY_DURATION: float = 0.7
const ATTACK_FLY_DURATION: float = 0.3

# 品质 → 拖尾颜色映射
const TRAIL_COLORS := {
	"废品":  Color(0.62, 0.62, 0.62, 1.0),   # 灰色 #9E9E9E
	"瑕疵":  Color(0.31, 0.76, 0.97, 1.0),   # 天蓝 #4FC3F7
	"标准":  Color(0.51, 0.78, 0.52, 1.0),   # 绿色 #81C784
	"卓越":  Color(1.00, 0.84, 0.31, 1.0),   # 金黄 #FFD54F
	"完美":  Color(0.90, 0.22, 0.21, 1.0),   # 红色 #E53935
}
# 当前攻击拖尾粒子节点
var _attack_trail: GPUParticles3D = null


## 获取攻击卡牌品质（优先从 BM.field 取，再兜底场景缓存）
func _get_attacker_quality(slot_idx: int) -> String:
	if _battle_mgr and _battle_mgr.player_self and slot_idx >= 0 and slot_idx < _battle_mgr.player_self.field.size():
		var card = _battle_mgr.player_self.field[slot_idx]
		if card and card.has_method("get_effective_element"):
			var q = card.quality if "quality" in card else "标准"
			if q == "": q = "标准"
			return q
	return "标准"


## 创建攻击拖尾粒子（火焰效果，挂载在卡牌下方）
func _spawn_attack_trail(card_node: Node, quality: String) -> void:
	_remove_attack_trail()
	var trail_color = TRAIL_COLORS.get(quality, TRAIL_COLORS["标准"])
	
	_attack_trail = GPUParticles3D.new()
	_attack_trail.name = "AttackTrail"
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


## 初始化，注入依赖
func setup(scene: Node3D, cam: Camera3D, player_slots: Array, enemy_slots: Array, player_hand_nodes: Array, player_hand_cards: Array, player_hand_datas: Array, card_front_mat: StandardMaterial3D, field_mgr = null, battle_mgr = null, enemy_card_nodes: Array = [], player_card_nodes: Array = []) -> void:
	_scene = scene
	_cam = cam
	_player_slots = player_slots
	_enemy_slots = enemy_slots
	_player_hand_nodes = player_hand_nodes
	_player_hand_cards = player_hand_cards
	_player_hand_datas = player_hand_datas
	_card_front_mat = card_front_mat
	_field_mgr = field_mgr
	_battle_mgr = battle_mgr
	_enemy_card_nodes = enemy_card_nodes
	_player_card_nodes = player_card_nodes


## 开始拖拽某张手牌
## 返回 true 表示可以拖拽，false 表示能量不足或无法拖拽
func start_drag(hand_idx: int) -> bool:
	if hand_idx < 0 or hand_idx >= _player_hand_cards.size():
		return false
	if _player_hand_cards[hand_idx] == null:
		return false
	# 能量检查：卡牌费用 > 当前能量 → 拒绝拖拽 + 抖动
	var cost: int = 0
	var card_data = _player_hand_datas[hand_idx]
	if card_data != null and card_data is Dictionary:
		cost = card_data.get("cost", card_data.get("energy_cost", card_data.get("base_cost", 0)))
		if _battle_mgr and _battle_mgr.has_method("get_player_energy"):
			var current_energy = _battle_mgr.get_player_energy()
			if cost > current_energy:
				print("[CardDragController] 能量不足: 需要 %d, 当前 %d" % [cost, current_energy])
				_shake_hand_card(hand_idx)
				return false
	_is_dragging = true
	_drag_hand_index = hand_idx
	# 保存拖拽卡片的节点与数据引用（hand_changed 会重建槽位，必须提前保存）
	_drag_card_node = _player_hand_cards[hand_idx]
	_drag_card_data = _player_hand_datas[hand_idx]
	# 创建抛物线
	_create_drag_line()
	# 高亮可用卡位
	_highlight_slots(true)
	print("[CardDragController] 开始拖拽手牌 %d (费用:%d)" % [hand_idx, cost])
	return true


## 拖拽中，更新指示线
func update_drag(screen_pos: Vector2) -> void:
	if not _is_dragging:
		return
	_update_drag_line(screen_pos)


## 松手，判定是否落在卡位上
## 返回 true 表示成功召唤到场地，false 表示取消
func end_drag(screen_pos: Vector2) -> bool:
	if not _is_dragging:
		return false
	_is_dragging = false
	_clear_drag_line()
	_highlight_slots(false)
	_highlight_enemy_slots(false)
	
	# 如果是攻击拖拽 → 走攻击分支
	if _is_attack_drag:
		_is_attack_drag = false
		var result = _end_attack_drag(screen_pos)
		_drag_slot_index = -1
		return result
	
	# ===== 召唤拖拽（手牌→场地） =====
	# ... 原有召唤拖拽逻辑 ...
	var card_node = _drag_card_node
	var card_data = _drag_card_data
	var hand_idx = _drag_hand_index
	_drag_card_node = null
	_drag_card_data = null
	
	var slot_idx = _get_slot_at_screen_pos(screen_pos)
	if slot_idx >= 0 and slot_idx < 5 and card_node:
		# ★ 提前将被拖卡从手牌槽摘出（reparent到场景根 + 清槽位引用），
		#   这样 do_action 触发 hand_changed 重建时不会污染/清掉这张卡
		var hand_node = _player_hand_nodes[hand_idx] if hand_idx >= 0 and hand_idx < _player_hand_nodes.size() else null
		card_node.reparent(_scene, true)
		if hand_idx >= 0 and hand_idx < _player_hand_cards.size():
			_player_hand_cards[hand_idx] = null
			_player_hand_datas[hand_idx] = null
		
		# 先调用BattleManager.do_action("summon") 做能量检查和数据层召唤
		if _battle_mgr and _battle_mgr.has_method("do_action"):
			var result = _battle_mgr.do_action("summon", {
				"hand_index": hand_idx,
				"slot_index": slot_idx
			})
			if result.get("success", false):
				print("[CardDragController] 召唤成功 手牌 %d → 卡位 %d" % [hand_idx, slot_idx])
				# 召唤成功音效
				Global.play_sfx("deal")
				_drag_hand_index = -1
				# 教学战推进
				if _scene and _scene.has_method("_advance_tutorial_step"):
					_scene._advance_tutorial_step("summon")
				# ★ 通用流程：飞到场地 → 入驻 → 执行效果 → 检查送墓
				# 从 BM 取最新卡牌数据（可能有效果修改过属性）
				var bm_card = null
				if _battle_mgr and _battle_mgr.player_self and slot_idx < _battle_mgr.player_self.field.size():
					bm_card = _battle_mgr.player_self.field[slot_idx]
				if bm_card and _scene and _scene.has_method("_battle_card_to_dict"):
					card_data = _scene._battle_card_to_dict(bm_card)
				# 飞入动画 + 数据转移（内部含效果执行和送墓判定）
				if card_node and card_data:
					if card_node.has_method("update_data"):
						card_node.update_data(card_data)
					_fly_card_to_slot_ext(hand_idx, slot_idx, card_node, card_data)
				return true
			else:
				print("[CardDragController] 召唤失败: %s" % result.get("reason", "未知原因"))
				_drag_hand_index = -1
				# 召唤失败 → 卡牌放回手牌
				if hand_node and card_node.is_inside_tree():
					card_node.reparent(hand_node, true)
					card_node.position = Vector3(0, 0, 0.02)
					card_node.visible = true
				if hand_idx >= 0 and hand_idx < _player_hand_cards.size():
					_player_hand_cards[hand_idx] = card_node
					_player_hand_datas[hand_idx] = card_data
				if _scene and _scene.has_method("_on_player_hand_changed"):
					_scene._on_player_hand_changed()
				return false
		else:
			# 没有BattleManager → 纯UI模式飞入
			print("[CardDragController] 无BattleManager, 纯UI飞入 手牌 %d → 卡位 %d" % [hand_idx, slot_idx])
			_drag_hand_index = -1
			if card_node:
				_fly_card_to_slot_ext(hand_idx, slot_idx, card_node, card_data)
			return true
	
	# 没有放到卡位上，取消
	_drag_hand_index = -1
	if card_node and card_node.is_inside_tree():
		card_node.visible = true
	return false


## 是否正在拖拽
func is_dragging() -> bool:
	return _is_dragging


# ===== 攻击拖拽方法 =====

## 开始攻击拖拽（从场地卡牌拖向敌方）
func start_attack_drag(slot_idx: int) -> bool:
	# 攻击动画播放中禁止新攻击
	if _is_attack_animating:
		return false
	if slot_idx < 0 or slot_idx >= _player_slots.size():
		return false
	if _battle_mgr == null:
		return false
	# 检查是否可攻击（通过 BM 的 can_do_action）
	if _battle_mgr.has_method("can_do_action"):
		var check = _battle_mgr.can_do_action("attack", {"slot": slot_idx})
		if not check.get("allowed", false):
			print("[CardDragController] 不能攻击: %s" % check.get("reason", "未知"))
			_shake_field_card(slot_idx)
			return false
	_is_dragging = true
	_is_attack_drag = true
	_drag_slot_index = slot_idx
	_drag_card_node = _field_mgr.get_card_at(slot_idx) if _field_mgr else null
	_drag_card_data = _field_mgr.get_card_data_at(slot_idx) if _field_mgr else {}
	# 创建攻击抛物线（红色）
	_create_attack_drag_line()
	_highlight_enemy_slots(true)
	print("[CardDragController] 开始攻击拖拽 场地 %d" % [slot_idx])
	return true


## 攻击拖拽松手处理
func _end_attack_drag(screen_pos: Vector2) -> bool:
	var attacker_slot = _drag_slot_index
	var card_node = _drag_card_node
	_drag_card_node = null
	_drag_card_data = null
	
	# 检测松手位置：敌方卡位 / 敌方英雄区
	var target_slot = _get_enemy_slot_at_screen_pos(screen_pos)
	# 检查敌方场上是否有卡牌
	var enemy_has_cards = false
	if _battle_mgr and _battle_mgr.player_opponent:
		for f in _battle_mgr.player_opponent.field:
			if f != null and f.is_alive():
				enemy_has_cards = true
				break
	# 敌方空场时，拖到敌方区域直接攻击英雄
	var direct_attack_hero = (not enemy_has_cards) and target_slot >= 0
	if direct_attack_hero:
		target_slot = -1
	if target_slot >= 0:
		# 检查目标槽位是否有卡牌
		var target_has_card = false
		if _battle_mgr and _battle_mgr.player_opponent:
			var target_card = _battle_mgr.player_opponent.field[target_slot]
			target_has_card = (target_card != null and target_card.is_alive())
		
		if not target_has_card:
			# 目标槽位为空，如果敌方有其他卡牌，则不能攻击（不能越过卡牌打空格）
			if enemy_has_cards:
				print("[CardDragController] 攻击失败: 目标槽位为空，不能攻击空格")
				_drag_slot_index = -1
				return false
			else:
				# 敌方全场为空，转为直接攻击英雄
				target_slot = -1
				direct_attack_hero = true
		
		if target_slot >= 0:
			# 攻击敌方卡牌
			# ★ 先检查可攻击（can_do_action），但延迟执行do_action到动画撞击后
			if _battle_mgr and _battle_mgr.has_method("can_do_action"):
				var check = _battle_mgr.can_do_action("attack", {"slot": attacker_slot, "target_slot": target_slot})
				if not check.get("allowed", false):
					print("[CardDragController] 攻击失败: %s" % check.get("reason", "未知"))
					_drag_slot_index = -1
					return false
			# 设置pending，动画撞击后再执行do_action
			_pending_player_attack = {"slot": attacker_slot, "target_slot": target_slot}
			_drag_slot_index = -1
			_play_attack_animation(attacker_slot, target_slot, card_node)
			return true
	elif _is_hit_enemy_hero(screen_pos) or direct_attack_hero:
		# 攻击敌方英雄
		if _battle_mgr and _battle_mgr.has_method("can_do_action"):
			var check = _battle_mgr.can_do_action("attack_hero", {"slot": attacker_slot})
			if not check.get("allowed", false):
				print("[CardDragController] 攻击英雄失败: %s" % check.get("reason", "未知"))
				_drag_slot_index = -1
				return false
		# 设置pending，动画撞击后再执行do_action
		_pending_player_attack = {"slot": attacker_slot, "target_slot": -1, "is_hero": true}
		_drag_slot_index = -1
		_play_attack_animation(attacker_slot, -1, card_node)
		return true
	
	_drag_slot_index = -1
	return false


## 创建攻击抛物线指示线（红色）
func _create_attack_drag_line() -> void:
	if _drag_line:
		_drag_line.queue_free()
	_drag_line = MeshInstance3D.new()
	_drag_line_mesh = ImmediateMesh.new()
	_drag_line.mesh = _drag_line_mesh
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = ATTACK_LINE_COLOR
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	_drag_line.material_override = mat
	_scene.add_child(_drag_line)


## 更新攻击拖拽线（从场地卡牌位置到手指射线位置）
func update_attack_drag(screen_pos: Vector2) -> void:
	if not _is_dragging or not _is_attack_drag:
		return
	if not _drag_line or not _drag_line_mesh or _drag_slot_index < 0:
		return
	var slot_node = _player_slots[_drag_slot_index]
	if not slot_node:
		return
	var start_pos = slot_node.global_position
	var from = _cam.project_ray_origin(screen_pos)
	var dir = _cam.project_ray_normal(screen_pos)
	var target_pos = from + dir * 10.0
	if dir.y != 0:
		var t = (0.15 - from.y) / dir.y
		if t > 0:
			target_pos = from + dir * t
	var mid = (start_pos + target_pos) * 0.5
	mid.y += 1.0
	_drag_line_mesh.clear_surfaces()
	_drag_line_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	var segments = 20
	for i in range(segments + 1):
		var f = float(i) / float(segments)
		var p = start_pos.lerp(mid, f).lerp(mid.lerp(target_pos, f), f)
		_drag_line_mesh.surface_add_vertex(p)
	_drag_line_mesh.surface_end()
	# 高亮敌方卡位
	var hs = _get_enemy_slot_at_screen_pos(screen_pos)
	_highlight_target_enemy_slot(hs)


## 获取屏幕位置对应的敌方卡位索引
func _get_enemy_slot_at_screen_pos(screen_pos: Vector2) -> int:
	if not _cam:
		return -1
	var from = _cam.project_ray_origin(screen_pos)
	var dir = _cam.project_ray_normal(screen_pos)
	if dir.y == 0:
		return -1
	var t = (0.15 - from.y) / dir.y
	if t <= 0:
		return -1
	var hit = from + dir * t
	for i in range(_enemy_slots.size()):
		if _enemy_slots[i]:
			var slot_pos = _enemy_slots[i].global_position
			var d = Vector2(hit.x - slot_pos.x, hit.z - slot_pos.z).length()
			if d < 0.8:
				return i
	return -1


## 检查屏幕位置是否命中敌方英雄区
func _is_hit_enemy_hero(screen_pos: Vector2) -> bool:
	if not _cam:
		return false
	var from = _cam.project_ray_origin(screen_pos)
	var dir = _cam.project_ray_normal(screen_pos)
	if dir.y == 0:
		return false
	var t = (0.15 - from.y) / dir.y
	if t <= 0:
		return false
	var hit = from + dir * t
	# 敌方英雄区：Z≈-4.5~-3.0, X≈-3.0~3.0
	if hit.z < -3.0 and hit.z > -5.0 and hit.x > -3.5 and hit.x < 3.5:
		return true
	return false


## 高亮/取消所有敌方卡位
func _highlight_enemy_slots(highlight: bool) -> void:
	for slot in _enemy_slots:
		if not slot:
			continue
		var face = slot.get_node_or_null("SlotFace") as MeshInstance3D
		if face:
			if highlight:
				var mat = StandardMaterial3D.new()
				mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				mat.albedo_color = ENEMY_HIGHLIGHT_COLOR
				face.material_override = mat
			else:
				face.material_override = null


## 高亮目标敌方卡位
var _current_enemy_highlight: int = -1
func _highlight_target_enemy_slot(slot_idx: int) -> void:
	if _current_enemy_highlight == slot_idx:
		return
	# 恢复旧的高亮
	if _current_enemy_highlight >= 0 and _current_enemy_highlight < _enemy_slots.size():
		var slot = _enemy_slots[_current_enemy_highlight]
		if slot:
			var face = slot.get_node_or_null("SlotFace") as MeshInstance3D
			if face:
				face.material_override = null
	# 高亮新的
	if slot_idx >= 0 and slot_idx < _enemy_slots.size():
		var slot = _enemy_slots[slot_idx]
		if slot:
			var face = slot.get_node_or_null("SlotFace") as MeshInstance3D
			if face:
				var mat = StandardMaterial3D.new()
				mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				mat.albedo_color = Color(1.0, 0.4, 0.4, 0.7)
				face.material_override = mat
	_current_enemy_highlight = slot_idx


## 场地卡牌抖动（不能攻击时）
func _shake_field_card(slot_idx: int) -> void:
	if slot_idx < 0 or slot_idx >= _player_slots.size():
		return
	var slot_node = _player_slots[slot_idx]
	if not slot_node:
		return
	var original_pos = slot_node.position
	var tween = _scene.create_tween()
	tween.tween_property(slot_node, "position:x", original_pos.x - SHAKE_AMPLITUDE, 0.05)
	tween.tween_property(slot_node, "position:x", original_pos.x + SHAKE_AMPLITUDE, 0.05)
	tween.tween_property(slot_node, "position:x", original_pos.x - SHAKE_AMPLITUDE, 0.05)
	tween.tween_property(slot_node, "position:x", original_pos.x + SHAKE_AMPLITUDE, 0.05)
	tween.tween_property(slot_node, "position", original_pos, 0.08).set_ease(Tween.EASE_OUT)


## 撞击闪烁效果（在指定位置播放一个快速淡出的发光面片）
func _play_hit_flash_at(pos: Vector3) -> void:
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
	# 旋转到水平
	flash.rotation.x = -PI / 2.0
	var tween = _scene.create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.25)
	tween.tween_callback(func():
		if is_instance_valid(flash):
			flash.queue_free()
	)


## 攻击动画：卡牌飞向目标→撞击(被攻击卡后退)→闪烁→飞回
func _play_attack_animation(attacker_slot: int, target_slot: int, card_node: Node) -> void:
	if not card_node:
		return
	# 串行锁
	_is_attack_animating = true
	# 攻击方位置
	var attacker_pos = _player_slots[attacker_slot].global_position if _player_slots[attacker_slot] else Vector3()
	# 目标位置（敌方卡位或敌方英雄区）
	var target_pos: Vector3
	var is_hero = false
	if target_slot >= 0 and target_slot < _enemy_slots.size() and _enemy_slots[target_slot]:
		target_pos = _enemy_slots[target_slot].global_position
	else:
		is_hero = true
		var hero_node = _scene.get_node_or_null("EnemyField/InfoArea")
		if hero_node:
			target_pos = hero_node.global_position + Vector3(0, 0.15, 0)
		else:
			target_pos = Vector3(0, 0.15, -4.0)
	
	# 获取被攻击卡牌节点（非英雄时，从引用表直接取）
	var target_card: Node = null
	if not is_hero and target_slot >= 0 and target_slot < _enemy_card_nodes.size():
		target_card = _enemy_card_nodes[target_slot]
	
	# 保存原材质用于恢复（用_card_front_mat作为可靠回退）
	var mesh = card_node.get_node_or_null("CardMesh") as MeshInstance3D
	var orig_mat = _card_front_mat  # 默认正面材质作为回退
	if mesh and mesh.material_override:
		orig_mat = mesh.material_override
	
	# ★ 杀掉已有相机 tween
	if _scene._cam_tween and _scene._cam_tween.is_valid():
		_scene._cam_tween.kill()
	
	# ★ 拖尾粒子（根据攻击卡牌品质）
	var quality = _get_attacker_quality(attacker_slot)
	card_node.reparent(_scene, true)
	card_node.global_position = attacker_pos
	_spawn_attack_trail(card_node, quality)
	
	if is_hero:
		# ★★★ 攻击英雄：相机追踪模式（卡牌始终在屏幕中心）★★★
		_play_hero_attack_animation(attacker_slot, target_pos, card_node, mesh, orig_mat, target_card)
	else:
		# ★★★ 攻击卡牌：固定视角模式 ★★★
		_play_card_attack_animation(attacker_slot, target_pos, card_node, mesh, orig_mat, target_card)


## 攻击英雄动画（相机追踪卡牌，保持卡牌在屏幕中心）
func _play_hero_attack_animation(attacker_slot: int, target_pos: Vector3, card_node: Node, mesh: MeshInstance3D, orig_mat: Material, target_card: Node) -> void:
	var attacker_pos = _player_slots[attacker_slot].global_position if _player_slots[attacker_slot] else Vector3()
	
	# 更新相机状态
	_scene._cam_state = 0
	if _scene._view_btn:
		_scene._view_btn.text = " 视角: 追踪"
	
	# 相机追踪参数：X固定不动，只跟Y/Z让卡牌保持屏幕上下中间
	# 相机俯视90°，屏幕上下=世界Z，所以相机Z跟卡牌Z，Y保持标准高度
	
	# 记录相机起始位置，用于平滑过渡
	var cam_start_pos = _cam.global_position
	
	var tween = _scene.create_tween()
	# ★ 阶段1：卡牌上升（0.15s，向上抬起1.5单位）
	var rise_pos = attacker_pos + Vector3(0, 1.5, 0)
	tween.tween_property(card_node, "global_position", rise_pos, 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	# 相机X固定，Z跟卡牌Z，Y保持标准高度（卡牌在屏幕上下中间）
	var rise_cam_target = Vector3(_scene.CAM_POS_X, _scene.CAM_POS_Y, rise_pos.z)
	tween.parallel().tween_method(func(t: float):
		if _cam:
			_cam.global_position = cam_start_pos.lerp(rise_cam_target, t)
	, 0.0, 1.0, 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	
	# ★ 阶段2：俯冲撞击（0.3s）- 相机X固定，Z跟卡牌Z，保持卡牌在屏幕上下中间
	tween.tween_property(card_node, "global_position", target_pos, ATTACK_FLY_DURATION).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	var target_cam_pos = Vector3(_scene.CAM_POS_X, _scene.CAM_POS_Y, target_pos.z)
	tween.parallel().tween_method(func(t: float):
		if _cam:
			_cam.global_position = rise_cam_target.lerp(target_cam_pos, t)
	, 0.0, 1.0, ATTACK_FLY_DURATION).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	
	# 撞击
	tween.tween_callback(func():
		if _attack_trail and is_instance_valid(_attack_trail):
			_attack_trail.emitting = false
		Global.play_sfx("attack_hit")
		if mesh and is_instance_valid(mesh):
			var flash = StandardMaterial3D.new()
			flash.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			flash.albedo_color = Color.WHITE
			mesh.material_override = flash
		_play_hit_flash_at(target_pos)
	)
	
	# 等shake完成后执行伤害
	tween.tween_interval(0.25)
	tween.tween_callback(func():
		if not _pending_player_attack.is_empty() and _battle_mgr and _battle_mgr.has_method("do_action"):
			var atk = _pending_player_attack.duplicate()
			_pending_player_attack = {}
			var action_type = "attack_hero"
			var params = {"slot": atk.get("slot", -1)}
			# 攻击飘窗
			if _scene and _scene.has_method("show_attack_popup"):
				var card_data = null
				var atk_slot = atk.get("slot", -1)
				if _battle_mgr.player_self and atk_slot >= 0 and atk_slot < _battle_mgr.player_self.field.size():
					card_data = _battle_mgr.player_self.field[atk_slot]
				if card_data:
					var atk_name = card_data.get_display_name()
					var atk_atk = card_data.current_atk
					_scene.show_attack_popup(atk_name, "敌方英雄", atk_atk, true)
			_battle_mgr.do_action(action_type, params)
			# 刷新双方场地显示（攻击英雄时攻击卡可能受反击）
			if _scene and _scene.has_method("_refresh_player_field_display"):
				_scene._refresh_player_field_display()
			if _scene and _scene.has_method("_refresh_enemy_field_display"):
				_scene._refresh_enemy_field_display()
			if _scene and _scene.has_method("_advance_tutorial_step"):
				_scene._advance_tutorial_step("attack")
	)

	# 恢复材质
	tween.tween_interval(0.1)
	tween.tween_callback(func():
		if mesh and is_instance_valid(mesh):
			mesh.material_override = orig_mat
	)

	# 飞回（相机从追踪位置平滑回己方视角）
	var return_cam_pos = Vector3(_scene.CAM_POS_X, _scene.CAM_POS_Y, _scene.CAM_POS_Z[2])
	tween.tween_property(card_node, "global_position", attacker_pos, ATTACK_FLY_DURATION * 0.8).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	# 相机从当前追踪位置平滑回己方视角
	var cam_track_end = _cam.global_position
	tween.parallel().tween_method(func(t: float):
		if _cam:
			_cam.global_position = cam_track_end.lerp(return_cam_pos, t)
	, 0.0, 1.0, ATTACK_FLY_DURATION * 0.8).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	
	# 飞回完成
	tween.tween_callback(func():
		_remove_attack_trail()
		_scene._cam_state = 2
		var cam_labels = ["敌方", "中", "己方"]
		if _scene._view_btn:
			_scene._view_btn.text = " 视角: " + cam_labels[2]
		# 恢复相机到标准位置和默认俯视朝向（rotation -90° 朝地面看，禁用 look_at）
		if _cam:
			_cam.global_position = Vector3(_scene.CAM_POS_X, _scene.CAM_POS_Y, _scene.CAM_POS_Z[2])
			_cam.rotation_degrees = Vector3(-90, 0, 0)
		if card_node and is_instance_valid(card_node) and _player_slots[attacker_slot]:
			card_node.reparent(_player_slots[attacker_slot], true)
			card_node.position = Vector3(0, 0.15, 0.0)
		if _scene and _scene.has_method("_refresh_player_field_display"):
			_scene._refresh_player_field_display()
		if _scene and _scene.has_method("_highlight_attack_slots"):
			_scene._highlight_attack_slots()
		_is_attack_animating = false
	)


## 攻击卡牌动画（固定视角切换）
func _play_card_attack_animation(attacker_slot: int, target_pos: Vector3, card_node: Node, mesh: MeshInstance3D, orig_mat: Material, target_card: Node) -> void:
	var attacker_pos = _player_slots[attacker_slot].global_position if _player_slots[attacker_slot] else Vector3()
	var target_cam_z = _scene.CAM_POS_Z[1]  # 中间视角
	_scene._cam_state = 1
	if _scene._view_btn:
		_scene._view_btn.text = " 视角: 中"
	
	var tween = _scene.create_tween()
	# 阶段1：上升
	var rise_pos = attacker_pos + Vector3(0, 1.5, 0)
	tween.tween_property(card_node, "global_position", rise_pos, 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	# 相机同步移动
	tween.parallel().tween_property(_cam, "position:z", target_cam_z, 0.15 + ATTACK_FLY_DURATION + 0.05).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	# 阶段2：俯冲
	tween.tween_property(card_node, "global_position", target_pos, ATTACK_FLY_DURATION).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	# 撞击
	tween.tween_callback(func():
		if _attack_trail and is_instance_valid(_attack_trail):
			_attack_trail.emitting = false
		Global.play_sfx("attack_hit")
		if mesh and is_instance_valid(mesh):
			var flash = StandardMaterial3D.new()
			flash.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			flash.albedo_color = Color.WHITE
			mesh.material_override = flash
		_play_hit_flash_at(target_pos)
		if target_card and is_instance_valid(target_card):
			var orig_pos = target_card.global_position
			var push_back = orig_pos + Vector3(0, 0, -0.25)
			var shake_tween = _scene.create_tween()
			shake_tween.tween_property(target_card, "global_position", push_back, 0.08).set_ease(Tween.EASE_OUT)
			shake_tween.tween_property(target_card, "global_position", orig_pos, 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BOUNCE)
	)
	
	# 等shake完成后执行伤害
	tween.tween_interval(0.25)
	tween.tween_callback(func():
		if not _pending_player_attack.is_empty() and _battle_mgr and _battle_mgr.has_method("do_action"):
			var atk = _pending_player_attack.duplicate()
			_pending_player_attack = {}
			var action_type = "attack"
			var params = {"slot": atk.get("slot", -1)}
			if atk.has("target_slot") and atk.get("target_slot", -1) >= 0:
				params["target_slot"] = atk["target_slot"]
			# 攻击飘窗
			if _scene and _scene.has_method("show_attack_popup"):
				var card_data = null
				var atk_slot = atk.get("slot", -1)
				if _battle_mgr.player_self and atk_slot >= 0 and atk_slot < _battle_mgr.player_self.field.size():
					card_data = _battle_mgr.player_self.field[atk_slot]
				var target_name = ""
				var tgt_slot = atk.get("target_slot", -1)
				if tgt_slot >= 0 and _battle_mgr.player_opponent and tgt_slot < _battle_mgr.player_opponent.field.size():
					var target_data = _battle_mgr.player_opponent.field[tgt_slot]
					if target_data:
						target_name = target_data.get_display_name()
				if card_data:
					var atk_name = card_data.get_display_name()
					var atk_atk = card_data.current_atk
					_scene.show_attack_popup(atk_name, target_name, atk_atk, true)
			_battle_mgr.do_action(action_type, params)
			# 刷新双方场地显示（攻击卡反击伤害 + 被攻击卡掉血）
			if _scene and _scene.has_method("_refresh_player_field_display"):
				_scene._refresh_player_field_display()
			if _scene and _scene.has_method("_refresh_enemy_field_display"):
				_scene._refresh_enemy_field_display()
			if _scene and _scene.has_method("_advance_tutorial_step"):
				_scene._advance_tutorial_step("attack")
	)

	# 恢复材质
	tween.tween_interval(0.1)
	tween.tween_callback(func():
		if mesh and is_instance_valid(mesh):
			mesh.material_override = orig_mat
	)

	# 飞回
	var return_cam_z = _scene.CAM_POS_Z[2]
	var return_tween = _scene.create_tween()
	return_tween.parallel().tween_property(_cam, "position:z", return_cam_z, ATTACK_FLY_DURATION * 0.8).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_property(card_node, "global_position", attacker_pos, ATTACK_FLY_DURATION * 0.8).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	
	# 飞回完成
	tween.tween_callback(func():
		_remove_attack_trail()
		_scene._cam_state = 2
		var cam_labels = ["敌方", "中", "己方"]
		if _scene._view_btn:
			_scene._view_btn.text = " 视角: " + cam_labels[2]
		if card_node and is_instance_valid(card_node) and _player_slots[attacker_slot]:
			card_node.reparent(_player_slots[attacker_slot], true)
			card_node.position = Vector3(0, 0.15, 0.0)
		if _scene and _scene.has_method("_refresh_player_field_display"):
			_scene._refresh_player_field_display()
		if _scene and _scene.has_method("_highlight_attack_slots"):
			_scene._highlight_attack_slots()
		_is_attack_animating = false
	)


# ===== 原有方法 =====

## 创建抛物线指示线
func _create_drag_line() -> void:
	if _drag_line:
		_drag_line.queue_free()
	_drag_line = MeshInstance3D.new()
	_drag_line_mesh = ImmediateMesh.new()
	_drag_line.mesh = _drag_line_mesh
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = DRAG_LINE_COLOR
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	_drag_line.material_override = mat
	_scene.add_child(_drag_line)


## 更新抛物线（从手牌位置到手指射线投射位置）
func _update_drag_line(screen_pos: Vector2) -> void:
	if not _drag_line or not _drag_line_mesh or _drag_hand_index < 0:
		return
	var hand_node = _player_hand_nodes[_drag_hand_index]
	if not hand_node:
		return
	var start_pos = hand_node.global_position
	# 从屏幕位置投射射线到3D空间
	var from = _cam.project_ray_origin(screen_pos)
	var dir = _cam.project_ray_normal(screen_pos)
	# 射线与场地平面(y=0.15)求交
	var target_pos = from + dir * 10.0
	if dir.y != 0:
		var t = (0.15 - from.y) / dir.y
		if t > 0:
			target_pos = from + dir * t
	# 抛物线：取中间点抬高
	var mid = (start_pos + target_pos) * 0.5
	mid.y += 1.5
	# 用ImmediateMesh绘制线段
	_drag_line_mesh.clear_surfaces()
	_drag_line_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	var segments = 20
	for i in range(segments + 1):
		var f = float(i) / float(segments)
		# 二次贝塞尔曲线
		var p = start_pos.lerp(mid, f).lerp(mid.lerp(target_pos, f), f)
		_drag_line_mesh.surface_add_vertex(p)
	_drag_line_mesh.surface_end()
	# 高亮当前指向的卡位
	var slot_idx = _get_slot_at_screen_pos(screen_pos)
	_highlight_target_slot(slot_idx)


## 清除拖拽线
func _clear_drag_line() -> void:
	if _drag_line:
		_drag_line.queue_free()
		_drag_line = null
		_drag_line_mesh = null


## 获取屏幕位置对应的卡位索引
func _get_slot_at_screen_pos(screen_pos: Vector2) -> int:
	if not _cam:
		return -1
	var from = _cam.project_ray_origin(screen_pos)
	var dir = _cam.project_ray_normal(screen_pos)
	# 射线与场地平面(y=0.15)求交
	if dir.y == 0:
		return -1
	var t = (0.15 - from.y) / dir.y
	if t <= 0:
		return -1
	var hit = from + dir * t
	# 查找最近的卡位（距离<0.8）
	for i in range(5):
		if _player_slots[i]:
			var slot_pos = _player_slots[i].global_position
			var d = Vector2(hit.x - slot_pos.x, hit.z - slot_pos.z).length()
			if d < 0.8:
				return i
	return -1


## 高亮/取消所有卡位
func _highlight_slots(highlight: bool) -> void:
	for slot in _player_slots:
		if not slot:
			continue
		var face = slot.get_node_or_null("SlotFace") as MeshInstance3D
		if face:
			if highlight:
				var mat = StandardMaterial3D.new()
				mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				mat.albedo_color = SLOT_HIGHLIGHT_COLOR
				face.material_override = mat
			else:
				face.material_override = null


## 高亮目标卡位
var _current_highlight_slot: int = -1
func _highlight_target_slot(slot_idx: int) -> void:
	if _current_highlight_slot == slot_idx:
		return
	# 先恢复旧的
	if _current_highlight_slot >= 0 and _current_highlight_slot < 5:
		var slot = _player_slots[_current_highlight_slot]
		if slot:
			var face = slot.get_node_or_null("SlotFace") as MeshInstance3D
			if face:
				var mat = StandardMaterial3D.new()
				mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				mat.albedo_color = SLOT_HIGHLIGHT_COLOR
				face.material_override = mat
	# 高亮新的
	if slot_idx >= 0 and slot_idx < 5:
		var slot = _player_slots[slot_idx]
		if slot:
			var face = slot.get_node_or_null("SlotFace") as MeshInstance3D
			if face:
				var mat = StandardMaterial3D.new()
				mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				mat.albedo_color = Color(0.3, 1.0, 0.3, 0.7)
				face.material_override = mat
	_current_highlight_slot = slot_idx


## 卡牌飞到卡位 + 数据转移（兼容入口：从手牌引用取）
func _fly_card_to_slot(hand_idx: int, slot_idx: int) -> void:
	var card_node = _player_hand_cards[hand_idx]
	var card_data = _player_hand_datas[hand_idx]
	if card_node and card_data != null:
		_player_hand_cards[hand_idx] = null
		_player_hand_datas[hand_idx] = null
		await _fly_card_to_slot_ext(hand_idx, slot_idx, card_node, card_data)


## 卡牌飞到卡位 + 数据转移（外部已传节点与数据）
## 通用流程：飞到场地 → 入驻卡位 → 执行效果 → 检查还在不在 → 在就停着，不在就飞墓地
func _fly_card_to_slot_ext(hand_idx: int, slot_idx: int, card_node: Node, card_data: Variant) -> void:
	if not card_node:
		return
	var slot_node = _player_slots[slot_idx]
	if not slot_node:
		return
	# 卡牌飞到卡位（弧线）
	var start_pos = card_node.global_position
	var end_pos = slot_node.global_position + Vector3(0, 0.3, 0)  # 飞到卡位上方
	var mid_pos = (start_pos + end_pos) * 0.5 + Vector3(0, 1.2, 0)  # 抬高弧线
	print("[CardDragController] 飞入: hand %d → slot %d | start %s → end %s" % [hand_idx, slot_idx, start_pos, end_pos])
	# 先reparent到场景根，保证global_position不受父节点影响
	card_node.reparent(_scene, true)
	card_node.global_position = start_pos
	# 翻面（背面→正面）
	if card_node.has_method("set_face_up"):
		card_node.set_face_up()
	# 弧线飞行
	var tween = _scene.create_tween()
	tween.tween_method(func(f: float):
		if not is_instance_valid(card_node):
			return
		var p = start_pos.lerp(mid_pos, f).lerp(mid_pos.lerp(end_pos, f), f)
		card_node.global_position = p
	, 0.0, 1.0, SUMMON_FLY_DURATION).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	# 等飞入动画完成
	await _scene.get_tree().create_timer(SUMMON_FLY_DURATION).timeout
	if not is_instance_valid(card_node):
		return
	# ★ 入驻卡位
	if _field_mgr and card_data:
		_field_mgr.place_card(slot_idx, card_node, card_data)
		print("[CardDragController] 飞入完成 → place_card slot %d" % slot_idx)
		# 写入引用表（让送墓/攻击动画能直接找到卡牌节点）
		if slot_idx < _player_card_nodes.size():
			_player_card_nodes[slot_idx] = card_node
	else:
		print("[CardDragController]  飞入后卡牌无效或无field_mgr! slot=%d" % slot_idx)
		return
	# ★ 执行召唤效果（BM内部含0/0送墓判定）
	if _battle_mgr and _battle_mgr.has_method("_execute_on_summon_effects"):
		var player = _battle_mgr.player_self
		if player and slot_idx < player.field.size() and player.field[slot_idx]:
			var card = player.field[slot_idx]
			_battle_mgr._execute_on_summon_effects(player, card, slot_idx)
	# 等待效果飘窗动画完成（淡入0.2 + 停留1.8 + 淡出0.3 = 2.3s）
	await _scene.get_tree().create_timer(2.5).timeout
	if not is_instance_valid(card_node):
		return
	# 检查卡牌是否已被 _on_card_sent_to_grave 处理过（已在墓地数组里）
	var already_in_grave = false
	var grave_arr = _scene._player_grave_cards if true else _scene._enemy_grave_cards  # 玩家召唤
	for c in grave_arr:
		if c == card_node:
			already_in_grave = true
			break
	if already_in_grave:
		# 卡牌已被送墓信号处理（fly_to_grave已在飞），不重复处理
		print("[CardDragController] 卡牌已由送墓信号处理 → 不重复飞墓地")
		return
	var still_on_field = false
	if _battle_mgr and _battle_mgr.player_self and slot_idx < _battle_mgr.player_self.field.size():
		still_on_field = _battle_mgr.player_self.field[slot_idx] != null
	if not still_on_field:
		# 卡牌不在场上了（被效果送墓/破坏）→ 原卡飞墓地
		print("[CardDragController] 效果后卡牌不在场上 → 飞墓地")
		if _field_mgr:
			_field_mgr.remove_card(slot_idx)
		# 清除引用表
		if slot_idx < _player_card_nodes.size():
			_player_card_nodes[slot_idx] = null
		_fly_card_to_grave_from_field(card_node, slot_idx, true)
	else:
		# 卡牌还在 → 刷新数据显示（效果可能改了属性）
		if _battle_mgr and _battle_mgr.player_self:
			var bm_card = _battle_mgr.player_self.field[slot_idx]
			if bm_card and card_node.has_method("update_data") and _scene.has_method("_battle_card_to_dict"):
				card_node.update_data(_scene._battle_card_to_dict(bm_card))
		print("[CardDragController] 召唤流程完成 slot %d" % slot_idx)


## 卡牌从场地飞向墓地（效果送墓/0/0送墓，原卡在场上卡位上）
func _fly_card_to_grave_from_field(card_node: Node, slot_idx: int, is_player: bool) -> void:
	if not card_node:
		return
	var grave_node = _scene._player_grave_node if is_player else _scene._enemy_grave_node
	if not grave_node:
		# fallback
		grave_node = _scene.get_node_or_null("PlayerField/GraveArea") if is_player else _scene.get_node_or_null("EnemyField/GraveArea")
	if not grave_node:
		print("[CardDragController]  找不到墓地节点!")
		return
	# 获取墓地堆叠数
	var grave_arr = _scene._player_grave_cards if is_player else _scene._enemy_grave_cards
	var stack_count = grave_arr.size()
	# reparent 到场景根（从卡位上摘出来）
	if card_node.get_parent() != _scene:
		card_node.reparent(_scene, true)
	# 翻面正面朝上
	if card_node.has_method("set_face_up"):
		card_node.set_face_up()
	var start_pos = card_node.global_position
	var end_pos = grave_node.global_position + Vector3(0, 0.02 + 0.03 * stack_count, 0)
	var mid_pos = (start_pos + end_pos) * 0.5 + Vector3(0, 0.8, 0)
	print("[CardDragController] 飞墓地: start %s → end %s" % [start_pos, end_pos])
	var tween = _scene.create_tween()
	tween.tween_method(func(f: float):
		if not is_instance_valid(card_node):
			return
		var p = start_pos.lerp(mid_pos, f).lerp(mid_pos.lerp(end_pos, f), f)
		card_node.global_position = p
	, 0.0, 1.0, 0.5).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(func():
		if not is_instance_valid(card_node):
			return
		card_node.reparent(grave_node, true)
		card_node.position = Vector3(0, 0.02 + 0.03 * stack_count, 0)
		if card_node.has_method("set_face_up"):
			card_node.set_face_up()
	)
	grave_arr.append(card_node)


## 能量不足时卡牌抖动
func _shake_hand_card(hand_idx: int) -> void:
	var hand_node = _player_hand_nodes[hand_idx]
	if not hand_node:
		return
	var original_pos = hand_node.position
	var tween = _scene.create_tween()
	# 左右快速抖动3次然后回正
	tween.tween_property(hand_node, "position:x", original_pos.x - SHAKE_AMPLITUDE, 0.05)
	tween.tween_property(hand_node, "position:x", original_pos.x + SHAKE_AMPLITUDE, 0.05)
	tween.tween_property(hand_node, "position:x", original_pos.x - SHAKE_AMPLITUDE, 0.05)
	tween.tween_property(hand_node, "position:x", original_pos.x + SHAKE_AMPLITUDE, 0.05)
	tween.tween_property(hand_node, "position", original_pos, 0.08).set_ease(Tween.EASE_OUT)
