extends ThemedControl

func _ready():
	super._ready()
	var _t0 = Time.get_ticks_msec()
	call_deferred("_maybe_show_street_tour")
	var back := get_node_or_null("BackBtn")
	if back is Button: back.pressed.connect(_on_back)
	var btn_shop := get_node_or_null("BtnShop")
	if btn_shop is Button: btn_shop.pressed.connect(_on_btn_pressed.bind("res://Shop.tscn"))
	var btn_pack := get_node_or_null("BtnCardPack")
	if btn_pack is Button: btn_pack.pressed.connect(_on_btn_pressed.bind("res://CardPackShop.tscn"))
	var btn_rent := get_node_or_null("BtnDeckRent")
	if btn_rent is Button: btn_rent.pressed.connect(_on_btn_pressed.bind("res://DeckRentShop.tscn"))
	var gold_label := get_node_or_null("GoldLabel")
	if gold_label is Label:
		gold_label.text = "💰 " + str(SaveManager.get_value("player", "gold", 0))
	print("[StoreStreet] _ready 完成: %dms" % [Time.get_ticks_msec() - _t0])

func _get_themed_button_names() -> Array:
	return ["BackBtn", "BtnShop", "BtnCardPack", "BtnDeckRent"]

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
		{"speaker": "老陈", "text": "这条街叫商店街，是卡师们买卖的地方。左边【📦素材商店】补制作材料，右边【🎁卡包商店】碰碰手气。"},
		{"speaker": "你", "text": "素材店和卡包店……都在这条街？"},
		{"speaker": "老陈", "text": "手头紧的时候，先逛逛素材店买点便宜料子，做出来的卡也能换俩钱。你先自己逛逛，熟悉一下环境。"},
	], func():
		SaveManager.set_value("tutorial", "fifth_act_stage", 4)
		SaveManager.save_to_disk()
	)
	add_child(popup)