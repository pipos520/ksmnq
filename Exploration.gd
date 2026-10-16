extends ThemedControl
var _maps := [
	{"id": "misty_forest", "name": "🌲 迷雾森林", "desc": "幽暗的森林中弥漫着神秘雾气，\n据说深处藏着古老的卡牌碎片。", "difficulty": "简单", "diff_color": Color("#5cb85c"), "recommend": "推荐战力：100", "bg_color": Color("#1a3a2a"), "icon": "🌲"},
	{"id": "flame_cavern", "name": "🔥 火焰洞穴", "desc": "灼热的岩浆在地底流淌，\n火焰精灵守护着珍贵的火系素材。", "difficulty": "普通", "diff_color": Color("#e8a838"), "recommend": "推荐战力：300", "bg_color": Color("#3a1a0a"), "icon": "🔥"},
	{"id": "duel", "name": "⚔ 决斗场", "desc": "与服务器上的其他玩家卡组进行虚拟对战！\n选择你的卡组，随机匹配对手。", "difficulty": "匹配", "diff_color": Color("#e8a838"), "recommend": "无限制", "bg_color": Color(0.25, 0.10, 0.15), "icon": "⚔"},
]
const MATERIAL_NAME_TO_ID := {
	"骨胶": "B01", "鱼鳔胶": "B02", "树汁胶": "B03", "精灵胶": "B04",
	"炎胶": "B05", "风凝胶": "B06", "冰胶": "B07", "龙涎胶": "B08",
	"清水": "E01", "生命露水": "E02", "月光露": "E03",
	"火焰精华": "E04", "熔岩之息": "E05", "风之灵息": "E06",
	"雷暴精华": "E07", "冰霜精华": "E08", "虚空精华": "E09", "圣光露": "E10",
	"白麻纤维": "F01", "青藤纤维": "F02", "枯草纤维": "F03",
	"月光麻": "F04", "火焰苔藓": "F05", "熔岩藤": "F06",
	"风暴棉": "F07", "雷纹藤": "F08", "冰霜亚麻": "F09",
	"暗影藤": "F10", "光之丝": "F11", "传说亚麻": "F12",
	"石灰矿粉": "M01", "辉光矿粉": "M02", "砂金石粉": "M03",
	"月长石粉": "M04", "熔核矿粉": "M05", "炎晶粉末": "M06",
	"雷击矿砂": "M07", "风暴晶尘": "M08", "冰晶粉末": "M09",
	"暗铁砂": "M10", "圣光石粉": "M11", "星辰粉末": "M12",
	"炭黑": "P01", "朱砂": "P02", "赭石": "P03",
	"石青": "P04", "硫磺黄": "P05", "云母粉": "P06",
	"雷晶粉": "P07", "冰蓝": "P08", "暗晶粉": "P09", "金粉": "P10",
	"普通松脂": "R01", "琥珀树脂": "R02",
	"古树树脂": "R03", "熔岩树脂": "R04", "龙血树脂": "R05",
	"风泪树脂": "R06", "冰霜琥珀": "R07", "暗影树脂": "R08",
}
const AUX_NAME_TO_ID := {
	"新生嫩芽": "AU16", "木质纤维": "AU17", "鹿角碎片": "AU18",
	"雾绒": "AU19", "孢子囊": "AU20", "蘑菇伞盖": "AU21",
	"草蜥蜴鳞片": "AU22", "蜥蜴尾": "AU23", "螳螂刀臂": "AU24",
	"螳螂翅膜": "AU25", "蛇鳞片": "AU26", "毒液囊": "AU27",
	"岩石核心": "AU28", "矿脉石鳞": "AU29", "熔岩核心": "AU30",
	"火鳞粉": "AU31", "暗晶尾刺": "AU32", "暗晶碎片": "AU33",
	"纯净水心": "AU34", "水纹护符": "AU35", "风蝶翅粉": "AU36",
	"轻羽": "AU37", "棱镜碎片": "AU38", "圣光余晖": "AU39",
	"巨人之心": "AU40", "山岩石板": "AU41", "暗影翎羽": "AU42",
	"夜喙碎片": "AU43", "风暴羽": "AU44", "雷电之眼": "AU45",
	"蛛丝囊": "AU46", "毒牙": "AU47", "熔岩龟甲": "AU48",
	"火核": "AU49", "幻光翅粉": "AU50", "圣光蝶翼": "AU51",
	"迷雾结晶": "AU52", "守护之核": "AU53",
}
const ENEMY_NAME_TO_DATA := {
	"树苗精": {"id": "MF_FOREST_M1", "level": 2, "hp": 20, "element": "地", "desc": "迷雾森林中最常见的低阶精灵，由古木精华凝聚而成。", "aux_drops": ["AU16", "AU17"]},
	"雾角鹿": {"id": "MF_FOREST_M2", "level": 3, "hp": 25, "element": "风", "desc": "沐浴在迷雾中生长的灵鹿，双角能凝聚雾气形成幻影。", "aux_drops": ["AU18", "AU19"]},
	"蘑菇人": {"id": "MF_FOREST_M3", "level": 4, "hp": 30, "element": "地", "desc": "寄宿在古树根部的蘑菇精灵，擅长用毒孢子折磨对手。", "aux_drops": ["AU20", "AU21"]},
	"草蜥蜴": {"id": "MF_GRASS_M1", "level": 5, "hp": 30, "element": "火", "desc": "草丛中潜伏的火焰蜥蜴。", "aux_drops": ["AU22", "AU23"]},
	"螳螂刀客": {"id": "MF_GRASS_M2", "level": 6, "hp": 35, "element": "风", "desc": "草丛中的顶级猎手，双臂如镰刀般锋利。", "aux_drops": ["AU24", "AU25"]},
	"青鳞蛇": {"id": "MF_GRASS_M3", "level": 7, "hp": 40, "element": "水", "desc": "草丛深处的剧毒之蛇。", "aux_drops": ["AU26", "AU27"]},
	"岩石傀儡": {"id": "MF_MINE_M1", "level": 8, "hp": 50, "element": "地", "desc": "矿区深处的岩石守卫。", "aux_drops": ["AU28", "AU29"]},
	"熔岩蠕虫": {"id": "MF_MINE_M2", "level": 9, "hp": 50, "element": "火", "desc": "盘踞在矿区岩浆裂隙中的巨型蠕虫。", "aux_drops": ["AU30", "AU31"]},
	"暗晶蝎": {"id": "MF_MINE_M3", "level": 10, "hp": 55, "element": "暗", "desc": "矿区深处吸收暗晶能量变异而成的巨蝎。", "aux_drops": ["AU32", "AU33"]},
	"水元素": {"id": "MF_VALLEY_M1", "level": 11, "hp": 55, "element": "水", "desc": "溪谷深处的纯净水元素。", "aux_drops": ["AU34", "AU35"]},
	"风灵蝶": {"id": "MF_VALLEY_M2", "level": 12, "hp": 55, "element": "风", "desc": "在溪谷上空翩翩起舞的精灵蝴蝶。", "aux_drops": ["AU36", "AU37"]},
	"光棱镜": {"id": "MF_VALLEY_M3", "level": 13, "hp": 65, "element": "光", "desc": "溪谷深处的水晶棱镜。", "aux_drops": ["AU38", "AU39"]},
	"岩石巨人": {"id": "MF_MOUNTAIN_M1", "level": 14, "hp": 65, "element": "地", "desc": "山道上的巨型岩石构造体。", "aux_drops": ["AU40", "AU41"]},
	"暗影鸦": {"id": "MF_MOUNTAIN_M2", "level": 15, "hp": 60, "element": "暗", "desc": "盘旋在山道暗影中的漆黑巨鸦。", "aux_drops": ["AU42", "AU43"]},
	"风暴鹰": {"id": "MF_MOUNTAIN_M3", "level": 16, "hp": 70, "element": "风", "desc": "山道之巅的风暴之王。", "aux_drops": ["AU44", "AU45"]},
	"暗穴蜘蛛": {"id": "MF_CAVE_M1", "level": 17, "hp": 70, "element": "暗", "desc": "暗穴深处编织巨网的巨型蜘蛛。", "aux_drops": ["AU46", "AU47"]},
	"熔岩龟": {"id": "MF_CAVE_M2", "level": 18, "hp": 75, "element": "火", "desc": "暗穴地底岩浆池中沉睡的远古巨龟。", "aux_drops": ["AU48", "AU49"]},
	"幻光蝶": {"id": "MF_CAVE_M3", "level": 19, "hp": 80, "element": "光", "desc": "暗穴中最神秘的存在，幻光蝶的翅膀散发着柔和的光芒。", "aux_drops": ["AU50", "AU51"]},
	"古木": {"id": "MF_BOSS_1", "level": 20, "hp": 100, "element": "地", "desc": "迷雾森林的远古守护者。", "aux_drops": ["AU52", "AU53"]},
	"烈焰": {"id": "MF_BOSS_2", "level": 20, "hp": 100, "element": "火", "desc": "迷雾森林的狂暴守护者。", "aux_drops": ["AU52", "AU53"]},
	"暗影": {"id": "MF_BOSS_3", "level": 20, "hp": 100, "element": "暗", "desc": "迷雾森林的诡秘守护者。", "aux_drops": ["AU52", "AU53"]},
	"岩浆": {"id": "FC_BOSS_1", "level": 30, "hp": 150, "element": "火", "desc": "火焰洞穴的BOSS。", "aux_drops": ["AU54", "AU1"]},
	"熔核": {"id": "FC_BOSS_2", "level": 30, "hp": 150, "element": "火", "desc": "火焰洞穴的BOSS。", "aux_drops": ["AU57", "AU58"]},
	"炎魔": {"id": "FC_BOSS_3", "level": 30, "hp": 150, "element": "火", "desc": "火焰洞穴的BOSS。", "aux_drops": ["AU2", "AU56"]},
	"雷电": {"id": "ST_BOSS_1", "level": 40, "hp": 200, "element": "风", "desc": "风暴高塔的BOSS。", "aux_drops": []},
	"风暴": {"id": "ST_BOSS_2", "level": 40, "hp": 200, "element": "风", "desc": "风暴高塔的BOSS。", "aux_drops": []},
	"云龙": {"id": "ST_BOSS_3", "level": 40, "hp": 200, "element": "风", "desc": "风暴高塔的BOSS。", "aux_drops": []},
}
var _guide_press_timer: float = 0.0
var _guide_pressed_label = null
var _guide_press_start_pos: Vector2 = Vector2.ZERO
var _guide_press_index: int = -1
const GUIDE_LONG_PRESS_TIME := 0.5
const GUIDE_DRAG_THRESHOLD := 30.0

