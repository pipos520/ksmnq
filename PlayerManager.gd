extends Node
## ============================================================
##  角色信息管理器 —— 集中管理所有玩家数据
##  自动加载单例，数据保存在独立的 player_data.json 中
## ============================================================
const SAVE_PATH := "user://player_data.json"

## 获取本地日期字符串（格式：YYYY-MM-DD）
func _get_local_date() -> String:
	var d = Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02d" % [d["year"], d["month"], d["day"]]
# 品质等级顺序（用于晋级条件向上兼容判断）
const QUALITY_LEVELS := {"废品": 0, "瑕疵": 1, "普通": 2, "优秀": 3, "卓越": 4, "完美": 5}
# ---------- 公会等级数据 ----------
const GUILD_LEVELS := [
	{"title": "见习制卡师",  "level": 1,  "cards_needed": 0,   "quality_needed": "",        "map_needed": ""},
	{"title": "初级制卡师",  "level": 2,  "cards_needed": 3,   "quality_needed": "",        "map_needed": ""},
	{"title": "中级制卡师",  "level": 3,  "cards_needed": 10,  "quality_needed": "",        "map_needed": ""},
	{"title": "高级制卡师",  "level": 4,  "cards_needed": 20,  "quality_needed": "优秀",    "map_needed": ""},
	{"title": "精英制卡师",  "level": 5,  "cards_needed": 40,  "quality_needed": "",        "map_needed": "迷雾森林"},
	{"title": "卓越制卡师",  "level": 6,  "cards_needed": 60,  "quality_needed": "卓越",    "map_needed": ""},
	{"title": "大师制卡师",  "level": 7,  "cards_needed": 80,  "quality_needed": "",        "map_needed": "火焰洞穴"},
	{"title": "宗师制卡师",  "level": 8,  "cards_needed": 100, "quality_needed": "",        "map_needed": "风暴高塔"},
	{"title": "传说制卡师",  "level": 9,  "cards_needed": 150, "quality_needed": "完美",    "map_needed": "暗影沼泽"},
	{"title": "制卡圣手",    "level": 10, "cards_needed": 200, "quality_needed": "",        "map_needed": "传说遗迹"},
]

# 默认初始数据
var _data: Dictionary = {}

# ---------- 信号 ----------
signal data_changed(section: String, key: String, value)
## 阶梯任务完成时发射：label(名称), step(第几阶1~), reward(金币), target(目标值)
signal ladder_step_completed(label: String, step: int, reward: int, target: int)

func _ready():
	load_data()

# ==================== 存档读写 ====================

## 从磁盘加载玩家数据
func load_data() -> void:
	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		print("[PlayerManager] 未找到玩家数据，使用默认初始数据")
		_init_default_data()
		return
	var json_str = file.get_as_text()
	file.close()
	var json = JSON.new()
	var err = json.parse(json_str)
	if err != OK:
		print("[PlayerManager] 数据解析错误：", json.get_error_message())
		_init_default_data()
		return
	_data = json.get_data()
	_ensure_defaults()
	print("[PlayerManager] 玩家数据加载成功")
	print("[PlayerManager] 当前称号：Lv.", get_guild_level(), " ", get_guild_title())

## 写入磁盘
func save_data() -> void:
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		print("[PlayerManager] 错误：无法写入数据文件")
		return
	var json_str = JSON.stringify(_data, "\t")
	file.store_string(json_str)
	file.close()

## 重置数据（清空并用默认值初始化）
func reset_data() -> void:
	_init_default_data()
	save_data()
	print("[PlayerManager] 数据已重置")

func _init_default_data() -> void:
	_data = {
		"profile": {
			"name": "卡师",
			"level": 1,
			"exp": 0,
			"gold": 100,
			"diamonds": 50
		},
		"crafting": {
			"cards_created": 0,
			"highest_quality": "",
			"cards_by_quality": {}
		},
		"progress": {
			"misty_forest": false,
			"flame_cavern": false,
			"storm_tower": false,
			"shadow_swamp": false,
			"legendary_ruins": false
		},
		"guild": {
			"level": 1,
			"title": "见习制卡师"
		},
		"inventory": {
			"cards": [],
			"decks": {},
			"materials": {}
		},
		"circuit": {
			"unlocked": ["TR01", "A01", "T02"]
		},
		"stats": {
			"total_damage_dealt": 0,
			"total_healing": 0,
			"total_energy_used": 0,
			"total_cards_drawn": 0,
			"total_special_summon": 0,
			"total_destructions": 0,
			"cards_collected": 0,
			"total_tasks_completed": 0
		},
		"guild_tasks": {
			"data": null
		}
	}

