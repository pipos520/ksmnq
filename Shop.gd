extends Control

# 当前标签页："items" / "lootbox"
var _current_tab: String = "items"

# 灰鲸广告节点
var _hj_ads: HJAdsNode = null


func _ready():
	# ---- 静态节点已在 Shop.tscn 中声明 ----
	var back := get_node_or_null("BackBtn")
	if back is Button: back.pressed.connect(_on_back)
	# 初始化广告
	_hj_ads = HJAdsNode.new()
	_hj_ads.name = "HJAdsNode"
	add_child(_hj_ads)
	_hj_ads.app_id = "234475"
	_hj_ads.rewarded_placement_id = "9701263723893953"
	_hj_ads.debug_mode = false
	_hj_ads.ad_loaded.connect(_on_ad_loaded_for_reward)
	_hj_ads.video_rewarded.connect(_on_video_rewarded)
	_hj_ads.ad_closed.connect(_on_ad_closed)
	_hj_ads.ad_failed.connect(_on_ad_failed_for_reward)
	_show_ad_status("⏳ 初始化广告...", Color("#FFD700"))
	await get_tree().process_frame
	_hj_ads.init()
	_hj_ads.loadRewardedAd()
	# 标签切换
	var items_tab := get_node_or_null("ItemsTab")
	if items_tab is Button: items_tab.pressed.connect(_switch_tab.bind("items"))
	var lootbox_tab := get_node_or_null("LootboxTab")
	if lootbox_tab is Button: lootbox_tab.pressed.connect(_switch_tab.bind("lootbox"))
	_update_tab_style()
	# 金币更新
	_update_gold()
	# 刷新商品
	_refresh_shop()
	Global.theme_changed.connect(_on_theme_changed)
	call_deferred("_apply_theme_styles")

func _apply_theme_styles():
	var bg = get_node_or_null("Background")
	if bg: Global.apply_bg(bg)
	for n in ["TopBar", "BottomBar", "TabBar"]:
		var r = get_node_or_null(n)
		if r is ColorRect: r.color = Global.current.topbar_bg
	for n in ["TopBarLine", "BottomBarLine", "TabLine"]:
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
	_update_tab_style()

func _update_gold():
	var gl = get_node_or_null("GoldLabel")
	if gl:
		var gold = SaveManager.get_value("player", "gold", 0)
		gl.text = "" + Global.n2s(gold)
		Global.make_gold_legible(gl)


func _switch_tab(tab: String):
	Global.play_sfx("click")
	_current_tab = tab
	_update_tab_style()
	_refresh_shop()


func _update_tab_style():
	var keys = ["items", "lootbox"]
	for key in keys:
		var btn_name = "ItemsTab" if key == "items" else "LootboxTab"
		var btn = get_node_or_null(btn_name)
		if not btn:
			continue
		var is_active = key == _current_tab
		var s = StyleBoxFlat.new()
		if is_active:
			s.bg_color = Global.current.btn_bg_hover
			s.border_width_bottom = 3
			s.border_color = Color("#FF6B6B")
		else:
			s.bg_color = Global.current.btn_bg
			s.border_width_bottom = 0
		btn.add_theme_stylebox_override("normal", s)
		btn.add_theme_color_override("font_color", Global.current.title if is_active else Global.current.btn_text)


func _refresh_shop():
	var vbox = get_node_or_null("ShopScroll/ShopList")
	if not vbox:
		return
	
	for child in vbox.get_children():
		vbox.remove_child(child)
		child.queue_free()
	
	match _current_tab:
		"items":
			_refresh_items(vbox)
		"lootbox":
			_refresh_lootbox(vbox)


