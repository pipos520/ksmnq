extends Control
## ============================================================
##  纹路图鉴 —— 查看所有纹路组件及解锁状态
##  风格参考仓库(Warehouse.gd)，支持长按查看详情
## ============================================================

# 筛选状态
var _filter_unlock: String = "all"  # "all" / "unlocked" / "locked"
var _filter_category: String = "all"  # "all" / "TR" / "C" / "A" / "T" / "CO"

# ===== 长按弹窗 =====
var _press_timer: float = 0.0
var _pressed_row = null
var _press_start_pos: Vector2 = Vector2.ZERO
var _press_index: int = -1
var _long_press_triggered: bool = false
var _popup_open: bool = false
const LONG_PRESS_TIME := 0.5
const DRAG_THRESHOLD := 30.0

# 缓存 StyleBox，避免每次进入场景重建
var _style_cat_btn: StyleBoxFlat = null
var _style_unlock_btn: StyleBoxFlat = null
var _style_back_btn: StyleBoxFlat = null
# ===== 长按弹窗 =====
func _ready():
	call_deferred("_init_scene")

func _init_scene():
	_apply_theme_colors()
	
	var back = get_node_or_null("BackBtn")
	if back:
		back.pressed.connect(_on_back)
	var cat_btn = get_node_or_null("CategoryBtn")
	if cat_btn:
		cat_btn.pressed.connect(_show_category_popup)
	var unlock_btn = get_node_or_null("UnlockBtn")
	if unlock_btn:
		unlock_btn.pressed.connect(_show_unlock_popup)
	Global.theme_changed.connect(_on_theme_changed)
	_setup_long_press()
	
	_fill_all_rows()


func _fill_all_rows():
	var vbox = get_node_or_null("ListScroll/ListVBox")
	if not vbox:
		return
	var scroll = vbox.get_parent()
	scroll.remove_child(vbox)
	
	var pool = Global.circuit_row_pool
	var total = pool.size()
	
	# 一次性获取数据
	var unlocked_cache = SaveManager.get_value("circuit", "unlocked", [])
	var all_comps = CircuitManager.get_all_components_flat()
	
	# 构建解锁条件缓存
	var unlock_cond_cache = {}
	for path in Global.get_unlock_paths():
		for cid in path["unlock"]:
			unlock_cond_cache[cid] = path["condition"]
	
	# 筛选+排序（所有数据，不过滤，因为后续筛选由_refresh_list处理）
	var cat_order := {"TR": 0, "A": 1, "T": 2, "C": 3, "CO": 4}
	var filtered = []
	for comp in all_comps:
		var cid = comp["id"]
		var unlocked = cid in unlocked_cache
		comp = comp.duplicate()
		comp["unlocked"] = unlocked
		filtered.append(comp)
	
	filtered.sort_custom(func(a, b):
		if a["unlocked"] != b["unlocked"]:
			return a["unlocked"] == true
		var ca = cat_order.get(a["category"], 9)
		var cb = cat_order.get(b["category"], 9)
		if ca != cb:
			return ca < cb
		return a["id"] < b["id"]
	)
	
	# 直接在填充时设置数据，避免_refresh_list的样式重算开销
	var count = min(total, filtered.size())
	for i in count:
		var row = pool[i]
		var comp = filtered[i]
		var cid = comp["id"]
		var unlocked = comp["unlocked"]
		
		row.set_meta("from_pool", true)
		row.set_meta("comp_id", cid)
		row.set_meta("row_data", comp)
		row.set_meta("row_index", i)
		
		var hbox = row.get_node("RowHBox")
		hbox.get_node("IDLabel").text = cid
		hbox.get_node("NameLabel").text = comp.get("name", cid)
		hbox.get_node("CatLabel").text = comp.get("category_name", "")
		
		var status = hbox.get_node("StatusLabel")
		if unlocked:
			status.text = "✅ 已解锁"
			status.add_theme_color_override("font_color", Color("#4CAF50"))
		else:
			var cond = unlock_cond_cache.get(cid, "")
			status.text = "🔒 " + cond if cond != "" else "🔒 初始解锁"
			status.add_theme_color_override("font_color", Color("#FF5252"))
		
		# 行背景色（只创建一次，后续只改颜色，不再调用add_theme_stylebox_override）
		var sb = row.get_meta("_stylebox") if row.has_meta("_stylebox") else null
		if sb == null:
			sb = StyleBoxFlat.new()
			row.set_meta("_stylebox", sb)
			row.add_theme_stylebox_override("panel", sb)
		sb.bg_color = _get_row_bg_color(i)
		
		vbox.add_child(row)
	
	# 底部留白
	var spacer = Control.new()
	spacer.name = "Spacer"
	spacer.custom_minimum_size = Vector2(0, Global.ph(0.05))
	vbox.add_child(spacer)
	
	pool.clear()
	scroll.add_child(vbox)
	
	_update_hint(filtered.size())

func _exit_tree():
	# 场景退出时，把行还回 Global 池子
	var vbox = get_node_or_null("ListScroll/ListVBox")
	if vbox:
		for child in vbox.get_children():
			vbox.remove_child(child)
			if child is Panel and child.has_meta("from_pool"):
				Global.circuit_row_pool.append(child)
			else:
				child.queue_free()

