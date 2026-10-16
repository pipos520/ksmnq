extends Control
## 卡包商店 —— 开包界面
var _hj_ads: HJAdsNode = null
var _pending_pack_id: String = ""
var _press_timer: float = 0.0
var _pressed_row: Control = null
var _press_start_pos: Vector2 = Vector2.ZERO
var _press_index: int = -1
const LONG_PRESS_TIME := 0.5
const DRAG_THRESHOLD := 30.0
# 卡包列表长按（独立于结果弹窗）
var _pack_press_timer: float = 0.0
var _pressed_pack: Control = null
# 主题(系列)长按
var _theme_press_timer: float = 0.0
var _pressed_theme: Control = null
var _theme_press_start: Vector2 = Vector2.ZERO
var _theme_press_index: int = -1
var _pack_press_start: Vector2 = Vector2.ZERO
var _pack_press_index: int = -1
# 官网基础URL（GitHub Pages 部署）
const OFFICIAL_BASE_URL := "https://pipos52.github.io/kashi-simulator/"
# pack_id → 官网页面+锚点映射表（官网按系列主题分区块，与游戏pack_id命名不同，故需显式映射）
const PACK_WIKI_MAP := {
	# ===== 沧澜系（worldview.html）=====
	"qp_jianxiu": "worldview.html#qingyun", "qp_fuxiu": "worldview.html#qingyun", "qp_zhenxiu": "worldview.html#qingyun", "qp_kongxin": "worldview.html#qingyun", "qy_jiujian": "worldview.html#qingyun",
	"dy_beijing": "worldview.html#dayong", "dy_zhilv": "worldview.html#dayong",
	"bl_haoran": "worldview.html#bailu", "bl_wenming": "worldview.html#bailu",
	"ty_shenzhong": "worldview.html#taiyi", "ty_fengshan": "worldview.html#taiyi",
	"sy_jiye": "worldview.html#shuangyue", "sy_yuejian": "worldview.html#shuangyue",
	"hj_xianghuo": "worldview.html#huangjin", "hj_kuhai": "worldview.html#huangjin",
	"dl_yuanqi": "worldview.html#donglan", "dl_gueixu": "worldview.html#donglan",
	"nj_zushen": "worldview.html#nanjiang", "nj_wuzibei": "worldview.html#nanjiang",
	"wm_wuming": "worldview.html#wuming", "wm_guzhan": "worldview.html#guzhan",
	# ===== 三约系（worldview_sy.html）=====
	"syjy_qw": "worldview_sy.html#qw", "syjy_wf": "worldview_sy.html#wf", "syjy_sg": "worldview_sy.html#sg", "syjy_sy": "worldview_sy.html#sy",
	"syjy_lj": "worldview_sy.html#lj", "syjy_yl": "worldview_sy.html#yl", "syjy_hs": "worldview_sy.html#hs", "syjy_sd": "worldview_sy.html#sd",
	# ===== 其他（worldview_nbd.html，无卡包级锚点，跳到卡牌区）=====
	"wq_shoutan": "worldview_nbd.html#cards", "nbd_rl": "worldview_nbd.html#cards",
}
# 主题分层：空=显示主题列表，非空=显示该主题下的卡包
var _current_theme: String = ""

# ===== 系列(主题)长按详情：简介 + 官网入口 =====
# 主题 → 官网页面入口（系列级，跳到对应世界观主页）
const THEME_WIKI_MAP := {
	"沧澜古界": "worldview.html",
	"三约纪元": "worldview_sy.html",
	"围棋": "worldview_nbd.html",
	"你不对劲": "worldview_nbd.html",
	"热恋期": "worldview_nbd.html",
}
# 主题 → 系列简介
const THEME_DESC_MAP := {
	"沧澜古界": "沧澜古界，诸国林立，剑修、符修、阵修争锋。大雍北境铁骑铮铮，白鹿书院浩然正气，太一门神钟卫道，霜月妖庭极夜降临……这是一片充满传说与纷争的古老大陆。",
	"三约纪元": "三约纪元，灰冠墟、万法之塔、圣光教廷、深渊猎魔……七王骑士团与万法议会并立，圣光与深渊交织。三份古老约定维系着世界的平衡，而如今，约定正在松动。",
	"围棋": "方寸棋盘，纵横十九道。黑子先行，白子贴目。做眼、打入、征子、屠龙……在黑白交错间，体验最纯粹的博弈之美与东方智慧。",
	"你不对劲": "你不对劲！这是一款充满网络热梗与无厘头笑料的搞怪卡包。冰箱里的牛奶、楼下的煎饼摊、半夜亮着的灯……那些看似日常却又处处透着「不对劲」的瞬间。",
	"热恋期": "热恋期日常，糖分超标预警。姜糖与宋迟的相识相知，从初见的心动到同居的琐碎，把甜甜的恋爱装进卡里，每一张都是心动的证明。",
}

func _ready():
	# —— 第五幕导览接力 ——
	call_deferred("_maybe_show_packshop_tour")
	# ---- 静态节点已在 CardPackShop.tscn 中声明 ----
	var back := get_node_or_null("BackBtn")
	if back is Button: back.pressed.connect(_on_back)
	# 金币显示
	var gl := get_node_or_null("GoldLabel")
	if gl is Label: gl.text = "💰 " + str(SaveManager.get_value("player", "gold", 0))
	# 主题
	Global.theme_changed.connect(_on_theme_changed)
	call_deferred("_apply_theme_styles")
	_init_ads()
	_build_theme_view()

func _init_ads():
	_hj_ads = HJAdsNode.new(); _hj_ads.name = "HJAdsNode"; add_child(_hj_ads)
	_hj_ads.app_id = "234475"; _hj_ads.rewarded_placement_id = "9701263723893953"
	_hj_ads.debug_mode = false
	_hj_ads.ad_loaded.connect(_on_ad_loaded)
	_hj_ads.video_rewarded.connect(_on_video_rewarded)
	_hj_ads.ad_closed.connect(_on_ad_closed)
	_hj_ads.ad_failed.connect(_on_ad_failed)
	_hj_ads.loadRewardedAd()