func _ensure_defaults() -> void:
	if not _data.has("profile"): _data["profile"] = {"name":"卡师","level":1,"exp":0,"gold":100,"diamonds":50}
	if not _data.has("crafting"): _data["crafting"] = {"cards_created":0,"highest_quality":"","cards_by_quality":{}}
	if not _data.has("progress"): _data["progress"] = {"misty_forest":false,"flame_cavern":false,"storm_tower":false,"shadow_swamp":false,"legendary_ruins":false}
	if not _data.has("guild"): _data["guild"] = {"level":1,"title":"见习制卡师"}
	if not _data.has("inventory"): _data["inventory"] = {"cards":[],"decks":{},"materials":{}}
	if not _data.has("circuit"): _data["circuit"] = {"unlocked":["TR01","A01","T02"]}
	if not _data.has("guild_tasks"): _data["guild_tasks"] = {"data": null}
	var p = _data["profile"]
	if not p.has("name"): p["name"] = "卡师"
	if not p.has("level"): p["level"] = 1
	if not p.has("exp"): p["exp"] = 0
	if not p.has("gold"): p["gold"] = 100
	if not p.has("diamonds"): p["diamonds"] = 50
	var c = _data["crafting"]
	if not c.has("cards_created"): c["cards_created"] = 0
	if not c.has("highest_quality"): c["highest_quality"] = ""
	if not c.has("cards_by_quality"): c["cards_by_quality"] = {}
	var pr = _data["progress"]
	if not pr.has("misty_forest"): pr["misty_forest"] = false
	if not pr.has("flame_cavern"): pr["flame_cavern"] = false
	if not pr.has("storm_tower"): pr["storm_tower"] = false
	if not pr.has("shadow_swamp"): pr["shadow_swamp"] = false
	if not pr.has("legendary_ruins"): pr["legendary_ruins"] = false
	var g = _data["guild"]
	if not g.has("level"): g["level"] = 1
	if not g.has("title"): g["title"] = "见习制卡师"
	var inv = _data["inventory"]
	if not inv.has("cards"): inv["cards"] = []
	if not inv.has("decks"): inv["decks"] = {}
	if not inv.has("materials"): inv["materials"] = {}
	var cir = _data["circuit"]
	if not cir.has("unlocked"): cir["unlocked"] = ["TR01","A01","T02"]
	if not _data.has("stats"): _data["stats"] = {"total_damage_dealt":0,"total_healing":0,"total_energy_used":0,"total_cards_drawn":0,"total_special_summon":0,"total_destructions":0,"cards_collected":0,"total_tasks_completed":0}

# ==================== 通用存取 ====================

func get_data(section: String, key: String, default_value = null):
	var sec = _data.get(section, {})
	return sec.get(key, default_value)

func set_data(section: String, key: String, value) -> void:
	if not _data.has(section):
		_data[section] = {}
	_data[section][key] = value
	data_changed.emit(section, key, value)

func get_section(section: String) -> Dictionary:
	return _data.get(section, {})

func set_section(section: String, data: Dictionary) -> void:
	_data[section] = data
	data_changed.emit(section, "", null)

# ==================== 角色属性 ====================

func get_player_name() -> String:          return get_data("profile", "name", "卡师")
func set_player_name(v: String) -> void:   set_data("profile", "name", v)

## ★ level/exp 代理到 SaveManager（统一单一数据源）
func get_level() -> int:            return SaveManager.get_value("player", "level", 1)
func set_level(v: int) -> void:     SaveManager.set_value("player", "level", v); SaveManager.save_to_disk()

func get_exp() -> int:              return SaveManager.get_value("player", "exp", 0)
func set_exp(v: int) -> void:       SaveManager.set_value("player", "exp", v); SaveManager.save_to_disk()

## ★ 金币代理到 SaveManager（统一单一数据源，修复双系统问题）
func get_gold() -> int:             return SaveManager.get_value("player", "gold", 100)
func set_gold(v: int) -> void:      SaveManager.set_value("player", "gold", v); SaveManager.save_to_disk()

## ★ 钻石代理到 SaveManager（统一单一数据源，预防未来双系统）
func get_diamonds() -> int:         return SaveManager.get_value("player", "diamonds", 50)
func set_diamonds(v: int) -> void:  SaveManager.set_value("player", "diamonds", v); SaveManager.save_to_disk()