func _refresh_items(vbox: VBoxContainer):
	var all_mats: Array = Global.get_fiber_list() + Global.get_mineral_list() + Global.get_resin_list() \
		+ Global.get_extract_list() + Global.get_pigment_list() + Global.get_binder_list()
	
	# 根据公会称号决定可售卖的素材品级
	var guild_level = PlayerManager.get_guild_level()
	var guild_title = PlayerManager.get_guild_title()
	var allowed_rarities := ["普通"]
	if guild_level >= 3:  allowed_rarities.append("稀有")
	if guild_level >= 5:  allowed_rarities.append("史诗")
	if guild_level >= 8:  allowed_rarities.append("传说")
	
	# 过滤素材
	var sale_mats := []
	for mat in all_mats:
		if mat.get("rarity", "") in allowed_rarities:
			sale_mats.append(mat)
	
	if sale_mats.size() == 0:
		var empty = Label.new()
		empty.text = "暂无在售商品"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_font_size_override("font_size", 50)
		empty.add_theme_color_override("font_color", Color("#5a5a6e"))
		empty.custom_minimum_size = Vector2(0, Global.ph(0.1))
		vbox.add_child(empty)
		return
	
	# 称号提示条
	var title_bar = Panel.new()
	title_bar.name = "TitleBar"
	title_bar.custom_minimum_size = Vector2(0, Global.ph(0.065))
	title_bar.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	var title_style = StyleBoxFlat.new()
	title_style.bg_color = Color("#1a1a2e")
	title_style.border_width_left = 1
	title_style.border_width_right = 1
	title_style.border_width_top = 1
	title_style.border_width_bottom = 1
	title_style.border_color = Color("#FFD700")
	title_style.corner_radius_top_left = 8
	title_style.corner_radius_top_right = 8
	title_style.corner_radius_bottom_left = 8
	title_style.corner_radius_bottom_right = 8
	title_bar.add_theme_stylebox_override("panel", title_style)
	vbox.add_child(title_bar)
	
	var title_label = Label.new()
	title_label.text = "" + guild_title + " · 可购品级：[" + " | ".join(allowed_rarities) + "]"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 38)
	title_label.add_theme_color_override("font_color", Color("#FFD700"))
	title_label.anchor_left = 0.0
	title_label.anchor_top = 0.0
	title_label.anchor_right = 1.0
	title_label.anchor_bottom = 1.0
	title_bar.add_child(title_label)
	
	var row_index := 0
	for mat in sale_mats:
		var mid = mat["id"]
		var name_str = mat.get("name", mid)
		var price = _calc_price(mat)
		
		var row_panel = Panel.new()
		row_panel.name = "RowPanel"
		var panel_style = StyleBoxFlat.new()
		panel_style.bg_color = _get_row_bg_color(row_index)
		row_panel.add_theme_stylebox_override("panel", Global.pixel_row_style(row_index, panel_style))
		row_panel.custom_minimum_size = Vector2(0, Global.ph(0.095))
		row_panel.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
		row_panel.mouse_filter = MOUSE_FILTER_PASS
		vbox.add_child(row_panel)
		
		var hbox = HBoxContainer.new()
		hbox.name = "RowHBox"
		hbox.anchor_left = 0.0
		hbox.anchor_top = 0.0
		hbox.anchor_right = 1.0
		hbox.anchor_bottom = 1.0
		hbox.offset_left = Global.pw(0.02)
		hbox.offset_top = 0
		hbox.offset_right = Global.pw(-0.02)
		hbox.offset_bottom = 0
		hbox.mouse_filter = MOUSE_FILTER_IGNORE
		row_panel.add_child(hbox)
		
		# 名称
		var name_label = Label.new()
		name_label.text = name_str
		name_label.add_theme_font_size_override("font_size", 50)
		name_label.add_theme_color_override("font_color", Global.current.title)
		name_label.size_flags_horizontal = SIZE_EXPAND
		hbox.add_child(name_label)
		
		# 价格
		var price_label = Label.new()
		price_label.text = "" + str(price)
		price_label.add_theme_font_size_override("font_size", 45)
		price_label.add_theme_color_override("font_color", Color("#FFD700"))
		price_label.custom_minimum_size = Vector2(Global.pw(0.15), 0)
		price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hbox.add_child(price_label)
		
		# 购买按钮
		var buy_btn = Button.new()
		buy_btn.text = "购买"
		buy_btn.add_theme_font_size_override("font_size", 45)
		var bs = StyleBoxFlat.new()
		bs.bg_color = Global.current.btn_bg
		bs.border_width_left = 2
		bs.border_width_right = 2
		bs.border_width_top = 2
		bs.border_width_bottom = 2
		bs.border_color = Color("#4CAF50")
		bs.corner_radius_top_left = 10
		bs.corner_radius_top_right = 10
		bs.corner_radius_bottom_left = 10
		bs.corner_radius_bottom_right = 10
		bs.content_margin_left = 16
		bs.content_margin_right = 16
		buy_btn.add_theme_stylebox_override("normal", bs)
		buy_btn.add_theme_color_override("font_color", Global.current.btn_text)
		buy_btn.pressed.connect(_on_buy.bind(mid, price))
		buy_btn.custom_minimum_size = Vector2(Global.pw(0.15), Global.ph(0.06))
		hbox.add_child(buy_btn)
		
		row_index += 1
	
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, Global.ph(0.05))
	vbox.add_child(spacer)


