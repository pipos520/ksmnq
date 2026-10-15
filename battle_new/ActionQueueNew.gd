extends RefCounted
class_name ActionQueueNew

## ============================================================
##  ActionQueueNew.gd — 操作序列化队列
##  所有游戏操作排队执行，解决异步动画+连锁插入问题
## ============================================================

enum ActionType {
	SUMMON,           # 召唤
	ATTACK_CARD,      # 攻击卡牌
	ATTACK_HERO,      # 直击英雄
	DRAW_CARD,        # 抽牌
	DISCARD,          # 弃牌
	DESTROY,          # 破坏
	BANISH,           # 除外
	HEAL,             # 治疗
	DAMAGE,           # 伤害
	BUFF,             # 增益
	BOUNCE,           # 弹回
	SPECIAL_SUMMON,   # 特殊召唤
	SEND_TO_GRAVE,    # 送墓
	CONTROL_CHANGE,   # 控制权转移
	END_PHASE,        # 结束阶段
	CUSTOM,           # 自定义（效果执行等）
}

# 队列元素结构: {type: ActionType, params: Dictionary, source: String}
var _queue: Array = []
var _executing: bool = false
var _paused: bool = false

# 信号：每个Action执行前发，UI可监听播动画
signal before_action(action: Dictionary)
signal after_action(action: Dictionary)
signal queue_emptied()


func push(action: Dictionary) -> void:
	_queue.append(action)
	if not _executing:
		process_next()

func push_front(action: Dictionary) -> void:
	_queue.insert(0, action)
	if not _executing:
		process_next()

func process_next() -> void:
	if _paused:
		return
	if _queue.is_empty():
		_executing = false
		queue_emptied.emit()
		return
	
	_executing = true
	var action = _queue.pop_front()
	before_action.emit(action)
	
	# 执行action（由BattleGame注册的处理函数决定）
	# 处理完后会再次调 process_next()
	# 如果action需要等动画，UI调 resume() 继续
	# 如果不需要动画，直接继续
	after_action.emit(action)
	process_next()

func pause() -> void:
	_paused = true

func resume() -> void:
	_paused = false
	process_next()

func clear() -> void:
	_queue.clear()
	_executing = false
	_paused = false

func is_empty() -> bool:
	return _queue.is_empty()

func size() -> int:
	return _queue.size()

func is_paused() -> bool:
	return _paused