func _ready():
	super._ready()
	var _t0 = Time.get_ticks_msec()
	set_process(true)
	var back := get_node_or_null("BackBtn")
	if back is Button: back.pressed.connect(_on_back)
	var switch_btn := get_node_or_null("BottomDeckSwitchBtn")
	if switch_btn is Button: switch_btn.pressed.connect(_on_bottom_deck_switch)
	var help_btn := get_node_or_null("HelpBtn")
	if help_btn is Button: help_btn.pressed.connect(_on_help)
	var tut_btn := get_node_or_null("MapScroll/MapList/TutorialCard/TutorialInfo/TutorialBtn")
	if tut_btn is Button: tut_btn.pressed.connect(_on_tutorial_battle_pressed)
	for i in range(3):
		var eb := get_node_or_null("MapScroll/MapList/MapCard_%d/MapExploreBtn_%d" % [i, i])
		if eb is Button and i < _maps.size():
			eb.pressed.connect(_on_explore.bind(_maps[i]["id"], _maps[i]["name"]))
	_refresh_map_cards()
	_refresh_bottom_deck_name()
	print("[Exploration] _ready 完成: %dms" % [Time.get_ticks_msec() - _t0])

func _refresh_map_cards():
	var tut_card = get_node_or_null("MapScroll/MapList/TutorialCard")
	if tut_card:
		tut_card.visible = (TutorialManager.get_progress() == TutorialManager.PROGRESS_AWAKENED)
	for i in range(_maps.size()):
		var data = _maps[i]
		var card = get_node_or_null("MapScroll/MapList/MapCard_%d" % i)
		if not card: continue
		card.visible = true
		var ps = StyleBoxFlat.new()
		ps.bg_color = data["bg_color"]
		ps.border_width_left = 2; ps.border_width_right = 2
		ps.border_width_top = 2; ps.border_width_bottom = 2
		ps.border_color = data["diff_color"]
		ps.corner_radius_top_left = 20; ps.corner_radius_top_right = 20
		ps.corner_radius_bottom_left = 20; ps.corner_radius_bottom_right = 20
		card.add_theme_stylebox_override("panel", ps)
		var dl := card.get_node_or_null("MapInfo_%d/MapDiff_%d" % [i, i])
		if dl is Label: dl.add_theme_color_override("font_color", data["diff_color"])
		# 探索按钮：4 态样式（圆角 + 难度色描边）
		var eb2 := card.get_node_or_null("MapExploreBtn_%d" % i)
		if eb2 is Button:
			var base_c = data["diff_color"]
			for state in ["normal", "hover", "pressed", "focus"]:
				var es = StyleBoxFlat.new()
				es.bg_color = base_c if state == "normal" else (base_c.lightened(0.15) if state == "hover" else base_c.darkened(0.2))
				es.border_width_left = 2; es.border_width_right = 2
				es.border_width_top = 2; es.border_width_bottom = 2
				es.border_color = base_c.lightened(0.2)
				es.corner_radius_top_left = 12; es.corner_radius_top_right = 12
				es.corner_radius_bottom_left = 12; es.corner_radius_bottom_right = 12
				es.content_margin_left = 16; es.content_margin_right = 16
				es.content_margin_top = 8; es.content_margin_bottom = 8
				eb2.add_theme_stylebox_override(state, es)

