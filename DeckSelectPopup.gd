extends CanvasLayer
class_name DeckSelectPopup

# ============================================================
#  卡组选择弹窗 —— 选择地图后弹出，选择要携带的卡组
#  点击卡组 → 选中 → 确认 → 进入地图
# ============================================================

signal deck_selected(deck_id: String, deck_name: String)
signal cancelled()

var select_only: bool = false  # 设为true时只选卡组，不跳转地图
var _map_id: String = ""
var _map_name: String = ""
var _is_duel: bool = false     # 决斗场（耐久消耗1）；否则探索（耐久消耗3）

# 选中卡组
var _selected_deck_id: String = ""
var _selected_deck_name: String = ""
# 选中的租借卡组id（非空表示选中的是租借卡组）
var _selected_rented_id: String = ""
# 当前列表模式：false=我的卡组 true=已租卡组
var _rented_mode: bool = false


func _ready():
	# 层级设为最高
	layer = 100
	
	# 半透明背景遮罩
	var overlay = ColorRect.new()
	overlay.name = "Overlay"
	overlay.color = Color(0.0, 0.0, 0.0, 0.7)
	overlay.anchor_left = 0.0; overlay.anchor_top = 0.0
	overlay.anchor_right = 1.0; overlay.anchor_bottom = 1.0
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	
	# 弹窗面板 - 直接用Panel全屏定位
	var panel = Panel.new()
	panel.name = "PopupPanel"
	panel.anchor_left = 0.05; panel.anchor_top = 0.12
	panel.anchor_right = 0.95; panel.anchor_bottom = 0.88
	
	var ps = StyleBoxFlat.new()
	ps.bg_color = Color(0.12, 0.10, 0.18)
	ps.border_width_left = 3; ps.border_width_right = 3
	ps.border_width_top = 3; ps.border_width_bottom = 3
	ps.border_color = Color(0.5, 0.4, 0.7)
	ps.corner_radius_top_left = 20; ps.corner_radius_top_right = 20
	ps.corner_radius_bottom_left = 20; ps.corner_radius_bottom_right = 20
	ps.content_margin_left = 0  # 不用content_margin，改用offset
	ps.content_margin_right = 0
	ps.content_margin_top = 0
	ps.content_margin_bottom = 0
	panel.add_theme_stylebox_override("panel", ps)
	add_child(panel)
	
	# 在panel内部创建一个容器来管理内容
	var margin = Control.new()
	margin.name = "MarginContainer"
	margin.anchor_left = 0.0; margin.anchor_top = 0.0
	margin.anchor_right = 1.0; margin.anchor_bottom = 1.0
	margin.offset_left = Global.pw(0.04)
	margin.offset_top = Global.ph(0.02)
	margin.offset_right = Global.pw(-0.04)
	margin.offset_bottom = Global.ph(-0.02)
	panel.add_child(margin)
	
	# 标题
	var title = Label.new()
	title.name = "Title"
	title.text = "📋 选择卡组"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 60)
	title.add_theme_color_override("font_color", Color("#f9d371"))
	title.add_theme_color_override("font_shadow_color", Color("#000000"))
	title.add_theme_constant_override("shadow_offset_x", 3)
	title.add_theme_constant_override("shadow_offset_y", 3)
	title.anchor_left = 0.0; title.anchor_top = 0.0
	title.anchor_right = 1.0; title.anchor_bottom = 0.0
	title.offset_left = 0; title.offset_top = 0
	title.offset_right = 0; title.offset_bottom = Global.ph(0.06)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	margin.add_child(title)
	
	# 卡组列表（可滚动）
	var scroll = ScrollContainer.new()
	scroll.name = "DeckScroll"
	scroll.anchor_left = 0.0; scroll.anchor_top = 0.0
	scroll.anchor_right = 1.0; scroll.anchor_bottom = 1.0
	scroll.offset_left = 0
	scroll.offset_top = Global.ph(0.115)
	scroll.offset_right = 0
	scroll.offset_bottom = Global.ph(0.09)
	scroll.scroll_deadzone = 0
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED  # 禁用水平滚动
	margin.add_child(scroll)

	var vbox = VBoxContainer.new()
	vbox.name = "DeckList"
	vbox.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
	vbox.custom_minimum_size = Vector2(0, 0)  # 不固定宽度，让ScrollContainer控制
	vbox.add_theme_constant_override("separation", Global.ph(0.01))
	scroll.add_child(vbox)

	# 「我的卡组 / 已租卡组」切换按钮
	var switch_btn = Button.new()
	switch_btn.name = "SwitchModeBtn"
	switch_btn.text = "🔄 已租卡组"
	switch_btn.add_theme_font_size_override("font_size", 36)
	switch_btn.add_theme_color_override("font_color", Color("#6c9bcf"))
	var sws = StyleBoxFlat.new(); sws.bg_color = Color(0.1, 0.16, 0.24, 0.9)
	sws.border_width_left = 2; sws.border_width_right = 2; sws.border_width_top = 2; sws.border_width_bottom = 2
	sws.border_color = Color("#6c9bcf")
	sws.corner_radius_top_left = 10; sws.corner_radius_top_right = 10
	sws.corner_radius_bottom_left = 10; sws.corner_radius_bottom_right = 10
	switch_btn.add_theme_stylebox_override("normal", sws)
	switch_btn.add_theme_stylebox_override("hover", sws)
	switch_btn.add_theme_stylebox_override("pressed", sws)
	switch_btn.anchor_left = 0.0; switch_btn.anchor_top = 0.0
	switch_btn.anchor_right = 1.0; switch_btn.anchor_bottom = 0.0
	switch_btn.offset_left = 0; switch_btn.offset_top = Global.ph(0.062)
	switch_btn.offset_right = 0; switch_btn.offset_bottom = Global.ph(0.11)
	switch_btn.pressed.connect(_on_switch_mode)
	margin.add_child(switch_btn)

	# 构建列表（默认我的卡组）
	_build_deck_list()
	
	# 底部按钮区
	var btn_hbox = HBoxContainer.new()
	btn_hbox.name = "BottomBtns"
	btn_hbox.anchor_left = 0.0; btn_hbox.anchor_top = 1.0
	btn_hbox.anchor_right = 1.0; btn_hbox.anchor_bottom = 1.0
	btn_hbox.offset_left = 0
	btn_hbox.offset_top = Global.ph(-0.07)
	btn_hbox.offset_right = 0
	btn_hbox.offset_bottom = 0
	btn_hbox.add_theme_constant_override("separation", Global.pw(0.04))
	btn_hbox.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	margin.add_child(btn_hbox)
	
	# 取消按钮
	var cancel_btn = Button.new()
	cancel_btn.text = "✖ 取消"
	cancel_btn.add_theme_font_size_override("font_size", 45)
	var cs = StyleBoxFlat.new()
	cs.bg_color = Color(0.2, 0.15, 0.25)
	cs.border_width_left = 2; cs.border_width_right = 2
	cs.border_width_top = 2; cs.border_width_bottom = 2
	cs.border_color = Color(0.5, 0.3, 0.3)
	cs.corner_radius_top_left = 12; cs.corner_radius_top_right = 12
	cs.corner_radius_bottom_left = 12; cs.corner_radius_bottom_right = 12
	cs.content_margin_left = 24; cs.content_margin_right = 24
	cs.content_margin_top = 8; cs.content_margin_bottom = 8
	cancel_btn.add_theme_stylebox_override("normal", cs)
	cancel_btn.add_theme_color_override("font_color", Color("#cc8888"))
	cancel_btn.custom_minimum_size = Vector2(Global.pw(0.25), Global.ph(0.055))
	cancel_btn.pressed.connect(_on_cancel)
	btn_hbox.add_child(cancel_btn)
	
	# 确认按钮
	var confirm_btn = Button.new()
	confirm_btn.name = "ConfirmBtn"
	confirm_btn.text = "✅ 确认出发"
	confirm_btn.add_theme_font_size_override("font_size", 45)
	confirm_btn.disabled = true
	var cfs = StyleBoxFlat.new()
	cfs.bg_color = Color(0.15, 0.25, 0.15)
	cfs.border_width_left = 2; cfs.border_width_right = 2
	cfs.border_width_top = 2; cfs.border_width_bottom = 2
	cfs.border_color = Color(0.3, 0.6, 0.3)
	cfs.corner_radius_top_left = 12; cfs.corner_radius_top_right = 12
	cfs.corner_radius_bottom_left = 12; cfs.corner_radius_bottom_right = 12
	cfs.content_margin_left = 24; cfs.content_margin_right = 24
	cfs.content_margin_top = 8; cfs.content_margin_bottom = 8
	confirm_btn.add_theme_stylebox_override("normal", cfs)
	confirm_btn.add_theme_color_override("font_color", Color("#88cc88"))
	confirm_btn.custom_minimum_size = Vector2(Global.pw(0.25), Global.ph(0.055))
	confirm_btn.pressed.connect(_on_confirm)
	btn_hbox.add_child(confirm_btn)


