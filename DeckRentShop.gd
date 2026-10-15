extends Control
# ============================================================
#  牌组租借商店 —— 租借决斗场AI卡组
#  看广告 或 100金币 租借，卡组10点耐久，不并入图鉴/编辑牌库
# ============================================================
var _hj_ads: HJAdsNode = null
var _pending_rent_deck: Dictionary = {}  # 待租借的卡组（广告回调用）

func _ready():
	var back := get_node_or_null("BackBtn")
	if back is Button: back.pressed.connect(_on_back)
	_update_gold()
	# 广告初始化
	_hj_ads = HJAdsNode.new(); _hj_ads.name = "HJAdsNode"; add_child(_hj_ads)
	_hj_ads.app_id = "234475"; _hj_ads.rewarded_placement_id = "9701263723893953"
	_hj_ads.debug_mode = false
	_hj_ads.ad_loaded.connect(_on_ad_loaded)
	_hj_ads.video_rewarded.connect(_on_video_rewarded)
	_hj_ads.ad_closed.connect(_on_ad_closed)
	_hj_ads.ad_failed.connect(_on_ad_failed)
	_build_list()  # 先建列表，立即显示
	# 参考 Shop.gd：延迟一帧再初始化广告，避免阻塞 UI
	await get_tree().process_frame
	_hj_ads.loadRewardedAd()

func _on_back(): Global.play_sfx("click"); Global.change_scene("res://StoreStreet.tscn")

func _update_gold():
	var g = get_node_or_null("GoldLabel")
	if g is Label: g.text = "💰 " + str(SaveManager.get_value("player", "gold", 0))

func _set_status(t: String, c: Color):
	var s = get_node_or_null("StatusLabel")
	if s is Label: s.text = t; s.add_theme_color_override("font_color", c)

# ============================================================
#  卡组列表（决斗场AI卡组池 server_decks）
# ============================================================
var _filter_series: String = "all"  # 系列筛选: all/canglan/go/syjy/nbd
var _search_text: String = ""
var _search_input: LineEdit = null

func _rebuild_list():
	var old = get_node_or_null("RentScroll")
	if old:
		remove_child(old)
		old.queue_free()
	_build_list()

