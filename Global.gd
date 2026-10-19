extends Node

## ============================================================
##  全局UI工具库 + 主题系统（Autoload 单例）
## ============================================================

enum ThemeMode { NIGHT, DAY }

const CONFIG_PATH := "user://theme_settings.cfg"
const CONFIG_SECTION := "theme"

const REF_W := 1080.0
const REF_H := 1920.0
const CANVAS_LANDSCAPE := Vector2i(1920, 1080)
const CANVAS_PORTRAIT := Vector2i(1080, 1920)
# 横屏战斗时画布变成 1920x1080，pw/ph 必须跟着换算，
# 否则 ph(0.35)=672 这种竖屏比例在 1080 高的画布上会把面板算出负高度（面板直接消失）。
static var landscape_canvas: bool = false

static func ph(ratio: float) -> float:
	if landscape_canvas:
		return CANVAS_LANDSCAPE.y * ratio
	return REF_H * ratio

static func pw(ratio: float) -> float:
	if landscape_canvas:
		return CANVAS_LANDSCAPE.x * ratio
	return REF_W * ratio

## 获取元素emoji
static func get_element_emoji(element: String) -> String:
	match element:
		"火": return "🔥"
		"水": return "💧"
		"风": return "🌪️"
		"地": return "⛰️"
		"光": return "✨"
		"暗": return "🌑"
	return ""

## 获取元素克制倍率
## 返回：1.0（无克制）或 1.2（克制）
static func get_element_affinity(atk_element: String, def_element: String) -> float:
	if atk_element == "无" or def_element == "无" or atk_element == "" or def_element == "":
		return 1.0
	
	var affinity = {
		"火": "风",
		"风": "地",
		"地": "水",
		"水": "火",
		"光": "暗",
		"暗": "光"
	}
	
	if affinity.get(atk_element, "") == def_element:
		return 1.2
	return 1.0

## 获取元素专属加成系数
## 参数：
##   element: 卡牌最终元素（get_effective_element）
##   power_bonus: 辅材提供的额外元素强度（0.1/0.15等，无辅材为0）
##   effect_type: 效果类型 "damage"伤害 / "heal"治疗 / "draw"抽牌 / "shield"护盾 / "counter"反制 / "destroy"破坏
## 返回：1.0 + 基础天赋加成 + 辅材加成（1.0为无加成）
## 卡牌自带元素提供基础天赋加成（火卡伤害天生+X%、水卡治疗天生+X%、风卡抽牌天生+X%），
## 辅材的 element_power_bonus 在天赋基础上叠加，且按效果类型匹配（火辅材只加伤害类）
static func get_element_power_multiplier(element: String, power_bonus: float, effect_type: String = "") -> float:
	if element == "无" or element == "":
		return 1.0
	var base_bonus := 0.0
	var bonus := 0.0
	match element:
		"火":
			if effect_type == "damage":
				base_bonus = 0.1
				bonus = power_bonus
		"水":
			if effect_type == "heal":
				base_bonus = 0.1
				bonus = power_bonus
		"风":
			if effect_type == "draw":
				base_bonus = 0.1
				bonus = power_bonus
		"地":
			if effect_type == "shield":
				base_bonus = 0.1
				bonus = power_bonus
		"光":
			if effect_type == "counter":
				base_bonus = 0.1
				bonus = power_bonus
		"暗":
			if effect_type == "damage" or effect_type == "destroy":
				base_bonus = 0.1
				bonus = power_bonus
	var total_bonus = base_bonus + bonus
	if total_bonus <= 0.0:
		return 1.0
	return 1.0 + total_bonus

class ThemeColors:
	var bg: Color
	var title: Color
	var title_shadow: Color
	var btn_text: Color
	var btn_text_hover: Color
	var btn_bg: Color
	var btn_bg_hover: Color
	var btn_bg_pressed: Color
	var version: Color
	var version_shadow: Color
	var gear_bg: Color
	var gear_hover: Color
	var topbar_bg: Color
	var topbar_border: Color
	var shadow_offset: int

	func _init(
		_bg: Color, _title: Color, _title_shadow: Color,
		_btn_text: Color, _btn_text_hover: Color,
		_btn_bg: Color, _btn_bg_hover: Color, _btn_bg_pressed: Color,
		_version: Color, _version_shadow: Color,
		_gear_bg: Color, _gear_hover: Color,
		_topbar_bg: Color, _topbar_border: Color,
		_shadow_offset: int
	):
		bg = _bg; title = _title; title_shadow = _title_shadow
		btn_text = _btn_text; btn_text_hover = _btn_text_hover
		btn_bg = _btn_bg; btn_bg_hover = _btn_bg_hover; btn_bg_pressed = _btn_bg_pressed
		version = _version; version_shadow = _version_shadow
		gear_bg = _gear_bg; gear_hover = _gear_hover
		topbar_bg = _topbar_bg; topbar_border = _topbar_border
		shadow_offset = _shadow_offset


var theme_night := ThemeColors.new(
	Color("#0f0e17"), Color("#f9d371"), Color("#000000"),
	Color("#e8d5b7"), Color("#ffffff"),
	Color("#1a1a2e"), Color("#2a2a4e"), Color("#0a0a1e"),
	Color("#9a9ab0"), Color("#000000"),
	Color("#1a1a2e"), Color("#2a2a4e"),
	Color("#1e1e3a"), Color("#3a3a5e"),
	6
)

var theme_day := ThemeColors.new(
	Color("#f5f0e8"), Color("#c0392b"), Color("#8a6b5a"),
	Color("#3d2b1f"), Color("#000000"),
	Color("#ede0d4"), Color("#d4c4b0"), Color("#c0a890"),
	Color("#7a6b5a"), Color("#d4c4b0"),
	Color("#ede0d4"), Color("#d4c4b0"),
	Color("#d6c8b8"), Color("#b8a898"),
	4
)

var current_mode: ThemeMode = ThemeMode.NIGHT
var current: ThemeColors:
	get: return theme_night if current_mode == ThemeMode.NIGHT else theme_day

# 预加载的场景缓存（LoadingScreen填充，各场景直接用change_scene_to_packed切换）
var preloaded_scenes: Dictionary = {}
# 服务器卡组池缓存（加载界面拉取，后续虚拟匹配使用）
var server_decks: Array = []
var server_decks_loaded: bool = false
# 服务器卡包缓存（加载界面拉取，后续开包使用）
var server_card_packs: Array = []
var server_card_packs_loaded: bool = false

# ============================================================
#  租借卡组系统（商店街租借决斗场AI卡组，独立存储，不并入图鉴/牌库，耐久消耗）
# ============================================================
const RENTED_DECK_MAX_DURABILITY := 10   # 单次租借获得的耐久（同名重复租借持续叠加，无上限）
const RENT_COST_GOLD := 100              # 金币租借价格
const RENT_DUR_COST_EXPLORE := 3         # 进入地图探索扣耐久
const RENT_DUR_COST_DUEL := 1            # 进入决斗场扣耐久

# 当前是否正携带一套租借卡组（战斗加载时据此走租借分支）
var current_rented_deck_id: String = ""
var current_rented_deck_name: String = ""

## 获取所有租借卡组（Dictionary: { "rented_id": {name, cards:[卡id], card_datas:[完整卡对象], durability:int, source_deck:String}, ... }）
func get_all_rented_decks() -> Dictionary:
	return SaveManager.get_value("player", "rented_decks", {})

## 租借一套决斗场AI卡组（来源 server_decks 的 deck_data）
## 同名卡组重复租借 = 耐久持续叠加（无上限）
## 返回 {"ok":bool, "id":String, "durability":int, "reason":String}
func rent_deck(source_deck_data: Dictionary) -> Dictionary:
	var dname = source_deck_data.get("name", "租借卡组")
	var card_datas = source_deck_data.get("card_datas", [])
	if card_datas.is_empty():
		return {"ok": false, "id": "", "durability": 0, "reason": "卡组内容为空"}
	var rented = get_all_rented_decks()
	# 提取卡id（用于显示张数），同时存完整卡对象（战斗直接用，不依赖图鉴）
	var cids := []
	for c in card_datas:
		cids.append(c.get("id", c.get("name", "")))
	# 同名已租 → 叠加耐久（刷新卡数据为最新真源）
	for rid in rented:
		if rented[rid].get("source_deck", "") == dname:
			var rd = rented[rid]
			var cur = int(rd.get("durability", 0))
			rd["durability"] = cur + RENTED_DECK_MAX_DURABILITY
			rd["cards"] = cids
			rd["card_datas"] = card_datas.duplicate(true)
			SaveManager.set_value("player", "rented_decks", rented)
			SaveManager.save_to_disk()
			print("[租借] 叠加耐久: ", dname, " ", cur, "→", rd["durability"])
			return {"ok": true, "id": rid, "durability": rd["durability"], "reason": "已叠加"}
	# 未租过 → 新建
	var rid = "rented_%d" % (Time.get_ticks_msec() + randi() % 1000)
	rented[rid] = {
		"name": dname,
		"cards": cids,
		"card_datas": card_datas.duplicate(true),
		"durability": RENTED_DECK_MAX_DURABILITY,
		"source_deck": dname,
	}
	SaveManager.set_value("player", "rented_decks", rented)
	SaveManager.save_to_disk()
	print("[租借] 租得卡组: ", dname, " id=", rid)
	return {"ok": true, "id": rid, "durability": RENTED_DECK_MAX_DURABILITY, "reason": "已租借"}

## 扣租借卡组耐久，归0则删除（不保留0耐久条目）。返回剩余耐久
func consume_rented_durability(rid: String, amount: int) -> int:
	var rented = get_all_rented_decks()
	if not rented.has(rid): return -1
	var dur = int(rented[rid].get("durability", 0)) - amount
	var left = dur if dur > 0 else 0
	if left <= 0:
		rented.erase(rid)
		# 若当前携带的正是这套，清除携带状态
		if current_rented_deck_id == rid:
			current_rented_deck_id = ""; current_rented_deck_name = ""
		print("[租借] 卡组耐久归0，已删除: ", rid)
	else:
		rented[rid]["durability"] = left
		print("[租借] 卡组耐久: ", rid, " -", amount, " 剩", left)
	SaveManager.set_value("player", "rented_decks", rented)
	SaveManager.save_to_disk()
	return left

## 获取单套租借卡组
func get_rented_deck(rid: String) -> Dictionary:
	return get_all_rented_decks().get(rid, {})

# ============================================================
#  后台场景加载（已废弃——改为 LoadingScreen 同步预加载）
# ============================================================
# 保留 start_background_loading 接口但内部不再做异步循环
func start_background_loading(scenes_to_preload: Array, total_tasks: int) -> void:
	pass  # 同步预加载已在 LoadingScreen 完成，此处无需异步循环

## 全局场景切换函数——优先使用预加载的场景缓存，瞬间切换无等待
# 战斗界面模式：false=横屏3D（默认），true=竖屏2D旧版
var use_legacy_battle: bool = false

# 根据设置返回战斗场景路径
func get_battle_scene_path() -> String:
	if use_legacy_battle:
		return "res://BattleSceneLegacy.tscn"
	return "res://BattleScene3D.tscn"

# ============================================================
# 横屏战斗画布
# 项目默认画布是竖屏 1080x1920（display/window/size/viewport_*），
# 而 BattleScene3D 的 HUD 全部是按横屏 1920x1080 的固定坐标手写布局的。
# 只调 DisplayServer.window_set_size 改不了逻辑画布：content_scale_size 仍被
# 项目设置钉在 1080x1920，结果横屏 HUD 被竖向压扁、底部一排按钮直接被裁掉。
# 因此进出战斗时必须同时切 content_scale_size，并用 KEEP（信箱）而不是
# EXPAND：EXPAND 会把可见区拉到 1920x3413，固定 Y 坐标的 UI 又跑偏。
# ============================================================
## 进入横屏战斗：逻辑画布切 1920x1080，窗口比例不符时留黑边而不是拉伸
func enter_landscape_canvas() -> void:
	landscape_canvas = true
	var w: Window = get_window()
	if w:
		w.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
		w.content_scale_size = CANVAS_LANDSCAPE
	DisplayServer.screen_set_orientation(DisplayServer.SCREEN_LANDSCAPE)
	DisplayServer.window_set_size(CANVAS_LANDSCAPE)

## 退出横屏战斗：恢复竖屏画布与 EXPAND 拉伸
func exit_landscape_canvas() -> void:
	landscape_canvas = false
	var w: Window = get_window()
	if w:
		w.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
		w.content_scale_size = CANVAS_PORTRAIT
	DisplayServer.screen_set_orientation(DisplayServer.SCREEN_PORTRAIT)
	DisplayServer.window_set_size(CANVAS_PORTRAIT)

func change_scene(path: String) -> void:
	var _t = Time.get_ticks_msec()
	# 缓存命中：直接切换（秒切）
	if preloaded_scenes.has(path):
		print("[Scene] %s 缓存命中 change_scene_to_packed: %dms" % [path, Time.get_ticks_msec() - _t])
		get_tree().change_scene_to_packed(preloaded_scenes[path])
		return
	# 缓存未命中：同步加载后切换（比 change_scene_to_file 更快，因为已有资源缓存）
	var packed = load(path)
	if packed:
		preloaded_scenes[path] = packed
		print("[Scene] %s 同步加载: %dms" % [path, Time.get_ticks_msec() - _t])
		get_tree().change_scene_to_packed(packed)
		return
	# 最终 fallback
	print("[Scene] %s fallback change_scene_to_file: %dms" % [path, Time.get_ticks_msec() - _t])
	get_tree().change_scene_to_file(path)
signal theme_changed(mode: ThemeMode)

# ============================================================
#  音效管理器（CC0 素材，Kenney Casino + Kenney UI + Lokif GUI）
#  每个音效预建独立 AudioStreamPlayer 并预绑 stream
#  播放时只调 .play()，零中间操作，最低延迟
# ============================================================
var _sfx_pool: Dictionary = {}  # key -> AudioStreamPlayer（已预绑stream）
var _sfx_enabled: bool = true

