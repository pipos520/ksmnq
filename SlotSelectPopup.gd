extends CanvasLayer
class_name SlotSelectPopup

## 场景位选择弹窗 —— 展示场地卡槽（带卡牌预览），选择一个空位或目标

var _battle_manager: BattleManager = null
var _is_enemy: bool = false       # true=显示敌方场地, false=显示己方场地
var _filter_empty: bool = false    # true=只显示空格（召唤用）, false=显示有卡牌的（攻击用）
var _on_selected: Callable = Callable()
var _on_cancel: Callable = Callable()
var _title_text: String = ""

var _slot_btns: Array = []


func _ready():
	layer = 210
	process_mode = PROCESS_MODE_ALWAYS
	
	# 半透明遮罩（点击关闭）
	var overlay = ColorRect.new()
	overlay.name = "Overlay"
	overlay.color = Color(0.0, 0.0, 0.0, 0.6)
	overlay.anchor_left = 0.0; overlay.anchor_top = 0.0
	overlay.anchor_right = 1.0; overlay.anchor_bottom = 1.0
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.gui_input.connect(_on_overlay_input)
	add_child(overlay)
	
	# ===== 弹窗面板 =====
	var panel = Panel.new()
	panel.name = "SlotPanel"
	var panel_s = StyleBoxFlat.new()
	panel_s.bg_color = Color(0.06, 0.04, 0.12)
	panel_s.border_width_left = 3; panel_s.border_width_right = 3
	panel_s.border_width_top = 3; panel_s.border_width_bottom = 3
	panel_s.border_color = Color(0.6, 0.4, 0.8, 0.9)
	panel_s.corner_radius_top_left = 16; panel_s.corner_radius_top_right = 16
	panel_s.corner_radius_bottom_left = 16; panel_s.corner_radius_bottom_right = 16
	panel.add_theme_stylebox_override("panel", panel_s)
	
	panel.anchor_left = 0.5; panel.anchor_top = 0.5
	panel.anchor_right = 0.5; panel.anchor_bottom = 0.5
	panel.offset_left = -Global.pw(0.40)
	panel.offset_right = Global.pw(0.40)
	panel.offset_top = -Global.ph(0.25)
	panel.offset_bottom = Global.ph(0.25)
	add_child(panel)
	
	# VBox
	var vbox = VBoxContainer.new()
	vbox.anchor_left = 0.0; vbox.anchor_top = 0.0
	vbox.anchor_right = 1.0; vbox.anchor_bottom = 1.0
	vbox.offset_left = Global.pw(0.03)
	vbox.offset_top = Global.ph(0.02)
	vbox.offset_right = Global.pw(-0.03)
	vbox.offset_bottom = Global.ph(-0.02)
	panel.add_child(vbox)
	
	# ===== 标题 =====
	var title_lbl = Label.new()
	title_lbl.name = "TitleLabel"
	title_lbl.add_theme_font_size_override("font_size", 60)
	title_lbl.add_theme_color_override("font_color", Color("#e8d5b7"))
	title_lbl.add_theme_constant_override("shadow_offset_x", 2)
	title_lbl.add_theme_constant_override("shadow_offset_y", 2)
	title_lbl.add_theme_color_override("font_shadow_color", Color("#000000"))
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.custom_minimum_size = Vector2(0, Global.ph(0.06))
	vbox.add_child(title_lbl)
	
	# 分隔线
	var sep = ColorRect.new()
	sep.color = Color(0.4, 0.3, 0.5, 0.4)
	sep.custom_minimum_size = Vector2(0, 2)
	sep.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
	vbox.add_child(sep)
	
	# ===== 卡槽区域 =====
	var slots_container = VBoxContainer.new()
	slots_container.size_flags_vertical = Control.SIZE_EXPAND | Control.SIZE_FILL
	slots_container.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
	slots_container.add_theme_constant_override("separation", Global.ph(0.01))
	vbox.add_child(slots_container)
	
	# 卡槽行（5个分两行，上行3个下行2个，或都用HBoxFlow）
	# 用一个HBox一行5个
	var slot_row = HBoxContainer.new()
	slot_row.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
	slot_row.size_flags_vertical = Control.SIZE_EXPAND | Control.SIZE_FILL
	slot_row.add_theme_constant_override("separation", Global.pw(0.02))
	slot_row.alignment = BoxContainer.ALIGNMENT_CENTER
	slots_container.add_child(slot_row)
	
	# 计算卡牌大小
	var slot_w = Global.pw(0.12)
	var slot_h = slot_w * 1.4
	
	for i in range(5):
		var slot_btn = Button.new()
		slot_btn.name = "SlotBtn_" + str(i)
		slot_btn.custom_minimum_size = Vector2(slot_w, slot_h)
		slot_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		slot_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slot_btn.text = ""
		slot_btn.pressed.connect(_on_slot_pressed.bind(i))
		
		# 子Label布局（同手牌卡牌样式）
		_add_card_labels(slot_btn)
		
		slot_row.add_child(slot_btn)
		_slot_btns.append(slot_btn)
	
	# ===== 底部按钮 =====
	var btn_row = HBoxContainer.new()
	btn_row.custom_minimum_size = Vector2(0, Global.ph(0.07))
	btn_row.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", Global.pw(0.05))
	vbox.add_child(btn_row)
	
	var cancel_btn = Button.new()
	cancel_btn.text = "✕ 取消"
	cancel_btn.add_theme_font_size_override("font_size", 40)
	var cs = StyleBoxFlat.new()
	cs.bg_color = Color(0.2, 0.12, 0.20)
	cs.border_width_left = 2; cs.border_width_right = 2
	cs.border_width_top = 2; cs.border_width_bottom = 2
	cs.border_color = Color(0.5, 0.3, 0.5, 0.8)
	cs.corner_radius_top_left = 8; cs.corner_radius_top_right = 8
	cs.corner_radius_bottom_left = 8; cs.corner_radius_bottom_right = 8
	cs.content_margin_left = 20; cs.content_margin_right = 20
	cancel_btn.add_theme_stylebox_override("normal", cs)
	cancel_btn.add_theme_stylebox_override("hover", cs)
	cancel_btn.add_theme_stylebox_override("pressed", cs)
	cancel_btn.add_theme_color_override("font_color", Color("#a0a0b0"))
	cancel_btn.pressed.connect(_on_cancel_pressed)
	btn_row.add_child(cancel_btn)
	
	hide()


