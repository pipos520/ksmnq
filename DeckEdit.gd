extends Control

# 长按相关
var _press_timer: float = 0.0
var _pressed_row = null
var _press_start_pos: Vector2 = Vector2.ZERO
var _press_index: int = -1
var _pressed_card_data = null
const LONG_PRESS_TIME := 0.5
const DRAG_THRESHOLD := 30.0

# 视图状态
var _current_view: String = "list"
var _current_deck_id: String = ""
var _current_deck_name: String = ""

# 节点引用（在 _ready() 中赋值）
var _scroll: ScrollContainer
var _list_vbox: VBoxContainer
var _edit_root: Control
var _edit_scroll: ScrollContainer
var _edit_title_label: Label
var _edit_deck_vbox: VBoxContainer
var _edit_avail_vbox: VBoxContainer
var _back_btn: Button
var _create_btn: Button
# 预构建的 10 个卡组行模板
var _prebuilt_rows: Array = []
var _prebuilt_row_count = 10
# 缓存纹理，避免每次切换主题都 load() 磁盘
var _tex_night: Texture2D
var _tex_day: Texture2D
var _is_initial_theme: bool = false
var _last_applied_mode = null  # 上次应用样式的主题（避免重复创建 StyleBoxFlat）

# 筛选/排序/搜索状态
var _filter_quality: String = "all"  # all/perfect/excellent/fine/normal
var _sort_field: String = "cost"  # cost/quality
var _sort_asc: bool = true
var _search_text: String = ""
var _search_input: LineEdit = null

func _ready():
	var _t0 = Time.get_ticks_msec()
	# ---- 静态界面：所有 UI 节点已在 DeckEdit.tscn 中声明 ----
	_scroll = get_node_or_null("DeckScroll")
	_list_vbox = get_node_or_null("DeckScroll/DeckList")
	_edit_root = get_node_or_null("EditRoot")
	_edit_scroll = get_node_or_null("EditRoot/EditScroll")
	_edit_title_label = get_node_or_null("EditRoot/EditTitle")
	_edit_deck_vbox = get_node_or_null("EditRoot/EditScroll/EditVBox/EditDeckCards")
	_edit_avail_vbox = get_node_or_null("EditRoot/EditScroll/EditVBox/EditAvailCards")
	_back_btn = get_node_or_null("BackBtn")
	_create_btn = get_node_or_null("CreateDeckBtn")
	print("[DeckEdit] _ready 节点引用: %dms" % [Time.get_ticks_msec() - _t0])

	# 动态尺寸（tscn 中无法用 Global.pw()，在此设置）
	if _list_vbox:
		_list_vbox.custom_minimum_size = Vector2(Global.pw(1.0), 0)
	var edit_vbox = get_node_or_null("EditRoot/EditScroll/EditVBox")
	if edit_vbox:
		edit_vbox.custom_minimum_size = Vector2(Global.pw(1.0), 0)

	# 信号连接
	if _back_btn:
		_back_btn.pressed.connect(_on_back)
	var gallery_btn = get_node_or_null("GalleryBtn")
	if gallery_btn:
		gallery_btn.pressed.connect(_on_gallery)
	var help_btn = get_node_or_null("HelpBtn")
	if help_btn:
		help_btn.pressed.connect(_on_help)
	if _create_btn:
		_create_btn.pressed.connect(_on_create_deck)
	print("[DeckEdit] _ready 完成: %dms" % [Time.get_ticks_msec() - _t0])

	# 刷新牌组列表（数据渲染，快）
	_refresh_deck_list()
	_setup_long_press()
	Global.theme_changed.connect(_on_theme_changed)
	# 主题样式延迟到下一帧，避免首帧卡顿
	_is_initial_theme = true
	call_deferred("_apply_theme_styles")

## 卡组行统一面板样式。
## 预构建行池（DeckRow_0..9）只有被真实牌组占用的行才会拿到这个 stylebox，
## 租借区块复用剩下的行时必须套同一份，否则那几行没有 content_margin：
## 内容会贴到 x=0、「操作」按钮直接顶到屏幕右边缘被裁。
func _make_row_style() -> StyleBoxFlat:
	var row_sb = StyleBoxFlat.new()
	row_sb.bg_color = Color(0.15, 0.13, 0.20, 0.9) if not Global.current_mode == Global.ThemeMode.DAY else Color(0.90, 0.85, 0.75, 0.9)
	row_sb.border_width_left = 2; row_sb.border_width_right = 2
	row_sb.border_width_top = 2; row_sb.border_width_bottom = 2
	row_sb.border_color = Color("#E8A838") if not Global.current_mode == Global.ThemeMode.DAY else Color("#946F38")
	row_sb.corner_radius_top_left = 12; row_sb.corner_radius_top_right = 12
	row_sb.corner_radius_bottom_left = 12; row_sb.corner_radius_bottom_right = 12
	row_sb.content_margin_left = 16; row_sb.content_margin_right = 16
	row_sb.content_margin_top = 8; row_sb.content_margin_bottom = 8
	return row_sb

# ============================================================
# 牌组列表刷新
# ============================================================

func _refresh_deck_list():
	var _t0 = Time.get_ticks_msec()
	# 行高：tscn 里写死 280，但行内只有「名称+卡片数」两行文字（实测内容高约 138），
	# 不收紧的话每张卡下面挂着一大片空白，一屏只能看到 2 个卡组。
	var row_min_h: float = Global.ph(0.078)
	# 先隐藏所有预构建行
	for i in range(_prebuilt_row_count):
		var row = _list_vbox.get_node_or_null("DeckRow_%d" % i)
		if row: row.visible = false
	# 隐藏所有分割线
	for n in _list_vbox.get_children():
		if n is ColorRect:
			n.visible = false

	var decks = CardManager.get_all_decks()
	if decks.size() == 0 or decks.keys().size() == 0:
		# 显示空状态
		var empty = _list_vbox.get_node_or_null("EmptyHint")
		if not empty:
			empty = Label.new()
			empty.name = "EmptyHint"
			empty.add_theme_font_size_override("font_size", 45)
			empty.add_theme_color_override("font_color", Color("#999999"))
			_list_vbox.add_child(empty)
		empty.text = "暂无牌组\n快去刻划卡片吧！"
		empty.horizontal_alignment = 1; empty.vertical_alignment = 1
		empty.custom_minimum_size = Vector2(0, Global.ph(0.4))
		empty.visible = true
		print("[DeckEdit] _refresh_deck_list: %dms (empty)" % [Time.get_ticks_msec() - _t0])
		return
	else:
		var empty = _list_vbox.get_node_or_null("EmptyHint")
		if empty: empty.visible = false

	# 构建查找表
	var all_cards = CardManager.get_all_cards()
	var card_lookup := {}
	for c in all_cards: card_lookup[c.get("id", "")] = c

	var idx = 0
	for deck_id in decks:
		var deck = decks[deck_id]
		var deck_name = deck.get("name", "未命名牌组")
		var card_ids = deck.get("cards", [])
		var actual_count = 0
		for cid in card_ids:
			if card_lookup.has(cid): actual_count += 1
		var card_count = actual_count

		var row = _list_vbox.get_node_or_null("DeckRow_%d" % idx)
		if not row: break
		row.visible = true
		row.name = "DeckRow_%d" % idx  # 保持原名
		row.set_meta("deck_id", deck_id)
		row.set_meta("deck_name", deck_name)

		# 面板样式
		row.add_theme_stylebox_override("panel", _make_row_style())
		row.custom_minimum_size = Vector2(0, row_min_h)

		# 填充数据
		var name_label = row.get_node_or_null("hbox_%d/info_%d/name_%d" % [idx, idx, idx])
		if name_label is Label: name_label.text = deck_name

		var count_label = row.get_node_or_null("hbox_%d/info_%d/count_%d" % [idx, idx, idx])
		if count_label is Label: count_label.text = "卡片数: " + str(card_count) + "/30"

		# 操作按钮 - 重新连接信号
		var action_btn = row.get_node_or_null("hbox_%d/action_%d" % [idx, idx])
		if action_btn is Button:
			# 断开旧连接
			for c in action_btn.pressed.get_connections():
				action_btn.pressed.disconnect(c["callable"])
			var d_id = deck_id; var d_name = deck_name
			action_btn.pressed.connect(func(): _show_deck_actions(d_id, d_name))

		idx += 1
	# 显示分割线
	for i in range(idx):
		# 每行后面加分割线，复用预构建的 ColorRect（按顺序找）
		var found = 0
		for n in _list_vbox.get_children():
			if n is ColorRect:
				if found == i:
					n.visible = true
					break
				found += 1

	# ===== 追加已租卡组（只读，不可修改/删除）=====
	if idx < _prebuilt_row_count:
		var rented = Global.get_all_rented_decks()
		if not rented.is_empty():
			# 租卡组区块标题（复用第一个未使用的行做纯文本）
			var head_row = _list_vbox.get_node_or_null("DeckRow_%d" % idx)
			if head_row:
				head_row.visible = true
				# 这一行只是分组标题，不该长成一张 280px 高的卡牌（会在标题下留一大片空白）。
				# 压成紧凑标题条 + 去掉卡面样式，视觉上才像「区块分隔」而不是空卡。
				head_row.custom_minimum_size = Vector2(0, Global.ph(0.06))
				# 透明背景 + 与普通行一致的水平内边距，否则标题会贴着屏幕左边缘
				var head_sb := StyleBoxEmpty.new()
				head_sb.content_margin_left = 16; head_sb.content_margin_right = 16
				head_sb.content_margin_top = 8; head_sb.content_margin_bottom = 8
				head_row.add_theme_stylebox_override("panel", head_sb)
				# 用名称区显示标题，其余置空
				var hl = head_row.get_node_or_null("hbox_%d/info_%d/name_%d" % [idx, idx, idx])
				if hl is Label:
					hl.text = "🃏 已租卡组（只读）"
					hl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
					hl.add_theme_color_override("font_color", Color("#a8d8ea"))
				var cl = head_row.get_node_or_null("hbox_%d/info_%d/count_%d" % [idx, idx, idx])
				if cl is Label: cl.text = " "
				var ab = head_row.get_node_or_null("hbox_%d/action_%d" % [idx, idx])
				if ab is Button:
					for c in ab.pressed.get_connections(): ab.pressed.disconnect(c["callable"])
					ab.visible = false
				idx += 1
			for rid in rented:
				if idx >= _prebuilt_row_count: break
				var rd = rented[rid]
				var rrow = _list_vbox.get_node_or_null("DeckRow_%d" % idx)
				if not rrow: break
				rrow.visible = true
				rrow.add_theme_stylebox_override("panel", _make_row_style())
				rrow.custom_minimum_size = Vector2(0, row_min_h)
				rrow.set_meta("deck_id", rid)
				rrow.set_meta("is_rented", true)
				var dur = int(rd.get("durability", 0))
				var rname = rd.get("name", "租借卡组")
				var rcount = rd.get("cards", []).size()
				var rl = rrow.get_node_or_null("hbox_%d/info_%d/name_%d" % [idx, idx, idx])
				if rl is Label: rl.text = "🃏 " + rname + "（租）"
				var rcl = rrow.get_node_or_null("hbox_%d/info_%d/count_%d" % [idx, idx, idx])
				if rcl is Label: rcl.text = str(rcount) + "/30 · 耐久 " + str(dur) + " 点"
				var rab = rrow.get_node_or_null("hbox_%d/action_%d" % [idx, idx])
				if rab is Button:
					for c in rab.pressed.get_connections(): rab.pressed.disconnect(c["callable"])
					var r_id = rid; var r_n = rname
					rab.pressed.connect(func(): _show_rented_notice(r_id, r_n, dur))
				idx += 1
	# 显示分割线（含租卡组行）
	for i in range(idx):
		var found = 0
		for n in _list_vbox.get_children():
			if n is ColorRect:
				if found == i:
					n.visible = true
					break
				found += 1
	print("[DeckEdit] _refresh_deck_list: %dms (decks=%d)" % [Time.get_ticks_msec() - _t0, idx])

