extends ThemedControl

func _ready():
	super._ready()
	var back := get_node_or_null("BackBtn")
	if back is Button:
		back.pressed.connect(_on_back)
	_connect_setting_btn("BtnToggle", "toggle")
	_connect_setting_btn("BtnReset", "reset")
	_connect_setting_btn("BtnExit", "exit")
	_connect_setting_btn("BtnDebug", "debug")
	_connect_setting_btn("BtnBattleMode", "battle_mode")
	_refresh_battle_mode_btn()
	_refresh_toggle_btn_text()

func _connect_setting_btn(node_name: String, action: String) -> void:
	var btn := get_node_or_null(node_name)
	if btn is Button:
		btn.pressed.connect(_on_setting_pressed.bind(action))
func _refresh_battle_mode_btn() -> void:
	var btn := get_node_or_null("BtnBattleMode")
	if btn is Button:
		if Global.use_legacy_battle:
			btn.text = "战斗:竖屏"
		else:
			btn.text = "战斗:横屏"

func _refresh_toggle_btn_text() -> void:
	for child in get_children():
		if child is Button:
			if child.text.contains("夜间模式") or child.text.contains("白天模式"):
				if Global.current_mode == Global.ThemeMode.NIGHT:
					child.text = "切换为白天模式"
				else:
					child.text = "切换为夜间模式"
				break


func _get_bar_names() -> Array:
	return ["TopBar"]

func _get_bar_line_names() -> Array:
	return ["TopBarLine"]

func _apply_theme_custom():
	var mode = Global.current_mode
	var is_day = mode == Global.ThemeMode.DAY
	var icon_c = Color("#645C50") if is_day else Color("#CBCBE0")
	var btn_bg = Color(0.15, 0.13, 0.20, 0.85) if not is_day else Color(0.90, 0.85, 0.75, 0.85)
	var btn_bg_hover = btn_bg.lightened(0.12)
	var btn_bg_pressed = btn_bg.darkened(0.15)
	var border_c = Color("#E8A838") if not is_day else Color("#946F38")
	for child in get_children():
		if not child is Button:
			continue
		child.add_theme_color_override("font_color", icon_c)
		child.add_theme_color_override("font_hover_color", icon_c.lightened(0.15))
		child.add_theme_color_override("font_pressed_color", icon_c.darkened(0.2))
		for state in ["normal", "hover", "pressed"]:
			var sb = StyleBoxFlat.new()
			sb.bg_color = btn_bg_hover if state == "hover" else (btn_bg_pressed if state == "pressed" else btn_bg)
			sb.border_width_left = 2; sb.border_width_right = 2
			sb.border_width_top = 2; sb.border_width_bottom = 2
			sb.border_color = border_c
			sb.corner_radius_top_left = 12; sb.corner_radius_top_right = 12
			sb.corner_radius_bottom_left = 12; sb.corner_radius_bottom_right = 12
			sb.content_margin_left = 16; sb.content_margin_right = 16
			sb.content_margin_top = 8; sb.content_margin_bottom = 8
			child.add_theme_stylebox_override(state, sb)
	_refresh_toggle_btn_text()


func _on_setting_pressed(action: String):
	Global.play_sfx("click")
	match action:
		"toggle":
			Global.toggle_theme()
			# _refresh_toggle_btn_text 会在 _on_theme_changed 里自动调用
		# "pvp":
		# 	print("[设置] 进入PvP对战...")
		# 	Global.change_scene("res://MatchmakingScene.tscn") # 已注释：PvP对战功能移除过审
		"battle_mode":
			Global.use_legacy_battle = not Global.use_legacy_battle
			Global._save_battle_mode()
			_refresh_battle_mode_btn()
			print("[设置] 战斗界面切换为:", "竖屏2D" if Global.use_legacy_battle else "横屏3D")
		"reset":
			print("[设置] 重置游戏...")
			_confirm_reset()
		"exit":
			get_tree().quit()
		"debug":
			print("[设置] 调试模式...")
			_show_debug_password()


