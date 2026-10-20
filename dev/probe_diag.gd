extends Node
## 挂 root 的诊断节点：第 25 帧全树扫描手牌真实节点
func _process(_d: float) -> void:
	if Engine.get_process_frames() != 25:
		return
	set_process(false)
	var tree := Engine.get_main_loop() as SceneTree
	var battle := tree.current_scene
	if battle == null:
		print("[PROBE] no scene")
		return
	print("[PROBE] scene=", battle.name, " root.size=", battle.size)
	var vp := battle.get_viewport()
	print("[PROBE] visible_rect=", vp.get_visible_rect())
	# 全树找名字含 Hand 的 Control
	_scan(battle, 0)
	# 额外：手牌卡按钮（HandCard_ 开头）
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

func _scan(n: Node, depth: int) -> void:
	if depth > 3:
		return
	for c in n.get_children():
		if c is Control and ("Hand" in String(c.name) or "hand" in String(c.name)):
			var cc := c as Control
			print("[PROBE] %s gpos=%s size=%s vis=%s" % [cc.get_path(), cc.global_position, cc.size, cc.visible])
		_scan(c, depth + 1)
