extends Control

# ============================
#  调制卡墨 - 主脚本
# ============================
# 投入规则：萃取液 1~2种 + 颜料 1~2种 + 粘合剂 1~2种（最少3种，最多6种）
# 无材料数量惩罚，每种素材最多选1个

const MAX_COUNT := {"extract": 2, "pigment": 2, "binder": 2}
const TOTAL_MIN := 3
const TOTAL_MAX := 6

var _selected := {
	"extract": {},
	"pigment": {},
	"binder": {}
}

var _preview_labels := {}
var _category_labels := {}
var _hint_label: Label = null

# 长按相关
var _picker_long_press_timer: float = 0.0
var _picker_long_press_row = null
var _picker_long_press_mat: Dictionary = {}
var _picker_long_press_active: bool = false
# 教程引导状态：-1=未开始，0=欢迎，1=选素材，2=预览讲解，3=制作，4=完成
var _tutorial_step: int = -1
var _tutorial_popup_overlay: Control = null
var _tutorial_done: bool = false
# ============================
#  _ready() 构建界面
# ============================
func _ready():
	# ---- 静态节点已在 InkMaking.tscn 中声明 ----
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
## 原先用 topbar_bg：白天主题下 TopBar 与页面底色恰好也是同一个米色，
## 三张素材卡 + 预览面板整块糊成一片，完全看不出分区（还只剩圆角边缘的锯齿）。
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
		{"key": "extract", "label": " 萃取液", "color": Color("#4FC3F7")},
		{"key": "pigment", "label": " 颜料", "color": Color("#FF8A65")},
		{"key": "binder", "label": " 粘合剂", "color": Color("#81C784")},
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
		# 原先写死 ph(0.15)=288 而内容实际只有 ~190，每张卡下面挂着大片空白。
		row.custom_minimum_size = Vector2(0, vbox_inner.get_combined_minimum_size().y + Global.ph(0.014))


# ============================
#  素材选择弹窗
# ============================
func _on_select_material(cat_key: String):
	if _get_cat_total(cat_key) >= MAX_COUNT[cat_key]:
		return
	if _get_total_count() >= TOTAL_MAX:
		return
	_show_material_picker(cat_key)


func _show_material_picker(cat_key: String):
	var overlay = ColorRect.new()
	overlay.name = "PickerOverlay"
	overlay.color = Color(0, 0, 0, 0.6)
	overlay.anchor_left = 0.0
	overlay.anchor_top = 0.0
	overlay.anchor_right = 1.0
	overlay.anchor_bottom = 1.0
	overlay.mouse_filter = MOUSE_FILTER_STOP
	add_child(overlay)
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
	var cat_names = {"extract": "萃取液", "pigment": "颜料", "binder": "粘合剂"}
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
		"extract": mat_list = Global.get_extract_list()
		"pigment": mat_list = Global.get_pigment_list()
		"binder": mat_list = Global.get_binder_list()
	
	var warehouse = get_node("/root/WarehouseManager")
	var inv = warehouse.get_materials()
	
	for mat in mat_list:
		var mid = mat["id"]
		var count = inv.get(mid, 0)
		if count <= 0:
			continue
		if _selected[cat_key].has(mid) and _selected[cat_key][mid] >= 1:
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
	
	# [-] 按钮（与卡基界面保持一致）
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
	
	# [+] 按钮（与卡基界面保持一致）
	var inc_btn = Button.new()
	inc_btn.text = "+"
	inc_btn.add_theme_font_size_override("font_size", 50)
	inc_btn.custom_minimum_size = Vector2(Global.pw(0.07), Global.ph(0.06))
	# 卡墨每种最多1个，且受类别上限和总上限限制
	var space_left = MAX_COUNT[cat_key] - _get_cat_total(cat_key) + selected_qty
	var total_space = TOTAL_MAX - _get_total_count() + selected_qty
	inc_btn.disabled = (selected_qty >= 1) or (count <= 0) or (space_left <= 0) or (total_space <= 0)
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
	
	row.gui_input.connect(_on_picker_row_input.bind(mat, cat_key, overlay, row))
	return row


func _on_pick_material(mid: String, cat_key: String, overlay: ColorRect, delta: int):
	var cur = _selected[cat_key].get(mid, 0)
	var new_qty = cur + delta
	if new_qty < 0:
		new_qty = 0
	# 卡墨每种最多1个
	if new_qty > 1:
		new_qty = 1
	# 检查类别上限
	if new_qty > 0:
		var cat_total = _get_cat_total(cat_key)
		var old_contrib = cur
		var space_left = MAX_COUNT[cat_key] - (cat_total - old_contrib)
		if delta > 0 and new_qty > space_left:
			new_qty = space_left
		# 检查总上限
		var total = _get_total_count()
		var total_space = TOTAL_MAX - (total - old_contrib)
		if delta > 0 and new_qty > total_space:
			new_qty = total_space
	
	if new_qty <= 0:
		_selected[cat_key].erase(mid)
	else:
		_selected[cat_key][mid] = new_qty
	
	_update_ui()
	_refresh_picker_rows(overlay, cat_key)
	
	# 教程引导：选齐三类素材后弹"看预览"讲解
	if _tutorial_step == 1 and _tutorial_done == false:
		if _get_cat_total("extract") >= 1 and _get_cat_total("pigment") >= 1 and _get_cat_total("binder") >= 1:
			# 先关闭当前素材选择弹窗，避免叠层
			if overlay and is_instance_valid(overlay):
				overlay.queue_free()
			_advance_tutorial("mats_ready")