func _apply_theme_colors():
	# 应用主题样式到.tscn里预创建的节点
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
		title.add_theme_font_size_override("font_size", 100)
		title.add_theme_color_override("font_color", Global.current.title)
		title.add_theme_color_override("font_shadow_color", Global.current.title_shadow)
		title.add_theme_constant_override("shadow_offset_x", Global.current.shadow_offset)
		title.add_theme_constant_override("shadow_offset_y", Global.current.shadow_offset)
	
	# 筛选按钮样式（StyleBox只创建一次，后续只更新颜色）
	var cat_btn = get_node_or_null("CategoryBtn")
	if cat_btn and cat_btn is Button:
		cat_btn.add_theme_font_size_override("font_size", 45)
		if _style_cat_btn == null:
			_style_cat_btn = StyleBoxFlat.new()
			_style_cat_btn.border_width_left = 2; _style_cat_btn.border_width_right = 2
			_style_cat_btn.border_width_top = 2; _style_cat_btn.border_width_bottom = 2
			_style_cat_btn.border_color = Color("#e8a838")
			_style_cat_btn.corner_radius_top_left = 12; _style_cat_btn.corner_radius_top_right = 12
			_style_cat_btn.corner_radius_bottom_left = 12; _style_cat_btn.corner_radius_bottom_right = 12
			_style_cat_btn.content_margin_left = 16; _style_cat_btn.content_margin_right = 16
			cat_btn.add_theme_stylebox_override("normal", _style_cat_btn)
		_style_cat_btn.bg_color = Global.current.btn_bg
		cat_btn.add_theme_color_override("font_color", Global.current.title)
	
	var unlock_btn = get_node_or_null("UnlockBtn")
	if unlock_btn and unlock_btn is Button:
		unlock_btn.add_theme_font_size_override("font_size", 45)
		if _style_unlock_btn == null:
			_style_unlock_btn = StyleBoxFlat.new()
			_style_unlock_btn.border_width_left = 2; _style_unlock_btn.border_width_right = 2
			_style_unlock_btn.border_width_top = 2; _style_unlock_btn.border_width_bottom = 2
			_style_unlock_btn.border_color = Color("#e8a838")
			_style_unlock_btn.corner_radius_top_left = 12; _style_unlock_btn.corner_radius_top_right = 12
			_style_unlock_btn.corner_radius_bottom_left = 12; _style_unlock_btn.corner_radius_bottom_right = 12
			_style_unlock_btn.content_margin_left = 16; _style_unlock_btn.content_margin_right = 16
			unlock_btn.add_theme_stylebox_override("normal", _style_unlock_btn)
		_style_unlock_btn.bg_color = Global.current.btn_bg
		unlock_btn.add_theme_color_override("font_color", Global.current.title)
	
	# 返回按钮样式
	var back = get_node_or_null("BackBtn")
	if back and back is Button:
		back.add_theme_font_size_override("font_size", 50)
		if _style_back_btn == null:
			_style_back_btn = StyleBoxFlat.new()
			_style_back_btn.border_width_left = 2; _style_back_btn.border_width_right = 2
			_style_back_btn.border_width_top = 2; _style_back_btn.border_width_bottom = 2
			_style_back_btn.border_color = Color("#888888")
			_style_back_btn.corner_radius_top_left = 10; _style_back_btn.corner_radius_top_right = 10
			_style_back_btn.corner_radius_bottom_left = 10; _style_back_btn.corner_radius_bottom_right = 10
			_style_back_btn.content_margin_left = 20; _style_back_btn.content_margin_right = 20
			back.add_theme_stylebox_override("normal", _style_back_btn)
		_style_back_btn.bg_color = Global.current.btn_bg
		back.add_theme_color_override("font_color", Global.current.title)
	
	# 提示标签
	var hint = get_node_or_null("HintLabel")
	if hint and hint is Label:
		hint.add_theme_font_size_override("font_size", 50)
		hint.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.5))