func _refresh_lootbox(vbox: VBoxContainer):
	# 看广告按钮
	var ad_btn = Button.new()
	ad_btn.name = "WatchAdBtn"
	ad_btn.text = "看广告领取10金币"
	ad_btn.add_theme_font_size_override("font_size", 55)
	var bs = StyleBoxFlat.new()
	bs.bg_color = Color("#FF6B6B")
	bs.border_width_left = 2
	bs.border_width_right = 2
	bs.border_width_top = 2
	bs.border_width_bottom = 2
	bs.border_color = Color("#FF5252")
	bs.corner_radius_top_left = 16
	bs.corner_radius_top_right = 16
	bs.corner_radius_bottom_left = 16
	bs.corner_radius_bottom_right = 16
	bs.content_margin_left = 24
	bs.content_margin_right = 24
	ad_btn.add_theme_stylebox_override("normal", bs)
	ad_btn.add_theme_color_override("font_color", Color("#FFFFFF"))
	ad_btn.custom_minimum_size = Vector2(0, Global.ph(0.12))
	ad_btn.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	ad_btn.pressed.connect(_on_watch_ad)
	vbox.add_child(ad_btn)
	
	# 状态提示
	var hint = Label.new()
	hint.name = "AdHint"
	hint.text = "观看完整激励广告即可获得10金币奖励！"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 40)
	hint.add_theme_color_override("font_color", Color("#5a5a6e"))
	hint.custom_minimum_size = Vector2(0, Global.ph(0.1))
	vbox.add_child(hint)
	
	# 底部错误信息区（在列表底部留白）
	var error_bar = ColorRect.new()
	error_bar.name = "AdErrorBar"
	error_bar.color = Color(0.2, 0.2, 0.2, 0.0)
	error_bar.custom_minimum_size = Vector2(0, Global.ph(0.1))
	error_bar.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	vbox.add_child(error_bar)
	
	var error_label = Label.new()
	error_label.name = "AdErrorLabel"
	error_label.text = ""
	error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	error_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	error_label.add_theme_font_size_override("font_size", 38)
	error_label.add_theme_color_override("font_color", Color("#FF5252"))
	error_label.anchor_left = 0.0
	error_label.anchor_top = 0.0
	error_label.anchor_right = 1.0
	error_label.anchor_bottom = 1.0
	error_bar.add_child(error_label)
	
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, Global.ph(0.05))
	vbox.add_child(spacer)


func _on_watch_ad():
	Global.play_sfx("click")
	Global.play_sfx("click")
	if _hj_ads == null:
		_show_ad_error(" 广告未初始化")
		return
	
	if _hj_ads.isRewardedAdReady():
		_show_ad_status("▶ 播放广告中...", Color("#FFD700"))
		_show_ad_error("")
		_hj_ads.showRewardedAd()
	else:
		_show_ad_status("⏳ 广告未就绪，重新加载中...", Color("#FFD700"))
		_hj_ads.loadRewardedAd()
		_show_ad_error("广告正在加载，请稍后点击")


func _on_video_rewarded(rewarded: bool):
	if not rewarded:
		_show_ad_status("⏳ 广告未完整播放，无奖励", Color("#FF5252"))
		_show_ad_error("广告未完整播放，下次请看完哦")
		return
	
	# 广告完整播放，发放10金币
	var gold = SaveManager.get_value("player", "gold", 0)
	gold += 10
	SaveManager.set_value("player", "gold", gold)
	SaveManager.save_to_disk()
	_update_gold()
	_show_ad_status(" 获得10金币奖励！", Color("#4CAF50"))
	_show_ad_error("")
	_show_popup(" 获得10金币！", Color("#4CAF50"))
	
	# ⚠️ 注意：不要在广告关闭前重新加载！
	# 等广告自然关闭后，由 _on_ad_closed 负责加载下一个广告