## 添加卡牌子Label
func _add_card_labels(btn: Button) -> void:
	# 元素-左上角
	var elem = Label.new()
	elem.name = "ElemLabel"
	elem.anchor_left = 0.0; elem.anchor_top = 0.0
	elem.anchor_right = 0.0; elem.anchor_bottom = 0.0
	elem.offset_left = 2; elem.offset_top = 1
	elem.offset_right = 25; elem.offset_bottom = 25
	elem.add_theme_font_size_override("font_size", 28)
	elem.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	elem.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	btn.add_child(elem)
	
	# 费用-右上角
	var cost = Label.new()
	cost.name = "CostLabel"
	cost.anchor_left = 0.0; cost.anchor_top = 0.0
	cost.anchor_right = 1.0; cost.anchor_bottom = 0.0
	cost.offset_left = -25; cost.offset_top = 1
	cost.offset_right = -2; cost.offset_bottom = 25
	cost.add_theme_font_size_override("font_size", 30)
	cost.add_theme_color_override("font_color", Color("#f9d371"))
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cost.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	btn.add_child(cost)
	
	# 中间内容
	var center = Label.new()
	center.name = "CenterLabel"
	center.anchor_left = 0.0; center.anchor_top = 0.0
	center.anchor_right = 1.0; center.anchor_bottom = 1.0
	center.offset_left = 2; center.offset_top = 24
	center.offset_right = -2; center.offset_bottom = -24
	center.add_theme_font_size_override("font_size", 26)
	center.add_theme_color_override("font_color", Color("#e8d5b7"))
	center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	center.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn.add_child(center)
	
	# 攻击-左下角
	var atk = Label.new()
	atk.name = "AtkLabel"
	atk.anchor_left = 0.0; atk.anchor_top = 0.0
	atk.anchor_right = 0.0; atk.anchor_bottom = 1.0
	atk.offset_left = 2; atk.offset_top = -24
	atk.offset_right = 25; atk.offset_bottom = -2
	atk.add_theme_font_size_override("font_size", 28)
	atk.add_theme_color_override("font_color", Color("#e74c3c"))
	atk.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	atk.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	btn.add_child(atk)
	
	# 生命-右下角
	var hp = Label.new()
	hp.name = "HpLabel"
	hp.anchor_left = 0.0; hp.anchor_top = 0.0
	hp.anchor_right = 1.0; hp.anchor_bottom = 1.0
	hp.offset_left = -25; hp.offset_top = -24
	hp.offset_right = -2; hp.offset_bottom = -2
	hp.add_theme_font_size_override("font_size", 28)
	hp.add_theme_color_override("font_color", Color("#2ecc71"))
	hp.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hp.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	btn.add_child(hp)


## 显示选择弹窗
func show_select(battle_manager: BattleManager, is_enemy: bool, filter_empty: bool, title: String, on_selected: Callable, on_cancel: Callable = Callable()) -> void:
	_battle_manager = battle_manager
	_is_enemy = is_enemy
	_filter_empty = filter_empty
	_title_text = title
	_on_selected = on_selected
	_on_cancel = on_cancel
	
	if _battle_manager == null:
		close()
		return
	
	# 设置标题
	var title_lbl = get_node_or_null("SlotPanel/TitleLabel") as Label
	if title_lbl:
		title_lbl.text = title
	
	# 刷新卡槽
	_refresh_slots()
	
	show()


