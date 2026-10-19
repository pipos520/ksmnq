extends Node

## ============================================================
##  卡牌管理器 —— 管理已刻画卡牌的增删查
##  所有操作底层调用 SaveManager 持久化
## ============================================================

const STORAGE_SECTION := "player"
const STORAGE_KEY := "cards"
const DECK_KEY := "decks"

## 是否已导入新手卡组（防止重复导入）
var _starter_imported := false

func _ready() -> void:
	# 延迟一帧，等 SaveManager 加载完存档再检查
	call_deferred("_check_import_starter")
	# 启动后延迟清理卡组残留失效ID（等新手卡组导入完成后再执行）
	call_deferred("_clean_invalid_deck_ids")

## 启动时扫描所有卡组，移除匹配不到收藏卡的失效ID（修复历史残留）
## 让「卡组显示牌数」与「实际战斗可用牌数」永远一致
func _clean_invalid_deck_ids() -> void:
	var decks = get_all_decks()
	if decks.size() == 0:
		return
	var all_cards = get_all_cards()
	# 建立可匹配 ID 集合（id + template_id 都算）
	var valid_ids := {}
	for card_data in all_cards:
		var cid = card_data.get("id", "")
		if cid != "":
			valid_ids[cid] = true
		var tid = card_data.get("template_id", "")
		if tid != "":
			valid_ids[tid] = true
	var changed := false
	for deck_id in decks:
		var deck = decks[deck_id]
		var cards = deck.get("cards", [])
		if cards is Array and cards.size() > 0:
			var new_cards := []
			var removed_any := false
			for cid in cards:
				if valid_ids.has(cid):
					new_cards.append(cid)
				else:
					removed_any = true
					print("[CardManager] 启动清理：卡组 ", deck_id, " 移除失效卡牌ID: ", cid)
			if removed_any:
				deck["cards"] = new_cards
				changed = true
	if changed:
		SaveManager.set_value("player", "decks", decks)
		SaveManager.save_to_disk()
		print("[CardManager]  卡组残留失效ID清理完成")
	else:
		print("[CardManager] 卡组检查：无残留失效ID，无需清理")

## 检查是否需要导入新手卡组
func _check_import_starter() -> void:
	if _starter_imported:
		return
	var cards = get_all_cards()
	if cards.size() > 0:
		_starter_imported = true
		return
	
	# 尝试从 res://starter_data.json 加载
	var file = FileAccess.open("res://starter_data.json", FileAccess.READ)
	if file == null:
		print("[CardManager] 未找到 starter_data.json，跳过导入")
		return
	
	var json_str = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var err = json.parse(json_str)
	if err != OK:
		print("[CardManager] 新手卡组 JSON 解析错误: ", json.get_error_message())
		return
	
	var data = json.get_data()
	var player_data = data.get("player", {})
	
	# 导入卡牌
	var starter_cards = player_data.get("cards", [])
	if starter_cards.size() > 0:
		SaveManager.set_value(STORAGE_SECTION, STORAGE_KEY, starter_cards)
		print("[CardManager]  导入新手卡组卡牌: ", starter_cards.size(), " 张")
	
	# 导入牌组
	var starter_decks = player_data.get("decks", {})
	if starter_decks.size() > 0:
		SaveManager.set_value(STORAGE_SECTION, DECK_KEY, starter_decks)
		print("[CardManager]  导入新手牌组: ", starter_decks.size(), " 个")
	
	# 初始化金币等
	if not SaveManager.get_value(STORAGE_SECTION, "gold", 0) > 0:
		SaveManager.set_value(STORAGE_SECTION, "gold", player_data.get("gold", 100))
		SaveManager.set_value(STORAGE_SECTION, "diamonds", player_data.get("diamonds", 50))
		SaveManager.set_value(STORAGE_SECTION, "level", 1)
		SaveManager.set_value(STORAGE_SECTION, "exp", 0)
	
	SaveManager.save_to_disk()
	_starter_imported = true
	print("[CardManager]  新手卡组导入完成！")

# ---------- 读取 ----------

## 获取所有卡牌（Array，最新在最后）
func get_all_cards() -> Array:
	return SaveManager.get_value(STORAGE_SECTION, STORAGE_KEY, [])

## 获取卡牌数量
func get_card_count() -> int:
	return get_all_cards().size()

## 获取指定索引的卡牌
func get_card(index: int) -> Dictionary:
	var cards = get_all_cards()
	if index < 0 or index >= cards.size():
		return {}
	return cards[index] as Dictionary

