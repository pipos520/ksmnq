extends Control
## 加载界面 —— 异步预加载所有场景，显示进度条（静态化）

const SCENES_TO_PRELOAD := [
	# Tier 1 — 入口主界面（加载完成后立即进入）
	"res://Main.tscn",
	# Tier 2 — Main 直达子场景（用户最可能先访问的6个）
	"res://Settings.tscn",
	"res://Exploration.tscn",
	"res://CardWorkshop.tscn",
	"res://DeckEdit.tscn",
	"res://Guild.tscn",
	"res://StoreStreet.tscn",
	# Tier 3 — CardWorkshop 子场景（制作链路5个）
	"res://CardBaseMaking.tscn",
	"res://InkMaking.tscn",
	"res://CardEngraving.tscn",
	"res://CircuitGallery.tscn",
	"res://Warehouse.tscn",
	# Tier 3 — Guild 子场景
	"res://PlayerInfo.tscn",
	"res://GuildTasks.tscn",
	# Tier 3 — StoreStreet 子场景
	"res://Shop.tscn",
	"res://CardPackShop.tscn",
	# Tier 3 — Exploration 子场景
	"res://MapNodeScene.tscn",
	# Tier 3 — DeckEdit 子场景
	"res://CardGallery.tscn",
	# Tier 4 — 最深层（GuildTasks → DailyTasks）
	"res://DailyTasks.tscn",
	# Tier 3 — 最重场景（放最后避免阻塞前面轻量场景；3D 战斗场已退役，横竖屏共用 Legacy）
	"res://BattleSceneLegacy.tscn",
]

const LOADING_TIPS := [
	"正在加载纹路图鉴数据",
	"正在加载卡牌数据",
	"正在加载素材数据",
	"正在加载场景资源",
	"正在优化加载速度",
	"正在同步云端卡组池",
	"正在同步云端卡包数据",
	"正在准备卡师世界",
]

const MIN_LOADING_SECONDS: float = 5.0

var _total_scenes: int = 0
var _loaded_count: int = 0
var _total_tasks: int = 0
var _tasks_done: int = 0
var _server_decks_loaded: bool = false
var _server_packs_loaded: bool = false
var _bar_fill: ColorRect
var _progress_label: Label
var _tip_index: int = 0
var _privacy_accepted_flag: bool = false
var _loading_timer: float = 0.0
var _has_entered_main: bool = false

func _ready():
	# 静态节点已在 .tscn 中声明，获取引用
	_bar_fill = get_node_or_null("BarFill")
	_progress_label = get_node_or_null("ProgressLabel")
	# 主题适配背景
	var bg = get_node_or_null("Background")
	Global.apply_bg(bg)
	# 标题颜色
	var title = get_node_or_null("Title")
	if title is Label:
		title.add_theme_color_override("font_color", Global.current.title)
		title.add_theme_color_override("font_shadow_color", Global.current.title_shadow)
		title.add_theme_constant_override("shadow_offset_x", Global.current.shadow_offset)
		title.add_theme_constant_override("shadow_offset_y", Global.current.shadow_offset)

	if not SaveManager.get_value("settings", "privacy_accepted", false):
		_show_privacy_dialog()
		while not _privacy_accepted_flag:
			await get_tree().process_frame
	await _start_loading()

func _start_loading():
	_total_scenes = SCENES_TO_PRELOAD.size()
	_total_tasks = _total_scenes + 2
	_loaded_count = 0
	_tasks_done = 0
	_loading_timer = 0.0
	_has_entered_main = false

	Global.server_decks = []
	Global.server_decks_loaded = false
	Global.server_card_packs = []
	Global.server_card_packs_loaded = false
	_start_fetch_decks()
	_start_fetch_card_packs()

	await _loading_loop()

func _start_fetch_decks():
	var result = await Global.get_all_decks()
	if result.has("error"):
		print("[LoadingScreen]  拉取卡组池失败: ", result.error)
	else:
		var decks = result.get("data", [])
		Global.server_decks = decks
		Global.server_decks_loaded = true
		print("[LoadingScreen]  拉取卡组池: ", decks.size(), " 套")
	_server_decks_loaded = true

func _start_fetch_card_packs():
	var result = await Global.get_all_card_packs()
	if result.has("error"):
		print("[LoadingScreen]  拉取卡包数据失败: ", result.error)
	else:
		var packs = result.get("data", [])
		Global.server_card_packs = packs
		Global.server_card_packs_loaded = true
		print("[LoadingScreen]  拉取卡包: ", packs.size(), " 个")
	_server_packs_loaded = true

func _loading_loop():
	while _loading_timer < MIN_LOADING_SECONDS and _tasks_done < _total_tasks:
		# 场景可能在 await 期间被切走（节点离树后 get_tree() 返回 null，
		# await 会直接抛错让调试器中断），因此每帧都要先确认自己还在树内。
		if not is_inside_tree():
			return
		await get_tree().process_frame
		if not is_inside_tree():
			return
		_loading_timer += get_process_delta_time()
		_check_progress()
	_enter_main_early()

