extends ThemedControl

const QRCode = preload("res://assets/share/QRCode.gd")

# 长按弹窗
var _press_timer: float = 0.0
var _pressed_row = null
var _press_start_pos: Vector2 = Vector2.ZERO
var _press_index: int = -1
const LONG_PRESS_TIME := 0.5
const DRAG_THRESHOLD := 30.0

# 筛选/排序/搜索状态
var _filter_quality: String = "all"
var _sort_field: String = "cost"
var _sort_asc: bool = true
var _search_text: String = ""
var _search_input: LineEdit = null

func _ready():
	super._ready()
	# ---- 静态节点已在 CardGallery.tscn 中声明 ----
	var back := get_node_or_null("BackBtn")
	if back is Button: back.pressed.connect(_on_back)
	var help := get_node_or_null("HelpBtn")
	if help is Button: help.pressed.connect(_on_help)
	var filter_btn := get_node_or_null("FilterBtn")
	if filter_btn is Button: filter_btn.pressed.connect(_show_filter_popup)
	# 动态内容构建
	call_deferred("_build_dynamic_content")

func _refresh_list():
	var vbox = get_node_or_null("CardScroll/CardList")
	if not vbox:
		return
	
	for child in vbox.get_children():
		vbox.remove_child(child)
		child.queue_free()
	
	var all_cards = CardManager.get_all_cards()
	all_cards.reverse()
	var cards = _get_filtered_sorted_cards(all_cards)
	
	# 更新统计
	var stats_label = get_node_or_null("StatsLabel")
	if stats_label:
		stats_label.text = "共 " + str(cards.size()) + " / " + str(all_cards.size()) + " 张卡牌"
	
	if cards.size() == 0:
		var empty = Label.new()
		if all_cards.size() == 0:
			empty.text = "还没有卡牌，去刻画一些吧！"
		else:
			empty.text = "没有匹配的卡牌"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_font_size_override("font_size", 50)
		empty.add_theme_color_override("font_color", Color("#5a5a6e"))
		empty.custom_minimum_size = Vector2(0, Global.ph(0.1))
		vbox.add_child(empty)
		return
	
	var row_index := 0
	for card in cards:
		var card_name = card.get("name", card.get("card_name", "未命名卡牌"))
		var attack = card.get("atk", card.get("attack", 0))
		var health = card.get("hp", card.get("health", 0))
		var energy_cost = card.get("cost", card.get("energy_cost", 0))
		var quality = card.get("quality", "—")
		var main_element = CardManager.get_card_element(card)
		var fields = card.get("fields", [])
		
		var row_panel = Panel.new()
		row_panel.name = "RowPanel"
		var panel_style = StyleBoxFlat.new()
		panel_style.bg_color = _get_row_bg_color(row_index)
		row_panel.add_theme_stylebox_override("panel", panel_style)
		row_panel.custom_minimum_size = Vector2(0, Global.ph(0.095))
		row_panel.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
		row_panel.mouse_filter = MOUSE_FILTER_PASS
		row_panel.set_meta("row_index", row_index)
		row_panel.set_meta("card_data", card)
		
		# 行底部分隔线
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
		
		# 内嵌 HBox
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
		
		# 左侧：卡名 + 字段
		var left_vbox = VBoxContainer.new()
		left_vbox.size_flags_horizontal = SIZE_EXPAND
		left_vbox.add_theme_constant_override("separation", 0)
		hbox.add_child(left_vbox)
		
		var name_label = Label.new()
		var elem_icon = Global.get_element_emoji(main_element)
		name_label.text = elem_icon + " " + card_name
		name_label.add_theme_font_size_override("font_size", 50)
		name_label.add_theme_color_override("font_color", Global.current.title)
		left_vbox.add_child(name_label)
		
		# 字段信息
		var field_str := ""
		for f in fields:
			if f != "":
				field_str += "[" + f + "] "
		if field_str != "":
			var field_label = Label.new()
			field_label.text = field_str
			field_label.add_theme_font_size_override("font_size", 40)
			field_label.add_theme_color_override("font_color", Global.current.btn_text)
			left_vbox.add_child(field_label)
		
		# 右侧：攻防 + 费用
		var attrs_label = Label.new()
		attrs_label.text = "⚔" + str(attack) + " ❤" + str(health) + " ⚡" + str(energy_cost)
		attrs_label.add_theme_font_size_override("font_size", 50)
		attrs_label.add_theme_color_override("font_color", Global.current.btn_text)
		attrs_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		attrs_label.custom_minimum_size = Vector2(Global.pw(0.35), 0)
		attrs_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hbox.add_child(attrs_label)
		
		# 品质标签
		var quality_label = Label.new()
		var display_quality = quality
		if " ~ " in quality:
			var q_parts = quality.split(" ~ ")
			display_quality = q_parts[q_parts.size() - 1].strip_edges()
		quality_label.text = display_quality
		quality_label.add_theme_font_size_override("font_size", 40)
		quality_label.add_theme_color_override("font_color", _get_quality_color(display_quality))
		quality_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		quality_label.custom_minimum_size = Vector2(Global.pw(0.12), 0)
		quality_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		hbox.add_child(quality_label)
		
		vbox.add_child(row_panel)
		row_index += 1
	
	# 底部留白
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, Global.ph(0.05))
	vbox.add_child(spacer)


func _get_row_bg_color(row_index: int) -> Color:
	if row_index % 2 == 0:
		return Global.current.topbar_bg
	else:
		return Color.TRANSPARENT


func _get_quality_color(quality: String) -> Color:
	return Global.get_quality_color(quality)


func _get_quality_rank(quality: String) -> int:
	return Global.get_quality_rank(quality)

func _get_filtered_sorted_cards(cards: Array) -> Array:
	var result = []
	for card in cards:
		if _filter_quality != "all":
			var q = card.get("quality", "")
			var rank = _get_quality_rank(q)
			match _filter_quality:
				"perfect":
					if rank < 5: continue
				"excellent":
					if rank < 4: continue
				"fine":
					if rank < 3: continue
				"normal":
					if rank > 2: continue
		if _search_text != "":
			var name_str = card.get("name", card.get("card_name", "")).to_lower()
			var desc_str = card.get("description", card.get("desc", "")).to_lower()
			if not _search_text.to_lower() in name_str and not _search_text.to_lower() in desc_str:
				continue
		result.append(card)
	result.sort_custom(func(a, b):
		var val_a
		var val_b
		if _sort_field == "cost":
			val_a = a.get("cost", a.get("energy_cost", 0))
			val_b = b.get("cost", b.get("energy_cost", 0))
		else:
			val_a = _get_quality_rank(a.get("quality", ""))
			val_b = _get_quality_rank(b.get("quality", ""))
		if _sort_asc:
			return val_a < val_b
		else:
			return val_a > val_b
	)
	return result

func _show_filter_popup():
	Global.play_sfx("click")
	_close_filter_popup()
	var overlay = ColorRect.new()
	overlay.name = "FilterOverlay"
	overlay.color = Color(0, 0, 0, 0.6)
	overlay.anchor_left = 0.0; overlay.anchor_top = 0.0
	overlay.anchor_right = 1.0; overlay.anchor_bottom = 1.0
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	var panel = Panel.new()
	panel.name = "FilterPanel"
	panel.anchor_left = 0.0; panel.anchor_top = 0.0
	panel.anchor_right = 1.0; panel.anchor_bottom = 1.0
	panel.offset_left = Global.pw(0.08); panel.offset_right = Global.pw(-0.08)
	panel.offset_top = Global.ph(0.15); panel.offset_bottom = Global.ph(-0.15)
	var ps = StyleBoxFlat.new()
	ps.bg_color = Global.current.bg
	ps.border_width_left = 3; ps.border_width_right = 3
	ps.border_width_top = 3; ps.border_width_bottom = 3
	ps.border_color = Color("#e8a838")
	ps.corner_radius_top_left = 16; ps.corner_radius_top_right = 16
	ps.corner_radius_bottom_left = 16; ps.corner_radius_bottom_right = 16
	panel.add_theme_stylebox_override("panel", ps)
	add_child(panel)
	_build_filter_popup_content(panel)

func _close_filter_popup():
	for c in get_children():
		if c.name == "FilterOverlay" or c.name == "FilterPanel":
			remove_child(c)
			c.queue_free()

