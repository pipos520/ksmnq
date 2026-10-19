extends Control
## ============================================================
##  个人信息 —— 称号、制卡进度、纹路收集（静态化）
## ============================================================
var _last_applied_mode = null

func _ready():
	call_deferred("_maybe_show_info_tour")
	# ---- 静态节点已在 PlayerInfo.tscn 中声明 ----
	var back := get_node_or_null("BackBtn")
	if back is Button: back.pressed.connect(_on_back)
	var help := get_node_or_null("HelpBtn")
	if help is Button: help.pressed.connect(_on_help)

	# 主题
	Global.theme_changed.connect(_on_theme_changed)
	call_deferred("_apply_theme_styles")
	call_deferred("_build_content")

func _on_theme_changed(mode = null):
	_apply_theme_styles()

func _apply_theme_styles():
	var mode = Global.current_mode
	var is_day = mode == Global.ThemeMode.DAY
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
	# 按钮
	var mode_key = mode
	if _last_applied_mode == mode_key: return
	_last_applied_mode = mode_key
	var icon_c = Color("#645C50") if is_day else Color("#CBCBE0")
	var btn_bg = Color(0.15, 0.13, 0.20, 0.85) if not is_day else Color(0.90, 0.85, 0.75, 0.85)
	var btn_bg_hover = btn_bg.lightened(0.12)
	var btn_bg_pressed = btn_bg.darkened(0.15)
	var border_c = Color("#E8A838") if not is_day else Color("#946F38")
	for bname in ["BackBtn", "HelpBtn"]:
		var btn = get_node_or_null(bname)
		if not btn is Button: continue
		btn.add_theme_color_override("font_color", icon_c)
		btn.add_theme_color_override("font_hover_color", icon_c.lightened(0.15))
		btn.add_theme_color_override("font_pressed_color", icon_c.darkened(0.2))
		for state in ["normal", "hover", "pressed", "focus"]:
			var sb = StyleBoxFlat.new()
			sb.bg_color = btn_bg_hover if state == "hover" else (btn_bg_pressed if state == "pressed" else btn_bg)
			sb.border_width_left = 2; sb.border_width_right = 2; sb.border_width_top = 2; sb.border_width_bottom = 2
			sb.border_color = border_c
			sb.corner_radius_top_left = 12; sb.corner_radius_top_right = 12
			sb.corner_radius_bottom_left = 12; sb.corner_radius_bottom_right = 12
			sb.content_margin_left = 16; sb.content_margin_right = 16; sb.content_margin_top = 8; sb.content_margin_bottom = 8
			btn.add_theme_stylebox_override(state, sb)

