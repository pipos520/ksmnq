extends Node
## 挂 root 的诊断节点：第 120 帧打印布局矩形 + 引擎内截图后自动退出
## 横屏额外巡三视角：field(120f) -> player(180f) -> enemy(240f) 各截一帧
var _is_land := false

func _process(_d: float) -> void:
	var f := Engine.get_process_frames()
	var tree := Engine.get_main_loop() as SceneTree
	var battle := tree.current_scene
	if battle == null:
		if f > 120:
			print("[PROBE] no scene")
			get_tree().quit()
		return
	_is_land = not Global.use_legacy_battle
	if f == 120:
		_diag_and_snap(battle, "init")
		if _is_land:
			battle.call("debug_set_view", 0)  # 先回全景（自动镜头开局会切我方视角）
		else:
			get_tree().quit()
	elif _is_land and f == 170:
		_snap(battle, "field")
		battle.call("debug_set_view", 1)  # 我方视角
	elif _is_land and f == 220:
		_snap(battle, "player")
		battle.call("debug_set_view", 2)  # 敌方视角
	elif _is_land and f == 270:
		_snap(battle, "enemy")
		get_tree().quit()

func _diag_and_snap(battle: Node, tag: String) -> void:
	print("[PROBE] scene=", battle.name, " root.size=", battle.size)
	var win := battle.get_window()
	print("[PROBE] window.size=", win.size, " content_scale_size=", win.content_scale_size, " scale_factor=", win.content_scale_factor, " scale_mode=", win.content_scale_mode, " aspect=", win.content_scale_aspect, " screen_size=", DisplayServer.screen_get_size(win.current_screen), " dpi=", DisplayServer.screen_get_dpi(win.current_screen))
	var vp := battle.get_viewport()
	print("[PROBE] visible_rect=", vp.get_visible_rect())
	# 真实手牌卡父链（代码建的真身，被改名 @ScrollContainer@63）
	var found := 0
	for n in battle.find_children("HandCard_*", "", true, false):
		if n is Control:
			found += 1
			if found > 1:
				continue
			var c := n as Control
			var cur: Node = c
			var chain := []
			while cur != null and cur is Control:
				var cc := cur as Control
				chain.append("%s sz=%s gp=%s" % [cur.name, cc.size, cc.global_position])
				cur = cur.get_parent()
			print("[PROBE] parent-chain ", " <- ".join(chain))
	print("[PROBE] HandCard_* total=", found)
	_snap(battle, tag)

func _snap(battle: Node, tag: String) -> void:
	var vp := battle.get_viewport()
	print("[PROBE] view=%s transform=%s _battle_view=%s" % [tag, vp.canvas_transform, battle.get("_battle_view")])
	var img := vp.get_texture().get_image()
	var path := "C:/Users/Administrator/Documents/ksmnq/shots/battle2d/engine_%s.png" % tag
	img.save_png(path)
	print("[PROBE] SAVED ", path, " size=", img.get_size())
