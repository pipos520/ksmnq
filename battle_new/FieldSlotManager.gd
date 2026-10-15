extends Node
class_name FieldSlotManager

## 场地卡位管理器
## 管理己方5个场地卡位的卡牌状态、显示更新、空位查找
## 由BattleScene3D创建并挂载，通过setup()注入依赖

# === 依赖注入 ===
var _scene: Node3D = null
var _player_slots: Array = []      # 5个己方场地Node3D

# === 场地卡牌数据 ===
# _field_cards[i] 存放BattleCard3D节点引用（null=空位）
var _field_cards: Array = [null, null, null, null, null]
# _field_card_datas[i] 存放卡牌原始数据
var _field_card_datas: Array = [null, null, null, null, null]


## 初始化，注入依赖
func setup(scene: Node3D, player_slots: Array) -> void:
	_scene = scene
	_player_slots = player_slots


## 查找第一个空位，返回索引，-1=已满
func find_empty_slot() -> int:
	for i in range(5):
		if _field_cards[i] == null:
			return i
	return -1


## 卡牌入驻卡位（卡牌已飞到目标位置后调用）
func place_card(slot_idx: int, card_node: Node, card_data: Variant) -> void:
	if slot_idx < 0 or slot_idx >= 5:
		return
	# 先清除旧的同名节点（防止重叠）
	var old = _player_slots[slot_idx].get_node_or_null("PlayerCard")
	if old and old != card_node:
		old.queue_free()
	_field_cards[slot_idx] = card_node
	_field_card_datas[slot_idx] = card_data
	# reparent到卡位节点下
	if _player_slots[slot_idx]:
		card_node.reparent(_player_slots[slot_idx], true)
		card_node.name = "PlayerCard"  # 统一命名，方便查找
		card_node.position = Vector3(0, 0.15, 0.0)  # 浮在卡位表面上方
	# 翻为正面
	if card_node.has_method("set_face_up"):
		card_node.set_face_up()
	print("[FieldSlotManager] 卡牌入驻卡位 %d: %s" % [slot_idx, card_data.get("name", "") if card_data is Dictionary else "?"])


## 获取卡位上的卡牌节点
func get_card_at(slot_idx: int) -> Node:
	if slot_idx < 0 or slot_idx >= 5:
		return null
	return _field_cards[slot_idx]


## 获取卡位上的卡牌数据
func get_card_data_at(slot_idx: int) -> Dictionary:
	if slot_idx < 0 or slot_idx >= 5:
		return {}
	var d = _field_card_datas[slot_idx]
	return d if d != null else {}


## 卡牌离开卡位（送墓/弹回手牌等）
func remove_card(slot_idx: int) -> Node:
	if slot_idx < 0 or slot_idx >= 5:
		return null
	var card = _field_cards[slot_idx]
	_field_cards[slot_idx] = null
	_field_card_datas[slot_idx] = null
	return card


## 场地卡牌数量
func get_field_count() -> int:
	var count = 0
	for c in _field_cards:
		if c != null:
			count += 1
	return count


## 场地是否已满
func is_full() -> bool:
	return find_empty_slot() == -1


## 获取所有场地卡牌数据（用于战斗系统同步）
func get_all_field_datas() -> Array:
	var result = []
	for i in range(5):
		if _field_card_datas[i] != null:
			result.append(_field_card_datas[i])
		else:
			result.append(null)
	return result