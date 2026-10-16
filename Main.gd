extends ThemedControl

## 卡师模拟器 · 主界面
## UI 全部静态写在 Main.tscn，此脚本只管交互逻辑 + 主题切换

# 卡片配置表：节点名 → 场景路径 + 昼夜配色
const CARDS = {
	"CardGuild":    {"scene": "res://Guild.tscn",         "id": "guild"},
	"CardWorkshop": {"scene": "res://CardWorkshop.tscn",  "id": "workshop"},
	"CardDeck":     {"scene": "res://DeckEdit.tscn",      "id": "deck"},
	"CardShop":     {"scene": "res://StoreStreet.tscn",  "id": "shop"},
	"CardExplore":  {"scene": "res://Exploration.tscn",   "id": "explore"},
}

# 夜间配色
const NIGHT = {
	"bg":          Color("#171426"),
	"logo":        Color("#E2C278"),
	"icon_btn":    Color("#CBCBE0"),
	"version":     Color("#787892"),
	"shadow_color": Color("#000000"),
	"shadow_alpha": 0.22,
	"cards": {
		"CardGuild":    {"top": Color("#24304A"), "bot": Color("#1A2134"), "icon": Color("#72A6E8"), "title": Color("#E6E6F2"), "desc": Color("#A4A4C2")},
		"CardWorkshop": {"top": Color("#48382E"), "bot": Color("#2B221C"), "icon": Color("#E4AA62"), "title": Color("#E6E6F2"), "desc": Color("#A4A4C2")},
		"CardDeck":     {"top": Color("#42282E"), "bot": Color("#291B1F"), "icon": Color("#C9666C"), "title": Color("#E6E6F2"), "desc": Color("#A4A4C2")},
		"CardShop":     {"top": Color("#44302C"), "bot": Color("#2A1F1C"), "icon": Color("#D47C5E"), "title": Color("#E6E6F2"), "desc": Color("#A4A4C2")},
		"CardExplore":  {"top": Color("#284036"), "bot": Color("#1B2923"), "icon": Color("#62BB84"), "title": Color("#E6E6F2"), "desc": Color("#A4A4C2")},
	}
}

# 白天配色
const DAY = {
	"bg":          Color("#F2EBDF"),
	"logo":        Color("#946F38"),
	"icon_btn":    Color("#645C50"),
	"version":     Color("#8C8274"),
	"shadow_color": Color("#8A7F72"),
	"shadow_alpha": 0.18,
	"cards": {
		"CardGuild":    {"top": Color("#D7E1F0"), "bot": Color("#C2CFE2"), "icon": Color("#3E69AD"), "title": Color("#2C3344"), "desc": Color("#626878")},
		"CardWorkshop": {"top": Color("#F0E2D2"), "bot": Color("#E4D1BA"), "icon": Color("#C47E38"), "title": Color("#42382E"), "desc": Color("#7A6F60")},
		"CardDeck":     {"top": Color("#F0D9DC"), "bot": Color("#E2C4C8"), "icon": Color("#A84E54"), "title": Color("#442E32"), "desc": Color("#7C6468")},
		"CardShop":     {"top": Color("#F0DDD4"), "bot": Color("#E4C9BB"), "icon": Color("#B46244"), "title": Color("#44342E"), "desc": Color("#7C6860")},
		"CardExplore":  {"top": Color("#DBE9E0"), "bot": Color("#C6DBCF"), "icon": Color("#3F895E"), "title": Color("#2E4236"), "desc": Color("#60786A")},
	}
}

func _ready():
	super._ready()
	for card_name in CARDS.keys():
		var btn = get_node_or_null("%s/Btn" % card_name)
		if btn is Button:
			btn.pressed.connect(_on_card_pressed.bind(CARDS[card_name]["scene"]))
	var gear = get_node_or_null("GearButton")
	if gear is Button:
		gear.pressed.connect(_on_gear_pressed)
	var guide = get_node_or_null("GuideBtn")
	if guide is Button:
		guide.pressed.connect(_on_guide)
	var website = get_node_or_null("WebsiteBtn")
	if website is Button:
		website.pressed.connect(_on_website_pressed)
	call_deferred("_setup_tutorial_flow")

# ==================== 主题切换 ====================

