extends Control

# ===== 卡基公式数据 =====
var _selected := {
	"fiber": {},
	"mineral": {},
	"resin": {}
}
const MAX_COUNT := {"fiber": 3, "mineral": 3, "resin": 2}
var _preview_labels := {}
var _category_labels := {}
var _hint_label: Label = null

# 长按相关
var _picker_long_press_timer: float = 0.0
var _picker_long_press_row = null
var _picker_long_press_mat: Dictionary = {}
var _picker_long_press_active: bool = false
# 教程引导状态：-1=未开始，0=欢迎说卡基，1=选素材，2=看预览，3=制作，4=完成
var _tutorial_step: int = -1
var _tutorial_popup_overlay: Control = null
var _tutorial_done: bool = false

func _ready():
	# ---- 静态节点已在 CardBaseMaking.tscn 中声明 ----
	var back := get_node_or_null("BackBtn")
	if back is Button: back.pressed.connect(_on_back)
	var help := get_node_or_null("HelpBtn")
	if help is Button: help.pressed.connect(_on_help)
	# 主题
	Global.theme_changed.connect(_on_theme_changed)
	call_deferred("_apply_theme_styles")
	# 动态内容构建
	call_deferred("_build_dynamic_content")

## 素材卡 / 预览面板的统一「卡片」样式。
## 原先用 topbar_bg：白天主题下 TopBar 与页面底色也是同一个米色，
## 三张素材卡 + 预览面板整块糊成一片，只剩圆角边缘的锯齿能看出边界。
func _make_card_style() -> StyleBoxFlat:
	var sb = StyleBoxFlat.new()
	sb.bg_color = Global.current.btn_bg
	sb.border_width_left = 2; sb.border_width_right = 2
	sb.border_width_top = 2; sb.border_width_bottom = 2
	sb.border_color = Global.current.topbar_border
	sb.corner_radius_top_left = 10; sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_left = 10; sb.corner_radius_bottom_right = 10
	return sb


func _build_material_section(parent: VBoxContainer):
	var cat_data = [
		{"key": "fiber", "label": " 纤维素材", "color": Color("#8BC34A")},
		{"key": "mineral", "label": " 矿粉素材", "color": Color("#FF9800")},
		{"key": "resin", "label": " 树脂素材", "color": Color("#E91E63")},
	]
	
	for cat in cat_data:
		var key = cat["key"]
		
		var row = Panel.new()
		row.name = "CatRow_" + key
		row.add_theme_stylebox_override("panel", _make_card_style())
		row.size_flags_horizontal = SIZE_FILL
		parent.add_child(row)
		
		var vbox_inner = VBoxContainer.new()
		vbox_inner.name = "InnerVBox_" + key
		vbox_inner.anchor_left = 0.0
		vbox_inner.anchor_top = 0.0
		vbox_inner.anchor_right = 1.0
		vbox_inner.anchor_bottom = 1.0
		vbox_inner.offset_left = Global.pw(0.02)
		vbox_inner.offset_top = Global.ph(0.006)
		vbox_inner.offset_right = Global.pw(-0.02)
		vbox_inner.offset_bottom = Global.ph(-0.006)
		vbox_inner.size_flags_horizontal = SIZE_FILL
		row.add_child(vbox_inner)
		
		var title_row = HBoxContainer.new()
		title_row.name = "TitleRow_" + key
		title_row.size_flags_horizontal = SIZE_FILL
		vbox_inner.add_child(title_row)
		
		var cat_label = Label.new()
		cat_label.text = cat["label"]
		cat_label.add_theme_font_size_override("font_size", 50)
		cat_label.add_theme_color_override("font_color", cat["color"])
		cat_label.size_flags_horizontal = SIZE_EXPAND
		title_row.add_child(cat_label)
		
		var count_label = Label.new()
		count_label.text = "0/" + str(MAX_COUNT[key])
		count_label.add_theme_font_size_override("font_size", 50)
		count_label.add_theme_color_override("font_color", Global.current.btn_text)
		count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		count_label.custom_minimum_size = Vector2(Global.pw(0.08), 0)
		title_row.add_child(count_label)
		
		var select_btn = Button.new()
		select_btn.text = "选择"
		select_btn.add_theme_font_size_override("font_size", 50)
		var sbs = StyleBoxFlat.new()
		sbs.bg_color = Global.current.btn_bg
		sbs.border_width_left = 2
		sbs.border_width_right = 2
		sbs.border_width_top = 2
		sbs.border_width_bottom = 2
		sbs.border_color = cat["color"]
		sbs.corner_radius_top_left = 8
		sbs.corner_radius_top_right = 8
		sbs.corner_radius_bottom_left = 8
		sbs.corner_radius_bottom_right = 8
		sbs.content_margin_left = 16
		sbs.content_margin_right = 16
		select_btn.add_theme_stylebox_override("normal", sbs)
		select_btn.add_theme_color_override("font_color", Global.current.btn_text)
		select_btn.pressed.connect(_on_select_material.bind(key))
		title_row.add_child(select_btn)
		
		var selected_row = HBoxContainer.new()
		selected_row.name = "SelectedRow_" + key
		selected_row.size_flags_horizontal = SIZE_FILL
		selected_row.custom_minimum_size = Vector2(0, Global.ph(0.06))
		vbox_inner.add_child(selected_row)
		
		_category_labels[key] = {"row": selected_row, "count": count_label}
		
		# Panel 不会按子节点自动撑高：用内容最小高度 + 少量留白定高，
		# 原先写死 ph(0.15)=288，而内容实际只有 ~190，每张卡下面挂着大片空白。
		row.custom_minimum_size = Vector2(0, vbox_inner.get_combined_minimum_size().y + Global.ph(0.014))


# ============================
#  素材选择弹窗
# ============================
func _on_select_material(cat_key: String):
	if _get_cat_total(cat_key) >= MAX_COUNT[cat_key]:
		return
	_show_material_picker(cat_key)

func _show_material_picker(cat_key: String):
	# 遮罩（拦截事件防止穿透到主界面）
	var overlay = ColorRect.new()
	overlay.name = "PickerOverlay"
	overlay.color = Color(0, 0, 0, 0.6)
	overlay.anchor_left = 0.0
	overlay.anchor_top = 0.0
	overlay.anchor_right = 1.0
	overlay.anchor_bottom = 1.0
	overlay.mouse_filter = MOUSE_FILTER_STOP
	add_child(overlay)
	
	# 点击遮罩关闭弹窗
	overlay.gui_input.connect(_on_overlay_input.bind(overlay))
	
	var panel = Panel.new()
	panel.name = "PickerPanel"
	panel.anchor_left = 0.05
	panel.anchor_top = 0.15
	panel.anchor_right = 0.95
	panel.anchor_bottom = 0.85
	panel.clip_contents = true
	var ps = StyleBoxFlat.new()
	ps.bg_color = Global.current.bg
	ps.border_width_left = 3
	ps.border_width_right = 3
	ps.border_width_top = 3
	ps.border_width_bottom = 3
	ps.border_color = Global.current.topbar_border
	ps.corner_radius_top_left = 16
	ps.corner_radius_top_right = 16
	ps.corner_radius_bottom_left = 16
	ps.corner_radius_bottom_right = 16
	panel.add_theme_stylebox_override("panel", ps)
	overlay.add_child(panel)
	
	var title_label = Label.new()
	var cat_names = {"fiber": "纤维素材", "mineral": "矿粉素材", "resin": "树脂素材"}
	title_label.text = "选择" + cat_names.get(cat_key, "")
	title_label.add_theme_font_size_override("font_size", 50)
	title_label.add_theme_color_override("font_color", Global.current.title)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.anchor_left = 0.0
	title_label.anchor_top = 0.0
	title_label.anchor_right = 1.0
	title_label.anchor_bottom = 0.0
	title_label.offset_left = 0
	title_label.offset_top = Global.ph(0.01)
	title_label.offset_right = 0
	title_label.offset_bottom = Global.ph(0.08)
	panel.add_child(title_label)
	
	var scroll = ScrollContainer.new()
	scroll.name = "PickerScroll"
	scroll.anchor_left = 0.02
	scroll.anchor_top = 0.0
	scroll.anchor_right = 0.98
	scroll.anchor_bottom = 1.0
	scroll.offset_left = 0
	scroll.offset_top = Global.ph(0.085)
	scroll.offset_right = 0
	scroll.offset_bottom = Global.ph(-0.065)
	scroll.scroll_horizontal = false
	scroll.scroll_vertical = true
	panel.add_child(scroll)
	
	var vbox = VBoxContainer.new()
	vbox.name = "PickerVBox"
	vbox.size_flags_horizontal = SIZE_FILL
	vbox.add_theme_constant_override("separation", Global.ph(0.005))
	scroll.add_child(vbox)
	
	var mat_list = []
	match cat_key:
		"fiber": mat_list = Global.get_fiber_list()
		"mineral": mat_list = Global.get_mineral_list()
		"resin": mat_list = Global.get_resin_list()
	
	var warehouse = get_node("/root/WarehouseManager")
	var inv = warehouse.get_materials()
	
	for mat in mat_list:
		var mid = mat["id"]
		var count = inv.get(mid, 0)
		if count <= 0:
			continue
		
		var mat_row = _make_picker_row(mat, count, cat_key, overlay)
		vbox.add_child(mat_row)
	
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
	close_btn.anchor_left = 0.3
	close_btn.anchor_top = 1.0
	close_btn.anchor_right = 0.7
	close_btn.anchor_bottom = 1.0
	close_btn.offset_left = 0
	close_btn.offset_top = Global.ph(-0.065)
	close_btn.offset_right = 0
	close_btn.offset_bottom = Global.ph(-0.01)
	close_btn.pressed.connect(_close_picker.bind(overlay))
	panel.add_child(close_btn)


