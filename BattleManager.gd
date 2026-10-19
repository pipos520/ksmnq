extends RefCounted
class_name BattleManager

# ============================================================
#  BattleManager.gd —— 战斗核心管理器
#  回合流程：抽牌 → 准备 → 主要 → 战斗 → 结束
#  开局双方5张手牌，3点能量
# ============================================================

# ===== 阶段与状态枚举 =====
enum Phase {
	NONE,     # 未开始
	DRAW,     # 抽牌阶段
	READY,    # 准备阶段
	MAIN,     # 主要阶段
	BATTLE,   # 战斗阶段
	END,      # 结束阶段
	DISCARD,  # 弃牌阶段（手牌超限时）
}

enum State {
	PLAYING,  # 进行中
	WON,      # 己方胜利
	LOST,     # 己方失败
	DRAW,     # 平局
}

# ===== 信号 =====
signal phase_changed(phase: Phase, current_player_index: int)
signal turn_changed(turn_count: int)
signal battle_state_changed(state: State)
signal action_result(action_type: String, success: bool, data: Dictionary)
signal effect_triggered(action_type: String, value: int, is_player_side: bool, source_slot: int, desc: String)
signal deck_search_requested(cards: Array, max_select: int, callback_id: int)  # 请求UI显示卡组检索弹窗
signal discard_requested(count: int, callback_id: int, reason: String)  # 请求UI显示弃牌选择弹窗
signal discard_animation_requested(callback_id: int, is_player_side: bool, discard_indices: Array)  # 弃牌后请求UI播放飞入墓地特效（动画结束后调 _on_discard_animation_finished）
signal chain_response_requested(callback_id: int)  # 请求玩家连锁响应（超时自动放弃）
signal chain_built(chain_count: int)  # 连锁构建完成，开始结算
signal chain_resolved(link_id: int)  # 单个连锁链结算完成
signal card_effect_activated(card_name: String, effect_desc: String, action_type: String, target_id: String, value: int, target_card_name: String, source_slot: int, is_player_side: bool, target_slot: int, target_is_player: bool, full_effect: Dictionary)  # 效果发动通知（飘窗用+画线用）
signal effect_line_fromto(from_slot: int, from_is_player: bool, to_slot: int, to_is_player: bool, action_type: String)  # 逐卡精确画线（群体效果每张卡发一次）
signal element_boost_triggered(boost_type: String, atk_elem: String, def_elem: String, from_value: int, to_value: int, is_player_side: bool, source_slot: int)  # 元素加成/克制飘字
signal poison_tick_triggered(is_player_side: bool, source_slot: int, damage: int, stacks: int)  # 中毒回合结算飘字（绿色毒系反馈）
signal end_phase_effects_pending_discard(need_discard: int)  # 回合结束效果已发完（数据层），通知UI等非飘窗动画播完后再推进弃牌阶段

# ===== 玩家引用 =====
var player_self: BattlePlayer     # 己方（索引0）
var player_opponent: BattlePlayer  # 敌方（索引1）

# 卡组检索回调映射
var _search_callbacks: Dictionary = {}  # callback_id -> {func: Callable, player: BattlePlayer, from_deck: bool}
var _search_callback_counter: int = 0
var _discard_callbacks: Dictionary = {}  # callback_id -> {func: Callable, player: BattlePlayer, count: int}
var _discard_callback_counter: int = 0

# ===== 回合状态 =====
var current_player_index: int = 0  # 0=己方, 1=敌方
var current_phase: Phase = Phase.NONE
var turn_count: int = 0
var battle_state: State = State.PLAYING

# 先手标记
var _is_first_turn: bool = true
# 已攻击的卡牌列表（当前战斗阶段）
var _attacked_this_battle: Array = []

# 敌方AI队列（用于分步执行）
var ai_action_queue: Array = []
var ai_phase_completed: bool = false
# ===== 回合状态 =====
# 敌方召唤/攻击动画状态
var _last_enemy_summon_slot_idx: int = -1
var _pending_enemy_attack: Dictionary = {}
var _enemy_phase_step: String = ""  # 敌方阶段步骤: "", "DRAW_DONE", "READY_DONE"
# 触发器注册表（用于亡语等）
# 格式: [ { "owner": BattlePlayer, "card": BattleCard, "trigger": "on_destroy", "effect_data": {...} } ]
var _trigger_registry: Array = []

# ===== 连锁系统 =====
var chain_stack: Array = []  # 连锁栈，格式: [{owner, card, effect, slot, chain_id}]
var chain_counter: int = 0  # 连锁编号计数器
const MAX_CHAIN_LENGTH := 10  # 连锁最大长度（防死循环）
var _chain_resolving: bool = false  # 正在结算连锁中
var _chain_response_callback_id: int = -1  # 当前等待响应的连锁ID
var _chain_timer: float = 0.0  # 连锁响应计时
var _ignore_chain: bool = false  # 临时忽略连锁（结算中不触发新连锁）

# ===== 约束系统 =====
var _constraint_used_once_per_turn: Dictionary = {}  # "card_id" -> bool（CO01: 一回合一次）
var _constraint_used_once_per_game: Dictionary = {}  # "card_id" -> bool（CO02: 一局一次）
var _constraint_effect_count: int = 0  # 效果发动次数计数（用于CO14）
var _constraint_self_damage_pending: int = 0  # 待处理的CO12自伤

# ===== AI 智能决策（全知视角 + 连招攒牌 + 卖血） =====
var _ai_omniscient: bool = true            # 全知视角：AI可查看玩家手牌/牌库做战略决策
var _ai_combo_pieces: Array = []           # 连招关键组件识别表（id -> 用途），每回合评估
var _ai_hold_combo_ids: Dictionary = {}    # 手牌中需要"攒着"的卡索引 -> 用途说明
var _ai_blood_threshold: float = 0.25      # 卖血阈值：血量高于此比例时倾向用血换节奏
var _ai_last_threat_analysis: Dictionary = {}  # 最近一次威胁评估缓存
var _ai_strategy: String = "balanced"      # 当前战略：balanced / aggro(抢血) / control(控场) / combo(攒连招)

# ===== AI 牌库预读 + 连招规划（预读牌库顺序，设计启动回合） =====
var _ai_lookahead_depth: int = 5           # 牌库预读深度（接下来几回合会抽到什么）
var _ai_lookahead_cards: Array = []        # 本回合牌库顶预读缓存（BattleCard 列表，按抽牌顺序）
var _ai_combo_plan_active: bool = false    # 是否有进行中的连招计划
var _ai_combo_plan_wait_turns: int = 0     # 还需等待几回合（启动回合剩余）
var _ai_combo_plan_key_hand_idx: int = -1  # 计划中手牌关键组件的索引（攒着等配套）
var _ai_combo_plan_partner_desc: String = ""  # 等待的配套牌描述（日志用）

# ===== 初始化 =====

func _init():
	pass

## 开始战斗
func start_battle(deck_id: String, enemy_name: String = "暗影法师", auto_start: bool = true) -> void:
	var deck_data = CardManager.get_deck(deck_id)
	var card_ids = deck_data.get("cards", [])
	var card_datas = _load_card_datas_by_ids(card_ids)
	
	# 创建己方（先手）
	player_self = BattlePlayer.new()
	player_self.player_name = "卡师"
	player_self.max_energy = 3
	player_self.energy = 3
	# 按公会称号等级设置血量（低级脆皮，高级耐打）
	var guild_max_hp = PlayerManager.get_guild_max_hp()
	player_self.max_hp = guild_max_hp
	# 爬塔模式：使用持久HP
	if Global.current_run_player_hp > 0:
		player_self.hp = Global.current_run_player_hp
	else:
		player_self.hp = guild_max_hp
	player_self.init_from_deck(deck_id, false, true)
	# ★ 兜底：未选卡组（deck_id 为空）或卡组已失效时，from_deck 会加载出 0 张，
	#   玩家开局无手牌直接被判负。这里退回「全部卡牌」，与 BattleScene3D 的显示逻辑一致。
	if player_self.deck == null or player_self.deck.size() == 0:
		var fallback_cards := CardManager.get_all_cards().duplicate(true)
		if fallback_cards.size() > 0:
			player_self.init_from_card_datas(fallback_cards, false, true)
			print("[BattleManager]  卡组ID无效(\"%s\")，已回退为全部卡牌: %d张" % [deck_id, fallback_cards.size()])
	# 如果是租借卡组，重新用 card_datas 初始化
	if Global.current_rented_deck_id != "":
		var rd = Global.get_rented_deck(Global.current_rented_deck_id)
		if not rd.is_empty() and rd.get("card_datas", []).size() > 0:
			player_self.init_from_card_datas(rd.get("card_datas", []), false, true)
			print("[BattleManager] 使用租借卡组: ", rd.get("name", ""), " ", rd.get("card_datas", []).size(), "张")
	
	# 检查是否有自定义敌人数据
	var enemy_data = Global.current_enemy_data
	if enemy_data.size() > 0 and (enemy_data.get("deck", []).size() > 0 or enemy_data.get("card_datas", []).size() > 0):
		# 使用自定义敌人卡组
		var enemy_name_custom = enemy_data.get("name", enemy_name)
		var enemy_hp = enemy_data.get("hp", 100)
		var enemy_max_hp = enemy_data.get("max_hp", 100)
		var enemy_energy = enemy_data.get("energy", 3)
		var enemy_max_energy = enemy_data.get("max_energy", 3)
		
		var enemy_card_datas := []
		# 优先使用预解析的完整卡牌数据（决斗场/虚拟匹配用）
		if enemy_data.get("card_datas", []).size() > 0:
			enemy_card_datas = enemy_data.get("card_datas", [])
		else:
			# 解析卡牌模板ID列表为完整卡牌数据（野怪/BOSS用）
			var deck_template_ids = enemy_data.get("deck", [])
			for template_id in deck_template_ids:
				var template = Global.get_enemy_card_template(template_id)
				if template.size() > 0:
					enemy_card_datas.append(template.duplicate(true))
				else:
					# 模板不存在时创建一个默认卡牌
					enemy_card_datas.append({
						"name": "未知卡牌", "cost": 1, "atk": 1, "hp": 1,
						"element": "无", "fields": [], "quality": "标准", "star": 1
					})
		
		# 创建敌方（后手，使用自定义卡组）
		player_opponent = BattlePlayer.new()
		player_opponent.player_name = enemy_name_custom
		player_opponent.max_energy = enemy_max_energy
		player_opponent.energy = enemy_energy
		player_opponent.hp = enemy_hp
		player_opponent.max_hp = enemy_max_hp
		player_opponent.init_from_card_datas(enemy_card_datas, true, false)
		
		# 注意：不清空 current_enemy_data，保留到战斗结束用于结算弹窗
		# BattleScene._go_back_to_map 中会清空
		
		if OS.is_debug_build():
			print("[战斗] 使用自定义敌人: ", enemy_name_custom, " HP:", enemy_hp, " 卡组:", enemy_card_datas.size(), "张")
	else:
		# 创建敌方（后手）
		# ★ 从「服务器卡组池 + 本地卡组」随机选一套作为AI对手卡组，避免永远打镜像
		var ai_card_datas := _pick_ai_deck(card_datas, deck_id)
		player_opponent = BattlePlayer.new()
		player_opponent.player_name = enemy_name
		player_opponent.max_energy = 3
		player_opponent.energy = 3
		# 普通对练对手使用固定默认血量
		player_opponent.max_hp = 100
		player_opponent.hp = 100
		player_opponent.init_from_card_datas(ai_card_datas, true, false)
	
	# 双方初始抽5张牌
	player_self.init_draw(5)
	player_opponent.init_draw(5)
	
	# ★ 重置连锁系统状态（防止上次战斗异常退出后残留）
	chain_stack.clear()
	chain_counter = 0
	_chain_resolving = false
	_ignore_chain = false
	_chain_response_callback_id = -1
	_chain_timer = 0.0
	
	# 连接玩家新信号
	player_self.card_summoned.connect(_on_player_card_summoned)
	player_opponent.card_summoned.connect(_on_player_card_summoned)
	player_self.card_sent_to_grave.connect(_on_player_card_sent_to_grave)
	player_opponent.card_sent_to_grave.connect(_on_player_card_sent_to_grave)
	
	_is_first_turn = true
	turn_count = 1
	current_player_index = 0
	current_phase = Phase.NONE
	
	turn_changed.emit(turn_count)
	if OS.is_debug_build():
		print("[战斗] ========== 战斗开始 ==========")
	if OS.is_debug_build():
		print("[战斗] 己方: 手牌", player_self.hand.size(), "张 能量", player_self.energy, "/", player_self.max_energy)
	if OS.is_debug_build():
		print("[战斗] 敌方: 手牌", player_opponent.hand.size(), "张 能量", player_opponent.energy, "/", player_opponent.max_energy)
	
	# ★ 检查敌方是否完全无战斗力：卡组、手牌、场地全空 → 直接胜利
	if player_opponent.deck.is_empty() and player_opponent.hand.is_empty() and player_opponent.get_field_count() == 0:
		if OS.is_debug_build():
			print("[战斗]  敌方卡组/手牌/场地全空，跳过战斗，直接胜利！")
		battle_state = State.WON
		battle_state_changed.emit(State.WON)
		return
	
	# 进入己方第一回合（从抽牌阶段开始）
	if auto_start:
		_enter_phase(Phase.DRAW)


## 延迟启动第一回合（RPS结束后调用）
func start_first_turn(player_wins_rps: bool) -> void:
	current_player_index = 0 if player_wins_rps else 1
	_enter_phase(Phase.DRAW)


## 根据卡牌ID列表加载完整卡牌数据
func _load_card_datas_by_ids(card_ids: Array) -> Array:
	var all_cards = CardManager.get_all_cards()
	var result := []
	for cid in card_ids:
		for card_data in all_cards:
			# ★ 同时匹配 id 和 template_id
			if card_data.get("id", "") == cid or card_data.get("template_id", "") == cid:
				result.append(card_data.duplicate())
				break
	return result

## ★ 从「服务器卡组池(Global.server_decks) + 本地卡组」随机选一套作为AI对手卡组
## 参数：
##   player_card_datas —— 玩家当前这套卡组的完整卡牌数据（回退用）
##   player_deck_id    —— 玩家当前卡组ID（从本地卡组池随机时用）
func _pick_ai_deck(player_card_datas: Array, player_deck_id: String) -> Array:
	var ai_card_datas := []
	# 收集所有候选卡组（服务器卡组池 + 本地卡组）
	var candidates: Array = []  # 每项为 { "name": String, "card_datas": Array }
	
	# 1. 服务器卡组池（加载界面已拉取到 Global.server_decks，数据含完整 card_datas）
	var server_decks = Global.server_decks if Global.server_decks != null else []
	for sdeck in server_decks:
		var deck_data = sdeck.get("deck_data", {})
		if deck_data is Dictionary:
			# 优先使用完整卡牌数据（本地JSON格式），兼容旧格式（ID列表）
			var sdeck_card_datas = deck_data.get("card_datas", [])
			if sdeck_card_datas is Array and sdeck_card_datas.size() > 0:
				var name = deck_data.get("name", sdeck.get("name", "AI卡组"))
				candidates.append({"name": name, "card_datas": sdeck_card_datas})
				if OS.is_debug_build():
					print("[战斗] AI卡组加载: ", name, " (", sdeck_card_datas.size(), "张)")
			else:
				# 兼容旧格式：ID列表，从玩家收藏解析
				var sdeck_cards = deck_data.get("cards", [])
				if sdeck_cards is Array and sdeck_cards.size() > 0:
					var parsed := _load_card_datas_by_ids(sdeck_cards)
					if parsed.size() > 0:
						candidates.append({
							"name": sdeck.get("name", deck_data.get("name", "服务器卡组")),
							"card_datas": parsed
						})
	
	# 2. 本地所有卡组（除玩家当前用的这套外，避免相同）
	var local_decks = CardManager.get_all_decks()
	for local_id in local_decks:
		if local_id == player_deck_id:
			continue  # 跳过玩家当前正在用的这套
		var local_deck = local_decks[local_id]
		var local_cards = local_deck.get("cards", [])
		if local_cards is Array and local_cards.size() > 0:
			var parsed := _load_card_datas_by_ids(local_cards)
			if parsed.size() > 0:
				candidates.append({
					"name": local_deck.get("name", local_id),
					"card_datas": parsed
				})
	
	# 3. 如果候选为空，回退到玩家当前卡组（至少能打）
	if candidates.is_empty():
		if OS.is_debug_build():
			print("[战斗]  服务器卡组池和本地卡组池均为空，回退到玩家当前卡组")
		return player_card_datas
	
	# 从候选中随机选一套
	var picked = candidates[randi() % candidates.size()]
	ai_card_datas = picked.get("card_datas", [])
	if OS.is_debug_build():
		print("[战斗]  AI对手使用卡组: ", picked.get("name", "未知"), " (", ai_card_datas.size(), "张)")
	return ai_card_datas


# ===== 阶段流转 =====

func _enter_phase(phase: Phase) -> void:
	current_phase = phase
	phase_changed.emit(phase, current_player_index)
	
	match phase:
		Phase.DRAW:
			_execute_draw_phase()
			if current_player_index == 1:
				# 敌方回合：不自动进READY，设置标记等3D层驱动抽牌动画
				_enemy_phase_step = "DRAW_DONE"
			else:
				# 玩家回合：抽牌后自动进入准备阶段
				_enter_phase(Phase.READY)
		
		Phase.READY:
			_execute_ready_phase()
			if current_player_index == 1:
				# 敌方回合：不自动进MAIN，设置标记等3D层驱动
				_enemy_phase_step = "READY_DONE"
			else:
				# 玩家回合：准备后进入主要阶段
				current_phase = Phase.MAIN
				phase_changed.emit(Phase.MAIN, current_player_index)
				if OS.is_debug_build():
					print("[战斗] 进入主要阶段，等待操作")
		
		Phase.MAIN:
			# 主动进入MAIN（用于AI/敌方回合）
			phase_changed.emit(Phase.MAIN, current_player_index)
			if current_player_index == 1:
				_build_ai_main_phase_queue()
		
		Phase.BATTLE:
			# 主动进入BATTLE（用于AI/敌方回合）
			phase_changed.emit(Phase.BATTLE, current_player_index)
			if current_player_index == 1:
				_build_ai_battle_phase_queue()
		
		Phase.END:
			_execute_end_phase()
			# 结束阶段效果触发完后，检查手牌是否超限
			var player = _get_current_player()
			var max_hand = 6
			if player.hand.size() > max_hand:
				# 进入弃牌阶段（由DISCARD分支统一处理弃牌请求）
				if OS.is_debug_build():
					print("[战斗] 手牌超限(", player.hand.size(), ">", max_hand, ")，等待回合结束动画播完再进入弃牌阶段")
				# 通知UI：回合结束效果已发完（数据层），等非飘窗动画（画线/闪烁）播完后再回调 proceed_to_discard_after_end_effects 推进弃牌
				# 这样避免回合结束效果的视角切换/画线动画与弃牌视角切换交错打架
				end_phase_effects_pending_discard.emit(player.hand.size() - max_hand)
			else:
				_switch_turn()
		Phase.DISCARD:
			# 弃牌阶段（手牌超限）
			var player = _get_current_player()
			var max_hand = 6
			var need_discard = player.hand.size() - max_hand
			if need_discard > 0:
				request_discard(player, need_discard, "end_phase", func():
					_switch_turn()
				)
			else:
				_switch_turn()


## 供UI在回合结束效果的非飘窗动画（画线/闪烁）播完后回调，推进弃牌阶段
## 仅当当前仍处于END阶段且手牌超限时才推进（防止状态已被其他流程改变）
func proceed_to_discard_after_end_effects() -> void:
	if current_phase != Phase.END:
		if OS.is_debug_build():
			print("[战斗] proceed_to_discard_after_end_effects: 当前不在END阶段(phase=", current_phase, ")，跳过")
		return
	var player = _get_current_player()
	var max_hand = 6
	if player.hand.size() > max_hand:
		if OS.is_debug_build():
			print("[战斗] 回合结束动画已播完，进入弃牌阶段")
		_enter_phase(Phase.DISCARD)
	else:
		# 动画播完时手牌已不超限（极少见，如效果改了手牌），直接切回合
		if OS.is_debug_build():
			print("[战斗] 回合结束动画播完时手牌已不超限，直接切回合")
		_switch_turn()


## 敌方阶段推进（由3D表现层调用，驱动敌方阶段流转）
func advance_enemy_phase() -> void:
	match _enemy_phase_step:
		"DRAW_DONE":
			# 抽牌动画完成 → 进入准备阶段
			_enemy_phase_step = ""
			_enter_phase(Phase.READY)
		"READY_DONE":
			# 准备阶段完成 → 进入主要阶段，构建AI队列
			_enemy_phase_step = ""
			current_phase = Phase.MAIN
			phase_changed.emit(Phase.MAIN, current_player_index)
			if OS.is_debug_build():
				print("[战斗] 敌方进入主要阶段")
			_build_ai_main_phase_queue()
		"":
			pass


func _execute_draw_phase() -> void:
	var player = _get_current_player()
	
	if _is_first_turn:
		_is_first_turn = false
		player.is_first_turn = false  # 同步清除玩家标记
	
	# 先手第一回合也抽牌（不再跳过）
	
	var card = player.draw_phase()
	if card:
		if OS.is_debug_build():
			print("[战斗]  抽牌: ", player.player_name, " 抽到 [", card.get_display_name(), "]")
	else:
		if OS.is_debug_build():
			print("[战斗]  抽牌: 卡组已空！")
	# ★ 抽牌后检查卡组耗尽判负（卡组/手牌/场地全空）
	_check_win_condition()


func _execute_ready_phase() -> void:
	var player = _get_current_player()
	var opponent = _get_opponent_player()
	
	# 能量上限+1（最多10）
	# 第1回合=玩家先手首回合，第2回合=敌方后手首回合，双方首回合都不加能量（用各自的初始能量）
	# 从第3回合起能量才增长
	if turn_count > 2:
		if player.max_energy < 10:
			player.max_energy += 1
	
	# 能量回满
	player.energy = player.max_energy
	player.energy_changed.emit(player.energy, player.max_energy)
	
	# 重置回合级约束（必须在触发回合效果之前重置，确保本回合的CO01标记从零开始）
	_reset_turn_constraints()
	
	# 重置卡牌状态（攻击标记、临时增减等）
	player.ready_phase()
	
	# 触发回合开始周期性效果
	_execute_periodic_effects(player, "start_of_turn")  # TR12: 己方回合开始
	_scan_and_trigger("TR13", opponent)  # TR13: 对方回合开始时（扫描对方场上）
	
	# 检查0/0卡牌自然送墓
	player.cleanup_destroyed()
	
	if OS.is_debug_build():
		print("[战斗]  准备: 能量上限", player.max_energy, " 能量回满，卡牌已重置")