func _refresh_list(vbox_override = null):
	var vbox = vbox_override
	if not vbox:
		vbox = get_node_or_null("ListScroll/ListVBox")
	if not vbox:
		return
	
	var unlocked_cache = SaveManager.get_value("circuit", "unlocked", [])
	var all_comps = CircuitManager.get_all_components_flat()
	
	var filtered = []
	for comp in all_comps:
		var cid = comp["id"]
		var unlocked = cid in unlocked_cache
		if _filter_category != "all" and comp["category"] != _filter_category:
			continue
		if _filter_unlock == "unlocked" and not unlocked:
			continue
		if _filter_unlock == "locked" and unlocked:
			continue
		comp = comp.duplicate()
		comp["unlocked"] = unlocked
		filtered.append(comp)
	
	var unlock_cond_cache = {}
	for path in Global.get_unlock_paths():
		for cid in path["unlock"]:
			unlock_cond_cache[cid] = path["condition"]
	
	if filtered.size() == 0:
		for child in vbox.get_children():
			child.visible = false
		var empty_label = get_node_or_null("ListScroll/ListVBox/EmptyLabel")
		if not empty_label:
			empty_label = Label.new()
			empty_label.name = "EmptyLabel"
			empty_label.text = "没有匹配的纹路组件"
			empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			empty_label.add_theme_font_size_override("font_size", 50)
			empty_label.add_theme_color_override("font_color", Color("#5a5a6e"))
			empty_label.custom_minimum_size = Vector2(0, Global.ph(0.1))
			vbox.add_child(empty_label)
		empty_label.visible = true
		_update_hint(0)
		return
	
	var cat_order := {"TR": 0, "A": 1, "T": 2, "C": 3, "CO": 4}
	filtered.sort_custom(func(a, b):
		if a["unlocked"] != b["unlocked"]:
			return a["unlocked"] == true
		var ca = cat_order.get(a["category"], 9)
		var cb = cat_order.get(b["category"], 9)
		if ca != cb:
			return ca < cb
		return a["id"] < b["id"]
	)
	
	var existing_rows = vbox.get_children()
	var need_count = filtered.size()
	
	var update_count = min(existing_rows.size(), need_count)
	for i in update_count:
		var child = existing_rows[i]
		child.visible = true
		if not (child is Panel and child.has_meta("from_pool")):
			continue
		var comp = filtered[i]
		var cid = comp["id"]
		var unlocked = comp["unlocked"]
		
		child.set_meta("comp_id", cid)
		child.set_meta("row_data", comp)
		child.set_meta("row_index", i)
		
		var hbox = child.get_node("RowHBox")
		hbox.get_node("IDLabel").text = cid
		hbox.get_node("NameLabel").text = comp.get("name", cid)
		hbox.get_node("CatLabel").text = comp.get("category_name", "")
		
		var status = hbox.get_node("StatusLabel")
		if unlocked:
			status.text = "✅ 已解锁"
			status.add_theme_color_override("font_color", Color("#4CAF50"))
		else:
			var cond = unlock_cond_cache.get(cid, "")
			status.text = "🔒 " + cond if cond != "" else "🔒 初始解锁"
			status.add_theme_color_override("font_color", Color("#FF5252"))
	
	for i in range(need_count, existing_rows.size()):
		var child = existing_rows[i]
		if child is Panel and child.has_meta("from_pool"):
			child.visible = false
	
	var empty_label = get_node_or_null("ListScroll/ListVBox/EmptyLabel")
	if empty_label:
		empty_label.visible = false
	
	_update_hint(filtered.size())
func _update_hint(shown_count: int):
	var hint = get_node_or_null("HintLabel")
	if hint:
		var total = CircuitManager.get_all_components_flat().size()
		hint.text = "显示 " + str(shown_count) + " / 共 " + str(total) + " 个纹路组件"


func _get_row_bg_color(row_index: int) -> Color:
	if row_index % 2 == 0:
		return Global.current.topbar_bg
	return Color.TRANSPARENT


func _show_category_popup():
	Global.play_sfx("click")
	_popup_open = true
	var overlay = ColorRect.new()
	overlay.name = "FilterOverlay"
	overlay.color = Color(0.0, 0.0, 0.0, 0.6)
	overlay.anchor_left = 0.0; overlay.anchor_top = 0.0
	overlay.anchor_right = 1.0; overlay.anchor_bottom = 1.0
	overlay.mouse_filter = MOUSE_FILTER_STOP
	overlay.gui_input.connect(_on_overlay_clicked.bind(overlay))
	add_child(overlay)
	
	var panel = Panel.new()
	panel.name = "FilterPanel"
	panel.anchor_left = 0.1; panel.anchor_top = 0.0
	panel.anchor_right = 0.9; panel.anchor_bottom = 0.0
	panel.offset_top = Global.ph(0.12)
	panel.offset_bottom = Global.ph(0.80)
	var ps = StyleBoxFlat.new()
	ps.bg_color = Global.current.bg
	ps.border_width_left = 3; ps.border_width_right = 3
	ps.border_width_top = 3; ps.border_width_bottom = 3
	ps.border_color = Color("#e8a838")
	ps.corner_radius_top_left = 16; ps.corner_radius_top_right = 16
	ps.corner_radius_bottom_left = 16; ps.corner_radius_bottom_right = 16
	panel.add_theme_stylebox_override("panel", ps)
	overlay.add_child(panel)
	
	# 用 VBoxContainer 自动排列
	var vbox = VBoxContainer.new()
	vbox.name = "FilterVBox"
	vbox.anchor_left = 0.0; vbox.anchor_top = 0.0
	vbox.anchor_right = 1.0; vbox.anchor_bottom = 1.0
	vbox.offset_left = Global.pw(0.04)
	vbox.offset_right = Global.pw(-0.04)
	vbox.offset_top = Global.ph(0.02)
	vbox.offset_bottom = Global.ph(-0.02)
	panel.add_child(vbox)
	
	var title = Label.new()
	title.text = "选择类别"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 55)
	title.add_theme_color_override("font_color", Global.current.title)
	title.custom_minimum_size = Vector2(0, Global.ph(0.08))
	title.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	vbox.add_child(title)
	
	# 分隔线
	var sep = ColorRect.new()
	sep.color = Global.current.topbar_border
	sep.custom_minimum_size = Vector2(0, Global.ph(0.003))
	sep.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	vbox.add_child(sep)
	
	var categories = [
		["all", "📂 全部类别"],
		["TR", "⚡ 触发器"],
		["A", "💥 动作"],
		["T", "🎯 目标"],
		["C", "🔍 条件"],
		["CO", "🔗 约束"]
	]
	
	for cat in categories:
		var btn = Button.new()
		btn.text = cat[1]
		btn.add_theme_font_size_override("font_size", 50)
		btn.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
		btn.custom_minimum_size = Vector2(0, Global.ph(0.08))
		var bs = StyleBoxFlat.new()
		bs.bg_color = Global.current.btn_bg
		bs.border_width_left = 2; bs.border_width_right = 2
		bs.border_width_top = 2; bs.border_width_bottom = 2
		bs.border_color = Color("#e8a838")
		bs.corner_radius_top_left = 10; bs.corner_radius_top_right = 10
		bs.corner_radius_bottom_left = 10; bs.corner_radius_bottom_right = 10
		btn.add_theme_stylebox_override("normal", bs)
		btn.add_theme_color_override("font_color", Global.current.title)
		btn.pressed.connect(_on_category_selected.bind(cat[0], overlay))
		vbox.add_child(btn)