# ============================================================
#  卡组列表构建（我的卡组 / 已租卡组）
# ============================================================
func _build_deck_list() -> void:
	var vbox = get_node_or_null("PopupPanel/MarginContainer/DeckScroll/DeckList")
	if not vbox: return
	# 清空旧列表
	for c in vbox.get_children(): c.queue_free()
	_selected_deck_id = ""; _selected_deck_name = ""; _selected_rented_id = ""
	_set_confirm_disabled(true)

	if not _rented_mode:
		# ===== 我的卡组 =====
		var decks = CardManager.get_all_decks()
		if decks.size() == 0:
			_add_empty_hint(vbox, "⚠️ 还没有卡组！\n请先去「卡组编辑」创建一套卡组")
		else:
			var all_cards = CardManager.get_all_cards()
			for deck_id in decks:
				var deck_data = decks[deck_id]
				var deck_name = deck_data.get("name", "未知卡组")
				var card_ids = deck_data.get("cards", [])
				var valid_count := 0
				if card_ids is Array:
					for cid in card_ids:
						var found := false
						for card_data in all_cards:
							if card_data.get("id", "") == cid or card_data.get("template_id", "") == cid:
								found = true; break
						if found: valid_count += 1
				_create_deck_card(vbox, deck_id, deck_name, valid_count)
	else:
		# ===== 已租卡组 =====
		var rented = Global.get_all_rented_decks()
		if rented.is_empty():
			_add_empty_hint(vbox, "⚠️ 还没有租借卡组！\n请先去「商店街 → 牌组租借」租一套")
		else:
			var shown := 0
			for rid in rented:
				var rd = rented[rid]
				var dur = int(rd.get("durability", 0))
				# 探索需3点耐久：只剩1~2点时不显示（无法进入探索）
				if not _is_duel and dur < Global.RENT_DUR_COST_EXPLORE:
					continue
				_create_rented_card(vbox, rid, rd.get("name", "租借卡组"), rd.get("cards", []).size(), dur)
				shown += 1
			if shown == 0:
				_add_empty_hint(vbox, "⚠️ 租借卡组耐久不足\n（探索需 3 点耐久）")

