extends Node
## ============================================================
##  教程管理器 —— 都市卡牌流新手教程状态机
##  存档字段：tutorial (section) / progress (key, int 0~5)
##   0 = 未开始（首次进入主界面自动触发觉醒剧情）
##   1 = 觉醒完成（老陈给了三张卡，引导去野外探索）
##   2 = 初战完成（打赢巷口混混，引导去制卡工坊）
##   3 = 制卡完成（做出第一张卡，引导去配置牌库）
##   4 = 组卡完成（编好第一套卡组，引导去公会）
##   5 = 公会任务完成（教程全部完成，不再触发）
## ============================================================
const SECTION := "tutorial"
const KEY_PROGRESS := "progress"
const KEY_VERSION := "tutorial_version"
const TUTORIAL_VERSION := 2  # 教程流程版本号，每次大改就+1，旧存档自动重置
const PROGRESS_NONE := 0
const PROGRESS_AWAKENED := 1      # 第一幕：觉醒
const PROGRESS_FIRST_BATTLE := 2  # 第二幕：巷战
const PROGRESS_FIRST_CARD := 3    # 第三幕：制卡
const PROGRESS_FIRST_DECK := 4    # 第四幕：组卡
const PROGRESS_DONE := 5          # 第五幕：公会完成
func _ready() -> void:
	# 不做任何存档写入操作！_ready() 执行顺序不确定，SaveManager 可能还没加载
	# 所有初始化逻辑移到 Main._setup_tutorial_flow 里（call_deferred 保证 SaveManager 已加载）
	pass
## 检查教程版本并重置（由 Main._setup_tutorial_flow 在 call_deferred 中调用，确保 SaveManager 已加载）
func check_version_and_reset() -> void:
	var saved_version = SaveManager.get_value(SECTION, KEY_VERSION, 0)
	if saved_version < TUTORIAL_VERSION:
		print("[教程] 教程版本升级: ", saved_version, " → ", TUTORIAL_VERSION, "，重置进度")
		SaveManager.set_value(SECTION, KEY_PROGRESS, PROGRESS_NONE)
		SaveManager.set_value(SECTION, KEY_VERSION, TUTORIAL_VERSION)
		SaveManager.save_to_disk()
	# 确保存档里至少有一个进度字段
	if SaveManager.get_value(SECTION, KEY_PROGRESS, -1) == -1:
		SaveManager.set_value(SECTION, KEY_PROGRESS, PROGRESS_NONE)
		SaveManager.save_to_disk()
## 当前教程进度
func get_progress() -> int:
	return SaveManager.get_value(SECTION, KEY_PROGRESS, PROGRESS_NONE)

## 是否处于教程中（未全部完成）
func is_in_tutorial() -> bool:
	return get_progress() < PROGRESS_DONE

## 是否已全部完成
func is_done() -> bool:
	return get_progress() >= PROGRESS_DONE

## 设置进度并保存
func set_progress(p: int) -> void:
	var new_p = maxi(PROGRESS_NONE, p)
	SaveManager.set_value(SECTION, KEY_PROGRESS, new_p)
	SaveManager.save_to_disk()
	print("[教程] 进度更新 → ", new_p)

## 完成当前进度 → +1（自动推进到下一幕）
func advance() -> void:
	set_progress(get_progress() + 1)

## 教程已完成的模块标记（解锁哪些系统引导已看过）
func is_awaken_done() -> bool:
	return get_progress() >= PROGRESS_AWAKENED
func is_first_battle_done() -> bool:
	return get_progress() >= PROGRESS_FIRST_BATTLE
func is_first_card_done() -> bool:
	return get_progress() >= PROGRESS_FIRST_CARD
func is_first_deck_done() -> bool:
	return get_progress() >= PROGRESS_FIRST_DECK