func _execute_end_phase() -> void:
	var player = _get_current_player()
	var opponent = _get_opponent_player()
	
	# 归还暂时夺取的控制权
	player.return_taken_control()
	opponent.return_taken_control()
	
	# TR18 控制权转移时（归还也算转移，扫描双方场上）
	_scan_and_trigger("TR18", player)
	_scan_and_trigger("TR18", opponent)
	
	# 触发回合结束周期性效果
	_execute_periodic_effects(player, "end_of_turn")  # TR14: 己方回合结束时
	_scan_and_trigger("TR15", opponent)  # TR15: 对方回合结束时（扫描对方场上）
	
	# 中毒结算：谁回合结束，结算谁方场地（中毒指示物按层数扣血，持续不掉层）
	_resolve_poison(player)
	
	player.end_phase()
	if OS.is_debug_build():
		print("[战斗]  结束: 手牌", player.hand.size(), "张 墓地", player.grave.size(), "张")

## 中毒结算：扫描指定玩家场地，有中毒指示物的卡牌每层扣1血（中毒指示物不清零，持续掉血）
func _resolve_poison(player: BattlePlayer) -> void:
	if player == null:
		return
	for i in range(player.max_field_size):
		var card = player.field[i]
		if card != null and card.poison_count > 0 and card.is_alive():
			var dmg = card.poison_count
			if OS.is_debug_build():
				print("[中毒] 回合结算: ", card.get_display_name(), " 中毒 ", card.poison_count, " 层，受到 ", dmg, " 点伤害")
			poison_tick_triggered.emit(player == player_self, i, dmg, card.poison_count)
			card.take_damage(dmg)
	# 结算后清理阵亡卡牌
	player.cleanup_destroyed()


func _on_discard_result(callback_id: int, selected_indices: Array) -> void:
	var cb_data = _discard_callbacks.get(callback_id)
	if cb_data == null:
		if OS.is_debug_build():
			print("[弃牌] 回调ID无效: ", callback_id)
		return
	var player = cb_data.player as BattlePlayer
	_do_discard(player, selected_indices)
	# 保持回调在字典中，等动画播完再通过 _on_discard_animation_finished 调用
	cb_data["discard_indices"] = selected_indices
	# 发信号让UI播放飞入墓地特效
	var is_player_side = (player == player_self)
	discard_animation_requested.emit(callback_id, is_player_side, selected_indices)
	if OS.is_debug_build():
		print("[弃牌] 请求播放弃牌动画: 回调ID=", callback_id, " 己方=", is_player_side, " 弃", selected_indices.size(), "张")

## UI在弃牌动画播放完后调用，此时才真正执行回调（切回合/继续出牌等）
func _on_discard_animation_finished(callback_id: int) -> void:
	var cb_data = _discard_callbacks.get(callback_id)
	if cb_data == null:
		if OS.is_debug_build():
			print("[弃牌] 动画完成但回调ID无效: ", callback_id)
		return
	_discard_callbacks.erase(callback_id)
	if cb_data.has("func") and cb_data.func is Callable:
		cb_data.func.call()

## 请求弃牌选择（通用方法）
## count: 需要弃的张数
## reason: 原因描述（"end_phase"=结束阶段弃牌, "CO04"=约束弃牌）
## callback: 弃牌完成后回调
func request_discard(owner: BattlePlayer, count: int, reason: String, callback: Callable) -> void:
	if count <= 0:
		callback.call()
		return
	# 己方回合 → 发信号让UI弹窗
	if owner == player_self:
		var callback_id = _discard_callback_counter
		_discard_callback_counter += 1
		_discard_callbacks[callback_id] = {"func": callback, "player": owner, "count": count}
		discard_requested.emit(count, callback_id, reason)
		if OS.is_debug_build():
			print("[弃牌] 请求玩家弃牌: ", count, "张, 原因: ", reason)
	# AI回合 → 自动评估弃掉最差的牌
	else:
		var opponent = _get_opponent_player() if owner == player_self else player_self
		var enemy_field_count = owner.get_field_count()
		var self_field_count = opponent.get_field_count()
		var scored := []
		for hi in range(owner.hand.size()):
			var card = owner.hand[hi] as BattleCard
			if card == null:
				continue
			var score = 0
			for eff in card.effects:
				if eff is Dictionary:
					var eval_result = _evaluate_effect_for_ai(eff, owner, opponent, enemy_field_count, self_field_count)
					score += eval_result.score
			score += card.current_atk * 10 + card.current_hp * 5 - card.base_cost * 2
			var field_state = _evaluate_field_state(owner, opponent)
			score += int(field_state.score * 0.3)
			scored.append({"idx": hi, "score": score, "name": card.get_display_name()})
		scored.sort_custom(func(a, b): return a.score < b.score)
		var indices := []
		for d in range(min(count, scored.size())):
			indices.append(scored[d].idx)
			if OS.is_debug_build():
				print("[AI弃牌]", reason, " 弃掉: ", scored[d].name, " (评分:", scored[d].score, ")")
		_do_discard(owner, indices)
		# AI弃牌也走动画信号（等待UI播完飞牌特效再回调）
		var callback_id = _discard_callback_counter
		_discard_callback_counter += 1
		_discard_callbacks[callback_id] = {"func": callback, "player": owner, "count": count, "discard_indices": indices}
		var is_player_side = (owner == player_self)
		discard_animation_requested.emit(callback_id, is_player_side, indices)
		if OS.is_debug_build():
			print("[AI弃牌] 请求播放弃牌动画: 回调ID=", callback_id, " 弃", indices.size(), "张")

func _do_discard(player: BattlePlayer, discard_indices: Array) -> void:
	var sorted := []
	for idx in discard_indices:
		sorted.append(int(idx))
	sorted.sort()
	sorted.reverse()
	for idx in sorted:
		if idx >= 0 and idx < player.hand.size():
			var discarded = player.hand[idx]
			player.hand.remove_at(idx)
			player.grave.append(discarded)
			if OS.is_debug_build():
				print("[战斗] 弃牌: ", discarded.get_display_name())
	player.hand_changed.emit()
	player.grave_changed.emit()
	_check_win_condition()

func _switch_turn() -> void:
	current_player_index = 1 if current_player_index == 0 else 0
	turn_count += 1
	
	turn_changed.emit(turn_count)
	if OS.is_debug_build():
		print("[战斗] ===== 第", turn_count, "回合 —— ", _get_current_player().player_name, " =====")
	
	_enter_phase(Phase.DRAW)


# ===== 敌方AI操作 =====

## 构建敌方AI队列：主要阶段
func _build_ai_main_phase_queue() -> void:
	ai_action_queue.clear()
	ai_phase_completed = false
	
	if current_player_index != 1 or battle_state != State.PLAYING:
		ai_phase_completed = true
		return
	
	var enemy = player_opponent
	var self_p = player_self
	if OS.is_debug_build():
		print("[AI] 敌方主要阶段开始...")
	
	# ★ AI 智能决策：先评估战略 + 连招攒牌 + 全知视角
	# ★ 推进连招计划：每回合等牌更近一步，配套到手(≤0)则解除等待，允许启动
	if _ai_combo_plan_active:
		_ai_combo_plan_wait_turns -= 1
		if _ai_combo_plan_wait_turns <= 0:
			if OS.is_debug_build():
				print("[AI-连招规划] 配套已到手! 本回合启动连招[", _ai_combo_plan_partner_desc, "]")
			_ai_combo_plan_active = false
	_update_ai_strategy()
	_update_ai_combo_hold()
	var sell_blood = _ai_should_sell_blood()
	var combo_mode = (_ai_strategy == "combo")
	var ai_strategy_desc = _ai_strategy
	if sell_blood:
		ai_strategy_desc += " (卖血)"
	if combo_mode:
		ai_strategy_desc += " (攒连招)"
	if OS.is_debug_build():
		print("[AI] 战略: ", ai_strategy_desc)
	
	# === 分析场上局势 ===
	var enemy_field_count = enemy.get_field_count()
	var self_field_count = self_p.get_field_count()
	var enemy_hero_hp = enemy.hp
	var self_hero_hp = self_p.hp
	var enemy_energy = enemy.energy
	
	# 收集手牌信息，统一按评分排序
	var hand_cards := []  # 所有手牌统一处理
	for hi in range(enemy.hand.size()):
		var card = enemy.hand[hi] as BattleCard
		if card == null:
			continue
		# 评分：有效果加分，有攻防加分，低费加分
		var score = 0
		for eff in card.effects:
			var eval_result = _evaluate_effect_for_ai(eff, enemy, self_p, enemy_field_count, self_field_count)
			score += eval_result.score
		score += card.current_atk * 10 + card.current_hp * 5 - card.base_cost * 2
		# ★ 场面局势加权 + 策略调整
		var field_state = _evaluate_field_state(enemy, self_p)
		score += int(field_state.score * 0.3)  # 场面分×0.3作为全局修正
		# 策略层：根据当前局势给特定类型效果加权
		var hp_ratio = enemy.hp / float(max(enemy.max_hp, 1))
		var field_diff = enemy.get_field_count() - self_p.get_field_count()
		for eff in card.effects:
			if not (eff is Dictionary):
				continue
			var act = eff.get("action", "")
			var trig = eff.get("trigger", "")
			# 残血时优先保命（回血卡加分）
			if hp_ratio < 0.3 and act == "A02":
				score += 40
			# 场面劣势时优先解场（破坏/弹回加分）
			if field_diff <= -2 and act in ["A03", "A06", "A07"]:
				score += 30
			# 手牌少时优先抽牌
			if enemy.hand.size() <= 2 and act == "A09":
				score += 30
			# ★ 持续价值：每回合自动触发型的卡（回合开始/结束）优先出
			# TR12 己方回合开始 / TR13 对方回合开始 / TR14 己方回合结束 / TR15 对方回合结束
			if trig in ["TR12", "TR13", "TR14", "TR15"]:
				score += 30
			# ★ 亡语价值：送墓时触发型的卡（死了也不亏），更积极上场交换
			if trig == "TR06":
				score += 15
		# ★ 能量规划：出这张卡后剩余能量<2，但手牌还有低费卡可以出 → 扣分保留能量
		var energy_after = enemy.energy - card.base_cost
		if energy_after < 2 and enemy.hand.size() > 1:
			var has_low_cost_fallback := false
			for c2 in enemy.hand:
				if c2 != card and c2.base_cost <= energy_after:
					has_low_cost_fallback = true
					break
			if has_low_cost_fallback:
				score -= 20
		# ★ ⑤保留能量给反制：手牌有TR16（对方发动效果时）反制卡时，保留至少1能量
		if energy_after < 1:
			var has_counter := false
			for c2 in enemy.hand:
				if c2 == card:
					continue
				for e2 in c2.effects:
					if e2.get("trigger", "") == "TR16":
						has_counter = true
						break
				if has_counter:
					break
			if has_counter:
				score -= 30
		
		# ★ 卡差意识：卡差>0的卡加分，卡差<0的卡减分（非紧急情况）
		var card_adv = _calc_card_advantage(card)
		if card_adv >= 1:
			score += card_adv * 15  # 赚卡差加分
		elif card_adv <= -1:
			# 亏卡差的卡，检查是否紧急情况
			var is_urgent := false
			if enemy.get_field_count() == 0 and self_p.get_field_count() > 0:
				is_urgent = true  # 空场需要下怪挡刀
			if enemy.hp <= 3 and self_p.hp > enemy.hp:
				is_urgent = true  # 残血需要保命
			if not is_urgent:
				score += card_adv * 10  # 亏卡差扣分（负数乘正数=负数）
		
		# ★ AI 全知视角加成：根据对手手牌情报微调评分
		score = _ai_apply_omniscient_bonus(card, score)
		# ★ AI 战略加权（连招/抢血/控场）
		var strategy = _ai_strategy
		if strategy == "aggro":
			# 抢血：优先出攻击力高的 + 直伤卡
			score += card.current_atk * 2
			for eff2 in card.effects:
				if eff2 is Dictionary and eff2.get("action", "") in ["A01", "A09"]:
					score += 20
		elif strategy == "control":
			# 控场：优先出解场卡
			for eff3 in card.effects:
				if eff3 is Dictionary and eff3.get("action", "") in ["A03", "A06", "A07", "A04", "A08", "A33"]:
					score += 30
		elif strategy == "combo":
			# 攒连招：关键组件标为"本回合不下"，其他铺场/资源卡可正常出
			if _ai_hold_combo_ids.has(hi):
				score -= 50  # 攒着！
			else:
				score += 10  # 非组件可以放心铺
		hand_cards.append({"card": card, "idx": hi, "score": score, "field_state": field_state})
	
	# ★ 按效果优先级排序：先解场→再铺场→再斩杀→再抽牌
	# 同一张卡取最低优先级的效果（决定它该在哪个阶段出）
	hand_cards.sort_custom(func(a, b):
		var pa = _get_effect_priority(a.card)
		var pb = _get_effect_priority(b.card)
		if pa != pb:
			return pa < pb  # 优先级低的（数字小）先出
		return a.score > b.score  # 同优先级内按评分
	)
	
	# === 决策：按评分从高到低出牌 ===
	
	# 用模拟能量计算，避免修改真实能量
	var sim_energy = enemy.energy
	
	# ★ 残血斩杀意识：对手血量<我方场上+手牌总伤害时，跳过铺场直接打脸
	var lethal_skip_summon := false
	var my_total_damage = _estimate_player_lethal(enemy)
	if self_p.hp <= my_total_damage and self_p.hp <= 10:
		lethal_skip_summon = true
		if OS.is_debug_build():
			print("[AI] 斩杀线达成! 跳过铺场，全力输出")
	
	var used_hand_indices := []  # 记录已决定出的手牌索引
	var has_real_action := false  # 是否有实际操作，没有则跳过等待
	var planned_summon_count := 0  # 已计划召唤的数量（用于分配不同槽位）
	for card_info in hand_cards:
		if sim_energy <= 0:
			break
		var card = card_info.card
		if card.base_cost > sim_energy:
			continue
		
		# ★ AI召唤时检查效果约束（CO类），避免盲目召唤导致效果发动失败
		# 汇编效果里所有约束ID，若约束无法满足则跳过该卡
		var can_play := true
		for eff in card.effects:
			if not (eff is Dictionary):
				continue
			var eff_constraints = eff.get("constraints", [])
			if not (eff_constraints is Array):
				continue
			for cid in eff_constraints:
				# 参照 _check_constraints_allowed 的代价检查逻辑
				match cid:
					"CO03":  # 支付生命（value = 支付量）
						var hp_cost = Global.get_constraint_param(eff, "CO03", 10)
						if enemy.hp < hp_cost:
							can_play = false
							if OS.is_debug_build():
								print("[AI] 跳过召唤 ", card.get_display_name(), "：CO03支付生命不足")
							break
					"CO04":  # 舍弃手牌（value = 舍弃张数）
						var discard_count = Global.get_constraint_param(eff, "CO04", 1)
						if enemy.hand.size() < discard_count:
							can_play = false
							if OS.is_debug_build():
								print("[AI] 跳过召唤 ", card.get_display_name(), "：CO04手牌不足")
							break
				if not can_play:
					break
		if not can_play:
			continue
		
		# 评分判断：分两种情况
		# ① 卡组还有牌 → 正常按评分，评分<10或空发卡都跳过，下回合抽新卡
		# ② 卡组空了 → 也按评分，但能空发（评分< -100也出），这是最后的机会
		# ★ 斩杀模式：跳过非伤害卡，只出能斩杀的卡
		if lethal_skip_summon:
			var has_damage := false
			for eff in card.effects:
				if eff is Dictionary and eff.get("action", "") == "A01":
					has_damage = true
					break
			if not has_damage and card.current_atk < 3:
				continue  # 没伤害的下怪跳过，只出直伤或高攻卡
		var deck_is_empty = enemy.deck.size() == 0
		if card_info.score < 10:
			if deck_is_empty:
				# 卡组空了，空发也比捏着强，硬出
				pass
			else:
				# 卡组还有牌，评分<10的跳过，下回合抽新的
				if card_info.score < -100:
					# 空发卡，跳过
					continue
				# 检查是否有评分>=10的卡，有则跳过，没有则硬出这张
				var has_high_score := false
				for ci in hand_cards:
					if ci.score >= 10 and ci.card.base_cost <= sim_energy:
						has_high_score = true
						break
				if has_high_score:
					continue
		
		var empty_slots = enemy.get_empty_slots()
		if empty_slots.is_empty():
			break
		
		# ★ 用 planned_summon_count 手动计数已计划召唤数，避免多个召唤选到同一个空槽
		# empty_slots 是当前真实空槽，但队列尚未执行，所以要用已计划的召唤数偏移
		var slot = -1
		if planned_summon_count < empty_slots.size():
			slot = empty_slots[planned_summon_count]
		else:
			slot = empty_slots[0]
		if not has_real_action:
			has_real_action = true
			ai_action_queue.append({"type": "wait", "delay": 0.8})
		ai_action_queue.append({"type": "enemy_summon", "hand_idx": card_info.idx, "slot_idx": slot})
		ai_action_queue.append({"type": "wait", "delay": 1.0})
		ai_action_queue.append({"type": "enemy_summon_effect", "slot_idx": slot})
		ai_action_queue.append({"type": "wait", "delay": 2.5})
		planned_summon_count += 1  # 手动记录已计划召唤数，分配下一个空槽
		sim_energy -= card.base_cost
		used_hand_indices.append(card_info.idx)
		enemy_field_count += 1
		if OS.is_debug_build():
			print("[AI] 召唤: ", card.get_display_name(), " (得分:", card_info.score, ")")
	
	# 有实际操作才加过渡等待，否则直接跳战斗阶段
	if has_real_action:
		ai_action_queue.append({"type": "wait", "delay": 0.5})
	ai_action_queue.append({"type": "to_battle"})

## 构建敌方AI队列：战斗阶段
func _build_ai_battle_phase_queue() -> void:
	ai_action_queue.clear()
	ai_phase_completed = false
	
	if current_player_index != 1 or battle_state != State.PLAYING:
		ai_phase_completed = true
		return
	
	if OS.is_debug_build():
		print("[AI] 敌方战斗阶段开始...")
	
	var enemy = player_opponent
	var self_p = player_self
	
	# ★ AI 卖血决策：手牌有斩杀/连招时，优先打脸抢血（把血当资源）
	var sell_blood = _ai_should_sell_blood()
	# ★ AI 斩杀意识：全知估算自己的总伤害，够斩杀就直接打脸
	var my_lethal = _estimate_player_lethal(enemy)
	var can_finish = my_lethal >= self_p.hp
	if sell_blood or can_finish:
		# ★ 守护规则：对方场上有卡时不能直击，即使卖血/斩杀也要先解场
		if self_p.get_field_count() > 0:
			if OS.is_debug_build():
				print("[AI] 卖血/斩杀模式但对方场上有卡，跳过直击，优先解场")
		else:
			var ai_aggro_desc = "卖血抢血，倾向直击英雄"
			if can_finish:
				ai_aggro_desc = "斩杀线达成! 全员打脸"
			if OS.is_debug_build():
				print("[AI] ", ai_aggro_desc)
			# 打脸模式：所有能攻击的卡直接打英雄
			var any_attacker := false
			for slot in range(enemy.max_field_size):
				var card = enemy.field[slot]
				if card and card.is_alive() and card.can_attack():
					ai_action_queue.append({"type": "enemy_attack_hero", "slot": slot})
					ai_action_queue.append({"type": "wait", "delay": 1.2})
					any_attacker = true
			if any_attacker:
				ai_action_queue.append({"type": "replan"})
				return
		# 没有可攻击的卡或对方场上有卡 → 走正常流程（继续往下）
	
	# 找最佳攻击者（只规划一个，打完后 replan 重新评估）
	var best_attacker_slot = -1
	var best_target_slot = -1
	var best_target_score = -1
	var attacker_score = -100000  # 极小值：只要我方场上有卡就必定选到目标，杜绝评分全负掉到直击
	
	for slot in range(enemy.max_field_size):
		var card = enemy.field[slot]
		if card == null or not card.is_alive() or not card.can_attack():
			continue
		
		# 找该攻击者的最佳目标
		if self_p.get_field_count() > 0:
			for target_slot in range(self_p.max_field_size):
				var target = self_p.field[target_slot]
				if target == null or not target.is_alive():
					continue
				var score = 0
				# ★ 攻击交换比：能杀死
				if card.current_atk >= target.current_hp:
					score += 1500
					# ★ 刚好能杀（完美交换）：用最低攻的怪去解，高攻留打脸
					var overkill = card.current_atk - target.current_hp
					if overkill == 0:
						score += 500  # 刚好杀死，完美！
					elif overkill <= 2:
						score += 200  # 浪费1-2点，还行
					else:
						score -= overkill * 8  # 浪费太多攻击力，扣分！
				# 对方攻击力越高越危险
				score += target.current_atk * 10
				# 对方生命值越低越好杀
				score -= target.current_hp * 2
				# 高攻低血优先
				if target.current_atk >= 3 and target.current_hp <= 2:
					score += 500
				# 持续收益卡优先集火
				for teff in target.effects:
					if teff is Dictionary:
						var ttrig = teff.get("trigger", "")
						if ttrig in ["TR12", "TR13", "TR14", "TR15"]:
							score += 300
							break
				
				# ★ 攻击者价值保留：高攻怪留着打脸更值钱
				if card.current_atk >= 4:
					# 如果场上还有别的低攻怪也能解这个目标 → 高攻怪扣分，让低攻怪去解
					var has_lower_attacker := false
					for s2 in range(enemy.max_field_size):
						if s2 == slot: continue
						var c2 = enemy.field[s2]
						if c2 and c2.is_alive() and c2.can_attack():
							if c2.current_atk >= target.current_hp and c2.current_atk < card.current_atk:
								has_lower_attacker = true
								break
					if has_lower_attacker:
						score -= 300  # 让低攻怪去解，高攻留打脸
				
				# 攻击者-目标组合评分 = 攻击者攻击力权重 + 目标评分
				var this_attacker_score = card.current_atk * 5 + score
				
				# 元素克制：克制目标时攻击伤害+20%，提高击杀成功率
				var atk_elem = card.get_effective_element()
				var def_elem = target.get_effective_element()
				var affinity = Global.get_element_affinity(atk_elem, def_elem)
				if affinity > 1.0:
					# 克制目标 → 伤害+20%，更容易击杀，加分
					this_attacker_score += 250
					# 如果刚好能击杀（克制后足够杀死），额外加分
					var effective_dmg = roundi(float(card.current_atk) * affinity)
					if effective_dmg >= target.current_hp:
						this_attacker_score += 400
					if OS.is_debug_build():
						print("[AI-元素] ", card.get_display_name(), " (", atk_elem, ") 克制 ", target.get_display_name(), " (", def_elem, ") 评分+", this_attacker_score)
				elif affinity < 1.0:
					# 实际上不会发生，先留着
					pass
				
				if this_attacker_score > attacker_score:
					attacker_score = this_attacker_score
					best_attacker_slot = slot
					best_target_slot = target_slot
					best_target_score = score
	
	# 有最佳目标 → 攻击卡牌
	if best_attacker_slot >= 0 and best_target_slot >= 0:
		var card = enemy.field[best_attacker_slot]
		ai_action_queue.append({"type": "enemy_attack", "slot": best_attacker_slot, "target_slot": best_target_slot})
		ai_action_queue.append({"type": "wait", "delay": 1.5})
		if OS.is_debug_build():
			print("[AI] 攻击: ", card.get_display_name(), " → 场地", best_target_slot, " (得分:", best_target_score, ")")
		# 攻击完后重新评估战场
		ai_action_queue.append({"type": "replan"})
		return
	
	# 没有场上目标 → 检查是否有能攻击英雄的卡牌
	var has_hero_attacker := false
	for slot in range(enemy.max_field_size):
		var card = enemy.field[slot]
		if card and card.is_alive() and card.can_attack():
			has_hero_attacker = true
			ai_action_queue.append({"type": "enemy_attack_hero", "slot": slot})
			ai_action_queue.append({"type": "wait", "delay": 1.5})
			if OS.is_debug_build():
				print("[AI] 攻击英雄: ", card.get_display_name())
			# 攻击完后重新评估战场
			ai_action_queue.append({"type": "replan"})
			break  # 只打一个，然后replan
	
	if not has_hero_attacker:
		ai_action_queue.append({"type": "to_end"})
		if OS.is_debug_build():
			print("[AI] 敌方结束战斗阶段，进入结束阶段")
