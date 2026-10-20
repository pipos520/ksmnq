extends Node
## 无头整局模拟回归：AI(敌方) vs 简单策略玩家，打完整局不崩溃、无脚本错误
## 运行：godot --headless --path . res://dev/test_ai_sim.tscn

const MAX_ITER := 6000

func _ready() -> void:
	var errors := _run_sim()
	if errors == 0:
		print("[AI-SIM] PASS")
	else:
		print("[AI-SIM] FAILED errors=", errors)
	get_tree().quit(1 if errors > 0 else 0)


func _run_sim() -> int:
	var errors := 0
	Global.current_enemy_data = {
		"name": "模拟怪", "hp": 30, "max_hp": 30, "energy": 3, "max_energy": 3,
		"deck": [],
	}
	var bm := BattleManager.new()
	add_child(Node.new())  # 保证在树内（信号发射不报错）
	bm.start_battle("", "模拟怪", true)
	var it := 0
	var turns_seen := {}
	while bm.battle_state == BattleManager.State.PLAYING and it < MAX_ITER:
		it += 1
		turns_seen[bm.turn_count] = true
		if it % 500 == 0:
			print("[AI-SIM] it=", it, " turn=", bm.turn_count, " idx=", bm.current_player_index,
				" phase=", bm.current_phase, " queue=", bm.ai_action_queue.size(),
				" q0=", bm.ai_action_queue[0].get("type", "?") if bm.ai_action_queue.size() > 0 else "-",
				" pending=", bm._pending_enemy_attack, " state=", bm.battle_state)
		if bm.current_player_index == 1:
			# 敌方 DRAW/READY 阶段等表现层调 advance_enemy_phase 推进 → 无头模拟直接驱动
			if bm._enemy_phase_step != "":
				bm.advance_enemy_phase()
				continue
			# END/DISCARD 阶段手牌超限等 UI 弃牌回调 → 无头模拟直接代弃并切回合
			if bm.ai_action_queue.is_empty() and bm._pending_enemy_attack.is_empty():
				var cur_p: BattlePlayer = bm._get_current_player()
				if cur_p.hand.size() > 6 and bm.current_phase in [bm.Phase.END, bm.Phase.DISCARD]:
					while cur_p.hand.size() > 6:
						cur_p.hand.pop_back()
					bm._switch_turn()
					continue
			# AI 回合：推进队列；待处理攻击直接结算（模拟动画完成）
			# wait 项由驱动器计时消费，无头模拟没有时钟——手动跳过
			if not bm.ai_action_queue.is_empty() and bm.ai_action_queue[0].get("type", "") == "wait":
				bm.ai_action_queue.pop_front()
			bm._execute_next_ai_action()
			if not bm._pending_enemy_attack.is_empty():
				bm._execute_pending_enemy_attack()
		else:
			_sim_player_turn(bm)
	# 判定：要么打完（非 PLAYING），要么跑满迭代但覆盖了多回合（无死循环在早期）
	var completed := bm.battle_state != BattleManager.State.PLAYING
	var covered_turns := turns_seen.size()
	print("[AI-SIM] 迭代=", it, " 回合数=", covered_turns, " 完成=", completed,
		" 玩家HP=", bm.player_self.hp, " 敌方HP=", bm.player_opponent.hp)
	if it >= MAX_ITER and covered_turns < 6:
		errors += 1
		print("[AI-SIM] FAIL: 早期停滞（疑似死循环/等待输入）")
	if covered_turns < 4:
		errors += 1
		print("[AI-SIM] FAIL: 回合推进过少，战斗链路未充分覆盖")
	return errors


## 简单玩家策略：能出怪就出 → 进战斗 → 能攻就攻 → 结束
func _sim_player_turn(bm: BattleManager) -> void:
	if bm.current_phase == BattleManager.Phase.MAIN:
		var acted := true
		var guard := 0
		while acted and guard < 20:
			guard += 1
			acted = false
			var self_p: BattlePlayer = bm.player_self
			for hi in range(self_p.hand.size()):
				var c = self_p.hand[hi]
				if c is BattleCard and c.base_cost <= self_p.energy:
					var empty: Array = self_p.get_empty_slots()
					if not empty.is_empty():
						var r: Dictionary = bm.do_action("summon", {"hand_index": hi, "slot_index": empty[0]})
						if r.get("success", false):
							acted = true
							break
		bm.do_action("end_main_phase")
	elif bm.current_phase == BattleManager.Phase.BATTLE:
		var attacked := true
		var guard := 0
		while attacked and guard < 20:
			guard += 1
			attacked = false
			for s in range(bm.player_self.max_field_size):
				var c = bm.player_self.field[s]
				if c is BattleCard and c.is_alive() and c.can_attack():
					var t_slot := -1
					for t in range(bm.player_opponent.max_field_size):
						var d = bm.player_opponent.field[t]
						if d is BattleCard and d.is_alive():
							t_slot = t
							break
					if t_slot >= 0:
						var r: Dictionary = bm.do_action("attack", {"slot": s, "target_slot": t_slot})
						if r.get("success", false):
							attacked = true
					else:
						var r2: Dictionary = bm.do_action("attack_hero", {"slot": s})
						if r2.get("success", false):
							attacked = true
					break
		bm.do_action("end_battle_phase")
	# END 阶段由 _enter_phase 自动流转到对方回合
