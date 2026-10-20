extends Node
## 挂 root 的诊断节点：第 120 帧打印布局矩形 + 引擎内截图后自动退出
func _process(_d: float) -> void:
	var f := Engine.get_process_frames()
	if f == 120:
		set_process(false)
		var tree := Engine.get_main_loop() as SceneTree
		var battle := tree.current_scene
		if battle == null:
			print("[PROBE] no scene")
			get_tree().quit()
			return
		print("[PROBE] scene=", battle.name, " root.size=", battle.size)
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
		# 引擎内截图：viewport 帧缓冲，完整一帧，不受窗口/DPI 影响
		var img := vp.get_texture().get_image()
		var tag := "landscape" if not Global.use_legacy_battle else "portrait"
		var path := "C:/Users/Administrator/Documents/ksmnq/shots/battle2d/engine_%s.png" % tag
		img.save_png(path)
		print("[PROBE] SAVED ", path, " size=", img.get_size())
		get_tree().quit()