func _build_filter_popup_content(panel: Panel):
	for c in panel.get_children():
		panel.remove_child(c)
		c.queue_free()
	var vbox = VBoxContainer.new()
	vbox.name = "FilterVBox"
	vbox.anchor_left = 0.0; vbox.anchor_top = 0.0
	vbox.anchor_right = 1.0; vbox.anchor_bottom = 1.0
	vbox.offset_left = Global.pw(0.04); vbox.offset_right = Global.pw(-0.04)
	vbox.offset_top = Global.ph(0.02); vbox.offset_bottom = Global.ph(-0.02)
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)
	var title = Label.new()
	title.text = "筛选卡牌"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 50)
	title.add_theme_color_override("font_color", Global.current.title)
	vbox.add_child(title)
	# 搜索输入框
	_search_input = LineEdit.new()
	_search_input.name = "PopupSearchInput"
	_search_input.placeholder_text = "搜索名称或描述..."
	_search_input.add_theme_font_size_override("font_size", 42)
	_search_input.custom_minimum_size = Vector2(0, Global.ph(0.08))
	_search_input.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	_search_input.text = _search_text
	vbox.add_child(_search_input)
	# 搜索操作按钮行
	var search_btn_hbox = HBoxContainer.new()
	search_btn_hbox.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	search_btn_hbox.custom_minimum_size = Vector2(0, Global.ph(0.08))
	search_btn_hbox.add_theme_constant_override("separation", 8)
	vbox.add_child(search_btn_hbox)
	var search_btn = Button.new()
	search_btn.text = "🔍 搜索"
	search_btn.add_theme_font_size_override("font_size", 42)
	var sbs = StyleBoxFlat.new()
	sbs.bg_color = Global.current.btn_bg
	sbs.border_width_left = 2; sbs.border_width_right = 2
	sbs.border_width_top = 2; sbs.border_width_bottom = 2
	sbs.border_color = Color("#e8a838")
	sbs.corner_radius_top_left = 10; sbs.corner_radius_top_right = 10
	sbs.corner_radius_bottom_left = 10; sbs.corner_radius_bottom_right = 10
	sbs.content_margin_left = 12; sbs.content_margin_right = 12
	search_btn.add_theme_stylebox_override("normal", sbs)
	search_btn.add_theme_color_override("font_color", Global.current.btn_text)
	search_btn.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	search_btn.pressed.connect(func():
		_search_text = _search_input.text.strip_edges()
		_refresh_list()
		_build_filter_popup_content(panel)
	)
	search_btn_hbox.add_child(search_btn)
	var clear_btn = Button.new()
	clear_btn.text = "✕ 清除"
	clear_btn.add_theme_font_size_override("font_size", 42)
	var cbs = StyleBoxFlat.new()
	cbs.bg_color = Color("#553333")
	cbs.border_width_left = 2; cbs.border_width_right = 2
	cbs.border_width_top = 2; cbs.border_width_bottom = 2
	cbs.border_color = Color("#e74c3c")
	cbs.corner_radius_top_left = 10; cbs.corner_radius_top_right = 10
	cbs.corner_radius_bottom_left = 10; cbs.corner_radius_bottom_right = 10
	cbs.content_margin_left = 12; cbs.content_margin_right = 12
	clear_btn.add_theme_stylebox_override("normal", cbs)
	clear_btn.add_theme_color_override("font_color", Color("#e74c3c"))
	clear_btn.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	clear_btn.pressed.connect(func():
		_search_text = ""
		_search_input.text = ""
		_refresh_list()
		_build_filter_popup_content(panel)
	)
	search_btn_hbox.add_child(clear_btn)
	# 品质筛选
	var q_label = Label.new()
	q_label.text = "品质筛选"
	q_label.add_theme_font_size_override("font_size", 36)
	q_label.add_theme_color_override("font_color", Color("#aaaaaa"))
	vbox.add_child(q_label)
	var filter_hbox = HBoxContainer.new()
	filter_hbox.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	filter_hbox.custom_minimum_size = Vector2(0, Global.ph(0.08))
	filter_hbox.add_theme_constant_override("separation", 6)
	vbox.add_child(filter_hbox)
	var quality_options = [
		{"key": "all", "label": "全部", "color": Color("#aaaaaa")},
		{"key": "perfect", "label": "完美", "color": Color("#f9d371")},
		{"key": "excellent", "label": "卓越", "color": Color("#c084fc")},
		{"key": "fine", "label": "精良", "color": Color("#60a5fa")},
		{"key": "normal", "label": "标准以下", "color": Color("#888888")},
	]
	for opt in quality_options:
		var q_btn = Button.new()
		q_btn.text = opt.label
		q_btn.add_theme_font_size_override("font_size", 38)
		var is_active = (_filter_quality == opt.key)
		var qbs = StyleBoxFlat.new()
		qbs.bg_color = Color("#3a3a4e") if is_active else Color("#222233")
		qbs.border_width_left = 2; qbs.border_width_right = 2
		qbs.border_width_top = 2; qbs.border_width_bottom = 2
		qbs.border_color = opt.color if is_active else Color("#444455")
		qbs.corner_radius_top_left = 8; qbs.corner_radius_top_right = 8
		qbs.corner_radius_bottom_left = 8; qbs.corner_radius_bottom_right = 8
		qbs.content_margin_left = 10; qbs.content_margin_right = 10
		q_btn.add_theme_stylebox_override("normal", qbs)
		q_btn.add_theme_color_override("font_color", opt.color if is_active else Color("#888888"))
		q_btn.custom_minimum_size = Vector2(0, Global.ph(0.07))
		q_btn.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
		var q_key = opt.key
		q_btn.pressed.connect(func():
			_search_text = _search_input.text.strip_edges()
			_filter_quality = q_key
			_refresh_list()
			_build_filter_popup_content(panel)
		)
		filter_hbox.add_child(q_btn)
	# 排序
	var s_label = Label.new()
	s_label.text = "排序"
	s_label.add_theme_font_size_override("font_size", 36)
	s_label.add_theme_color_override("font_color", Color("#aaaaaa"))
	vbox.add_child(s_label)
	var sort_hbox = HBoxContainer.new()
	sort_hbox.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	sort_hbox.custom_minimum_size = Vector2(0, Global.ph(0.08))
	sort_hbox.add_theme_constant_override("separation", 8)
	vbox.add_child(sort_hbox)
	var sort_options = [
		{"key": "cost", "label": "⚡能量"},
		{"key": "quality", "label": "⭐品质"},
	]
	for opt in sort_options:
		var so_btn = Button.new()
		so_btn.text = opt.label
		so_btn.add_theme_font_size_override("font_size", 38)
		var is_active = (_sort_field == opt.key)
		var sobs = StyleBoxFlat.new()
		sobs.bg_color = Color("#3a3a4e") if is_active else Color("#222233")
		sobs.border_width_left = 2; sobs.border_width_right = 2
		sobs.border_width_top = 2; sobs.border_width_bottom = 2
		sobs.border_color = Color("#e8a838") if is_active else Color("#444455")
		sobs.corner_radius_top_left = 8; sobs.corner_radius_top_right = 8
		sobs.corner_radius_bottom_left = 8; sobs.corner_radius_bottom_right = 8
		sobs.content_margin_left = 10; sobs.content_margin_right = 10
		so_btn.add_theme_stylebox_override("normal", sobs)
		so_btn.add_theme_color_override("font_color", Color("#e8a838") if is_active else Color("#888888"))
		so_btn.custom_minimum_size = Vector2(0, Global.ph(0.07))
		so_btn.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
		var s_key = opt.key
		so_btn.pressed.connect(func():
			_search_text = _search_input.text.strip_edges()
			if _sort_field == s_key:
				_sort_asc = not _sort_asc
			else:
				_sort_field = s_key
				_sort_asc = true
			_refresh_list()
			_build_filter_popup_content(panel)
		)
		sort_hbox.add_child(so_btn)
	var order_label = Label.new()
	order_label.text = "↑升序" if _sort_asc else "↓降序"
	order_label.add_theme_font_size_override("font_size", 38)
	order_label.add_theme_color_override("font_color", Color("#e8a838"))
	order_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sort_hbox.add_child(order_label)
	# 间隔
	var spacer = ColorRect.new()
	spacer.color = Color.TRANSPARENT
	spacer.custom_minimum_size = Vector2(0, Global.ph(0.02))
	vbox.add_child(spacer)
	# 底部按钮行
	var btn_hbox = HBoxContainer.new()
	btn_hbox.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	btn_hbox.custom_minimum_size = Vector2(0, Global.ph(0.10))
	btn_hbox.add_theme_constant_override("separation", 8)
	vbox.add_child(btn_hbox)
	# 重置按钮
	var reset_btn = Button.new()
	reset_btn.text = "↻ 重置"
	reset_btn.add_theme_font_size_override("font_size", 42)
	var rbs = StyleBoxFlat.new()
	rbs.bg_color = Color("#553333")
	rbs.border_width_left = 2; rbs.border_width_right = 2
	rbs.border_width_top = 2; rbs.border_width_bottom = 2
	rbs.border_color = Color("#e74c3c")
	rbs.corner_radius_top_left = 10; rbs.corner_radius_top_right = 10
	rbs.corner_radius_bottom_left = 10; rbs.corner_radius_bottom_right = 10
	rbs.content_margin_left = 0; rbs.content_margin_right = 0
	reset_btn.add_theme_stylebox_override("normal", rbs)
	reset_btn.add_theme_color_override("font_color", Color("#e74c3c"))
	reset_btn.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	reset_btn.pressed.connect(func():
		_filter_quality = "all"
		_sort_field = "cost"
		_sort_asc = true
		_search_text = ""
		_refresh_list()
		_build_filter_popup_content(panel)
	)
	btn_hbox.add_child(reset_btn)
	# 确定按钮
	var confirm_btn = Button.new()
	confirm_btn.text = "✓ 确定"
	confirm_btn.add_theme_font_size_override("font_size", 42)
	var cfs = StyleBoxFlat.new()
	cfs.bg_color = Global.current.btn_bg
	cfs.border_width_left = 2; cfs.border_width_right = 2
	cfs.border_width_top = 2; cfs.border_width_bottom = 2
	cfs.border_color = Color("#e8a838")
	cfs.corner_radius_top_left = 10; cfs.corner_radius_top_right = 10
	cfs.corner_radius_bottom_left = 10; cfs.corner_radius_bottom_right = 10
	cfs.content_margin_left = 0; cfs.content_margin_right = 0
	confirm_btn.add_theme_stylebox_override("normal", cfs)
	confirm_btn.add_theme_color_override("font_color", Color("#e8a838"))
	confirm_btn.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	confirm_btn.pressed.connect(func():
		_search_text = _search_input.text.strip_edges()
		_refresh_list()
		_close_filter_popup()
	)
	btn_hbox.add_child(confirm_btn)
	# 关闭按钮
	var close_btn = Button.new()
	close_btn.text = "✕ 关闭"
	close_btn.add_theme_font_size_override("font_size", 42)
	var clbs = StyleBoxFlat.new()
	clbs.bg_color = Color("#333333")
	clbs.border_width_left = 2; clbs.border_width_right = 2
	clbs.border_width_top = 2; clbs.border_width_bottom = 2
	clbs.border_color = Color("#888888")
	clbs.corner_radius_top_left = 10; clbs.corner_radius_top_right = 10
	clbs.corner_radius_bottom_left = 10; clbs.corner_radius_bottom_right = 10
	clbs.content_margin_left = 0; clbs.content_margin_right = 0
	close_btn.add_theme_stylebox_override("normal", clbs)
	close_btn.add_theme_color_override("font_color", Color("#aaaaaa"))
	close_btn.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	close_btn.pressed.connect(func():
		Global.play_sfx("click")
		_close_filter_popup()
	)
	btn_hbox.add_child(close_btn)