func _build_list():
	var scroll = ScrollContainer.new(); scroll.name = "RentScroll"
	scroll.anchor_left = 0.0; scroll.anchor_top = 0.0; scroll.anchor_right = 1.0; scroll.anchor_bottom = 1.0
	scroll.offset_top = Global.ph(0.085); scroll.offset_bottom = Global.ph(-0.06)
	# 参考 CardPackShop：禁止水平滚动，垂直滚动条始终显示
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# scroll_deadzone 用默认值 10，避免太灵敏导致滑动不顺畅
	add_child(scroll)
	var vbox = VBoxContainer.new(); vbox.name = "RentList"
	vbox.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	# 不设置 custom_minimum_size，让 VBox 自动适应 ScrollContainer 宽度（扣除滚动条）
	vbox.add_theme_constant_override("separation", Global.ph(0.012)); scroll.add_child(vbox)

	var hint = Label.new(); hint.text = "🃏 租借决斗场卡组 · 每次 +" + str(Global.RENTED_DECK_MAX_DURABILITY) + " 耐久（重复租借可叠加）· 仅用于对战"
	hint.add_theme_font_size_override("font_size", 40); hint.add_theme_color_override("font_color", Color("#d4b8e8"))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(0, Global.ph(0.06)); vbox.add_child(hint)
	# 搜索 + 筛选栏
	var filter_hbox = HBoxContainer.new()
	filter_hbox.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	filter_hbox.custom_minimum_size = Vector2(0, Global.ph(0.07))
	filter_hbox.add_theme_constant_override("separation", 12)
	vbox.add_child(filter_hbox)
	# 搜索输入框
	_search_input = LineEdit.new()
	_search_input.placeholder_text = "🔍 搜索卡组名..."
	_search_input.add_theme_font_size_override("font_size", 38)
	_search_input.custom_minimum_size = Vector2(0, Global.ph(0.06))
	_search_input.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	_search_input.text = _search_text
	_search_input.text_changed.connect(func(t): _search_text = t; _apply_filter())
	filter_hbox.add_child(_search_input)
	# 筛选按钮
	var filter_btn = Button.new()
	filter_btn.text = "🎯 筛选"
	filter_btn.add_theme_font_size_override("font_size", 38)
	var fbs = StyleBoxFlat.new()
	fbs.bg_color = Color(0.15, 0.13, 0.20)
	fbs.border_width_left = 2; fbs.border_width_right = 2; fbs.border_width_top = 2; fbs.border_width_bottom = 2
	fbs.border_color = Color("#e8a838")
	fbs.corner_radius_top_left = 10; fbs.corner_radius_top_right = 10
	fbs.corner_radius_bottom_left = 10; fbs.corner_radius_bottom_right = 10
	fbs.content_margin_left = 16; fbs.content_margin_right = 16
	filter_btn.add_theme_stylebox_override("normal", fbs)
	filter_btn.add_theme_stylebox_override("hover", fbs)
	filter_btn.add_theme_stylebox_override("pressed", fbs)
	filter_btn.add_theme_color_override("font_color", Color("#e8a838"))
	filter_btn.custom_minimum_size = Vector2(Global.pw(0.18), Global.ph(0.06))
	filter_btn.pressed.connect(_show_filter_popup)
	filter_hbox.add_child(filter_btn)
	var decks = Global.server_decks
	if decks.is_empty():
		var empty = Label.new(); empty.text = "暂无可租借卡组\n请等待加载"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty.add_theme_font_size_override("font_size", 45); empty.add_theme_color_override("font_color", Color("#5a5a6e"))
		empty.custom_minimum_size = Vector2(0, Global.ph(0.3)); vbox.add_child(empty); return
	# 应用筛选
	var filtered = _apply_filter_to_decks(decks)
	if filtered.is_empty():
		var no_result = Label.new(); no_result.text = "没有符合条件的卡组"
		no_result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; no_result.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		no_result.add_theme_font_size_override("font_size", 45); no_result.add_theme_color_override("font_color", Color("#5a5a6e"))
		no_result.custom_minimum_size = Vector2(0, Global.ph(0.3)); vbox.add_child(no_result); return
	for sdeck in filtered:
		var dd = sdeck.get("deck_data", {})
		if dd.is_empty(): continue
		var dname = dd.get("name", "未知卡组")
		var cc = dd.get("card_datas", []).size()
		# 查该卡组当前已租耐久（叠加后可见）
		var owned_dur := -1
		for rd in Global.get_all_rented_decks().values():
			if rd.get("source_deck", "") == dname:
				owned_dur = int(rd.get("durability", 0)); break
		_build_row(vbox, dd, dname, cc, owned_dur)

func _apply_filter_to_decks(decks: Array) -> Array:
	var result = []
	for sdeck in decks:
		var dd = sdeck.get("deck_data", {})
		if dd.is_empty(): continue
		var dname = dd.get("name", "")
		# 系列筛选
		if _filter_series != "all":
			var series = CardManager.get_back_id_for_deck_name(dname)
			if series != _filter_series: continue
		# 搜索筛选
		if _search_text != "":
			if not _search_text.to_lower() in dname.to_lower(): continue
		result.append(sdeck)
	return result

