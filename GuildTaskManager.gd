extends Node
## ============================================================
##  公会任务管理器 —— 自动加载单例
##  管理任务生成、刷新、提交、奖励发放
##  三类任务：纹路解锁 / 素材收集 / 金币收集
##  两种提交方式：提交卡牌 / 提交素材
##  8小时刷新周期，每次10个任务
## ============================================================

const TASK_COUNT := 10
const REFRESH_HOURS := 4.0
const REFRESH_SECONDS := REFRESH_HOURS * 3600
const SAVE_VERSION := 2  # 存档版本，用于检测旧格式

enum TaskType { UNLOCK_CIRCUIT, COLLECT_MATERIAL, COLLECT_GOLD }
enum SubmitType { SUBMIT_CARD, SUBMIT_MATERIAL }

var tasks: Array = []
var refresh_timestamp: int = 0

signal tasks_refreshed(tasks: Array)
signal task_completed(task_index: int)

var _all_circuit_ids: Array = []

func _ready():
	_build_circuit_id_list()
	_load_tasks()
	if _should_refresh():
		refresh_tasks()

func _build_circuit_id_list() -> void:
	_all_circuit_ids.clear()
	for comp in Global.circuit_triggers:
		_all_circuit_ids.append(comp["id"])
	for comp in Global.circuit_conditions:
		_all_circuit_ids.append(comp["id"])
	for comp in Global.circuit_actions:
		_all_circuit_ids.append(comp["id"])
	for comp in Global.circuit_targets:
		_all_circuit_ids.append(comp["id"])
	for comp in Global.circuit_constraints:
		_all_circuit_ids.append(comp["id"])

# ==================== 存档读写 ====================

func _load_tasks() -> void:
	var data = PlayerManager.get_data("guild_tasks", "data", null)
	if data == null:
		tasks = []
		refresh_timestamp = 0
		return
	if data is Dictionary:
		var version = data.get("version", 0)
		tasks = data.get("tasks", [])
		refresh_timestamp = data.get("refresh", 0)
		# 如果版本不匹配，强制刷新
		if version < SAVE_VERSION:
			tasks = []
			refresh_timestamp = 0

func _save_tasks() -> void:
	PlayerManager.set_data("guild_tasks", "data", {
		"tasks": tasks,
		"refresh": refresh_timestamp,
		"version": SAVE_VERSION
	})
	PlayerManager.save_data()

func _should_refresh() -> bool:
	if tasks.size() == 0:
		return true
	# 检查是否有旧格式任务（缺少title等字段）
	for t in tasks:
		if not t.has("title") or t.get("title", "") == "":
			return true
	var now = Time.get_unix_time_from_system()
	return now >= refresh_timestamp

func _update_refresh_timestamp() -> void:
	var now = Time.get_unix_time_from_system()
	refresh_timestamp = now + REFRESH_SECONDS

# ==================== 公开接口 ====================

## 重置公会任务（清空内存数据，下次 _ready 时自动刷新）
func reset_tasks() -> void:
	tasks = []
	refresh_timestamp = 0
	print("[GuildTaskManager] 公会任务已重置")

func refresh_tasks() -> void:
	_generate_tasks()
	_update_refresh_timestamp()
	_save_tasks()
	tasks_refreshed.emit(tasks)
	print("[GuildTaskManager] 任务已刷新，共 ", tasks.size(), " 个任务")

func get_tasks() -> Array:
	return tasks.duplicate()

func get_remaining_seconds() -> int:
	var now = Time.get_unix_time_from_system()
	return max(0, refresh_timestamp - now)

func get_refresh_time_text() -> String:
	var secs = get_remaining_seconds()
	if secs <= 0:
		return "即将刷新"
	var hours = secs / 3600
	var mins = (secs % 3600) / 60
	if hours > 0:
		return str(hours) + "小时" + str(mins) + "分后"
	return str(mins) + "分后"

func get_completed_count() -> int:
	var count = 0
	for t in tasks:
		if t.get("completed", false):
			count += 1
	return count

func get_total_count() -> int:
	return tasks.size()

# ==================== 任务提交 ====================

func submit_with_card(task_index: int, card_data: Dictionary) -> Dictionary:
	if task_index < 0 or task_index >= tasks.size():
		return {"success": false, "message": "无效的任务索引"}
	var task = tasks[task_index]
	if task.get("completed", false):
		return {"success": false, "message": "该任务已完成"}
	if task.get("submit_type", -1) != SubmitType.SUBMIT_CARD:
		return {"success": false, "message": "该任务需要提交素材"}
	var check = _check_card_match(task, card_data)
	if not check["match"]:
		return {"success": false, "message": check["reason"]}
	if not _remove_card_from_inventory(card_data):
		return {"success": false, "message": "从背包移除卡牌失败"}
	var reward_result = _apply_rewards(task)
	task["completed"] = true
	PlayerManager.add_tasks_completed(1)
	var new_unlocks = CircuitManager.check_and_apply_unlocks()
	if new_unlocks.size() > 0:
		var names = []
		for cid in new_unlocks:
			var info = Global.get_circuit_by_id(cid)
			names.append(info.get("name", cid))
		print("[GuildTaskManager]  任务完成触发纹路解锁：", ", ".join(names))
	_save_tasks()
	task_completed.emit(task_index)
	print("[GuildTaskManager]  任务完成：", task.get("title", ""))
	return {"success": true, "message": "任务完成！" + reward_result}

