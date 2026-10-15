extends RefCounted
class_name BattleFieldNew

## ============================================================
##  BattleFieldNew.gd — 场地管理器
##  封装5槽位场地，提供增删改查
## ============================================================

signal field_changed()

var _slots: Array = []  # BattleCardNew[] or null，固定5个槽
var max_slots: int = 5

func _init():
	for i in range(max_slots):
		_slots.append(null)

func get_slot(index: int):
	if index < 0 or index >= max_slots:
		return null
	return _slots[index]

func set_slot(index: int, card) -> void:
	if index < 0 or index >= max_slots:
		return
	_slots[index] = card
	field_changed.emit()

func get_field_count() -> int:
	var c = 0
	for i in range(max_slots):
		if _slots[i] != null and _slots[i].is_alive():
			c += 1
	return c

func get_attackable_count() -> int:
	var c = 0
	for i in range(max_slots):
		if _slots[i] != null and _slots[i].can_attack():
			c += 1
	return c

func get_empty_slots() -> Array:
	var slots := []
	for i in range(max_slots):
		if _slots[i] == null:
			slots.append(i)
	return slots

func find_card(card) -> int:
	for i in range(max_slots):
		if _slots[i] == card:
			return i
	return -1

func has_living_card() -> bool:
	for i in range(max_slots):
		if _slots[i] != null and _slots[i].is_alive():
			return true
	return false

func get_all() -> Array:
	return _slots.duplicate()

func clear() -> void:
	for i in range(max_slots):
		_slots[i] = null
	field_changed.emit()