func _on_category_selected(cat_id: String, overlay: ColorRect):
	Global.play_sfx("click")
	_filter_category = cat_id
	var btn = get_node_or_null("CategoryBtn")
	if btn:
		var names = {"all": "📂 全部类别", "TR": "⚡ 触发器", "A": "💥 动作", "T": "🎯 目标", "C": "🔍 条件", "CO": "🔗 约束"}
		btn.text = names.get(cat_id, "📂 全部类别")
	_popup_open = false
	overlay.queue_free()
	_refresh_list()


func _show_unlock_popup():
	Global.play_sfx("click")
	_popup_open = true
	var overlay = ColorRect.new()
	overlay.name = "UnlockFilterOverlay"
	overlay.color = Color(0.0, 0.0, 0.0, 0.6)
	overlay.anchor_left = 0.0; overlay.anchor_top = 0.0
	overlay.anchor_right = 1.0; overlay.anchor_bottom = 1.0
	overlay.mouse_filter = MOUSE_FILTER_STOP
	overlay.gui_input.connect(_on_overlay_clicked.bind(overlay))
	add_child(overlay)
	
	var panel = Panel.new()
	panel.name = "UnlockFilterPanel"
	panel.anchor_left = 0.1; panel.anchor_top = 0.0
	panel.anchor_right = 0.9; panel.anchor_bottom = 0.0
	panel.offset_top = Global.ph(0.2)
	panel.offset_bottom = Global.ph(0.65)
	var ps = StyleBoxFlat.new()
	ps.bg_color = Global.current.bg
	ps.border_width_left = 3; ps.border_width_right = 3
	ps.border_width_top = 3; ps.border_width_bottom = 3
	ps.border_color = Color("#e8a838")
	ps.corner_radius_top_left = 16; ps.corner_radius_top_right = 16
	ps.corner_radius_bottom_left = 16; ps.corner_radius_bottom_right = 16
	panel.add_theme_stylebox_override("panel", ps)
	overlay.add_child(panel)
	
	# 用 VBoxContainer 自动排列
	var vbox = VBoxContainer.new()
	vbox.name = "UnlockFilterVBox"
	vbox.anchor_left = 0.0; vbox.anchor_top = 0.0
	vbox.anchor_right = 1.0; vbox.anchor_bottom = 1.0
	vbox.offset_left = Global.pw(0.04)
	vbox.offset_right = Global.pw(-0.04)
	vbox.offset_top = Global.ph(0.02)
	vbox.offset_bottom = Global.ph(-0.02)
	panel.add_child(vbox)
	
	var title = Label.new()
	title.text = "选择解锁状态"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 55)
	title.add_theme_color_override("font_color", Global.current.title)
	title.custom_minimum_size = Vector2(0, Global.ph(0.08))
	title.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	vbox.add_child(title)
	
	# 分隔线
	var sep = ColorRect.new()
	sep.color = Global.current.topbar_border
	sep.custom_minimum_size = Vector2(0, Global.ph(0.003))
	sep.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	vbox.add_child(sep)
	
	var options = [
		["all", "🔓 全部"],
		["unlocked", "✅ 已解锁"],
		["locked", "🔒 未解锁"]
	]
	
	for opt in options:
		var btn = Button.new()
		btn.text = opt[1]
		btn.add_theme_font_size_override("font_size", 50)
		btn.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
		btn.custom_minimum_size = Vector2(0, Global.ph(0.08))
		var bs = StyleBoxFlat.new()
		bs.bg_color = Global.current.btn_bg
		bs.border_width_left = 2; bs.border_width_right = 2
		bs.border_width_top = 2; bs.border_width_bottom = 2
		bs.border_color = Color("#e8a838")
		bs.corner_radius_top_left = 10; bs.corner_radius_top_right = 10
		bs.corner_radius_bottom_left = 10; bs.corner_radius_bottom_right = 10
		btn.add_theme_stylebox_override("normal", bs)
		btn.add_theme_color_override("font_color", Global.current.title)
		btn.pressed.connect(_on_unlock_selected.bind(opt[0], overlay))
		vbox.add_child(btn)


