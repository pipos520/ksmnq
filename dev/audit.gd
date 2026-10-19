extends RefCounted

# Runtime UI audit helper. Loaded via ResourceLoader with CACHE_MODE_IGNORE.
# Every line is tagged so the Python side can isolate one run inside a
# cumulative game log:   [AUD:<tag>] ...   with BEGIN / END markers.

const DESIGN_W := 1080.0
const DESIGN_H := 1920.0

var tag := "x"


func _p(s: String) -> void:
	print("[AUD:" + tag + "] " + s)


func _text_of(n: Node) -> String:
	if n is Label:
		return (n as Label).text
	if n is Button:
		return (n as Button).text
	if n is RichTextLabel:
		return (n as RichTextLabel).get_parsed_text()
	if n is LineEdit:
		return (n as LineEdit).text
	return ""


func _collect(n: Node, depth: int, out: Array, max_depth: int) -> void:
	if n is Control:
		out.append(n)
	if depth >= max_depth:
		return
	for c in n.get_children():
		_collect(c, depth + 1, out, max_depth)


# Rect actually visible after intersecting every clipping ancestor.
func _clipped_rect(n: Control) -> Rect2:
	var r := n.get_global_rect()
	var p := n.get_parent()
	while p != null:
		if p is Control and (p as Control).clip_contents:
			r = r.intersection((p as Control).get_global_rect())
		p = p.get_parent()
	return r


func _has_clipping_ancestor(n: Control) -> bool:
	var p := n.get_parent()
	while p != null:
		if p is Control and (p as Control).clip_contents:
			return true
		p = p.get_parent()
	return false


func hook_btn(t: String, needle: String) -> String:
	tag = t
	var all: Array = []
	_collect(Engine.get_main_loop().root, 0, all, 20)
	_p("BEGIN")
	for c in all:
		if not (c is BaseButton):
			continue
		var b := c as BaseButton
		if b.text.find(needle) < 0:
			continue
		var tg := tag
		b.pressed.connect(func(): print("[HOOK:" + tg + "] PRESSED"))
		b.gui_input.connect(func(ev: InputEvent): print("[HOOK:" + tg + "] GUI " + ev.as_text()))
		b.mouse_entered.connect(func(): print("[HOOK:" + tg + "] ENTER"))
		_p("HOOKED " + str(b.get_path()))
	_p("END")
	return "ok"


func fix_mouse(t: String) -> String:
	tag = t
	var all: Array = []
	_collect(Engine.get_main_loop().root, 0, all, 20)
	var n := 0
	for c in all:
		var ctl := c as Control
		if ctl.mouse_filter == Control.MOUSE_FILTER_IGNORE and ctl is Container:
			ctl.mouse_filter = Control.MOUSE_FILTER_PASS
			n += 1
	_p("BEGIN")
	_p("FIXED " + str(n))
	_p("END")
	return "ok"


func check_btn(t: String, needle: String) -> String:
	tag = t
	var r: Node = Engine.get_main_loop().root
	var all: Array = []
	_collect(r, 0, all, 20)
	_p("BEGIN")
	for c in all:
		if not (c is BaseButton):
			continue
		var b := c as BaseButton
		if b.text.find(needle) < 0:
			continue
		_p("BTNCHECK | " + str(b.get_path()) + " | text=" + b.text)
		_p("  pressed_conns=" + str(b.pressed.get_connections().size()) + " disabled=" + str(b.disabled) + " mouse=" + str(b.mouse_filter) + " vis=" + str(b.is_visible_in_tree()) + " rect=" + str(b.get_global_rect()))
		var p := b.get_parent()
		while p != null:
			var mf := "n/a"
			if p is Control:
				mf = str((p as Control).mouse_filter)
			_p("  parent " + str(p.name) + " (" + p.get_class() + ") mouse=" + mf)
			p = p.get_parent()
	_p("END")
	return "ok"