func _on_ad_closed(result: String):
	# 广告关闭回调
	_show_ad_status(" 广告已关闭，可再次观看", Color("#4CAF50"))
	_show_ad_error("")
	# 预加载下一个广告（加1秒延迟确保SDK清理干净）
	await get_tree().create_timer(1.0).timeout
	_hj_ads.loadRewardedAd()
	_show_ad_status("⏳ 加载下一个广告...", Color("#FFD700"))


func _on_ad_loaded_for_reward(placement_id: String):
	_show_ad_status(" 广告已就绪，点击观看", Color("#4CAF50"))
	_show_ad_error("")


func _on_ad_failed_for_reward(error_msg: String):
	_show_ad_status(" 广告加载失败", Color("#FF5252"))
	_show_ad_error("错误详情: " + error_msg)
	# 暂时禁用重试，避免弹窗叠加
	# _show_popup("❌ 广告加载失败: " + error_msg, Color("#FF5252"))
	# 重新加载
	# await get_tree().create_timer(3.0).timeout
	# _hj_ads.loadRewardedAd()
	# _show_ad_status("⏳ 重新加载广告...", Color("#FFD700"))


func _show_ad_status(text: String, color: Color):
	var hint = get_node_or_null("ShopScroll/ShopList/AdHint")
	if hint and hint is Label:
		hint.text = text
		hint.add_theme_color_override("font_color", color)


func _show_popup(text: String, color: Color):
	# 创建一个弹窗覆盖层
	var existing = get_node_or_null("PopupOverlay")
	if existing:
		existing.queue_free()
	
	var overlay = ColorRect.new()
	overlay.name = "PopupOverlay"
	overlay.color = Color(0.0, 0.0, 0.0, 0.5)
	overlay.anchor_left = 0.0
	overlay.anchor_top = 0.0
	overlay.anchor_right = 1.0
	overlay.anchor_bottom = 1.0
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	
	# 弹窗面板
	var panel = ColorRect.new()
	panel.name = "PopupPanel"
	panel.color = Global.current.bg
	panel.anchor_left = 0.0
	panel.anchor_top = 0.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 0.0
	panel.offset_left = Global.pw(0.1)
	panel.offset_top = Global.ph(0.35)
	panel.offset_right = Global.pw(-0.1)
	panel.offset_bottom = Global.ph(0.55)
	overlay.add_child(panel)
	
	# 圆角边框
	var border = StyleBoxFlat.new()
	border.bg_color = Global.current.bg
	border.border_width_left = 2
	border.border_width_right = 2
	border.border_width_top = 2
	border.border_width_bottom = 2
	border.border_color = Color("#e8a838")
	border.corner_radius_top_left = 20
	border.corner_radius_top_right = 20
	border.corner_radius_bottom_left = 20
	border.corner_radius_bottom_right = 20
	panel.add_theme_stylebox_override("panel", border)
	
	# 文本
	var label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 50)
	label.add_theme_color_override("font_color", color)
	label.anchor_left = 0.0
	label.anchor_top = 0.0
	label.anchor_right = 1.0
	label.anchor_bottom = 1.0
	label.offset_left = Global.pw(0.05)
	label.offset_top = 0
	label.offset_right = Global.pw(-0.05)
	label.offset_bottom = 0
	panel.add_child(label)
	
	# 关闭按钮
	var close_btn = Button.new()
	close_btn.text = "关闭"
	close_btn.add_theme_font_size_override("font_size", 40)
	var btn_bs = StyleBoxFlat.new()
	btn_bs.bg_color = color
	btn_bs.border_width_left = 2
	btn_bs.border_width_right = 2
	btn_bs.border_width_top = 2
	btn_bs.border_width_bottom = 2
	btn_bs.border_color = color
	btn_bs.corner_radius_top_left = 10
	btn_bs.corner_radius_top_right = 10
	btn_bs.corner_radius_bottom_left = 10
	btn_bs.corner_radius_bottom_right = 10
	close_btn.add_theme_stylebox_override("normal", btn_bs)
	close_btn.add_theme_color_override("font_color", Color("#FFFFFF"))
	close_btn.anchor_left = 0.3
	close_btn.anchor_top = 0.0
	close_btn.anchor_right = 0.7
	close_btn.anchor_bottom = 0.0
	close_btn.offset_left = 0
	close_btn.offset_top = Global.ph(0.12)
	close_btn.offset_right = 0
	close_btn.offset_bottom = Global.ph(0.18)
	close_btn.pressed.connect(_close_popup)
	panel.add_child(close_btn)


