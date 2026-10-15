extends Control
## ============================================================
##  每日任务 —— 每日阶梯任务界面（静态化）
##  包含决斗场/杀敌/通关地图/制卡 四个阶梯
## ============================================================

var _hj_ads: HJAdsNode = null
var _pending_reset_key: String = ""
var _ad_status_label: Label = null
var _ad_reset_btn: Button = null
var _last_applied_mode = null

func _ready():
	# ---- 静态界面节点已在 DailyTasks.tscn 中声明 ----
	var back := get_node_or_null("BackBtn")
	if back is Button:
		back.pressed.connect(_on_back)

	# 主题
	Global.theme_changed.connect(_on_theme_changed)
	call_deferred("_apply_theme_styles")

	# ===== 每日阶梯任务（动态生成）=====
	var ladder_y = 0.12
	_add_daily_ladder_card(ladder_y, "⚔ 决斗场", PlayerManager.get_current_duel_ladder_step(), PlayerManager.get_daily_duel_wins(), PlayerManager.DAILY_DUEL_LADDER, PlayerManager.DAILY_DUEL_REWARDS, Color("#FF6B6B"), "duel")
	_add_daily_ladder_card(ladder_y + 0.16, "💀 杀敌", PlayerManager.get_kill_step(), PlayerManager.get_kill_count(), PlayerManager.DAILY_LADDER, PlayerManager.DAILY_LADDER_REWARDS, Color("#FF9800"), "kill")
	_add_daily_ladder_card(ladder_y + 0.32, "🗺️ 通关地图", PlayerManager.get_map_clear_step(), PlayerManager.get_map_clear_count(), PlayerManager.DAILY_LADDER, PlayerManager.DAILY_LADDER_REWARDS, Color("#4FC3F7"), "map_clear")
	_add_daily_ladder_card(ladder_y + 0.48, "🃏 制卡", PlayerManager.get_craft_step(), PlayerManager.get_craft_count(), PlayerManager.DAILY_LADDER, PlayerManager.DAILY_LADDER_REWARDS, Color("#81C784"), "craft")

	PlayerManager.ladder_step_completed.connect(func(label: String, step: int, reward: int, target: int):
		Global.show_global_toast("🎉 " + label + " 第" + str(step) + "阶完成！+" + str(reward) + "金币", Color("#FFD700"))
	)

	# ===== 初始化广告 =====
	_hj_ads = HJAdsNode.new()
	_hj_ads.name = "DailyLadderHJAds"
	add_child(_hj_ads)
	_hj_ads.app_id = "234475"
	_hj_ads.rewarded_placement_id = "9701263723893953"
	_hj_ads.debug_mode = false

	_hj_ads.ad_loaded.connect(_on_ladder_ad_loaded)
	_hj_ads.video_rewarded.connect(_on_ladder_ad_rewarded)
	_hj_ads.ad_closed.connect(_on_ladder_ad_closed)
	_hj_ads.ad_failed.connect(_on_ladder_ad_failed)

	await get_tree().process_frame
	_hj_ads.init()
	_hj_ads.loadRewardedAd()

	# 广告状态条
	var ad_bar = Panel.new()
	ad_bar.name = "LadderAdBar"
	ad_bar.anchor_left = 0.1; ad_bar.anchor_top = ladder_y + 0.64 + 0.005; ad_bar.anchor_right = 0.9; ad_bar.anchor_bottom = ladder_y + 0.64 + 0.055
	var ads = StyleBoxFlat.new()
	ads.bg_color = Global.current.bg
	ads.border_width_left = 2; ads.border_width_right = 2
	ads.border_width_top = 2; ads.border_width_bottom = 2
	ads.border_color = Color("#FF6B6B")
	ads.corner_radius_top_left = 8; ads.corner_radius_top_right = 8
	ads.corner_radius_bottom_left = 8; ads.corner_radius_bottom_right = 8
	ad_bar.add_theme_stylebox_override("panel", ads)
	add_child(ad_bar)

	_ad_reset_btn = Button.new()
	_ad_reset_btn.text = "🔄 看广告重置全部"
	_ad_reset_btn.add_theme_font_size_override("font_size", 35)
	var abs = StyleBoxFlat.new()
	abs.bg_color = Color("#FF6B6B")
	abs.border_width_left = 2; abs.border_width_right = 2
	abs.border_width_top = 2; abs.border_width_bottom = 2
	abs.border_color = Color("#FF5252")
	abs.corner_radius_top_left = 6; abs.corner_radius_top_right = 6
	abs.corner_radius_bottom_left = 6; abs.corner_radius_bottom_right = 6
	_ad_reset_btn.add_theme_stylebox_override("normal", abs)
	_ad_reset_btn.add_theme_color_override("font_color", Color("#ffffff"))
	_ad_reset_btn.anchor_left = 0.0; _ad_reset_btn.anchor_top = 0.0; _ad_reset_btn.anchor_right = 0.5; _ad_reset_btn.anchor_bottom = 1.0
	_ad_reset_btn.offset_left = Global.pw(0.02); _ad_reset_btn.offset_top = Global.ph(0.005)
	_ad_reset_btn.offset_right = Global.pw(-0.01); _ad_reset_btn.offset_bottom = Global.ph(-0.005)
	_ad_reset_btn.pressed.connect(_on_ladder_ad_pressed)
	ad_bar.add_child(_ad_reset_btn)

	_ad_status_label = Label.new()
	_ad_status_label.text = "⏳ 加载广告..."
	_ad_status_label.add_theme_font_size_override("font_size", 30)
	_ad_status_label.add_theme_color_override("font_color", Color("#aaaaaa"))
	_ad_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ad_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_ad_status_label.anchor_left = 0.5; _ad_status_label.anchor_top = 0.0; _ad_status_label.anchor_right = 1.0; _ad_status_label.anchor_bottom = 1.0
	_ad_status_label.offset_left = Global.pw(0.01); _ad_status_label.offset_top = 0
	_ad_status_label.offset_right = Global.pw(-0.02); _ad_status_label.offset_bottom = 0
	ad_bar.add_child(_ad_status_label)

