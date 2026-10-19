extends Control
var _last_applied_mode = null
var _tex_night: Texture2D
var _tex_day: Texture2D

func _ready():
	var _t0 = Time.get_ticks_msec()
	# ---- 静态界面：UI 节点已在 CardWorkshop.tscn 中声明 ----
	var back := get_node_or_null("BackBtn")
	if back is Button: back.pressed.connect(_on_back)
	var help := get_node_or_null("HelpBtn")
	if help is Button: help.pressed.connect(_on_help)
	# 5 个功能按钮
	var btn_map = {
		"BtnCardBase": "制作卡基",
		"BtnInk": "调制卡墨",
		"BtnEngrave": "刻画卡牌",
		"BtnCircuit": "纹路图鉴",
		"BtnWarehouse": "仓库",
	}
	for bname in btn_map:
		var btn = get_node_or_null(bname)
		if btn is Button:
			var text = btn_map[bname]
			btn.pressed.connect(_on_workshop_btn_pressed.bind(text))
	Global.theme_changed.connect(_on_theme_changed)
	call_deferred("_apply_theme_styles")
	print("[CardWorkshop] _ready 完成: %dms" % [Time.get_ticks_msec() - _t0])

func _on_theme_changed(mode = null):
	if mode == null: mode = Global.current_mode
	_apply_theme_styles()

func _apply_theme_styles():
	var mode = Global.current_mode
	var is_day = mode == Global.ThemeMode.DAY
	# 背景纹理
	var bg = get_node_or_null("Background")
	if bg and bg is TextureRect:
		if _tex_night == null:
			_tex_night = load("res://assets/theme/bg_night.png")
			_tex_day = load("res://assets/theme/bg_day.png")
		bg.texture = _tex_day if is_day else _tex_night
	# 顶栏
	var topbar = get_node_or_null("TopBar")
	if topbar and topbar is ColorRect: topbar.color = Global.current.topbar_bg
	var topbar_line = get_node_or_null("TopBarLine")
	if topbar_line and topbar_line is ColorRect: topbar_line.color = Global.current.topbar_border
	# 标题
	var title = get_node_or_null("Title")
	if title and title is Label:
		title.add_theme_color_override("font_color", Global.current.title)
		title.add_theme_color_override("font_shadow_color", Global.current.title_shadow)
		title.add_theme_constant_override("shadow_offset_x", Global.current.shadow_offset)
		title.add_theme_constant_override("shadow_offset_y", Global.current.shadow_offset)
	# 按钮样式
	var mode_key = mode
	if _last_applied_mode == mode_key: return
	_last_applied_mode = mode_key
	var icon_c = Color("#645C50") if is_day else Color("#CBCBE0")
	var btn_bg = Color(0.15, 0.13, 0.20, 0.85) if not is_day else Color(0.90, 0.85, 0.75, 0.85)
	var btn_bg_hover = btn_bg.lightened(0.12)
	var btn_bg_pressed = btn_bg.darkened(0.15)
	var border_c = Color("#E8A838") if not is_day else Color("#946F38")
	for bname in ["BackBtn", "HelpBtn", "BtnCardBase", "BtnInk", "BtnEngrave", "BtnCircuit", "BtnWarehouse"]:
		var btn = get_node_or_null(bname)
		if not btn is Button: continue
		btn.add_theme_color_override("font_color", icon_c)
		btn.add_theme_color_override("font_hover_color", icon_c.lightened(0.15))
		btn.add_theme_color_override("font_pressed_color", icon_c.darkened(0.2))
		for state in ["normal", "hover", "pressed", "focus"]:
			var sb = StyleBoxFlat.new()
			sb.bg_color = btn_bg_hover if state == "hover" else (btn_bg_pressed if state == "pressed" else btn_bg)
			sb.border_width_left = 2; sb.border_width_right = 2
			sb.border_width_top = 2; sb.border_width_bottom = 2
			sb.border_color = border_c
			sb.corner_radius_top_left = 12; sb.corner_radius_top_right = 12
			sb.corner_radius_bottom_left = 12; sb.corner_radius_bottom_right = 12
			sb.content_margin_left = 16; sb.content_margin_right = 16
			sb.content_margin_top = 8; sb.content_margin_bottom = 8
			btn.add_theme_stylebox_override(state, sb)