func _confirm_reset() -> void:
	# 创建确认弹窗
	var overlay = ColorRect.new()
	overlay.name = "ResetOverlay"
	overlay.color = Color(0.0, 0.0, 0.0, 0.7)
	overlay.anchor_left = 0.0; overlay.anchor_top = 0.0
	overlay.anchor_right = 1.0; overlay.anchor_bottom = 1.0
	overlay.mouse_filter = MOUSE_FILTER_STOP
	add_child(overlay)
	
	var panel = Panel.new()
	panel.name = "ResetPanel"
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
	
	# 提示文字
	var msg = Label.new()
	msg.text = "⚠️ 确定要重置游戏吗？\n\n所有数据将被清除，\n并恢复为初始状态。"
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	msg.add_theme_font_size_override("font_size", 50)
	msg.add_theme_color_override("font_color", Color("#ffffff"))
	msg.anchor_left = 0.0; msg.anchor_top = 0.0
	msg.anchor_right = 1.0; msg.anchor_bottom = 1.0
	msg.offset_left = Global.pw(0.05)
	msg.offset_top = Global.ph(0.02)
	msg.offset_right = Global.pw(-0.05)
	msg.offset_bottom = Global.ph(-0.15)
	panel.add_child(msg)
	
	# 按钮横排
	var btn_hbox = HBoxContainer.new()
	btn_hbox.anchor_left = 0.0; btn_hbox.anchor_top = 1.0
	btn_hbox.anchor_right = 1.0; btn_hbox.anchor_bottom = 1.0
	btn_hbox.offset_left = Global.pw(0.05)
	btn_hbox.offset_top = Global.ph(-0.12)
	btn_hbox.offset_right = Global.pw(-0.05)
	btn_hbox.offset_bottom = Global.ph(-0.02)
	btn_hbox.add_theme_constant_override("separation", 20)
	panel.add_child(btn_hbox)
	
	# 取消按钮
	var cancel_btn = Button.new()
	cancel_btn.text = "取消"
	cancel_btn.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	cancel_btn.custom_minimum_size = Vector2(0, Global.ph(0.06))
	cancel_btn.add_theme_font_size_override("font_size", 45)
	var cs = StyleBoxFlat.new()
	cs.bg_color = Global.current.btn_bg
	cs.border_width_left = 2; cs.border_width_right = 2; cs.border_width_top = 2; cs.border_width_bottom = 2
	cs.border_color = Color("#888888")
	cs.corner_radius_top_left = 10; cs.corner_radius_top_right = 10
	cs.corner_radius_bottom_left = 10; cs.corner_radius_bottom_right = 10
	cancel_btn.add_theme_stylebox_override("normal", cs)
	cancel_btn.add_theme_color_override("font_color", Global.current.btn_text)
	cancel_btn.pressed.connect(_do_reset_cancel.bind(overlay))
	btn_hbox.add_child(cancel_btn)
	
	# 确认按钮
	var confirm_btn = Button.new()
	confirm_btn.text = "确认重置"
	confirm_btn.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	confirm_btn.custom_minimum_size = Vector2(0, Global.ph(0.06))
	confirm_btn.add_theme_font_size_override("font_size", 45)
	var cs2 = StyleBoxFlat.new()
	cs2.bg_color = Color("#c0392b")
	cs2.border_width_left = 2; cs2.border_width_right = 2; cs2.border_width_top = 2; cs2.border_width_bottom = 2
	cs2.border_color = Color("#e74c3c")
	cs2.corner_radius_top_left = 10; cs2.corner_radius_top_right = 10
	cs2.corner_radius_bottom_left = 10; cs2.corner_radius_bottom_right = 10
	confirm_btn.add_theme_stylebox_override("normal", cs2)
	confirm_btn.add_theme_color_override("font_color", Color("#ffffff"))
	confirm_btn.pressed.connect(_do_reset_confirm.bind(overlay))
	btn_hbox.add_child(confirm_btn)