# ============================
#  刷新弹窗行
# ============================
func _refresh_picker_rows(overlay: ColorRect, cat_key: String):
	if not overlay or not is_instance_valid(overlay):
		return
	var scroll = overlay.get_node_or_null("PickerPanel/PickerScroll")
	if not scroll:
		return
	var vbox = scroll.get_node_or_null("PickerVBox")
	if not vbox:
		return
	for child in vbox.get_children():
		if child is Panel:
			var hbox = child.get_child(0) if child.get_child_count() > 0 else null
			if hbox and hbox is HBoxContainer:
				for c in hbox.get_children():
					if c is Label and c.name.begins_with("PickerQty_"):
						var mid2 = c.name.trim_prefix("PickerQty_")
						var qty = _selected[cat_key].get(mid2, 0)
						c.text = str(qty)
						# 更新+按钮状态
						var idx = c.get_index()
						if idx + 1 < hbox.get_child_count():
							var inc_btn2 = hbox.get_child(idx + 1)
							if inc_btn2 is Button and inc_btn2.text == "+":
								var stock = 0
								var warehouse = get_node("/root/WarehouseManager")
								var inv = warehouse.get_materials()
								stock = inv.get(mid2, 0)
								var space_left2 = MAX_COUNT[cat_key] - _get_cat_total(cat_key) + qty
								var total_space2 = TOTAL_MAX - _get_total_count() + qty
								inc_btn2.disabled = (qty >= 1) or (stock <= 0) or (space_left2 <= 0) or (total_space2 <= 0)
						break
	
	if _hint_label:
		_hint_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.5))
		_hint_label.text = "已选 " + str(_get_cat_total(cat_key)) + "/" + str(MAX_COUNT[cat_key]) + "，用 [-] [+] 调整数量"


# ============================
#  长按查看素材详情
# ============================
func _on_picker_row_input(event: InputEvent, mat: Dictionary, cat_key: String, overlay: ColorRect, row: Panel):
	if event is InputEventScreenTouch:
		if event.pressed:
			_picker_long_press_timer = 0.0
			_picker_long_press_mat = mat
			_picker_long_press_row = row
			_picker_long_press_active = true
		else:
			_picker_long_press_active = false
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
		if _picker_long_press_timer >= 0.5:
			_picker_long_press_active = false
			_show_material_detail(_picker_long_press_mat)