func _on_theme_changed(mode):
	super._on_theme_changed(mode)
	var is_day = mode == Global.ThemeMode.DAY
	var theme = DAY if is_day else NIGHT
	
	# 背景（切换纹理图）
	var bg = get_node_or_null("Background")
	if bg:
		var tex_path = "res://assets/theme/bg_day.png" if is_day else "res://assets/theme/bg_night.png"
		var tex = load(tex_path)
		if tex:
			bg.texture = tex
	
	# LOGO
	var logo = get_node_or_null("Logo")
	if logo:
		logo.add_theme_color_override("font_color", theme["logo"])
	
	# 图标按钮
	var icon_c = theme["icon_btn"]
	var gear = get_node_or_null("GearButton")
	if gear:
		gear.add_theme_color_override("font_color", icon_c)
	var guide = get_node_or_null("GuideBtn")
	if guide:
		guide.add_theme_color_override("font_color", icon_c)
	
	# 版本号
	var version = get_node_or_null("VersionLabel")
	if version:
		version.add_theme_color_override("font_color", theme["version"])
	
	# 官网按钮
	var website_btn = get_node_or_null("WebsiteBtn")
	if website_btn:
		website_btn.add_theme_color_override("font_color", theme["icon_btn"])
	
	# 卡片
	for card_name in CARDS.keys():
		var colors = theme["cards"][card_name]
		var card_node = get_node_or_null(card_name)
		if not card_node:
			continue
		
		# ShaderMaterial
		var bg_node = card_node.get_node_or_null("Bg")
		if bg_node and bg_node.material is ShaderMaterial:
			var mat = bg_node.material as ShaderMaterial
			mat.set_shader_parameter("color_top", colors["top"])
			mat.set_shader_parameter("color_bottom", colors["bot"])
			mat.set_shader_parameter("shadow_color", theme["shadow_color"])
			mat.set_shader_parameter("shadow_alpha", theme["shadow_alpha"])
		
		# 图标
		var icon = card_node.get_node_or_null("Icon")
		if icon:
			icon.add_theme_color_override("font_color", colors["icon"])
		
		# 标题
		var title = card_node.get_node_or_null("Title")
		if title:
			title.add_theme_color_override("font_color", colors["title"])
		
		# 描述
		var desc = card_node.get_node_or_null("Desc")
		if desc:
			desc.add_theme_color_override("font_color", colors["desc"])

# ==================== 交互 ====================

func _on_card_pressed(scene_path: String):
	Global.play_sfx("click")
	Global.change_scene(scene_path)

func _on_gear_pressed():
	Global.play_sfx("click")
	Global.change_scene("res://Settings.tscn")

func _on_guide():
	Global.play_sfx("click")
	_show_guide()

func _on_website_pressed():
	Global.play_sfx("click")
	OS.shell_open("https://pipos52.github.io/kashi-simulator/")

# ==================== 教程 ====================

func _setup_tutorial_flow() -> void:
	if TutorialManager.is_done():
		return
	TutorialManager.check_version_and_reset()
	match TutorialManager.get_progress():
		TutorialManager.PROGRESS_NONE:
			_show_awaken_dialogue()
		TutorialManager.PROGRESS_AWAKENED:
			_show_first_battle_guide()
		TutorialManager.PROGRESS_FIRST_BATTLE:
			_show_first_card_guide()
		TutorialManager.PROGRESS_FIRST_CARD:
			_show_first_deck_guide()
		TutorialManager.PROGRESS_FIRST_DECK:
			_show_guild_guide()

func _show_awaken_dialogue() -> void:
	var popup = preload("res://TutorialDialoguePopup.gd").new()
	popup.setup([
		{"speaker": "老陈", "text": "醒醒，小子。这条巷子可不是睡觉的地方。"},
		{"speaker": "老陈", "text": "……你那个眼神，是新来的吧？这座城市的规矩，卡牌说了算。"},
		{"speaker": "你", "text": "（头……好痛。这里是哪？我明明……）"},
		{"speaker": "老陈", "text": "别慌，小子。这是一个新手卡组，压箱底货，凑合用。"},
		{"speaker": "老陈", "text": "卡是死的，人是活的。去野外探索，打一场——赢了，你就当练手。"},
	], func():
		_open_starter_pack()
		TutorialManager.advance()
		_show_toast("✨ 获得新手卡包×1（已自动领取）")
		_show_first_battle_guide()
	)
	# 右上角"跳过"按钮：一键跳过所有教程
	popup.show_skip_button(true, _skip_all_tutorials)
	add_child(popup)

## 跳过所有教程：标记完成 + 发放新手奖励 + 保留可玩的初始卡组
func _skip_all_tutorials() -> void:
	_open_starter_pack()
	TutorialManager.set_progress(TutorialManager.PROGRESS_DONE)
	_show_toast("⏭ 已跳过新手教程")

