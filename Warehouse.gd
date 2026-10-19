extends Control

# 当前标签页： "all" 或 "material" 或 "card_base" 或 "ink" 或 "aux"
var _current_tab: String = "all"

# 筛选状态（仅素材用）
var _filter_category: String = ""
var _filter_rarity: String = ""

# ===== 长按弹窗 =====
var _press_timer: float = 0.0
var _pressed_row = null
var _press_start_pos: Vector2 = Vector2.ZERO
var _press_index: int = -1
const LONG_PRESS_TIME := 0.5
const DRAG_THRESHOLD := 30.0

func _ready():
	# ---- 静态节点已在 Warehouse.tscn 中声明 ----
	var back := get_node_or_null("BackBtn")
	if back is Button: back.pressed.connect(_on_back)
	# 主题
	Global.theme_changed.connect(_on_theme_changed)
	call_deferred("_apply_theme_styles")
	# 动态内容构建
	call_deferred("_build_dynamic_content")

func _refresh_list():
	if _current_tab == "all":
		# 全部：显示所有分类（素材+卡基+卡墨+辅材）
		_refresh_all_list()
	elif _current_tab == "material":
		_refresh_material_list()
	elif _current_tab == "ink":
		_refresh_ink_list()
	elif _current_tab == "aux":
		_refresh_aux_list()
	else:
		_refresh_card_base_list()
	
	var filter_btn = get_node_or_null("FilterBtn")
	if filter_btn:
		filter_btn.visible = (_current_tab == "material")
	
	var hint = get_node_or_null("HintLabel")
	if hint:
		var hint_text = "长按查看"
		match _current_tab:
			"material": hint_text += "素材"
			"card_base": hint_text += "卡基"
			"ink": hint_text += "卡墨"
			"aux": hint_text += "辅材"
		hint.text = hint_text + "详情"


func _refresh_material_list() -> void:
	var vbox = get_node_or_null("ListScroll/ListVBox")
	if not vbox:
		return
	
	for child in vbox.get_children():
		vbox.remove_child(child)
		child.queue_free()
	
	var mats := WarehouseManager.get_materials()
	if mats.size() == 0:
		var empty = Label.new()
		empty.text = "仓库空空如也..."
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_font_size_override("font_size", 50)
		empty.add_theme_color_override("font_color", Color("#5a5a6e"))
		empty.custom_minimum_size = Vector2(0, Global.ph(0.1))
		vbox.add_child(empty)
		return
	
	# 收集所有素材信息并按分类+稀有度排序
	var material_rows := []
	for mid in mats.keys():
		var count = mats[mid]
		if count <= 0:
			continue
		
		var mat_data := Global.get_material_by_id(mid)
		if mat_data.is_empty():
			continue
		
		var name_str: String = mat_data.get("name", mid)
		var rarity: String = mat_data.get("rarity", "普通")
		var category: String = _get_category(mid)
		
		# 筛选：分类过滤
		if _filter_category != "" and category != _filter_category:
			continue
		# 筛选：品质过滤
		if _filter_rarity != "" and rarity != _filter_rarity:
			continue
		
		var color := _get_rarity_color(rarity)
		
		material_rows.append({
			"id": mid,
			"name": name_str,
			"rarity": rarity,
			"category": category,
			"count": count,
			"color": color
		})
	
	# 排序：稀有度从高到低 > 同稀有度按分类 > 同分类按ID
	var rarity_order := {"传说": 0, "史诗": 1, "稀有": 2, "普通": 3}
	var cat_order := {"纤维": 0, "矿粉": 1, "树脂": 2, "萃取液": 3, "颜料": 4, "粘合剂": 5}
	material_rows.sort_custom(func(a, b):
		var ra = rarity_order.get(a["rarity"], 9)
		var rb = rarity_order.get(b["rarity"], 9)
		if ra != rb:
			return ra < rb
		var ca = cat_order.get(a["category"], 9)
		var cb = cat_order.get(b["category"], 9)
		if ca != cb:
			return ca < cb
		return a["id"] < b["id"]
	)
	
	# 生成行
	var row_index := 0
	for row in material_rows:
		# 用 Panel + StyleBoxFlat 作为行容器（背景色用 StyleBox 保证可见）
		var row_panel = Panel.new()
		row_panel.name = "RowPanel"
		var panel_style = StyleBoxFlat.new()
		panel_style.bg_color = _get_row_bg_color(row_index)
		row_panel.add_theme_stylebox_override("panel", panel_style)
		row_panel.custom_minimum_size = Vector2(0, Global.ph(0.085))
		row_panel.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
		row_panel.mouse_filter = MOUSE_FILTER_PASS
		row_panel.set_meta("row_data", row)
		row_panel.set_meta("row_index", row_index)
		
		# 行底部分隔线（贴在底部）
		var row_line = ColorRect.new()
		row_line.name = "RowLine"
		row_line.color = Color(1.0, 1.0, 1.0, 0.20)
		row_line.anchor_left = 0.0
		row_line.anchor_top = 1.0
		row_line.anchor_right = 1.0
		row_line.anchor_bottom = 1.0
		row_line.offset_left = 0
		row_line.offset_top = -2
		row_line.offset_right = 0
		row_line.offset_bottom = 0
		row_line.mouse_filter = MOUSE_FILTER_IGNORE
		row_panel.add_child(row_line)
		
		# 内嵌 HBoxContainer 装标签（覆盖在背景之上）
		var hbox = HBoxContainer.new()
		hbox.name = "RowHBox"
		hbox.anchor_left = 0.0
		hbox.anchor_top = 0.0
		hbox.anchor_right = 1.0
		hbox.anchor_bottom = 1.0
		hbox.offset_left = 0
		hbox.offset_top = 0
		hbox.offset_right = 0
		hbox.offset_bottom = 0
		hbox.mouse_filter = MOUSE_FILTER_IGNORE
		row_panel.add_child(hbox)
		
		# 名称
		var name_label = Label.new()
		name_label.text = row["name"]
		name_label.add_theme_font_size_override("font_size", 50)
		name_label.add_theme_color_override("font_color", row["color"])
		name_label.custom_minimum_size = Vector2(Global.pw(0.35), 0)
		name_label.size_flags_horizontal = SIZE_EXPAND
		hbox.add_child(name_label)
		
		# 类型
		var type_label = Label.new()
		type_label.text = row["category"]
		type_label.add_theme_font_size_override("font_size", 50)
		type_label.add_theme_color_override("font_color", Global.current.btn_text)
		type_label.custom_minimum_size = Vector2(Global.pw(0.18), 0)
		type_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hbox.add_child(type_label)
		
		# 稀有度
		var rarity_label = Label.new()
		rarity_label.text = row["rarity"]
		rarity_label.add_theme_font_size_override("font_size", 50)
		rarity_label.add_theme_color_override("font_color", row["color"])
		rarity_label.custom_minimum_size = Vector2(Global.pw(0.22), 0)
		rarity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hbox.add_child(rarity_label)
		
		# 数量
		var count_label = Label.new()
		count_label.text = "x" + str(int(row["count"]))
		count_label.add_theme_font_size_override("font_size", 50)
		count_label.add_theme_color_override("font_color", Global.current.title)
		count_label.custom_minimum_size = Vector2(Global.pw(0.15), 0)
		count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		hbox.add_child(count_label)
		
		vbox.add_child(row_panel)
		row_index += 1
	
	# 添加底部留白
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, Global.ph(0.05))
	vbox.add_child(spacer)


# ===== 标签切换 =====

func _switch_tab(tab: String):
	_current_tab = tab
	if tab == "card_base":
		_filter_category = ""
		_filter_rarity = ""
	# 更新按钮文字
	var btn = get_node_or_null("CategoryBtn")
	if btn:
		match tab:
			"all": btn.text = "全部"
			"material": btn.text = "素材"
			"card_base": btn.text = "卡基"
			"ink": btn.text = "卡墨"
			"aux": btn.text = "辅材"
	_refresh_list()

## 分类选择弹窗
func _show_category_popup() -> void:
	var overlay = ColorRect.new()
	overlay.name = "CategoryOverlay"
	overlay.color = Color(0.0, 0.0, 0.0, 0.6)
	overlay.anchor_left = 0.0; overlay.anchor_top = 0.0
	overlay.anchor_right = 1.0; overlay.anchor_bottom = 1.0
	overlay.mouse_filter = MOUSE_FILTER_STOP
	overlay.gui_input.connect(func(e: InputEvent, o = overlay):
		if e is InputEventScreenTouch and not e.pressed:
			e.accept()
			o.queue_free()
	)
	add_child(overlay)
	
	var panel = Panel.new()
	panel.name = "CategoryPanel"
	var ps = StyleBoxFlat.new()
	ps.bg_color = Color(0.12, 0.10, 0.18)
	ps.corner_radius_top_left = 16; ps.corner_radius_top_right = 16
	ps.corner_radius_bottom_left = 16; ps.corner_radius_bottom_right = 16
	ps.border_width_left = 2; ps.border_width_right = 2
	ps.border_width_top = 2; ps.border_width_bottom = 2
	ps.border_color = Color(0.5, 0.4, 0.7)
	panel.add_theme_stylebox_override("panel", ps)
	panel.anchor_left = 0.0; panel.anchor_top = 0.0
	panel.anchor_right = 1.0; panel.anchor_bottom = 1.0
	panel.offset_left = Global.pw(0.25)
	panel.offset_top = Global.ph(0.25)
	panel.offset_right = Global.pw(-0.25)
	panel.offset_bottom = -Global.ph(0.25)
	overlay.add_child(panel)
	
	var vbox = VBoxContainer.new()
	vbox.name = "CategoryVBox"
	vbox.anchor_left = 0.0; vbox.anchor_top = 0.0
	vbox.anchor_right = 1.0; vbox.anchor_bottom = 1.0
	vbox.offset_left = Global.pw(0.02); vbox.offset_top = Global.ph(0.02)
	vbox.offset_right = Global.pw(-0.02); vbox.offset_bottom = Global.ph(-0.02)
	vbox.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	vbox.add_theme_constant_override("separation", 0)
	panel.add_child(vbox)
	
	var categories = [
		{"tab": "all", "label": " 全部"},
		{"tab": "material", "label": " 素材"},
		{"tab": "card_base", "label": " 卡基"},
		{"tab": "ink", "label": " 卡墨"},
		{"tab": "aux", "label": " 辅材"},
	]
	
	for cat in categories:
		var is_active = (cat["tab"] == _current_tab)
		var btn = Button.new()
		btn.text = cat["label"]
		btn.add_theme_font_size_override("font_size", 50)
		var s = StyleBoxFlat.new()
		s.bg_color = Global.current.btn_bg_hover if is_active else Global.current.btn_bg
		s.border_width_bottom = 1
		s.border_color = Color(0.3, 0.25, 0.4)
		s.corner_radius_top_left = 0; s.corner_radius_top_right = 0
		s.corner_radius_bottom_left = 0; s.corner_radius_bottom_right = 0
		btn.add_theme_stylebox_override("normal", s)
		btn.add_theme_color_override("font_color", Global.current.title if is_active else Global.current.btn_text)
		btn.custom_minimum_size = Vector2(0, Global.ph(0.065))
		btn.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
		btn.pressed.connect(func():
			overlay.queue_free()
			_switch_tab(cat["tab"])
		)
		vbox.add_child(btn)
	
	# 调整面板高度适应内容
	await get_tree().process_frame
	var h = 0
	for child in vbox.get_children():
		if child is Button:
			h += child.custom_minimum_size.y
	panel.custom_minimum_size = Vector2(0, h)