func submit_with_material(task_index: int) -> Dictionary:
	if task_index < 0 or task_index >= tasks.size():
		return {"success": false, "message": "无效的任务索引"}
	var task = tasks[task_index]
	if task.get("completed", false):
		return {"success": false, "message": "该任务已完成"}
	if task.get("submit_type", -1) != SubmitType.SUBMIT_MATERIAL:
		return {"success": false, "message": "该任务需要提交卡牌"}
	var materials_needed = task.get("submit_condition", {}).get("materials", {})
	# 从 WarehouseManager 检查素材库存
	for mat_id in materials_needed:
		var needed = materials_needed[mat_id]
		var owned = WarehouseManager.get_material_count(mat_id)
		if owned < needed:
			var mat_info = Global.get_material_by_id(mat_id)
			var mat_name = mat_info.get("name", mat_id)
			return {"success": false, "message": "素材不足：" + mat_name + " 需要" + str(needed) + "个（拥有" + str(owned) + "个）"}
	# 从 WarehouseManager 消耗素材
	for mat_id in materials_needed:
		var needed = materials_needed[mat_id]
		if not WarehouseManager.consume_material(mat_id, needed):
			return {"success": false, "message": "消耗素材失败：" + mat_id}
	var reward_result = _apply_rewards(task)
	task["completed"] = true
	PlayerManager.add_tasks_completed(1)
	var new_unlocks = CircuitManager.check_and_apply_unlocks()
	if new_unlocks.size() > 0:
		var names = []
		for cid in new_unlocks:
			var info = Global.get_circuit_by_id(cid)
			names.append(info.get("name", cid))
		print("[GuildTaskManager]  任务完成触发纹路解锁：", ", ".join(names))
	_save_tasks()
	task_completed.emit(task_index)
	print("[GuildTaskManager]  任务完成：", task.get("title", ""))
	return {"success": true, "message": "任务完成！" + reward_result}

# ==================== 任务生成 ====================