func find_text(t: String, needle: String) -> String:
	tag = t
	var r: Node = Engine.get_main_loop().root
	var all: Array = []
	_collect(r, 0, all, 20)
	_p("BEGIN")
	var n_found := 0
	for c in all:
		var n: Control = c
		var s := _text_of(n)
		if s.find(needle) >= 0:
			var rr: Rect2 = n.get_global_rect()
			var chain := ""
			var p := n.get_parent()
			while p != null and chain.length() < 160:
				chain = "/" + str(p.name) + chain
				p = p.get_parent()
			_p("FOUND | " + str(n.get_path()) + " | " + n.get_class() + " | vis=" + str(n.is_visible_in_tree()) + " | mod_a=" + str(n.modulate.a) + " | self_mod_a=" + str(n.self_modulate.a) + " | " + str(rr) + " | parent=" + chain)
			n_found += 1
	_p("COUNT " + str(n_found))
	_p("END")
	return "ok"


func dump_root(t: String = "x") -> String:
	tag = t
	var r: Node = Engine.get_main_loop().root
	var cur: Node = (Engine.get_main_loop() as SceneTree).current_scene
	_p("BEGIN")
	for i in range(r.get_child_count()):
		var c := r.get_child(i)
		var extra := ""
		if c is Control:
			var cr: Rect2 = (c as Control).get_global_rect()
			extra = " rect=" + str(cr)
		_p("ROOT | " + str(i) + " | " + str(c.name) + " | " + c.get_class() + " | is_current=" + str(c == cur) + extra)
	_p("END")
	return "ok"


func dump_texts(t: String = "x") -> String:
	tag = t
	var cur: Node = (Engine.get_main_loop() as SceneTree).current_scene
	if cur == null:
		return "no_scene"
	var all: Array = []
	_collect(cur, 0, all, 14)
	_p("BEGIN")
	for c in all:
		var n: Control = c
		if not n.is_visible_in_tree():
			continue
		if not (n is Label or n is RichTextLabel or n is Button or n is LineEdit):
			continue
		var r: Rect2 = n.get_global_rect()
		var ms: Vector2 = n.get_minimum_size()
		var wrap := ""
		var clip := ""
		var lines := 0
		var lh := 0
		if n is Label:
			wrap = str((n as Label).autowrap_mode)
			clip = str((n as Label).clip_text)
			lines = (n as Label).get_line_count()
			lh = (n as Label).get_line_height()
		elif n is Button:
			wrap = str((n as Button).autowrap_mode)
			clip = str((n as Button).clip_text)
		_p("TXT | " + str(cur.get_path_to(n)) + " | " + n.get_class() + " | " + str(int(r.position.x)) + "," + str(int(r.position.y)) + " " + str(int(r.size.x)) + "x" + str(int(r.size.y)) + " | min=" + str(int(ms.x)) + "x" + str(int(ms.y)) + " | wrap=" + wrap + " clip=" + clip + " lines=" + str(lines) + " lh=" + str(lh) + " | " + _text_of(n).left(60))
	_p("END")
	return "ok"


func dump_controls(t: String = "x") -> String:
	tag = t
	var cur: Node = (Engine.get_main_loop() as SceneTree).current_scene
	if cur == null:
		return "no_scene"
	var all: Array = []
	_collect(cur, 0, all, 14)
	_p("BEGIN")
	for c in all:
		var n: Control = c
		if not n.is_visible_in_tree():
			continue
		var r: Rect2 = n.get_global_rect()
		_p("CTL | " + str(cur.get_path_to(n)) + " | " + n.get_class() + " | " + str(int(r.position.x)) + "," + str(int(r.position.y)) + " " + str(int(r.size.x)) + "x" + str(int(r.size.y)) + " | a=" + str(n.anchor_left) + "," + str(n.anchor_top) + "," + str(n.anchor_right) + "," + str(n.anchor_bottom) + " | clip=" + str(n.clip_contents))
	_p("END")
	return "ok"


