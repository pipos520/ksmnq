extends Control
## ============================================================
##  公会任务 —— 任务列表、纹路获取
## ============================================================

var _task_scroll: ScrollContainer
var _task_vbox: VBoxContainer
var _refresh_label: Label
var _progress_label: Label

# 长按相关
var _long_press_timer: float = 0.0
var _long_press_target = null
var _long_press_active: bool = false
var _long_press_task: Dictionary = {}
var _long_press_type: String = ""

# 卡牌选择弹窗相关
var _card_picker_timer: float = 0.0
var _card_picker_active: bool = false
var _card_picker_card: Dictionary = {}
var _card_picker_overlay = null

# 广告刷新相关
var _hj_ads: HJAdsNode = null
var _ad_refresh_btn: Button = null
var _ad_status_label: Label = null

func _ready():
	# ---- 静态节点已在 GuildTasks.tscn 中声明 ----
	var back := get_node_or_null("BackBtn")
	if back is Button: back.pressed.connect(_on_back)
	# 内容容器
	var content := get_node_or_null("Content")
	# ---- 顶部信息栏 ----
	var info_bar = Panel.new()
	info_bar.name = "InfoBar"
	info_bar.anchor_left = 0.0; info_bar.anchor_top = 0.0; info_bar.anchor_right = 1.0; info_bar.anchor_bottom = 0.0
	info_bar.offset_left = 0; info_bar.offset_top = 0; info_bar.offset_bottom = Global.ph(0.10)
	var ibs = StyleBoxFlat.new()
	ibs.bg_color = Global.current.bg
	ibs.corner_radius_top_left = 15; ibs.corner_radius_top_right = 15
	ibs.corner_radius_bottom_left = 15; ibs.corner_radius_bottom_right = 15
	ibs.border_width_left = 2; ibs.border_width_right = 2
	ibs.border_width_top = 2; ibs.border_width_bottom = 2
	ibs.border_color = Color("#e8a838")
	info_bar.add_theme_stylebox_override("panel", ibs)
	content.add_child(info_bar)

	var guild_level = PlayerManager.get_guild_level()
	var guild_title = PlayerManager.get_guild_title()

	var hint_label = Label.new()
	hint_label.name = "HintLabel"
	hint_label.text = "Lv." + str(guild_level) + "  " + guild_title
	hint_label.add_theme_font_size_override("font_size", 48)
	hint_label.add_theme_color_override("font_color", Global.current.btn_text)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint_label.anchor_left = 0.0; hint_label.anchor_top = 0.0; hint_label.anchor_right = 0.5; hint_label.anchor_bottom = 1.0
	info_bar.add_child(hint_label)

	_progress_label = Label.new()
	_progress_label.name = "ProgressLabel"
	_progress_label.add_theme_font_size_override("font_size", 40)
	_progress_label.add_theme_color_override("font_color", Color("#e8a838"))
	_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_progress_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_progress_label.anchor_left = 0.5; _progress_label.anchor_top = 0.0; _progress_label.anchor_right = 1.0; _progress_label.anchor_bottom = 0.5
	info_bar.add_child(_progress_label)

	_refresh_label = Label.new()
	_refresh_label.name = "RefreshLabel"
	_refresh_label.add_theme_font_size_override("font_size", 40)
	_refresh_label.add_theme_color_override("font_color", Color("#aaaaaa"))
	_refresh_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_refresh_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_refresh_label.anchor_left = 0.5; _refresh_label.anchor_top = 0.5; _refresh_label.anchor_right = 1.0; _refresh_label.anchor_bottom = 1.0
	info_bar.add_child(_refresh_label)

	# ---- 任务列表滚动区域 ----
	_task_scroll = ScrollContainer.new()
	_task_scroll.name = "TaskScroll"
	_task_scroll.anchor_left = 0.0; _task_scroll.anchor_top = 0.0; _task_scroll.anchor_right = 1.0; _task_scroll.anchor_bottom = 1.0
	_task_scroll.offset_left = 0; _task_scroll.offset_top = Global.ph(0.265)
	_task_scroll.offset_right = 0; _task_scroll.offset_bottom = 0
	_task_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(_task_scroll)

	_task_vbox = VBoxContainer.new()
	_task_vbox.name = "TaskVBox"
	_task_vbox.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
	_task_vbox.add_theme_constant_override("separation", Global.ph(0.008))
	_task_scroll.add_child(_task_vbox)

	_refresh_ui()

	GuildTaskManager.tasks_refreshed.connect(_on_tasks_refreshed)
	GuildTaskManager.task_completed.connect(_on_task_completed)

	var timer = Timer.new()
	timer.name = "RefreshTimer"
	timer.wait_time = 1.0
	timer.timeout.connect(_update_refresh_display)
	add_child(timer)
	timer.start()

	# ===== 初始化灰鲸广告 =====
	_hj_ads = HJAdsNode.new()
	_hj_ads.name = "GuildHJAdsNode"
	add_child(_hj_ads)
	_hj_ads.app_id = "234475"
	_hj_ads.rewarded_placement_id = "9701263723893953"
	_hj_ads.debug_mode = false
	_hj_ads.ad_loaded.connect(_on_ad_loaded_refresh)
	_hj_ads.video_rewarded.connect(_on_video_rewarded_refresh)
	_hj_ads.ad_closed.connect(_on_ad_closed_refresh)
	_hj_ads.ad_failed.connect(_on_ad_failed_refresh)
	await get_tree().process_frame
	_hj_ads.init()
	_hj_ads.loadRewardedAd()

	# ---- 广告刷新按钮行 ----
	var ad_bar = Panel.new()
	ad_bar.name = "AdRefreshBar"
	ad_bar.anchor_left = 0.0; ad_bar.anchor_top = 0.0; ad_bar.anchor_right = 1.0; ad_bar.anchor_bottom = 0.0
	ad_bar.offset_left = 0; ad_bar.offset_top = Global.ph(0.10 + 0.005)
	ad_bar.offset_right = 0; ad_bar.offset_bottom = Global.ph(0.10 + 0.005 + 0.075)
	var ads = StyleBoxFlat.new()
	ads.bg_color = Global.current.bg
	ads.border_width_left = 2; ads.border_width_right = 2
	ads.border_width_top = 2; ads.border_width_bottom = 2
	ads.border_color = Color("#FF6B6B")
	ads.corner_radius_top_left = 10; ads.corner_radius_top_right = 10
	ads.corner_radius_bottom_left = 10; ads.corner_radius_bottom_right = 10
	ad_bar.add_theme_stylebox_override("panel", ads)
	content.add_child(ad_bar)

	_ad_refresh_btn = Button.new()
	_ad_refresh_btn.name = "AdRefreshBtn"
	_ad_refresh_btn.text = "看广告刷新任务"
	_ad_refresh_btn.add_theme_font_size_override("font_size", 40)
	var abs = StyleBoxFlat.new()
	abs.bg_color = Color("#FF6B6B")
	abs.border_width_left = 2; abs.border_width_right = 2
	abs.border_width_top = 2; abs.border_width_bottom = 2
	abs.border_color = Color("#FF5252")
	abs.corner_radius_top_left = 8; abs.corner_radius_top_right = 8
	abs.corner_radius_bottom_left = 8; abs.corner_radius_bottom_right = 8
	_ad_refresh_btn.add_theme_stylebox_override("normal", abs)
	_ad_refresh_btn.add_theme_color_override("font_color", Color("#ffffff"))
	_ad_refresh_btn.anchor_left = 0.0; _ad_refresh_btn.anchor_top = 0.0; _ad_refresh_btn.anchor_right = 0.5; _ad_refresh_btn.anchor_bottom = 1.0
	_ad_refresh_btn.offset_left = Global.pw(0.02); _ad_refresh_btn.offset_top = Global.ph(0.005)
	_ad_refresh_btn.offset_right = Global.pw(-0.01); _ad_refresh_btn.offset_bottom = Global.ph(-0.005)
	_ad_refresh_btn.pressed.connect(_on_ad_refresh_pressed)
	ad_bar.add_child(_ad_refresh_btn)

	_ad_status_label = Label.new()
	_ad_status_label.name = "AdRefreshStatus"
	_ad_status_label.text = ""  # 初值为空，真正点广告时再显示状态
	_ad_status_label.add_theme_font_size_override("font_size", 35)
	_ad_status_label.add_theme_color_override("font_color", Color("#aaaaaa"))
	_ad_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ad_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_ad_status_label.anchor_left = 0.5; _ad_status_label.anchor_top = 0.0; _ad_status_label.anchor_right = 1.0; _ad_status_label.anchor_bottom = 1.0
	_ad_status_label.offset_left = Global.pw(0.01); _ad_status_label.offset_top = 0
	_ad_status_label.offset_right = Global.pw(-0.02); _ad_status_label.offset_bottom = 0
	ad_bar.add_child(_ad_status_label)

	# ---- 每日任务入口按钮 ----
	var daily_bar = Panel.new()
	daily_bar.name = "DailyTaskBar"
	daily_bar.anchor_left = 0.0; daily_bar.anchor_top = 0.0; daily_bar.anchor_right = 1.0; daily_bar.anchor_bottom = 0.0
	daily_bar.offset_left = 0; daily_bar.offset_top = Global.ph(0.10 + 0.005 + 0.075 + 0.005)
	daily_bar.offset_right = 0; daily_bar.offset_bottom = Global.ph(0.10 + 0.005 + 0.075 + 0.005 + 0.075)
	var dbs = StyleBoxFlat.new()
	dbs.bg_color = Global.current.bg
	dbs.border_width_left = 2; dbs.border_width_right = 2
	dbs.border_width_top = 2; dbs.border_width_bottom = 2
	dbs.border_color = Color("#81C784")
	dbs.corner_radius_top_left = 10; dbs.corner_radius_top_right = 10
	dbs.corner_radius_bottom_left = 10; dbs.corner_radius_bottom_right = 10
	daily_bar.add_theme_stylebox_override("panel", dbs)
	content.add_child(daily_bar)

	var daily_btn = Button.new()
	daily_btn.text = "每日任务"
	daily_btn.add_theme_font_size_override("font_size", 40)
	var dabs = StyleBoxFlat.new()
	dabs.bg_color = Color("#4CAF50")
	dabs.border_width_left = 2; dabs.border_width_right = 2
	dabs.border_width_top = 2; dabs.border_width_bottom = 2
	dabs.border_color = Color("#388E3C")
	dabs.corner_radius_top_left = 8; dabs.corner_radius_top_right = 8
	dabs.corner_radius_bottom_left = 8; dabs.corner_radius_bottom_right = 8
	daily_btn.add_theme_stylebox_override("normal", dabs)
	daily_btn.add_theme_color_override("font_color", Color("#ffffff"))
	daily_btn.anchor_left = 0.0; daily_btn.anchor_top = 0.0; daily_btn.anchor_right = 0.5; daily_btn.anchor_bottom = 1.0
	daily_btn.offset_left = Global.pw(0.02); daily_btn.offset_top = Global.ph(0.005)
	daily_btn.offset_right = Global.pw(-0.01); daily_btn.offset_bottom = Global.ph(-0.005)
	daily_btn.pressed.connect(_on_daily_task_pressed)
	daily_bar.add_child(daily_btn)

	var daily_status = Label.new()
	daily_status.text = "每日阶梯任务"
	daily_status.add_theme_font_size_override("font_size", 35)
	daily_status.add_theme_color_override("font_color", Color("#81C784"))
	daily_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	daily_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	daily_status.anchor_left = 0.5; daily_status.anchor_top = 0.0; daily_status.anchor_right = 1.0; daily_status.anchor_bottom = 1.0
	daily_status.offset_left = Global.pw(0.01); daily_status.offset_top = 0
	daily_status.offset_right = Global.pw(-0.02); daily_status.offset_bottom = 0
	daily_bar.add_child(daily_status)

	# 主题
	Global.theme_changed.connect(_on_theme_changed)
	call_deferred("_apply_theme_styles")