func _do_reset_confirm(overlay: ColorRect) -> void:
	Global.play_sfx("click")
	print("[设置] 执行重置游戏...")
	print("[重置] 🔥 彻底清除所有存档数据...")
	
	# ====== 0. 清理交易服务器数据（已注释：卡牌交易功能已移除过审） ======
	# await Global.cleanup_trade_data()
	
	# ====== 1. 清空所有内存数据 ======
	# 清空SaveManager内存
	SaveManager.save_data = {}
	# 重置PlayerManager数据（用默认初始值）
	PlayerManager.reset_data()
	# 重置纹路解锁到初始状态
	CircuitManager.reset_unlocks()
	# 重置仓库数据（清空素材/卡基/卡墨/辅材）
	SaveManager.set_value("warehouse", "materials", {})
	SaveManager.set_value("warehouse", "card_bases", {})
	SaveManager.set_value("warehouse", "ink_inventory", [])
	SaveManager.set_value("warehouse", "aux_items", {})
	# 重置公会任务（清空 PlayerManager 的数据 + 清空 GuildTaskManager 内存）
	PlayerManager.set_data("guild_tasks", "data", null)
	GuildTaskManager.reset_tasks()
	# 立即刷新生成全新任务（基于重置后的初始公会等级Lv.1）
	GuildTaskManager.refresh_tasks()
	# 重置主题模式为初始默认（夜间）
	Global.current_mode = Global.ThemeMode.NIGHT
	# 恢复默认主题
	Global.theme_changed.emit(Global.current_mode)
	# 重置CardManager的导入标记（允许重新导入新手卡组）
	CardManager.reset_starter_import_flag()
	
	# ====== 2. 重新导入新手卡组（从 starter_data.json） ======
	var file = FileAccess.open("res://starter_data.json", FileAccess.READ)
	if file:
		var json_str = file.get_as_text()
		file.close()
		var json = JSON.new()
		if json.parse(json_str) == OK:
			var data = json.get_data()
			var player_data = data.get("player", {})
			var starter_cards = player_data.get("cards", [])
			var starter_decks = player_data.get("decks", {})
			if starter_cards.size() > 0:
				SaveManager.set_value("player", "cards", starter_cards)
			if starter_decks.size() > 0:
				SaveManager.set_value("player", "decks", starter_decks)
			SaveManager.set_value("player", "gold", player_data.get("gold", 100))
			SaveManager.set_value("player", "diamonds", player_data.get("diamonds", 50))
			SaveManager.set_value("player", "level", 1)
			SaveManager.set_value("player", "exp", 0)
			print("[重置] ✅ 新手卡组已恢复")
	
	# ====== 3. 保存（覆盖旧存档） ======
	SaveManager.save_to_disk()
	PlayerManager.save_data()
	
	# ====== 4. 删除残留文件（非存档管理的配置） ======
	var dir = DirAccess.open("user://")
	if dir:
		if dir.file_exists("theme_settings.cfg"):
			dir.remove("theme_settings.cfg")
			print("[重置] ✅ theme_settings.cfg 已删除")
		if dir.file_exists("player_id.txt"):
			dir.remove("player_id.txt")
			print("[重置] ✅ player_id.txt 已删除")
	
	print("[重置] 🎉 重置完成！所有数据已恢复为初始状态")
	
	# 关闭弹窗
	_do_reset_cancel(overlay)
	
	# 回到主界面
	Global.change_scene("res://Main.tscn")


func _do_reset_cancel(overlay: ColorRect) -> void:
	Global.play_sfx("click")
	if overlay and is_instance_valid(overlay):
		overlay.queue_free()
func _on_back():
	Global.play_sfx("click")
	Global.change_scene("res://Main.tscn")


# ==================== 调试功能 ====================