func _on_workshop_btn_pressed(text: String):
	Global.play_sfx("click")
	match text:
		"制作卡基": Global.change_scene("res://CardBaseMaking.tscn")
		"调制卡墨": Global.change_scene("res://InkMaking.tscn")
		"刻画卡牌": Global.change_scene("res://CardEngraving.tscn")
		"纹路图鉴": Global.change_scene("res://CircuitGallery.tscn")
		"仓库": Global.change_scene("res://Warehouse.tscn")

func _on_back(): Global.play_sfx("click"); Global.change_scene("res://Main.tscn")

func _on_help(): Global.play_sfx("click"); _show_help_guide()

func _show_help_guide():
	var overlay = ColorRect.new()
	overlay.name = "HelpOverlay"; overlay.color = Color(0,0,0,0.7)
	overlay.anchor_left = 0.0; overlay.anchor_top = 0.0; overlay.anchor_right = 1.0; overlay.anchor_bottom = 1.0
	overlay.mouse_filter = MOUSE_FILTER_STOP
	overlay.gui_input.connect(func(ev): if ev is InputEventMouseButton and ev.pressed: Global.play_sfx("click"); overlay.queue_free())
	add_child(overlay)
	var panel = Panel.new()
	panel.name = "HelpPanel"; panel.anchor_left = 0.05; panel.anchor_top = 0.05; panel.anchor_right = 0.95; panel.anchor_bottom = 0.95
	panel.clip_contents = true
	var ps = StyleBoxFlat.new()
	ps.bg_color = Global.current.bg; ps.border_width_left = 3; ps.border_width_right = 3; ps.border_width_top = 3; ps.border_width_bottom = 3
	ps.border_color = Color("#e8a838"); ps.corner_radius_top_left = 16; ps.corner_radius_top_right = 16
	ps.corner_radius_bottom_left = 16; ps.corner_radius_bottom_right = 16
	panel.add_theme_stylebox_override("panel", ps); overlay.add_child(panel)
	var title = Label.new()
	title.text = "制卡工坊指南"; title.add_theme_font_size_override("font_size", 60)
	title.add_theme_color_override("font_color", Global.current.title)
	title.horizontal_alignment = 1; title.anchor_left = 0.0; title.anchor_top = 0.0; title.anchor_right = 1.0; title.anchor_bottom = 0.0
	title.offset_left = 0; title.offset_top = Global.ph(0.01); title.offset_right = 0; title.offset_bottom = Global.ph(0.08)
	panel.add_child(title)
	var scroll = ScrollContainer.new()
	scroll.name = "HelpScroll"
	scroll.anchor_left = 0.02; scroll.anchor_top = 0.0; scroll.anchor_right = 0.98; scroll.anchor_bottom = 1.0
	scroll.offset_left = 0; scroll.offset_top = Global.ph(0.085); scroll.offset_right = 0; scroll.offset_bottom = Global.ph(-0.08)
	scroll.scroll_horizontal = false; panel.add_child(scroll)
	var vbox = VBoxContainer.new()
	vbox.name = "HelpVBox"; vbox.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	vbox.add_theme_constant_override("separation", Global.ph(0.008)); scroll.add_child(vbox)
	_build_help_content(vbox)
	call_deferred("_set_help_vbox_width", vbox, scroll)
	var close_btn = Button.new()
	close_btn.text = "关闭"; close_btn.add_theme_font_size_override("font_size", 50)
	var cs = StyleBoxFlat.new()
	cs.bg_color = Global.current.btn_bg; cs.border_width_left = 2; cs.border_width_right = 2; cs.border_width_top = 2; cs.border_width_bottom = 2
	cs.border_color = Color("#888888"); cs.corner_radius_top_left = 10; cs.corner_radius_top_right = 10
	cs.corner_radius_bottom_left = 10; cs.corner_radius_bottom_right = 10
	close_btn.add_theme_stylebox_override("normal", cs)
	close_btn.add_theme_color_override("font_color", Global.current.btn_text)
	close_btn.anchor_left = 0.3; close_btn.anchor_top = 1.0; close_btn.anchor_right = 0.7; close_btn.anchor_bottom = 1.0
	close_btn.offset_left = 0; close_btn.offset_top = Global.ph(-0.075); close_btn.offset_right = 0; close_btn.offset_bottom = Global.ph(-0.01)
	close_btn.pressed.connect(func(): Global.play_sfx("click"); overlay.queue_free()); panel.add_child(close_btn)