func _execute_next_ai_action() -> bool:
	"""返回true表示还有更多动作，false表示队列已空"""
	# 战斗已结束，停止AI
	if battle_state != State.PLAYING:
		ai_action_queue.clear()
		ai_phase_completed = true
		return false
	
	if ai_action_queue.is_empty():
		ai_phase_completed = true
		return false
	
	var action = ai_action_queue.pop_front()
	match action.get("type", ""):
		"wait":
			# wait的处理在BattleScene中通过计时器完成
			# 这里只是把action放回队列前端，由BattleScene检查delay
			ai_action_queue.push_front(action)
			return true
		
		"enemy_summon":
			var hand_idx = action.get("hand_idx", -1)
			var slot_idx = action.get("slot_idx", -1)
			var enemy = player_opponent
			# 设置召唤标记，让 field_changed 信号触发动画
			_last_enemy_summon_slot_idx = slot_idx
			var success = enemy.summon_from_hand(hand_idx, slot_idx)
			if success:
				var card = enemy.field[slot_idx]
				if OS.is_debug_build():
					print("[AI] 敌方召唤: ", card.get_display_name() if card else "?")
				# 注意：此处只召唤上场，效果和送墓在 enemy_summon_effect 中处理
				# 让动画先播放，玩家能看到卡牌上场
			else:
				_last_enemy_summon_slot_idx = -1
		
		"enemy_summon_effect":
			# 动画播放完后，触发效果并处理送墓
			# ★ 用 action.get("slot_idx") 直接从队列读取槽位，不依赖 _last_enemy_summon_slot_idx
			# ★ （因为 _last_enemy_summon_slot_idx 已被 BattleScene 的 field_changed 消费掉）
			# ★ 检查卡牌是否真实存在，若召唤失败（slot为空）则跳过效果
			var enemy = player_opponent
			var slot_idx = action.get("slot_idx", -1)
			if slot_idx >= 0 and slot_idx < enemy.max_field_size:
				var card = enemy.field[slot_idx]
				if card:
					# 注意：不检查 is_alive()，因为0/0卡牌也需要触发召唤效果
					_execute_on_summon_effects(enemy, card, slot_idx)
					# 注意：_execute_on_summon_effects 内部已经处理了0/0卡牌送墓
					_check_win_condition()
			# 重置召唤槽位标记，防止重复触发
			_last_enemy_summon_slot_idx = -1
		
		"enemy_attack":
			var slot = action.get("slot", -1)
			var target_slot = action.get("target_slot", -1)
			# 设置待处理攻击标记，让BattleScene播放动画后再执行伤害
			_pending_enemy_attack = {"type": "attack", "slot": slot, "target_slot": target_slot}
		
		"enemy_attack_hero":
			var slot = action.get("slot", -1)
			# 设置待处理攻击标记，让BattleScene播放动画后再执行伤害
			_pending_enemy_attack = {"type": "attack_hero", "slot": slot}
		
		"to_battle":
			if OS.is_debug_build():
				print("[AI] 敌方结束主要阶段，进入战斗阶段")
			current_phase = Phase.BATTLE
			_enter_phase(Phase.BATTLE)
		
		"replan":
			_build_ai_battle_phase_queue()
		"to_end":
			if OS.is_debug_build():
				print("[AI] 敌方结束战斗阶段，进入结束阶段")
			_enter_phase(Phase.END)
	
	return not ai_action_queue.is_empty()

## 执行待处理的敌方攻击伤害（动画播放完后调用）
func _execute_pending_enemy_attack() -> void:
	if _pending_enemy_attack.is_empty():
		return
	var atk = _pending_enemy_attack.duplicate()
	_pending_enemy_attack = {}
	
	var enemy = player_opponent
	var self_p = player_self
	var slot = atk.get("slot", -1)
	var card = enemy.field[slot] if slot >= 0 and slot < enemy.field.size() else null
	
	if atk.get("type") == "attack_hero":
		if card and card.is_alive():
			# === 触发 TR09: 攻击宣言时（攻击方自身） ===
			_trigger_card_trigger("TR09", enemy, card, slot)
			var atk_result = enemy.attack_hero(slot, self_p.hp, self_p)
			self_p.hp = atk_result.get("new_hp", self_p.hp)
			self_p.hp_changed.emit(self_p.hp + atk_result.get("damage", 0), self_p.hp)
			# === 触发 TR11: 给予战斗伤害时（攻击方自身） ===
			if atk_result.get("damage", 0) > 0:
				_trigger_card_trigger("TR11", enemy, card, slot)
			if OS.is_debug_build():
				print("[AI] 敌方直接攻击英雄: ", card.get_display_name(), " 造成", atk_result.get("damage", 0), "伤害")
			_check_win_condition()
	else:
		var target_slot = atk.get("target_slot", -1)
		var target = self_p.field[target_slot] if target_slot >= 0 and target_slot < self_p.field.size() else null
		
		# ★ 目标已死亡 → 若我方场上还有其他存活卡，则改攻击其他卡牌；场上无卡才直击英雄
		if card and card.is_alive():
			if target == null or not target.is_alive():
				# 先找场上其他存活卡作为替代目标
				var alt_target_slot = -1
				if self_p.get_field_count() > 0:
					for ts in range(self_p.max_field_size):
						if ts == target_slot:
							continue
						var alt = self_p.field[ts]
						if alt != null and alt.is_alive():
							alt_target_slot = ts
							break
				if alt_target_slot >= 0:
					if OS.is_debug_build():
						print("[AI] 目标已死，转向攻击其他卡牌: ", card.get_display_name(), " → 场地", alt_target_slot)
					# === 触发 TR09: 攻击宣言时（攻击方自身） ===
					_trigger_card_trigger("TR09", enemy, card, slot)
					var alt_target = self_p.field[alt_target_slot]
					_trigger_card_trigger("TR10", player_self, alt_target, alt_target_slot, false)
					var alt_result = enemy.attack(slot, alt_target)
					if alt_result.get("damage_to_defender", 0) > 0:
						_trigger_card_trigger("TR11", enemy, card, slot)
					if alt_result.get("attacker_destroyed", false):
						enemy.send_to_grave(card)
					if alt_result.get("defender_destroyed", false):
						self_p.send_to_grave(alt_target)
					_check_win_condition()
					return
				# 我方场上确实无存活卡 → 直击英雄
				if OS.is_debug_build():
					print("[AI] 目标已死且我方场上无卡，攻击英雄: ", card.get_display_name())
				# === 触发 TR09: 攻击宣言时（攻击方自身） ===
				_trigger_card_trigger("TR09", enemy, card, slot)
				var atk_result = enemy.attack_hero(slot, self_p.hp, self_p)
				self_p.hp = atk_result.get("new_hp", self_p.hp)
				self_p.hp_changed.emit(self_p.hp + atk_result.get("damage", 0), self_p.hp)
				# === 触发 TR11: 给予战斗伤害时（攻击方自身） ===
				if atk_result.get("damage", 0) > 0:
					_trigger_card_trigger("TR11", enemy, card, slot)
				_check_win_condition()
				return
			
			# 正常攻击 — 触发攻击宣言纹路（攻击方自身 + 防御方自身）
			_trigger_card_trigger("TR09", enemy, card, slot)
			_trigger_card_trigger("TR10", player_self, target, target_slot, false)
			var atk_result = enemy.attack(slot, target)
			if OS.is_debug_build():
				print("[AI] 敌方攻击: ", card.get_display_name(), " → ", target.get_display_name())
			# 元素克制飘字
			var eb = atk_result.get("element_boost", {})
			if eb.get("type", "") != "":
				element_boost_triggered.emit("affinity", eb.get("atk_elem", ""), eb.get("def_elem", ""), eb.get("from_value", 0), eb.get("to_value", 0), false, slot)
			# === 触发 TR11: 给予战斗伤害时（攻击方自身） ===
			if atk_result.get("damage_to_defender", 0) > 0:
				_trigger_card_trigger("TR11", enemy, card, slot)
			if atk_result.get("attacker_destroyed", false):
				enemy.send_to_grave(card)
			if atk_result.get("defender_destroyed", false):
				self_p.send_to_grave(target)
			_check_win_condition()


## AI评估单一效果的价值（覆盖全部24种动作类型）
func _evaluate_effect_for_ai(effect: Dictionary, enemy: BattlePlayer, self_p: BattlePlayer,
	enemy_field_count: int, self_field_count: int) -> Dictionary:
	var action = effect.get("action", "")
	var target = effect.get("target", "")
	var value = effect.get("value", 0)
	var score = 0
	var desc = ""
	
	# ★ 条件检查：效果的条件不满足时，效果评分为0（卡牌本身仍可凭攻防站场）
	var conditions = effect.get("conditions", [])
	if conditions is Array and conditions.size() > 0:
		var all_conditions_met := true
		for cond_data in conditions:
			if not (cond_data is Dictionary):
				continue
			if not Global.check_condition(cond_data, enemy, self_p, null):
				all_conditions_met = false
				var cond_id = cond_data.get("id", "?")
				desc += "条件" + cond_id + "不满足 "
				break
		if not all_conditions_met:
			# 条件不满足：效果分给0，卡牌自身攻防仍在总评分中体现
			return {"score": 0, "desc": desc.strip_edges(), "action": action}
	
	# === 目标有效性检查：场上没目标就不发 ===
	# T02(敌方单体)/T04(敌方全体/敌方全场) → 目标在玩家场上，玩家空场无效
	if target in ["T02", "T04"] and self_field_count == 0:
		if action in ["A01", "A03", "A04", "A06", "A07", "A08", "A20", "A21", "A22", "A23", "A24", "A28"]:
			return {"score": -999, "desc": "目标无效(敌方空场)"}
	# T03(己方单体)/T05(己方全体/我方全场) → 目标在AI场上，AI空场无效
	if target in ["T03", "T05"] and enemy_field_count == 0:
		if action in ["A20", "A21", "A22", "A23", "A24", "A28"]:
			return {"score": -999, "desc": "目标无效(己方空场)"}
	# T06(全场) → 需要至少一方有目标
	if target == "T06" and self_field_count == 0 and enemy_field_count == 0:
		if action in ["A01", "A03", "A04", "A06", "A07", "A08", "A20", "A21", "A22", "A23", "A24"]:
			return {"score": -999, "desc": "目标无效(全场空)"}
	# ★ 全体/全场效果浪费检查：场上只有少量目标时，攒着等更多目标
	# T04(敌方全体/敌方全场) → 玩家场上只有1-2张时太浪费
	if target == "T04" and self_field_count <= 2 and self_field_count > 0:
		desc += "敌方全场浪费(仅" + str(self_field_count) + "目标) "
		score -= 60
	# T05(己方全体/我方全场) → AI场上只有1-2张时太浪费
	if target == "T05" and enemy_field_count <= 2 and enemy_field_count > 0:
		desc += "我方全场浪费(仅" + str(enemy_field_count) + "目标) "
		score -= 60
	# T06(全场) → 总目标数≤3时浪费
	if target == "T06" and (self_field_count + enemy_field_count) <= 3 and (self_field_count + enemy_field_count) > 0:
		desc += "全场浪费(共" + str(self_field_count + enemy_field_count) + "目标) "
		score -= 50
	# ★ 增益/减益效果空放检查
	# T01(自身) → 卡自己加给自己，不需要额外目标，不算空放
	# T03(己方单体)/T05(己方全体/我方全场) → 需要AI场上有怪才能加增益
	if action in ["A20", "A21", "A22", "A23"]:
		if target in ["T03", "T05"] and enemy_field_count == 0:
			return {"score": -999, "desc": "增益空放(我方空场)"}
		if target in ["T02", "T04"] and self_field_count == 0:
			return {"score": -999, "desc": "减益空放(敌方空场)"}
	# A24(全场增减) T01=己方全场(AI) → 需要AI场上有怪
	if action == "A24":
		if target == "T01" and enemy_field_count == 0:
			return {"score": -999, "desc": "增益空放(我方空场)"}
		if target == "T02" and self_field_count == 0:
			return {"score": -999, "desc": "减益空放(敌方空场)"}
	# A25(交换攻防) 对敌方(T02/T04) → 需要玩家场上有怪
	if action == "A25" and target in ["T02", "T04"] and self_field_count == 0:
		return {"score": -999, "desc": "交换空放(敌方空场)"}
	# A28(无法攻击) 对敌方(T02/T04) → 需要玩家场上有怪
	if action == "A28" and target in ["T02", "T04"] and self_field_count == 0:
		return {"score": -999, "desc": "无法攻击空放(敌方空场)"}
	# T13(对方攻击最高)/T14(对方攻击最低) → 需要对方场上有目标
	if target in ["T13", "T14"] and enemy_field_count == 0:
		if action in ["A31", "A32", "A33", "A03", "A01"]:
			return {"score": -999, "desc": "目标无效(对方空场)"}
	# T15(我方攻击最高)/T16(我方攻击最低) → 需要己方场上有目标
	if target in ["T15", "T16"] and self_field_count == 0:
		if action in ["A31", "A32", "A33", "A20", "A21", "A23", "A25"]:
			return {"score": -999, "desc": "目标无效(己方空场)"}
	
	match action:
		"A01": # 伤害
			score = value * 8
			if target in ["T02", "T04"] and self_field_count > 0: score += 20
			if target in ["T05", "T06", "T08"] and self_field_count == 0: score += 30
			desc = "伤害"
		
		"A02": # 治疗
			if enemy.hp < enemy.max_hp * 0.7: score = value * 6 + 30
			else: score = value * 3
			desc = "治疗"
		
		"A03": # 破坏
			if self_field_count > 0:
				score = 60 + self_field_count * 15
				for i in range(self_p.max_field_size):
					var c = self_p.field[i]
					if c and c.is_alive(): score += c.current_atk * 3 + c.current_hp * 2
			else: score = 10
			desc = "破坏"
		
		"A04": # 除外
			score = 70  # 除外比破坏强（无法复活）
			if self_field_count > 0:
				for i in range(self_p.max_field_size):
					var c = self_p.field[i]
					if c and c.is_alive(): score += c.current_atk * 3 + c.current_hp * 2
			desc = "除外"
		
		"A05": # 墓地除外
			if self_p.grave.size() > 0: score = 20 + self_p.grave.size() * 5
			else: score = 0
			desc = "墓地除外"
		
		"A06": # 弹回手牌
			if self_field_count > 0: score = 40 + self_field_count * 10
			else: score = 5
			desc = "弹回手牌"
		
		"A07": # 弹回卡组
			if self_field_count > 0: score = 50 + self_field_count * 10
			else: score = 5
			desc = "弹回卡组"
		
		"A08": # 送入墓地
			if self_field_count > 0 or enemy.hand.size() > 0: score = 30
			else: score = 5
			desc = "送入墓地"
		
		"A09": # 抽牌
			if enemy.hand.size() < 5: score = 25 + (5 - enemy.hand.size()) * 10
			else: score = 10
			desc = "抽牌"
		
		"A10": # 检索字段
			if enemy.hand.size() < 6: score = 35
			else: score = 15
			desc = "检索字段"
		
		"A11": # 检索任意
			if enemy.hand.size() < 6: score = 40
			else: score = 20
			desc = "检索任意"
		
		"A12": # 墓地回收
			if enemy.grave.size() > 0:
				score = 30 + enemy.grave.size() * 5
				for c in enemy.grave:
					if c.current_atk > 5 or c.current_hp > 5: score += 20
			else: score = 0
			desc = "墓地回收"
		
		"A13": # 除外回收
			if enemy.banished.size() > 0: score = 25 + enemy.banished.size() * 5
			else: score = 0
			desc = "除外回收"
		
		"A14": # 卡组堆墓
			score = 15
			desc = "卡组堆墓"
		
		"A15": # 手牌特召
			if enemy_field_count < enemy.max_field_size and enemy.hand.size() > 1:
				score = 30
			else: score = 5
			desc = "手牌特召"
		
		"A16": # 墓地特召
			if enemy_field_count < enemy.max_field_size and enemy.grave.size() > 0:
				score = 45 + enemy.grave.size() * 5
				for c in enemy.grave:
					if c.current_atk > 4 or c.current_hp > 4: score += 15
			else: score = 0
			desc = "墓地特召"
		
		"A17": # 卡组特召
			if enemy_field_count < enemy.max_field_size:
				score = 50
			else: score = 0
			desc = "卡组特召"
		
		"A18": # 除外特召
			if enemy_field_count < enemy.max_field_size and enemy.banished.size() > 0:
				score = 40 + enemy.banished.size() * 5
			else: score = 0
			desc = "除外特召"
		
		"A19": # 召唤衍生物
			if enemy_field_count < enemy.max_field_size:
				score = 25 + (enemy.max_field_size - enemy_field_count) * 10
			else: score = 0
			desc = "召唤衍生物"
		
		"A20": # 攻永久增益
			if target in ["T01", "T03"] and enemy_field_count > 0:
				score = value * 5 + 20
			elif target in ["T02", "T04"] and self_field_count > 0:
				score = -value * 5 + 20
			elif target == "T08":
				score = value * 3 + 10
			else: score = 5
			desc = "攻增益"
		
		"A21": # 命永久增益
			if target in ["T01", "T03"] and enemy_field_count > 0:
				score = value * 4 + 20
			elif target in ["T02", "T04"] and self_field_count > 0:
				score = -value * 4 + 20
			elif target == "T08":
				score = value * 3 + 10
			else: score = 5
			desc = "命增益"
		
		"A22": # 攻命双增益
			score = value * 6 + 30
			if target in ["T02", "T04"] and self_field_count > 0: score += 15
			desc = "双增益"
		
		"A23": # 回合内临时增减
			score = value * 3 + 15
			if target in ["T02", "T04"] and self_field_count > 0: score += 10
			desc = "临时增减"
		
		"A24": # 全场增减
			if target == "T01":
				if enemy_field_count > 0: score = value * 4 * enemy_field_count + 30
				else: score = 5
			else:
				if self_field_count > 0: score = -value * 4 * self_field_count + 30
				else: score = 5
			desc = "全场增减"
		
		"A25": # 交换攻防
			if target in ["T02", "T04"]:
				var best_swap = 0
				for i in range(self_p.max_field_size):
					var c = self_p.field[i]
					if c and c.is_alive() and c.current_atk < c.current_hp:
						best_swap = max(best_swap, c.current_hp - c.current_atk)
				score = best_swap * 3 + 20
			else: score = 10
			desc = "交换攻防"
		
		"A28": # 无法攻击
			if self_field_count > 0:
				score = 25 + self_field_count * 10
				for i in range(self_p.max_field_size):
					var c = self_p.field[i]
					if c and c.is_alive() and c.current_atk > 3: score += 15
			else: score = 5
			desc = "无法攻击"
		
		"A29": # 表示形式变更
			score = 15
			desc = "表示变更"
		
		"A26": # 暂时夺取控制权
			if self_field_count > 0:
				score = 45 + self_field_count * 15
				for i in range(self_p.max_field_size):
					var c = self_p.field[i]
					if c and c.is_alive(): score += c.current_atk * 3 + c.current_hp * 2
			else: score = 10
			desc = "暂时夺取控制权"
		
		"A27": # 永久夺取控制权
			if self_field_count > 0:
				score = 60 + self_field_count * 20
				for i in range(self_p.max_field_size):
					var c = self_p.field[i]
					if c and c.is_alive(): score += c.current_atk * 4 + c.current_hp * 3
			else: score = 10
			desc = "永久夺取控制权"
		
		"A30": # 无效效果并破坏
			if chain_stack.size() > 0:
				score = 70 + chain_stack.size() * 30
			else: score = 5
			desc = "无效效果并破坏"

		"A31": # 控制权变更·一回合（夺敌/送己，回合结束归还）
			if target in ["T02", "T04", "T13", "T14"] and self_field_count > 0:
				score = 50 + self_field_count * 15
				for i in range(self_p.max_field_size):
					var c = self_p.field[i]
					if c and c.is_alive(): score += c.current_atk * 3 + c.current_hp * 2
			elif target in ["T03", "T05", "T15", "T16"] and enemy_field_count > 0:
				# 送卡战术：送弱卡给对面换触发，评分偏低
				score = 15
			else: score = 10
			desc = "控制权变更·一回合"

		"A32": # 控制权变更·永久
			if target in ["T02", "T04", "T13", "T14"] and self_field_count > 0:
				score = 65 + self_field_count * 20
				for i in range(self_p.max_field_size):
					var c = self_p.field[i]
					if c and c.is_alive(): score += c.current_atk * 4 + c.current_hp * 3
			elif target in ["T03", "T05", "T15", "T16"] and enemy_field_count > 0:
				score = 15
			else: score = 10
			desc = "控制权变更·永久"

		"A33": # 禁用效果（一回合）
			if target in ["T02", "T04", "T13", "T14"] and self_field_count > 0:
				score = 55 + self_field_count * 15
				for i in range(self_p.max_field_size):
					var c = self_p.field[i]
					if c and c.is_alive() and c.current_atk > 3: score += 20
			else: score = 10
			desc = "禁用效果"
	
	# 目标修正：己方单体/英雄保守一点
	if target in ["T05", "T08"]: score = int(score * 0.7)
	
	return {"score": score, "desc": desc, "action": action}