func _add_empty_hint(vbox, text: String) -> void:
	var empty_lbl = Label.new()
	empty_lbl.text = text
	empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	empty_lbl.add_theme_font_size_override("font_size", 40)
	empty_lbl.add_theme_color_override("font_color", Color("#aaaaaa"))
	empty_lbl.size_flags_vertical = Control.SIZE_EXPAND | Control.SIZE_FILL
	empty_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(empty_lbl)

func _on_switch_mode() -> void:
	Global.play_sfx("click")
	_rented_mode = not _rented_mode
	var btn = get_node_or_null("PopupPanel/MarginContainer/SwitchModeBtn")
	if btn is Button:
		btn.text = "🔄 我的卡组" if _rented_mode else "🔄 已租卡组"
	_build_deck_list()

func _set_confirm_disabled(dis: bool) -> void:
	var cb = get_node_or_null("PopupPanel/MarginContainer/BottomBtns/ConfirmBtn")
	if cb is Button:
		cb.disabled = dis
		if dis: cb.text = "✅ 确认出发"

# 已租卡组卡片
func _create_rented_card(parent: VBoxContainer, rented_id: String, deck_name: String, card_count: int, durability: int) -> void:
	var card = Panel.new()
	card.name = "RentedCard_" + rented_id
	var ps = StyleBoxFlat.new()
	ps.bg_color = Color(0.12, 0.18, 0.22)
	ps.border_width_left = 2; ps.border_width_right = 2; ps.border_width_top = 2; ps.border_width_bottom = 2
	ps.border_color = Color(0.3, 0.5, 0.6)
	ps.corner_radius_top_left = 12; ps.corner_radius_top_right = 12
	ps.corner_radius_bottom_left = 12; ps.corner_radius_bottom_right = 12
	ps.content_margin_left = Global.pw(0.03); ps.content_margin_right = Global.pw(0.03)
	ps.content_margin_top = Global.ph(0.01); ps.content_margin_bottom = Global.ph(0.01)
	card.add_theme_stylebox_override("panel", ps)
	card.custom_minimum_size = Vector2(0, Global.ph(0.07))
	card.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
	card.set_meta("rented_id", rented_id)
	card.set_meta("deck_name", deck_name)
	# 名称
	var name_lbl = Label.new()
	name_lbl.text = "🃏 " + deck_name + "（租）"
	name_lbl.add_theme_font_size_override("font_size", 45)
	name_lbl.add_theme_color_override("font_color", Color("#a8d8ea"))
	name_lbl.anchor_left = 0.0; name_lbl.anchor_top = 0.0; name_lbl.anchor_right = 0.0; name_lbl.anchor_bottom = 1.0
	name_lbl.offset_left = 0; name_lbl.offset_right = Global.pw(0.5)
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	card.add_child(name_lbl)
	# 张数 + 耐久
	var info_lbl = Label.new()
	var dur_cost = Global.RENT_DUR_COST_DUEL if _is_duel else Global.RENT_DUR_COST_EXPLORE
	info_lbl.text = str(card_count) + " 张 · 耐久 " + str(durability) + " 点（本次 -" + str(dur_cost) + "）"
	info_lbl.add_theme_font_size_override("font_size", 34)
	info_lbl.add_theme_color_override("font_color", Color("#e8a838"))
	info_lbl.anchor_left = 0.0; info_lbl.anchor_top = 0.0; info_lbl.anchor_right = 1.0; info_lbl.anchor_bottom = 1.0
	info_lbl.offset_left = Global.pw(0.5); info_lbl.offset_right = Global.pw(-0.02)
	info_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	info_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	card.add_child(info_lbl)
	# 选中标记
	var check = Label.new()
	check.name = "CheckMark"; check.text = "✅"
	check.add_theme_font_size_override("font_size", 40)
	check.anchor_left = 1.0; check.anchor_top = 0.0; check.anchor_right = 1.0; check.anchor_bottom = 1.0
	check.offset_left = Global.pw(-0.1); check.offset_right = Global.pw(-0.02)
	check.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; check.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	check.visible = false
	card.add_child(check)
	card.gui_input.connect(_on_deck_card_gui_input.bind(card))
	parent.add_child(card)

