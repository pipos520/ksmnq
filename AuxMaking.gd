extends ThemedControl

## ============================
##  制作辅材 - 主界面
##  消耗素材 + 金币，制作辅材道具
## ============================

var _selected_aux: Dictionary = {}
var _preview_labels := {}
var _hint_label: Label = null

# 长按相关
var _picker_long_press_timer: float = 0.0
var _picker_long_press_item = null
var _picker_long_press_active: bool = false


func _ready():
	super._ready()
	var bg = Global.make_bg()
	bg.name = "Background"
	add_child(bg)
	
	var topbar = Global.make_topbar(0.083)
	topbar.name = "TopBar"
	add_child(topbar)
	var topbar_line = Global.make_topbar_bottom_line(0.083)
	topbar_line.name = "TopBarLine"
	add_child(topbar_line)
	
	var back = Global.make_back_btn()
	back.name = "BackBtn"
	back.pressed.connect(_on_back)
	add_child(back)
	
	var title = Label.new()
	title.name = "Title"
	title.text = "🧪 制作辅材"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 100)
	title.add_theme_color_override("font_color", Global.current.title)
	title.add_theme_color_override("font_shadow_color", Global.current.title_shadow)
	title.add_theme_constant_override("shadow_offset_x", Global.current.shadow_offset)
	title.add_theme_constant_override("shadow_offset_y", Global.current.shadow_offset)
	title.anchor_left = 0.0
	title.anchor_top = 0.0
	title.anchor_right = 1.0
	title.anchor_bottom = 0.0
	title.offset_left = 0
	title.offset_top = Global.ph(0.01)
	title.offset_right = 0
	title.offset_bottom = Global.ph(0.083)
	add_child(title)
	
	var scroll = ScrollContainer.new()
	scroll.name = "ContentScroll"
	scroll.anchor_left = 0.0
	scroll.anchor_top = 0.0
	scroll.anchor_right = 1.0
	scroll.anchor_bottom = 1.0
	scroll.offset_left = 0
	scroll.offset_top = Global.ph(0.083)
	scroll.offset_right = 0
	scroll.offset_bottom = Global.ph(-0.083)
	add_child(scroll)
	
	var vbox = VBoxContainer.new()
	vbox.name = "ContentVBox"
	vbox.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	vbox.custom_minimum_size = Vector2(Global.pw(1.0), 0)
	vbox.add_theme_constant_override("separation", Global.ph(0.01))
	scroll.add_child(vbox)
	
	_build_aux_list(vbox)
	_build_preview_section(vbox)
	_build_make_button(vbox)
	
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, Global.ph(0.15))
	vbox.add_child(spacer)
	
	# ===== 底部UI条 =====
	var bottom_bar = Global.make_topbar(0.083)
	bottom_bar.name = "BottomBar"
	bottom_bar.anchor_top = 1.0
	bottom_bar.anchor_bottom = 1.0
	bottom_bar.offset_top = Global.ph(-0.083)
	bottom_bar.offset_bottom = 0
	add_child(bottom_bar)
	
	var bottom_bar_line = Global.make_topbar_bottom_line(0.083)
	bottom_bar_line.name = "BottomBarLine"
	bottom_bar_line.anchor_top = 1.0
	bottom_bar_line.anchor_bottom = 1.0
	bottom_bar_line.offset_top = Global.ph(-0.083)
	bottom_bar_line.offset_bottom = 0
	add_child(bottom_bar_line)
	
	# 提示文字（底部UI条内，靠右）
	_hint_label = Label.new()
	_hint_label.name = "HintLabel"
	_hint_label.text = "选择辅材查看详情并制作"
	_hint_label.add_theme_font_size_override("font_size", 50)
	_hint_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.5))
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hint_label.anchor_left = 0.0
	_hint_label.anchor_top = 1.0
	_hint_label.anchor_right = 1.0
	_hint_label.anchor_bottom = 1.0
	_hint_label.offset_left = Global.pw(0.11)
	_hint_label.offset_top = Global.ph(-0.075)
	_hint_label.offset_right = Global.pw(-0.02)
	_hint_label.offset_bottom = Global.ph(-0.01)
	add_child(_hint_label)