func _generate_tasks() -> void:
	tasks.clear()
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	var guild_level = PlayerManager.get_guild_level()
	var unlocked = CircuitManager.get_all_components_flat().map(func(c): return c.id).filter(func(cid): return CircuitManager.is_unlocked(cid))
	var locked_circuits = _get_locked_circuits(unlocked)
	locked_circuits.shuffle()
	var circuit_count = clampi(1 + guild_level / 3, 1, 4)
	circuit_count = mini(circuit_count, locked_circuits.size())
	var remaining = TASK_COUNT - circuit_count
	var material_count = ceil(remaining * 0.6)
	var gold_count = remaining - material_count
	var index = 0

	# 任务名随机池
	var title_pool = [
		"炼金术师的烦恼", "铁匠的请求", "工匠的委托",
		"收藏家的订单", "符文师的求助", "探险家的补给",
		"公会后勤需求", "材料商的预约", "锻造师的嘱托",
		"附魔师的研究", "学者的恳求", "商人的订单"
	]

	# 1. 纹路解锁任务（提交卡牌）
	for i in range(circuit_count):
		var circuit_id = locked_circuits[i]
		var circuit_info = Global.get_circuit_by_id(circuit_id)
		var circuit_name = circuit_info.get("name", circuit_id)
		var category_name = _get_circuit_category_name(circuit_id)
		var submit_condition = _generate_card_submit_condition(rng, guild_level)
		var bonus_gold = 10 + guild_level * 5
		tasks.append({
			"id": index, "type": TaskType.UNLOCK_CIRCUIT,
			"title": "纹路研究委托",
			"content": "公会需要研究【" + category_name + "】纹路——" + circuit_name + "，提交符合条件的卡牌以供解析",
			"requirement": submit_condition.get("desc", "提交一张卡牌"),
			"reward_text": "解锁纹路：【" + circuit_name + "】 + 金币×" + Global.n2s(bonus_gold),
			"submit_type": SubmitType.SUBMIT_CARD,
			"submit_condition": submit_condition,
			"rewards": {"circuit_id": circuit_id, "gold": bonus_gold, "materials": {}},
			"completed": false
		})
		index += 1

	# 2. 素材收集任务（提交素材）
	var all_material_ids = _get_all_material_ids()
	all_material_ids.shuffle()
	var used_mats = 0
	for i in range(material_count):
		if used_mats >= all_material_ids.size():
			gold_count += 1
			continue
		var mat_id = all_material_ids[used_mats]
		used_mats += 1
		var mat_info = Global.get_material_by_id(mat_id)
		var mat_name = mat_info.get("name", mat_id)
		var mat_rarity = mat_info.get("rarity", "普通")
		var count = 3
		if mat_rarity == "稀有": count = 2
		elif mat_rarity == "史诗": count = 1
		# 奖励：只用金币，不返还素材
		var gold_reward = 15 + guild_level * 8
		var title = title_pool[rng.randi_range(0, title_pool.size() - 1)]
		tasks.append({
			"id": index, "type": TaskType.COLLECT_MATERIAL,
			"title": title,
			"content": "制作卡牌缺少【" + mat_name + "】×" + str(count) + "，急需补充",
			"requirement": "提交【" + mat_name + "】×" + str(count),
			"reward_text": "金币×" + Global.n2s(gold_reward),
			"submit_type": SubmitType.SUBMIT_MATERIAL,
			"submit_condition": {"materials": {mat_id: count}, "desc": "提交【" + mat_name + "】×" + str(count)},
			"rewards": {"circuit_id": "", "gold": gold_reward, "materials": {}},
			"completed": false
		})
		index += 1

	# 3. 金币收集任务（提交卡牌）
	for i in range(gold_count):
		var gold_amount = 20 + guild_level * 10
		var submit_condition = _generate_card_submit_condition(rng, guild_level)
		tasks.append({
			"id": index, "type": TaskType.COLLECT_GOLD,
			"title": "公会资金募集",
			"content": "公会需要筹集资金，提交符合条件的卡牌兑换奖励",
			"requirement": submit_condition.get("desc", "提交一张卡牌"),
			"reward_text": "金币×" + Global.n2s(gold_amount),
			"submit_type": SubmitType.SUBMIT_CARD,
			"submit_condition": submit_condition,
			"rewards": {"circuit_id": "", "gold": gold_amount, "materials": {}},
			"completed": false
		})
		index += 1
	print("[GuildTaskManager] 生成任务：", tasks.size(), " 个（纹路", circuit_count, " / 素材", material_count, " / 金币", gold_count, "）")

# ==================== 卡牌条件生成 ====================

func _generate_card_submit_condition(rng: RandomNumberGenerator, guild_level: int) -> Dictionary:
	var condition_type = rng.randi_range(0, 4)
	match condition_type:
		0:
			var elements = ["火", "水", "风", "地", "光", "暗", "无"]
			var el = elements[rng.randi_range(0, elements.size() - 1)]
			return {"type": "element", "element": el, "desc": "提交一张" + el + "属性卡牌"}
		1:
			var min_cost = clampi(guild_level - 1, 1, 6)
			var max_cost = mini(min_cost + rng.randi_range(1, 3), 10)
			return {"type": "cost_range", "min_cost": min_cost, "max_cost": max_cost, "desc": "提交费用" + str(min_cost) + "~" + str(max_cost) + "的卡牌"}
		2:
			var min_atk = clampi(guild_level * 2 - 1, 2, 12)
			return {"type": "atk_min", "min_atk": min_atk, "desc": "提交攻击力≥" + str(min_atk) + "的卡牌"}
		3:
			var qualities = ["标准", "卓越", "完美"]
			var q_idx = clampi(guild_level / 3 - 1, 0, 2)
			return {"type": "quality", "quality": qualities[q_idx], "desc": "提交" + qualities[q_idx] + "品质的卡牌"}
		4:
			var keywords = ["破坏", "伤害", "抽牌", "恢复", "召唤"]
			var kw = keywords[rng.randi_range(0, keywords.size() - 1)]
			return {"type": "effect_keyword", "keyword": kw, "desc": "提交带「" + kw + "」效果的卡牌"}
	return {"type": "element", "element": "无", "desc": "提交一张任意卡牌"}

# ==================== 卡牌匹配检查 ====================

