extends CanvasLayer
class_name DeckSearchPopup

## 卡组检索弹窗 — 可滑动列表显示卡牌，支持字段筛选、长按详情、多选

var _on_selected: Callable = Callable()  # 回调：func(selected_cards: Array)
var _selected_indices: Array = []
var _max_select: int = 1
var _all_cards: Array = []  # 原始列表
var _card_btns: Array = []  # 行按钮列表

func _ready():
	layer = 220
	process_mode = PROCESS_MODE_ALWAYS

## 显示检索弹窗
## cards: 卡牌列表（已筛选）
## title: 标题
## max_select: 最大选择张数（0=不限）
## on_selected: 回调函数，接收选中的卡牌数组
func show_search(cards: Array, title: String, max_select: int, on_selected: Callable) -> void:
	_all_cards = cards.duplicate()
	_max_select = max_select
	_on_selected = on_selected
	_selected_indices = []
	
	# 遮罩
	var overlay = ColorRect.new()
	overlay.name = "DeckSearchOverlay"
	overlay.color = Color(0.0, 0.0, 0.0, 0.75)
	overlay.anchor_left = 0.0; overlay.anchor_top = 0.0
	overlay.anchor_right = 1.0; overlay.anchor_bottom = 1.0
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			close()
	)
	add_child(overlay)
	
	# 面板
	var panel = Panel.new()
	panel.name = "DeckSearchPanel"
	var ps = StyleBoxFlat.new()
	ps.bg_color = Color(0.06, 0.04, 0.12)
	ps.border_width_left = 3; ps.border_width_right = 3
	ps.border_width_top = 3; ps.border_width_bottom = 3
	ps.border_color = Color(0.6, 0.4, 0.8, 0.9)
	ps.corner_radius_top_left = 16; ps.corner_radius_top_right = 16
	ps.corner_radius_bottom_left = 16; ps.corner_radius_bottom_right = 16
	panel.add_theme_stylebox_override("panel", ps)
	panel.anchor_left = 0.0; panel.anchor_top = 0.0
	panel.anchor_right = 0.0; panel.anchor_bottom = 0.0
	panel.offset_left = Global.pw(0.08)
	panel.offset_top = Global.ph(0.08)
	panel.offset_right = Global.pw(-0.08)
	panel.offset_bottom = Global.ph(0.88)
	overlay.add_child(panel)
	
	# 标题
	var title_lbl = Label.new()
	title_lbl.name = "SearchTitle"
	title_lbl.text = title + "  (" + str(cards.size()) + "张)"
	title_lbl.add_theme_font_size_override("font_size", 50)
	title_lbl.add_theme_color_override("font_color", Color("#e8d5b7"))
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.anchor_left = 0.0; title_lbl.anchor_top = 0.0
	title_lbl.anchor_right = 1.0; title_lbl.anchor_bottom = 0.0
	title_lbl.offset_left = Global.pw(0.05); title_lbl.offset_top = Global.ph(0.015)
	title_lbl.offset_right = Global.pw(-0.05); title_lbl.offset_bottom = Global.ph(0.07)
	panel.add_child(title_lbl)
	
	# 提示标签
	var hint = Label.new()
	var hint_text = "点击选择卡牌"
	if max_select > 1:
		hint_text = "选择 " + str(max_select) + " 张（点击已选可取消）"
	hint.text = hint_text
	hint.add_theme_font_size_override("font_size", 30)
	hint.add_theme_color_override("font_color", Color("#a0a0b0"))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.anchor_left = 0.0; hint.anchor_top = 0.0
	hint.anchor_right = 1.0; hint.anchor_bottom = 0.0
	hint.offset_left = Global.pw(0.05); hint.offset_top = Global.ph(0.07)
	hint.offset_right = Global.pw(-0.05); hint.offset_bottom = Global.ph(0.095)
	panel.add_child(hint)
	
	# 分割线
	var line = ColorRect.new()
	line.color = Color(0.4, 0.3, 0.5, 0.3)
	line.anchor_left = 0.0; line.anchor_top = 0.0
	line.anchor_right = 1.0; line.anchor_bottom = 0.0
	line.offset_left = Global.pw(0.05); line.offset_top = Global.ph(0.095)
	line.offset_right = Global.pw(-0.05); line.offset_bottom = Global.ph(0.097)
	panel.add_child(line)
	
	# 滚动列表
	var scroll = ScrollContainer.new()
	scroll.anchor_left = 0.0; scroll.anchor_top = 0.0
	scroll.anchor_right = 1.0; scroll.anchor_bottom = 1.0
	scroll.offset_left = Global.pw(0.03); scroll.offset_top = Global.ph(0.10)
	scroll.offset_right = Global.pw(-0.03); scroll.offset_bottom = Global.ph(-0.12)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	
	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
	vbox.custom_minimum_size = Vector2(Global.pw(0.80), 0)
	scroll.add_child(vbox)
	
	# 构建卡牌行
	var row_idx := 0
	for card in cards:
		var c = card as BattleCard
		if c == null:
			continue
		
		var row = Panel.new()
		row.name = "CardRow_" + str(row_idx)
		var rs = StyleBoxFlat.new()
		rs.bg_color = Color(0.15, 0.12, 0.20) if row_idx % 2 == 0 else Color(0.11, 0.09, 0.16)
		rs.corner_radius_top_left = 6; rs.corner_radius_top_right = 6
		rs.corner_radius_bottom_left = 6; rs.corner_radius_bottom_right = 6
		row.add_theme_stylebox_override("panel", rs)
		row.custom_minimum_size = Vector2(0, Global.ph(0.065))
		row.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
		vbox.add_child(row)
		
		# 行内容 HBox
		var hbox = HBoxContainer.new()
		hbox.anchor_left = 0.0; hbox.anchor_top = 0.0
		hbox.anchor_right = 1.0; hbox.anchor_bottom = 1.0
		hbox.offset_left = Global.pw(0.02)
		row.add_child(hbox)
		
		# 选中标记
		var check_lbl = Label.new()
		check_lbl.name = "CheckLabel"
		check_lbl.text = ""
		check_lbl.add_theme_font_size_override("font_size", 40)
		check_lbl.add_theme_color_override("font_color", Color("#a0a0b0"))
		check_lbl.custom_minimum_size = Vector2(Global.pw(0.06), 0)
		check_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hbox.add_child(check_lbl)
		
		# 品质颜色
		var q_color = Color("#e8d5b7")
		match c.quality:
			"传说": q_color = Color("#f9d371")
			"史诗": q_color = Color("#c084fc")
			"稀有": q_color = Color("#60a5fa")
		
		# 元素图标
		var elem_icon = ""
		match c.element:
			"火": elem_icon = ""
			"水": elem_icon = ""
			"风": elem_icon = ""
			"地": elem_icon = ""
			"光": elem_icon = ""
			"暗": elem_icon = ""
		var elem_lbl = Label.new()
		elem_lbl.text = elem_icon
		elem_lbl.add_theme_font_size_override("font_size", 36)
		elem_lbl.custom_minimum_size = Vector2(Global.pw(0.06), 0)
		elem_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hbox.add_child(elem_lbl)
		
		# 卡牌名称
		var name_lbl = Label.new()
		name_lbl.text = c.get_display_name()
		name_lbl.add_theme_font_size_override("font_size", 38)
		name_lbl.add_theme_color_override("font_color", q_color)
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND
		name_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
		hbox.add_child(name_lbl)
		
		# 费用
		var cost_lbl = Label.new()
		cost_lbl.text = "" + str(c.base_cost)
		cost_lbl.add_theme_font_size_override("font_size", 34)
		cost_lbl.add_theme_color_override("font_color", Color("#f9d371"))
		cost_lbl.custom_minimum_size = Vector2(Global.pw(0.07), 0)
		cost_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hbox.add_child(cost_lbl)
		
		# 攻防
		var stats_lbl = Label.new()
		stats_lbl.text = "" + str(c.base_atk) + " " + str(c.base_hp)
		stats_lbl.add_theme_font_size_override("font_size", 34)
		stats_lbl.add_theme_color_override("font_color", Color("#7a8a7a"))
		stats_lbl.custom_minimum_size = Vector2(Global.pw(0.18), 0)
		stats_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		hbox.add_child(stats_lbl)
		
		# 字段标签
		if c.fields.size() > 0:
			var field_lbl = Label.new()
			field_lbl.text = "[" + c.fields[0] + "]"
			field_lbl.add_theme_font_size_override("font_size", 28)
			field_lbl.add_theme_color_override("font_color", Color("#5a7a8a"))
			field_lbl.custom_minimum_size = Vector2(Global.pw(0.12), 0)
			field_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			hbox.add_child(field_lbl)
		
		# 点击事件
		var card_ref = c
		var row_ref = row
		var check_ref = check_lbl
		var idx = row_idx
		
		row.gui_input.connect(func(event: InputEvent, _card: BattleCard = card_ref, _idx: int = idx, _check: Label = check_ref, _row: Panel = row_ref):
			if event is InputEventMouseButton:
				if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
					# 启动长按计时
					_row.set_meta("press_time", Time.get_ticks_msec() / 1000.0)
					_row.set_meta("longpress_triggered", false)
				elif not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
					if not _row.get_meta("longpress_triggered", false):
						# 点击选择/取消
						_toggle_selection(_idx, _check)
		)
		
		# 长按检测
		row.set_meta("press_time", 0.0)
		row.set_meta("longpress_triggered", false)
		row.set_meta("card_ref", card_ref)
		
		_card_btns.append(row)
		row_idx += 1
	
	# 长按检测定时器
	var check_timer = Timer.new()
	check_timer.wait_time = 0.1
	check_timer.one_shot = false
	check_timer.timeout.connect(func():
		for btn in _card_btns:
			var press_time = btn.get_meta("press_time", 0.0)
			var triggered = btn.get_meta("longpress_triggered", false)
			if press_time > 0 and not triggered:
				var now = Time.get_ticks_msec() / 1000.0
				if now - press_time >= 0.4:
					btn.set_meta("longpress_triggered", true)
					btn.set_meta("press_time", 0.0)
					var c = btn.get_meta("card_ref", null) as BattleCard
					if c:
						var popup = CardDetailPopup.new()
						add_child(popup)
						popup.show_card(c, "view")
	)
	add_child(check_timer)
	check_timer.start()
	
	# 底部按钮
	var bottom_hbox = HBoxContainer.new()
	bottom_hbox.anchor_left = 0.0; bottom_hbox.anchor_top = 1.0
	bottom_hbox.anchor_right = 1.0; bottom_hbox.anchor_bottom = 1.0
	bottom_hbox.offset_left = Global.pw(0.10); bottom_hbox.offset_top = Global.ph(-0.11)
	bottom_hbox.offset_right = Global.pw(-0.10); bottom_hbox.offset_bottom = Global.ph(-0.01)
	bottom_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom_hbox.add_theme_constant_override("separation", Global.pw(0.05))
	panel.add_child(bottom_hbox)
	
	var confirm_btn = Button.new()
	confirm_btn.text = "确认选择"
	confirm_btn.add_theme_font_size_override("font_size", 40)
	var cs = StyleBoxFlat.new()
	cs.bg_color = Color(0.2, 0.3, 0.2)
	cs.border_width_left = 2; cs.border_width_right = 2
	cs.border_width_top = 2; cs.border_width_bottom = 2
	cs.border_color = Color(0.3, 0.6, 0.3, 0.8)
	cs.corner_radius_top_left = 8; cs.corner_radius_top_right = 8
	cs.corner_radius_bottom_left = 8; cs.corner_radius_bottom_right = 8
	cs.content_margin_left = 20; cs.content_margin_right = 20
	confirm_btn.add_theme_stylebox_override("normal", cs)
	confirm_btn.add_theme_stylebox_override("hover", cs)
	confirm_btn.add_theme_stylebox_override("pressed", cs)
	confirm_btn.add_theme_color_override("font_color", Color("#a0d0a0"))
	confirm_btn.pressed.connect(_on_confirm)
	bottom_hbox.add_child(confirm_btn)
	
	var cancel_btn = Button.new()
	cancel_btn.text = "取消"
	cancel_btn.add_theme_font_size_override("font_size", 40)
	var cs2 = StyleBoxFlat.new()
	cs2.bg_color = Color(0.2, 0.12, 0.20)
	cs2.border_width_left = 2; cs2.border_width_right = 2
	cs2.border_width_top = 2; cs2.border_width_bottom = 2
	cs2.border_color = Color(0.5, 0.3, 0.5, 0.8)
	cs2.corner_radius_top_left = 8; cs2.corner_radius_top_right = 8
	cs2.corner_radius_bottom_left = 8; cs2.corner_radius_bottom_right = 8
	cs2.content_margin_left = 20; cs2.content_margin_right = 20
	cancel_btn.add_theme_stylebox_override("normal", cs2)
	cancel_btn.add_theme_stylebox_override("hover", cs2)
	cancel_btn.add_theme_stylebox_override("pressed", cs2)
	cancel_btn.add_theme_color_override("font_color", Color("#a0a0b0"))
	cancel_btn.pressed.connect(_on_cancel)
	bottom_hbox.add_child(cancel_btn)
	
	show()


func _toggle_selection(idx: int, check_lbl: Label) -> void:
	if idx in _selected_indices:
		_selected_indices.erase(idx)
		check_lbl.text = ""
		check_lbl.add_theme_color_override("font_color", Color("#a0a0b0"))
	else:
		if _max_select > 0 and _selected_indices.size() >= _max_select:
			# 已满，替换第一个
			var old_idx = _selected_indices.pop_front()
			var old_row = _card_btns[old_idx]
			if old_row:
				var old_check = old_row.get_node_or_null("CheckLabel")
				if old_check:
					old_check.text = ""
					old_check.add_theme_color_override("font_color", Color("#a0a0b0"))
		_selected_indices.append(idx)
		check_lbl.text = ""
		check_lbl.add_theme_color_override("font_color", Color("#60d060"))


func _on_confirm() -> void:
	var selected_cards := []
	for idx in _selected_indices:
		if idx >= 0 and idx < _all_cards.size():
			selected_cards.append(_all_cards[idx])
	if _on_selected.is_valid():
		_on_selected.call(selected_cards)
	close()


func _on_cancel() -> void:
	if _on_selected.is_valid():
		_on_selected.call([])  # 空数组表示取消
	close()


func close() -> void:
	hide()
	queue_free()