func _on_theme_changed(_mode):
	_apply_theme_styles()

func _apply_theme_styles():
	var bg = get_node_or_null("Background")
	if bg: Global.apply_bg(bg)
	for n in ["TopBar", "BottomBar"]:
		var r = get_node_or_null(n)
		if r is ColorRect: r.color = Global.current.topbar_bg
	for n in ["TopBarLine", "BottomBarLine"]:
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
		var s = StyleBoxFlat.new()
		s.bg_color = Global.current.btn_bg
		s.border_width_left = 2; s.border_width_right = 2; s.border_width_top = 2; s.border_width_bottom = 2
		s.border_color = Color("#888888")
		s.corner_radius_top_left = 10; s.corner_radius_top_right = 10
		s.corner_radius_bottom_left = 10; s.corner_radius_bottom_right = 10
		back.add_theme_stylebox_override("normal", s)
		back.add_theme_color_override("font_color", Global.current.btn_text)
	_refresh_ui()

func _refresh_ui() -> void:
	# 清空现有任务
	for child in _task_vbox.get_children():
		child.queue_free()

	var tasks = GuildTaskManager.get_tasks()
	var completed = GuildTaskManager.get_completed_count()
	var total = GuildTaskManager.get_total_count()

	_progress_label.text = "已完成 " + str(completed) + " / " + str(total)
	_update_refresh_display()

	if tasks.size() == 0:
		var empty_label = Label.new()
		empty_label.text = "暂无任务，等待刷新……"
		empty_label.add_theme_font_size_override("font_size", 35)
		empty_label.add_theme_color_override("font_color", Color("#888888"))
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty_label.custom_minimum_size = Vector2(0, Global.ph(0.3))
		empty_label.size_flags_horizontal = Control.SIZE_EXPAND
		_task_vbox.add_child(empty_label)
		return

	for task in tasks:
		var task_card = _create_task_card(task)
		_task_vbox.add_child(task_card)

func _update_refresh_display() -> void:
	_refresh_label.text = "刷新：" + GuildTaskManager.get_refresh_time_text()