func _refresh_bottom_deck_name():
	var dl = get_node_or_null("BottomDeckName")
	if dl is Label:
		dl.text = Global.current_deck_name if Global.current_deck_name != "" else "未选择卡组"

func _get_bar_names() -> Array:
	return ["TopBar", "BottomBar", "BottomDeckBar"]

func _get_bar_line_names() -> Array:
	return ["TopBarLine", "BottomBarLine", "BottomDeckBarLine"]

func _get_themed_button_names() -> Array:
	return ["BackBtn", "BottomDeckSwitchBtn", "HelpBtn"]

func _apply_theme_custom():
	var dn = get_node_or_null("BottomDeckName")
	if dn is Label: dn.add_theme_color_override("font_color", Global.current.title)

func _on_back(): Global.play_sfx("click"); Global.change_scene("res://Main.tscn")

func _on_tutorial_battle_pressed():
	Global.play_sfx("click")
	var popup = preload("res://DeckSelectPopup.gd").new()
	popup.select_only = true; popup.set_map_data("", "新手教学战")
	popup.deck_selected.connect(_on_tutorial_deck_selected)
	popup.cancelled.connect(_on_popup_cancelled)
	add_child(popup)

func _on_tutorial_deck_selected(deck_id: String, deck_name: String) -> void:
	_start_tutorial_battle(deck_id, deck_name)

