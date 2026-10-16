extends Node

## ============================================================
##  ThemeManager — 主题系统 + UI 工厂 + 飘窗通知（Autoload）
## ============================================================

enum ThemeMode { NIGHT, DAY }

const CONFIG_PATH := "user://theme_settings.cfg"
const CONFIG_SECTION := "theme"

const REF_W := 1080.0
const REF_H := 1920.0

static func ph(ratio: float) -> float:
	return REF_H * ratio

static func pw(ratio: float) -> float:
	return REF_W * ratio


class ThemeColors:
	var bg: Color
	var title: Color
	var title_shadow: Color
	var btn_text: Color
	var btn_text_hover: Color
	var btn_bg: Color
	var btn_bg_hover: Color
	var btn_bg_pressed: Color
	var version: Color
	var version_shadow: Color
	var gear_bg: Color
	var gear_hover: Color
	var topbar_bg: Color
	var topbar_border: Color
	var shadow_offset: int

	func _init(
		_bg: Color, _title: Color, _title_shadow: Color,
		_btn_text: Color, _btn_text_hover: Color,
		_btn_bg: Color, _btn_bg_hover: Color, _btn_bg_pressed: Color,
		_version: Color, _version_shadow: Color,
		_gear_bg: Color, _gear_hover: Color,
		_topbar_bg: Color, _topbar_border: Color,
		_shadow_offset: int
	):
		bg = _bg; title = _title; title_shadow = _title_shadow
		btn_text = _btn_text; btn_text_hover = _btn_text_hover
		btn_bg = _btn_bg; btn_bg_hover = _btn_bg_hover; btn_bg_pressed = _btn_bg_pressed
		version = _version; version_shadow = _version_shadow
		gear_bg = _gear_bg; gear_hover = _gear_hover
		topbar_bg = _topbar_bg; topbar_border = _topbar_border
		shadow_offset = _shadow_offset

var theme_night := ThemeColors.new(
	Color("#0f0e17"), Color("#f9d371"), Color("#000000"),
	Color("#e8d5b7"), Color("#ffffff"),
	Color("#1a1a2e"), Color("#2a2a4e"), Color("#0a0a1e"),
	Color("#9a9ab0"), Color("#000000"),
	Color("#1a1a2e"), Color("#2a2a4e"),
	Color("#1e1e3a"), Color("#3a3a5e"),
	6
)

var theme_day := ThemeColors.new(
	Color("#f5f0e8"), Color("#c0392b"), Color("#8a6b5a"),
	Color("#3d2b1f"), Color("#000000"),
	Color("#ede0d4"), Color("#d4c4b0"), Color("#c0a890"),
	Color("#7a6b5a"), Color("#d4c4b0"),
	Color("#ede0d4"), Color("#d4c4b0"),
	Color("#d6c8b8"), Color("#b8a898"),
	4
)

var current_mode: ThemeMode = ThemeMode.NIGHT
var current: ThemeColors:
	get: return theme_night if current_mode == ThemeMode.NIGHT else theme_day

signal theme_changed(mode: ThemeMode)

## 战斗界面模式：false=横屏3D（默认），true=竖屏2D旧版
var use_legacy_battle: bool = false

func get_battle_scene_path() -> String:
	if use_legacy_battle:
		return "res://BattleSceneLegacy.tscn"
	return "res://BattleScene3D.tscn"


func _ready() -> void:
	_setup_ui_font()
	_load_theme()
	_load_battle_mode()


func _setup_ui_font() -> void:
	var font_path := "res://assets/share/font_pixel.ttf"
	if not FileAccess.file_exists(font_path):
		return
	var f := FontFile.new()
	if f.load_dynamic_font(font_path) == OK:
		ThemeDB.fallback_font = f


func switch_theme(mode: ThemeMode) -> void:
	current_mode = mode
	_save_theme()
	theme_changed.emit(mode)


func toggle_theme() -> void:
	current_mode = ThemeMode.DAY if current_mode == ThemeMode.NIGHT else ThemeMode.NIGHT
	_save_theme()
	theme_changed.emit(current_mode)


func _save_theme() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(CONFIG_SECTION, "mode", current_mode)
	cfg.save(CONFIG_PATH)


func _load_theme() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(CONFIG_PATH)
	if err == OK:
		var saved_mode: int = cfg.get_value(CONFIG_SECTION, "mode", ThemeMode.NIGHT)
		current_mode = saved_mode as ThemeMode
	else:
		current_mode = ThemeMode.NIGHT