func _build_pack_list():
	# 清理旧列表（主题切换时重建，先移除再释放避免同名冲突）
	var old_scroll = get_node_or_null("PackScroll")
	if old_scroll:
		remove_child(old_scroll)
		old_scroll.queue_free()
	var scroll = ScrollContainer.new(); scroll.name = "PackScroll"
	scroll.anchor_left = 0.0; scroll.anchor_top = 0.0; scroll.anchor_right = 1.0; scroll.anchor_bottom = 1.0
	scroll.offset_left = 0; scroll.offset_top = Global.ph(0.083); scroll.offset_right = 0; scroll.offset_bottom = Global.ph(-0.083)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS; scroll.scroll_deadzone = 0; add_child(scroll)
	var vbox = VBoxContainer.new(); vbox.name = "PackList"
	vbox.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL; vbox.custom_minimum_size = Vector2(Global.pw(1.0), 0); scroll.add_child(vbox)
	
	var packs = Global.server_card_packs
	# 按当前主题过滤
	if _current_theme != "":
		var filtered = []
		for p in packs:
			if p.get("theme", "沧澜古界") == _current_theme:
				filtered.append(p)
		packs = filtered
	if packs.size() == 0:
		var empty = Label.new(); empty.text = "暂无可用卡包\n请等待服务器更新"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty.add_theme_font_size_override("font_size", 50)
		empty.add_theme_color_override("font_color", Color("#5a5a6e"))
		empty.custom_minimum_size = Vector2(0, Global.ph(0.3)); vbox.add_child(empty); return
	
	for i in range(packs.size()):
		var pack = packs[i]; var pd = pack.get("pack_data", {})
		var pid = pack.get("pack_id", pd.get("pack_id", "unknown"))
		var pname = pd.get("name", "未知卡包"); var pdesc = pd.get("desc", "")
		var cards = pd.get("cards", []); var cc = cards.size()
		
		var cp = Panel.new(); cp.name = "PackPanel_"+pid
		var ps = StyleBoxFlat.new(); ps.bg_color = Color(0.08,0.06,0.15) if i%2==0 else Color(0.10,0.08,0.18)
		ps.border_width_left=2; ps.border_width_right=2; ps.border_width_top=1; ps.border_width_bottom=1
		ps.border_color=Color(0.4,0.2,0.6,0.3); ps.corner_radius_top_left=12; ps.corner_radius_top_right=12
		ps.corner_radius_bottom_left=16; ps.corner_radius_bottom_right=16
		ps.content_margin_left=12; ps.content_margin_right=12; ps.content_margin_top=6; ps.content_margin_bottom=6
		cp.add_theme_stylebox_override("panel", ps); cp.custom_minimum_size=Vector2(0,Global.ph(0.18))
		cp.size_flags_horizontal=SIZE_EXPAND|SIZE_FILL; cp.mouse_filter=Control.MOUSE_FILTER_PASS; cp.set_meta("pack_id",pid); cp.set_meta("pack_data",pd); vbox.add_child(cp)
		
		var iv = VBoxContainer.new(); iv.size_flags_horizontal=SIZE_EXPAND|SIZE_FILL; iv.size_flags_vertical=SIZE_EXPAND|SIZE_FILL; cp.add_child(iv)
		# 第一排：卡包名 + 卡牌数量
		var tr = HBoxContainer.new(); tr.size_flags_horizontal=SIZE_EXPAND|SIZE_FILL; tr.custom_minimum_size=Vector2(0,Global.ph(0.05)); iv.add_child(tr)
		var nl = Label.new(); nl.text="🎴 "+pname; nl.add_theme_font_size_override("font_size",50)
		nl.add_theme_color_override("font_color",Color("#d4b8e8")); nl.size_flags_horizontal=SIZE_EXPAND|SIZE_FILL; tr.add_child(nl)
		var cl = Label.new(); cl.text="共 "+str(cc)+" 张"; cl.add_theme_font_size_override("font_size",35)
		cl.add_theme_color_override("font_color",Color("#8a8aa0")); cl.vertical_alignment=VERTICAL_ALIGNMENT_CENTER; tr.add_child(cl)
		# 第二排：描述
		if pdesc!="":
			var dl=Label.new(); dl.text=pdesc; dl.add_theme_font_size_override("font_size",30)
			dl.add_theme_color_override("font_color",Color("#6a6a80")); dl.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
			dl.custom_minimum_size=Vector2(0,Global.ph(0.04)); dl.size_flags_horizontal=SIZE_EXPAND|SIZE_FILL; iv.add_child(dl)
		# 第三排：金币 + 广告按钮
		var br=HBoxContainer.new(); br.size_flags_horizontal=SIZE_EXPAND|SIZE_FILL; br.size_flags_vertical=SIZE_EXPAND|SIZE_FILL
		br.alignment=BoxContainer.ALIGNMENT_CENTER; br.custom_minimum_size=Vector2(0,Global.ph(0.07)); iv.add_child(br)
		
		var gb=Button.new(); gb.text="💰 100金币"; gb.add_theme_font_size_override("font_size",45)
		var gbs=StyleBoxFlat.new(); gbs.bg_color=Color("#2a1a3a"); gbs.border_width_left=2; gbs.border_width_right=2
		gbs.border_width_top=2; gbs.border_width_bottom=2; gbs.border_color=Color("#f9d371")
		gbs.corner_radius_top_left=12; gbs.corner_radius_top_right=12; gbs.corner_radius_bottom_left=12; gbs.corner_radius_bottom_right=12
		gbs.content_margin_left=20; gbs.content_margin_right=20
		gb.add_theme_stylebox_override("normal",gbs); gb.add_theme_stylebox_override("hover",gbs)
		gb.add_theme_stylebox_override("pressed",gbs); gb.add_theme_stylebox_override("focus",gbs)
		gb.add_theme_color_override("font_color",Color("#f9d371"))
		gb.custom_minimum_size=Vector2(Global.pw(0.25),Global.ph(0.06)); gb.pressed.connect(_on_gold_open.bind(pid,pd)); br.add_child(gb)
		
		var sp=Control.new(); sp.custom_minimum_size=Vector2(Global.pw(0.04),0); br.add_child(sp)
		var ab=Button.new(); ab.text="🎬 看广告"; ab.add_theme_font_size_override("font_size",45)
		var abs=StyleBoxFlat.new(); abs.bg_color=Color("#2a1a3a"); abs.border_width_left=2; abs.border_width_right=2
		abs.border_width_top=2; abs.border_width_bottom=2; abs.border_color=Color("#6c9bcf")
		abs.corner_radius_top_left=12; abs.corner_radius_top_right=12; abs.corner_radius_bottom_left=12; abs.corner_radius_bottom_right=12
		abs.content_margin_left=20; abs.content_margin_right=20
		ab.add_theme_stylebox_override("normal",abs); ab.add_theme_stylebox_override("hover",abs)
		ab.add_theme_stylebox_override("pressed",abs); ab.add_theme_stylebox_override("focus",abs)
		ab.add_theme_color_override("font_color",Color("#6c9bcf"))
		ab.custom_minimum_size=Vector2(Global.pw(0.25),Global.ph(0.06)); ab.pressed.connect(_on_ad_open.bind(pid,pd)); br.add_child(ab)

# ============================
#  主题分层视图
# ============================
func _build_theme_view():
	# 清理旧内容（先移除再释放避免同名冲突）
	var old_scroll = get_node_or_null("PackScroll")
	if old_scroll:
		remove_child(old_scroll)
		old_scroll.queue_free()
	_current_theme = ""
	var back = get_node_or_null("BackBtn")
	if back is Button: back.text = "← 返回"
	var scroll = ScrollContainer.new(); scroll.name = "PackScroll"
	scroll.anchor_left = 0.0; scroll.anchor_top = 0.0; scroll.anchor_right = 1.0; scroll.anchor_bottom = 1.0
	scroll.offset_left = 0; scroll.offset_top = Global.ph(0.083); scroll.offset_right = 0; scroll.offset_bottom = Global.ph(-0.083)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS; scroll.scroll_deadzone = 0; add_child(scroll)
	var vbox = VBoxContainer.new(); vbox.name = "PackList"
	vbox.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL; vbox.custom_minimum_size = Vector2(Global.pw(1.0), 0); scroll.add_child(vbox)
	
	var packs = Global.server_card_packs
	if packs.size() == 0:
		var empty = Label.new(); empty.text = "暂无可用卡包\n请等待服务器更新"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty.add_theme_font_size_override("font_size", 50)
		empty.add_theme_color_override("font_color", Color("#5a5a6e"))
		empty.custom_minimum_size = Vector2(0, Global.ph(0.3)); vbox.add_child(empty); return
	
	# 收集主题（保持出现顺序，去重）
	var themes := []
	for p in packs:
		var t = p.get("theme", "沧澜古界")
		if not themes.has(t): themes.append(t)
	
	# 主题标题
	var hint = Label.new(); hint.text = "🌍 选择卡包主题"
	hint.add_theme_font_size_override("font_size", 52)
	hint.add_theme_color_override("font_color", Color("#d4b8e8"))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.custom_minimum_size = Vector2(0, Global.ph(0.07)); vbox.add_child(hint)
	var sub = Label.new(); sub.text = "共 " + str(themes.size()) + " 个主题 · " + str(packs.size()) + " 个卡包"
	sub.add_theme_font_size_override("font_size", 32)
	sub.add_theme_color_override("font_color", Color("#6a6a80"))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.custom_minimum_size = Vector2(0, Global.ph(0.04)); vbox.add_child(sub)
	
	var theme_colors := {
		"沧澜古界": Color(0.10, 0.14, 0.28),
	}
	for i in range(themes.size()):
		var tname: String = themes[i]
		var tp = Panel.new(); tp.name = "ThemePanel_" + str(i)
		var tbg = theme_colors.get(tname, Color(0.10, 0.08, 0.20))
		var tps = StyleBoxFlat.new(); tps.bg_color = tbg
		tps.border_width_left = 2; tps.border_width_right = 2; tps.border_width_top = 2; tps.border_width_bottom = 2
		tps.border_color = Color("#c9a86a"); tps.corner_radius_top_left = 16; tps.corner_radius_top_right = 16
		tps.corner_radius_bottom_left = 16; tps.corner_radius_bottom_right = 16
		tps.content_margin_left = 16; tps.content_margin_right = 16; tps.content_margin_top = 10; tps.content_margin_bottom = 10
		tp.add_theme_stylebox_override("panel", tps)
		tp.custom_minimum_size = Vector2(0, Global.ph(0.16))
		tp.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
		tp.mouse_filter = Control.MOUSE_FILTER_PASS  # 允许滑动穿透到ScrollContainer
		tp.set_meta("theme_name", tname)
		vbox.add_child(tp)
		var iv = VBoxContainer.new(); iv.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL; iv.size_flags_vertical = SIZE_EXPAND | SIZE_FILL; tp.add_child(iv)
		var tr = HBoxContainer.new(); tr.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL; tr.custom_minimum_size = Vector2(0, Global.ph(0.05)); iv.add_child(tr)
		var nl = Label.new(); nl.text = "🌍 " + tname; nl.add_theme_font_size_override("font_size", 55)
		nl.add_theme_color_override("font_color", Color("#f9d371")); nl.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL; tr.add_child(nl)
		var cnt = 0
		for p in packs:
			if p.get("theme", "沧澜古界") == tname: cnt += 1
		var cl = Label.new(); cl.text = str(cnt) + " 个卡包"; cl.add_theme_font_size_override("font_size", 38)
		cl.add_theme_color_override("font_color", Color("#8a8aa0")); cl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; tr.add_child(cl)
		var dl = Label.new(); dl.text = "👆 点击进入 · 长按详情"
		dl.add_theme_font_size_override("font_size", 32)
		dl.add_theme_color_override("font_color", Color("#6c9bcf")); dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		dl.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL; tr.add_child(dl)
		tp.gui_input.connect(_on_theme_tap.bind(tname))

func _on_theme_tap(ev: InputEvent, tname: String):
	var is_press := false
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		is_press = true
	elif ev is InputEventScreenTouch and ev.pressed:
		is_press = true
	if is_press:
		Global.play_sfx("click")
		_enter_theme(tname)

func _enter_theme(tname: String):
	_current_theme = tname
	var back = get_node_or_null("BackBtn")
	if back is Button: back.text = "← 主题"
	_build_pack_list()

func _on_gold_open(pid: String, pd: Dictionary):
	Global.play_sfx("click")
	var gold = SaveManager.get_value("player", "gold", 0)
	if gold < 100:
		_show_popup("⚠️ 金币不足！", "需要100金币\n当前: "+str(gold)+" 金币", Color("#FF5252")); return
	gold -= 100; SaveManager.set_value("player","gold",gold); SaveManager.save_to_disk(); _update_gold()
	_do_open_pack(pid, pd, true)

