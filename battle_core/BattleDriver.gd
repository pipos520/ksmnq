class_name BattleDriver
extends Node

## 战斗驱动核心（UI 无关）——横屏 3D 与竖屏 2D 战斗场景共用
##
## 背景：战斗规则逻辑全部在 BattleManager（UI 无关）中，但「敌方回合的推进节奏」
## （阶段步骤推进 / AI 动作队列消费 / wait 计时 / 攻击与召唤的动画前后回调）
## 曾分别实现在 BattleSceneLegacy 与 battle_new/EnemyAIController 两份里，
## 行为不一致且直接访问 BattleManager 私有成员。
## 本驱动器把该协议收敛为唯一实现，两个战斗场景只保留各自的表现层。
##
## 驱动协议（由 BattleManager 定义，本类唯一执行）：
##   1. 敌方回合 DRAW 完成后 BM 置 _enemy_phase_step="DRAW_DONE"
##      → 本类通知表现层播抽牌动画，并推进到 READY
##   2. READY 完成后 BM 置 "READY_DONE"
##      → 短暂展示后本类推进到 MAIN（BM 构建 ai_action_queue）
##   3. 消费 ai_action_queue：
##      - wait        → 本类计时，到时弹出并执行下一项
##      - enemy_summon → 执行数据层召唤（设 _last_enemy_summon_slot_idx），
##                       发信号请表现层播入场动画，播完后才继续
##      - enemy_attack → 设 _pending_enemy_attack，发信号请表现层播攻击动画，
##                       撞击瞬间回调结算伤害，播完后才继续
##
## 表现层协议（UI 侧只需实现动画，不关心规则）：
##   - 信号 enemy_draw_animation_requested()            → 自发播放，无需回调
##   - 信号 enemy_summon_animation_requested(slot)      → 播完调 report_animation_done()
##   - 信号 enemy_attack_animation_requested(slot, target_slot, is_hero)
##       → 撞击瞬间调 report_attack_impact()，播完调 report_animation_done()
##   - set_ui_busy(bool)：表现层打开长时模态（弃牌/连锁/检索弹窗）时置位，
##     暂停队列消费，关闭时复位（防止动画与弹窗交错）
##
## 注意：本节点必须以 PROCESS_MODE_ALWAYS 运行——表现层动画期间会
## get_tree().paused = true，驱动器必须继续运转才能推进回合。

# ===== 表现层请求信号 =====
## 敌方抽牌：请表现层播放抽牌动画（不阻塞驱动，自发播放即可）
signal enemy_draw_animation_requested()
## 敌方召唤入场：请表现层播放 slot_idx 的入场动画，播完回调 report_animation_done()
signal enemy_summon_animation_requested(slot_idx: int)
## 敌方攻击：请表现层播放攻击动画；撞击瞬间回调 report_attack_impact()，播完回调 report_animation_done()
signal enemy_attack_animation_requested(slot_idx: int, target_slot: int, is_hero: bool)

# ===== 配置 =====
const READY_DELAY: float = 0.5        ## READY_DONE 后的展示停留（秒）
const ANIMATION_TIMEOUT: float = 8.0  ## 表现层动画回调超时保护（秒），防止 UI 漏回调卡死战斗

# ===== 状态 =====
var battle_manager: BattleManager = null

var _ui_busy: bool = false          ## 表现层模态进行中（弃牌/连锁/检索弹窗）
var _awaiting_anim: bool = false    ## 已发动画请求，等待表现层 report_animation_done()
var _awaiting_impact: bool = false  ## 攻击动画中，等待 report_attack_impact() 结算伤害
var _anim_elapsed: float = 0.0      ## 动画等待计时（超时保护用）
var _ai_wait_elapsed: float = 0.0   ## AI 队列 wait 项计时
var _enemy_ready_delay: float = 0.0 ## READY_DONE 停留计时


func _ready() -> void:
	# 表现层动画期间会暂停场景树，驱动器必须照常运转
	process_mode = Node.PROCESS_MODE_ALWAYS


## 绑定战斗逻辑核心（场景仍自行创建 BattleManager 并连接表现信号）
func attach(bm: BattleManager) -> void:
	battle_manager = bm


## 开始战斗（透传 BattleManager.start_battle）
func start_battle(deck_id: String, enemy_name: String = "暗影法师", auto_start: bool = true) -> void:
	battle_manager.start_battle(deck_id, enemy_name, auto_start)


## RPS 结束后启动第一回合（透传 BattleManager.start_first_turn）
func start_first_turn(player_wins_rps: bool) -> void:
	battle_manager.start_first_turn(player_wins_rps)