func _show_material_detail(mat: Dictionary):
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
	
	var name_label = Label.new()
	name_label.text = mat.get("name", "未知素材")
	name_label.add_theme_font_size_override("font_size", 55)
	name_label.add_theme_color_override("font_color", _get_rarity_color(mat.get("rarity", "普通")))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_label)
	
	var rarity_label = Label.new()
	rarity_label.text = "【" + mat.get("rarity", "普通") + "】"
	rarity_label.add_theme_font_size_override("font_size", 50)
	rarity_label.add_theme_color_override("font_color", _get_rarity_color(mat.get("rarity", "普通")))
	rarity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(rarity_label)
	
	var area = mat.get("area", "")
	if area != "":
		var area_label = Label.new()
		area_label.text = "采集区域：" + area
		area_label.add_theme_font_size_override("font_size", 50)
		area_label.add_theme_color_override("font_color", Global.current.btn_text)
		area_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(area_label)
	
	var line = HSeparator.new()
	line.add_theme_color_override("color", Global.current.topbar_border)
	vbox.add_child(line)
	
	var mid = mat.get("id", "")
	var attrs_to_show := []
	if mid.begins_with("E"):
		attrs_to_show = [
			{"key": "conductivity", "label": "传导性", "color": Color("#4FC3F7")},
			{"key": "purity", "label": "纯度", "color": Color("#CE93D8")},
			{"key": "tendency", "label": "倾向", "color": Color("#FFD700")},
		]
	elif mid.begins_with("P"):
		attrs_to_show = [
			{"key": "adhesion", "label": "附着力", "color": Color("#FF8A65")},
			{"key": "chromatography", "label": "显色", "color": Color("#FFD54F")},
			{"key": "tendency", "label": "倾向", "color": Color("#FFD700")},
		]
	elif mid.begins_with("B"):
		attrs_to_show = [
			{"key": "harmony", "label": "调和度", "color": Color("#81C784")},
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
				var t = str(val)
				if t == "":
					t = "无"
				val_lbl.text = t
			else:
				val_lbl.text = str(val)
			val_lbl.add_theme_font_size_override("font_size", 50)
			val_lbl.add_theme_color_override("font_color", Global.current.title)
			val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			row.add_child(val_lbl)
	
	var desc = mat.get("description", "")
	if desc != "":
		var desc_label = Label.new()
		desc_label.text = desc
		desc_label.add_theme_font_size_override("font_size", 50)
		desc_label.add_theme_color_override("font_color", Global.current.btn_text)
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(desc_label)
	
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
#  UI 更新
# ============================
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
	var total = _get_total_count()
	btn.disabled = total < TOTAL_MIN


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


func _on_overlay_input(event: InputEvent, overlay: ColorRect):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
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
	title.text = "卡墨属性预览"
	title.add_theme_font_size_override("font_size", 50)
	title.add_theme_color_override("font_color", Global.current.title)
	vbox.add_child(title)
	
	var attrs = [
		{"key": "load_reduce", "label": "负荷减免"},
		{"key": "effect_power", "label": "效果强度"},
		{"key": "quality_stab", "label": "品质稳定性"},
		{"key": "discount", "label": "倾向折扣"},
		{"key": "resistance", "label": "属性抗性"},
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
	
	# Panel 不会按子节点自动撑高（默认 minimum_size 为 0），必须显式给高度，
	# 否则面板会被压成 0 高、与下方的「调制卡墨」按钮重叠（按钮文字透出来）。
	vbox.size_flags_vertical = SIZE_SHRINK_BEGIN
	panel.custom_minimum_size = Vector2(0, vbox.get_combined_minimum_size().y + Global.ph(0.02))


# ============================
#  卡墨属性计算公式
# ============================
func _update_preview():
	var extract_mats := []
	var pigment_mats := []
	var binder_mats := []
	
	for mid in _selected["extract"].keys():
		var qty = _selected["extract"][mid]
		var mat = Global.get_material_by_id(mid)
		if not mat.is_empty():
			for i in range(qty):
				extract_mats.append(mat)
	for mid in _selected["pigment"].keys():
		var qty = _selected["pigment"][mid]
		var mat = Global.get_material_by_id(mid)
		if not mat.is_empty():
			for i in range(qty):
				pigment_mats.append(mat)
	for mid in _selected["binder"].keys():
		var qty = _selected["binder"][mid]
		var mat = Global.get_material_by_id(mid)
		if not mat.is_empty():
			for i in range(qty):
				binder_mats.append(mat)
	
	var load_reduce = _calc_load_reduce(extract_mats, binder_mats)
	var effect_power = _calc_effect_power(pigment_mats)
	var quality_stab = _calc_quality_stab(pigment_mats)
	var discount = _calc_discount(extract_mats, pigment_mats)
	var resistance = _calc_resistance(extract_mats, pigment_mats, binder_mats)

	_preview_labels["load_reduce"].text = str(load_reduce)
	_preview_labels["effect_power"].text = str(effect_power) + "%"
	_preview_labels["quality_stab"].text = str(quality_stab) + "%"

	if discount.is_empty():
		_preview_labels["discount"].text = "无"
	else:
		var parts := []
		for k in discount.keys():
			parts.append(k + str(discount[k]) + "%")
		_preview_labels["discount"].text = "".join(parts)

	# 抗性预览
	var res_str := _format_resistance(resistance)
	_preview_labels["resistance"].text = res_str
	
	var consumption_parts := []
	for key in _selected.keys():
		var count = _get_cat_total(key)
		if count > 0:
			var cat_name = {"extract": "萃取液", "pigment": "颜料", "binder": "粘合剂"}
			consumption_parts.append(cat_name.get(key, key) + "x" + str(int(count)))
	if consumption_parts.is_empty():
		_preview_labels["consumption"].text = "无"
	else:
		_preview_labels["consumption"].text = "".join(consumption_parts)
	
	if _hint_label:
		var total = _get_total_count()
		if total > 0:
			_hint_label.text = "已选 " + str(total) + "/" + str(TOTAL_MAX) + " 种素材"
		else:
			_hint_label.text = "选择素材开始调制卡墨"


# 公式1：负荷减免 = Σ(传导性)×0.3 + Σ(调和度)×0.2 + Σ(萃取液倾向)×0.1，上限-3.5
func _calc_load_reduce(extract_mats: Array, binder_mats: Array) -> float:
	var sum_conductivity := 0.0
	for m in extract_mats:
		sum_conductivity += m.get("conductivity", 0)
	var sum_harmony := 0.0
	for m in binder_mats:
		sum_harmony += m.get("harmony", 0)
	var sum_extract_tend := 0.0
	for m in extract_mats:
		var t = m.get("tendency", "")
		if t.length() > 0:
			var num_part = t.substr(t.length() - 1, 1)
			sum_extract_tend += float(num_part)
	var raw = sum_conductivity * 0.3 + sum_harmony * 0.2 + sum_extract_tend * 0.1
	raw = round(raw * 10.0) / 10.0
	return min(raw, 3.5)


# 公式2：效果强度加成 = Σ(显色)×3%，上限30%
func _calc_effect_power(pigment_mats: Array) -> float:
	var sum_chroma := 0.0
	for m in pigment_mats:
		sum_chroma += m.get("chromatography", 0)
	var raw = sum_chroma * 3.0
	return min(raw, 30.0)


# 公式3：品质稳定性 = Σ(附着力)×2%，上限20%
func _calc_quality_stab(pigment_mats: Array) -> float:
	var sum_adhesion := 0.0
	for m in pigment_mats:
		sum_adhesion += m.get("adhesion", 0)
	var raw = sum_adhesion * 2.0
	return min(raw, 20.0)


# 公式4：倾向折扣（独立）= Σ(萃取液倾向)×5% + Σ(颜料倾向)×3%
# 返回字典，如 {"火": 13, "风": 8}
func _calc_discount(extract_mats: Array, pigment_mats: Array) -> Dictionary:
	var result := {}
	for m in extract_mats:
		var t = m.get("tendency", "")
		if t.length() >= 2:
			var type_char = t[0]
			var num_part = t.substr(t.length() - 1, 1)
			var val = float(num_part) * 5.0
			result[type_char] = result.get(type_char, 0.0) + val
	for m in pigment_mats:
		var t = m.get("tendency", "")
		if t.length() >= 2:
			var type_char = t[0]
			var num_part = t.substr(t.length() - 1, 1)
			var val = float(num_part) * 3.0
			result[type_char] = result.get(type_char, 0.0) + val
	for k in result.keys():
		result[k] = round(result[k])
	return result


# 公式5：属性抗性 = 根据材料组合决定抗性类型和数值
# 全部同倾向材料 → 该属性 +20%
# 两种不同倾向 → 两种各 +10%
# 三种及以上不同倾向 → 无抗性
# 全部无倾向 → 全属性 +5%
func _calc_resistance(extract_mats: Array, pigment_mats: Array, binder_mats: Array) -> Dictionary:
	var all_mats = extract_mats + pigment_mats + binder_mats
	var elem_set := {}
	var has_tendency := false

	for m in all_mats:
		var t = m.get("tendency", "")
		if t.length() >= 2:
			has_tendency = true
			var elem = t[0]
			elem_set[elem] = true

	if not has_tendency:
		# 全部无倾向 → 全属性 +5%
		return {"all": 5}

	var unique_count = elem_set.size()
	if unique_count == 1:
		# 全部同属性
		var elem = elem_set.keys()[0]
		return {elem: 20}
	elif unique_count == 2:
		# 两种不同属性
		var result := {}
		for e in elem_set.keys():
			result[e] = 10
		return result
	else:
		# 三种及以上不同
		return {}


# 格式化抗性字典为字符串
func _format_resistance(resistance: Dictionary) -> String:
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


# ============================
#  制作按钮
# ============================
func _build_make_button(parent: VBoxContainer):
	var btn = Button.new()
	btn.name = "MakeBtn"
	btn.text = "调制卡墨"
	btn.add_theme_font_size_override("font_size", 60)
	btn.size_flags_horizontal = SIZE_FILL
	btn.custom_minimum_size = Vector2(0, Global.ph(0.08))
	
	var s = StyleBoxFlat.new()
	s.bg_color = Color("#6c9bcf")
	s.border_width_left = 3
	s.border_width_right = 3
	s.border_width_top = 3
	s.border_width_bottom = 3
	s.border_color = Color("#4a7baf")
	s.corner_radius_top_left = 16
	s.corner_radius_top_right = 16
	s.corner_radius_bottom_left = 16
	s.corner_radius_bottom_right = 16
	s.content_margin_left = 24
	s.content_margin_right = 24
	
	var sh = s.duplicate()
	sh.bg_color = Color("#5a8bbf")
	var sp = s.duplicate()
	sp.bg_color = Color("#3a6b9f")
	
	btn.add_theme_stylebox_override("normal", s)
	btn.add_theme_stylebox_override("hover", sh)
	btn.add_theme_stylebox_override("pressed", sp)
	btn.add_theme_stylebox_override("focus", s)
	btn.add_theme_color_override("font_color", Color("#ffffff"))
	btn.add_theme_color_override("font_hover_color", Color("#ffffff"))
	btn.add_theme_color_override("font_pressed_color", Color("#ffffff"))
	# 禁用态默认沿用主题里的暗灰字体色，压在 #6c9bcf 蓝底上几乎看不见。
	# 这里单独给一个偏亮的半透明白 + 更沉的底色，既看得出「不可点」又读得清字。
	btn.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.78))
	var sd_ = s.duplicate()
	sd_.bg_color = Color("#7e93a6")
	sd_.border_color = Color("#65798c")
	btn.add_theme_stylebox_override("disabled", sd_)
	btn.pressed.connect(_on_make)
	btn.disabled = true
	parent.add_child(btn)
	
	_preview_labels["make_btn"] = btn