func _on_theme_changed(_mode = null):
	super._on_theme_changed(_mode)
	var stats_label = get_node_or_null("StatsLabel")
	if stats_label and stats_label is Label:
		stats_label.add_theme_color_override("font_color", Global.current.btn_text)
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
	_refresh_list()


func _on_help():
	Global.play_sfx("click")
	_show_help_guide()
func _show_help_guide():
	var overlay = ColorRect.new()
	overlay.name = "HelpOverlay"
	overlay.color = Color(0, 0, 0, 0.7)
	overlay.anchor_left = 0.0; overlay.anchor_top = 0.0
	overlay.anchor_right = 1.0; overlay.anchor_bottom = 1.0
	overlay.mouse_filter = MOUSE_FILTER_STOP
	overlay.gui_input.connect(func(ev: InputEvent):
		if not is_instance_valid(overlay): return
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			overlay.queue_free()
	)
	add_child(overlay)
	
	var panel = Panel.new()
	panel.name = "HelpPanel"
	panel.anchor_left = 0.05; panel.anchor_top = 0.05
	panel.anchor_right = 0.95; panel.anchor_bottom = 0.95
	panel.clip_contents = true
	var ps = StyleBoxFlat.new()
	ps.bg_color = Global.current.bg
	ps.border_width_left = 3; ps.border_width_right = 3
	ps.border_width_top = 3; ps.border_width_bottom = 3
	ps.border_color = Color("#e8a838")
	ps.corner_radius_top_left = 16; ps.corner_radius_top_right = 16
	ps.corner_radius_bottom_left = 16; ps.corner_radius_bottom_right = 16
	panel.add_theme_stylebox_override("panel", ps)
	overlay.add_child(panel)
	
	var title = Label.new()
	title.text = "🖼️ 卡牌图鉴指南"
	title.add_theme_font_size_override("font_size", 60)
	title.add_theme_color_override("font_color", Color("#6c9bcf"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.anchor_left = 0.0; title.anchor_top = 0.0
	title.anchor_right = 1.0; title.anchor_bottom = 0.0
	title.offset_left = 0; title.offset_top = Global.ph(0.01)
	title.offset_right = 0; title.offset_bottom = Global.ph(0.08)
	panel.add_child(title)
	
	var scroll = ScrollContainer.new()
	scroll.name = "HelpScroll"
	scroll.anchor_left = 0.02; scroll.anchor_top = 0.0
	scroll.anchor_right = 0.98; scroll.anchor_bottom = 1.0
	scroll.offset_left = 0; scroll.offset_top = Global.ph(0.085)
	scroll.offset_right = 0; scroll.offset_bottom = Global.ph(-0.08)
	scroll.scroll_horizontal = false
	panel.add_child(scroll)
	
	var vbox = VBoxContainer.new()
	vbox.name = "HelpVBox"
	vbox.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	vbox.add_theme_constant_override("separation", Global.ph(0.008))
	scroll.add_child(vbox)
	
	var lbl = Label.new()
	lbl.text = "卡牌图鉴展示所有已获得的卡牌，可按品质、元素、星数筛选和排序。"
	lbl.add_theme_font_size_override("font_size", 42)
	lbl.add_theme_color_override("font_color", Global.current.btn_text)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.size_flags_horizontal = SIZE_FILL
	vbox.add_child(lbl)
	
	lbl = Label.new()
	lbl.text = ""
	lbl.add_theme_font_size_override("font_size", 5)
	vbox.add_child(lbl)
	
	lbl = Label.new()
	lbl.text = "📋 功能说明"
	lbl.add_theme_font_size_override("font_size", 50)
	lbl.add_theme_color_override("font_color", Color("#e8a838"))
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.size_flags_horizontal = SIZE_FILL
	vbox.add_child(lbl)
	
	var items = [
		"🔍 筛选：按品质、元素、星数筛选卡牌",
		"📊 排序：按攻击力、生命值、星级等排序",
		"👆 长按卡牌：查看卡牌详情和效果",
		"🆔 唯一ID：每张卡牌有独立实例ID，同名卡独立展示",
		"⭐ 星数：1~5星，星数越高卡牌越强",
		"💎 品质：废品→瑕疵→标准→精良→卓越→完美",
		"🗑️ 删除：可删除不需要的卡牌",
		"📤 分享：将卡牌信息分享到社交平台",
	]
	for item in items:
		lbl = Label.new()
		lbl.text = item
		lbl.add_theme_font_size_override("font_size", 42)
		lbl.add_theme_color_override("font_color", Color("#CCCCCC"))
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.size_flags_horizontal = SIZE_FILL
		vbox.add_child(lbl)
	
	lbl = Label.new()
	lbl.text = ""
	lbl.add_theme_font_size_override("font_size", 5)
	vbox.add_child(lbl)
	
	lbl = Label.new()
	lbl.text = "💡 长按卡牌查看详情，点击 ❌ 可删除卡牌"
	lbl.add_theme_font_size_override("font_size", 42)
	lbl.add_theme_color_override("font_color", Color("#FFD700"))
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.size_flags_horizontal = SIZE_FILL
	vbox.add_child(lbl)
	
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, Global.ph(0.02))
	vbox.add_child(spacer)
	
	call_deferred("_set_help_vbox_width", vbox, scroll)
func _set_help_vbox_width(vbox: VBoxContainer, scroll: ScrollContainer):
	if not is_instance_valid(vbox) or not is_instance_valid(scroll): return
	var w = scroll.size.x
	if w <= 0: w = get_viewport_rect().size.x * 0.85
	vbox.custom_minimum_size = Vector2(w, 0)


# ===== 长按弹窗 =====

func _setup_long_press() -> void:
	set_process(true)

func _process(delta: float) -> void:
	if _pressed_row != null:
		_press_timer += delta
		if _press_timer >= LONG_PRESS_TIME:
			_show_card_detail(_pressed_row)
			_cancel_press()

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var pos = event.position
		if event.pressed:
			print("[CardGallery] 触摸按下 pos=", pos)
			var row = _find_row_at(pos)
			if row != null:
				print("[CardGallery] 找到行: ", row.name)
				_pressed_row = row
				_press_timer = 0.0
				_press_start_pos = pos
				_press_index = event.index
				var sb = StyleBoxFlat.new()
				sb.bg_color = Global.current.btn_bg_hover
				row.add_theme_stylebox_override("panel", sb)
		else:
			if event.index == _press_index:
				_cancel_press()
	elif event is InputEventScreenDrag:
		if _pressed_row != null and event.index == _press_index:
			var dist = event.position.distance_to(_press_start_pos)
			if dist > DRAG_THRESHOLD:
				_cancel_press()

func _find_row_at(pos: Vector2) -> Control:
	var vbox = get_node_or_null("CardScroll/CardList")
	if not vbox:
		return null
	# 用 gui_get_mouse_position 拿到相对当前节点的坐标
	# 但 row_panel 用 get_global_rect() 取的是世界坐标，需要把 pos 转换
	var vbox_global_rect = vbox.get_global_rect()
	# 遍历子行，用本地坐标对比（row_panel 在 vbox 内）
	for child in vbox.get_children():
		if child is Control and child.has_meta("card_data"):
			var child_rect_local = child.get_rect()
			# 把全局 pos 转到 vbox 局部坐标
			var pos_in_vbox = pos - vbox_global_rect.position
			if child_rect_local.has_point(pos_in_vbox):
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
func _show_card_detail(row: Control) -> void:
	var card = row.get_meta("card_data", {})
	if card.is_empty():
		return
	
	var card_name = card.get("name", card.get("card_name", "未命名卡牌"))
	var attack = card.get("atk", card.get("attack", 0))
	var health = card.get("hp", card.get("health", 0))
	var energy_cost = card.get("cost", card.get("energy_cost", 0))
	var quality = card.get("quality", "—")
	# 品质范围转显示用品质（取范围上限，如"标准 ~ 卓越"→"卓越"）
	var display_quality = quality
	if " ~ " in quality:
		var q_parts = quality.split(" ~ ")
		display_quality = q_parts[q_parts.size() - 1].strip_edges()
	var main_element = CardManager.get_card_element(card)
	var fields = card.get("fields", [])
	var desc = card.get("description", card.get("desc", ""))
	var star = card.get("star", 1)
	var effects = card.get("effects", [])
	
	# 遮罩
	var overlay = ColorRect.new()
	overlay.name = "CardDetailOverlay"
	overlay.color = Color(0.0, 0.0, 0.0, 0.7)
	overlay.anchor_left = 0.0; overlay.anchor_top = 0.0
	overlay.anchor_right = 1.0; overlay.anchor_bottom = 1.0
	overlay.mouse_filter = MOUSE_FILTER_STOP
	overlay.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and not e.pressed:
			overlay.queue_free()
	)
	add_child(overlay)
	
	# 弹窗面板
	var panel = Panel.new()
	panel.name = "CardDetailPanel"
	panel.anchor_left = 0.05; panel.anchor_top = 0.08
	panel.anchor_right = 0.95; panel.anchor_bottom = 0.92
	
	var ps = StyleBoxFlat.new()
	ps.bg_color = Global.current.bg
	ps.border_width_left = 2; ps.border_width_right = 2
	ps.border_width_top = 2; ps.border_width_bottom = 2
	ps.border_color = _get_quality_color(display_quality)
	ps.corner_radius_top_left = 20; ps.corner_radius_top_right = 20
	ps.corner_radius_bottom_left = 20; ps.corner_radius_bottom_right = 20
	panel.add_theme_stylebox_override("panel", ps)
	overlay.add_child(panel)
	
	# 标题
	var elem_icon = ""
	match main_element:
		"火": elem_icon = "🔥"
		"水": elem_icon = "💧"
		"风": elem_icon = "🌪️"
		"暗": elem_icon = "🌑"
		"光": elem_icon = "☀️"
	
	var title_label = Label.new()
	title_label.text = elem_icon + " " + card_name
	title_label.add_theme_font_size_override("font_size", 65)
	title_label.add_theme_color_override("font_color", Global.current.title)
	title_label.add_theme_color_override("font_shadow_color", Global.current.title_shadow)
	title_label.add_theme_constant_override("shadow_offset_x", Global.current.shadow_offset)
	title_label.add_theme_constant_override("shadow_offset_y", Global.current.shadow_offset)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.anchor_left = 0.0; title_label.anchor_top = 0.0
	title_label.anchor_right = 1.0; title_label.anchor_bottom = 0.0
	title_label.offset_left = Global.pw(0.04); title_label.offset_top = Global.ph(0.02)
	title_label.offset_right = Global.pw(-0.04); title_label.offset_bottom = Global.ph(0.08)
	panel.add_child(title_label)
	
	# 星级
	var star_label = Label.new()
	var star_text = ""
	for i in range(star):
		star_text += "⭐"
	star_label.text = star_text
	star_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	star_label.add_theme_font_size_override("font_size", 40)
	star_label.anchor_left = 0.0; star_label.anchor_top = 0.0
	star_label.anchor_right = 1.0; star_label.anchor_bottom = 0.0
	star_label.offset_left = 0; star_label.offset_top = Global.ph(0.075)
	star_label.offset_right = 0; star_label.offset_bottom = Global.ph(0.11)
	panel.add_child(star_label)
	
	# 分隔线
	var line = ColorRect.new()
	line.color = Global.current.topbar_border
	line.anchor_left = 0.0; line.anchor_top = 0.0
	line.anchor_right = 1.0; line.anchor_bottom = 0.0
	line.offset_left = Global.pw(0.05); line.offset_top = Global.ph(0.12)
	line.offset_right = Global.pw(-0.05); line.offset_bottom = Global.ph(0.122)
	panel.add_child(line)
	
	# 可滚动区域
	var info_scroll = ScrollContainer.new()
	info_scroll.name = "DetailInfoScroll"
	info_scroll.anchor_left = 0.0; info_scroll.anchor_top = 0.0
	info_scroll.anchor_right = 1.0; info_scroll.anchor_bottom = 1.0
	info_scroll.offset_left = 0; info_scroll.offset_top = Global.ph(0.125)
	info_scroll.offset_right = 0; info_scroll.offset_bottom = Global.ph(0.15)
	info_scroll.scroll_deadzone = 0
	panel.add_child(info_scroll)
	
	var info_vbox = VBoxContainer.new()
	info_vbox.name = "DetailInfoVBox"
	info_vbox.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	info_vbox.custom_minimum_size = Vector2(Global.pw(0.9), 0)
	info_scroll.add_child(info_vbox)
	
	# 信息行
	var info_items := []
	
	# 品质
	info_items.append(["品质", display_quality])
	# 属性
	info_items.append(["属性", elem_icon + " " + main_element if main_element != "" and main_element != "无" else "无"])
	# 费用/攻防
	info_items.append(["⚡费用", str(energy_cost)])
	info_items.append(["⚔攻击", str(attack)])
	info_items.append(["❤生命", str(health)])
	# 字段
	if fields.size() > 0:
		info_items.append(["字段", " ".join(fields)])
	# 效果
	if effects.size() > 0:
		for i in range(effects.size()):
			var eff = effects[i]
			var eff_desc = ""
			if eff is Dictionary:
				eff_desc = Global.get_effect_desc(eff)
			elif eff is String:
				var comp = Global.get_circuit_by_id(eff)
				if comp and comp.has("name"):
					eff_desc = comp["name"]
				else:
					eff_desc = eff
			if eff_desc != "":
				info_items.append(["效果" + str(i+1), eff_desc])
	# 辅材
	var aux_items = card.get("aux_items", [])
	if aux_items.size() > 0:
		for i in range(aux_items.size()):
			var aux = aux_items[i]
			var aux_name = aux.get("name", "未知辅材")
			var aux_eff = _describe_aux_effect(aux)
			info_items.append(["辅材" + str(i+1), aux_name + (("　" + aux_eff) if aux_eff != "" else "")])
	# 描述
	if desc != "":
		info_items.append(["描述", desc])
	
	for item in info_items:
		var key = item[0]; var val = item[1]
		var row_hbox = HBoxContainer.new()
		row_hbox.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
		row_hbox.custom_minimum_size = Vector2(0, Global.ph(0.05))
		info_vbox.add_child(row_hbox)
		
		var key_label = Label.new()
		key_label.text = key + "："
		key_label.add_theme_font_size_override("font_size", 40)
		key_label.add_theme_color_override("font_color", Global.current.btn_text)
		key_label.custom_minimum_size = Vector2(Global.pw(0.35), 0)
		key_label.size_flags_horizontal = SIZE_SHRINK_BEGIN
		row_hbox.add_child(key_label)
		
		var val_label = Label.new()
		val_label.text = val
		val_label.add_theme_font_size_override("font_size", 40)
		val_label.add_theme_color_override("font_color", Global.current.title)
		val_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		val_label.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
		val_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row_hbox.add_child(val_label)
	
	# 底部按钮区域
	var bottom_hbox = HBoxContainer.new()
	bottom_hbox.anchor_left = 0.0; bottom_hbox.anchor_top = 1.0
	bottom_hbox.anchor_right = 1.0; bottom_hbox.anchor_bottom = 1.0
	bottom_hbox.offset_left = Global.pw(0.08)
	bottom_hbox.offset_top = Global.ph(-0.13)
	bottom_hbox.offset_right = Global.pw(-0.08)
	bottom_hbox.offset_bottom = Global.ph(-0.03)
	bottom_hbox.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	panel.add_child(bottom_hbox)
	
	# 删除按钮（二次确认）
	var delete_btn = Button.new()
	delete_btn.text = "🗑️ 删除"
	delete_btn.add_theme_font_size_override("font_size", 50)
	var ds = StyleBoxFlat.new()
	ds.bg_color = Global.current.btn_bg
	ds.border_width_left = 2; ds.border_width_right = 2
	ds.border_width_top = 2; ds.border_width_bottom = 2
	ds.border_color = Color("#ef4444")
	ds.corner_radius_top_left = 12; ds.corner_radius_top_right = 12
	ds.corner_radius_bottom_left = 12; ds.corner_radius_bottom_right = 12
	ds.content_margin_left = 20; ds.content_margin_right = 20
	delete_btn.add_theme_stylebox_override("normal", ds)
	delete_btn.add_theme_color_override("font_color", Color("#ef4444"))
	delete_btn.custom_minimum_size = Vector2(Global.pw(0.25), 0)
	delete_btn.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	
	# 二次确认弹窗
	delete_btn.pressed.connect(func():
		# 确认遮罩
		var confirm_overlay = ColorRect.new()
		confirm_overlay.name = "DeleteConfirmOverlay"
		confirm_overlay.color = Color(0.0, 0.0, 0.0, 0.6)
		confirm_overlay.anchor_left = 0.0; confirm_overlay.anchor_top = 0.0
		confirm_overlay.anchor_right = 1.0; confirm_overlay.anchor_bottom = 1.0
		confirm_overlay.mouse_filter = MOUSE_FILTER_STOP
		confirm_overlay.gui_input.connect(func(ce: InputEvent):
			if ce is InputEventMouseButton and not ce.pressed:
				confirm_overlay.queue_free()
		)
		add_child(confirm_overlay)
		
		# 确认面板
		var confirm_panel = Panel.new()
		confirm_panel.name = "DeleteConfirmPanel"
		confirm_panel.anchor_left = 0.15; confirm_panel.anchor_top = 0.35
		confirm_panel.anchor_right = 0.85; confirm_panel.anchor_bottom = 0.65
		
		var cps = StyleBoxFlat.new()
		cps.bg_color = Global.current.bg
		cps.border_width_left = 2; cps.border_width_right = 2
		cps.border_width_top = 2; cps.border_width_bottom = 2
		cps.border_color = Color("#ef4444")
		cps.corner_radius_top_left = 20; cps.corner_radius_top_right = 20
		cps.corner_radius_bottom_left = 20; cps.corner_radius_bottom_right = 20
		confirm_panel.add_theme_stylebox_override("panel", cps)
		confirm_overlay.add_child(confirm_panel)
		
		# 提示文字
		var msg = Label.new()
		msg.text = "确认删除「" + card_name + "」？\n此操作不可撤销！"
		msg.add_theme_font_size_override("font_size", 45)
		msg.add_theme_color_override("font_color", Global.current.title)
		msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		msg.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		msg.anchor_left = 0.0; msg.anchor_top = 0.0
		msg.anchor_right = 1.0; msg.anchor_bottom = 1.0
		msg.offset_left = Global.pw(0.05); msg.offset_top = Global.ph(0.03)
		msg.offset_right = Global.pw(-0.05); msg.offset_bottom = Global.ph(-0.15)
		confirm_panel.add_child(msg)
		
		# 确认按钮行
		var btn_hbox = HBoxContainer.new()
		btn_hbox.anchor_left = 0.0; btn_hbox.anchor_top = 1.0
		btn_hbox.anchor_right = 1.0; btn_hbox.anchor_bottom = 1.0
		btn_hbox.offset_left = Global.pw(0.08)
		btn_hbox.offset_top = Global.ph(-0.12)
		btn_hbox.offset_right = Global.pw(-0.08)
		btn_hbox.offset_bottom = Global.ph(-0.03)
		btn_hbox.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
		confirm_panel.add_child(btn_hbox)
		
		# 取消按钮
		var cancel_btn = Button.new()
		cancel_btn.text = "取消"
		cancel_btn.add_theme_font_size_override("font_size", 45)
		var cs = StyleBoxFlat.new()
		cs.bg_color = Global.current.btn_bg
		cs.border_width_left = 2; cs.border_width_right = 2
		cs.border_width_top = 2; cs.border_width_bottom = 2
		cs.border_color = Global.current.topbar_border
		cs.corner_radius_top_left = 12; cs.corner_radius_top_right = 12
		cs.corner_radius_bottom_left = 12; cs.corner_radius_bottom_right = 12
		cs.content_margin_left = 20; cs.content_margin_right = 20
		cancel_btn.add_theme_stylebox_override("normal", cs)
		cancel_btn.add_theme_color_override("font_color", Global.current.btn_text)
		cancel_btn.custom_minimum_size = Vector2(Global.pw(0.25), 0)
		cancel_btn.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
		cancel_btn.pressed.connect(func(): confirm_overlay.queue_free())
		btn_hbox.add_child(cancel_btn)
		
		# 确认删除按钮
		var confirm_btn = Button.new()
		confirm_btn.text = "确认删除"
		confirm_btn.add_theme_font_size_override("font_size", 45)
		var cfs = StyleBoxFlat.new()
		cfs.bg_color = Color("#ef4444")
		cfs.border_width_left = 2; cfs.border_width_right = 2
		cfs.border_width_top = 2; cfs.border_width_bottom = 2
		cfs.border_color = Color("#ef4444")
		cfs.corner_radius_top_left = 12; cfs.corner_radius_top_right = 12
		cfs.corner_radius_bottom_left = 12; cfs.corner_radius_bottom_right = 12
		cfs.content_margin_left = 20; cfs.content_margin_right = 20
		confirm_btn.add_theme_stylebox_override("normal", cfs)
		confirm_btn.add_theme_color_override("font_color", Color("#ffffff"))
		confirm_btn.custom_minimum_size = Vector2(Global.pw(0.25), 0)
		confirm_btn.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
		confirm_btn.pressed.connect(func():
			# 执行删除
			var card_id = card.get("id", "")
			if card_id != "":
				CardManager.remove_card_by_id(card_id)
			else:
				# 没有id，按名称匹配
				var cards = CardManager.get_all_cards()
				for ci in range(cards.size()):
					if cards[ci].get("name", cards[ci].get("card_name", "")) == card_name:
						CardManager.remove_card(ci)
						break
			_refresh_list()
			confirm_overlay.queue_free()
			overlay.queue_free()
		)
		btn_hbox.add_child(confirm_btn)
	)
	bottom_hbox.add_child(delete_btn)
	
	# 分享按钮
	var share_btn = Button.new()
	share_btn.text = "📤 分享"
	share_btn.add_theme_font_size_override("font_size", 50)
	var ss = StyleBoxFlat.new()
	ss.bg_color = Global.current.btn_bg
	ss.border_width_left = 2; ss.border_width_right = 2
	ss.border_width_top = 2; ss.border_width_bottom = 2
	ss.border_color = Color("#4CAF50")
	ss.corner_radius_top_left = 12; ss.corner_radius_top_right = 12
	ss.corner_radius_bottom_left = 12; ss.corner_radius_bottom_right = 12
	ss.content_margin_left = 20; ss.content_margin_right = 20
	share_btn.add_theme_stylebox_override("normal", ss)
	share_btn.add_theme_color_override("font_color", Color("#4CAF50"))
	share_btn.custom_minimum_size = Vector2(Global.pw(0.25), 0)
	share_btn.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	share_btn.pressed.connect(func(): _on_share_card(card, overlay))
	bottom_hbox.add_child(share_btn)
	
	# 关闭按钮
	var close_btn = Button.new()
	close_btn.text = "✕ 关闭"
	close_btn.add_theme_font_size_override("font_size", 50)
	var cs = StyleBoxFlat.new()
	cs.bg_color = Global.current.btn_bg
	cs.border_width_left = 2; cs.border_width_right = 2
	cs.border_width_top = 2; cs.border_width_bottom = 2
	cs.border_color = Color("#888888")
	cs.corner_radius_top_left = 12; cs.corner_radius_top_right = 12
	cs.corner_radius_bottom_left = 12; cs.corner_radius_bottom_right = 12
	cs.content_margin_left = 20; cs.content_margin_right = 20
	close_btn.add_theme_stylebox_override("normal", cs)
	close_btn.add_theme_color_override("font_color", Global.current.btn_text)
	close_btn.custom_minimum_size = Vector2(Global.pw(0.25), 0)
	close_btn.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	close_btn.pressed.connect(func(): overlay.queue_free())
	bottom_hbox.add_child(close_btn)