## 全部列表渲染
func _refresh_all_list() -> void:
	var vbox = get_node_or_null("ListScroll/ListVBox")
	if not vbox:
		return
	
	for child in vbox.get_children():
		vbox.remove_child(child)
		child.queue_free()
	
	var has_any := false
	var row_index := 0
	
	# 素材
	var mats := WarehouseManager.get_materials()
	if mats.size() > 0:
		# 分类标题
		var sec_title = Label.new()
		sec_title.text = "素材"
		sec_title.add_theme_font_size_override("font_size", 55)
		sec_title.add_theme_color_override("font_color", Color("#f9d371"))
		sec_title.custom_minimum_size = Vector2(0, Global.ph(0.07))
		sec_title.add_theme_constant_override("outline_size", 0)
		vbox.add_child(sec_title)
		has_any = true
		
		for mid in mats.keys():
			var count = mats[mid]
			if count <= 0:
				continue
			var mat_data := Global.get_material_by_id(mid)
			if mat_data.is_empty():
				continue
			var name_str = mat_data.get("name", mid)
			var rarity = mat_data.get("rarity", "普通")
			var color = _get_rarity_color(rarity)
			
			var row = Panel.new()
			var rs = StyleBoxFlat.new()
			rs.bg_color = _get_row_bg_color(row_index)
			row.add_theme_stylebox_override("panel", rs)
			row.custom_minimum_size = Vector2(0, Global.ph(0.07))
			row.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
			row.mouse_filter = MOUSE_FILTER_PASS
			var category = _get_category(mid)
			row.set_meta("row_data", {"id": mid, "name": name_str, "rarity": rarity, "category": category, "count": count, "color": color})
			row.set_meta("row_index", row_index)
			row.set_meta("row_type", "material")
			vbox.add_child(row)
			
			var hbox = HBoxContainer.new()
			hbox.anchor_left = 0.0; hbox.anchor_top = 0.0
			hbox.anchor_right = 1.0; hbox.anchor_bottom = 1.0
			hbox.offset_left = Global.pw(0.03)
			hbox.offset_right = Global.pw(-0.03)
			hbox.mouse_filter = MOUSE_FILTER_IGNORE
			row.add_child(hbox)
			
			var name_lbl = Label.new()
			name_lbl.text = name_str
			name_lbl.add_theme_font_size_override("font_size", 42)
			name_lbl.add_theme_color_override("font_color", color)
			name_lbl.size_flags_horizontal = SIZE_EXPAND
			hbox.add_child(name_lbl)
			
			var count_lbl = Label.new()
			count_lbl.text = "x" + str(int(count))
			count_lbl.add_theme_font_size_override("font_size", 42)
			count_lbl.add_theme_color_override("font_color", Global.current.title)
			count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			count_lbl.custom_minimum_size = Vector2(Global.pw(0.12), 0)
			hbox.add_child(count_lbl)
			
			row_index += 1
	
	# 卡基
	var cbs = WarehouseManager.get_card_bases()
	if cbs.size() > 0:
		var sec_title = Label.new()
		sec_title.text = "卡基"
		sec_title.add_theme_font_size_override("font_size", 55)
		sec_title.add_theme_color_override("font_color", Color("#60a5fa"))
		sec_title.custom_minimum_size = Vector2(0, Global.ph(0.07))
		vbox.add_child(sec_title)
		has_any = true
		
		for cb_id in cbs.keys():
			var cb_data = cbs[cb_id]
			if cb_data.is_empty():
				continue
			var name_str = WarehouseManager.get_card_base_display_name(cb_data)
			var rarity = cb_data.get("rarity", "普通")
			var color = _get_rarity_color(rarity)
			
			var row = Panel.new()
			var rs = StyleBoxFlat.new()
			rs.bg_color = _get_row_bg_color(row_index)
			row.add_theme_stylebox_override("panel", rs)
			row.custom_minimum_size = Vector2(0, Global.ph(0.07))
			row.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
			row.mouse_filter = MOUSE_FILTER_PASS
			row.set_meta("row_data", cb_data)
			row.set_meta("row_index", row_index)
			row.set_meta("row_type", "card_base")
			vbox.add_child(row)
			
			var hbox = HBoxContainer.new()
			hbox.anchor_left = 0.0; hbox.anchor_top = 0.0
			hbox.anchor_right = 1.0; hbox.anchor_bottom = 1.0
			hbox.offset_left = Global.pw(0.03)
			hbox.offset_right = Global.pw(-0.03)
			hbox.mouse_filter = MOUSE_FILTER_IGNORE
			row.add_child(hbox)
			
			var name_lbl = Label.new()
			name_lbl.text = name_str
			name_lbl.add_theme_font_size_override("font_size", 42)
			name_lbl.add_theme_color_override("font_color", color)
			name_lbl.size_flags_horizontal = SIZE_EXPAND
			hbox.add_child(name_lbl)
			
			row_index += 1
	
	# 卡墨
	var inks = WarehouseManager.get_ink_inventory()
	if inks.size() > 0:
		var sec_title = Label.new()
		sec_title.text = "卡墨"
		sec_title.add_theme_font_size_override("font_size", 55)
		sec_title.add_theme_color_override("font_color", Color("#c084fc"))
		sec_title.custom_minimum_size = Vector2(0, Global.ph(0.07))
		vbox.add_child(sec_title)
		has_any = true
		
		for ink in inks:
			if ink.is_empty():
				continue
			var name_str = ink.get("name", "未知卡墨")
			var ink_id = ink.get("id", "")
			var load_reduce = ink.get("load_reduce", 0)
			var effect_power = ink.get("effect_power", 0)
			
			var row = Panel.new()
			var rs = StyleBoxFlat.new()
			rs.bg_color = _get_row_bg_color(row_index)
			row.add_theme_stylebox_override("panel", rs)
			row.custom_minimum_size = Vector2(0, Global.ph(0.07))
			row.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
			row.mouse_filter = MOUSE_FILTER_PASS
			row.set_meta("row_data", ink)
			row.set_meta("row_index", row_index)
			row.set_meta("row_type", "ink")
			vbox.add_child(row)
			
			var hbox = HBoxContainer.new()
			hbox.anchor_left = 0.0; hbox.anchor_top = 0.0
			hbox.anchor_right = 1.0; hbox.anchor_bottom = 1.0
			hbox.offset_left = Global.pw(0.03)
			hbox.offset_right = Global.pw(-0.03)
			hbox.mouse_filter = MOUSE_FILTER_IGNORE
			row.add_child(hbox)
			
			var name_lbl = Label.new()
			name_lbl.text = name_str
			name_lbl.add_theme_font_size_override("font_size", 42)
			name_lbl.add_theme_color_override("font_color", Color("#c084fc"))
			name_lbl.size_flags_horizontal = SIZE_EXPAND
			hbox.add_child(name_lbl)
			
			var info_lbl = Label.new()
			info_lbl.text = "负荷-" + str(load_reduce) + " 效果+" + str(effect_power) + "%"
			info_lbl.add_theme_font_size_override("font_size", 30)
			info_lbl.add_theme_color_override("font_color", Color("#7a7a8a"))
			info_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			info_lbl.custom_minimum_size = Vector2(Global.pw(0.35), 0)
			hbox.add_child(info_lbl)
			
			row_index += 1
	
	# 辅材
	var aux_inv = WarehouseManager.get_aux_items()
	if aux_inv.size() > 0:
		var sec_title = Label.new()
		sec_title.text = "辅材"
		sec_title.add_theme_font_size_override("font_size", 55)
		sec_title.add_theme_color_override("font_color", Color("#4ade80"))
		sec_title.custom_minimum_size = Vector2(0, Global.ph(0.07))
		vbox.add_child(sec_title)
		has_any = true
		
		for aid in aux_inv.keys():
			var count = aux_inv[aid]
			if count <= 0:
				continue
			var aux_data = Global.get_aux_by_id(aid)
			if aux_data.is_empty():
				continue
			var name_str = aux_data.get("name", "未知")
			var rarity = aux_data.get("rarity", "普通")
			var color = _get_rarity_color(rarity)
			
			var row = Panel.new()
			var rs = StyleBoxFlat.new()
			rs.bg_color = _get_row_bg_color(row_index)
			row.add_theme_stylebox_override("panel", rs)
			row.custom_minimum_size = Vector2(0, Global.ph(0.07))
			row.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
			row.mouse_filter = MOUSE_FILTER_PASS
			row.set_meta("row_data", aux_data)
			row.set_meta("row_index", row_index)
			row.set_meta("row_type", "aux")
			vbox.add_child(row)
			
			var hbox = HBoxContainer.new()
			hbox.anchor_left = 0.0; hbox.anchor_top = 0.0
			hbox.anchor_right = 1.0; hbox.anchor_bottom = 1.0
			hbox.offset_left = Global.pw(0.03)
			hbox.offset_right = Global.pw(-0.03)
			hbox.mouse_filter = MOUSE_FILTER_IGNORE
			row.add_child(hbox)
			
			var name_lbl = Label.new()
			name_lbl.text = name_str
			name_lbl.add_theme_font_size_override("font_size", 42)
			name_lbl.add_theme_color_override("font_color", color)
			name_lbl.size_flags_horizontal = SIZE_EXPAND
			hbox.add_child(name_lbl)
			
			var count_lbl = Label.new()
			count_lbl.text = "x" + str(int(count))
			count_lbl.add_theme_font_size_override("font_size", 42)
			count_lbl.add_theme_color_override("font_color", Global.current.title)
			count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			count_lbl.custom_minimum_size = Vector2(Global.pw(0.12), 0)
			hbox.add_child(count_lbl)
			
			row_index += 1
	
	if not has_any:
		var empty = Label.new()
		empty.text = "仓库空空如也..."
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_font_size_override("font_size", 50)
		empty.add_theme_color_override("font_color", Color("#5a5a6e"))
		empty.custom_minimum_size = Vector2(0, Global.ph(0.1))
		vbox.add_child(empty)
	
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, Global.ph(0.05))
	vbox.add_child(spacer)


# ===== 卡基列表渲染 =====

func _refresh_card_base_list():
	var vbox = get_node_or_null("ListScroll/ListVBox")
	if not vbox:
		return
	
	for child in vbox.get_children():
		vbox.remove_child(child)
		child.queue_free()
	
	var bases := WarehouseManager.get_card_bases()
	if bases.size() == 0:
		var empty = Label.new()
		empty.text = "还没有卡基，去制作一些吧！"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_font_size_override("font_size", 50)
		empty.add_theme_color_override("font_color", Color("#5a5a6e"))
		empty.custom_minimum_size = Vector2(0, Global.ph(0.1))
		vbox.add_child(empty)
		return
	
	var base_list := []
	for cid in bases.keys():
		base_list.append(bases[cid])
	
	base_list.sort_custom(func(a, b):
		return a.get("created_at", 0) > b.get("created_at", 0)
	)
	
	var row_index := 0
	for data in base_list:
		var cid = data.get("id", "未知")
		var quality = data.get("quality", "—")
		var load_cap = data.get("load_cap", 0)
		var slots = data.get("slots", 0)
		var durability = data.get("durability", 0)
		
		var row_panel = Panel.new()
		row_panel.name = "RowPanel"
		var panel_style = StyleBoxFlat.new()
		panel_style.bg_color = _get_row_bg_color(row_index)
		row_panel.add_theme_stylebox_override("panel", panel_style)
		row_panel.custom_minimum_size = Vector2(0, Global.ph(0.095))
		row_panel.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
		row_panel.mouse_filter = MOUSE_FILTER_PASS
		row_panel.set_meta("row_data", data)
		row_panel.set_meta("row_index", row_index)
		row_panel.set_meta("row_type", "card_base")
		
		var row_line = ColorRect.new()
		row_line.name = "RowLine"
		row_line.color = Color(1.0, 1.0, 1.0, 0.20)
		row_line.anchor_left = 0.0
		row_line.anchor_top = 1.0
		row_line.anchor_right = 1.0
		row_line.anchor_bottom = 1.0
		row_line.offset_left = 0
		row_line.offset_top = -2
		row_line.offset_right = 0
		row_line.offset_bottom = 0
		row_line.mouse_filter = MOUSE_FILTER_IGNORE
		row_panel.add_child(row_line)
		
		var hbox = HBoxContainer.new()
		hbox.name = "RowHBox"
		hbox.anchor_left = 0.0
		hbox.anchor_top = 0.0
		hbox.anchor_right = 1.0
		hbox.anchor_bottom = 1.0
		hbox.offset_left = Global.pw(0.02)
		hbox.offset_top = 0
		hbox.offset_right = Global.pw(-0.02)
		hbox.offset_bottom = 0
		hbox.mouse_filter = MOUSE_FILTER_IGNORE
		row_panel.add_child(hbox)
		
		# 左侧：品质 + ID
		var left_vbox = VBoxContainer.new()
		left_vbox.size_flags_horizontal = SIZE_EXPAND
		left_vbox.add_theme_constant_override("separation", 0)
		hbox.add_child(left_vbox)
		
		var quality_label = Label.new()
		quality_label.text = "品质: " + str(quality)
		quality_label.add_theme_font_size_override("font_size", 45)
		quality_label.add_theme_color_override("font_color", Global.current.title)
		left_vbox.add_child(quality_label)
		
		var id_label = Label.new()
		id_label.text = cid.substr(0, 14) + "..."
		id_label.add_theme_font_size_override("font_size", 30)
		id_label.add_theme_color_override("font_color", Global.current.btn_text)
		left_vbox.add_child(id_label)
		
		# 右侧：属性
		var attrs_label = Label.new()
		attrs_label.text = "承载力:" + str(load_cap) + " 卡槽:" + str(slots) + " 耐久:" + str(durability)
		attrs_label.add_theme_font_size_override("font_size", 35)
		attrs_label.add_theme_color_override("font_color", Global.current.btn_text)
		attrs_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		attrs_label.custom_minimum_size = Vector2(Global.pw(0.5), 0)
		attrs_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hbox.add_child(attrs_label)
		
		vbox.add_child(row_panel)
		row_index += 1
	
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, Global.ph(0.05))
	vbox.add_child(spacer)