## 评估场面局势，返回场面价值分（用于AI决策加权）
func _evaluate_field_state(owner: BattlePlayer, opponent: BattlePlayer) -> Dictionary:
	var score = 0.0
	var desc = ""
	
	# ① 血量评估
	var hp_ratio = owner.hp / float(max(owner.max_hp, 1))
	var opp_hp_ratio = opponent.hp / float(max(opponent.max_hp, 1))
	if hp_ratio < 0.3:
		score -= 30  # 残血，危险！
		desc += "残血-30 "
	elif hp_ratio > 0.8 and opp_hp_ratio < 0.4:
		score += 30  # 大优势
		desc += "血量优势+30 "
	
	# ② 场面数量评估
	var field_diff = owner.get_field_count() - opponent.get_field_count()
	score += field_diff * 15  # 每多一只怪+15分
	if field_diff >= 2:
		score += 20  # 场面压制额外加分
		desc += "场面压制+20 "
	elif field_diff <= -2:
		score -= 30  # 场面被压制
		desc += "场面劣势-30 "
	
	# ③ 手牌资源评估
	var hand_size = owner.hand.size()
	if hand_size <= 1:
		score -= 20  # 手牌枯竭
		desc += "手牌枯竭-20 "
	elif hand_size >= 5:
		score += 15  # 手牌充裕
		desc += "手牌充裕+15 "
	
	# ④ 卡组厚度评估
	if owner.deck.size() <= 3:
		score -= 40  # 卡组快空了
		desc += "卡组见底-40 "
	
	return {"score": score, "desc": desc.strip_edges()}

## ★ 效果优先级排序：数字越小越先出
## 优先级：封印(0) > 解场(1) > 控制权(2) > 特召铺场(3) > 主力站场(4) > 斩杀伤害(5) > 抽牌资源(6) > 炮灰填场(7)
func _get_effect_priority(card: BattleCard) -> int:
	var priority = 7  # 默认炮灰级
	for eff in card.effects:
		if not (eff is Dictionary):
			continue
		var act = eff.get("action", "")
		match act:
			"A33":  # 封印效果 → 必须先出，再出其他
				priority = min(priority, 0)
			"A03", "A04", "A06", "A07", "A08":  # 解场（破坏/除外/弹回/送墓）
				priority = min(priority, 1)
			"A31", "A32":  # 控制权夺取
				priority = min(priority, 2)
			"A15", "A16", "A17", "A18":  # 特召铺场
				priority = min(priority, 3)
			"A01":  # 伤害（斩杀用）
				priority = min(priority, 5)
			"A09", "A10", "A11", "A12", "A13", "A14":  # 抽牌/检索/回收
				priority = min(priority, 6)
			_:
				# 纯站场怪
				if card.current_atk >= 4 or card.current_hp >= 4:
					priority = min(priority, 4)  # 主力站场
				else:
					priority = min(priority, 7)  # 炮灰
	return priority

## ★ 卡差评估：这张卡能赚多少资源差
func _calc_card_advantage(card: BattleCard) -> int:
	var advantage = 0
	advantage -= 1  # 用掉这张卡本身 = -1
	for eff in card.effects:
		if not (eff is Dictionary):
			continue
		var act = eff.get("action", "")
		match act:
			"A03", "A04":  # 破坏/除外 → 对面少1张
				advantage += 1
			"A06", "A07":  # 弹回 → 对面少1张（但可能再出，卡差略低）
				advantage += 1
			"A08":  # 送墓 → 对面手牌少1张
				advantage += 1
			"A09":  # 抽牌 → 自己多1张（净赚1-1=0，但不亏）
				advantage += 0
			"A10", "A11":  # 检索 → 自己多1张（净赚0）
				advantage += 0
			"A12":  # 墓地回收 → 自己多1张
				advantage += 1
			"A15", "A16":  # 特召（不耗手牌资源）+ 额外站场
				advantage += 1
			"A31", "A32":  # 控制权夺取（对面少1张 + 自己多1张）
				advantage += 2
			"A33":  # 封印效果（不算直接卡差，但战略价值高）
				advantage += 0
	# 高攻高血的卡本身价值更高
	if card.current_atk >= 5:
		advantage += 1
	if card.current_hp >= 5:
		advantage += 1
	# 低费卡更容易赚卡差
	if card.base_cost <= 1:
		advantage += 1
	return advantage

## ===== AI 牌库预读 + 连招规划（预读牌库顺序，设计启动回合） =====

## 预读自己牌库顶N张，缓存到 _ai_lookahead_cards（按抽牌顺序，索引0=下回合会抽到）
func _ai_preview_deck() -> void:
	var enemy = player_opponent
	_ai_lookahead_cards.clear()
	if enemy.deck == null:
		return
	# BattleDeck.peek_top_multiple 直接返回牌顶N张（不抽走），顺序：0=牌顶
	var preview = enemy.deck.peek_top_multiple(_ai_lookahead_depth)
	for c in preview:
		if c is BattleCard:
			_ai_lookahead_cards.append(c)

## 判断一张卡是否属于"连招组件"（与 _rank_hand_strategy 的 combo 判定保持一致）
func _ai_is_combo_piece(card: BattleCard) -> bool:
	if not (card is BattleCard):
		return false
	for eff in card.effects:
		if not (eff is Dictionary):
			continue
		var act = eff.get("action", "")
		var trig = eff.get("trigger", "")
		if act in ["A31", "A32", "A33"] or trig in ["TR18"] or act in ["A26", "A27"]:
			return true
	return false

## 判断两张卡能否组成"可启动连招"（核心逻辑：控制权组件配触发/判定/斩杀）
## 返回 true 表示 card_a（手牌）在 card_b（牌库即将抽到）到手后可以组成连招
func _ai_can_combo_with(card_a: BattleCard, card_b: BattleCard) -> bool:
	if not (card_a is BattleCard) or not (card_b is BattleCard):
		return false
	var a_acts := {}
	var b_acts := {}
	var a_trigs := {}
	var b_trigs := {}
	for eff in card_a.effects:
		if eff is Dictionary:
			a_acts[eff.get("action", "")] = true
			a_trigs[eff.get("trigger", "")] = true
	for eff in card_b.effects:
		if eff is Dictionary:
			b_acts[eff.get("action", "")] = true
			b_trigs[eff.get("trigger", "")] = true
	# ① 控制权类组件（A31/A32）互配 → 连招"NTR控场"
	if (a_acts.has("A31") or a_acts.has("A32")) and (b_acts.has("A31") or b_acts.has("A32")):
		return true
	# ② 控制权类 + TR18触发 → "夺取+触发"
	if (a_acts.has("A31") or a_acts.has("A32")) and (b_trigs.has("TR18") or a_trigs.has("TR18")):
		return true
	# ③ 禁用效果A33 + 破坏解场 → "先禁后拆"（防亡语/防反制）
	if (a_acts.has("A33") and (b_acts.has("A03") or b_acts.has("A06") or b_acts.has("A07"))) or \
	   (b_acts.has("A33") and (a_acts.has("A03") or a_acts.has("A06") or a_acts.has("A07"))):
		return true
	# ④ 控制权 + 直伤斩杀 → "抢高攻怪+打脸"（抢来的怪攻击=斩杀组件）
	if (a_acts.has("A31") or a_acts.has("A32")) and (b_acts.has("A01") or a_acts.has("A09")):
		return true
	# ⑤ TR18 + 控制权（任意方向）→ 触发链
	if a_trigs.has("TR18") and (b_acts.has("A31") or b_acts.has("A32")):
		return true
	return false

## 核心：预读牌库 + 手牌配对，生成连招计划
## 手上有连招组件时，若牌库顶N张内有配套组件 → 建立"攒牌等配套"计划
func _ai_build_combo_plan() -> void:
	_ai_preview_deck()
	var enemy = player_opponent
	# 先清空旧计划
	_ai_combo_plan_active = false
	_ai_combo_plan_wait_turns = 0
	_ai_combo_plan_key_hand_idx = -1
	_ai_combo_plan_partner_desc = ""
	
	if _ai_lookahead_cards.is_empty():
		return
	
	# 只检查手牌里的连招组件（不包含已被标记整组的卡）
	for hi in range(enemy.hand.size()):
		var hand_card = enemy.hand[hi]
		if not (hand_card is BattleCard):
			continue
		if not _ai_is_combo_piece(hand_card):
			continue
		# 牌库预读顺序 = 接下来几个回合会抽到的牌
		for di in range(_ai_lookahead_cards.size()):
			var deck_card = _ai_lookahead_cards[di]
			if not (deck_card is BattleCard):
				continue
			if not _ai_is_combo_piece(deck_card):
				continue
			# 手牌组件 + 牌库组件能配对 → 建计划
			if _ai_can_combo_with(hand_card, deck_card):
				_ai_combo_plan_active = true
				_ai_combo_plan_wait_turns = di + 1  # 第di张=再等di+1回合抽到
				_ai_combo_plan_key_hand_idx = hi
				_ai_combo_plan_partner_desc = deck_card.get_display_name()
				if OS.is_debug_build():
					print("[AI-连招规划] 预读牌库: 手牌[", hand_card.get_display_name(), "] 等[", 
					_ai_combo_plan_wait_turns, "回合]抽到[", _ai_combo_plan_partner_desc, "] 启动连招!")
				return

func _rank_hand_strategy(hand: Array) -> Dictionary:
	"""按用途给手牌分组：combo组件/解场/铺场/斩杀/资源”，返回 key->[card]"""
	var groups := {"combo": [], "removal": [], "threat": [], "finisher": [], "resource": []}
	for card in hand:
		if not (card is BattleCard):
			continue
		var is_combo := false
		var is_removal := false
		var is_finisher := false
		var is_resource := false
		for eff in card.effects:
			if not (eff is Dictionary):
				continue
			var act = eff.get("action", "")
			var trig = eff.get("trigger", "")
			if act in ["A31", "A32", "A33"] or trig in ["TR18"] or act in ["A26", "A27"]:
				is_combo = true
			if act in ["A03", "A06", "A07", "A04", "A08"]:
				is_removal = true
			if act in ["A01", "A09"]:
				is_finisher = true
			if act in ["A02", "A09", "A10", "A11", "A12"]:
				is_resource = true
		if is_combo:
			groups.combo.append(card)
		elif is_finisher:
			groups.finisher.append(card)
		elif is_removal:
			groups.removal.append(card)
		elif is_resource:
			groups.resource.append(card)
		else:
			groups.threat.append(card)
	return groups

func _estimate_player_lethal(player: BattlePlayer) -> int:
	"""全知视角：估算对方下回合的理论总伤害（场上攻击总和 + 手牌里能打的伤害）"""
	var total := 0
	for slot in range(player.max_field_size):
		var c = player.field[slot]
		if c and c.is_alive() and c.can_attack():
			total += c.current_atk
	# 全知：看对方手牌，预估潜在直伤/斩杀（A01 伤害类）
	for card in player.hand:
		if not (card is BattleCard):
			continue
		for eff in card.effects:
			if not (eff is Dictionary):
				continue
			var act = eff.get("action", "")
			var val = eff.get("value", 0)
			if act == "A01" and val > 0:
				total += val
	return total

func _update_ai_strategy() -> void:
	"""根据当前局面动态调整战略：aggro/control/combo/balanced"""
	var enemy = player_opponent
	var self_p = player_self
	var enemy_hp_ratio = enemy.hp / float(max(enemy.max_hp, 1))
	var self_hp_ratio = self_p.hp / float(max(self_p.max_hp, 1))
	var field_diff = enemy.get_field_count() - self_p.get_field_count()
	var hand_groups = _rank_hand_strategy(enemy.hand)
	
	# 0. ★ 有进行中的连招计划（预读牌库已配对）→ 锁定 combo 战略，不动摇
	if _ai_combo_plan_active:
		_ai_strategy = "combo"
		return
	
	# 1. 有斩杀组件（大量直伤/连招组件）→ 抢血
	var lethal_now = _estimate_player_lethal(self_p)
	var enemy_lethal = _estimate_player_lethal(enemy)
	if enemy_hp_ratio <= 0.5 and lethal_now >= enemy.hp:
		_ai_strategy = "combo"  # 能一波带走
		return
	# 2. 手上有关键连招组件多 → 攒连招
	if hand_groups.combo.size() >= 2:
		_ai_strategy = "combo"
		return
	# 3. 场面被压、自己在卖血 → 控场优先
	if field_diff <= -1 and self_hp_ratio > _ai_blood_threshold:
		_ai_strategy = "control"
		return
	# 4. 血量优势 + 手牌有斩杀 → 抢血
	if enemy_hp_ratio <= 0.4 and self_hp_ratio >= 0.6:
		_ai_strategy = "aggro"
		return
	_ai_strategy = "balanced"

func _ai_apply_omniscient_bonus(card: BattleCard, base_score: int) -> int:
	"""全知视角：根据对手手牌/牌库情报给卡牌评分加成"""
	var self_p = player_self
	var score = base_score
	# 预估对手威胁（手牌里有多少高攻/破坏类）
	var opp_threat := 0
	for c in self_p.hand:
		if not (c is BattleCard):
			continue
		for eff in c.effects:
			if not (eff is Dictionary):
				continue
			var act = eff.get("action", "")
			if act in ["A03", "A06", "A07", "A01", "A04"]:
				opp_threat += 10
			if c.current_atk >= 3:
				opp_threat += 5
	# 对手威胁高且这卡是低费炮灰 → 加分（拿它挡刀/送死）
	if opp_threat > 20 and card.base_cost <= 2 and card.current_hp <= 2:
		score += 20
	return score

## 连招攒牌：识别手牌里能组成连招的关键组件，标记"本回合不下、攒着"
## ★ 升级：不只手牌≥2才攒——预读牌库发现"手牌组件 + 牌库即将抽到的配套"也能组成连招时，同样攒着等配套
func _update_ai_combo_hold() -> void:
	var enemy = player_opponent
	var self_p = player_self
	_ai_hold_combo_ids.clear()
	
	# ★ 先跑"预读牌库 + 连招规划"：看手牌组件能否和牌库顶的卡配对
	_ai_build_combo_plan()
	
	var hand_groups = _rank_hand_strategy(enemy.hand)
	var combo_cards = hand_groups.combo
	
	# 分支一：有进行中的连招计划（手牌组件 + 牌库配套已配对）
	# → 把计划中的手牌组件标记"攒着"，等待启动回合
	if _ai_combo_plan_active and _ai_combo_plan_key_hand_idx >= 0:
		_ai_hold_combo_ids[_ai_combo_plan_key_hand_idx] = "combo_wait"
		# 若手牌里还有其他组件，也一并攒着（整套留着，启动回合一起打）
		for i in range(enemy.hand.size()):
			var c2 = enemy.hand[i]
			if i == _ai_combo_plan_key_hand_idx:
				continue
			if c2 is BattleCard and _ai_is_combo_piece(c2):
				_ai_hold_combo_ids[i] = "combo_wait"
		if OS.is_debug_build():
			print("[AI-攒牌] 连招计划进行中: 攒[", enemy.hand[_ai_combo_plan_key_hand_idx].get_display_name(),
			"] 等[", _ai_combo_plan_partner_desc, "] 再等", _ai_combo_plan_wait_turns, "回合")
		return
	
	# 分支二：手牌已有≥2组件（成套了）→ 直接启动连招，不攒着！
	# 攒牌只服务于"等配套"；配套齐了就该打，而不是卡在手里
	if combo_cards.size() < 2:
		# 只有1个组件且没有预读配套 → 这个组件如果是主动件(A31/A32/A33)可以单出，
		# 如果是触发件(TR18)单独没价值 → 得等配套，攒着
		if combo_cards.size() == 1:
			var solo = combo_cards[0]
			var solo_is_active := false
			for eff in solo.effects:
				if eff is Dictionary and eff.get("action", "") in ["A31", "A32", "A33"]:
					solo_is_active = true
					break
			if not solo_is_active:
				# 只有触发件(TR18)，等配套；标记攒着
				for i in range(enemy.hand.size()):
					if enemy.hand[i] == solo:
						_ai_hold_combo_ids[i] = "combo_wait"
						if OS.is_debug_build():
							print("[AI-攒牌] 手牌只有触发件[", solo.get_display_name(), "]，攒着等主动组件")
						return
		# 主动件可单出，或组件真不足 → 不强行攒
		return
	
	# 成套（≥2组件）→ 直接启动连招！解除攒牌，正常出牌流程会按评分打出
	# 战略层已经切到 combo，会给连招组件加权，这里无需再标记"攒着"
		var _combo_names: Array = combo_cards.map(func(c): return c.get_display_name())
		if OS.is_debug_build():
			print("[AI-连招] 手牌组件已成套(", combo_cards.size(), "张): ", ", ".join(_combo_names), " → 本回合启动连招!")

## 卖血决策：血量允许时，倾向于保留攻击频率/不防御性下怪，把血当资源
func _ai_should_sell_blood() -> bool:
	var enemy = player_opponent
	var self_p = player_self
	# 血多才卖，且手牌有斩杀/连招时更激进
	if enemy.hp / float(max(enemy.max_hp, 1)) < _ai_blood_threshold:
		return false
	# 手牌有连招或斩杀组件时，愿意用血换节奏
	var groups = _rank_hand_strategy(enemy.hand)
	if groups.combo.size() >= 2 or groups.finisher.size() >= 1:
		return true
	return false

# ===== 连锁系统（Chain System） =====

## 压入连锁栈
func _push_to_chain(owner: BattlePlayer, card: BattleCard, effect: Dictionary, slot: int) -> int:
	# ★ 连锁长度限制：超过最大长度则拒绝压栈，防止无限连锁死循环
	if chain_stack.size() >= MAX_CHAIN_LENGTH:
		if OS.is_debug_build():
			print("[连锁] 已达最大连锁长度(", MAX_CHAIN_LENGTH, ")，拒绝压栈")
		return -1
	chain_counter += 1
	var chain_id = chain_counter
	chain_stack.append({
		"owner": owner,
		"card": card,
		"effect": effect.duplicate(),
		"slot": slot,
		"chain_id": chain_id,
		"negated": false  # 是否被无效化
	})
	if OS.is_debug_build():
		print("[连锁] 连锁", chain_id, " 加入: ", card.get_display_name(), " (", owner.player_name, ")")
	return chain_id

## 开始连锁响应（构建阶段）
func _start_chain_building() -> void:
	"""效果压入栈后，给对方响应机会"""
	if _ignore_chain or chain_stack.is_empty():
		_resolve_chain()
		return
	
	# 检查对方场上是否有可以连锁的卡牌（有TR16效果且条件/约束满足的）
	var opponent = _get_opponent_player()
	var has_response = false
	for i in range(opponent.max_field_size):
		var c = opponent.field[i]
		if c == null or not c.is_alive():
			continue
		for eff in c.effects:
			var parsed = Global.parse_circuit(eff)
			if parsed.is_valid and parsed.trigger == "TR16":
				# 条件+约束预检：只有能真正发动的才算可连锁
				if _precheck_effect(opponent, c, eff):
					has_response = true
					break
		if has_response:
			break
	
	if not has_response:
		# 没有可连锁的卡牌，直接结算
		_resolve_chain()
		return
	
	# 有响应机会
	if current_player_index == 0:
		# 己方回合 → 敌方（AI）机会
		# AI自动判断是否要连锁
		_ai_chain_response()
	else:
		# 敌方回合 → 己方（玩家）机会，发信号给UI
		_chain_response_callback_id = chain_counter
		chain_response_requested.emit(_chain_response_callback_id)

## AI连锁响应决策
func _ai_chain_response() -> void:
	"""AI判断是否要连锁，用评分函数评估"""
	if chain_stack.is_empty():
		_resolve_chain()
		return
	
	var opponent = _get_opponent_player()
	var self_p = _get_current_player()
	
	# ★ ①连锁能量检查：能量不够根本无法发动效果，直接放弃
	if opponent.energy < 1:
		if OS.is_debug_build():
			print("[AI-连锁] 能量不足，放弃连锁")
		_resolve_chain()
		return
	
	var opponent_field_count = opponent.get_field_count()
	var self_field_count = self_p.get_field_count()
	
	# ★ AI 全知连锁阈值：残血时更积极连锁保命，上风时可更省
	var self_hp_ratio = self_p.hp / float(max(self_p.max_hp, 1))
	var chain_threshold := 30
	if self_hp_ratio < 0.3:
		chain_threshold = 10  # 残血 → 能连锁就连锁
	elif self_hp_ratio > 0.7:
		chain_threshold = 50  # 血厚 → 省资源，只打关键连锁
	
	var best_score = 0
	var best_response = null  # {card, effect, slot}
	
	for i in range(opponent.max_field_size):
		var c = opponent.field[i]
		if c == null or not c.is_alive():
			continue
		for eff in c.effects:
			var parsed = Global.parse_circuit(eff)
			if not parsed.is_valid or parsed.trigger != "TR16":
				continue
			# 条件+约束预检（压栈前检查）
			if not _precheck_effect(opponent, c, eff):
				continue
			# 评估这个效果是否值得连锁发动
			var eval_result = _evaluate_effect_for_ai(eff, opponent, self_p, opponent_field_count, self_field_count)
			if eval_result.score > best_score:
				best_score = eval_result.score
				best_response = {"card": c, "effect": eff, "slot": i}
	
	if best_response and best_score > chain_threshold:
		# AI选择连锁
		var c = best_response.card
		var eff = best_response.effect
		var slot = best_response.slot
		if OS.is_debug_build():
			print("[AI-连锁] 连锁响应: ", c.get_display_name(), " (评分:", best_score, " 阈值:", chain_threshold, ")")
		_push_to_chain(opponent, c, eff, slot)
		# 递归：继续给对方（玩家）响应机会
		_start_chain_building()
	else:
		# AI放弃连锁，结算
		if OS.is_debug_build():
			print("[AI-连锁] 放弃连锁")
		_resolve_chain()

## 玩家连锁响应（从BattleScene调用）
func on_player_chain_response(should_chain: bool, card_data: Dictionary = {}) -> void:
	"""玩家选择是否连锁"""
	if should_chain and card_data.size() > 0:
		var owner = player_self
		var card = card_data.get("card", null) as BattleCard
		var effect = card_data.get("effect", {})
		var slot = card_data.get("slot", -1)
		if card and effect.size() > 0:
			# 条件+约束预检（压栈前检查）
			if not _precheck_effect(owner, card, effect):
				if OS.is_debug_build():
					print("[连锁] 玩家连锁响应: 条件/约束不满足，无法发动")
				_resolve_chain()
				return
			_push_to_chain(owner, card, effect, slot)
			# 继续给AI响应机会
			_start_chain_building()
			return
	
	# 玩家放弃连锁，结算
	_resolve_chain()