func _on_share_card(card: Dictionary, detail_overlay: ColorRect) -> void:
	# 生成卡牌分享图片（异步：内部有await等渲染帧）
	var success = await _generate_card_image(card)
	
	if success:
		_show_share_success_dialog()
	else:
		# 备用方案：复制压缩码到剪贴板
		var compressed = _compress_card(card)
		DisplayServer.clipboard_set(compressed)
		_show_share_toast("✅ 卡牌压缩码已复制（" + str(compressed.length()) + "字符）")
	
	# 关闭详情弹窗
	_close_detail(detail_overlay)


## 生成卡牌分享图片（使用 SubViewport + Control._draw() 渲染）
func _generate_card_image(card: Dictionary) -> bool:
	# 压缩码（二维码用）
	var qr_data = _compress_card(card)
	
	# 创建离屏渲染视口（960x1360 高清）
	var viewport = SubViewport.new()
	viewport.name = "ShareCardViewport"
	viewport.size = Vector2i(960, 1360)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.disable_3d = true
	add_child(viewport)
	
	# 渲染面板
	var panel = CardRenderPanel.new()
	panel.setup(card, qr_data)
	viewport.add_child(panel)
	
	# 等待渲染完成（至少两帧）
	await get_tree().process_frame
	await get_tree().process_frame
	
	# 从视口取图
	var tex = viewport.get_texture()
	var img = tex.get_image()
	if img == null or img.is_empty():
		viewport.queue_free()
		return false
	
	# 保存到 user://
	var save_path = "user://share_card.png"
	var err = img.save_png(save_path)
	viewport.queue_free()
	if err != OK:
		return false
	
	# Android 上用 CardScanner 插件通过 MediaStore 保存到相册（兼容 Scoped Storage）
	if OS.get_name() == "Android":
		var scanner = _get_scanner_node()
		if scanner != null and scanner.saveImageToGallery(ProjectSettings.globalize_path(save_path)):
			pass  # 已保存到相册（DCIM/Camera）
		else:
			# 相册保存失败也没关系，图片已存到 user://
			push_warning("相册保存失败，图片已存到 user:// 目录")
	
	return true