func _on_theme_changed(mode = null):
	_apply_theme_styles()

func _apply_theme_styles():
	var mode = Global.current_mode
	var is_day = mode == Global.ThemeMode.DAY
	# 背景颜色
	var bg = get_node_or_null("Background")
	Global.apply_bg(bg)
	# 顶栏/底栏
	for n in ["TopBar","BottomBar"]:
		var r = get_node_or_null(n)
		if r is ColorRect: r.color = Global.current.topbar_bg
	for n in ["TopBarLine","BottomBarLine"]:
		var r = get_node_or_null(n)
		if r is ColorRect: r.color = Global.current.topbar_border
	# 标题
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
	var btn = get_node_or_null("BackBtn")
	if btn is Button:
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

func _on_back():
	Global.play_sfx("click")
	Global.change_scene("res://GuildTasks.tscn")

# ============================
#  每日阶梯任务卡片（通用）
# ============================
func _add_daily_ladder_card(top_y: float, label: String, step: int, count: int, ladder: Array, rewards: Array, color: Color, reset_key: String = ""):
	var panel = Panel.new()
	panel.name = "DailyLadder_" + label
	panel.anchor_left = 0.1; panel.anchor_top = top_y; panel.anchor_right = 0.9; panel.anchor_bottom = top_y + 0.14
	var ps = StyleBoxFlat.new()
	ps.bg_color = Global.current.bg
	ps.border_width_left = 2; ps.border_width_right = 2
	ps.border_width_top = 2; ps.border_width_bottom = 2
	ps.border_color = color if step >= 0 else Color("#555555")
	ps.corner_radius_top_left = 12; ps.corner_radius_top_right = 12
	ps.corner_radius_bottom_left = 12; ps.corner_radius_bottom_right = 12
	panel.add_theme_stylebox_override("panel", ps)
	add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.anchor_left = 0.0; vbox.anchor_top = 0.0
	vbox.anchor_right = 1.0; vbox.anchor_bottom = 1.0
	vbox.offset_left = Global.pw(0.03); vbox.offset_top = Global.ph(0.003)
	vbox.offset_right = Global.pw(-0.03); vbox.offset_bottom = Global.ph(-0.003)
	vbox.add_theme_constant_override("separation", 1)
	panel.add_child(vbox)

	var title_row = HBoxContainer.new()
	title_row.size_flags_horizontal = SIZE_FILL
	vbox.add_child(title_row)

	var title = Label.new()
	if step < 0:
		title.text = "🎉 " + label + " — 全部完成！"
	else:
		title.text = label
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", color if step >= 0 else Color("#44cc44"))
	title.size_flags_horizontal = SIZE_EXPAND
	title_row.add_child(title)

	var count_label = Label.new()
	count_label.text = str(count) + " 次"
	count_label.add_theme_font_size_override("font_size", 40)
	count_label.add_theme_color_override("font_color", Color("#FFD700"))
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	title_row.add_child(count_label)

	if step >= 0:
		var target = ladder[step]
		var reward = rewards[step]

		var bar_bg = ColorRect.new()
		bar_bg.color = Color("#333333")
		bar_bg.custom_minimum_size = Vector2(0, Global.ph(0.02))
		bar_bg.size_flags_horizontal = SIZE_FILL
		vbox.add_child(bar_bg)

		var bar_fill = ColorRect.new()
		bar_fill.color = color
		var ratio = float(count) / float(target)
		bar_fill.anchor_left = 0.0; bar_fill.anchor_top = 0.0
		bar_fill.anchor_right = min(ratio, 1.0); bar_fill.anchor_bottom = 1.0
		bar_bg.add_child(bar_fill)

		var target_row = HBoxContainer.new()
		target_row.size_flags_horizontal = SIZE_FILL
		vbox.add_child(target_row)

		var target_label = Label.new()
		target_label.text = "目标：" + str(target) + " 次"
		target_label.add_theme_font_size_override("font_size", 35)
		target_label.add_theme_color_override("font_color", Global.current.btn_text)
		target_label.size_flags_horizontal = SIZE_EXPAND
		target_row.add_child(target_label)

		var reward_label = Label.new()
		reward_label.text = "🏆 +" + str(reward) + "金币"
		reward_label.add_theme_font_size_override("font_size", 35)
		reward_label.add_theme_color_override("font_color", Color("#FFD700"))
		reward_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		target_row.add_child(reward_label)

		if reset_key != "":
			var reset_btn = Button.new()
			reset_btn.text = "🔄 重置"
			reset_btn.add_theme_font_size_override("font_size", 28)
			var rbs = StyleBoxFlat.new()
			rbs.bg_color = color
			rbs.border_width_left = 1; rbs.border_width_right = 1
			rbs.border_width_top = 1; rbs.border_width_bottom = 1
			rbs.border_color = Color("#ffffff44")
			rbs.corner_radius_top_left = 4; rbs.corner_radius_top_right = 4
			rbs.corner_radius_bottom_left = 4; rbs.corner_radius_bottom_right = 4
			reset_btn.add_theme_stylebox_override("normal", rbs)
			reset_btn.add_theme_color_override("font_color", Color("#ffffff"))
			reset_btn.custom_minimum_size = Vector2(Global.pw(0.12), Global.ph(0.025))
			reset_btn.size_flags_horizontal = SIZE_SHRINK_END
			reset_btn.pressed.connect(_on_ladder_reset_pressed.bind(reset_key))
			target_row.add_child(reset_btn)

	if step >= 0:
		var dot_row = HBoxContainer.new()
		dot_row.size_flags_horizontal = SIZE_FILL
		dot_row.alignment = BoxContainer.ALIGNMENT_CENTER
		vbox.add_child(dot_row)

		for i in range(ladder.size()):
			var dot = Label.new()
			if i < step:
				dot.text = "●"
				dot.add_theme_color_override("font_color", Color("#44cc44"))
			elif i == step:
				dot.text = "●"
				dot.add_theme_color_override("font_color", color)
			else:
				dot.text = "○"
				dot.add_theme_color_override("font_color", Color("#555555"))
			dot.add_theme_font_size_override("font_size", 24)
			dot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			dot.custom_minimum_size = Vector2(Global.pw(0.05), 0)
			dot_row.add_child(dot)

