extends RefCounted
class_name IBattleControllerNew

## ============================================================
##  IBattleControllerNew.gd — 统一操作接口
##  AI和玩家都实现这个接口，走完全相同的操作路径
##  BattleGameNew只通过这个接口和Controller通信
## ============================================================

# 当阶段进入时通知Controller
# 玩家实现：显示可操作高亮、等待输入
# AI实现：自动决策，调用game.request_xxx()
func on_phase_enter(phase: int) -> void:
	pass

# 当需要做选择时通知Controller
func on_discard_requested(count: int, callback_id: int, reason: String) -> void:
	pass

func on_deck_search_requested(cards: Array, max_select: int, callback_id: int) -> void:
	pass

func on_chain_requested(callback_id: int, chainable_cards: Array) -> void:
	pass

# 获取视角信息
# 玩家：只能看自己的手牌
# AI：可以看全部（全知视角）
func get_view() -> Dictionary:
	return {}