func _start_tutorial_battle(deck_id: String, deck_name: String = ""):
	Global.is_tutorial_battle = true
	Global.current_enemy_data = {"name": "🥊 巷口混混", "hp": 20, "max_hp": 20, "energy": 2, "max_energy": 2, "card_datas": [
		{"name": "混混·小喽啰", "cost":1,"atk":1,"hp":1,"element":"地","fields":["街头"],"quality":"标准","star":1},
		{"name": "混混·小喽啰", "cost":1,"atk":1,"hp":1,"element":"地","fields":["街头"],"quality":"标准","star":1},
		{"name": "混混·小喽啰", "cost":1,"atk":1,"hp":1,"element":"地","fields":["街头"],"quality":"标准","star":1},
		{"name": "混混·小喽啰", "cost":2,"atk":2,"hp":2,"element":"地","fields":["街头"],"quality":"标准","star":1},
		{"name": "混混·小喽啰", "cost":2,"atk":2,"hp":2,"element":"地","fields":["街头"],"quality":"标准","star":1},
		{"name": "混混·小喽啰", "cost":3,"atk":3,"hp":3,"element":"地","fields":["街头"],"quality":"标准","star":1}]}
	Global.current_deck_id = deck_id; Global.current_deck_name = deck_name
	Global.current_map_id = ""; Global.current_map_name = "🥊 新手教学战"
	Global.current_battle_terrain = ""; Global.current_is_boss = false
	Global.change_scene(Global.get_battle_scene_path())

func _on_explore(map_id: String, map_name: String) -> void:
	Global.play_sfx("click")
	print("[野外探索] 选择地图: ", map_name, " (", map_id, ")")
	if map_id == "duel":
		# 决斗场：预选卡组需检查租借耐久（决斗场扣1点）
		if Global.current_deck_id == "":
			var popup = preload("res://DeckSelectPopup.gd").new()
			popup.select_only = true; popup._is_duel = true
			popup.deck_selected.connect(_on_duel_deck_selected)
			popup.cancelled.connect(_on_popup_cancelled)
			add_child(popup)
		else:
			if not _check_and_consume_rented(true): return
			_on_duel_deck_selected(Global.current_deck_id, Global.current_deck_name)
		return

	# 探索：预选卡组需检查租借耐久（探索扣3点）
	if Global.current_deck_id == "":
		var popup = preload("res://DeckSelectPopup.gd").new()
		popup.set_map_data(map_id, map_name)
		popup._is_duel = false
		popup.deck_selected.connect(_on_deck_selected)
		popup.cancelled.connect(_on_popup_cancelled)
		add_child(popup)
	else:
		if not _check_and_consume_rented(false): return
		_enter_map(map_id, map_name)