# ---------- 添加 ----------

## 添加一张卡牌（自动生成 id 和时间戳）
func add_card(card_data: Dictionary) -> void:
	var cards = get_all_cards()
	
	# 始终生成唯一实例ID（避免同名卡ID重复，导致交易/删除时无法区分）
	var new_data = card_data.duplicate()
	# 保存模板ID作为参考（如 CARD_QP_001），用于识别卡牌种类
	if new_data.has("id") and new_data["id"] != "":
		new_data["template_id"] = new_data["id"]
	# 生成唯一实例ID
	new_data["id"] = _generate_card_id()
	
	# 添加创建时间戳
	new_data["created_at"] = Time.get_unix_time_from_system()
	
	cards.append(new_data)
	SaveManager.set_value(STORAGE_SECTION, STORAGE_KEY, cards)
	SaveManager.save_to_disk()
	print("[CardManager] 添加卡牌: ", new_data.get("card_name", "未知"), " (id: ", new_data["id"], ")")

# ---------- 删除 ----------

## 删除指定索引的卡牌，返回是否成功
func remove_card(index: int) -> bool:
	var cards = get_all_cards()
	if index < 0 or index >= cards.size():
		return false
	var card_id = cards[index].get("id", "")
	cards.remove_at(index)
	SaveManager.set_value(STORAGE_SECTION, STORAGE_KEY, cards)
	# ★ 同步清理所有卡组中的该卡牌ID，避免残留失效ID
	if card_id != "":
		_remove_card_id_from_all_decks(card_id)
	SaveManager.save_to_disk()
	print("[CardManager] 删除卡牌，索引: ", index)
	return true

## 删除指定 id 的卡牌，返回是否成功
func remove_card_by_id(card_id: String) -> bool:
	var cards = get_all_cards()
	for i in range(cards.size()):
		if cards[i].get("id", "") == card_id:
			cards.remove_at(i)
			SaveManager.set_value(STORAGE_SECTION, STORAGE_KEY, cards)
			# ★ 同步清理所有卡组中的该卡牌ID，避免产生失效残留导致「显示牌数>实际牌数」
			_remove_card_id_from_all_decks(card_id)
			SaveManager.save_to_disk()
			print("[CardManager] 删除卡牌: ", card_id)
			return true
	return false

## 从所有卡组中移除指定的卡牌ID（删除卡牌时保持卡组同步）
func _remove_card_id_from_all_decks(card_id: String) -> void:
	var decks = get_all_decks()
	var changed := false
	for deck_id in decks:
		var deck = decks[deck_id]
		var cards = deck.get("cards", [])
		if cards is Array and cards.size() > 0:
			var new_cards := []
			var removed := false
			for cid in cards:
				if cid == card_id:
					removed = true
				else:
					new_cards.append(cid)
			if removed:
				deck["cards"] = new_cards
				changed = true
				print("[CardManager] 卡组 ", deck_id, " 同步移除残留卡牌: ", card_id)
	if changed:
		SaveManager.set_value("player", "decks", decks)

# ---------- 更新 ----------

## 更新指定索引的卡牌数据，返回是否成功
func update_card(index: int, card_data: Dictionary) -> bool:
	var cards = get_all_cards()
	if index < 0 or index >= cards.size():
		return false
	cards[index] = card_data.duplicate()
	SaveManager.set_value(STORAGE_SECTION, STORAGE_KEY, cards)
	SaveManager.save_to_disk()
	print("[CardManager] 更新卡牌，索引: ", index)
	return true

## 更新指定 id 的卡牌数据，返回是否成功
func update_card_by_id(card_id: String, card_data: Dictionary) -> bool:
	var cards = get_all_cards()
	for i in range(cards.size()):
		if cards[i].get("id", "") == card_id:
			cards[i] = card_data.duplicate()
			SaveManager.set_value(STORAGE_SECTION, STORAGE_KEY, cards)
			SaveManager.save_to_disk()
			print("[CardManager] 更新卡牌: ", card_id)
			return true
	return false

# ---------- 搜索/筛选 ----------

## 按卡名搜索卡牌（模糊匹配）
func search_cards(keyword: String) -> Array:
	if keyword == "":
		return get_all_cards()
	var cards = get_all_cards()
	var result := []
	var kw = keyword.to_lower()
	for card in cards:
		var name = card.get("name", card.get("card_name", "")).to_lower()
		if kw in name:
			result.append(card)
	return result