## 音效名 → 文件路径 映射（语义化命名，方便调用）
const SFX_MAP := {
	# --- UI 音效 ---
	"click": "res://assets/audio/ui/click1.wav",
	"click_alt": "res://assets/audio/ui/click2.wav",
	"hover": "res://assets/audio/ui/rollover1.wav",
	"switch": "res://assets/audio/ui/switch1.wav",
	"confirm": "res://assets/audio/ui/positive.wav",
	"cancel": "res://assets/audio/ui/negative.wav",
	"save": "res://assets/audio/ui/save.wav",
	"load": "res://assets/audio/ui/load.wav",
	"menu": "res://assets/audio/ui/misc_menu.wav",
	"error": "res://assets/audio/ui/negative_2.wav",
	"echo": "res://assets/audio/ui/sharp_echo.wav",
	# --- 卡牌音效 ---
	"draw": "res://assets/audio/card/draw.wav",
	"deal": "res://assets/audio/card/deal.wav",
	"deal_alt": "res://assets/audio/card/deal_alt.wav",
	"flip": "res://assets/audio/ui/misc_menu_2.wav",
	"fan": "res://assets/audio/ui/rollover2.wav",
	"pack_open": "res://assets/audio/ui/misc_sound.wav",
	"pack_take": "res://assets/audio/ui/rollover3.wav",
	"shuffle": "res://assets/audio/ui/switch2.wav",
	# --- 战斗音效 ---
	"attack_hit": "res://assets/audio/card/attack_hit.wav",
	"effect_cast": "res://assets/audio/ui/sharp_echo.wav",
	"card_death": "res://assets/audio/card/card_death.wav",
	"damage": "res://assets/audio/system/damage.wav",
	"heal": "res://assets/audio/ui/positive.wav",
	"destroy": "res://assets/audio/card/destroy.wav",
	# --- 系统/金币音效 ---
	"coin": "res://assets/audio/ui/switch3.wav",
	"coin_stack": "res://assets/audio/ui/switch4.wav",
	"dice": "res://assets/audio/ui/switch5.wav",
}

func _init_sfx() -> void:
	if _sfx_pool.size() > 0:
		return
	for key in SFX_MAP.keys():
		var res = load(SFX_MAP[key])
		if not res and SFX_MAP[key].ends_with(".wav"):
			# load() 失败时，尝试直接从文件读取wav构建AudioStreamWAV
			res = _load_wav_from_file(SFX_MAP[key])
		if res:
			var p = AudioStreamPlayer.new()
			p.name = "Sfx_" + key
			p.stream = res
			p.volume_db = 0.0
			add_child(p)
			_sfx_pool[key] = p
		else:
			print("[SFX] ⚠️ 加载失败: %s" % SFX_MAP[key])
	print("[SFX] ✅ 音效池初始化完成，共 %d 个" % _sfx_pool.size())


## 从文件系统直接读取wav构建AudioStreamWAV（load()失败时的后备方案）
func _load_wav_from_file(res_path: String) -> AudioStreamWAV:
	# res:// → 实际文件路径
	var file_path = res_path.replace("res://", "")
	var fa = FileAccess.open(file_path, FileAccess.READ)
	if not fa:
		print("[SFX] 文件打开失败: %s" % file_path)
		return null
	# 读取RIFF头
	var riff = fa.get_buffer(4)
	if riff.get_string_from_ascii() != "RIFF":
		fa.close()
		return null
	fa.get_32()  # 文件大小
	var wave = fa.get_buffer(4)
	if wave.get_string_from_ascii() != "WAVE":
		fa.close()
		return null
	# 解析fmt和data chunk
	var format_code := 0
	var num_channels := 1
	var sample_rate := 44100
	var byte_rate := 0
	var block_align := 0
	var bits_per_sample := 16
	var audio_data := PackedByteArray()
	while fa.get_position() < fa.get_length():
		var chunk_id = fa.get_buffer(4).get_string_from_ascii()
		var chunk_size = fa.get_32()
		if chunk_id == "fmt ":
			format_code = fa.get_16()
			num_channels = fa.get_16()
			sample_rate = fa.get_32()
			byte_rate = fa.get_32()
			block_align = fa.get_16()
			bits_per_sample = fa.get_16()
			# 跳过剩余的fmt数据
			if chunk_size > 16:
				fa.seek(fa.get_position() + chunk_size - 16)
		elif chunk_id == "data":
			audio_data = fa.get_buffer(chunk_size)
		else:
			# 跳过未知chunk
			fa.seek(fa.get_position() + chunk_size)
		# 对齐到偶数位置
		if chunk_size % 2 == 1:
			var pos = fa.get_position()
			fa.seek(pos + 1)
	fa.close()
	if audio_data.is_empty():
		return null
	var stream = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS if bits_per_sample == 16 else AudioStreamWAV.FORMAT_8_BITS
	stream.mix_rate = sample_rate
	stream.stereo = num_channels == 2
	stream.data = audio_data
	return stream

## 播放音效（一行调用）：Global.play_sfx("click")
func play_sfx(sfx_name: String) -> void:
	if not _sfx_enabled:
		return
	if _sfx_pool.has(sfx_name):
		_sfx_pool[sfx_name].play()
	else:
		print("[SFX] 未知音效: %s" % sfx_name)

## 设置音效开关
func set_sfx_enabled(enabled: bool) -> void:
	_sfx_enabled = enabled

# ============================================================
#  PvP对战系统配置（已注释：PvP对战功能已移除过审）
# ============================================================
# const SUPABASE_URL: String = "https://mosdtstftotjcfgctaxg.supabase.co"
# const SUPABASE_ANON_KEY: String = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1vc2R0c3RmdG90amNmZ2N0YXhnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODU1MjM2MTksImV4cCI6MjEwMTA5OTYxOX0.qpLnut-aj1JcDEfhETAeb6fupaFpvx02kF-GfnzosZM"
# var pvp_player_id: String = ""  # 当前玩家唯一ID
# var pvp_player_name: String = "卡师"
# var pvp_player_deck_id: String = ""  # PvP使用的卡组ID
# var pvp_battle_id: String = ""  # 当前对战的battle_id

# 地图数据传递（用于爬塔地图）
var current_map_id: String = ""
var current_map_name: String = ""

# 卡组选择传递（用于战斗场景）
var current_deck_id: String = ""
var current_deck_name: String = ""

# 敌人数据传递（用于爬塔战斗）
var current_enemy_data: Dictionary = {}
var current_battle_terrain: String = ""  # 当前战斗的地形（用于掉落判定）
var current_map_layer: int = -1  # 当前地图层数，用于战斗后返回
var current_map_node: int = -1   # 当前地图节点索引，用于战斗后滚动到该节点位置
var current_is_boss: bool = false  # 当前战斗是否为BOSS战（用于通关标记）
var current_is_ambush: bool = false  # 当前战斗是否为伏击战（采集彩蛋，双倍掉落）
var is_tutorial_battle: bool = false  # 当前战斗是否为新手教学战（教战AI放水+教学提示条）
# 爬塔持久HP（让休息节点有意义，每次进入地图时重置）
var current_run_player_hp: int = -1  # 当前爬塔的玩家HP，-1表示未初始化
var current_run_player_max_hp: int = 0  # 当前爬塔的玩家最大HP
var saved_map_node_data: Array = []  # 保存地图节点状态(available/completed)，用于战斗后恢复
var _enemy_data_cache: Dictionary = {}

func load_enemy_data() -> Dictionary:
	if _enemy_data_cache.size() > 0:
		return _enemy_data_cache
	var file = FileAccess.open("res://Data/enemies.json", FileAccess.READ)
	if file == null:
		print("[Global] 警告：无法读取敌人数据文件 res://Data/enemies.json")
		return {}
	var json_str = file.get_as_text()
	file.close()
	var json := JSON.new()
	var err := json.parse(json_str)
	if err != OK:
		print("[Global] 敌人JSON解析错误：", json.get_error_message())
		return {}
	_enemy_data_cache = json.get_data()
	print("[Global] 敌人数据加载完成")
	return _enemy_data_cache
func get_enemy_card_template(template_id: String) -> Dictionary:
	var data = load_enemy_data()
	return data.get("card_templates", {}).get(template_id, {})
func get_map_monsters(map_id: String, terrain: String) -> Array:
	var data = load_enemy_data()
	var maps = data.get("maps", {})
	var map_data = maps.get(map_id, {})
	var terrains = map_data.get("terrains", {})
	var terrain_data = terrains.get(terrain, {})
	return terrain_data.get("monsters", [])

## 获取某地图的BOSS数据（从3个BOSS中随机选一个）
func get_map_boss(map_id: String) -> Dictionary:
	var data = load_enemy_data()
	var maps = data.get("maps", {})
	var map_data = maps.get(map_id, {})
	var boss_list = map_data.get("boss", [])
	
	if boss_list is Array and boss_list.size() > 0:
		var rng = RandomNumberGenerator.new()
		rng.randomize()
		var chosen = boss_list[rng.randi_range(0, boss_list.size() - 1)]
		print("[Global] 随机选中BOSS: ", chosen.get("name", "未知"))
		return chosen.duplicate(true)
	
	return {}

# ============================================================
#  素材数据系统
# ============================================================

var material_data: Dictionary = {}
var formula_data: Dictionary = {}
var _material_map: Dictionary = {}


func get_material_by_id(id: String) -> Dictionary:
	return _material_map.get(id, {})

func get_fiber_list() -> Array:
	return material_data.get("fiber", [])

func get_mineral_list() -> Array:
	return material_data.get("mineral", [])

func get_resin_list() -> Array:
	return material_data.get("resin", [])

func get_extract_list() -> Array:
	return material_data.get("extract", [])

func get_pigment_list() -> Array:
	return material_data.get("pigment", [])

func get_binder_list() -> Array:
	return material_data.get("binder", [])

func get_formulas() -> Dictionary:
	return formula_data

## 获取某地图某地形可采集的素材列表
## 返回 Array[{material_id, name, rarity, min, max, prob}]
func get_gather_materials(map_id: String, terrain: String) -> Array:
	var result := []
	for cat in ["fiber", "mineral", "resin", "extract", "pigment", "binder"]:
		for mat in material_data.get(cat, []):
			var gather_info = mat.get("gather", {})
			var terrain_list = gather_info.get(map_id, [])
			for entry in terrain_list:
				if entry.get("terrain", "") == terrain:
					result.append({
						"material_id": mat.get("id", ""),
						"name": mat.get("name", ""),
						"rarity": mat.get("rarity", "普通"),
						"min": entry.get("min", 1),
						"max": entry.get("max", 1),
						"prob": entry.get("prob", 0.5),
					})
	return result

func _load_materials() -> void:
	var file = FileAccess.open("res://Data/materials.json", FileAccess.READ)
	if file == null:
		print("[Global] 警告：无法读取素材数据文件 res://Data/materials.json")
		return

	var json_str = file.get_as_text()
	file.close()
	var json := JSON.new()
	var err := json.parse(json_str)
	if err != OK:
		print("[Global] 素材JSON解析错误：", json.get_error_message())
		return

	var data = json.get_data()
	material_data = data.get("materials", {})
	formula_data = data.get("formulas", {})
	_material_map.clear()
	for category in ["fiber", "mineral", "resin", "extract", "pigment", "binder"]:
		for mat in material_data.get(category, []):
			var mid = mat.get("id", "")
			if mid != "":
				_material_map[mid] = mat

	print("[Global] 素材数据加载完成")