## 结算连锁（后进先出 LIFO）
func _resolve_chain() -> void:
	if chain_stack.is_empty():
		_chain_resolving = false
		return
	
	_chain_resolving = true
	_ignore_chain = true  # 结算中不触发新连锁
	
	chain_built.emit(chain_stack.size())
	if OS.is_debug_build():
		print("[连锁] ===== 开始结算连锁（共", chain_stack.size(), "链）=====")
	
	# 后进先出结算
	while not chain_stack.is_empty():
		var link = chain_stack.pop_back()
		if link.negated:
			if OS.is_debug_build():
				print("[连锁] 连锁", link.chain_id, " 已被无效化，跳过")
			chain_resolved.emit(link.chain_id)
			continue
		
		# 执行这个连锁链的效果
		_execute_chain_link(link)
		chain_resolved.emit(link.chain_id)
	
	_ignore_chain = false
	_chain_resolving = false
	if OS.is_debug_build():
		print("[连锁] ===== 连锁结算完成 =====")
	
	# 检查胜利条件
	_check_win_condition()

## 执行单个连锁链效果
func _execute_chain_link(link: Dictionary) -> void:
	var owner = link.owner as BattlePlayer
	var card = link.card as BattleCard
	var effect = link.effect as Dictionary
	var slot = link.slot
	
	if not card or not is_instance_valid(card):
		if OS.is_debug_build():
			print("[连锁] 连锁链卡牌已失效，跳过")
		return
	
	if OS.is_debug_build():
		print("[连锁] 执行连锁", link.chain_id, ": ", card.get_display_name(), " (", owner.player_name, ")")
	
	# 直接执行效果（不再压入连锁栈）
	_ignore_chain = true
	_execute_effect(owner, card, effect, slot)
	_ignore_chain = false

## 条件和约束预检（在压入连锁栈之前调用）
## 返回 true 表示可以发动，false 表示被阻止
func _precheck_effect(owner: BattlePlayer, source_card: BattleCard, effect: Dictionary) -> bool:
	var parsed = Global.parse_circuit(effect)
	if not parsed.is_valid:
		return false
	# A33 禁用效果
	if source_card.effect_disabled:
		return false
	var opponent = player_self if owner == player_opponent else player_opponent
	# 条件检查
	for condition in parsed.conditions:
		if not Global.check_condition(condition, owner, opponent, source_card):
			if OS.is_debug_build():
				print("[效果] 条件不满足，效果被阻止: ", condition)
			return false
	# 约束检查
	if not _check_constraints_allowed(owner, source_card, effect, parsed):
		if OS.is_debug_build():
			print("[效果] 约束阻止了效果发动: ", source_card.get_display_name())
		return false
	return true

## 公开接口：执行效果时先压入连锁栈
func _execute_effect_with_chain(owner: BattlePlayer, source_card: BattleCard, effect: Dictionary, source_slot: int) -> void:
	"""效果执行入口：压入连锁栈 → 给对方响应机会 → 结算"""
	if _ignore_chain or _chain_resolving:
		# 连锁结算中或忽略连锁中，直接执行
		_execute_effect(owner, source_card, effect, source_slot)
		return
	
	# 压入连锁栈
	var chain_id = _push_to_chain(owner, source_card, effect, source_slot)
	if chain_id < 0:
		# 连锁已满，直接执行（不走连锁）
		if OS.is_debug_build():
			print("[连锁] 连锁已满，直接执行效果")
		_execute_effect(owner, source_card, effect, source_slot)
		return
	
	# 开始连锁构建（给对方响应机会）
	_start_chain_building()

## A30: 无效效果发动并破坏
func _execute_negate_and_destroy(owner: BattlePlayer, opponent: BattlePlayer, target_id: String) -> void:
	"""在连锁栈中查找指定链接，无效化并破坏来源卡"""
	if chain_stack.is_empty():
		if OS.is_debug_build():
			print("[连锁-A30] 连锁栈为空，无法无效化")
		return
	
	# 找到最新的没有被无效化的链
	var target_chain = null
	for i in range(chain_stack.size() - 1, -1, -1):
		var link = chain_stack[i]
		if not link.negated:
			target_chain = link
			break
	
	if target_chain == null:
		if OS.is_debug_build():
			print("[连锁-A30] 没有可无效化的效果")
		return
	
	# 标记为无效化
	target_chain.negated = true
	var target_card = target_chain.card as BattleCard
	if OS.is_debug_build():
		print("[连锁-A30] 无效化连锁", target_chain.chain_id, ": ", target_card.get_display_name())
	
	# 破坏来源卡（如果还在场上）
	if target_card and is_instance_valid(target_card) and target_card.is_alive():
		var target_owner = target_chain.owner as BattlePlayer
		var old_slot = target_card.slot_index
		target_owner.send_to_grave(target_card)
		_trigger_on_destroy(target_owner, target_card, old_slot)
		if OS.is_debug_build():
			print("[连锁-A30] 破坏卡牌: ", target_card.get_display_name())
# ===== 约束系统（Constraint System） =====

## 检查所有约束是否允许发动
func _check_constraints_allowed(owner: BattlePlayer, card: BattleCard, effect: Dictionary, parsed: Dictionary) -> bool:
	var constraint_ids = parsed.constraints
	if constraint_ids.is_empty():
		return true
	
	var opponent = _get_opponent_player() if owner == player_self else player_self
	var card_id = card.card_id if card.card_id else str(card.get_instance_id())
	
	for cid in constraint_ids:
		# 先检查Global中的基础检查（CO08-CO11等）
		if not Global.check_constraint(cid, owner, battle_state, current_phase, current_player_index):
			if OS.is_debug_build():
				print("[约束] ", cid, " 不满足发动条件，效果被阻止")
			return false
		
		# 运行时检查
		match cid:
			"CO01":  # 一回合一次
				if _constraint_used_once_per_turn.has(card_id) and _constraint_used_once_per_turn[card_id]:
					if OS.is_debug_build():
						print("[约束] CO01 一回合一次: ", card.get_display_name(), " 本回合已用过")
					return false
			
			"CO02":  # 一局一次
				if _constraint_used_once_per_game.has(card_id) and _constraint_used_once_per_game[card_id]:
					if OS.is_debug_build():
						print("[约束] CO02 一局一次: ", card.get_display_name(), " 本局已用过")
					return false
			
			"CO03":  # 支付生命（param=支付量）
				var cost = Global.get_constraint_param(effect, "CO03", 10)
				if owner.hp < cost:
					if OS.is_debug_build():
						print("[约束] CO03 支付生命: 生命不足, 需要", cost, " 当前", owner.hp)
					return false
			
			"CO04":  # 舍弃手牌（param=舍弃张数）
				var discard_count = Global.get_constraint_param(effect, "CO04", 1)
				if owner.hand.size() < discard_count:
					if OS.is_debug_build():
						print("[约束] CO04 舍弃手牌: 手牌不足, 需要", discard_count, " 当前", owner.hand.size())
					return false

			"CO05":  # 消耗能量点（param=消耗量）
				var energy_cost = Global.get_constraint_param(effect, "CO05", 1)
				if owner.energy < energy_cost:
					if OS.is_debug_build():
						print("[约束] CO05 消耗能量点: 能量不足, 需要", energy_cost, " 当前", owner.energy)
					return false
			
			"CO15":  # 仅对克制属性生效
				# 需要检查目标卡牌的属性，暂简化
				pass
			
			"CO16":  # 仅对被克制属性生效
				pass
	
	return true

## 执行约束的后处理（代价支付和效果后处理）
func _execute_constraint_effects(owner: BattlePlayer, card: BattleCard, effect: Dictionary, parsed: Dictionary) -> void:
	var constraint_ids = parsed.constraints
	if constraint_ids.is_empty():
		return
	
	var opponent = _get_opponent_player() if owner == player_self else player_self
	var card_id = card.card_id if card.card_id else str(card.get_instance_id())
	
	for cid in constraint_ids:
		match cid:
			"CO01":  # 一回合一次 — 标记已用
				_constraint_used_once_per_turn[card_id] = true
				if OS.is_debug_build():
					print("[约束] CO01 标记: ", card.get_display_name(), " 本回合已用")
			
			"CO02":  # 一局一次 — 标记已用
				_constraint_used_once_per_game[card_id] = true
				if OS.is_debug_build():
					print("[约束] CO02 标记: ", card.get_display_name(), " 本局已用")
			
			"CO03":  # 支付生命
				var cost = Global.get_constraint_param(effect, "CO03", 10)
				owner.damage_hero(cost)
				if OS.is_debug_build():
					print("[约束] CO03 支付生命: -", cost, " HP(", owner.hp, "/", owner.max_hp, ")")
			
			"CO04":  # 舍弃手牌（已由 _execute_effect 的 request_discard 统一处理：玩家弹窗/AI评分）
				pass
			
			"CO05":  # 消耗能量点（后处理：实际扣除能量）
				var energy_cost = Global.get_constraint_param(effect, "CO05", 1)
				owner.energy -= energy_cost
				owner.energy_changed.emit(owner.energy, owner.max_energy)
				if OS.is_debug_build():
					print("[约束] CO05 消耗能量点: -", energy_cost, " 能量(", owner.energy, "/", owner.max_energy, ")")
			
			"CO06":  # 发动后除外
				if card and is_instance_valid(card) and card.is_on_field:
					owner.banish_card(card)
					if OS.is_debug_build():
						print("[约束] CO06 发动后除外: ", card.get_display_name())
			
			"CO07":  # 效果后自毁
				if card and is_instance_valid(card) and card.is_alive():
					var old_slot = card.slot_index
					owner.send_to_grave(card)
					_trigger_on_destroy(owner, card, old_slot)
					if OS.is_debug_build():
						print("[约束] CO07 效果后自毁: ", card.get_display_name())
			
			"CO12":  # 发动后受伤害
				var damage = Global.get_constraint_param(effect, "CO12", 5)
				owner.damage_hero(damage)
				if OS.is_debug_build():
					print("[约束] CO12 发动后受伤害: -", damage, " HP(", owner.hp, "/", owner.max_hp, ")")

## 清空回合级约束（每回合准备阶段调用）
func _reset_turn_constraints() -> void:
	_constraint_used_once_per_turn.clear()
	_constraint_effect_count = 0
	if OS.is_debug_build():
		print("[约束] 回合约束已重置")


# ===== 获取当前/对方玩家 =====

func _get_current_player() -> BattlePlayer:
	return player_self if current_player_index == 0 else player_opponent

func _get_opponent_player() -> BattlePlayer:
	return player_opponent if current_player_index == 0 else player_self

func is_player_turn() -> bool:
	return current_player_index == 0

## 获取己方当前能量
func get_player_energy() -> int:
	return player_self.energy


# ===== 抽象操作方法（统一管理所有操作） =====

## 检查操作是否可行
func can_do_action(action_type: String, params: Dictionary = {}) -> Dictionary:
	var result = {"allowed": false, "reason": ""}
	if battle_state != State.PLAYING:
		result.reason = "战斗已结束"
		return result
	
	match action_type:
		"end_main_phase":
			result.allowed = (current_phase == Phase.MAIN and current_player_index == 0)
			if not result.allowed: result.reason = "当前不在己方主要阶段"
		
		"end_battle_phase":
			result.allowed = (current_phase == Phase.BATTLE and current_player_index == 0)
			if not result.allowed: result.reason = "当前不在己方战斗阶段"
		
		"summon":
			var hand_index = params.get("hand_index", -1)
			var slot_index = params.get("slot_index", -1)
			if current_phase != Phase.MAIN or current_player_index != 0:
				result.reason = "只能在己方主要阶段召唤"
			elif hand_index < 0 or hand_index >= player_self.hand.size():
				result.reason = "手牌索引无效"
			elif slot_index < 0 or slot_index >= player_self.max_field_size:
				result.reason = "场地索引无效"
			elif player_self.field[slot_index] != null:
				result.reason = "该场地已有卡牌"
			else:
				var card = player_self.hand[hand_index] as BattleCard
				if card.base_cost > player_self.energy:
					result.reason = "能量不足（需要" + str(card.base_cost) + "，当前" + str(player_self.energy) + "）"
				else:
					result.allowed = true
					result.reason = ""
		
		"attack":
			var slot = params.get("slot", -1)
			if current_phase != Phase.BATTLE or current_player_index != 0:
				result.reason = "只能在己方战斗阶段攻击"
			elif slot < 0 or slot >= player_self.max_field_size:
				result.reason = "场地索引无效"
			elif player_self.field[slot] == null:
				result.reason = "该位置没有卡牌"
			elif not player_self.field[slot].can_attack():
				result.reason = "该卡牌不能攻击"
			else:
				result.allowed = true
		
		"attack_hero":
			result = can_do_action("attack", params)
			if result.allowed:
				# 检查对方场上是否有卡牌
				if player_opponent.get_field_count() > 0:
					result.allowed = false
					result.reason = "对方场上有卡牌，必须先攻击卡牌"
		
		"end_turn":
			result.allowed = (current_player_index == 0 and current_phase == Phase.MAIN)
			if not result.allowed: result.reason = "当前不能结束回合"
	
	return result


## 执行操作
func do_action(action_type: String, params: Dictionary = {}) -> Dictionary:
	var result = {"success": false, "reason": "", "data": {}}
	var check = {"allowed": false, "reason": ""}
	
	if battle_state != State.PLAYING:
		result.reason = "战斗已结束"
		action_result.emit(action_type, false, result)
		return result
	
	match action_type:
		"end_main_phase":
			check = can_do_action("end_main_phase")
			if check.allowed:
				current_phase = Phase.BATTLE
				_attacked_this_battle.clear()
				phase_changed.emit(Phase.BATTLE, current_player_index)
				if OS.is_debug_build():
					print("[战斗] 进入战斗阶段")
				result.success = true
				result.data = {"phase": "battle"}
		
		"end_battle_phase":
			check = can_do_action("end_battle_phase")
			if check.allowed:
				_enter_phase(Phase.END)
				result.success = true
				result.data = {"phase": "end"}
		
		"summon":
			# summon 现在是通用"打出卡牌"动作的别名
			result = _play_card(player_self, params)
			if result.success:
				# 兼容旧返回值
				if not result.data.has("slot"):
					result.data["slot"] = params.get("slot_index", -1)
				_check_win_condition()
				action_result.emit(action_type, true, result)
			else:
				if result.reason == "":
					result.reason = check.get("reason", "出牌失败")
				action_result.emit(action_type, false, result)
			return result
		
		"play_card":
			result = _play_card(player_self, params)
			if result.success:
				_check_win_condition()
				action_result.emit(action_type, true, result)
			else:
				action_result.emit(action_type, false, result)
			return result
		
		"attack":
			check = can_do_action("attack", params)
			if check.allowed:
				var slot = params.get("slot", -1)
				var target_slot = params.get("target_slot", -1)
				var attacker = player_self.field[slot]
				
				if target_slot >= 0 and target_slot < player_opponent.max_field_size and player_opponent.field[target_slot] != null:
					var defender = player_opponent.field[target_slot]
					
					# === 触发 TR09: 攻击宣言时（攻击方自身） + TR10: 被攻击时（防御方自身） ===
					_trigger_card_trigger("TR09", player_self, attacker, slot)
					_trigger_card_trigger("TR10", player_opponent, defender, target_slot, false)
					
					var atk_result = player_self.attack(slot, defender)
					result.data = atk_result
					
					# 元素克制飘字
					var eb = atk_result.get("element_boost", {})
					if eb.get("type", "") != "":
						element_boost_triggered.emit("affinity", eb.get("atk_elem", ""), eb.get("def_elem", ""), eb.get("from_value", 0), eb.get("to_value", 0), true, slot)
					
					# === 触发 TR11: 给予战斗伤害时（攻击方自身） ===
					if atk_result.get("damage_to_defender", 0) > 0:
						_trigger_card_trigger("TR11", player_self, attacker, slot)
					
					# 送墓被破坏的卡牌（触发TR06/TR08在send_to_grave中）
					if atk_result.get("attacker_destroyed", false):
						var old_slot = attacker.slot_index
						player_self.send_to_grave(attacker)
						_trigger_on_destroy(player_self, attacker, old_slot)
					if atk_result.get("defender_destroyed", false):
						var old_slot = defender.slot_index
						player_opponent.send_to_grave(defender)
						_trigger_on_destroy(player_opponent, defender, old_slot)
					
					result.success = true
				else:
					result.reason = "攻击目标无效"
		
		"attack_hero":
			check = can_do_action("attack_hero", params)
			if check.allowed:
				var slot = params.get("slot", -1)
				var attacker = player_self.field[slot]
				# === 触发 TR09: 攻击宣言时（攻击方自身） ===
				_trigger_card_trigger("TR09", player_self, attacker, slot)
				var atk_result = player_self.attack_hero(slot, player_opponent.hp, player_opponent)
				player_opponent.hp = atk_result.get("new_hp", player_opponent.hp)
				player_opponent.hp_changed.emit(player_opponent.hp + atk_result.get("damage", 0), player_opponent.hp)
				# === 触发 TR11: 给予战斗伤害时（攻击方自身） ===
				if atk_result.get("damage", 0) > 0:
					_trigger_card_trigger("TR11", player_self, attacker, slot)
				result.data = atk_result
				result.success = true
				
				# 检查胜利条件
				_check_win_condition()
		
		"end_turn":
			current_phase = Phase.END
			phase_changed.emit(Phase.END, current_player_index)
			_enter_phase(Phase.END)
			result.success = true
		# "discard_done" 已废弃 → 改用 request_discard + _on_discard_result 回调机制
	
	if result.success:
		action_result.emit(action_type, true, result)
	else:
		if result.reason == "":
			result.reason = check.get("reason", "操作不允许")
		action_result.emit(action_type, false, result)
	
	return result


# ===== 卡牌打出逻辑 =====

## 统一召唤卡牌（所有卡牌类型统一处理）
## 返回 {"success": bool, "reason": str, "data": {"slot": int, ...}}
func _play_card(player: BattlePlayer, params: Dictionary) -> Dictionary:
	var result = {"success": false, "reason": "", "data": {}}
	
	var hand_index = params.get("hand_index", -1)
	var slot_index = params.get("slot_index", -1)
	
	# 参数检查
	if hand_index < 0 or hand_index >= player.hand.size():
		result.reason = "手牌索引无效"
		return result
	if slot_index < 0 or slot_index >= player.max_field_size:
		result.reason = "场地索引无效"
		return result
	
	var card = player.hand[hand_index] as BattleCard
	if card == null:
		result.reason = "卡牌数据为空"
		return result
	
	# 能量检查（考虑辅材能量减免）
	if player.energy < card.get_actual_cost():
		result.reason = "能量不足"
		return result
	
	# 场地检查
	if player.field[slot_index] != null:
		result.reason = "该位置已有卡牌"
		return result
	
	# 执行召唤
	var summoned = player.summon_from_hand(hand_index, slot_index)
	if not summoned:
		result.reason = "召唤失败"
		return result
	
	# 召唤成功，卡已在场上
	var summoned_card = player.field[slot_index] as BattleCard
	if summoned_card == null:
		result.reason = "召唤后卡牌丢失"
		return result
	
	result.success = true
	result.data["slot"] = slot_index
	result.data["card"] = summoned_card
	result.data["hand_index"] = hand_index
	
	# 打印召唤信息
	if OS.is_debug_build():
		print("[战斗] 打出卡牌: ", summoned_card.get_display_name(), 
		  " (", summoned_card.current_atk, "/", summoned_card.current_hp, ") → 场地", slot_index)
	
	# 效果执行延迟到表现层飞入完成后（由3D层调 _execute_on_summon_effects）
	# 不再在此同步执行效果和0/0送墓
	
	return result

## 召唤成功后处理效果（由3D层在卡牌飞到场地后调用）
func _execute_on_summon_effects(player: BattlePlayer, card: BattleCard, slot_index: int) -> void:
	# 1. 辅材召唤效果（抽牌/疾风等）
	var aux_effects = card.get_summon_aux_effects()
	if aux_effects.size() > 0:
		if aux_effects.has("draw"):
			var draw_count = aux_effects["draw"]
			for i in range(draw_count):
				player.draw_card()
			if OS.is_debug_build():
				print("[战斗] 辅材效果: 上场抽", draw_count, "张牌")
		if aux_effects.get("haste", false):
			card.has_attacked = false
			if OS.is_debug_build():
				print("[战斗] 辅材效果: 疾风之羽，当回合可攻击")
	
	# 2. 触发所有 "召唤时" 效果（纹路格式：trigger="TR01"，兼容旧格式type="instant"/"buff"）
	# 这些效果通过连锁系统执行，对手可响应
	# 条件+约束预检在压入连锁栈之前
	for effect in card.effects:
		var effect_type = effect.get("type", "")
		var effect_trigger = effect.get("trigger", "")
		var should_execute = false
		# 新格式：TR01=召唤成功时 → 走连锁系统
		if effect_trigger == "TR01":
			should_execute = true
		# 旧格式兼容 → 走连锁系统
		elif effect_type == "instant" or effect_type == "buff":
			should_execute = true
		elif effect_type == "trigger" and effect.get("trigger", "") == "on_summon":
			should_execute = true
		# 条件+约束预检通过才执行
		if should_execute and _precheck_effect(player, card, effect):
			_execute_effect_with_chain(player, card, effect, slot_index)
	
	# 3. 检查是否为0/0卡牌（生命<=0），自然送墓
	if card.current_hp <= 0:
		if OS.is_debug_build():
			print("[战斗] 0/0卡牌自然送墓: ", card.get_display_name())
		player.send_to_grave(card)
		# 触发送墓效果
		_trigger_on_destroy(player, card, card.slot_index)
	
	# 4. 触发 TR17: 对方召唤成功时（扫描对方场上）— 在TR01效果执行完之后
	var opponent_17 = player_self if player == player_opponent else player_opponent
	_scan_and_trigger("TR17", opponent_17)

## 触发周期性效果（回合开始/结束）
func _execute_periodic_effects(player: BattlePlayer, phase: String) -> void:
	# 扫描场上所有己方卡牌，找出 phase 匹配的 periodic 效果
	for i in range(player.max_field_size):
		var card = player.field[i] as BattleCard
		if card == null or not card.is_alive():
			continue
		for effect in card.effects:
			var effect_type = effect.get("type", "")
			var effect_phase = effect.get("phase", "")
			var effect_trigger = effect.get("trigger", "")
			var should_execute = false
			# 新格式：TR12=己方回合开始，TR14=己方回合结束 → 走连锁系统
			if effect_trigger == "TR12" and phase == "start_of_turn":
				should_execute = true
			elif effect_trigger == "TR14" and phase == "end_of_turn":
				should_execute = true
			# 旧格式兼容 → 走连锁系统
			elif effect_type == "periodic" and effect_phase == phase:
				should_execute = true
			# 条件+约束预检通过才执行
			if should_execute and _precheck_effect(player, card, effect):
				_execute_effect_with_chain(player, card, effect, i)