func _make_picker_row(mat: Dictionary, count: int, cat_key: String, overlay: ColorRect) -> Panel:
	var row = Panel.new()
	var rs = StyleBoxFlat.new()
	rs.bg_color = Global.current.topbar_bg
	rs.corner_radius_top_left = 6
	rs.corner_radius_top_right = 6
	rs.corner_radius_bottom_left = 6
	rs.corner_radius_bottom_right = 6
	row.add_theme_stylebox_override("panel", rs)
	row.custom_minimum_size = Vector2(0, Global.ph(0.1))
	row.size_flags_horizontal = SIZE_FILL
	
	var hbox = HBoxContainer.new()
	hbox.size_flags_horizontal = SIZE_FILL
	row.add_child(hbox)
	
	var name_label = Label.new()
	name_label.text = mat["name"]
	name_label.add_theme_font_size_override("font_size", 50)
	name_label.add_theme_color_override("font_color", Global.current.btn_text)
	name_label.size_flags_horizontal = SIZE_EXPAND
	name_label.custom_minimum_size = Vector2(Global.pw(0.2), 0)
	hbox.add_child(name_label)
	
	var mid = mat["id"]
	var selected_qty = _selected[cat_key].get(mid, 0)
	
	# [-] 按钮
	var dec_btn = Button.new()
	dec_btn.text = "—"
	dec_btn.add_theme_font_size_override("font_size", 50)
	dec_btn.custom_minimum_size = Vector2(Global.pw(0.07), Global.ph(0.06))
	dec_btn.pressed.connect(func(): _on_pick_material(mid, cat_key, overlay, -1))
	hbox.add_child(dec_btn)
	
	# 数量标签
	var qty_label = Label.new()
	qty_label.name = "PickerQty_" + mid
	qty_label.text = str(selected_qty)
	qty_label.add_theme_font_size_override("font_size", 50)
	qty_label.add_theme_color_override("font_color", Global.current.title)
	qty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	qty_label.custom_minimum_size = Vector2(Global.pw(0.07), 0)
	hbox.add_child(qty_label)
	
	# [+] 按钮
	var inc_btn = Button.new()
	inc_btn.text = "+"
	inc_btn.add_theme_font_size_override("font_size", 50)
	inc_btn.custom_minimum_size = Vector2(Global.pw(0.07), Global.ph(0.06))
	var space_left = MAX_COUNT[cat_key] - _get_cat_total(cat_key) + selected_qty
	inc_btn.disabled = (selected_qty >= count) or (space_left <= 0)
	inc_btn.pressed.connect(func(): _on_pick_material(mid, cat_key, overlay, 1))
	hbox.add_child(inc_btn)
	
	# 库存标签
	var stock_label = Label.new()
	stock_label.text = "库存:" + str(count)
	stock_label.add_theme_font_size_override("font_size", 45)
	stock_label.add_theme_color_override("font_color", Global.current.btn_text)
	stock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stock_label.custom_minimum_size = Vector2(Global.pw(0.12), 0)
	hbox.add_child(stock_label)
	
	# 长按查看详情
	row.gui_input.connect(_on_picker_row_input.bind(mat, cat_key, overlay, row))
	
	return row


# ============================
#  选取素材
# ============================
func _on_pick_material(mid: String, cat_key: String, overlay: ColorRect, delta: int):
	var cur = _selected[cat_key].get(mid, 0)
	var new_qty = cur + delta
	if new_qty < 0:
		new_qty = 0
	if new_qty > 0:
		var cat_total = _get_cat_total(cat_key)
		var old_contrib = cur
		var space_left = MAX_COUNT[cat_key] - (cat_total - old_contrib)
		if delta > 0 and new_qty > space_left:
			new_qty = space_left

	if new_qty <= 0:
		_selected[cat_key].erase(mid)
	else:
		_selected[cat_key][mid] = new_qty
	
	_update_ui()
	# 刷新弹窗中的行显示
	_refresh_picker_rows(overlay, cat_key)
	
	# 教程引导：选齐三类素材后弹"看预览"讲解
	if _tutorial_step == 1 and _tutorial_done == false:
		if _get_cat_total("fiber") >= 1 and _get_cat_total("mineral") >= 1 and _get_cat_total("resin") >= 1:
			# 先关闭当前素材选择弹窗，避免叠层
			if overlay and is_instance_valid(overlay):
				overlay.queue_free()
			_advance_tutorial("mats_ready")


# ============================
#  长按查看素材详情
# ============================
func _on_picker_row_input(event: InputEvent, mat: Dictionary, cat_key: String, overlay: ColorRect, row: Panel):
	# 触摸按下：开始计时
	if event is InputEventScreenTouch:
		if event.pressed:
			_picker_long_press_timer = 0.0
			_picker_long_press_mat = mat
			_picker_long_press_row = row
			_picker_long_press_active = true
		else:
			# 手指抬起：如果还没触发长按，忽略
			_picker_long_press_active = false
	
	# 鼠标按下（兼容PC测试）
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_picker_long_press_timer = 0.0
			_picker_long_press_mat = mat
			_picker_long_press_row = row
			_picker_long_press_active = true
		elif not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_picker_long_press_active = false


func _process(delta: float):
	if _picker_long_press_active:
		_picker_long_press_timer += delta
		# 长按 0.5 秒触发详情
		if _picker_long_press_timer >= 0.5:
			_picker_long_press_active = false
			_show_material_detail(_picker_long_press_mat)


func _show_material_detail(mat: Dictionary):
	# 如果已有详情弹窗则关闭
	var existing = get_node_or_null("DetailOverlay")
	if existing:
		existing.queue_free()
	
	# 遮罩
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
	
	# 详情面板
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
	ps.border_color = _get_rarity_color(mat.get("rarity", "普通"))
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
	
	# 素材名称
	var name_label = Label.new()
	name_label.text = mat.get("name", "未知素材")
	name_label.add_theme_font_size_override("font_size", 55)
	name_label.add_theme_color_override("font_color", _get_rarity_color(mat.get("rarity", "普通")))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_label)
	
	# 稀有度
	var rarity_label = Label.new()
	rarity_label.text = "【" + mat.get("rarity", "普通") + "】"
	rarity_label.add_theme_font_size_override("font_size", 50)
	rarity_label.add_theme_color_override("font_color", _get_rarity_color(mat.get("rarity", "普通")))
	rarity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(rarity_label)
	
	# 分隔线
	var line = HSeparator.new()
	line.add_theme_color_override("color", Global.current.topbar_border)
	vbox.add_child(line)
	
	# 属性列表
	var attrs_to_show = [
		{"key": "hardness", "label": "硬度", "color": Color("#FF9800")},
		{"key": "gloss", "label": "光泽", "color": Color("#E91E63")},
		{"key": "carry", "label": "承载力", "color": Color("#8BC34A")},
		{"key": "stability", "label": "稳定性", "color": Color("#3498DB")},
		{"key": "toughness", "label": "韧性", "color": Color("#9B59B6")},
		{"key": "bond", "label": "粘合度", "color": Color("#FF5722")},
		{"key": "tendency", "label": "倾向", "color": Color("#FFD700")},
	]
	
	for attr in attrs_to_show:
		var val = mat.get(attr["key"], null)
		if val != null:
			var row = HBoxContainer.new()
			row.size_flags_horizontal = SIZE_FILL
			vbox.add_child(row)
			
			var lbl = Label.new()
			lbl.text = attr["label"] + "："
			lbl.add_theme_font_size_override("font_size", 50)
			lbl.add_theme_color_override("font_color", attr["color"])
			lbl.size_flags_horizontal = SIZE_EXPAND
			row.add_child(lbl)
			
			var val_lbl = Label.new()
			if attr["key"] == "tendency":
				val_lbl.text = str(val)
			else:
				val_lbl.text = str(val)
			val_lbl.add_theme_font_size_override("font_size", 50)
			val_lbl.add_theme_color_override("font_color", Global.current.title)
			val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			row.add_child(val_lbl)
	
	# 描述
	var desc = mat.get("description", "")
	if desc != "":
		var desc_label = Label.new()
		desc_label.text = desc
		desc_label.add_theme_font_size_override("font_size", 50)
		desc_label.add_theme_color_override("font_color", Global.current.btn_text)
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(desc_label)
	
	# 关闭按钮
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


