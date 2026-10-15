extends Node3D
class_name BattleCard3D

## 3D卡牌预制：手牌/场地用四角布局
## 所有Label3D的朝向统一由tscn预制决定，代码只更新文字内容

var card_data: Dictionary = {}

# 手牌模式节点引用（tscn预制，setup时手动获取，不依赖@onready）
var _mesh_instance: MeshInstance3D = null
var _elem_lbl: Label3D = null
var _cost_lbl: Label3D = null
var _center_lbl: Label3D = null
var _fields_lbl: Label3D = null
var _effects_lbl: Label3D = null
var _atk_lbl: Label3D = null
var _hp_lbl: Label3D = null
var _poison_lbl: Label3D = null  # 中毒指示物
var _shield_lbl: Label3D = null  # 护盾指示物

var _front_mat: StandardMaterial3D = null
var _back_mat: StandardMaterial3D = null


func setup(data: Dictionary, front_mat: StandardMaterial3D, back_mat: StandardMaterial3D) -> void:
	card_data = data
	_front_mat = front_mat
	_back_mat = back_mat
	# 手动获取子节点引用（不依赖@onready，add_child前后都能用）
	_mesh_instance = get_node_or_null("CardMesh") as MeshInstance3D
	_elem_lbl = get_node_or_null("ElemLabel") as Label3D
	_cost_lbl = get_node_or_null("CostLabel") as Label3D
	_center_lbl = get_node_or_null("CenterLabel") as Label3D
	_fields_lbl = get_node_or_null("FieldsLabel") as Label3D
	_effects_lbl = get_node_or_null("EffectsLabel") as Label3D
	_atk_lbl = get_node_or_null("AtkLabel") as Label3D
	_hp_lbl = get_node_or_null("HpLabel") as Label3D
	# 创建状态指示物
	_ensure_status_labels()
	# 更新文字
	_update_labels()
	# 默认背面朝上
	set_face_down(back_mat)

## 复用节点：仅更新数据与文字，不重置朝向/材质
func update_data(data: Dictionary) -> void:
	card_data = data
	_ensure_status_labels()
	_update_labels()


func _update_labels() -> void:
	if not is_inside_tree():
		return
	var card_name: String = card_data.get("name", card_data.get("card_name", ""))
	var atk: int = card_data.get("atk", card_data.get("attack", 0))
	var hp_val: int = card_data.get("hp", card_data.get("health", 0))
	var cost: int = card_data.get("cost", card_data.get("energy_cost", 0))
	var element: String = card_data.get("element", CardManager.get_card_element(card_data))
	
	# 四角布局
	var elem_icon := ""
	match element:
		"火": elem_icon = "🔥"
		"水": elem_icon = "💧"
		"风": elem_icon = "🌪"
		"地": elem_icon = "⛰"
		"光": elem_icon = "✨"
		"暗": elem_icon = "🌑"
		_: elem_icon = ""
	_elem_lbl.text = elem_icon
	_cost_lbl.text = "⚡" + str(cost)
	# 中间三行拆开：卡名 / 字段 / 效果数（和老2D战斗界面一致）
	_center_lbl.text = card_name
	var fields: Array = card_data.get("fields", [])
	if _fields_lbl:
		if fields.size() > 0:
			_fields_lbl.text = "📖" + "|".join(fields)
			_fields_lbl.visible = true
		else:
			_fields_lbl.text = ""
			_fields_lbl.visible = false
	var effects: Array = card_data.get("effects", [])
	if _effects_lbl:
		if effects.size() > 0:
			_effects_lbl.text = "📜" + str(effects.size()) + "效果"
			_effects_lbl.visible = true
		else:
			_effects_lbl.text = ""
			_effects_lbl.visible = false
	_atk_lbl.text = "⚔" + str(atk)
	_hp_lbl.text = "❤" + str(hp_val)


func set_face_up(mat: StandardMaterial3D = null) -> void:
	if mat == null:
		mat = _front_mat
	if _mesh_instance:
		_mesh_instance.material_override = mat
	_show_labels()
	# 翻正后重新同步文字与可见性（_show_labels 会亮出全部标签，
	# 需重新判断字段/效果是否显示，避免空内容也显示）
	_update_labels()


func set_face_down(mat: StandardMaterial3D) -> void:
	if _mesh_instance:
		_mesh_instance.material_override = mat
	_hide_labels()


func _show_labels() -> void:
	for child in get_children():
		if child is Label3D:
			child.visible = true


func _hide_labels() -> void:
	for child in get_children():
		if child is Label3D:
			child.visible = false

## 创建状态指示物（中毒/护盾）并更新显示
func _ensure_status_labels() -> void:
	if not is_inside_tree():
		return
	if not _poison_lbl:
		_poison_lbl = Label3D.new()
		_poison_lbl.name = "PoisonLabel"
		_poison_lbl.text = ""
		_poison_lbl.font_size = 27
		_poison_lbl.modulate = Color(0.5, 1.0, 0.2, 1.0)
		_poison_lbl.outline_size = 2
		_poison_lbl.outline_modulate = Color(0, 0, 0, 0.8)
		_poison_lbl.no_depth_test = true
		_poison_lbl.render_priority = 2
		# 卡牌右上角（在HpLabel上方）
		_poison_lbl.transform = Transform3D(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(0.35, 0.004, 0.35))
		add_child(_poison_lbl)
	if not _shield_lbl:
		_shield_lbl = Label3D.new()
		_shield_lbl.name = "ShieldLabel"
		_shield_lbl.text = ""
		_shield_lbl.font_size = 27
		_shield_lbl.modulate = Color(0.4, 0.8, 1.0, 1.0)
		_shield_lbl.outline_size = 2
		_shield_lbl.outline_modulate = Color(0, 0, 0, 0.8)
		_shield_lbl.no_depth_test = true
		_shield_lbl.render_priority = 2
		# 卡牌左上角（在ElemLabel上方）
		_shield_lbl.transform = Transform3D(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0), Vector3(-0.35, 0.004, 0.35))
		add_child(_shield_lbl)
	# 更新显示
	var poison_count: int = card_data.get("poison_count", 0)
	if _poison_lbl:
		if poison_count > 0:
			_poison_lbl.text = "毒" + str(poison_count)
			_poison_lbl.visible = true
		else:
			_poison_lbl.visible = false
	var shield_pts: int = card_data.get("shield_points", 0)
	if _shield_lbl:
		if shield_pts > 0:
			_shield_lbl.text = "盾" + str(shield_pts)
			_shield_lbl.visible = true
		else:
			_shield_lbl.visible = false

## 卡牌飞向墓地（自身动画）
func fly_to_grave(grave_node: Node3D, stack_count: int) -> void:
	# 基础Y偏移0.02确保卡牌在GraveArea的Face面板(0.001)之上
	var stack_offset = Vector3(0, 0.02 + 0.03 * stack_count, 0)
	var start_pos = global_position
	# reparent到场景根做全局飞行
	var scene_root = get_tree().current_scene
	if get_parent() != scene_root:
		reparent(scene_root, true)
	var grave_pos = grave_node.global_position + stack_offset
	var mid_pos = (start_pos + grave_pos) * 0.5 + Vector3(0, 0.8, 0)
	var tween = create_tween()
	tween.tween_method(func(f: float):
		if not is_instance_valid(self):
			return
		var p = start_pos.lerp(mid_pos, f).lerp(mid_pos.lerp(grave_pos, f), f)
		global_position = p
	, 0.0, 1.0, 0.5).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(func():
		if not is_instance_valid(self):
			return
		reparent(grave_node, true)
		position = stack_offset
		set_face_up()
	)
