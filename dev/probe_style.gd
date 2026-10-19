extends RefCounted

# 运行时样式探针：打印当前场景里各类控件的 stylebox 实际类型
# 用法: ResourceLoader.load('res://dev/probe_style.gd').new().run()

func _p(tag: String, s: String) -> void:
	print("[PS:%s] %s" % [tag, s])


func run() -> void:
	var ml: MainLoop = Engine.get_main_loop()
	var cs: Node = (ml as SceneTree).current_scene if ml is SceneTree else null
	if cs == null:
		_p("X", "no scene")
		return
	_p("SCENE", str(cs.name))
	var stack: Array = [cs]
	var flat_total := 0
	var tex_total := 0
	var lines: Array = []
	var guard := 0
	while stack.size() > 0 and guard < 4000:
		guard += 1
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is Panel:
			var s: StyleBox = (n as Panel).get_theme_stylebox("panel")
			if s is StyleBoxFlat:
				flat_total += 1
				if lines.size() < 6:
					lines.append("%s(FLAT %s)" % [n.name, str((s as StyleBoxFlat).bg_color)])
			elif s is StyleBoxTexture:
				tex_total += 1
		elif n is PanelContainer:
			var s2: StyleBox = (n as PanelContainer).get_theme_stylebox("panel")
			if s2 is StyleBoxFlat:
				flat_total += 1
				if lines.size() < 6:
					lines.append("%s(PC-FLAT)" % n.name)
			elif s2 is StyleBoxTexture:
				tex_total += 1
		elif n is BaseButton:
			var s3: StyleBox = (n as BaseButton).get_theme_stylebox("normal")
			if s3 is StyleBoxFlat:
				flat_total += 1
				if lines.size() < 6:
					lines.append("%s(BTN-FLAT)" % n.name)
			elif s3 is StyleBoxTexture:
				tex_total += 1
	_p("TOTAL", "flat=%d tex=%d" % [flat_total, tex_total])
	for l in lines:
		_p("SAMPLE", str(l))
	_p("END", "done")