func _close_popup():
	var overlay = get_node_or_null("PopupOverlay")
	if overlay:
		overlay.queue_free()


func _show_ad_error(text: String):
	var error_label = get_node_or_null("ShopScroll/ShopList/AdErrorBar/AdErrorLabel")
	if error_label and error_label is Label:
		error_label.text = text
		# 有错误时显示背景
		var error_bar = get_node_or_null("ShopScroll/ShopList/AdErrorBar")
		if error_bar and error_bar is ColorRect:
			if text == "":
				error_bar.color = Color(0.2, 0.2, 0.2, 0.0)
			else:
				error_bar.color = Color(0.2, 0.0, 0.0, 0.3)


## 根据素材稀有度和属性重新计算物价
## 公式：price = base + stat_sum × mult + tendency_bonus
## 普通：base=1,  mult=1,  tendency=0
## 稀有：base=5,  mult=2,  tendency=1
## 史诗：base=12, mult=3,  tendency=2
## 传说：base=25, mult=5,  tendency=3
func _calc_price(mat: Dictionary) -> int:
	var rarity = mat.get("rarity", "普通")
	var base := 1
	var mult := 1
	var tendency_bonus := 0
	match rarity:
		"稀有":
			base = 5; mult = 2; tendency_bonus = 1
		"史诗":
			base = 12; mult = 3; tendency_bonus = 2
		"传说":
			base = 25; mult = 5; tendency_bonus = 3
	
	# 累加所有属性值
	var stat_sum := 0
	for key in ["carry", "toughness", "stability", "hardness", "bond", "gloss",
		"conductivity", "purity", "adhesion", "chromatography", "harmony"]:
		stat_sum += mat.get(key, 0)
	
	return base + stat_sum * mult + tendency_bonus


func _get_row_bg_color(row_index: int) -> Color:
	# 斑马纹第二色必须是「略深的羊皮纸」，不能是透明。
	# 页面底色是深色贴图(bg_day/bg_night)，透明会让后半数行直接压成深底，
	# 而行内文字是深棕色 -> 对比度接近 1:1，整行看不见。
	if row_index % 2 == 0:
		return Global.current.topbar_bg
	return Global.current.topbar_bg.darkened(0.10)


func _on_buy(mid: String, price: int):
	Global.play_sfx("click")
	# 弹出批量购买确认弹窗
	_show_buy_confirm(mid, price)

var _buy_mid: String = ""
var _buy_price: int = 0
var _buy_qty: int = 1
var _buy_mat_name: String = ""
var _buy_overlay: ColorRect = null

