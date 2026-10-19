extends Control
var _last_applied_mode = null
var _tex_night: Texture2D
var _tex_day: Texture2D

func _ready():
	var _t0 = Time.get_ticks_msec()
	# ---- 静态界面：UI 节点已在 StoreStreet.tscn 中声明 ----
	call_deferred("_maybe_show_street_tour")
	var back := get_node_or_null("BackBtn")
	if back is Button: back.pressed.connect(_on_back)
	var btn_shop := get_node_or_null("BtnShop")
	if btn_shop is Button: btn_shop.pressed.connect(_on_btn_pressed.bind("res://Shop.tscn"))
	# 卡包商店
	var btn_pack := get_node_or_null("BtnCardPack")
	if btn_pack is Button: btn_pack.pressed.connect(_on_btn_pressed.bind("res://CardPackShop.tscn"))
	# 牌组租借
	var btn_rent := get_node_or_null("BtnDeckRent")
	if btn_rent is Button: btn_rent.pressed.connect(_on_btn_pressed.bind("res://DeckRentShop.tscn"))
	# 更新金币
	var gold_label := get_node_or_null("GoldLabel")
	if gold_label is Label:
		gold_label.text = "" + Global.n2s(SaveManager.get_value("player", "gold", 0))
		Global.make_gold_legible(gold_label)
	Global.theme_changed.connect(_on_theme_changed)
	call_deferred("_apply_theme_styles")
	print("[StoreStreet] _ready 完成: %dms" % [Time.get_ticks_msec() - _t0])

func _on_theme_changed(mode = null):
	if mode == null: mode = Global.current_mode
	_apply_theme_styles()

func _apply_theme_styles():
	var mode = Global.current_mode
	var is_day = mode == Global.ThemeMode.DAY
	# 背景纹理
	var bg = get_node_or_null("Background")
	if bg and bg is TextureRect:
		if _tex_night == null:
			_tex_night = load("res://assets/theme/bg_night.png")
			_tex_day = load("res://assets/theme/bg_day.png")
		bg.texture = _tex_day if is_day else _tex_night
	# 顶栏/底栏
	for n in ["TopBar","BottomBar"]:
		var r = get_node_or_null(n)
		if r and r is ColorRect: r.color = Global.current.topbar_bg
	for n in ["TopBarLine","BottomBarLine"]:
		var r = get_node_or_null(n)
		if r and r is ColorRect: r.color = Global.current.topbar_border
	# 标题
	var title = get_node_or_null("Title")
	if title and title is Label:
		title.add_theme_color_override("font_color", Global.current.title)
		title.add_theme_color_override("font_shadow_color", Global.current.title_shadow)
		title.add_theme_constant_override("shadow_offset_x", Global.current.shadow_offset)
		title.add_theme_constant_override("shadow_offset_y", Global.current.shadow_offset)
	# 按钮样式
	var mode_key = mode
	if _last_applied_mode == mode_key: return
	_last_applied_mode = mode_key
	var icon_c = Color("#645C50") if is_day else Color("#CBCBE0")
	var btn_bg = Color(0.15, 0.13, 0.20, 0.85) if not is_day else Color(0.90, 0.85, 0.75, 0.85)
	var btn_bg_hover = btn_bg.lightened(0.12)
	var btn_bg_pressed = btn_bg.darkened(0.15)
	var border_c = Color("#E8A838") if not is_day else Color("#946F38")
	for bname in ["BackBtn", "BtnShop", "BtnCardPack", "BtnDeckRent"]:
		var btn = get_node_or_null(bname)
		if not btn is Button: continue
		btn.add_theme_color_override("font_color", icon_c)
		btn.add_theme_color_override("font_hover_color", icon_c.lightened(0.15))
		btn.add_theme_color_override("font_pressed_color", icon_c.darkened(0.2))
		for state in ["normal", "hover", "pressed", "focus"]:
			var sb = StyleBoxFlat.new()
			sb.bg_color = btn_bg_hover if state == "hover" else (btn_bg_pressed if state == "pressed" else btn_bg)
			sb.border_width_left = 2; sb.border_width_right = 2
			sb.border_width_top = 2; sb.border_width_bottom = 2
			sb.border_color = border_c
			sb.corner_radius_top_left = 12; sb.corner_radius_top_right = 12
			sb.corner_radius_bottom_left = 12; sb.corner_radius_bottom_right = 12
			sb.content_margin_left = 16; sb.content_margin_right = 16
			sb.content_margin_top = 8; sb.content_margin_bottom = 8
			btn.add_theme_stylebox_override(state, sb)

func _on_back(): Global.play_sfx("click"); Global.change_scene("res://Main.tscn")
func _on_btn_pressed(scene_path: String): Global.play_sfx("click"); Global.change_scene(scene_path)

# ============================
#  第五幕 · 导览接力（商店街介绍）
# ============================
func _maybe_show_street_tour() -> void:
	if TutorialManager.get_progress() < TutorialManager.PROGRESS_DONE: return
	var stage = SaveManager.get_value("tutorial", "fifth_act_stage", 0)
	if stage != 2: return
	SaveManager.set_value("tutorial", "fifth_act_stage", 3)
	SaveManager.save_to_disk()
	_show_street_tour_dialogue()

func _show_street_tour_dialogue() -> void:
	var popup = preload("res://TutorialDialoguePopup.gd").new()
	popup.setup([
		{"speaker": "老陈", "text": "这条街叫商店街，是卡师们买卖的地方。左边【素材商店】补制作材料，右边【卡包商店】碰碰手气。"},
		{"speaker": "你", "text": "素材店和卡包店……都在这条街？"},
		{"speaker": "老陈", "text": "手头紧的时候，先逛逛素材店买点便宜料子，做出来的卡也能换俩钱。你先自己逛逛，熟悉一下环境。"},
	], func():
		SaveManager.set_value("tutorial", "fifth_act_stage", 4)
		SaveManager.save_to_disk()
	)
	add_child(popup)