func _create_task_card(task: Dictionary) -> PanelContainer:
	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(0, Global.ph(0.24))
	card.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
	card.mouse_filter = Control.MOUSE_FILTER_PASS

	var task_type = task.get("type", -1)
	var completed = task.get("completed", false)
	var title = task.get("title", "")
	var content = task.get("content", "")
	var requirement = task.get("requirement", "")
	var reward_text = task.get("reward_text", "")

	# 任务类型颜色和图标
	var type_color = Color("#888888")
	var type_icon = ""
	match task_type:
		GuildTaskManager.TaskType.UNLOCK_CIRCUIT:
			type_color = Color("#e8a838")
			type_icon = ""
		GuildTaskManager.TaskType.COLLECT_MATERIAL:
			type_color = Color("#58a8d8")
			type_icon = ""
		GuildTaskManager.TaskType.COLLECT_GOLD:
			type_color = Color("#f0c040")
			type_icon = ""

	var bg_color = Global.current.bg
	if completed:
		bg_color = bg_color.darkened(0.15)

	var s = StyleBoxFlat.new()
	s.bg_color = bg_color
	s.corner_radius_top_left = 10; s.corner_radius_top_right = 10
	s.corner_radius_bottom_left = 10; s.corner_radius_bottom_right = 10
	s.border_width_left = 2; s.border_width_right = 2
	s.border_width_top = 2; s.border_width_bottom = 2
	s.border_color = type_color if not completed else Color("#555555")
	s.content_margin_left = 12; s.content_margin_right = 12
	s.content_margin_top = 6; s.content_margin_bottom = 6
	card.add_theme_stylebox_override("panel", s)

	# 用 HBoxContainer 做左右布局
	var hbox = HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
	hbox.size_flags_vertical = Control.SIZE_EXPAND | Control.SIZE_FILL
	hbox.add_theme_constant_override("separation", Global.pw(0.02))
	card.add_child(hbox)

	# 左侧：文字区域（VBoxContainer）
	var text_vbox = VBoxContainer.new()
	text_vbox.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
	text_vbox.size_flags_vertical = Control.SIZE_EXPAND | Control.SIZE_FILL
	text_vbox.add_theme_constant_override("separation", 2)
	hbox.add_child(text_vbox)

	# 任务名 + 类型图标
	var title_label = Label.new()
	title_label.text = type_icon + " " + title
	title_label.add_theme_font_size_override("font_size", 40)
	title_label.add_theme_color_override("font_color", type_color if not completed else Color("#888888"))
	title_label.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_vbox.add_child(title_label)

	# 任务内容
	var content_label = Label.new()
	content_label.text = content
	content_label.add_theme_font_size_override("font_size", 40)
	content_label.add_theme_color_override("font_color", Color("#ffffff") if not completed else Color("#666666"))
	content_label.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
	content_label.size_flags_vertical = Control.SIZE_EXPAND
	content_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_vbox.add_child(content_label)

	# 任务需求 + 奖励（一行）
	var info_row = HBoxContainer.new()
	info_row.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
	text_vbox.add_child(info_row)

	var req_label = Label.new()
	req_label.text = "" + requirement
	req_label.add_theme_font_size_override("font_size", 40)
	req_label.add_theme_color_override("font_color", Color("#58a8d8") if not completed else Color("#555555"))
	req_label.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
	req_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	req_label.mouse_filter = Control.MOUSE_FILTER_STOP
	req_label.gui_input.connect(_on_req_gui_input.bind(task))
	info_row.add_child(req_label)

	var reward_label = Label.new()
	reward_label.text = "" + reward_text
	reward_label.add_theme_font_size_override("font_size", 40)
	reward_label.add_theme_color_override("font_color", Color("#f0c040") if not completed else Color("#555555"))
	reward_label.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
	reward_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reward_label.mouse_filter = Control.MOUSE_FILTER_STOP
	reward_label.gui_input.connect(_on_reward_gui_input.bind(task))
	info_row.add_child(reward_label)

	# 右侧：状态/提交按钮
	if completed:
		var done_label = Label.new()
		done_label.text = ""
		done_label.add_theme_font_size_override("font_size", 40)
		done_label.add_theme_color_override("font_color", Color("#44cc44"))
		done_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		done_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		done_label.custom_minimum_size = Vector2(Global.pw(0.14), 0)
		hbox.add_child(done_label)
	else:
		var submit_btn = Button.new()
		submit_btn.text = "提交"
		submit_btn.add_theme_font_size_override("font_size", 40)
		submit_btn.add_theme_color_override("font_color", Color("#ffffff"))
		submit_btn.add_theme_color_override("font_hover_color", Color("#f0c040"))
		var sbs = StyleBoxFlat.new()
		sbs.bg_color = Color("#3a3a5e")
		sbs.corner_radius_top_left = 8; sbs.corner_radius_top_right = 8
		sbs.corner_radius_bottom_left = 8; sbs.corner_radius_bottom_right = 8
		sbs.border_width_left = 1; sbs.border_width_right = 1
		sbs.border_width_top = 1; sbs.border_width_bottom = 1
		sbs.border_color = Color("#e8a838")
		submit_btn.add_theme_stylebox_override("normal", sbs)
		submit_btn.custom_minimum_size = Vector2(Global.pw(0.14), Global.ph(0.08))
		submit_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		submit_btn.pressed.connect(_on_submit_pressed.bind(task.get("id", -1)))
		hbox.add_child(submit_btn)

	return card

# ==================== 长按详情弹窗 ====================

func _process(delta: float):
	if _long_press_active:
		_long_press_timer += delta
		if _long_press_timer >= 0.5:
			_long_press_active = false
			if _long_press_type == "requirement":
				_show_requirement_detail(_long_press_task)
			elif _long_press_type == "reward":
				_show_reward_detail(_long_press_task)
	if _card_picker_active:
		_card_picker_timer += delta
		if _card_picker_timer >= 0.5:
			_card_picker_active = false
			_show_card_detail_popup(_card_picker_card)

func _on_req_gui_input(event: InputEvent, task: Dictionary):
	if event is InputEventScreenTouch:
		if event.pressed:
			_long_press_timer = 0.0
			_long_press_task = task
			_long_press_type = "requirement"
			_long_press_active = true
		else:
			_long_press_active = false
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_long_press_timer = 0.0
			_long_press_task = task
			_long_press_type = "requirement"
			_long_press_active = true
		elif not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_long_press_active = false

func _on_reward_gui_input(event: InputEvent, task: Dictionary):
	if event is InputEventScreenTouch:
		if event.pressed:
			_long_press_timer = 0.0
			_long_press_task = task
			_long_press_type = "reward"
			_long_press_active = true
		else:
			_long_press_active = false
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_long_press_timer = 0.0
			_long_press_task = task
			_long_press_type = "reward"
			_long_press_active = true
		elif not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_long_press_active = false