## 顶部分段控件（tab 栏）是刻意铺满整宽的，不该当成「内容贴边」报警。
## 判据：同级里还有别的按钮，把这些按钮横向并起来几乎覆盖整个屏幕宽度。
func _in_tab_group(n: BaseButton) -> bool:
	var par := n.get_parent()
	if par == null:
		return false
	var lo := 1e9
	var hi := -1e9
	var cnt := 0
	for c in par.get_children():
		if c is BaseButton and (c as BaseButton).is_visible_in_tree():
			var rr := (c as BaseButton).get_global_rect()
			lo = min(lo, rr.position.x)
			hi = max(hi, rr.end.x)
			cnt += 1
	if cnt < 2:
		return false
	return (hi - lo) >= DESIGN_W * 0.95 and (hi - lo) > n.get_global_rect().size.x + 1.0


## 当前场景 Background 节点的类型 + 纹理/颜色，用来核对主题背景有没有被正确应用
func probe_bg() -> String:
	var cur: Node = (Engine.get_main_loop() as SceneTree).current_scene
	if cur == null:
		return "no_scene"
	var b := cur.get_node_or_null("Background")
	if b == null:
		return "%s | NO_BACKGROUND" % cur.name
	if b is TextureRect:
		var tx := (b as TextureRect).texture
		var p := "null_tex"
		if tx != null:
			p = tx.resource_path.get_file()
		return "%s | TextureRect | %s" % [cur.name, p]
	if b is ColorRect:
		return "%s | ColorRect | %s" % [cur.name, (b as ColorRect).color]
	return "%s | %s" % [cur.name, b.get_class()]


## WCAG 相对亮度 / 对比度，用于判断按钮文字是否压在自己的底色上看不清
func _srgb_ch(v: float) -> float:
	if v <= 0.03928:
		return v / 12.92
	return pow((v + 0.055) / 1.055, 2.4)


func _lum(c: Color) -> float:
	return 0.2126 * _srgb_ch(c.r) + 0.7152 * _srgb_ch(c.g) + 0.0722 * _srgb_ch(c.b)


func _contrast(a: Color, b: Color) -> float:
	var la := _lum(a)
	var lb := _lum(b)
	var hi := maxf(la, lb)
	var lo := minf(la, lb)
	return (hi + 0.05) / (lo + 0.05)