## 调试密码弹窗
func _show_debug_password() -> void:
	var overlay = ColorRect.new()
	overlay.name = "DebugPwdOverlay"
	overlay.color = Color(0.0, 0.0, 0.0, 0.7)
	overlay.anchor_left = 0.0; overlay.anchor_top = 0.0
	overlay.anchor_right = 1.0; overlay.anchor_bottom = 1.0
	overlay.mouse_filter = MOUSE_FILTER_STOP
	overlay.gui_input.connect(func(event: InputEvent, o=overlay):
		if event is InputEventScreenTouch and not event.pressed:
			o.queue_free()
	)
	add_child(overlay)
	
	var panel = Panel.new()
	panel.name = "DebugPwdPanel"
	panel.anchor_left = 0.15; panel.anchor_top = 0.35
	panel.anchor_right = 0.85; panel.anchor_bottom = 0.65
	
	var ps = StyleBoxFlat.new()
	ps.bg_color = Global.current.bg
	ps.border_width_left = 3; ps.border_width_right = 3
	ps.border_width_top = 3; ps.border_width_bottom = 3
	ps.border_color = Color("#e8a838")
	ps.corner_radius_top_left = 16; ps.corner_radius_top_right = 16
	ps.corner_radius_bottom_left = 16; ps.corner_radius_bottom_right = 16
	panel.add_theme_stylebox_override("panel", ps)
	overlay.add_child(panel)
	
	# 提示文字
	var msg = Label.new()
	msg.text = "🔒 请输入调试密码"
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	msg.add_theme_font_size_override("font_size", 50)
	msg.add_theme_color_override("font_color", Color("#ffffff"))
	msg.anchor_left = 0.0; msg.anchor_top = 0.0
	msg.anchor_right = 1.0; msg.anchor_bottom = 1.0
	msg.offset_left = Global.pw(0.05)
	msg.offset_top = Global.ph(0.02)
	msg.offset_right = Global.pw(-0.05)
	msg.offset_bottom = Global.ph(-0.25)
	panel.add_child(msg)
	
	# 密码输入框
	var line_edit = LineEdit.new()
	line_edit.name = "DebugPwdInput"
	line_edit.placeholder_text = "输入密码..."
	line_edit.secret = true
	line_edit.add_theme_font_size_override("font_size", 50)
	line_edit.add_theme_color_override("font_color", Color("#ffffff"))
	line_edit.add_theme_color_override("font_placeholder_color", Color("#666666"))
	line_edit.custom_minimum_size = Vector2(0, Global.ph(0.06))
	line_edit.anchor_left = 0.15; line_edit.anchor_top = 0.45
	line_edit.anchor_right = 0.85; line_edit.anchor_bottom = 0.55
	panel.add_child(line_edit)
	
	# 按钮横排
	var btn_hbox = HBoxContainer.new()
	btn_hbox.anchor_left = 0.0; btn_hbox.anchor_top = 1.0
	btn_hbox.anchor_right = 1.0; btn_hbox.anchor_bottom = 1.0
	btn_hbox.offset_left = Global.pw(0.08)
	btn_hbox.offset_top = Global.ph(-0.12)
	btn_hbox.offset_right = Global.pw(-0.08)
	btn_hbox.offset_bottom = Global.ph(-0.02)
	btn_hbox.add_theme_constant_override("separation", 20)
	panel.add_child(btn_hbox)
	
	# 取消按钮
	var cancel_btn = Button.new()
	cancel_btn.text = "取消"
	cancel_btn.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	cancel_btn.custom_minimum_size = Vector2(0, Global.ph(0.06))
	cancel_btn.add_theme_font_size_override("font_size", 45)
	var cs = StyleBoxFlat.new()
	cs.bg_color = Global.current.btn_bg
	cs.border_width_left = 2; cs.border_width_right = 2; cs.border_width_top = 2; cs.border_width_bottom = 2
	cs.border_color = Color("#888888")
	cs.corner_radius_top_left = 10; cs.corner_radius_top_right = 10
	cs.corner_radius_bottom_left = 10; cs.corner_radius_bottom_right = 10
	cancel_btn.add_theme_stylebox_override("normal", cs)
	cancel_btn.add_theme_color_override("font_color", Global.current.btn_text)
	cancel_btn.pressed.connect(func(): Global.play_sfx("click"); overlay.queue_free())
	btn_hbox.add_child(cancel_btn)
	
	# 确认按钮
	var confirm_btn = Button.new()
	confirm_btn.text = "确认"
	confirm_btn.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	confirm_btn.custom_minimum_size = Vector2(0, Global.ph(0.06))
	confirm_btn.add_theme_font_size_override("font_size", 45)
	var cs2 = StyleBoxFlat.new()
	cs2.bg_color = Global.current.btn_bg
	cs2.border_width_left = 2; cs2.border_width_right = 2; cs2.border_width_top = 2; cs2.border_width_bottom = 2
	cs2.border_color = Color("#e8a838")
	cs2.corner_radius_top_left = 10; cs2.corner_radius_top_right = 10
	cs2.corner_radius_bottom_left = 10; cs2.corner_radius_bottom_right = 10
	confirm_btn.add_theme_stylebox_override("normal", cs2)
	confirm_btn.add_theme_color_override("font_color", Global.current.btn_text)
	confirm_btn.pressed.connect(_do_debug_password_check.bind(overlay, line_edit))  # debug入口不配音效
	btn_hbox.add_child(confirm_btn)