func _save_battle_mode() -> void:
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)
	cfg.set_value(CONFIG_SECTION, "battle_mode", use_legacy_battle)
	cfg.save(CONFIG_PATH)


func _load_battle_mode() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(CONFIG_PATH)
	if err == OK:
		use_legacy_battle = cfg.get_value(CONFIG_SECTION, "battle_mode", false)


func save_battle_mode() -> void:
	_save_battle_mode()


# ============================================================
#  UI 工厂函数
# ============================================================

func make_topbar(top_ratio: float = 0.083) -> ColorRect:
	var h = ph(top_ratio)
	var r = ColorRect.new()
	r.name = "TopBar"
	r.color = current.topbar_bg
	r.anchor_left = 0.0; r.anchor_top = 0.0
	r.anchor_right = 1.0; r.anchor_bottom = 0.0
	r.offset_left = 0; r.offset_top = 0
	r.offset_right = 0; r.offset_bottom = h
	return r


func make_topbar_bottom_line(top_ratio: float = 0.083) -> ColorRect:
	var h = ph(top_ratio)
	var r = ColorRect.new()
	r.name = "TopBarLine"
	r.color = current.topbar_border
	r.anchor_left = 0.0; r.anchor_top = 0.0
	r.anchor_right = 1.0; r.anchor_bottom = 0.0
	r.offset_left = 0; r.offset_top = h - 2
	r.offset_right = 0; r.offset_bottom = h
	return r


var _bg_day_tex: Texture2D = null
var _bg_night_tex: Texture2D = null

func _get_bg_day() -> Texture2D:
	if _bg_day_tex == null:
		_bg_day_tex = load("res://assets/theme/bg_day.png")
	return _bg_day_tex

func _get_bg_night() -> Texture2D:
	if _bg_night_tex == null:
		_bg_night_tex = load("res://assets/theme/bg_night.png")
	return _bg_night_tex


func make_bg() -> TextureRect:
	var r = TextureRect.new()
	r.texture = _get_bg_night() if current_mode == ThemeMode.NIGHT else _get_bg_day()
	r.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.anchor_left = 0.0; r.anchor_top = 0.0
	r.anchor_right = 1.0; r.anchor_bottom = 1.0
	r.offset_left = 0; r.offset_top = 0
	r.offset_right = 0; r.offset_bottom = 0
	return r


func apply_bg(node: Node) -> void:
	if node is TextureRect:
		(node as TextureRect).texture = _get_bg_night() if current_mode == ThemeMode.NIGHT else _get_bg_day()
	elif node is ColorRect:
		(node as ColorRect).color = current.bg


func make_title(text: String, font_size: int = 200, bottom_ratio: float = 0.135) -> Label:
	var lbl = Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", current.title)
	lbl.add_theme_color_override("font_shadow_color", current.title_shadow)
	lbl.add_theme_constant_override("shadow_offset_x", current.shadow_offset)
	lbl.add_theme_constant_override("shadow_offset_y", current.shadow_offset)
	lbl.anchor_left = 0.0; lbl.anchor_top = 0.0
	lbl.anchor_right = 1.0; lbl.anchor_bottom = 0.0
	lbl.offset_left = 0; lbl.offset_top = 0
	lbl.offset_right = 0; lbl.offset_bottom = ph(bottom_ratio)
	return lbl


func make_version(text: String, font_size: int = 50) -> Label:
	var lbl = Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", current.version)
	lbl.add_theme_color_override("font_shadow_color", current.version_shadow)
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)
	lbl.anchor_left = 0.0; lbl.anchor_top = 1.0
	lbl.anchor_right = 1.0; lbl.anchor_bottom = 1.0
	lbl.offset_left = 0; lbl.offset_top = ph(-0.083)
	lbl.offset_right = 0; lbl.offset_bottom = ph(-0.016)
	return lbl


func make_bordered_btn(text: String, border_color: Color, font_size: int = 55) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", font_size)
	var s = StyleBoxFlat.new()
	s.bg_color = current.btn_bg
	s.border_width_left = 3; s.border_width_right = 3
	s.border_width_top = 3; s.border_width_bottom = 3
	s.border_color = border_color
	s.corner_radius_top_left = 16; s.corner_radius_top_right = 16
	s.corner_radius_bottom_left = 16; s.corner_radius_bottom_right = 16
	s.content_margin_left = 24; s.content_margin_right = 24
	var sh = s.duplicate()
	sh.bg_color = current.btn_bg_hover
	sh.border_color = border_color.lightened(0.3)
	var sp = s.duplicate()
	sp.bg_color = current.btn_bg_pressed
	sp.border_color = border_color.darkened(0.4)
	btn.add_theme_stylebox_override("normal", s)
	btn.add_theme_stylebox_override("hover", sh)
	btn.add_theme_stylebox_override("pressed", sp)
	btn.add_theme_stylebox_override("focus", s)
	btn.add_theme_color_override("font_color", current.btn_text)
	btn.add_theme_color_override("font_hover_color", current.btn_text_hover)
	btn.add_theme_color_override("font_pressed_color", current.btn_text_hover)
	return btn