## 按品质筛选卡牌
func filter_by_quality(quality_keyword: String) -> Array:
	var cards = get_all_cards()
	var result := []
	for card in cards:
		var q = card.get("quality", "")
		if quality_keyword in q:
			result.append(card)
	return result

## 统一读取卡牌属性：null/空串/缺字段一律归一化为"无"
## 全项目所有读卡牌属性的地方都应使用本函数，保证显示与检测一致
static func get_card_element(card: Dictionary) -> String:
	var el = card.get("element", card.get("main_element", "无"))
	if el == null or str(el).strip_edges() == "":
		return "无"
	return str(el)

## 按属性筛选卡牌
func filter_by_element(element: String) -> Array:
	var cards = get_all_cards()
	var result := []
	for card in cards:
		var card_el = CardManager.get_card_element(card)
		if card_el == element:
			result.append(card)
	return result

## 按字段筛选卡牌
func filter_by_field(field: String) -> Array:
	var cards = get_all_cards()
	var result := []
	for card in cards:
		var fields = card.get("fields", [])
		for f in fields:
			if f == field:
				result.append(card)
				break
	return result

# ---------- 统计 ----------

## 获取所有牌组（Dictionary: { "deck_id": {"name":"...", "cards":[...]}, ... }）
func get_all_decks() -> Dictionary:
	return SaveManager.get_value("player", "decks", {})

## 获取指定牌组
func get_deck(deck_id: String) -> Dictionary:
	var decks = get_all_decks()
	return decks.get(deck_id, {})

## 创建牌组
func create_deck(deck_id: String, deck_name: String) -> bool:
	var decks = get_all_decks()
	if decks.has(deck_id):
		return false
	decks[deck_id] = {"name": deck_name, "cards": []}
	SaveManager.set_value("player", "decks", decks)
	SaveManager.save_to_disk()
	print("[CardManager] 创建牌组: ", deck_name, " (", deck_id, ")")
	return true

## 删除牌组
func delete_deck(deck_id: String) -> bool:
	var decks = get_all_decks()
	if not decks.has(deck_id):
		return false
	decks.erase(deck_id)
	SaveManager.set_value("player", "decks", decks)
	SaveManager.save_to_disk()
	print("[CardManager] 删除牌组: ", deck_id)
	return true

## 向牌组添加卡牌（按卡牌id）
func add_card_to_deck(deck_id: String, card_id: String) -> bool:
	var decks = get_all_decks()
	if not decks.has(deck_id):
		return false
	var deck = decks[deck_id]
	deck["cards"].append(card_id)
	SaveManager.set_value("player", "decks", decks)
	SaveManager.save_to_disk()
	print("[CardManager] 牌组 ", deck_id, " 添加卡牌: ", card_id)
	return true

## 从牌组移除卡牌（按卡牌id）
func remove_card_from_deck_by_id(deck_id: String, card_id: String) -> bool:
	var decks = get_all_decks()
	if not decks.has(deck_id):
		return false
	var deck = decks[deck_id]
	var cards = deck["cards"]
	for i in range(cards.size()):
		if cards[i] == card_id:
			cards.remove_at(i)
			SaveManager.set_value("player", "decks", decks)
			SaveManager.save_to_disk()
			print("[CardManager] 牌组 ", deck_id, " 移除卡牌: ", card_id)
			return true
	return false

## 从牌组移除卡牌（按索引）
func remove_card_from_deck(deck_id: String, card_index: int) -> bool:
	var decks = get_all_decks()
	if not decks.has(deck_id):
		return false
	var deck = decks[deck_id]
	if card_index < 0 or card_index >= deck["cards"].size():
		return false
	deck["cards"].remove_at(card_index)
	SaveManager.set_value("player", "decks", decks)
	SaveManager.save_to_disk()
	print("[CardManager] 牌组 ", deck_id, " 移除卡牌，索引: ", card_index)
	return true

## 设置牌组卡牌列表（直接覆盖）
func set_deck_cards(deck_id: String, card_ids: Array) -> bool:
	var decks = get_all_decks()
	if not decks.has(deck_id):
		return false
	decks[deck_id]["cards"] = card_ids.duplicate()
	SaveManager.set_value("player", "decks", decks)
	SaveManager.save_to_disk()
	print("[CardManager] 牌组 ", deck_id, " 卡牌列表已更新")
	return true

## 获取所有品质及其数量
func get_quality_stats() -> Dictionary:
	var cards = get_all_cards()
	var stats := {}
	for card in cards:
		var q = card.get("quality", "未知")
		stats[q] = stats.get(q, 0) + 1
	return stats