## 通用触发器扫描器：扫描场上所有存活卡牌，查找匹配 trigger_id 的效果
## trigger_id: TR01-TR17
## player: 要扫描的玩家（通常是触发方的对手或全场）
## context: 额外上下文（可选）
func _scan_and_trigger(trigger_id: String, player: BattlePlayer, context: Dictionary = {}) -> void:
	var opponent = _get_opponent_player() if player == player_self else player_self
	for i in range(player.max_field_size):
		var card = player.field[i] as BattleCard
		if card == null or not card.is_alive():
			continue
		# A33 禁用效果：被禁用的卡本回合不触发任何效果
		if card.effect_disabled:
			continue
		for effect in card.effects:
			var parsed = Global.parse_circuit(effect)
			if not parsed.is_valid:
				continue
			if parsed.trigger != trigger_id:
				continue
			# 条件+约束预检（在压入连锁栈之前）
			if _precheck_effect(player, card, effect):
				# 扫描触发器效果通过连锁系统执行，对手可响应
				_execute_effect_with_chain(player, card, effect, i)

## 触发单张卡的指定纹路（只触发这一张卡，不扫描全场）
## 用于攻击宣言（TR09/TR10）等只应由具体卡牌自身触发的效果
func _trigger_card_trigger(trigger_id: String, owner: BattlePlayer, card: BattleCard, slot: int, require_alive: bool = true) -> void:
	if card == null:
		return
	if require_alive and not card.is_alive():
		return
	# A33 禁用效果：被禁用的卡不触发自身效果
	if card.effect_disabled:
		return
	for effect in card.effects:
		var parsed = Global.parse_circuit(effect)
		if not parsed.is_valid:
			continue
		if parsed.trigger != trigger_id:
			continue
		# 条件+约束预检（在压入连锁栈之前）
		if _precheck_effect(owner, card, effect):
			_execute_effect_with_chain(owner, card, effect, slot)
## 执行单个效果（使用全局纹路系统）
func _execute_effect(owner: BattlePlayer, source_card: BattleCard, effect: Dictionary, source_slot: int) -> void:
	# 解析纹路效果（支持新格式和旧格式兼容）
	var parsed = Global.parse_circuit(effect)
	if not parsed.is_valid:
		if OS.is_debug_build():
			print("[效果] 无效纹路，跳过: ", effect)
		return
	
	var action_id = parsed.get("action", "A01")
	var target_id = parsed.get("target", "T01")
	var value = parsed.get("value", 0)
	var trigger_id = parsed.get("trigger", "TR01")
	
	var opponent = player_self if owner == player_opponent else player_opponent
	
	# === 条件检查：在效果执行前检查条件是否满足（特别是C08能量点） ===
	for condition in parsed.conditions:
		if not Global.check_condition(condition, owner, opponent, source_card):
			if OS.is_debug_build():
				print("[效果] 条件不满足，效果被阻止: ", condition)
			return
	
	# === 约束检查：在效果执行前检查约束是否允许发动 ===
	if not _check_constraints_allowed(owner, source_card, effect, parsed):
		if OS.is_debug_build():
			print("[效果] 约束阻止了效果发动")
		return
	
	# 打印效果信息
	var desc = Global.format_effect_description(parsed)
	if OS.is_debug_build():
		print("[效果] ", owner.player_name, " 的 ", source_card.get_display_name(), 
		  " 触发: ", desc)
	
	# 计算目标卡牌名和槽位（飘窗+画线用）
	var is_player = (owner == player_self)
	var target_card_name = ""
	var target_slot = -1
	var target_is_player = is_player
	match target_id:
		"T01":  # 自身
			target_card_name = source_card.get_display_name()
			target_slot = source_slot
		"T02":  # 敌方单体（随机，英雄保底仅限加减血）
			var tc = _pick_random_field_card(opponent)
			if tc != null:
				target_card_name = tc.get_display_name()
				target_slot = tc.slot_index
				target_is_player = not is_player
			elif action_id in ["A01"]:
				# 场上无卡，伤害重定向到敌方英雄
				target_id = "T07"
				target_card_name = "敌方英雄"
				target_slot = -1
				target_is_player = not is_player
			else:
				# 非加减血操作，场上无卡时无效
				if OS.is_debug_build():
					print("[效果] 敌方场上无卡牌，效果无法生效")
				return
		"T03":  # 己方单体（随机，英雄保底仅限加减血）
			var tc2 = _pick_random_field_card(owner)
			if tc2 != null:
				target_card_name = tc2.get_display_name()
				target_slot = tc2.slot_index
				target_is_player = is_player
			elif action_id in ["A02"]:
				# 场上无卡，治疗重定向到己方英雄
				target_id = "T08"
				target_card_name = "己方英雄"
				target_slot = -1
				target_is_player = is_player
			elif action_id in ["A09"]:
				# 抽牌不依赖场上卡牌，直接对玩家使用
				target_card_name = "己方"
				target_slot = -1
				target_is_player = is_player
			else:
				# 非加减血操作，场上无卡时无效
				if OS.is_debug_build():
					print("[效果] 己方场上无卡牌，效果无法生效")
				return
		"T04":  # 敌方全体
			target_card_name = "敌方全体"
			target_slot = -1
			target_is_player = not is_player
		"T05":  # 己方全体
			target_card_name = "己方全体"
			target_slot = -1
			target_is_player = is_player
		"T06":  # 全场
			target_card_name = "全场"
			target_slot = -1
			target_is_player = false
		"T07":  # 敌方英雄
			target_card_name = "敌方英雄"
			target_slot = -1
			target_is_player = not is_player
		"T08":  # 己方英雄
			target_card_name = "己方英雄"
			target_slot = -1
			target_is_player = is_player
		"T13":  # 对方攻击最高
			var ec = _pick_attack_extreme_card(opponent, true)
			if ec != null:
				target_card_name = ec.get_display_name()
				target_slot = ec.slot_index
				target_is_player = not is_player
			else:
				if OS.is_debug_build():
					print("[效果] 对方场上无卡牌，效果无法生效")
				return
		"T14":  # 对方攻击最低
			var ec2 = _pick_attack_extreme_card(opponent, false)
			if ec2 != null:
				target_card_name = ec2.get_display_name()
				target_slot = ec2.slot_index
				target_is_player = not is_player
			else:
				if OS.is_debug_build():
					print("[效果] 对方场上无卡牌，效果无法生效")
				return
		"T15":  # 我方攻击最高
			var ec3 = _pick_attack_extreme_card(owner, true)
			if ec3 != null:
				target_card_name = ec3.get_display_name()
				target_slot = ec3.slot_index
				target_is_player = is_player
			else:
				if OS.is_debug_build():
					print("[效果] 己方场上无卡牌，效果无法生效")
				return
		"T16":  # 我方攻击最低
			var ec4 = _pick_attack_extreme_card(owner, false)
			if ec4 != null:
				target_card_name = ec4.get_display_name()
				target_slot = ec4.slot_index
				target_is_player = is_player
			else:
				if OS.is_debug_build():
					print("[效果] 己方场上无卡牌，效果无法生效")
				return
	
	# T13-T16 目标已解析为具体槽位，统一映射为 T02/T03 供后续动作执行
	if target_id in ["T13", "T14"]:
		target_id = "T02"
	elif target_id in ["T15", "T16"]:
		target_id = "T03"
	
	# 发射效果发动通知（飘窗用+画线用）
	card_effect_activated.emit(source_card.get_display_name(), desc, action_id, target_id, value, target_card_name, source_slot, is_player, target_slot, target_is_player, effect)
	
	# 执行约束后处理（代价支付等）
	# CO04 舍弃手牌：先走弃牌（玩家弹窗/AI评分），弃完回调再执行其余约束+动作分发
	var _has_co04: bool = parsed.constraints.has("CO04")
	if _has_co04:
		request_discard(owner, Global.get_constraint_param(effect, "CO04", 1), "CO04", func():
			_execute_constraint_effects(owner, source_card, effect, parsed)
			_dispatch_effect_action(owner, opponent, source_card, source_slot, action_id, target_id, target_slot, value, desc, parsed, is_player)
		)
	else:
		_execute_constraint_effects(owner, source_card, effect, parsed)
		_dispatch_effect_action(owner, opponent, source_card, source_slot, action_id, target_id, target_slot, value, desc, parsed, is_player)

## 根据动作ID分发执行效果（供 CO04 弃牌弹窗回调后继续执行）
func _dispatch_effect_action(owner: BattlePlayer, opponent: BattlePlayer, source_card: BattleCard, source_slot: int, action_id: String, target_id: String, target_slot: int, value: int, desc: String, parsed: Dictionary, is_player: bool) -> void:
	# 根据动作ID分发执行
	match action_id:
		# === 伤害效果 ===
		"A01":
			var final_damage = value
			var original_damage = value
			# 🔥 火元素：效果伤害受 element_power_bonus 加成；克制目标时额外+20%
			var src_elem = source_card.get_effective_element()
			var power_mult = Global.get_element_power_multiplier(src_elem, source_card.element_power_bonus, "damage")
			final_damage = roundi(float(final_damage) * power_mult)
			# 元素加成飘字（数值有变化时）
			if final_damage != original_damage:
				element_boost_triggered.emit("power", src_elem, "", original_damage, final_damage, owner == player_self, source_slot)
			_execute_damage_action(owner, opponent, source_card, target_id, final_damage, target_slot)
		
		# === 恢复效果 ===
		"A02":
			var final_heal = value
			# 💧 水元素：治疗效果受 element_power_bonus 加成
			var src_elem2 = source_card.get_effective_element()
			var power_mult2 = Global.get_element_power_multiplier(src_elem2, source_card.element_power_bonus, "heal")
			var original_heal = final_heal
			final_heal = roundi(float(final_heal) * power_mult2)
			# 元素加成飘字
			if final_heal != original_heal:
				element_boost_triggered.emit("power", src_elem2, "", original_heal, final_heal, owner == player_self, source_slot)
			_execute_heal_action(owner, opponent, source_card, target_id, final_heal, target_slot)
		
		# === 破坏效果 ===
		"A03":
			_execute_destroy_action(owner, opponent, source_card, target_id, target_slot)
		
		# === 除外效果 ===
		"A04":
			_execute_banish_action(owner, opponent, source_card, target_id, target_slot)
		
		# === 抽牌效果 ===
		"A09":
			var final_draw = value
			# 🌪️ 风元素：抽牌数量受 element_power_bonus 加成（四舍五入取整）
			var src_elem3 = source_card.get_effective_element()
			var power_mult3 = Global.get_element_power_multiplier(src_elem3, source_card.element_power_bonus, "draw")
			var original_draw = final_draw
			final_draw = roundi(float(final_draw) * power_mult3)
			# 元素加成飘字
			if final_draw != original_draw:
				element_boost_triggered.emit("power", src_elem3, "", original_draw, final_draw, owner == player_self, source_slot)
			_execute_draw_action(owner, opponent, target_id, final_draw)
		
		# === 召唤衍生物 ===
		"A19":
			_execute_token_summon(owner, source_card)
		
		# === 永久增益 ===
		"A20":
			var final_value = value
			_execute_stat_buff(owner, source_card, target_id, "atk_up", final_value, target_slot)
		"A21":
			var final_value = value
			if final_value < 0:
				# 负数 = 扣血 → 走效果伤害逻辑（🔥火元素加成 + 克制）
				var dmg = abs(final_value)
				var src_elem_d = source_card.get_effective_element()
				var power_mult_d = Global.get_element_power_multiplier(src_elem_d, source_card.element_power_bonus, "damage")
				var original_dmg = dmg
				dmg = roundi(float(dmg) * power_mult_d)
				# 元素加成飘字
				if dmg != original_dmg:
					element_boost_triggered.emit("power", src_elem_d, "", original_dmg, dmg, owner == player_self, source_slot)
				_execute_damage_action(owner, opponent, source_card, target_id, dmg, target_slot)
			else:
				# 正数 = 回血 → 走治疗逻辑（💧水元素加成）
				var heal = final_value
				var src_elem_h = source_card.get_effective_element()
				var power_mult_h = Global.get_element_power_multiplier(src_elem_h, source_card.element_power_bonus, "heal")
				var original_heal = heal
				heal = roundi(float(heal) * power_mult_h)
				# 元素加成飘字
				if heal != original_heal:
					element_boost_triggered.emit("power", src_elem_h, "", original_heal, heal, owner == player_self, source_slot)
				_execute_heal_action(owner, opponent, source_card, target_id, heal, target_slot)
		"A22":
			var final_value = value
			_execute_stat_buff(owner, source_card, target_id, "atk_up", final_value, target_slot)
			_execute_stat_buff(owner, source_card, target_id, "hp_up", final_value, target_slot)
		
		# === 除外墓地卡 ===
		"A05":
			_execute_banish_from_grave_action(owner, opponent, target_id)
		
		# === 弹回手牌 ===
		"A06":
			_execute_bounce_to_hand(owner, opponent, source_card, target_id, target_slot)
		
		# === 弹回卡组 ===
		"A07":
			_execute_bounce_to_deck(owner, opponent, source_card, target_id, target_slot)
		
		# === 送入墓地 ===
		"A08":
			_execute_send_to_grave_action(owner, opponent, source_card, target_id, target_slot)
		
		# === 检索字段卡 ===
		"A10":
			var field_name = parsed.get("field", "")
			_execute_search_field(owner, target_id, field_name, value)
		
		# === 检索卡 ===
		"A11":
			_execute_search_any(owner, target_id, value)
		
		# === 墓地回收 ===
		"A12":
			_execute_recycle_from_grave(owner, target_id, value)
		
		# === 除外回收 ===
		"A13":
			_execute_recycle_from_banish(owner, target_id, value)
		
		# === 卡组堆墓 ===
		"A14":
			_execute_mill_from_deck(owner, target_id, value)
		
		# === 手牌特召 ===
		"A15":
			_execute_special_summon_from_hand(owner, source_card, target_id, value)
		
		# === 墓地特召 ===
		"A16":
			_execute_special_summon_from_grave(owner, target_id, value)
		
		# === 卡组特召 ===
		"A17":
			_execute_special_summon_from_deck(owner, target_id, value)
		
		# === 除外特召 ===
		"A18":
			_execute_special_summon_from_banish(owner, target_id, value)
		
		# === 回合内攻命增减 ===
		"A23":
			var final_value = value
			_execute_temp_stat_change(owner, source_card, target_id, "atk", final_value, target_slot)
		
		# === 全场增减 ===
		"A24":
			var final_value = value
			_execute_all_field_stat_change(owner, opponent, target_id, final_value)
		
		# === 交换攻防 ===
		"A25":
			_execute_swap_atk_hp(owner, opponent, target_id, target_slot)
		
		# === 暂时夺取控制权 ===
		"A26":
			_execute_take_control_temporary(owner, opponent, target_id, target_slot)
		
		# === 永久夺取控制权 ===
		"A27":
			_execute_take_control_permanent(owner, opponent, target_id, target_slot)

		# === 控制权变更·一回合（配敌方目标=夺给我方；配己方目标=送对方）===
		"A31":
			_execute_control_change(owner, opponent, target_id, target_slot, true)

		# === 控制权变更·永久（同上，不归还）===
		"A32":
			_execute_control_change(owner, opponent, target_id, target_slot, false)

		# === 禁用效果（一回合）===
		"A33":
			_execute_disable_effect(owner, opponent, target_id, target_slot)
		
		# === 无法攻击 ===
		"A28":
			_execute_cannot_attack(owner, opponent, target_id, target_slot)
		
		# === 表示形式变更 ===
		"A29":
			_execute_change_form(owner, opponent, target_id, target_slot)
		
		# === 无效效果发动并破坏 ===
		"A30":
			_execute_negate_and_destroy(owner, opponent, target_id)
		
		_:
			if OS.is_debug_build():
				print("[效果] 未知动作: ", action_id)
	
	# 发射效果触发信号，让BattleScene显示飘字和闪烁
	is_player = (owner == player_self)
	effect_triggered.emit(action_id, value, is_player, source_slot, desc)
	
	# 刷新双方场地UI，让数值变化检测触发浮动数字和动画
	player_self.field_changed.emit()
	player_opponent.field_changed.emit()
	
	# === 触发 TR16: 对方发动效果时（扫描对方场上） ===
	var effect_opponent = _get_opponent_player() if owner == player_self else player_self
	_scan_and_trigger("TR16", effect_opponent)

## 随机选择一个场上存活卡牌（单体目标用）
func _pick_random_field_card(player: BattlePlayer) -> BattleCard:
	var alive := []
	for i in range(player.max_field_size):
		var c = player.field[i]
		if c != null and c.is_alive():
			alive.append(c)
	if alive.is_empty():
		return null
	return alive[randi() % alive.size()]

## 选取攻击力最高(extreme=true)/最低(extreme=false)的场上存活卡（T13~T16）
func _pick_attack_extreme_card(player: BattlePlayer, extreme: bool) -> BattleCard:
	var best: BattleCard = null
	for i in range(player.max_field_size):
		var c = player.field[i]
		if c == null or not c.is_alive():
			continue
		if best == null:
			best = c
			continue
		if extreme:
			if c.current_atk > best.current_atk:
				best = c
		else:
			if c.current_atk < best.current_atk:
				best = c
	return best

## 伤害动作执行
func _execute_damage_action(owner: BattlePlayer, opponent: BattlePlayer, source_card: BattleCard, target_id: String, damage: int, target_slot: int = -1) -> void:
	var is_player = (owner == player_self)
	var owner_tag = "【我方】" if is_player else "【敌方】"
	# 源卡槽位（用于画线）
	var from_slot = source_card.slot_index
	# 源卡元素（用于克制判断）
	var src_elem = source_card.get_effective_element()
	match target_id:
		"T07":  # 敌方英雄
			var dmg = opponent.damage_hero(damage)
			if OS.is_debug_build():
				print("[战斗] ", owner_tag, source_card.get_display_name(), " 发动效果：对敌方英雄造成", dmg, "点伤害")
			_check_win_condition()
		"T02":  # 敌方单体（使用预解析的槽位）
			if target_slot >= 0 and target_slot < opponent.max_field_size:
				var target_card = opponent.field[target_slot]
				if target_card != null and target_card.is_alive():
					# 元素克制：源卡元素克制目标元素时额外+20%
					var target_elem = target_card.get_effective_element()
					var affinity = Global.get_element_affinity(src_elem, target_elem)
					var actual_damage = roundi(float(damage) * affinity)
					if affinity > 1.0:
						if OS.is_debug_build():
							print("[元素克制] ", source_card.get_display_name(), " (", src_elem, ") 克制 ", target_card.get_display_name(), " (", target_elem, ") 伤害 x", affinity)
						element_boost_triggered.emit("affinity", src_elem, target_elem, damage, actual_damage, is_player, from_slot)
					target_card.take_damage(actual_damage)
					# 画线：源→目标
					effect_line_fromto.emit(from_slot, is_player, target_slot, not is_player, "A01")
					var destroyed = not target_card.is_alive()
					var destroy_tag = "（破坏）" if destroyed else ""
					if OS.is_debug_build():
						print("[战斗] ", owner_tag, source_card.get_display_name(), " 发动效果", destroy_tag, "：", target_card.get_display_name(), " 生命-", actual_damage, " → ", target_card.current_hp)
					opponent.cleanup_destroyed()
		"T04":  # 敌方全体
			var destroyed_count = 0
			for i in range(opponent.max_field_size):
				var target_card = opponent.field[i]
				if target_card != null and target_card.is_alive():
					# 元素克制（逐目标判断）
					var target_elem = target_card.get_effective_element()
					var affinity = Global.get_element_affinity(src_elem, target_elem)
					var actual_damage = roundi(float(damage) * affinity)
					if affinity > 1.0:
						element_boost_triggered.emit("affinity", src_elem, target_elem, damage, actual_damage, is_player, from_slot)
					target_card.take_damage(actual_damage)
					# 逐卡画线：源→每张目标卡
					effect_line_fromto.emit(from_slot, is_player, i, not is_player, "A01")
					var destroyed = not target_card.is_alive()
					if destroyed:
						destroyed_count += 1
					var destroy_tag = "（破坏）" if destroyed else ""
					if OS.is_debug_build():
						print("[战斗] ", owner_tag, source_card.get_display_name(), " 发动效果", destroy_tag, "：", target_card.get_display_name(), " 生命-", actual_damage, " → ", target_card.current_hp)
			opponent.cleanup_destroyed()
			if destroyed_count > 0:
				if OS.is_debug_build():
					print("[战斗] → 敌方全场清理，", destroyed_count, "张卡被破坏")
		"T06":  # 全场（双方都受伤）
			# 敌方侧
			for i in range(opponent.max_field_size):
				var target_card = opponent.field[i]
				if target_card != null and target_card.is_alive():
					var target_elem = target_card.get_effective_element()
					var affinity = Global.get_element_affinity(src_elem, target_elem)
					var actual_damage = roundi(float(damage) * affinity)
					if affinity > 1.0:
						element_boost_triggered.emit("affinity", src_elem, target_elem, damage, actual_damage, is_player, from_slot)
					target_card.take_damage(actual_damage)
					effect_line_fromto.emit(from_slot, is_player, i, not is_player, "A01")
					if OS.is_debug_build():
						print("[战斗] ", owner_tag, source_card.get_display_name(), " 全场效果：敌方", target_card.get_display_name(), " 受到", actual_damage, "点伤害")
			opponent.cleanup_destroyed()
			# 己方侧
			for i in range(owner.max_field_size):
				var target_card = owner.field[i]
				if target_card != null and target_card.is_alive():
					# 己方侧不应用克制（源卡不会克制自己人）
					target_card.take_damage(damage)
					effect_line_fromto.emit(from_slot, is_player, i, is_player, "A01")
					if OS.is_debug_build():
						print("[战斗] ", owner_tag, source_card.get_display_name(), " 全场效果：己方", target_card.get_display_name(), " 受到", damage, "点伤害")
			owner.cleanup_destroyed()
		"enemy_hero":  # 旧格式兼容
			var dmg = opponent.damage_hero(damage)
			if OS.is_debug_build():
				print("[战斗] ", owner_tag, source_card.get_display_name(), " 发动效果：对敌方英雄造成", dmg, "点伤害")
			_check_win_condition()
		"enemy_all":  # 旧格式兼容
			for i in range(opponent.max_field_size):
				var target_card = opponent.field[i]
				if target_card != null and target_card.is_alive():
					target_card.take_damage(damage)
					var destroyed = not target_card.is_alive()
					var destroy_tag = "（破坏）" if destroyed else ""
					if OS.is_debug_build():
						print("[战斗] ", owner_tag, source_card.get_display_name(), " 发动效果", destroy_tag, "：", target_card.get_display_name(), " 生命-", damage, " → ", target_card.current_hp)
			opponent.cleanup_destroyed()
		"enemy":  # 旧格式兼容
			var dmg = opponent.damage_hero(damage)
			if OS.is_debug_build():
				print("[战斗] ", owner_tag, source_card.get_display_name(), " 发动效果：对敌方英雄造成", dmg, "点伤害")
			_check_win_condition()
		_:  # 默认攻击敌方英雄
			var dmg = opponent.damage_hero(damage)
			if OS.is_debug_build():
				print("[战斗] ", owner_tag, source_card.get_display_name(), " 发动效果：对敌方英雄造成", dmg, "点伤害")
			_check_win_condition()