# ============================
#  辅材列表
# ============================
func _build_aux_list(parent: VBoxContainer):
	var panel = Panel.new()
	panel.name = "AuxListPanel"
	var ps = StyleBoxFlat.new()
	ps.bg_color = Global.current.topbar_bg
	ps.corner_radius_top_left = 8
	ps.corner_radius_top_right = 8
	ps.corner_radius_bottom_left = 8
	ps.corner_radius_bottom_right = 8
	panel.add_theme_stylebox_override("panel", ps)
	panel.size_flags_horizontal = SIZE_FILL
	parent.add_child(panel)
	
	var vbox = VBoxContainer.new()
	vbox.name = "AuxVBox"
	vbox.anchor_left = 0.0
	vbox.anchor_top = 0.0
	vbox.anchor_right = 1.0
	vbox.anchor_bottom = 1.0
	vbox.offset_left = Global.pw(0.03)
	vbox.offset_top = Global.ph(0.01)
	vbox.offset_right = Global.pw(-0.03)
	vbox.offset_bottom = Global.ph(-0.01)
	vbox.size_flags_horizontal = SIZE_FILL
	vbox.add_theme_constant_override("separation", Global.ph(0.005))
	panel.add_child(vbox)
	
	var title = Label.new()
	title.text = "🧪 可选辅材"
	title.add_theme_font_size_override("font_size", 50)
	title.add_theme_color_override("font_color", Global.current.title)
	vbox.add_child(title)
	
	var aux_list = Global.get_aux_list()
	var warehouse = get_node("/root/WarehouseManager")
	
	for aux in aux_list:
		var aid = aux.get("id", "")
		var name = aux.get("name", "")
		var rarity = aux.get("rarity", "普通")
		var desc = aux.get("description", "")
		var cost = aux.get("craft_cost", {})
		var gold_cost = cost.get("gold", 0)
		var mats_needed = cost.get("materials", {})
		
		# 检查是否可制作（素材够不够）
		var can_craft = true
		var material_details := []
		var inv = warehouse.get_materials()
		for mid in mats_needed.keys():
			var need = mats_needed[mid]
			var have = inv.get(mid, 0)
			var mat_info = Global.get_material_by_id(mid)
			var mat_name = mat_info.get("name", mid)
			material_details.append(mat_name + " x" + str(need) + "(" + str(have) + ")")
			if have < need:
				can_craft = false
		var gold = SaveManager.get_value("player", "gold", 0)
		if gold < gold_cost:
			can_craft = false
		
		var row = Panel.new()
		var rs = StyleBoxFlat.new()
		rs.bg_color = Global.current.btn_bg
		rs.corner_radius_top_left = 6
		rs.corner_radius_top_right = 6
		rs.corner_radius_bottom_left = 6
		rs.corner_radius_bottom_right = 6
		row.add_theme_stylebox_override("panel", rs)
		row.custom_minimum_size = Vector2(0, Global.ph(0.12))
		row.size_flags_horizontal = SIZE_FILL
		vbox.add_child(row)
		
		var hbox = HBoxContainer.new()
		hbox.size_flags_horizontal = SIZE_FILL
		row.add_child(hbox)
		
		# 名称 + 稀有度
		var info_vbox = VBoxContainer.new()
		info_vbox.size_flags_horizontal = SIZE_EXPAND
		hbox.add_child(info_vbox)
		
		var name_label = Label.new()
		name_label.text = name
		name_label.add_theme_font_size_override("font_size", 45)
		name_label.add_theme_color_override("font_color", _get_rarity_color(rarity))
		info_vbox.add_child(name_label)
		
		var cost_label = Label.new()
		cost_label.text = "💰" + str(gold_cost) + "  " + " ".join(material_details)
		cost_label.add_theme_font_size_override("font_size", 35)
		cost_label.add_theme_color_override("font_color", Global.current.btn_text)
		cost_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info_vbox.add_child(cost_label)
		
		# 制作按钮
		var make_btn = Button.new()
		make_btn.text = "制作" if can_craft else "素材不足"
		make_btn.add_theme_font_size_override("font_size", 40)
		make_btn.disabled = not can_craft
		make_btn.custom_minimum_size = Vector2(Global.pw(0.15), 0)
		make_btn.pressed.connect(_on_make_aux.bind(aid, aux))
		hbox.add_child(make_btn)
		
		# 长按查看详情
		row.gui_input.connect(_on_aux_row_input.bind(aux, row))