# ============================================================
#  纹路组件系统（90个）
# ============================================================
# 9.3 触发器（17个）
# 格式: {"id": "TR01", "name": "...", "speed": 1, "once_only": true, "base_load": 0.4}
var circuit_triggers := [
	{"id": "TR01", "name": "召唤成功时", "speed": 1, "once_only": true, "base_energy": 0.5, "base_load": 0.4,
		"desc": "卡牌从手牌打出到场上时触发。只触发被召唤的卡牌自身，不扫描全场。速度1，可被速度2效果连锁响应。仅触发一次。"},
	# {"id": "TR02", "name": "特殊召唤成功时", "speed": 1, "once_only": true, "base_energy": 0.5, "base_load": 0.4},
	# {"id": "TR03", "name": "从墓地特殊召唤时", "speed": 1, "once_only": true, "base_energy": 0.8, "base_load": 0.6},
	# {"id": "TR04", "name": "被战斗破坏时", "speed": 1, "once_only": false, "base_energy": 1.0, "base_load": 0.8},
	{"id": "TR06", "name": "被送去墓地时", "speed": 1, "once_only": false, "base_energy": 0.8, "base_load": 0.6,
		"desc": "卡牌从场上被送入墓地时触发。只触发被送墓的卡牌自身，不扫描全场。速度1，可被速度2效果连锁响应。每次送墓都会触发。"},
	# {"id": "TR07", "name": "被除外时", "speed": 1, "once_only": false, "base_energy": 0.8, "base_load": 0.6},
	# {"id": "TR08", "name": "离开场上时", "speed": 1, "once_only": false, "base_energy": 0.8, "base_load": 0.6},
	{"id": "TR09", "name": "攻击宣言时", "speed": 1, "once_only": false, "base_energy": 1.2, "base_load": 1.0,
		"desc": "己方卡牌宣告攻击时、在攻击执行前触发。只触发攻击卡自身，不扫描全场。无论攻击卡牌还是攻击英雄都会触发。速度1，可被速度2效果连锁响应。"},
	{"id": "TR10", "name": "被攻击时", "speed": 1, "once_only": false, "base_energy": 1.0, "base_load": 0.8,
		"desc": "己方卡牌被选为攻击目标时、在攻击执行前触发。只触发被攻击的卡牌自身，不扫描全场。速度1，可被速度2效果连锁响应。"},
	{"id": "TR11", "name": "给予战斗伤害时", "speed": 1, "once_only": false, "base_energy": 1.2, "base_load": 1.0,
		"desc": "己方卡牌攻击造成伤害后触发。只触发攻击卡自身，不扫描全场。攻击卡牌需对防御方造成伤害，攻击英雄需对英雄造成伤害。速度1，可被速度2效果连锁响应。"},
	{"id": "TR12", "name": "己方回合开始时", "speed": 1, "once_only": false, "base_energy": 1.5, "base_load": 1.2,
		"desc": "己方回合的准备阶段开始时触发。扫描己方场上所有存活卡牌。速度1，可被速度2效果连锁响应。"},
	{"id": "TR13", "name": "对方回合开始时", "speed": 1, "once_only": false, "base_energy": 1.5, "base_load": 1.2,
		"desc": "对方回合的准备阶段开始时触发。扫描对方场上所有存活卡牌。速度1，可被速度2效果连锁响应。"},
	{"id": "TR14", "name": "己方回合结束时", "speed": 1, "once_only": false, "base_energy": 1.2, "base_load": 1.0,
		"desc": "己方回合的结束阶段触发。扫描己方场上所有存活卡牌。速度1，可被速度2效果连锁响应。"},
	{"id": "TR15", "name": "对方回合结束时", "speed": 1, "once_only": false, "base_energy": 1.2, "base_load": 1.0,
		"desc": "对方回合的结束阶段触发。扫描对方场上所有存活卡牌。速度1，可被速度2效果连锁响应。"},
	{"id": "TR16", "name": "对方发动效果时", "speed": 2, "once_only": false, "base_energy": 2.0, "base_load": 1.6,
		"desc": "对方发动效果（包括召唤时、攻击时、送墓时等）时触发，可连锁响应。扫描对方场上所有存活卡牌。速度2，可连锁速度1效果。"},
	{"id": "TR17", "name": "对方召唤成功时", "speed": 2, "once_only": false, "base_energy": 1.5, "base_load": 1.2,
		"desc": "对方成功召唤卡牌到场上时触发。扫描对方场上所有存活卡牌。速度2，可连锁速度1效果。"},
	{"id": "TR18", "name": "控制权转移时", "speed": 2, "once_only": false, "base_energy": 2.0, "base_load": 1.6,
		"desc": "场上任意卡牌控制权变更（夺取/归还/交换）时触发。扫描全场卡牌。速度2，可连锁速度1效果。"},
]
# 9.4 条件（15个）
var circuit_conditions := [
	{"id": "C01", "name": "场上存在指定字段", "params": "字段名", "base_energy": 0.3, "base_load": 1.5},
	{"id": "C02", "name": "场上怪兽数量", "params": "比较符+数值", "base_energy": 0.3, "base_load": 1.0},
	{"id": "C04", "name": "生命值比较", "params": "比较符+数值", "base_energy": 0.3, "base_load": 1.0},
	{"id": "C06", "name": "生命值差", "params": "数值", "base_energy": 0.4, "base_load": 1.2},
	{"id": "C07", "name": "手牌数", "params": "比较符+数值", "base_energy": 0.3, "base_load": 1.0},
	{"id": "C08", "name": "能量点", "params": "数值", "base_energy": 0.3, "base_load": 1.0},
	{"id": "C09", "name": "墓地卡牌数量", "params": "比较符+数值", "base_energy": 0.3, "base_load": 1.2},
	{"id": "C10", "name": "墓地存在字段卡", "params": "字段名", "base_energy": 0.3, "base_load": 1.5},
	# {"id": "C11", "name": "除外区卡牌数量", "params": "比较符+数值", "base_energy": 0.3, "base_load": 0.2},
	{"id": "C12", "name": "卡组数量", "params": "比较符+数值", "base_energy": 0.3, "base_load": 1.2},
	# {"id": "C13", "name": "手牌中特定卡", "params": "字段名", "base_energy": 0.3, "base_load": 0.2},
	# {"id": "C14", "name": "本回合发动过N次", "params": "数值", "base_energy": 0.4, "base_load": 0.2},
	# {"id": "C15", "name": "己方场上只有X字段", "params": "字段名", "base_energy": 0.5, "base_load": 0.3},
	{"id": "C16", "name": "控制权异动卡数量", "params": "比较符+数值", "base_energy": 0.3, "base_load": 1.2},
]
# 9.5 动作（30个）
var circuit_actions := [
	{"id": "A01", "name": "效果伤害", "base_energy": "数值×0.8", "default_element": "火", "base_load": 1.8},
	{"id": "A02", "name": "恢复生命", "base_energy": "数值×0.6", "default_element": "水", "base_load": 1.5},
	{"id": "A03", "name": "破坏", "base_energy": 3.0, "default_element": "无", "base_load": 9.0},
	# {"id": "A04", "name": "除外", "base_energy": 4.0, "default_element": "暗", "base_load": 2.5},
	# {"id": "A05", "name": "除外墓地卡", "base_energy": 2.0, "default_element": "暗", "base_load": 1.5},
	{"id": "A06", "name": "弹回手牌", "base_energy": 3.0, "default_element": "风", "base_load": 6.0},
	{"id": "A07", "name": "弹回卡组", "base_energy": 4.0, "default_element": "风", "base_load": 9.5},
	# {"id": "A08", "name": "送入墓地(非破坏)", "base_energy": 2.5, "default_element": "无", "base_load": 1.8},
	{"id": "A09", "name": "抽牌", "base_energy": "数值×1.5", "default_element": "风", "base_load": 2.5},
	# {"id": "A10", "name": "检索字段卡", "base_energy": 2.0, "default_element": "风", "base_load": 1.5},
	# {"id": "A11", "name": "检索卡", "base_energy": 3.0, "default_element": "风", "base_load": 2.0},
	# {"id": "A12", "name": "墓地回收", "base_energy": 2.5, "default_element": "无", "base_load": 1.8},
	# {"id": "A13", "name": "除外回收", "base_energy": 3.0, "default_element": "无", "base_load": 2.0},
	# {"id": "A14", "name": "卡组堆墓", "base_energy": "数值×1.0", "default_element": "无", "base_load": 1.0},
	# {"id": "A15", "name": "手牌特召", "base_energy": 3.0, "default_element": "无", "base_load": 2.0},
	# {"id": "A16", "name": "墓地特召", "base_energy": 3.5, "default_element": "无", "base_load": 2.5},
	# {"id": "A17", "name": "卡组特召", "base_energy": 4.0, "default_element": "无", "base_load": 3.0},
	# {"id": "A18", "name": "除外特召", "base_energy": 4.5, "default_element": "无", "base_load": 3.0},
	# {"id": "A19", "name": "召唤衍生物", "base_energy": "2+攻×0.5+命×0.3×数量", "default_element": "无", "base_load": 2.5},
	{"id": "A20", "name": "攻击力增减(永久)", "base_energy": "数值×0.7", "default_element": "无", "base_load": 1.5},
	{"id": "A21", "name": "生命值增减(永久)", "base_energy": "数值×0.5", "default_element": "水", "base_load": 1.2},
	# {"id": "A22", "name": "攻命同时增减", "base_energy": "数值×1.0", "default_element": "无", "base_load": 1.5},
	{"id": "A23", "name": "回合内攻命增减", "base_energy": "数值×0.5", "default_element": "无", "base_load": 1.0},
	# {"id": "A24", "name": "全场增减", "base_energy": "数值×1.2", "default_element": "无", "base_load": 1.5},
	{"id": "A25", "name": "交换攻防", "base_energy": 2.5, "default_element": "无", "base_load": 3.0},
	# {"id": "A26", "name": "暂时夺取控制权", "base_energy": 4.0, "default_element": "暗", "base_load": 2.5},
	# {"id": "A27", "name": "永久夺取控制权", "base_energy": 6.0, "default_element": "暗", "base_load": 3.5},
	# {"id": "A28", "name": "无法攻击", "base_energy": 2.0, "default_element": "无", "base_load": 1.5},
	# {"id": "A29", "name": "表示形式变更", "base_energy": 1.5, "default_element": "无", "base_load": 1.0},
	# {"id": "A30", "name": "无效效果发动并破坏", "base_energy": 3.5, "default_element": "光", "base_load": 2.5},
	{"id": "A31", "name": "控制权变更·一回合", "base_energy": 4.0, "default_element": "暗", "base_load": 11.0},
	{"id": "A32", "name": "控制权变更·永久", "base_energy": 6.0, "default_element": "暗", "base_load": 13.0},
	{"id": "A33", "name": "禁用效果（一回合）", "base_energy": 3.0, "default_element": "光", "base_load": 6.0},
]
# 9.6 目标（12个）
var circuit_targets := [
	# {"id": "T01", "name": "自身", "modifier": 1.0, "base_load": 0.3},
	{"id": "T02", "name": "敌方单体", "modifier": 1.0, "base_load": 0.5},
	{"id": "T03", "name": "己方单体", "modifier": 1.0, "base_load": 0.3},
	{"id": "T04", "name": "敌方全体", "modifier": 1.8, "base_load": 4.0},
	{"id": "T05", "name": "己方全体", "modifier": 1.8, "base_load": 3.0},
	{"id": "T06", "name": "全场", "modifier": 2.2, "base_load": 5.0},
	# {"id": "T07", "name": "敌方英雄", "modifier": 1.2, "base_load": 0.5},
	# {"id": "T08", "name": "己方英雄", "modifier": 1.0, "base_load": 0.3},
	# {"id": "T09", "name": "手牌", "modifier": 1.0, "base_load": 0.5},
	{"id": "T10", "name": "墓地", "modifier": 1.0, "base_load": 0.6},
	# {"id": "T11", "name": "卡组", "modifier": 1.2, "base_load": 0.8},
	# {"id": "T12", "name": "除外区", "modifier": 1.2, "base_load": 0.8},
	{"id": "T13", "name": "对方攻击最高", "modifier": 1.0, "base_load": 0.8},
	{"id": "T14", "name": "对方攻击最低", "modifier": 1.0, "base_load": 0.8},
	{"id": "T15", "name": "我方攻击最高", "modifier": 1.0, "base_load": 0.8},
	{"id": "T16", "name": "我方攻击最低", "modifier": 1.0, "base_load": 0.8},
]
# 9.7 约束（16个）
var circuit_constraints := [
	# {"id": "CO01", "name": "一回合一次", "energy_adjust": -1.5, "base_load": 0.5},
	# {"id": "CO02", "name": "一局一次", "energy_adjust": -3.0, "base_load": 1.0},
	{"id": "CO03", "name": "支付生命", "energy_adjust": "-X×0.2", "base_load": 0.8},
	{"id": "CO04", "name": "舍弃手牌", "energy_adjust": "-X×0.8", "base_load": 1.0},
	{"id": "CO05", "name": "消耗能量点", "energy_adjust": "-X×0.5", "base_load": 0.5},
	# {"id": "CO06", "name": "发动后除外", "energy_adjust": -2.5, "base_load": 0.8},
	# {"id": "CO07", "name": "效果后自毁", "energy_adjust": -2.0, "base_load": 0.7},
	# {"id": "CO08", "name": "仅己方回合", "energy_adjust": -0.5, "base_load": 0.2},
	# {"id": "CO09", "name": "仅对方回合", "energy_adjust": -0.5, "base_load": 0.2},
	# {"id": "CO10", "name": "仅主要阶段", "energy_adjust": -0.3, "base_load": 0.1},
	# {"id": "CO11", "name": "仅战斗阶段", "energy_adjust": -0.3, "base_load": 0.1},
	# {"id": "CO12", "name": "发动后受伤害", "energy_adjust": "-X×0.5", "base_load": 0.5},
	# {"id": "CO13", "name": "不可被连锁", "energy_adjust": 2.0, "base_load": 0.8},
	# {"id": "CO14", "name": "不受对方效果影响", "energy_adjust": 3.0, "base_load": 1.5},
	# {"id": "CO15", "name": "仅对克制属性生效", "energy_adjust": -1.0, "base_load": 0.3},
	# {"id": "CO16", "name": "仅对被克制属性生效", "energy_adjust": 1.5, "base_load": 0.5},
]
# 9.8 互斥规则
var circuit_mutex := {
	"triggers": [["TR09", "TR10"],["TR12", "TR13"], ["TR14", "TR15"]],
	"conditions": [["C02", "C04"]],
	"actions": [["A06", "A07"]],
	"targets": [["T04", "T06"]],
	"constraints": [],
	# ★ 动作×目标互斥（硬逻辑矛盾）
	"action_target_pairs": [
		# 增益/属性操作 → 不能对墓地（墓地卡无属性）
		["A20", "T10"],  # 攻击力增减 → 墓地
		["A21", "T10"],  # 生命值增减 → 墓地
		["A23", "T10"],  # 回合内攻命增减 → 墓地
		["A25", "T10"],  # 交换攻防 → 墓地
		["A31", "T10"],  # 控制权变更·一回合 → 墓地
		["A32", "T10"],  # 控制权变更·永久 → 墓地
		["A33", "T10"],  # 禁用效果 → 墓地（墓地卡效果已失效）
		# 抽牌 → 不能从墓地抽（语义混乱）
		["A09", "T10"],  # 抽牌 → 墓地
	]
}
var _circuit_map: Dictionary = {}
# 14.1 初始解锁组件（15个）
var initial_unlocked := ["TR01", "A01", "T02"]
# 14.2 解锁路径（已废弃，改用公会等级系统）
var unlock_paths := [{"condition": "首次制卡", "guild_level": 1, "unlock": ["C07", "A20", "T03"]},{"condition": "制作3张卡", "guild_level": 2, "unlock": ["C01", "A02", "A09"]},{"condition": "制作10张卡", "guild_level": 3, "unlock": ["TR12", "C02", "CO04", "C12"]},{"condition": "制作20张卡", "guild_level": 4, "unlock": ["TR14", "TR15", "C04", "A21"]},{"condition": "首张卓越品质", "guild_level": 4, "unlock": ["C10"]},{"condition": "首张完美品质", "guild_level": 6, "unlock": ["TR16"]},{"condition": "累计造成500点伤害", "guild_level": 4, "unlock": ["TR09", "TR11", "A03"]},{"condition": "累计恢复500点生命", "guild_level": 4, "unlock": ["C06", "A23", "T04"]},{"condition": "累计消耗100点能量", "guild_level": 3, "unlock": ["C08", "CO05"]},{"condition": "累计特召30次", "guild_level": 4, "unlock": ["TR06", "TR18"]},{"condition": "累计破坏20张卡", "guild_level": 4, "unlock": ["A07", "T06", "A33"]},{"condition": "通关迷雾森林", "guild_level": 5, "unlock": ["C04", "A06", "CO03", "TR10"]},{"condition": "通关火焰洞穴", "guild_level": 7, "unlock": ["TR06", "C09", "T10", "A25"]},{"condition": "完成5次公会任务", "guild_level": 3, "unlock": ["T13", "T14"]},{"condition": "完成20次公会任务", "guild_level": 5, "unlock": ["T15", "T16", "A31", "A32"]},{"condition": "通关暗影沼泽", "guild_level": 9, "unlock": ["T05"]},{"condition": "通关传说遗迹", "guild_level": 10, "unlock": ["TR17"]},{"condition": "卡牌图鉴收集50张", "guild_level": 5, "unlock": ["TR13", "C04", "C16"]},]
func get_all_triggers() -> Array:
	return circuit_triggers.duplicate()

func get_all_conditions() -> Array:
	return circuit_conditions.duplicate()

func get_all_actions() -> Array:
	return circuit_actions.duplicate()

func get_all_targets() -> Array:
	return circuit_targets.duplicate()

func get_all_constraints() -> Array:
	return circuit_constraints.duplicate()

func get_circuit_by_id(id: String) -> Dictionary:
	return _circuit_map.get(id, {})