func _on_unlock_selected(filter_id: String, overlay: ColorRect):
	Global.play_sfx("click")
	_filter_unlock = filter_id
	var btn = get_node_or_null("UnlockBtn")
	if btn:
		var names = {"all": "🔓 全部", "unlocked": "✅ 已解锁", "locked": "🔒 未解锁"}
		btn.text = names.get(filter_id, "🔓 全部")
	_popup_open = false
	overlay.queue_free()
	_refresh_list()


func _on_overlay_clicked(event: InputEvent, overlay: ColorRect):
	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		Global.play_sfx("click")
		_popup_open = false
		overlay.queue_free()


func _on_row_click(event: InputEvent, row_panel: Panel):
	# 已废弃：全部由 _input 统一处理
	pass


func _show_component_detail(cid: String):
	_popup_open = true
	var info = CircuitManager.get_component_info(cid)
	if info.is_empty():
		return
	
	var unlocked = CircuitManager.is_unlocked(cid)
	var cond = CircuitManager.get_unlock_condition(cid)
	
	# 从 CID 前缀提取类别（原始数据没有 category 字段）
	var cat = ""
	if cid.begins_with("TR"):
		cat = "TR"
	elif cid.begins_with("A"):
		cat = "A"
	elif cid.begins_with("T"):
		cat = "T"
	elif cid.begins_with("C"):
		cat = "C"
	elif cid.begins_with("CO"):
		cat = "CO"
	var cat_names = {"TR": "触发器", "A": "动作", "T": "目标", "C": "条件", "CO": "约束"}
	var cat_name = cat_names.get(cat, cat)
	var name_str = info.get("name", cid)
	
	var overlay = ColorRect.new()
	overlay.name = "DetailOverlay"
	overlay.color = Color(0.0, 0.0, 0.0, 0.7)
	overlay.anchor_left = 0.0; overlay.anchor_top = 0.0
	overlay.anchor_right = 1.0; overlay.anchor_bottom = 1.0
	overlay.mouse_filter = MOUSE_FILTER_STOP
	overlay.gui_input.connect(_on_overlay_clicked.bind(overlay))
	add_child(overlay)
	
	var panel = ColorRect.new()
	panel.name = "DetailPanel"
	panel.color = Global.current.bg
	panel.anchor_left = 0.0; panel.anchor_top = 0.0
	panel.anchor_right = 1.0; panel.anchor_bottom = 0.0
	panel.offset_left = Global.pw(0.05)
	panel.offset_top = Global.ph(0.15)
	panel.offset_right = Global.pw(-0.05)
	panel.offset_bottom = Global.ph(0.65)
	overlay.add_child(panel)
	
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color.TRANSPARENT
	panel_style.corner_radius_top_left = 20
	panel_style.corner_radius_top_right = 20
	panel_style.corner_radius_bottom_left = 20
	panel_style.corner_radius_bottom_right = 20
	panel.add_theme_stylebox_override("panel", panel_style)
	
	# 标题
	var title = Label.new()
	title.text = "[" + cid + "] " + name_str
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 55)
	title.add_theme_color_override("font_color", Global.current.title if unlocked else Color(0.6, 0.6, 0.7))
	title.add_theme_color_override("font_shadow_color", Global.current.title_shadow)
	title.add_theme_constant_override("shadow_offset_x", 2)
	title.add_theme_constant_override("shadow_offset_y", 2)
	title.anchor_left = 0.0; title.anchor_top = 0.0
	title.anchor_right = 1.0; title.anchor_bottom = 0.0
	title.offset_left = Global.pw(0.04); title.offset_right = Global.pw(-0.04)
	title.offset_top = Global.ph(0.015); title.offset_bottom = Global.ph(0.065)
	panel.add_child(title)
	
	# 分隔线
	var line = ColorRect.new()
	line.color = Global.current.topbar_border
	line.anchor_left = 0.0; line.anchor_top = 0.0
	line.anchor_right = 1.0; line.anchor_bottom = 0.0
	line.offset_left = Global.pw(0.05); line.offset_top = Global.ph(0.07)
	line.offset_right = Global.pw(-0.05); line.offset_bottom = Global.ph(0.073)
	panel.add_child(line)
	
	var y = 0.078
	
	# 类别
	var cat_label = Label.new()
	cat_label.text = "类别：" + cat_name
	cat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cat_label.add_theme_font_size_override("font_size", 40)
	cat_label.add_theme_color_override("font_color", Global.current.btn_text)
	cat_label.anchor_left = 0.0; cat_label.anchor_top = 0.0
	cat_label.anchor_right = 1.0; cat_label.anchor_bottom = 0.0
	cat_label.offset_left = 0; cat_label.offset_top = Global.ph(y)
	cat_label.offset_right = 0; cat_label.offset_bottom = Global.ph(y + 0.035)
	panel.add_child(cat_label)
	y += 0.04
	
	# 解锁状态
	var status_label = Label.new()
	if unlocked:
		status_label.text = "✅ 已解锁"
		status_label.add_theme_color_override("font_color", Color("#4CAF50"))
	else:
		if cond != "":
			status_label.text = "🔒 解锁条件：" + cond
		else:
			status_label.text = "🔒 初始解锁"
		status_label.add_theme_color_override("font_color", Color("#FF5252"))
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 38)
	status_label.anchor_left = 0.0; status_label.anchor_top = 0.0
	status_label.anchor_right = 1.0; status_label.anchor_bottom = 0.0
	status_label.offset_left = 0; status_label.offset_top = Global.ph(y)
	status_label.offset_right = 0; status_label.offset_bottom = Global.ph(y + 0.04)
	panel.add_child(status_label)
	y += 0.045
	
	# 负荷（醒目高亮 · 数值参数每点另计 +1.7）
	var load_val = info.get("base_load", null)
	if load_val != null:
		var load_label = Label.new()
		load_label.text = "⚡ 负荷：" + ("+" if load_val >= 0 else "") + str(load_val)
		load_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		load_label.add_theme_font_size_override("font_size", 46)
		load_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
		load_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
		load_label.add_theme_constant_override("shadow_offset_x", 1)
		load_label.add_theme_constant_override("shadow_offset_y", 1)
		load_label.anchor_left = 0.0; load_label.anchor_top = 0.0
		load_label.anchor_right = 1.0; load_label.anchor_bottom = 0.0
		load_label.offset_left = 0; load_label.offset_top = Global.ph(y)
		load_label.offset_right = 0; load_label.offset_bottom = Global.ph(y + 0.04)
		panel.add_child(load_label)
		y += 0.045
	
	# 参数信息
	var param_text = ""
	match cat:
		"TR":
			var speed_val = info.get("speed", "")
			if speed_val is float or speed_val is int or (speed_val is String and speed_val != ""):
				param_text += "速度：" + str(speed_val) + "\n"
			var once = info.get("once_only", false)
			param_text += "仅一次：" + ("是" if once else "否")
			var desc = info.get("desc", "")
			if desc != "":
				param_text += "\n\n" + desc
		"A":
			var energy = info.get("base_energy", "")
			if energy is float or energy is int or (energy is String and energy != ""):
				param_text += "基础能耗：" + str(energy) + "\n"
			var elem = info.get("default_element", "")
			if elem is String and elem != "":
				param_text += "默认元素：" + elem + "\n"
			param_text += "效果描述：对目标" + name_str
		"T":
			var modifier = info.get("modifier", "")
			if modifier is float or modifier is int or (modifier is String and modifier != ""):
				param_text += "目标倍率：×" + str(modifier)
		"C":
			var params = info.get("params", "")
			if params is String and params != "":
				param_text += "参数格式：" + params
		"CO":
			var adj = info.get("energy_adjust", "")
			if adj is float or adj is int or (adj is String and adj != ""):
				param_text += "能耗调整：" + str(adj)
	if param_text == "":
		param_text = "无额外参数"
	
	var param_label = Label.new()
	param_label.text = param_text
	param_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	param_label.add_theme_font_size_override("font_size", 36)
	param_label.add_theme_color_override("font_color", Global.current.title)
	param_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	param_label.anchor_left = 0.0; param_label.anchor_top = 0.0
	param_label.anchor_right = 1.0; param_label.anchor_bottom = 0.0
	param_label.offset_left = Global.pw(0.04); param_label.offset_right = Global.pw(-0.04)
	param_label.offset_top = Global.ph(y); param_label.offset_bottom = Global.ph(y + 0.12)
	panel.add_child(param_label)
	y += 0.13
	
	# 关闭按钮（仓库同款风格）
	var close_btn = Button.new()
	close_btn.text = "关闭"
	close_btn.add_theme_font_size_override("font_size", 40)
	var cs = StyleBoxFlat.new()
	cs.bg_color = Global.current.btn_bg
	cs.border_width_left = 2; cs.border_width_right = 2
	cs.border_width_top = 2; cs.border_width_bottom = 2
	cs.border_color = Color("#888888")
	cs.corner_radius_top_left = 12; cs.corner_radius_top_right = 12
	cs.corner_radius_bottom_left = 12; cs.corner_radius_bottom_right = 12
	close_btn.add_theme_stylebox_override("normal", cs)
	close_btn.add_theme_color_override("font_color", Global.current.title)
	close_btn.anchor_left = 0.3; close_btn.anchor_top = 0.0
	close_btn.anchor_right = 0.7; close_btn.anchor_bottom = 0.0
	close_btn.offset_left = 0; close_btn.offset_top = Global.ph(y)
	close_btn.offset_right = 0; close_btn.offset_bottom = Global.ph(y + 0.07)
	close_btn.pressed.connect(_on_detail_close.bind(overlay))
	panel.add_child(close_btn)


