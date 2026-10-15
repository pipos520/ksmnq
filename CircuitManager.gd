extends Node
## ============================================================
##  纹路管理器 —— 管理纹路组件的解锁状态
##  自动加载单例，所有纹路解锁相关逻辑集中在此
## ============================================================

# ---------- 公开接口：查询解锁状态 ----------

## 检查某个纹路组件是否已解锁
func is_unlocked(circuit_id: String) -> bool:
	var unlocked = SaveManager.get_value("circuit", "unlocked", [])
	return circuit_id in unlocked

## 获取指定类别中所有已解锁的组件
func get_unlocked_components(category: String) -> Array:
	var all = _get_all_by_category(category)
	var unlocked = SaveManager.get_value("circuit", "unlocked", [])
	var result = []
	for comp in all:
		if comp["id"] in unlocked:
			result.append(comp)
	return result

## 获取指定类别中所有未解锁的组件
func get_locked_components(category: String) -> Array:
	var all = _get_all_by_category(category)
	var unlocked = SaveManager.get_value("circuit", "unlocked", [])
	var result = []
	for comp in all:
		if not comp["id"] in unlocked:
			result.append(comp)
	return result

## 获取指定类别中所有组件（不分解锁状态）
func get_all_components_by_category(category: String) -> Array:
	return _get_all_by_category(category)

## 获取所有纹路组件（扁平数组，含类别标记）
func get_all_components_flat() -> Array:
	var result = []
	for comp in Global.get_all_triggers():
		comp = comp.duplicate()
		comp["category"] = "TR"
		comp["category_name"] = "触发器"
		result.append(comp)
	for comp in Global.get_all_conditions():
		comp = comp.duplicate()
		comp["category"] = "C"
		comp["category_name"] = "条件"
		result.append(comp)
	for comp in Global.get_all_actions():
		comp = comp.duplicate()
		comp["category"] = "A"
		comp["category_name"] = "动作"
		result.append(comp)
	for comp in Global.get_all_targets():
		comp = comp.duplicate()
		comp["category"] = "T"
		comp["category_name"] = "目标"
		result.append(comp)
	for comp in Global.get_all_constraints():
		comp = comp.duplicate()
		comp["category"] = "CO"
		comp["category_name"] = "约束"
		result.append(comp)
	return result

## 获取某个纹路的解锁条件描述
func get_unlock_condition(circuit_id: String) -> String:
	for path in Global.get_unlock_paths():
		if circuit_id in path["unlock"]:
			var req_level = path.get("guild_level", 1)
			var cond = path["condition"]
			var level_title = ""
			for lv in PlayerManager.GUILD_LEVELS:
				if lv.level == req_level:
					level_title = lv.title
					break
			return cond + "（需要Lv." + str(req_level) + " " + level_title + "）"
	return ""

## 获取某个纹路的详细数据
func get_component_info(circuit_id: String) -> Dictionary:
	return Global.get_circuit_by_id(circuit_id)

# ---------- 公开接口：解锁检查与触发 ----------

## 检查所有解锁路径，返回新解锁的组件ID列表
## 在制卡完成、战斗胜利等事件后调用
func check_and_apply_unlocks() -> Array:
	var newly_unlocked = []
	var unlocked = SaveManager.get_value("circuit", "unlocked", [])
	var already = []
	for cid in unlocked:
		already.append(cid)
	
	for path in Global.get_unlock_paths():
		var to_unlock = path["unlock"]
		
		# 检查是否还有未解锁的
		var has_locked = false
		for cid in to_unlock:
			if not cid in already:
				has_locked = true
				break
		if not has_locked:
			continue  # 全解锁了，跳过
		
		# 检查公会称号等级是否达标
		var req_level = path.get("guild_level", 1)
		if PlayerManager.get_guild_level() < req_level:
			continue  # 称号等级不够，不能解锁
		
		# 检查条件是否满足
		if _check_condition(path["condition"]):
			for cid in to_unlock:
				if not cid in already:
					unlocked.append(cid)
					newly_unlocked.append(cid)
					print("[CircuitManager] 解锁新组件：", cid, "（", path["condition"], "）")
	
	if newly_unlocked.size() > 0:
		SaveManager.set_value("circuit", "unlocked", unlocked)
		SaveManager.save_to_disk()
		print("[CircuitManager] 本次共解锁 ", newly_unlocked.size(), " 个新组件")
	
	return newly_unlocked