func _show_buy_confirm(mid: String, price: int):
	_buy_mid = mid
	_buy_price = price
	_buy_qty = 1
	
	# 查找素材名称
	_buy_mat_name = mid
	var all_mats = Global.get_fiber_list() + Global.get_mineral_list() + Global.get_resin_list() \
		+ Global.get_extract_list() + Global.get_pigment_list() + Global.get_binder_list()
	for mat in all_mats:
		if mat.get("id", "") == mid:
			_buy_mat_name = mat.get("name", mid)
			break
	
	var gold = SaveManager.get_value("player", "gold", 0)
	var max_qty = floor(gold / price)
	if max_qty <= 0:
		_show_popup(" 金币不足！", Color("#FF5252"))
		return
	
	# 创建遮罩
	_buy_overlay = ColorRect.new()
	_buy_overlay.name = "BuyConfirmOverlay"
	_buy_overlay.color = Color(0, 0, 0, 0.6)
	_buy_overlay.anchor_left = 0.0; _buy_overlay.anchor_top = 0.0
	_buy_overlay.anchor_right = 1.0; _buy_overlay.anchor_bottom = 1.0
	_buy_overlay.mouse_filter = MOUSE_FILTER_STOP
	_buy_overlay.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed:
			_buy_overlay.queue_free(); _buy_overlay = null)
	add_child(_buy_overlay)
	
	# 面板
	var panel = Panel.new()
	panel.anchor_left = 0.15; panel.anchor_top = 0.3
	panel.anchor_right = 0.85; panel.anchor_bottom = 0.7
	var ps = StyleBoxFlat.new()
	ps.bg_color = Global.current.bg
	ps.border_width_left = 3; ps.border_width_right = 3
	ps.border_width_top = 3; ps.border_width_bottom = 3
	ps.border_color = Color("#e8a838")
	ps.corner_radius_top_left = 16; ps.corner_radius_top_right = 16
	ps.corner_radius_bottom_left = 16; ps.corner_radius_bottom_right = 16
	panel.add_theme_stylebox_override("panel", ps)
	_buy_overlay.add_child(panel)
	
	var vbox = VBoxContainer.new()
	vbox.anchor_left = 0.0; vbox.anchor_top = 0.0
	vbox.anchor_right = 1.0; vbox.anchor_bottom = 1.0
	vbox.offset_left = Global.pw(0.05); vbox.offset_top = Global.ph(0.03)
	vbox.offset_right = Global.pw(-0.05); vbox.offset_bottom = Global.ph(-0.03)
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)
	
	# 标题
	var title = Label.new()
	title.text = "批量购买"
	title.add_theme_font_size_override("font_size", 50)
	title.add_theme_color_override("font_color", Global.current.title)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	
	# 素材名称（已在 _buy_mat_name 中查找完毕）
	
	var name_label = Label.new()
	name_label.text = _buy_mat_name
	name_label.add_theme_font_size_override("font_size", 45)
	name_label.add_theme_color_override("font_color", Global.current.btn_text)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_label)
	
	# 单价信息
	var unit_label = Label.new()
	unit_label.text = "单价：" + str(price) + "  最多可买 x" + str(int(max_qty))
	unit_label.add_theme_font_size_override("font_size", 40)
	unit_label.add_theme_color_override("font_color", Color("#FFD700"))
	unit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(unit_label)
	
	# 数量选择行
	var qty_hbox = HBoxContainer.new()
	qty_hbox.size_flags_horizontal = SIZE_FILL
	qty_hbox.add_theme_constant_override("separation", 20)
	vbox.add_child(qty_hbox)
	
	# 先声明 qty_val 和 total_label (在闭包之前)
	var qty_val = Label.new()
	var total_label = Label.new()
	
	var dec_btn = Button.new()
	dec_btn.text = "−"
	dec_btn.add_theme_font_size_override("font_size", 60)
	dec_btn.custom_minimum_size = Vector2(Global.pw(0.1), Global.ph(0.08))
	dec_btn.pressed.connect(func():
		_buy_qty = max(1, _buy_qty - 1)
		_update_buy_confirm_ui(qty_val, total_label, gold))
	qty_hbox.add_child(dec_btn)
	
	qty_hbox.add_spacer(true)
	
	qty_val.text = str(_buy_qty)
	qty_val.add_theme_font_size_override("font_size", 60)
	qty_val.add_theme_color_override("font_color", Global.current.title)
	qty_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	qty_val.custom_minimum_size = Vector2(Global.pw(0.15), 0)
	qty_hbox.add_child(qty_val)
	
	qty_hbox.add_spacer(true)
	
	var inc_btn = Button.new()
	inc_btn.text = "+"
	inc_btn.add_theme_font_size_override("font_size", 60)
	inc_btn.custom_minimum_size = Vector2(Global.pw(0.1), Global.ph(0.08))
	inc_btn.pressed.connect(func():
		_buy_qty = min(max_qty, _buy_qty + 1)
		_update_buy_confirm_ui(qty_val, total_label, gold))
	qty_hbox.add_child(inc_btn)
	
	# 总价
	total_label.text = "总价：" + str(_buy_qty * price)
	total_label.add_theme_font_size_override("font_size", 45)
	total_label.add_theme_color_override("font_color", Color("#FFD700"))
	total_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(total_label)
	
	# 按钮行
	var btn_hbox = HBoxContainer.new()
	btn_hbox.size_flags_horizontal = SIZE_FILL
	btn_hbox.add_theme_constant_override("separation", 20)
	vbox.add_child(btn_hbox)
	
	var cancel_btn = Button.new()
	cancel_btn.text = "取消"
	cancel_btn.add_theme_font_size_override("font_size", 45)
	cancel_btn.size_flags_horizontal = SIZE_EXPAND
	cancel_btn.pressed.connect(func():
		_buy_overlay.queue_free(); _buy_overlay = null)
	btn_hbox.add_child(cancel_btn)
	
	var confirm_btn = Button.new()
	confirm_btn.text = "确认购买"
	confirm_btn.add_theme_font_size_override("font_size", 45)
	confirm_btn.size_flags_horizontal = SIZE_EXPAND
	var cs = StyleBoxFlat.new()
	cs.bg_color = Color("#4CAF50")
	cs.corner_radius_top_left = 8; cs.corner_radius_top_right = 8
	cs.corner_radius_bottom_left = 8; cs.corner_radius_bottom_right = 8
	confirm_btn.add_theme_stylebox_override("normal", cs)
	confirm_btn.add_theme_color_override("font_color", Color("#FFFFFF"))
	confirm_btn.pressed.connect(func():
		_do_buy(_buy_mid, _buy_price, _buy_qty))
	btn_hbox.add_child(confirm_btn)