## 预选租借卡组进入前：检查耐久 + 扣减。返回 false 表示耐久不足/已失效
func _check_and_consume_rented(is_duel: bool) -> bool:
	var rid = Global.current_rented_deck_id
	if rid == "": return true  # 非租借卡组，放行
	var rd = Global.get_rented_deck(rid)
	if rd.is_empty():
		_show_toast("⚠️ 租借卡组已失效")
		Global.current_rented_deck_id = ""; Global.current_deck_id = ""; Global.current_deck_name = ""
		_refresh_bottom_deck_name()
		return false
	var dur = int(rd.get("durability", 0))
	var cost = Global.RENT_DUR_COST_DUEL if is_duel else Global.RENT_DUR_COST_EXPLORE
	if dur < cost:
		_show_toast("⚠️ 租借卡组耐久不足！\n剩 " + str(dur) + " 点，本次需 " + str(cost) + " 点")
		return false
	Global.consume_rented_durability(rid, cost)
	return true
func _show_toast(text: String) -> void:
	var existing = get_node_or_null("ExploreToast")
	if existing: existing.queue_free()
	var overlay = ColorRect.new(); overlay.name = "ExploreToast"
	overlay.color = Color(0, 0, 0, 0.65)
	overlay.anchor_left = 0.0; overlay.anchor_top = 0.0; overlay.anchor_right = 1.0; overlay.anchor_bottom = 1.0
	overlay.mouse_filter = MOUSE_FILTER_STOP
	add_child(overlay)
	var lbl = Label.new(); lbl.text = text
	lbl.add_theme_font_size_override("font_size", 45); lbl.add_theme_color_override("font_color", Color("#FF5252"))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.anchor_left = 0.0; lbl.anchor_top = 0.0; lbl.anchor_right = 1.0; lbl.anchor_bottom = 1.0
	overlay.add_child(lbl)
	var btn = Button.new(); btn.text = "知道了"; btn.add_theme_font_size_override("font_size", 40)
	btn.anchor_left = 0.3; btn.anchor_top = 0.62; btn.anchor_right = 0.7; btn.anchor_bottom = 0.70
	btn.pressed.connect(func(): overlay.queue_free())
	overlay.add_child(btn)

func _enter_map(map_id: String, map_name: String) -> void:
	Global.current_map_id = map_id; Global.current_map_name = map_name
	Global.saved_map_node_data = []; Global.current_map_layer = -1; Global.current_map_node = -1
	Global.current_run_player_hp = PlayerManager.get_guild_max_hp()
	Global.current_run_player_max_hp = PlayerManager.get_guild_max_hp()
	Global.change_scene("res://MapNodeScene.tscn")

func _on_deck_selected(deck_id: String, deck_name: String) -> void:
	Global.current_deck_id = deck_id; Global.current_deck_name = deck_name
	_refresh_bottom_deck_name()

func _on_popup_cancelled() -> void: print("[野外探索] 取消选择卡组")

func _on_duel_deck_selected(deck_id: String, deck_name: String) -> void:
	print("[决斗场] 已选自己的卡组: ", deck_name, " (", deck_id, ")")
	var pool := []
	for sdeck in Global.server_decks:
		var dd = sdeck.get("deck_data", {})
		if dd.size() > 0 and (dd.get("cards", []).size() > 0 or dd.get("card_datas", []).size() > 0):
			pool.append(dd)
	for did in CardManager.get_all_decks():
		# 排除当前携带的卡组（租借卡组id不属于本地牌库，不参与排除）
		if did == deck_id: continue
		var ld = CardManager.get_all_decks()[did]
		if ld.get("cards", []).size() > 0: pool.append(ld)
	if pool.size() == 0:
		var own = CardManager.get_deck(deck_id)
		if own.get("cards", []).size() > 0: pool.append(own)
		else: return
	var rng = RandomNumberGenerator.new(); rng.randomize()
	var chosen = pool[rng.randi_range(0, pool.size() - 1)]
	var opp_name = chosen.get("name", "未知卡组")
	var card_datas := []
	var full = chosen.get("card_datas", [])
	if full is Array and full.size() > 0: card_datas = full.duplicate(true)
	else:
		for cid in chosen.get("cards", []):
			for cd in CardManager.get_all_cards():
				if cd.get("id","") == cid or cd.get("template_id","") == cid:
					card_datas.append(cd.duplicate(true)); break
	if card_datas.size() == 0: return
	Global.current_enemy_data = {"name": "决斗者·" + opp_name, "hp": 50, "max_hp": 50, "energy": 3, "max_energy": 3, "card_datas": card_datas}
	Global.current_deck_id = deck_id; Global.current_deck_name = deck_name
	Global.current_map_id = ""; Global.current_map_name = "⚔ 决斗场"
	Global.current_battle_terrain = ""; Global.current_is_boss = false
	Global.change_scene(Global.get_battle_scene_path())