# ==================== 每日决斗场阶梯任务 ====================

## 每日决斗场胜利阶梯：1→5→10→15→20→25→30胜
const DAILY_DUEL_LADDER := [1, 5, 10, 15, 20, 25, 30]
const DAILY_DUEL_REWARDS := [10, 20, 30, 40, 50, 60, 100]

## 获取每日决斗场胜利次数
func get_daily_duel_wins() -> int:
	# 检查日期是否变更，变更则重置
	var today = _get_local_date()
	var last_date = get_daily_duel_date()
	if last_date != today:
		set_daily_duel_wins(0)
		set_daily_duel_ladder_index(-1)
		set_daily_duel_date(today)
	return get_data("daily", "duel_wins", 0)

## 设置每日决斗场胜利次数
func set_daily_duel_wins(v: int) -> void:
	set_data("daily", "duel_wins", v)

## 获取每日决斗场已完成阶梯索引（-1表示还没完成任何一阶）
func get_daily_duel_ladder_index() -> int:
	return get_data("daily", "duel_ladder_index", -1)

## 设置每日决斗场已完成阶梯索引
func set_daily_duel_ladder_index(v: int) -> void:
	set_data("daily", "duel_ladder_index", v)

## 获取每日决斗场记录日期
func get_daily_duel_date() -> String:
	return get_data("daily", "duel_date", "")

## 设置每日决斗场记录日期
func set_daily_duel_date(v: String) -> void:
	set_data("daily", "duel_date", v)

## 决斗场胜利时调用，记录胜场并检查是否达到下一阶梯
## 返回：{ "completed": bool, "reward": int, "next_target": int } 或 null
func record_duel_win() -> Dictionary:
	# 检查日期是否变更，变更则重置
	var today = _get_local_date()
	var last_date = get_daily_duel_date()
	if last_date != today:
		set_daily_duel_wins(0)
		set_daily_duel_ladder_index(-1)
		set_daily_duel_date(today)
	
	var wins = get_daily_duel_wins() + 1
	set_daily_duel_wins(wins)
	
	# 检查是否达到下一阶梯
	var current_idx = get_daily_duel_ladder_index()
	var next_idx = current_idx + 1
	if next_idx < DAILY_DUEL_LADDER.size() and wins >= DAILY_DUEL_LADDER[next_idx]:
		# 完成阶梯！
		set_daily_duel_ladder_index(next_idx)
		var reward = DAILY_DUEL_REWARDS[next_idx]
		set_gold(get_gold() + reward)
		ladder_step_completed.emit(" 决斗场", next_idx + 1, reward, DAILY_DUEL_LADDER[next_idx])
		save_data()
		var next_target = DAILY_DUEL_LADDER[next_idx + 1] if next_idx + 1 < DAILY_DUEL_LADDER.size() else -1
		return {"completed": true, "reward": reward, "next_target": next_target, "next_idx": next_idx + 1}
	
	save_data()
	return {"completed": false, "wins": wins}

## 获取当前应显示的阶梯索引（0=第1阶，以此类推，完成全部返回-1）
func get_current_duel_ladder_step() -> int:
	# 检查日期是否变更，变更则重置
	var today = _get_local_date()
	var last_date = get_daily_duel_date()
	if last_date != today:
		set_daily_duel_wins(0)
		set_daily_duel_ladder_index(-1)
		set_daily_duel_date(today)
	var idx = get_daily_duel_ladder_index()
	var next_idx = idx + 1
	if next_idx >= DAILY_DUEL_LADDER.size():
		return -1  # 全部完成
	return next_idx

## 获取当前阶梯的胜利目标
func get_current_duel_ladder_target() -> int:
	var step = get_current_duel_ladder_step()
	if step < 0:
		return -1
	return DAILY_DUEL_LADDER[step]

## 获取当前阶梯的金币奖励
func get_current_duel_ladder_reward() -> int:
	var step = get_current_duel_ladder_step()
	if step < 0:
		return 0
	return DAILY_DUEL_REWARDS[step]

## 重置决斗场阶梯（看广告后调用）
func reset_duel_ladder() -> void:
	set_daily_duel_wins(0)
	set_daily_duel_ladder_index(-1)
	set_daily_duel_date(_get_local_date())
	save_data()

