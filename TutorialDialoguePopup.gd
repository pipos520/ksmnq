extends Control
class_name TutorialDialoguePopup
## ============================================================
##  教程对话弹窗 —— 都市卡牌流剧情对话框
##  用法：
##    var popup = preload("res://TutorialDialoguePopup.gd").new()
##    popup.setup([
##      {"speaker": "老陈", "text": "第一句", "portrait_color": Color(...)},
##      {"speaker": "主角", "text": "第二句", "portrait_color": Color(...)},
##    ], callback)
##    popup.show_skip_button(true, skip_callback)  # 可选：右上角"跳过"按钮
##    add_child(popup)
##  点「下一步」逐句推进；最后一句点完自动回调并关闭
## ============================================================
signal finished
signal skip_requested

var _lines: Array = []
var _idx: int = 0
var _on_finish: Callable = Callable()
var _on_skip: Callable = Callable()
var _name_label: Label
var _text_label: Label
var _next_btn: Button
var _skip_btn: Button = null

# 都市卡牌流角色配色
const COLOR_LAOCHEN := Color("#8a7a5a")   # 老陈：烟灰棕
const COLOR_PLAYER := Color("#4a7a9a")    # 主角：现代都市蓝灰

func setup(lines: Array, on_finish: Callable = Callable()) -> void:
	_lines = lines
	_on_finish = on_finish
	# 关键：把弹窗自身设置为全屏尺寸，否则子节点(遮罩/面板)全部不可见
	set_anchors_preset(Control.PRESET_FULL_RECT)
	custom_minimum_size = Vector2(0, 0)
	_build_ui()
	_show_line()

## 显示右上角"跳过"按钮（skip_callback 触发后弹窗自动关闭）
func show_skip_button(enabled: bool = true, skip_callback: Callable = Callable()) -> void:
	if not enabled:
		return
	_on_skip = skip_callback
	_add_skip_button()

func _add_skip_button() -> void:
	_skip_btn = Button.new()
	_skip_btn.name = "SkipBtn"
	_skip_btn.text = "跳过 ⏭"
	_skip_btn.add_theme_font_size_override("font_size", 32)
	var bs = StyleBoxFlat.new()
	bs.bg_color = Color(0.25, 0.15, 0.15, 0.85)
	bs.border_width_left = 2; bs.border_width_right = 2
	bs.border_width_top = 2; bs.border_width_bottom = 2
	bs.border_color = Color("#c97b7b")
	bs.corner_radius_top_left = 12; bs.corner_radius_top_right = 12
	bs.corner_radius_bottom_left = 12; bs.corner_radius_bottom_right = 12
	_skip_btn.add_theme_stylebox_override("normal", bs)
	_skip_btn.add_theme_color_override("font_color", Color("#f0b8b8"))
	# 面板内右上角定位
	_skip_btn.anchor_left = 1.0; _skip_btn.anchor_top = 0.0
	_skip_btn.anchor_right = 1.0; _skip_btn.anchor_bottom = 0.0
	_skip_btn.offset_left = Global.pw(-0.24)
	_skip_btn.offset_top = Global.ph(0.015)
	_skip_btn.offset_right = Global.pw(-0.025)
	_skip_btn.offset_bottom = Global.ph(0.06)
	_skip_btn.pressed.connect(_on_skip_pressed)
	# 找面板挂上
	var panel = get_node_or_null("Overlay/DialoguePanel")
	if panel:
		panel.add_child(_skip_btn)

func _on_skip_pressed() -> void:
	# 中断打字动画
	_typing = false
	# 通知外部
	skip_requested.emit()
	if _on_skip.is_valid():
		_on_skip.call()
	# 关闭弹窗（不再触发 on_finish）
	queue_free()