func _show_requirement_detail(task: Dictionary):
	var existing = get_node_or_null("DetailOverlay")
	if existing:
		existing.queue_free()

	var overlay = ColorRect.new()
	overlay.name = "DetailOverlay"
	overlay.color = Color(0, 0, 0, 0.7)
	overlay.anchor_left = 0.0; overlay.anchor_top = 0.0
	overlay.anchor_right = 1.0; overlay.anchor_bottom = 1.0
	overlay.mouse_filter = MOUSE_FILTER_STOP
	overlay.gui_input.connect(_on_detail_overlay_input.bind(overlay))
	add_child(overlay)

	var panel = Panel.new()
	panel.name = "DetailPanel"
	panel.anchor_left = 0.08; panel.anchor_top = 0.2
	panel.anchor_right = 0.92; panel.anchor_bottom = 0.8
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

	var vbox = VBoxContainer.new()
	vbox.name = "DetailVBox"
	vbox.anchor_left = 0.0; vbox.anchor_top = 0.0
	vbox.anchor_right = 1.0; vbox.anchor_bottom = 1.0
	vbox.offset_left = Global.pw(0.04); vbox.offset_top = Global.ph(0.02)
	vbox.offset_right = Global.pw(-0.04); vbox.offset_bottom = Global.ph(-0.02)
	vbox.size_flags_horizontal = SIZE_FILL
	vbox.add_theme_constant_override("separation", Global.ph(0.01))
	panel.add_child(vbox)

	# 标题
	var title_label = Label.new()
	title_label.text = "任务需求详情"
	title_label.add_theme_font_size_override("font_size", 55)
	title_label.add_theme_color_override("font_color", Color("#58a8d8"))
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title_label)

	var line = HSeparator.new()
	line.add_theme_color_override("color", Global.current.topbar_border)
	vbox.add_child(line)

	var submit_type = task.get("submit_type", -1)
	var requirement = task.get("requirement", "无")
	var submit_condition = task.get("submit_condition", {})

	if submit_type == GuildTaskManager.SubmitType.SUBMIT_MATERIAL:
		var materials = submit_condition.get("materials", {})
		for mat_id in materials:
			var needed = materials[mat_id]
			var mat_info = Global.get_material_by_id(mat_id)
			var mat_name = mat_info.get("name", mat_id)
			var mat_rarity = mat_info.get("rarity", "普通")
			var mat_desc = mat_info.get("description", "")
			var rarity_color = Color("#95A5A6")
			match mat_rarity:
				"传说": rarity_color = Color("#FFD700")
				"史诗": rarity_color = Color("#9B59B6")
				"稀有": rarity_color = Color("#3498DB")
				"普通": rarity_color = Color("#95A5A6")

			var name_lbl = Label.new()
			name_lbl.text = "【" + mat_name + "】 ×" + str(needed)
			name_lbl.add_theme_font_size_override("font_size", 50)
			name_lbl.add_theme_color_override("font_color", rarity_color)
			vbox.add_child(name_lbl)

			var rarity_lbl = Label.new()
			rarity_lbl.text = "稀有度：" + mat_rarity
			rarity_lbl.add_theme_font_size_override("font_size", 45)
			rarity_lbl.add_theme_color_override("font_color", rarity_color)
			vbox.add_child(rarity_lbl)

			if mat_desc != "":
				var desc_lbl = Label.new()
				desc_lbl.text = mat_desc
				desc_lbl.add_theme_font_size_override("font_size", 45)
				desc_lbl.add_theme_color_override("font_color", Color("#cccccc"))
				desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				vbox.add_child(desc_lbl)

			# 素材属性
			var attrs = [
				{"key": "hardness", "label": "硬度", "color": Color("#FF9800")},
				{"key": "gloss", "label": "光泽", "color": Color("#E91E63")},
				{"key": "carry", "label": "承载力", "color": Color("#8BC34A")},
				{"key": "stability", "label": "稳定性", "color": Color("#3498DB")},
				{"key": "toughness", "label": "韧性", "color": Color("#9B59B6")},
				{"key": "bond", "label": "粘合度", "color": Color("#FF5722")},
			]
			for attr in attrs:
				var val = mat_info.get(attr["key"], null)
				if val != null:
					var row = HBoxContainer.new()
					row.size_flags_horizontal = SIZE_FILL
					vbox.add_child(row)
					var lbl = Label.new()
					lbl.text = attr["label"] + "：" + str(val)
					lbl.add_theme_font_size_override("font_size", 45)
					lbl.add_theme_color_override("font_color", attr["color"])
					row.add_child(lbl)

	else:
		# 卡牌提交条件
		var desc_label = Label.new()
		desc_label.text = requirement
		desc_label.add_theme_font_size_override("font_size", 50)
		desc_label.add_theme_color_override("font_color", Color("#ffffff"))
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(desc_label)

		var cond_type = submit_condition.get("type", "")
		var cond_detail = ""
		match cond_type:
			"element": cond_detail = "需要卡牌属性为：" + submit_condition.get("element", "无")
			"cost_range": cond_detail = "需要卡牌费用在 " + str(submit_condition.get("min_cost", 0)) + " ~ " + str(submit_condition.get("max_cost", 99)) + " 之间"
			"atk_min": cond_detail = "需要卡牌攻击力 ≥ " + str(submit_condition.get("min_atk", 0))
			"quality": cond_detail = "需要卡牌品质为：" + submit_condition.get("quality", "无")
			"effect_keyword": cond_detail = "需要卡牌效果包含「" + submit_condition.get("keyword", "") + "」"
		if cond_detail != "":
			var detail_lbl = Label.new()
			detail_lbl.text = cond_detail
			detail_lbl.add_theme_font_size_override("font_size", 45)
			detail_lbl.add_theme_color_override("font_color", Color("#e8a838"))
			detail_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			vbox.add_child(detail_lbl)

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
	close_btn.size_flags_horizontal = SIZE_FILL
	close_btn.custom_minimum_size = Vector2(0, Global.ph(0.07))
	close_btn.pressed.connect(_close_detail.bind(overlay))
	vbox.add_child(close_btn)


func _show_reward_detail(task: Dictionary):
	var existing = get_node_or_null("DetailOverlay")
	if existing:
		existing.queue_free()

	var overlay = ColorRect.new()
	overlay.name = "DetailOverlay"
	overlay.color = Color(0, 0, 0, 0.7)
	overlay.anchor_left = 0.0; overlay.anchor_top = 0.0
	overlay.anchor_right = 1.0; overlay.anchor_bottom = 1.0
	overlay.mouse_filter = MOUSE_FILTER_STOP
	overlay.gui_input.connect(_on_detail_overlay_input.bind(overlay))
	add_child(overlay)

	var panel = Panel.new()
	panel.name = "DetailPanel"
	panel.anchor_left = 0.08; panel.anchor_top = 0.2
	panel.anchor_right = 0.92; panel.anchor_bottom = 0.8
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

	var vbox = VBoxContainer.new()
	vbox.name = "DetailVBox"
	vbox.anchor_left = 0.0; vbox.anchor_top = 0.0
	vbox.anchor_right = 1.0; vbox.anchor_bottom = 1.0
	vbox.offset_left = Global.pw(0.04); vbox.offset_top = Global.ph(0.02)
	vbox.offset_right = Global.pw(-0.04); vbox.offset_bottom = Global.ph(-0.02)
	vbox.size_flags_horizontal = SIZE_FILL
	vbox.add_theme_constant_override("separation", Global.ph(0.01))
	panel.add_child(vbox)

	# 标题
	var title_label = Label.new()
	title_label.text = "任务奖励详情"
	title_label.add_theme_font_size_override("font_size", 55)
	title_label.add_theme_color_override("font_color", Color("#f0c040"))
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title_label)

	var line = HSeparator.new()
	line.add_theme_color_override("color", Global.current.topbar_border)
	vbox.add_child(line)

	var rewards = task.get("rewards", {})
	var circuit_id = rewards.get("circuit_id", "")
	var gold = rewards.get("gold", 0)

	# 金币奖励
	if gold > 0:
		var gold_lbl = Label.new()
		gold_lbl.text = "金币 ×" + Global.n2s(gold)
		gold_lbl.add_theme_font_size_override("font_size", 50)
		gold_lbl.add_theme_color_override("font_color", Color("#f0c040"))
		vbox.add_child(gold_lbl)

	# 纹路奖励
	if circuit_id != "":
		var circuit_info = Global.get_circuit_by_id(circuit_id)
		var circuit_name = circuit_info.get("name", circuit_id)
		var is_unlocked = CircuitManager.is_unlocked(circuit_id)

		var circuit_lbl = Label.new()
		circuit_lbl.text = "纹路解锁：" + circuit_name
		circuit_lbl.add_theme_font_size_override("font_size", 50)
		circuit_lbl.add_theme_color_override("font_color", Color("#e8a838"))
		vbox.add_child(circuit_lbl)

		if is_unlocked:
			var unlocked_lbl = Label.new()
			unlocked_lbl.text = "纹路已解锁，奖励转为200金币"
			unlocked_lbl.add_theme_font_size_override("font_size", 40)
			unlocked_lbl.add_theme_color_override("font_color", Color("#ff6666"))
			vbox.add_child(unlocked_lbl)

		# 纹路详情
		var category_name = ""
		if circuit_id.begins_with("TR"): category_name = "触发器"
		elif circuit_id.begins_with("C"): category_name = "条件"
		elif circuit_id.begins_with("A"): category_name = "动作"
		elif circuit_id.begins_with("T"): category_name = "目标"
		elif circuit_id.begins_with("CO"): category_name = "约束"

		var cat_lbl = Label.new()
		cat_lbl.text = "类型：" + category_name
		cat_lbl.add_theme_font_size_override("font_size", 45)
		cat_lbl.add_theme_color_override("font_color", Color("#aaaaaa"))
		vbox.add_child(cat_lbl)

		# 纹路额外信息
		if circuit_info.has("speed"):
			var speed_lbl = Label.new()
			speed_lbl.text = "速度等级：" + str(circuit_info.get("speed", 1))
			speed_lbl.add_theme_font_size_override("font_size", 45)
			speed_lbl.add_theme_color_override("font_color", Color("#aaaaaa"))
			vbox.add_child(speed_lbl)
		if circuit_info.has("once_only"):
			var once_lbl = Label.new()
			once_lbl.text = "一局仅一次：" + ("是" if circuit_info.get("once_only", false) else "否")
			once_lbl.add_theme_font_size_override("font_size", 45)
			once_lbl.add_theme_color_override("font_color", Color("#aaaaaa"))
			vbox.add_child(once_lbl)
		if circuit_info.has("base_energy"):
			var energy_lbl = Label.new()
			var energy_val = circuit_info.get("base_energy", "")
			energy_lbl.text = "基础能耗：" + str(energy_val)
			energy_lbl.add_theme_font_size_override("font_size", 45)
			energy_lbl.add_theme_color_override("font_color", Color("#aaaaaa"))
			vbox.add_child(energy_lbl)
		if circuit_info.has("params"):
			var params_lbl = Label.new()
			params_lbl.text = "参数：" + str(circuit_info.get("params", ""))
			params_lbl.add_theme_font_size_override("font_size", 45)
			params_lbl.add_theme_color_override("font_color", Color("#aaaaaa"))
			vbox.add_child(params_lbl)

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
	close_btn.size_flags_horizontal = SIZE_FILL
	close_btn.custom_minimum_size = Vector2(0, Global.ph(0.07))
	close_btn.pressed.connect(_close_detail.bind(overlay))
	vbox.add_child(close_btn)