## 已租卡组点击提示：只读，不可修改
func _show_rented_notice(rid: String, rname: String, durability: int):
	Global.play_sfx("click")
	var existing = get_node_or_null("RentedNotice")
	if existing: existing.queue_free()
	var overlay = ColorRect.new(); overlay.name = "RentedNotice"
	overlay.color = Color(0, 0, 0, 0.65)
	overlay.anchor_left = 0.0; overlay.anchor_top = 0.0; overlay.anchor_right = 1.0; overlay.anchor_bottom = 1.0
	overlay.mouse_filter = MOUSE_FILTER_STOP
	add_child(overlay)
	var panel = Panel.new()
	panel.anchor_left = 0.0; panel.anchor_top = 0.0; panel.anchor_right = 1.0; panel.anchor_bottom = 1.0
	panel.offset_left = Global.pw(0.1); panel.offset_right = Global.pw(-0.1)
	panel.offset_top = Global.ph(0.28); panel.offset_bottom = Global.ph(-0.28)
	var ps = StyleBoxFlat.new()
	ps.bg_color = Global.current.bg
	ps.border_width_left = 3; ps.border_width_right = 3; ps.border_width_top = 3; ps.border_width_bottom = 3
	ps.border_color = Color("#6c9bcf")
	ps.corner_radius_top_left = 16; ps.corner_radius_top_right = 16; ps.corner_radius_bottom_left = 16; ps.corner_radius_bottom_right = 16
	panel.add_theme_stylebox_override("panel", ps)
	overlay.add_child(panel)
	var title = Label.new(); title.text = "🃏 " + rname + "（租）"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 50); title.add_theme_color_override("font_color", Color("#f9d371"))
	title.anchor_left = 0.0; title.anchor_top = 0.0; title.anchor_right = 1.0; title.anchor_bottom = 0.0
	title.offset_top = Global.ph(0.04); title.offset_bottom = Global.ph(0.10)
	panel.add_child(title)
	var info = Label.new()
	info.text = "当前耐久：" + str(durability) + " 点\n\n⚠️ 租借卡组仅供对战使用\n无法在此修改或编辑\n耐久用尽后自动归还"
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	info.add_theme_font_size_override("font_size", 40); info.add_theme_color_override("font_color", Color("#a8d8ea"))
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.anchor_left = 0.0; info.anchor_top = 0.0; info.anchor_right = 1.0; info.anchor_bottom = 1.0
	info.offset_top = Global.ph(0.12); info.offset_bottom = Global.ph(-0.10)
	panel.add_child(info)
	var btn = Button.new(); btn.text = "知道了"; btn.add_theme_font_size_override("font_size", 42)
	btn.anchor_left = 0.25; btn.anchor_top = 1.0; btn.anchor_right = 0.75; btn.anchor_bottom = 1.0
	btn.offset_top = Global.ph(-0.10); btn.offset_bottom = Global.ph(-0.03)
	btn.pressed.connect(func(): if is_instance_valid(overlay): overlay.queue_free())
	panel.add_child(btn)

# ============================================================
# 操作弹窗（重命名 / 编辑 / 删除）
# ============================================================

func _show_deck_actions(deck_id: String, deck_name: String):
	Global.play_sfx("click")
	var overlay = ColorRect.new()
	overlay.name = "ActionOverlay"
	overlay.color = Color(0, 0, 0, 0.6)
	overlay.anchor_left = 0.0; overlay.anchor_top = 0.0; overlay.anchor_right = 1.0; overlay.anchor_bottom = 1.0
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	var panel = Panel.new()
	panel.name = "ActionPanel"
	panel.anchor_left = 0.0; panel.anchor_top = 0.0; panel.anchor_right = 1.0; panel.anchor_bottom = 1.0
	panel.offset_left = Global.pw(0.1); panel.offset_right = Global.pw(-0.1)
	panel.offset_top = Global.ph(0.3); panel.offset_bottom = Global.ph(-0.3)
	var ps = StyleBoxFlat.new()
	ps.bg_color = Global.current.bg
	ps.border_width_left = 3; ps.border_width_right = 3; ps.border_width_top = 3; ps.border_width_bottom = 3
	ps.border_color = Color("#e8a838")
	ps.corner_radius_top_left = 16; ps.corner_radius_top_right = 16
	ps.corner_radius_bottom_left = 16; ps.corner_radius_bottom_right = 16
	panel.add_theme_stylebox_override("panel", ps)
	add_child(panel)

	var panel_vbox = VBoxContainer.new()
	panel_vbox.name = "ActionVBox"
	panel_vbox.anchor_left = 0.0; panel_vbox.anchor_top = 0.0; panel_vbox.anchor_right = 1.0; panel_vbox.anchor_bottom = 1.0
	panel_vbox.offset_left = Global.pw(0.04); panel_vbox.offset_right = Global.pw(-0.04)
	panel_vbox.offset_top = Global.ph(0.02); panel_vbox.offset_bottom = Global.ph(-0.02)
	panel.add_child(panel_vbox)

	var title_label = Label.new()
	title_label.text = deck_name
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 55)
	title_label.add_theme_color_override("font_color", Global.current.title)
	panel_vbox.add_child(title_label)

	var spacer = ColorRect.new()
	spacer.color = Color.TRANSPARENT
	spacer.custom_minimum_size = Vector2(0, Global.ph(0.03))
	panel_vbox.add_child(spacer)

	var make_btn = func(text: String, color: Color):
		var btn = Button.new()
		btn.text = text
		btn.add_theme_font_size_override("font_size", 45)
		var bbs = StyleBoxFlat.new()
		bbs.bg_color = Color("#333333")
		bbs.border_width_left = 2; bbs.border_width_right = 2; bbs.border_width_top = 2; bbs.border_width_bottom = 2
		bbs.border_color = color
		bbs.corner_radius_top_left = 16; bbs.corner_radius_top_right = 16
		bbs.corner_radius_bottom_left = 16; bbs.corner_radius_bottom_right = 16
		bbs.content_margin_left = 0; bbs.content_margin_right = 0
		var bbsh = bbs.duplicate(); bbsh.bg_color = Global.current.btn_bg_hover
		btn.add_theme_stylebox_override("normal", bbs)
		btn.add_theme_stylebox_override("hover", bbsh)
		btn.add_theme_stylebox_override("pressed", bbs)
		btn.add_theme_color_override("font_color", color)
		btn.add_theme_color_override("font_hover_color", Color.WHITE)
		btn.custom_minimum_size = Vector2(0, Global.ph(0.08))
		btn.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
		return btn

	var rename_btn = make_btn.call("✏️ 重命名", Color("#3498db"))
	var d_id = deck_id
	rename_btn.pressed.connect(func():
		Global.play_sfx("click")
		_close_action_popup()
		_show_rename_dialog(d_id)
	)
	panel_vbox.add_child(rename_btn)

	var edit_btn = make_btn.call("✂️ 编辑牌组", Color("#2ecc71"))
	edit_btn.pressed.connect(func():
		Global.play_sfx("click")
		_close_action_popup()
		_enter_edit_mode(d_id)
	)
	panel_vbox.add_child(edit_btn)

	var back_btn = make_btn.call("🎴 卡背选择", Color("#9b59b6"))
	back_btn.pressed.connect(func():
		Global.play_sfx("click")
		_close_action_popup()
		_show_back_select(d_id, deck_name)
	)
	panel_vbox.add_child(back_btn)

	var cloth_btn = make_btn.call("🟦 桌布选择", Color("#16a085"))
	cloth_btn.pressed.connect(func():
		Global.play_sfx("click")
		_close_action_popup()
		_show_tablecloth_select(d_id, deck_name)
	)
	panel_vbox.add_child(cloth_btn)

	var delete_btn = make_btn.call("❌ 删除牌组", Color("#e74c3c"))
	delete_btn.pressed.connect(func():
		Global.play_sfx("click")
		_close_action_popup()
		_confirm_delete_deck(d_id)
	)
	panel_vbox.add_child(delete_btn)

