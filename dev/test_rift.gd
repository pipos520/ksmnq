extends Node

## 裂隙局链路验证：开局 → MapNodeScene 随机图生成 → 节点类型统计 → 撤离结算
## 运行：godot --path . --headless res://dev/test_rift.tscn

func _ready() -> void:
	_run()

func _run() -> void:
	Global.rift_start(3)  # Rift 3 → flame_cavern 区域
	Global.current_map_id = "rift"
	Global.current_map_name = "虚渊裂缝 · Rift 3"
	Global.saved_map_node_data = []
	print("[TEST] rift_start ok, depth=", Global.rift_depth, " loot_map=", Global.rift_depth_to_map(3))
	# 以子节点实例化（change_scene 会把测试节点自己释放掉，协程会死）
	var ms = load("res://MapNodeScene.tscn").instantiate()
	add_child(ms)
	await get_tree().create_timer(2.0).timeout
	if not ms.has_method("init_map"):
		print("[TEST] FAIL: 场景不是 MapNodeScene")
		get_tree().quit()
		return
	var nd: Array = ms._node_data
	var total := 0
	var type_count := {}
	for layer in nd:
		for n in layer:
			total += 1
			var k := str(n["type"])
			type_count[k] = int(type_count.get(k, 0)) + 1
	print("[TEST] 节点总数=", total, " （期望 8-12）类型分布=", type_count)
	# 模拟局内掉落 → 背包
	var ok1 := Global.rift_add_loot("material", "MAT_TEST", "测试素材", 2)
	var ok2 := Global.rift_add_loot("aux", "AU16", "测试辅材", 1)
	print("[TEST] 背包写入:", ok1, ok2, " 格数=", Global.rift_backpack.size())
	# 撤离结算 → 仓库
	var res = Global.rift_settle_exit()
	print("[TEST] 撤离结算 brought=", res["brought"], " （期望 3） 首通金币=", res["first_clear_gold"])
	print("[TEST] 仓库测试素材=", WarehouseManager.get_materials().get("MAT_TEST", 0), " AU16=", WarehouseManager.get_aux_items().get("AU16", 0))
	# 全灭折损
	Global.rift_start(1)
	Global.rift_add_loot("material", "MAT_W", "折损素材", 5)
	var w = Global.rift_settle_wipe()
	print("[TEST] 全灭折损 kept=", w["kept"], " lost=", w["lost"], " （期望 kept=3 lost=2）")
	print("[TEST] DONE")
	get_tree().quit()