func _enter_main_early():
	if _has_entered_main:
		return
	_has_entered_main = true

	for i in SCENES_TO_PRELOAD.size():
		var scene_path = SCENES_TO_PRELOAD[i]
		var packed = load(scene_path)
		if packed:
			Global.preloaded_scenes[scene_path] = packed
		else:
			print("[LoadingScreen]  加载失败: %s" % scene_path)
		var pct = int(float(i + 1) / SCENES_TO_PRELOAD.size() * 100.0)
		_progress_label.text = "正在加载场景资源 %d/%d  %d%%" % [i + 1, SCENES_TO_PRELOAD.size(), pct]
		_bar_fill.offset_right = -150.0 + 300.0 * float(i + 1) / SCENES_TO_PRELOAD.size()
		# 同 _loading_loop：离树后 get_tree() 为 null，await 会抛错冻结游戏
		if not is_inside_tree():
			return
		await get_tree().process_frame

	print("[LoadingScreen]  全部 %d 个场景同步加载完成" % SCENES_TO_PRELOAD.size())
	_progress_label.text = "正在进入卡师世界..."
	Global.change_scene("res://Main.tscn")

func _check_progress():
	_loaded_count = 0
	_tasks_done = _loaded_count + (1 if _server_decks_loaded else 0) + (1 if _server_packs_loaded else 0)
	var progress = float(_tasks_done) / float(_total_tasks) if _total_tasks > 0 else 0.0
	_update_progress(progress)
	_tip_index = (_tip_index + 1) % LOADING_TIPS.size()

func _update_progress(progress: float):
	var fill_width = 300.0 * progress
	_bar_fill.offset_right = -150.0 + fill_width
	var pct = int(progress * 100.0)
	_progress_label.text = LOADING_TIPS[_tip_index] + "  " + str(pct) + "%"