# ============================================================
# 关闭弹窗
# ============================================================

func _close_action_popup():
	for c in get_children():
		if c.name == "ActionOverlay" or c.name == "ActionPanel" or c.name == "ActionVBox":
			remove_child(c)
			c.queue_free()

# ============================================================
# 卡背选择弹窗
# ============================================================

func _show_back_select(deck_id: String, deck_name: String):
	# 关闭弹窗
	for c in get_children():
		if c.name in ["BackOverlay", "BackPanel", "BackVBox"]:
			remove_child(c); c.queue_free()
	# 构建
	var overlay = ColorRect.new()
	overlay.name = "BackOverlay"
	overlay.color = Color(0, 0, 0, 0.65)
	overlay.anchor_left = 0.0; overlay.anchor_top = 0.0
	overlay.anchor_right = 1.0; overlay.anchor_bottom = 1.0
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	var panel = Panel.new()
	panel.name = "BackPanel"
	panel.anchor_left = 0.0; panel.anchor_top = 0.0
	panel.anchor_right = 1.0; panel.anchor_bottom = 1.0
	panel.offset_left = Global.pw(0.06); panel.offset_right = Global.pw(-0.06)
	panel.offset_top = Global.ph(0.10); panel.offset_bottom = Global.ph(-0.10)
	var ps = StyleBoxFlat.new()
	ps.bg_color = Global.current.bg
	ps.border_width_left = 3; ps.border_width_right = 3
	ps.border_width_top = 3; ps.border_width_bottom = 3
	ps.border_color = Color("#9b59b6")
	ps.corner_radius_top_left = 16; ps.corner_radius_top_right = 16
	ps.corner_radius_bottom_left = 16; ps.corner_radius_bottom_right = 16
	panel.add_theme_stylebox_override("panel", ps)
	add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.name = "BackVBox"
	vbox.anchor_left = 0.0; vbox.anchor_top = 0.0
	vbox.anchor_right = 1.0; vbox.anchor_bottom = 1.0
	vbox.offset_left = Global.pw(0.04); vbox.offset_right = Global.pw(-0.04)
	vbox.offset_top = Global.ph(0.02); vbox.offset_bottom = Global.ph(-0.02)
	panel.add_child(vbox)

	# 标题
	var title = Label.new()
	title.text = "选择卡背 · " + deck_name
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 45)
	title.add_theme_color_override("font_color", Global.current.title)
	vbox.add_child(title)

	var sp = ColorRect.new()
	sp.color = Color.TRANSPARENT
	sp.custom_minimum_size = Vector2(0, Global.ph(0.03))
	vbox.add_child(sp)

	# 可滚动区域
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	# 5 款卡背 列表布局（横向：图片+文字）
	var list = VBoxContainer.new()
	list.add_theme_constant_override("separation", 12)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.mouse_filter = Control.MOUSE_FILTER_PASS  # 允许滑动事件传递到ScrollContainer
	scroll.add_child(list)

	var current_back = CardManager.get_deck_back(deck_id)
	for bid in CardManager.DECK_BACKS:
		var info = CardManager.DECK_BACKS[bid]
		var cell = Panel.new()
		cell.mouse_filter = Control.MOUSE_FILTER_PASS  # 允许滑动穿透到ScrollContainer
		var b_is_sel = (bid == current_back)
		var is_unlocked = CardManager.is_back_unlocked(bid)
		var unlock_hint = CardManager.get_unlock_hint(bid, true)
		
		var cs = StyleBoxFlat.new()
		# 未解锁：灰色背景
		if is_unlocked:
			cs.bg_color = Color(0.20, 0.17, 0.26)
		else:
			cs.bg_color = Color(0.12, 0.12, 0.14)
		cs.border_width_left = 3; cs.border_width_right = 3
		cs.border_width_top = 3; cs.border_width_bottom = 3
		# 未解锁：灰色边框
		if is_unlocked:
			cs.border_color = Color("#c8a03c") if b_is_sel else Color("#555555")
		else:
			cs.border_color = Color("#333333")
		cs.corner_radius_top_left = 12; cs.corner_radius_top_right = 12
		cs.corner_radius_bottom_left = 12; cs.corner_radius_bottom_right = 12
		cs.content_margin_left = 12; cs.content_margin_right = 12
		cs.content_margin_top = 12; cs.content_margin_bottom = 12
		cell.add_theme_stylebox_override("panel", cs)
		cell.custom_minimum_size = Vector2(0, Global.ph(0.18))
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		# 横向布局：图片在左，文字在右
		var hbox = HBoxContainer.new()
		hbox.anchor_left = 0.0; hbox.anchor_top = 0.0
		hbox.anchor_right = 1.0; hbox.anchor_bottom = 1.0
		hbox.offset_left = 8; hbox.offset_top = 8
		hbox.offset_right = -8; hbox.offset_bottom = -8
		hbox.add_theme_constant_override("separation", 20)
		cell.add_child(hbox)

		# 缩略图（统一显示尺寸，保持原始比例）
		var tex_rect = TextureRect.new()
		tex_rect.texture = load(info["path"])
		tex_rect.custom_minimum_size = Vector2(Global.pw(0.15), Global.ph(0.14))
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		# 未解锁：灰色modulate
		if not is_unlocked:
			tex_rect.modulate = Color(0.4, 0.4, 0.4, 0.8)
		hbox.add_child(tex_rect)

		# 右侧文字区域
		var text_vbox = VBoxContainer.new()
		text_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		hbox.add_child(text_vbox)

		# 名称（大字）
		var lbl = Label.new()
		if is_unlocked:
			lbl.text = info["name"] + (" ✓" if b_is_sel else "")
			lbl.add_theme_color_override("font_color", Color("#c8a03c") if b_is_sel else Color("#dddddd"))
		else:
			lbl.text = info["name"] + " 🔒"
			lbl.add_theme_color_override("font_color", Color("#666666"))
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		lbl.add_theme_font_size_override("font_size", 40)
		text_vbox.add_child(lbl)

		# 解锁条件提示（更大字体）
		if not is_unlocked and unlock_hint != "":
			var hint_lbl = Label.new()
			hint_lbl.text = unlock_hint
			hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			hint_lbl.add_theme_font_size_override("font_size", 32)
			hint_lbl.add_theme_color_override("font_color", Color("#888888"))
			text_vbox.add_child(hint_lbl)

		var b_id = bid
		cell.gui_input.connect(func(ev):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				Global.play_sfx("click")
				# 未解锁：不做任何操作（静默忽略）
				if not CardManager.is_back_unlocked(b_id):
					return
				if CardManager.set_deck_back(deck_id, b_id):
					_show_back_select(deck_id, deck_name)
				else:
					print("[DeckEdit] 设置卡背失败: ", b_id)
		)
		list.add_child(cell)

	# 关闭按钮
	var close_btn = Button.new()
	close_btn.text = "关闭"
	close_btn.add_theme_font_size_override("font_size", 40)
	close_btn.custom_minimum_size = Vector2(0, Global.ph(0.06))
	var cb = StyleBoxFlat.new()
	cb.bg_color = Color("#333333")
	cb.border_width_left = 2; cb.border_width_right = 2
	cb.border_width_top = 2; cb.border_width_bottom = 2
	cb.border_color = Color("#888888")
	cb.corner_radius_top_left = 12; cb.corner_radius_top_right = 12
	cb.corner_radius_bottom_left = 12; cb.corner_radius_bottom_right = 12
	close_btn.add_theme_stylebox_override("normal", cb)
	close_btn.add_theme_stylebox_override("pressed", cb)
	close_btn.add_theme_stylebox_override("hover", cb)
	close_btn.add_theme_color_override("font_color", Color("#dddddd"))
	close_btn.pressed.connect(func():
		Global.play_sfx("click")
		for c in get_children():
			if c.name in ["BackOverlay", "BackPanel", "BackVBox"]:
				remove_child(c); c.queue_free()
	)
	vbox.add_child(close_btn)


