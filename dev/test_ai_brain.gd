extends Node
## 无头 AI 决策测试：构造固定局面，断言主要阶段/战斗阶段队列决策正确
## 运行：godot --headless --path . res://dev/test_ai_brain.tscn

var fails := 0
var checks := 0

func _ready() -> void:
	_case_summon_survival()
	_case_no_suicide_trade()
	_case_best_trade()
	_case_hero_face_empty_board()
	_case_danger_control()
	_case_focus_value_target()
	if fails == 0:
		print("[AI-TEST] ALL PASS (", checks, " checks)")
	else:
		print("[AI-TEST] FAILED: ", fails, "/", checks)
	get_tree().quit(1 if fails > 0 else 0)


func _mk_bm() -> BattleManager:
	var bm := BattleManager.new()
	bm.player_self = BattlePlayer.new()
	bm.player_self.player_name = "玩家"
	bm.player_self.hp = 30; bm.player_self.max_hp = 30
	bm.player_self.energy = 5; bm.player_self.max_energy = 5
	bm.player_opponent = BattlePlayer.new()
	bm.player_opponent.player_name = "敌方AI"
	bm.player_opponent.hp = 30; bm.player_opponent.max_hp = 30
	bm.player_opponent.energy = 5; bm.player_opponent.max_energy = 5
	bm.player_opponent.deck = BattleDeck.new()  # 空卡组：连招预读返回空，不干扰
	bm.current_player_index = 1
	bm.battle_state = BattleManager.State.PLAYING
	return bm


func _mk_card(cname: String, cost: int, atk: int, hp: int, effects: Array = []) -> BattleCard:
	return BattleCard.from_dict({
		"id": "TEST_" + cname, "name": cname,
		"energy_cost": cost, "attack": atk, "health": hp,
		"main_element": "无", "fields": [], "effects": effects,
		"quality": "标准", "star": 1,
	})


func _mk_field_card(cname: String, atk: int, hp: int) -> BattleCard:
	var c := _mk_card(cname, 1, atk, hp)
	c.is_on_field = true
	c.summoned_this_turn = false
	c.slot_index = 0
	return c


func _check(cond: bool, msg: String) -> void:
	checks += 1
	if cond:
		print("[AI-TEST] PASS: ", msg)
	else:
		fails += 1
		print("[AI-TEST] FAIL: ", msg)


## 用例1 主阶段：玩家 4/4 压场，AI 1 费只能下一张——3/1 白板(会被白吃) vs 3/5 白板(站得住)
## 期望：只召唤 3/5，不送 3/1
func _case_summon_survival() -> void:
	var bm := _mk_bm()
	bm.player_self.field[0] = _mk_field_card("玩家大怪", 4, 4)
	var weak := _mk_card("脆皮白板", 1, 3, 1)
	var sturdy := _mk_card("硬壳白板", 1, 3, 5)
	bm.player_opponent.hand = [weak, sturdy]
	bm.player_opponent.energy = 1
	bm._build_ai_main_phase_queue()
	var summoned_names := []
	for action in bm.ai_action_queue:
		if action.get("type", "") == "enemy_summon":
			summoned_names.append(bm.player_opponent.hand[action.get("hand_idx", -1)].card_name)
	_check(summoned_names.has("硬壳白板"), "主阶段：站得住的 3/5 被召唤")
	_check(not summoned_names.has("脆皮白板"), "主阶段：会被白吃的 3/1 白板没被送")


## 用例2 战斗阶段：AI 1/1 vs 玩家 5/5——打不死且必死，期望不攻
func _case_no_suicide_trade() -> void:
	var bm := _mk_bm()
	var attacker := _mk_field_card("小豆丁", 1, 1)
	bm.player_opponent.field[0] = attacker
	bm.player_self.field[0] = _mk_field_card("巨墙", 5, 5)
	bm._build_ai_battle_phase_queue()
	var has_attack := false
	for action in bm.ai_action_queue:
		if action.get("type", "") in ["enemy_attack", "enemy_attack_hero"]:
			has_attack = true
	_check(not has_attack, "战斗阶段：1/1 撞 5/5 必送，选择不攻")


## 用例3 战斗阶段：AI 5/5 + 2/2，玩家 3/3——5/5 能白吃（自己不死），2/2 会送
## 期望：选 5/5 去交换
func _case_best_trade() -> void:
	var bm := _mk_bm()
	var big := _mk_field_card("主力", 5, 5)
	var small := _mk_field_card("斥候", 2, 2)
	bm.player_opponent.field[0] = big
	bm.player_opponent.field[1] = small
	var target := _mk_field_card("敌中坚", 3, 3)
	bm.player_self.field[0] = target
	bm._build_ai_battle_phase_queue()
	var found := false
	for action in bm.ai_action_queue:
		if action.get("type", "") == "enemy_attack":
			var a_slot: int = action.get("slot", -1)
			var t_slot: int = action.get("target_slot", -1)
			if bm.player_opponent.field[a_slot] == big and bm.player_self.field[t_slot] == target:
				found = true
	_check(found, "战斗阶段：5/5 白吃 3/3，而不是让 2/2 去送")


## 用例4 战斗阶段：玩家空场 → 守护解除，全员直击英雄
func _case_hero_face_empty_board() -> void:
	var bm := _mk_bm()
	bm.player_opponent.field[0] = _mk_field_card("打手A", 3, 3)
	bm.player_opponent.field[1] = _mk_field_card("打手B", 2, 2)
	bm._build_ai_battle_phase_queue()
	var hero_attacks := 0
	for action in bm.ai_action_queue:
		if action.get("type", "") == "enemy_attack_hero":
			hero_attacks += 1
	_check(hero_attacks == 2, "战斗阶段：对方空场，两只怪都直击英雄")


## 用例5 战略：对方下回合理论伤害 >= AI 血量 → 危急防御 control（压过攒连招）
func _case_danger_control() -> void:
	var bm := _mk_bm()
	bm.player_opponent.hp = 10; bm.player_opponent.max_hp = 30
	bm.player_self.field[0] = _mk_field_card("斩杀者", 6, 6)
	bm.player_self.field[1] = _mk_field_card("斩杀者2", 6, 6)
	# AI 手上两张连招组件（旧逻辑会选 combo 攒连招）
	var combo1 := _mk_card("夺卡术", 2, 0, 1, [{"trigger": "TR01", "action": "A31", "target": "T13", "value": 1}])
	var combo2 := _mk_card("禁印", 2, 0, 1, [{"trigger": "TR01", "action": "A33", "target": "T13", "value": 1}])
	bm.player_opponent.hand = [combo1, combo2]
	bm._update_ai_strategy()
	_check(bm._ai_strategy == "control", "战略：将被斩杀时切 control 保命，而不是攒连招")


## 用例6 战斗阶段：有持续收益怪（回合开始触发）优先集火
func _case_focus_value_target() -> void:
	var bm := _mk_bm()
	bm.player_opponent.field[0] = _mk_field_card("平庸怪", 4, 4)
	var low_value := _mk_field_card("白板", 2, 5)
	var engine := _mk_field_card("引擎", 1, 5)
	engine.effects = [{"trigger": "TR12", "action": "A09", "target": "T01", "value": 1}]
	bm.player_self.field[0] = low_value
	bm.player_self.field[1] = engine
	bm._build_ai_battle_phase_queue()
	var target_card = null
	for action in bm.ai_action_queue:
		if action.get("type", "") == "enemy_attack":
			target_card = bm.player_self.field[action.get("target_slot", -1)]
	_check(target_card == engine, "战斗阶段：优先集火持续收益的引擎怪")