func _update_ui():
	for key in _selected.keys():
		var data = _category_labels.get(key)
		if not data:
			continue
		
		var row = data["row"]
		for child in row.get_children():
			row.remove_child(child)
			child.queue_free()
		
		var cnt = _get_cat_total(key)
		data["count"].text = str(cnt) + "/" + str(MAX_COUNT[key])
		
		for mid in _selected[key].keys():
			var qty = _selected[key][mid]
			var mat = Global.get_material_by_id(mid)
			if mat.is_empty():
				continue
			
			var tag = Button.new()
			tag.text = mat["name"] + " ×" + str(qty)
			tag.add_theme_font_size_override("font_size", 50)
			var ts = StyleBoxFlat.new()
			ts.bg_color = Global.current.btn_bg
			ts.border_width_left = 1
			ts.border_width_right = 1
			ts.border_width_top = 1
			ts.border_width_bottom = 1
			ts.border_color = _get_rarity_color(mat.get("rarity", "普通"))
			ts.corner_radius_top_left = 6
			ts.corner_radius_top_right = 6
			ts.corner_radius_bottom_left = 6
			ts.corner_radius_bottom_right = 6
			ts.content_margin_left = 8
			ts.content_margin_right = 8
			tag.add_theme_stylebox_override("normal", ts)
			tag.add_theme_color_override("font_color", Global.current.btn_text)
			tag.pressed.connect(_on_remove_material.bind(mid, key))
			row.add_child(tag)
	
	_update_make_btn()
	_update_preview()


func _update_make_btn():
	var btn = _preview_labels.get("make_btn")
	if not btn:
		return
	var fiber_count = _get_cat_total("fiber")
	var mineral_count = _get_cat_total("mineral")
	var resin_count = _get_cat_total("resin")
	var rules = Global.get_formulas().get("input_rules", {})
	var ready = true
	if fiber_count < rules.get("fiber_min", 1): ready = false
	if mineral_count < rules.get("mineral_min", 1): ready = false
	if resin_count < rules.get("resin_min", 1): ready = false
	btn.disabled = not ready


func _on_remove_material(mid: String, cat_key: String):
	_selected[cat_key].erase(mid)
	_update_ui()


func _get_cat_total(cat_key: String) -> int:
	var total = 0
	for mid in _selected[cat_key]:
		total += _selected[cat_key][mid]
	return total

func _get_total_count() -> int:
	var total = 0
	for key in _selected.keys():
		total += _get_cat_total(key)
	return total

func _get_rarity_color(rarity: String) -> Color:
	match rarity:
		"传说": return Color("#FFD700")
		"史诗": return Color("#9B59B6")
		"稀有": return Color("#3498DB")
		"普通": return Color("#95A5A6")
	return Color("#95A5A6")


func _close_picker(overlay: ColorRect):
	if overlay and is_instance_valid(overlay):
		overlay.queue_free()


func _refresh_picker_rows(overlay: ColorRect, cat_key: String):
	if not overlay or not is_instance_valid(overlay):
		return
	var scroll = overlay.get_node_or_null("ConfirmPanel/PickerScroll")
	if not scroll:
		# 兼容旧路径名（素材选择弹窗用 PickerScroll）
		scroll = overlay.get_node_or_null("ConfirmPanel/PickerScroll")
		if not scroll:
			scroll = overlay.get_node_or_null("PickerPanel/PickerScroll")
	if not scroll:
		return
	var vbox = scroll.get_node_or_null("PickerVBox")
	if not vbox:
		return
	# 更新每行的数量标签
	for child in vbox.get_children():
		if child is Panel:
			var hbox = child.get_child(0) if child.get_child_count() > 0 else null
			if hbox and hbox is HBoxContainer:
				# 找数量标签（第三个子节点，索引2）
				for c in hbox.get_children():
					if c is Label and c.name.begins_with("PickerQty_"):
						var mid = c.name.trim_prefix("PickerQty_")
						var qty = _selected[cat_key].get(mid, 0)
						c.text = str(qty)
						# 更新+按钮状态
						var idx = c.get_index()
						if idx + 1 < hbox.get_child_count():
							var inc_btn = hbox.get_child(idx + 1)
							if inc_btn is Button and inc_btn.text == "+":
								var stock = 0
								var warehouse = get_node("/root/WarehouseManager")
								var inv = warehouse.get_materials()
								stock = inv.get(mid, 0)
								var space_left = MAX_COUNT[cat_key] - _get_cat_total(cat_key) + qty
								inc_btn.disabled = (qty >= stock) or (space_left <= 0)
						break
	
	if _hint_label:
		_hint_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.5))
		_hint_label.text = "已选 " + str(_get_cat_total(cat_key)) + "/" + str(MAX_COUNT[cat_key]) + "，用 [-] [+] 调整数量"


func _on_overlay_input(event: InputEvent, overlay: ColorRect):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# 点击遮罩（面板外）关闭弹窗
		var panel = overlay.get_node_or_null("PickerPanel")
		if panel:
			var mouse_pos = overlay.get_local_mouse_position()
			var panel_rect = Rect2(panel.position, panel.size)
			if not panel_rect.has_point(mouse_pos):
				_close_picker(overlay)


# ============================
#  属性预览区域
# ============================
func _build_preview_section(parent: VBoxContainer):
	var panel = Panel.new()
	panel.name = "PreviewPanel"
	panel.add_theme_stylebox_override("panel", _make_card_style())
	panel.size_flags_horizontal = SIZE_FILL
	parent.add_child(panel)
	
	var vbox = VBoxContainer.new()
	vbox.name = "PreviewVBox"
	# Panel 不会给子节点做内缩：必须用锚点+内边距铺满，否则内容会贴屏幕左边缘
	vbox.anchor_left = 0.0
	vbox.anchor_top = 0.0
	vbox.anchor_right = 1.0
	vbox.anchor_bottom = 1.0
	vbox.offset_left = Global.pw(0.03)
	vbox.offset_top = Global.ph(0.01)
	vbox.offset_right = Global.pw(-0.03)
	vbox.offset_bottom = Global.ph(-0.01)
	vbox.size_flags_horizontal = SIZE_FILL
	vbox.size_flags_vertical = SIZE_SHRINK_BEGIN
	vbox.add_theme_constant_override("separation", Global.ph(0.005))
	panel.add_child(vbox)
	
	var title = Label.new()
	title.text = "卡基属性预览"
	title.add_theme_font_size_override("font_size", 50)
	title.add_theme_color_override("font_color", Global.current.title)
	vbox.add_child(title)
	
	var attrs = [
		{"key": "load_cap", "label": "承载力"},
		{"key": "slots", "label": "卡槽"},
		{"key": "durability", "label": "耐久度"},
		{"key": "quality", "label": "品质"},
		{"key": "tendency", "label": "倾向"},
		{"key": "consumption", "label": "消耗"},
	]
	
	for attr in attrs:
		var row = HBoxContainer.new()
		row.size_flags_horizontal = SIZE_FILL
		vbox.add_child(row)
		
		var name_label = Label.new()
		name_label.text = attr["label"] + "："
		name_label.add_theme_font_size_override("font_size", 50)
		name_label.add_theme_color_override("font_color", Global.current.btn_text)
		name_label.size_flags_horizontal = SIZE_EXPAND
		row.add_child(name_label)
		
		var val_label = Label.new()
		val_label.text = "—"
		val_label.name = "PreviewVal_" + attr["key"]
		val_label.add_theme_font_size_override("font_size", 50)
		val_label.add_theme_color_override("font_color", Global.current.title)
		val_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(val_label)
		
		_preview_labels[attr["key"]] = val_label
	
	# 同素材卡：写死 ph(0.42)=806 时下面挂着 260px 空白，按内容高度收
	panel.custom_minimum_size = Vector2(0, vbox.get_combined_minimum_size().y + Global.ph(0.02))


# ============================
#  属性计算公式
# ============================
func _update_preview():
	var fiber_mats := []
	var mineral_mats := []
	var resin_mats := []
	
	for mid in _selected["fiber"].keys():
		var qty = _selected["fiber"][mid]
		var mat = Global.get_material_by_id(mid)
		if not mat.is_empty():
			for i in range(qty):
				fiber_mats.append(mat)
	for mid in _selected["mineral"].keys():
		var qty = _selected["mineral"][mid]
		var mat = Global.get_material_by_id(mid)
		if not mat.is_empty():
			for i in range(qty):
				mineral_mats.append(mat)
	for mid in _selected["resin"].keys():
		var qty = _selected["resin"][mid]
		var mat = Global.get_material_by_id(mid)
		if not mat.is_empty():
			for i in range(qty):
				resin_mats.append(mat)
	
	var load_cap = _calc_load_cap(mineral_mats, resin_mats)
	var slots = _calc_slots(fiber_mats, mineral_mats)
	var durability = _calc_durability(fiber_mats, resin_mats)
	var quality = _calc_quality(mineral_mats, resin_mats)
	var tendency = _calc_tendency(fiber_mats, mineral_mats, resin_mats)
	
	_preview_labels["load_cap"].text = str(load_cap)
	_preview_labels["slots"].text = str(slots)
	_preview_labels["durability"].text = str(durability)
	_preview_labels["quality"].text = quality
	
	if tendency.is_empty():
		_preview_labels["tendency"].text = "无"
	else:
		var parts := []
		for k in tendency.keys():
			parts.append(k + str(tendency[k]))
		_preview_labels["tendency"].text = "".join(parts)
	
	# 消耗显示
	var consumption_parts := []
	for key in _selected.keys():
		var count = _get_cat_total(key)
		if count > 0:
			var cat_name = {"fiber": "纤维", "mineral": "矿粉", "resin": "树脂"}
			consumption_parts.append(cat_name.get(key, key) + "x" + str(int(count)))
	
	if consumption_parts.is_empty():
		_preview_labels["consumption"].text = "无"
	else:
		_preview_labels["consumption"].text = "".join(consumption_parts)