# ============================================================
# 桌布选择弹窗
# ============================================================

func _show_tablecloth_select(deck_id: String, deck_name: String):
	# 关闭弹窗
	for c in get_children():
		if c.name in ["ClothOverlay", "ClothPanel", "ClothVBox"]:
			remove_child(c); c.queue_free()
	# 构建
	var overlay = ColorRect.new()
	overlay.name = "ClothOverlay"
	overlay.color = Color(0, 0, 0, 0.65)
	overlay.anchor_left = 0.0; overlay.anchor_top = 0.0
	overlay.anchor_right = 1.0; overlay.anchor_bottom = 1.0
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	var panel = Panel.new()
	panel.name = "ClothPanel"
	panel.anchor_left = 0.0; panel.anchor_top = 0.0
	panel.anchor_right = 1.0; panel.anchor_bottom = 1.0
	panel.offset_left = Global.pw(0.06); panel.offset_right = Global.pw(-0.06)
	panel.offset_top = Global.ph(0.10); panel.offset_bottom = Global.ph(-0.10)
	var ps = StyleBoxFlat.new()
	ps.bg_color = Global.current.bg
	ps.border_width_left = 3; ps.border_width_right = 3
	ps.border_width_top = 3; ps.border_width_bottom = 3
	ps.border_color = Color("#16a085")
	ps.corner_radius_top_left = 16; ps.corner_radius_top_right = 16
	ps.corner_radius_bottom_left = 16; ps.corner_radius_bottom_right = 16
	panel.add_theme_stylebox_override("panel", ps)
	add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.name = "ClothVBox"
	vbox.anchor_left = 0.0; vbox.anchor_top = 0.0
	vbox.anchor_right = 1.0; vbox.anchor_bottom = 1.0
	vbox.offset_left = Global.pw(0.04); vbox.offset_right = Global.pw(-0.04)
	vbox.offset_top = Global.ph(0.02); vbox.offset_bottom = Global.ph(-0.02)
	panel.add_child(vbox)

	# 标题
	var title = Label.new()
	title.text = "选择桌布 · " + deck_name
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 45)
	title.add_theme_color_override("font_color", Global.current.title)
	vbox.add_child(title)

	var sp = ColorRect.new()
	sp.color = Color.TRANSPARENT
	sp.custom_minimum_size = Vector2(0, Global.ph(0.03))
	vbox.add_child(sp)

	# 可滚动区域
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	# 5 款桌布 列表布局（横向：图片+文字）
	var list = VBoxContainer.new()
	list.add_theme_constant_override("separation", 12)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.mouse_filter = Control.MOUSE_FILTER_PASS  # 允许滑动事件传递到ScrollContainer
	scroll.add_child(list)

	var current_cloth = CardManager.get_deck_tablecloth(deck_id)
	for cid in CardManager.DECK_TABLECLOTHS:
		var info = CardManager.DECK_TABLECLOTHS[cid]
		var cell = Panel.new()
		cell.mouse_filter = Control.MOUSE_FILTER_PASS  # 允许滑动穿透到ScrollContainer
		var b_is_sel = (cid == current_cloth)
		var is_unlocked = CardManager.is_tablecloth_unlocked(cid)
		var unlock_hint = CardManager.get_unlock_hint(cid, false)
		
		var cs = StyleBoxFlat.new()
		# 未解锁：灰色背景
		if is_unlocked:
			cs.bg_color = Color(0.20, 0.17, 0.26)
		else:
			cs.bg_color = Color(0.12, 0.12, 0.14)
		cs.border_width_left = 3; cs.border_width_right = 3
		cs.border_width_top = 3; cs.border_width_bottom = 3
		# 未解锁：灰色边框
		if is_unlocked:
			cs.border_color = Color("#c8a03c") if b_is_sel else Color("#555555")
		else:
			cs.border_color = Color("#333333")
		cs.corner_radius_top_left = 12; cs.corner_radius_top_right = 12
		cs.corner_radius_bottom_left = 12; cs.corner_radius_bottom_right = 12
		cs.content_margin_left = 12; cs.content_margin_right = 12
		cs.content_margin_top = 12; cs.content_margin_bottom = 12
		cell.add_theme_stylebox_override("panel", cs)
		# 横版列表项：高度固定，宽度撑满
		cell.custom_minimum_size = Vector2(0, Global.ph(0.16))
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		# 横向布局：图片在左，文字在右
		var hbox = HBoxContainer.new()
		hbox.anchor_left = 0.0; hbox.anchor_top = 0.0
		hbox.anchor_right = 1.0; hbox.anchor_bottom = 1.0
		hbox.offset_left = 8; hbox.offset_top = 8
		hbox.offset_right = -8; hbox.offset_bottom = -8
		hbox.add_theme_constant_override("separation", 20)
		cell.add_child(hbox)

		# 缩略图（横版 16:9，保持原始比例）
		var tex_rect = TextureRect.new()
		tex_rect.texture = load(info["path"])
		tex_rect.custom_minimum_size = Vector2(Global.pw(0.25), Global.ph(0.14))
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		# 未解锁：灰色modulate
		if not is_unlocked:
			tex_rect.modulate = Color(0.4, 0.4, 0.4, 0.8)
		hbox.add_child(tex_rect)

		# 右侧文字区域
		var text_vbox = VBoxContainer.new()
		text_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		hbox.add_child(text_vbox)

		# 名称（大字）
		var lbl = Label.new()
		if is_unlocked:
			lbl.text = info["name"] + (" ✓" if b_is_sel else "")
			lbl.add_theme_color_override("font_color", Color("#c8a03c") if b_is_sel else Color("#dddddd"))
		else:
			lbl.text = info["name"] + " 🔒"
			lbl.add_theme_color_override("font_color", Color("#666666"))
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		lbl.add_theme_font_size_override("font_size", 40)
		text_vbox.add_child(lbl)

		# 解锁条件提示（更大字体）
		if not is_unlocked and unlock_hint != "":
			var hint_lbl = Label.new()
			hint_lbl.text = unlock_hint
			hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			hint_lbl.add_theme_font_size_override("font_size", 32)
			hint_lbl.add_theme_color_override("font_color", Color("#888888"))
			text_vbox.add_child(hint_lbl)

		var c_id = cid
		cell.gui_input.connect(func(ev):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				Global.play_sfx("click")
				# 未解锁：不做任何操作（静默忽略）
				if not CardManager.is_tablecloth_unlocked(c_id):
					return
				if CardManager.set_deck_tablecloth(deck_id, c_id):
					_show_tablecloth_select(deck_id, deck_name)
				else:
					print("[DeckEdit] 设置桌布失败: ", c_id)
		)
		list.add_child(cell)

	# 关闭按钮
	var close_btn = Button.new()
	close_btn.text = "关闭"
	close_btn.add_theme_font_size_override("font_size", 40)
	close_btn.custom_minimum_size = Vector2(0, Global.ph(0.06))
	var cb = StyleBoxFlat.new()
	cb.bg_color = Color("#333333")
	cb.border_width_left = 2; cb.border_width_right = 2
	cb.border_width_top = 2; cb.border_width_bottom = 2
	cb.border_color = Color("#888888")
	cb.corner_radius_top_left = 12; cb.corner_radius_top_right = 12
	cb.corner_radius_bottom_left = 12; cb.corner_radius_bottom_right = 12
	close_btn.add_theme_stylebox_override("normal", cb)
	close_btn.add_theme_stylebox_override("pressed", cb)
	close_btn.add_theme_stylebox_override("hover", cb)
	close_btn.add_theme_color_override("font_color", Color("#dddddd"))
	close_btn.pressed.connect(func():
		Global.play_sfx("click")
		for c in get_children():
			if c.name in ["ClothOverlay", "ClothPanel", "ClothVBox"]:
				remove_child(c); c.queue_free()
	)
	vbox.add_child(close_btn)