func _check_card_match(task: Dictionary, card_data: Dictionary) -> Dictionary:
	var condition = task.get("submit_condition", {})
	var cond_type = condition.get("type", "")
	match cond_type:
		"element":
			var target_el = condition.get("element", "")
			var card_el = CardManager.get_card_element(card_data)
			if card_el == target_el:
				return {"match": true}
			return {"match": false, "reason": "需要" + target_el + "属性卡牌（当前：" + card_el + "）"}
		"cost_range":
			var min_cost = condition.get("min_cost", 0)
			var max_cost = condition.get("max_cost", 99)
			var card_cost = card_data.get("cost", card_data.get("energy_cost", 0))
			if card_cost >= min_cost and card_cost <= max_cost:
				return {"match": true}
			return {"match": false, "reason": "需要费用" + str(min_cost) + "~" + str(max_cost) + "（当前：" + str(card_cost) + "）"}
		"atk_min":
			var min_atk = condition.get("min_atk", 0)
			var card_atk = card_data.get("atk", card_data.get("attack", 0))
			if card_atk >= min_atk:
				return {"match": true}
			return {"match": false, "reason": "需要攻击力≥" + str(min_atk) + "（当前：" + str(card_atk) + "）"}
		"quality":
			var target_q = condition.get("quality", "")
			var card_q = card_data.get("quality", "")
			# 自制卡牌 quality 可能是范围格式，如 "标准 ~ 卓越"
			if card_q.find(" ~ ") != -1:
				var parts = card_q.split(" ~ ")
				var lower_q = parts[0].strip_edges()
				var upper_q = parts[1].strip_edges()
				var q_order = ["废品", "瑕疵", "标准", "卓越", "完美"]
				var target_idx = q_order.find(target_q)
				var lower_idx = q_order.find(lower_q)
				var upper_idx = q_order.find(upper_q)
				if target_idx != -1 and lower_idx != -1 and upper_idx != -1:
					if target_idx >= lower_idx and target_idx <= upper_idx:
						return {"match": true}
			if card_q == target_q:
				return {"match": true}
			return {"match": false, "reason": "需要" + target_q + "品质（当前：" + card_q + "）"}
		"effect_keyword":
			var keyword = condition.get("keyword", "")
			# 从纹路组件数据中，找所有 name 包含关键词的组件 ID
			var matched_ids := []
			var all_components = []
			all_components.append_array(Global.circuit_actions)
			all_components.append_array(Global.circuit_triggers)
			for comp in all_components:
				if comp.get("name", "").find(keyword) != -1:
					matched_ids.append(comp.get("id", ""))
			var card_effects = card_data.get("effects", [])
			for eff in card_effects:
				# 1. 检查 desc 文本（老卡兼容，如"入场：抽1张牌"）
				var desc = ""
				if eff is String: desc = eff
				elif eff is Dictionary: desc = eff.get("desc", "")
				if desc.find(keyword) != -1:
					return {"match": true}
				# 2. 检查效果字段是否匹配纹路组件 ID（基于纹路数据，不受 desc 文本格式影响）
				if eff is Dictionary and matched_ids.size() > 0:
					for key in ["action", "trigger"]:
						if matched_ids.has(eff.get(key, "")):
							return {"match": true}
			return {"match": false, "reason": "需要带「" + keyword + "」效果的卡牌"}
	return {"match": false, "reason": "未知的提交条件类型"}

# ==================== 奖励发放 ====================

func _apply_rewards(task: Dictionary) -> String:
	var rewards = task.get("rewards", {})
	var messages = []
	# 纹路解锁奖励
	var circuit_id = rewards.get("circuit_id", "")
	if circuit_id != "":
		if CircuitManager.is_unlocked(circuit_id):
			messages.append("纹路已解锁，奖励转为200金币")
			PlayerManager.set_gold(PlayerManager.get_gold() + 200)
		else:
			CircuitManager.unlock_component(circuit_id)
			var circuit_info = Global.get_circuit_by_id(circuit_id)
			messages.append("解锁纹路：" + circuit_info.get("name", circuit_id))
	# 金币奖励（统一用 PlayerManager，与其他系统保持一致）
	var gold = rewards.get("gold", 0)
	if gold > 0:
		PlayerManager.set_gold(PlayerManager.get_gold() + gold)
		messages.append("获得" + Global.n2s(gold) + "金币")
	PlayerManager.save_data()
	return " ".join(messages)

# ==================== 背包操作 ====================

func _remove_card_from_inventory(card_data: Dictionary) -> bool:
	var target_id = card_data.get("id", "")
	return CardManager.remove_card_by_id(target_id)

# ==================== 辅助方法 ====================

func _get_locked_circuits(unlocked: Array) -> Array:
	var locked = []
	for cid in _all_circuit_ids:
		if not cid in unlocked:
			locked.append(cid)
	return locked

func _get_circuit_category_name(circuit_id: String) -> String:
	if circuit_id.begins_with("TR"): return "触发器"
	elif circuit_id.begins_with("C"): return "条件"
	elif circuit_id.begins_with("A"): return "动作"
	elif circuit_id.begins_with("T"): return "目标"
	elif circuit_id.begins_with("CO"): return "约束"
	return "其他"

func _get_all_material_ids() -> Array:
	var ids = []
	for cat in ["fiber", "mineral", "resin", "extract", "pigment", "binder"]:
		for mat in Global.material_data.get(cat, []):
			var mid = mat.get("id", "")
			if mid != "":
				ids.append(mid)
	return ids