func _build_content():
	var content = get_node_or_null("Content")
	if not content: return
	var cards_created = PlayerManager.get_cards_created()
	var highest_quality = PlayerManager.get_highest_quality()
	var guild_level = PlayerManager.get_guild_level()
	var guild_title = PlayerManager.get_guild_title()

	# 称号卡片
	var title_card = Panel.new()
	title_card.name = "TitleCard"
	title_card.anchor_left = 0.0; title_card.anchor_top = 0.0; title_card.anchor_right = 1.0; title_card.anchor_bottom = 0.0
	title_card.offset_left = 0; title_card.offset_top = 0; title_card.offset_right = 0; title_card.offset_bottom = Global.ph(0.15)
	var ts = StyleBoxFlat.new()
	ts.bg_color = Global.current.bg
	ts.corner_radius_top_left = 20; ts.corner_radius_top_right = 20
	ts.corner_radius_bottom_left = 20; ts.corner_radius_bottom_right = 20
	ts.border_width_left = 2; ts.border_width_right = 2
	ts.border_width_top = 2; ts.border_width_bottom = 2
	ts.border_color = Color("#6c9bcf")
	title_card.add_theme_stylebox_override("panel", ts)
	content.add_child(title_card)

	var icon = Label.new()
	icon.name = "Icon"
	icon.text = "🏛️"
	icon.add_theme_font_size_override("font_size", 80)
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon.anchor_left = 0.0; icon.anchor_top = 0.0; icon.anchor_right = 0.0; icon.anchor_bottom = 1.0
	icon.offset_left = Global.pw(0.02); icon.offset_right = Global.pw(0.18)
	title_card.add_child(icon)

	var title_label = Label.new()
	title_label.name = "TitleLabel"
	title_label.text = "Lv." + str(guild_level) + "  " + guild_title
	title_label.add_theme_font_size_override("font_size", 65)
	title_label.add_theme_color_override("font_color", Color("#FFD700"))
	Global.make_gold_legible(title_label)
	title_label.add_theme_color_override("font_shadow_color", Color("#8B6914"))
	title_label.add_theme_constant_override("shadow_offset_x", 2)
	title_label.add_theme_constant_override("shadow_offset_y", 2)
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.anchor_left = 0.0; title_label.anchor_top = 0.0; title_label.anchor_right = 1.0; title_label.anchor_bottom = 0.5
	title_label.offset_left = Global.pw(0.2)
	title_card.add_child(title_label)

	var next_info = PlayerManager.get_next_guild_level_info()
	if not next_info.is_max:
		var next_tip = ""
		for c in next_info.conditions:
			next_tip += ("✅ " if c.done else "❌ ") + c.text
			if c.current != "":
				next_tip += "（" + c.current + "）"
			next_tip += "\n"
		var next_label = Label.new()
		next_label.name = "NextLabel"
		next_label.text = "下一级：Lv." + str(next_info.level) + " " + next_info.title + "\n" + next_tip
		next_label.add_theme_font_size_override("font_size", 35)
		next_label.add_theme_color_override("font_color", Global.current.btn_text)
		next_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		next_label.anchor_left = 0.0; next_label.anchor_top = 0.5; next_label.anchor_right = 1.0; next_label.anchor_bottom = 1.0
		next_label.offset_left = Global.pw(0.2); next_label.offset_bottom = Global.ph(-0.01)
		title_card.add_child(next_label)
	else:
		var max_label = Label.new()
		max_label.name = "MaxLabel"
		max_label.text = "🌟 已达成最高等级！"
		max_label.add_theme_font_size_override("font_size", 40)
		max_label.add_theme_color_override("font_color", Color("#FFD700"))
		Global.make_gold_legible(max_label)
		max_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		max_label.anchor_left = 0.0; max_label.anchor_top = 0.5; max_label.anchor_right = 1.0; max_label.anchor_bottom = 1.0
		max_label.offset_left = Global.pw(0.2)
		title_card.add_child(max_label)

	# 进度概览
	var overview = Panel.new()
	overview.name = "Overview"
	overview.anchor_left = 0.0; overview.anchor_top = 0.0; overview.anchor_right = 1.0; overview.anchor_bottom = 0.0
	overview.offset_left = 0; overview.offset_top = Global.ph(0.17)
	overview.offset_right = 0; overview.offset_bottom = Global.ph(0.40)
	var os = StyleBoxFlat.new()
	os.bg_color = Global.current.bg
	os.corner_radius_top_left = 20; os.corner_radius_top_right = 20
	os.corner_radius_bottom_left = 20; os.corner_radius_bottom_right = 20
	os.border_width_left = 2; os.border_width_right = 2
	os.border_width_top = 2; os.border_width_bottom = 2
	os.border_color = Color("#888888")
	overview.add_theme_stylebox_override("panel", os)
	content.add_child(overview)

	var ov_title = Label.new()
	ov_title.name = "OvTitle"
	ov_title.text = "📊 制卡进度"
	ov_title.add_theme_font_size_override("font_size", 50)
	ov_title.add_theme_color_override("font_color", Global.current.title)
	ov_title.add_theme_color_override("font_shadow_color", Global.current.title_shadow)
	ov_title.add_theme_constant_override("shadow_offset_x", Global.current.shadow_offset)
	ov_title.add_theme_constant_override("shadow_offset_y", Global.current.shadow_offset)
	ov_title.anchor_left = 0.0; ov_title.anchor_top = 0.0; ov_title.anchor_right = 1.0; ov_title.anchor_bottom = 0.0
	ov_title.offset_left = Global.pw(0.04); ov_title.offset_top = Global.ph(0.01); ov_title.offset_bottom = Global.ph(0.06)
	overview.add_child(ov_title)

	var ov_line = ColorRect.new()
	ov_line.name = "OvLine"
	ov_line.color = Global.current.topbar_border
	ov_line.anchor_left = 0.0; ov_line.anchor_top = 0.0; ov_line.anchor_right = 1.0; ov_line.anchor_bottom = 0.0
	ov_line.offset_left = Global.pw(0.03); ov_line.offset_top = Global.ph(0.06)
	ov_line.offset_right = Global.pw(-0.03); ov_line.offset_bottom = Global.ph(0.06) + 2
	overview.add_child(ov_line)

	var items = [
		{"label": "制作卡牌", "value": str(cards_created) + " 张", "color": Color("#FFD700")},
		{"label": "最高品质", "value": highest_quality if highest_quality != "" else "暂无", "color": Color("#FF6B6B")},
		{"label": "地图进度", "value": PlayerManager.get_map_progress_text(), "color": Color("#5cb85c")},
	]
	var item_start_y = 0.07
	for i in range(items.size()):
		var item = items[i]
		var y = item_start_y + i * 0.055
		var item_label = Label.new()
		item_label.text = item.label
		item_label.add_theme_font_size_override("font_size", 40)
		item_label.add_theme_color_override("font_color", Global.current.btn_text)
		item_label.anchor_left = 0.0; item_label.anchor_top = 0.0; item_label.anchor_right = 0.5; item_label.anchor_bottom = 0.0
		item_label.offset_left = Global.pw(0.04); item_label.offset_top = Global.ph(y); item_label.offset_bottom = Global.ph(y + 0.045)
		overview.add_child(item_label)
		var item_val = Label.new()
		item_val.text = item.value
		item_val.add_theme_font_size_override("font_size", 40)
		item_val.add_theme_color_override("font_color", item.color)
		item_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		item_val.anchor_left = 0.5; item_val.anchor_top = 0.0; item_val.anchor_right = 1.0; item_val.anchor_bottom = 0.0
		item_val.offset_left = 0; item_val.offset_top = Global.ph(y)
		item_val.offset_right = Global.pw(-0.04); item_val.offset_bottom = Global.ph(y + 0.045)
		overview.add_child(item_val)

	# 纹路收集进度
	var circuit_panel = Panel.new()
	circuit_panel.name = "CircuitPanel"
	circuit_panel.anchor_left = 0.0; circuit_panel.anchor_top = 0.0; circuit_panel.anchor_right = 1.0; circuit_panel.anchor_bottom = 0.0
	circuit_panel.offset_left = 0; circuit_panel.offset_top = Global.ph(0.42)
	circuit_panel.offset_right = 0; circuit_panel.offset_bottom = Global.ph(0.60)
	var cs = StyleBoxFlat.new()
	cs.bg_color = Global.current.bg
	cs.corner_radius_top_left = 20; cs.corner_radius_top_right = 20
	cs.corner_radius_bottom_left = 20; cs.corner_radius_bottom_right = 20
	cs.border_width_left = 2; cs.border_width_right = 2
	cs.border_width_top = 2; cs.border_width_bottom = 2
	cs.border_color = Color("#888888")
	circuit_panel.add_theme_stylebox_override("panel", cs)
	content.add_child(circuit_panel)

	var cp_title = Label.new()
	cp_title.name = "CPTitle"
	cp_title.text = "🔮 纹路收集"
	cp_title.add_theme_font_size_override("font_size", 50)
	cp_title.add_theme_color_override("font_color", Global.current.title)
	cp_title.add_theme_color_override("font_shadow_color", Global.current.title_shadow)
	cp_title.add_theme_constant_override("shadow_offset_x", Global.current.shadow_offset)
	cp_title.add_theme_constant_override("shadow_offset_y", Global.current.shadow_offset)
	cp_title.anchor_left = 0.0; cp_title.anchor_top = 0.0; cp_title.anchor_right = 1.0; cp_title.anchor_bottom = 0.0
	cp_title.offset_left = Global.pw(0.04); cp_title.offset_top = Global.ph(0.01); cp_title.offset_bottom = Global.ph(0.06)
	circuit_panel.add_child(cp_title)

	var cp_line = ColorRect.new()
	cp_line.name = "CPLine"
	cp_line.color = Global.current.topbar_border
	cp_line.anchor_left = 0.0; cp_line.anchor_top = 0.0; cp_line.anchor_right = 1.0; cp_line.anchor_bottom = 0.0
	cp_line.offset_left = Global.pw(0.03); cp_line.offset_top = Global.ph(0.06)
	cp_line.offset_right = Global.pw(-0.03); cp_line.offset_bottom = Global.ph(0.06) + 2
	circuit_panel.add_child(cp_line)

	var unlocked_circuits = CircuitManager.get_all_components_flat().map(func(c): return c.id).filter(func(cid): return CircuitManager.is_unlocked(cid))
	var total_circuits = CircuitManager.get_all_components_flat().size()

	var cp_count = Label.new()
	cp_count.name = "CPCount"
	cp_count.text = "已解锁： " + str(unlocked_circuits.size()) + " / " + str(total_circuits)
	cp_count.add_theme_font_size_override("font_size", 40)
	cp_count.add_theme_color_override("font_color", Color("#9b59b6"))
	cp_count.anchor_left = 0.0; cp_count.anchor_top = 0.0; cp_count.anchor_right = 1.0; cp_count.anchor_bottom = 0.0
	cp_count.offset_left = Global.pw(0.04); cp_count.offset_top = Global.ph(0.07); cp_count.offset_bottom = Global.ph(0.12)
	circuit_panel.add_child(cp_count)

	var gallery_btn = Button.new()
	gallery_btn.name = "GalleryBtn"
	gallery_btn.text = "🔮 查看纹路图鉴"
	gallery_btn.add_theme_font_size_override("font_size", 40)
	var gs = StyleBoxFlat.new()
	gs.bg_color = Global.current.btn_bg
	gs.border_width_left = 2; gs.border_width_right = 2
	gs.border_width_top = 2; gs.border_width_bottom = 2
	gs.border_color = Color("#e8a838")
	gs.corner_radius_top_left = 10; gs.corner_radius_top_right = 10
	gs.corner_radius_bottom_left = 10; gs.corner_radius_bottom_right = 10
	gallery_btn.add_theme_stylebox_override("normal", gs)
	gallery_btn.add_theme_color_override("font_color", Global.current.btn_text)
	gallery_btn.anchor_left = 0.0; gallery_btn.anchor_top = 0.0; gallery_btn.anchor_right = 1.0; gallery_btn.anchor_bottom = 0.0
	gallery_btn.offset_left = Global.pw(0.1); gallery_btn.offset_top = Global.ph(0.13)
	gallery_btn.offset_right = Global.pw(-0.1); gallery_btn.offset_bottom = Global.ph(0.18)
	gallery_btn.pressed.connect(_on_gallery)
	circuit_panel.add_child(gallery_btn)