# ===== 卡墨列表渲染 =====

func _refresh_ink_list():
	var vbox = get_node_or_null("ListScroll/ListVBox")
	if not vbox:
		return
	
	for child in vbox.get_children():
		vbox.remove_child(child)
		child.queue_free()
	
	var inks := WarehouseManager.get_ink_inventory()
	if inks.size() == 0:
		var empty = Label.new()
		empty.text = "还没有卡墨，去调制一些吧！"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_font_size_override("font_size", 50)
		empty.add_theme_color_override("font_color", Color("#5a5a6e"))
		empty.custom_minimum_size = Vector2(0, Global.ph(0.1))
		vbox.add_child(empty)
		return
	
	# 按加入顺序倒序显示
	var ink_list := inks.duplicate()
	ink_list.reverse()
	
	var row_index := 0
	for data in ink_list:
		var ink_id = data.get("id", "未知")
		var ink_name = data.get("name", "未知卡墨")
		var load_reduce = data.get("load_reduce", 0)
		var effect_power = data.get("effect_power", 0)
		var quality_stab = data.get("quality_stab", 0)
		
		var row_panel = Panel.new()
		row_panel.name = "RowPanel"
		var panel_style = StyleBoxFlat.new()
		panel_style.bg_color = _get_row_bg_color(row_index)
		row_panel.add_theme_stylebox_override("panel", panel_style)
		row_panel.custom_minimum_size = Vector2(0, Global.ph(0.095))
		row_panel.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
		row_panel.mouse_filter = MOUSE_FILTER_PASS
		row_panel.set_meta("row_data", data)
		row_panel.set_meta("row_index", row_index)
		row_panel.set_meta("row_type", "ink")
		
		var row_line = ColorRect.new()
		row_line.name = "RowLine"
		row_line.color = Color(1.0, 1.0, 1.0, 0.20)
		row_line.anchor_left = 0.0
		row_line.anchor_top = 1.0
		row_line.anchor_right = 1.0
		row_line.anchor_bottom = 1.0
		row_line.offset_left = 0
		row_line.offset_top = -2
		row_line.offset_right = 0
		row_line.offset_bottom = 0
		row_line.mouse_filter = MOUSE_FILTER_IGNORE
		row_panel.add_child(row_line)
		
		var hbox = HBoxContainer.new()
		hbox.name = "RowHBox"
		hbox.anchor_left = 0.0
		hbox.anchor_top = 0.0
		hbox.anchor_right = 1.0
		hbox.anchor_bottom = 1.0
		hbox.offset_left = Global.pw(0.02)
		hbox.offset_top = 0
		hbox.offset_right = Global.pw(-0.02)
		hbox.offset_bottom = 0
		hbox.mouse_filter = MOUSE_FILTER_IGNORE
		row_panel.add_child(hbox)
		
		# 左侧：名称
		var left_vbox = VBoxContainer.new()
		left_vbox.size_flags_horizontal = SIZE_EXPAND
		left_vbox.add_theme_constant_override("separation", 0)
		hbox.add_child(left_vbox)
		
		var name_label = Label.new()
		name_label.text = ink_name
		name_label.add_theme_font_size_override("font_size", 45)
		name_label.add_theme_color_override("font_color", Global.current.title)
		left_vbox.add_child(name_label)
		
		var id_label = Label.new()
		id_label.text = ink_id.substr(0, 20) + (". . ." if ink_id.length() > 20 else "")
		id_label.add_theme_font_size_override("font_size", 30)
		id_label.add_theme_color_override("font_color", Global.current.btn_text)
		left_vbox.add_child(id_label)
		
		# 右侧：属性
		var attrs_label = Label.new()
		attrs_label.text = "负荷减免:" + str(load_reduce) + " 效果:" + str(effect_power) + "% 稳定:" + str(quality_stab) + "%"
		attrs_label.add_theme_font_size_override("font_size", 35)
		attrs_label.add_theme_color_override("font_color", Global.current.btn_text)
		attrs_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		attrs_label.custom_minimum_size = Vector2(Global.pw(0.5), 0)
		attrs_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hbox.add_child(attrs_label)
		
		vbox.add_child(row_panel)
		row_index += 1
	
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, Global.ph(0.05))
	vbox.add_child(spacer)


# ===== 辅材列表渲染 =====

func _refresh_aux_list():
	var vbox = get_node_or_null("ListScroll/ListVBox")
	if not vbox:
		return
	
	for child in vbox.get_children():
		vbox.remove_child(child)
		child.queue_free()
	
	var aux_inv = WarehouseManager.get_aux_items()
	if aux_inv.size() == 0:
		var empty = Label.new()
		empty.text = "还没有辅材，去击败卡兽获取吧！"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_font_size_override("font_size", 50)
		empty.add_theme_color_override("font_color", Color("#5a5a6e"))
		empty.custom_minimum_size = Vector2(0, Global.ph(0.1))
		vbox.add_child(empty)
		return
	
	var row_index := 0
	for aid in aux_inv.keys():
		var count = aux_inv[aid]
		if count <= 0:
			continue
		var aux_data = Global.get_aux_by_id(aid)
		if aux_data.is_empty():
			continue
		
		var aname = aux_data.get("name", "未知")
		var rarity = aux_data.get("rarity", "普通")
		var desc = aux_data.get("description", "")
		var atype = aux_data.get("type", "")
		
		var rarity_color = Color("#e8d5b7")
		match rarity:
			"传说": rarity_color = Color("#f9d371")
			"史诗": rarity_color = Color("#c084fc")
			"稀有": rarity_color = Color("#60a5fa")
		
		var row_panel = Panel.new()
		row_panel.name = "RowPanel"
		var panel_style = StyleBoxFlat.new()
		panel_style.bg_color = _get_row_bg_color(row_index)
		row_panel.add_theme_stylebox_override("panel", panel_style)
		row_panel.custom_minimum_size = Vector2(0, Global.ph(0.095))
		row_panel.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
		row_panel.mouse_filter = MOUSE_FILTER_PASS
		row_panel.set_meta("row_data", aux_data)
		row_panel.set_meta("row_index", row_index)
		row_panel.set_meta("row_type", "aux")
		
		var row_line = ColorRect.new()
		row_line.name = "RowLine"
		row_line.color = Color(1.0, 1.0, 1.0, 0.20)
		row_line.anchor_left = 0.0
		row_line.anchor_top = 1.0
		row_line.anchor_right = 1.0
		row_line.anchor_bottom = 1.0
		row_line.offset_left = 0
		row_line.offset_top = -2
		row_line.offset_right = 0
		row_line.offset_bottom = 0
		row_line.mouse_filter = MOUSE_FILTER_IGNORE
		row_panel.add_child(row_line)
		
		var hbox = HBoxContainer.new()
		hbox.name = "RowHBox"
		hbox.anchor_left = 0.0
		hbox.anchor_top = 0.0
		hbox.anchor_right = 1.0
		hbox.anchor_bottom = 1.0
		hbox.offset_left = Global.pw(0.02)
		hbox.offset_top = 0
		hbox.offset_right = Global.pw(-0.02)
		hbox.offset_bottom = 0
		hbox.mouse_filter = MOUSE_FILTER_IGNORE
		row_panel.add_child(hbox)
		
		# 左侧：名称+描述
		var left_vbox = VBoxContainer.new()
		left_vbox.size_flags_horizontal = SIZE_EXPAND
		left_vbox.add_theme_constant_override("separation", 0)
		hbox.add_child(left_vbox)
		
		var name_label = Label.new()
		name_label.text = aname
		name_label.add_theme_font_size_override("font_size", 45)
		name_label.add_theme_color_override("font_color", rarity_color)
		left_vbox.add_child(name_label)
		
		var desc_label = Label.new()
		desc_label.text = desc
		desc_label.add_theme_font_size_override("font_size", 32)
		desc_label.add_theme_color_override("font_color", Global.current.btn_text)
		left_vbox.add_child(desc_label)
		
		# 右侧：数量+类型
		var right_vbox = VBoxContainer.new()
		right_vbox.custom_minimum_size = Vector2(Global.pw(0.2), 0)
		hbox.add_child(right_vbox)
		
		var count_label = Label.new()
		count_label.text = "x" + str(int(count))
		count_label.add_theme_font_size_override("font_size", 45)
		count_label.add_theme_color_override("font_color", rarity_color)
		count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		right_vbox.add_child(count_label)
		
		var type_label = Label.new()
		match atype:
			"boost": type_label.text = "增幅"
			"element": type_label.text = "元素"
			"protect": type_label.text = "保护"
			"special": type_label.text = "特殊"
			"poison": type_label.text = "剧毒"
			"combo": type_label.text = "连击"
			_: type_label.text = atype
		type_label.add_theme_font_size_override("font_size", 30)
		type_label.add_theme_color_override("font_color", Global.current.btn_text)
		type_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		right_vbox.add_child(type_label)
		
		vbox.add_child(row_panel)
		row_index += 1
	
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, Global.ph(0.05))
	vbox.add_child(spacer)