## 直接解锁指定组件（用于调试/管理）
func unlock_component(circuit_id: String) -> void:
	var unlocked = SaveManager.get_value("circuit", "unlocked", [])
	if not circuit_id in unlocked:
		unlocked.append(circuit_id)
		SaveManager.set_value("circuit", "unlocked", unlocked)
		SaveManager.save_to_disk()
		print("[CircuitManager] 手动解锁：", circuit_id)

## 重置所有解锁状态（恢复到初始）
func reset_unlocks() -> void:
	var initial = Global.get_initial_unlocked()
	SaveManager.set_value("circuit", "unlocked", initial)
	SaveManager.save_to_disk()
	print("[CircuitManager] 解锁状态已重置为初始状态")

# ---------- 私有方法 ----------

func _get_all_by_category(category: String) -> Array:
	match category:
		"TR": return Global.get_all_triggers()
		"C": return Global.get_all_conditions()
		"A": return Global.get_all_actions()
		"T": return Global.get_all_targets()
		"CO": return Global.get_all_constraints()
	return []

func _check_condition(condition: String) -> bool:
	match condition:
		"首次制卡":
			return PlayerManager.get_cards_created() >= 1
		"制作3张卡":
			return PlayerManager.get_cards_created() >= 3
		"制作10张卡":
			return PlayerManager.get_cards_created() >= 10
		"制作20张卡":
			return PlayerManager.get_cards_created() >= 20
		"首张卓越品质":
			return PlayerManager.get_highest_quality() == "卓越"
		"首张完美品质":
			return PlayerManager.get_highest_quality() == "完美"
		"累计造成500点伤害":
			return PlayerManager.get_total_damage_dealt() >= 500
		"累计恢复500点生命":
			return PlayerManager.get_total_healing() >= 500
		"累计消耗100点能量":
			return PlayerManager.get_total_energy_used() >= 100
		"累计抽牌50张":
			return PlayerManager.get_total_cards_drawn() >= 50
		"累计特召30次":
			return PlayerManager.get_total_special_summon() >= 30
		"累计破坏20张卡":
			return PlayerManager.get_total_destructions() >= 20
		"卡牌图鉴收集50张":
			return PlayerManager.get_cards_collected() >= 50
		"完成5次公会任务":
			return PlayerManager.get_total_tasks_completed() >= 5
		"完成20次公会任务":
			return PlayerManager.get_total_tasks_completed() >= 20
		"通关迷雾森林":
			return PlayerManager.is_map_cleared("misty_forest")
		"通关火焰洞穴":
			return PlayerManager.is_map_cleared("flame_cavern")
		"通关风暴高塔":
			return PlayerManager.is_map_cleared("storm_tower")
		"通关暗影沼泽":
			return PlayerManager.is_map_cleared("shadow_swamp")
		"通关传说遗迹":
			return PlayerManager.is_map_cleared("legendary_ruins")
	return false

# ---------- 初始化 ----------

func _ready() -> void:
	_init_unlocks()

func _init_unlocks() -> void:
	var unlocked = SaveManager.get_value("circuit", "unlocked", [])
	if unlocked.size() == 0:
		var initial = Global.get_initial_unlocked()
		SaveManager.set_value("circuit", "unlocked", initial)
		SaveManager.save_to_disk()
		print("[CircuitManager] 初始解锁完成：", initial.size(), " 个组件")