func _update_buy_confirm_ui(qty_val: Label, total_label: Label, gold: int):
	qty_val.text = str(_buy_qty)
	total_label.text = "总价：" + str(_buy_qty * _buy_price)

func _do_buy(mid: String, price: int, qty: int):
	var gold = SaveManager.get_value("player", "gold", 0)
	var total_cost = price * qty
	if gold < total_cost:
		_show_popup(" 金币不足！", Color("#FF5252"))
		return
	
	# 扣钱
	gold -= total_cost
	SaveManager.set_value("player", "gold", gold)
	SaveManager.save_to_disk()
	
	# 加素材
	WarehouseManager.add_material(mid, qty)
	
	_update_gold()
	
	# 关闭购买弹窗
	if _buy_overlay and is_instance_valid(_buy_overlay):
		_buy_overlay.queue_free()
		_buy_overlay = null
	
	# 成功弹窗
	_show_popup(" 成功购买 " + str(qty) + " 个 " + _buy_mat_name + "！", Color("#4CAF50"))


func _on_theme_changed(_mode):
	var bg = get_node_or_null("Background")
	if bg: Global.apply_bg(bg)
	
	var topbar = get_node_or_null("TopBar")
	if topbar and topbar is ColorRect:
		topbar.color = Global.current.topbar_bg
	
	var topbar_line = get_node_or_null("TopBarLine")
	if topbar_line and topbar_line is ColorRect:
		topbar_line.color = Global.current.topbar_border
	
	var tab_bar = get_node_or_null("TabBar")
	if tab_bar and tab_bar is ColorRect:
		tab_bar.color = Global.current.topbar_bg
	
	var tab_line = get_node_or_null("TabLine")
	if tab_line and tab_line is ColorRect:
		tab_line.color = Global.current.topbar_border
	
	var bottom_bar = get_node_or_null("BottomBar")
	if bottom_bar and bottom_bar is ColorRect:
		bottom_bar.color = Global.current.topbar_bg
	
	var bottom_bar_line = get_node_or_null("BottomBarLine")
	if bottom_bar_line and bottom_bar_line is ColorRect:
		bottom_bar_line.color = Global.current.topbar_border
	
	var title = get_node_or_null("Title")
	if title and title is Label:
		title.add_theme_color_override("font_color", Global.current.title)
		title.add_theme_color_override("font_shadow_color", Global.current.title_shadow)
		title.add_theme_constant_override("shadow_offset_x", Global.current.shadow_offset)
		title.add_theme_constant_override("shadow_offset_y", Global.current.shadow_offset)
	
	_update_tab_style()
	
	for child in get_children():
		if child is Button:
			child.add_theme_color_override("font_color", Global.current.btn_text)
			child.add_theme_color_override("font_hover_color", Global.current.btn_text_hover)
	
	_refresh_shop()


func _on_back():
	Global.play_sfx("click")
	Global.change_scene("res://Main.tscn")