func _calc_load_cap(mineral_mats: Array, resin_mats: Array) -> int:
	var sum_hardness := 0
	for m in mineral_mats:
		sum_hardness += m.get("hardness", 0)
	var sum_gloss := 0
	for m in resin_mats:
		sum_gloss += m.get("gloss", 0)
	var raw = sum_hardness * 2 + sum_gloss * 1 + 5
	return min(raw, 30)


func _calc_slots(fiber_mats: Array, mineral_mats: Array) -> int:
	var sum_carry := 0
	for m in fiber_mats:
		sum_carry += m.get("carry", 0)
	var sum_stability := 0
	for m in mineral_mats:
		sum_stability += m.get("stability", 0)
	var raw = floor(sum_carry * 0.5 + sum_stability * 0.3) + 2
	return min(raw, 12)


func _calc_durability(fiber_mats: Array, resin_mats: Array) -> int:
	var sum_toughness := 0
	for m in fiber_mats:
		sum_toughness += m.get("toughness", 0)
	var sum_bond := 0
	for m in resin_mats:
		sum_bond += m.get("bond", 0)
	var raw = 5 + sum_toughness * 3 + sum_bond * 2
	return min(raw, 60)


func _calc_quality(mineral_mats: Array, resin_mats: Array) -> String:
	var total_count = _get_total_count()
	
	var m_count = mineral_mats.size()
	var lower_raw := 0
	if m_count > 0:
		var sum_stability := 0
		for m in mineral_mats:
			sum_stability += m.get("stability", 0)
		lower_raw = floor(sum_stability / m_count)
	
	var r_count = resin_mats.size()
	var upper_raw := 0
	if r_count > 0:
		var sum_gloss := 0
		for m in resin_mats:
			sum_gloss += m.get("gloss", 0)
		upper_raw = floor(sum_gloss / r_count)
	
	var formulas = Global.get_formulas()
	var penalties = formulas.get("material_penalty", [])
	var q_mod := 0
	var u_mod := 0
	for p in penalties:
		var r = p.get("total_count_range", [0, 0])
		if total_count >= r[0] and total_count <= r[1]:
			q_mod = p.get("quality_mod", 0)
			u_mod = p.get("complexity_mod", 0)
			break
	
	lower_raw = max(0, lower_raw + q_mod)
	upper_raw = max(0, upper_raw - u_mod)
	
	var lower_map = formulas.get("attributes", {}).get("quality_lower", {}).get("mapping", {})
	var upper_map = formulas.get("attributes", {}).get("quality_upper", {}).get("mapping", {})
	
	var lower_str := ""
	var upper_str := ""
	
	for k in lower_map.keys():
		if k == "4+":
			if lower_raw >= 4:
				lower_str = lower_map[k]
		else:
			if lower_raw == int(k):
				lower_str = lower_map[k]
	
	for k in upper_map.keys():
		if k == "2+":
			if upper_raw >= 2:
				upper_str = upper_map[k]
		else:
			if upper_raw == int(k):
				upper_str = upper_map[k]
	
	if lower_str == "" and upper_str == "":
		return "—"
	
	return lower_str + " ~ " + upper_str


func _calc_tendency(fiber_mats: Array, mineral_mats: Array, resin_mats: Array) -> Dictionary:
	var result := {}
	var all_mats = fiber_mats + mineral_mats + resin_mats
	for mat in all_mats:
		var t = mat.get("tendency", "")
		if t == "" or t == null:
			continue
		if t.length() >= 2:
			var elem = t[0]
			var val = int(t.substr(t.length() - 1, 1))
			result[elem] = result.get(elem, 0) + val
	return result


# ============================
#  制作按钮
# ============================
func _build_make_button(parent: VBoxContainer):
	var btn = Button.new()
	btn.name = "MakeBtn"
	btn.text = "开始制作"
	btn.add_theme_font_size_override("font_size", 55)
	
	var s = StyleBoxFlat.new()
	s.bg_color = Global.current.btn_bg
	s.border_width_left = 3
	s.border_width_right = 3
	s.border_width_top = 3
	s.border_width_bottom = 3
	s.border_color = Color("#FF9800")
	s.corner_radius_top_left = 16
	s.corner_radius_top_right = 16
	s.corner_radius_bottom_left = 16
	s.corner_radius_bottom_right = 16
	s.content_margin_left = 24
	s.content_margin_right = 24
	
	var sh = s.duplicate()
	sh.bg_color = Global.current.btn_bg_hover
	
	var sp = s.duplicate()
	sp.bg_color = Global.current.btn_bg_pressed
	
	btn.add_theme_stylebox_override("normal", s)
	btn.add_theme_stylebox_override("hover", sh)
	btn.add_theme_stylebox_override("pressed", sp)
	btn.add_theme_stylebox_override("focus", s)
	btn.add_theme_color_override("font_color", Global.current.btn_text)
	btn.add_theme_color_override("font_hover_color", Global.current.btn_text_hover)
	btn.add_theme_color_override("font_pressed_color", Global.current.btn_text_hover)
	# 没有 disabled 样式覆盖时，禁用态会退回主题默认的灰色块 + 默认暗灰字，
	# 于是按钮样式突然「变成另一个灰色按钮」且字几乎看不清。
	# 这里保持本按钮的配色，只压低亮度/字号不透明度来表示「不可点」。
	btn.add_theme_color_override("font_disabled_color",
		Color(Global.current.btn_text.r, Global.current.btn_text.g, Global.current.btn_text.b, 0.62))
	var sd = s.duplicate()
	sd.bg_color = Global.current.btn_bg.darkened(0.10)
	sd.border_color = Color(Global.current.topbar_border.r, Global.current.topbar_border.g,
		Global.current.topbar_border.b, 0.85)
	btn.add_theme_stylebox_override("disabled", sd)
	
	btn.size_flags_horizontal = SIZE_FILL
	btn.custom_minimum_size = Vector2(0, Global.ph(0.09))
	btn.pressed.connect(_on_make)
	btn.disabled = true  # 初始禁用
	parent.add_child(btn)
	
	_preview_labels["make_btn"] = btn
	
	# 提示移到底部UI条


func _on_make():
	if not _hint_label:
		return
	
	var formulas = Global.get_formulas()
	var rules = formulas.get("input_rules", {})
	
	var fiber_count = _get_cat_total("fiber")
	var mineral_count = _get_cat_total("mineral")
	var resin_count = _get_cat_total("resin")
	var total_count = _get_total_count()
	
	var err := ""
	if fiber_count < rules.get("fiber_min", 1):
		err = "需要至少 " + str(rules.get("fiber_min", 1)) + " 种纤维素材"
	elif fiber_count > rules.get("fiber_max", 3):
		err = "纤维素材最多 " + str(rules.get("fiber_max", 3)) + " 种"
	elif mineral_count < rules.get("mineral_min", 1):
		err = "需要至少 " + str(rules.get("mineral_min", 1)) + " 种矿粉素材"
	elif mineral_count > rules.get("mineral_max", 3):
		err = "矿粉素材最多 " + str(rules.get("mineral_max", 3)) + " 种"
	elif resin_count < rules.get("resin_min", 1):
		err = "需要至少 " + str(rules.get("resin_min", 1)) + " 种树脂素材"
	elif resin_count > rules.get("resin_max", 2):
		err = "树脂素材最多 " + str(rules.get("resin_max", 2)) + " 种"
	elif total_count < rules.get("total_min", 3):
		err = "至少需要 " + str(rules.get("total_min", 3)) + " 种素材（当前" + str(total_count) + "种）"
	elif total_count > rules.get("total_max", 8):
		err = "最多 " + str(rules.get("total_max", 8)) + " 种素材（当前" + str(total_count) + "种）"
	
	if err != "":
		_hint_label.text = err
		_hint_label.add_theme_color_override("font_color", Color("#FF5252"))
		return
	
	_hint_label.text = ""
	
	# 弹出制作确认弹窗
	_show_make_confirm_dialog()


func _on_back():
	Global.play_sfx("click")
	Global.change_scene("res://CardWorkshop.tscn")


func _on_help():
	Global.play_sfx("click")
	_show_help_guide()