# ============================
#  制作辅材
# ============================
func _on_make_aux(aux_id: String, aux_data: Dictionary):
	var cost = aux_data.get("craft_cost", {})
	var mats_needed = cost.get("materials", {})
	var gold_cost = cost.get("gold", 0)
	var warehouse = get_node("/root/WarehouseManager")
	
	# 检查金币
	var gold = SaveManager.get_value("player", "gold", 0)
	if gold < gold_cost:
		_show_popup("💰 金币不足！需要 " + str(gold_cost) + " 金币", Color("#FF6B6B"))
		return
	
	# 预检所有素材是否充足（避免部分消耗后失败）
	for mid in mats_needed.keys():
		var need = mats_needed[mid]
		if warehouse.get_material_count(mid) < need:
			_show_popup("素材不足，无法制作", Color("#FF6B6B"))
			return
	
	# 消耗素材
	for mid in mats_needed.keys():
		warehouse.consume_material(mid, mats_needed[mid])
	
	# 消耗金币
	SaveManager.set_value("player", "gold", gold - gold_cost)
	SaveManager.save_to_disk()
	
	# 添加辅材到仓库
	warehouse.add_aux(aux_id, 1)
	
	_show_popup("✅ 制作成功！获得【" + aux_data.get("name", "") + "】", Color("#4CAF50"))
	
	# 刷新界面
	_refresh_aux_list()


func _refresh_aux_list():
	var scroll = get_node_or_null("ContentScroll")
	if not scroll:
		return
	var vbox = scroll.get_node_or_null("ContentVBox")
	if not vbox:
		return
	# 清空并重建
	for child in vbox.get_children():
		child.queue_free()
	_build_aux_list(vbox)
	_build_preview_section(vbox)
	_build_make_button(vbox)
	
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, Global.ph(0.15))
	vbox.add_child(spacer)


# ============================
#  预览区域
# ============================
func _build_preview_section(parent: VBoxContainer):
	var panel = Panel.new()
	panel.name = "PreviewPanel"
	var ps = StyleBoxFlat.new()
	ps.bg_color = Global.current.topbar_bg
	ps.corner_radius_top_left = 8
	ps.corner_radius_top_right = 8
	ps.corner_radius_bottom_left = 8
	ps.corner_radius_bottom_right = 8
	panel.add_theme_stylebox_override("panel", ps)
	panel.size_flags_horizontal = SIZE_FILL
	parent.add_child(panel)
	
	var vbox = VBoxContainer.new()
	vbox.name = "PreviewVBox"
	vbox.anchor_left = 0.0
	vbox.anchor_top = 0.0
	vbox.anchor_right = 1.0
	vbox.anchor_bottom = 1.0
	vbox.offset_left = Global.pw(0.03)
	vbox.offset_top = Global.ph(0.01)
	vbox.offset_right = Global.pw(-0.03)
	vbox.offset_bottom = Global.ph(-0.01)
	vbox.size_flags_horizontal = SIZE_FILL
	vbox.add_theme_constant_override("separation", Global.ph(0.005))
	panel.add_child(vbox)
	
	var title = Label.new()
	title.text = "📋 辅材说明"
	title.add_theme_font_size_override("font_size", 50)
	title.add_theme_color_override("font_color", Global.current.title)
	vbox.add_child(title)
	
	var info = Label.new()
	info.name = "AuxInfo"
	info.text = "选择辅材查看详细效果"
	info.add_theme_font_size_override("font_size", 45)
	info.add_theme_color_override("font_color", Global.current.btn_text)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(info)
	
	_preview_labels["aux_info"] = info


func _build_make_button(parent: VBoxContainer):
	# 占位，实际制作按钮在每行中
	pass


# ============================
#  长按查看详情
# ============================
func _on_aux_row_input(event: InputEvent, aux: Dictionary, row: Panel):
	if event is InputEventScreenTouch:
		if event.pressed:
			_picker_long_press_timer = 0.0
			_picker_long_press_item = aux
			_picker_long_press_active = true
		else:
			_picker_long_press_active = false
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_picker_long_press_timer = 0.0
			_picker_long_press_item = aux
			_picker_long_press_active = true
		elif not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_picker_long_press_active = false


func _process(delta: float):
	if _picker_long_press_active:
		_picker_long_press_timer += delta
		if _picker_long_press_timer >= 0.5:
			_picker_long_press_active = false
			_show_aux_detail(_picker_long_press_item)