func _on_make():
	var total = _get_total_count()
	if total < TOTAL_MIN:
		_hint_label.text = "至少需要 " + str(TOTAL_MIN) + " 种素材！"
		_hint_label.add_theme_color_override("font_color", Color("#FF6B6B"))
		return
	
	var has_extract = _get_cat_total("extract") > 0
	var has_pigment = _get_cat_total("pigment") > 0
	var has_binder = _get_cat_total("binder") > 0
	
	if not (has_extract and has_pigment and has_binder):
		_hint_label.text = "每类至少需要1种素材！"
		_hint_label.add_theme_color_override("font_color", Color("#FF6B6B"))
		return
	
	# 弹出制作确认弹窗
	_show_make_confirm_dialog()


# ============================
#  确认制作弹窗（含批量制作）
# ============================
var _confirm_qty: int = 1
var _confirm_overlay: ColorRect = null
var _consume_rows: Array = []

func _show_make_confirm_dialog():
	var overlay = ColorRect.new()
	_confirm_overlay = overlay
	overlay.name = "ConfirmOverlay"
	overlay.color = Color(0, 0, 0, 0.6)
	overlay.anchor_left = 0.0; overlay.anchor_top = 0.0; overlay.anchor_right = 1.0; overlay.anchor_bottom = 1.0
	overlay.mouse_filter = MOUSE_FILTER_STOP
	add_child(overlay)
	
	var panel = Panel.new()
	panel.name = "ConfirmPanel"
	panel.anchor_left = 0.08; panel.anchor_top = 0.2; panel.anchor_right = 0.92; panel.anchor_bottom = 0.8
	var cps = StyleBoxFlat.new()
	cps.bg_color = Global.current.bg
	cps.border_width_left = 3; cps.border_width_right = 3; cps.border_width_top = 3; cps.border_width_bottom = 3
	cps.border_color = Global.current.topbar_border
	cps.corner_radius_top_left = 16; cps.corner_radius_top_right = 16
	cps.corner_radius_bottom_left = 16; cps.corner_radius_bottom_right = 16
	panel.add_theme_stylebox_override("panel", cps)
	overlay.add_child(panel)
	
	var margin = Global.pw(0.04)
	var top_margin = Global.ph(0.02)
	var vbox = VBoxContainer.new()
	vbox.name = "ConfirmVBox"
	vbox.anchor_left = 0.0; vbox.anchor_top = 0.0; vbox.anchor_right = 1.0; vbox.anchor_bottom = 1.0
	vbox.offset_left = margin; vbox.offset_top = top_margin; vbox.offset_right = -margin; vbox.offset_bottom = Global.ph(-0.02)
	vbox.add_theme_constant_override("separation", 0)
	panel.add_child(vbox)
	
	# 标题
	var title_label = Label.new()
	title_label.text = "确认调制卡墨"
	title_label.add_theme_font_size_override("font_size", 55)
	title_label.add_theme_color_override("font_color", Global.current.title)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.custom_minimum_size = Vector2(0, Global.ph(0.07))
	title_label.size_flags_vertical = SIZE_SHRINK_CENTER
	vbox.add_child(title_label)
	
	# 分隔线
	var line = HSeparator.new()
	line.add_theme_color_override("color", Global.current.topbar_border)
	line.custom_minimum_size = Vector2(0, Global.ph(0.005))
	vbox.add_child(line)
	
	# 可滚动区域
	var scroll = ScrollContainer.new()
	scroll.name = "ConfirmScroll"
	scroll.size_flags_vertical = SIZE_EXPAND | SIZE_FILL
	scroll.scroll_horizontal = false
	scroll.scroll_vertical = true
	vbox.add_child(scroll)
	
	var scroll_vbox = VBoxContainer.new()
	scroll_vbox.name = "ScrollVBox"
	scroll_vbox.size_flags_horizontal = SIZE_FILL
	scroll_vbox.add_theme_constant_override("separation", Global.ph(0.005))
	scroll.add_child(scroll_vbox)
	
	# 素材消耗列表
	_consume_rows.clear()
	var warehouse = get_node("/root/WarehouseManager")
	var inv = warehouse.get_materials()
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
	
	# 数量选择行
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
	
	var total_consume_label = Label.new()
	total_consume_label.name = "TotalConsume"
	total_consume_label.text = "本次消耗：制作 x" + str(_confirm_qty)
	total_consume_label.add_theme_font_size_override("font_size", 50)
	total_consume_label.add_theme_color_override("font_color", Color("#FF9800"))
	total_consume_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scroll_vbox.add_child(total_consume_label)
	
	# 底部按钮行
	var bottom_line = HSeparator.new()
	bottom_line.add_theme_color_override("color", Global.current.topbar_border)
	bottom_line.custom_minimum_size = Vector2(0, Global.ph(0.005))
	vbox.add_child(bottom_line)
	
	var btn_row = HBoxContainer.new()
	btn_row.size_flags_horizontal = SIZE_FILL
	btn_row.custom_minimum_size = Vector2(0, Global.ph(0.07))
	btn_row.add_theme_constant_override("separation", Global.pw(0.04))
	vbox.add_child(btn_row)
	
	var cancel_btn = Button.new()
	cancel_btn.text = "取消"
	cancel_btn.add_theme_font_size_override("font_size", 50)
	cancel_btn.size_flags_horizontal = SIZE_FILL
	var ccs = StyleBoxFlat.new()
	ccs.bg_color = Global.current.btn_bg
	ccs.border_width_left = 2; ccs.border_width_right = 2; ccs.border_width_top = 2; ccs.border_width_bottom = 2
	ccs.border_color = Color("#888888")
	ccs.corner_radius_top_left = 10; ccs.corner_radius_top_right = 10; ccs.corner_radius_bottom_left = 10; ccs.corner_radius_bottom_right = 10
	cancel_btn.add_theme_stylebox_override("normal", ccs)
	cancel_btn.add_theme_color_override("font_color", Global.current.btn_text)
	cancel_btn.pressed.connect(func(): _close_make_confirm())
	btn_row.add_child(cancel_btn)
	
	var confirm_btn = Button.new()
	confirm_btn.text = "确认制作"
	confirm_btn.add_theme_font_size_override("font_size", 50)
	confirm_btn.size_flags_horizontal = SIZE_FILL
	var cfs = StyleBoxFlat.new()
	cfs.bg_color = Global.current.btn_bg_hover
	cfs.border_width_left = 2; cfs.border_width_right = 2; cfs.border_width_top = 2; cfs.border_width_bottom = 2
	cfs.border_color = Color("#4CAF50")
	cfs.corner_radius_top_left = 10; cfs.corner_radius_top_right = 10; cfs.corner_radius_bottom_left = 10; cfs.corner_radius_bottom_right = 10
	confirm_btn.add_theme_stylebox_override("normal", cfs)
	confirm_btn.add_theme_color_override("font_color", Global.current.btn_text)
	confirm_btn.pressed.connect(func(): _on_confirm_make())
	btn_row.add_child(confirm_btn)