## 显示卡基制作指南弹窗
func _show_help_guide():
	var overlay = ColorRect.new()
	overlay.name = "HelpOverlay"
	overlay.color = Color(0, 0, 0, 0.7)
	overlay.anchor_left = 0.0; overlay.anchor_top = 0.0
	overlay.anchor_right = 1.0; overlay.anchor_bottom = 1.0
	overlay.mouse_filter = MOUSE_FILTER_STOP
	overlay.gui_input.connect(func(ev: InputEvent):
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
	
	# 标题
	var title = Label.new()
	title.text = "卡基制作指南"
	title.add_theme_font_size_override("font_size", 60)
	title.add_theme_color_override("font_color", Global.current.title)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.anchor_left = 0.0; title.anchor_top = 0.0
	title.anchor_right = 1.0; title.anchor_bottom = 0.0
	title.offset_left = 0; title.offset_top = Global.ph(0.01)
	title.offset_right = 0; title.offset_bottom = Global.ph(0.08)
	panel.add_child(title)
	
	# 滚动区域
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
	
	# 构建指南内容
	_build_help_content(vbox)
	
	# 延迟一帧设置宽度，让布局完成后生效
	call_deferred("_set_help_vbox_width", vbox, scroll)
	
	# 关闭按钮
	var close_btn = Button.new()
	close_btn.text = "关闭"
	close_btn.add_theme_font_size_override("font_size", 50)
	var cs = StyleBoxFlat.new()
	cs.bg_color = Global.current.btn_bg
	cs.border_width_left = 2; cs.border_width_right = 2
	cs.border_width_top = 2; cs.border_width_bottom = 2
	cs.border_color = Color("#888888")
	cs.corner_radius_top_left = 10; cs.corner_radius_top_right = 10
	cs.corner_radius_bottom_left = 10; cs.corner_radius_bottom_right = 10
	close_btn.add_theme_stylebox_override("normal", cs)
	close_btn.add_theme_color_override("font_color", Global.current.btn_text)
	close_btn.anchor_left = 0.3; close_btn.anchor_top = 1.0
	close_btn.anchor_right = 0.7; close_btn.anchor_bottom = 1.0
	close_btn.offset_left = 0; close_btn.offset_top = Global.ph(-0.075)
	close_btn.offset_right = 0; close_btn.offset_bottom = Global.ph(-0.01)
	close_btn.pressed.connect(overlay.queue_free)
	panel.add_child(close_btn)


func _set_help_vbox_width(vbox: VBoxContainer, scroll: ScrollContainer):
	if not is_instance_valid(vbox) or not is_instance_valid(scroll):
		return
	var w = scroll.size.x
	if w <= 0:
		w = get_viewport_rect().size.x * 0.85
	vbox.custom_minimum_size = Vector2(w, 0)


func _make_help_section(vbox: VBoxContainer, title_text: String, title_color: Color) -> VBoxContainer:
	var section = VBoxContainer.new()
	section.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	section.add_theme_constant_override("separation", Global.ph(0.005))
	vbox.add_child(section)
	
	var sep = HSeparator.new()
	sep.add_theme_color_override("color", Global.current.topbar_border)
	sep.size_flags_horizontal = SIZE_FILL
	section.add_child(sep)
	
	var lbl = Label.new()
	lbl.text = title_text
	lbl.add_theme_font_size_override("font_size", 50)
	lbl.add_theme_color_override("font_color", title_color)
	lbl.size_flags_horizontal = SIZE_FILL
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	section.add_child(lbl)
	
	return section


func _make_help_row(vbox: VBoxContainer, left: String, right: String, right_color: Color = Color("#FFFFFF")):
	var row = HBoxContainer.new()
	row.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	vbox.add_child(row)
	
	var l = Label.new()
	l.text = left + "  " + right
	l.add_theme_font_size_override("font_size", 45)
	l.add_theme_color_override("font_color", Global.current.btn_text)
	l.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(l)


func _make_help_label(vbox: VBoxContainer, text: String, color: Color = Color("#FFFFFF"), font_size: int = 45):
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.size_flags_horizontal = SIZE_FILL
	vbox.add_child(lbl)


func _build_help_content(vbox: VBoxContainer):
	# 1. 输入规则
	var s1 = _make_help_section(vbox, " ① 输入规则", Color("#FF9800"))
	_make_help_label(s1, "制作卡基需要选择三种素材，每种有数量限制：", Global.current.btn_text, 42)
	_make_help_row(s1, "  纤维素材", "1 ~ 3 种", Color("#8BC34A"))
	_make_help_row(s1, " 矿粉素材", "1 ~ 3 种", Color("#FF9800"))
	_make_help_row(s1, " 树脂素材", "1 ~ 2 种", Color("#E91E63"))
	_make_help_row(s1, " 素材总数", "3 ~ 8 种", Color("#FFD700"))
	
	# 2. 素材属性说明
	var s2 = _make_help_section(vbox, " ② 素材属性说明", Color("#3498DB"))
	_make_help_label(s2, "每种素材有独有属性，影响成品卡基的最终数值：", Global.current.btn_text, 42)
	
	_make_help_label(s2, " 纤维素材", Color("#8BC34A"), 48)
	_make_help_label(s2, "  • 承载力 (carry)：影响卡基的【卡槽】数量", Color("#CCCCCC"))
	_make_help_label(s2, "  • 韧性 (toughness)：影响卡基的【耐久度】", Color("#CCCCCC"))
	
	_make_help_label(s2, " 矿粉素材", Color("#FF9800"), 48)
	_make_help_label(s2, "  • 硬度 (hardness)：影响卡基的【承载力】", Color("#CCCCCC"))
	_make_help_label(s2, "  • 稳定性 (stability)：影响【卡槽】和【品质下限】", Color("#CCCCCC"))
	
	_make_help_label(s2, " 树脂素材", Color("#E91E63"), 48)
	_make_help_label(s2, "  • 光泽 (gloss)：影响【承载力】和【品质上限】", Color("#CCCCCC"))
	_make_help_label(s2, "  • 粘合度 (bond)：影响卡基的【耐久度】", Color("#CCCCCC"))
	
	_make_help_label(s2, " 共通属性", Color("#FFD700"), 48)
	_make_help_label(s2, "  • 倾向 (tendency)：所有素材的倾向值累加，决定卡基的【元素倾向】", Color("#CCCCCC"))
	_make_help_label(s2, "  • 稀有度：影响素材边框颜色（普通/稀有/史诗/传说）", Color("#CCCCCC"))
	
	# 3. 计算公式
	var s3 = _make_help_section(vbox, " ③ 计算公式", Color("#9B59B6"))
	
	_make_help_label(s3, " 承载力 (Load Cap)", Color("#FF9800"), 48)
	_make_help_label(s3, "公式：min( Σ(矿粉硬度)×2 + Σ(树脂光泽)×1 + 5 , 30 )", Color("#FFD700"), 42)
	_make_help_label(s3, "→ 矿粉硬度越高、树脂光泽越多，承载力越大，上限30", Color("#CCCCCC"))
	_make_help_label(s3, "→ 承载力决定卡基能承载多少纹路效果", Color("#CCCCCC"))
	
	_make_help_label(s3, " 卡槽 (Slots)", Color("#8BC34A"), 48)
	_make_help_label(s3, "公式：min( floor( Σ(纤维承载力)×0.5 + Σ(矿粉稳定性)×0.3 ) + 2 , 12 )", Color("#FFD700"), 42)
	_make_help_label(s3, "→ 纤维承载力和矿粉稳定性越高，卡槽越多，上限12", Color("#CCCCCC"))
	_make_help_label(s3, "→ 卡槽数 = 可安装的纹路组件数量", Color("#CCCCCC"))
	
	_make_help_label(s3, " 耐久度 (Durability)", Color("#E91E63"), 48)
	_make_help_label(s3, "公式：min( 5 + Σ(纤维韧性)×3 + Σ(树脂粘合度)×2 , 60 )", Color("#FFD700"), 42)
	_make_help_label(s3, "→ 纤维韧性和树脂粘合度越高，耐久度越高，上限60", Color("#CCCCCC"))
	_make_help_label(s3, "→ 耐久度影响卡牌在战斗中的使用次数", Color("#CCCCCC"))
	
	_make_help_label(s3, " 品质 (Quality)", Color("#9B59B6"), 48)
	_make_help_label(s3, "品质下限 = floor( Σ(矿粉稳定性) / 矿粉种类数 )", Color("#FFD700"), 42)
	_make_help_label(s3, "品质上限 = floor( Σ(树脂光泽) / 树脂种类数 )", Color("#FFD700"), 42)
	_make_help_label(s3, "映射关系：", Color("#CCCCCC"))
	_make_help_label(s3, "  0 → 废品  |  1 → 瑕疵  |  2 → 标准  |  3 → 卓越  |  4+ → 完美", Color("#AAAAAA"))
	_make_help_label(s3, "最终品质范围：下限 ~ 上限（如「标准 ~ 卓越」）", Color("#CCCCCC"))
	
	_make_help_label(s3, " 倾向 (Tendency)", Color("#FFD700"), 48)
	_make_help_label(s3, "公式：Σ(所有纤维/矿粉/树脂素材的倾向值)", Color("#FFD700"), 42)
	_make_help_label(s3, "→ 倾向值格式：元素+数字，如「火3」表示火系倾向+3", Color("#CCCCCC"))
	_make_help_label(s3, "→ 倾向最高的元素成为卡基的主元素", Color("#CCCCCC"))
	
	# 4. 素材惩罚
	var s4 = _make_help_section(vbox, " ④ 素材惩罚", Color("#FF5252"))
	_make_help_label(s4, "素材总数越多，制作难度越大，品质会受影响：", Global.current.btn_text, 42)
	_make_help_row(s4, "3 ~ 4 种素材", "无惩罚 ", Color("#4CAF50"))
	_make_help_row(s4, "5 ~ 6 种素材", "品质下限-1", Color("#FF9800"))
	_make_help_row(s4, "7 ~ 8 种素材", "品质下限-2，品质上限-1", Color("#FF5252"))
	_make_help_label(s4, " 建议：在满足需求的前提下，尽量用少的素材种类来避免惩罚！", Color("#FFD700"), 42)
	
	# 5. 制作步骤
	var s5 = _make_help_section(vbox, " ⑤ 制作步骤", Color("#4CAF50"))
	_make_help_label(s5, "1. 点击「选择」按钮，从仓库中选择素材", Global.current.btn_text, 42)
	_make_help_label(s5, "2. 用 [-] [+] 调整每种素材的数量", Global.current.btn_text, 42)
	_make_help_label(s5, "3. 在「卡基属性预览」中查看实时计算结果", Global.current.btn_text, 42)
	_make_help_label(s5, "4. 点击「开始制作」生成卡基", Global.current.btn_text, 42)
	_make_help_label(s5, "5. 制作好的卡基会存入仓库，可在刻画界面选择使用", Global.current.btn_text, 42)
	_make_help_label(s5, " 长按素材行可查看详情", Color("#FFD700"), 42)
	
	# 底部留白
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, Global.ph(0.02))
	vbox.add_child(spacer)