## 从效果字典生成可读描述（兼容旧格式——没有desc字段的旧卡牌）
func get_effect_desc(eff: Dictionary) -> String:
	# 效果名称前缀（如有自定义名称则前置显示）
	var eff_name = eff.get("name", "")
	if eff_name != "":
		eff_name = "【" + eff_name + "】"
	# 从 trigger/condition/action/target/value/constraints 完整动态生成
	var trigger_id = eff.get("trigger", "")
	var action_id = eff.get("action", "")
	var target_id = eff.get("target", "T01")
	var value = eff.get("value", 0)
	
	var trigger_name = trigger_id
	var t_data = _circuit_map.get(trigger_id, {})
	if t_data.has("name"):
		trigger_name = t_data["name"]
	var action_name = action_id
	var a_data = _circuit_map.get(action_id, {})
	if a_data.has("name"):
		action_name = a_data["name"]
	var target_name = target_id
	var tar_data = _circuit_map.get(target_id, {})
	if tar_data.has("name"):
		target_name = tar_data["name"]
	
	# 目标前缀
	var target_pre = ""
	if target_name == "全场":
		target_pre = "对所有单位"
	elif target_name == "敌方单体":
		target_pre = "敌方单体"
	elif target_name == "己方单体":
		target_pre = "己方单体"
	elif target_name == "自身":
		target_pre = "自身"
	elif target_name == "敌方全体":
		target_pre = "敌方全体"
	elif target_name == "己方全体":
		target_pre = "己方全体"
	elif target_name == "墓地":
		target_pre = "墓地"
	else:
		target_pre = target_name
	
	# 简短拼接
	var parts := []
	if trigger_name == "召唤成功时":
		parts.append("入场：")
	elif trigger_name != "":
		parts.append(trigger_name + "，")
	
	# 条件描述（带参数）
	var conds = eff.get("conditions", [])
	if conds is Array and conds.size() > 0:
		var cond_strs := []
		for cond in conds:
			if not (cond is Dictionary):
				continue
			var cond_id = cond.get("id", "")
			var cond_name = cond_id
			var c_data = _circuit_map.get(cond_id, {})
			if c_data.has("name"):
				cond_name = c_data["name"]
			var param_str = ""
			var param_type = c_data.get("params", "无")
			if param_type == "字段名":
				var field_val = cond.get("字段名", cond.get("field", ""))
				if field_val != "":
					param_str = "「" + field_val + "」"
			elif param_type == "比较符+数值":
				var comp = cond.get("compare", cond.get("comparison", "≥"))
				var val = cond.get("value", cond.get("数值", 0))
				param_str = " " + comp + " " + str(val)
			elif param_type == "数值":
				var val = cond.get("value", cond.get("数值", 0))
				param_str = " " + str(val)
			if param_str != "":
				cond_strs.append(cond_name + param_str)
			else:
				cond_strs.append(cond_name)
		if cond_strs.size() > 0:
			parts.append("（" + "、".join(cond_strs) + "）")
	
	# 动作描述（语义化 + 数值）
	if action_name == "效果伤害":
		parts.append("对" + target_pre + "造成" + str(value) + "点伤害")
	elif action_name == "恢复生命":
		parts.append("恢复" + target_pre + str(value) + "点生命")
	elif action_name == "抽牌":
		parts.append("抽牌" + str(value) + "张")
	elif action_name == "破坏":
		parts.append("破坏" + target_pre)
	elif action_name == "攻击力增减(永久)":
		parts.append("攻击力" + ("+" if value >= 0 else "") + str(value))
	elif action_name == "生命值增减(永久)":
		parts.append("生命值" + ("+" if value >= 0 else "") + str(value))
	elif action_name == "回合内攻命增减":
		parts.append("本回合攻命" + ("+" if value >= 0 else "") + str(value))
	elif action_name == "弹回手牌":
		parts.append("将" + target_pre + "弹回手牌")
	elif action_name == "弹回卡组":
		parts.append("将" + target_pre + "弹回卡组")
	elif action_name == "交换攻防":
		parts.append("交换攻击力与生命值")
	elif action_name == "手牌特召":
		parts.append("从手牌特殊召唤")
	elif action_name == "墓地特召":
		parts.append("从墓地特殊召唤")
	elif action_name == "卡组特召":
		parts.append("从卡组特殊召唤")
	else:
		parts.append(action_name)
		if target_name != "自身":
			parts.append("(" + target_name + ")")
		if value != 0:
			parts.append(" 数值:" + str(value))
	
	# 约束描述（带数值：CO03支付生命×N / CO04舍弃手牌×N / CO12受伤害×N）
	var cons = eff.get("constraints", [])
	if cons is Array and cons.size() > 0:
		var co_strs := []
		for co_id in cons:
			match co_id:
				"CO03":
					co_strs.append("支付生命×" + str(Global.get_constraint_param(eff, "CO03", 10)))
				"CO04":
					co_strs.append("舍弃手牌×" + str(Global.get_constraint_param(eff, "CO04", 1)))
				"CO12":
					co_strs.append("发动后受伤害×" + str(Global.get_constraint_param(eff, "CO12", 5)))
				"CO05":
					var co_val = Global.get_constraint_param(eff, "CO05", 500)
					co_strs.append("需能量≥" + str(co_val))
				_:
					co_strs.append(co_id)
		if co_strs.size() > 0:
			parts.append("（" + "、".join(co_strs) + "）")
	
	if parts.size() > 0:
		return eff_name + "".join(parts)
	
	# 完全无结构化数据时 fallback 到原始 desc
	if eff.has("desc") and eff.get("desc", "") != "":
		return eff_name + eff.get("desc", "")
	
	return eff_name


func get_mutex_by_category(cat: String) -> Array:
	return circuit_mutex.get(cat, [])

## ★ 检查动作×目标是否互斥
func is_action_target_mutex(action_id: String, target_id: String) -> bool:
	var pairs = circuit_mutex.get("action_target_pairs", [])
	for pair in pairs:
		if pair.size() >= 2 and pair[0] == action_id and pair[1] == target_id:
			return true
	return false

func get_initial_unlocked() -> Array:
	return initial_unlocked.duplicate()

func get_unlock_paths() -> Array:
	return unlock_paths.duplicate()

func _build_circuit_map() -> void:
	_circuit_map.clear()
	for item in circuit_triggers:
		_circuit_map[item["id"]] = item
	for item in circuit_conditions:
		_circuit_map[item["id"]] = item
	for item in circuit_actions:
		_circuit_map[item["id"]] = item
	for item in circuit_targets:
		_circuit_map[item["id"]] = item
	for item in circuit_constraints:
		_circuit_map[item["id"]] = item
	print("[Global] 纹路组件加载完成：共 ", _circuit_map.size(), " 个组件")
	print("[Global] 初始解锁：", initial_unlocked.size(), " 个组件")
	print("[Global] 解锁路径：", unlock_paths.size(), " 条")

# ============================================================
#  辅材系统（Aux Items）
# ============================================================

var _aux_item_data: Array = []
var _aux_item_map: Dictionary = {}

func get_aux_list() -> Array:
	return _aux_item_data.duplicate()

func get_aux_by_id(id: String) -> Dictionary:
	return _aux_item_map.get(id, {})

func _load_aux_data() -> void:
	var file = FileAccess.open("res://Data/aux_items.json", FileAccess.READ)
	if file == null:
		print("[Global] 警告：无法读取辅材数据文件 res://Data/aux_items.json")
		return
	var json_str = file.get_as_text()
	file.close()
	var json := JSON.new()
	var err := json.parse(json_str)
	if err != OK:
		print("[Global] 辅材JSON解析错误：", json.get_error_message())
		return
	var data = json.get_data()
	_aux_item_data = data.get("aux_items", [])
	_aux_item_map.clear()
	for item in _aux_item_data:
		var aid = item.get("id", "")
		if aid != "":
			_aux_item_map[aid] = item
	print("[Global] 辅材数据加载完成：共 ", _aux_item_data.size(), " 个辅材")

	# ============================================================
	#  全局纹路解析系统
	# ============================================================

## 解析纹路效果（新格式：TR+C+A+T+CO 或旧格式兼容）
## 返回标准化效果数据
static func parse_circuit(effect_data: Dictionary) -> Dictionary:
	var result = {
	"trigger": "",
	"conditions": [],
	"action": "",
	"target": "",
	"constraints": [],
	"value": 0,
	"field": "",
	"is_valid": false,
	"raw_data": effect_data
	}
	# 新格式：包含 trigger, action, target 字段
	if effect_data.has("trigger") and effect_data.has("action"):
		result.trigger = effect_data.get("trigger", "")
		result.action = effect_data.get("action", "")
		result.target = effect_data.get("target", "")
		result.value = effect_data.get("value", 0)
		result.field = effect_data.get("field", "")
		result.conditions = effect_data.get("conditions", [])
		result.constraints = effect_data.get("constraints", [])
		result["name"] = effect_data.get("name", "")
		result.is_valid = true
		return result
	# 旧格式兼容：{"type":"instant","effect":"damage","value":2,"target":"enemy_hero"}
	# 自动映射为 TR01（召唤成功时）+ A01（效果伤害）+ T02/T07/T04
	var old_type = effect_data.get("type", "instant")
	var old_effect = effect_data.get("effect", "")
	var old_value = effect_data.get("value", 0)
	var old_target = effect_data.get("target", "self")
	# 默认TR01（召唤成功时）
	result.trigger = "TR01"
	result.value = old_value
	result.target = ""
	# 旧格式触发时机映射（type="trigger" 或 type="periodic"）
	var old_trigger = effect_data.get("trigger", "")
	var old_phase = effect_data.get("phase", "")
	if old_trigger == "on_summon":
		result.trigger = "TR01"
	elif old_trigger == "on_destroy":
		result.trigger = "TR04"
	elif old_phase == "start_of_turn":
		result.trigger = "TR12"
	elif old_phase == "end_of_turn":
		result.trigger = "TR14"
	else:
		result.trigger = "TR01"
	# 效果类型映射
	var action_map = {
	"damage": "A01",      # 效果伤害
	"heal_self": "A02",   # 恢复生命（自身）
	"heal": "A02",        # 恢复生命
	"draw": "A09",        # 抽牌
	"summon": "A19",      # 召唤衍生物
	"debuff": "A20",      # 攻击力增减
	"atk_up": "A20",      # 攻击力增加（buff）
	"hp_up": "A21",       # 生命值增加（buff）
	}
	result.action = action_map.get(old_effect, "A01")
	# 目标映射
	var target_map = {
	"self": "T01",
	"hero": "T08",
	"enemy": "T02",
	"enemy_hero": "T07",
	"enemy_all": "T04",
	"enemy_single": "T02",   # 敌方单体→T02
	"all_enemies": "T04",    # 敌方全体→T04
	"friendly": "T03",       # 己方单体→T03
	"ally": "T03",           # 己方单体别名
	}
	result.target = target_map.get(old_target, "T01")
	result.is_valid = true
	return result
static func _norm_field(f: String) -> String:
	return f.replace("　", " ").strip_edges()

static func _card_has_field(ck, field: String) -> bool:
	var nf = _norm_field(field)
	if nf == "":
		return false
	for f in ck.fields:
		if f is String and _norm_field(f) == nf:
			return true
	return false

## 数值比较辅助：支持全部5种比较符（> ≥ = ≤ <）及 >= / <= 变体，兼容中文全角符号
static func _compare_num(count, compare_str: String, param) -> bool:
	var v: float = float(count)
	var p: float = float(param)
	match compare_str:
		">", "＞":
			return v > p
		"≥", ">=", "＞=":
			return v >= p
		"≤", "<=", "＜=":
			return v <= p
		"<", "＜":
			return v < p
		"=", "==", "＝":
			return v == p
		"!=", "≠":
			return v != p
	return false

## 检查条件是否满足
static func check_condition(condition_data: Dictionary, owner, opponent, source_card = null) -> bool:
	var condition_id = condition_data.get("id", "")
	# 兼容制卡系统中存储的中文/备选键名和 battle 系统中使用的标准键名
	# param: 兼容 "param" / "数值" / "value"
	var param = condition_data.get("param", condition_data.get("数值", condition_data.get("value", 0)))
	# field: 兼容 "field" / "字段名"
	var field = condition_data.get("field", condition_data.get("字段名", ""))
	# compare: 兼容 "compare" / "comparison"
	var compare_str = condition_data.get("compare", condition_data.get("comparison", "≥"))
	match condition_id:
		"C01":  # 场上存在指定字段（排除本卡自身）
			for i in range(owner.max_field_size):
				var card = owner.field[i]
				if card == null or card == source_card:
					continue
				if _card_has_field(card, field):
					return true
			return false
		"C02":  # 场上怪兽数量（比较符+数值）
			return _compare_num(owner.get_field_count(), compare_str, param)
		"C04":  # 生命值比较（当前生命 hp，支持比较符，默认≥）
			var c04_compare = condition_data.get("compare", condition_data.get("comparison", "≥"))
			return _compare_num(owner.hp, c04_compare, param)
		"C06":  # 生命值差（当前生命差绝对值，支持比较符，默认≥）
			var diff = abs(owner.hp - opponent.hp)
			return _compare_num(diff, compare_str, param)
		"C07":  # 手牌数
			return _compare_num(owner.hand.size(), compare_str, param)
		"C08":  # 能量点（当前可用能量 energy，非上限；支持比较符，默认≥）
			return _compare_num(owner.energy, compare_str, param)
		"C09":  # 墓地卡牌数量
			return _compare_num(owner.grave.size(), compare_str, param)
		"C10":  # 墓地存在字段卡
			for grave_card in owner.grave:
				if _card_has_field(grave_card, field):
					return true
			return false
		"C11":  # 除外区卡牌数量（简化：暂用墓地数据替代）
			return _compare_num(owner.grave.size(), compare_str, param)
		"C12":  # 卡组数量
			return _compare_num(owner.deck.size(), compare_str, param)
		"C13":  # 手牌中特定卡（字段）
			for hand_card in owner.hand:
				if _card_has_field(hand_card, field):
					return true
			return false
		"C14":  # 本回合发动过N次（简化：检查卡牌是否已发动）
			# 这个需要BattleCard或BattleManager维护状态，暂返回true
			return true
		"C15":  # 己方场上只有X字段
			for i in range(owner.max_field_size):
				var card = owner.field[i]
				if card != null and not _card_has_field(card, field):
					return false
			return owner.get_field_count() > 0
		"C16":  # 控制权异动卡数量（比较符+数值）；判定场上有 current_owner != original_owner 的卡
			var hijack_count := 0
			for i in range(owner.max_field_size):
				var c = owner.field[i]
				if c != null and c.original_owner != null and c.current_owner != null and c.current_owner != c.original_owner:
					hijack_count += 1
			return _compare_num(hijack_count, compare_str, param)
	return false