## 显示隐私协议弹窗（第一次启动时）
func _show_privacy_dialog():
	var overlay = ColorRect.new()
	overlay.name = "PrivacyOverlay"
	overlay.color = Color(0, 0, 0, 0.75)
	overlay.anchor_left = 0.0; overlay.anchor_top = 0.0
	overlay.anchor_right = 1.0; overlay.anchor_bottom = 1.0
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	var panel = Panel.new()
	panel.name = "PrivacyPanel"
	var ps = StyleBoxFlat.new()
	ps.bg_color = Global.current.bg
	ps.border_width_left = 3; ps.border_width_right = 3
	ps.border_width_top = 3; ps.border_width_bottom = 3
	ps.border_color = Color("#e8a838")
	ps.corner_radius_top_left = 16; ps.corner_radius_top_right = 16
	ps.corner_radius_bottom_left = 16; ps.corner_radius_bottom_right = 16
	panel.add_theme_stylebox_override("panel", ps)
	panel.anchor_left = 0.0; panel.anchor_top = 0.0
	panel.anchor_right = 1.0; panel.anchor_bottom = 0.0
	panel.offset_left = Global.pw(0.08); panel.offset_top = Global.ph(0.15)
	panel.offset_right = Global.pw(-0.08); panel.offset_bottom = Global.ph(0.85)
	overlay.add_child(panel)

	var title = Label.new()
	title.text = "隐私政策与用户协议"
	title.add_theme_font_size_override("font_size", 55)
	title.add_theme_color_override("font_color", Global.current.title)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.anchor_left = 0.0; title.anchor_top = 0.0
	title.anchor_right = 1.0; title.anchor_bottom = 0.0
	title.offset_left = Global.pw(0.04); title.offset_top = Global.ph(0.02)
	title.offset_right = Global.pw(-0.04); title.offset_bottom = Global.ph(0.09)
	panel.add_child(title)

	var line = ColorRect.new()
	line.color = Global.current.topbar_border
	line.anchor_left = 0.0; line.anchor_top = 0.0
	line.anchor_right = 1.0; line.anchor_bottom = 0.0
	line.offset_left = Global.pw(0.05); line.offset_top = Global.ph(0.095)
	line.offset_right = Global.pw(-0.05); line.offset_bottom = Global.ph(0.096)
	panel.add_child(line)

	var scroll = ScrollContainer.new()
	scroll.anchor_left = 0.0; scroll.anchor_top = 0.0
	scroll.anchor_right = 1.0; scroll.anchor_bottom = 1.0
	scroll.offset_left = Global.pw(0.03); scroll.offset_top = Global.ph(0.10)
	scroll.offset_right = Global.pw(-0.03); scroll.offset_bottom = Global.ph(-0.12)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
	vbox.custom_minimum_size = Vector2(Global.pw(0.74), 0)
	scroll.add_child(vbox)

	var sections = [
		{"title": " 信息收集与使用", "content": "本游戏不会收集您的个人身份信息（如姓名、地址、电话号码等）。\n游戏运行过程中，系统会记录必要的游戏数据（如卡牌数据、游戏进度等），这些数据仅保存在您的设备本地，或通过您主动登录的账号进行云端同步。"},
		{"title": " 广告服务", "content": "本游戏集成了第三方广告服务（灰鲸HJ广告SDK），用于展示激励视频广告及摇一摇等交互式广告。广告服务可能会收集设备标识符（OAID、Android ID）、设备型号、网络状态信息、IP地址及设备传感器信息（如加速度传感器、陀螺仪），用于广告展示、摇一摇广告交互识别及归因统计。此外，为实现广告反作弊和质量保障，广告SDK可能会读取您设备上已安装的应用列表（包名），该信息仅用于广告欺诈检测，不会用于其他目的。"},
		{"title": " 网络通信", "content": "游戏的部分功能（如卡包同步、排行榜等）需要通过Supabase后端服务进行网络通信。传输的数据仅包含游戏相关内容（卡牌信息等），不包含个人敏感信息。"},
		{"title": " 数据存储", "content": "游戏存档保存在您的设备本地存储中（user://路径）。您可以通过设置界面清除数据或重置游戏进度。建议定期备份存档文件。"},
		{"title": " 数据安全", "content": "我们采用行业标准的安全措施保护您的数据，包括传输加密（HTTPS）和本地存储安全。但请注意，任何互联网传输和电子存储方式都无法保证100%的安全。"},
		{"title": " 儿童隐私", "content": "本游戏面向所有年龄段的玩家。我们不会故意收集14岁以下儿童的个人信息。如果您是家长或监护人，发现孩子未经同意提供了个人信息，请与我们联系。"},
		{"title": " 政策更新", "content": "我们可能会不时更新本隐私政策。更新后的政策将在游戏内公布，继续使用本游戏即表示您同意更新后的条款。"},
		{"title": " 联系我们", "content": "如您对本隐私政策有任何疑问或建议，请通过游戏内设置界面的「反馈」功能与我们联系。"},
	]

	for sec in sections:
		var st = Label.new()
		st.text = sec["title"]
		st.add_theme_font_size_override("font_size", 45)
		st.add_theme_color_override("font_color", Color("#e8a838"))
		st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		st.size_flags_horizontal = Control.SIZE_FILL
		vbox.add_child(st)

		var ct = Label.new()
		ct.text = sec["content"]
		ct.add_theme_font_size_override("font_size", 38)
		ct.add_theme_color_override("font_color", Global.current.btn_text)
		ct.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ct.size_flags_horizontal = Control.SIZE_FILL
		vbox.add_child(ct)

		var sp = Control.new()
		sp.custom_minimum_size = Vector2(0, Global.ph(0.01))
		vbox.add_child(sp)

	var btn_hbox = HBoxContainer.new()
	btn_hbox.anchor_left = 0.0; btn_hbox.anchor_top = 1.0
	btn_hbox.anchor_right = 1.0; btn_hbox.anchor_bottom = 1.0
	btn_hbox.offset_left = Global.pw(0.05); btn_hbox.offset_top = Global.ph(-0.10)
	btn_hbox.offset_right = Global.pw(-0.05); btn_hbox.offset_bottom = Global.ph(-0.01)
	panel.add_child(btn_hbox)

	# 拒绝按钮
	var reject_btn = Button.new()
	reject_btn.text = "拒绝并退出"
	reject_btn.add_theme_font_size_override("font_size", 40)
	var rs = StyleBoxFlat.new()
	rs.bg_color = Global.current.btn_bg
	rs.border_width_left = 2; rs.border_width_right = 2
	rs.border_width_top = 2; rs.border_width_bottom = 2
	rs.border_color = Color("#FF5252")
	rs.corner_radius_top_left = 10; rs.corner_radius_top_right = 10
	rs.corner_radius_bottom_left = 10; rs.corner_radius_bottom_right = 10
	reject_btn.add_theme_stylebox_override("normal", rs)
	reject_btn.add_theme_stylebox_override("hover", rs)
	reject_btn.add_theme_color_override("font_color", Color("#FF5252"))
	reject_btn.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
	reject_btn.pressed.connect(func():
		get_tree().quit()
	)
	btn_hbox.add_child(reject_btn)

	# 同意按钮
	var accept_btn = Button.new()
	accept_btn.text = "同意并继续"
	accept_btn.add_theme_font_size_override("font_size", 40)
	var acc_s = StyleBoxFlat.new()
	acc_s.bg_color = Global.current.btn_bg
	acc_s.border_width_left = 2; acc_s.border_width_right = 2
	acc_s.border_width_top = 2; acc_s.border_width_bottom = 2
	acc_s.border_color = Color("#4CAF50")
	acc_s.corner_radius_top_left = 10; acc_s.corner_radius_top_right = 10
	acc_s.corner_radius_bottom_left = 10; acc_s.corner_radius_bottom_right = 10
	accept_btn.add_theme_stylebox_override("normal", acc_s)
	accept_btn.add_theme_stylebox_override("hover", acc_s)
	accept_btn.add_theme_color_override("font_color", Color("#4CAF50"))
	accept_btn.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
	accept_btn.pressed.connect(func():
		Global.play_sfx("click")
		SaveManager.set_value("settings", "privacy_accepted", true)
		SaveManager.save_to_disk()
		_privacy_accepted_flag = true
		overlay.queue_free()
	)
	btn_hbox.add_child(accept_btn)