## 自定义压缩：单字母前缀 + | 分隔，极致紧凑
## 格式示例：N炎龙|A8|H5|C4|Q3|EF|S1|F龙族|X造成2点伤害
func _compress_card(card: Dictionary) -> String:
	var parts := []
	
	# 名称
	var name = card.get("name", card.get("card_name", ""))
	if name != "":
		parts.append("N" + _sanitize(name))
	
	# 攻击（float统一转int，避免压缩码出现"3.0"）
	var atk = card.get("atk", card.get("attack", 0))
	if atk is float:
		atk = int(atk)
	parts.append("A" + str(atk))
	
	# 生命
	var hp = card.get("hp", card.get("health", 0))
	if hp is float:
		hp = int(hp)
	parts.append("H" + str(hp))
	
	# 费用
	var cost = card.get("cost", card.get("energy_cost", 0))
	if cost is float:
		cost = int(cost)
	parts.append("C" + str(cost))
	
	# 品质（单字编码：覆盖全部档位，兼容标准/精良）
	var quality = card.get("quality", "")
	var compress_q = quality
	if " ~ " in quality:
		var q_parts = quality.split(" ~ ")
		compress_q = q_parts[q_parts.size() - 1].strip_edges()
	var q_map = Global.QUALITY_ENCODE
	parts.append("Q" + q_map.get(compress_q, "0"))
	
	# 属性（单字母编码）
	var element = CardManager.get_card_element(card)
	var e_map = {"火": "F", "水": "W", "风": "A", "暗": "D", "光": "L", "地": "E", "无": "N"}
	parts.append("E" + e_map.get(element, "N"))
	
	# 星级
	var star = card.get("star", 1)
	parts.append("S" + str(star))
	
	# 字段列表
	var fields = card.get("fields", [])
	if fields.size() > 0:
		var clean_fields := []
		for f in fields:
			clean_fields.append(_sanitize(f))
		parts.append("F" + ",".join(clean_fields))
	
	# 描述
	var desc = card.get("description", card.get("desc", ""))
	if desc != "":
		parts.append("D" + _sanitize(desc))
	
	# 效果列表
	var effects = card.get("effects", [])
	if effects.size() > 0:
		var eff_strs := []
		# 检测是否为纹路槽位ID格式（["TR01", "A01", ...]）
		var is_slot_format = effects.size() > 0 and effects[0] is String and \
			(effects[0].begins_with("TR") or effects[0].begins_with("A") or \
			 effects[0].begins_with("C") or effects[0].begins_with("T") or \
			 effects[0].begins_with("CO"))
		for eff in effects:
			var d = ""
			if eff is Dictionary:
				# 结构化编码：$trigger,action,target,value,desc,name（保留效果完整字段供解压还原）
				var t = str(eff.get("trigger", ""))
				var a = str(eff.get("action", ""))
				var tg = str(eff.get("target", ""))
				var v = str(eff.get("value", 0))
				var dd = str(eff.get("desc", eff.get("effect", "")))
				var nm = str(eff.get("name", ""))
				if t != "" or a != "" or tg != "":
					d = "$" + _sanitize(t) + "," + _sanitize(a) + "," + _sanitize(tg) + "," + _sanitize(v) + "," + _sanitize(dd) + "," + _sanitize(nm)
				else:
					d = _sanitize(dd)
			elif eff is String:
				if is_slot_format:
					# 纹路组件ID直接保留（TR01/A01等）
					d = eff
				else:
					d = eff
			if d != "":
				eff_strs.append(d)
		if eff_strs.size() > 0:
			parts.append("X" + ";".join(eff_strs))
	
	# ID（如果有）
	if card.has("id"):
		parts.append("I" + _sanitize(str(card["id"])))
	
	# 确保压缩码不超出QR码容量（Byte mode M纠错，版本18：最大563字节UTF-8数据）
	# 最极端卡牌数据约456字节，留8%余量用520
	var compressed = "|".join(parts)
	var MAX_QR_BYTES = 520
	var utf8 = compressed.to_utf8_buffer()
	if utf8.size() > MAX_QR_BYTES:
		# 超长时：丢弃描述，效果只保留1个且截字
		push_warning("卡牌压缩码过长（" + str(utf8.size()) + "字节），正在截断...")
		var minimal_parts := []
		minimal_parts.append("N" + _sanitize(card.get("name", card.get("card_name", ""))))
		var min_atk = card.get("atk", 0)
		if min_atk is float:
			min_atk = int(min_atk)
		minimal_parts.append("A" + str(min_atk))
		var min_hp = card.get("hp", 0)
		if min_hp is float:
			min_hp = int(min_hp)
		minimal_parts.append("H" + str(min_hp))
		var min_cost = card.get("cost", 0)
		if min_cost is float:
			min_cost = int(min_cost)
		minimal_parts.append("C" + str(min_cost))
		var q = card.get("quality", "普通")
		q_map = Global.QUALITY_ENCODE
		minimal_parts.append("Q" + q_map.get(q, "1"))
		var e = card.get("element", "无")
		e_map = {"火":"F", "水":"W", "风":"A", "暗":"D", "光":"L", "地":"E", "无":"N"}
		minimal_parts.append("E" + e_map.get(e, "N"))
		minimal_parts.append("S" + str(card.get("star", 1)))
		fields = card.get("fields", [])
		if fields.size() > 0:
			var clean_fields := []
			for f in fields:
				clean_fields.append(_sanitize(f))
			minimal_parts.append("F" + ",".join(clean_fields))
		# 效果只保留第1个，截短至8字
		effects = card.get("effects", [])
		if effects.size() > 0:
			var eff = effects[0]
			var d = ""
			if eff is Dictionary:
				d = eff.get("desc", eff.get("effect", ""))
			elif eff is String:
				d = eff
			if d != "":
				if d.length() > 8:
					d = d.substr(0, 8) + "…"
				minimal_parts.append("X" + _sanitize(d))
		# 描述丢弃（最占空间，非核心字段）
		desc = card.get("description", card.get("desc", ""))
		if desc != "":
			if desc.length() > 8:
				desc = desc.substr(0, 8) + "…"
			minimal_parts.append("D" + _sanitize(desc))
			# 检查加上描述后是否超限，超限则丢弃描述
			var try_compressed = "|".join(minimal_parts)
			if try_compressed.to_utf8_buffer().size() > MAX_QR_BYTES:
				minimal_parts.erase(minimal_parts.back())
				push_warning("描述已丢弃以缩减二维码数据")
		if card.has("id"):
			minimal_parts.append("I" + _sanitize(str(card["id"])))
		compressed = "|".join(minimal_parts)
		utf8 = compressed.to_utf8_buffer()
		push_warning("截断后压缩码长度: " + str(utf8.size()) + "字节")
	
	return compressed