func _show_ink_detail(row: Control) -> void:
	var data = row.get_meta("row_data")
	if data == null:
		return
	
	var ink_id = data.get("id", "未知")
	var ink_name = data.get("name", "未知卡墨")
	var load_reduce = data.get("load_reduce", 0)
	var effect_power = data.get("effect_power", 0)
	var quality_stab = data.get("quality_stab", 0)
	var discount = data.get("discount", {})
	var resistance = data.get("resistance", {})
	var materials = data.get("materials", {})
	
	var overlay = ColorRect.new()
	overlay.name = "DetailOverlay"
	overlay.color = Color(0.0, 0.0, 0.0, 0.6)
	overlay.anchor_left = 0.0
	overlay.anchor_top = 0.0
	overlay.anchor_right = 1.0
	overlay.anchor_bottom = 1.0
	overlay.mouse_filter = MOUSE_FILTER_STOP
	overlay.gui_input.connect(_on_overlay_clicked.bind(overlay))
	add_child(overlay)
	
	var panel = ColorRect.new()
	panel.name = "DetailPanel"
	panel.color = Global.current.bg
	panel.anchor_left = 0.0
	panel.anchor_top = 0.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 0.0
	panel.offset_left = Global.pw(0.05)
	panel.offset_top = Global.ph(0.2)
	panel.offset_right = Global.pw(-0.05)
	panel.offset_bottom = Global.ph(0.6)
	overlay.add_child(panel)
	
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color.TRANSPARENT
	panel_style.corner_radius_top_left = 20
	panel_style.corner_radius_top_right = 20
	panel_style.corner_radius_bottom_left = 20
	panel_style.corner_radius_bottom_right = 20
	panel.add_theme_stylebox_override("panel", panel_style)
	
	var title_label = Label.new()
	title_label.text = "卡墨"
	title_label.add_theme_font_size_override("font_size", 60)
	title_label.add_theme_color_override("font_color", Global.current.title)
	title_label.add_theme_color_override("font_shadow_color", Global.current.title_shadow)
	title_label.add_theme_constant_override("shadow_offset_x", 2)
	title_label.add_theme_constant_override("shadow_offset_y", 2)
	title_label.anchor_left = 0.0
	title_label.anchor_top = 0.0
	title_label.anchor_right = 1.0
	title_label.anchor_bottom = 0.0
	title_label.offset_left = Global.pw(0.04)
	title_label.offset_top = Global.ph(0.015)
	title_label.offset_right = Global.pw(-0.04)
	title_label.offset_bottom = Global.ph(0.08)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(title_label)
	
	var name_label2 = Label.new()
	name_label2.text = ink_name
	name_label2.add_theme_font_size_override("font_size", 40)
	name_label2.add_theme_color_override("font_color", Global.current.btn_text)
	name_label2.anchor_left = 0.0
	name_label2.anchor_top = 0.0
	name_label2.anchor_right = 1.0
	name_label2.anchor_bottom = 0.0
	name_label2.offset_left = 0
	name_label2.offset_top = Global.ph(0.075)
	name_label2.offset_right = 0
	name_label2.offset_bottom = Global.ph(0.11)
	name_label2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(name_label2)
	
	var line = ColorRect.new()
	line.color = Global.current.topbar_border
	line.anchor_left = 0.0
	line.anchor_top = 0.0
	line.anchor_right = 1.0
	line.anchor_bottom = 0.0
	line.offset_left = Global.pw(0.05)
	line.offset_top = Global.ph(0.115)
	line.offset_right = Global.pw(-0.05)
	line.offset_bottom = Global.ph(0.12)
	panel.add_child(line)
	
	# 倾向折扣文本
	var discount_str := "无"
	if not discount.is_empty():
		var parts := []
		for k in discount.keys():
			parts.append(k + str(discount[k]) + "%")
		discount_str = " ".join(parts)
	
	var info_y := 0.13
	var info_labels := [
		["负荷减免", str(load_reduce)],
		["效果强度加成", str(effect_power) + "%"],
		["品质稳定性", str(quality_stab) + "%"],
		["倾向折扣", discount_str],
		["属性抗性", _format_ink_resistance(resistance)],
	]
	
	# 素材消耗
	var mat_parts := []
	for key in ["extract", "pigment", "binder"]:
		if materials.has(key):
			for mid in materials[key].keys():
				var mat = Global.get_material_by_id(mid)
				if not mat.is_empty():
					mat_parts.append(mat.get("name", mid))
	if mat_parts.size() > 0:
		info_labels.append(["素材", " ".join(mat_parts)])
	
	for info in info_labels:
		var key = info[0]
		var val = info[1]
		
		var key_label = Label.new()
		key_label.text = key + "："
		key_label.add_theme_font_size_override("font_size", 36)
		key_label.add_theme_color_override("font_color", Global.current.btn_text)
		key_label.anchor_left = 0.0
		key_label.anchor_top = 0.0
		key_label.anchor_right = 1.0
		key_label.anchor_bottom = 0.0
		key_label.offset_left = Global.pw(0.06)
		key_label.offset_top = Global.ph(info_y)
		key_label.offset_right = Global.pw(-0.5)
		key_label.offset_bottom = Global.ph(info_y + 0.04)
		panel.add_child(key_label)
		
		var val_label = Label.new()
		val_label.text = val
		val_label.add_theme_font_size_override("font_size", 36)
		val_label.add_theme_color_override("font_color", Global.current.title)
		val_label.anchor_left = 0.0
		val_label.anchor_top = 0.0
		val_label.anchor_right = 1.0
		val_label.anchor_bottom = 0.0
		val_label.offset_left = Global.pw(0.5)
		val_label.offset_top = Global.ph(info_y)
		val_label.offset_right = Global.pw(-0.06)
		val_label.offset_bottom = Global.ph(info_y + 0.04)
		val_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		panel.add_child(val_label)
		
		info_y += 0.045
	
	var close_btn = Button.new()
	close_btn.text = "关闭"
	close_btn.add_theme_font_size_override("font_size", 45)
	var cs = StyleBoxFlat.new()
	cs.bg_color = Global.current.btn_bg
	cs.border_width_left = 2
	cs.border_width_right = 2
	cs.border_width_top = 2
	cs.border_width_bottom = 2
	cs.border_color = Color("#888888")
	cs.corner_radius_top_left = 12
	cs.corner_radius_top_right = 12
	cs.corner_radius_bottom_left = 12
	cs.corner_radius_bottom_right = 12
	cs.content_margin_left = 24
	cs.content_margin_right = 24
	close_btn.add_theme_stylebox_override("normal", cs)
	close_btn.add_theme_color_override("font_color", Global.current.btn_text)
	close_btn.anchor_left = 0.0
	close_btn.anchor_top = 0.0
	close_btn.anchor_right = 1.0
	close_btn.anchor_bottom = 0.0
	close_btn.offset_left = Global.pw(0.25)
	close_btn.offset_top = Global.ph(0.45)
	close_btn.offset_right = Global.pw(-0.25)
	close_btn.offset_bottom = Global.ph(0.51)
	close_btn.pressed.connect(_close_detail.bind(overlay))
	panel.add_child(close_btn)


# 格式化卡墨抗性字典为字符串
func _format_ink_resistance(resistance: Dictionary) -> String:
	if resistance.is_empty():
		return "无"
	var parts := []
	for k in resistance.keys():
		var elem_name := ""
		match k:
			"火": elem_name = "火"
			"水": elem_name = "水"
			"风": elem_name = "风"
			"暗": elem_name = "暗"
			"光": elem_name = "光"
			"all": elem_name = "全属性"
			_: elem_name = k
		parts.append(elem_name + "+" + str(resistance[k]) + "%")
	return " ".join(parts)


func _get_category(mid: String) -> String:
	if mid.begins_with("F"):
		return "纤维"
	elif mid.begins_with("M"):
		return "矿粉"
	elif mid.begins_with("R"):
		return "树脂"
	elif mid.begins_with("E"):
		return "萃取液"
	elif mid.begins_with("P"):
		return "颜料"
	elif mid.begins_with("B"):
		return "粘合剂"
	return "未知"


func _get_rarity_color(rarity: String) -> Color:
	match rarity:
		"传说":
			return Color("#f9d371")  # 金色
		"史诗":
			return Color("#c084fc")  # 紫色
		"稀有":
			return Color("#60a5fa")  # 蓝色
		_:
			return Global.current.btn_text  # 普通=默认文本色


# 交替斑马纹背景色
func _get_row_bg_color(row_index: int) -> Color:
	# 斑马纹第二色必须是「略深的羊皮纸」，不能是透明：页面底色是深色贴图，
	# 透明会让后半数行压成深底，而行内文字是深棕色 -> 整行看不见。
	if row_index % 2 == 0:
		return Global.current.topbar_bg
	return Global.current.topbar_bg.darkened(0.10)


# ===== 长按弹窗 =====

func _setup_long_press() -> void:
	set_process(true)

func _process(delta: float) -> void:
	if _pressed_row != null:
		_press_timer += delta
		if _press_timer >= LONG_PRESS_TIME:
			_show_detail(_pressed_row)
			_cancel_press()

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			# 按下：找到触摸位置下的素材行
			var row = _find_row_at(event.position)
			if row != null:
				_pressed_row = row
				_press_timer = 0.0
				_press_start_pos = event.position
				_press_index = event.index
				# 高亮行背景（Panel用StyleBox改色）
				var sb = StyleBoxFlat.new()
				sb.bg_color = Global.current.btn_bg_hover
				row.add_theme_stylebox_override("panel", sb)
		else:
			# 松开：如果计时没到就取消
			if event.index == _press_index:
				_cancel_press()
	
	elif event is InputEventScreenDrag:
		# 滑动检测：移动超过阈值就取消长按
		if _pressed_row != null and event.index == _press_index:
			var dist = event.position.distance_to(_press_start_pos)
			if dist > DRAG_THRESHOLD:
				_cancel_press()

func _find_row_at(pos: Vector2) -> Control:
	var vbox = get_node_or_null("ListScroll/ListVBox")
	if not vbox:
		return null
	# 遍历所有Control检测点击
	for child in vbox.get_children():
		if child is Control and child.has_meta("row_data"):
			var rect = Rect2(child.get_global_rect().position, child.get_global_rect().size)
			if rect.has_point(pos):
				return child
	return null

func _cancel_press() -> void:
	if _pressed_row != null:
		var idx = _pressed_row.get_meta("row_index", 0)
		var sb = StyleBoxFlat.new()
		sb.bg_color = _get_row_bg_color(idx)
		_pressed_row.add_theme_stylebox_override("panel", sb)
	_pressed_row = null
	_press_timer = 0.0
	_press_index = -1