func _do_open_pack(pid: String, pd: Dictionary, paid_gold: bool = false):
	var result = await Global.open_card_pack(pid, 3)
	if result.has("error"):
		if paid_gold: _refund_gold(100)
		_show_popup("⚠️ 开包失败",result.error,Color("#FF5252")); return
	var picked = result.get("data",[])
	if picked.size()==0:
		if paid_gold: _refund_gold(100)
		_show_popup("⚠️ 开包失败","未获得卡牌",Color("#FF5252")); return
	for card in picked: CardManager.add_card(card)
	
	# 增加系列购买计数并检查解锁
	var series_id = _get_series_id_from_pack(pd)
	if series_id != "":
		var unlock_result = CardManager.add_series_pack_count(series_id)
		_show_pack_result(picked, pd, unlock_result)
	else:
		_show_pack_result(picked, pd)

func _refund_gold(amount: int):
	var gold = SaveManager.get_value("player", "gold", 0)
	SaveManager.set_value("player", "gold", gold + amount)
	SaveManager.save_to_disk()
	_update_gold()

## 从卡包数据获取系列ID
func _get_series_id_from_pack(pd: Dictionary) -> String:
	var pack_name = pd.get("name", "")
	# 根据卡包名匹配系列
	if "不对劲" in pack_name or "热恋期" in pack_name:
		return "nbd"
	if "围棋" in pack_name or "手谈" in pack_name:
		return "go"
	if "三约" in pack_name:
		return "syjy"
	if "沧澜" in pack_name or "古界" in pack_name:
		return "canglan"
	# 默认归入沧澜
	return "canglan"

func _show_pack_result(cards: Array, pd: Dictionary, unlock_result: Dictionary = {}):
	var pname = pd.get("name","卡包")
	var overlay=ColorRect.new(); overlay.name="ResultOverlay"
	overlay.color=Color(0,0,0,0.75); overlay.anchor_left=0.0; overlay.anchor_top=0.0
	overlay.anchor_right=1.0; overlay.anchor_bottom=1.0; overlay.mouse_filter=Control.MOUSE_FILTER_STOP
	overlay.gui_input.connect(func(ev):
		if not is_instance_valid(overlay): return
		if ev is InputEventMouseButton and not ev.pressed and ev.button_index==MOUSE_BUTTON_LEFT: overlay.queue_free())
	add_child(overlay)
	
	var panel=Panel.new(); panel.name="ResultPanel"
	var ps=StyleBoxFlat.new(); ps.bg_color=Global.current.bg; ps.border_width_left=3; ps.border_width_right=3
	ps.border_width_top=3; ps.border_width_bottom=3; ps.border_color=Color(0.6,0.4,0.8,0.9)
	ps.corner_radius_top_left=16; ps.corner_radius_top_right=16; ps.corner_radius_bottom_left=16; ps.corner_radius_bottom_right=16
	panel.add_theme_stylebox_override("panel",ps); panel.anchor_left=0.5; panel.anchor_top=0.5
	panel.anchor_right=0.5; panel.anchor_bottom=0.5; panel.offset_left=-Global.pw(0.40); panel.offset_right=Global.pw(0.40)
	panel.offset_top=-Global.ph(0.35); panel.offset_bottom=Global.ph(0.35); overlay.add_child(panel)
	
	var vbox=VBoxContainer.new(); vbox.size_flags_horizontal=SIZE_EXPAND|SIZE_FILL; vbox.size_flags_vertical=SIZE_EXPAND|SIZE_FILL
	vbox.anchor_left=0.0; vbox.anchor_top=0.0; vbox.anchor_right=1.0; vbox.anchor_bottom=1.0
	vbox.offset_left=Global.pw(0.03); vbox.offset_top=Global.ph(0.02); vbox.offset_right=Global.pw(-0.03); vbox.offset_bottom=Global.ph(-0.02)
	panel.add_child(vbox)
	
	var tl=Label.new(); tl.text="🎉 开包成功！"; tl.add_theme_font_size_override("font_size",70)
	tl.add_theme_color_override("font_color",Color("#f9d371")); tl.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	tl.custom_minimum_size=Vector2(0,Global.ph(0.07)); vbox.add_child(tl)
	var nl=Label.new(); nl.text=pname; nl.add_theme_font_size_override("font_size",45)
	nl.add_theme_color_override("font_color",Color("#a0a0b0")); nl.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	nl.custom_minimum_size=Vector2(0,Global.ph(0.04)); vbox.add_child(nl)
	
	var line=ColorRect.new(); line.color=Global.current.topbar_border; line.custom_minimum_size=Vector2(0,2)
	line.size_flags_horizontal=SIZE_EXPAND|SIZE_FILL; vbox.add_child(line)
	
	for i in range(cards.size()):
		var card=cards[i]; var cn=card.get("name",card.get("card_name","未命名卡牌"))
		var q=card.get("quality","—"); var atk=card.get("atk",card.get("attack",0))
		var hp=card.get("hp",card.get("health",0)); var star=card.get("star",card.get("stars",0))
		
		var row=Panel.new(); row.name="CardRow_"+str(i)
		var rs=StyleBoxFlat.new(); rs.bg_color=Color(0.10,0.08,0.18) if i%2==0 else Color(0.12,0.10,0.20)
		rs.border_width_left=1; rs.border_width_right=1; rs.border_width_top=1; rs.border_width_bottom=1
		rs.border_color=Color(0.3,0.15,0.5,0.2); rs.corner_radius_top_left=8; rs.corner_radius_top_right=8
		rs.corner_radius_bottom_left=8; rs.corner_radius_bottom_right=8
		row.add_theme_stylebox_override("panel",rs); row.custom_minimum_size=Vector2(0,Global.ph(0.08))
		row.size_flags_horizontal=SIZE_EXPAND|SIZE_FILL; row.set_meta("card_data",card); vbox.add_child(row)
		var hbox=HBoxContainer.new(); hbox.size_flags_horizontal=SIZE_EXPAND|SIZE_FILL; hbox.size_flags_vertical=SIZE_EXPAND|SIZE_FILL; row.add_child(hbox)
		var il=Label.new(); il.text="#"+str(i+1); il.add_theme_font_size_override("font_size",40)
		il.add_theme_color_override("font_color",Color("#8a8aa0")); il.custom_minimum_size=Vector2(Global.pw(0.06),0); il.vertical_alignment=VERTICAL_ALIGNMENT_CENTER; hbox.add_child(il)
		var ss=""; for s in range(star): ss+="⭐"
		var sl=Label.new(); sl.text=ss; sl.add_theme_font_size_override("font_size",30)
		sl.custom_minimum_size=Vector2(Global.pw(0.12),0); sl.vertical_alignment=VERTICAL_ALIGNMENT_CENTER; hbox.add_child(sl)
		var nvl=Label.new(); nvl.text=cn; nvl.add_theme_font_size_override("font_size",45)
		nvl.add_theme_color_override("font_color",Color("#e8d5b7")); nvl.size_flags_horizontal=SIZE_EXPAND|SIZE_FILL; nvl.vertical_alignment=VERTICAL_ALIGNMENT_CENTER; hbox.add_child(nvl)
		var ql=Label.new(); ql.text=q; ql.add_theme_font_size_override("font_size",35)
		ql.add_theme_color_override("font_color",_get_qc(q)); ql.custom_minimum_size=Vector2(Global.pw(0.08),0)
		ql.vertical_alignment=VERTICAL_ALIGNMENT_CENTER; ql.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; hbox.add_child(ql)
		var stl=Label.new(); stl.text="⚔"+str(atk)+" ❤"+str(hp); stl.add_theme_font_size_override("font_size",35)
		stl.add_theme_color_override("font_color",Color("#a0a0b0")); stl.custom_minimum_size=Vector2(Global.pw(0.15),0)
		stl.vertical_alignment=VERTICAL_ALIGNMENT_CENTER; stl.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT; hbox.add_child(stl)
	
	var hl=Label.new(); hl.text="💡 长按卡牌查看详情\n点击任意处关闭"; hl.add_theme_font_size_override("font_size",35)
	hl.add_theme_color_override("font_color",Color("#5a5a6e")); hl.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	hl.custom_minimum_size=Vector2(0,Global.ph(0.06)); vbox.add_child(hl)
	
	# 显示解锁提示
	if not unlock_result.is_empty():
		_show_unlock_notification(unlock_result)

func _process(delta:float)->void:
	# 结果弹窗内卡牌长按
	if _pressed_row!=null:
		_press_timer+=delta
		if _press_timer>=LONG_PRESS_TIME:
			var card=_pressed_row.get_meta("card_data",{})
			if not card.is_empty(): _show_card_detail(card)
			_cancel_press()
	# 卡包列表长按
	if _pressed_pack!=null:
		_pack_press_timer+=delta
		if _pack_press_timer>=LONG_PRESS_TIME:
			var pd=_pressed_pack.get_meta("pack_data",{})
			var pid=_pressed_pack.get_meta("pack_id","")
			if not pd.is_empty(): _show_pack_detail(pd,pid)
			_cancel_pack_press()
	# 主题(系列)长按
	if _pressed_theme!=null:
		_theme_press_timer+=delta
		if _theme_press_timer>=LONG_PRESS_TIME:
			var tname=_pressed_theme.get_meta("theme_name","")
			if tname!="": _show_theme_detail(tname)
			_cancel_theme_press()

