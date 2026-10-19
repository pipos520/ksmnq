extends RefCounted
class_name BattleDeck

# ============================================================
#  BattleDeck.gd —— 战斗中的卡组
#  负责洗牌、抽牌、管理卡组剩余卡牌
#  使用 Fisher-Yates 洗牌算法
# ============================================================

# 卡组中的卡牌列表（按顺序，牌顶在索引0）
var _cards: Array = []

# 卡组已空的回调（可选）
signal deck_empty()


# ===== 工厂方法 =====

## 从卡牌ID列表创建卡组（从 CardManager 加载卡牌数据）
static func from_deck(deck_id: String, shuffle_cards: bool = true) -> BattleDeck:
	var deck = BattleDeck.new()
	
	# 获取卡组数据
	var deck_data = CardManager.get_deck(deck_id)
	var card_ids = deck_data.get("cards", [])
	
	# 加载每张卡牌数据
	var all_cards = CardManager.get_all_cards()
	for card_id in card_ids:
		# 查找卡牌完整数据
		var found := false
		for card_data in all_cards:
			# ★ 同时匹配 id 和 template_id，兼容卡牌ID被 add_card 替换后，
			# 牌组仍引用原始模板ID（如 CARD_QP_008）的情况
			if card_data.get("id", "") == card_id or card_data.get("template_id", "") == card_id:
				var battle_card = BattleCard.from_dict(card_data)
				deck._cards.append(battle_card)
				found = true
				break
		if not found:
			print("[BattleDeck]  卡牌ID匹配失败，跳过: ", card_id)
	
	if shuffle_cards:
		deck.shuffle()
	
	print("[BattleDeck] 卡组加载完成: ", deck_data.get("name", "未知"), " (", deck._cards.size(), "张)")
	return deck


## 从完整的卡牌数据数组创建卡组（用于敌方/测试）
static func from_card_list(card_datas: Array, shuffle_cards: bool = true) -> BattleDeck:
	var deck = BattleDeck.new()
	for card_data in card_datas:
		var battle_card = BattleCard.from_dict(card_data)
		deck._cards.append(battle_card)
	
	if shuffle_cards:
		deck.shuffle()
	
	print("[BattleDeck] 卡组创建完成: ", deck._cards.size(), "张")
	return deck


## 从现有的 BattleCard 数组创建卡组（复制）
static func from_battle_cards(cards: Array, shuffle_cards: bool = true) -> BattleDeck:
	var deck = BattleDeck.new()
	for c in cards:
		deck._cards.append(c.clone())
	
	if shuffle_cards:
		deck.shuffle()
	
	return deck


# ===== 核心操作 =====

## 洗牌（Fisher-Yates 算法）
func shuffle() -> void:
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	
	for i in range(_cards.size() - 1, 0, -1):
		var j = rng.randi_range(0, i)
		var temp = _cards[i]
		_cards[i] = _cards[j]
		_cards[j] = temp


## 抽牌（从牌顶抽一张）
func draw() -> BattleCard:
	if _cards.is_empty():
		deck_empty.emit()
		return null
	
	return _cards.pop_front()


## 抽多张牌
func draw_multiple(count: int) -> Array:
	var drawn := []
	for i in range(count):
		var card = draw()
		if card == null:
			break
		drawn.append(card)
	return drawn


## 查看牌顶（不抽走）
func peek_top() -> BattleCard:
	if _cards.is_empty():
		return null
	return _cards[0]


## 查看牌顶多张
func peek_top_multiple(count: int) -> Array:
	var result := []
	for i in range(min(count, _cards.size())):
		result.append(_cards[i])
	return result


## 查看牌底
func peek_bottom() -> BattleCard:
	if _cards.is_empty():
		return null
	return _cards[_cards.size() - 1]


## 将卡牌放回牌顶
func put_on_top(card: BattleCard) -> void:
	_cards.push_front(card)


## 将卡牌放回牌底
func put_on_bottom(card: BattleCard) -> void:
	_cards.append(card)


## 将卡牌随机插入卡组
func insert_random(card: BattleCard) -> void:
	if _cards.is_empty():
		_cards.append(card)
		return
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	var pos = rng.randi_range(0, _cards.size())
	_cards.insert(pos, card)


## 从牌堆中搜索特定的卡牌（按条件）并移除
func search_and_remove(matcher: Callable) -> BattleCard:
	for i in range(_cards.size()):
		if matcher.call(_cards[i]):
			return _cards.pop_at(i)
	return null


## 从牌堆中搜索所有符合条件的卡牌
func search_all(matcher: Callable) -> Array:
	var result := []
	for i in range(_cards.size() - 1, -1, -1):
		if matcher.call(_cards[i]):
			result.append(_cards.pop_at(i))
	return result


# ===== 查询方法 =====

## 获取卡组剩余张数
func size() -> int:
	return _cards.size()


## 是否为空
func is_empty() -> bool:
	return _cards.is_empty()


## 获取所有卡牌（不修改）
func get_all_cards() -> Array:
	return _cards.duplicate()


## 获取所有卡牌ID列表
func get_card_ids() -> Array:
	var ids := []
	for c in _cards:
		ids.append(c.card_id)
	return ids
## 按属性统计
func count_by_element() -> Dictionary:
	var stats := {}
	for c in _cards:
		var e = c.element
		stats[e] = stats.get(e, 0) + 1
	return stats


# ===== 调试 =====

func print_debug() -> void:
	print("[BattleDeck] 卡组剩余: ", _cards.size(), "张")
	for i in range(min(_cards.size(), 5)):
		var c = _cards[i]
		print("  [", i, "] ", c.get_display_name(), " (", c.get_stat_text(), ")")


# ===== 序列化 =====

## 保存当前卡组状态为字典（用于存档）
func serialize() -> Dictionary:
	var data = {
		"card_ids": get_card_ids(),
	}
	return data


## 从字典恢复卡组状态
static func deserialize(data: Dictionary) -> BattleDeck:
	var deck = BattleDeck.new()
	var card_ids = data.get("card_ids", [])
	var all_cards = CardManager.get_all_cards()
	
	for card_id in card_ids:
		for card_data in all_cards:
			# ★ 同时匹配 id 和 template_id
			if card_data.get("id", "") == card_id or card_data.get("template_id", "") == card_id:
				deck._cards.append(BattleCard.from_dict(card_data))
				break
	
	return deck