## 密码验证
func _do_debug_password_check(pwd_overlay: ColorRect, line_edit: LineEdit) -> void:
	var pwd = line_edit.text.strip_edges()
	if pwd == "pipos":
		print("[调试] ✅ 密码正确！")
		pwd_overlay.queue_free()
		_show_debug_menu()
	else:
		print("[调试] ❌ 密码错误")
		line_edit.text = ""
		# 显示错误提示
		var err_label = Label.new()
		err_label.text = "❌ 密码错误，请重试"
		err_label.add_theme_font_size_override("font_size", 35)
		err_label.add_theme_color_override("font_color", Color("#e74c3c"))
		err_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		err_label.anchor_left = 0.0; err_label.anchor_top = 0.55
		err_label.anchor_right = 1.0; err_label.anchor_bottom = 0.65
		var parent = line_edit.get_parent()
		if parent:
			parent.add_child(err_label)
			var timer = get_tree().create_timer(1.5)
			timer.timeout.connect(func():
				if is_instance_valid(err_label):
					err_label.queue_free()
			)


## 调试菜单弹窗
func _show_debug_menu() -> void:
	var overlay = ColorRect.new()
	overlay.name = "DebugMenuOverlay"
	overlay.color = Color(0.0, 0.0, 0.0, 0.7)
	overlay.anchor_left = 0.0; overlay.anchor_top = 0.0
	overlay.anchor_right = 1.0; overlay.anchor_bottom = 1.0
	overlay.mouse_filter = MOUSE_FILTER_STOP
	overlay.gui_input.connect(func(event: InputEvent, o=overlay):
		if event is InputEventScreenTouch and not event.pressed:
			o.queue_free()
	)
	add_child(overlay)
	
	var panel = Panel.new()
	panel.name = "DebugMenuPanel"
	panel.anchor_left = 0.12; panel.anchor_top = 0.25
	panel.anchor_right = 0.88; panel.anchor_bottom = 0.75
	
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
	title.text = "🔧 调试菜单"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 60)
	title.add_theme_color_override("font_color", Global.current.title)
	title.anchor_left = 0.0; title.anchor_top = 0.0
	title.anchor_right = 1.0; title.anchor_bottom = 0.0
	title.offset_left = 0; title.offset_top = Global.ph(0.03)
	title.offset_right = 0; title.offset_bottom = Global.ph(0.12)
	panel.add_child(title)
	
	# 按钮区域 VBox
	var btn_vbox = VBoxContainer.new()
	btn_vbox.anchor_left = 0.0; btn_vbox.anchor_top = 0.0
	btn_vbox.anchor_right = 1.0; btn_vbox.anchor_bottom = 1.0
	btn_vbox.offset_left = Global.pw(0.08)
	btn_vbox.offset_top = Global.ph(0.15)
	btn_vbox.offset_right = Global.pw(-0.08)
	btn_vbox.offset_bottom = Global.ph(-0.15)
	btn_vbox.add_theme_constant_override("separation", 20)
	panel.add_child(btn_vbox)
	
	# 解锁全部按钮
	var unlock_btn = make_debug_btn("🌟 解锁全部", "解锁全部纹路/素材/最高公会等级")
	unlock_btn.pressed.connect(_do_debug_unlock_all.bind(overlay))
	btn_vbox.add_child(unlock_btn)
	
	# 导入卡牌按钮
	var import_btn = make_debug_btn("📥 导入卡牌", "从剪贴板导入分享码")
	import_btn.pressed.connect(_do_debug_import_card.bind(overlay))
	btn_vbox.add_child(import_btn)
	
	# 获得所有辅材各10个按钮
	var aux_btn = make_debug_btn("🧪 获得辅材各10", "获得所有辅材各10个")
	aux_btn.pressed.connect(_do_debug_get_all_aux.bind(overlay))
	btn_vbox.add_child(aux_btn)
	
	# 关闭按钮
	var close_btn = Button.new()
	close_btn.text = "关闭"
	close_btn.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	close_btn.custom_minimum_size = Vector2(0, Global.ph(0.06))
	close_btn.add_theme_font_size_override("font_size", 45)
	var cs = StyleBoxFlat.new()
	cs.bg_color = Global.current.btn_bg
	cs.border_width_left = 2; cs.border_width_right = 2; cs.border_width_top = 2; cs.border_width_bottom = 2
	cs.border_color = Color("#888888")
	cs.corner_radius_top_left = 10; cs.corner_radius_top_right = 10
	cs.corner_radius_bottom_left = 10; cs.corner_radius_bottom_right = 10
	close_btn.add_theme_stylebox_override("normal", cs)
	close_btn.add_theme_color_override("font_color", Global.current.btn_text)
	close_btn.pressed.connect(func(): Global.play_sfx("click"); overlay.queue_free())
	btn_vbox.add_child(close_btn)