func _on_theme_changed(_mode):
	var bg = get_node_or_null("Background")
	if bg: Global.apply_bg(bg)
	
	var topbar = get_node_or_null("TopBar")
	if topbar and topbar is ColorRect:
		topbar.color = Global.current.topbar_bg
	
	var topbar_line = get_node_or_null("TopBarLine")
	if topbar_line and topbar_line is ColorRect:
		topbar_line.color = Global.current.topbar_border
	
	var title = get_node_or_null("Title")
	if title and title is Label:
		title.add_theme_color_override("font_color", Global.current.title)
		title.add_theme_color_override("font_shadow_color", Global.current.title_shadow)
	# 刷新分类面板颜色
	for key in ["fiber", "mineral", "resin"]:
		var row = get_node_or_null("ContentScroll/ContentVBox/CatRow_" + key)
		if row and row is Panel:
			row.add_theme_stylebox_override("panel", _make_card_style())
	
	# 刷新预览面板
	var prev = get_node_or_null("ContentScroll/ContentVBox/PreviewPanel")
	if prev and prev is Panel:
		prev.add_theme_stylebox_override("panel", _make_card_style())


# ============================
# ===== 制作确认弹窗 =====
var _confirm_qty: int = 1
var _confirm_overlay: ColorRect = null
var _consume_rows := []  # 每项: {name_label, total_label, stock}

func _show_make_confirm_dialog():
	var overlay = ColorRect.new()
	_confirm_overlay = overlay
	overlay.name = "ConfirmOverlay"
	overlay.color = Color(0, 0, 0, 0.6)
	overlay.anchor_left = 0.0
	overlay.anchor_top = 0.0
	overlay.anchor_right = 1.0
	overlay.anchor_bottom = 1.0
	overlay.mouse_filter = MOUSE_FILTER_STOP
	add_child(overlay)
	
	var panel = Panel.new()
	panel.name = "ConfirmPanel"
	panel.anchor_left = 0.08
	panel.anchor_top = 0.2
	panel.anchor_right = 0.92
	panel.anchor_bottom = 0.8
	# panel.clip_contents = true  # 关掉裁剪，让内容正常显示
	var cps = StyleBoxFlat.new()
	cps.bg_color = Global.current.bg
	cps.border_width_left = 3
	cps.border_width_right = 3
	cps.border_width_top = 3
	cps.border_width_bottom = 3
	cps.border_color = Global.current.topbar_border
	cps.corner_radius_top_left = 16
	cps.corner_radius_top_right = 16
	cps.corner_radius_bottom_left = 16
	cps.corner_radius_bottom_right = 16
	panel.add_theme_stylebox_override("panel", cps)
	overlay.add_child(panel)
	
	var margin = Global.pw(0.04)
	var top_margin = Global.ph(0.02)
	var bottom_margin = Global.ph(-0.02)

	# 主 VBox 容器（锚定撑满 Panel）
	var vbox = VBoxContainer.new()
	vbox.name = "ConfirmVBox"
	vbox.anchor_left = 0.0
	vbox.anchor_top = 0.0
	vbox.anchor_right = 1.0
	vbox.anchor_bottom = 1.0
	vbox.offset_left = margin
	vbox.offset_top = top_margin
	vbox.offset_right = -margin
	vbox.offset_bottom = bottom_margin
	vbox.add_theme_constant_override("separation", 0)
	panel.add_child(vbox)

	# 标题（固定高度）
	var title_label = Label.new()
	title_label.text = "确认制作"
	title_label.add_theme_font_size_override("font_size", 55)
	title_label.add_theme_color_override("font_color", Global.current.title)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.custom_minimum_size = Vector2(0, Global.ph(0.07))
	title_label.size_flags_vertical = SIZE_SHRINK_CENTER
	vbox.add_child(title_label)

	# 标题分隔线（固定高度）
	var line = HSeparator.new()
	line.add_theme_color_override("color", Global.current.topbar_border)
	line.custom_minimum_size = Vector2(0, Global.ph(0.005))
	vbox.add_child(line)

	# 可滚动区域（填充剩余空间）
	var scroll = ScrollContainer.new()
	scroll.name = "ConfirmScroll"
	scroll.size_flags_vertical = SIZE_EXPAND | SIZE_FILL
	scroll.scroll_horizontal = false
	scroll.scroll_vertical = true
	vbox.add_child(scroll)

	var scroll_vbox = VBoxContainer.new()
	scroll_vbox.name = "ScrollVBox"
	scroll_vbox.size_flags_horizontal = SIZE_FILL
	scroll.add_child(scroll_vbox)

	# 底部按钮行分隔线
	var bottom_line = HSeparator.new()
	bottom_line.add_theme_color_override("color", Global.current.topbar_border)
	bottom_line.custom_minimum_size = Vector2(0, Global.ph(0.005))
	vbox.add_child(bottom_line)

	# 按钮行（固定高度）
	var btn_row = HBoxContainer.new()
	btn_row.size_flags_horizontal = SIZE_FILL
	btn_row.custom_minimum_size = Vector2(0, Global.ph(0.07))
	btn_row.add_theme_constant_override("separation", Global.pw(0.04))
	vbox.add_child(btn_row)

	var cancel_btn = Button.new()
	cancel_btn.text = "取消"
	cancel_btn.add_theme_font_size_override("font_size", 50)
	cancel_btn.size_flags_horizontal = SIZE_FILL
	cancel_btn.size_flags_stretch_ratio = 1.0
	var ccs = StyleBoxFlat.new()
	ccs.bg_color = Global.current.btn_bg
	ccs.border_width_left = 2
	ccs.border_width_right = 2
	ccs.border_width_top = 2
	ccs.border_width_bottom = 2
	ccs.border_color = Color("#888888")
	ccs.corner_radius_top_left = 10
	ccs.corner_radius_top_right = 10
	ccs.corner_radius_bottom_left = 10
	ccs.corner_radius_bottom_right = 10
	cancel_btn.add_theme_stylebox_override("normal", ccs)
	cancel_btn.add_theme_color_override("font_color", Global.current.btn_text)
	cancel_btn.pressed.connect(func(): _close_make_confirm())
	btn_row.add_child(cancel_btn)

	var confirm_btn = Button.new()
	confirm_btn.text = "确认制作"
	confirm_btn.add_theme_font_size_override("font_size", 50)
	confirm_btn.size_flags_horizontal = SIZE_FILL
	confirm_btn.size_flags_stretch_ratio = 1.0
	var cfs = StyleBoxFlat.new()
	cfs.bg_color = Global.current.btn_bg_hover
	cfs.border_width_left = 2
	cfs.border_width_right = 2
	cfs.border_width_top = 2
	cfs.border_width_bottom = 2
	cfs.border_color = Color("#4CAF50")
	cfs.corner_radius_top_left = 10
	cfs.corner_radius_top_right = 10
	cfs.corner_radius_bottom_left = 10
	cfs.corner_radius_bottom_right = 10
	confirm_btn.add_theme_stylebox_override("normal", cfs)
	confirm_btn.add_theme_color_override("font_color", Global.current.btn_text)
	confirm_btn.pressed.connect(func(): _on_confirm_make())
	btn_row.add_child(confirm_btn)
	
	var warehouse = get_node("/root/WarehouseManager")
	var inv = warehouse.get_materials()
	
	# 表头
	var header = HBoxContainer.new()
	header.size_flags_horizontal = SIZE_FILL
	scroll_vbox.add_child(header)
	var header_left = Label.new()
	header_left.text = "单份消耗"
	header_left.add_theme_font_size_override("font_size", 50)
	header_left.add_theme_color_override("font_color", Global.current.title)
	header_left.size_flags_horizontal = SIZE_EXPAND
	header.add_child(header_left)
	var header_right = Label.new()
	header_right.text = "总消耗"
	header_right.add_theme_font_size_override("font_size", 50)
	header_right.add_theme_color_override("font_color", Global.current.title)
	header_right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header_right.size_flags_horizontal = SIZE_FILL
	header.add_child(header_right)
	
	var line2 = HSeparator.new()
	line2.add_theme_color_override("color", Global.current.topbar_border)
	scroll_vbox.add_child(line2)
	
	_consume_rows.clear()
	var max_qty := 999999
	for key in _selected.keys():
		for mid in _selected[key].keys():
			var qty = _selected[key][mid]
			var stock = inv.get(mid, 0)
			var per_stock = floor(stock / qty) if qty > 0 else 0
			max_qty = min(max_qty, per_stock)
			var mat = Global.get_material_by_id(mid)
			if not mat.is_empty() and qty > 0:
				var mat_name = mat.get("name", mid)
				var row = HBoxContainer.new()
				row.size_flags_horizontal = SIZE_FILL
				scroll_vbox.add_child(row)
				
				var name_label = Label.new()
				name_label.text = "" + mat_name + "×" + str(qty)
				name_label.add_theme_font_size_override("font_size", 50)
				name_label.add_theme_color_override("font_color", Global.current.btn_text)
				name_label.size_flags_horizontal = SIZE_EXPAND
				row.add_child(name_label)
				
				var total_label = Label.new()
				var total_need = _confirm_qty * qty
				total_label.text = "(" + str(total_need) + "/" + str(stock) + ")"
				total_label.add_theme_font_size_override("font_size", 50)
				total_label.add_theme_color_override("font_color", Global.current.btn_text)
				total_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
				total_label.size_flags_horizontal = SIZE_FILL
				row.add_child(total_label)
				
				_consume_rows.append({"name_label": name_label, "total_label": total_label, "stock": stock, "per_qty": qty})
	
	if max_qty <= 0:
		max_qty = 0
	_confirm_qty = min(1, max_qty)
	if _confirm_qty < 1:
		_confirm_qty = 0
	
	var qty_row = HBoxContainer.new()
	qty_row.name = "QtyRow"
	qty_row.size_flags_horizontal = SIZE_FILL
	scroll_vbox.add_child(qty_row)
	
	var qty_label = Label.new()
	qty_label.text = "制作数量："
	qty_label.add_theme_font_size_override("font_size", 50)
	qty_label.add_theme_color_override("font_color", Global.current.title)
	qty_label.size_flags_horizontal = SIZE_EXPAND
	qty_row.add_child(qty_label)
	
	var dec_btn = Button.new()
	dec_btn.text = "—"
	dec_btn.add_theme_font_size_override("font_size", 50)
	dec_btn.custom_minimum_size = Vector2(Global.pw(0.08), Global.ph(0.06))
	dec_btn.pressed.connect(func(): _on_confirm_qty_change(-1))
	qty_row.add_child(dec_btn)
	
	var qty_val = Label.new()
	qty_val.name = "ConfirmQtyVal"
	qty_val.text = str(_confirm_qty)
	qty_val.add_theme_font_size_override("font_size", 50)
	qty_val.add_theme_color_override("font_color", Global.current.title)
	qty_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	qty_val.custom_minimum_size = Vector2(Global.pw(0.1), 0)
	qty_row.add_child(qty_val)
	
	var inc_btn = Button.new()
	inc_btn.text = "+"
	inc_btn.add_theme_font_size_override("font_size", 50)
	inc_btn.custom_minimum_size = Vector2(Global.pw(0.12), Global.ph(0.08))
	inc_btn.pressed.connect(func(): _on_confirm_qty_change(1))
	qty_row.add_child(inc_btn)
	
	var total_label = Label.new()
	total_label.name = "TotalConsume"
	total_label.text = "本次消耗：制作 x" + str(_confirm_qty)
	total_label.add_theme_font_size_override("font_size", 50)
	total_label.add_theme_color_override("font_color", Color("#FF9800"))
	total_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scroll_vbox.add_child(total_label)