func _on_detail_close(overlay: ColorRect):
	Global.play_sfx("click")
	_popup_open = false
	overlay.queue_free()


func _on_back():
	Global.play_sfx("click")
	Global.change_scene("res://CardWorkshop.tscn")


func _on_theme_changed(_mode):
	_apply_theme_colors()
	_refresh_list()


# ===== 长按弹窗系统 =====

func _setup_long_press() -> void:
	set_process(true)

func _process(delta: float) -> void:
	if _pressed_row != null:
		_press_timer += delta
		if _press_timer >= LONG_PRESS_TIME:
			_long_press_triggered = true
			_show_detail(_pressed_row)
			_cancel_press()

func _input(event: InputEvent) -> void:
	if _popup_open:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			# 按下：找到触摸位置下的纹路行
			_long_press_triggered = false
			var row = _find_row_at(event.position)
			if row != null:
				_pressed_row = row
				_press_timer = 0.0
				_press_start_pos = event.position
				_press_index = event.index
				# 高亮行背景
				var sb = StyleBoxFlat.new()
				sb.bg_color = Global.current.btn_bg_hover
				row.add_theme_stylebox_override("panel", sb)
		else:
			# 松开：判断是否触发了长按
			if event.index == _press_index:
				if not _long_press_triggered:
					# 短按：弹出点击详情
					var cid = _pressed_row.get_meta("comp_id", "") if _pressed_row != null else ""
					if cid != "":
						_show_component_detail(cid)
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
	# 注意：不重置 _long_press_triggered，由新触摸时重置


