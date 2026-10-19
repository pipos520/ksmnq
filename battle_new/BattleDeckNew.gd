extends RefCounted
class_name BattleDeckNew

## ============================================================
##  BattleDeckNew.gd — 战斗中的卡组（纯数据）
##  负责洗牌、抽牌、管理卡组剩余卡牌
##  使用 Fisher-Yates 洗牌算法
## ============================================================

var _cards: Array = []  # BattleCardNew数组，牌顶在索引0

signal deck_empty()


# ===== 工厂方法 =====

static func from_deck(deck_id: String, shuffle_cards: bool = true) -> BattleDeckNew:
	var deck = BattleDeckNew.new()
	var deck_data = CardManager.get_deck(deck_id)
	var card_ids = deck_data.get("cards", [])
	var all_cards = CardManager.get_all_cards()
	for card_id in card_ids:
		var found := false
		for card_data in all_cards:
			if card_data.get("id", "") == card_id or card_data.get("template_id", "") == card_id:
				deck._cards.append(BattleCardNew.from_dict(card_data))
				found = true
				break
		if not found:
			print("[BattleDeckNew]  卡牌ID匹配失败，跳过: ", card_id)
	if shuffle_cards:
		deck.shuffle()
	print("[BattleDeckNew] 卡组加载: ", deck_data.get("name", "未知"), " (", deck._cards.size(), "张)")
	return deck


static func from_card_list(card_datas: Array, shuffle_cards: bool = true) -> BattleDeckNew:
	var deck = BattleDeckNew.new()
	for card_data in card_datas:
		deck._cards.append(BattleCardNew.from_dict(card_data))
	if shuffle_cards:
		deck.shuffle()
	print("[BattleDeckNew] 卡组创建: ", deck._cards.size(), "张")
	return deck


static func from_battle_cards(cards: Array, shuffle_cards: bool = true) -> BattleDeckNew:
	var deck = BattleDeckNew.new()
	for c in cards:
		deck._cards.append(c.clone())
	if shuffle_cards:
		deck.shuffle()
	return deck


# ===== 核心操作 =====

func shuffle() -> void:
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	for i in range(_cards.size() - 1, 0, -1):
		var j = rng.randi_range(0, i)
		var temp = _cards[i]
		_cards[i] = _cards[j]
		_cards[j] = temp

func draw() -> BattleCardNew:
	if _cards.is_empty():
		deck_empty.emit()
		return null
	return _cards.pop_front()

func draw_multiple(count: int) -> Array:
	var drawn := []
	for i in range(count):
		var card = draw()
		if card == null:
			break
		drawn.append(card)
	return drawn

func peek_top() -> BattleCardNew:
	return _cards[0] if not _cards.is_empty() else null

func peek_top_multiple(count: int) -> Array:
	var result := []
	for i in range(min(count, _cards.size())):
		result.append(_cards[i])
	return result

func put_on_top(card: BattleCardNew) -> void:
	_cards.push_front(card)

func put_on_bottom(card: BattleCardNew) -> void:
	_cards.append(card)

func insert_random(card: BattleCardNew) -> void:
	if _cards.is_empty():
		_cards.append(card)
		return
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	_cards.insert(rng.randi_range(0, _cards.size()), card)

func search_and_remove(matcher: Callable) -> BattleCardNew:
	for i in range(_cards.size()):
		if matcher.call(_cards[i]):
			return _cards.pop_at(i)
	return null

func search_all(matcher: Callable) -> Array:
	var result := []
	for i in range(_cards.size() - 1, -1, -1):
		if matcher.call(_cards[i]):
			result.append(_cards.pop_at(i))
	return result


# ===== 查询 =====
func size() -> int:
	return _cards.size()

func is_empty() -> bool:
	return _cards.is_empty()

func get_all_cards() -> Array:
	return _cards.duplicate()

func get_card_ids() -> Array:
	var ids := []
	for c in _cards:
		ids.append(c.card_id)
	return ids

func count_by_element() -> Dictionary:
	var stats := {}
	for c in _cards:
		var e = c.element
		stats[e] = stats.get(e, 0) + 1
	return stats