# ============================
# 广告回调：看广告重置阶梯
# ============================
func _on_ladder_reset_pressed(reset_key: String) -> void:
	Global.play_sfx("click")
	if _hj_ads == null:
		if _ad_status_label:
			_ad_status_label.text = "⚠ 广告未初始化"
			_ad_status_label.add_theme_color_override("font_color", Color("#FF5252"))
		return

	if _hj_ads.isRewardedAdReady():
		_pending_reset_key = reset_key
		if _ad_status_label:
			_ad_status_label.text = "▶️ 播放广告中..."
			_ad_status_label.add_theme_color_override("font_color", Color("#FFD700"))
		_hj_ads.showRewardedAd()
	else:
		if _ad_status_label:
			_ad_status_label.text = "⏳ 广告未就绪，重新加载中..."
			_ad_status_label.add_theme_color_override("font_color", Color("#FFD700"))
		_hj_ads.loadRewardedAd()
		_show_message("广告正在加载，请稍后点击", Color("#FF5252"))

func _on_ladder_ad_pressed() -> void:
	Global.play_sfx("click")
	if _hj_ads == null:
		if _ad_status_label:
			_ad_status_label.text = "⚠ 广告未初始化"
			_ad_status_label.add_theme_color_override("font_color", Color("#FF5252"))
		return

	if _hj_ads.isRewardedAdReady():
		_pending_reset_key = "all"
		if _ad_status_label:
			_ad_status_label.text = "▶️ 播放广告中..."
			_ad_status_label.add_theme_color_override("font_color", Color("#FFD700"))
		_hj_ads.showRewardedAd()
	else:
		if _ad_status_label:
			_ad_status_label.text = "⏳ 广告未就绪，重新加载中..."
			_ad_status_label.add_theme_color_override("font_color", Color("#FFD700"))
		_hj_ads.loadRewardedAd()
		_show_message("广告正在加载，请稍后点击", Color("#FF5252"))

