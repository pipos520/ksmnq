class_name ElementSystem

## ============================================================
##  ElementSystem — 元素克制与加成系统（纯静态，无状态）
## ============================================================

## 元素克制关系：key 克制 value
const AFFINITY_MAP := {
	"火": "风",
	"风": "地",
	"地": "水",
	"水": "火",
	"光": "暗",
	"暗": "光",
}


static func get_element_emoji(element: String) -> String:
	match element:
		"火": return "🔥"
		"水": return "💧"
		"风": return "🌪️"
		"地": return "⛰️"
		"光": return "✨"
		"暗": return "🌑"
	return ""


## 获取元素克制倍率（1.0=无克制，1.2=克制）
static func get_element_affinity(atk_element: String, def_element: String) -> float:
	if atk_element == "无" or def_element == "无" or atk_element == "" or def_element == "":
		return 1.0
	if AFFINITY_MAP.get(atk_element, "") == def_element:
		return 1.2
	return 1.0


## 获取元素专属加成系数
## element: 卡牌最终元素
## power_bonus: 辅材提供的额外元素强度
## effect_type: "damage"/"heal"/"draw"/"shield"/"counter"/"destroy"
## 返回: 1.0 + 基础天赋加成 + 辅材加成
static func get_element_power_multiplier(element: String, power_bonus: float, effect_type: String = "") -> float:
	if element == "无" or element == "":
		return 1.0
	var base_bonus := 0.0
	var bonus := 0.0
	match element:
		"火":
			if effect_type == "damage":
				base_bonus = 0.1
				bonus = power_bonus
		"水":
			if effect_type == "heal":
				base_bonus = 0.1
				bonus = power_bonus
		"风":
			if effect_type == "draw":
				base_bonus = 0.1
				bonus = power_bonus
		"地":
			if effect_type == "shield":
				base_bonus = 0.1
				bonus = power_bonus
		"光":
			if effect_type == "counter":
				base_bonus = 0.1
				bonus = power_bonus
		"暗":
			if effect_type == "damage" or effect_type == "destroy":
				base_bonus = 0.1
				bonus = power_bonus
	var total_bonus = base_bonus + bonus
	if total_bonus <= 0.0:
		return 1.0
	return 1.0 + total_bonus
