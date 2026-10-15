extends RefCounted
class_name BattleHandNew

## ============================================================
##  BattleHandNew.gd — 手牌管理器
##  封装手牌数组，提供增删改查
## ============================================================

signal hand_changed()

var _cards: Array = []  # BattleCardNew[]

func add(card) -> void:
	_cards.append(card)
	hand_changed.emit()

func add_at(card, index: int) -> void:
	_cards.insert(index, card)
	hand_changed.emit()

func remove_at(index: int) -> BattleCardNew:
	if index < 0 or index >= _cards.size():
		return null
	var c = _cards[index]
	_cards.remove_at(index)
	hand_changed.emit()
	return c

func get_card(index: int) -> BattleCardNew:
	if index < 0 or index >= _cards.size():
		return null
	return _cards[index]

func size() -> int:
	return _cards.size()

func is_empty() -> bool:
	return _cards.is_empty()

func has_card(card_id: String) -> bool:
	for c in _cards:
		if c.card_id == card_id:
			return true
	return false

func find(card) -> int:
	for i in range(_cards.size()):
		if _cards[i] == card:
			return i
	return -1

func get_all() -> Array:
	return _cards.duplicate()

func clear() -> void:
	_cards.clear()
	hand_changed.emit()

func get_summonable_indices(max_energy: int) -> Array:
	var indices := []
	for i in range(_cards.size()):
		if _cards[i].base_cost <= max_energy:
			indices.append(i)
	return indices