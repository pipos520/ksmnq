extends Node

## ============================================================
##  DataCache — 游戏数据缓存与查询（Autoload）
##  统一管理敌人、素材、辅材、卡包、卡组的JSON数据加载
## ============================================================

# ===== 服务器数据缓存 =====
var server_decks: Array = []
var server_decks_loaded: bool = false
var server_card_packs: Array = []
var server_card_packs_loaded: bool = false

# ===== 敌人数据 =====
var _enemy_data_cache: Dictionary = {}
var _enemy_name_map: Dictionary = {}
var _enemy_plain_name_map: Dictionary = {}

func load_enemy_data() -> Dictionary:
	if _enemy_data_cache.size() > 0:
		return _enemy_data_cache
	var file = FileAccess.open("res://Data/enemies.json", FileAccess.READ)
	if file == null:
		print("[DataCache] 无法读取敌人数据文件 res://Data/enemies.json")
		return {}
	var json_str = file.get_as_text()
	file.close()
	var json := JSON.new()
	var err := json.parse(json_str)
	if err != OK:
		print("[DataCache] 敌人JSON解析错误：", json.get_error_message())
		return {}
	_enemy_data_cache = json.get_data()
	_enemy_name_map.clear()
	_enemy_plain_name_map.clear()
	for map_id in _enemy_data_cache.get("maps", {}).keys():
		var map_data = _enemy_data_cache["maps"][map_id]
		for terrain_id in map_data.get("terrains", {}).keys():
			var terrain_data = map_data["terrains"][terrain_id]
			for monster in terrain_data.get("monsters", []):
				var mname = monster.get("name", "")
				if mname != "":
					_enemy_name_map[mname] = monster.duplicate(true)
					var plain = _strip_emoji(mname)
					if plain != "":
						_enemy_plain_name_map[plain] = monster.duplicate(true)
			var boss = terrain_data.get("boss", {})
			if boss is Dictionary and boss.size() > 0:
				var bname = boss.get("name", "")
				if bname != "":
					_enemy_name_map[bname] = boss.duplicate(true)
					var plain = _strip_emoji(bname)
					if plain != "":
						_enemy_plain_name_map[plain] = boss.duplicate(true)
			elif boss is Array:
				for b in boss:
					var bname = b.get("name", "")
					if bname != "":
						_enemy_name_map[bname] = b.duplicate(true)
						var plain = _strip_emoji(bname)
						if plain != "":
							_enemy_plain_name_map[plain] = b.duplicate(true)
	print("[DataCache] 敌人数据加载完成，共 ", _enemy_name_map.size(), " 个敌人")
	return _enemy_data_cache

func get_enemy_card_template(template_id: String) -> Dictionary:
	var data = load_enemy_data()
	return data.get("card_templates", {}).get(template_id, {})

func get_enemy_by_name(name: String) -> Dictionary:
	load_enemy_data()
	return _enemy_name_map.get(name, {})

func get_enemy_name_list() -> Array:
	load_enemy_data()
	return _enemy_name_map.keys()

func get_enemy_by_plain_name(name: String) -> Dictionary:
	load_enemy_data()
	return _enemy_plain_name_map.get(name, {})

func get_enemy_plain_name_list() -> Array:
	load_enemy_data()
	return _enemy_plain_name_map.keys()

func _strip_emoji(name: String) -> String:
	var result = ""
	for i in range(name.length()):
		var c = name.unicode_at(i)
		if c >= 0x20 and c <= 0x7F:
			result += name[i]
		elif c >= 0x4E00 and c <= 0x9FFF:
			result += name[i]
		elif c >= 0x3400 and c <= 0x4DBF:
			result += name[i]
	return result.strip_edges()

func get_map_monsters(map_id: String, terrain: String) -> Array:
	var data = load_enemy_data()
	var maps = data.get("maps", {})
	var map_data = maps.get(map_id, {})
	var terrains = map_data.get("terrains", {})
	var terrain_data = terrains.get(terrain, {})
	return terrain_data.get("monsters", [])

func get_map_boss(map_id: String) -> Dictionary:
	var data = load_enemy_data()
	var maps = data.get("maps", {})
	var map_data = maps.get(map_id, {})
	var boss_list = map_data.get("boss", [])
	if boss_list is Array and boss_list.size() > 0:
		var rng = RandomNumberGenerator.new()
		rng.randomize()
		var chosen = boss_list[rng.randi_range(0, boss_list.size() - 1)]
		print("[DataCache] 随机选中BOSS: ", chosen.get("name", "未知"))
		return chosen.duplicate(true)
	return {}

# ===== 素材数据 =====
var material_data: Dictionary = {}
var formula_data: Dictionary = {}
var _material_map: Dictionary = {}
var _material_name_map: Dictionary = {}
var _material_category_map: Dictionary = {}

func get_material_by_id(id: String) -> Dictionary:
	return _material_map.get(id, {})

func get_material_category(id: String) -> String:
	return _material_category_map.get(id, "未知")

func get_material_by_name(name: String) -> Dictionary:
	var mid = _material_name_map.get(name, "")
	return _material_map.get(mid, {})

func get_material_id_by_name(name: String) -> String:
	return _material_name_map.get(name, "")

