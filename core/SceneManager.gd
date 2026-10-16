extends Node

## ============================================================
##  SceneManager — 场景切换 + 预加载缓存（Autoload）
## ============================================================

## 预加载的场景缓存（LoadingScreen填充，各场景直接用change_scene_to_packed切换）
var preloaded_scenes: Dictionary = {}


func start_background_loading(scenes_to_preload: Array, total_tasks: int) -> void:
	pass  # 同步预加载已在 LoadingScreen 完成，此处无需异步循环


## 全局场景切换函数——优先使用预加载的场景缓存，瞬间切换无等待
func change_scene(path: String) -> void:
	var _t = Time.get_ticks_msec()
	# 缓存命中：直接切换（秒切）
	if preloaded_scenes.has(path):
		print("[Scene] %s 缓存命中 change_scene_to_packed: %dms" % [path, Time.get_ticks_msec() - _t])
		get_tree().change_scene_to_packed(preloaded_scenes[path])
		return
	# 缓存未命中：同步加载后切换
	var packed = load(path)
	if packed:
		preloaded_scenes[path] = packed
		print("[Scene] %s 同步加载: %dms" % [path, Time.get_ticks_msec() - _t])
		get_tree().change_scene_to_packed(packed)
		return
	# 最终 fallback
	print("[Scene] %s fallback change_scene_to_file: %dms" % [path, Time.get_ticks_msec() - _t])
	get_tree().change_scene_to_file(path)