func _create_deck_card(parent: VBoxContainer, deck_id: String, deck_name: String, card_count: int) -> void:
	var card = Panel.new()
	card.name = "DeckCard_" + deck_id
	
	var ps = StyleBoxFlat.new()
	ps.bg_color = Color(0.15, 0.13, 0.22)
	ps.border_width_left = 2; ps.border_width_right = 2
	ps.border_width_top = 2; ps.border_width_bottom = 2
	ps.border_color = Color(0.3, 0.25, 0.4)
	ps.corner_radius_top_left = 12; ps.corner_radius_top_right = 12
	ps.corner_radius_bottom_left = 12; ps.corner_radius_bottom_right = 12
	ps.content_margin_left = Global.pw(0.03)
	ps.content_margin_right = Global.pw(0.03)
	ps.content_margin_top = Global.ph(0.01)
	ps.content_margin_bottom = Global.ph(0.01)
	card.add_theme_stylebox_override("panel", ps)
	card.custom_minimum_size = Vector2(0, Global.ph(0.07))
	card.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
	
	# 记录卡组数据到meta
	card.set_meta("deck_id", deck_id)
	card.set_meta("deck_name", deck_name)
	
	# 左侧：卡组名 + 张数
	var name_lbl = Label.new()
	name_lbl.text = "📚 " + deck_name
	name_lbl.add_theme_font_size_override("font_size", 45)
	name_lbl.add_theme_color_override("font_color", Color("#e8d5b7"))
	name_lbl.anchor_left = 0.0; name_lbl.anchor_top = 0.0
	name_lbl.anchor_right = 0.0; name_lbl.anchor_bottom = 1.0
	name_lbl.offset_left = 0; name_lbl.offset_top = 0
	name_lbl.offset_right = Global.pw(0.5); name_lbl.offset_bottom = 0
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	card.add_child(name_lbl)
	
	# 右侧：张数
	var count_lbl = Label.new()
	count_lbl.text = str(card_count) + " 张"
	count_lbl.add_theme_font_size_override("font_size", 40)
	count_lbl.add_theme_color_override("font_color", Color("#aaaaaa"))
	count_lbl.anchor_left = 0.0; count_lbl.anchor_top = 0.0
	count_lbl.anchor_right = 1.0; count_lbl.anchor_bottom = 1.0
	count_lbl.offset_left = Global.pw(0.5); count_lbl.offset_top = 0
	count_lbl.offset_right = Global.pw(-0.02); count_lbl.offset_bottom = 0
	count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	card.add_child(count_lbl)
	
	# 选中标记（默认隐藏）
	var check = Label.new()
	check.name = "CheckMark"
	check.text = "✅"
	check.add_theme_font_size_override("font_size", 40)
	check.anchor_left = 1.0; check.anchor_top = 0.0
	check.anchor_right = 1.0; check.anchor_bottom = 1.0
	check.offset_left = Global.pw(-0.1); check.offset_top = 0
	check.offset_right = Global.pw(-0.02); check.offset_bottom = 0
	check.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	check.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	check.visible = false
	card.add_child(check)
	
	# 点击选择
	card.gui_input.connect(_on_deck_card_gui_input.bind(card))
	
	parent.add_child(card)