func _show_rename_dialog(deck_id: String):
	var overlay = ColorRect.new()
	overlay.name = "RenameOverlay"
	overlay.color = Color(0, 0, 0, 0.6)
	overlay.anchor_left = 0.0; overlay.anchor_top = 0.0; overlay.anchor_right = 1.0; overlay.anchor_bottom = 1.0
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	var panel = Panel.new()
	panel.name = "RenamePanel"
	panel.anchor_left = 0.0; panel.anchor_top = 0.0; panel.anchor_right = 1.0; panel.anchor_bottom = 1.0
	panel.offset_left = Global.pw(0.1); panel.offset_right = Global.pw(-0.1)
	panel.offset_top = Global.ph(0.35); panel.offset_bottom = Global.ph(-0.35)
	var ps = StyleBoxFlat.new()
	ps.bg_color = Global.current.bg
	ps.border_width_left = 3; ps.border_width_right = 3; ps.border_width_top = 3; ps.border_width_bottom = 3
	ps.border_color = Color("#e8a838")
	ps.corner_radius_top_left = 16; ps.corner_radius_top_right = 16
	ps.corner_radius_bottom_left = 16; ps.corner_radius_bottom_right = 16
	panel.add_theme_stylebox_override("panel", ps)
	add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.name = "RenameVBox"
	vbox.anchor_left = 0.0; vbox.anchor_top = 0.0; vbox.anchor_right = 1.0; vbox.anchor_bottom = 1.0
	vbox.offset_left = Global.pw(0.04); vbox.offset_right = Global.pw(-0.04)
	vbox.offset_top = Global.ph(0.02); vbox.offset_bottom = Global.ph(-0.02)
	panel.add_child(vbox)

	var label = Label.new()
	label.text = "请输入新名称："
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 45)
	label.add_theme_color_override("font_color", Global.current.title)
	vbox.add_child(label)

	var input = LineEdit.new()
	input.name = "RenameInput"
	input.placeholder_text = "牌组名称"
	input.add_theme_font_size_override("font_size", 40)
	input.custom_minimum_size = Vector2(0, Global.ph(0.07))
	input.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	vbox.add_child(input)

	var spacer = ColorRect.new()
	spacer.color = Color.TRANSPARENT
	spacer.custom_minimum_size = Vector2(0, Global.ph(0.02))
	vbox.add_child(spacer)

	var hbox = HBoxContainer.new()
	hbox.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	hbox.custom_minimum_size = Vector2(0, Global.ph(0.08))

	var cancel_btn = Button.new()
	cancel_btn.text = "取消"
	cancel_btn.add_theme_font_size_override("font_size", 40)
	var cs = StyleBoxFlat.new()
	cs.bg_color = Global.current.btn_bg; cs.border_width_left = 2; cs.border_width_right = 2; cs.border_width_top = 2; cs.border_width_bottom = 2
	cs.border_color = Color("#888888"); cs.corner_radius_top_left = 10; cs.corner_radius_top_right = 10
	cs.corner_radius_bottom_left = 10; cs.corner_radius_bottom_right = 10; cs.content_margin_left = 0; cs.content_margin_right = 0
	var csh = cs.duplicate(); csh.bg_color = Global.current.btn_bg_hover
	cancel_btn.add_theme_stylebox_override("normal", cs); cancel_btn.add_theme_stylebox_override("hover", csh)
	cancel_btn.add_theme_stylebox_override("pressed", cs)
	cancel_btn.add_theme_color_override("font_color", Global.current.btn_text)
	cancel_btn.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	cancel_btn.pressed.connect(func(): Global.play_sfx("click"); _close_rename_popup())
	hbox.add_child(cancel_btn)

	var confirm_btn = Button.new()
	confirm_btn.text = "确认"
	confirm_btn.add_theme_font_size_override("font_size", 40)
	var cfs = StyleBoxFlat.new()
	cfs.bg_color = Global.current.btn_bg; cfs.border_width_left = 2; cfs.border_width_right = 2; cfs.border_width_top = 2; cfs.border_width_bottom = 2
	cfs.border_color = Color("#e8a838"); cfs.corner_radius_top_left = 10; cfs.corner_radius_top_right = 10
	cfs.corner_radius_bottom_left = 10; cfs.corner_radius_bottom_right = 10; cfs.content_margin_left = 0; cfs.content_margin_right = 0
	var cfsh = cfs.duplicate(); cfsh.bg_color = Global.current.btn_bg_hover
	confirm_btn.add_theme_stylebox_override("normal", cfs); confirm_btn.add_theme_stylebox_override("hover", cfsh)
	confirm_btn.add_theme_stylebox_override("pressed", cfs)
	confirm_btn.add_theme_color_override("font_color", Global.current.btn_text)
	confirm_btn.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	var d_id = deck_id
	confirm_btn.pressed.connect(func():
		Global.play_sfx("click")
		_do_rename(d_id, input)
	)
	hbox.add_child(confirm_btn)

	vbox.add_child(hbox)

func _close_rename_popup():
	for c in get_children():
		if c.name.begins_with("Rename"):
			remove_child(c)
			c.queue_free()

func _do_rename(deck_id: String, input_node: LineEdit):
	var new_name = input_node.text.strip_edges()
	if new_name == "":
		return
	var decks = CardManager.get_all_decks()
	if decks.has(deck_id):
		decks[deck_id]["name"] = new_name
		SaveManager.save_to_disk()
	_close_rename_popup()
	_refresh_deck_list()

# ============================================================
# 删除确认
# ============================================================

func _confirm_delete_deck(deck_id: String):
	var overlay = ColorRect.new()
	overlay.name = "DeleteOverlay"
	overlay.color = Color(0, 0, 0, 0.6)
	overlay.anchor_left = 0.0; overlay.anchor_top = 0.0; overlay.anchor_right = 1.0; overlay.anchor_bottom = 1.0
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	var panel = Panel.new()
	panel.name = "DeletePanel"
	panel.anchor_left = 0.0; panel.anchor_top = 0.0; panel.anchor_right = 1.0; panel.anchor_bottom = 1.0
	panel.offset_left = Global.pw(0.1); panel.offset_right = Global.pw(-0.1)
	panel.offset_top = Global.ph(0.35); panel.offset_bottom = Global.ph(-0.35)
	var ps = StyleBoxFlat.new()
	ps.bg_color = Global.current.bg
	ps.border_width_left = 3; ps.border_width_right = 3; ps.border_width_top = 3; ps.border_width_bottom = 3
	ps.border_color = Color("#e8a838")
	ps.corner_radius_top_left = 16; ps.corner_radius_top_right = 16
	ps.corner_radius_bottom_left = 16; ps.corner_radius_bottom_right = 16
	panel.add_theme_stylebox_override("panel", ps)
	add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.name = "DeleteVBox"
	vbox.anchor_left = 0.0; vbox.anchor_top = 0.0; vbox.anchor_right = 1.0; vbox.anchor_bottom = 1.0
	vbox.offset_left = Global.pw(0.04); vbox.offset_right = Global.pw(-0.04)
	vbox.offset_top = Global.ph(0.02); vbox.offset_bottom = Global.ph(-0.02)
	panel.add_child(vbox)

	var label = Label.new()
	label.text = "确定要删除此牌组吗？\n牌组内的卡牌不会被删除"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 40)
	label.add_theme_color_override("font_color", Color("#e74c3c"))
	vbox.add_child(label)

	var spacer = ColorRect.new()
	spacer.color = Color.TRANSPARENT
	spacer.custom_minimum_size = Vector2(0, Global.ph(0.02))
	vbox.add_child(spacer)

	var hbox = HBoxContainer.new()
	hbox.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	hbox.custom_minimum_size = Vector2(0, Global.ph(0.08))

	var cancel_btn = Button.new()
	cancel_btn.text = "取消"
	cancel_btn.add_theme_font_size_override("font_size", 40)
	var cs = StyleBoxFlat.new()
	cs.bg_color = Global.current.btn_bg; cs.border_width_left = 2; cs.border_width_right = 2; cs.border_width_top = 2; cs.border_width_bottom = 2
	cs.border_color = Color("#888888"); cs.corner_radius_top_left = 10; cs.corner_radius_top_right = 10
	cs.corner_radius_bottom_left = 10; cs.corner_radius_bottom_right = 10; cs.content_margin_left = 0; cs.content_margin_right = 0
	var csh = cs.duplicate(); csh.bg_color = Global.current.btn_bg_hover
	cancel_btn.add_theme_stylebox_override("normal", cs); cancel_btn.add_theme_stylebox_override("hover", csh)
	cancel_btn.add_theme_stylebox_override("pressed", cs)
	cancel_btn.add_theme_color_override("font_color", Global.current.btn_text)
	cancel_btn.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	cancel_btn.pressed.connect(func(): Global.play_sfx("click"); _close_delete_popup())
	hbox.add_child(cancel_btn)

	var confirm_btn = Button.new()
	confirm_btn.text = "确认删除"
	confirm_btn.add_theme_font_size_override("font_size", 40)
	var cfs = StyleBoxFlat.new()
	cfs.bg_color = Color("#6b2c2c"); cfs.border_width_left = 2; cfs.border_width_right = 2; cfs.border_width_top = 2; cfs.border_width_bottom = 2
	cfs.border_color = Color("#e74c3c"); cfs.corner_radius_top_left = 10; cfs.corner_radius_top_right = 10
	cfs.corner_radius_bottom_left = 10; cfs.corner_radius_bottom_right = 10; cfs.content_margin_left = 0; cfs.content_margin_right = 0
	var cfsh = cfs.duplicate(); cfsh.bg_color = Global.current.btn_bg_hover
	confirm_btn.add_theme_stylebox_override("normal", cfs); confirm_btn.add_theme_stylebox_override("hover", cfsh)
	confirm_btn.add_theme_stylebox_override("pressed", cfs)
	confirm_btn.add_theme_color_override("font_color", Color("#e74c3c"))
	confirm_btn.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	var d_id = deck_id
	confirm_btn.pressed.connect(func(): Global.play_sfx("click"); _do_delete_deck(d_id))
	hbox.add_child(confirm_btn)

	vbox.add_child(hbox)