## 通用：重置每日阶梯（看广告后调用）
func reset_daily_ladder(key_prefix: String) -> void:
	set_data("daily", key_prefix + "_count", 0)
	set_data("daily", key_prefix + "_ladder_idx", -1)
	set_data("daily", key_prefix + "_date", _get_local_date())
	save_data()

# ==================== 每日通用阶梯任务 ====================

## 通用每日阶梯：杀敌/通关/制卡 共用阶梯规则
const DAILY_LADDER := [1, 5, 10, 15, 20, 25, 30]
const DAILY_LADDER_REWARDS := [10, 20, 30, 40, 50, 60, 100]

## 通用：检查日期变更并重置
func _check_daily_reset(key_prefix: String) -> void:
	var today = _get_local_date()
	var last_date = get_data("daily", key_prefix + "_date", "")
	if last_date != today:
		set_data("daily", key_prefix + "_count", 0)
		set_data("daily", key_prefix + "_ladder_idx", -1)
		set_data("daily", key_prefix + "_date", today)

## 通用：记录一次计数，检测阶梯完成
## key_prefix: 如 "kill"/"map_clear"/"craft"
## 返回：{ "completed": bool, "reward": int, "step": int, "target": int }
func _record_daily_ladder(key_prefix: String, label: String = "") -> Dictionary:
	_check_daily_reset(key_prefix)
	var count = get_data("daily", key_prefix + "_count", 0) + 1
	set_data("daily", key_prefix + "_count", count)
	var idx = get_data("daily", key_prefix + "_ladder_idx", -1)
	var next_idx = idx + 1
	if next_idx < DAILY_LADDER.size() and count >= DAILY_LADDER[next_idx]:
		set_data("daily", key_prefix + "_ladder_idx", next_idx)
		var reward = DAILY_LADDER_REWARDS[next_idx]
		set_gold(get_gold() + reward)
		if label != "":
			ladder_step_completed.emit(label, next_idx + 1, reward, DAILY_LADDER[next_idx])
		save_data()
		var next_target = DAILY_LADDER[next_idx + 1] if next_idx + 1 < DAILY_LADDER.size() else -1
		return {"completed": true, "reward": reward, "step": next_idx, "target": next_target}
	save_data()
	return {"completed": false, "count": count}

## 通用：获取当前阶梯索引
func _get_daily_ladder_step(key_prefix: String) -> int:
	_check_daily_reset(key_prefix)  # ★ 读取前必须检查日期，否则指示点会停留在昨天的阶段
	var idx = get_data("daily", key_prefix + "_ladder_idx", -1)
	var next_idx = idx + 1
	if next_idx >= DAILY_LADDER.size():
		return -1
	return next_idx

## 通用：获取当前阶梯目标
func _get_daily_ladder_target(key_prefix: String) -> int:
	var step = _get_daily_ladder_step(key_prefix)
	if step < 0:
		return -1
	return DAILY_LADDER[step]

## 通用：获取当前计数
func _get_daily_ladder_count(key_prefix: String) -> int:
	_check_daily_reset(key_prefix)
	return get_data("daily", key_prefix + "_count", 0)

# ==================== 杀敌阶梯 ====================

func record_kill() -> Dictionary:
	return _record_daily_ladder("kill", " 杀敌")
func get_kill_step() -> int:
	return _get_daily_ladder_step("kill")
func get_kill_target() -> int:
	return _get_daily_ladder_target("kill")
func get_kill_count() -> int:
	return _get_daily_ladder_count("kill")

# ==================== 通关地图阶梯 ====================

func record_map_clear() -> Dictionary:
	return _record_daily_ladder("map_clear", " 通关地图")
func get_map_clear_step() -> int:
	return _get_daily_ladder_step("map_clear")
func get_map_clear_target() -> int:
	return _get_daily_ladder_target("map_clear")
func get_map_clear_count() -> int:
	return _get_daily_ladder_count("map_clear")

# ==================== 制卡阶梯 ====================

func record_craft() -> Dictionary:
	return _record_daily_ladder("craft", " 制卡")
func get_craft_step() -> int:
	return _get_daily_ladder_step("craft")
func get_craft_target() -> int:
	return _get_daily_ladder_target("craft")
func get_craft_count() -> int:
	return _get_daily_ladder_count("craft")
func get_cards_created() -> int: return get_data("crafting", "cards_created", 0)
func set_cards_created(v: int) -> void: set_data("crafting", "cards_created", v)