## 获取动作的能量消耗（简化版，完整版需要制卡系统配合）
static func get_action_cost(action_id: String, value: int) -> float:
	match action_id:
		"A01": return float(value) * 0.8    # 效果伤害
		"A02": return float(value) * 0.6    # 恢复生命
		"A03": return 3.0                  # 破坏
		"A04": return 4.0                  # 除外
		"A05": return 2.0                  # 除外墓地卡
		"A06": return 3.0                  # 弹回手牌
		"A07": return 4.0                  # 弹回卡组
		"A08": return 2.5                  # 送入墓地(非破坏)
		"A09": return float(value) * 1.5   # 抽牌
		"A10": return 2.0                  # 检索字段卡
		"A11": return 3.0                  # 检索卡
		"A12": return 2.5                  # 墓地回收
		"A13": return 3.0                  # 除外回收
		"A14": return float(value) * 1.0   # 卡组堆墓
		"A15": return 3.0                  # 手牌特召
		"A16": return 3.5                  # 墓地特召
		"A17": return 4.0                  # 卡组特召
		"A18": return 4.5                  # 除外特召
		"A19": return 2.0                  # 召唤衍生物（简化）
		"A20": return abs(value) * 0.7     # 攻击力增减(永久)
		"A21": return abs(value) * 0.5     # 生命值增减(永久)
		"A22": return abs(value) * 1.0     # 攻命同时增减
		"A23": return abs(value) * 0.5     # 回合内攻命增减
		"A24": return abs(value) * 1.2     # 全场增减
		"A25": return 2.5                  # 交换攻防
		"A26": return 4.0                  # 暂时夺取控制权
		"A27": return 6.0                  # 永久夺取控制权
		"A28": return 2.0                  # 无法攻击
		"A29": return 1.5                  # 表示形式变更
		"A30": return 3.5                  # 无效效果发动并破坏
		"A31": return 4.0                  # 控制权变更·一回合
		"A32": return 6.0                  # 控制权变更·永久
		"A33": return 3.0                  # 禁用效果（一回合）
	return 1.0  # 默认
## 检查约束是否允许发动
static func check_constraint(constraint_id: String, owner, battle_state: int, current_phase: int, player_index: int) -> bool:
	match constraint_id:
		"CO08":  # 仅己方回合
			return player_index == 0
		"CO09":  # 仅对方回合
			return player_index == 1
		"CO10":  # 仅主要阶段
			return current_phase == 3  # Phase.MAIN
		"CO11":  # 仅战斗阶段
			return current_phase == 4  # Phase.BATTLE
		"CO13":  # 不可被连锁
			# 这个标记效果，不影响是否可发动
			return true
		"CO14":  # 不受对方效果影响
			# 这个标记效果，不影响是否可发动
			return true
		"CO15":  # 仅对克制属性生效
			# 需要属性系统，暂返回true
			return true
		"CO16":  # 仅或被克制属性生效
			# 需要属性系统，暂返回true
			return true
		_:  # 其他约束（CO01-07, CO12）不影响发动，只是能量调整或后处理
			return true
	return true
## 检查纹路是否可发动（完整检查）
func can_activate_circuit(parsed_effect: Dictionary, owner, opponent, source_card, battle_state: int, current_phase: int, player_index: int) -> Dictionary:
	var result = {"allowed": false, "reason": ""}
	var trigger = parsed_effect.get("trigger", "")
	var action = parsed_effect.get("action", "")
	var target = parsed_effect.get("target", "")
	var conditions = parsed_effect.get("conditions", [])
	var constraints = parsed_effect.get("constraints", [])
	# 检查动作和目标是否有效
	var action_info = _circuit_map.get(action, {})
	var target_info = _circuit_map.get(target, {})
	if action_info.is_empty() or target_info.is_empty():
		result.reason = "无效的动作或目标"
		return result
	# 检查条件
	for condition in conditions:
		var condition_id = condition.get("id", "")
		var condition_info = _circuit_map.get(condition_id, {})
		if condition_info.is_empty():
			continue
		if not check_condition(condition, owner, opponent, source_card):
			result.reason = "条件不满足: " + condition_info.get("name", "")
			return result
	# 检查约束
	for constraint_id in constraints:
		var constraint_info = _circuit_map.get(constraint_id, {})
		if constraint_info.is_empty():
			continue
		if not check_constraint(constraint_id, owner, battle_state, current_phase, player_index):
			result.reason = "约束不满足: " + constraint_info.get("name", "")
			return result
	result.allowed = true
	return result
## 获取目标修正系数
func get_target_modifier(target_id: String) -> float:
	var target_info = _circuit_map.get(target_id, {})
	return target_info.get("modifier", 1.0)
## 检查是否可连锁（速度等级）
func can_chain(trigger_id: String, current_chain_speed: int) -> bool:
	var trigger_info = _circuit_map.get(trigger_id, {})
	var speed = trigger_info.get("speed", 1)
	return speed >= current_chain_speed
## 检查互斥规则
static func check_mutex(parsed_effect: Dictionary) -> bool:
	var trigger = parsed_effect.get("trigger", "")
	var action = parsed_effect.get("action", "")
	var target = parsed_effect.get("target", "")
	var conditions = parsed_effect.get("conditions", [])
	var constraints = parsed_effect.get("constraints", [])
	# 互斥规则检查（简化版，实际使用时需要更多上下文）
	# 这里只是验证单个效果内部不冲突，效果间互斥需要在BattleManager中检查
	return true
## 获取约束参数值（CO03/CO04/CO12 等带X数值的约束）
## 优先读 effect["constraint_params"][cid]（新制卡保存），兼容旧卡读 effect["value"]，再兜底 fallback
static func get_constraint_param(effect: Dictionary, cid: String, fallback: int = 1) -> int:
	var params = effect.get("constraint_params", {})
	if params is Dictionary and params.has(cid):
		var p = params[cid]
		if p is Dictionary:
			# 数值可能存在 "数值" 或 "X" 或 "value" 键
			for key in ["数值", "X", "value"]:
				if p.has(key):
					var v = p[key]
					if v is String and v.is_valid_int():
						return int(v)
					if v is int or v is float:
						return int(v)
		elif p is int or p is float:
			return int(p)
	# 兼容旧卡：约束ID对应的数值存在效果value里（如 value=2 的A03+CO04）
	var v = effect.get("value", fallback)
	if v is String and v.is_valid_int():
		var iv = int(v)
		return iv if iv > 0 else fallback
	if v is int or v is float:
		var iv = int(v)
		return iv if iv > 0 else fallback
	return fallback
## 格式化效果描述（用于显示）
func format_effect_description(parsed_effect: Dictionary) -> String:
	"""生成自然语言效果描述，供飘窗显示"""
	var trigger = parsed_effect.get("trigger", "")
	var action = parsed_effect.get("action", "")
	var target = parsed_effect.get("target", "")
	var value = parsed_effect.get("value", 0)
	var field = parsed_effect.get("field", "")
	var conditions = parsed_effect.get("conditions", [])
	var constraints = parsed_effect.get("constraints", [])
	
	# 触发时机描述
	var trigger_text = ""
	match trigger:
		"TR01": trigger_text = "召唤时"
		"TR02": trigger_text = "特殊召唤时"
		"TR03": trigger_text = "从墓地特召时"
		"TR04": trigger_text = "被战斗破坏时"
		"TR06": trigger_text = "送墓时"
		"TR07": trigger_text = "被除外时"
		"TR08": trigger_text = "离场时"
		"TR09": trigger_text = "攻击时"
		"TR10": trigger_text = "被攻击时"
		"TR11": trigger_text = "战斗伤害时"
		"TR12": trigger_text = "己方回合开始"
		"TR13": trigger_text = "对方回合开始"
		"TR14": trigger_text = "己方回合结束"
		"TR15": trigger_text = "对方回合结束"
		"TR16": trigger_text = "对方发动效果时"
		"TR17": trigger_text = "对方召唤时"
		_: trigger_text = trigger
	
	# 动作描述
	var action_text = ""
	match action:
		"A01": # 效果伤害
			action_text = "造成" + str(value) + "点伤害"
		"A02": # 恢复生命
			action_text = "恢复" + str(value) + "点生命"
		"A03": # 破坏
			action_text = "破坏"
		"A04": # 除外
			action_text = "除外"
		"A05": action_text = "从墓地除外"
		"A06": action_text = "弹回手牌"
		"A07": action_text = "弹回卡组"
		"A08": action_text = "送入墓地"
		"A09": # 抽牌
			action_text = "从牌库抽" + str(value) + "张牌"
		"A10": action_text = "从卡组检索1张" + field + "字段卡"
		"A11": action_text = "从卡组检索1张卡"
		"A12": action_text = "从墓地回收1张卡"
		"A13": action_text = "从除外区回收1张卡"
		"A14": action_text = "从卡组送" + str(value) + "张牌入墓地"
		"A15": action_text = "从手牌特殊召唤"
		"A16": action_text = "从墓地特殊召唤"
		"A17": action_text = "从卡组特殊召唤"
		"A18": action_text = "从除外区特殊召唤"
		"A19": action_text = "召唤衍生物"
		"A20": # 攻击力增减
			if value >= 0:
				action_text = "攻击力+" + str(value)
			else:
				action_text = "攻击力" + str(value)
		"A21": # 生命值增减
			if value >= 0:
				action_text = "生命值+" + str(value)
			else:
				action_text = "生命值" + str(value)
		"A22": action_text = "攻命各+" + str(value)
		"A23": # 回合内攻命增减（支持负数=回合内减益）
			if value >= 0:
				action_text = "本回合攻命+" + str(value)
			else:
				action_text = "本回合攻命" + str(value)
		"A24": action_text = "全场攻命+" + str(value)
		"A25": action_text = "交换攻防"
		"A26": action_text = "暂时夺取控制权"
		"A27": action_text = "永久夺取控制权"
		"A28": action_text = "无法攻击"
		"A29": action_text = "变更表示形式"
		"A30": action_text = "无效效果并破坏"
		"A31": action_text = "夺取控制权（一回合）"
		"A32": action_text = "夺取控制权（永久）"
		"A33": action_text = "禁用效果（一回合）"
		_: action_text = action
	
	# 目标描述
	var target_text = ""
	match target:
		"T01": target_text = "自身"
		"T02": target_text = "敌方单体"
		"T03": target_text = "己方单体"
		"T04": target_text = "敌方全体"
		"T05": target_text = "己方全体"
		"T06": target_text = "全场"
		"T07": target_text = "敌方英雄"
		"T08": target_text = "己方英雄"
		"T09": target_text = "手牌"
		"T10": target_text = "墓地"
		"T11": target_text = "卡组"
		"T12": target_text = "除外区"
		"T13": target_text = "敌方攻击最高"
		"T14": target_text = "敌方攻击最低"
		"T15": target_text = "己方攻击最高"
		"T16": target_text = "己方攻击最低"
		_: target_text = target
	
	# 组合描述（条件/约束排最前面）
	var prefix = ""
	for cond in conditions:
		var cid = cond.get("id", "")
		var cp = cond.get("param", cond.get("value", cond.get("数值", 0)))
		var cf = cond.get("字段名", cond.get("field", ""))
		var cc = cond.get("comparison", cond.get("compare", "≥"))
		match cid:
			"C01": prefix += "【场上需有「" + cf + "」】"
			"C02": prefix += "【场上怪兽" + cc + str(cp) + "】"
			"C04": prefix += "【生命" + cc + str(cp) + "】"
			"C06": prefix += "【生命差≥" + str(cp) + "】"
			"C07": prefix += "【手牌" + cc + str(cp) + "】"
			"C08": prefix += "【能量≥" + str(cp) + "】"
			"C09": prefix += "【墓地" + cc + str(cp) + "】"
			"C10": prefix += "【墓地需有「" + cf + "」】"
			"C12": prefix += "【卡组" + cc + str(cp) + "】"
	for cns in constraints:
		match cns:
			"CO03": prefix += "【支付生命】"
			"CO04": prefix += "【舍弃手牌】"
			"CO01": prefix += "【一回合一次】"
			"CO02": prefix += "【一局一次】"
	# 如果目标是自身，省略目标描述
	var eff_name = parsed_effect.get("name", "")
	var name_prefix = "【" + eff_name + "】" if eff_name != "" else ""
	if target == "T01":
		return name_prefix + prefix + trigger_text + "，" + action_text
	else:
		return name_prefix + prefix + trigger_text + "，对" + target_text + action_text
## 简化效果触发时机（旧格式兼容）
enum TRIGGER_TYPE {
	NONE,
	ON_SUMMON,      # 召唤成功时 TR01
	ON_SPECIAL_SUMMON,  # 特殊召唤成功时 TR02
	ON_BATTLE_DESTROY,  # 被战斗破坏时 TR04
	ON_GRAVE,       # 送墓时 TR06
	ON_ATTACK,      # 攻击时 TR09
	ON_ATTACKED,    # 被攻击时 TR10
	ON_DAMAGE,      # 给予战斗伤害时 TR11
	ON_TURN_START,  # 回合开始时 TR12/TR13
	ON_TURN_END,    # 回合结束时 TR14/TR15
	ON_EFFECT,      # 对方发动效果时 TR16
	ON_SUMMON_ENEMY  # 对方召唤时 TR17
}
static func trigger_to_type(trigger_id: String) -> TRIGGER_TYPE:
	match trigger_id:
		"TR01": return TRIGGER_TYPE.ON_SUMMON
		"TR02": return TRIGGER_TYPE.ON_SPECIAL_SUMMON
		"TR03": return TRIGGER_TYPE.ON_SPECIAL_SUMMON
		"TR04": return TRIGGER_TYPE.ON_BATTLE_DESTROY
		"TR06": return TRIGGER_TYPE.ON_GRAVE
		"TR09": return TRIGGER_TYPE.ON_ATTACK
		"TR10": return TRIGGER_TYPE.ON_ATTACKED
		"TR11": return TRIGGER_TYPE.ON_DAMAGE
		"TR12": return TRIGGER_TYPE.ON_TURN_START
		"TR13": return TRIGGER_TYPE.ON_TURN_START
		"TR14": return TRIGGER_TYPE.ON_TURN_END
		"TR15": return TRIGGER_TYPE.ON_TURN_END
		"TR16": return TRIGGER_TYPE.ON_EFFECT
		"TR17": return TRIGGER_TYPE.ON_SUMMON_ENEMY
	return TRIGGER_TYPE.NONE
func _ready() -> void:
	_setup_ui_font()
	_load_theme()
	_load_battle_mode()
	_load_materials()
	_load_aux_data()
	_build_circuit_map()
	_build_circuit_row_template()
	_init_sfx()

## 全局 UI 字体：加载精简版中文字体（738KB），避免全量字体(25MB)拖慢界面
func _setup_ui_font() -> void:
	var font_path := "res://assets/share/font_pixel.ttf"
	if not FileAccess.file_exists(font_path):
		return
	var f := FontFile.new()
	if f.load_dynamic_font(font_path) == OK:
		ThemeDB.fallback_font = f