func _show_detail(row: Control):
	var row_type = row.get_meta("row_type", "material")
	var data = row.get_meta("row_data")
	if data == null:
		return
	
	# 根据类型获取数据
	var title_text := ""
	var subtitle_text := ""
	var info_pairs := []
	var rarity_color = Color("#e8d5b7")
	var icon := ""
	
	match row_type:
		"material":
			icon = ""
			var mid: String = data.get("id", "")
			var mat_data := Global.get_material_by_id(mid)
			if mat_data.is_empty():
				return
			var name_str = mat_data.get("name", "未知")
			var rarity = mat_data.get("rarity", "普通")
			var category = data.get("category", _get_category(mid))
			var area = mat_data.get("area", "未知")
			var tendency = mat_data.get("tendency", "无")
			if tendency == "": tendency = "无"
			var count = data.get("count", 0)
			rarity_color = _get_rarity_color(rarity)
			title_text = name_str
			subtitle_text = rarity + "  ·  " + category + "  ·  x" + str(int(count))
			var props_text := ""
			match category:
				"纤维": props_text = "承载力: " + str(mat_data.get("carry", 0)) + "  韧性: " + str(mat_data.get("toughness", 0))
				"矿粉": props_text = "稳定性: " + str(mat_data.get("stability", 0)) + "  硬度: " + str(mat_data.get("hardness", 0))
				"树脂": props_text = "粘合度: " + str(mat_data.get("bond", 0)) + "  光泽: " + str(mat_data.get("gloss", 0))
				"萃取液": props_text = "传导性: " + str(mat_data.get("conductivity", 0)) + "  纯度: " + str(mat_data.get("purity", 0))
				"颜料": props_text = "附着力: " + str(mat_data.get("adhesion", 0)) + "  显色: " + str(mat_data.get("chromatography", 0))
				"粘合剂": props_text = "调和度: " + str(mat_data.get("harmony", 0))
			info_pairs = [["采集区域", area], ["倾向", tendency], ["属性", props_text]]
		
		"card_base":
			icon = ""
			var cid = data.get("id", "未知")
			var quality = data.get("quality", "—")
			var load_cap = data.get("load_cap", 0)
			var slots = data.get("slots", 0)
			var durability = data.get("durability", 0)
			var tendency = data.get("tendency", {})
			var created_at = data.get("created_at", 0)
			title_text = "卡基"
			subtitle_text = "ID: " + cid
			rarity_color = Color("#60a5fa")
			var tendency_str := "无"
			if not tendency.is_empty():
				var parts := []
				for k in tendency.keys(): parts.append(k + str(tendency[k]))
				tendency_str = " ".join(parts)
			info_pairs = [["品质", str(quality)], ["承载力", str(load_cap)], ["卡槽", str(slots)], ["耐久度", str(durability)], ["倾向", tendency_str], ["制作时间", Time.get_date_string_from_unix_time(created_at) if created_at > 0 else "未知"]]
		
		"ink":
			icon = ""
			var ink_name = data.get("name", "未知卡墨")
			var ink_id = data.get("id", "未知")
			var load_reduce = data.get("load_reduce", 0)
			var effect_power = data.get("effect_power", 0)
			var quality_stab = data.get("quality_stab", 0)
			var discount = data.get("discount", {})
			var resistance = data.get("resistance", {})
			var materials = data.get("materials", {})
			title_text = ink_name
			subtitle_text = "ID: " + ink_id
			rarity_color = Color("#c084fc")
			var discount_str := "无"
			if not discount.is_empty():
				var parts := []
				for k in discount.keys(): parts.append(k + str(discount[k]) + "%")
				discount_str = " ".join(parts)
			var resistance_str := "无"
			if not resistance.is_empty():
				var parts := []
				for k in resistance.keys(): parts.append(k + "抗性" + str(resistance[k]))
				resistance_str = " ".join(parts)
			info_pairs = [["负荷减免", str(load_reduce)], ["效果强度加成", str(effect_power) + "%"], ["品质稳定性", str(quality_stab) + "%"], ["倾向折扣", discount_str], ["属性抗性", resistance_str]]
			var mat_parts := []
			for key in ["extract", "pigment", "binder"]:
				if materials.has(key):
					for mid in materials[key].keys():
						var mat = Global.get_material_by_id(mid)
						if not mat.is_empty(): mat_parts.append(mat.get("name", mid))
			if mat_parts.size() > 0: info_pairs.append(["素材", " ".join(mat_parts)])
		
		"aux":
			icon = ""
			var aname = data.get("name", "未知")
			var aid = data.get("id", "未知")
			var rarity = data.get("rarity", "普通")
			var desc = data.get("description", "")
			var atype = data.get("type", "")
			var effect = data.get("effect", {})
			rarity_color = _get_rarity_color(rarity)
			var type_name = ""
			match atype:
				"boost": type_name = " 属性增幅"
				"element": type_name = " 元素赋予"
				"protect": type_name = " 保护"
				"special": type_name = " 特殊效果"
			title_text = aname
			subtitle_text = rarity + "  ·  " + type_name
			info_pairs = [["说明", desc]]
			var effect_text := ""
			for k in effect.keys():
				var v = effect[k]
				match k:
					"atk_bonus": effect_text += "攻击力+" + str(v)
					"hp_bonus": effect_text += "生命值+" + str(v)
					"damage_reduce": effect_text += "受到伤害-" + str(v)
					"damage_halve": effect_text += "伤害减半"
					"shield": effect_text += "护盾" + str(v) + "点"
					"element": effect_text += "赋予" + str(v) + "属性"
					"element_power": effect_text += "，效果强度+" + str(v * 100) + "%"
					"energy_reduce": effect_text += "能量消耗-" + str(v)
					"draw_on_summon": effect_text += "上场抽" + str(v) + "张牌"
					"haste": effect_text += "召唤当回合可攻击"
					"indestructible_once": effect_text += "免破坏（1次）"
					"field_sync": effect_text += "同字段在场时攻防各+" + str(v.get("atk", 0))
					"extra_trigger": effect_text += "额外触发" + str(v) + "次"
					_: effect_text += k + ":" + str(v)
			if effect_text != "": info_pairs.append(["效果", effect_text])
	
	# ---- 统一弹窗渲染 ----
	var overlay = ColorRect.new()
	overlay.name = "DetailOverlay"
	overlay.color = Color(0.0, 0.0, 0.0, 0.65)
	overlay.anchor_left = 0.0; overlay.anchor_top = 0.0
	overlay.anchor_right = 1.0; overlay.anchor_bottom = 1.0
	overlay.mouse_filter = MOUSE_FILTER_STOP
	overlay.gui_input.connect(_on_overlay_clicked.bind(overlay))
	add_child(overlay)
	
	var panel = Panel.new()
	panel.name = "DetailPanel"
	var ps = StyleBoxFlat.new()
	ps.bg_color = Color(0.12, 0.10, 0.18)
	ps.corner_radius_top_left = 20; ps.corner_radius_top_right = 20
	ps.corner_radius_bottom_left = 20; ps.corner_radius_bottom_right = 20
	ps.border_width_left = 2; ps.border_width_right = 2
	ps.border_width_top = 2; ps.border_width_bottom = 2
	ps.border_color = Color(0.5, 0.4, 0.7)
	panel.add_theme_stylebox_override("panel", ps)
	panel.anchor_left = 0.0; panel.anchor_top = 0.0
	panel.anchor_right = 1.0; panel.anchor_bottom = 1.0
	panel.offset_left = Global.pw(0.08); panel.offset_top = Global.ph(0.22)
	panel.offset_right = Global.pw(-0.08); panel.offset_bottom = -Global.ph(0.22)
	overlay.add_child(panel)
	
	var title = Label.new()
	title.text = icon + " " + title_text
	title.add_theme_font_size_override("font_size", 55)
	title.add_theme_color_override("font_color", rarity_color)
	title.add_theme_color_override("font_shadow_color", Color("#000000"))
	title.add_theme_constant_override("shadow_offset_x", 2)
	title.add_theme_constant_override("shadow_offset_y", 2)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.anchor_left = 0.0; title.anchor_top = 0.0
	title.anchor_right = 1.0; title.anchor_bottom = 0.0
	title.offset_left = 0; title.offset_top = Global.ph(0.02)
	title.offset_right = 0; title.offset_bottom = Global.ph(0.08)
	panel.add_child(title)
	
	var sub = Label.new()
	sub.text = subtitle_text
	sub.add_theme_font_size_override("font_size", 36)
	sub.add_theme_color_override("font_color", Color("#a0a0b0"))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.anchor_left = 0.0; sub.anchor_top = 0.0
	sub.anchor_right = 1.0; sub.anchor_bottom = 0.0
	sub.offset_left = 0; sub.offset_top = Global.ph(0.075)
	sub.offset_right = 0; sub.offset_bottom = Global.ph(0.11)
	panel.add_child(sub)
	
	var line = ColorRect.new()
	line.color = Color(1.0, 1.0, 1.0, 0.15)
	line.anchor_left = 0.0; line.anchor_top = 0.0
	line.anchor_right = 1.0; line.anchor_bottom = 0.0
	line.offset_left = Global.pw(0.05); line.offset_top = Global.ph(0.115)
	line.offset_right = Global.pw(-0.05); line.offset_bottom = Global.ph(0.118)
	panel.add_child(line)
	
	var scroll = ScrollContainer.new()
	scroll.anchor_left = 0.0; scroll.anchor_top = 0.0
	scroll.anchor_right = 1.0; scroll.anchor_bottom = 1.0
	scroll.offset_left = Global.pw(0.03); scroll.offset_top = Global.ph(0.12)
	scroll.offset_right = Global.pw(-0.03); scroll.offset_bottom = -Global.ph(0.12)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	
	var info_vbox = VBoxContainer.new()
	info_vbox.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	info_vbox.custom_minimum_size = Vector2(Global.pw(0.70), 0)
	info_vbox.add_theme_constant_override("separation", 4)
	scroll.add_child(info_vbox)
	
	for pair in info_pairs:
		var key = pair[0]; var val = pair[1]
		var row_hbox = HBoxContainer.new()
		row_hbox.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
		row_hbox.custom_minimum_size = Vector2(0, Global.ph(0.045))
		info_vbox.add_child(row_hbox)
		
		var key_lbl = Label.new()
		key_lbl.text = key + "："
		key_lbl.add_theme_font_size_override("font_size", 38)
		key_lbl.add_theme_color_override("font_color", Color("#a0a0b0"))
		key_lbl.custom_minimum_size = Vector2(Global.pw(0.22), 0)
		row_hbox.add_child(key_lbl)
		
		var val_lbl = Label.new()
		val_lbl.text = val
		val_lbl.add_theme_font_size_override("font_size", 38)
		val_lbl.add_theme_color_override("font_color", Color("#e8d5b7"))
		val_lbl.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
		val_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row_hbox.add_child(val_lbl)
	
	var close_btn = Button.new()
	close_btn.text = "关闭"
	close_btn.add_theme_font_size_override("font_size", 45)
	var cs = StyleBoxFlat.new()
	cs.bg_color = Global.current.btn_bg
	cs.border_width_left = 2; cs.border_width_right = 2
	cs.border_width_top = 2; cs.border_width_bottom = 2
	cs.border_color = Color("#888888")
	cs.corner_radius_top_left = 12; cs.corner_radius_top_right = 12
	cs.corner_radius_bottom_left = 12; cs.corner_radius_bottom_right = 12
	cs.content_margin_left = 24; cs.content_margin_right = 24
	close_btn.add_theme_stylebox_override("normal", cs)
	close_btn.add_theme_color_override("font_color", Global.current.btn_text)
	close_btn.anchor_left = 0.0; close_btn.anchor_top = 1.0
	close_btn.anchor_right = 1.0; close_btn.anchor_bottom = 1.0
	close_btn.offset_left = Global.pw(0.25); close_btn.offset_top = -Global.ph(0.1)
	close_btn.offset_right = Global.pw(-0.25); close_btn.offset_bottom = -Global.ph(0.02)
	close_btn.pressed.connect(_close_detail.bind(overlay))
	panel.add_child(close_btn)