func _on_deck_card_gui_input(event: InputEvent, card: Panel) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_select_deck(card)


func _select_deck(card: Panel) -> void:
	var deck_id = card.get_meta("deck_id", "")
	var rented_id = card.get_meta("rented_id", "")
	var deck_name = card.get_meta("deck_name", "")

	if deck_id == "" and rented_id == "":
		return

	# 清除所有卡组的选中状态
	var deck_list = get_node_or_null("PopupPanel/MarginContainer/DeckScroll/DeckList")
	if deck_list:
		for child in deck_list.get_children():
			var check_mark = child.get_node_or_null("CheckMark")
			if check_mark:
				check_mark.visible = false

	_selected_deck_id = deck_id
	_selected_rented_id = rented_id
	_selected_deck_name = deck_name

	# 标记选中
	var check_mark = card.get_node_or_null("CheckMark")
	if check_mark:
		check_mark.visible = true

	# 启用确认按钮
	var confirm_btn = get_node_or_null("PopupPanel/MarginContainer/BottomBtns/ConfirmBtn")
	if confirm_btn:
		confirm_btn.disabled = false
		confirm_btn.text = "✅ 进入"


func _on_confirm() -> void:
	if _selected_deck_id == "" and _selected_rented_id == "":
		return

	# ===== 租借卡组分支 =====
	if _selected_rented_id != "":
		var rd = Global.get_rented_deck(_selected_rented_id)
		if rd.is_empty():
			_show_toast("⚠️ 该租借卡组已失效")
			_build_deck_list()
			return
		var dur = int(rd.get("durability", 0))
		var dur_cost = Global.RENT_DUR_COST_DUEL if _is_duel else Global.RENT_DUR_COST_EXPLORE
		if dur < dur_cost:
			_show_toast("⚠️ 耐久不足（剩 " + str(dur) + " 点，需 " + str(dur_cost) + " 点）")
			_build_deck_list()
			return
		# 扣耐久 + 设置携带租借卡组
		Global.consume_rented_durability(_selected_rented_id, dur_cost)
		Global.current_rented_deck_id = _selected_rented_id
		Global.current_rented_deck_name = _selected_deck_name
		Global.current_deck_id = _selected_rented_id
		Global.current_deck_name = _selected_deck_name
	else:
		# ===== 普通卡组：清除租借标志 =====
		Global.current_rented_deck_id = ""
		Global.current_rented_deck_name = ""
		Global.current_deck_id = _selected_deck_id
		Global.current_deck_name = _selected_deck_name

	# 发射信号
	deck_selected.emit(_selected_deck_id if _selected_rented_id == "" else _selected_rented_id, _selected_deck_name)

	if select_only:
		# 只选卡组，不跳转
		queue_free()
		return

	Global.current_map_id = _map_id
	Global.current_map_name = _map_name
	Global.saved_map_node_data = []
	Global.current_map_layer = -1
	Global.current_map_node = -1
	# 初始化爬塔持久HP（满血开始）
	Global.current_run_player_hp = PlayerManager.get_guild_max_hp()
	Global.current_run_player_max_hp = PlayerManager.get_guild_max_hp()
	Global.change_scene("res://MapNodeScene.tscn")