func _apply_filter():
	_rebuild_list()

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
	ps.bg_color = Color(0.08, 0.08, 0.12)
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
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)
	# 标题
	var title = Label.new()
	title.text = "筛选卡组"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 50)
	title.add_theme_color_override("font_color", Color("#e8a838"))
	vbox.add_child(title)
	# 当前搜索文本
	var search_lbl = Label.new()
	search_lbl.text = "搜索: " + (_search_text if _search_text != "" else "(无)")
	search_lbl.add_theme_font_size_override("font_size", 36)
	search_lbl.add_theme_color_override("font_color", Color("#a0a0b0"))
	vbox.add_child(search_lbl)
	# 系列筛选按钮
	var series_title = Label.new()
	series_title.text = "按系列筛选:"
	series_title.add_theme_font_size_override("font_size", 40)
	vbox.add_child(series_title)
	var series_grid = GridContainer.new()
	series_grid.columns = 2
	series_grid.add_theme_constant_override("h_separation", 12)
	series_grid.add_theme_constant_override("v_separation", 12)
	vbox.add_child(series_grid)
	var series_list = [
		{"id": "all", "name": "全部"},
		{"id": "canglan", "name": "沧澜古界"},
		{"id": "go", "name": "围棋"},
		{"id": "syjy", "name": "三约纪元"},
		{"id": "nbd", "name": "你不对劲"}
	]
	for s in series_list:
		var btn = Button.new()
		var is_sel = (_filter_series == s.id)
		btn.text = ("✓ " if is_sel else "") + s.name
		btn.add_theme_font_size_override("font_size", 38)
		var bs = StyleBoxFlat.new()
		bs.bg_color = Color(0.2, 0.17, 0.26) if not is_sel else Color(0.3, 0.25, 0.15)
		bs.border_width_left = 2; bs.border_width_right = 2
		bs.border_width_top = 2; bs.border_width_bottom = 2
		bs.border_color = Color("#c8a03c") if is_sel else Color("#555555")
		bs.corner_radius_top_left = 10; bs.corner_radius_top_right = 10
		bs.corner_radius_bottom_left = 10; bs.corner_radius_bottom_right = 10
		btn.add_theme_stylebox_override("normal", bs)
		btn.add_theme_stylebox_override("hover", bs)
		btn.add_theme_stylebox_override("pressed", bs)
		btn.add_theme_color_override("font_color", Color("#e8d5b7") if is_sel else Color("#a0a0b0"))
		btn.custom_minimum_size = Vector2(0, Global.ph(0.06))
		btn.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
		var sid = s.id
		btn.pressed.connect(func():
			_filter_series = sid
			_apply_filter()
			_close_filter_popup()
		)
		series_grid.add_child(btn)
	# 关闭按钮
	var close_btn = Button.new()
	close_btn.text = "关闭"
	close_btn.add_theme_font_size_override("font_size", 42)
	var cbs = StyleBoxFlat.new()
	cbs.bg_color = Color("#553333")
	cbs.border_width_left = 2; cbs.border_width_right = 2
	cbs.border_width_top = 2; cbs.border_width_bottom = 2
	cbs.border_color = Color("#aa5555")
	cbs.corner_radius_top_left = 10; cbs.corner_radius_top_right = 10
	cbs.corner_radius_bottom_left = 10; cbs.corner_radius_bottom_right = 10
	close_btn.add_theme_stylebox_override("normal", cbs)
	close_btn.add_theme_stylebox_override("hover", cbs)
	close_btn.add_theme_stylebox_override("pressed", cbs)
	close_btn.add_theme_color_override("font_color", Color("#ffaaaa"))
	close_btn.custom_minimum_size = Vector2(0, Global.ph(0.07))
	close_btn.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	close_btn.pressed.connect(_close_filter_popup)
	vbox.add_child(close_btn)