func _on_help():
	Global.play_sfx("click")
	_show_guild_guide()

func _show_guild_guide():
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

	var title = Label.new()
	title.text = "🏛️ 公会等级指南"
	title.add_theme_font_size_override("font_size", 60)
	title.add_theme_color_override("font_color", Global.current.title)
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
	vbox.add_theme_constant_override("separation", Global.ph(0.006))
	scroll.add_child(vbox)

	var intro = Label.new()
	intro.text = "公会等级通过完成制卡和挑战来提升，等级越高可解锁的纹路越多！"
	intro.add_theme_font_size_override("font_size", 35)
	intro.add_theme_color_override("font_color", Global.current.btn_text)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(intro)

	var line = HSeparator.new()
	line.add_theme_color_override("color", Global.current.topbar_border)
	vbox.add_child(line)

	var level_colors = [
		Color("#9E9E9E"), Color("#8D6E63"), Color("#4CAF50"), Color("#2196F3"),
		Color("#9C27B0"), Color("#E91E63"), Color("#FF9800"), Color("#F44336"),
		Color("#FFD700"), Color("#FF6F00")
	]
	for i in range(PlayerManager.GUILD_LEVELS.size()):
		var lv = PlayerManager.GUILD_LEVELS[i]
		var section = VBoxContainer.new()
		section.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
		section.add_theme_constant_override("separation", Global.ph(0.002))
		vbox.add_child(section)

		var lv_label = Label.new()
		var star = ""
		if i == 0: star = "🌱 "
		elif i == PlayerManager.GUILD_LEVELS.size() - 1: star = "👑 "
		else: star = "⭐ "
		lv_label.text = star + "Lv." + str(lv.level) + "  " + lv.title
		lv_label.add_theme_font_size_override("font_size", 45)
		lv_label.add_theme_color_override("font_color", level_colors[i] if i < level_colors.size() else Color("#FFD700"))
		section.add_child(lv_label)

		var conds = []
		if lv.cards_needed > 0:
			conds.append("制作 " + str(lv.cards_needed) + " 张卡牌")
		if lv.quality_needed != "":
			conds.append("品质达到【" + lv.quality_needed + "】")
		if lv.map_needed != "":
			conds.append("通关【" + lv.map_needed + "】")

		var cond_text = ""
		if conds.size() > 0:
			cond_text = "  └ 晋升条件：" + "、".join(conds)
		else:
			cond_text = "  └ 初始称号"

		var cond_label = Label.new()
		cond_label.text = cond_text
		cond_label.add_theme_font_size_override("font_size", 30)
		cond_label.add_theme_color_override("font_color", Global.current.btn_text)
		section.add_child(cond_label)

		if i < PlayerManager.GUILD_LEVELS.size() - 1:
			var l = HSeparator.new()
			l.add_theme_color_override("color", Global.current.topbar_border)
			section.add_child(l)

	call_deferred("_set_guide_vbox_width", vbox, scroll)

	# 关闭按钮（统一风格）
	var close_btn = Button.new()
	close_btn.text = "✕ 关闭"
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
	close_btn.pressed.connect(func():
		Global.play_sfx("click")
		overlay.queue_free()
	)
	panel.add_child(close_btn)