func get_material_name_list() -> Array:
	return _material_name_map.keys()

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
		print("[DataCache] 无法读取素材数据文件 res://Data/materials.json")
		return
	var json_str = file.get_as_text()
	file.close()
	var json := JSON.new()
	var err := json.parse(json_str)
	if err != OK:
		print("[DataCache] 素材JSON解析错误：", json.get_error_message())
		return
	var data = json.get_data()
	material_data = data.get("materials", {})
	formula_data = data.get("formulas", {})
	_material_map.clear()
	_material_name_map.clear()
	for category in ["fiber", "mineral", "resin", "extract", "pigment", "binder"]:
		var cat_label = {"fiber": "纤维", "mineral": "矿粉", "resin": "树脂", "extract": "萃取液", "pigment": "颜料", "binder": "粘合剂"}.get(category, "未知")
		for mat in material_data.get(category, []):
			var mid = mat.get("id", "")
			if mid != "":
				_material_map[mid] = mat
				_material_category_map[mid] = cat_label
				var mname = mat.get("name", "")
				if mname != "":
					_material_name_map[mname] = mid
	print("[DataCache] 素材数据加载完成")

# ===== 辅材数据 =====
var _aux_item_data: Array = []
var _aux_item_map: Dictionary = {}
var _aux_name_map: Dictionary = {}

func get_aux_list() -> Array:
	return _aux_item_data.duplicate()

func get_aux_by_id(id: String) -> Dictionary:
	return _aux_item_map.get(id, {})

func get_aux_by_name(name: String) -> Dictionary:
	var aid = _aux_name_map.get(name, "")
	return _aux_item_map.get(aid, {})

func get_aux_id_by_name(name: String) -> String:
	return _aux_name_map.get(name, "")

func get_aux_name_list() -> Array:
	return _aux_name_map.keys()

func _load_aux_data() -> void:
	var file = FileAccess.open("res://Data/aux_items.json", FileAccess.READ)
	if file == null:
		print("[DataCache] 无法读取辅材数据文件 res://Data/aux_items.json")
		return
	var json_str = file.get_as_text()
	file.close()
	var json := JSON.new()
	var err := json.parse(json_str)
	if err != OK:
		print("[DataCache] 辅材JSON解析错误：", json.get_error_message())
		return
	var data = json.get_data()
	_aux_item_data = data.get("aux_items", [])
	_aux_item_map.clear()
	_aux_name_map.clear()
	for item in _aux_item_data:
		var aid = item.get("id", "")
		if aid != "":
			_aux_item_map[aid] = item
			var aname = item.get("name", "")
			if aname != "":
				_aux_name_map[aname] = aid
	print("[DataCache] 辅材数据加载完成：共 ", _aux_item_data.size(), " 个辅材")

# ===== 服务器数据（卡组池 + 卡包） =====

func _load_local_json(path: String) -> Dictionary:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		print("[DataCache] 无法读取本地数据文件 ", path)
		return {"error": "本地数据文件缺失: " + path}
	var json_str = file.get_as_text()
	file.close()
	var json := JSON.new()
	var err := json.parse(json_str)
	if err != OK:
		print("[DataCache] JSON解析错误 ", path, " : ", json.get_error_message())
		return {"error": "JSON解析失败: " + path}
	var data = json.get_data()
	if data is Array:
		return {"data": data}
	return {"data": []}

func get_all_decks() -> Dictionary:
	if server_decks_loaded:
		return {"data": server_decks}
	return _load_local_json("res://Data/local_ai_decks.json")

func get_random_deck() -> Dictionary:
	var result = await get_all_decks()
	if result.has("error") or not result.has("data") or result["data"].size() == 0:
		return {"error": "卡组池为空"}
	var decks = result["data"]
	var rnd = randi() % decks.size()
	var pick = decks[rnd]
	return {"data": pick.get("deck_data", {})}

func get_all_card_packs() -> Dictionary:
	if server_card_packs_loaded:
		return {"data": server_card_packs}
	return _load_local_json("res://Data/local_card_packs.json")

func get_server_card_pack(pack_id: String) -> Dictionary:
	if server_card_packs_loaded:
		var found = []
		for p in server_card_packs:
			if p.get("pack_id") == pack_id:
				found.append(p)
		return {"data": found}
	var result = _load_local_json("res://Data/local_card_packs.json")
	if result.has("error"):
		return result
	var packs = result.get("data", [])
	var found = []
	for p in packs:
		if p.get("pack_id") == pack_id:
			found.append(p)
	return {"data": found}

func open_card_pack(pack_id: String, count: int = 3) -> Dictionary:
	var pack_result = await get_server_card_pack(pack_id)
	if pack_result.has("error") or not pack_result.has("data") or pack_result["data"].size() == 0:
		return {"error": "卡包不存在"}
	var pack = pack_result["data"][0]
	var cards = pack.get("pack_data", {}).get("cards", [])
	if cards.size() == 0:
		return {"error": "卡包为空"}
	var pool = cards.duplicate()
	var picked := []
	while picked.size() < count and pool.size() > 0:
		var rnd = randi() % pool.size()
		picked.append(pool[rnd])
		pool.remove_at(rnd)
	return {"data": picked}

# ===== 玩家ID =====

func get_player_id() -> String:
	const PLAYER_ID_FILE := "user://player_id.txt"
	var file = FileAccess.open(PLAYER_ID_FILE, FileAccess.READ)
	if file:
		var id = file.get_as_text().strip_edges()
		file.close()
		if id != "":
			return id
	var device_id = OS.get_unique_id()
	var id = device_id if device_id != "" else _generate_player_uuid()
	file = FileAccess.open(PLAYER_ID_FILE, FileAccess.WRITE)
	if file:
		file.store_string(id)
		file.close()
		print("[DataCache] 玩家ID已缓存: ", id)
	else:
		print("[DataCache] 无法写入玩家ID缓存文件")
	return id

func _generate_player_uuid() -> String:
	var chars = "abcdefghijklmnopqrstuvwxyz0123456789"
	var id = "player_"
	for i in range(16):
		id += chars[randi() % chars.length()]
	return id

# ===== 初始化 =====

func _ready() -> void:
	_load_materials()
	_load_aux_data()