# 简易提示弹窗
func _show_toast(text: String) -> void:
	var existing = get_node_or_null("ToastOverlay")
	if existing: existing.queue_free()
	var overlay = ColorRect.new(); overlay.name = "ToastOverlay"
	overlay.color = Color(0, 0, 0, 0.6)
	overlay.anchor_left = 0.0; overlay.anchor_top = 0.0; overlay.anchor_right = 1.0; overlay.anchor_bottom = 1.0
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	var lbl = Label.new(); lbl.text = text
	lbl.add_theme_font_size_override("font_size", 45); lbl.add_theme_color_override("font_color", Color("#FF5252"))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.anchor_left = 0.0; lbl.anchor_top = 0.0; lbl.anchor_right = 1.0; lbl.anchor_bottom = 1.0
	overlay.add_child(lbl)
	var btn = Button.new(); btn.text = "知道了"
	btn.add_theme_font_size_override("font_size", 40)
	btn.anchor_left = 0.3; btn.anchor_top = 0.62; btn.anchor_right = 0.7; btn.anchor_bottom = 0.70
	btn.pressed.connect(func(): overlay.queue_free())
	overlay.add_child(btn)


func _on_cancel() -> void:
	cancelled.emit()
	queue_free()


# 设置地图数据（从 Exploration.gd 调用）
func set_map_data(map_id: String, map_name: String) -> void:
	_map_id = map_id
	_map_name = map_name
