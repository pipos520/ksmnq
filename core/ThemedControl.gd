class_name ThemedControl
extends Control

## Base class for themed Control screens.
## Handles background, bars, title, and standard button styling.
## Override _get_themed_button_names() to specify which buttons to style.
## Override _apply_theme_custom() for additional custom theming.

var _last_applied_mode = null

func _ready():
	Global.theme_changed.connect(_on_theme_changed)
	call_deferred("_apply_theme_styles")

func _on_theme_changed(_mode = null):
	_apply_theme_styles()

func _apply_theme_styles():
	var mode = Global.current_mode
	var is_day = mode == Global.ThemeMode.DAY

	var bg = get_node_or_null("Background")
	if bg:
		Global.apply_bg(bg)

	for n in _get_bar_names():
		var r = get_node_or_null(n)
		if r is ColorRect:
			r.color = Global.current.topbar_bg

	for n in _get_bar_line_names():
		var r = get_node_or_null(n)
		if r is ColorRect:
			r.color = Global.current.topbar_border

	var title = get_node_or_null("Title")
	if title is Label:
		title.add_theme_color_override("font_color", Global.current.title)
		title.add_theme_color_override("font_shadow_color", Global.current.title_shadow)
		title.add_theme_constant_override("shadow_offset_x", Global.current.shadow_offset)
		title.add_theme_constant_override("shadow_offset_y", Global.current.shadow_offset)

	_apply_theme_custom()

	var mode_key = mode
	if _last_applied_mode == mode_key:
		return
	_last_applied_mode = mode_key

	var btn_names = _get_themed_button_names()
	if not btn_names.is_empty():
		_style_standard_buttons(btn_names, is_day)

func _style_standard_buttons(btn_names: Array, is_day: bool):
	var icon_c = Color("#645C50") if is_day else Color("#CBCBE0")
	var btn_bg = Color(0.15, 0.13, 0.20, 0.85) if not is_day else Color(0.90, 0.85, 0.75, 0.85)
	var btn_bg_hover = btn_bg.lightened(0.12)
	var btn_bg_pressed = btn_bg.darkened(0.15)
	var border_c = Color("#E8A838") if not is_day else Color("#946F38")
	for bname in btn_names:
		var btn = get_node_or_null(bname)
		if not btn is Button:
			continue
		btn.add_theme_color_override("font_color", icon_c)
		btn.add_theme_color_override("font_hover_color", icon_c.lightened(0.15))
		btn.add_theme_color_override("font_pressed_color", icon_c.darkened(0.2))
		var r = _get_button_corner_radius(bname)
		for state in ["normal", "hover", "pressed", "focus"]:
			var sb = StyleBoxFlat.new()
			sb.bg_color = btn_bg_hover if state == "hover" else (btn_bg_pressed if state == "pressed" else btn_bg)
			sb.border_width_left = 2; sb.border_width_right = 2
			sb.border_width_top = 2; sb.border_width_bottom = 2
			sb.border_color = border_c
			sb.corner_radius_top_left = r; sb.corner_radius_top_right = r
			sb.corner_radius_bottom_left = r; sb.corner_radius_bottom_right = r
			sb.content_margin_left = 16; sb.content_margin_right = 16
			sb.content_margin_top = 8; sb.content_margin_bottom = 8
			btn.add_theme_stylebox_override(state, sb)

# === Virtual methods — override in subclasses ===

func _get_bar_names() -> Array:
	return ["TopBar", "BottomBar"]

func _get_bar_line_names() -> Array:
	return ["TopBarLine", "BottomBarLine"]

func _get_themed_button_names() -> Array:
	return []

func _get_button_corner_radius(_bname: String) -> int:
	return 12

func _apply_theme_custom():
	pass
