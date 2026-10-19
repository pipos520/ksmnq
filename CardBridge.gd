extends Node

# 卡牌桥接器：游戏端(ksmnqsp) ↔ 交易端 的本地文件交换
# 退出/挂后台时全量导出卡牌，进入时导入交易回传的卡牌

## Android 端走公共存储目录；桌面端（Windows/Linux/macOS）没有该路径的写权限，
## 退回 user:// 目录，避免启动时 "Could not create directory: '/storage'" 报错。
const SHARED_DIR_ANDROID := "/storage/emulated/0/Documents/CardSim/"

var _shared_dir: String = ""
var _game_to_trade: String = ""
var _trade_to_game: String = ""

func _resolve_paths() -> void:
	if _shared_dir != "":
		return
	_shared_dir = SHARED_DIR_ANDROID if OS.get_name() == "Android" else "user://CardBridge/"
	_game_to_trade = _shared_dir.path_join("game_to_trade.json")
	_trade_to_game = _shared_dir.path_join("trade_to_game.json")

func _ready():
	_resolve_paths()
	_ensure_dir()
	_import_from_trade()

func _notification(what):
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_CLOSE_REQUEST:
			_export_to_trade()

func _ensure_dir():
	_resolve_paths()
	if not DirAccess.dir_exists_absolute(_shared_dir):
		DirAccess.make_dir_recursive_absolute(_shared_dir)

# === 导出：游戏端所有卡牌 → game_to_trade.json ===
func _export_to_trade():
	if not CardManager:
		return
	var cards: Array = CardManager.get_all_cards()
	var data := {"cards": cards, "export_time": Time.get_unix_time_from_system()}
	var file := FileAccess.open(_game_to_trade, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()
		print("[CardBridge] 导出 ", cards.size(), " 张卡牌")

# === 导入：trade_to_game.json → 加入库存 ===
func _import_from_trade():
	if not FileAccess.file_exists(_trade_to_game):
		return
	var file := FileAccess.open(_trade_to_game, FileAccess.READ)
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
	DirAccess.remove_absolute(_trade_to_game)