func _close_detail(overlay: ColorRect):
	if overlay and is_instance_valid(overlay):
		overlay.queue_free()

func _on_detail_overlay_input(event: InputEvent, overlay: ColorRect):
	var pressed = false
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed = true
	if event is InputEventScreenTouch and event.pressed:
		pressed = true
	if pressed:
		var panel = overlay.get_node_or_null("DetailPanel")
		if panel:
			var mouse_pos = overlay.get_local_mouse_position()
			var panel_rect = Rect2(panel.position, panel.size)
			if not panel_rect.has_point(mouse_pos):
				_close_detail(overlay)

func _on_submit_pressed(task_index: int) -> void:
	var task = null
	for t in GuildTaskManager.get_tasks():
		if t.get("id", -1) == task_index:
			task = t
			break
	if task == null:
		return

	var submit_type = task.get("submit_type", -1)
	if submit_type == GuildTaskManager.SubmitType.SUBMIT_MATERIAL:
		_show_submit_confirm(task_index, task)
	else:
		_show_card_picker(task_index, task)

func _show_submit_confirm(task_index: int, task: Dictionary):
	var overlay = ColorRect.new()
	overlay.name = "SubmitConfirmOverlay"
	overlay.color = Color(0, 0, 0, 0.7)
	overlay.anchor_left = 0.0; overlay.anchor_top = 0.0
	overlay.anchor_right = 1.0; overlay.anchor_bottom = 1.0
	overlay.mouse_filter = MOUSE_FILTER_STOP
	overlay.gui_input.connect(_on_detail_overlay_input.bind(overlay))
	add_child(overlay)

	var panel = Panel.new()
	panel.name = "ConfirmPanel"
	panel.anchor_left = 0.1; panel.anchor_top = 0.3
	panel.anchor_right = 0.9; panel.anchor_bottom = 0.7
	var ps = StyleBoxFlat.new()
	ps.bg_color = Global.current.bg
	ps.border_width_left = 3; ps.border_width_right = 3
	ps.border_width_top = 3; ps.border_width_bottom = 3
	ps.border_color = Color("#e8a838")
	ps.corner_radius_top_left = 16; ps.corner_radius_top_right = 16
	ps.corner_radius_bottom_left = 16; ps.corner_radius_bottom_right = 16
	panel.add_theme_stylebox_override("panel", ps)
	overlay.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.anchor_left = 0.0; vbox.anchor_top = 0.0
	vbox.anchor_right = 1.0; vbox.anchor_bottom = 1.0
	vbox.offset_left = Global.pw(0.04); vbox.offset_top = Global.ph(0.02)
	vbox.offset_right = Global.pw(-0.04); vbox.offset_bottom = Global.ph(-0.02)
	vbox.size_flags_horizontal = SIZE_FILL
	vbox.add_theme_constant_override("separation", Global.ph(0.02))
	panel.add_child(vbox)

	var title_lbl = Label.new()
	title_lbl.text = "确认提交素材"
	title_lbl.add_theme_font_size_override("font_size", 50)
	title_lbl.add_theme_color_override("font_color", Color("#e8a838"))
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title_lbl)

	var reward_text = task.get("reward_text", "")
	var requirement = task.get("requirement", "")
	var desc_lbl = Label.new()
	desc_lbl.text = "需求：" + requirement + "\n奖励：" + reward_text
	desc_lbl.add_theme_font_size_override("font_size", 40)
	desc_lbl.add_theme_color_override("font_color", Color("#ffffff"))
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(desc_lbl)

	var spacer = Control.new()
	spacer.size_flags_vertical = SIZE_EXPAND
	vbox.add_child(spacer)

	var btn_row = HBoxContainer.new()
	btn_row.size_flags_horizontal = SIZE_FILL
	btn_row.add_theme_constant_override("separation", Global.pw(0.04))
	vbox.add_child(btn_row)

	var cancel_btn = Button.new()
	cancel_btn.text = "取消"
	cancel_btn.add_theme_font_size_override("font_size", 45)
	var cs = StyleBoxFlat.new()
	cs.bg_color = Color("#3a3a5e")
	cs.border_width_left = 2; cs.border_width_right = 2
	cs.border_width_top = 2; cs.border_width_bottom = 2
	cs.border_color = Color("#888888")
	cs.corner_radius_top_left = 10; cs.corner_radius_top_right = 10
	cs.corner_radius_bottom_left = 10; cs.corner_radius_bottom_right = 10
	cancel_btn.add_theme_stylebox_override("normal", cs)
	cancel_btn.add_theme_color_override("font_color", Global.current.btn_text)
	cancel_btn.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	cancel_btn.custom_minimum_size = Vector2(0, Global.ph(0.08))
	cancel_btn.pressed.connect(_close_detail.bind(overlay))
	btn_row.add_child(cancel_btn)

	var confirm_btn = Button.new()
	confirm_btn.text = "确认提交"
	confirm_btn.add_theme_font_size_override("font_size", 45)
	var cfs = StyleBoxFlat.new()
	cfs.bg_color = Color("#2a5a2a")
	cfs.border_width_left = 2; cfs.border_width_right = 2
	cfs.border_width_top = 2; cfs.border_width_bottom = 2
	cfs.border_color = Color("#44cc44")
	cfs.corner_radius_top_left = 10; cfs.corner_radius_top_right = 10
	cfs.corner_radius_bottom_left = 10; cfs.corner_radius_bottom_right = 10
	confirm_btn.add_theme_stylebox_override("normal", cfs)
	confirm_btn.add_theme_color_override("font_color", Color("#ffffff"))
	confirm_btn.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	confirm_btn.custom_minimum_size = Vector2(0, Global.ph(0.08))
	confirm_btn.pressed.connect(_do_submit_material.bind(task_index, overlay))
	btn_row.add_child(confirm_btn)