## 显示解锁通知弹窗
func _show_unlock_notification(unlock_result: Dictionary):
	var series_id = unlock_result.get("series_id", "")
	var series_name = CardManager.DECK_BACKS.get(series_id, {}).get("name", series_id)
	var new_count = unlock_result.get("new_count", 0)
	
	var overlay = ColorRect.new()
	overlay.name = "UnlockOverlay"
	overlay.color = Color(0, 0, 0, 0.8)
	overlay.anchor_left = 0.0; overlay.anchor_top = 0.0
	overlay.anchor_right = 1.0; overlay.anchor_bottom = 1.0
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	
	var panel = Panel.new()
	panel.name = "UnlockPanel"
	panel.anchor_left = 0.5; panel.anchor_top = 0.5
	panel.anchor_right = 0.5; panel.anchor_bottom = 0.5
	panel.offset_left = -Global.pw(0.35); panel.offset_right = Global.pw(0.35)
	panel.offset_top = -Global.ph(0.25); panel.offset_bottom = Global.ph(0.25)
	var ps = StyleBoxFlat.new()
	ps.bg_color = Global.current.bg
	ps.border_width_left = 4; ps.border_width_right = 4
	ps.border_width_top = 4; ps.border_width_bottom = 4
	ps.border_color = Color("#f9d371")
	ps.corner_radius_top_left = 20; ps.corner_radius_top_right = 20
	ps.corner_radius_bottom_left = 20; ps.corner_radius_bottom_right = 20
	panel.add_theme_stylebox_override("panel", ps)
	overlay.add_child(panel)
	
	var vbox = VBoxContainer.new()
	vbox.anchor_left = 0.0; vbox.anchor_top = 0.0
	vbox.anchor_right = 1.0; vbox.anchor_bottom = 1.0
	vbox.offset_left = Global.pw(0.04); vbox.offset_top = Global.ph(0.03)
	vbox.offset_right = Global.pw(-0.04); vbox.offset_bottom = Global.ph(-0.03)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)
	
	# 标题
	var title = Label.new()
	title.text = "🎉 解锁新内容！"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 60)
	title.add_theme_color_override("font_color", Color("#f9d371"))
	vbox.add_child(title)
	
	var spacer1 = ColorRect.new()
	spacer1.color = Color.TRANSPARENT
	spacer1.custom_minimum_size = Vector2(0, Global.ph(0.02))
	vbox.add_child(spacer1)
	
	# 解锁内容
	var unlocked_back = unlock_result.get("unlocked_back", false)
	var unlocked_cloth = unlock_result.get("unlocked_cloth", false)
	
	if unlocked_back:
		var back_info = CardManager.DECK_BACKS.get(series_id, {})
		_add_unlock_item(vbox, "卡背", back_info.get("name", ""), back_info.get("path", ""), new_count, 1)
	
	if unlocked_cloth:
		var cloth_info = CardManager.DECK_TABLECLOTHS.get(series_id, {})
		_add_unlock_item(vbox, "桌布", cloth_info.get("name", ""), cloth_info.get("path", ""), new_count, 3)
	
	# 进度提示
	var progress_lbl = Label.new()
	progress_lbl.text = "%s系列卡包进度：%d/3" % [series_name, new_count]
	progress_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	progress_lbl.add_theme_font_size_override("font_size", 30)
	progress_lbl.add_theme_color_override("font_color", Color("#aaaaaa"))
	vbox.add_child(progress_lbl)
	
	var spacer2 = ColorRect.new()
	spacer2.color = Color.TRANSPARENT
	spacer2.custom_minimum_size = Vector2(0, Global.ph(0.03))
	vbox.add_child(spacer2)
	
	# 关闭按钮
	var close_btn = Button.new()
	close_btn.text = "太棒了！"
	close_btn.add_theme_font_size_override("font_size", 45)
	close_btn.custom_minimum_size = Vector2(Global.pw(0.4), Global.ph(0.07))
	var cb = StyleBoxFlat.new()
	cb.bg_color = Color("#f9d371")
	cb.border_width_left = 2; cb.border_width_right = 2
	cb.border_width_top = 2; cb.border_width_bottom = 2
	cb.border_color = Color("#c8a03c")
	cb.corner_radius_top_left = 12; cb.corner_radius_top_right = 12
	cb.corner_radius_bottom_left = 12; cb.corner_radius_bottom_right = 12
	close_btn.add_theme_stylebox_override("normal", cb)
	close_btn.add_theme_stylebox_override("pressed", cb)
	close_btn.add_theme_stylebox_override("hover", cb)
	close_btn.add_theme_color_override("font_color", Color("#333333"))
	close_btn.pressed.connect(func():
		Global.play_sfx("click")
		overlay.queue_free()
	)
	var btn_center = CenterContainer.new()
	btn_center.add_child(close_btn)
	vbox.add_child(btn_center)
	
	# 点击遮罩关闭
	overlay.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and not ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			overlay.queue_free()
	)

## 添加解锁项到弹窗
func _add_unlock_item(parent: VBoxContainer, type_name: String, item_name: String, img_path: String, current: int, required: int):
	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 20)
	parent.add_child(hbox)
	
	# 图片
	if img_path != "":
		var tex_rect = TextureRect.new()
		tex_rect.texture = load(img_path)
		tex_rect.custom_minimum_size = Vector2(Global.pw(0.15), Global.ph(0.15))
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		hbox.add_child(tex_rect)
	
	# 文字
	var text_vbox = VBoxContainer.new()
	text_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(text_vbox)
	
	var type_lbl = Label.new()
	type_lbl.text = "新" + type_name
	type_lbl.add_theme_font_size_override("font_size", 35)
	type_lbl.add_theme_color_override("font_color", Color("#aaaaaa"))
	text_vbox.add_child(type_lbl)
	
	var name_lbl = Label.new()
	name_lbl.text = item_name
	name_lbl.add_theme_font_size_override("font_size", 45)
	name_lbl.add_theme_color_override("font_color", Color("#ffffff"))
	text_vbox.add_child(name_lbl)
	
	var progress_lbl = Label.new()
	progress_lbl.text = "(%d/%d)" % [current, required]
	progress_lbl.add_theme_font_size_override("font_size", 28)
	progress_lbl.add_theme_color_override("font_color", Color("#f9d371"))
	text_vbox.add_child(progress_lbl)

func _input(event:InputEvent)->void:
	# 处理结果弹窗内卡牌长按
	var overlay=get_node_or_null("ResultOverlay")
	if overlay and overlay.visible:
		if event is InputEventScreenTouch:
			if event.pressed:
				var row=_find_card_row(event.position)
				if row!=null: _pressed_row=row; _press_timer=0.0; _press_start_pos=event.position; _press_index=event.index
			else:
				if event.index==_press_index: _cancel_press()
		elif event is InputEventScreenDrag:
			if _pressed_row!=null and event.index==_press_index:
				if event.position.distance_to(_press_start_pos)>DRAG_THRESHOLD: _cancel_press()
		return
	# 处理卡包详情弹窗内卡牌长按
	var pd_overlay=get_node_or_null("PackDetailOverlay")
	if pd_overlay and pd_overlay.visible:
		if event is InputEventScreenTouch:
			if event.pressed:
				var row=_find_pack_card_row(event.position)
				if row!=null: _pressed_row=row; _press_timer=0.0; _press_start_pos=event.position; _press_index=event.index
			else:
				if event.index==_press_index: _cancel_press()
		elif event is InputEventScreenDrag:
			if _pressed_row!=null and event.index==_press_index:
				if event.position.distance_to(_press_start_pos)>DRAG_THRESHOLD: _cancel_press()
		return
	# 处理卡包列表长按（PackScroll 内）
	if event is InputEventScreenTouch:
		if event.pressed:
			# 主题视图下检测主题长按，否则检测卡包长按
			if _current_theme=="":
				var theme=_find_theme_at(event.position)
				if theme!=null: _pressed_theme=theme; _theme_press_timer=0.0; _theme_press_start=event.position; _theme_press_index=event.index
			else:
				var pack=_find_pack_at(event.position)
				if pack!=null: _pressed_pack=pack; _pack_press_timer=0.0; _pack_press_start=event.position; _pack_press_index=event.index
		else:
			if event.index==_pack_press_index: _cancel_pack_press()
			if event.index==_theme_press_index: _cancel_theme_press()
	elif event is InputEventScreenDrag:
		if _pressed_pack!=null and event.index==_pack_press_index:
			if event.position.distance_to(_pack_press_start)>DRAG_THRESHOLD: _cancel_pack_press()
		if _pressed_theme!=null and event.index==_theme_press_index:
			if event.position.distance_to(_theme_press_start)>DRAG_THRESHOLD: _cancel_theme_press()

func _find_card_row(pos:Vector2)->Control:
	var overlay=get_node_or_null("ResultOverlay")
	if not overlay: return null
	var panel=overlay.get_node_or_null("ResultPanel")
	if not panel: return null
	for child in panel.get_children():
		if child is VBoxContainer:
			for sub in child.get_children():
				if sub is Panel and sub.has_meta("card_data"):
					if Rect2(sub.get_global_rect().position,sub.get_global_rect().size).has_point(pos): return sub
	return null