func _show_aux_detail(row: Control):
	var data = row.get_meta("row_data")
	if data == null:
		return
	
	var aid = data.get("id", "未知")
	var aname = data.get("name", "未知")
	var rarity = data.get("rarity", "普通")
	var desc = data.get("description", "")
	var atype = data.get("type", "")
	var effect = data.get("effect", {})
	
	var rarity_color = Color("#e8d5b7")
	match rarity:
		"传说": rarity_color = Color("#f9d371")
		"史诗": rarity_color = Color("#c084fc")
		"稀有": rarity_color = Color("#60a5fa")
	
	var type_name = ""
	match atype:
		"boost": type_name = " 属性增幅"
		"element": type_name = " 元素赋予"
		"protect": type_name = " 保护"
		"special": type_name = " 特殊效果"
		"poison": type_name = " 剧毒"
		"combo": type_name = " 连击"
	
	var overlay = ColorRect.new()
	overlay.name = "DetailOverlay"
	overlay.color = Color(0.0, 0.0, 0.0, 0.65)
	overlay.anchor_left = 0.0; overlay.anchor_top = 0.0
	overlay.anchor_right = 1.0; overlay.anchor_bottom = 1.0
	overlay.mouse_filter = MOUSE_FILTER_STOP
	overlay.gui_input.connect(_on_overlay_clicked.bind(overlay))
	add_child(overlay)
	
	var panel = Panel.new()
	panel.name = "DetailPanel"
	var ps = StyleBoxFlat.new()
	ps.bg_color = Color(0.12, 0.10, 0.18)
	ps.corner_radius_top_left = 20; ps.corner_radius_top_right = 20
	ps.corner_radius_bottom_left = 20; ps.corner_radius_bottom_right = 20
	ps.border_width_left = 2; ps.border_width_right = 2
	ps.border_width_top = 2; ps.border_width_bottom = 2
	ps.border_color = Color(0.5, 0.4, 0.7)
	panel.add_theme_stylebox_override("panel", ps)
	panel.anchor_left = 0.0; panel.anchor_top = 0.0
	panel.anchor_right = 0.0; panel.anchor_bottom = 0.0
	panel.offset_left = Global.pw(0.08); panel.offset_top = Global.ph(0.28)
	panel.offset_right = Global.pw(-0.08); panel.offset_bottom = Global.ph(0.72)
	overlay.add_child(panel)
	
	var vbox = VBoxContainer.new()
	vbox.anchor_left = 0.0; vbox.anchor_top = 0.0
	vbox.anchor_right = 1.0; vbox.anchor_bottom = 1.0
	vbox.offset_left = Global.pw(0.05); vbox.offset_top = Global.ph(0.03)
	vbox.offset_right = Global.pw(-0.05); vbox.offset_bottom = Global.ph(0.12)
	panel.add_child(vbox)
	
	var title = Label.new()
	title.text = aname
	title.add_theme_font_size_override("font_size", 55)
	title.add_theme_color_override("font_color", rarity_color)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	
	var id_label = Label.new()
	id_label.text = aid + "  ·  " + rarity + "  ·  " + type_name
	id_label.add_theme_font_size_override("font_size", 38)
	id_label.add_theme_color_override("font_color", Global.current.btn_text)
	id_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(id_label)
	
	var line = ColorRect.new()
	line.color = Color(1.0, 1.0, 1.0, 0.15)
	line.custom_minimum_size = Vector2(0, 2)
	line.size_flags_horizontal = SIZE_FILL
	vbox.add_child(line)
	
	var desc_label = Label.new()
	desc_label.text = desc
	desc_label.add_theme_font_size_override("font_size", 40)
	desc_label.add_theme_color_override("font_color", Color("#e8d5b7"))
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(desc_label)
	
	# 效果详情
	var effect_label = Label.new()
	var effect_text = "效果："
	for k in effect.keys():
		var v = effect[k]
		match k:
			"atk_bonus": effect_text += "攻击力+" + str(v)
			"hp_bonus": effect_text += "生命值+" + str(v)
			"damage_reduce": effect_text += "受到伤害-" + str(v)
			"damage_halve": effect_text += "伤害减半"
			"shield": effect_text += "护盾" + str(v) + "点"
			"element": effect_text += "赋予" + str(v) + "属性"
			"element_power": effect_text += "，效果强度+" + str(v * 100) + "%"
			"energy_reduce": effect_text += "能量消耗-" + str(v)
			"draw_on_summon": effect_text += "上场抽" + str(v) + "张牌"
			"haste": effect_text += "召唤当回合可攻击"
			"indestructible_once": effect_text += "免破坏（1次）"
			"field_sync": effect_text += "同字段在场时攻防各+" + str(v.get("atk", 0))
			"extra_trigger": effect_text += "额外触发" + str(v) + "次"
			_: effect_text += k + ":" + str(v)
	effect_label.text = effect_text
	effect_label.add_theme_font_size_override("font_size", 38)
	effect_label.add_theme_color_override("font_color", Color("#c084fc"))
	effect_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(effect_label)
	
	# 关闭按钮
	var close_btn = Button.new()
	close_btn.text = "关闭"
	close_btn.add_theme_font_size_override("font_size", 45)
	var cs = StyleBoxFlat.new()
	cs.bg_color = Global.current.btn_bg
	cs.border_width_left = 2; cs.border_width_right = 2
	cs.border_width_top = 2; cs.border_width_bottom = 2
	cs.border_color = Color("#888888")
	cs.corner_radius_top_left = 12; cs.corner_radius_top_right = 12
	cs.corner_radius_bottom_left = 12; cs.corner_radius_bottom_right = 12
	cs.content_margin_left = 24; cs.content_margin_right = 24
	close_btn.add_theme_stylebox_override("normal", cs)
	close_btn.add_theme_color_override("font_color", Global.current.btn_text)
	close_btn.size_flags_horizontal = SIZE_FILL
	close_btn.pressed.connect(_close_detail.bind(overlay))
	vbox.add_child(close_btn)


func _show_card_base_detail(row: Control):
	var data = row.get_meta("row_data")
	if data == null:
		return
	
	var cid = data.get("id", "未知")
	var quality = data.get("quality", "—")
	var load_cap = data.get("load_cap", 0)
	var slots = data.get("slots", 0)
	var durability = data.get("durability", 0)
	var tendency = data.get("tendency", {})
	var created_at = data.get("created_at", 0)
	
	var overlay = ColorRect.new()
	overlay.name = "DetailOverlay"
	overlay.color = Color(0.0, 0.0, 0.0, 0.6)
	overlay.anchor_left = 0.0
	overlay.anchor_top = 0.0
	overlay.anchor_right = 1.0
	overlay.anchor_bottom = 1.0
	overlay.mouse_filter = MOUSE_FILTER_STOP
	overlay.gui_input.connect(_on_overlay_clicked.bind(overlay))
	add_child(overlay)
	
	var panel = ColorRect.new()
	panel.name = "DetailPanel"
	panel.color = Global.current.bg
	panel.anchor_left = 0.0
	panel.anchor_top = 0.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 0.0
	panel.offset_left = Global.pw(0.05)
	panel.offset_top = Global.ph(0.2)
	panel.offset_right = Global.pw(-0.05)
	panel.offset_bottom = Global.ph(0.6)
	overlay.add_child(panel)
	
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color.TRANSPARENT
	panel_style.corner_radius_top_left = 20
	panel_style.corner_radius_top_right = 20
	panel_style.corner_radius_bottom_left = 20
	panel_style.corner_radius_bottom_right = 20
	panel.add_theme_stylebox_override("panel", panel_style)
	
	var title_label = Label.new()
	title_label.text = "" + WarehouseManager.get_card_base_display_name(data)
	title_label.add_theme_font_size_override("font_size", 60)
	title_label.add_theme_color_override("font_color", Global.current.title)
	title_label.add_theme_color_override("font_shadow_color", Global.current.title_shadow)
	title_label.add_theme_constant_override("shadow_offset_x", 2)
	title_label.add_theme_constant_override("shadow_offset_y", 2)
	title_label.anchor_left = 0.0
	title_label.anchor_top = 0.0
	title_label.anchor_right = 1.0
	title_label.anchor_bottom = 0.0
	title_label.offset_left = Global.pw(0.04)
	title_label.offset_top = Global.ph(0.015)
	title_label.offset_right = Global.pw(-0.04)
	title_label.offset_bottom = Global.ph(0.08)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(title_label)
	
	var id_label2 = Label.new()
	id_label2.text = "ID: " + cid
	id_label2.add_theme_font_size_override("font_size", 30)
	id_label2.add_theme_color_override("font_color", Global.current.btn_text)
	id_label2.anchor_left = 0.0
	id_label2.anchor_top = 0.0
	id_label2.anchor_right = 1.0
	id_label2.anchor_bottom = 0.0
	id_label2.offset_left = 0
	id_label2.offset_top = Global.ph(0.075)
	id_label2.offset_right = 0
	id_label2.offset_bottom = Global.ph(0.11)
	id_label2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(id_label2)
	
	var line = ColorRect.new()
	line.color = Global.current.topbar_border
	line.anchor_left = 0.0
	line.anchor_top = 0.0
	line.anchor_right = 1.0
	line.anchor_bottom = 0.0
	line.offset_left = Global.pw(0.05)
	line.offset_top = Global.ph(0.115)
	line.offset_right = Global.pw(-0.05)
	line.offset_bottom = Global.ph(0.12)
	panel.add_child(line)
	
	# 倾向文本
	var tendency_str := "无"
	if not tendency.is_empty():
		var parts := []
		for k in tendency.keys():
			parts.append(k + str(tendency[k]))
		tendency_str = " ".join(parts)
	
	var info_y := 0.13
	var info_labels := [
		["品质", str(quality)],
		["承载力", str(load_cap)],
		["卡槽", str(slots)],
		["耐久度", str(durability)],
		["倾向", tendency_str],
		["制作时间", Time.get_date_string_from_unix_time(created_at) if created_at > 0 else "未知"]
	]
	
	for info in info_labels:
		var key = info[0]
		var val = info[1]
		
		var key_label = Label.new()
		key_label.text = key + "："
		key_label.add_theme_font_size_override("font_size", 36)
		key_label.add_theme_color_override("font_color", Global.current.btn_text)
		key_label.anchor_left = 0.0
		key_label.anchor_top = 0.0
		key_label.anchor_right = 1.0
		key_label.anchor_bottom = 0.0
		key_label.offset_left = Global.pw(0.06)
		key_label.offset_top = Global.ph(info_y)
		key_label.offset_right = Global.pw(-0.5)
		key_label.offset_bottom = Global.ph(info_y + 0.04)
		panel.add_child(key_label)
		
		var val_label = Label.new()
		val_label.text = val
		val_label.add_theme_font_size_override("font_size", 36)
		val_label.add_theme_color_override("font_color", Global.current.title)
		val_label.anchor_left = 0.0
		val_label.anchor_top = 0.0
		val_label.anchor_right = 1.0
		val_label.anchor_bottom = 0.0
		val_label.offset_left = Global.pw(0.5)
		val_label.offset_top = Global.ph(info_y)
		val_label.offset_right = Global.pw(-0.06)
		val_label.offset_bottom = Global.ph(info_y + 0.04)
		val_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		panel.add_child(val_label)
		
		info_y += 0.045
	
	var close_btn = Button.new()
	close_btn.text = "关闭"
	close_btn.add_theme_font_size_override("font_size", 45)
	var cs = StyleBoxFlat.new()
	cs.bg_color = Global.current.btn_bg
	cs.border_width_left = 2
	cs.border_width_right = 2
	cs.border_width_top = 2
	cs.border_width_bottom = 2
	cs.border_color = Color("#888888")
	cs.corner_radius_top_left = 12
	cs.corner_radius_top_right = 12
	cs.corner_radius_bottom_left = 12
	cs.corner_radius_bottom_right = 12
	cs.content_margin_left = 24
	cs.content_margin_right = 24
	close_btn.add_theme_stylebox_override("normal", cs)
	close_btn.add_theme_color_override("font_color", Global.current.btn_text)
	close_btn.anchor_left = 0.0
	close_btn.anchor_top = 0.0
	close_btn.anchor_right = 1.0
	close_btn.anchor_bottom = 0.0
	close_btn.offset_left = Global.pw(0.25)
	close_btn.offset_top = Global.ph(0.45)
	close_btn.offset_right = Global.pw(-0.25)
	close_btn.offset_bottom = Global.ph(0.51)
	close_btn.pressed.connect(_close_detail.bind(overlay))
	panel.add_child(close_btn)