## 清理特殊字符（避免与分隔符冲突）
func _sanitize(s: String) -> String:
	s = s.replace("|", "丨")  # 替换竖线为中文竖线
	s = s.replace("\n", " ")  # 换行变空格
	return s


## 解压缩：把紧凑字符串还原为卡牌数据
func _decompress_card(compressed: String) -> Dictionary:
	var card := {}
	var parts = compressed.split("|")
	for part in parts:
		if part.length() < 2:
			continue
		var prefix = part[0]
		var value = part.substr(1)
		match prefix:
			"N": card["name"] = value
			"A": card["atk"] = int(value)
			"H": card["hp"] = int(value)
			"C": card["cost"] = int(value)
			"Q":
				var q_map = Global.QUALITY_DECODE
				card["quality"] = q_map.get(value, "普通")
			"E":
				var e_map = {"F": "火", "W": "水", "A": "风", "D": "暗", "L": "光", "E": "地", "N": "无"}
				card["element"] = e_map.get(value, "无")
			"S": card["star"] = int(value)
			"F": card["fields"] = value.split(",")
			"D": card["desc"] = value
			"X":
				var eff_items = value.split(";")
				# 检测是否为纹路组件ID格式（TR01/A01/C01/T01/CO01）
				if eff_items.size() > 0 and eff_items[0].length() >= 2 and \
					(eff_items[0].begins_with("TR") or eff_items[0].begins_with("A") or \
					 eff_items[0].begins_with("C") or eff_items[0].begins_with("T") or \
					 eff_items[0].begins_with("CO")):
					# 还原为纹路槽位数组（原始格式，与CardEngraving._slots兼容）
					card["effects"] = eff_items
				else:
					# 还原为文本描述字典数组
					var effects := []
					for d in eff_items:
						if d.begins_with("$"):
							# 结构化效果：$trigger,action,target,value,desc,name
							var fields = d.substr(1).split(",", true, 5)
							var eff_dict := {}
							if fields.size() >= 1 and fields[0] != "":
								eff_dict["trigger"] = fields[0]
							if fields.size() >= 2 and fields[1] != "":
								eff_dict["action"] = fields[1]
							if fields.size() >= 3 and fields[2] != "":
								eff_dict["target"] = fields[2]
							if fields.size() >= 4 and fields[3] != "":
								eff_dict["value"] = int(fields[3])
							if fields.size() >= 5 and fields[4] != "":
								eff_dict["desc"] = fields[4]
							if fields.size() >= 6 and fields[5] != "":
								eff_dict["name"] = fields[5]
							effects.append(eff_dict)
						else:
							effects.append({"desc": d})
					card["effects"] = effects
			"I": card["id"] = value
	# ★ 字段归一化：同时生成初始卡字段(name/atk/hp/cost)和自制卡字段(card_name/attack/health/energy_cost)
	# 这样导入的卡无论被图鉴/战斗/仓库哪个系统读取，都能无缝兼容
	if card.has("name"):
		card["card_name"] = card["name"]
	elif card.has("card_name"):
		card["name"] = card["card_name"]
	if card.has("atk"):
		card["attack"] = card["atk"]
	elif card.has("attack"):
		card["atk"] = card["attack"]
	if card.has("hp"):
		card["health"] = card["hp"]
	elif card.has("health"):
		card["hp"] = card["health"]
	if card.has("cost"):
		card["energy_cost"] = card["cost"]
	elif card.has("energy_cost"):
		card["cost"] = card["energy_cost"]
	if card.has("element"):
		card["main_element"] = card["element"]
	elif card.has("main_element"):
		card["element"] = card["main_element"]
	if card.has("desc"):
		card["description"] = card["desc"]
	elif card.has("description"):
		card["desc"] = card["description"]
	return card


func _show_share_toast(msg: String) -> void:
	var toast = Label.new()
	toast.text = msg
	toast.add_theme_font_size_override("font_size", 40)
	toast.add_theme_color_override("font_color", Color("#4CAF50"))
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	toast.anchor_left = 0.1; toast.anchor_top = 0.45
	toast.anchor_right = 0.9; toast.anchor_bottom = 0.55
	toast.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(toast)
	# 2秒后自动消失
	var timer = get_tree().create_timer(2.0)
	timer.timeout.connect(func():
		if is_instance_valid(toast):
			toast.queue_free()
	)


func _on_detail_overlay_clicked(event: InputEvent, overlay: ColorRect) -> void:
	if event is InputEventScreenTouch and not event.pressed:
		_close_detail(overlay)

func _close_detail(overlay: ColorRect) -> void:
	if overlay and is_instance_valid(overlay):
		overlay.queue_free()


## 分享成功弹窗
func _show_share_success_dialog() -> void:
	# 弹窗遮罩
	var overlay = ColorRect.new()
	overlay.name = "ShareSuccessOverlay"
	overlay.color = Color(0.0, 0.0, 0.0, 0.6)
	overlay.anchor_left = 0.0; overlay.anchor_top = 0.0
	overlay.anchor_right = 1.0; overlay.anchor_bottom = 1.0
	overlay.mouse_filter = MOUSE_FILTER_STOP
	overlay.gui_input.connect(func(event: InputEvent):
		if event is InputEventScreenTouch and not event.pressed:
			if is_instance_valid(overlay):
				overlay.queue_free()
	)
	add_child(overlay)

	# 面板
	var panel = Panel.new()
	panel.name = "ShareSuccessPanel"
	panel.anchor_left = 0.15; panel.anchor_top = 0.35
	panel.anchor_right = 0.85; panel.anchor_bottom = 0.65

	var ps = StyleBoxFlat.new()
	ps.bg_color = Global.current.bg
	ps.border_width_left = 2; ps.border_width_right = 2
	ps.border_width_top = 2; ps.border_width_bottom = 2
	ps.border_color = Color("#e8a838")
	ps.corner_radius_top_left = 20; ps.corner_radius_top_right = 20
	ps.corner_radius_bottom_left = 20; ps.corner_radius_bottom_right = 20
	panel.add_theme_stylebox_override("panel", ps)
	overlay.add_child(panel)

	# 提示文字
	var msg_label = Label.new()
	msg_label.text = "✅ 卡牌图片已保存到相册\n请手动分享给好友吧！"
	msg_label.add_theme_font_size_override("font_size", 42)
	msg_label.add_theme_color_override("font_color", Global.current.title)
	msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	msg_label.anchor_left = 0.0; msg_label.anchor_top = 0.0
	msg_label.anchor_right = 1.0; msg_label.anchor_bottom = 1.0
	msg_label.offset_left = Global.pw(0.05); msg_label.offset_top = Global.ph(0.03)
	msg_label.offset_right = Global.pw(-0.05); msg_label.offset_bottom = Global.ph(-0.15)
	panel.add_child(msg_label)

	# 确定按钮
	var btn_hbox = HBoxContainer.new()
	btn_hbox.anchor_left = 0.0; btn_hbox.anchor_top = 1.0
	btn_hbox.anchor_right = 1.0; btn_hbox.anchor_bottom = 1.0
	btn_hbox.offset_left = Global.pw(0.15)
	btn_hbox.offset_top = Global.ph(-0.12)
	btn_hbox.offset_right = Global.pw(-0.15)
	btn_hbox.offset_bottom = Global.ph(-0.02)
	btn_hbox.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	panel.add_child(btn_hbox)

	var ok_btn = Button.new()
	ok_btn.text = "👍 好的"
	ok_btn.add_theme_font_size_override("font_size", 45)
	var cs = StyleBoxFlat.new()
	cs.bg_color = Color("#4CAF50")
	cs.border_width_left = 2; cs.border_width_right = 2
	cs.border_width_top = 2; cs.border_width_bottom = 2
	cs.border_color = Color("#66BB6A")
	cs.corner_radius_top_left = 12; cs.corner_radius_top_right = 12
	cs.corner_radius_bottom_left = 12; cs.corner_radius_bottom_right = 12
	cs.content_margin_left = 16; cs.content_margin_right = 16
	ok_btn.add_theme_stylebox_override("normal", cs)
	ok_btn.add_theme_color_override("font_color", Color("#ffffff"))
	ok_btn.custom_minimum_size = Vector2(Global.pw(0.4), 0)
	ok_btn.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	ok_btn.pressed.connect(func():
		if is_instance_valid(overlay):
			overlay.queue_free()
	)
	btn_hbox.add_child(ok_btn)