func _on_confirm_qty_change(delta: int):
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
		if _hint_label:
			_hint_label.add_theme_color_override("font_color", Color("#FF5252"))
			_hint_label.text = "素材不足，无法制作！"
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
					_hint_label.text = "素材不足！" + mat.get("name", mid) + " 需要" + str(_confirm_qty * qty) + " 仅剩" + str(stock) + "个"
				_close_make_confirm()
				_show_popup(" " + _hint_label.text, Color("#FF6B6B"))
				return
	
	# 计算属性
	var extract_mats := []
	var pigment_mats := []
	var binder_mats := []
	for mid in _selected["extract"].keys():
		var qty = _selected["extract"][mid]
		var mat = Global.get_material_by_id(mid)
		if not mat.is_empty():
			for j in range(qty):
				extract_mats.append(mat)
	for mid in _selected["pigment"].keys():
		var qty = _selected["pigment"][mid]
		var mat = Global.get_material_by_id(mid)
		if not mat.is_empty():
			for j in range(qty):
				pigment_mats.append(mat)
	for mid in _selected["binder"].keys():
		var qty = _selected["binder"][mid]
		var mat = Global.get_material_by_id(mid)
		if not mat.is_empty():
			for j in range(qty):
				binder_mats.append(mat)
	
	var load_reduce = _calc_load_reduce(extract_mats, binder_mats)
	var effect_power = _calc_effect_power(pigment_mats)
	var quality_stab = _calc_quality_stab(pigment_mats)
	var discount = _calc_discount(extract_mats, pigment_mats)
	var resistance = _calc_resistance(extract_mats, pigment_mats, binder_mats)
	
	# 生成卡墨ID和名称
	var ink_id_base = "INK_"
	# 生成卡墨中文名（取每个素材名的前2字，用+连接，简洁）
	var name_parts := []
	for key in _selected.keys():
		for mid in _selected[key].keys():
			var mat = Global.get_material_by_id(mid)
			if not mat.is_empty():
				var nm = mat.get("name", mid)
				var _short = nm.substr(0, mini(nm.length(), 2))
				if not _short in name_parts:
					name_parts.append(_short)
	var ink_name = "卡墨·"
	if name_parts.size() <= 3:
		ink_name += "+".join(name_parts)
	else:
		ink_name += "+".join(name_parts.slice(0, 3)) + "等"

	
	# 先一次性消耗所有素材
	for key in _selected.keys():
		for mid in _selected[key].keys():
			var qty = _selected[key][mid]
			warehouse.consume_material(mid, qty * _confirm_qty)
	
	# 再循环保存每个卡墨
	for i in range(_confirm_qty):
		var ink_id = ink_id_base + "_" + str(Time.get_unix_time_from_system()) + "_" + str(i)
		var ink_data = {
			"id": ink_id,
			"name": ink_name,
			"type": "ink",
			"load_reduce": load_reduce,
			"effect_power": effect_power,
			"quality_stab": quality_stab,
			"discount": discount.duplicate() if discount is Dictionary else discount,
			"resistance": resistance.duplicate() if resistance is Dictionary else resistance,
			"materials": {
				"extract": _selected["extract"].duplicate(),
				"pigment": _selected["pigment"].duplicate(),
				"binder": _selected["binder"].duplicate()
			}
		}
		warehouse.add_ink(ink_data)
		print("[卡墨调制] 制作成功！ID: ", ink_id)
	
	_close_make_confirm()
	
	# 清空选择
	for key in _selected.keys():
		_selected[key].clear()
	_update_ui()
	
	if _hint_label:
		_hint_label.add_theme_color_override("font_color", Color("#4CAF50"))
		_hint_label.text = "成功调制 " + str(_confirm_qty) + " 个卡墨！"
	
	# 教程引导：制作成功 → 弹收尾对话（提示去刻画卡牌）
	if _tutorial_done == false:
		_advance_tutorial("made")
	else:
		# 弹出成功提示
		_show_popup(" 成功调制 " + str(_confirm_qty) + " 个卡墨！", Color("#81C784"))


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
	# 已看过卡墨引导则跳过（存档标记，防重进场景重复弹）
	if SaveManager.get_value("tutorial", "card_ink_guide_seen", false):
		_tutorial_done = true
		return
	SaveManager.set_value("tutorial", "card_ink_guide_seen", true)
	SaveManager.save_to_disk()
	_tutorial_step = 0
	_show_tutorial_dialogue([
		{"speaker": "老陈", "text": "这是卡墨台。卡牌的灵魂，全在墨里。萃取液、颜料、粘合剂，三样调一调。"},
		{"speaker": "你", "text": "和卡基有点像……也是三类素材？"},
		{"speaker": "老陈", "text": "还是老规矩，三栏各挑一个。挑完教你看门道。"},
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
					{"speaker": "老陈", "text": "看底下那栏【卡墨属性预览】——负荷减免、效果强度、品质稳定性、属性抗性，都在里头。"},
					{"speaker": "老陈", "text": "效果强度决定卡牌技能威力，品质稳定性让刻画更稳。好墨才能出好卡。"},
					{"speaker": "老陈", "text": "选齐了就点【调制卡墨】试试。"},
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
					{"speaker": "老陈", "text": "好墨成了！这一瓶，够你画好几张卡。"},
					{"speaker": "你", "text": "瓶子不大，但看着挺透的……"},
					{"speaker": "老陈", "text": "身板和墨都齐了，去【刻画卡牌】那台，把第一张卡画出来吧。"},
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
#  主题切换
# ============================
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
		title.add_theme_constant_override("shadow_offset_x", Global.current.shadow_offset)
		title.add_theme_constant_override("shadow_offset_y", Global.current.shadow_offset)
	
	# 更新所有按钮主题
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
	
	# 更新素材分类面板
	for key in _category_labels.keys():
		var row = get_node_or_null("ContentScroll/ContentVBox/CatRow_" + key)
		if row and row is Panel:
			row.add_theme_stylebox_override("panel", _make_card_style())
	
	# 更新预览面板
	var preview_panel = get_node_or_null("ContentScroll/ContentVBox/PreviewPanel")
	if preview_panel and preview_panel is Panel:
		preview_panel.add_theme_stylebox_override("panel", _make_card_style())


# ============================
#  导航
# ============================
func _on_back():
	Global.play_sfx("click")
	Global.change_scene("res://CardWorkshop.tscn")


func _on_help():
	Global.play_sfx("click")
	_show_help_guide()


## 显示调制卡墨指南弹窗
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
	ps.border_color = Color("#9B59B6")
	ps.corner_radius_top_left = 16; ps.corner_radius_top_right = 16
	ps.corner_radius_bottom_left = 16; ps.corner_radius_bottom_right = 16
	panel.add_theme_stylebox_override("panel", ps)
	overlay.add_child(panel)
	
	# 标题
	var title = Label.new()
	title.text = "调制卡墨指南"
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
	
	# 延迟一帧设置宽度
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
	_make_help_label(s1, "调制卡墨需要选择三种素材，每种有数量限制：", Global.current.btn_text, 42)
	_make_help_label(s1, " 萃取液（Extract）：1 ~ 2 种", Color("#4FC3F7"), 45)
	_make_help_label(s1, " 颜料（Pigment）：1 ~ 2 种", Color("#FF8A65"), 45)
	_make_help_label(s1, " 粘合剂（Binder）：1 ~ 2 种", Color("#81C784"), 45)
	_make_help_label(s1, " 素材总数：3 ~ 6 种", Color("#FFD700"), 45)
	_make_help_label(s1, " 每种素材最多选1个，无素材数量惩罚", Color("#4CAF50"), 42)
	
	# 2. 素材属性说明
	var s2 = _make_help_section(vbox, " ② 素材属性说明", Color("#3498DB"))
	_make_help_label(s2, "每种素材有独有属性，影响成品卡墨的最终数值：", Global.current.btn_text, 42)
	
	_make_help_label(s2, " 萃取液素材", Color("#4FC3F7"), 48)
	_make_help_label(s2, "  • 传导性（conductivity）：影响卡墨的【负荷减免】", Color("#CCCCCC"))
	_make_help_label(s2, "  • 纯度（purity）：提取品质，影响萃取液的效果基础", Color("#CCCCCC"))
	_make_help_label(s2, "  • 倾向（tendency）：影响【负荷减免】和【倾向折扣】", Color("#CCCCCC"))
	
	_make_help_label(s2, " 颜料素材", Color("#FF8A65"), 48)
	_make_help_label(s2, "  • 附着力（adhesion）：影响卡墨的【品质稳定性】", Color("#CCCCCC"))
	_make_help_label(s2, "  • 显色（chromatography）：影响卡墨的【效果强度加成】", Color("#CCCCCC"))
	_make_help_label(s2, "  • 倾向（tendency）：影响卡墨的【倾向折扣】", Color("#CCCCCC"))
	
	_make_help_label(s2, " 粘合剂素材", Color("#81C784"), 48)
	_make_help_label(s2, "  • 调和度（harmony）：影响卡墨的【负荷减免】", Color("#CCCCCC"))
	
	_make_help_label(s2, " 共通属性", Color("#FFD700"), 48)
	_make_help_label(s2, "  • 倾向（tendency）：所有素材的倾向值组合，决定【抗性】和【折扣】", Color("#CCCCCC"))
	_make_help_label(s2, "  • 稀有度：影响素材边框颜色（普通/稀有/史诗/传说）", Color("#CCCCCC"))
	
	# 3. 计算公式
	var s3 = _make_help_section(vbox, " ③ 计算公式", Color("#9B59B6"))
	
	_make_help_label(s3, " 负荷减免（Load Reduce）", Color("#4FC3F7"), 48)
	_make_help_label(s3, "公式：min( Σ(传导性)×0.3 + Σ(调和度)×0.2 + Σ(萃取液倾向数字)×0.1 , 3.5 )", Color("#FFD700"), 42)
	_make_help_label(s3, "→ 萃取液传导性越高、粘合剂调和度越高，负荷减免越多", Color("#CCCCCC"))
	_make_help_label(s3, "→ 萃取液倾向值中的数字部分也会计入（如「火3」→ +3×0.1）", Color("#CCCCCC"))
	_make_help_label(s3, "→ 结果四舍五入到一位小数，上限3.5", Color("#CCCCCC"))
	_make_help_label(s3, "→ 负荷减免越高，刻画纹路时消耗的能量越少", Color("#CCCCCC"))
	
	_make_help_label(s3, " 效果强度加成（Effect Power）", Color("#FF8A65"), 48)
	_make_help_label(s3, "公式：min( Σ(显色)×3% , 30% )", Color("#FFD700"), 42)
	_make_help_label(s3, "→ 颜料的显色值越高，效果强度加成越多，上限30%", Color("#CCCCCC"))
	_make_help_label(s3, "→ 效果强度影响卡牌纹路效果的触发成功率", Color("#CCCCCC"))
	
	_make_help_label(s3, " 品质稳定性（Quality Stability）", Color("#FFD54F"), 48)
	_make_help_label(s3, "公式：min( Σ(附着力)×2% , 20% )", Color("#FFD700"), 42)
	_make_help_label(s3, "→ 颜料的附着力越高，品质稳定性越高，上限20%", Color("#CCCCCC"))
	_make_help_label(s3, "→ 品质稳定性影响卡基制作时的品质波动范围", Color("#CCCCCC"))
	
	_make_help_label(s3, " 倾向折扣（Discount）", Color("#FFD700"), 48)
	_make_help_label(s3, "公式：Σ(萃取液倾向数字)×5% + Σ(颜料倾向数字)×3%（按元素分别计算）", Color("#FFD700"), 42)
	_make_help_label(s3, "→ 每种元素独立计算折扣，返回字典如「火13% 风8%」", Color("#CCCCCC"))
	_make_help_label(s3, "→ 例如「火3」萃取液 → 火系折扣+15%，「火2」颜料 → 火系折扣+6%", Color("#CCCCCC"))
	_make_help_label(s3, "→ 倾向折扣影响对应元素卡牌的纹路刻画能量消耗", Color("#CCCCCC"))
	
	_make_help_label(s3, " 属性抗性（Resistance）", Color("#E91E63"), 48)
	_make_help_label(s3, "抗性根据所有素材的倾向组合决定：", Color("#CCCCCC"))
	_make_help_label(s3, "  • 全部同倾向（如全是火系）→ 该属性抗性 +20%", Color("#4FC3F7"))
	_make_help_label(s3, "  • 两种不同倾向 → 各 +10%", Color("#FF9800"))
	_make_help_label(s3, "  • 三种及以上不同倾向 → 无抗性", Color("#FF5252"))
	_make_help_label(s3, "  • 全部无倾向素材 → 全属性抗性 +5%", Color("#8BC34A"))
	_make_help_label(s3, "→ 属性抗性影响卡牌受到对应元素伤害时的减免", Color("#CCCCCC"))
	
	_make_help_label(s3, " 消耗（Consumption）", Color("#95A5A6"), 48)
	_make_help_label(s3, "公式：各素材类别数量组合（如 萃取液x2 颜料x1 粘合剂x1）", Color("#FFD700"), 42)
	_make_help_label(s3, "→ 消耗仅显示用了哪些素材，不计入最终属性", Color("#CCCCCC"))
	
	# 4. 制作技巧
	var s4 = _make_help_section(vbox, " ④ 制作技巧", Color("#4CAF50"))
	_make_help_label(s4, "1. 萃取液和粘合剂 → 提升负荷减免，降低纹路能量消耗", Global.current.btn_text, 42)
	_make_help_label(s4, "2. 颜料 → 提升效果强度和品质稳定性", Global.current.btn_text, 42)
	_make_help_label(s4, "3. 想追求单属性抗性 → 全部选同倾向的素材", Global.current.btn_text, 42)
	_make_help_label(s4, "4. 想追求全属性抗性 → 全部选无倾向素材", Global.current.btn_text, 42)
	_make_help_label(s4, "5. 倾向折扣可以叠加多种元素，适合多属性卡组", Global.current.btn_text, 42)
	
	# 5. 制作步骤
	var s5 = _make_help_section(vbox, " ⑤ 制作步骤", Color("#3498DB"))
	_make_help_label(s5, "1. 点击「选择」按钮，从仓库中选择素材", Global.current.btn_text, 42)
	_make_help_label(s5, "2. 用 [-] [+] 调整每种素材的数量（最多1个）", Global.current.btn_text, 42)
	_make_help_label(s5, "3. 在「卡墨属性预览」中查看实时计算结果", Global.current.btn_text, 42)
	_make_help_label(s5, "4. 每类至少选1种，总数至少3种，点击「调制卡墨」生成", Global.current.btn_text, 42)
	_make_help_label(s5, "5. 制作好的卡墨会存入仓库，可在刻画界面选择使用", Global.current.btn_text, 42)
	_make_help_label(s5, " 长按素材行可查看素材详情", Color("#FFD700"), 42)
	
	# 底部留白
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, Global.ph(0.02))
	vbox.add_child(spacer)


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
	# ★ 创建底部提示 Label（之前从未初始化导致 _on_make 里 _hint_label.text 崩溃）
	if not _hint_label:
		_hint_label = Label.new()
		_hint_label.name = "HintLabel"
		_hint_label.add_theme_font_size_override("font_size", 42)
		_hint_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.7))
		_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_hint_label.text = "选择萃取液、颜料、黏合剂开始调制卡墨"
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
	# 内容区左右留白 + 卡片间距：tscn 里 ContentScroll 是锚满整宽的，
	# 素材卡/预览面板会紧贴屏幕左右边缘、并且彼此相连（VBox 默认间距 0），
	# 于是整页看起来是一整块同色区域，没有分区感。
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
	call_deferred("_start_tutorial_if_needed")
