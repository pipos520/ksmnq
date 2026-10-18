extends Node

# 卡牌桥接器：游戏端(ksmnqsp) ↔ 交易端 的本地文件交换
# 退出/挂后台时全量导出卡牌，进入时导入交易回传的卡牌

const SHARED_DIR := "/storage/emulated/0/Documents/CardSim/"
const GAME_TO_TRADE := SHARED_DIR + "game_to_trade.json"
const TRADE_TO_GAME := SHARED_DIR + "trade_to_game.json"

func _ready():
	_ensure_dir()
	_import_from_trade()

func _notification(what):
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_CLOSE_REQUEST:
			_export_to_trade()

func _ensure_dir():
	if not DirAccess.dir_exists_absolute(SHARED_DIR):
		DirAccess.make_dir_recursive_absolute(SHARED_DIR)

# === 导出：游戏端所有卡牌 → game_to_trade.json ===
func _export_to_trade():
	if not CardManager:
		return
	var cards: Array = CardManager.get_all_cards()
	var data := {"cards": cards, "export_time": Time.get_unix_time_from_system()}
	var file := FileAccess.open(GAME_TO_TRADE, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()
		print("[CardBridge] 导出 ", cards.size(), " 张卡牌")

# === 导入：trade_to_game.json → 加入库存 ===
func _import_from_trade():
	if not FileAccess.file_exists(TRADE_TO_GAME):
		return
	var file := FileAccess.open(TRADE_TO_GAME, FileAccess.READ)
	if not file:
		return
	var json_str := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(json_str) != OK:
		return
	var data = json.data
	if not data is Dictionary or not data.has("cards"):
		return
	var cards_arr: Array = data["cards"]
	var imported := 0
	for card_dict in cards_arr:
		if not card_dict is Dictionary:
			continue
		CardManager.add_card(card_dict)
		imported += 1
	if imported > 0:
		print("[CardBridge] 从交易端导入 ", imported, " 张新卡牌")
	DirAccess.remove_absolute(TRADE_TO_GAME)