func _build_ui() -> void:
	# 全屏半透明遮罩
	var overlay = ColorRect.new()
	overlay.name = "Overlay"
	overlay.color = Color(0, 0, 0, 0.55)
	overlay.anchor_left = 0.0; overlay.anchor_top = 0.0
	overlay.anchor_right = 1.0; overlay.anchor_bottom = 1.0
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	# 主对话框面板（下半屏）
	var panel = Panel.new()
	panel.name = "DialoguePanel"
	panel.anchor_left = 0.03; panel.anchor_top = 0.55
	panel.anchor_right = 0.97; panel.anchor_bottom = 0.95
	var ps = StyleBoxFlat.new()
	ps.bg_color = Color(0.08, 0.07, 0.06, 0.96)
	ps.border_width_left = 4; ps.border_width_right = 4
	ps.border_width_top = 4; ps.border_width_bottom = 4
	ps.border_color = Color("#e8a838")
	ps.corner_radius_top_left = 20; ps.corner_radius_top_right = 20
	ps.corner_radius_bottom_left = 20; ps.corner_radius_bottom_right = 20
	panel.add_theme_stylebox_override("panel", ps)
	panel.clip_contents = true
	overlay.add_child(panel)

	# 右上角说话者名
	_name_label = Label.new()
	_name_label.name = "SpeakerName"
	_name_label.anchor_left = 0.0; _name_label.anchor_top = 0.0
	_name_label.anchor_right = 1.0; _name_label.anchor_bottom = 0.0
	_name_label.offset_left = Global.pw(0.04); _name_label.offset_top = Global.ph(0.015)
	_name_label.offset_right = Global.pw(-0.02); _name_label.offset_bottom = Global.ph(0.07)
	_name_label.text = "老陈"
	_name_label.add_theme_font_size_override("font_size", 42)
	_name_label.add_theme_color_override("font_color", Color("#f9d371"))
	panel.add_child(_name_label)

	# 正文（打字机效果）
	_text_label = Label.new()
	_text_label.name = "DialogueText"
	_text_label.anchor_left = 0.04; _text_label.anchor_top = 0.0
	_text_label.anchor_right = 1.0; _text_label.anchor_bottom = 1.0
	_text_label.offset_left = Global.pw(0.04); _text_label.offset_top = Global.ph(0.075)
	_text_label.offset_right = Global.pw(-0.03); _text_label.offset_bottom = Global.ph(-0.11)
	_text_label.add_theme_font_size_override("font_size", 40)
	_text_label.add_theme_color_override("font_color", Color("#f0e6d6"))
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	panel.add_child(_text_label)

	# 下一步按钮
	_next_btn = Button.new()
	_next_btn.name = "NextBtn"
	_next_btn.text = "下一步 ▶"
	_next_btn.add_theme_font_size_override("font_size", 38)
	var bs = StyleBoxFlat.new()
	bs.bg_color = Color(0.2, 0.18, 0.13, 1.0)
	bs.border_width_left = 2; bs.border_width_right = 2
	bs.border_width_top = 2; bs.border_width_bottom = 2
	bs.border_color = Color("#e8a838")
	bs.corner_radius_top_left = 12; bs.corner_radius_top_right = 12
	bs.corner_radius_bottom_left = 12; bs.corner_radius_bottom_right = 12
	_next_btn.add_theme_stylebox_override("normal", bs)
	_next_btn.add_theme_color_override("font_color", Color("#f9d371"))
	_next_btn.anchor_left = 1.0; _next_btn.anchor_top = 1.0
	_next_btn.anchor_right = 1.0; _next_btn.anchor_bottom = 1.0
	_next_btn.offset_left = Global.pw(-0.24); _next_btn.offset_top = Global.ph(-0.052)
	_next_btn.offset_right = Global.pw(-0.025); _next_btn.offset_bottom = Global.ph(-0.012)
	_next_btn.pressed.connect(_on_next)
	panel.add_child(_next_btn)

func _show_line() -> void:
	if _idx >= _lines.size():
		_close()
		return
	var line = _lines[_idx]
	var speaker = line.get("speaker", "老陈")
	var text = line.get("text", "")
	_name_label.text = speaker
	# 打字机效果
	_text_label.text = ""
	_type_line(text)
	# 更新按钮文字
	if _idx >= _lines.size() - 1:
		_next_btn.text = "继续 ▶"
	else:
		_next_btn.text = "下一步 ▶"

var _type_char_idx: int = 0
var _type_timer: float = 0.0
var _type_full_text: String = ""
var _typing: bool = false

func _type_line(text: String) -> void:
	_type_full_text = text
	_type_char_idx = 0
	_typing = true
	_type_timer = 0.0

func _process(delta: float) -> void:
	if not _typing:
		return
	_type_timer += delta
	# 每 0.03 秒打一个字
	while _type_timer >= 0.03 and _type_char_idx < _type_full_text.length():
		_type_char_idx += 1
		_text_label.text = _type_full_text.substr(0, _type_char_idx)
		_type_timer -= 0.03
	if _type_char_idx >= _type_full_text.length():
		_typing = false

func _on_next() -> void:
	if _typing:
		# 正在打字：点击直接显示全文
		_text_label.text = _type_full_text
		_type_char_idx = _type_full_text.length()
		_typing = false
		return
	_idx += 1
	_show_line()

func _close() -> void:
	if _on_finish.is_valid():
		_on_finish.call()
	finished.emit()
	queue_free()