func _set_help_vbox_width(vbox, scroll):
	if not is_instance_valid(vbox) or not is_instance_valid(scroll): return
	var w = scroll.size.x; if w <= 0: w = get_viewport_rect().size.x * 0.85
	vbox.custom_minimum_size = Vector2(w, 0)

func _make_help_section(vbox, title_text, title_color):
	var section = VBoxContainer.new()
	section.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	section.add_theme_constant_override("separation", Global.ph(0.005)); vbox.add_child(section)
	var sep = HSeparator.new()
	sep.add_theme_color_override("color", Global.current.topbar_border)
	sep.size_flags_horizontal = SIZE_FILL; section.add_child(sep)
	var lbl = Label.new()
	lbl.text = title_text; lbl.add_theme_font_size_override("font_size", 50)
	lbl.add_theme_color_override("font_color", title_color)
	lbl.size_flags_horizontal = SIZE_FILL; lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	section.add_child(lbl); return section

func _make_help_label(vbox, text, color = Color("#FFFFFF"), font_size = 45):
	var lbl = Label.new()
	lbl.text = text; lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.size_flags_horizontal = SIZE_FILL; vbox.add_child(lbl)

func _build_help_content(vbox):
	var s1 = _make_help_section(vbox, " ① 制卡工坊总览", Color("#e8a838"))
	_make_help_label(s1, "制卡工坊是制作和管理卡牌的核心场所，提供4个功能入口：", Global.current.btn_text, 42)
	_make_help_label(s1, " 制作卡基 — 选择素材制作卡牌底基", Color("#e8a838"), 45)
	_make_help_label(s1, " 调制卡墨 — 调配墨水用于刻画纹路", Color("#6c9bcf"), 45)
	_make_help_label(s1, " 刻画卡牌 — 在卡基上刻画纹路，完成卡牌制作", Color("#5cb85c"), 45)
	_make_help_label(s1, " 仓库 — 查看和管理所有素材、卡基、卡墨和成品卡牌", Color("#7f8c8d"), 45)
	_make_help_label(s1, " 完整流程：制作卡基 → 调制卡墨 → 刻画卡牌 → 编入牌组参战", Color("#FFD700"), 42)
	var s2 = _make_help_section(vbox, " ② 制作卡基", Color("#e8a838"))
	_make_help_label(s2, "选择纤维、矿粉、树脂三种素材，制作卡牌底基。", Global.current.btn_text, 42)
	_make_help_label(s2, "卡基的6个属性决定了卡牌的基础性能：", Color("#CCCCCC"))
	_make_help_label(s2, "  • 承载力（Load Cap）：决定纹路承载上限", Color("#FF9800"))
	_make_help_label(s2, "  • 卡槽（Slots）：决定可安装纹路组件数量", Color("#8BC34A"))
	_make_help_label(s2, "  • 耐久度（Durability）：决定卡牌战斗使用次数", Color("#E91E63"))
	_make_help_label(s2, "  • 品质（Quality）：影响成品卡牌的品质等级", Color("#9B59B6"))
	_make_help_label(s2, "  • 倾向（Tendency）：决定卡牌的主元素", Color("#FFD700"))
	_make_help_label(s2, "  • 消耗（Consumption）：显示用了哪些素材", Color("#95A5A6"))
	_make_help_label(s2, " 素材越多品质惩罚越大，建议在满足需求的前提下用最少种类", Color("#FFD700"), 42)
	var s3 = _make_help_section(vbox, " ③ 调制卡墨", Color("#6c9bcf"))
	_make_help_label(s3, "选择萃取液、颜料、粘合剂三种素材，调制卡墨。", Global.current.btn_text, 42)
	_make_help_label(s3, "卡墨的5个属性影响刻画纹路的效果：", Color("#CCCCCC"))
	_make_help_label(s3, "  • 负荷减免（Load Reduce）：降低纹路刻画能量消耗", Color("#4FC3F7"))
	_make_help_label(s3, "  • 效果强度（Effect Power）：提升纹路效果触发成功率", Color("#FF8A65"))
	_make_help_label(s3, "  • 品质稳定性（Quality Stability）：稳定卡基品质波动", Color("#FFD54F"))
	_make_help_label(s3, "  • 倾向折扣（Discount）：按元素降低纹路能量消耗", Color("#FFD700"))
	_make_help_label(s3, "  • 属性抗性（Resistance）：提升卡牌对元素伤害的抗性", Color("#E91E63"))
	_make_help_label(s3, " 每种素材最多选1个，无素材数量惩罚", Color("#4CAF50"), 42)
	var s4 = _make_help_section(vbox, " ④ 刻画卡牌", Color("#5cb85c"))
	_make_help_label(s4, "在已制作的卡基上，使用卡墨刻画纹路，完成卡牌制作。", Global.current.btn_text, 42)
	_make_help_label(s4, "刻画步骤：", Color("#CCCCCC"))
	_make_help_label(s4, "  1. 选择一张已制作的【卡基】作为底材", Color("#CCCCCC"))
	_make_help_label(s4, "  2. 选择已调制的【卡墨】作为墨水", Color("#CCCCCC"))
	_make_help_label(s4, "  3. 选择要刻画的【纹路】组件（攻击、防御、效果等）", Color("#CCCCCC"))
	_make_help_label(s4, "  4. 消耗能量完成刻画，生成成品卡牌", Color("#CCCCCC"))
	_make_help_label(s4, " 卡基的承载力、卡槽和卡墨的品质稳定性会影响刻画成功率", Color("#FFD700"), 42)
	var s5 = _make_help_section(vbox, " ⑤ 仓库", Color("#7f8c8d"))
	_make_help_label(s5, "仓库是存放所有素材、半成品和成品的空间。", Global.current.btn_text, 42)
	_make_help_label(s5, "仓库分类：", Color("#CCCCCC"))
	_make_help_label(s5, "  • 素材（Materials）：采集获得的纤维、矿粉、树脂等原料", Color("#CCCCCC"))
	_make_help_label(s5, "  • 卡基（Card Bases）：制作完成的卡牌底基", Color("#CCCCCC"))
	_make_help_label(s5, "  • 卡墨（Inks）：调制完成的墨水", Color("#CCCCCC"))
	_make_help_label(s5, "  • 卡牌（Cards）：刻画完成的成品卡牌", Color("#CCCCCC"))
	_make_help_label(s5, " 长按素材/卡基/卡墨可查看详情，长按卡牌可查看属性", Color("#FFD700"), 42)
	var s6 = _make_help_section(vbox, " ⑥ 完整制作流程", Color("#4CAF50"))
	_make_help_label(s6, "从零到一张可用的卡牌，需要经过以下步骤：", Global.current.btn_text, 42)
	_make_help_label(s6, "Step 1  采集素材 — 在关卡中采集纤维、矿粉、树脂等原料", Color("#FF9800"), 45)
	_make_help_label(s6, "Step 2  制作卡基 — 在制卡工坊选择素材制作卡牌底基", Color("#e8a838"), 45)
	_make_help_label(s6, "Step 3  调制卡墨 — 调配适合的墨水，优化纹路刻画效果", Color("#6c9bcf"), 45)
	_make_help_label(s6, "Step 4  刻画卡牌 — 在卡基上刻画纹路，生成成品卡牌", Color("#5cb85c"), 45)
	_make_help_label(s6, "Step 5  编入牌组 — 将成品卡牌编入出战牌组", Color("#7f8c8d"), 45)
	_make_help_label(s6, "Step 6  投入战斗 — 在关卡中使用卡牌战斗！", Color("#FFD700"), 45)
	_make_help_label(s6, " 高品质卡基 + 合适卡墨 = 更强力的成品卡牌！", Color("#FFD700"), 42)
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, Global.ph(0.02))
	vbox.add_child(spacer)