func _show_aux_detail(aux: Dictionary):
	# 更新预览
	var info = _preview_labels.get("aux_info")
	if info:
		var name = aux.get("name", "")
		var rarity = aux.get("rarity", "普通")
		var desc = aux.get("description", "")
		var effect = aux.get("effect", {})
		var etype = aux.get("type", "")
		
		var type_names = {"boost": "⚡属性增幅", "element": "🔥元素赋予", "protect": "🛡️保护", "special": "✨特殊效果", "poison": "🐍剧毒", "combo": "⚔️连击"}
		var type_name = type_names.get(etype, "未知")
		
		var effect_desc = ""
		for k in effect.keys():
			var v = effect[k]
			match k:
				"atk_bonus": effect_desc += "攻击力+" + str(v) + " "
				"hp_bonus": effect_desc += "生命值+" + str(v) + " "
				"damage_halve": effect_desc += "伤害减半 "
				"element": effect_desc += "赋予" + str(v) + "属性 "
				"element_power": effect_desc += str(int(v * 100)) + "%效果强度 "
				"indestructible_once": effect_desc += "一次性免破坏 "
				"energy_reduce": effect_desc += "能量消耗-" + str(v) + " "
				"draw_on_summon": effect_desc += "上场抽" + str(v) + "张牌 "
				"haste": effect_desc += "召唤当回合可攻击 "
				"extra_trigger": effect_desc += "额外触发" + str(v) + "次 "
				"poison": effect_desc += "攻击附加中毒+" + str(v) + "层 "
				"combo": effect_desc += "连击（一回合可攻击两次） "
				"field_sync": 
					if typeof(v) == TYPE_DICTIONARY:
						effect_desc += "同字段在场时攻+" + str(v.get("atk", 0)) + "命+" + str(v.get("hp", 0)) + " "
				_: effect_desc += k + ":" + str(v) + " "
		
		info.text = "【" + rarity + "】" + name + "\n"
		info.text += "类型：" + type_name + "\n"
		info.text += "效果：" + effect_desc + "\n"
		info.text += desc
	
	# 弹窗详情
	var existing = get_node_or_null("DetailOverlay")
	if existing:
		existing.queue_free()
	
	var overlay = ColorRect.new()
	overlay.name = "DetailOverlay"
	overlay.color = Color(0, 0, 0, 0.7)
	overlay.anchor_left = 0.0
	overlay.anchor_top = 0.0
	overlay.anchor_right = 1.0
	overlay.anchor_bottom = 1.0
	overlay.mouse_filter = MOUSE_FILTER_STOP
	overlay.gui_input.connect(_on_detail_overlay_input.bind(overlay))
	add_child(overlay)
	
	var panel = Panel.new()
	panel.name = "DetailPanel"
	panel.anchor_left = 0.08
	panel.anchor_top = 0.2
	panel.anchor_right = 0.92
	panel.anchor_bottom = 0.8
	panel.clip_contents = true
	var ps = StyleBoxFlat.new()
	ps.bg_color = Global.current.bg
	ps.border_width_left = 3
	ps.border_width_right = 3
	ps.border_width_top = 3
	ps.border_width_bottom = 3
	ps.border_color = _get_rarity_color(aux.get("rarity", "普通"))
	ps.corner_radius_top_left = 16
	ps.corner_radius_top_right = 16
	ps.corner_radius_bottom_left = 16
	ps.corner_radius_bottom_right = 16
	panel.add_theme_stylebox_override("panel", ps)
	overlay.add_child(panel)
	
	var vbox = VBoxContainer.new()
	vbox.name = "DetailVBox"
	vbox.anchor_left = 0.0
	vbox.anchor_top = 0.0
	vbox.anchor_right = 1.0
	vbox.anchor_bottom = 1.0
	vbox.offset_left = Global.pw(0.04)
	vbox.offset_top = Global.ph(0.02)
	vbox.offset_right = Global.pw(-0.04)
	vbox.offset_bottom = Global.ph(-0.02)
	vbox.size_flags_horizontal = SIZE_FILL
	vbox.add_theme_constant_override("separation", Global.ph(0.01))
	panel.add_child(vbox)
	
	var name_label = Label.new()
	name_label.text = aux.get("name", "未知辅材")
	name_label.add_theme_font_size_override("font_size", 55)
	name_label.add_theme_color_override("font_color", _get_rarity_color(aux.get("rarity", "普通")))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_label)
	
	var rarity_label = Label.new()
	rarity_label.text = "【" + aux.get("rarity", "普通") + "】"
	rarity_label.add_theme_font_size_override("font_size", 50)
	rarity_label.add_theme_color_override("font_color", _get_rarity_color(aux.get("rarity", "普通")))
	rarity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(rarity_label)
	
	var line = HSeparator.new()
	line.add_theme_color_override("color", Global.current.topbar_border)
	vbox.add_child(line)
	
	var desc_label = Label.new()
	desc_label.text = aux.get("description", "")
	desc_label.add_theme_font_size_override("font_size", 50)
	desc_label.add_theme_color_override("font_color", Global.current.btn_text)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(desc_label)
	
	var effect = aux.get("effect", {})
	if not effect.is_empty():
		var effect_label = Label.new()
		var effect_str = "效果加成：\n"
		for k in effect.keys():
			var v = effect[k]
			effect_str += "  • " + k + " = " + str(v) + "\n"
		effect_label.text = effect_str
		effect_label.add_theme_font_size_override("font_size", 45)
		effect_label.add_theme_color_override("font_color", Color("#FFD700"))
		effect_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(effect_label)
	
	var cost = aux.get("craft_cost", {})
	var gold_cost = cost.get("gold", 0)
	var mats = cost.get("materials", {})
	var cost_str = "制作消耗：💰" + str(gold_cost) + "金币"
	for mid in mats.keys():
		var mat_info = Global.get_material_by_id(mid)
		cost_str += "\n  • " + mat_info.get("name", mid) + " x" + str(mats[mid])
	
	var cost_label = Label.new()
	cost_label.text = cost_str
	cost_label.add_theme_font_size_override("font_size", 45)
	cost_label.add_theme_color_override("font_color", Global.current.btn_text)
	cost_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(cost_label)
	
	var close_btn = Button.new()
	close_btn.text = "关闭"
	close_btn.add_theme_font_size_override("font_size", 50)
	var cs = StyleBoxFlat.new()
	cs.bg_color = Global.current.btn_bg
	cs.border_width_left = 2
	cs.border_width_right = 2
	cs.border_width_top = 2
	cs.border_width_bottom = 2
	cs.border_color = Color("#888888")
	cs.corner_radius_top_left = 10
	cs.corner_radius_top_right = 10
	cs.corner_radius_bottom_left = 10
	cs.corner_radius_bottom_right = 10
	close_btn.add_theme_stylebox_override("normal", cs)
	close_btn.add_theme_color_override("font_color", Global.current.btn_text)
	close_btn.size_flags_horizontal = SIZE_FILL
	close_btn.custom_minimum_size = Vector2(0, Global.ph(0.07))
	close_btn.pressed.connect(_close_detail.bind(overlay))
	vbox.add_child(close_btn)