func _do_submit_material(task_index: int, overlay: ColorRect):
	_close_detail(overlay)
	var result = GuildTaskManager.submit_with_material(task_index)
	if result["success"]:
		_show_message(" " + result["message"], Color("#44cc44"))
		_refresh_ui()
	else:
		_show_message(" " + result["message"], Color("#ff6666"))

func _show_card_picker(task_index: int, task: Dictionary):
	var all_cards = CardManager.get_all_cards()
	var condition = task.get("submit_condition", {})
	var matching = []
	for card in all_cards:
		if _check_card_for_condition(card, condition):
			matching.append(card)

	var overlay = ColorRect.new()
	overlay.name = "CardPickerOverlay"
	overlay.color = Color(0, 0, 0, 0.7)
	overlay.anchor_left = 0.0; overlay.anchor_top = 0.0
	overlay.anchor_right = 1.0; overlay.anchor_bottom = 1.0
	overlay.mouse_filter = MOUSE_FILTER_STOP
	overlay.gui_input.connect(_on_card_picker_overlay_input.bind(overlay, task_index))
	add_child(overlay)

	var panel = Panel.new()
	panel.name = "CardPickerPanel"
	panel.anchor_left = 0.05; panel.anchor_top = 0.1
	panel.anchor_right = 0.95; panel.anchor_bottom = 0.9
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
	var title_lbl = Label.new()
	title_lbl.text = "选择卡牌提交（共" + str(matching.size()) + "张符合条件）"
	title_lbl.add_theme_font_size_override("font_size", 45)
	title_lbl.add_theme_color_override("font_color", Color("#e8a838"))
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.anchor_left = 0.0; title_lbl.anchor_top = 0.0
	title_lbl.anchor_right = 1.0; title_lbl.anchor_bottom = 0.0
	title_lbl.offset_left = 0; title_lbl.offset_top = Global.ph(0.01)
	title_lbl.offset_right = 0; title_lbl.offset_bottom = Global.ph(0.08)
	panel.add_child(title_lbl)

	# 关闭按钮
	var close_btn = Button.new()
	close_btn.text = ""
	close_btn.add_theme_font_size_override("font_size", 40)
	close_btn.add_theme_color_override("font_color", Color("#ff6666"))
	var cls = StyleBoxFlat.new()
	cls.bg_color = Color.TRANSPARENT
	close_btn.add_theme_stylebox_override("normal", cls)
	close_btn.anchor_left = 1.0; close_btn.anchor_top = 0.0
	close_btn.anchor_right = 1.0; close_btn.anchor_bottom = 0.0
	close_btn.offset_left = Global.pw(-0.1); close_btn.offset_top = Global.ph(0.005)
	close_btn.offset_right = 0; close_btn.offset_bottom = Global.ph(0.075)
	close_btn.pressed.connect(_close_card_picker.bind(overlay))
	panel.add_child(close_btn)

	# 滚动列表
	var scroll = ScrollContainer.new()
	scroll.anchor_left = 0.02; scroll.anchor_top = 0.0
	scroll.anchor_right = 0.98; scroll.anchor_bottom = 1.0
	scroll.offset_left = 0; scroll.offset_top = Global.ph(0.085)
	scroll.offset_right = 0; scroll.offset_bottom = Global.ph(-0.01)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	var list_vbox = VBoxContainer.new()
	list_vbox.name = "CardListVBox"
	list_vbox.size_flags_horizontal = SIZE_FILL
	list_vbox.add_theme_constant_override("separation", Global.ph(0.005))
	scroll.add_child(list_vbox)

	if matching.size() == 0:
		var empty_lbl = Label.new()
		empty_lbl.text = "没有符合条件卡牌"
		empty_lbl.add_theme_font_size_override("font_size", 40)
		empty_lbl.add_theme_color_override("font_color", Color("#888888"))
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.custom_minimum_size = Vector2(0, Global.ph(0.15))
		empty_lbl.size_flags_horizontal = SIZE_FILL
		list_vbox.add_child(empty_lbl)
	else:
		for card in matching:
			var card_row = _make_card_row(card, task_index, overlay)
			list_vbox.add_child(card_row)

func _check_card_for_condition(card: Dictionary, condition: Dictionary) -> bool:
	var cond_type = condition.get("type", "")
	match cond_type:
		"element":
			var card_el = CardManager.get_card_element(card)
			return card_el == condition.get("element", "")
		"cost_range":
			var cost = card.get("cost", card.get("energy_cost", 0))
			return cost >= condition.get("min_cost", 0) and cost <= condition.get("max_cost", 99)
		"atk_min":
			var atk = card.get("atk", card.get("attack", 0))
			return atk >= condition.get("min_atk", 0)
		"quality":
			var card_q = card.get("quality", "")
			var target_q = condition.get("quality", "")
			# 自制卡牌 quality 可能是范围格式，如 "标准 ~ 卓越"
			if card_q.find(" ~ ") != -1:
				var parts = card_q.split(" ~ ")
				var lower_q = parts[0].strip_edges()
				var upper_q = parts[1].strip_edges()
				var q_order = ["废品", "瑕疵", "标准", "卓越", "完美"]
				var target_idx = q_order.find(target_q)
				var lower_idx = q_order.find(lower_q)
				var upper_idx = q_order.find(upper_q)
				if target_idx != -1 and lower_idx != -1 and upper_idx != -1:
					return target_idx >= lower_idx and target_idx <= upper_idx
			return card_q == target_q
		"effect_keyword":
			var keyword = condition.get("keyword", "")
			# 从纹路组件数据中，找所有 name 包含关键词的组件 ID
			var matched_ids := []
			var all_components = []
			all_components.append_array(Global.circuit_actions)
			all_components.append_array(Global.circuit_triggers)
			for comp in all_components:
				if comp.get("name", "").find(keyword) != -1:
					matched_ids.append(comp.get("id", ""))
			var effects = card.get("effects", [])
			for eff in effects:
				# 1. 检查 desc 文本（老卡兼容，如"入场：抽1张牌"）
				var desc = ""
				if eff is String: desc = eff
				elif eff is Dictionary: desc = eff.get("desc", "")
				if desc.find(keyword) != -1:
					return true
				# 2. 检查效果字段是否匹配纹路组件 ID（基于纹路数据，不受 desc 文本格式影响）
				if eff is Dictionary and matched_ids.size() > 0:
					for key in ["action", "trigger"]:
						if matched_ids.has(eff.get(key, "")):
							return true
			return false
	return true

# 品质范围转显示用品质（取范围上限，如"标准 ~ 卓越"→"卓越"）
func _get_quality_display(quality: String) -> String:
	if quality.find(" ~ ") != -1:
		var parts = quality.split(" ~ ")
		return parts[1].strip_edges()
	return quality