## 治疗动作执行
func _execute_heal_action(owner: BattlePlayer, opponent: BattlePlayer, source_card: BattleCard, target_id: String, heal: int, target_slot: int = -1) -> void:
	var is_player = (owner == player_self)
	var owner_tag = "【我方】" if is_player else "【敌方】"
	# 源卡槽位（用于画线）
	var from_slot = source_card.slot_index
	match target_id:
		"T01":  # 自身
			source_card.heal(heal)
			if OS.is_debug_build():
				print("[战斗] ", owner_tag, source_card.get_display_name(), " 发动效果：自身恢复", heal, "点生命 → ", source_card.current_hp)
		"T08":  # 己方英雄
			var healed = owner.heal_hero(heal)
			if OS.is_debug_build():
				print("[战斗] ", owner_tag, source_card.get_display_name(), " 发动效果：己方英雄恢复", healed, "点生命")
		"T03":  # 己方单体（使用预解析的槽位）
			if target_slot >= 0 and target_slot < owner.max_field_size:
				var target_card = owner.field[target_slot]
				if target_card != null and target_card.is_alive():
					target_card.heal(heal)
					# 画线：源→目标
					effect_line_fromto.emit(from_slot, is_player, target_slot, is_player, "A02")
					if OS.is_debug_build():
						print("[战斗] ", owner_tag, source_card.get_display_name(), " 发动效果：", target_card.get_display_name(), " 恢复", heal, "点生命 → ", target_card.current_hp)
		"T05":  # 己方全体
			for i in range(owner.max_field_size):
				var target_card = owner.field[i]
				if target_card != null and target_card.is_alive():
					target_card.heal(heal)
					# 逐卡画线：源→每张目标卡
					effect_line_fromto.emit(from_slot, is_player, i, is_player, "A02")
					if OS.is_debug_build():
						print("[战斗] ", owner_tag, source_card.get_display_name(), " 发动效果：", target_card.get_display_name(), " 恢复", heal, "点生命 → ", target_card.current_hp)
		"T06":  # 全场（双方都回血）
			for i in range(owner.max_field_size):
				var target_card = owner.field[i]
				if target_card != null and target_card.is_alive():
					target_card.heal(heal)
					effect_line_fromto.emit(from_slot, is_player, i, is_player, "A02")
			for i in range(opponent.max_field_size):
				var target_card = opponent.field[i]
				if target_card != null and target_card.is_alive():
					target_card.heal(heal)
					effect_line_fromto.emit(from_slot, is_player, i, not is_player, "A02")
		"self":  # 旧格式兼容
			source_card.heal(heal)
			if OS.is_debug_build():
				print("[战斗] ", owner_tag, source_card.get_display_name(), " 发动效果：自身恢复", heal, "点生命 → ", source_card.current_hp)
		"hero":  # 旧格式兼容
			var healed = owner.heal_hero(heal)
			if OS.is_debug_build():
				print("[战斗] ", owner_tag, source_card.get_display_name(), " 发动效果：己方英雄恢复", healed, "点生命")
		"enemy_hero":  # 旧格式兼容（治疗敌方英雄？）
			var healed = opponent.heal_hero(heal)
			if OS.is_debug_build():
				print("[战斗] ", owner_tag, source_card.get_display_name(), " 发动效果：敌方英雄恢复", healed, "点生命")

## 破坏动作执行
func _execute_destroy_action(owner: BattlePlayer, opponent: BattlePlayer, source_card: BattleCard, target_id: String, target_slot: int = -1) -> void:
	var is_player = (owner == player_self)
	var from_slot = source_card.slot_index if source_card else -1
	match target_id:
		"T02":  # 敌方单体（使用预解析的槽位）
			if target_slot >= 0 and target_slot < opponent.max_field_size:
				var target_card = opponent.field[target_slot]
				if target_card != null and target_card.is_alive():
					target_card.current_hp = 0
					opponent.send_to_grave(target_card)
					# 画线：源→目标
					if from_slot >= 0:
						effect_line_fromto.emit(from_slot, is_player, target_slot, not is_player, "A03")
					if OS.is_debug_build():
						print("  → 破坏敌方 ", target_card.get_display_name())
					_trigger_on_destroy(opponent, target_card, target_slot)
		"T04":  # 敌方全体
			for i in range(opponent.max_field_size):
				var target_card = opponent.field[i]
				if target_card != null and target_card.is_alive():
					target_card.current_hp = 0
					opponent.send_to_grave(target_card)
					# 逐卡画线：源→每张目标卡
					if from_slot >= 0:
						effect_line_fromto.emit(from_slot, is_player, i, not is_player, "A03")
					if OS.is_debug_build():
						print("  → 破坏敌方 ", target_card.get_display_name())
					_trigger_on_destroy(opponent, target_card, i)
			opponent.cleanup_destroyed()
		"enemy_all":  # 旧格式兼容
			for i in range(opponent.max_field_size):
				var target_card = opponent.field[i]
				if target_card != null and target_card.is_alive():
					target_card.current_hp = 0
					opponent.send_to_grave(target_card)
					if OS.is_debug_build():
						print("  → 破坏敌方 ", target_card.get_display_name())
					_trigger_on_destroy(opponent, target_card, i)
			opponent.cleanup_destroyed()

## 除外动作执行（简化为送墓）
func _execute_banish_action(owner: BattlePlayer, opponent: BattlePlayer, source_card: BattleCard, target_id: String, target_slot: int = -1) -> void:
	var is_player = (owner == player_self)
	var from_slot = source_card.slot_index if source_card else -1
	var banished_cards: Array[BattleCard] = []
	match target_id:
		"T02":  # 敌方单体（使用预解析的槽位）
			if target_slot >= 0 and target_slot < opponent.max_field_size:
				var target_card = opponent.field[target_slot]
				if target_card != null and target_card.is_alive():
					opponent.banish_card(target_card)
					banished_cards.append(target_card)
					if from_slot >= 0:
						effect_line_fromto.emit(from_slot, is_player, target_slot, not is_player, "A04")
					if OS.is_debug_build():
						print("  → 除外敌方 ", target_card.get_display_name())
		"T04":  # 敌方全体
			for i in range(opponent.max_field_size):
				var target_card = opponent.field[i]
				if target_card != null and target_card.is_alive():
					opponent.banish_card(target_card)
					banished_cards.append(target_card)
					if from_slot >= 0:
						effect_line_fromto.emit(from_slot, is_player, i, not is_player, "A04")
					if OS.is_debug_build():
						print("  → 除外敌方 ", target_card.get_display_name())
	# 触发 TR07: 被除外时（扫描被除外卡牌持有者的场上）
	for bc in banished_cards:
		var bc_owner = owner if "owner_ref" in bc and bc.get("owner_ref") == owner else opponent
		_scan_and_trigger("TR07", bc_owner)  # TR07 已注释，保留兼容
## 从墓地除外动作
func _execute_banish_from_grave_action(owner: BattlePlayer, opponent: BattlePlayer, target_id: String) -> void:
	var count = 1
	match target_id:
		"T02", "T04":  # 敌方墓地
			for i in range(min(count, opponent.grave.size())):
				var card = opponent.grave.pop_back()
				if card:
					opponent.banish_card(card)
					if OS.is_debug_build():
						print("  → 从敌方墓地除外: ", card.get_display_name())
		"T03", "T05":  # 己方墓地
			for i in range(min(count, owner.grave.size())):
				var card = owner.grave.pop_back()
				if card:
					owner.banish_card(card)
					if OS.is_debug_build():
						print("  → 从己方墓地除外: ", card.get_display_name())

## 卡组检索结果回调（由BattleScene调用）
func _on_deck_search_result(callback_id: int, selected_cards: Array) -> void:
	var cb_data = _search_callbacks.get(callback_id)
	if cb_data == null:
		return
	_search_callbacks.erase(callback_id)
	
	var player = cb_data.get("player", null) as BattlePlayer
	var from_deck = cb_data.get("from_deck", false)
	var cb_func = cb_data.get("func", Callable())
	
	if cb_func.is_valid():
		cb_func.call(player, selected_cards)
	
	# 如果是从卡组检索，要洗牌
	if from_deck and player != null and player.deck != null:
		player.deck.shuffle()
		player.deck_count_changed.emit()
		if OS.is_debug_build():
			print("[检索] 卡组已洗牌")
func _execute_draw_action(owner: BattlePlayer, opponent: BattlePlayer, target_id: String, draw_count: int) -> void:
	match target_id:
		"T01":  # 自身（卡牌持有者）
			owner.draw_cards(draw_count)
			if OS.is_debug_build():
				print("  → 抽牌 +", draw_count)
		"T03":  # 己方
			owner.draw_cards(draw_count)
			if OS.is_debug_build():
				print("  → 己方抽牌 +", draw_count)
		"T08":  # 己方英雄（同己方）
			owner.draw_cards(draw_count)
			if OS.is_debug_build():
				print("  → 己方英雄抽牌 +", draw_count)
		"T02":  # 敌方
			opponent.draw_cards(draw_count)
			if OS.is_debug_build():
				print("  → 敌方抽牌 +", draw_count)
		"T04":  # 敌方全体（简化为抽指定数量）
			opponent.draw_cards(draw_count)
			if OS.is_debug_build():
				print("  → 敌方抽牌 +", draw_count)
		"self":  # 旧格式兼容
			owner.draw_cards(draw_count)
			if OS.is_debug_build():
				print("  → 抽牌 +", draw_count)
		"enemy":  # 旧格式兼容
			opponent.draw_cards(draw_count)
			if OS.is_debug_build():
				print("  → 敌方抽牌 +", draw_count)

## 召唤衍生物动作执行
func _execute_token_summon(owner: BattlePlayer, source_card: BattleCard) -> void:
	var empty_slots = owner.get_empty_slots()
	if empty_slots.size() > 0:
		var new_slot = empty_slots[0]
		var token_data = {
			"name": "衍生物", "atk": 1, "hp": 1, 
			"element": "无", "cost": 0
		}
		var token = BattleCard.from_dict(token_data)
		token.is_on_field = true
		token.slot_index = new_slot
		owner.field[new_slot] = token
		owner.field_changed.emit()
		if OS.is_debug_build():
			print("  → 召唤衍生物 → 场地", new_slot)

## 状态增益动作执行
func _execute_stat_buff(owner: BattlePlayer, source_card: BattleCard, target_id: String, stat_type: String, value: int, target_slot: int = -1) -> void:
	var opponent = player_self if owner == player_opponent else player_opponent
	var is_player = (owner == player_self)
	var from_slot = source_card.slot_index if source_card else -1
	match target_id:
		"T01":  # 自身
			source_card.add_buff(stat_type, value)
			if OS.is_debug_build():
				print("  → 自身", stat_type, "永久+", value)
		"T02":  # 敌方单体（减益，使用预解析的槽位）
			if target_slot >= 0 and target_slot < opponent.max_field_size:
				var target_card = opponent.field[target_slot]
				if target_card != null and target_card.is_alive():
					target_card.add_buff(stat_type, value)
					if from_slot >= 0:
						effect_line_fromto.emit(from_slot, is_player, target_slot, not is_player, "A20")
					if OS.is_debug_build():
						print("  → 敌方 ", target_card.get_display_name(), " ", stat_type, value)
		"T03":  # 己方单体（使用预解析的槽位）
			if target_slot >= 0 and target_slot < owner.max_field_size:
				var target_card = owner.field[target_slot]
				if target_card != null and target_card.is_alive():
					target_card.add_buff(stat_type, value)
					if from_slot >= 0:
						effect_line_fromto.emit(from_slot, is_player, target_slot, is_player, "A20")
					if OS.is_debug_build():
						print("  → 己方 ", target_card.get_display_name(), " ", stat_type, "+", value)
		"T04":  # 敌方全体（减益）
			for i in range(opponent.max_field_size):
				var target_card = opponent.field[i]
				if target_card != null and target_card.is_alive():
					target_card.add_buff(stat_type, value)
					if from_slot >= 0:
						effect_line_fromto.emit(from_slot, is_player, i, not is_player, "A20")
					if OS.is_debug_build():
						print("  → 敌方 ", target_card.get_display_name(), " ", stat_type, value)
		"T05":  # 己方全体
			for i in range(owner.max_field_size):
				var target_card = owner.field[i]
				if target_card != null and target_card.is_alive():
					target_card.add_buff(stat_type, value)
					if from_slot >= 0:
						effect_line_fromto.emit(from_slot, is_player, i, is_player, "A20")
					if OS.is_debug_build():
						print("  → 己方 ", target_card.get_display_name(), " ", stat_type, "+", value)

## 弹回手牌动作
func _execute_bounce_to_hand(owner: BattlePlayer, opponent: BattlePlayer, source_card: BattleCard, target_id: String, target_slot: int = -1) -> void:
	var is_player = (owner == player_self)
	var from_slot = source_card.slot_index if source_card else -1
	var bounced_owner = null
	match target_id:
		"T02":  # 敌方单体（使用预解析的槽位）
			if target_slot >= 0 and target_slot < opponent.max_field_size:
				var target_card = opponent.field[target_slot]
				if target_card != null and target_card.is_alive():
					target_card.reset_for_leave_field()
					target_card.is_on_field = false
					target_card.slot_index = -1
					opponent.field[target_slot] = null
					opponent.hand.append(target_card)
					bounced_owner = opponent
					if from_slot >= 0:
						effect_line_fromto.emit(from_slot, is_player, target_slot, not is_player, "A06")
					if OS.is_debug_build():
						print("  → 弹回敌方 ", target_card.get_display_name(), " 到手牌")
					opponent.field_changed.emit()
					opponent.hand_changed.emit()
		"T04":  # 敌方全体
			for i in range(opponent.max_field_size):
				var target_card = opponent.field[i]
				if target_card != null and target_card.is_alive():
					target_card.reset_for_leave_field()
					target_card.is_on_field = false
					target_card.slot_index = -1
					opponent.field[i] = null
					opponent.hand.append(target_card)
					bounced_owner = opponent
					if from_slot >= 0:
						effect_line_fromto.emit(from_slot, is_player, i, not is_player, "A06")
					if OS.is_debug_build():
						print("  → 弹回敌方 ", target_card.get_display_name(), " 到手牌")
			opponent.field_changed.emit()
			opponent.hand_changed.emit()
		"T03":  # 己方单体（使用预解析的槽位）
			if target_slot >= 0 and target_slot < owner.max_field_size:
				var target_card = owner.field[target_slot]
				if target_card != null and target_card.is_alive():
					target_card.reset_for_leave_field()
					target_card.is_on_field = false
					target_card.slot_index = -1
					owner.field[target_slot] = null
					owner.hand.append(target_card)
					bounced_owner = owner
					if from_slot >= 0:
						effect_line_fromto.emit(from_slot, is_player, target_slot, is_player, "A06")
					if OS.is_debug_build():
						print("  → 弹回己方 ", target_card.get_display_name(), " 到手牌")
					owner.field_changed.emit()
					owner.hand_changed.emit()
		"T05":  # 己方全体
			for i in range(owner.max_field_size):
				var target_card = owner.field[i]
				if target_card != null and target_card.is_alive():
					target_card.reset_for_leave_field()
					target_card.is_on_field = false
					target_card.slot_index = -1
					owner.field[i] = null
					owner.hand.append(target_card)
					bounced_owner = owner
					if from_slot >= 0:
						effect_line_fromto.emit(from_slot, is_player, i, is_player, "A06")
					if OS.is_debug_build():
						print("  → 弹回己方 ", target_card.get_display_name(), " 到手牌")
			owner.field_changed.emit()
			owner.hand_changed.emit()
		"T10":  # 墓地（己方墓地随机1张回手）
			if owner.grave.size() > 0:
				var idx = randi() % owner.grave.size()
				var card = owner.grave[idx]
				owner.grave.remove_at(idx)
				if card:
					card.reset_for_leave_field()
					card.is_on_field = false
					card.slot_index = -1
					owner.hand.append(card)
					bounced_owner = owner
					if OS.is_debug_build():
						print("  → 从己方墓地随机回收 ", card.get_display_name(), " 到手牌")
					owner.hand_changed.emit()
					owner.grave_changed.emit()
			else:
				if OS.is_debug_build():
					print("  → 己方墓地为空，无法回收")
	# 触发 TR08: 离开场上时
	if bounced_owner:
		_scan_and_trigger("TR08", bounced_owner)  # TR08 已注释，保留兼容
## 弹回卡组动作
func _execute_bounce_to_deck(owner: BattlePlayer, opponent: BattlePlayer, source_card: BattleCard, target_id: String, target_slot: int = -1) -> void:
	var is_player = (owner == player_self)
	var from_slot = source_card.slot_index if source_card else -1
	var bounced_owner = null
	match target_id:
		"T02":  # 敌方单体（使用预解析的槽位）
			if target_slot >= 0 and target_slot < opponent.max_field_size:
				var target_card = opponent.field[target_slot]
				if target_card != null and target_card.is_alive():
					target_card.reset_for_leave_field()
					target_card.is_on_field = false
					target_card.slot_index = -1
					opponent.field[target_slot] = null
					opponent.deck.insert_random(target_card)
					bounced_owner = opponent
					if from_slot >= 0:
						effect_line_fromto.emit(from_slot, is_player, target_slot, not is_player, "A07")
					if OS.is_debug_build():
						print("  → 弹回敌方 ", target_card.get_display_name(), " 到卡组")
					opponent.field_changed.emit()
					opponent.deck_count_changed.emit()
		"T04":  # 敌方全体
			for i in range(opponent.max_field_size):
				var target_card = opponent.field[i]
				if target_card != null and target_card.is_alive():
					target_card.reset_for_leave_field()
					target_card.is_on_field = false
					target_card.slot_index = -1
					opponent.field[i] = null
					opponent.deck.insert_random(target_card)
					bounced_owner = opponent
					if from_slot >= 0:
						effect_line_fromto.emit(from_slot, is_player, i, not is_player, "A07")
					if OS.is_debug_build():
						print("  → 弹回敌方 ", target_card.get_display_name(), " 到卡组")
			opponent.field_changed.emit()
			opponent.deck_count_changed.emit()
		"T10":  # 墓地（己方墓地随机1张回卡组）
			if owner.grave.size() > 0:
				var idx = randi() % owner.grave.size()
				var card = owner.grave[idx]
				owner.grave.remove_at(idx)
				if card:
					card.reset_for_leave_field()
					card.is_on_field = false
					card.slot_index = -1
					owner.deck.insert_random(card)
					bounced_owner = owner
					if OS.is_debug_build():
						print("  → 从己方墓地随机回收 ", card.get_display_name(), " 到卡组随机位置")
					owner.deck_count_changed.emit()
					owner.grave_changed.emit()
			else:
				if OS.is_debug_build():
					print("  → 己方墓地为空，无法回收")
	# 触发 TR08: 离开场上时
	if bounced_owner:
		_scan_and_trigger("TR08", bounced_owner)  # TR08 已注释，保留兼容
## 送入墓地动作
func _execute_send_to_grave_action(owner: BattlePlayer, opponent: BattlePlayer, source_card: BattleCard, target_id: String, target_slot: int = -1) -> void:
	var is_player = (owner == player_self)
	var from_slot = source_card.slot_index if source_card else -1
	match target_id:
		"T02":  # 敌方单体（使用预解析的槽位）
			if target_slot >= 0 and target_slot < opponent.max_field_size:
				var target_card = opponent.field[target_slot]
				if target_card != null and target_card.is_alive():
					opponent.send_to_grave(target_card)
					if from_slot >= 0:
						effect_line_fromto.emit(from_slot, is_player, target_slot, not is_player, "A08")
					_trigger_on_destroy(opponent, target_card, target_slot)
					if OS.is_debug_build():
						print("  → 送墓敌方 ", target_card.get_display_name())
		"T04":  # 敌方全体
			for i in range(opponent.max_field_size):
				var target_card = opponent.field[i]
				if target_card != null and target_card.is_alive():
					opponent.send_to_grave(target_card)
					if from_slot >= 0:
						effect_line_fromto.emit(from_slot, is_player, i, not is_player, "A08")
					_trigger_on_destroy(opponent, target_card, i)
					if OS.is_debug_build():
						print("  → 送墓敌方 ", target_card.get_display_name())
## 检索字段卡
func _execute_search_field(owner: BattlePlayer, target_id: String, field_name: String, count: int) -> void:
	# 从卡组中搜索指定字段的卡牌
	var all_cards = owner.deck.get_all_cards()
	var filtered := []
	for c in all_cards:
		if field_name == "" or c.fields.has(field_name):
			filtered.append(c)
	
	if filtered.is_empty():
		if OS.is_debug_build():
			print("  → 检索字段[", field_name, "] 未找到符合条件的卡牌")
		# 洗牌
		owner.deck.shuffle()
		owner.deck_count_changed.emit()
		return
	
	var callback_id = _search_callback_counter
	_search_callback_counter += 1
	
	_search_callbacks[callback_id] = {
		"func": func(player: BattlePlayer, selected: Array):
			# 从卡组中移除选中的卡牌并加入手牌
			var added = 0
			for card in selected:
				var removed = player.deck.search_and_remove(func(c): return c == card)
				if removed:
					player.hand.append(removed)
					added += 1
					if OS.is_debug_build():
						print("  → 检索字段[", field_name, "] 加入手牌: ", removed.get_display_name())
			if added > 0:
				player.hand_changed.emit()
				if OS.is_debug_build():
					print("  → 检索完成，找到 ", added, " 张"),
		"player": owner,
		"from_deck": true
	}
	
	deck_search_requested.emit(filtered, min(count, filtered.size()), callback_id)
## 检索任意卡
func _execute_search_any(owner: BattlePlayer, target_id: String, count: int) -> void:
	# 从卡组中搜索任意卡牌
	var all_cards = owner.deck.get_all_cards()
	if all_cards.is_empty():
		if OS.is_debug_build():
			print("  → 检索任意卡：卡组为空")
		return
	
	var callback_id = _search_callback_counter
	_search_callback_counter += 1
	
	_search_callbacks[callback_id] = {
		"func": func(player: BattlePlayer, selected: Array):
			var added = 0
			for card in selected:
				var removed = player.deck.search_and_remove(func(c): return c == card)
				if removed:
					player.hand.append(removed)
					added += 1
					if OS.is_debug_build():
						print("  → 检索加入手牌: ", removed.get_display_name())
			if added > 0:
				player.hand_changed.emit()
				if OS.is_debug_build():
					print("  → 检索完成，找到 ", added, " 张"),
		"player": owner,
		"from_deck": true
	}
	
	deck_search_requested.emit(all_cards, min(count, all_cards.size()), callback_id)
