extends Node
## 离线渲染探针：横屏战斗（视角转换）
func _ready() -> void:
	Global.use_legacy_battle = false
	Global.current_enemy_data = {"name": "迷雾幼藤", "hp": 20, "max_hp": 20, "energy": 3, "max_energy": 3, "deck": []}
	Global.current_battle_terrain = "misty_forest"
	Global.current_map_id = "misty_forest"
	Global.is_tutorial_battle = false
	Global.rift_active = false
	Global.change_scene("res://BattleSceneLegacy.tscn")
