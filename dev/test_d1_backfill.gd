extends Node

## C1 后手补偿（D1 定稿）逻辑验证：直接驱动 BattleManager，
## 检查后手（敌方）自身第 1/2 回合能量 +1、第 3 回合起与先手同轨。
## 运行：godot --path . --headless res://dev/test_d1_backfill.tscn（需窗口模式验证时可去掉 --headless）

var bm: BattleManager

func _ready() -> void:
	bm = BattleManager.new()
	bm.start_battle("", "测试宿主", true)
	bm.player_self.energy_changed.connect(_on_energy.bind("先手(己方)"))
	bm.player_opponent.energy_changed.connect(_on_energy.bind("后手(敌方)"))
	_run_test()

func _on_energy(e: int, m: int, who: String) -> void:
	print("[TEST] T%d %s energy=%d/%d" % [bm.turn_count, who, e, m])

func _sw() -> void:
	bm._switch_turn()
	await get_tree().create_timer(0.3).timeout
	if bm.current_player_index == 1:
		# 敌方回合由场景层驱动（GDD §6.2）：DRAW_DONE → advance → READY（能量在此结算）
		bm.advance_enemy_phase()
		await get_tree().create_timer(0.15).timeout

func _run_test() -> void:
	await get_tree().create_timer(1.5).timeout
	print("[TEST] --- T1 先手自身#1（期望 3/3，无补偿）---")
	await _sw()
	print("[TEST] --- T2 后手自身#1（期望 4/3 临时+1）---")
	await _sw()
	print("[TEST] --- T3 先手自身#2（期望 4/4 正常轨道）---")
	await _sw()
	print("[TEST] --- T4 后手自身#2（期望 5/4 临时+1）---")
	await _sw()
	print("[TEST] --- T5 先手自身#3（期望 5/5）---")
	await _sw()
	print("[TEST] --- T6 后手自身#3（期望 5/5 同轨，不再补偿）---")
	print("[TEST] DONE")
	get_tree().quit()