func _close_detail(overlay: ColorRect):
	if overlay and is_instance_valid(overlay):
		overlay.queue_free()


func _on_detail_overlay_input(event: InputEvent, overlay: ColorRect):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var panel = overlay.get_node_or_null("DetailPanel")
		if panel:
			var mouse_pos = overlay.get_local_mouse_position()
			var panel_rect = Rect2(panel.position, panel.size)
			if not panel_rect.has_point(mouse_pos):
				_close_detail(overlay)


# ============================
#  通用
# ============================
func _show_popup(text: String, color: Color):
	var existing = get_node_or_null("PopupOverlay")
	if existing:
		existing.queue_free()
	
	var overlay = ColorRect.new()
	overlay.name = "PopupOverlay"
	overlay.color = Color(0, 0, 0, 0.5)
	overlay.anchor_left = 0.0
	overlay.anchor_top = 0.0
	overlay.anchor_right = 1.0
	overlay.anchor_bottom = 1.0
	overlay.mouse_filter = MOUSE_FILTER_STOP
	overlay.gui_input.connect(_on_popup_click.bind(overlay))
	add_child(overlay)
	
	var panel = Panel.new()
	panel.anchor_left = 0.2
	panel.anchor_top = 0.35
	panel.anchor_right = 0.8
	panel.anchor_bottom = 0.65
	var ps = StyleBoxFlat.new()
	ps.bg_color = Global.current.bg
	ps.border_width_left = 3
	ps.border_width_right = 3
	ps.border_width_top = 3
	ps.border_width_bottom = 3
	ps.border_color = color
	ps.corner_radius_top_left = 16
	ps.corner_radius_top_right = 16
	ps.corner_radius_bottom_left = 16
	ps.corner_radius_bottom_right = 16
	panel.add_theme_stylebox_override("panel", ps)
	overlay.add_child(panel)
	
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 50)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.anchor_left = 0.0
	label.anchor_top = 0.0
	label.anchor_right = 1.0
	label.anchor_bottom = 1.0
	panel.add_child(label)
	
	# 自动关闭（1.5秒后）
	var timer = get_tree().create_timer(1.5)
	timer.timeout.connect(_close_popup.bind(overlay))


func _on_popup_click(event: InputEvent, overlay: ColorRect):
	if event is InputEventMouseButton and event.pressed:
		_close_popup(overlay)


func _close_popup(overlay: ColorRect):
	if overlay and is_instance_valid(overlay):
		overlay.queue_free()


func _get_rarity_color(rarity: String) -> Color:
	match rarity:
		"传说": return Color("#FFD700")
		"史诗": return Color("#9B59B6")
		"稀有": return Color("#3498DB")
		"普通": return Color("#95A5A6")
	return Color("#95A5A6")


func _on_back():
	Global.change_scene("res://CardWorkshop.tscn")