# ============================================================
# 卡背选择（每个牌组可选 5 款卡背）
# ============================================================

## 所有可用卡背款式（id -> {name, path}）
const DECK_BACKS: Dictionary = {
	"default": {"name": "经典", "path": "res://assets/3d/card_backs/card_back_default.png"},
	"canglan": {"name": "沧澜古界", "path": "res://assets/3d/card_backs/card_back_canglan.png"},
	"go":      {"name": "围棋",   "path": "res://assets/3d/card_backs/card_back_go.png"},
	"syjy":    {"name": "三约纪元", "path": "res://assets/3d/card_backs/card_back_syjy.png"},
	"nbd":     {"name": "你不对劲", "path": "res://assets/3d/card_backs/card_back_nbd.png"},
}

## 获取牌组的卡背 id（未设置默认 "default"）
func get_deck_back(deck_id: String) -> String:
	var decks = get_all_decks()
	if not decks.has(deck_id):
		return "default"
	return String(decks[deck_id].get("back", "default"))

## 设置牌组的卡背 id
func set_deck_back(deck_id: String, back_id: String) -> bool:
	if not DECK_BACKS.has(back_id):
		print("[CardManager] 未知卡背: ", back_id)
		return false
	var decks = get_all_decks()
	if not decks.has(deck_id):
		return false
	decks[deck_id]["back"] = back_id
	SaveManager.set_value("player", "decks", decks)
	SaveManager.save_to_disk()
	print("[CardManager] 牌组 ", deck_id, " 卡背设为: ", back_id)
	return true
## 按卡背 id 获取纹理路径（用于战斗场景加载）
func get_deck_back_path(back_id: String) -> String:
	if DECK_BACKS.has(back_id):
		return DECK_BACKS[back_id]["path"]
	return DECK_BACKS["default"]["path"]


# ============================================================
# 桌布选择（战斗背景，每个牌组可选 5 款桌布）
# ============================================================

## 所有可用桌布款式（id -> {name, path}）
const DECK_TABLECLOTHS: Dictionary = {
	"default": {"name": "经典",     "path": "res://assets/3d/battle_bg_default.png"},
	"canglan": {"name": "沧澜古界", "path": "res://assets/3d/battle_bg_canglan.png"},
	"go":      {"name": "围棋",     "path": "res://assets/3d/battle_bg_go.png"},
	"syjy":    {"name": "三约纪元", "path": "res://assets/3d/battle_bg_syjy.png"},
	"nbd":     {"name": "你不对劲", "path": "res://assets/3d/battle_bg_nbd.png"},
}

## 获取牌组的桌布 id（未设置默认 "default"）
func get_deck_tablecloth(deck_id: String) -> String:
	var decks = get_all_decks()
	if not decks.has(deck_id):
		return "default"
	return String(decks[deck_id].get("tablecloth", "default"))

## 设置牌组的桌布 id
func set_deck_tablecloth(deck_id: String, cloth_id: String) -> bool:
	if not DECK_TABLECLOTHS.has(cloth_id):
		print("[CardManager] 未知桌布: ", cloth_id)
		return false
	var decks = get_all_decks()
	if not decks.has(deck_id):
		return false
	decks[deck_id]["tablecloth"] = cloth_id
	SaveManager.set_value("player", "decks", decks)
	SaveManager.save_to_disk()
	print("[CardManager] 牌组 ", deck_id, " 桌布设为: ", cloth_id)
	return true

## 按桌布 id 获取纹理路径（用于横屏 3D 战斗场景加载）
func get_deck_tablecloth_path(cloth_id: String) -> String:
	if DECK_TABLECLOTHS.has(cloth_id):
		return DECK_TABLECLOTHS[cloth_id]["path"]
	return DECK_TABLECLOTHS["default"]["path"]

## 所有可用竖版桌布（用于竖屏 2D 战斗场景）
const DECK_TABLECLOTHS_PORTRAIT: Dictionary = {
	"default": {"name": "经典",     "path": "res://assets/3d/battle_bg_portrait/battle_bg_default.jpg"},
	"canglan": {"name": "沧澜古界", "path": "res://assets/3d/battle_bg_portrait/battle_bg_canglan.jpg"},
	"go":      {"name": "围棋",     "path": "res://assets/3d/battle_bg_portrait/battle_bg_go.jpg"},
	"syjy":    {"name": "三约纪元", "path": "res://assets/3d/battle_bg_portrait/battle_bg_syjy.jpg"},
	"nbd":     {"name": "你不对劲", "path": "res://assets/3d/battle_bg_portrait/battle_bg_nbd.jpg"},
}

