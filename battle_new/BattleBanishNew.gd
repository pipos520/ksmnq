extends RefCounted
class_name BattleBanishNew

## ============================================================
##  BattleBanishNew.gd — 除外区管理器
## ============================================================

signal banish_changed()

var _cards: Array = []  # BattleCardNew[]

func add(card) -> void:
	_cards.append(card)
	banish_changed.emit()

func remove_at(index: int) -> BattleCardNew:
	if index < 0 or index >= _cards.size():
		return null
	var c = _cards[index]
	_cards.remove_at(index)
	banish_changed.emit()
	return c

func pop_random() -> BattleCardNew:
	if _cards.is_empty():
		return null
	var idx = randi() % _cards.size()
	return remove_at(idx)

func size() -> int:
	return _cards.size()

func is_empty() -> bool:
	return _cards.is_empty()

func get_all() -> Array:
	return _cards.duplicate()

func clear() -> void:
	_cards.clear()
	banish_changed.emit()