extends Node

## ============================================================
##  仓库管理器 —— 管理素材/卡牌的库存
##  所有增减操作自动调用 SaveManager 持久化
## ============================================================

const STORAGE_SECTION := "warehouse"

# ---------- 素材库存 ----------

## 获取素材库存（Dictionary: { "F01": 数量, "M01": 数量, ... }）
func get_materials() -> Dictionary:
	return SaveManager.get_value(STORAGE_SECTION, "materials", {})

## 设置素材库存（直接覆盖）
func set_materials(data: Dictionary) -> void:
	SaveManager.set_value(STORAGE_SECTION, "materials", data)
	SaveManager.save_to_disk()

## 获取某种素材的数量
func get_material_count(material_id: String) -> int:
	var mats = get_materials()
	return mats.get(material_id, 0)

## 添加素材（数量为正数）
func add_material(material_id: String, amount: int) -> void:
	if amount <= 0:
		return
	var mats = get_materials()
	var current = mats.get(material_id, 0)
	mats[material_id] = current + amount
	SaveManager.set_value(STORAGE_SECTION, "materials", mats)
	SaveManager.save_to_disk()
	print("[仓库] 添加 ", material_id, " x", amount, "，当前持有：", mats[material_id])

## 消耗素材（数量为正数），返回是否成功
func consume_material(material_id: String, amount: int) -> bool:
	if amount <= 0:
		return false
	var mats = get_materials()
	var current = mats.get(material_id, 0)
	if current < amount:
		print("[仓库] 素材不足：", material_id, " 需要 ", amount, "，持有 ", current)
		return false
	mats[material_id] = current - amount
	SaveManager.set_value(STORAGE_SECTION, "materials", mats)
	SaveManager.save_to_disk()
	print("[仓库] 消耗 ", material_id, " x", amount, "，剩余：", mats[material_id])
	return true

# ---------- 卡基库存 ----------

## 获取卡基库存（Dictionary: { "CB_xxx": {...}, ... }）
func get_card_bases() -> Dictionary:
	return SaveManager.get_value(STORAGE_SECTION, "card_bases", {})

## 添加卡基
func add_card_base(data: Dictionary) -> void:
	var bases = get_card_bases()
	var cid = data.get("id", "")
	if cid == "":
		return
	bases[cid] = data
	SaveManager.set_value(STORAGE_SECTION, "card_bases", bases)
	SaveManager.save_to_disk()
	print("[仓库] 添加卡基 ", cid)

## 删除卡基
func remove_card_base(card_base_id: String) -> bool:
	var bases = get_card_bases()
	if not bases.has(card_base_id):
		return false
	bases.erase(card_base_id)
	SaveManager.set_value(STORAGE_SECTION, "card_bases", bases)
	SaveManager.save_to_disk()
	return true

# ---------- 初始化 ----------

func _ready() -> void:
	# 延迟一帧等 Global 和 SaveManager 都准备好
	call_deferred("_init_warehouse")

func _init_warehouse() -> void:
	# 初始化金币（首次运行）
	var gold = SaveManager.get_value("player", "gold", -1)
	if gold == -1:
		SaveManager.set_value("player", "gold", 100)
		SaveManager.save_to_disk()
		print("[仓库] 初始金币已发放：100")


# ---------- 卡墨库存 ----------

## 获取卡墨库存（Array: [{...}, {...}]）
func get_ink_inventory() -> Array:
	return SaveManager.get_value(STORAGE_SECTION, "ink_inventory", [])

## 添加卡墨
func add_ink(data: Dictionary) -> void:
	var inks = get_ink_inventory()
	inks.append(data)
	SaveManager.set_value(STORAGE_SECTION, "ink_inventory", inks)
	SaveManager.save_to_disk()
	print("[仓库] 添加卡墨 ", data.get("id", ""), " - ", data.get("name", ""))

## 设置卡墨库存（直接覆盖）
func set_ink_inventory(data: Array) -> void:
	SaveManager.set_value(STORAGE_SECTION, "ink_inventory", data)
	SaveManager.save_to_disk()

## 删除卡墨（按id）
func remove_ink(ink_id: String) -> bool:
	var inks = get_ink_inventory()
	for i in range(inks.size()):
		if inks[i].get("id", "") == ink_id:
			inks.remove_at(i)
			SaveManager.set_value(STORAGE_SECTION, "ink_inventory", inks)
			SaveManager.save_to_disk()
			return true
	return false

# ---------- 辅材库存 ----------

## 获取辅材库存（Dictionary: { "AU01": 数量, "AU02": 数量, ... }）
func get_aux_items() -> Dictionary:
	return SaveManager.get_value(STORAGE_SECTION, "aux_items", {})

## 获取某种辅材的数量
func get_aux_count(aux_id: String) -> int:
	var aux = get_aux_items()
	return aux.get(aux_id, 0)

## 添加辅材
func add_aux(aux_id: String, amount: int) -> void:
	if amount <= 0:
		return
	var aux = get_aux_items()
	var current = aux.get(aux_id, 0)
	aux[aux_id] = current + amount
	SaveManager.set_value(STORAGE_SECTION, "aux_items", aux)
	SaveManager.save_to_disk()
	print("[仓库] 添加辅材 ", aux_id, " x", amount, "，当前持有：", aux[aux_id])

## 消耗辅材，返回是否成功
func consume_aux(aux_id: String, amount: int) -> bool:
	if amount <= 0:
		return false
	var aux = get_aux_items()
	var current = aux.get(aux_id, 0)
	if current < amount:
		print("[仓库] 辅材不足：", aux_id, " 需要 ", amount, "，持有 ", current)
		return false
	aux[aux_id] = current - amount
	SaveManager.set_value(STORAGE_SECTION, "aux_items", aux)
	SaveManager.save_to_disk()
	print("[仓库] 消耗辅材 ", aux_id, " x", amount, "，剩余：", aux[aux_id])
	return true
# ---------- 卡基兼容名（旧存档无name字段时从素材重建）----------
func get_card_base_display_name(data: Dictionary) -> String:
	var name = data.get("name", "")
	if name != "":
		return name
	# 旧存档兼容：从 materials 拼接中文名
	var mats = data.get("materials", {})
	var parts := []
	for cat in mats.keys():
		for mid in mats[cat].keys():
			var mat = Global.get_material_by_id(mid)
			if not mat.is_empty():
				var nm = mat.get("name", mid)
				var _short = nm.substr(0, mini(nm.length(), 2))
				if not _short in parts:
					parts.append(_short)
	name = "卡基·"
	if parts.size() <= 3:
		name += "+".join(parts)
	else:
		name += "+".join(parts.slice(0, 3)) + "等"
	if name == "卡基·":
		name = data.get("id", "未知卡基")
	return name