func _on_confirm_qty_change(delta: int):
	print("[调试] 数量变更被调用了！delta=", delta)
	var overlay = _confirm_overlay
	if not overlay or not is_instance_valid(overlay):
		return
	var warehouse = get_node("/root/WarehouseManager")
	var inv = warehouse.get_materials()
	var max_qty := 999999
	for key in _selected.keys():
		for mid in _selected[key].keys():
			var qty = _selected[key][mid]
			var stock = inv.get(mid, 0)
			var per_stock = floor(stock / qty) if qty > 0 else 0
			max_qty = min(max_qty, per_stock)
	if max_qty <= 0:
		max_qty = 0
	
	var new_qty = _confirm_qty + delta
	new_qty = clamp(new_qty, 1, max_qty)
	if max_qty <= 0:
		new_qty = 0
	_confirm_qty = new_qty
	
	var qty_val = overlay.get_node_or_null("ConfirmPanel/ConfirmVBox/ConfirmScroll/ScrollVBox/QtyRow/ConfirmQtyVal")
	if qty_val:
		qty_val.text = str(_confirm_qty)
	
	# 更新总消耗列
	for entry in _consume_rows:
		var n = entry["total_label"]
		var s = entry["stock"]
		var pq = entry.get("per_qty", 1)
		n.text = "(" + str(_confirm_qty * pq) + "/" + str(s) + ")"


func _on_confirm_make():
	var overlay = _confirm_overlay
	if not overlay or not is_instance_valid(overlay):
		return
	if _confirm_qty <= 0:
		# ★ 弹窗内显示错误提示（不要依赖主界面 hint_label，被弹窗遮罩盖住看不到）
		if _hint_label:
			_hint_label.add_theme_color_override("font_color", Color("#FF5252"))
			_hint_label.text = "素材不足，无法制作！"
		# 弹窗内加醒目错误提示，避免"点了没反应"错觉
		_close_make_confirm()
		_show_popup(" 素材不足，无法制作！请检查仓库库存", Color("#FF6B6B"))
		return
	
	var warehouse = get_node("/root/WarehouseManager")
	var inv = warehouse.get_materials()
	# 检查每种素材库存是否足够
	for key in _selected.keys():
		for mid in _selected[key].keys():
			var qty = _selected[key][mid]
			var stock = inv.get(mid, 0)
			if stock < _confirm_qty * qty:
				if _hint_label:
					_hint_label.add_theme_color_override("font_color", Color("#FF5252"))
					var mat = Global.get_material_by_id(mid)
					var msg = "素材不足！" + mat.get("name", mid) + " 需要" + str(_confirm_qty * qty) + " 仅剩" + str(stock) + "个"
					_hint_label.text = msg
				# ★ 弹窗内也显示，避免"点了没反应"
				_close_make_confirm()
				_show_popup(" " + _hint_label.text, Color("#FF6B6B"))
				return
	
	# 计算属性（复用预览逻辑）
	var fiber_mats := []
	var mineral_mats := []
	var resin_mats := []
	for mid in _selected["fiber"].keys():
		var qty = _selected["fiber"][mid]
		var mat = Global.get_material_by_id(mid)
		if not mat.is_empty():
			for j in range(qty):
				fiber_mats.append(mat)
	for mid in _selected["mineral"].keys():
		var qty = _selected["mineral"][mid]
		var mat = Global.get_material_by_id(mid)
		if not mat.is_empty():
			for j in range(qty):
				mineral_mats.append(mat)
	for mid in _selected["resin"].keys():
		var qty = _selected["resin"][mid]
		var mat = Global.get_material_by_id(mid)
		if not mat.is_empty():
			for j in range(qty):
				resin_mats.append(mat)
	
	var load_cap = _calc_load_cap(mineral_mats, resin_mats)
	var slots = _calc_slots(fiber_mats, mineral_mats)
	var durability = _calc_durability(fiber_mats, resin_mats)
	var quality = _calc_quality(mineral_mats, resin_mats)
	var tendency = _calc_tendency(fiber_mats, mineral_mats, resin_mats)
	
	# 先一次性消耗所有素材
	for key in _selected.keys():
		for mid in _selected[key].keys():
			var qty = _selected[key][mid]
			warehouse.consume_material(mid, qty * _confirm_qty)
	
	# 生成卡基中文名（用素材名拼接，和卡墨风格一致）
	# 生成卡基中文名（取每个素材名的前2字，用+连接，简洁）
	var base_name_parts := []
	for _key in _selected.keys():
		for _mid in _selected[_key].keys():
			var _mat = Global.get_material_by_id(_mid)
			if not _mat.is_empty():
				var _nm = _mat.get("name", _mid)
				# 取前2个字
				var _short = _nm.substr(0, mini(_nm.length(), 2))
				if not _short in base_name_parts:
					base_name_parts.append(_short)
	var card_base_name = "卡基·"
	if base_name_parts.size() <= 3:
		card_base_name += "+".join(base_name_parts)
	else:
		card_base_name += "+".join(base_name_parts.slice(0, 3)) + "等"


	# 再循环保存每个卡基
	for i in range(_confirm_qty):
		var card_base_id = "CB_" + str(Time.get_unix_time_from_system()) + "_" + str(i)
		var card_base_data = {
			"id": card_base_id,
			"name": card_base_name,
			"materials": _selected.duplicate(true),
			"load_cap": load_cap,
			"slots": slots,
			"durability": durability,
			"quality": quality,
			"tendency": tendency.duplicate(),
			"created_at": Time.get_unix_time_from_system()
		}
		warehouse.add_card_base(card_base_data)
		print("[卡基制作] 制作成功！ID: ", card_base_id)
	
	_close_make_confirm()
	
	for key in _selected.keys():
		_selected[key].clear()
	_update_ui()
	
	if _hint_label:
		_hint_label.add_theme_color_override("font_color", Color("#4CAF50"))
		_hint_label.text = "成功制作 " + str(_confirm_qty) + " 个卡基！"
	
	# 教程引导：制作成功 → 弹"完成祝贺+看预览属性回顾"
	if _tutorial_done == false:
		_advance_tutorial("made")
	else:
		# 弹出成功提示
		_show_popup(" 成功制作 " + str(_confirm_qty) + " 个卡基！", Color("#81C784"))