func switch_theme(mode: ThemeMode) -> void:
	current_mode = mode
	_save_theme()
	theme_changed.emit(mode)
func toggle_theme() -> void:
	current_mode = ThemeMode.DAY if current_mode == ThemeMode.NIGHT else ThemeMode.NIGHT
	_save_theme()
	theme_changed.emit(current_mode)
func _save_theme() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(CONFIG_SECTION, "mode", current_mode)
	cfg.save(CONFIG_PATH)
func _load_theme() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(CONFIG_PATH)
	if err == OK:
		var saved_mode: int = cfg.get_value(CONFIG_SECTION, "mode", ThemeMode.NIGHT)
		current_mode = saved_mode as ThemeMode
	else:
		current_mode = ThemeMode.NIGHT
func _save_battle_mode() -> void:
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)
	cfg.set_value(CONFIG_SECTION, "battle_mode", use_legacy_battle)
	cfg.save(CONFIG_PATH)
func _load_battle_mode() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(CONFIG_PATH)
	if err == OK:
		use_legacy_battle = cfg.get_value(CONFIG_SECTION, "battle_mode", false)
func make_topbar(top_ratio: float = 0.083) -> ColorRect:
	var h = ph(top_ratio)
	var r = ColorRect.new()
	r.name = "TopBar"
	r.color = current.topbar_bg
	r.anchor_left = 0.0
	r.anchor_top = 0.0
	r.anchor_right = 1.0
	r.anchor_bottom = 0.0
	r.offset_left = 0
	r.offset_top = 0
	r.offset_right = 0
	r.offset_bottom = h
	return r
func make_topbar_bottom_line(top_ratio: float = 0.083) -> ColorRect:
	var h = ph(top_ratio)
	var r = ColorRect.new()
	r.name = "TopBarLine"
	r.color = current.topbar_border
	r.anchor_left = 0.0
	r.anchor_top = 0.0
	r.anchor_right = 1.0
	r.anchor_bottom = 0.0
	r.offset_left = 0
	r.offset_top = h - 2
	r.offset_right = 0
	r.offset_bottom = h
	return r
var _bg_day_tex: Texture2D = null
var _bg_night_tex: Texture2D = null

func _get_bg_day() -> Texture2D:
	if _bg_day_tex == null:
		_bg_day_tex = load("res://assets/theme/bg_day.png")
	return _bg_day_tex

func _get_bg_night() -> Texture2D:
	if _bg_night_tex == null:
		_bg_night_tex = load("res://assets/theme/bg_night.png")
	return _bg_night_tex

func make_bg() -> TextureRect:
	var r = TextureRect.new()
	r.texture = _get_bg_night() if current_mode == ThemeMode.NIGHT else _get_bg_day()
	r.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.anchor_left = 0.0
	r.anchor_top = 0.0
	r.anchor_right = 1.0
	r.anchor_bottom = 1.0
	r.offset_left = 0
	r.offset_top = 0
	r.offset_right = 0
	r.offset_bottom = 0
	return r

## 主题切换时更新背景贴图（兼容 ColorRect 和 TextureRect）
## 数值 → 显示字符串。
## 存档 / 服务端 JSON 里的整数在 Godot 里会被解析成 float，直接 str() 会显示成
## 「x1.0」「💰 6.0」「金币×20.0」这种明显不是人写出来的数字。整数值统一按整数渲染。
func n2s(v) -> String:
	if typeof(v) == TYPE_FLOAT:
		var f: float = v
		if is_equal_approx(f, roundf(f)):
			return str(int(roundf(f)))
		return str(f)
	return str(v)


## 货币/数值这类「金色」标签统一加一圈深色描边。
## 白天主题下顶栏底色本身就是米色(topbar_bg)，纯金 #FFD700 压上去对比只有 ~1.1:1，
## 数字基本看不见；加描边后两种主题下都能读清，同时保留金色的视觉身份。
func make_gold_legible(lbl: Label) -> void:
	if lbl == null:
		return
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.62))
	lbl.add_theme_constant_override("outline_size", 6)


func apply_bg(node: Node) -> void:
	if node is TextureRect:
		(node as TextureRect).texture = _get_bg_night() if current_mode == ThemeMode.NIGHT else _get_bg_day()
	elif node is ColorRect:
		(node as ColorRect).color = current.bg
func make_title(text: String, font_size: int = 200, bottom_ratio: float = 0.135) -> Label:
	var lbl = Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", current.title)
	lbl.add_theme_color_override("font_shadow_color", current.title_shadow)
	lbl.add_theme_constant_override("shadow_offset_x", current.shadow_offset)
	lbl.add_theme_constant_override("shadow_offset_y", current.shadow_offset)
	lbl.anchor_left = 0.0
	lbl.anchor_top = 0.0
	lbl.anchor_right = 1.0
	lbl.anchor_bottom = 0.0
	lbl.offset_left = 0
	lbl.offset_top = 0
	lbl.offset_right = 0
	lbl.offset_bottom = ph(bottom_ratio)
	return lbl
func make_version(text: String, font_size: int = 50) -> Label:
	var lbl = Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", current.version)
	lbl.add_theme_color_override("font_shadow_color", current.version_shadow)
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)
	lbl.anchor_left = 0.0
	lbl.anchor_top = 1.0
	lbl.anchor_right = 1.0
	lbl.anchor_bottom = 1.0
	lbl.offset_left = 0
	lbl.offset_top = ph(-0.083)
	lbl.offset_right = 0
	lbl.offset_bottom = ph(-0.016)
	return lbl
func make_bordered_btn(text: String, border_color: Color, font_size: int = 55) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", font_size)
	var s = StyleBoxFlat.new()
	s.bg_color = current.btn_bg
	s.border_width_left = 3
	s.border_width_right = 3
	s.border_width_top = 3
	s.border_width_bottom = 3
	s.border_color = border_color
	s.corner_radius_top_left = 16
	s.corner_radius_top_right = 16
	s.corner_radius_bottom_left = 16
	s.corner_radius_bottom_right = 16
	s.content_margin_left = 24
	s.content_margin_right = 24

	var sh = s.duplicate()
	sh.bg_color = current.btn_bg_hover
	sh.border_color = border_color.lightened(0.3)

	var sp = s.duplicate()
	sp.bg_color = current.btn_bg_pressed
	sp.border_color = border_color.darkened(0.4)

	btn.add_theme_stylebox_override("normal", s)
	btn.add_theme_stylebox_override("hover", sh)
	btn.add_theme_stylebox_override("pressed", sp)
	btn.add_theme_stylebox_override("focus", s)
	btn.add_theme_color_override("font_color", current.btn_text)
	btn.add_theme_color_override("font_hover_color", current.btn_text_hover)
	btn.add_theme_color_override("font_pressed_color", current.btn_text_hover)
	return btn

func make_gear_btn() -> Button:
	var btn = Button.new()
	btn.text = "\u2699"
	btn.add_theme_font_size_override("font_size", 80)

	var s = StyleBoxFlat.new()
	s.bg_color = current.gear_bg
	s.border_width_left = 3
	s.border_width_right = 3
	s.border_width_top = 3
	s.border_width_bottom = 3
	s.border_color = Color("#888888")
	s.corner_radius_top_left = 16
	s.corner_radius_top_right = 16
	s.corner_radius_bottom_left = 16
	s.corner_radius_bottom_right = 16
	s.content_margin_left = 0
	s.content_margin_right = 0

	var sh = s.duplicate()
	sh.bg_color = current.gear_hover
	sh.border_color = Color("#aaaaaa")

	btn.add_theme_stylebox_override("normal", s)
	btn.add_theme_stylebox_override("hover", sh)
	btn.add_theme_stylebox_override("pressed", s)
	btn.add_theme_stylebox_override("focus", s)
	btn.add_theme_color_override("font_color", current.btn_text)
	btn.add_theme_color_override("font_hover_color", current.btn_text_hover)
	btn.add_theme_color_override("font_pressed_color", current.btn_text)

	btn.anchor_left = 1.0
	btn.anchor_top = 1.0
	btn.anchor_right = 1.0
	btn.anchor_bottom = 1.0
	btn.offset_left = pw(-0.13)
	btn.offset_top = ph(-0.073)
	btn.offset_right = pw(-0.028)
	btn.offset_bottom = ph(-0.016)
	return btn

func make_back_btn() -> Button:
	var btn = Button.new()
	btn.text = "← 返回"
	btn.add_theme_font_size_override("font_size", 50)

	var s = StyleBoxFlat.new()
	s.bg_color = current.btn_bg
	s.border_width_left = 2
	s.border_width_right = 2
	s.border_width_top = 2
	s.border_width_bottom = 2
	s.border_color = Color("#888888")
	s.corner_radius_top_left = 10
	s.corner_radius_top_right = 10
	s.corner_radius_bottom_left = 10
	s.corner_radius_bottom_right = 10
	s.content_margin_left = 20
	s.content_margin_right = 20

	var sh = s.duplicate()
	sh.bg_color = current.btn_bg_hover

	btn.add_theme_stylebox_override("normal", s)
	btn.add_theme_stylebox_override("hover", sh)
	btn.add_theme_stylebox_override("pressed", s)
	btn.add_theme_stylebox_override("focus", s)
	btn.add_theme_color_override("font_color", current.btn_text)
	btn.add_theme_color_override("font_hover_color", current.btn_text_hover)
	btn.add_theme_color_override("font_pressed_color", current.btn_text)

	btn.anchor_left = 0.0
	btn.anchor_top = 0.0
	btn.anchor_right = 0.0
	btn.anchor_bottom = 0.0
	btn.offset_left = pw(0.019)
	btn.offset_top = ph(0.01)
	btn.offset_right = pw(0.167)
	btn.offset_bottom = ph(0.042)
	return btn

# ============================================================
#  纹路图鉴行模板（预构建，避免每次打开重建720个节点）
# ============================================================
var circuit_row_pool: Array[Panel] = []

func _build_circuit_row_template() -> void:
	"""预构建90个纹路图鉴行，放入池子，并临时挂到树上触发 _ready()"""
	# 创建临时容器，挂到Global上（Global在场景树中），触发子节点的 _ready()
	var temp_container = Node.new()
	temp_container.name = "TempRowContainer"
	add_child(temp_container)
	
	for i in 100:
		# 行容器 Panel
		var row_panel = Panel.new()
		row_panel.name = "RowPanel"
		var panel_style = StyleBoxFlat.new()
		panel_style.bg_color = Color(0.15, 0.15, 0.22)
		row_panel.add_theme_stylebox_override("panel", panel_style)
		row_panel.custom_minimum_size = Vector2(0, ph(0.085))
		row_panel.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
		row_panel.mouse_filter = Control.MOUSE_FILTER_PASS
		
		# 底部分隔线
		var row_line = ColorRect.new()
		row_line.name = "RowLine"
		row_line.color = Color(1.0, 1.0, 1.0, 0.20)
		row_line.anchor_left = 0.0; row_line.anchor_top = 1.0
		row_line.anchor_right = 1.0; row_line.anchor_bottom = 1.0
		row_line.offset_left = 0; row_line.offset_top = -2
		row_line.offset_right = 0; row_line.offset_bottom = 0
		row_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row_panel.add_child(row_line)
		
		# 水平容器
		var hbox = HBoxContainer.new()
		hbox.name = "RowHBox"
		hbox.anchor_left = 0.0; hbox.anchor_top = 0.0
		hbox.anchor_right = 1.0; hbox.anchor_bottom = 1.0
		hbox.offset_left = pw(0.02); hbox.offset_top = 0
		hbox.offset_right = pw(-0.02); hbox.offset_bottom = 0
		hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row_panel.add_child(hbox)
		
		# ID 标签
		var id_label = Label.new()
		id_label.name = "IDLabel"
		id_label.add_theme_font_size_override("font_size", 40)
		id_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.8))
		id_label.custom_minimum_size = Vector2(pw(0.12), 0)
		id_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hbox.add_child(id_label)
		
		# 名称标签（超长名称省略，避免把右侧状态列挤出屏幕）
		var name_label = Label.new()
		name_label.name = "NameLabel"
		name_label.add_theme_font_size_override("font_size", 50)
		name_label.custom_minimum_size = Vector2(pw(0.30), 0)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
		name_label.clip_text = true
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		hbox.add_child(name_label)
		
		# 类别标签
		var cat_label = Label.new()
		cat_label.name = "CatLabel"
		cat_label.add_theme_font_size_override("font_size", 45)
		cat_label.add_theme_color_override("font_color", Color(0.8, 0.7, 0.5))
		cat_label.custom_minimum_size = Vector2(pw(0.18), 0)
		cat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hbox.add_child(cat_label)
		
		# 状态标签（解锁条件可能很长，允许换行，避免整列被挤出屏幕）
		var status_label = Label.new()
		status_label.name = "StatusLabel"
		status_label.add_theme_font_size_override("font_size", 38)
		status_label.custom_minimum_size = Vector2(pw(0.26), 0)
		status_label.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
		status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hbox.add_child(status_label)
		
		# 临时挂到树上触发 _ready()，再摘下来
		temp_container.add_child(row_panel)
		temp_container.remove_child(row_panel)
		
		# 存入池子
		circuit_row_pool.append(row_panel)
	
	# 清理临时容器
	remove_child(temp_container)
	temp_container.queue_free()
	
	print("[Global] 纹路图鉴行池预构建完成：共 ", circuit_row_pool.size(), " 行")

# ============================================================
#  Supabase 网络接入（卡牌交换系统）

## 获取玩家设备ID（作为玩家唯一标识）
## 使用本地缓存文件，确保每次启动ID不变
func get_player_id() -> String:
	const PLAYER_ID_FILE := "user://player_id.txt"
	
	# 先读本地缓存
	var file = FileAccess.open(PLAYER_ID_FILE, FileAccess.READ)
	if file:
		var id = file.get_as_text().strip_edges()
		file.close()
		if id != "":
			return id
	
	# 没有缓存：用设备ID，回退为随机生成的固定ID
	var device_id = OS.get_unique_id()
	var id = device_id if device_id != "" else _generate_player_uuid()
	
	# 存起来，以后每次都用这个
	file = FileAccess.open(PLAYER_ID_FILE, FileAccess.WRITE)
	if file:
		file.store_string(id)
		file.close()
		print("[Global] 玩家ID已缓存: ", id)
	else:
		print("[Global] 警告：无法写入玩家ID缓存文件")
	
	return id

## 生成UUID备用（当设备ID为空时）
func _generate_player_uuid() -> String:
	var chars = "abcdefghijklmnopqrstuvwxyz0123456789"
	var id = "player_"
	for i in range(16):
		id += chars[randi() % chars.length()]
	return id