func _show_delete_confirm(card: Dictionary, detail_overlay: ColorRect) -> void:
	var card_name = card.get("name", card.get("card_name", "未命名卡牌"))
	
	# 确认弹窗遮罩
	var confirm_overlay = ColorRect.new()
	confirm_overlay.name = "DeleteConfirmOverlay"
	confirm_overlay.color = Color(0.0, 0.0, 0.0, 0.6)
	confirm_overlay.anchor_left = 0.0; confirm_overlay.anchor_top = 0.0
	confirm_overlay.anchor_right = 1.0; confirm_overlay.anchor_bottom = 1.0
	confirm_overlay.mouse_filter = MOUSE_FILTER_STOP
	confirm_overlay.gui_input.connect(_on_confirm_overlay_clicked.bind(confirm_overlay))
	add_child(confirm_overlay)
	
	# 确认面板
	var panel = Panel.new()
	panel.name = "DeleteConfirmPanel"
	panel.anchor_left = 0.15; panel.anchor_top = 0.35
	panel.anchor_right = 0.85; panel.anchor_bottom = 0.65
	
	var ps = StyleBoxFlat.new()
	ps.bg_color = Global.current.bg
	ps.border_width_left = 2; ps.border_width_right = 2
	ps.border_width_top = 2; ps.border_width_bottom = 2
	ps.border_color = Color("#e74c3c")
	ps.corner_radius_top_left = 20; ps.corner_radius_top_right = 20
	ps.corner_radius_bottom_left = 20; ps.corner_radius_bottom_right = 20
	panel.add_theme_stylebox_override("panel", ps)
	confirm_overlay.add_child(panel)
	
	# 提示文字
	var msg_label = Label.new()
	msg_label.text = "确认删除「" + card_name + "」？\n此操作不可撤销！"
	msg_label.add_theme_font_size_override("font_size", 45)
	msg_label.add_theme_color_override("font_color", Global.current.title)
	msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	msg_label.anchor_left = 0.0; msg_label.anchor_top = 0.0
	msg_label.anchor_right = 1.0; msg_label.anchor_bottom = 1.0
	msg_label.offset_left = Global.pw(0.05); msg_label.offset_top = Global.ph(0.03)
	msg_label.offset_right = Global.pw(-0.05); msg_label.offset_bottom = Global.ph(-0.15)
	panel.add_child(msg_label)
	
	# 按钮区域
	var btn_hbox = HBoxContainer.new()
	btn_hbox.anchor_left = 0.0; btn_hbox.anchor_top = 1.0
	btn_hbox.anchor_right = 1.0; btn_hbox.anchor_bottom = 1.0
	btn_hbox.offset_left = Global.pw(0.06)
	btn_hbox.offset_top = Global.ph(-0.12)
	btn_hbox.offset_right = Global.pw(-0.06)
	btn_hbox.offset_bottom = Global.ph(-0.02)
	btn_hbox.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	panel.add_child(btn_hbox)
	
	# 确认删除按钮
	var confirm_btn = Button.new()
	confirm_btn.text = "🗑️ 确认删除"
	confirm_btn.add_theme_font_size_override("font_size", 45)
	var cs = StyleBoxFlat.new()
	cs.bg_color = Color("#c0392b")
	cs.border_width_left = 2; cs.border_width_right = 2
	cs.border_width_top = 2; cs.border_width_bottom = 2
	cs.border_color = Color("#e74c3c")
	cs.corner_radius_top_left = 12; cs.corner_radius_top_right = 12
	cs.corner_radius_bottom_left = 12; cs.corner_radius_bottom_right = 12
	cs.content_margin_left = 16; cs.content_margin_right = 16
	confirm_btn.add_theme_stylebox_override("normal", cs)
	confirm_btn.add_theme_color_override("font_color", Color("#ffffff"))
	confirm_btn.custom_minimum_size = Vector2(Global.pw(0.3), 0)
	confirm_btn.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	confirm_btn.pressed.connect(_do_delete_card.bind(card, detail_overlay, confirm_overlay))
	btn_hbox.add_child(confirm_btn)
	
	# 取消按钮
	var cancel_btn = Button.new()
	cancel_btn.text = "取消"
	cancel_btn.add_theme_font_size_override("font_size", 45)
	var cancel_s = StyleBoxFlat.new()
	cancel_s.bg_color = Global.current.btn_bg
	cancel_s.border_width_left = 2; cancel_s.border_width_right = 2
	cancel_s.border_width_top = 2; cancel_s.border_width_bottom = 2
	cancel_s.border_color = Color("#888888")
	cancel_s.corner_radius_top_left = 12; cancel_s.corner_radius_top_right = 12
	cancel_s.corner_radius_bottom_left = 12; cancel_s.corner_radius_bottom_right = 12
	cancel_s.content_margin_left = 16; cancel_s.content_margin_right = 16
	cancel_btn.add_theme_stylebox_override("normal", cancel_s)
	cancel_btn.add_theme_color_override("font_color", Global.current.btn_text)
	cancel_btn.custom_minimum_size = Vector2(Global.pw(0.3), 0)
	cancel_btn.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	cancel_btn.pressed.connect(_close_confirm.bind(confirm_overlay))
	btn_hbox.add_child(cancel_btn)

func _on_confirm_overlay_clicked(event: InputEvent, confirm_overlay: ColorRect) -> void:
	if event is InputEventScreenTouch and not event.pressed:
		_close_confirm(confirm_overlay)

func _close_confirm(confirm_overlay: ColorRect) -> void:
	if confirm_overlay and is_instance_valid(confirm_overlay):
		confirm_overlay.queue_free()

func _do_delete_card(card: Dictionary, detail_overlay: ColorRect, confirm_overlay: ColorRect) -> void:
	var card_id = card.get("id", "")
	if card_id == "":
		print("[卡牌图鉴] 错误：卡牌没有 ID，无法删除")
		_close_confirm(confirm_overlay)
		return
	
	var ok = CardManager.remove_card_by_id(card_id)
	if ok:
		print("[卡牌图鉴] 已删除卡牌: ", card.get("name", card.get("card_name", "未知")))
		# 关闭确认弹窗和详情弹窗
		_close_confirm(confirm_overlay)
		_close_detail(detail_overlay)
		# 刷新列表
		_refresh_list()
	else:
		print("[卡牌图鉴] 删除卡牌失败: ", card_id)
		_close_confirm(confirm_overlay)


# ============================================================
# 辅材描述辅助
# ============================================================

func _describe_aux_effect(aux: Dictionary) -> String:
	var effect = aux.get("effect", {})
	if effect.is_empty():
		return ""
	var parts = []
	if effect.has("atk_bonus"):
		parts.append("攻击+" + str(effect["atk_bonus"]))
	if effect.has("hp_bonus"):
		parts.append("生命+" + str(effect["hp_bonus"]))
	if effect.has("energy_reduce"):
		parts.append("费用-" + str(effect["energy_reduce"]))
	if effect.has("element"):
		parts.append("属性→" + str(effect["element"]))
	if effect.has("element_power"):
		parts.append("元素威力+" + str(effect["element_power"] * 100) + "%")
	if effect.has("shield"):
		parts.append("护盾" + str(effect["shield"]))
	if effect.get("indestructible_once", false):
		parts.append("免毁一次")
	if effect.get("haste", false):
		parts.append("急速")
	if effect.has("extra_trigger"):
		parts.append("额外触发+" + str(effect["extra_trigger"]))
	if effect.has("draw_on_summon"):
		parts.append("召唤抽" + str(effect["draw_on_summon"]))
	if effect.has("damage_reduce"):
		parts.append("减伤" + str(effect["damage_reduce"]))
	if effect.get("damage_halve", false):
		parts.append("伤害减半")
	if effect.has("poison"):
		parts.append("中毒+" + str(effect["poison"]))
	if effect.get("combo", false):
		parts.append("连击")
	if effect.has("revive_chance"):
		parts.append("复活" + str(int(effect["revive_chance"] * 100)) + "%")
	if effect.has("field_sync"):
		parts.append("场地同步")
	return "[" + " ".join(parts) + "]"


func _on_back():
	Global.play_sfx("click")
	Global.change_scene("res://Main.tscn")

# ==================== 扫码导入 ====================

var _scanner_node: Node = null

## 获取扫码桥接节点（懒初始化）
func _get_scanner_node() -> Node:
	if _scanner_node == null:
		_setup_scanner()
	return _scanner_node

## 初始化扫码桥接节点（CardScanner Android插件）
func _setup_scanner() -> void:
	if _scanner_node != null:
		return
	var script_path = "res://addons/CardScanner/CardScannerNode.gd"
	if not ResourceLoader.exists(script_path):
		push_warning("[CardGallery] 扫码桥接脚本不存在: " + script_path)
		return
	var scanner = Node.new()
	scanner.set_script(load(script_path))
	scanner.name = "CardScannerBridge"
	add_child(scanner)
	_scanner_node = scanner
	scanner.scan_success.connect(_on_scan_success)
	scanner.scan_cancelled.connect(_on_scan_cancelled)
	scanner.scan_error.connect(_on_scan_error)