func _find_pack_card_row(pos:Vector2)->Control:
	var overlay=get_node_or_null("PackDetailOverlay")
	if not overlay: return null
	var panel=overlay.get_node_or_null("PackDetailPanel")
	if not panel: return null
	var scroll=panel.get_node_or_null("PackDetailScroll")
	if not scroll: return null
	for child in scroll.get_children():
		if child is VBoxContainer:
			for sub in child.get_children():
				if sub is Panel and sub.has_meta("card_data"):
					if Rect2(sub.get_global_rect().position,sub.get_global_rect().size).has_point(pos): return sub
	return null

func _cancel_press()->void: _pressed_row=null; _press_timer=0.0; _press_index=-1
func _find_pack_at(pos:Vector2)->Control:
	var scroll=get_node_or_null("PackScroll")
	if not scroll: return null
	var vbox=get_node_or_null("PackScroll/PackList")
	if not vbox: return null
	for child in vbox.get_children():
		if child is Panel and child.has_meta("pack_data"):
			if Rect2(child.get_global_rect().position,child.get_global_rect().size).has_point(pos): return child
	return null
func _cancel_pack_press()->void: _pressed_pack=null; _pack_press_timer=0.0; _pack_press_index=-1
func _find_theme_at(pos:Vector2)->Control:
	var scroll=get_node_or_null("PackScroll")
	if not scroll: return null
	var vbox=get_node_or_null("PackScroll/PackList")
	if not vbox: return null
	for child in vbox.get_children():
		if child is Panel and child.has_meta("theme_name"):
			if Rect2(child.get_global_rect().position,child.get_global_rect().size).has_point(pos): return child
	return null
func _cancel_theme_press()->void: _pressed_theme=null; _theme_press_timer=0.0; _theme_press_index=-1

## 系列(主题)长按详情弹窗：简介 + 卡包数 + 跳转官网按钮
func _show_theme_detail(tname:String)->void:
	var desc=THEME_DESC_MAP.get(tname,"暂无该系列的简介。")
	# 统计该主题卡包数
	var cnt=0
	for p in Global.server_card_packs:
		if p.get("theme","沧澜古界")==tname: cnt+=1
	# 遮罩
	var overlay=ColorRect.new(); overlay.name="ThemeDetailOverlay"
	overlay.color=Color(0,0,0,0.7); overlay.anchor_left=0.0; overlay.anchor_top=0.0
	overlay.anchor_right=1.0; overlay.anchor_bottom=1.0; overlay.mouse_filter=Control.MOUSE_FILTER_STOP
	add_child(overlay)
	# 面板
	var panel=Panel.new(); panel.name="ThemeDetailPanel"
	var ps=StyleBoxFlat.new(); ps.bg_color=Global.current.bg
	ps.border_width_left=3; ps.border_width_right=3; ps.border_width_top=3; ps.border_width_bottom=3
	ps.border_color=Color(0.6,0.4,0.8,0.9)
	ps.corner_radius_top_left=18; ps.corner_radius_top_right=18; ps.corner_radius_bottom_left=18; ps.corner_radius_bottom_right=18
	panel.add_theme_stylebox_override("panel",ps)
	panel.anchor_left=0.0; panel.anchor_top=0.0; panel.anchor_right=1.0; panel.anchor_bottom=0.0
	panel.offset_left=Global.pw(0.08); panel.offset_top=Global.ph(0.20)
	panel.offset_right=Global.pw(-0.08); panel.offset_bottom=Global.ph(0.72)
	overlay.add_child(panel)
	# 点击遮罩空白处关闭
	overlay.gui_input.connect(func(ev):
		if (ev is InputEventMouseButton and ev.pressed) or (ev is InputEventScreenTouch and ev.pressed):
			var mp=overlay.get_local_mouse_position()
			if not panel.get_rect().has_point(mp): overlay.queue_free()
	)
	# 标题
	var title=Label.new(); title.text="🌍 "+tname
	title.add_theme_font_size_override("font_size",52); title.add_theme_color_override("font_color",Color("#f9d371"))
	title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	title.anchor_left=0.0; title.anchor_top=0.0; title.anchor_right=1.0; title.anchor_bottom=0.0
	title.offset_left=0; title.offset_top=Global.ph(0.025); title.offset_right=0; title.offset_bottom=Global.ph(0.085)
	panel.add_child(title)
	# 卡包数
	var cnt_l=Label.new(); cnt_l.text="共 "+str(cnt)+" 个卡包"
	cnt_l.add_theme_font_size_override("font_size",34); cnt_l.add_theme_color_override("font_color",Color("#8a8aa0"))
	cnt_l.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	cnt_l.anchor_left=0.0; cnt_l.anchor_top=0.0; cnt_l.anchor_right=1.0; cnt_l.anchor_bottom=0.0
	cnt_l.offset_left=0; cnt_l.offset_top=Global.ph(0.09); cnt_l.offset_right=0; cnt_l.offset_bottom=Global.ph(0.13)
	panel.add_child(cnt_l)
	# 分割线
	var sep=ColorRect.new(); sep.color=Color(0.6,0.4,0.8,0.5)
	sep.anchor_left=0.0; sep.anchor_top=0.0; sep.anchor_right=1.0; sep.anchor_bottom=0.0
	sep.offset_left=Global.pw(0.05); sep.offset_top=Global.ph(0.14); sep.offset_right=Global.pw(-0.05); sep.offset_bottom=Global.ph(0.142)
	panel.add_child(sep)
	# 简介（滚动）
	var scroll=ScrollContainer.new()
	scroll.anchor_left=0.0; scroll.anchor_top=0.0; scroll.anchor_right=1.0; scroll.anchor_bottom=0.0
	scroll.offset_left=Global.pw(0.05); scroll.offset_top=Global.ph(0.16); scroll.offset_right=Global.pw(-0.05); scroll.offset_bottom=Global.ph(0.40)
	panel.add_child(scroll)
	var dl=Label.new(); dl.text=desc
	dl.add_theme_font_size_override("font_size",34); dl.add_theme_color_override("font_color",Color("#d8d8e8"))
	dl.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	dl.size_flags_horizontal=Control.SIZE_EXPAND|Control.SIZE_FILL
	dl.custom_minimum_size=Vector2(Global.pw(0.74),0); scroll.add_child(dl)
	# 🌐 查看更多按钮（跳转官网系列页）
	var more=Button.new(); more.text="🌐 查看更多"
	more.add_theme_font_size_override("font_size",38); more.add_theme_color_override("font_color",Color("#6c9bcf"))
	var ms=StyleBoxFlat.new(); ms.bg_color=Color(0.15,0.2,0.35,0.9)
	ms.border_width_left=2; ms.border_width_right=2; ms.border_width_top=2; ms.border_width_bottom=2; ms.border_color=Color(0.42,0.6,0.81,0.8)
	ms.corner_radius_top_left=12; ms.corner_radius_top_right=12; ms.corner_radius_bottom_left=12; ms.corner_radius_bottom_right=12
	more.add_theme_stylebox_override("normal",ms); more.add_theme_stylebox_override("hover",ms); more.add_theme_stylebox_override("pressed",ms)
	more.anchor_left=0.0; more.anchor_top=0.0; more.anchor_right=1.0; more.anchor_bottom=0.0
	more.offset_left=Global.pw(0.15); more.offset_top=Global.ph(0.42); more.offset_right=Global.pw(-0.15); more.offset_bottom=Global.ph(0.47)
	more.mouse_filter=Control.MOUSE_FILTER_STOP
	more.pressed.connect(func(): _on_theme_more_pressed(tname))
	panel.add_child(more)
	# 关闭按钮
	var close=Button.new(); close.text="✕ 关闭"
	close.add_theme_font_size_override("font_size",38); close.add_theme_color_override("font_color",Color("#a0a0b0"))
	var cs=StyleBoxFlat.new(); cs.bg_color=Color(0.2,0.12,0.2,0.9)
	cs.corner_radius_top_left=12; cs.corner_radius_top_right=12; cs.corner_radius_bottom_left=12; cs.corner_radius_bottom_right=12
	close.add_theme_stylebox_override("normal",cs); close.add_theme_stylebox_override("hover",cs); close.add_theme_stylebox_override("pressed",cs)
	close.anchor_left=0.0; close.anchor_top=0.0; close.anchor_right=1.0; close.anchor_bottom=0.0
	close.offset_left=Global.pw(0.15); close.offset_top=Global.ph(0.50); close.offset_right=Global.pw(-0.15); close.offset_bottom=Global.ph(0.55)
	close.mouse_filter=Control.MOUSE_FILTER_STOP
	close.pressed.connect(func(): if is_instance_valid(overlay): overlay.queue_free())
	panel.add_child(close)