func get_highest_quality() -> String: return get_data("crafting", "highest_quality", "")
func set_highest_quality(v: String) -> void: set_data("crafting", "highest_quality", v)

## 记录制卡一次（自动加1，检查品质突破）
func record_card_creation(quality: String = "") -> void:
	var count = get_cards_created() + 1
	set_cards_created(count)
	if quality != "":
		var current_highest = get_highest_quality()
		var quality_order = {"普通": 0, "优秀": 1, "卓越": 2, "完美": 3}
		var new_rank = quality_order.get(quality, 0)
		var old_rank = quality_order.get(current_highest, -1)
		if new_rank > old_rank:
			set_highest_quality(quality)
		# 记录各品质数量
		var by_quality = get_data("crafting", "cards_by_quality", {})
		by_quality[quality] = by_quality.get(quality, 0) + 1
		set_data("crafting", "cards_by_quality", by_quality)
	# 自动更新公会等级
	_update_guild_level()
	save_data()

# ==================== 地图进度 ====================

func is_map_cleared(map_key: String) -> bool:
	return get_data("progress", map_key, false)

func set_map_cleared(map_key: String, cleared: bool = true) -> void:
	set_data("progress", map_key, cleared)
	if cleared:
		_update_guild_level()
	save_data()

func get_cleared_map_count() -> int:
	var count = 0
	for key in ["misty_forest", "flame_cavern", "storm_tower", "shadow_swamp", "legendary_ruins"]:
		if get_data("progress", key, false):
			count += 1
	return count

func get_map_progress_text() -> String:
	return str(get_cleared_map_count()) + " / 5 个"

# ==================== 公会等级 ====================

func get_guild_level() -> int:
	return get_data("guild", "level", 1)

func get_guild_title() -> String:
	return get_data("guild", "title", "见习制卡师")

## 按公会称号等级获取玩家最大生命值
## 等级越低越脆弱，等级越高越耐打，体现成长感
func get_guild_max_hp() -> int:
	var level = get_guild_level()
	# Lv.1~10: 20→25→30→35→40→50→55→60→70→80
	match level:
		1:  return 20
		2:  return 25
		3:  return 30
		4:  return 35
		5:  return 40
		6:  return 50
		7:  return 55
		8:  return 60
		9:  return 70
		10: return 80
		_:  return 20

func _update_guild_level() -> void:
	var cards_created = get_cards_created()
	var highest_quality = get_highest_quality()
	var new_level = 1
	var new_title = GUILD_LEVELS[0].title
	for i in range(GUILD_LEVELS.size() - 1, -1, -1):
		var lv = GUILD_LEVELS[i]
		if cards_created >= lv.cards_needed:
			if lv.quality_needed != "" and QUALITY_LEVELS.get(highest_quality, -1) < QUALITY_LEVELS.get(lv.quality_needed, 0):
				continue
			if lv.map_needed != "":
				var map_key = {"迷雾森林":"misty_forest","火焰洞穴":"flame_cavern","风暴高塔":"storm_tower","暗影沼泽":"shadow_swamp","传说遗迹":"legendary_ruins"}
				if not get_data("progress", map_key.get(lv.map_needed, ""), false):
					continue
			new_level = lv.level
			new_title = lv.title
			break
	var old_level = get_guild_level()
	set_data("guild", "level", new_level)
	set_data("guild", "title", new_title)
	if new_level > old_level:
		print("[PlayerManager]  公会升级！Lv.", old_level, " → Lv.", new_level, " ", new_title)

## 获取下一级信息（用于界面显示）
func get_next_guild_level_info() -> Dictionary:
	var current = get_guild_level()
	var next = null
	for i in range(GUILD_LEVELS.size()):
		if GUILD_LEVELS[i].level == current + 1:
			next = GUILD_LEVELS[i].duplicate()
			break
	if next == null:
		return {"is_max": true, "title": "", "conditions": []}
	var conds = []
	var cards_created = get_cards_created()
	var highest_quality = get_highest_quality()
	conds.append({"text": "制作 " + str(next.cards_needed) + " 张卡", "done": cards_created >= next.cards_needed, "current": str(cards_created) + "张"})
	if next.quality_needed != "":
		var ok = QUALITY_LEVELS.get(highest_quality, -1) >= QUALITY_LEVELS.get(next.quality_needed, 0)
		conds.append({"text": "品质达到" + next.quality_needed + "及以上", "done": ok, "current": highest_quality if highest_quality != "" else "暂无"})
	if next.map_needed != "":
		var map_key = {"迷雾森林":"misty_forest","火焰洞穴":"flame_cavern","风暴高塔":"storm_tower","暗影沼泽":"shadow_swamp","传说遗迹":"legendary_ruins"}
		var mk = map_key.get(next.map_needed, "")
		var cleared = get_data("progress", mk, false)
		conds.append({"text": "通关" + next.map_needed, "done": cleared, "current": ""})
	return {"is_max": false, "level": next.level, "title": next.title, "conditions": conds}