func _close_delete_popup():
	for c in get_children():
		if c.name.begins_with("Delete"):
			remove_child(c)
			c.queue_free()

func _do_delete_deck(deck_id: String):
	CardManager.delete_deck(deck_id)
	SaveManager.save_to_disk()
	_close_delete_popup()
	_refresh_deck_list()

# ============================================================
# 编辑模式 - 进入
# ============================================================

func _enter_edit_mode(deck_id: String):
	_current_deck_id = deck_id
	_current_view = "edit"
	_create_btn.visible = false

	# 查找牌组名称
	var decks = CardManager.get_all_decks()
	if decks.has(deck_id):
		_current_deck_name = decks[deck_id].get("name", "未命名牌组")

	# 切换可见性
	_scroll.visible = false
	_edit_root.visible = true

	_edit_title_label.text = "编辑: " + _current_deck_name

	# ★ 返回按钮切换为退出编辑模式（只在进入时做一次，避免 _refresh_edit_view 反复调用报错）
	if _back_btn and _back_btn.pressed.is_connected(_on_back):
		_back_btn.pressed.disconnect(_on_back)
	if _back_btn and not _back_btn.pressed.is_connected(_exit_edit_mode):
		_back_btn.pressed.connect(_exit_edit_mode)

	_refresh_edit_view()

# ============================================================
# 编辑模式 - 刷新视图
# ============================================================

func _refresh_edit_view():
	# 清空旧内容
	for c in _edit_deck_vbox.get_children():
		_edit_deck_vbox.remove_child(c)
		c.queue_free()
	for c in _edit_avail_vbox.get_children():
		_edit_avail_vbox.remove_child(c)
		c.queue_free()

	# 获取数据
	var decks = CardManager.get_all_decks()
	var deck_cards_ids = []
	if decks.has(_current_deck_id):
		deck_cards_ids = decks[_current_deck_id].get("cards", [])

	var all_cards = CardManager.get_all_cards()
	# 构建 ID→card 查找表，避免 O(n²) 嵌套循环
	var card_lookup := {}
	for c in all_cards:
		card_lookup[c.get("id", "")] = c

	# 渲染牌组内卡牌
	if deck_cards_ids.size() == 0:
		var empty = Label.new()
		empty.text = "（牌组为空，点击下方卡牌加入）"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_font_size_override("font_size", 40)
		empty.add_theme_color_override("font_color", Color("#999999"))
		empty.custom_minimum_size = Vector2(0, Global.ph(0.06))
		_edit_deck_vbox.add_child(empty)
	else:
		for cid in deck_cards_ids:
			var card = card_lookup.get(cid)
			if card == null:
				continue

			var row = HBoxContainer.new()
			row.name = "DeckCardRow_" + cid
			row.custom_minimum_size = Vector2(0, Global.ph(0.08))
			row.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
			row.set_meta("card_data", card)
			row.set_meta("row_index", _edit_deck_vbox.get_child_count())

			var card_name = card.get("name", card.get("card_name", "未知"))
			var cost = card.get("cost", card.get("energy_cost", 0))
			var atk = card.get("atk", card.get("attack", 0))
			var hp = card.get("hp", card.get("health", 0))

			var info = Label.new()
			info.text = "⚡" + str(cost) + "  " + str(card_name) + "  ⚔" + str(atk) + " ❤" + str(hp)
			info.add_theme_font_size_override("font_size", 45)
			info.add_theme_color_override("font_color", Color("#f1c40f"))
			info.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
			row.add_child(info)

			var remove_btn = Button.new()
			remove_btn.text = "移除"
			remove_btn.add_theme_font_size_override("font_size", 40)
			var rbs = StyleBoxFlat.new()
			rbs.bg_color = Color("#6b2c2c"); rbs.border_width_left = 1; rbs.border_width_right = 1; rbs.border_width_top = 1; rbs.border_width_bottom = 1
			rbs.border_color = Color("#e74c3c"); rbs.corner_radius_top_left = 8; rbs.corner_radius_top_right = 8
			rbs.corner_radius_bottom_left = 8; rbs.corner_radius_bottom_right = 8; rbs.content_margin_left = 12; rbs.content_margin_right = 12
			remove_btn.add_theme_stylebox_override("normal", rbs)
			remove_btn.add_theme_color_override("font_color", Color("#e74c3c"))
			var card_id = cid
			remove_btn.pressed.connect(func(): _remove_card_from_deck(card_id))
			row.add_child(remove_btn)

			_edit_deck_vbox.add_child(row)

	# 可用卡牌（不在牌组中的）
	var in_deck = {}
	for cid in deck_cards_ids:
		in_deck[cid] = true

	var available = []
	for c in all_cards:
		if not in_deck.has(c.get("id", "")):
			available.append(c)

	# 筛选按钮
	var filter_btn = Button.new()
	filter_btn.text = "🔍 筛选"
	filter_btn.add_theme_font_size_override("font_size", 36)
	var fbs = StyleBoxFlat.new()
	fbs.bg_color = Global.current.btn_bg
	fbs.border_width_left = 2; fbs.border_width_right = 2
	fbs.border_width_top = 2; fbs.border_width_bottom = 2
	fbs.border_color = Color("#e8a838")
	fbs.corner_radius_top_left = 10; fbs.corner_radius_top_right = 10
	fbs.corner_radius_bottom_left = 10; fbs.corner_radius_bottom_right = 10
	fbs.content_margin_left = 16; fbs.content_margin_right = 16
	var fbsh = fbs.duplicate(); fbsh.bg_color = Global.current.btn_bg_hover
	filter_btn.add_theme_stylebox_override("normal", fbs)
	filter_btn.add_theme_stylebox_override("hover", fbsh)
	filter_btn.add_theme_stylebox_override("pressed", fbs)
	filter_btn.add_theme_color_override("font_color", Global.current.btn_text)
	filter_btn.custom_minimum_size = Vector2(0, Global.ph(0.07))
	filter_btn.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	filter_btn.pressed.connect(func(): _show_filter_popup())
	_edit_avail_vbox.add_child(filter_btn)

	# 应用筛选+排序
	var filtered = _get_filtered_sorted_available(available)

	# 结果计数
	var count_label = Label.new()
	count_label.text = "可用卡牌: " + str(filtered.size()) + " / " + str(available.size()) + " 张"
	count_label.add_theme_font_size_override("font_size", 32)
	count_label.add_theme_color_override("font_color", Color("#888888"))
	count_label.custom_minimum_size = Vector2(0, Global.ph(0.04))
	_edit_avail_vbox.add_child(count_label)

	if filtered.size() == 0:
		var empty = Label.new()
		empty.text = "（没有匹配的卡牌）"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_font_size_override("font_size", 40)
		empty.add_theme_color_override("font_color", Color("#999999"))
		empty.custom_minimum_size = Vector2(0, Global.ph(0.06))
		_edit_avail_vbox.add_child(empty)
	else:
		for card in filtered:
			var row = HBoxContainer.new()
			row.name = "AvailRow_" + card.get("id", "")
			row.custom_minimum_size = Vector2(0, Global.ph(0.08))
			row.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
			row.set_meta("card_data", card)
			row.set_meta("row_index", _edit_avail_vbox.get_child_count())

			var card_name = card.get("name", card.get("card_name", "未知"))
			var cost = card.get("cost", card.get("energy_cost", 0))
			var atk = card.get("atk", card.get("attack", 0))
			var hp = card.get("hp", card.get("health", 0))
			var quality = card.get("quality", "—")
			var display_q = quality
			if " ~ " in quality:
				var q_parts = quality.split(" ~ ")
				display_q = q_parts[q_parts.size() - 1].strip_edges()

			var info = Label.new()
			info.text = "⚡" + str(cost) + "  " + str(card_name) + "  [" + display_q + "]  ⚔" + str(atk) + " ❤" + str(hp)
			info.add_theme_font_size_override("font_size", 45)
			info.add_theme_color_override("font_color", _get_quality_color(display_q))
			info.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
			row.add_child(info)

			var add_btn = Button.new()
			add_btn.text = "加入"
			add_btn.add_theme_font_size_override("font_size", 40)
			var abs = StyleBoxFlat.new()
			abs.bg_color = Color("#2c6b2c"); abs.border_width_left = 1; abs.border_width_right = 1; abs.border_width_top = 1; abs.border_width_bottom = 1
			abs.border_color = Color("#2ecc71"); abs.corner_radius_top_left = 8; abs.corner_radius_top_right = 8
			abs.corner_radius_bottom_left = 8; abs.corner_radius_bottom_right = 8; abs.content_margin_left = 12; abs.content_margin_right = 12
			add_btn.add_theme_stylebox_override("normal", abs)
			add_btn.add_theme_color_override("font_color", Color("#2ecc71"))
			var card_id = card.get("id", "")
			add_btn.pressed.connect(func(): _add_card_to_deck(card_id))
			row.add_child(add_btn)

			_edit_avail_vbox.add_child(row)

	# ★ 返回按钮的信号切换已在 _enter_edit_mode 中完成，此处不再重复操作

