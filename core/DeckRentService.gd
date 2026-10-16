class_name DeckRentService

## ============================================================
##  DeckRentService — 租借卡组业务逻辑（纯静态方法）
##  依赖 SaveManager autoload
## ============================================================

const RENTED_DECK_MAX_DURABILITY := 10
const RENT_COST_GOLD := 100
const RENT_DUR_COST_EXPLORE := 3
const RENT_DUR_COST_DUEL := 1

## 当前携带的租借卡组（运行时状态）
static var current_rented_deck_id: String = ""
static var current_rented_deck_name: String = ""


static func get_all_rented_decks() -> Dictionary:
	return SaveManager.get_value("player", "rented_decks", {})


## 租借一套决斗场AI卡组（同名重复租借=耐久叠加）
## 返回 {"ok":bool, "id":String, "durability":int, "reason":String}
static func rent_deck(source_deck_data: Dictionary) -> Dictionary:
	var dname = source_deck_data.get("name", "租借卡组")
	var card_datas = source_deck_data.get("card_datas", [])
	if card_datas.is_empty():
		return {"ok": false, "id": "", "durability": 0, "reason": "卡组内容为空"}
	var rented = get_all_rented_decks()
	var cids := []
	for c in card_datas:
		cids.append(c.get("id", c.get("name", "")))
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


## 扣租借卡组耐久，归0则删除。返回剩余耐久
static func consume_rented_durability(rid: String, amount: int) -> int:
	var rented = get_all_rented_decks()
	if not rented.has(rid): return -1
	var dur = int(rented[rid].get("durability", 0)) - amount
	var left = dur if dur > 0 else 0
	if left <= 0:
		rented.erase(rid)
		if current_rented_deck_id == rid:
			current_rented_deck_id = ""
			current_rented_deck_name = ""
		print("[租借] 卡组耐久归0，已删除: ", rid)
	else:
		rented[rid]["durability"] = left
		print("[租借] 卡组耐久: ", rid, " -", amount, " 剩", left)
	SaveManager.set_value("player", "rented_decks", rented)
	SaveManager.save_to_disk()
	return left


static func get_rented_deck(rid: String) -> Dictionary:
	return get_all_rented_decks().get(rid, {})
