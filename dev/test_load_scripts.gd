extends Node

## 编译冒烟：加载两个战斗场景脚本，确认无 parse error

func _ready() -> void:
	var ok := true
	for path in ["res://BattleSceneLegacy.gd", "res://BattleManager.gd", "res://battle_core/BattleDriver.gd", "res://MapNodeScene.gd", "res://Exploration.gd", "res://Global.gd"]:
		var s = load(path)
		if s == null:
			print("[TEST] FAIL: ", path)
			ok = false
		else:
			print("[TEST] OK: ", path)
	print("[TEST] DONE ok=", ok)
	get_tree().quit()