## 墓地回收
func _execute_recycle_from_grave(owner: BattlePlayer, target_id: String, count: int) -> void:
	# 从墓地回收卡牌到手牌
	var recycled = 0
	for i in range(min(count, owner.grave.size())):
		var card = owner.grave.pop_back()
		if card:
			owner.hand.append(card)
			recycled += 1
			if OS.is_debug_build():
				print("  → 回收: ", card.get_display_name())
	if recycled > 0:
		owner.hand_changed.emit()
		owner.grave_changed.emit()
		if OS.is_debug_build():
			print("  → 回收完成，回收 ", recycled, " 张")
## 除外回收
func _execute_recycle_from_banish(owner: BattlePlayer, target_id: String, count: int) -> void:
	# 从除外区回收卡牌到手牌
	var recycled = 0
	for i in range(min(count, owner.banished.size())):
		var card = owner.banished.pop_back()
		if card:
			owner.hand.append(card)
			recycled += 1
			if OS.is_debug_build():
				print("  → 除外回收: ", card.get_display_name())
	if recycled > 0:
		owner.hand_changed.emit()
		owner.banish_changed.emit()
		if OS.is_debug_build():
			print("  → 除外回收完成，回收 ", recycled, " 张")
## 卡组堆墓
func _execute_mill_from_deck(owner: BattlePlayer, target_id: String, count: int) -> void:
	# 从卡组顶送墓
	var milled = 0
	for i in range(count):
		var card = owner.deck.draw()
		if card:
			owner.grave.append(card)
			milled += 1
			if OS.is_debug_build():
				print("  → 堆墓: ", card.get_display_name())
	if milled > 0:
		owner.grave_changed.emit()
		owner.deck_count_changed.emit()
		if OS.is_debug_build():
			print("  → 堆墓完成，送墓 ", milled, " 张")
## 手牌特召
func _execute_special_summon_from_hand(owner: BattlePlayer, source_card: BattleCard, target_id: String, count: int) -> void:
	# 从手牌特殊召唤到场上（不消耗能量）
	var summoned = 0
	for hi in range(owner.hand.size()):
		if summoned >= count:
			break
		var card = owner.hand[hi] as BattleCard
		if card == null or card == source_card:
			continue
		var empty_slots = owner.get_empty_slots()
		if empty_slots.is_empty():
			break
		var slot = empty_slots[0]
		if owner.special_summon(card, slot):
			summoned += 1
			if OS.is_debug_build():
				print("  → 手牌特召: ", card.get_display_name(), " → 场地", slot)
	if summoned > 0:
		if OS.is_debug_build():
			print("  → 手牌特召完成，召唤 ", summoned, " 张")
## 墓地特召
func _execute_special_summon_from_grave(owner: BattlePlayer, target_id: String, count: int) -> void:
	# 从墓地特殊召唤到场上
	var summoned = 0
	for gi in range(owner.grave.size()):
		if summoned >= count:
			break
		var card = owner.grave[gi] as BattleCard
		if card == null:
			continue
		var empty_slots = owner.get_empty_slots()
		if empty_slots.is_empty():
			break
		var slot = empty_slots[0]
		# 先从墓地移除
		owner.grave.remove_at(gi)
		# 使用 special_summon 发射信号，触发 TR02/TR03/TR17
		if owner.special_summon(card, slot):
			card.summoned_this_turn = true
			# 触发 TR03: 从墓地特殊召唤时
			_scan_and_trigger("TR03", owner)  # TR03 已注释，保留兼容
			summoned += 1
			if OS.is_debug_build():
				print("  → 墓地特召: ", card.get_display_name(), " → 场地", slot)
	if summoned > 0:
		owner.grave_changed.emit()
		if OS.is_debug_build():
			print("  → 墓地特召完成，召唤 ", summoned, " 张")
## 除外特召
func _execute_special_summon_from_banish(owner: BattlePlayer, target_id: String, count: int) -> void:
	# 从除外区特殊召唤到场上
	var summoned = 0
	for bi in range(owner.banished.size()):
		if summoned >= count:
			break
		var card = owner.banished[bi] as BattleCard
		if card == null:
			continue
		var empty_slots = owner.get_empty_slots()
		if empty_slots.is_empty():
			break
		var slot = empty_slots[0]
		# 先从除外区移除
		owner.banished.remove_at(bi)
		# 使用 special_summon 发射信号
		if owner.special_summon(card, slot):
			card.summoned_this_turn = true
			summoned += 1
			if OS.is_debug_build():
				print("  → 除外特召: ", card.get_display_name(), " → 场地", slot)
	if summoned > 0:
		owner.banish_changed.emit()
		if OS.is_debug_build():
			print("  → 除外特召完成，召唤 ", summoned, " 张")
## 卡组特召
func _execute_special_summon_from_deck(owner: BattlePlayer, target_id: String, count: int) -> void:
	# 从卡组中搜索卡牌并特殊召唤到场上
	var all_cards = owner.deck.get_all_cards()
	if all_cards.is_empty():
		if OS.is_debug_build():
			print("  → 卡组特召：卡组为空")
		return
	
	# 检查是否有空场地
	var empty_slots = owner.get_empty_slots()
	if empty_slots.is_empty():
		if OS.is_debug_build():
			print("  → 卡组特召：场上没有空位")
		return
	
	var callback_id = _search_callback_counter
	_search_callback_counter += 1
	
	_search_callbacks[callback_id] = {
		"func": func(player: BattlePlayer, selected: Array):
			var summoned = 0
			for card in selected:
				var removed = player.deck.search_and_remove(func(c): return c == card)
				if removed:
					var slots = player.get_empty_slots()
					if slots.is_empty():
						break
					var slot = slots[0]
					if player.special_summon(removed, slot):
						removed.summoned_this_turn = true
						summoned += 1
						if OS.is_debug_build():
							print("  → 卡组特召: ", removed.get_display_name(), " → 场地", slot)
			if summoned > 0:
				if OS.is_debug_build():
					print("  → 卡组特召完成，召唤 ", summoned, " 张"),
		"player": owner,
		"from_deck": true
	}
	
	deck_search_requested.emit(all_cards, min(count, all_cards.size()), callback_id)
## 回合内临时攻命增减
func _execute_temp_stat_change(owner: BattlePlayer, source_card: BattleCard, target_id: String, stat: String, value: int, target_slot: int = -1) -> void:
	var opponent = _get_opponent_player() if owner == player_self else player_self
	match target_id:
		"T01":  # 自身
			source_card.add_temp_buff(stat, value)
			if OS.is_debug_build():
				print("  → 自身回合内", stat, value)
		"T02":  # 敌方单体（使用预解析的槽位）
			if target_slot >= 0 and target_slot < opponent.max_field_size:
				var target_card = opponent.field[target_slot]
				if target_card != null and target_card.is_alive():
					target_card.add_temp_buff(stat, value)
					if OS.is_debug_build():
						print("  → 敌方 ", target_card.get_display_name(), " 回合内", stat, value)
		"T03":  # 己方单体（使用预解析的槽位）
			if target_slot >= 0 and target_slot < owner.max_field_size:
				var target_card = owner.field[target_slot]
				if target_card != null and target_card.is_alive():
					target_card.add_temp_buff(stat, value)
					if OS.is_debug_build():
						print("  → 己方 ", target_card.get_display_name(), " 回合内", stat, value)
## 全场攻命增减
func _execute_all_field_stat_change(owner: BattlePlayer, opponent: BattlePlayer, target_id: String, value: int) -> void:
	if target_id in ["T02", "T04"]:
		# 敌方全体
		for i in range(opponent.max_field_size):
			var card = opponent.field[i]
			if card != null and card.is_alive():
				card.add_buff("atk_up", value)
				card.add_buff("hp_up", value)
		if OS.is_debug_build():
			print("  → 敌方全场攻命", value)
	elif target_id in ["T03", "T05"]:
		# 己方全体
		for i in range(owner.max_field_size):
			var card = owner.field[i]
			if card != null and card.is_alive():
				card.add_buff("atk_up", value)
				card.add_buff("hp_up", value)
		if OS.is_debug_build():
			print("  → 己方全场攻命", value)
	elif target_id == "T06":
		# 全场
		for i in range(owner.max_field_size):
			var card = owner.field[i]
			if card != null and card.is_alive():
				card.add_buff("atk_up", value)
				card.add_buff("hp_up", value)
		for i in range(opponent.max_field_size):
			var card = opponent.field[i]
			if card != null and card.is_alive():
				card.add_buff("atk_up", value)
				card.add_buff("hp_up", value)
		if OS.is_debug_build():
			print("  → 全场攻命", value)
## 交换攻防
func _execute_swap_atk_hp(owner: BattlePlayer, opponent: BattlePlayer, target_id: String, target_slot: int = -1) -> void:
	if target_id == "T02" and target_slot >= 0:
		var card = opponent.field[target_slot]
		if card != null and card.is_alive():
			var old_atk = card.current_atk
			var old_hp = card.current_hp
			card.base_atk = old_hp
			card.base_hp = old_atk
			card.current_atk = old_hp
			card.current_hp = old_atk
			if OS.is_debug_build():
				print("  → 交换攻防: ", card.get_display_name(), " (", old_atk, "/", old_hp, " → ", card.current_atk, "/", card.current_hp, ")")
			opponent.field_changed.emit()
	elif target_id == "T03" and target_slot >= 0:
		var card = owner.field[target_slot]
		if card != null and card.is_alive():
			var old_atk = card.current_atk
			var old_hp = card.current_hp
			card.base_atk = old_hp
			card.base_hp = old_atk
			card.current_atk = old_hp
			card.current_hp = old_atk
			if OS.is_debug_build():
				print("  → 交换攻防: ", card.get_display_name(), " (", old_atk, "/", old_hp, " → ", card.current_atk, "/", card.current_hp, ")")
			owner.field_changed.emit()
	else:
		# T04:敌方全体 / T05:己方全体 / T06:全场 攻防交换
		var sides: Array = []
		if target_id == "T04":
			sides.append(opponent)
		elif target_id == "T05":
			sides.append(owner)
		elif target_id == "T06":
			sides.append(owner)
			sides.append(opponent)
		for side in sides:
			for i in range(side.max_field_size):
				var card = side.field[i]
				if card != null and card.is_alive():
					var old_atk = card.current_atk
					var old_hp = card.current_hp
					card.base_atk = old_hp
					card.base_hp = old_atk
					card.current_atk = old_hp
					card.current_hp = old_atk
					if OS.is_debug_build():
						print("  → 交换攻防: ", card.get_display_name(), " (", old_atk, "/", old_hp, " → ", card.current_atk, "/", card.current_hp, ")")
			side.field_changed.emit()

## 暂时夺取控制权（回合结束时归还）
func _execute_take_control_temporary(owner: BattlePlayer, opponent: BattlePlayer, target_id: String, target_slot: int = -1) -> void:
	"""A26: 夺取对方场上卡牌的控制权，回合结束时归还"""
	var target = opponent if target_id in ["T02", "T04"] else owner
	var slot = target_slot if target_id in ["T02", "T03"] and target_slot >= 0 else -1
	if slot >= 0:
		var card = target.field[slot]
		if card != null and card.is_alive():
			var success = owner.take_control_of(card, target, slot, true)
			if success:
				if OS.is_debug_build():
					print("[控制权] 暂时夺取: ", card.get_display_name(), " (回合结束时归还)")
	else:
		for i in range(target.max_field_size):
			var card = target.field[i]
			if card != null and card.is_alive():
				var success = owner.take_control_of(card, target, i, true)
				if success:
					if OS.is_debug_build():
						print("[控制权] 暂时夺取: ", card.get_display_name(), " (回合结束时归还)")
				break

## 永久夺取控制权
func _execute_take_control_permanent(owner: BattlePlayer, opponent: BattlePlayer, target_id: String, target_slot: int = -1) -> void:
	"""A27: 永久夺取对方场上卡牌的控制权"""
	var target = opponent if target_id in ["T02", "T04"] else owner
	var slot = target_slot if target_id in ["T02", "T03"] and target_slot >= 0 else -1
	if slot >= 0:
		var card = target.field[slot]
		if card != null and card.is_alive():
			var success = owner.take_control_of(card, target, slot, false)
			if success:
				if OS.is_debug_build():
					print("[控制权] 永久夺取: ", card.get_display_name())
	else:
		for i in range(target.max_field_size):
			var card = target.field[i]
			if card != null and card.is_alive():
				var success = owner.take_control_of(card, target, i, false)
				if success:
					if OS.is_debug_build():
						print("[控制权] 永久夺取: ", card.get_display_name())
				break

## 控制权变更（A31 一回合 / A32 永久）——方向由目标决定：
## 目标指向敌方（T02/T04/T13/T14）→ 把对方场上的卡夺到我方；目标指向己方（T03/T05/T15/T16）→ 把我方场上的卡送对方
func _execute_control_change(owner: BattlePlayer, opponent: BattlePlayer, target_id: String, target_slot: int, temporary: bool) -> void:
	var enemy_targets := ["T02", "T04", "T13", "T14"]
	if target_id in enemy_targets:
		# 夺对方卡 → 我方
		var card = null
		var slot = -1
		if target_slot >= 0 and target_slot < opponent.max_field_size:
			card = opponent.field[target_slot]
			slot = target_slot
		if card == null or not card.is_alive():
			# 兜底：选取对方攻击最高/最低或敌方单体随机
			if target_id in ["T13", "T14"]:
				card = _pick_attack_extreme_card(opponent, target_id == "T13")
			else:
				card = _pick_random_field_card(opponent)
			if card != null:
				slot = card.slot_index
		if card != null and card.is_alive():
			var ok = owner.take_control_of(card, opponent, slot, temporary)
			if ok:
				if OS.is_debug_build():
					print("[控制权-变更] ", "一回合" if temporary else "永久", " 夺取: ", card.get_display_name())
				# TR18 控制权转移时触发（扫描双方场上）
				_scan_and_trigger("TR18", owner)
				_scan_and_trigger("TR18", opponent)
	else:
		# 送己方卡 → 对方
		var card2 = null
		var slot2 = -1
		if target_slot >= 0 and target_slot < owner.max_field_size:
			card2 = owner.field[target_slot]
			slot2 = target_slot
		if card2 == null or not card2.is_alive():
			if target_id in ["T15", "T16"]:
				card2 = _pick_attack_extreme_card(owner, target_id == "T15")
			else:
				card2 = _pick_random_field_card(owner)
			if card2 != null:
				slot2 = card2.slot_index
		if card2 != null and card2.is_alive():
			var ok2 = opponent.take_control_of(card2, owner, slot2, temporary)
			if ok2:
				if OS.is_debug_build():
					print("[控制权-变更] ", "一回合" if temporary else "永久", " 送卡: ", card2.get_display_name())
				# TR18 控制权转移时触发（扫描双方场上）
				_scan_and_trigger("TR18", owner)
				_scan_and_trigger("TR18", opponent)

## 禁用效果（A33）：目标本回合无法发动/结算效果
func _execute_disable_effect(owner: BattlePlayer, opponent: BattlePlayer, target_id: String, target_slot: int = -1) -> void:
	var target = opponent if target_id in ["T02", "T04", "T13", "T14"] else owner
	var card: BattleCard = null
	if target_slot >= 0 and target_slot < target.max_field_size:
		card = target.field[target_slot]
	if card == null or not card.is_alive():
		if target_id in ["T13", "T14"]:
			card = _pick_attack_extreme_card(opponent, target_id == "T13")
		elif target_id in ["T15", "T16"]:
			card = _pick_attack_extreme_card(owner, target_id == "T15")
		else:
			card = _pick_random_field_card(target)
	if card != null and card.is_alive():
		card.effect_disabled = true
		if OS.is_debug_build():
			print("[禁用效果] ", card.get_display_name(), " 本回合无法发动效果")
		target.field_changed.emit()
## 无法攻击
func _execute_cannot_attack(owner: BattlePlayer, opponent: BattlePlayer, target_id: String, target_slot: int = -1) -> void:
	if target_id == "T02" and target_slot >= 0:
		var card = opponent.field[target_slot]
		if card != null and card.is_alive():
			card.cannot_attack = true
			if OS.is_debug_build():
				print("  → 无法攻击: ", card.get_display_name())
			opponent.field_changed.emit()
	elif target_id == "T03" and target_slot >= 0:
		var card = owner.field[target_slot]
		if card != null and card.is_alive():
			card.cannot_attack = true
			if OS.is_debug_build():
				print("  → 无法攻击: ", card.get_display_name())
			owner.field_changed.emit()
	else:
		var target = opponent if target_id in ["T04"] else owner
		for i in range(target.max_field_size):
			var card = target.field[i]
			if card != null and card.is_alive():
				card.cannot_attack = true
				if OS.is_debug_build():
					print("  → 无法攻击: ", card.get_display_name())
				target.field_changed.emit()
				break
## 表示形式变更
func _execute_change_form(owner: BattlePlayer, opponent: BattlePlayer, target_id: String, target_slot: int = -1) -> void:
	if target_id == "T02" and target_slot >= 0:
		var card = opponent.field[target_slot]
		if card != null and card.is_alive():
			card.is_turned = not card.is_turned
			if OS.is_debug_build():
				print("  → 变更表示形式: ", card.get_display_name(), " → ", "守备" if card.is_turned else "攻击")
			opponent.field_changed.emit()
	elif target_id == "T03" and target_slot >= 0:
		var card = owner.field[target_slot]
		if card != null and card.is_alive():
			card.is_turned = not card.is_turned
			if OS.is_debug_build():
				print("  → 变更表示形式: ", card.get_display_name(), " → ", "守备" if card.is_turned else "攻击")
			owner.field_changed.emit()
	else:
		var target = opponent if target_id in ["T04"] else owner
		for i in range(target.max_field_size):
			var card = target.field[i]
			if card != null and card.is_alive():
				card.is_turned = not card.is_turned
				if OS.is_debug_build():
					print("  → 变更表示形式: ", card.get_display_name(), " → ", "守备" if card.is_turned else "攻击")
				target.field_changed.emit()
				break

## 触发亡语/破坏效果
func _trigger_on_destroy(owner: BattlePlayer, card: BattleCard, old_slot: int) -> void:
	var opponent = player_self if owner == player_opponent else player_opponent
	
	for effect in card.effects:
		var effect_type = effect.get("type", "")
		var effect_name = effect.get("effect", "")
		var effect_trigger = effect.get("trigger", "")
		var should_execute = false
		# 新格式：TR04=被破坏时 → 走连锁系统
		if effect_trigger == "TR04":
			should_execute = true
		# 旧格式兼容 → 走连锁系统
		elif effect_type == "trigger" and effect_name == "on_destroy":
			should_execute = true
		# 条件+约束预检通过才执行
		if should_execute and _precheck_effect(owner, card, effect):
			if OS.is_debug_build():
				print("[亡语] ", card.get_display_name(), " 触发: ", effect)
			_execute_effect_with_chain(owner, card, effect, old_slot)

## 卡牌被召唤/特召到场上时触发
func _on_player_card_summoned(card, slot_index: int) -> void:
	var owner = null
	var is_player = false
	if player_self != null and slot_index < player_self.max_field_size and player_self.field[slot_index] == card:
		owner = player_self
		is_player = true
	elif player_opponent != null and slot_index < player_opponent.max_field_size and player_opponent.field[slot_index] == card:
		owner = player_opponent
		is_player = false
	else:
		return
	
	# 触发 TR02: 特殊召唤成功时
	_scan_and_trigger("TR02", owner)  # TR02 已注释，保留兼容
	# TR17: 对方召唤成功时 → 已移至 _execute_on_summon_effects 末尾，在TR01效果执行完之后触发

## 卡牌被送入墓地时触发
func _on_player_card_sent_to_grave(card) -> void:
	var owner = null
	if player_self != null and card in player_self.grave:
		owner = player_self
	elif player_opponent != null and card in player_opponent.grave:
		owner = player_opponent
	else:
		return
	
	# 触发 TR06: 被送去墓地时（只触发被送墓卡自身，不扫描全场）
	if card is BattleCard and card.effects.size() > 0:
		var slot = card.slot_index  # 已经 -1 了，但没关系
		for effect in card.effects:
			var parsed = Global.parse_circuit(effect)
			if parsed.is_valid and parsed.trigger == "TR06":
				# 条件+约束预检（在压入连锁栈之前）
				if _precheck_effect(owner, card, effect):
					if OS.is_debug_build():
						print("[亡语] ", card.get_display_name(), " 送墓触发 TR06: ", effect)
					_execute_effect_with_chain(owner, card, effect, card.slot_index if card.slot_index >= 0 else 0)
	_scan_and_trigger("TR08", owner)  # TR08 已注释，保留兼容
# ===== 胜利条件检查 =====
func _check_win_condition() -> void:
	# 双方都归0 → 平局
	if player_self.hp <= 0 and player_opponent.hp <= 0:
		battle_state = State.DRAW
		battle_state_changed.emit(State.DRAW)
		if OS.is_debug_build():
			print("[战斗]  平局！双方英雄生命同时归零！")
	# 敌方归0 → 己方胜利
	elif player_opponent.hp <= 0:
		battle_state = State.WON
		battle_state_changed.emit(State.WON)
		if OS.is_debug_build():
			print("[战斗]  胜利！敌方英雄生命归零！")
	# 己方归0 → 己方失败
	elif player_self.hp <= 0:
		battle_state = State.LOST
		battle_state_changed.emit(State.LOST)
		if OS.is_debug_build():
			print("[战斗]  败北！己方英雄生命归零！")
	# ★ 敌方卡组+手牌+场地全空 → 己方胜利（卡组耗尽判负）
	elif player_opponent.deck.is_empty() and player_opponent.hand.is_empty() and player_opponent.get_field_count() == 0:
		battle_state = State.WON
		battle_state_changed.emit(State.WON)
		if OS.is_debug_build():
			print("[战斗]  胜利！敌方卡组/手牌/场地全空，无力再战！")
	# ★ 己方卡组+手牌+场地全空 → 己方失败
	elif player_self.deck.is_empty() and player_self.hand.is_empty() and player_self.get_field_count() == 0:
		battle_state = State.LOST
		battle_state_changed.emit(State.LOST)
		if OS.is_debug_build():
			print("[战斗]  败北！己方卡组/手牌/场地全空，无力再战！")


# ===== 查询方法 =====

func get_phase_name() -> String:
	match current_phase:
		Phase.DRAW: return "抽牌阶段"
		Phase.READY: return "准备阶段"
		Phase.MAIN: return "主要阶段"
		Phase.BATTLE: return "战斗阶段"
		Phase.END: return "结束阶段"
		Phase.DISCARD: return "弃牌阶段"
		_: return "未知"

func get_turn_info() -> String:
	var who = "己方" if current_player_index == 0 else "敌方"
	var phase_name = get_phase_name()
	return "第" + str(turn_count) + "回合 " + who + "回合·" + phase_name


# ===== 调试 =====

func print_all_status() -> void:
	if OS.is_debug_build():
		print("\n========== 战斗状态 ==========")
	if OS.is_debug_build():
		print(get_turn_info())
	player_self.print_status()
	if OS.is_debug_build():
		print("")
	player_opponent.print_status()
	if OS.is_debug_build():
		print("==============================\n")