func _on_ladder_ad_rewarded(rewarded: bool) -> void:
	if not rewarded:
		if _ad_status_label:
			_ad_status_label.text = "⏳ 广告未完整播放，无奖励"
			_ad_status_label.add_theme_color_override("font_color", Color("#FF5252"))
		_show_message("广告未完整播放，下次请看完哦", Color("#FF5252"))
		_pending_reset_key = ""
		return

	if _pending_reset_key == "all":
		PlayerManager.reset_duel_ladder()
		PlayerManager.reset_daily_ladder("kill")
		PlayerManager.reset_daily_ladder("map_clear")
		PlayerManager.reset_daily_ladder("craft")
		_show_message("✅ 所有每日阶梯已重置！", Color("#44cc44"))
	elif _pending_reset_key == "duel":
		PlayerManager.reset_duel_ladder()
		_show_message("✅ 决斗场阶梯已重置！", Color("#44cc44"))
	elif _pending_reset_key != "":
		PlayerManager.reset_daily_ladder(_pending_reset_key)
		_show_message("✅ " + _pending_reset_key + " 阶梯已重置！", Color("#44cc44"))

	_pending_reset_key = ""

	if _ad_status_label:
		_ad_status_label.text = "✅ 重置成功！"
		_ad_status_label.add_theme_color_override("font_color", Color("#4CAF50"))

	_refresh_ladder_ui()

func _refresh_ladder_ui() -> void:
	for child in get_children():
		if child.name.begins_with("DailyLadder_"):
			child.queue_free()
	var ladder_y = 0.12
	_add_daily_ladder_card(ladder_y, "⚔ 决斗场", PlayerManager.get_current_duel_ladder_step(), PlayerManager.get_daily_duel_wins(), PlayerManager.DAILY_DUEL_LADDER, PlayerManager.DAILY_DUEL_REWARDS, Color("#FF6B6B"), "duel")
	_add_daily_ladder_card(ladder_y + 0.16, "💀 杀敌", PlayerManager.get_kill_step(), PlayerManager.get_kill_count(), PlayerManager.DAILY_LADDER, PlayerManager.DAILY_LADDER_REWARDS, Color("#FF9800"), "kill")
	_add_daily_ladder_card(ladder_y + 0.32, "🗺️ 通关地图", PlayerManager.get_map_clear_step(), PlayerManager.get_map_clear_count(), PlayerManager.DAILY_LADDER, PlayerManager.DAILY_LADDER_REWARDS, Color("#4FC3F7"), "map_clear")
	_add_daily_ladder_card(ladder_y + 0.48, "🃏 制卡", PlayerManager.get_craft_step(), PlayerManager.get_craft_count(), PlayerManager.DAILY_LADDER, PlayerManager.DAILY_LADDER_REWARDS, Color("#81C784"), "craft")

func _on_ladder_ad_closed(result: String) -> void:
	if _ad_status_label:
		_ad_status_label.text = "✅ 广告已关闭，可再次观看"
		_ad_status_label.add_theme_color_override("font_color", Color("#4CAF50"))
	await get_tree().create_timer(1.0).timeout
	_hj_ads.loadRewardedAd()
	if _ad_status_label:
		_ad_status_label.text = "⏳ 加载下一个广告..."
		_ad_status_label.add_theme_color_override("font_color", Color("#FFD700"))

func _on_ladder_ad_loaded(placement_id: String) -> void:
	if _ad_status_label:
		_ad_status_label.text = "✅ 广告已就绪，点击观看"
		_ad_status_label.add_theme_color_override("font_color", Color("#4CAF50"))

func _on_ladder_ad_failed(error_msg: String) -> void:
	if _ad_status_label:
		_ad_status_label.text = "⚠ 广告加载失败"
		_ad_status_label.add_theme_color_override("font_color", Color("#FF5252"))

func _show_message(text: String, color: Color) -> void:
	var msg = Label.new()
	msg.text = text
	msg.add_theme_font_size_override("font_size", 30)
	msg.add_theme_color_override("font_color", color)
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	msg.anchor_left = 0.0; msg.anchor_top = 0.0; msg.anchor_right = 1.0; msg.anchor_bottom = 1.0
	msg.offset_top = Global.ph(0.8)
	msg.offset_bottom = Global.ph(0.85)
	add_child(msg)
	await get_tree().create_timer(2.0).timeout
	msg.queue_free()