func _exit_edit_mode():
	Global.play_sfx("click")
	_current_view = "list"
	_current_deck_id = ""
	_create_btn.visible = true
	_scroll.visible = true
	_edit_root.visible = false
	# ★ 安全断开/连接，避免重复调用报错
	if _back_btn and _back_btn.pressed.is_connected(_exit_edit_mode):
		_back_btn.pressed.disconnect(_exit_edit_mode)
	if _back_btn and not _back_btn.pressed.is_connected(_on_back):
		_back_btn.pressed.connect(_on_back)
	# 关闭筛选弹窗（如果打开的话）
	_close_filter_popup()
	# 重置筛选状态
	_filter_quality = "all"
	_sort_field = "cost"
	_sort_asc = true
	_search_text = ""
	_search_input = null
	_refresh_deck_list()

func _add_card_to_deck(card_id: String):
	Global.play_sfx("click")
	CardManager.add_card_to_deck(_current_deck_id, card_id)
	SaveManager.save_to_disk()
	_refresh_edit_view()

func _remove_card_from_deck(card_id: String):
	Global.play_sfx("click")
	CardManager.remove_card_from_deck_by_id(_current_deck_id, card_id)
	SaveManager.save_to_disk()
	_refresh_edit_view()

# ============================================================
# 筛选 / 排序 / 搜索
# ============================================================

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
	# 标题
	var title = Label.new()
	title.text = "筛选卡牌"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 50)
	title.add_theme_color_override("font_color", Global.current.title)
	vbox.add_child(title)
	# 搜索输入框（独占一行）
	_search_input = LineEdit.new()
	_search_input.name = "PopupSearchInput"
	_search_input.placeholder_text = "搜索名称或描述..."
	_search_input.add_theme_font_size_override("font_size", 42)
	_search_input.custom_minimum_size = Vector2(0, Global.ph(0.08))
	_search_input.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	_search_input.text = _search_text
	vbox.add_child(_search_input)
	# 搜索操作按钮行（在输入框下方）
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
		_refresh_edit_view()
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
		_refresh_edit_view()
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
		{"key": "normal", "label": "普通", "color": Color("#888888")},
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
			_refresh_edit_view()
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
			_refresh_edit_view()
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
		_refresh_edit_view()
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
		_refresh_edit_view()
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

func _get_quality_rank(quality: String) -> int:
	var q = quality
	if " ~ " in q:
		var parts = q.split(" ~ ")
		q = parts[parts.size() - 1].strip_edges()
	if "完美" in q:
		return 4
	elif "卓越" in q:
		return 3
	elif "精良" in q:
		return 2
	else:
		return 1

func _get_filtered_sorted_available(available: Array) -> Array:
	var result = []
	# 品质筛选
	for card in available:
		if _filter_quality != "all":
			var q = card.get("quality", "")
			var rank = _get_quality_rank(q)
			match _filter_quality:
				"perfect":
					if rank != 4: continue
				"excellent":
					if rank != 3: continue
				"fine":
					if rank != 2: continue
				"normal":
					if rank != 1: continue
		# 搜索筛选
		if _search_text != "":
			var name_str = card.get("name", card.get("card_name", "")).to_lower()
			var desc_str = card.get("desc", "").to_lower()
			if not _search_text.to_lower() in name_str and not _search_text.to_lower() in desc_str:
				continue
		result.append(card)
	# 排序
	result.sort_custom(func(a, b):
		var val_a
		var val_b
		if _sort_field == "cost":
			val_a = a.get("cost", a.get("energy_cost", 0))
			val_b = b.get("cost", b.get("energy_cost", 0))
		else:  # quality
			val_a = _get_quality_rank(a.get("quality", ""))
			val_b = _get_quality_rank(b.get("quality", ""))
		if _sort_asc:
			return val_a < val_b
		else:
			return val_a > val_b
	)
	return result

# ============================================================
# 长按系统
# ============================================================

func _setup_long_press():
	set_process(false)

func _process(delta):
	if _pressed_row == null or _pressed_card_data == null:
		_press_timer = 0.0
		set_process(false)
		return

	_press_timer += delta
	if _press_timer >= LONG_PRESS_TIME:
		_show_card_detail(_pressed_card_data)
		_cancel_press()

func _input(event):
	if event is InputEventScreenTouch:
		if event.pressed:
			_press_start_pos = event.position
			_press_timer = 0.0
			_pressed_row = null
			_pressed_card_data = null
			_press_index = -1

			# 如果是在编辑模式，查找触摸位置的行
			if _current_view == "edit" and _edit_root.visible:
				_pressed_row = _find_row_at(event.position, _edit_deck_vbox)
				if _pressed_row == null:
					_pressed_row = _find_row_at(event.position, _edit_avail_vbox)
				if _pressed_row != null and _pressed_row.has_meta("card_data"):
					_pressed_card_data = _pressed_row.get_meta("card_data")
					set_process(true)
		else:
			if _pressed_row != null:
				var dist = event.position.distance_to(_press_start_pos)
				if dist < DRAG_THRESHOLD and _press_timer < LONG_PRESS_TIME:
					pass
			_cancel_press()

func _find_row_at(pos: Vector2, container: VBoxContainer) -> Control:
	for c in container.get_children():
		if c is Control and c.has_meta("card_data"):
			var rect = Rect2(c.get_global_rect().position, c.get_global_rect().size)
			if rect.has_point(pos):
				return c
	return null

func _cancel_press():
	_press_timer = 0.0
	_pressed_row = null
	_pressed_card_data = null
	_press_index = -1
	set_process(false)

func _show_card_detail(card_data: Dictionary):
	var card_name = card_data.get("name", card_data.get("card_name", "未命名卡牌"))
	var attack = card_data.get("atk", card_data.get("attack", 0))
	var health = card_data.get("hp", card_data.get("health", 0))
	var energy_cost = card_data.get("cost", card_data.get("energy_cost", 0))
	var quality = card_data.get("quality", "—")
	# 品质范围转显示用品质（取范围上限，如"标准 ~ 卓越"→"卓越"）
	var display_quality = quality
	if " ~ " in quality:
		var q_parts = quality.split(" ~ ")
		display_quality = q_parts[q_parts.size() - 1].strip_edges()
	var main_element = CardManager.get_card_element(card_data)
	var fields = card_data.get("fields", [])
	var desc = card_data.get("desc", "")
	var star = card_data.get("star", 1)
	var effects = card_data.get("effects", [])
	
	# 遮罩
	var overlay = ColorRect.new()
	overlay.name = "DetailOverlay"
	overlay.color = Color(0.0, 0.0, 0.0, 0.7)
	overlay.anchor_left = 0.0; overlay.anchor_top = 0.0
	overlay.anchor_right = 1.0; overlay.anchor_bottom = 1.0
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and not e.pressed:
			Global.play_sfx("click"); overlay.queue_free()
	)
	add_child(overlay)
	
	# 弹窗面板
	var panel = Panel.new()
	panel.name = "DetailPanel"
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
	var aux_items = card_data.get("aux_items", [])
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
	
	# 关闭按钮
	var close_btn = Button.new()
	close_btn.text = "关闭"
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
	close_btn.pressed.connect(func(): Global.play_sfx("click"); overlay.queue_free())
	bottom_hbox.add_child(close_btn)
func _get_quality_color(quality: String) -> Color:
	if "完美" in quality:
		return Color("#f9d371")
	elif "卓越" in quality:
		return Color("#c084fc")
	elif "精良" in quality:
		return Color("#60a5fa")
	else:
		return Color("#aaaaaa")
func _on_create_deck():
	Global.play_sfx("click")
	var deck_id = "DECK_" + str(Time.get_unix_time_from_system())
	var deck_name = "新牌组"
	CardManager.create_deck(deck_id, deck_name)
	_refresh_deck_list()
	# 创建后自动进入编辑模式
	_enter_edit_mode(deck_id)

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

# ============================================================
#  导航
# ============================================================
func _on_back():
	Global.play_sfx("click")
	# 第四幕：组卡完成 → 返回时无条件推进进度（防死循环）
	# 只要进了组卡界面再返回，就说明已"看过"组卡引导了
	if TutorialManager.get_progress() == TutorialManager.PROGRESS_FIRST_CARD:
		TutorialManager.advance()
		print("[教程] 组卡完成，进度 3→4")
	Global.change_scene("res://Main.tscn")