## 系列"查看更多"→ 确认后跳浏览器打开对应系列官网主页
func _on_theme_more_pressed(tname:String)->void:
	var page=THEME_WIKI_MAP.get(tname,"worldview.html")
	var url=OFFICIAL_BASE_URL+page
	# 确认弹窗遮罩
	var overlay=ColorRect.new(); overlay.name="WebJumpConfirmOverlay"
	overlay.color=Color(0,0,0,0.7); overlay.anchor_left=0.0; overlay.anchor_top=0.0
	overlay.anchor_right=1.0; overlay.anchor_bottom=1.0; overlay.mouse_filter=Control.MOUSE_FILTER_STOP
	add_child(overlay)
	var panel=Panel.new()
	var ps=StyleBoxFlat.new(); ps.bg_color=Global.current.bg; ps.border_width_left=3; ps.border_width_right=3
	ps.border_width_top=3; ps.border_width_bottom=3; ps.border_color=Color(0.6,0.4,0.8,0.9)
	ps.corner_radius_top_left=16; ps.corner_radius_top_right=16; ps.corner_radius_bottom_left=16; ps.corner_radius_bottom_right=16
	panel.add_theme_stylebox_override("panel",ps)
	panel.anchor_left=0.0; panel.anchor_top=0.0; panel.anchor_right=1.0; panel.anchor_bottom=0.0
	panel.offset_left=Global.pw(0.12); panel.offset_top=Global.ph(0.34)
	panel.offset_right=Global.pw(-0.12); panel.offset_bottom=Global.ph(0.62)
	overlay.add_child(panel)
	var msg=Label.new()
	msg.text="即将跳转浏览器打开\n「"+tname+"」系列详情页\n\n（外部网页，非游戏内容）"
	msg.add_theme_font_size_override("font_size",34); msg.add_theme_color_override("font_color",Color("#e8e8f0"))
	msg.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; msg.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	msg.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	msg.anchor_left=0.0; msg.anchor_top=0.0; msg.anchor_right=1.0; msg.anchor_bottom=1.0
	msg.offset_left=Global.pw(0.03); msg.offset_top=Global.ph(0.02); msg.offset_right=Global.pw(-0.03); msg.offset_bottom=Global.ph(-0.09)
	panel.add_child(msg)
	var ok=Button.new(); ok.text="✓ 打开网页"
	ok.add_theme_font_size_override("font_size",36); ok.add_theme_color_override("font_color",Color("#e8d5b7"))
	var oks=StyleBoxFlat.new(); oks.bg_color=Color(0.25,0.15,0.4,0.9)
	oks.corner_radius_top_left=12; oks.corner_radius_top_right=12; oks.corner_radius_bottom_left=12; oks.corner_radius_bottom_right=12
	ok.add_theme_stylebox_override("normal",oks); ok.add_theme_stylebox_override("hover",oks); ok.add_theme_stylebox_override("pressed",oks)
	ok.anchor_left=0.0; ok.anchor_top=1.0; ok.anchor_right=0.5; ok.anchor_bottom=1.0
	ok.offset_left=Global.pw(0.03); ok.offset_top=Global.ph(-0.08); ok.offset_right=Global.pw(-0.02); ok.offset_bottom=Global.ph(-0.02)
	ok.mouse_filter=Control.MOUSE_FILTER_STOP
	ok.pressed.connect(func():
		if is_instance_valid(overlay): overlay.queue_free()
		OS.shell_open(url)
	)
	panel.add_child(ok)
	var cancel=Button.new(); cancel.text="✕ 取消"
	cancel.add_theme_font_size_override("font_size",36); cancel.add_theme_color_override("font_color",Color("#a0a0b0"))
	var ccs=StyleBoxFlat.new(); ccs.bg_color=Color(0.2,0.12,0.2,0.9)
	ccs.corner_radius_top_left=12; ccs.corner_radius_top_right=12; ccs.corner_radius_bottom_left=12; ccs.corner_radius_bottom_right=12
	cancel.add_theme_stylebox_override("normal",ccs); cancel.add_theme_stylebox_override("hover",ccs); cancel.add_theme_stylebox_override("pressed",ccs)
	cancel.anchor_left=0.5; cancel.anchor_top=1.0; cancel.anchor_right=1.0; cancel.anchor_bottom=1.0
	cancel.offset_left=Global.pw(0.02); cancel.offset_top=Global.ph(-0.08); cancel.offset_right=Global.pw(-0.03); cancel.offset_bottom=Global.ph(-0.02)
	cancel.mouse_filter=Control.MOUSE_FILTER_STOP
	cancel.pressed.connect(func(): if is_instance_valid(overlay): overlay.queue_free())
	panel.add_child(cancel)