func _show_material_detail(row: Control) -> void:
	var row_data = row.get_meta("row_data")
	if row_data == null:
		return
	
	var mid: String = row_data.get("id", "")
	var mat_data := Global.get_material_by_id(mid)
	if mat_data.is_empty():
		return
	
	# 获取完整素材信息
	var name_str: String = mat_data.get("name", "未知")
	var rarity: String = mat_data.get("rarity", "普通")
	var area: String = mat_data.get("area", "未知")
	var tendency: String = mat_data.get("tendency", "无")
	if tendency == "":
		tendency = "无"
	
	var category: String = row_data.get("category", "未知")
	var count: int = row_data.get("count", 0)
	var rarity_color := _get_rarity_color(rarity)
	
	# 获取分类专属属性
	var props_text := ""
	match category:
		"纤维":
			var carry = mat_data.get("carry", 0)
			var tough = mat_data.get("toughness", 0)
			props_text = "承载力: " + str(carry) + "  韧性: " + str(tough)
		"矿粉":
			var stab = mat_data.get("stability", 0)
			var hard = mat_data.get("hardness", 0)
			props_text = "稳定性: " + str(stab) + "  硬度: " + str(hard)
		"树脂":
			var bond = mat_data.get("bond", 0)
			var gloss = mat_data.get("gloss", 0)
			props_text = "粘合度: " + str(bond) + "  光泽: " + str(gloss)
		"萃取液":
			var cond = mat_data.get("conductivity", 0)
			var pur = mat_data.get("purity", 0)
			props_text = "传导性: " + str(cond) + "  纯度: " + str(pur)
		"颜料":
			var adh = mat_data.get("adhesion", 0)
			var chr = mat_data.get("chromatography", 0)
			props_text = "附着力: " + str(adh) + "  显色: " + str(chr)
		"粘合剂":
			var har = mat_data.get("harmony", 0)
			props_text = "调和度: " + str(har)
	
	# ---- 弹窗控件 ----
	# 遮罩背景
	var overlay = ColorRect.new()
	overlay.name = "DetailOverlay"
	overlay.color = Color(0.0, 0.0, 0.0, 0.6)
	overlay.anchor_left = 0.0
	overlay.anchor_top = 0.0
	overlay.anchor_right = 1.0
	overlay.anchor_bottom = 1.0
	overlay.offset_left = 0
	overlay.offset_top = 0
	overlay.offset_right = 0
	overlay.offset_bottom = 0
	overlay.mouse_filter = MOUSE_FILTER_STOP
	overlay.gui_input.connect(_on_overlay_clicked.bind(overlay))
	add_child(overlay)
	
	# 弹窗面板
	var panel = ColorRect.new()
	panel.name = "DetailPanel"
	panel.color = Global.current.bg
	panel.anchor_left = 0.0
	panel.anchor_top = 0.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 0.0
	panel.offset_left = Global.pw(0.05)
	panel.offset_top = Global.ph(0.25)
	panel.offset_right = Global.pw(-0.05)
	panel.offset_bottom = Global.ph(0.65)
	overlay.add_child(panel)
	
	# 面板圆角（用StyleBoxFlat）
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color.TRANSPARENT
	panel_style.corner_radius_top_left = 20
	panel_style.corner_radius_top_right = 20
	panel_style.corner_radius_bottom_left = 20
	panel_style.corner_radius_bottom_right = 20
	panel.add_theme_stylebox_override("panel", panel_style)
	
	# 标题：素材名称
	var title_label = Label.new()
	title_label.text = name_str
	title_label.add_theme_font_size_override("font_size", 60)
	title_label.add_theme_color_override("font_color", rarity_color)
	title_label.add_theme_color_override("font_shadow_color", Global.current.title_shadow)
	title_label.add_theme_constant_override("shadow_offset_x", 2)
	title_label.add_theme_constant_override("shadow_offset_y", 2)
	title_label.anchor_left = 0.0
	title_label.anchor_top = 0.0
	title_label.anchor_right = 1.0
	title_label.anchor_bottom = 0.0
	title_label.offset_left = Global.pw(0.04)
	title_label.offset_top = Global.ph(0.015)
	title_label.offset_right = Global.pw(-0.04)
	title_label.offset_bottom = Global.ph(0.08)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(title_label)
	
	# 稀有度标签
	var rarity_label2 = Label.new()
	rarity_label2.text = rarity
	rarity_label2.add_theme_font_size_override("font_size", 40)
	rarity_label2.add_theme_color_override("font_color", rarity_color)
	rarity_label2.anchor_left = 0.0
	rarity_label2.anchor_top = 0.0
	rarity_label2.anchor_right = 1.0
	rarity_label2.anchor_bottom = 0.0
	rarity_label2.offset_left = 0
	rarity_label2.offset_top = Global.ph(0.075)
	rarity_label2.offset_right = 0
	rarity_label2.offset_bottom = Global.ph(0.12)
	rarity_label2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(rarity_label2)
	
	# 分割线
	var line = ColorRect.new()
	line.color = Global.current.topbar_border
	line.anchor_left = 0.0
	line.anchor_top = 0.0
	line.anchor_right = 1.0
	line.anchor_bottom = 0.0
	line.offset_left = Global.pw(0.05)
	line.offset_top = Global.ph(0.125)
	line.offset_right = Global.pw(-0.05)
	line.offset_bottom = Global.ph(0.13)
	panel.add_child(line)
	
	# 信息区域
	var info_y := 0.14
	var info_labels := [
		["类型", category],
		["采集区域", area],
		["数量", "x" + str(int(count))],
		["倾向", tendency],
		["属性", props_text]
	]
	
	for info in info_labels:
		var key = info[0]
		var val = info[1]
		
		var key_label = Label.new()
		key_label.text = key + "："
		key_label.add_theme_font_size_override("font_size", 36)
		key_label.add_theme_color_override("font_color", Global.current.btn_text)
		key_label.anchor_left = 0.0
		key_label.anchor_top = 0.0
		key_label.anchor_right = 1.0
		key_label.anchor_bottom = 0.0
		key_label.offset_left = Global.pw(0.06)
		key_label.offset_top = Global.ph(info_y)
		key_label.offset_right = Global.pw(-0.5)
		key_label.offset_bottom = Global.ph(info_y + 0.035)
		panel.add_child(key_label)
		
		var val_label = Label.new()
		val_label.text = val
		val_label.add_theme_font_size_override("font_size", 36)
		val_label.add_theme_color_override("font_color", Global.current.title)
		val_label.anchor_left = 0.0
		val_label.anchor_top = 0.0
		val_label.anchor_right = 1.0
		val_label.anchor_bottom = 0.0
		val_label.offset_left = Global.pw(0.5)
		val_label.offset_top = Global.ph(info_y)
		val_label.offset_right = Global.pw(-0.06)
		val_label.offset_bottom = Global.ph(info_y + 0.035)
		val_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		panel.add_child(val_label)
		
		info_y += 0.045
	
	# 关闭按钮
	var close_btn = Button.new()
	close_btn.text = "关闭"
	close_btn.add_theme_font_size_override("font_size", 45)
	
	var cs = StyleBoxFlat.new()
	cs.bg_color = Global.current.btn_bg
	cs.border_width_left = 2
	cs.border_width_right = 2
	cs.border_width_top = 2
	cs.border_width_bottom = 2
	cs.border_color = Color("#888888")
	cs.corner_radius_top_left = 12
	cs.corner_radius_top_right = 12
	cs.corner_radius_bottom_left = 12
	cs.corner_radius_bottom_right = 12
	cs.content_margin_left = 24
	cs.content_margin_right = 24
	close_btn.add_theme_stylebox_override("normal", cs)
	close_btn.add_theme_color_override("font_color", Global.current.btn_text)
	
	close_btn.anchor_left = 0.0
	close_btn.anchor_top = 0.0
	close_btn.anchor_right = 1.0
	close_btn.anchor_bottom = 0.0
	close_btn.offset_left = Global.pw(0.25)
	close_btn.offset_top = Global.ph(0.52)
	close_btn.offset_right = Global.pw(-0.25)
	close_btn.offset_bottom = Global.ph(0.58)
	close_btn.pressed.connect(_close_detail.bind(overlay))
	panel.add_child(close_btn)


func _on_overlay_clicked(event: InputEvent, overlay: ColorRect) -> void:
	if event is InputEventScreenTouch and not event.pressed:
		_close_detail(overlay)

func _close_detail(overlay: ColorRect) -> void:
	if overlay and is_instance_valid(overlay):
		overlay.queue_free()


func _on_theme_changed(_mode):
	var bg = get_node_or_null("Background")
	if bg: Global.apply_bg(bg)
	
	var topbar = get_node_or_null("TopBar")
	if topbar and topbar is ColorRect:
		topbar.color = Global.current.topbar_bg
	
	var topbar_line = get_node_or_null("TopBarLine")
	if topbar_line and topbar_line is ColorRect:
		topbar_line.color = Global.current.topbar_border
	
	var bottom_bar = get_node_or_null("BottomBar")
	if bottom_bar and bottom_bar is ColorRect:
		bottom_bar.color = Global.current.topbar_bg
	
	var bottom_bar_line = get_node_or_null("BottomBarLine")
	if bottom_bar_line and bottom_bar_line is ColorRect:
		bottom_bar_line.color = Global.current.topbar_border
	
	var title = get_node_or_null("Title")
	if title and title is Label:
		title.add_theme_color_override("font_color", Global.current.title)
		title.add_theme_color_override("font_shadow_color", Global.current.title_shadow)
		title.add_theme_constant_override("shadow_offset_x", Global.current.shadow_offset)
		title.add_theme_constant_override("shadow_offset_y", Global.current.shadow_offset)
	
	# 分类按钮
	var cat_btn = get_node_or_null("CategoryBtn")
	if cat_btn and cat_btn is Button:
		cat_btn.add_theme_color_override("font_color", Global.current.title)
		cat_btn.add_theme_color_override("font_hover_color", Global.current.title)
		for state in ["normal", "hover", "pressed", "focus"]:
			var sb = cat_btn.get_theme_stylebox(state)
			if sb and sb is StyleBoxFlat:
				if state == "normal":
					sb.bg_color = Global.current.btn_bg
				elif state == "hover":
					sb.bg_color = Global.current.btn_bg_hover
				elif state == "pressed":
					sb.bg_color = Global.current.btn_bg_pressed
				cat_btn.add_theme_stylebox_override(state, sb)
	
	for child in get_children():
		if child is Button:
			child.add_theme_color_override("font_color", Global.current.btn_text)
			child.add_theme_color_override("font_hover_color", Global.current.btn_text_hover)
			for state in ["normal", "hover", "pressed", "focus"]:
				var sb = child.get_theme_stylebox(state)
				if sb and sb is StyleBoxFlat:
					if state == "normal":
						sb.bg_color = Global.current.btn_bg
					elif state == "hover":
						sb.bg_color = Global.current.btn_bg_hover
					elif state == "pressed":
						sb.bg_color = Global.current.btn_bg_pressed
					child.add_theme_stylebox_override(state, sb)
	
	# 刷新列表
	_refresh_list()


func _on_filter():
	_show_filter_popup()

# ===== 筛选弹窗 =====