## 创建调试菜单按钮
func make_debug_btn(text: String, hint: String) -> Button:
	var btn = Button.new()
	btn.text = text + "\n" + hint
	btn.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	btn.custom_minimum_size = Vector2(0, Global.ph(0.08))
	btn.add_theme_font_size_override("font_size", 45)
	var bs = StyleBoxFlat.new()
	bs.bg_color = Global.current.btn_bg
	bs.border_width_left = 2; bs.border_width_right = 2
	bs.border_width_top = 2; bs.border_width_bottom = 2
	bs.border_color = Color("#e8a838")
	bs.corner_radius_top_left = 12; bs.corner_radius_top_right = 12
	bs.corner_radius_bottom_left = 12; bs.corner_radius_bottom_right = 12
	btn.add_theme_stylebox_override("normal", bs)
	btn.add_theme_color_override("font_color", Global.current.btn_text)
	return btn


## 解锁全部功能
func _do_debug_unlock_all(menu_overlay: ColorRect) -> void:
	print("[调试] 🌟 解锁全部...")
	
	# 1. 公会等级升到最高（Lv.10 制卡圣手）
	# 直接设置公会数据，模拟满足全部条件
	var all_maps = {"misty_forest": true, "flame_cavern": true, "storm_tower": true, "shadow_swamp": true, "legendary_ruins": true}
	for map_key in all_maps:
		SaveManager.set_value("progress", map_key, true)
	SaveManager.set_value("player", "cards_created", 200)
	SaveManager.set_value("player", "highest_quality", "完美")
	# 触发公会等级更新
	PlayerManager._update_guild_level()
	print("[调试] ✅ 公会等级已升至最高：", PlayerManager.get_guild_title())
	
	# 2. 解锁全部纹路组件（90个）
	var all_circuits := []
	for comp in Global.get_all_triggers():
		all_circuits.append(comp.get("id", ""))
	for comp in Global.get_all_conditions():
		all_circuits.append(comp.get("id", ""))
	for comp in Global.get_all_actions():
		all_circuits.append(comp.get("id", ""))
	for comp in Global.get_all_targets():
		all_circuits.append(comp.get("id", ""))
	for comp in Global.get_all_constraints():
		all_circuits.append(comp.get("id", ""))
	
	var unlocked = SaveManager.get_value("circuit", "unlocked", [])
	for cid in all_circuits:
		if cid != "" and not cid in unlocked:
			unlocked.append(cid)
	SaveManager.set_value("circuit", "unlocked", unlocked)
	print("[调试] ✅ 已解锁全部纹路组件：", all_circuits.size(), " 个")
	
	# 3. 获得全部素材各10个
	var all_mats := []
	all_mats.append_array(Global.get_fiber_list())
	all_mats.append_array(Global.get_mineral_list())
	all_mats.append_array(Global.get_resin_list())
	all_mats.append_array(Global.get_extract_list())
	all_mats.append_array(Global.get_pigment_list())
	all_mats.append_array(Global.get_binder_list())
	
	var mats = PlayerManager.get_materials()
	for mat in all_mats:
		var mid = mat.get("id", "")
		if mid != "":
			mats[mid] = mats.get(mid, 0) + 10
	PlayerManager.set_materials(mats)
	
	# 也添加仓库素材
	var warehouse = WarehouseManager
	for mat in all_mats:
		var mid = mat.get("id", "")
		if mid != "":
			warehouse.add_material(mid, 10)
	
	SaveManager.save_to_disk()
	print("[调试] ✅ 全部素材各+10，共 ", all_mats.size(), " 种素材")
	
	# 关闭菜单
	menu_overlay.queue_free()
	_show_debug_toast("🌟 解锁全部成功！公会★10 + 纹路90个 + 素材各10")