## 玩家动作入口（透传 BattleManager.do_action）
func do_action(action_type: String, params: Dictionary = {}) -> Dictionary:
	return battle_manager.do_action(action_type, params)


## 回合结束效果动画播完后的弃牌推进（透传 BattleManager.proceed_to_discard_after_end_effects）
func proceed_to_discard_after_end_effects() -> void:
	battle_manager.proceed_to_discard_after_end_effects()


# ===== 表现层回调入口 =====

## 表现层打开/关闭长时模态（弃牌、连锁响应、卡组检索等弹窗）
func set_ui_busy(busy: bool) -> void:
	_ui_busy = busy


## 表现层动画播放完成
func report_animation_done() -> void:
	_awaiting_anim = false
	_anim_elapsed = 0.0
	_ai_wait_elapsed = 0.0
	# 兜底：表现层若漏调 report_attack_impact()，在此结算，防止攻击永远不结算
	if _awaiting_impact:
		_awaiting_impact = false
		_settle_pending_attack()


## 表现层攻击动画撞击瞬间（结算伤害）
func report_attack_impact() -> void:
	if _awaiting_impact:
		_awaiting_impact = false
		_settle_pending_attack()


func _settle_pending_attack() -> void:
	if battle_manager and not battle_manager._pending_enemy_attack.is_empty():
		battle_manager._execute_pending_enemy_attack()


# ===== 驱动主循环 =====

func _process(delta: float) -> void:
	if battle_manager == null:
		return
	# 战斗结束：停止驱动
	if battle_manager.battle_state != BattleManager.State.PLAYING:
		return
	# 等待表现层动画回调（含超时保护）
	if _awaiting_anim:
		_anim_elapsed += delta
		if _anim_elapsed >= ANIMATION_TIMEOUT:
			push_warning("[BattleDriver] 表现层动画回调超时，强制继续（UI 可能漏接信号）")
			report_animation_done()
		return
	# 表现层模态中：暂停队列消费
	if _ui_busy:
		return

	# --- 敌方回合阶段步骤推进 ---
	var step: String = battle_manager._enemy_phase_step
	if step == "DRAW_DONE":
		# 通知表现层播抽牌动画（自发播放，不阻塞），随后推进到 READY
		enemy_draw_animation_requested.emit()
		battle_manager.advance_enemy_phase()  # DRAW_DONE → READY（内部置 READY_DONE）
		_enemy_ready_delay = READY_DELAY
		return
	if step == "READY_DONE":
		# 短暂停留让玩家看到敌方准备完毕，再推进到 MAIN（BM 构建 AI 队列）
		if _enemy_ready_delay > 0.0:
			_enemy_ready_delay -= delta
			return
		battle_manager.advance_enemy_phase()  # READY_DONE → MAIN
		return

	# --- 以下仅在敌方回合执行 ---
	if battle_manager.current_player_index != 1:
		return

	# 待播放的敌方攻击动画（BM 执行 enemy_attack 项时设置）
	var atk: Dictionary = battle_manager._pending_enemy_attack
	if not atk.is_empty():
		_awaiting_anim = true
		_awaiting_impact = true
		_anim_elapsed = 0.0
		if atk.get("type") == "attack_hero":
			enemy_attack_animation_requested.emit(atk.get("slot", -1), -1, true)
		else:
			enemy_attack_animation_requested.emit(atk.get("slot", -1), atk.get("target_slot", -1), false)
		return

	# 待播放的敌方召唤入场动画（BM 执行 enemy_summon 项时设置槽位标记）
	var last_summon: int = battle_manager._last_enemy_summon_slot_idx
	if last_summon >= 0:
		# 消费标记，防止重复触发
		battle_manager._last_enemy_summon_slot_idx = -1
		_awaiting_anim = true
		_anim_elapsed = 0.0
		enemy_summon_animation_requested.emit(last_summon)
		return

	# --- 消费 AI 动作队列 ---
	var queue: Array = battle_manager.ai_action_queue
	if queue.is_empty():
		return
	var front: Dictionary = queue[0]
	if front.get("type", "") == "wait":
		_ai_wait_elapsed += delta
		if _ai_wait_elapsed >= float(front.get("delay", 1.0)):
			_ai_wait_elapsed = 0.0
			queue.pop_front()
			battle_manager._execute_next_ai_action()
		return
	# 非等待动作：直接执行（summon/attack 项会在下一步转为动画请求）
	battle_manager._execute_next_ai_action()