func _open_starter_pack() -> void:
	var gold = SaveManager.get_value("player", "gold", 0)
	SaveManager.set_value("player", "gold", gold + 100)
	SaveManager.save_to_disk()

func show_toast(text: String) -> void:
	_show_toast(text)

func _show_toast(text: String) -> void:
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 36)
	lbl.add_theme_color_override("font_color", Color("#FFD700"))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.anchor_left = 0.1; lbl.anchor_top = 0.3
	lbl.anchor_right = 0.9; lbl.anchor_bottom = 0.3
	lbl.offset_top = 0; lbl.offset_bottom = Global.ph(0.06)
	add_child(lbl)
	lbl.modulate.a = 0.0
	var tw = create_tween()
	tw.tween_property(lbl, "modulate:a", 1.0, 0.3)
	tw.tween_interval(1.6)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.4)
	tw.tween_callback(lbl.queue_free)

func _show_first_battle_guide() -> void:
	var popup = preload("res://TutorialDialoguePopup.gd").new()
	popup.setup([
		{"speaker": "老陈", "text": "看到那个「野外探索」了吗？进去，选新手卡组，打一场巷口混混。"},
		{"speaker": "老陈", "text": "他在巷口堵了三年，收保护费的。你正好拿他练手。"},
		{"speaker": "你", "text": "（用卡牌……战斗？这个世界……到底怎么回事。）"},
		{"speaker": "老陈", "text": "打赢他，回来告诉我。卡牌这行，命比技术重要。"},
	], func():
		Global.change_scene("res://Exploration.tscn")
	)
	add_child(popup)

func _show_first_card_guide() -> void:
	var popup = preload("res://TutorialDialoguePopup.gd").new()
	popup.setup([
		{"speaker": "老陈", "text": "打完了？有点意思。光会打架不算本事——这座城市的卡，是人做的。"},
		{"speaker": "你", "text": "（查看掉落材料）这些……就是做卡的东西？"},
		{"speaker": "老陈", "text": "刚打赢那小子掉了一套材料：卡基用的纤维、矿粉、松脂，卡墨用的清水、炭黑、骨胶——够你做出第一张卡了。"},
		{"speaker": "你", "text": "好，我去试试看。"},
		{"speaker": "老陈", "text": "去制卡工坊：先做卡基，再调卡墨，然后刻画成卡。卡牌这行，靠手艺吃饭。"},
	], func():
		Global.change_scene("res://CardWorkshop.tscn")
	)
	add_child(popup)

func _show_first_deck_guide() -> void:
	var popup = preload("res://TutorialDialoguePopup.gd").new()
	popup.setup([
		{"speaker": "老陈", "text": "一张卡打不了架。把会用、敢用的卡编成一套，出门才带得出手。"},
		{"speaker": "你", "text": "组卡……具体要怎么做？"},
		{"speaker": "老陈", "text": "去配置牌库，至少凑二十张。能打、能扛、能救命，三样都得有。"},
		{"speaker": "你", "text": "我试试看。"},
	], func():
		Global.change_scene("res://DeckEdit.tscn")
	)
	add_child(popup)

func _show_guild_guide() -> void:
	var popup = preload("res://TutorialDialoguePopup.gd").new()
	popup.setup([
		{"speaker": "老陈", "text": "卡组成型了？那你有资格进公会了。里面接活、卖卡、换材料，都在那里。"},
		{"speaker": "你", "text": "公会……听起来像组织？"},
		{"speaker": "老陈", "text": "进了那道门，你就不算野卡师了。……行，比老子当年强。"},
		{"speaker": "老陈", "text": "对了，纹路组件——做卡时那些TR、A、T——靠升级称号和完成公会任务解锁。多干活，自然有新花样。"},
	], func():
		TutorialManager.advance()
		Global.change_scene("res://Guild.tscn")
	)
	add_child(popup)

# ==================== 帮助指南 ====================