## 获得所有辅材各10个
func _do_debug_get_all_aux(menu_overlay: ColorRect) -> void:
	print("[调试] 🧪 获得所有辅材各10个...")
	var all_aux = Global.get_aux_list()
	for aux in all_aux:
		var aid = aux.get("id", "")
		if aid != "":
			WarehouseManager.add_aux(aid, 10)
	SaveManager.save_to_disk()
	print("[调试] ✅ 所有辅材各+10，共 ", all_aux.size(), " 种辅材")
	menu_overlay.queue_free()
	_show_debug_toast("🧪 获得所有辅材各10个成功！")


## 导入卡牌功能
func _do_debug_import_card(menu_overlay: ColorRect) -> void:
	# 先关闭调试菜单
	menu_overlay.queue_free()
	
	# 读取剪贴板
	var code = DisplayServer.clipboard_get()
	if code.is_empty() or code.length() < 10:
		_show_debug_toast("❌ 剪贴板为空或格式不正确")
		return
	
	# 尝试解压缩
	var card = _decompress_card(code)
	if card.is_empty() or not card.has("name"):
		_show_debug_toast("❌ 分享码解析失败，请检查格式")
		return
	
	# 清除ID让CardManager自动生成新ID（避免与原卡牌ID冲突）
	card.erase("id")
	
	# 添加到卡牌管理器
	CardManager.add_card(card)
	SaveManager.save_to_disk()
	
	var card_name = card.get("name", "未知卡牌")
	print("[调试] 📥 导入卡牌：", card_name)
	_show_debug_toast("✅ 已导入卡牌：「" + card_name + "」")


## 解压缩卡牌分享码（从CardGallery复制）
func _decompress_card(compressed: String) -> Dictionary:
	var card := {}
	var parts = compressed.split("|")
	for part in parts:
		if part.length() < 2:
			continue
		var prefix = part[0]
		var value = part.substr(1)
		match prefix:
			"N": card["name"] = value
			"A": card["atk"] = int(value)
			"H": card["hp"] = int(value)
			"C": card["cost"] = int(value)
			"Q":
				var q_map = Global.QUALITY_DECODE
				card["quality"] = q_map.get(value, "普通")
			"E":
				var e_map = {"F": "火", "W": "水", "A": "风", "D": "暗", "L": "光", "E": "地", "N": "无"}
				card["element"] = e_map.get(value, "无")
			"S": card["star"] = int(value)
			"F": card["fields"] = value.split(",")
			"D": card["desc"] = value
			"X":
				var eff_items = value.split(";")
				# 检测是否为纹路组件ID格式
				if eff_items.size() > 0 and eff_items[0].length() >= 2 and \
					(eff_items[0].begins_with("TR") or eff_items[0].begins_with("A") or \
					 eff_items[0].begins_with("C") or eff_items[0].begins_with("T") or \
					 eff_items[0].begins_with("CO")):
					card["effects"] = eff_items
				else:
					var effects := []
					for d in eff_items:
						effects.append({"desc": d})
					card["effects"] = effects
			"I": card["id"] = value
	return card


## 调试Toast提示
func _show_debug_toast(msg: String) -> void:
	var toast = Label.new()
	toast.text = msg
	toast.add_theme_font_size_override("font_size", 40)
	toast.add_theme_color_override("font_color", Global.current.title)
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	toast.anchor_left = 0.1; toast.anchor_top = 0.45
	toast.anchor_right = 0.9; toast.anchor_bottom = 0.55
	toast.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(toast)
	var timer = get_tree().create_timer(2.0)
	timer.timeout.connect(func():
		if is_instance_valid(toast):
			toast.queue_free()
	)