func make_gear_btn() -> Button:
	var btn = Button.new()
	btn.text = "\u2699"
	btn.add_theme_font_size_override("font_size", 80)
	var s = StyleBoxFlat.new()
	s.bg_color = current.gear_bg
	s.border_width_left = 3; s.border_width_right = 3
	s.border_width_top = 3; s.border_width_bottom = 3
	s.border_color = Color("#888888")
	s.corner_radius_top_left = 16; s.corner_radius_top_right = 16
	s.corner_radius_bottom_left = 16; s.corner_radius_bottom_right = 16
	s.content_margin_left = 0; s.content_margin_right = 0
	var sh = s.duplicate()
	sh.bg_color = current.gear_hover
	sh.border_color = Color("#aaaaaa")
	btn.add_theme_stylebox_override("normal", s)
	btn.add_theme_stylebox_override("hover", sh)
	btn.add_theme_stylebox_override("pressed", s)
	btn.add_theme_stylebox_override("focus", s)
	btn.add_theme_color_override("font_color", current.btn_text)
	btn.add_theme_color_override("font_hover_color", current.btn_text_hover)
	btn.add_theme_color_override("font_pressed_color", current.btn_text)
	btn.anchor_left = 1.0; btn.anchor_top = 1.0
	btn.anchor_right = 1.0; btn.anchor_bottom = 1.0
	btn.offset_left = pw(-0.13); btn.offset_top = ph(-0.073)
	btn.offset_right = pw(-0.028); btn.offset_bottom = ph(-0.016)
	return btn


func make_back_btn() -> Button:
	var btn = Button.new()
	btn.text = "← 返回"
	btn.add_theme_font_size_override("font_size", 50)
	var s = StyleBoxFlat.new()
	s.bg_color = current.btn_bg
	s.border_width_left = 2; s.border_width_right = 2
	s.border_width_top = 2; s.border_width_bottom = 2
	s.border_color = Color("#888888")
	s.corner_radius_top_left = 10; s.corner_radius_top_right = 10
	s.corner_radius_bottom_left = 10; s.corner_radius_bottom_right = 10
	s.content_margin_left = 20; s.content_margin_right = 20
	var sh = s.duplicate()
	sh.bg_color = current.btn_bg_hover
	btn.add_theme_stylebox_override("normal", s)
	btn.add_theme_stylebox_override("hover", sh)
	btn.add_theme_stylebox_override("pressed", s)
	btn.add_theme_stylebox_override("focus", s)
	btn.add_theme_color_override("font_color", current.btn_text)
	btn.add_theme_color_override("font_hover_color", current.btn_text_hover)
	btn.add_theme_color_override("font_pressed_color", current.btn_text)
	btn.anchor_left = 0.0; btn.anchor_top = 0.0
	btn.anchor_right = 0.0; btn.anchor_bottom = 0.0
	btn.offset_left = pw(0.019); btn.offset_top = ph(0.01)
	btn.offset_right = pw(0.167); btn.offset_bottom = ph(0.042)
	return btn


# ============================================================
#  全局飘窗通知
# ============================================================

func show_global_toast(text: String, color: Color = Color("#FFD700")) -> void:
	var scene_root = get_tree().current_scene
	if scene_root == null:
		return
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 40)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_shadow_color", Color("#000000"))
	lbl.add_theme_constant_override("shadow_offset_x", 2)
	lbl.add_theme_constant_override("shadow_offset_y", 2)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.anchor_left = 0.1; lbl.anchor_top = 0.0
	lbl.anchor_right = 0.9; lbl.anchor_bottom = 0.0
	lbl.offset_top = ph(0.35); lbl.offset_bottom = ph(0.42)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.modulate.a = 0.0
	scene_root.add_child(lbl)
	var tw = create_tween()
	tw.tween_property(lbl, "modulate:a", 1.0, 0.25)
	tw.tween_interval(1.8)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.4)
	tw.tween_callback(lbl.queue_free)