## 通用HTTP请求函数（已注释：PvP/卡牌交易功能已移除过审，无调用方）
# func supabase_request(method: int, path: String, body: String = "") -> Dictionary:
# 	print("[supabase] 开始请求: ", method, " ", path)
# 	var http = HTTPRequest.new()
# 	add_child(http)
# 	
# 	var headers = [
# 		"apikey: " + SUPABASE_ANON_KEY,
# 		"Content-Type: application/json"
# 	]
# 	# POST/PATCH 时要求返回完整数据（获取插入/更新后的行）
# 	if method == HTTPClient.METHOD_POST or method == HTTPClient.METHOD_PATCH:
# 		headers.append("Prefer: return=representation")
# 	
# 	var url = SUPABASE_URL + path
# 	print("[supabase] 请求URL: ", url)
# 	var err = http.request(url, headers, method, body)
# 	print("[supabase] http.request 返回: ", err)
# 	if err != OK:
# 		remove_child(http)
# 		http.queue_free()
# 		return {"error": "HTTP请求失败: " + str(err)}
# 	
# 	print("[supabase] 等待 request_completed 信号...")
# 	var response = await http.request_completed
# 	print("[supabase] request_completed 收到！")
# 	remove_child(http)
# 	http.queue_free()
# 	
# 	var result_code = response[1]
# 	var response_body = response[3].get_string_from_utf8()
# 	print("[supabase] 响应码: ", result_code, " 响应体长度: ", response_body.length())
# 	
# 	if result_code != 200 and result_code != 201 and result_code != 204:
# 		return {"error": "HTTP " + str(result_code), "body": response_body}
# 	
# 	var json = JSON.new()
# 	if result_code == 204 or response_body == "":
# 		return {"data": [], "code": result_code}
# 	json.parse(response_body)
# 	return {"data": json.get_data(), "code": result_code}

## ===== 卡牌同步（已注释：卡牌交易功能已移除过审） =====
## 上传本地卡牌到云端
# func upload_card(card_data: Dictionary) -> Dictionary:
# 	var body = JSON.stringify({
# 		"player_id": get_player_id(),
# 		"card_data": card_data,
# 		"is_tradable": true
# 	})
# 	return await supabase_request(HTTPClient.METHOD_POST, "/rest/v1/cards", body)

## 获取我的卡牌列表
# func get_my_cards() -> Dictionary:
# 	var path = "/rest/v1/cards?player_id=eq." + get_player_id() + "&select=*"
# 	return await supabase_request(HTTPClient.METHOD_GET, path)

## ===== 交换发布（A发布） =====
## 上架：上传卡牌到服务器 → 删除本地 → 创建发布
#func publish_trade_offer(offer_card_id: String, want_description: String, card_data: Dictionary) -> Dictionary:
#	# 1. 上传卡牌到服务器cards表
#	var upload_result = await upload_card(card_data)
#	if upload_result.has("error"):
#		return {"error": "上传卡牌失败: " + str(upload_result.error)}
#	
#	# 获取服务器返回的卡牌ID
#	var server_card_id = ""
#	var resp_data = upload_result.get("data", [])
#	if resp_data is Array and resp_data.size() > 0:
#		server_card_id = resp_data[0].get("id", "")
#	elif resp_data is Dictionary:
#		server_card_id = resp_data.get("id", "")
#	if server_card_id == "":
#		return {"error": "无法获取服务器卡牌ID"}
#	
#	# 2. 删除本地卡牌
#	CardManager.remove_card_by_id(offer_card_id)
#	
#	# 3. 创建发布
#	var exchange_code = _generate_exchange_code()
#	var body = JSON.stringify({
#		"creator_id": get_player_id(),
#		"offer_card_id": server_card_id,
#		"want_description": want_description,
#		"exchange_code": exchange_code,
#		"card_data": card_data,
#		"status": "open"
#	})
#	return await supabase_request(HTTPClient.METHOD_POST, "/rest/v1/trade_offers", body)
#
### 生成8位交换码
#func _generate_exchange_code() -> String:
#	var chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
#	var code = ""
#	for i in range(8):
#		code += chars[randi() % chars.length()]
#		if i == 3:
#			code += "-"
#	return code
#
### 获取我的上架
#func get_my_offers() -> Dictionary:
#	var path = "/rest/v1/trade_offers?creator_id=eq." + get_player_id() + "&select=*"
#	return await supabase_request(HTTPClient.METHOD_GET, path)
#
### 获取所有开放的上架
#func get_open_offers() -> Dictionary:
#	return await supabase_request(HTTPClient.METHOD_GET, "/rest/v1/trade_offers?status=eq.open&select=*")
#
### 通过交换码查找发布
#func get_offer_by_code(code: String) -> Dictionary:
#	var path = "/rest/v1/trade_offers?exchange_code=eq." + code + "&select=*"
#	return await supabase_request(HTTPClient.METHOD_GET, path)
#
### ===== 提交卡牌（B提交） =====
### 提交提案：上传卡牌到服务器 → 删除本地 → 创建提案
#func submit_card_to_offer(offer_id: String, my_card_id: String, card_data: Dictionary) -> Dictionary:
#	# 0. 先检查offer状态是否还是open，防止对已关闭的提交提案
#	var check_offer = await supabase_request(HTTPClient.METHOD_GET, "/rest/v1/trade_offers?id=eq." + offer_id + "&select=status")
#	if not check_offer.has("error"):
#		var offer_data = check_offer.get("data", [])
#		if offer_data is Array and offer_data.size() > 0:
#			var offer_status = offer_data[0].get("status", "")
#			if offer_status != "open":
#				return {"error": "该上架已关闭，无法提交提案"}
#	
#	# 1. 上传卡牌到服务器cards表
#	var upload_result = await upload_card(card_data)
#	if upload_result.has("error"):
#		return {"error": "上传卡牌失败: " + str(upload_result.error)}
#	
#	# 获取服务器返回的卡牌ID
#	var server_card_id = ""
#	var resp_data = upload_result.get("data", [])
#	if resp_data is Array and resp_data.size() > 0:
#		server_card_id = resp_data[0].get("id", "")
#	elif resp_data is Dictionary:
#		server_card_id = resp_data.get("id", "")
#	if server_card_id == "":
#		return {"error": "无法获取服务器卡牌ID"}
#	
#	# 1.5 再次检查offer状态（上传卡牌后可能已被关闭）
#	var recheck = await supabase_request(HTTPClient.METHOD_GET, "/rest/v1/trade_offers?id=eq." + offer_id + "&select=status")
#	if not recheck.has("error"):
#		var re_data = recheck.get("data", [])
#		if re_data is Array and re_data.size() > 0:
#			var re_status = re_data[0].get("status", "")
#			if re_status != "open":
#				# 上传的卡牌要删掉，不然卡在服务器上
#				await delete_server_card(server_card_id)
#				return {"error": "该上架已被关闭，卡牌已退还"}
#	
#	# 2. 删除本地卡牌
#	CardManager.remove_card_by_id(my_card_id)
#	
#	# 3. 创建提案
#	var body = JSON.stringify({
#		"offer_id": offer_id,
#		"proposer_id": get_player_id(),
#		"offered_card_id": server_card_id,
#		"card_data": card_data,
#		"status": "pending"
#	})
#	return await supabase_request(HTTPClient.METHOD_POST, "/rest/v1/trade_proposals", body)
#
### 从服务器下载卡牌（根据server_card_id查cards表，获取card_data）
#func download_card_from_server(server_card_id: String) -> Dictionary:
#	var path = "/rest/v1/cards?id=eq." + server_card_id + "&select=*"
#	return await supabase_request(HTTPClient.METHOD_GET, path)
#
### 从服务器删除卡牌
#func delete_server_card(server_card_id: String) -> Dictionary:
#	return await supabase_request(HTTPClient.METHOD_DELETE, "/rest/v1/cards?id=eq." + server_card_id)
#
### 获取我收到的提案（A查看收到的提案）
### 先拿自己的发布列表，再查这些发布对应的提案
#func get_incoming_proposals() -> Dictionary:
#	var offers_result = await get_my_offers()
#	if offers_result.has("error") or not offers_result.has("data"):
#		return {"data": []}
#	var offers = offers_result["data"]
#	if offers.size() == 0:
#		return {"data": []}
#	var ids = []
#	for offer in offers:
#		ids.append(offer.get("id", ""))
#	var path = "/rest/v1/trade_proposals?select=*&offer_id=in.(" + ",".join(ids) + ")"
#	return await supabase_request(HTTPClient.METHOD_GET, path)
#
### 获取我提交的提案（B查看自己提交的提案）
#func get_my_proposals() -> Dictionary:
#	var path = "/rest/v1/trade_proposals?proposer_id=eq." + get_player_id() + "&select=*"
#	return await supabase_request(HTTPClient.METHOD_GET, path)
#
### ===== 同意/拒绝交换 =====
### A同意交换：服务器换卡 → 双方下载新卡
### A同意交换：服务器换卡 → A下载对方卡牌
### 返回: {"success": true, "my_card_name": "...", "their_card_name": "..."}
### 或 {"error": "失败原因"}
#func accept_trade(proposal_id: String, offer_id: String, my_server_card_id: String, their_server_card_id: String, their_player_id: String) -> Dictionary:
#	# 0. 先检查offer状态是否还是open，防止重复同意
#	var check_offer = await supabase_request(HTTPClient.METHOD_GET, "/rest/v1/trade_offers?id=eq." + offer_id + "&select=status")
#	if not check_offer.has("error"):
#		var offer_data = check_offer.get("data", [])
#		if offer_data is Array and offer_data.size() > 0:
#			var offer_status = offer_data[0].get("status", "")
#			if offer_status != "open":
#				return {"error": "该上架已关闭，无法重复交换"}
#	
#	# 0.1 检查提案状态是否还是pending
#	var check_prop = await supabase_request(HTTPClient.METHOD_GET, "/rest/v1/trade_proposals?id=eq." + proposal_id + "&select=status")
#	if not check_prop.has("error"):
#		var prop_data = check_prop.get("data", [])
#		if prop_data is Array and prop_data.size() > 0:
#			var prop_status = prop_data[0].get("status", "")
#			if prop_status != "pending":
#				return {"error": "该提案已处理，无法重复操作"}
#	# 1. 更新提案状态为accepted（条件更新：只有status=pending才能更新成功）
#	var body1 = JSON.stringify({"status": "accepted", "responded_at": "now()"})
#	var r1 = await supabase_request(HTTPClient.METHOD_PATCH, "/rest/v1/trade_proposals?id=eq." + proposal_id + "&status=eq.pending", body1)
#	if r1.has("error"):
#		return {"error": "更新提案状态失败: " + str(r1.error)}
#	# 检查是否真的更新了（如果返回0行，说明状态已不是pending）
#	var r1_data = r1.get("data", [])
#	if r1_data is Array and r1_data.size() == 0:
#		return {"error": "该提案已被其他请求处理"}
#	
#	# 2. 更新发布状态为closed（条件更新：只有status=open才能更新成功）
#	var body2 = JSON.stringify({"status": "closed"})
#	var r2 = await supabase_request(HTTPClient.METHOD_PATCH, "/rest/v1/trade_offers?id=eq." + offer_id + "&status=eq.open", body2)
#	if r2.has("error"):
#		return {"error": "关闭发布失败: " + str(r2.error)}
#	
#	# 2.5 自动拒绝该发布的其他 pending 提案（防止同一张卡被多次交换）
#	# 只把提案标记为 rejected，保留提案记录和卡牌在服务器上，
#	# 让提案方(B)在"提交的提案"里看到被拒绝的提案，点"取回卡牌"自己下载
#	var others_result = await supabase_request(HTTPClient.METHOD_GET, "/rest/v1/trade_proposals?offer_id=eq." + offer_id + "&status=eq.pending&id=neq." + proposal_id + "&select=id,offered_card_id")
#	if not others_result.has("error") and others_result.has("data"):
#		var others = others_result["data"]
#		for other in others:
#			var oth_id = other.get("id", "")
#			if oth_id != "":
#				var reject_body = JSON.stringify({"status": "rejected", "responded_at": "now()"})
#				await supabase_request(HTTPClient.METHOD_PATCH, "/rest/v1/trade_proposals?id=eq." + oth_id + "&status=eq.pending", reject_body)
#				print("[Global] ↩️ 自动拒绝了其他提案: ", oth_id)
#	
#	# 3. 交换卡牌所有权：我的卡给对方
#	var body3 = JSON.stringify({"player_id": their_player_id})
#	var r3 = await supabase_request(HTTPClient.METHOD_PATCH, "/rest/v1/cards?id=eq." + my_server_card_id, body3)
#	if r3.has("error"):
#		return {"error": "转移我的卡牌失败: " + str(r3.error)}
#	
#	# 4. 对方的卡给我
#	var body4 = JSON.stringify({"player_id": get_player_id()})
#	var r4 = await supabase_request(HTTPClient.METHOD_PATCH, "/rest/v1/cards?id=eq." + their_server_card_id, body4)
#	if r4.has("error"):
#		return {"error": "接收对方卡牌失败: " + str(r4.error)}
#	
#	# 5. A下载对方卡牌到本地
#	var download_result = await download_card_from_server(their_server_card_id)
#	if download_result.has("error"):
#		return {"error": "下载对方卡牌失败: " + str(download_result.error)}
#	
#	var resp_data = download_result.get("data", [])
#	if resp_data is Array and resp_data.size() > 0:
#		var their_card_data = resp_data[0].get("card_data", {})
#		if not their_card_data.is_empty():
#			CardManager.add_card(their_card_data)
#			var their_name = their_card_data.get("name", "未知")
#			# 删除服务器上的卡牌（已下载到本地，不留副本）
#			await delete_server_card(their_server_card_id)
#			print("[Global] ✅ 交换成功，下载并删除服务器卡牌: ", their_name)
#			# 也查一下我给了对方什么卡（用于展示）
#			var my_card_info = "未知"
#			var my_card_req = await download_card_from_server(my_server_card_id)
#			if not my_card_req.has("error"):
#				var my_data = my_card_req.get("data", [])
#				if my_data is Array and my_data.size() > 0:
#					my_card_info = my_data[0].get("card_data", {}).get("name", "未知")
#			return {"success": true, "my_card_name": my_card_info, "their_card_name": their_name}
#	
#	return {"error": "下载卡牌数据为空"}
#
### B领取交换到的卡牌（B刷新提案页时调用）
### 传入被接受的提案，自动下载对方的卡牌到本地
#func claim_trade_card(proposal: Dictionary) -> Dictionary:
#	var offer_id = proposal.get("offer_id", "")
#	var proposal_id = proposal.get("id", "")
#	var status = proposal.get("status", "")
#	if status != "accepted":
#		return {"error": "提案状态不是accepted"}
#	
#	# 0. 检查提案是否还在服务器上（防止重复领取）
#	var check_prop = await supabase_request(HTTPClient.METHOD_GET, "/rest/v1/trade_proposals?id=eq." + proposal_id + "&select=status")
#	if not check_prop.has("error"):
#		var prop_data = check_prop.get("data", [])
#		if prop_data is Array and prop_data.size() == 0:
#			return {"error": "该提案已不存在，可能已被领取"}
#	
#	# 查发布信息，获取对方的卡牌服务器ID
#	var offer_result = await supabase_request(HTTPClient.METHOD_GET, "/rest/v1/trade_offers?id=eq." + offer_id + "&select=*")
#	if offer_result.has("error"):
#		return {"error": "查询发布信息失败: " + str(offer_result.error)}
#	
#	var offer_data = offer_result.get("data", [])
#	if offer_data is not Array or offer_data.size() == 0:
#		return {"error": "找不到发布信息"}
#	
#	var my_new_card_id = offer_data[0].get("offer_card_id", "")
#	if my_new_card_id == "":
#		return {"error": "发布信息中卡牌ID为空"}
#	
#	# 下载这张卡牌到本地
#	var download_result = await download_card_from_server(my_new_card_id)
#	if download_result.has("error"):
#		return {"error": "下载卡牌失败: " + str(download_result.error)}
#	
#	var resp_data = download_result.get("data", [])
#	if resp_data is Array and resp_data.size() > 0:
#		var card_data = resp_data[0].get("card_data", {})
#		if not card_data.is_empty():
#			CardManager.add_card(card_data)
#			# 删除服务器上的卡牌（已下载到本地，不留副本）
#			await delete_server_card(my_new_card_id)
#			# 交易完成，删除服务器上的提案和发布记录
#			await supabase_request(HTTPClient.METHOD_DELETE, "/rest/v1/trade_proposals?id=eq." + proposal_id)
#			await supabase_request(HTTPClient.METHOD_DELETE, "/rest/v1/trade_offers?id=eq." + offer_id)
#			var card_name = card_data.get("name", "未知")
#			print("[Global] 🎉 B领取交换卡牌，已删除服务器副本及交易记录: ", card_name)
#			return {"success": true, "card_name": card_name}
#	
#	return {"error": "卡牌数据为空"}
#
### A拒绝提案：拒绝后返回卡牌给提案方
#func reject_proposal(proposal_id: String, offered_server_card_id: String) -> Dictionary:
#	# 0. 检查提案是否还在服务器上
#	var check_prop = await supabase_request(HTTPClient.METHOD_GET, "/rest/v1/trade_proposals?id=eq." + proposal_id + "&select=status")
#	if not check_prop.has("error"):
#		var prop_data = check_prop.get("data", [])
#		if prop_data is Array and prop_data.size() == 0:
#			return {"error": "该提案已不存在，无法重复操作"}
#	
#	# 1. 下载提案方的卡牌（从服务器取回）
#	var download_result = await download_card_from_server(offered_server_card_id)
#	if not download_result.has("error"):
#		var resp_data = download_result.get("data", [])
#		if resp_data is Array and resp_data.size() > 0:
#			var card_data = resp_data[0].get("card_data", {})
#			if not card_data.is_empty():
#				# 把卡牌还给提案方（加到本地CardManager）
#				CardManager.add_card(card_data)
#				print("[Global] ↩️ 拒绝提案，返回卡牌: ", card_data.get("name", "未知"))
#	
#	# 2. 删除服务器上的卡牌
#	await delete_server_card(offered_server_card_id)
#	
#	# 3. 删除提案记录
#	return await supabase_request(HTTPClient.METHOD_DELETE, "/rest/v1/trade_proposals?id=eq." + proposal_id)
### B取消自己的提案：取消后取回自己的卡牌
#func cancel_proposal(proposal_id: String, offered_server_card_id: String) -> Dictionary:
#	# 0. 检查提案是否还在服务器上
#	var check_prop = await supabase_request(HTTPClient.METHOD_GET, "/rest/v1/trade_proposals?id=eq." + proposal_id + "&select=status")
#	if not check_prop.has("error"):
#		var prop_data = check_prop.get("data", [])
#		if prop_data is Array and prop_data.size() == 0:
#			return {"error": "该提案已不存在，无法重复操作"}
#	
#	# 1. 下载自己的卡牌
#	var download_result = await download_card_from_server(offered_server_card_id)
#	if not download_result.has("error"):
#		var resp_data = download_result.get("data", [])
#		if resp_data is Array and resp_data.size() > 0:
#			var card_data = resp_data[0].get("card_data", {})
#			if not card_data.is_empty():
#				CardManager.add_card(card_data)
#				print("[Global] ↩️ 取消提案，取回卡牌: ", card_data.get("name", "未知"))
#	
#	# 2. 删除服务器上的卡牌
#	await delete_server_card(offered_server_card_id)
#	
#	# 3. 删除提案记录
#	return await supabase_request(HTTPClient.METHOD_DELETE, "/rest/v1/trade_proposals?id=eq." + proposal_id)
#
#
### 撤销上架：拒绝所有pending提案 → 下载卡牌回本地 → 删除服务器卡牌 → 删除上架记录
#func cancel_offer(offer_id: String, offer_card_id: String) -> Dictionary:
#	# 0. 检查上架是否还在服务器上
#	var check_offer = await supabase_request(HTTPClient.METHOD_GET, "/rest/v1/trade_offers?id=eq." + offer_id + "&select=status")
#	if not check_offer.has("error"):
#		var offer_data = check_offer.get("data", [])
#		if offer_data is Array and offer_data.size() == 0:
#			return {"error": "该上架已不存在"}
#	
#	# 1. 拒绝所有pending提案
#	var props_result = await supabase_request(HTTPClient.METHOD_GET, "/rest/v1/trade_proposals?offer_id=eq." + offer_id + "&status=eq.pending&select=id,offered_card_id")
#	if not props_result.has("error") and props_result.has("data"):
#		var props = props_result["data"]
#		for prop in props:
#			var prop_id = prop.get("id", "")
#			var offered_card_id = prop.get("offered_card_id", "")
#			if prop_id != "" and offered_card_id != "":
#				await reject_proposal(prop_id, offered_card_id)
#				print("[Global] ↩️ 撤销上架时拒绝提案: ", prop_id)
#	
#	# 2. 下载卡牌回本地
#	var download_result = await download_card_from_server(offer_card_id)
#	if not download_result.has("error"):
#		var resp_data = download_result.get("data", [])
#		if resp_data is Array and resp_data.size() > 0:
#			var card_data = resp_data[0].get("card_data", {})
#			if not card_data.is_empty():
#				CardManager.add_card(card_data)
#				print("[Global] ↩️ 撤销上架，取回卡牌: ", card_data.get("name", "未知"))
#	
#	# 3. 删除服务器上的卡牌
#	await delete_server_card(offer_card_id)
#	
#	# 4. 删除上架记录
#	return await supabase_request(HTTPClient.METHOD_DELETE, "/rest/v1/trade_offers?id=eq." + offer_id)
#
### 清理交易数据：重置游戏时调用，删除当前玩家在服务器上的所有交易记录
#func cleanup_trade_data() -> void:
#	var pid = get_player_id()
#	print("[Global] 🧹 清理交易数据，玩家ID: ", pid)
#	
#	# 1. 处理我收到的pending提案：按拒绝处理，把卡还给提案方
#	var offers_result = await get_my_offers()
#	if not offers_result.has("error") and offers_result.has("data"):
#		var offers = offers_result["data"]
#		for offer in offers:
#			var offer_id = offer.get("id", "")
#			if offer_id == "": continue
#			# 查这个上架的所有pending提案
#			var props_result = await supabase_request(HTTPClient.METHOD_GET, "/rest/v1/trade_proposals?offer_id=eq." + offer_id + "&status=eq.pending&select=id,offered_card_id")
#			if props_result.has("error") or not props_result.has("data"): continue
#			var props = props_result["data"]
#			for prop in props:
#				var prop_id = prop.get("id", "")
#				var offered_card_id = prop.get("offered_card_id", "")
#				if prop_id != "" and offered_card_id != "":
#					await reject_proposal(prop_id, offered_card_id)
#					print("[Global] ↩️ 已拒绝提案: ", prop_id)
#			# 删除上架关联的卡牌（我的卡）
#			var offer_card_id = offer.get("offer_card_id", "")
#			if offer_card_id != "":
#				await delete_server_card(offer_card_id)
#		print("[Global] ✅ 已拒绝所有收到的提案，卡牌已归还提案方")
#	
#	# 2. 删除我提交的所有pending提案（我自己的卡，重置不要了，直接删）
#	await supabase_request(HTTPClient.METHOD_DELETE, "/rest/v1/trade_proposals?proposer_id=eq." + pid)
#	print("[Global] ✅ 已清理提交的提案")
#	
#	# 3. 删除我的上架（已处理完关联数据）
#	await supabase_request(HTTPClient.METHOD_DELETE, "/rest/v1/trade_offers?creator_id=eq." + pid)
#	print("[Global] ✅ 已清理上架记录")
#	
#	# 4. 删除我的服务器卡牌
#	await supabase_request(HTTPClient.METHOD_DELETE, "/rest/v1/cards?player_id=eq." + pid)
#	print("[Global] ✅ 已清理服务器卡牌")
#	print("[Global] 🎉 交易数据清理完成")
#
### ============================================================
###  卡组区（decks）—— 虚拟匹配用，全局共享
###  玩家上传多套卡组，匹配时随机拉取一套作为对手卡组
### ============================================================
### 上传一套卡组到服务器（供虚拟匹配使用）
#func upload_deck(deck_data: Dictionary) -> Dictionary:
#	var body = JSON.stringify({
#		"player_id": get_player_id(),
#		"deck_data": deck_data
#	})
#	return await supabase_request(HTTPClient.METHOD_POST, "/rest/v1/decks", body)
### 通用本地JSON读取（返回 {data: [...]}，与服务器返回结构一致）
func _load_local_json(path: String) -> Dictionary:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		print("[Global] 警告：无法读取本地数据文件 ", path)
		return {"error": "本地数据文件缺失: " + path}
	var json_str = file.get_as_text()
	file.close()
	var json := JSON.new()
	var err := json.parse(json_str)
	if err != OK:
		print("[Global] JSON解析错误 ", path, " : ", json.get_error_message())
		return {"error": "JSON解析失败: " + path}
	var data = json.get_data()
	if data is Array:
		return {"data": data}
	return {"data": []}