func _on_help(): Global.play_sfx("click"); _show_help_guide()

func _show_help_guide():
	var overlay = ColorRect.new()
	overlay.name = "HelpOverlay"; overlay.color = Color(0,0,0,0.7)
	overlay.anchor_left = 0.0; overlay.anchor_top = 0.0; overlay.anchor_right = 1.0; overlay.anchor_bottom = 1.0
	overlay.mouse_filter = MOUSE_FILTER_STOP
	overlay.gui_input.connect(func(ev): 
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT: overlay.queue_free())
	add_child(overlay)
	var panel = Panel.new()
	panel.name = "HelpPanel"; panel.anchor_left = 0.05; panel.anchor_top = 0.05; panel.anchor_right = 0.95; panel.anchor_bottom = 0.95
	panel.clip_contents = true
	var ps = StyleBoxFlat.new()
	ps.bg_color = Global.current.bg; ps.border_width_left = 3; ps.border_width_right = 3; ps.border_width_top = 3; ps.border_width_bottom = 3
	ps.border_color = Color("#e8a838"); ps.corner_radius_top_left = 16; ps.corner_radius_top_right = 16
	ps.corner_radius_bottom_left = 16; ps.corner_radius_bottom_right = 16
	panel.add_theme_stylebox_override("panel", ps); overlay.add_child(panel)
	var title = Label.new()
	title.text = "📖 野外探索指南"; title.add_theme_font_size_override("font_size", 60)
	title.add_theme_color_override("font_color", Global.current.title)
	title.horizontal_alignment = 1; title.anchor_left = 0.0; title.anchor_top = 0.0; title.anchor_right = 1.0; title.anchor_bottom = 0.0
	title.offset_left = 0; title.offset_top = Global.ph(0.01); title.offset_right = 0; title.offset_bottom = Global.ph(0.08)
	panel.add_child(title)
	var scroll = ScrollContainer.new()
	scroll.name = "HelpScroll"
	scroll.anchor_left = 0.02; scroll.anchor_top = 0.0; scroll.anchor_right = 0.98; scroll.anchor_bottom = 1.0
	scroll.offset_left = 0; scroll.offset_top = Global.ph(0.085); scroll.offset_right = 0; scroll.offset_bottom = Global.ph(-0.08)
	scroll.scroll_horizontal = false; panel.add_child(scroll)
	var vbox = VBoxContainer.new()
	vbox.name = "HelpVBox"; vbox.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	vbox.add_theme_constant_override("separation", Global.ph(0.008)); scroll.add_child(vbox)
	_build_help_content(vbox)
	call_deferred("_set_help_vbox_width", vbox, scroll)
	var close_btn = Button.new()
	close_btn.text = "✕ 关闭"; close_btn.add_theme_font_size_override("font_size", 50)
	var cs = StyleBoxFlat.new()
	cs.bg_color = Global.current.btn_bg; cs.border_width_left = 2; cs.border_width_right = 2; cs.border_width_top = 2; cs.border_width_bottom = 2
	cs.border_color = Color("#888888"); cs.corner_radius_top_left = 10; cs.corner_radius_top_right = 10
	cs.corner_radius_bottom_left = 10; cs.corner_radius_bottom_right = 10
	close_btn.add_theme_stylebox_override("normal", cs)
	close_btn.add_theme_color_override("font_color", Global.current.btn_text)
	close_btn.anchor_left = 0.3; close_btn.anchor_top = 1.0; close_btn.anchor_right = 0.7; close_btn.anchor_bottom = 1.0
	close_btn.offset_left = 0; close_btn.offset_top = Global.ph(-0.075); close_btn.offset_right = 0; close_btn.offset_bottom = Global.ph(-0.01)
	close_btn.pressed.connect(func(): Global.play_sfx("click"); overlay.queue_free()); panel.add_child(close_btn)

func _set_help_vbox_width(vbox, scroll):
	if not is_instance_valid(vbox) or not is_instance_valid(scroll): return
	var w = scroll.size.x; if w <= 0: w = get_viewport_rect().size.x * 0.85
	vbox.custom_minimum_size = Vector2(w, 0)