## 点击「扫码导入」按钮
func _on_scan_import() -> void:
	if _scanner_node == null:
		_setup_scanner()
	if _scanner_node == null:
		_show_share_toast("⚠️ 扫码桥接未初始化")
		return
	# 相机检查（Android插件不可用时回退提示）
	if _scanner_node.has_method("isCameraAvailable"):
		if not _scanner_node.isCameraAvailable():
			_show_share_toast("⚠️ 设备无可用相机")
			return
	if _scanner_node.has_method("startScan"):
		_scanner_node.startScan()
		_show_share_toast("📷 正在启动扫码...")
	else:
		_show_share_toast("⚠️ 扫码插件不可用（仅Android支持）")

## 扫码成功回调
func _on_scan_success(content: String) -> void:
	print("[CardGallery] 扫码结果: ", content)
	var trimmed = content.strip_edges()
	if trimmed == "":
		_show_share_toast("❌ 二维码内容为空")
		return
	# 反解压缩卡牌码
	var card = _decompress_card(trimmed)
	if card.is_empty():
		_show_share_toast("❌ 无法识别的卡牌码: " + trimmed)
		return
	# 弹窗预览卡牌信息，确认后导入
	_show_scan_preview_dialog(card)


## 扫码预览弹窗（确认后才导入）
func _show_scan_preview_dialog(card: Dictionary) -> void:
	# 弹窗遮罩
	var overlay = ColorRect.new()
	overlay.name = "ScanPreviewOverlay"
	overlay.color = Color(0.0, 0.0, 0.0, 0.7)
	overlay.anchor_left = 0.0
	overlay.anchor_top = 0.0
	overlay.anchor_right = 1.0
	overlay.anchor_bottom = 1.0
	overlay.mouse_filter = MOUSE_FILTER_STOP
	add_child(overlay)
	
	# 面板
	var panel = Panel.new()
	panel.name = "ScanPreviewPanel"
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Global.current.topbar_bg
	panel_style.border_width_left = 3
	panel_style.border_width_right = 3
	panel_style.border_width_top = 3
	panel_style.border_width_bottom = 3
	panel_style.border_color = Color("#4CAF50")
	panel_style.corner_radius_top_left = 20
	panel_style.corner_radius_top_right = 20
	panel_style.corner_radius_bottom_left = 20
	panel_style.corner_radius_bottom_right = 20
	panel.add_theme_stylebox_override("panel", panel_style)
	
	# 面板居中
	var pw = Global.pw(1.0)
	var ph = Global.ph(1.0)
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -pw * 0.38
	panel.offset_top = -ph * 0.35
	panel.offset_right = pw * 0.38
	panel.offset_bottom = ph * 0.35
	panel.mouse_filter = MOUSE_FILTER_STOP
	overlay.add_child(panel)
	
	# 面板内部 VBox
	var vbox = VBoxContainer.new()
	vbox.anchor_left = 0.0
	vbox.anchor_top = 0.0
	vbox.anchor_right = 1.0
	vbox.anchor_bottom = 1.0
	vbox.offset_left = 20
	vbox.offset_top = 20
	vbox.offset_right = -20
	vbox.offset_bottom = -20
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)
	
	# 标题：扫码预览
	var title_bar = HBoxContainer.new()
	title_bar.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	vbox.add_child(title_bar)
	
	var title_label = Label.new()
	title_label.text = "📄 扫码预览"
	title_label.add_theme_font_size_override("font_size", 48)
	title_label.add_theme_color_override("font_color", Color("#4CAF50"))
	title_label.size_flags_horizontal = SIZE_EXPAND
	title_bar.add_child(title_label)
	
	# 卡牌信息区域（带滚动）
	var info_scroll = ScrollContainer.new()
	info_scroll.size_flags_vertical = SIZE_EXPAND | SIZE_FILL
	info_scroll.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	info_scroll.custom_minimum_size = Vector2(0, 0)
	vbox.add_child(info_scroll)
	
	var info_vbox = VBoxContainer.new()
	info_vbox.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	info_vbox.add_theme_constant_override("separation", 6)
	info_scroll.add_child(info_vbox)
	
	# 卡名
	var card_name = card.get("name", card.get("card_name", "未命名卡牌"))
	var name_label = Label.new()
	# 元素图标
	var main_element = CardManager.get_card_element(card)
	var elem_icon = ""
	match main_element:
		"火": elem_icon = "🔥"
		"水": elem_icon = "💧"
		"风": elem_icon = "🌪️"
		"暗": elem_icon = "🌑"
		"光": elem_icon = "☀️"
	name_label.text = elem_icon + " " + card_name
	name_label.add_theme_font_size_override("font_size", 52)
	name_label.add_theme_color_override("font_color", Global.current.title)
	info_vbox.add_child(name_label)
	
	# 品质 + 星级
	var quality = card.get("quality", "—")
	var star = card.get("star", 0)
	var q_label = Label.new()
	var display_q = quality
	if " ~ " in quality:
		var q_parts = quality.split(" ~ ")
		display_q = q_parts[q_parts.size() - 1].strip_edges()
	q_label.text = "⭐" + str(star) + "  " + display_q
	q_label.add_theme_font_size_override("font_size", 40)
	q_label.add_theme_color_override("font_color", _get_quality_color(display_q))
	info_vbox.add_child(q_label)
	
	# 属性
	var attack = card.get("atk", card.get("attack", 0))
	var health = card.get("hp", card.get("health", 0))
	var cost = card.get("cost", card.get("energy_cost", 0))
	var stats_label = Label.new()
	stats_label.text = "⚔" + str(attack) + "  ❤" + str(health) + "  ⚡" + str(cost)
	stats_label.add_theme_font_size_override("font_size", 44)
	stats_label.add_theme_color_override("font_color", Global.current.btn_text)
	info_vbox.add_child(stats_label)
	
	# 字段
	var fields = card.get("fields", [])
	if fields.size() > 0:
		var field_str := ""
		for f in fields:
			if f != "":
				field_str += "[" + f + "] "
		if field_str != "":
			var f_label = Label.new()
			f_label.text = field_str
			f_label.add_theme_font_size_override("font_size", 38)
			f_label.add_theme_color_override("font_color", Global.current.btn_text)
			info_vbox.add_child(f_label)
	
	# 描述
	var desc = card.get("description", card.get("desc", ""))
	if desc != "":
		var d_label = Label.new()
		d_label.text = desc
		d_label.add_theme_font_size_override("font_size", 36)
		d_label.add_theme_color_override("font_color", Color("#b0b0c0"))
		d_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info_vbox.add_child(d_label)
	
	# 效果
	var effects = card.get("effects", [])
	if effects.size() > 0:
		var eff_title = Label.new()
		eff_title.text = "【效果】"
		eff_title.add_theme_font_size_override("font_size", 36)
		eff_title.add_theme_color_override("font_color", Color("#f9d371"))
		info_vbox.add_child(eff_title)
		for eff in effects:
			var eff_desc = ""
			if eff is Dictionary:
				eff_desc = Global.get_effect_desc(eff)
			elif eff is String:
				var comp = Global.get_circuit_by_id(eff)
				if comp and comp.has("name"):
					eff_desc = comp["name"]
				else:
					eff_desc = eff
			if eff_desc != "":
				var e_label = Label.new()
				e_label.text = "  • " + eff_desc
				e_label.add_theme_font_size_override("font_size", 34)
				e_label.add_theme_color_override("font_color", Color("#d0d0e0"))
				e_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				info_vbox.add_child(e_label)
	
	# 底部按钮区域
	var btn_hbox = HBoxContainer.new()
	btn_hbox.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	btn_hbox.custom_minimum_size = Vector2(0, Global.ph(0.07))
	vbox.add_child(btn_hbox)
	
	# 取消按钮
	var cancel_btn = Button.new()
	cancel_btn.text = "取消"
	cancel_btn.add_theme_font_size_override("font_size", 40)
	cancel_btn.size_flags_horizontal = SIZE_EXPAND
	cancel_btn.size_flags_vertical = SIZE_FILL
	var cs = StyleBoxFlat.new()
	cs.bg_color = Color("#555555")
	cs.border_width_left = 2
	cs.border_width_right = 2
	cs.border_width_top = 2
	cs.border_width_bottom = 2
	cs.border_color = Color("#777777")
	cs.corner_radius_top_left = 12
	cs.corner_radius_top_right = 12
	cs.corner_radius_bottom_left = 12
	cs.corner_radius_bottom_right = 12
	cancel_btn.add_theme_stylebox_override("normal", cs)
	cancel_btn.add_theme_color_override("font_color", Color("#cccccc"))
	cancel_btn.pressed.connect(func():
		overlay.queue_free()
		_show_share_toast("已取消导入"))
	btn_hbox.add_child(cancel_btn)
	
	# 间隔
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(20, 0)
	btn_hbox.add_child(spacer)
	
	# 确认导入按钮
	var confirm_btn = Button.new()
	confirm_btn.text = "✅ 确认导入"
	confirm_btn.add_theme_font_size_override("font_size", 40)
	confirm_btn.size_flags_horizontal = SIZE_EXPAND
	confirm_btn.size_flags_vertical = SIZE_FILL
	var cbs = StyleBoxFlat.new()
	cbs.bg_color = Color("#2E7D32")
	cbs.border_width_left = 2
	cbs.border_width_right = 2
	cbs.border_width_top = 2
	cbs.border_width_bottom = 2
	cbs.border_color = Color("#4CAF50")
	cbs.corner_radius_top_left = 12
	cbs.corner_radius_top_right = 12
	cbs.corner_radius_bottom_left = 12
	cbs.corner_radius_bottom_right = 12
	confirm_btn.add_theme_stylebox_override("normal", cbs)
	confirm_btn.add_theme_color_override("font_color", Color("#FFFFFF"))
	confirm_btn.pressed.connect(func():
		CardManager.add_card(card)
		overlay.queue_free()
		_show_share_toast("✅ 卡牌导入成功: " + card_name)
		_refresh_list())
	btn_hbox.add_child(confirm_btn)

## 扫码取消回调
func _on_scan_cancelled() -> void:
	print("[CardGallery] 用户取消扫码")
	_show_share_toast("已取消扫码")

## 扫码出错回调
func _on_scan_error(error_msg: String) -> void:
	print("[CardGallery] 扫码错误: ", error_msg)
	_show_share_toast("❌ 扫码失败: " + error_msg)

func _apply_theme_custom():
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
	_setup_long_press()