# ==================== 背包 ====================

func get_cards() -> Array:
	return get_data("inventory", "cards", [])

func set_cards(v: Array) -> void:
	set_data("inventory", "cards", v)

func get_decks() -> Dictionary:
	return get_data("inventory", "decks", {})

func set_decks(v: Dictionary) -> void:
	set_data("inventory", "decks", v)

func get_materials() -> Dictionary:
	return get_data("inventory", "materials", {})

func set_materials(v: Dictionary) -> void:
	set_data("inventory", "materials", v)

func add_material(material_id: String, amount: int = 1) -> void:
	var mats = get_materials()
	mats[material_id] = mats.get(material_id, 0) + amount
	set_materials(mats)

# ==================== 纹路 ====================

func get_unlocked_circuits() -> Array:
	return get_data("circuit", "unlocked", [])

func set_unlocked_circuits(v: Array) -> void:
	set_data("circuit", "unlocked", v)

func is_circuit_unlocked(circuit_id: String) -> bool:
	return circuit_id in get_unlocked_circuits()

func unlock_circuit(circuit_id: String) -> bool:
	var unlocked = get_unlocked_circuits()
	if circuit_id in unlocked:
		return false
	unlocked.append(circuit_id)
	set_unlocked_circuits(unlocked)
	save_data()
	print("[PlayerManager]  解锁纹路：", circuit_id)
	return true

func get_unlocked_circuit_count() -> int:
	return get_unlocked_circuits().size()

# ==================== 解锁统计 ====================

func get_total_damage_dealt() -> int:     return get_data("stats", "total_damage_dealt", 0)
func set_total_damage_dealt(v: int) -> void: set_data("stats", "total_damage_dealt", v); save_data()
func add_damage_dealt(v: int) -> void: set_total_damage_dealt(get_total_damage_dealt() + v)

func get_total_healing() -> int:          return get_data("stats", "total_healing", 0)
func set_total_healing(v: int) -> void:   set_data("stats", "total_healing", v); save_data()
func add_healing(v: int) -> void:         set_total_healing(get_total_healing() + v)

func get_total_energy_used() -> int:      return get_data("stats", "total_energy_used", 0)
func set_total_energy_used(v: int) -> void: set_data("stats", "total_energy_used", v); save_data()
func add_energy_used(v: int) -> void:     set_total_energy_used(get_total_energy_used() + v)

func get_total_cards_drawn() -> int:      return get_data("stats", "total_cards_drawn", 0)
func set_total_cards_drawn(v: int) -> void: set_data("stats", "total_cards_drawn", v); save_data()
func add_cards_drawn(v: int) -> void:     set_total_cards_drawn(get_total_cards_drawn() + v)

func get_total_special_summon() -> int:   return get_data("stats", "total_special_summon", 0)
func set_total_special_summon(v: int) -> void: set_data("stats", "total_special_summon", v); save_data()
func add_special_summon(v: int) -> void:  set_total_special_summon(get_total_special_summon() + v)

func get_total_destructions() -> int:     return get_data("stats", "total_destructions", 0)
func set_total_destructions(v: int) -> void: set_data("stats", "total_destructions", v); save_data()
func add_destructions(v: int) -> void:    set_total_destructions(get_total_destructions() + v)

func get_cards_collected() -> int:        return get_data("stats", "cards_collected", 0)
func set_cards_collected(v: int) -> void: set_data("stats", "cards_collected", v); save_data()
func add_cards_collected(v: int) -> void: set_cards_collected(get_cards_collected() + v)

func get_total_tasks_completed() -> int:  return get_data("stats", "total_tasks_completed", 0)
func set_total_tasks_completed(v: int) -> void: set_data("stats", "total_tasks_completed", v); save_data()
func add_tasks_completed(v: int) -> void: set_total_tasks_completed(get_total_tasks_completed() + v)