func _show_guide():
	var overlay = ColorRect.new()
	overlay.name = "GuideOverlay"
	overlay.color = Color(0, 0, 0, 0.7)
	overlay.anchor_left = 0.0; overlay.anchor_top = 0.0
	overlay.anchor_right = 1.0; overlay.anchor_bottom = 1.0
	overlay.mouse_filter = MOUSE_FILTER_STOP
	overlay.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			Global.play_sfx("click")
			overlay.queue_free()
	)
	add_child(overlay)
	
	var panel = Panel.new()
	panel.name = "GuidePanel"
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
	title.text = "📖 卡师模拟器 · 新手指南"
	title.add_theme_font_size_override("font_size", 60)
	title.add_theme_color_override("font_color", Global.current.title)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.anchor_left = 0.0; title.anchor_top = 0.0
	title.anchor_right = 1.0; title.anchor_bottom = 0.0
	title.offset_top = Global.ph(0.01)
	title.offset_bottom = Global.ph(0.08)
	panel.add_child(title)
	
	var scroll = ScrollContainer.new()
	scroll.name = "GuideScroll"
	scroll.anchor_left = 0.02; scroll.anchor_top = 0.0
	scroll.anchor_right = 0.98; scroll.anchor_bottom = 1.0
	scroll.offset_top = Global.ph(0.085)
	scroll.offset_bottom = Global.ph(-0.08)
	scroll.scroll_horizontal = false
	panel.add_child(scroll)
	
	var vbox = VBoxContainer.new()
	vbox.name = "GuideVBox"
	vbox.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	vbox.add_theme_constant_override("separation", Global.ph(0.008))
	scroll.add_child(vbox)
	
	_build_guide_content(vbox)
	call_deferred("_set_guide_vbox_width", vbox, scroll)
	
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
	close_btn.offset_top = Global.ph(-0.075)
	close_btn.offset_bottom = Global.ph(-0.01)
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

func _make_guide_section(vbox: VBoxContainer, title_text: String, title_color: Color) -> VBoxContainer:
	var section = VBoxContainer.new()
	section.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	section.add_theme_constant_override("separation", Global.ph(0.005))
	vbox.add_child(section)
	var sep = HSeparator.new()
	sep.add_theme_color_override("color", Global.current.topbar_border)
	sep.size_flags_horizontal = SIZE_FILL
	section.add_child(sep)
	var lbl = Label.new()
	lbl.text = title_text
	lbl.add_theme_font_size_override("font_size", 50)
	lbl.add_theme_color_override("font_color", title_color)
	lbl.size_flags_horizontal = SIZE_FILL
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	section.add_child(lbl)
	return section

func _make_guide_label(vbox: VBoxContainer, text: String, color: Color = Color("#FFFFFF"), font_size: int = 45):
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.size_flags_horizontal = SIZE_FILL
	vbox.add_child(lbl)

func _build_guide_content(vbox: VBoxContainer):
	var s1 = _make_guide_section(vbox, "🎮 ① 欢迎来到卡师模拟器", Color("#e8a838"))
	_make_guide_label(s1, "在这个世界中，你将扮演一名卡牌制作师，采集素材、调制卡墨、制作卡基、刻画卡牌，最终用自己亲手制作的卡牌去战斗！", Global.current.btn_text, 42)
	_make_guide_label(s1, "游戏的核心循环：采集素材 → 制作卡基/调制卡墨 → 刻画卡牌 → 配入牌组 → 野外战斗 → 获取更强素材 → 制作更强卡牌", Color("#FFD700"), 42)
	
	var s2 = _make_guide_section(vbox, "🏭 ② 制卡工坊", Color("#e8a838"))
	_make_guide_label(s2, "制卡工坊包含4个功能：制作卡基、调制卡墨、刻画卡牌、仓库管理。", Global.current.btn_text, 42)
	
	var s3 = _make_guide_section(vbox, "🗺️ ③ 野外探索", Color("#e8a838"))
	_make_guide_label(s3, "野外探索是获取素材和辅材的主要途径。共有5个地图，每个地图包含多层地形。", Global.current.btn_text, 42)
	
	var s4 = _make_guide_section(vbox, "⚔️ ④ 战斗系统", Color("#e8a838"))
	_make_guide_label(s4, "每回合获得1点能量，用于召唤卡牌。卡牌有攻击力和生命值，击败卡兽可获得辅材和素材掉落。", Global.current.btn_text, 42)
	
	var s5 = _make_guide_section(vbox, "🏪 ⑤ 商店街", Color("#e8a838"))
	_make_guide_label(s5, "卡牌交易、素材商店、卡包商店三个功能入口。", Global.current.btn_text, 42)
	
	var s6 = _make_guide_section(vbox, "🏛️ ⑥ 卡师公会", Color("#e8a838"))
	_make_guide_label(s6, "接取公会任务，完成任务获得奖励，提升公会等级解锁更多纹路组件和功能。", Global.current.btn_text, 42)
	
	var s7 = _make_guide_section(vbox, "🃏 ⑦ 配置牌库", Color("#e8a838"))
	_make_guide_label(s7, "从仓库中选择卡牌编入牌组，用于野外战斗。合理搭配不同属性的卡牌应对不同敌人。", Global.current.btn_text, 42)
	
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, Global.ph(0.02))
	vbox.add_child(spacer)