func _make_help_section(vbox, title_text, title_color):
	var section = VBoxContainer.new()
	section.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	section.add_theme_constant_override("separation", Global.ph(0.005)); vbox.add_child(section)
	var sep = HSeparator.new()
	sep.add_theme_color_override("color", Global.current.topbar_border)
	sep.size_flags_horizontal = SIZE_FILL; section.add_child(sep)
	var lbl = Label.new()
	lbl.text = title_text; lbl.add_theme_font_size_override("font_size", 50)
	lbl.add_theme_color_override("font_color", title_color)
	lbl.size_flags_horizontal = SIZE_FILL; lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	section.add_child(lbl); return section

func _make_help_label(vbox, text, color = Color("#FFFFFF"), font_size = 45):
	var lbl = Label.new()
	lbl.text = text; lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.size_flags_horizontal = SIZE_FILL; vbox.add_child(lbl)

func _build_help_content(vbox):
	var s1 = _make_help_section(vbox, "🗺️ ① 野外探索简介", Color("#5cb85c"))
	_make_help_label(s1, "选择地图进入爬塔探索，每层可选择战斗或采集。", Global.current.btn_text, 42)
	_make_help_label(s1, "击败卡兽可获得辅材掉落，采集可获得制作素材。", Color("#CCCCCC"))
	_make_help_label(s1, "通关全部8层并击败BOSS即可获得胜利！", Color("#CCCCCC"))
	var s2 = _make_help_section(vbox, "🌲 ② 迷雾森林 · 掉落一览", Color("#5cb85c"))
	_make_help_label(s2, "难度：简单 | 推荐战力：100", Color("#AAAAAA"))
	_make_help_label(s2, "🌲 树林采集：", Color("#8BC34A"), 48)
	_make_help_label(s2, "  • 白麻纤维 (普通) prob:70%", Color("#CCCCCC"))
	_make_help_label(s2, "  • 青藤纤维 (普通) prob:70%", Color("#CCCCCC"))
	_make_help_label(s2, "  • 普通松脂 (普通) prob:70%", Color("#CCCCCC"))
	_make_help_label(s2, "  • 骨胶 (普通) prob:70%", Color("#CCCCCC"))
	_make_help_label(s2, "🌿 草丛采集：", Color("#FF9800"), 48)
	_make_help_label(s2, "  • 生命露水 (普通) prob:70%", Color("#CCCCCC"))
	_make_help_label(s2, "  • 炭黑 (普通) prob:70%", Color("#CCCCCC"))
	_make_help_label(s2, "  • 朱砂 (普通) prob:70%", Color("#CCCCCC"))
	_make_help_label(s2, "⛏️ 矿区采集：", Color("#9B59B6"), 48)
	_make_help_label(s2, "  • 石灰矿粉 (普通) prob:70%", Color("#CCCCCC"))
	_make_help_label(s2, "  • 辉光矿粉 (普通) prob:70%", Color("#CCCCCC"))
	_make_help_label(s2, "💧 溪谷采集：", Color("#3498DB"), 48)
	_make_help_label(s2, "  • 砂金石粉 (普通) prob:70%", Color("#CCCCCC"))
	_make_help_label(s2, "  • 清水 (普通) prob:70%", Color("#CCCCCC"))
	_make_help_label(s2, "  • 鱼鳔胶 (普通) prob:70%", Color("#CCCCCC"))
	_make_help_label(s2, "🌪️ 山道采集：", Color("#E87D38"), 48)
	_make_help_label(s2, "  • 枯草纤维 (普通) prob:70%", Color("#CCCCCC"))
	_make_help_label(s2, "  • 赭石 (普通) prob:70%", Color("#CCCCCC"))
	_make_help_label(s2, "🌑 暗穴采集：", Color("#8E44AD"), 48)
	_make_help_label(s2, "  • 琥珀树脂 (普通) prob:70%", Color("#CCCCCC"))
	_make_help_label(s2, "  • 树汁胶 (普通) prob:70%", Color("#CCCCCC"))

func _on_bottom_deck_switch():
	Global.play_sfx("click")
	var popup = preload("res://DeckSelectPopup.gd").new()
	popup.select_only = true
	popup.deck_selected.connect(_on_bottom_deck_selected)
	popup.cancelled.connect(_on_popup_cancelled)
	add_child(popup)

func _on_bottom_deck_selected(deck_id: String, deck_name: String) -> void:
	Global.current_deck_id = deck_id; Global.current_deck_name = deck_name
	_refresh_bottom_deck_name()