func _show_pack_detail(pd:Dictionary, pid:String="")->void:
	var pname=pd.get("name","未知卡包"); var pdesc=pd.get("desc","")
	var cards=pd.get("cards",[])
	# 遮罩（参考墓地弹窗）
	var overlay=ColorRect.new(); overlay.name="PackDetailOverlay"
	overlay.color=Color(0,0,0,0.75); overlay.anchor_left=0.0; overlay.anchor_top=0.0
	overlay.anchor_right=1.0; overlay.anchor_bottom=1.0; overlay.mouse_filter=Control.MOUSE_FILTER_STOP
	overlay.gui_input.connect(func(ev):
		if not is_instance_valid(overlay): return
		if ev is InputEventMouseButton and ev.pressed and ev.button_index==MOUSE_BUTTON_LEFT:
			var panel=overlay.get_node_or_null("PackDetailPanel")
			if panel and Rect2(panel.get_global_rect().position,panel.get_global_rect().size).has_point(Vector2(ev.position.x,ev.position.y)):
				return  # 点在面板内，不关闭，让滚动正常工作
			overlay.queue_free())
	add_child(overlay)
	# 面板（参考墓地弹窗，offset定位）
	var panel=Panel.new(); panel.name="PackDetailPanel"
	var ps=StyleBoxFlat.new(); ps.bg_color=Global.current.bg; ps.border_width_left=3; ps.border_width_right=3
	ps.border_width_top=3; ps.border_width_bottom=3; ps.border_color=Color(0.6,0.4,0.8,0.9)
	ps.corner_radius_top_left=16; ps.corner_radius_top_right=16; ps.corner_radius_bottom_left=16; ps.corner_radius_bottom_right=16
	panel.add_theme_stylebox_override("panel",ps)
	panel.anchor_left=0.0; panel.anchor_top=0.0; panel.anchor_right=1.0; panel.anchor_bottom=0.0
	panel.offset_left=Global.pw(0.10); panel.offset_top=Global.ph(0.12)
	panel.offset_right=Global.pw(-0.10); panel.offset_bottom=Global.ph(0.88)
	overlay.add_child(panel)
	# 关闭按钮（右上角，参考墓地弹窗的切换按钮位置）
	var close_btn=Button.new(); close_btn.text="✕"
	close_btn.add_theme_font_size_override("font_size",40); close_btn.add_theme_color_override("font_color",Color("#a0a0b0"))
	var cbs=StyleBoxFlat.new(); cbs.bg_color=Color(0.2,0.1,0.3,0.8); cbs.corner_radius_top_left=50; cbs.corner_radius_top_right=50
	cbs.corner_radius_bottom_left=50; cbs.corner_radius_bottom_right=50; cbs.content_margin_left=8; cbs.content_margin_right=8
	close_btn.add_theme_stylebox_override("normal",cbs); close_btn.add_theme_stylebox_override("hover",cbs)
	close_btn.add_theme_stylebox_override("pressed",cbs); close_btn.add_theme_stylebox_override("focus",cbs)
	close_btn.anchor_left=1.0; close_btn.anchor_top=0.0; close_btn.anchor_right=1.0; close_btn.anchor_bottom=0.0
	close_btn.offset_left=Global.pw(-0.08); close_btn.offset_top=Global.ph(0.01); close_btn.offset_right=Global.pw(-0.01); close_btn.offset_bottom=Global.ph(0.06)
	close_btn.pressed.connect(func(): if is_instance_valid(overlay): overlay.queue_free())
	close_btn.mouse_filter=Control.MOUSE_FILTER_STOP
	overlay.add_child(close_btn)
	# 标题
	var title=Label.new(); title.text="🎴 "+pname
	title.add_theme_font_size_override("font_size",50); title.add_theme_color_override("font_color",Color("#f9d371"))
	title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	title.anchor_left=0.0; title.anchor_top=0.0; title.anchor_right=1.0; title.anchor_bottom=0.0
	title.offset_left=Global.pw(0.08); title.offset_top=Global.ph(0.015); title.offset_right=Global.pw(-0.08); title.offset_bottom=Global.ph(0.07)
	panel.add_child(title)
	# 描述
	if pdesc!="":
		var dl=Label.new(); dl.text=pdesc; dl.add_theme_font_size_override("font_size",28)
		dl.add_theme_color_override("font_color",Color("#a0a0b0")); dl.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		dl.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		dl.anchor_left=0.0; dl.anchor_top=0.0; dl.anchor_right=1.0; dl.anchor_bottom=0.0
		dl.offset_left=Global.pw(0.04); dl.offset_top=Global.ph(0.065); dl.offset_right=Global.pw(-0.04); dl.offset_bottom=Global.ph(0.10)
		panel.add_child(dl)
	# 卡牌数量
	var cl=Label.new(); cl.text="共 "+str(cards.size())+" 张卡牌（长按查看详情）"
	cl.add_theme_font_size_override("font_size",28); cl.add_theme_color_override("font_color",Color("#8a8aa0"))
	cl.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	cl.anchor_left=0.0; cl.anchor_top=0.0; cl.anchor_right=1.0; cl.anchor_bottom=0.0
	cl.offset_left=0; cl.offset_top=Global.ph(0.10); cl.offset_right=0; cl.offset_bottom=Global.ph(0.135)
	panel.add_child(cl)
	# 分割线
	var line=ColorRect.new(); line.color=Global.current.topbar_border
	line.anchor_left=0.0; line.anchor_top=0.0; line.anchor_right=1.0; line.anchor_bottom=0.0
	line.offset_left=Global.pw(0.05); line.offset_top=Global.ph(0.14); line.offset_right=Global.pw(-0.05); line.offset_bottom=Global.ph(0.141)
	panel.add_child(line)
	# 滚动列表（参考墓地弹窗）
	var scroll=ScrollContainer.new(); scroll.name="PackDetailScroll"
	scroll.anchor_left=0.0; scroll.anchor_top=0.0; scroll.anchor_right=1.0; scroll.anchor_bottom=1.0
	scroll.offset_left=Global.pw(0.03); scroll.offset_top=Global.ph(0.15); scroll.offset_right=Global.pw(-0.03); scroll.offset_bottom=Global.ph(-0.11)
	scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO; scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	# 查看更多按钮（底部，点击跳转浏览器打开对应卡包的官网/wiki页）
	var more_btn=Button.new(); more_btn.text="🌐 查看更多"
	more_btn.add_theme_font_size_override("font_size",36); more_btn.add_theme_color_override("font_color",Color("#e8d5b7"))
	var mbs=StyleBoxFlat.new(); mbs.bg_color=Color(0.25,0.15,0.4,0.9)
	mbs.corner_radius_top_left=12; mbs.corner_radius_top_right=12; mbs.corner_radius_bottom_left=12; mbs.corner_radius_bottom_right=12
	mbs.border_width_left=2; mbs.border_width_right=2; mbs.border_width_top=2; mbs.border_width_bottom=2; mbs.border_color=Color(0.6,0.4,0.8,0.9)
	more_btn.add_theme_stylebox_override("normal",mbs); more_btn.add_theme_stylebox_override("hover",mbs); more_btn.add_theme_stylebox_override("pressed",mbs)
	more_btn.anchor_left=0.0; more_btn.anchor_top=1.0; more_btn.anchor_right=1.0; more_btn.anchor_bottom=1.0
	more_btn.offset_left=Global.pw(0.20); more_btn.offset_top=Global.ph(-0.095); more_btn.offset_right=Global.pw(-0.20); more_btn.offset_bottom=Global.ph(-0.03)
	more_btn.mouse_filter=Control.MOUSE_FILTER_STOP
	more_btn.pressed.connect(func(): _on_pack_more_pressed(pid, pname))
	panel.add_child(more_btn)
	var vbox=VBoxContainer.new(); vbox.name="PackDetailList"
	vbox.size_flags_horizontal=Control.SIZE_EXPAND|Control.SIZE_FILL; vbox.custom_minimum_size=Vector2(Global.pw(0.74),0)
	scroll.add_child(vbox)
	# 卡牌列表
	for i in range(cards.size()):
		var card=cards[i]; var cn=card.get("name",card.get("card_name","未命名卡牌"))
		var q=card.get("quality","—"); var atk=card.get("atk",card.get("attack",0))
		var hp=card.get("hp",card.get("health",0)); var star=card.get("star",card.get("stars",0))
		var row=Panel.new(); row.name="PackCardRow_"+str(i)
		row.mouse_filter=Control.MOUSE_FILTER_IGNORE  # 参考墓地弹窗，让事件穿透到scroll
		var rs=StyleBoxFlat.new(); rs.bg_color=Color(0.10,0.08,0.18) if i%2==0 else Color(0.12,0.10,0.20)
		rs.border_width_left=1; rs.border_width_right=1; rs.border_width_top=1; rs.border_width_bottom=1
		rs.border_color=Color(0.3,0.15,0.5,0.2); rs.corner_radius_top_left=8; rs.corner_radius_top_right=8
		rs.corner_radius_bottom_left=8; rs.corner_radius_bottom_right=8
		row.add_theme_stylebox_override("panel",rs); row.custom_minimum_size=Vector2(0,Global.ph(0.08))
		row.size_flags_horizontal=Control.SIZE_EXPAND|Control.SIZE_FILL; row.set_meta("card_data",card); vbox.add_child(row)
		var hbox=HBoxContainer.new(); hbox.size_flags_horizontal=Control.SIZE_EXPAND|Control.SIZE_FILL; hbox.size_flags_vertical=Control.SIZE_EXPAND|Control.SIZE_FILL; row.add_child(hbox)
		var ss=""; for s in range(star): ss+="⭐"
		var sl=Label.new(); sl.text=ss; sl.add_theme_font_size_override("font_size",28)
		sl.custom_minimum_size=Vector2(Global.pw(0.12),0); sl.vertical_alignment=VERTICAL_ALIGNMENT_CENTER; hbox.add_child(sl)
		var nvl=Label.new(); nvl.text=cn; nvl.add_theme_font_size_override("font_size",42)
		nvl.add_theme_color_override("font_color",Color("#e8d5b7")); nvl.size_flags_horizontal=Control.SIZE_EXPAND|Control.SIZE_FILL; nvl.vertical_alignment=VERTICAL_ALIGNMENT_CENTER; hbox.add_child(nvl)
		var ql=Label.new(); ql.text=q; ql.add_theme_font_size_override("font_size",33)
		ql.add_theme_color_override("font_color",_get_qc(q)); ql.custom_minimum_size=Vector2(Global.pw(0.08),0)
		ql.vertical_alignment=VERTICAL_ALIGNMENT_CENTER; ql.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; hbox.add_child(ql)
		var stl=Label.new(); stl.text="⚔"+str(atk)+" ❤"+str(hp); stl.add_theme_font_size_override("font_size",33)
		stl.add_theme_color_override("font_color",Color("#a0a0b0")); stl.custom_minimum_size=Vector2(Global.pw(0.15),0)
		stl.vertical_alignment=VERTICAL_ALIGNMENT_CENTER; stl.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT; hbox.add_child(stl)
func _show_card_detail(card:Dictionary)->void:
	var popup=CardDetailPopup.new(); popup.name="CardDetailPopup"; add_child(popup)
	var bc=BattleCard.from_dict(card); popup.show_card(bc,"view")

## "查看更多"按钮点击 → 弹确认框 → 确认后跳浏览器打开对应卡包官网/wiki页
func _on_pack_more_pressed(pid:String, pname:String)->void:
	if pid=="":
		_show_popup("⚠️ 无法打开","未找到卡包标识",Color("#FF5252")); return
	if not PACK_WIKI_MAP.has(pid):
		_show_popup("⚠️ 无法打开","该卡包暂无线上详情页",Color("#FF5252")); return
	var url=OFFICIAL_BASE_URL+PACK_WIKI_MAP[pid]
	# 确认弹窗遮罩
	var overlay=ColorRect.new(); overlay.name="WebJumpConfirmOverlay"
	overlay.color=Color(0,0,0,0.7); overlay.anchor_left=0.0; overlay.anchor_top=0.0
	overlay.anchor_right=1.0; overlay.anchor_bottom=1.0; overlay.mouse_filter=Control.MOUSE_FILTER_STOP
	add_child(overlay)
	# 确认弹窗面板
	var panel=Panel.new()
	var ps=StyleBoxFlat.new(); ps.bg_color=Global.current.bg; ps.border_width_left=3; ps.border_width_right=3
	ps.border_width_top=3; ps.border_width_bottom=3; ps.border_color=Color(0.6,0.4,0.8,0.9)
	ps.corner_radius_top_left=16; ps.corner_radius_top_right=16; ps.corner_radius_bottom_left=16; ps.corner_radius_bottom_right=16
	panel.add_theme_stylebox_override("panel",ps)
	panel.anchor_left=0.0; panel.anchor_top=0.0; panel.anchor_right=1.0; panel.anchor_bottom=0.0
	panel.offset_left=Global.pw(0.12); panel.offset_top=Global.ph(0.34)
	panel.offset_right=Global.pw(-0.12); panel.offset_bottom=Global.ph(0.62)
	overlay.add_child(panel)
	# 提示文本
	var msg=Label.new()
	msg.text="即将跳转浏览器打开\n「"+pname+"」卡牌详情页\n\n（外部网页，非游戏内容）"
	msg.add_theme_font_size_override("font_size",34); msg.add_theme_color_override("font_color",Color("#e8e8f0"))
	msg.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; msg.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	msg.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	msg.anchor_left=0.0; msg.anchor_top=0.0; msg.anchor_right=1.0; msg.anchor_bottom=1.0
	msg.offset_left=Global.pw(0.03); msg.offset_top=Global.ph(0.02); msg.offset_right=Global.pw(-0.03); msg.offset_bottom=Global.ph(-0.09)
	panel.add_child(msg)
	# 确认按钮
	var ok=Button.new(); ok.text="✓ 打开网页"
	ok.add_theme_font_size_override("font_size",36); ok.add_theme_color_override("font_color",Color("#e8d5b7"))
	var oks=StyleBoxFlat.new(); oks.bg_color=Color(0.25,0.15,0.4,0.9)
	oks.corner_radius_top_left=12; oks.corner_radius_top_right=12; oks.corner_radius_bottom_left=12; oks.corner_radius_bottom_right=12
	ok.add_theme_stylebox_override("normal",oks); ok.add_theme_stylebox_override("hover",oks); ok.add_theme_stylebox_override("pressed",oks)
	ok.anchor_left=0.0; ok.anchor_top=1.0; ok.anchor_right=0.5; ok.anchor_bottom=1.0
	ok.offset_left=Global.pw(0.03); ok.offset_top=Global.ph(-0.08); ok.offset_right=Global.pw(-0.02); ok.offset_bottom=Global.ph(-0.02)
	ok.mouse_filter=Control.MOUSE_FILTER_STOP
	ok.pressed.connect(func():
		if is_instance_valid(overlay): overlay.queue_free()
		OS.shell_open(url)
	)
	panel.add_child(ok)
	# 取消按钮
	var cancel=Button.new(); cancel.text="✕ 取消"
	cancel.add_theme_font_size_override("font_size",36); cancel.add_theme_color_override("font_color",Color("#a0a0b0"))
	var ccs=StyleBoxFlat.new(); ccs.bg_color=Color(0.2,0.12,0.2,0.9)
	ccs.corner_radius_top_left=12; ccs.corner_radius_top_right=12; ccs.corner_radius_bottom_left=12; ccs.corner_radius_bottom_right=12
	cancel.add_theme_stylebox_override("normal",ccs); cancel.add_theme_stylebox_override("hover",ccs); cancel.add_theme_stylebox_override("pressed",ccs)
	cancel.anchor_left=0.5; cancel.anchor_top=1.0; cancel.anchor_right=1.0; cancel.anchor_bottom=1.0
	cancel.offset_left=Global.pw(0.02); cancel.offset_top=Global.ph(-0.08); cancel.offset_right=Global.pw(-0.03); cancel.offset_bottom=Global.ph(-0.02)
	cancel.mouse_filter=Control.MOUSE_FILTER_STOP
	cancel.pressed.connect(func(): if is_instance_valid(overlay): overlay.queue_free())
	panel.add_child(cancel)