func _show_deck_detail(dd: Dictionary, dname: String):
	Global.play_sfx("click")
	var overlay = ColorRect.new()
	overlay.name = "DeckDetailOverlay"
	overlay.color = Color(0, 0, 0, 0.75)
	overlay.anchor_left = 0.0; overlay.anchor_top = 0.0
	overlay.anchor_right = 1.0; overlay.anchor_bottom = 1.0
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.gui_input.connect(func(ev):
		if not is_instance_valid(overlay): return
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			var panel = overlay.get_node_or_null("DeckDetailPanel")
			if panel and Rect2(panel.get_global_rect().position, panel.get_global_rect().size).has_point(Vector2(ev.position.x, ev.position.y)):
				return
			overlay.queue_free())
	add_child(overlay)
	var panel = Panel.new()
	panel.name = "DeckDetailPanel"
	var ps = StyleBoxFlat.new()
	ps.bg_color = Color(0.08, 0.08, 0.12)
	ps.border_width_left = 3; ps.border_width_right = 3
	ps.border_width_top = 3; ps.border_width_bottom = 3
	ps.border_color = Color("#e8a838")
	ps.corner_radius_top_left = 16; ps.corner_radius_top_right = 16
	ps.corner_radius_bottom_left = 16; ps.corner_radius_bottom_right = 16
	panel.add_theme_stylebox_override("panel", ps)
	panel.anchor_left = 0.0; panel.anchor_top = 0.0; panel.anchor_right = 1.0; panel.anchor_bottom = 0.0
	panel.offset_left = Global.pw(0.06); panel.offset_top = Global.ph(0.10)
	panel.offset_right = Global.pw(-0.06); panel.offset_bottom = Global.ph(0.90)
	overlay.add_child(panel)
	# 关闭按钮
	var close_btn = Button.new(); close_btn.text = "✕"
	close_btn.add_theme_font_size_override("font_size", 40)
	close_btn.add_theme_color_override("font_color", Color("#a0a0b0"))
	var cbs = StyleBoxFlat.new()
	cbs.bg_color = Color(0.2, 0.1, 0.3, 0.8)
	cbs.corner_radius_top_left = 50; cbs.corner_radius_top_right = 50
	cbs.corner_radius_bottom_left = 50; cbs.corner_radius_bottom_right = 50
	close_btn.add_theme_stylebox_override("normal", cbs)
	close_btn.add_theme_stylebox_override("hover", cbs)
	close_btn.add_theme_stylebox_override("pressed", cbs)
	close_btn.anchor_left = 1.0; close_btn.anchor_top = 0.0
	close_btn.anchor_right = 1.0; close_btn.anchor_bottom = 0.0
	close_btn.offset_left = Global.pw(-0.08); close_btn.offset_top = Global.ph(0.01)
	close_btn.offset_right = Global.pw(-0.01); close_btn.offset_bottom = Global.ph(0.06)
	close_btn.pressed.connect(func(): if is_instance_valid(overlay): overlay.queue_free())
	close_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(close_btn)
	# 标题
	var title = Label.new(); title.text = "🃏 " + dname
	title.add_theme_font_size_override("font_size", 50)
	title.add_theme_color_override("font_color", Color("#f9d371"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.anchor_left = 0.0; title.anchor_top = 0.0
	title.anchor_right = 1.0; title.anchor_bottom = 0.0
	title.offset_top = Global.ph(0.015); title.offset_bottom = Global.ph(0.07)
	panel.add_child(title)
	# 分割线
	var line = ColorRect.new()
	line.color = Color(0.91, 0.659, 0.22, 0.6)
	line.anchor_left = 0.0; line.anchor_top = 0.0
	line.anchor_right = 1.0; line.anchor_bottom = 0.0
	line.offset_left = Global.pw(0.05); line.offset_top = Global.ph(0.075)
	line.offset_right = Global.pw(-0.05); line.offset_bottom = Global.ph(0.076)
	panel.add_child(line)
	# 卡牌列表
	var cards = dd.get("card_datas", [])
	var scroll = ScrollContainer.new()
	scroll.anchor_left = 0.0; scroll.anchor_top = 0.0
	scroll.anchor_right = 1.0; scroll.anchor_bottom = 1.0
	scroll.offset_left = Global.pw(0.03); scroll.offset_top = Global.ph(0.09)
	scroll.offset_right = Global.pw(-0.03); scroll.offset_bottom = Global.ph(-0.02)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(vbox)
	for i in range(cards.size()):
		var card = cards[i]
		var cn = card.get("name", card.get("card_name", "未命名卡牌"))
		var cost = card.get("cost", card.get("energy", 0))
		var atk = card.get("atk", card.get("attack", 0))
		var hp = card.get("hp", card.get("health", 0))
		var row = Panel.new()
		row.name = "CardRow_" + str(i)
		var rs = StyleBoxFlat.new()
		rs.bg_color = Color(0.10, 0.08, 0.18) if i % 2 == 0 else Color(0.12, 0.10, 0.20)
		rs.border_width_left = 1; rs.border_width_right = 1
		rs.border_width_top = 1; rs.border_width_bottom = 1
		rs.border_color = Color(0.3, 0.15, 0.5, 0.2)
		rs.corner_radius_top_left = 8; rs.corner_radius_top_right = 8
		rs.corner_radius_bottom_left = 8; rs.corner_radius_bottom_right = 8
		row.add_theme_stylebox_override("panel", rs)
		row.custom_minimum_size = Vector2(0, Global.ph(0.06))
		row.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(row)
		var hbox = HBoxContainer.new()
		hbox.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
		hbox.size_flags_vertical = SIZE_EXPAND | SIZE_FILL
		row.add_child(hbox)
		var cl = Label.new()
		cl.text = "⚡" + str(cost)
		cl.add_theme_font_size_override("font_size", 32)
		cl.add_theme_color_override("font_color", Color("#f9d371"))
		cl.custom_minimum_size = Vector2(Global.pw(0.08), 0)
		cl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hbox.add_child(cl)
		var nvl = Label.new()
		nvl.text = cn
		nvl.add_theme_font_size_override("font_size", 36)
		nvl.add_theme_color_override("font_color", Color("#e8d5b7"))
		nvl.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
		nvl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hbox.add_child(nvl)
		var stl = Label.new()
		stl.text = "⚔" + str(atk) + " ❤" + str(hp)
		stl.add_theme_font_size_override("font_size", 32)
		stl.add_theme_color_override("font_color", Color("#a0a0b0"))
		stl.custom_minimum_size = Vector2(Global.pw(0.15), 0)
		stl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		stl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		hbox.add_child(stl)

func _build_row(vbox, dd: Dictionary, dname: String, cc: int, owned_dur: int = -1):
	var row = Panel.new()
	var ps = StyleBoxFlat.new(); ps.bg_color = Color(0.15, 0.13, 0.20, 0.9)
	ps.border_width_left = 2; ps.border_width_right = 2; ps.border_width_top = 2; ps.border_width_bottom = 2
	ps.border_color = Color("#E8A838")
	ps.corner_radius_top_left = 12; ps.corner_radius_top_right = 12
	ps.corner_radius_bottom_left = 12; ps.corner_radius_bottom_right = 12
	ps.content_margin_left = 16; ps.content_margin_right = 16; ps.content_margin_top = 10; ps.content_margin_bottom = 10
	row.add_theme_stylebox_override("panel", ps)
	row.custom_minimum_size = Vector2(0, Global.ph(0.14))  # 参考 CardPackShop 0.18，略紧凑
	row.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	row.mouse_filter = Control.MOUSE_FILTER_PASS  # 让事件穿透到 scroll，同时 Row 也能处理长按
	row.set_meta("deck_data", dd)
	row.set_meta("deck_name", dname)
	vbox.add_child(row)
	# 长按检测（参考 CardPackShop）
	var press_timer = Timer.new()
	press_timer.wait_time = 0.5
	press_timer.one_shot = true
	press_timer.timeout.connect(func(): _show_deck_detail(dd, dname))
	row.add_child(press_timer)
	row.gui_input.connect(func(ev):
		if ev is InputEventMouseButton:
			if ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				press_timer.start()
			elif not ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				if press_timer.time_left > 0:
					press_timer.stop()
	)
	# 内部垂直容器（参考 CardPackShop，避免 anchor 定位超出）
	var iv = VBoxContainer.new()
	iv.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	iv.size_flags_vertical = SIZE_EXPAND | SIZE_FILL
	row.add_child(iv)
	# 第一排：卡组名 + 张数/耐久
	var tr = HBoxContainer.new()
	tr.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	tr.custom_minimum_size = Vector2(0, Global.ph(0.055))
	iv.add_child(tr)
	var nl = Label.new(); nl.text = "🃏 " + dname
	nl.add_theme_font_size_override("font_size", 50); nl.add_theme_color_override("font_color", Color("#e8d5b7"))
	nl.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	tr.add_child(nl)
	var cl = Label.new()
	if owned_dur < 0:
		cl.text = str(cc) + " 张"
	else:
		cl.text = str(cc) + " 张 · 已租耐久 " + str(owned_dur)
	cl.add_theme_font_size_override("font_size", 35)
	if owned_dur >= 0:
		cl.add_theme_color_override("font_color", Color("#4CAF50"))
	else:
		cl.add_theme_color_override("font_color", Color("#8a8aa0"))
	cl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tr.add_child(cl)
	# 第二排：按钮
	var br = HBoxContainer.new()
	br.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	br.size_flags_vertical = SIZE_EXPAND | SIZE_FILL
	br.alignment = BoxContainer.ALIGNMENT_CENTER
	br.custom_minimum_size = Vector2(0, Global.ph(0.065))
	iv.add_child(br)
	# 金币按钮
	var gb = Button.new(); gb.text = "💰 " + str(Global.RENT_COST_GOLD)
	gb.add_theme_font_size_override("font_size", 42); gb.add_theme_color_override("font_color", Color("#f9d371"))
	var gbs = StyleBoxFlat.new(); gbs.bg_color = Color(0.2, 0.16, 0.08, 0.9)
	gbs.corner_radius_top_left = 10; gbs.corner_radius_top_right = 10; gbs.corner_radius_bottom_left = 10; gbs.corner_radius_bottom_right = 10
	gbs.border_width_left = 2; gbs.border_width_right = 2; gbs.border_width_top = 2; gbs.border_width_bottom = 2; gbs.border_color = Color("#E8A838")
	gb.add_theme_stylebox_override("normal", gbs); gb.add_theme_stylebox_override("hover", gbs); gb.add_theme_stylebox_override("pressed", gbs)
	gb.custom_minimum_size = Vector2(Global.pw(0.22), Global.ph(0.055))
	gb.pressed.connect(func(): _rent_with_gold(dd))
	br.add_child(gb)
	# 间隔
	var sp = Control.new(); sp.custom_minimum_size = Vector2(Global.pw(0.04), 0); br.add_child(sp)
	# 广告按钮
	var ab = Button.new(); ab.text = "🎬 广告"
	ab.add_theme_font_size_override("font_size", 42); ab.add_theme_color_override("font_color", Color("#6c9bcf"))
	var abs_ = StyleBoxFlat.new(); abs_.bg_color = Color(0.1, 0.16, 0.24, 0.9)
	abs_.corner_radius_top_left = 10; abs_.corner_radius_top_right = 10; abs_.corner_radius_bottom_left = 10; abs_.corner_radius_bottom_right = 10
	abs_.border_width_left = 2; abs_.border_width_right = 2; abs_.border_width_top = 2; abs_.border_width_bottom = 2; abs_.border_color = Color("#6c9bcf")
	ab.add_theme_stylebox_override("normal", abs_); ab.add_theme_stylebox_override("hover", abs_); ab.add_theme_stylebox_override("pressed", abs_)
	ab.custom_minimum_size = Vector2(Global.pw(0.22), Global.ph(0.055))
	ab.pressed.connect(func(): _rent_with_ad(dd))
	br.add_child(ab)

# ============================================================
#  租借逻辑
# ============================================================
func _rent_with_gold(dd: Dictionary):
	Global.play_sfx("click")
	var gold = SaveManager.get_value("player", "gold", 0)
	if gold < Global.RENT_COST_GOLD:
		_set_status("⚠️ 金币不足！需要 " + str(Global.RENT_COST_GOLD) + " 金币", Color("#FF5252")); return
	gold -= Global.RENT_COST_GOLD
	SaveManager.set_value("player", "gold", gold); SaveManager.save_to_disk()
	_update_gold()
	_do_rent(dd)

func _rent_with_ad(dd: Dictionary):
	Global.play_sfx("click")
	if _hj_ads == null: _set_status("⚠️ 广告未初始化", Color("#FF5252")); return
	if _hj_ads.isRewardedAdReady():
		_pending_rent_deck = dd; _set_status("▶️ 播放广告中...", Color("#FFD700")); _hj_ads.showRewardedAd()
	else:
		_set_status("⏳ 广告加载中，请稍候", Color("#FFD700")); _hj_ads.loadRewardedAd()

func _do_rent(dd: Dictionary):
	var r = Global.rent_deck(dd)
	var dname = dd.get("name", "")
	if not r.get("ok", false):
		_set_status("⚠️ " + str(r.get("reason", "租借失败")), Color("#FF5252")); return
	if r.get("reason", "") == "已叠加":
		_set_status("✅ 「" + dname + "」耐久 +" + str(Global.RENTED_DECK_MAX_DURABILITY) + " → 共 " + str(r.get("durability", 0)) + " 点", Color("#4CAF50"))
	else:
		_set_status("✅ 已租借「" + dname + "」耐久 " + str(r.get("durability", 0)) + " 点", Color("#4CAF50"))
	# 刷新列表（已租耐久立即可见）
	_rebuild_list()

# ============================================================
#  广告回调
# ============================================================
func _on_ad_loaded(_pid: String): _set_status("✅ 广告已就绪", Color("#4CAF50"))
func _on_video_rewarded(rewarded: bool):
	if not rewarded:
		_set_status("⏳ 广告未完整播放", Color("#FF5252")); return
	if _pending_rent_deck.is_empty(): return
	_do_rent(_pending_rent_deck); _pending_rent_deck = {}
func _on_ad_closed(_r: String):
	await get_tree().create_timer(1.0).timeout
	if _hj_ads: _hj_ads.loadRewardedAd()
func _on_ad_failed(_e = null): _set_status("⚠️ 广告加载失败", Color("#FF5252"))