func _process(_delta):
	if _guide_pressed_label != null:
		_guide_press_timer += _delta
		if _guide_press_timer >= GUIDE_LONG_PRESS_TIME:
			_show_guide_material_detail(_guide_pressed_label)
			_guide_cancel_press()

func _input(event):
	if event is InputEventScreenTouch:
		if event.pressed:
			var label = _find_guide_material_label_at(event.position)
			if label != null:
				_guide_pressed_label = label; _guide_press_timer = 0.0
				_guide_press_start_pos = event.position; _guide_press_index = event.index
				label.add_theme_color_override("font_color", Color("#FFD700"))
		elif event.index == _guide_press_index: _guide_cancel_press()
	elif event is InputEventScreenDrag:
		if _guide_pressed_label != null and event.index == _guide_press_index:
			if event.position.distance_to(_guide_press_start_pos) > GUIDE_DRAG_THRESHOLD: _guide_cancel_press()

func _find_guide_material_label_at(pos: Vector2):
	var scroll = get_node_or_null("HelpScroll")
	if not scroll or not scroll.visible: return null
	for c in get_tree().get_nodes_in_group("guide_material"):
		if c is Label:
			var rect = Rect2(c.get_global_rect().position, c.get_global_rect().size)
			if rect.has_point(pos): return c
	return null

func _guide_cancel_press():
	if _guide_pressed_label != null:
		_guide_pressed_label.add_theme_color_override("font_color", Color("#CCCCCC"))
	_guide_pressed_label = null; _guide_press_timer = 0.0; _guide_press_index = -1

func _show_guide_material_detail(label):
	var text = label.text
	var mat_id = MATERIAL_NAME_TO_ID.get(text.strip_edges(), "")
	if mat_id != "":
		var mat = Global.get_material_by_id(mat_id)
		if mat.size() > 0: _show_detail_popup(mat.get("name", text), mat.get("desc", ""), mat.get("rarity", "普通"))
	var aux_id = AUX_NAME_TO_ID.get(text.strip_edges(), "")
	if aux_id != "":
		var aux = Global.get_aux_by_id(aux_id)
		if aux.size() > 0: _show_detail_popup(aux.get("name", text), aux.get("desc", ""), aux.get("rarity", "普通"))

func _show_detail_popup(name, desc, rarity):
	var overlay = ColorRect.new()
	overlay.name = "MatDetailOverlay"; overlay.color = Color(0,0,0,0.7)
	overlay.anchor_left = 0.0; overlay.anchor_top = 0.0; overlay.anchor_right = 1.0; overlay.anchor_bottom = 1.0
	overlay.mouse_filter = MOUSE_FILTER_STOP
	overlay.gui_input.connect(func(ev): if ev is InputEventMouseButton and ev.pressed: overlay.queue_free())
	add_child(overlay)
	var panel = Panel.new()
	panel.anchor_left = 0.15; panel.anchor_top = 0.3; panel.anchor_right = 0.85; panel.anchor_bottom = 0.7
	var ps = StyleBoxFlat.new()
	ps.bg_color = Global.current.bg; ps.border_width_left = 2; ps.border_width_right = 2; ps.border_width_top = 2; ps.border_width_bottom = 2
	ps.border_color = Color("#5cb85c"); ps.corner_radius_top_left = 16; ps.corner_radius_top_right = 16
	ps.corner_radius_bottom_left = 16; ps.corner_radius_bottom_right = 16
	panel.add_theme_stylebox_override("panel", ps); overlay.add_child(panel)
	var tl = Label.new()
	tl.text = name; tl.add_theme_font_size_override("font_size", 60)
	tl.add_theme_color_override("font_color", Global.current.title)
	tl.horizontal_alignment = 1; tl.anchor_left = 0.0; tl.anchor_top = 0.0; tl.anchor_right = 1.0; tl.anchor_bottom = 0.0
	tl.offset_top = Global.ph(0.02); tl.offset_bottom = Global.ph(0.25); panel.add_child(tl)
	var dl = Label.new()
	dl.text = desc; dl.add_theme_font_size_override("font_size", 40)
	dl.add_theme_color_override("font_color", Color("#CCCCCC"))
	dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dl.anchor_left = 0.05; dl.anchor_top = 0.0; dl.anchor_right = 0.95; dl.anchor_bottom = 1.0
	dl.offset_top = Global.ph(0.25); dl.offset_bottom = Global.ph(-0.1); panel.add_child(dl)