func _on_ad_loaded(_pid:String): _set_status("✅ 广告已就绪",Color("#4CAF50"))
func _on_video_rewarded(rewarded:bool):
	if not rewarded: _set_status("⏳ 广告未完整播放",Color("#FF5252")); _show_popup("⚠️ 广告未完整播放","下次请看完哦",Color("#FF5252")); return
	if _pending_pack_id=="": return
	_set_status("✅ 广告播放完成，开包中...",Color("#4CAF50"))
	var pd={}
	for pack in Global.server_card_packs:
		if pack.get("pack_id","")==_pending_pack_id: pd=pack.get("pack_data",{}); break
	_do_open_pack(_pending_pack_id,pd); _pending_pack_id=""
func _on_ad_closed(_result:String):
	_set_status("✅ 广告已关闭",Color("#4CAF50"))
	await get_tree().create_timer(1.0).timeout; _hj_ads.loadRewardedAd()
func _on_ad_failed(err:String):
	_set_status("⚠ 广告加载失败",Color("#FF5252"))
	# 不弹 Popup 报错——避免审核员在断网环境下看到"报错"而被判定为联网功能异常

func _update_gold():
	var gl=get_node_or_null("GoldLabel")
	if gl: gl.text="💰 "+str(SaveManager.get_value("player","gold",0))
func _set_status(t:String,c:Color):
	var sl=get_node_or_null("StatusLabel")
	if sl: sl.text=t; sl.add_theme_color_override("font_color",c)
func _get_qc(q: String) -> Color:
	match q:
		"传说", "SSR", "SSR+":
			return Color("#FFD700")
		"史诗", "SR", "SR+":
			return Color("#9B59B6")
		"稀有", "R", "R+":
			return Color("#6c9bcf")
		"普通", "N", "N+":
			return Color("#a0a0b0")
	return Global.get_quality_color(q)
func _show_popup(tt:String,mt:String,c:Color):
	var overlay=ColorRect.new(); overlay.name="PopupOverlay"; overlay.color=Color(0,0,0,0.6)
	overlay.anchor_left=0.0; overlay.anchor_top=0.0; overlay.anchor_right=1.0; overlay.anchor_bottom=1.0
	overlay.mouse_filter=Control.MOUSE_FILTER_STOP
	overlay.gui_input.connect(func(ev):
		if not is_instance_valid(overlay): return
		if ev is InputEventMouseButton and not ev.pressed and ev.button_index==MOUSE_BUTTON_LEFT: overlay.queue_free())
	add_child(overlay)
	var panel=Panel.new(); var ps=StyleBoxFlat.new(); ps.bg_color=Global.current.bg
	ps.border_width_left=2; ps.border_width_right=2; ps.border_width_top=2; ps.border_width_bottom=2
	ps.border_color=Color("#e8a838"); ps.corner_radius_top_left=16; ps.corner_radius_top_right=12; ps.corner_radius_bottom_left=16; ps.corner_radius_bottom_right=16
	panel.add_theme_stylebox_override("panel",ps); panel.anchor_left=0.5; panel.anchor_top=0.5
	panel.anchor_right=0.5; panel.anchor_bottom=0.5; panel.offset_left=-Global.pw(0.30); panel.offset_right=Global.pw(0.30)
	panel.offset_top=-Global.ph(0.15); panel.offset_bottom=Global.ph(0.15); overlay.add_child(panel)
	var vbox=VBoxContainer.new(); vbox.size_flags_horizontal=SIZE_EXPAND|SIZE_FILL; vbox.size_flags_vertical=SIZE_EXPAND|SIZE_FILL
	vbox.anchor_left=0.0; vbox.anchor_top=0.0; vbox.anchor_right=1.0; vbox.anchor_bottom=1.0
	vbox.offset_left=Global.pw(0.03); vbox.offset_top=Global.ph(0.02); vbox.offset_right=Global.pw(-0.03); vbox.offset_bottom=Global.ph(-0.02)
	panel.add_child(vbox)
	var ttl=Label.new(); ttl.text=tt; ttl.add_theme_font_size_override("font_size",55)
	ttl.add_theme_color_override("font_color",c); ttl.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	ttl.custom_minimum_size=Vector2(0,Global.ph(0.06)); vbox.add_child(ttl)
	var mtl=Label.new(); mtl.text=mt; mtl.add_theme_font_size_override("font_size",40)
	mtl.add_theme_color_override("font_color",Color("#e8d5b7")); mtl.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	mtl.custom_minimum_size=Vector2(0,Global.ph(0.06)); vbox.add_child(mtl)
	var htl=Label.new(); htl.text="点击关闭"; htl.add_theme_font_size_override("font_size",35)
	htl.add_theme_color_override("font_color",Color("#5a5a6e")); htl.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	htl.custom_minimum_size=Vector2(0,Global.ph(0.04)); vbox.add_child(htl)

func _on_back():
	Global.play_sfx("click")
	if _current_theme != "":
		_build_theme_view()
	else:
		Global.change_scene("res://StoreStreet.tscn")

# ============================
#  第五幕 · 导览接力（卡包商店介绍·终点）
#  商店街介绍（stage=3）之后进入本场景触发；点完停留，让玩家自己开包
# ============================
func _maybe_show_packshop_tour() -> void:
	if TutorialManager.get_progress() < TutorialManager.PROGRESS_DONE:
		return
	var stage = SaveManager.get_value("tutorial", "fifth_act_stage", 0)
	if stage != 3:
		return  # 还没轮到卡包商店
	SaveManager.set_value("tutorial", "fifth_act_stage", 4)
	SaveManager.save_to_disk()
	_show_packshop_tour_dialogue()
func _show_packshop_tour_dialogue() -> void:
	var popup = preload("res://TutorialDialoguePopup.gd").new()
	popup.setup([
		{"speaker": "老陈", "text": "……咳。这卡包店，是我开的。"},
		{"speaker": "你", "text": "什么？！你开的？"},
		{"speaker": "老陈", "text": "每天开一批新包，运气好能开出好卡苗子。你要是真想谢我，就多来照顾照顾生意——赚了钱，记得请我喝奶茶。"},
	], func():
		# 终点：引导结束，停留让玩家自行开包
		return
	)
	add_child(popup)
func _on_theme_changed(_mode):
	var bg=get_node_or_null("Background"); if bg: Global.apply_bg(bg)
	var tl=get_node_or_null("Title"); if tl and tl is Label:
		tl.add_theme_color_override("font_color",Global.current.title)
		tl.add_theme_color_override("font_shadow_color",Global.current.title_shadow)
		tl.add_theme_constant_override("shadow_offset_x",Global.current.shadow_offset)
		tl.add_theme_constant_override("shadow_offset_y",Global.current.shadow_offset)

func _apply_theme_styles():
	var bg = get_node_or_null("Background")
	if bg: Global.apply_bg(bg)
	for n in ["TopBar","BottomBar"]:
		var r = get_node_or_null(n)
		if r is ColorRect: r.color = Global.current.topbar_bg
	for n in ["TopBarLine","BottomBarLine"]:
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
		back.add_theme_stylebox_override("normal", _make_btn_style())
		back.add_theme_stylebox_override("hover", _make_btn_style(true))
		back.add_theme_stylebox_override("pressed", _make_btn_style())
		back.add_theme_color_override("font_color", Global.current.btn_text)

func _make_btn_style(hover: bool = false) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = Global.current.btn_bg_hover if hover else Global.current.btn_bg
	s.border_width_left = 2; s.border_width_right = 2; s.border_width_top = 2; s.border_width_bottom = 2
	s.border_color = Color("#888888")
	s.corner_radius_top_left = 10; s.corner_radius_top_right = 10
	s.corner_radius_bottom_left = 10; s.corner_radius_bottom_right = 10
	return s