## 按桌布 id 获取竖版纹理路径（用于竖屏 2D 战斗场景）
func get_deck_tablecloth_path_portrait(cloth_id: String) -> String:
	if DECK_TABLECLOTHS_PORTRAIT.has(cloth_id):
		return DECK_TABLECLOTHS_PORTRAIT[cloth_id]["path"]
	return DECK_TABLECLOTHS_PORTRAIT["default"]["path"]



## 租借卡组 → 所属系列 → 卡背 id（按卡组名匹配，返回对应系列卡背；未命中返回 "default"）
func get_back_id_for_deck_name(name: String) -> String:
	if name.is_empty():
		return "default"
	# 你不对劲（先匹配，因为最特殊）
	if name.begins_with("AI·热恋期日常") or "不对劲" in name or "热恋期" in name:
		return "nbd"
	# 围棋
	if name.begins_with("AI·手谈围棋") or "围棋" in name or "手谈" in name:
		return "go"
	# 三约纪元
	if name.begins_with("AI·三约松动") or "三约" in name:
		return "syjy"
	# 沧澜古界（其余 AI 卡组全部归入沧澜）
	return "canglan"

# ============================================================
# 卡背/桌布解锁系统
# ============================================================

## 系列购买计数存储 key
const PACK_COUNT_KEY = "series_pack_counts"

## 获取系列购买计数
func get_series_pack_count(series_id: String) -> int:
	var counts = SaveManager.get_value("player", PACK_COUNT_KEY, {})
	return int(counts.get(series_id, 0))

## 增加系列购买计数（返回 {new_count, unlocked_back, unlocked_cloth}）
func add_series_pack_count(series_id: String) -> Dictionary:
	var counts = SaveManager.get_value("player", PACK_COUNT_KEY, {})
	var old_count = int(counts.get(series_id, 0))
	var new_count = old_count + 1
	counts[series_id] = new_count
	SaveManager.set_value("player", PACK_COUNT_KEY, counts)
	SaveManager.save_to_disk()
	
	var result = {
		"series_id": series_id,
		"old_count": old_count,
		"new_count": new_count,
		"unlocked_back": false,
		"unlocked_cloth": false,
		"back_id": "",
		"cloth_id": ""
	}
	
	# 检查是否解锁卡背（1个）
	if old_count < 1 and new_count >= 1:
		result["unlocked_back"] = true
		result["back_id"] = series_id
	
	# 检查是否解锁桌布（3个）
	if old_count < 3 and new_count >= 3:
		result["unlocked_cloth"] = true
		result["cloth_id"] = series_id
	
	print("[CardManager] 系列 %s 购买计数: %d -> %d, 解锁卡背:%s, 解锁桌布:%s" % [
		series_id, old_count, new_count, result["unlocked_back"], result["unlocked_cloth"]
	])
	return result

## 检查卡背是否解锁
func is_back_unlocked(back_id: String) -> bool:
	if back_id == "default":
		return true
	return get_series_pack_count(back_id) >= 1

## 检查桌布是否解锁
func is_tablecloth_unlocked(cloth_id: String) -> bool:
	if cloth_id == "default":
		return true
	return get_series_pack_count(cloth_id) >= 3

## 获取解锁条件描述
func get_unlock_hint(back_or_cloth_id: String, is_back: bool) -> String:
	if back_or_cloth_id == "default":
		return ""
	var count = get_series_pack_count(back_or_cloth_id)
	var series_name = DECK_BACKS.get(back_or_cloth_id, {}).get("name", back_or_cloth_id)
	if is_back:
		return "购买%s系列卡包解锁 %d/1" % [series_name, count]
	else:
		return "购买%s系列卡包解锁 %d/3" % [series_name, count]

## 获取所有属性及其数量
func get_element_stats() -> Dictionary:
	var cards = get_all_cards()
	var stats := {}
	for card in cards:
		var e = CardManager.get_card_element(card)
		stats[e] = stats.get(e, 0) + 1
	return stats

## 重置新手卡组导入标记（用于重置游戏时允许重新导入）
func reset_starter_import_flag() -> void:
	_starter_imported = false

var _id_counter: int = 0

func _generate_card_id() -> String:
	_id_counter += 1
	var timestamp = Time.get_unix_time_from_system()
	return "CARD_" + str(timestamp) + "_" + str(_id_counter)
