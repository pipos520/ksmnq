extends Control
## ============================================================
##  卡师公会 —— 功能菜单页（静态化 + 风格统一）
## ============================================================
const GUIDE_KEY := "fifth_act_stage"

var _tex_night: Texture2D
var _tex_day: Texture2D
var _last_applied_mode = null

func _ready():
	var _t0 = Time.get_ticks_msec()
	# ---- 静态界面：所有 UI 节点已在 Guild.tscn 中声明 ----
	# 信号连接
	var back := get_node_or_null("BackBtn")
	if back is Button:
		back.pressed.connect(_on_back)
	var btn_info := get_node_or_null("BtnPlayerInfo")
	if btn_info is Button:
		btn_info.pressed.connect(_on_btn_pressed.bind("res://PlayerInfo.tscn"))
	var btn_tasks := get_node_or_null("BtnGuildTasks")
	if btn_tasks is Button:
		btn_tasks.pressed.connect(_on_btn_pressed.bind("res://GuildTasks.tscn"))
	
	# 刷新称号显示
	_refresh_status()
	print("[Guild] _ready 完成: %dms" % [Time.get_ticks_msec() - _t0])
	
	# 主题
	Global.theme_changed.connect(_on_theme_changed)
	call_deferred("_apply_theme_styles")
	
	# 第五幕导览
	call_deferred("_maybe_show_guild_tour")

func _refresh_status():
	var status_label = get_node_or_null("StatusLabel")
	if status_label is Label:
		var guild_level = PlayerManager.get_guild_level()
		var guild_title = PlayerManager.get_guild_title()
		status_label.text = "🏛️ Lv." + str(int(guild_level)) + "  " + guild_title
		Global.make_gold_legible(status_label)

func _on_theme_changed(mode = null):
	if mode == null:
		mode = Global.current_mode
	_apply_theme_styles()
	_refresh_status()

func _apply_theme_styles():
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
	# 状态栏
	var status_bar = get_node_or_null("StatusBar")
	if status_bar and status_bar is ColorRect:
		status_bar.color = Global.current.topbar_bg
	var status_line = get_node_or_null("StatusLine")
	if status_line and status_line is ColorRect:
		status_line.color = Global.current.topbar_border
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
	
	# 按钮：如果主题没变，跳过 StyleBoxFlat 重建
	var mode_key = mode
	if _last_applied_mode == mode_key:
		return
	_last_applied_mode = mode_key
	
	var icon_c = Color("#645C50") if is_day else Color("#CBCBE0")
	var btn_bg = Color(0.15, 0.13, 0.20, 0.85) if not is_day else Color(0.90, 0.85, 0.75, 0.85)
	var btn_bg_hover = btn_bg.lightened(0.12)
	var btn_bg_pressed = btn_bg.darkened(0.15)
	var border_c = Color("#E8A838") if not is_day else Color("#946F38")
	var btn_names = ["BackBtn", "BtnPlayerInfo", "BtnGuildTasks"]
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
			sb.corner_radius_top_left = r; sb.corner_radius_top_right = r
			sb.corner_radius_bottom_left = r; sb.corner_radius_bottom_right = r
			sb.content_margin_left = 16; sb.content_margin_right = 16
			sb.content_margin_top = 8; sb.content_margin_bottom = 8
			btn.add_theme_stylebox_override(state, sb)

func _on_back():
	Global.play_sfx("click")
	Global.change_scene("res://Main.tscn")
func _on_btn_pressed(scene_path: String):
	Global.play_sfx("click")
	Global.change_scene(scene_path)

# ============================
#  第五幕 · 导览引导（公会介绍）
# ============================
func _maybe_show_guild_tour() -> void:
	if TutorialManager.get_progress() < TutorialManager.PROGRESS_DONE:
		return
	var stage = SaveManager.get_value("tutorial", GUIDE_KEY, 0)
	if stage >= 1:
		return
	SaveManager.set_value("tutorial", GUIDE_KEY, 1)
	SaveManager.save_to_disk()
	_show_guild_tour_dialogue()

func _show_guild_tour_dialogue() -> void:
	var popup = preload("res://TutorialDialoguePopup.gd").new()
	popup.setup([
		{"speaker": "老陈", "text": "这就是卡师公会——咱们这行的'据点'。接活、卖卡、换材料，都在这门里。以后你有好卡，或者缺材料，就上这儿来。"},
		{"speaker": "你", "text": "听起来挺齐全的……"},
		{"speaker": "老陈", "text": "公会按级给你发称号，活儿干得多了，等级上去了，能解锁的纹路组件也越来越多——做卡时那些TR、A、T，都得靠升级称号和完成公会任务才能拿到。先看看你的个人信息。"},
	], func():
		Global.change_scene("res://PlayerInfo.tscn")
	)
	add_child(popup)