func _make_card_row(card: Dictionary, task_index: int, overlay: ColorRect) -> Panel:
	var row = Panel.new()
	var rs = StyleBoxFlat.new()
	rs.bg_color = Global.current.topbar_bg
	rs.corner_radius_top_left = 6; rs.corner_radius_top_right = 6
	rs.corner_radius_bottom_left = 6; rs.corner_radius_bottom_right = 6
	row.add_theme_stylebox_override("panel", rs)
	row.custom_minimum_size = Vector2(0, Global.ph(0.1))
	row.size_flags_horizontal = SIZE_FILL

	var hbox = HBoxContainer.new()
	hbox.size_flags_horizontal = SIZE_FILL
	row.add_child(hbox)

	var card_name = card.get("name", card.get("card_name", "未知卡牌"))
	var card_quality = _get_quality_display(card.get("quality", "标准"))
	var card_element = CardManager.get_card_element(card)
	var card_cost = card.get("cost", card.get("energy_cost", 0))
	var card_atk = card.get("atk", card.get("attack", 0))
	var card_hp = card.get("hp", card.get("health", 0))
	var el_icon = ""
	match card_element:
		"火": el_icon = ""
		"水": el_icon = ""
		"风": el_icon = ""
		"地": el_icon = ""
		"光": el_icon = ""
		"暗": el_icon = ""
		_: el_icon = ""

	var quality_color = Color("#95A5A6")
	match card_quality:
		"完美": quality_color = Color("#FFD700")
		"卓越": quality_color = Color("#9B59B6")
		"标准": quality_color = Color("#95A5A6")

	var info_lbl = Label.new()
	info_lbl.text = el_icon + " " + card_name + "  [" + card_quality + "]  " + str(card_cost) + "  " + str(card_atk) + "/" + str(card_hp)
	info_lbl.add_theme_font_size_override("font_size", 35)
	info_lbl.add_theme_color_override("font_color", Global.current.btn_text)
	info_lbl.size_flags_horizontal = SIZE_EXPAND
	info_lbl.mouse_filter = MOUSE_FILTER_STOP
	info_lbl.gui_input.connect(_on_card_picker_row_input.bind(card, row))
	hbox.add_child(info_lbl)

	var select_btn = Button.new()
	select_btn.text = "选择"
	select_btn.add_theme_font_size_override("font_size", 35)
	var sbs = StyleBoxFlat.new()
	sbs.bg_color = Color("#3a3a5e")
	sbs.border_width_left = 1; sbs.border_width_right = 1
	sbs.border_width_top = 1; sbs.border_width_bottom = 1
	sbs.border_color = quality_color
	sbs.corner_radius_top_left = 6; sbs.corner_radius_top_right = 6
	sbs.corner_radius_bottom_left = 6; sbs.corner_radius_bottom_right = 6
	select_btn.add_theme_stylebox_override("normal", sbs)
	select_btn.add_theme_color_override("font_color", quality_color)
	select_btn.custom_minimum_size = Vector2(Global.pw(0.12), Global.ph(0.06))
	select_btn.pressed.connect(_do_submit_card.bind(card, task_index, overlay))
	hbox.add_child(select_btn)

	return row

func _on_card_picker_row_input(event: InputEvent, card: Dictionary, row: Panel):
	if event is InputEventScreenTouch:
		if event.pressed:
			_card_picker_timer = 0.0
			_card_picker_card = card
			_card_picker_active = true
		else:
			_card_picker_active = false
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_card_picker_timer = 0.0
			_card_picker_card = card
			_card_picker_active = true
		elif not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_card_picker_active = false

func _show_card_detail_popup(card: Dictionary):
	var overlay = ColorRect.new()
	overlay.name = "CardDetailOverlay"
	overlay.color = Color(0, 0, 0, 0.7)
	overlay.anchor_left = 0.0; overlay.anchor_top = 0.0
	overlay.anchor_right = 1.0; overlay.anchor_bottom = 1.0
	overlay.mouse_filter = MOUSE_FILTER_STOP
	overlay.gui_input.connect(_on_detail_overlay_input.bind(overlay))
	add_child(overlay)

	var panel = Panel.new()
	panel.name = "DetailPanel"
	panel.anchor_left = 0.08; panel.anchor_top = 0.15
	panel.anchor_right = 0.92; panel.anchor_bottom = 0.85
	panel.clip_contents = true
	var card_quality = _get_quality_display(card.get("quality", "标准"))
	var border_color = Color("#95A5A6")
	match card_quality:
		"完美": border_color = Color("#FFD700")
		"卓越": border_color = Color("#9B59B6")
		"标准": border_color = Color("#95A5A6")
	var ps = StyleBoxFlat.new()
	ps.bg_color = Global.current.bg
	ps.border_width_left = 3; ps.border_width_right = 3
	ps.border_width_top = 3; ps.border_width_bottom = 3
	ps.border_color = border_color
	ps.corner_radius_top_left = 16; ps.corner_radius_top_right = 16
	ps.corner_radius_bottom_left = 16; ps.corner_radius_bottom_right = 16
	panel.add_theme_stylebox_override("panel", ps)
	overlay.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.name = "CardDetailVBox"
	vbox.anchor_left = 0.0; vbox.anchor_top = 0.0
	vbox.anchor_right = 1.0; vbox.anchor_bottom = 1.0
	vbox.offset_left = Global.pw(0.04); vbox.offset_top = Global.ph(0.02)
	vbox.offset_right = Global.pw(-0.04); vbox.offset_bottom = Global.ph(-0.02)
	vbox.size_flags_horizontal = SIZE_FILL
	vbox.add_theme_constant_override("separation", Global.ph(0.008))
	panel.add_child(vbox)

	var card_name = card.get("name", card.get("card_name", "未知卡牌"))
	var card_element = CardManager.get_card_element(card)
	var card_quality_str = _get_quality_display(card.get("quality", "标准"))
	var card_cost = card.get("cost", card.get("energy_cost", 0))
	var card_atk = card.get("atk", card.get("attack", 0))
	var card_hp = card.get("hp", card.get("health", 0))
	var card_desc = card.get("desc", card.get("description", ""))
	var card_fields = card.get("fields", [])
	var card_effects = card.get("effects", [])

	var el_icon = ""
	match card_element:
		"火": el_icon = ""
		"水": el_icon = ""
		"风": el_icon = ""
		"地": el_icon = ""
		"光": el_icon = ""
		"暗": el_icon = ""
		_: el_icon = ""

	var name_lbl = Label.new()
	name_lbl.text = el_icon + " " + card_name
	name_lbl.add_theme_font_size_override("font_size", 55)
	name_lbl.add_theme_color_override("font_color", border_color)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_lbl)

	var info_lbl = Label.new()
	info_lbl.text = "【" + card_quality_str + "】 " + card_element + "属性"
	info_lbl.add_theme_font_size_override("font_size", 40)
	info_lbl.add_theme_color_override("font_color", Color("#aaaaaa"))
	info_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(info_lbl)

	var line = HSeparator.new()
	line.add_theme_color_override("color", Global.current.topbar_border)
	vbox.add_child(line)

	var stats_lbl = Label.new()
	stats_lbl.text = "费用：" + str(card_cost) + "    攻击：" + str(card_atk) + "    生命：" + str(card_hp)
	stats_lbl.add_theme_font_size_override("font_size", 40)
	stats_lbl.add_theme_color_override("font_color", Color("#ffffff"))
	vbox.add_child(stats_lbl)

	if card_fields.size() > 0:
		var fields_lbl = Label.new()
		fields_lbl.text = "字段：" + "、".join(card_fields)
		fields_lbl.add_theme_font_size_override("font_size", 40)
		fields_lbl.add_theme_color_override("font_color", Color("#e8a838"))
		fields_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(fields_lbl)

	if card_desc != "":
		var desc_lbl = Label.new()
		desc_lbl.text = "" + card_desc
		desc_lbl.add_theme_font_size_override("font_size", 40)
		desc_lbl.add_theme_color_override("font_color", Color("#cccccc"))
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(desc_lbl)

	if card_effects.size() > 0:
		var eff_title = Label.new()
		eff_title.text = "效果："
		eff_title.add_theme_font_size_override("font_size", 40)
		eff_title.add_theme_color_override("font_color", Color("#f0c040"))
		vbox.add_child(eff_title)
		for eff in card_effects:
			var eff_desc = ""
			if eff is String: eff_desc = eff
			elif eff is Dictionary: eff_desc = eff.get("desc", "")
			if eff_desc != "":
				var eff_lbl = Label.new()
				eff_lbl.text = "• " + eff_desc
				eff_lbl.add_theme_font_size_override("font_size", 35)
				eff_lbl.add_theme_color_override("font_color", Color("#dddddd"))
				eff_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				vbox.add_child(eff_lbl)
	# 辅材
	var aux_items = card.get("aux_items", [])
	if aux_items.size() > 0:
		var aux_title = Label.new()
		aux_title.text = "辅材："
		aux_title.add_theme_font_size_override("font_size", 40)
		aux_title.add_theme_color_override("font_color", Color("#4fc3f7"))
		vbox.add_child(aux_title)
		for aux in aux_items:
			var aux_name = aux.get("name", "未知辅材")
			var aux_eff = _describe_aux_effect(aux)
			var aux_lbl = Label.new()
			aux_lbl.text = "• " + aux_name + ((" " + aux_eff) if aux_eff != "" else "")
			aux_lbl.add_theme_font_size_override("font_size", 35)
			aux_lbl.add_theme_color_override("font_color", Color("#b0d4f1"))
			aux_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			vbox.add_child(aux_lbl)

	var spacer = Control.new()
	spacer.size_flags_vertical = SIZE_EXPAND
	vbox.add_child(spacer)

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
	close_btn.size_flags_horizontal = SIZE_FILL
	close_btn.custom_minimum_size = Vector2(0, Global.ph(0.07))
	close_btn.pressed.connect(_close_detail.bind(overlay))
	vbox.add_child(close_btn)