func _show_detail(row: Control):
	_popup_open = true
	var comp = row.get_meta("row_data", {})
	if comp.is_empty():
		return
	var cid = comp.get("id", "")
	var name_str = comp.get("name", cid)
	var cat_name = comp.get("category_name", "")
	var cat = comp.get("category", "")
	var unlocked = CircuitManager.is_unlocked(cid)
	var cond = CircuitManager.get_unlock_condition(cid)
	var info = CircuitManager.get_component_info(cid)
	
	var overlay = ColorRect.new()
	overlay.name = "LongPressDetailOverlay"
	overlay.color = Color(0.0, 0.0, 0.0, 0.7)
	overlay.anchor_left = 0.0; overlay.anchor_top = 0.0
	overlay.anchor_right = 1.0; overlay.anchor_bottom = 1.0
	overlay.mouse_filter = MOUSE_FILTER_STOP
	overlay.gui_input.connect(_on_overlay_clicked.bind(overlay))
	add_child(overlay)
	
	var panel = ColorRect.new()
	panel.name = "DetailPanel"
	panel.color = Global.current.bg
	panel.anchor_left = 0.0; panel.anchor_top = 0.0
	panel.anchor_right = 1.0; panel.anchor_bottom = 0.0
	panel.offset_left = Global.pw(0.05)
	panel.offset_top = Global.ph(0.15)
	panel.offset_right = Global.pw(-0.05)
	panel.offset_bottom = Global.ph(0.65)
	overlay.add_child(panel)
	
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color.TRANSPARENT
	panel_style.corner_radius_top_left = 20
	panel_style.corner_radius_top_right = 20
	panel_style.corner_radius_bottom_left = 20
	panel_style.corner_radius_bottom_right = 20
	panel.add_theme_stylebox_override("panel", panel_style)
	
	# 标题
	var title = Label.new()
	title.text = "[" + cid + "] " + name_str
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 55)
	title.add_theme_color_override("font_color", Global.current.title if unlocked else Color(0.6, 0.6, 0.7))
	title.add_theme_color_override("font_shadow_color", Global.current.title_shadow)
	title.add_theme_constant_override("shadow_offset_x", 2)
	title.add_theme_constant_override("shadow_offset_y", 2)
	title.anchor_left = 0.0; title.anchor_top = 0.0
	title.anchor_right = 1.0; title.anchor_bottom = 0.0
	title.offset_left = Global.pw(0.04); title.offset_right = Global.pw(-0.04)
	title.offset_top = Global.ph(0.015); title.offset_bottom = Global.ph(0.065)
	panel.add_child(title)
	
	# 分隔线
	var line = ColorRect.new()
	line.color = Global.current.topbar_border
	line.anchor_left = 0.0; line.anchor_top = 0.0
	line.anchor_right = 1.0; line.anchor_bottom = 0.0
	line.offset_left = Global.pw(0.05); line.offset_top = Global.ph(0.07)
	line.offset_right = Global.pw(-0.05); line.offset_bottom = Global.ph(0.073)
	panel.add_child(line)
	
	var y = 0.078
	
	# 类别
	var cat_label = Label.new()
	cat_label.text = "类别：" + cat_name
	cat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cat_label.add_theme_font_size_override("font_size", 40)
	cat_label.add_theme_color_override("font_color", Global.current.btn_text)
	cat_label.anchor_left = 0.0; cat_label.anchor_top = 0.0
	cat_label.anchor_right = 1.0; cat_label.anchor_bottom = 0.0
	cat_label.offset_left = 0; cat_label.offset_top = Global.ph(y)
	cat_label.offset_right = 0; cat_label.offset_bottom = Global.ph(y + 0.035)
	panel.add_child(cat_label)
	y += 0.04
	
	# 解锁状态
	var status_label = Label.new()
	if unlocked:
		status_label.text = "✅ 已解锁"
		status_label.add_theme_color_override("font_color", Color("#4CAF50"))
	else:
		if cond != "":
			status_label.text = "🔒 解锁条件：" + cond
		else:
			status_label.text = "🔒 初始解锁"
		status_label.add_theme_color_override("font_color", Color("#FF5252"))
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 38)
	status_label.anchor_left = 0.0; status_label.anchor_top = 0.0
	status_label.anchor_right = 1.0; status_label.anchor_bottom = 0.0
	status_label.offset_left = 0; status_label.offset_top = Global.ph(y)
	status_label.offset_right = 0; status_label.offset_bottom = Global.ph(y + 0.04)
	panel.add_child(status_label)
	y += 0.045
	
	# 负荷（醒目高亮 · 数值参数每点另计 +1.7）
	var load_val = info.get("base_load", null)
	if load_val != null:
		var load_label = Label.new()
		load_label.text = "⚡ 负荷：" + ("+" if load_val >= 0 else "") + str(load_val)
		load_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		load_label.add_theme_font_size_override("font_size", 46)
		load_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
		load_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
		load_label.add_theme_constant_override("shadow_offset_x", 1)
		load_label.add_theme_constant_override("shadow_offset_y", 1)
		load_label.anchor_left = 0.0; load_label.anchor_top = 0.0
		load_label.anchor_right = 1.0; load_label.anchor_bottom = 0.0
		load_label.offset_left = 0; load_label.offset_top = Global.ph(y)
		load_label.offset_right = 0; load_label.offset_bottom = Global.ph(y + 0.04)
		panel.add_child(load_label)
		y += 0.045
	
	# 参数信息
	var param_text = ""
	match cat:
		"TR":
			var speed_val = info.get("speed", "")
			if speed_val is float or speed_val is int or (speed_val is String and speed_val != ""):
				param_text += "速度：" + str(speed_val) + "\n"
			var once = info.get("once_only", false)
			param_text += "仅一次：" + ("是" if once else "否")
			var desc = info.get("desc", "")
			if desc != "":
				param_text += "\n\n" + desc
		"A":
			var energy = info.get("base_energy", "")
			if energy is float or energy is int or (energy is String and energy != ""):
				param_text += "基础能耗：" + str(energy) + "\n"
			var elem = info.get("default_element", "")
			if elem is String and elem != "":
				param_text += "默认元素：" + elem + "\n"
			param_text += "效果描述：对目标" + name_str
		"T":
			var modifier = info.get("modifier", "")
			if modifier is float or modifier is int or (modifier is String and modifier != ""):
				param_text += "目标倍率：×" + str(modifier)
		"C":
			var params = info.get("params", "")
			if params is String and params != "":
				param_text += "参数格式：" + params
		"CO":
			var adj = info.get("energy_adjust", "")
			if adj is float or adj is int or (adj is String and adj != ""):
				param_text += "能耗调整：" + str(adj)
	if param_text == "":
		param_text = "无额外参数"
	
	var param_label = Label.new()
	param_label.text = param_text
	param_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	param_label.add_theme_font_size_override("font_size", 36)
	param_label.add_theme_color_override("font_color", Global.current.title)
	param_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	param_label.anchor_left = 0.0; param_label.anchor_top = 0.0
	param_label.anchor_right = 1.0; param_label.anchor_bottom = 0.0
	param_label.offset_left = Global.pw(0.04); param_label.offset_right = Global.pw(-0.04)
	param_label.offset_top = Global.ph(y); param_label.offset_bottom = Global.ph(y + 0.12)
	panel.add_child(param_label)
	y += 0.13
	
	# 关闭按钮（仓库同款风格）
	var close_btn = Button.new()
	close_btn.text = "关闭"
	close_btn.add_theme_font_size_override("font_size", 40)
	var cs = StyleBoxFlat.new()
	cs.bg_color = Global.current.btn_bg
	cs.border_width_left = 2; cs.border_width_right = 2
	cs.border_width_top = 2; cs.border_width_bottom = 2
	cs.border_color = Color("#888888")
	cs.corner_radius_top_left = 12; cs.corner_radius_top_right = 12
	cs.corner_radius_bottom_left = 12; cs.corner_radius_bottom_right = 12
	close_btn.add_theme_stylebox_override("normal", cs)
	close_btn.add_theme_color_override("font_color", Global.current.title)
	close_btn.anchor_left = 0.3; close_btn.anchor_top = 0.0
	close_btn.anchor_right = 0.7; close_btn.anchor_bottom = 0.0
	close_btn.offset_left = 0; close_btn.offset_top = Global.ph(y)
	close_btn.offset_right = 0; close_btn.offset_bottom = Global.ph(y + 0.07)
	close_btn.pressed.connect(_on_detail_close.bind(overlay))
	panel.add_child(close_btn)