func _close_make_confirm():
	var overlay = _confirm_overlay
	if overlay and is_instance_valid(overlay):
		overlay.queue_free()
	_confirm_overlay = null


# ============================
#  教程引导（对话式 · 操作驱动）
# ============================
## 仅教程阶段（制卡幕 进度==2）触发；完成后不再弹
func _start_tutorial_if_needed() -> void:
	if _tutorial_done or TutorialManager.get_progress() != TutorialManager.PROGRESS_FIRST_BATTLE:
		return
	# 已看过卡基引导则跳过（存档标记，防重进场景重复弹）
	if SaveManager.get_value("tutorial", "card_base_guide_seen", false):
		_tutorial_done = true
		return
	SaveManager.set_value("tutorial", "card_base_guide_seen", true)
	SaveManager.save_to_disk()
	_tutorial_step = 0
	_show_tutorial_dialogue([
		{"speaker": "老陈", "text": "这就是卡基台。卡牌的身板，全靠它撑。纤维、矿粉、树脂，三样东西合一块儿。"},
		{"speaker": "你", "text": "（打量工具台）得先挑材料？"},
		{"speaker": "老陈", "text": "每栏点【选素材】，先各挑一个。挑完我教你看门道。"},
	])

## 推进教程：trigger 匹配当前步骤
## "mats_ready" 素材选齐 → 讲预览；"made" 制作成功 → 收尾
func _advance_tutorial(trigger: String) -> void:
	if _tutorial_done:
		return
	match _tutorial_step:
		0:
			return  # 开场对话点完按钮直接推进（由对话回调触发）
		1:
			if trigger == "mats_ready":
				_tutorial_step = 2
				_show_tutorial_dialogue([
					{"speaker": "老陈", "text": "看底下那栏【卡基属性预览】——五个属性，决定了你卡牌的底子。"},
					{"speaker": "老陈", "text": " 承载力——决定卡牌能扛多少纹路和数值，承载力越高，能刻的料越足。"},
					{"speaker": "老陈", "text": " 卡槽——决定能装几个纹路组件。槽越多，卡牌花活越多。"},
					{"speaker": "老陈", "text": " 耐久度——卡牌在战斗里能用多少次。耐久越高，越经打。"},
					{"speaker": "老陈", "text": " 品质——从低到高分废品、瑕疵、标准、卓越、完美。品质越高，基础数值越猛。"},
					{"speaker": "老陈", "text": " 倾向——卡牌的‘性格’，火水土风……不同倾向影响卡牌能配什么纹路和打法。"},
					{"speaker": "老陈", "text": "素材选够了，点【制作卡基】试试？"},
				], func():
					_tutorial_step = 3  # 进入"等制作"状态
				)
		2:
			pass  # 讲解预览，点完按钮后进入3
		3:
			if trigger == "made":
				_tutorial_step = 4
				_tutorial_done = true
				_show_tutorial_dialogue([
					{"speaker": "老陈", "text": "成了！一个能用的卡基到手，身板挺结实。"},
					{"speaker": "你", "text": "看着还行……下一步呢？"},
					{"speaker": "老陈", "text": "光有身子不行，还得有墨。去【调制卡墨】那台看看，我等你。"},
				])
		4:
			return

## 弹对话式引导弹窗；on_finish 可选（一般用于步骤推进）
func _show_tutorial_dialogue(lines: Array, on_finish: Callable = Callable()) -> void:
	_close_tutorial_overlay()
	var popup = preload("res://TutorialDialoguePopup.gd").new()
	popup.setup(lines, func():
		# 开场对话（step0）点完 → 进入 step1（等选素材）
		if _tutorial_step == 0:
			_tutorial_step = 1
		elif on_finish.is_valid():
			on_finish.call()
	)
	add_child(popup)

func _close_tutorial_overlay() -> void:
	# 同一时间只保留一个对话弹窗
	for child in get_children():
		if child is TutorialDialoguePopup:
			child.queue_free()

# ============================
#  弹窗工具
# ============================
func _show_popup(text: String, color: Color):
	var existing = get_node_or_null("PopupOverlay")
	if existing:
		existing.queue_free()
	
	var overlay = ColorRect.new()
	overlay.name = "PopupOverlay"
	overlay.color = Color(0, 0, 0, 0.5)
	overlay.anchor_left = 0.0; overlay.anchor_top = 0.0; overlay.anchor_right = 1.0; overlay.anchor_bottom = 1.0
	overlay.mouse_filter = MOUSE_FILTER_STOP
	overlay.gui_input.connect(_on_popup_click.bind(overlay))
	add_child(overlay)
	
	var panel = Panel.new()
	panel.anchor_left = 0.2; panel.anchor_top = 0.35; panel.anchor_right = 0.8; panel.anchor_bottom = 0.65
	var ps = StyleBoxFlat.new()
	ps.bg_color = Global.current.bg
	ps.border_width_left = 3; ps.border_width_right = 3; ps.border_width_top = 3; ps.border_width_bottom = 3
	ps.border_color = color
	ps.corner_radius_top_left = 16; ps.corner_radius_top_right = 16
	ps.corner_radius_bottom_left = 16; ps.corner_radius_bottom_right = 16
	panel.add_theme_stylebox_override("panel", ps)
	overlay.add_child(panel)
	
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 50)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.anchor_left = 0.0; label.anchor_top = 0.0; label.anchor_right = 1.0; label.anchor_bottom = 1.0
	panel.add_child(label)
	
	var timer = get_tree().create_timer(1.5)
	timer.timeout.connect(_close_popup.bind(overlay))


func _on_popup_click(event: InputEvent, overlay: ColorRect):
	if event is InputEventMouseButton and event.pressed:
		_close_popup(overlay)


func _close_popup(overlay):
	if overlay and is_instance_valid(overlay):
		overlay.queue_free()

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
	# ★ 创建底部提示 Label（之前从未初始化导致 _on_make 里 if not _hint_label: return 按钮点了没反应）
	if not _hint_label:
		_hint_label = Label.new()
		_hint_label.name = "HintLabel"
		_hint_label.add_theme_font_size_override("font_size", 42)
		_hint_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.7))
		_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_hint_label.text = "选择各类素材开始制作卡基"
		# 挂到 BottomBar 上
		var bottom_bar = get_node_or_null("BottomBar")
		if bottom_bar:
			_hint_label.anchor_left = 0.05
			_hint_label.anchor_top = 0.0
			_hint_label.anchor_right = 0.95
			_hint_label.anchor_bottom = 1.0
			_hint_label.offset_top = Global.ph(0.02)
			_hint_label.offset_bottom = Global.ph(-0.02)
			_hint_label.size_flags_vertical = SIZE_SHRINK_CENTER
			bottom_bar.add_child(_hint_label)
		else:
			add_child(_hint_label)
	var vbox = get_node_or_null("ContentScroll/ContentVBox")
	if not vbox: return
	# 内容区左右留白 + 卡片间距：tscn 里 ContentScroll 锚满整宽，
	# 素材卡/预览面板会紧贴屏幕左右边缘并且彼此相连（VBox 默认 separation=0）。
	var scroll := get_node_or_null("ContentScroll") as ScrollContainer
	if scroll:
		scroll.offset_left = Global.pw(0.03)
		scroll.offset_right = Global.pw(-0.03)
	vbox.add_theme_constant_override("separation", int(Global.ph(0.014)))
	_build_material_section(vbox)
	_build_preview_section(vbox)
	_build_make_button(vbox)
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, Global.ph(0.15))
	vbox.add_child(spacer)
	# ★ 启动卡基制作教程引导
	_start_tutorial_if_needed()