func run(t: String = "r", max_depth: int = 12) -> String:
	tag = t
	_p("BEGIN")
	var cur: Node = (Engine.get_main_loop() as SceneTree).current_scene
	if cur == null:
		_p("NO_SCENE")
		_p("END")
		return "no_scene"
	var all: Array = []
	_collect(cur, 0, all, max_depth)
	var vis := 0
	for c in all:
		if (c as Control).is_visible_in_tree():
			vis += 1
	_p("SCENE " + str(cur.name) + " nodes=" + str(all.size()) + " visible=" + str(vis))
	var issues := 0
	var screen := Rect2(0, 0, DESIGN_W, DESIGN_H)
	for c in all:
		var n: Control = c
		if not n.is_visible_in_tree():
			continue
		var r: Rect2 = n.get_global_rect()
		var vr: Rect2 = _clipped_rect(n)
		var t2 := n.get_class()
		var p := str(cur.get_path_to(n)) if cur.is_ancestor_of(n) else str(n.get_path())
		var txt := _text_of(n)
		var scrolled := _has_clipping_ancestor(n)
		var is_bg := r.size.x > DESIGN_W * 1.05 or r.size.y > DESIGN_H * 1.05
		# 1) fully hidden because it is scrolled out -> ignore
		var visible_part := vr.size.x > 0.5 and vr.size.y > 0.5
		# 2) outside the screen (clipped rect, so scrolled-out rows are ignored)
		if not is_bg and r.size.x >= 1.0 and r.size.y >= 1.0:
			if not visible_part:
				pass
			elif not screen.intersects(vr):
				_p("ISSUE OFFSCREEN | " + p + " | " + t2 + " | " + str(r) + " | " + txt.left(20))
				issues += 1
			elif vr.position.x < -8.0 or vr.position.y < -8.0 or vr.end.x > DESIGN_W + 8.0 or vr.end.y > DESIGN_H + 8.0:
				_p("ISSUE PARTIAL_OUT | " + p + " | " + t2 + " | " + str(r) + " | " + txt.left(20))
				issues += 1
		# 2b) horizontally clipped by an ancestor (this game never scrolls horizontally)
		if not is_bg and scrolled and r.size.x > 1.0 and vr.size.x > 0.5 and vr.size.x < r.size.x - 4.0:
			_p("ISSUE H_CLIP | " + p + " | " + t2 + " | node_w=" + str(int(r.size.x)) + " visible_w=" + str(int(vr.size.x)) + " | " + txt.left(20))
			issues += 1
		# 3) zero-size interactive
		if (n is BaseButton or n is Label) and (r.size.x < 2.0 or r.size.y < 2.0) and visible_part:
			_p("ISSUE ZERO_SIZE | " + p + " | " + t2 + " | " + str(r.size) + " | " + txt.left(20))
			issues += 1
		# 4) tiny touch target
		if n is BaseButton and r.size.y > 1.0 and (r.size.y < 60.0 or r.size.x < 60.0):
			_p("ISSUE TINY_TARGET | " + p + " | " + t2 + " | " + str(r.size) + " | " + txt.left(20))
			issues += 1
		# 4b) 按钮文字与自身底色对比度太低 —— 直观表现就是「字看不清 / 像没画上去」
		if n is BaseButton and txt != "":
			var bb := n as BaseButton
			var st_name: String = "disabled" if bb.disabled else "normal"
			var sbx: StyleBox = bb.get_theme_stylebox(st_name)
			if sbx is StyleBoxFlat:
				var bgc: Color = (sbx as StyleBoxFlat).bg_color
				if bgc.a > 0.55:
					var key_c: String = "font_disabled_color" if bb.disabled else "font_color"
					var fc: Color = bb.get_theme_color(key_c)
					fc = Color(bgc.r + (fc.r - bgc.r) * fc.a,
						bgc.g + (fc.g - bgc.g) * fc.a,
						bgc.b + (fc.b - bgc.b) * fc.a, 1.0)
					var cr: float = _contrast(bgc, fc)
					if cr < 2.2:
						_p("ISSUE LOW_CONTRAST | " + p + " | " + t2 + " | ratio=" + str(snappedf(cr, 0.01)) + " disabled=" + str(bb.disabled) + " | " + txt.left(20))
						issues += 1
		# 4d) 自定义了 normal 样式、却没给 disabled 样式 —— 一旦禁用会退回主题默认灰块，
		# 按钮「突然变成另一个灰色按钮」，配默认暗灰字还经常看不清
		if n is BaseButton:
			var bbc := n as BaseButton
			if bbc.disabled and bbc.has_theme_stylebox_override("normal") and not bbc.has_theme_stylebox_override("disabled"):
				_p("ISSUE NO_DISABLED_STYLE | " + p + " | " + t2 + " | 缺 disabled 样式，禁用时变默认灰块 | " + txt.left(20))
				issues += 1
		# 5) text overflow horizontally
		if txt != "" and (n is Label or n is Button):
			var f: Font = n.get_theme_font("font")
			var fs: int = n.get_theme_font_size("font_size")
			var is_wrap := false
			var is_clip := false
			if n is Label:
				is_wrap = (n as Label).autowrap_mode != TextServer.AUTOWRAP_OFF
				is_clip = (n as Label).clip_text
			elif n is Button:
				is_wrap = (n as Button).autowrap_mode != TextServer.AUTOWRAP_OFF
				is_clip = (n as Button).clip_text
			if f != null and fs > 0 and not is_wrap and not is_clip:
				var w: float = f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				if w > r.size.x + 8.0:
					_p("ISSUE TEXT_OVERFLOW_X | " + p + " | " + t2 + " | text_w=" + str(int(w)) + " avail=" + str(int(r.size.x)) + " | " + txt.left(24))
					issues += 1
		# 6) wrapped text taller than the control -> vertical clipping
		if n is Label and txt != "":
			var lb := n as Label
			var lc := lb.get_line_count()
			var lh := lb.get_line_height()
			if lh > 0 and lc > 1:
				var need: float = lc * lh
				if need > r.size.y + 4.0:
					_p("ISSUE TEXT_CLIP_V | " + p + " | " + t2 + " | lines=" + str(lc) + " need_h=" + str(int(need)) + " have=" + str(int(r.size.y)) + " | " + txt.left(24))
					issues += 1
		# 7) interactive but effectively invisible (alpha 0)
		if n is BaseButton and n.modulate.a < 0.05 and (n as BaseButton).disabled == false:
			_p("ISSUE INVISIBLE_BUTTON | " + p + " | " + t2 + " | " + txt.left(20))
			issues += 1
		# 8) text hugging the screen edge (no side margin)
		var in_tabs := (n is BaseButton) and _in_tab_group(n)
		# 居中文本的控件本身铺满整宽是正常的（文字离边很远），不该按「贴边」算
		var centered := false
		if n is Label:
			centered = (n as Label).horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER
		elif n is Button:
			centered = (n as Button).alignment == HORIZONTAL_ALIGNMENT_CENTER
		if (n is Label or n is BaseButton) and txt != "" and r.size.x > 1.0 and r.size.x < DESIGN_W * 0.9 and not in_tabs and not centered:
			if r.end.x > DESIGN_W - 6.0:
				_p("ISSUE EDGE_R | " + p + " | " + t2 + " | right=" + str(int(r.end.x)) + " | " + txt.left(20))
				issues += 1
			elif r.position.x < 6.0:
				_p("ISSUE EDGE_L | " + p + " | " + t2 + " | left=" + str(int(r.position.x)) + " | " + txt.left(20))
				issues += 1
	# 8) overlapping sibling buttons inside the same parent
	var by_parent := {}
	for c in all:
		var n2: Control = c
		if not n2.is_visible_in_tree():
			continue
		if not (n2 is BaseButton):
			continue
		var r2 := n2.get_global_rect()
		if r2.size.x < 4.0 or r2.size.y < 4.0:
			continue
		var pnode := n2.get_parent()
		var key := str(pnode.get_path()) if pnode != null else "?"
		if not by_parent.has(key):
			by_parent[key] = []
		by_parent[key].append([n2, r2])
	for key in by_parent:
		var arr: Array = by_parent[key]
		for i in range(arr.size()):
			for j in range(i + 1, arr.size()):
				var a: Array = arr[i]
				var b: Array = arr[j]
				var inter: Rect2 = (a[1] as Rect2).intersection(b[1] as Rect2)
				if inter.size.x > 8.0 and inter.size.y > 8.0:
					var area: float = inter.size.x * inter.size.y
					var small: float = min((a[1] as Rect2).size.x * (a[1] as Rect2).size.y, (b[1] as Rect2).size.x * (b[1] as Rect2).size.y)
					if small > 0.0 and area / small > 0.12:
						_p("ISSUE BTN_OVERLAP | " + str((a[0] as Node).name) + " & " + str((b[0] as Node).name) + " under " + key + " | overlap=" + str(int(area)))
						issues += 1
	_p("DONE issues=" + str(issues))
	_p("END")
	return "ok"


func dump_buttons(t: String = "b") -> String:
	tag = t
	var cur: Node = (Engine.get_main_loop() as SceneTree).current_scene
	if cur == null:
		return "no_scene"
	var all: Array = []
	_collect(cur, 0, all, 12)
	_p("BEGIN")
	for c in all:
		var n: Control = c
		if not n.is_visible_in_tree():
			continue
		if n is BaseButton:
			var r: Rect2 = n.get_global_rect()
			_p("BTN | " + str(cur.get_path_to(n)) + " | " + n.get_class() + " | " + str(int(r.position.x)) + "," + str(int(r.position.y)) + " " + str(int(r.size.x)) + "x" + str(int(r.size.y)) + " | " + _text_of(n).left(24) + " | disabled=" + str((n as BaseButton).disabled))
	_p("END")
	return "ok"