func _refresh_slots() -> void:
	if _battle_manager == null:
		return
	
	var player = _battle_manager.player_opponent if _is_enemy else _battle_manager.player_self
	var max_slots = player.max_field_size
	
	var empty_bg = Color(0.2, 0.5, 0.8, 0.3)  # 蓝色
	var enemy_bg = Color(0.7, 0.2, 0.2, 0.3)  # 红色
	
	for i in range(_slot_btns.size()):
		var btn = _slot_btns[i] as Button
		if btn == null:
			continue
		
		var elem_lbl = btn.get_node_or_null("ElemLabel") as Label
		var cost_lbl = btn.get_node_or_null("CostLabel") as Label
		var center_lbl = btn.get_node_or_null("CenterLabel") as Label
		var atk_lbl = btn.get_node_or_null("AtkLabel") as Label
		var hp_lbl = btn.get_node_or_null("HpLabel") as Label
		
		if i < max_slots and player.field[i] != null:
			# 有卡牌
			var card = player.field[i] as BattleCard
			if card == null or not card.is_alive():
				# 空卡槽或死亡
				_set_slot_empty(btn, elem_lbl, cost_lbl, center_lbl, atk_lbl, hp_lbl, empty_bg if not _is_enemy else enemy_bg)
				btn.disabled = _filter_empty  # 召唤时只选空格，这里disabled
				continue
			
			# 显示卡牌信息
			var element_icon = ""
			match card.element:
				"火": element_icon = "🔥"
				"水": element_icon = "💧"
				"风": element_icon = "🌪️"
				"地": element_icon = "⛰️"
				"光": element_icon = "✨"
				"暗": element_icon = "🌑"
			if elem_lbl: elem_lbl.text = element_icon
			if cost_lbl: cost_lbl.text = "⚡" + str(card.base_cost)
			if center_lbl: center_lbl.text = card.card_name
			if atk_lbl: atk_lbl.text = "⚔️" + str(card.current_atk)
			if hp_lbl: hp_lbl.text = "❤️" + str(card.current_hp)
			
			# 可点击样式
			var s = StyleBoxFlat.new()
			s.bg_color = Color(0.18, 0.14, 0.25)
			s.border_width_left = 2; s.border_width_right = 2
			s.border_width_top = 2; s.border_width_bottom = 2
			s.border_color = Color(0.4, 0.3, 0.5, 0.6)
			s.corner_radius_top_left = 6; s.corner_radius_top_right = 6
			s.corner_radius_bottom_left = 6; s.corner_radius_bottom_right = 6
			btn.add_theme_stylebox_override("normal", s)
			btn.add_theme_stylebox_override("hover", s)
			btn.add_theme_stylebox_override("pressed", s)
			
			# 如果是召唤模式（filter_empty=true），有卡牌的卡槽不可选
			# 如果是攻击模式（filter_empty=false），有卡牌的卡槽可选
			btn.disabled = _filter_empty
		else:
			# 空卡槽
			_set_slot_empty(btn, elem_lbl, cost_lbl, center_lbl, atk_lbl, hp_lbl, empty_bg if not _is_enemy else enemy_bg)
			# 召唤模式：空格可选；攻击模式：空格不可选
			btn.disabled = not _filter_empty


func _set_slot_empty(btn: Button, elem_lbl, cost_lbl, center_lbl, atk_lbl, hp_lbl, bg_color: Color) -> void:
	if elem_lbl: elem_lbl.text = ""
	if cost_lbl: cost_lbl.text = ""
	if center_lbl: center_lbl.text = "空"
	if atk_lbl: atk_lbl.text = ""
	if hp_lbl: hp_lbl.text = ""
	
	var s = StyleBoxFlat.new()
	s.bg_color = bg_color
	s.border_width_left = 2; s.border_width_right = 2
	s.border_width_top = 2; s.border_width_bottom = 2
	s.border_color = Color(1.0, 1.0, 1.0, 0.15)
	s.corner_radius_top_left = 6; s.corner_radius_top_right = 6
	s.corner_radius_bottom_left = 6; s.corner_radius_bottom_right = 6
	btn.add_theme_stylebox_override("normal", s)
	btn.add_theme_stylebox_override("hover", s)
	btn.add_theme_stylebox_override("pressed", s)


func _on_slot_pressed(slot_index: int) -> void:
	if _on_selected.is_valid():
		_on_selected.call(slot_index)
	close()


func _on_cancel_pressed() -> void:
	if _on_cancel.is_valid():
		_on_cancel.call()
	close()


func _on_overlay_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _on_cancel.is_valid():
			_on_cancel.call()
		close()


func close() -> void:
	hide()
	queue_free()