func _do_submit_card(card: Dictionary, task_index: int, overlay: ColorRect):
	_close_card_picker(overlay)
	var result = GuildTaskManager.submit_with_card(task_index, card)
	if result["success"]:
		_show_message(" " + result["message"], Color("#44cc44"))
		_refresh_ui()
	else:
		_show_message(" " + result["message"], Color("#ff6666"))

func _close_card_picker(overlay: ColorRect):
	if overlay and is_instance_valid(overlay):
		overlay.queue_free()

func _on_card_picker_overlay_input(event: InputEvent, overlay: ColorRect, task_index: int):
	var pressed = false
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed = true
	if event is InputEventScreenTouch and event.pressed:
		pressed = true
	if pressed:
		var panel = overlay.get_node_or_null("CardPickerPanel")
		if panel:
			var mouse_pos = overlay.get_local_mouse_position()
			var panel_rect = Rect2(panel.position, panel.size)
			if not panel_rect.has_point(mouse_pos):
				_close_card_picker(overlay)

func _show_message(msg: String, msg_color: Color = Color("#ffffff")) -> void:
	# 简单的消息提示
	var toast = Label.new()
	toast.text = msg
	toast.add_theme_font_size_override("font_size", 30)
	toast.add_theme_color_override("font_color", msg_color)
	toast.add_theme_color_override("font_shadow_color", Color("#000000"))
	toast.add_theme_constant_override("shadow_offset_x", 2)
	toast.add_theme_constant_override("shadow_offset_y", 2)
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	toast.anchor_left = 0.0; toast.anchor_top = 0.0; toast.anchor_right = 1.0; toast.anchor_bottom = 1.0
	toast.offset_left = Global.pw(0.1); toast.offset_top = Global.ph(0.4)
	toast.offset_right = Global.pw(-0.1); toast.offset_bottom = Global.ph(0.5)
	toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(toast)
	var timer = get_tree().create_timer(2.0)
	timer.timeout.connect(func(): if is_instance_valid(toast): toast.queue_free())

# ==================== 广告刷新任务回调 ====================

func _on_ad_refresh_pressed():
	if _hj_ads == null:
		if _ad_status_label:
			_ad_status_label.text = "广告未初始化"
			_ad_status_label.add_theme_color_override("font_color", Color("#FF5252"))
		return
	
	if _hj_ads.isRewardedAdReady():
		if _ad_status_label:
			_ad_status_label.text = "▶ 播放广告中..."
			_ad_status_label.add_theme_color_override("font_color", Color("#FFD700"))
		_hj_ads.showRewardedAd()
	else:
		if _ad_status_label:
			_ad_status_label.text = "⏳ 广告未就绪，重新加载中..."
			_ad_status_label.add_theme_color_override("font_color", Color("#FFD700"))
		_hj_ads.loadRewardedAd()
		_show_message("广告正在加载，请稍后点击", Color("#FF5252"))
func _on_video_rewarded_refresh(rewarded: bool):
	if not rewarded:
		if _ad_status_label:
			_ad_status_label.text = "⏳ 广告未完整播放，无奖励"
			_ad_status_label.add_theme_color_override("font_color", Color("#FF5252"))
		_show_message("广告未完整播放，下次请看完哦", Color("#FF5252"))
		return
	
	# 广告完整播放！刷新任务
	if _ad_status_label:
		_ad_status_label.text = "广告播放成功，任务刷新中..."
		_ad_status_label.add_theme_color_override("font_color", Color("#4CAF50"))
	GuildTaskManager.refresh_tasks()
	_show_message(" 看广告成功！任务已刷新", Color("#44cc44"))

func _on_ad_closed_refresh(result: String):
	if _ad_status_label:
		_ad_status_label.text = "广告已关闭，可再次观看"
		_ad_status_label.add_theme_color_override("font_color", Color("#4CAF50"))
	await get_tree().create_timer(1.0).timeout
	_hj_ads.loadRewardedAd()
	if _ad_status_label:
		_ad_status_label.text = "⏳ 加载下一个广告..."
		_ad_status_label.add_theme_color_override("font_color", Color("#FFD700"))

func _on_ad_loaded_refresh(placement_id: String):
	if _ad_status_label:
		_ad_status_label.text = "广告已就绪，点击观看"
		_ad_status_label.add_theme_color_override("font_color", Color("#4CAF50"))
func _on_ad_failed_refresh(error_msg: String):
	if _ad_status_label:
		_ad_status_label.text = "广告加载失败"
		_ad_status_label.add_theme_color_override("font_color", Color("#FF5252"))

func _on_tasks_refreshed(new_tasks: Array) -> void:
	_refresh_ui()

func _on_task_completed(task_index: int) -> void:
	_refresh_ui()

func _on_back():
	Global.play_sfx("click")
	Global.change_scene("res://Guild.tscn")

func _on_daily_task_pressed():
	Global.change_scene("res://DailyTasks.tscn")

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
	if effect.has("field_sync"):
		parts.append("场地同步")
	return "[" + " ".join(parts) + "]"