func _on_gallery():
	Global.play_sfx("click")
	Global.change_scene("res://CardGallery.tscn")
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
			Global.play_sfx("click"); overlay.queue_free()
	)
	add_child(overlay)
	
	var panel = Panel.new()
	panel.name = "HelpPanel"
	panel.anchor_left = 0.05; panel.anchor_top = 0.05
	panel.anchor_right = 0.95; panel.anchor_bottom = 0.95
	panel.clip_contents = true
	var ps = StyleBoxFlat.new()
	ps.bg_color = Color(0.08, 0.06, 0.12)
	ps.border_width_left = 3; ps.border_width_right = 3
	ps.border_width_top = 3; ps.border_width_bottom = 3
	ps.border_color = Color("#c0392b")
	ps.corner_radius_top_left = 16; ps.corner_radius_top_right = 16
	ps.corner_radius_bottom_left = 16; ps.corner_radius_bottom_right = 16
	panel.add_theme_stylebox_override("panel", ps)
	overlay.add_child(panel)
	
	var title = Label.new()
	title.text = "🃏 配置牌库指南"
	title.add_theme_font_size_override("font_size", 60)
	title.add_theme_color_override("font_color", Color("#c0392b"))
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
	lbl.text = "配置牌库用于管理你的卡组，每套卡组最多20张卡牌。"
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
		"🆕 新建牌组：输入名称创建新卡组",
		"✏️ 重命名：点击卡组名可修改",
		"🗑️ 删除：清空卡组后可删除",
		"📦 从仓库选卡：点击卡组进入编辑，从仓库添加卡牌",
		"🃏 同名卡：同名卡可编入多张（每张独立实例ID）",
		"⚡ 能量上限：每回合自动获得1点能量",
		"💡 建议搭配攻击、防御、效果卡牌保持平衡",
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
	lbl.text = "💡 长按卡牌可查看详情，点击卡牌可加入/移出牌组"
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

func _on_theme_changed(mode = null):
	var _t0 = Time.get_ticks_msec()
	if mode == null:
		mode = Global.current_mode
	var is_day = mode == Global.ThemeMode.DAY

	_apply_theme_styles()

	# 非首次切换时才刷新列表（首次已在 _ready 里刷过了）
	if not _is_initial_theme:
		_refresh_deck_list()
		if _current_view == "edit" and _edit_root and _edit_root.visible:
			_refresh_edit_view()
	_is_initial_theme = false
	print("[DeckEdit] _on_theme_changed: %dms" % [Time.get_ticks_msec() - _t0])

func _apply_theme_styles():
	var _t0 = Time.get_ticks_msec()
	var mode = Global.current_mode
	var is_day = mode == Global.ThemeMode.DAY

	# 背景纹理切换
	var bg = get_node_or_null("Background")
	if bg and bg is TextureRect:
		if _tex_night == null:
			_tex_night = load("res://assets/theme/bg_night.png")
			_tex_day = load("res://assets/theme/bg_day.png")
		bg.texture = _tex_day if is_day else _tex_night

	# 顶栏
	var topbar = get_node_or_null("TopBar")
	if topbar and topbar is ColorRect:
		topbar.color = Global.current.topbar_bg
	var topbar_line = get_node_or_null("TopBarLine")
	if topbar_line and topbar_line is ColorRect:
		topbar_line.color = Global.current.topbar_border

	# 底栏
	var bottom_bar = get_node_or_null("BottomBar")
	if bottom_bar and bottom_bar is ColorRect:
		bottom_bar.color = Global.current.topbar_bg
	var bottom_bar_line = get_node_or_null("BottomBarLine")
	if bottom_bar_line and bottom_bar_line is ColorRect:
		bottom_bar_line.color = Global.current.topbar_border

	# 标题
	var title = get_node_or_null("Title")
	if title and title is Label:
		title.add_theme_color_override("font_color", Global.current.title)
		title.add_theme_color_override("font_shadow_color", Global.current.title_shadow)
		title.add_theme_constant_override("shadow_offset_x", Global.current.shadow_offset)
		title.add_theme_constant_override("shadow_offset_y", Global.current.shadow_offset)

	# 编辑区标题
	if _edit_title_label:
		_edit_title_label.add_theme_color_override("font_color", Global.current.title)

	# 按钮：圆角背景 + 统一文字颜色（跟主界面/设置界面风格统一）
	# 如果主题没变，直接跳过（避免重复创建16个StyleBoxFlat）
	var mode_key = mode
	if _last_applied_mode == mode_key:
		print("[DeckEdit] _apply_theme_styles: 跳过（主题未变）")
		return
	_last_applied_mode = mode_key
	
	var icon_c = Color("#645C50") if is_day else Color("#CBCBE0")
	var btn_bg = Color(0.15, 0.13, 0.20, 0.85) if not is_day else Color(0.90, 0.85, 0.75, 0.85)
	var btn_bg_hover = btn_bg.lightened(0.12)
	var btn_bg_pressed = btn_bg.darkened(0.15)
	var border_c = Color("#E8A838") if not is_day else Color("#946F38")
	var btn_names = ["BackBtn", "GalleryBtn", "CreateDeckBtn", "HelpBtn"]
	for bname in btn_names:
		var btn = get_node_or_null(bname)
		if not btn is Button:
			continue
		btn.add_theme_color_override("font_color", icon_c)
		btn.add_theme_color_override("font_hover_color", icon_c.lightened(0.15))
		btn.add_theme_color_override("font_pressed_color", icon_c.darkened(0.2))
		for state in ["normal", "hover", "pressed", "focus"]:
			var sb = StyleBoxFlat.new()
			sb.bg_color = btn_bg_hover if state == "hover" else (btn_bg_pressed if state == "pressed" else btn_bg)
			sb.border_width_left = 2; sb.border_width_right = 2
			sb.border_width_top = 2; sb.border_width_bottom = 2
			sb.border_color = border_c
			var r = 12
			if bname == "HelpBtn":
				r = 50
			sb.corner_radius_top_left = r; sb.corner_radius_top_right = r
			sb.corner_radius_bottom_left = r; sb.corner_radius_bottom_right = r
			sb.content_margin_left = 16; sb.content_margin_right = 16
			sb.content_margin_top = 8; sb.content_margin_bottom = 8
			btn.add_theme_stylebox_override(state, sb)
	print("[DeckEdit] _apply_theme_styles: %dms" % [Time.get_ticks_msec() - _t0])

# ============================================================
# 通用提示弹窗
# ============================================================

func _show_popup(title: String, message: String, color: Color):
	var overlay = ColorRect.new()
	overlay.name = "PopupOverlay"
	overlay.color = Color(0, 0, 0, 0.7)
	overlay.anchor_left = 0.0; overlay.anchor_top = 0.0
	overlay.anchor_right = 1.0; overlay.anchor_bottom = 1.0
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	
	var panel = Panel.new()
	panel.name = "PopupPanel"
	panel.anchor_left = 0.5; panel.anchor_top = 0.5
	panel.anchor_right = 0.5; panel.anchor_bottom = 0.5
	panel.offset_left = -Global.pw(0.35); panel.offset_right = Global.pw(0.35)
	panel.offset_top = -Global.ph(0.15); panel.offset_bottom = Global.ph(0.15)
	var ps = StyleBoxFlat.new()
	ps.bg_color = Global.current.bg
	ps.border_width_left = 3; ps.border_width_right = 3
	ps.border_width_top = 3; ps.border_width_bottom = 3
	ps.border_color = color
	ps.corner_radius_top_left = 16; ps.corner_radius_top_right = 16
	ps.corner_radius_bottom_left = 16; ps.corner_radius_bottom_right = 16
	panel.add_theme_stylebox_override("panel", ps)
	overlay.add_child(panel)
	
	var vbox = VBoxContainer.new()
	vbox.anchor_left = 0.0; vbox.anchor_top = 0.0
	vbox.anchor_right = 1.0; vbox.anchor_bottom = 1.0
	vbox.offset_left = Global.pw(0.04); vbox.offset_top = Global.ph(0.03)
	vbox.offset_right = Global.pw(-0.04); vbox.offset_bottom = Global.ph(-0.03)
	panel.add_child(vbox)
	
	var title_lbl = Label.new()
	title_lbl.text = title
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 50)
	title_lbl.add_theme_color_override("font_color", color)
	vbox.add_child(title_lbl)
	
	var msg_lbl = Label.new()
	msg_lbl.text = message
	msg_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg_lbl.add_theme_font_size_override("font_size", 35)
	msg_lbl.add_theme_color_override("font_color", Color("#cccccc"))
	msg_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(msg_lbl)
	
	var spacer = ColorRect.new()
	spacer.color = Color.TRANSPARENT
	spacer.custom_minimum_size = Vector2(0, Global.ph(0.02))
	vbox.add_child(spacer)
	
	var close_btn = Button.new()
	close_btn.text = "确定"
	close_btn.add_theme_font_size_override("font_size", 40)
	close_btn.custom_minimum_size = Vector2(0, Global.ph(0.06))
	var cb = StyleBoxFlat.new()
	cb.bg_color = Color("#333333")
	cb.border_width_left = 2; cb.border_width_right = 2
	cb.border_width_top = 2; cb.border_width_bottom = 2
	cb.border_color = color
	cb.corner_radius_top_left = 12; cb.corner_radius_top_right = 12
	cb.corner_radius_bottom_left = 12; cb.corner_radius_bottom_right = 12
	close_btn.add_theme_stylebox_override("normal", cb)
	close_btn.add_theme_stylebox_override("pressed", cb)
	close_btn.add_theme_stylebox_override("hover", cb)
	close_btn.add_theme_color_override("font_color", Color("#dddddd"))
	close_btn.pressed.connect(func():
		Global.play_sfx("click")
		overlay.queue_free()
	)
	vbox.add_child(close_btn)
	
	# 点击遮罩关闭
	overlay.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and not ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			overlay.queue_free()
	)