## 获取所有玩家上传的卡组（虚拟匹配池）
func get_all_decks() -> Dictionary:
	# 本地读取AI卡组池（原为Supabase联网拉取，已本地化以过隐私合规）
	return _load_local_json("res://Data/local_ai_decks.json")
## 随机拉取一套卡组（虚拟匹配：从所有上传的卡组中随机取一套）
func get_random_deck() -> Dictionary:
	var result = await get_all_decks()
	if result.has("error") or not result.has("data") or result["data"].size() == 0:
		return {"error": "卡组池为空"}
	var decks = result["data"]
	var rnd = randi() % decks.size()
	var pick = decks[rnd]
	return {"data": pick.get("deck_data", {})}
## 删除一套卡组（按对方玩家+卡组内容标识）
#func delete_server_deck(server_deck_id: String) -> Dictionary:
#	var path = "/rest/v1/decks?id=eq." + server_deck_id
#	return await supabase_request(HTTPClient.METHOD_DELETE, path)
#
### ============================================================
###  卡包区（card_packs）—— 预制卡包，全局共享
###  玩家点击广告开包后，从对应卡包随机拉取3张卡牌
### ============================================================
### 上传/保存一个预制卡包到服务器
#func upload_card_pack(pack_data: Dictionary) -> Dictionary:
#	var body = JSON.stringify({
#		"pack_data": pack_data
#	})
#	return await supabase_request(HTTPClient.METHOD_POST, "/rest/v1/card_packs", body)
### 获取所有预制卡包
func get_all_card_packs() -> Dictionary:
	# 本地读取卡包数据（原为Supabase联网拉取，已本地化以过隐私合规）
	return _load_local_json("res://Data/local_card_packs.json")
## 获取指定卡包（按 pack_id）
func get_server_card_pack(pack_id: String) -> Dictionary:
	# 本地读取指定卡包（原为Supabase联网查询）
	var result = _load_local_json("res://Data/local_card_packs.json")
	if result.has("error"):
		return result
	var packs = result.get("data", [])
	var found = []
	for p in packs:
		if p.get("pack_id") == pack_id:
			found.append(p)
	return {"data": found}
## 开包：从指定卡包随机拉取 N 张卡牌（默认3张）
func open_card_pack(pack_id: String, count: int = 3) -> Dictionary:
	var pack_result = await get_server_card_pack(pack_id)
	if pack_result.has("error") or not pack_result.has("data") or pack_result["data"].size() == 0:
		return {"error": "卡包不存在"}
	var pack = pack_result["data"][0]
	var cards = pack.get("pack_data", {}).get("cards", [])
	if cards.size() == 0:
		return {"error": "卡包为空"}
	# 随机抽取 count 张（不重复）
	var pool = cards.duplicate()
	var picked := []
	while picked.size() < count and pool.size() > 0:
		var rnd = randi() % pool.size()
		picked.append(pool[rnd])
		pool.remove_at(rnd)
	return {"data": picked}
## 删除一个预制卡包
#func delete_server_card_pack(server_pack_id: String) -> Dictionary:
#	var path = "/rest/v1/card_packs?id=eq." + server_pack_id
#	return await supabase_request(HTTPClient.METHOD_DELETE, path)
#

# ============================================================
#  全局飘窗通知（可在任何场景调用，自动添加到当前场景树）
# ============================================================

## 显示一个全局飘窗通知，带淡入淡出动画
## 在任何场景中调用：Global.show_global_toast("消息内容", Color("#FFD700"))
func show_global_toast(text: String, color: Color = Color("#FFD700")) -> void:
	var scene_root = get_tree().current_scene
	if scene_root == null:
		return
	
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 40)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_shadow_color", Color("#000000"))
	lbl.add_theme_constant_override("shadow_offset_x", 2)
	lbl.add_theme_constant_override("shadow_offset_y", 2)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.anchor_left = 0.1; lbl.anchor_top = 0.0
	lbl.anchor_right = 0.9; lbl.anchor_bottom = 0.0
	lbl.offset_top = Global.ph(0.35); lbl.offset_bottom = Global.ph(0.42)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.modulate.a = 0.0
	scene_root.add_child(lbl)
	var tw = create_tween()
	tw.tween_property(lbl, "modulate:a", 1.0, 0.25)
	tw.tween_interval(1.8)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.4)
	tw.tween_callback(lbl.queue_free)
