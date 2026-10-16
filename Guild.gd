extends ThemedControl
## ============================================================
##  卡师公会 —— 功能菜单页（静态化 + 风格统一）
## ============================================================
const GUIDE_KEY := "fifth_act_stage"

func _ready():
	super._ready()
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
	
	# 第五幕导览
	call_deferred("_maybe_show_guild_tour")

func _refresh_status():
	var status_label = get_node_or_null("StatusLabel")
	if status_label is Label:
		var guild_level = PlayerManager.get_guild_level()
		var guild_title = PlayerManager.get_guild_title()
		status_label.text = "🏛️ Lv." + str(guild_level) + "  " + guild_title

func _on_theme_changed(mode = null):
	super._on_theme_changed(mode)
	_refresh_status()

func _get_bar_names() -> Array:
	return ["TopBar", "BottomBar", "StatusBar"]

func _get_bar_line_names() -> Array:
	return ["TopBarLine", "BottomBarLine", "StatusLine"]

func _get_themed_button_names() -> Array:
	return ["BackBtn", "BtnPlayerInfo", "BtnGuildTasks"]

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