func _show_filter_popup() -> void:
	# 遮罩
	var overlay = ColorRect.new()
	overlay.name = "FilterOverlay"
	overlay.color = Color(0.0, 0.0, 0.0, 0.6)
	overlay.anchor_left = 0.0
	overlay.anchor_top = 0.0
	overlay.anchor_right = 1.0
	overlay.anchor_bottom = 1.0
	overlay.offset_left = 0
	overlay.offset_top = 0
	overlay.offset_right = 0
	overlay.offset_bottom = 0
	overlay.mouse_filter = MOUSE_FILTER_STOP
	overlay.gui_input.connect(_on_filter_overlay_clicked.bind(overlay))
	add_child(overlay)
	
	# 弹窗面板
	var panel = ColorRect.new()
	panel.name = "FilterPanel"
	panel.color = Global.current.bg
	panel.anchor_left = 0.0
	panel.anchor_top = 0.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 0.0
	panel.offset_left = Global.pw(0.05)
	panel.offset_top = Global.ph(0.2)
	panel.offset_right = Global.pw(-0.05)
	panel.offset_bottom = Global.ph(0.80)
	overlay.add_child(panel)
	
	# 面板圆角
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color.TRANSPARENT
	panel_style.corner_radius_top_left = 20
	panel_style.corner_radius_top_right = 20
	panel_style.corner_radius_bottom_left = 20
	panel_style.corner_radius_bottom_right = 20
	panel.add_theme_stylebox_override("panel", panel_style)
	
	# 标题
	var title_label = Label.new()
	title_label.text = "筛选素材"
	title_label.add_theme_font_size_override("font_size", 60)
	title_label.add_theme_color_override("font_color", Global.current.title)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.anchor_left = 0.0
	title_label.anchor_top = 0.0
	title_label.anchor_right = 1.0
	title_label.anchor_bottom = 0.0
	title_label.offset_left = 0
	title_label.offset_top = Global.ph(0.02)
	title_label.offset_right = 0
	title_label.offset_bottom = Global.ph(0.08)
	panel.add_child(title_label)
	
	# ---- 分类选择 ----
	var cat_title = Label.new()
	cat_title.text = "素材分类"
	cat_title.add_theme_font_size_override("font_size", 40)
	cat_title.add_theme_color_override("font_color", Global.current.btn_text)
	cat_title.anchor_left = 0.0
	cat_title.anchor_top = 0.0
	cat_title.anchor_right = 1.0
	cat_title.anchor_bottom = 0.0
	cat_title.offset_left = Global.pw(0.05)
	cat_title.offset_top = Global.ph(0.09)
	cat_title.offset_right = Global.pw(-0.05)
	cat_title.offset_bottom = Global.ph(0.13)
	panel.add_child(cat_title)
	
	# 分类按钮行（两行：第一行4个，第二行3个）
	var cat_btns := ["全部", "纤维", "矿粉", "树脂", "萃取液", "颜料", "粘合剂"]
	var cat_start_x := 0.05
	var cat_btn_w := 0.20
	var cat_gap := 0.02
	for i in range(cat_btns.size()):
		var btn = Button.new()
		btn.text = cat_btns[i]
		btn.add_theme_font_size_override("font_size", 36)
		var bs = StyleBoxFlat.new()
		bs.bg_color = Global.current.btn_bg
		bs.corner_radius_top_left = 10
		bs.corner_radius_top_right = 10
		bs.corner_radius_bottom_left = 10
		bs.corner_radius_bottom_right = 10
		bs.content_margin_left = 8
		bs.content_margin_right = 8
		btn.add_theme_stylebox_override("normal", bs)
		btn.add_theme_color_override("font_color", Global.current.btn_text)
		
		# 高亮当前选中
		var is_selected = (_filter_category == "" and i == 0) or (_filter_category == cat_btns[i] and i > 0)
		if is_selected:
			bs.bg_color = Global.current.btn_bg_hover
		
		var cat_val = "" if i == 0 else cat_btns[i]
		btn.pressed.connect(_on_filter_cat_selected.bind(cat_val, overlay))
		
		# 第一行：索引0~3（全部、纤维、矿粉、树脂）
		# 第二行：索引4~6（萃取液、颜料、粘合剂）
		var row = 0 if i < 4 else 1
		var col = i if row == 0 else i - 4
		btn.anchor_left = 0.0
		btn.anchor_top = 0.0
		btn.anchor_right = 0.0
		btn.anchor_bottom = 0.0
		btn.offset_left = Global.pw(cat_start_x + col * (cat_btn_w + cat_gap))
		btn.offset_top = Global.ph(0.14 + row * 0.06)
		btn.offset_right = Global.pw(cat_start_x + col * (cat_btn_w + cat_gap) + cat_btn_w)
		btn.offset_bottom = Global.ph(0.19 + row * 0.06)
		panel.add_child(btn)
	
	# ---- 品质选择 ----
	var rarity_title = Label.new()
	rarity_title.text = "品质"
	rarity_title.add_theme_font_size_override("font_size", 40)
	rarity_title.add_theme_color_override("font_color", Global.current.btn_text)
	rarity_title.anchor_left = 0.0
	rarity_title.anchor_top = 0.0
	rarity_title.anchor_right = 1.0
	rarity_title.anchor_bottom = 0.0
	rarity_title.offset_left = Global.pw(0.05)
	rarity_title.offset_top = Global.ph(0.27)
	rarity_title.offset_right = Global.pw(-0.05)
	rarity_title.offset_bottom = Global.ph(0.31)
	panel.add_child(rarity_title)
	
	# 品质按钮（分两行）
	var rarity_btns := ["全部", "普通", "稀有", "史诗", "传说"]
	var rarity_colors := [
		Global.current.btn_text,
		Color("#60a5fa"),
		Color("#c084fc"),
		Color("#f9d371")
	]
	# 第一行：全部 + 普通 + 稀有
	var row1_btns := ["全部", "普通", "稀有"]
	var row1_start_x := 0.05
	var row1_btn_w := 0.25
	var row1_gap := 0.03
	for i in range(row1_btns.size()):
		var btn = Button.new()
		btn.text = row1_btns[i]
		btn.add_theme_font_size_override("font_size", 34)
		var bs = StyleBoxFlat.new()
		bs.bg_color = Global.current.btn_bg
		bs.corner_radius_top_left = 10
		bs.corner_radius_top_right = 10
		bs.corner_radius_bottom_left = 10
		bs.corner_radius_bottom_right = 10
		bs.content_margin_left = 6
		bs.content_margin_right = 6
		btn.add_theme_stylebox_override("normal", bs)
		
		# 品质文字颜色
		var btn_idx = rarity_btns.find(row1_btns[i])
		if btn_idx > 0:
			btn.add_theme_color_override("font_color", rarity_colors[btn_idx - 1])
		else:
			btn.add_theme_color_override("font_color", Global.current.btn_text)
		
		# 高亮当前选中
		var is_selected = (_filter_rarity == "" and row1_btns[i] == "全部") or (_filter_rarity == row1_btns[i] and row1_btns[i] != "全部")
		if is_selected:
			bs.bg_color = Global.current.btn_bg_hover
		
		var rarity_val = "" if row1_btns[i] == "全部" else row1_btns[i]
		btn.pressed.connect(_on_filter_rarity_selected.bind(rarity_val, overlay))
		
		btn.anchor_left = 0.0
		btn.anchor_top = 0.0
		btn.anchor_right = 0.0
		btn.anchor_bottom = 0.0
		btn.offset_left = Global.pw(row1_start_x + i * (row1_btn_w + row1_gap))
		btn.offset_top = Global.ph(0.33)
		btn.offset_right = Global.pw(row1_start_x + i * (row1_btn_w + row1_gap) + row1_btn_w)
		btn.offset_bottom = Global.ph(0.38)
		panel.add_child(btn)
	
	# 第二行：史诗 + 传说
	var row2_btns := ["史诗", "传说"]
	var row2_start_x := 0.15
	var row2_btn_w := 0.30
	var row2_gap := 0.05
	for i in range(row2_btns.size()):
		var btn = Button.new()
		btn.text = row2_btns[i]
		btn.add_theme_font_size_override("font_size", 34)
		var bs = StyleBoxFlat.new()
		bs.bg_color = Global.current.btn_bg
		bs.corner_radius_top_left = 10
		bs.corner_radius_top_right = 10
		bs.corner_radius_bottom_left = 10
		bs.corner_radius_bottom_right = 10
		bs.content_margin_left = 6
		bs.content_margin_right = 6
		btn.add_theme_stylebox_override("normal", bs)
		
		var btn_idx = rarity_btns.find(row2_btns[i])
		btn.add_theme_color_override("font_color", rarity_colors[btn_idx - 1])
		
		var is_selected = _filter_rarity == row2_btns[i]
		if is_selected:
			bs.bg_color = Global.current.btn_bg_hover
		
		btn.pressed.connect(_on_filter_rarity_selected.bind(row2_btns[i], overlay))
		
		btn.anchor_left = 0.0
		btn.anchor_top = 0.0
		btn.anchor_right = 0.0
		btn.anchor_bottom = 0.0
		btn.offset_left = Global.pw(row2_start_x + i * (row2_btn_w + row2_gap))
		btn.offset_top = Global.ph(0.39)
		btn.offset_right = Global.pw(row2_start_x + i * (row2_btn_w + row2_gap) + row2_btn_w)
		btn.offset_bottom = Global.ph(0.44)
		panel.add_child(btn)
	
	# 当前筛选状态提示
	var status_label = Label.new()
	var status_text = "当前："
	if _filter_category == "" and _filter_rarity == "":
		status_text += "显示全部"
	else:
		if _filter_category != "":
			status_text += _filter_category + " "
		if _filter_rarity != "":
			status_text += _filter_rarity
	status_label.text = status_text
	status_label.add_theme_font_size_override("font_size", 36)
	status_label.add_theme_color_override("font_color", Global.current.title)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.anchor_left = 0.0
	status_label.anchor_top = 0.0
	status_label.anchor_right = 1.0
	status_label.anchor_bottom = 0.0
	status_label.offset_left = 0
	status_label.offset_top = Global.ph(0.46)
	status_label.offset_right = 0
	status_label.offset_bottom = Global.ph(0.50)
	panel.add_child(status_label)
	
	# 关闭按钮
	var close_btn = Button.new()
	close_btn.text = "关闭"
	close_btn.add_theme_font_size_override("font_size", 45)
	var cs = StyleBoxFlat.new()
	cs.bg_color = Global.current.btn_bg
	cs.border_width_left = 2
	cs.border_width_right = 2
	cs.border_width_top = 2
	cs.border_width_bottom = 2
	cs.border_color = Color("#888888")
	cs.corner_radius_top_left = 12
	cs.corner_radius_top_right = 12
	cs.corner_radius_bottom_left = 12
	cs.corner_radius_bottom_right = 12
	cs.content_margin_left = 24
	cs.content_margin_right = 24
	close_btn.add_theme_stylebox_override("normal", cs)
	close_btn.add_theme_color_override("font_color", Global.current.btn_text)
	close_btn.anchor_left = 0.0
	close_btn.anchor_top = 0.0
	close_btn.anchor_right = 1.0
	close_btn.anchor_bottom = 0.0
	close_btn.offset_left = Global.pw(0.25)
	close_btn.offset_top = Global.ph(0.52)
	close_btn.offset_right = Global.pw(-0.25)
	close_btn.offset_bottom = Global.ph(0.58)
	close_btn.pressed.connect(_close_filter.bind(overlay))
	panel.add_child(close_btn)


func _on_filter_cat_selected(cat_val: String, overlay: ColorRect) -> void:
	_filter_category = cat_val
	_refresh_material_list()
	_close_filter(overlay)

func _on_filter_rarity_selected(rarity_val: String, overlay: ColorRect) -> void:
	_filter_rarity = rarity_val
	_refresh_material_list()
	_close_filter(overlay)

func _on_filter_overlay_clicked(event: InputEvent, overlay: ColorRect) -> void:
	if event is InputEventScreenTouch and not event.pressed:
		_close_filter(overlay)

func _close_filter(overlay: ColorRect) -> void:
	if overlay and is_instance_valid(overlay):
		overlay.queue_free()


func _on_back():
	Global.play_sfx("click")
	Global.change_scene("res://CardWorkshop.tscn")

func _apply_theme_styles():
	var bg = get_node_or_null("Background")
	Global.apply_bg(bg)
	for n in ["TopBar","BottomBar"]:
		var r = get_node_or_null(n)
		if r is ColorRect: r.color = Global.current.topbar_bg
	for n in ["TopBarLine","BottomBarLine"]:
		var r = get_node_or_null(n)
		if r is ColorRect: r.color = Global.current.topbar_border
	var title = get_node_or_null("Title")
	if title is Label:
		title.add_theme_color_override("font_color", Global.current.title)
		title.add_theme_color_override("font_shadow_color", Global.current.title_shadow)
		title.add_theme_constant_override("shadow_offset_x", Global.current.shadow_offset)
		title.add_theme_constant_override("shadow_offset_y", Global.current.shadow_offset)
	var back = get_node_or_null("BackBtn")
	if back is Button:
		back.add_theme_color_override("font_color", Global.current.btn_text)
		var s = StyleBoxFlat.new()
		s.bg_color = Global.current.btn_bg
		s.border_width_left = 2; s.border_width_right = 2; s.border_width_top = 2; s.border_width_bottom = 2
		s.border_color = Color("#888888")
		s.corner_radius_top_left = 10; s.corner_radius_top_right = 10
		s.corner_radius_bottom_left = 10; s.corner_radius_bottom_right = 10
		back.add_theme_stylebox_override("normal", s)
func _build_dynamic_content():
	_refresh_list()