func _set_guide_vbox_width(vbox: VBoxContainer, scroll: ScrollContainer):
	if not is_instance_valid(vbox) or not is_instance_valid(scroll):
		return
	var w = scroll.size.x
	if w <= 0:
		w = get_viewport_rect().size.x * 0.85
	vbox.custom_minimum_size = Vector2(w, 0)

func _on_back():
	Global.play_sfx("click")
	Global.change_scene("res://Guild.tscn")

# ============================
#  第五幕 · 导览接力（个人信息介绍）
# ============================
func _maybe_show_info_tour() -> void:
	if TutorialManager.get_progress() < TutorialManager.PROGRESS_DONE:
		return
	var stage = SaveManager.get_value("tutorial", "fifth_act_stage", 0)
	if stage != 1:
		return
	SaveManager.set_value("tutorial", "fifth_act_stage", 2)
	SaveManager.save_to_disk()
	_show_info_tour_dialogue()
func _show_info_tour_dialogue() -> void:
	var popup = preload("res://TutorialDialoguePopup.gd").new()
	popup.setup([
		{"speaker": "老陈", "text": "这页是你的'名片'——称号、制卡数、最高品质、纹路收集，全记在这儿。公会认的就是这页纸。"},
		{"speaker": "你", "text": "（查看个人信息）原来这些数据都记着……"},
		{"speaker": "老陈", "text": "把活儿干漂亮，称号往上涨，别人看了也得敬你三分。看完了？走，带你认认这条街的门面。"},
	], func():
		Global.change_scene("res://StoreStreet.tscn")
	)
	add_child(popup)

func _on_gallery():
	Global.play_sfx("click")
	Global.change_scene("res://CircuitGallery.tscn")
