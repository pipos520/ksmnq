extends Control

## BOSS 首通金币 = 100 × 区域序号（野外地图，仅首次通关发放；[PLACEHOLDER] L4 校准）
const BOSS_FIRST_CLEAR_GOLD := {
	"misty_forest": 100,
	"flame_cavern": 200,
	"storm_tower": 300,
	"shadow_swamp": 400,
	"legendary_ruins": 500,
}

# ============================================================
#  战斗场景 —— 分区域布局
# 双方场地区（5卡位）+ 手牌区 + 墓地 + 卡组 + 信息区
# ============================================================

# 战斗数据
var _player_hp: int = 0      # 在 _ready() 中由 PlayerManager.get_guild_max_hp() 设置
var _player_max_hp: int = 0  # 同上
var _player_energy: int = 3
var _player_max_energy: int = 5
var _enemy_hp: int = 100
var _enemy_max_hp: int = 100
var _enemy_energy: int = 3
var _enemy_max_energy: int = 5

var _player_name: String = "卡师"
var _enemy_name: String = "暗影法师"

# 节点引用
var _player_slots := []  # 5个己方场地卡槽
var _enemy_slots := []   # 5个敌方场地卡槽
var _hand_cards := []    # 己方手牌卡槽
var _enemy_hand_cards := []  # 敌方手牌卡槽

# BattleManager引用
var _battle_manager: BattleManager = null
# 战斗节奏驱动器（横竖屏共用同一驱动协议，见 battle_core/BattleDriver.gd）
var _battle_driver: BattleDriver = null
# UI控件引用
var _end_btn: Button = null
var _phase_label: Label = null
# 攻击选择状态
var _selected_attacker_slot: int = -1
var _attack_target_mode: bool = false

# 拖拽召唤状态
var _drag_hand_index: int = -1
var _is_dragging: bool = false
var _drag_preview: Control = null
var _drag_start_global: Vector2 = Vector2()

# 拖拽攻击状态
var _drag_attack_press_slot: int = -1
var _drag_attack_press_pos: Vector2 = Vector2()
var _is_dragging_attack: bool = false
var _drag_attack_slot: int = -1
var _drag_attack_preview: Control = null

# 动画状态
var _is_animating: bool = false
var _prev_player_field_count: int = 0
# 退出目标：true=主界面，false=地图内继续探索
var _exit_to_main: bool = true
# 数值变化检测（用于浮动数字特效）
var _prev_player_atk := []  # 上次己方场地卡牌攻击力
var _prev_player_hp := []   # 上次己方场地卡牌生命值
var _prev_enemy_atk := []   # 上次敌方场地卡牌攻击力
var _prev_enemy_hp := []    # 上次敌方场地卡牌生命值
var _float_counter: int = 0  # 浮动数字计数，防止同时多个时恢复冲突
var _prev_player_field_size: int = 0  # 上次己方场地卡牌数量
var _prev_enemy_field_size: int = 0  # 上次敌方场地卡牌数量
var _last_summon_hand_idx: int = -1
var _last_summon_slot_idx: int = -1

# 连锁响应状态
var _chain_callback_id: int = -1
var _chain_overlay: ColorRect = null
var _chain_awaiting_response: bool = false

# 弃牌阶段
var _discard_mode: bool = false
var _discard_selected: Array = []  # 选中的手牌索引
var _discard_panel: Panel = null
var _discard_count_label: Label = null
var _discard_confirm_btn: Button = null
var _discard_max: int = 6  # 弃到6张
var _discard_need: int = 0  # 本次需要弃的张数（由信号传入，CO04可能≠手牌-6）
var _discard_callback_id: int = -1  # 当前弃牌回调ID
var _discard_request_queue: Array = []  # ★ 待处理的弃牌请求队列（弹窗忙时排队）
# 飞入墓地动画
var _player_grave_btn: Button = null
var _enemy_grave_btn: Button = null
var _discard_anim_positions: Array = []  # 弃牌动画起始位置（全局坐标）

# === PvP对战相关（已移除：PvP对战功能移除过审） ===
var _turn_timer_label: Label = null  # 回合倒计时标签
# var _is_pvp_battle: bool = false
# var _network_mgr: NetworkBattleManager = null


## tscn 里预置了一套与代码重建同名的 UI 节点（历史遗留）。不清理的话：
# 1) _update_label 按名取节点会命中 tscn 旧节点（先入树），运行时数值刷不到可见层；
# 2) 横屏重排后 tscn 节点按旧锚点错位，从半透明色块下透出鬼影。
const _TSCN_DUP_NODES := [
	"EnemyInfoBar", "EnemyInfoLine", "EnemyName", "EnemyHP", "EnemyEnergy",
	"EnemyHandArea", "EnemyHandLabel", "EnemyHandScroll",
	"EnemyGrave", "EnemyDeck", "EnemyBanish",
	"EnemySlot_0", "EnemySlot_1", "EnemySlot_2", "EnemySlot_3", "EnemySlot_4",
	"MiddleDiv", "PhaseLabel", "TurnTimerLabel",
	"PlayerSlot_0", "PlayerSlot_1", "PlayerSlot_2", "PlayerSlot_3", "PlayerSlot_4",
	"PlayerGrave", "PlayerDeck", "PlayerBanish",
	"HandArea", "HandLabel", "HandScroll",
	"PlayerInfoBar", "PlayerInfoLine", "PlayerName", "PlayerHP", "PlayerEnergy",
	"BottomBar", "EndTurnBtn", "BackBtn",
]

func _ready():
	# 横屏/竖屏画布接线：横屏=1920x1080 画布+按横屏比例重排；竖屏=防御性恢复（幂等）
	if Global.use_legacy_battle:
		Global.exit_landscape_canvas()
	else:
		Global.enter_landscape_canvas()
	# 先释放 tscn 预置的重复 UI 节点（BG/GridBG 背景装饰保留），
	# 让代码重建的节点持有规范名，_update_label 等按名查找命中可见节点
	for n in _TSCN_DUP_NODES:
		var old_n := get_node_or_null(NodePath(n))
		if old_n:
			remove_child(old_n)
			old_n.free()
	# 按公会称号等级设置玩家血量
	var guild_max_hp = PlayerManager.get_guild_max_hp()
	_player_max_hp = guild_max_hp
	_player_hp = guild_max_hp
	
	# 从Global读取敌人数据（如果有）
	var enemy_data = Global.current_enemy_data
	if not enemy_data.is_empty():
		# 覆盖敌人生成值
		_enemy_name = enemy_data.get("name", "暗影法师")
		_enemy_hp = enemy_data.get("hp", 100)
		_enemy_max_hp = enemy_data.get("max_hp", 100)
		_enemy_energy = enemy_data.get("energy", 3)
		_enemy_max_energy = enemy_data.get("max_energy", 5)
	
	# 背景
	var bg = ColorRect.new()
	bg.color = Color(0.06, 0.04, 0.034)
	bg.anchor_left = 0.0; bg.anchor_top = 0.0
	bg.anchor_right = 1.0; bg.anchor_bottom = 1.0
	add_child(bg)
	
	# 网格装饰
	_add_grid_bg()
	
	# ===== 区域纵向堆叠：横屏按 1080 高度重新分配比例（敌方上/手牌下） =====
	if Global.landscape_canvas:
		_add_info_bar(0.0, 0.095, _enemy_name, _enemy_hp, _enemy_max_hp, _enemy_energy, _enemy_max_energy, true)
		_enemy_hand_cards = _add_enemy_hand_area(0.095, 0.155)
		_add_grave_deck(0.155, 0.23, true)
		_enemy_slots = _add_field_slots(0.23, 0.40, Color(0.7, 0.2, 0.2, 0.3), true)
		_add_middle_divider(0.40, 0.465)
		_player_slots = _add_field_slots(0.465, 0.63, Color(0.2, 0.5, 0.8, 0.3), false)
		_add_grave_deck(0.63, 0.695, false)
		_hand_cards = _add_hand_area(0.695, 0.87)
		_add_info_bar(0.87, 0.945, _player_name, _player_hp, _player_max_hp, _player_energy, _player_max_energy, false)
		_add_bottom_bar(0.945, 1.0)
	else:
		# ===== 1. 敌方信息区 (0 ~ 0.06) 115px =====
		_add_info_bar(0.0, 0.09, _enemy_name, _enemy_hp, _enemy_max_hp, _enemy_energy, _enemy_max_energy, true)
		
		# ===== 2. 敌方手牌区 (0.06 ~ 0.10) 77px =====
		_enemy_hand_cards = _add_enemy_hand_area(0.09, 0.16)
		
		# ===== 3. 敌方墓地/卡组 (0.10 ~ 0.15) 96px =====
		_add_grave_deck(0.16, 0.24, true)
		
		# ===== 4. 敌方场地区 (0.16 ~ 0.32) 307px =====
		_enemy_slots = _add_field_slots(0.24, 0.36, Color(0.7, 0.2, 0.2, 0.3), true)
		
		# ===== 5. 中间分隔区 (0.32 ~ 0.35) 58px =====
		_add_middle_divider(0.36, 0.40)
		
		# ===== 6. 己方场地区 (0.36 ~ 0.52) 307px =====
		_player_slots = _add_field_slots(0.40, 0.54, Color(0.2, 0.5, 0.8, 0.3), false)
		
		# ===== 7. 己方墓地/卡组 (0.52 ~ 0.57) 96px =====
		_add_grave_deck(0.54, 0.62, false)
		
		# ===== 8. 己方手牌区 (0.57 ~ 0.78) 403px =====
		_hand_cards = _add_hand_area(0.62, 0.8685)
		
		# ===== 9. 己方信息区 (0.78 ~ 0.84) 115px =====
		_add_info_bar(0.8685, 0.937, _player_name, _player_hp, _player_max_hp, _player_energy, _player_max_energy, false)
		
		# ===== 10. 底部操作栏 (0.84 ~ 1.0) 307px =====
		_add_bottom_bar(0.937, 1.0)
	
	# 更新显示
	_update_all_info()
	
	# ===== 初始化战斗系统（面向对象） =====
	_init_battle()
	
	# 打印所有区域调试信息
	_debug_print_layout()
	
	# ===== PvP对战检测（已移除：PvP对战功能移除过审） =====
	# 检查场景树中是否有NetworkBattleManager（由MatchmakingScene转移过来）
	# _check_pvp_setup()


# ===== 网格背景装饰 =====
func _add_grid_bg():
	var grid = ColorRect.new()
	grid.color = Color(0.12, 0.08, 0.068, 0.3)
	grid.anchor_left = 0.0; grid.anchor_top = 0.16
	grid.anchor_right = 1.0; grid.anchor_bottom = 0.52
	add_child(grid)


# ===== 信息条 =====
func _add_info_bar(top: float, bottom: float, name_str: String, hp: int, max_hp: int, energy: int, max_energy: int, is_enemy: bool):
	var bar = ColorRect.new()
	bar.color = Color(0.10, 0.08, 0.068) if is_enemy else Color(0.08, 0.12, 0.18)
	bar.anchor_left = 0.0; bar.anchor_top = top
	bar.anchor_right = 1.0; bar.anchor_bottom = bottom
	add_child(bar)
	
	# 底边线
	var line = ColorRect.new()
	line.color = Color(0.3, 0.2, 0.17, 0.5)
	line.anchor_left = 0.0; line.anchor_top = bottom
	line.anchor_right = 1.0; line.anchor_bottom = bottom
	line.offset_top = -2; line.offset_bottom = 0
	add_child(line)
	
	# ===== 第一排：名字 =====
	var mid_y = (top + bottom) / 2.0
	var name_lbl = Label.new()
	name_lbl.text = name_str
	name_lbl.add_theme_font_size_override("font_size", 50)
	name_lbl.add_theme_color_override("font_color", Color("#e8d5b7"))
	name_lbl.add_theme_constant_override("shadow_offset_x", 2)
	name_lbl.add_theme_constant_override("shadow_offset_y", 2)
	name_lbl.add_theme_color_override("font_shadow_color", Color("#000000"))
	name_lbl.anchor_left = 0.0; name_lbl.anchor_top = top
	# 横屏：单行布局（名字左/血量中/能量右）；竖屏：上排名字
	if Global.landscape_canvas:
		name_lbl.anchor_right = 0.32; name_lbl.anchor_bottom = bottom
	else:
		name_lbl.anchor_right = 0.25; name_lbl.anchor_bottom = mid_y
	name_lbl.offset_left = Global.pw(0.025)
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(name_lbl)
	
	# ===== 第二排：血量 + 能量 =====
	var mid = (top + bottom) / 2.0
	# 血量
	var hp_lbl = Label.new()
	hp_lbl.name = ("EnemyHP" if is_enemy else "PlayerHP")
	hp_lbl.text = "" + str(hp) + "/" + str(max_hp)
	hp_lbl.add_theme_font_size_override("font_size", 40)
	hp_lbl.add_theme_color_override("font_color", Color("#e74c3c"))
	hp_lbl.add_theme_constant_override("shadow_offset_x", 1)
	hp_lbl.add_theme_constant_override("shadow_offset_y", 1)
	hp_lbl.add_theme_color_override("font_shadow_color", Color("#000000"))
	if Global.landscape_canvas:
		hp_lbl.anchor_left = 0.32; hp_lbl.anchor_top = top
		hp_lbl.anchor_right = 0.58; hp_lbl.anchor_bottom = bottom
	else:
		hp_lbl.anchor_left = 0.0; hp_lbl.anchor_top = mid
		hp_lbl.anchor_right = 0.40; hp_lbl.anchor_bottom = bottom
	hp_lbl.offset_left = Global.pw(0.025)
	hp_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(hp_lbl)
	
	# 能量
	var energy_lbl = Label.new()
	energy_lbl.name = ("EnemyEnergy" if is_enemy else "PlayerEnergy")
	energy_lbl.text = "" + str(energy) + "/" + str(max_energy)
	energy_lbl.add_theme_font_size_override("font_size", 40)
	energy_lbl.add_theme_color_override("font_color", Color("#f9d371"))
	energy_lbl.add_theme_constant_override("shadow_offset_x", 1)
	energy_lbl.add_theme_constant_override("shadow_offset_y", 1)
	energy_lbl.add_theme_color_override("font_shadow_color", Color("#000000"))
	if Global.landscape_canvas:
		energy_lbl.anchor_left = 0.58; energy_lbl.anchor_top = top
		energy_lbl.anchor_right = 0.84; energy_lbl.anchor_bottom = bottom
	else:
		energy_lbl.anchor_left = 0.40; energy_lbl.anchor_top = mid
		energy_lbl.anchor_right = 0.70; energy_lbl.anchor_bottom = bottom
	energy_lbl.offset_left = Global.pw(0.025)
	energy_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(energy_lbl)


# ===== 墓地/卡组区 =====
func _add_grave_deck(top: float, bottom: float, is_enemy: bool):
	var prefix = "Enemy" if is_enemy else "Player"
	
	# 墓地（左侧）
	var grave_btn = Button.new()
	grave_btn.name = prefix + "Grave"
	grave_btn.text = "\n0"
	grave_btn.add_theme_font_size_override("font_size", 50)
	grave_btn.disabled = false
	var grave_s = StyleBoxFlat.new()
	grave_s.bg_color = Color(0.15, 0.10, 0.20)
	grave_s.border_width_left = 2; grave_s.border_width_right = 2
	grave_s.border_width_top = 2; grave_s.border_width_bottom = 2
	grave_s.border_color = Color(0.4, 0.3, 0.5)
	grave_s.corner_radius_top_left = 8; grave_s.corner_radius_top_right = 8
	grave_s.corner_radius_bottom_left = 8; grave_s.corner_radius_bottom_right = 8
	grave_btn.add_theme_stylebox_override("normal", grave_s)
	grave_btn.add_theme_color_override("font_color", Color("#a0a0b0"))
	grave_btn.anchor_left = 0.02; grave_btn.anchor_top = top
	grave_btn.anchor_right = 0.0; grave_btn.anchor_bottom = bottom
	grave_btn.offset_right = Global.pw(0.07) if Global.landscape_canvas else Global.pw(0.13)
	grave_btn.offset_top += Global.ph(0.005); grave_btn.offset_bottom -= Global.ph(0.005)
	add_child(grave_btn)
	if is_enemy:
		grave_btn.pressed.connect(_on_enemy_grave_clicked)
		_enemy_grave_btn = grave_btn
	else:
		grave_btn.pressed.connect(_on_player_grave_clicked)
		_player_grave_btn = grave_btn
	
	# 卡组（右侧）
	var deck_btn = Button.new()
	deck_btn.name = prefix + "Deck"
	deck_btn.text = "\n30"
	deck_btn.add_theme_font_size_override("font_size", 50)
	deck_btn.disabled = true
	var deck_s = StyleBoxFlat.new()
	deck_s.bg_color = Color(0.12, 0.15, 0.22)
	deck_s.border_width_left = 2; deck_s.border_width_right = 2
	deck_s.border_width_top = 2; deck_s.border_width_bottom = 2
	deck_s.border_color = Color(0.3, 0.4, 0.6)
	deck_s.corner_radius_top_left = 8; deck_s.corner_radius_top_right = 8
	deck_s.corner_radius_bottom_left = 8; deck_s.corner_radius_bottom_right = 8
	deck_btn.add_theme_stylebox_override("normal", deck_s)
	deck_btn.add_theme_color_override("font_color", Color("#a0a0b0"))
	deck_btn.anchor_left = 1.0; deck_btn.anchor_top = top
	deck_btn.anchor_right = 1.0; deck_btn.anchor_bottom = bottom
	deck_btn.offset_left = Global.pw(-0.09) if Global.landscape_canvas else Global.pw(-0.15)
	deck_btn.offset_right = Global.pw(-0.02)
	deck_btn.offset_top += Global.ph(0.005); deck_btn.offset_bottom -= Global.ph(0.005)
	add_child(deck_btn)
	
	# 除外区（中间）
	var banish_btn = Button.new()
	banish_btn.name = prefix + "Banish"
	banish_btn.text = "\n0"
	banish_btn.add_theme_font_size_override("font_size", 50)
	banish_btn.disabled = false
	var banish_s = StyleBoxFlat.new()
	banish_s.bg_color = Color(0.08, 0.06, 0.18)
	banish_s.border_width_left = 2; banish_s.border_width_right = 2
	banish_s.border_width_top = 2; banish_s.border_width_bottom = 2
	banish_s.border_color = Color(0.5, 0.2, 0.6)
	banish_s.corner_radius_top_left = 8; banish_s.corner_radius_top_right = 8
	banish_s.corner_radius_bottom_left = 8; banish_s.corner_radius_bottom_right = 8
	banish_btn.add_theme_stylebox_override("normal", banish_s)
	banish_btn.add_theme_color_override("font_color", Color("#b080c0"))
	banish_btn.anchor_left = 0.5; banish_btn.anchor_top = top
	banish_btn.anchor_right = 0.5; banish_btn.anchor_bottom = bottom
	if Global.landscape_canvas:
		banish_btn.offset_left = Global.pw(-0.04); banish_btn.offset_right = Global.pw(0.04)
	else:
		banish_btn.offset_left = Global.pw(-0.07); banish_btn.offset_right = Global.pw(0.07)
	banish_btn.offset_top += Global.ph(0.005); banish_btn.offset_bottom -= Global.ph(0.005)
	add_child(banish_btn)
	if is_enemy:
		banish_btn.pressed.connect(_on_enemy_banish_clicked)
	else:
		banish_btn.pressed.connect(_on_player_banish_clicked)


# ============================================================
#  卡面/卡位素材（羊皮纸墨线风）
# ============================================================
const CARD_FACE_PATH := "res://assets/cards/ink/card_face.png"
const SLOT_RECESS_PATH := "res://assets/cards/ink/slot_recess.png"
var _card_face_tex: Texture2D
var _slot_recess_tex: Texture2D

func _get_card_face_tex() -> Texture2D:
	if _card_face_tex == null:
		_card_face_tex = load(CARD_FACE_PATH)
	return _card_face_tex

func _get_slot_recess_tex() -> Texture2D:
	if _slot_recess_tex == null:
		_slot_recess_tex = load(SLOT_RECESS_PATH)
	return _slot_recess_tex

func _make_flat_fallback(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_width_left = 2; s.border_width_right = 2
	s.border_width_top = 2; s.border_width_bottom = 2
	s.border_color = border
	s.corner_radius_top_left = 6; s.corner_radius_top_right = 6
	s.corner_radius_bottom_left = 6; s.corner_radius_bottom_right = 6
	return s

## 卡面样式（手牌/场地位上的卡牌），素材缺失时回退纯色羊皮纸块
func _make_card_face_style(tint: Color = Color.WHITE) -> StyleBox:
	var tex := _get_card_face_tex()
	if tex == null:
		return _make_flat_fallback(Color(0.87, 0.80, 0.62), Color(0.30, 0.20, 0.12))
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.modulate_color = tint
	return sb

## 空卡位凹槽样式
func _make_slot_recess_style(tint: Color = Color.WHITE) -> StyleBox:
	var tex := _get_slot_recess_tex()
	if tex == null:
		return _make_flat_fallback(Color(0.24, 0.18, 0.12, 0.9), Color(0.35, 0.25, 0.15))
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.modulate_color = tint
	return sb

func _apply_all_states(btn: Button, sb: StyleBox) -> void:
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(state, sb)

## 功能高亮描边（绿色可召唤 / 金色可攻击 / 红色可选中）
func _set_card_highlight(btn: Button, color: Color) -> void:
	var hl := btn.get_node_or_null("HighlightOverlay") as Panel
	if hl == null:
		hl = Panel.new()
		hl.name = "HighlightOverlay"
		hl.set_anchors_preset(Control.PRESET_FULL_RECT)
		hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var hs := StyleBoxFlat.new()
		hs.bg_color = Color(0, 0, 0, 0)
		hs.border_width_left = 3; hs.border_width_right = 3
		hs.border_width_top = 3; hs.border_width_bottom = 3
		hl.add_theme_stylebox_override("panel", hs)
		btn.add_child(hl)
	var hs2 := hl.get_theme_stylebox("panel") as StyleBoxFlat
	if hs2:
		hs2.border_color = color
	hl.visible = true

func _clear_card_highlight(btn: Button) -> void:
	var hl := btn.get_node_or_null("HighlightOverlay") as Panel
	if hl:
		hl.visible = false

func _mk_card_label(lname: String, r: Rect2, fsize: int, col: Color, halign: int, autowrap: bool = false) -> Label:
	var l := Label.new()
	l.name = lname
	l.anchor_left = r.position.x
	l.anchor_top = r.position.y
	l.anchor_right = r.position.x + r.size.x
	l.anchor_bottom = r.position.y + r.size.y
	l.offset_left = 0; l.offset_top = 0
	l.offset_right = 0; l.offset_bottom = 0
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", col)
	l.horizontal_alignment = halign
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if autowrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

## 卡面文字组：费用左上蜡印 / 元素右上 / 名称条 / 描述区 / 攻击左下 / 生命右下
## 分区坐标与 card_face.png 的墨线结构一一对应（横线约在 16% 与 72% 高度）
func _add_card_labels(parent: Control, scale: float) -> void:
	var ink_dark := Color("#3a2617")   # 名称主墨色
	var ink_dim := Color("#54402c")    # 描述次级墨色
	var wax_red := Color("#8a2418")    # 费用蜡印红
	var atk_red := Color("#9c2b1e")
	var hp_green := Color("#1f6b38")

	var cost_size = max(12, int(24 * scale * 1.6))
	var elem_size = max(10, int(24 * scale * 1.2))
	var name_size = max(12, int(30 * scale * 1.3))
	var desc_size = max(9, int(20 * scale * 1.1))
	var atk_hp_size = max(12, int(22 * scale * 1.8))

	# 费用-左上角（朱红蜡印徽章上）
	parent.add_child(_mk_card_label("CostLabel", Rect2(0.04, 0.03, 0.14, 0.11), cost_size, wax_red, HORIZONTAL_ALIGNMENT_CENTER))
	# 元素-右上角（小方框内）
	parent.add_child(_mk_card_label("ElemLabel", Rect2(0.82, 0.03, 0.14, 0.11), elem_size, ink_dim, HORIZONTAL_ALIGNMENT_CENTER))
	# 名称条（顶部两方框之间）
	var name_l := _mk_card_label("NameLabel", Rect2(0.21, 0.03, 0.58, 0.11), name_size, ink_dark, HORIZONTAL_ALIGNMENT_CENTER)
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	parent.add_child(name_l)
	# 描述区（上下两条墨线之间）：字段 | 效果数
	parent.add_child(_mk_card_label("DescLabel", Rect2(0.09, 0.19, 0.82, 0.50), desc_size, ink_dim, HORIZONTAL_ALIGNMENT_CENTER, true))
	# 攻击-左下（墨剑图标右侧）
	parent.add_child(_mk_card_label("AtkLabel", Rect2(0.16, 0.75, 0.18, 0.21), atk_hp_size, atk_red, HORIZONTAL_ALIGNMENT_LEFT))
	# 生命-右下（墨心图标左侧）
	parent.add_child(_mk_card_label("HpLabel", Rect2(0.62, 0.75, 0.18, 0.21), atk_hp_size, hp_green, HORIZONTAL_ALIGNMENT_RIGHT))

func _get_card_labels(btn: Button) -> Dictionary:
	return {
		"elem": btn.get_node_or_null("ElemLabel") as Label,
		"cost": btn.get_node_or_null("CostLabel") as Label,
		"name": btn.get_node_or_null("NameLabel") as Label,
		"desc": btn.get_node_or_null("DescLabel") as Label,
		"atk": btn.get_node_or_null("AtkLabel") as Label,
		"hp": btn.get_node_or_null("HpLabel") as Label,
	}

## 填充卡牌文字到卡面对应分区
func _set_card_texts(btn: Button, card: BattleCard) -> void:
	var lbls := _get_card_labels(btn)
	# 元素-右上角（当前元素图标已清空，保留分区）
	if lbls.elem:
		lbls.elem.text = ""
	# 费用-左上角蜡印
	if lbls.cost:
		lbls.cost.text = str(card.base_cost)
	# 名称条
	if lbls.name:
		lbls.name.text = card.card_name
	# 描述区：字段 | 效果数
	if lbls.desc:
		var dt := ""
		if card.fields.size() > 0:
			dt += "|".join(card.fields)
		if card.effects.size() > 0:
			if dt != "":
				dt += "\n"
			dt += str(card.effects.size()) + "效果"
		lbls.desc.text = dt
	# 攻/血角标
	if lbls.atk:
		lbls.atk.text = str(card.current_atk)
	if lbls.hp:
		lbls.hp.text = str(card.current_hp)

func _clear_card_texts(btn: Button) -> void:
	var lbls := _get_card_labels(btn)
	for key in lbls:
		var l: Label = lbls[key]
		if l:
			l.text = ""


# ===== 场地区（5个可点击Button卡位，固定宽高，子Label布局同手牌） =====
func _add_field_slots(top: float, bottom: float, slot_color: Color, is_enemy: bool = false) -> Array:
	var slots := []
	var area_h = self.size.y * (bottom - top)
	var gap_r = 0.025
	var slot_w_r: float
	var slot_h_r: float
	if Global.landscape_canvas:
		# 横屏：卡槽取与手牌同级的高度基准尺寸，整排自动居中
		var slot_w_px := Global.ph(0.115)
		var slot_h_px := slot_w_px * (680.0 / 480.0)
		slot_w_r = slot_w_px / Global.pw(1.0)
		slot_h_r = slot_h_px / Global.ph(1.0)
		gap_r = 0.02
	else:
		var side_margin_r = 0.05
		slot_w_r = (1.0 - side_margin_r * 2 - gap_r * 4) / 5.0
		# slot_w_r是宽度百分比，要转成高度百分比需要乘以屏幕宽高比
		slot_h_r = slot_w_r * (680.0/480.0) * (self.size.x / self.size.y)
		var max_h_r = (bottom - top) * 0.85
		if slot_h_r > max_h_r:
			slot_h_r = max_h_r
	var total_w_r = 5 * slot_w_r + 4 * gap_r
	var start_x_r = (1.0 - total_w_r) / 2.0
	var center_y_r = (top + bottom) / 2.0
	
	# 字号缩放——以实际像素宽度/300.0为基准（卡面标签统一由 _add_card_labels 生成）
	var actual_slot_w = (Global.pw(1.0) if Global.landscape_canvas else self.size.x) * slot_w_r  # 场地卡槽实际像素宽度
	var scale = actual_slot_w / 300.0

	for i in range(5):
		# 全部使用锚点百分比定位——自适应任何屏幕
		var slot_btn = Button.new()
		slot_btn.name = ("EnemySlot_" if is_enemy else "PlayerSlot_") + str(i)
		slot_btn.anchor_left = start_x_r + i * (slot_w_r + gap_r)
		slot_btn.anchor_top = center_y_r - slot_h_r / 2.0
		slot_btn.anchor_right = start_x_r + i * (slot_w_r + gap_r) + slot_w_r
		slot_btn.anchor_bottom = center_y_r + slot_h_r / 2.0
		# 偏移全归零，尺寸完全由锚点决定
		slot_btn.offset_left = 0; slot_btn.offset_top = 0
		slot_btn.offset_right = 0; slot_btn.offset_bottom = 0
		slot_btn.text = ""
		
		# 空位：羊皮纸墨线凹槽
		_apply_all_states(slot_btn, _make_slot_recess_style())

		# 卡面文字组（与手牌同一套分区）
		_add_card_labels(slot_btn, scale)
		
		# 护盾遮罩（半透明浅蓝色，覆盖整张卡）
		var shield_overlay = ColorRect.new()
		shield_overlay.name = "ShieldOverlay"
		shield_overlay.anchor_left = 0.0; shield_overlay.anchor_top = 0.0
		shield_overlay.anchor_right = 1.0; shield_overlay.anchor_bottom = 1.0
		shield_overlay.offset_left = 0; shield_overlay.offset_top = 0
		shield_overlay.offset_right = 0; shield_overlay.offset_bottom = 0
		shield_overlay.color = Color(0.5, 0.8, 1.0, 0.35)
		shield_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		shield_overlay.visible = false
		slot_btn.add_child(shield_overlay)
		
		# 护盾数值标签（卡牌下方外部）
		var shield_lbl = Label.new()
		shield_lbl.name = "ShieldLabel"
		shield_lbl.anchor_left = 0.0; shield_lbl.anchor_top = 1.0
		shield_lbl.anchor_right = 1.0; shield_lbl.anchor_bottom = 1.0
		shield_lbl.offset_left = 0; shield_lbl.offset_top = 2
		shield_lbl.offset_right = 0; shield_lbl.offset_bottom = 0
		shield_lbl.add_theme_font_size_override("font_size", max(10, int(35 * scale)))
		shield_lbl.add_theme_color_override("font_color", Color("#4FC3F7"))
		shield_lbl.text = ""
		shield_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		shield_lbl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		shield_lbl.visible = false
		slot_btn.add_child(shield_lbl)
		
		if is_enemy:
			slot_btn.pressed.connect(_on_enemy_slot_clicked.bind(i))
			slot_btn.gui_input.connect(_on_enemy_slot_gui_input.bind(i))
		else:
			slot_btn.pressed.connect(_on_player_slot_clicked.bind(i))
			slot_btn.gui_input.connect(_on_player_slot_gui_input.bind(i))
		
		add_child(slot_btn)
		slots.append(slot_btn)
	
	return slots


# ===== 中间分隔区 =====
func _add_middle_divider(top: float, bottom: float):
	var div = ColorRect.new()
	div.color = Color(0.15, 0.10, 0.085, 0.6)
	div.anchor_left = 0.0; div.anchor_top = top
	div.anchor_right = 1.0; div.anchor_bottom = bottom
	add_child(div)
	
	# 阶段标签（中间分隔区左侧）
	_phase_label = Label.new()
	_phase_label.name = "PhaseLabel"
	_phase_label.anchor_left = 0.0; _phase_label.anchor_top = top
	_phase_label.anchor_right = 0.55; _phase_label.anchor_bottom = bottom
	_phase_label.offset_left = Global.pw(0.04)
	_phase_label.add_theme_font_size_override("font_size", 50)
	_phase_label.add_theme_color_override("font_color", Color("#e8d5b7"))
	_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_phase_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_phase_label.text = "主要阶段"
	add_child(_phase_label)
	
	# 倒计时标签（中间分隔区右侧）
	_turn_timer_label = Label.new()
	_turn_timer_label.name = "TurnTimerLabel"
	_turn_timer_label.anchor_left = 0.55; _turn_timer_label.anchor_top = top
	_turn_timer_label.anchor_right = 1.0; _turn_timer_label.anchor_bottom = bottom
	_turn_timer_label.add_theme_font_size_override("font_size", 45)
	_turn_timer_label.add_theme_color_override("font_color", Color("#a0a0b0"))
	_turn_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_turn_timer_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_turn_timer_label.offset_right = -Global.pw(0.04)
	_turn_timer_label.text = ""
	add_child(_turn_timer_label)
	
	# 上装饰线
	var line_top = ColorRect.new()
	line_top.color = Color(0.4, 0.2, 0.17, 0.3)
	line_top.anchor_left = 0.1; line_top.anchor_top = top
	line_top.anchor_right = 0.9; line_top.anchor_bottom = top
	line_top.offset_bottom = 1
	add_child(line_top)
	
	# 下装饰线
	var line_bottom = ColorRect.new()
	line_bottom.color = Color(0.4, 0.2, 0.17, 0.3)
	line_bottom.anchor_left = 0.1; line_bottom.anchor_top = bottom
	line_bottom.anchor_right = 0.9; line_bottom.anchor_bottom = bottom
	line_bottom.offset_top = -1
	add_child(line_bottom)


# ===== 手牌区（固定宽高卡牌Button，子Label布局，左右滑动） =====
func _add_hand_area(top: float, bottom: float) -> Array:
	var cards := []
	var gap = Global.pw(0.015)
	
	# 卡牌宽度自适应（占手牌区宽度的22%），高度为宽度*1.4；横屏按高度基准取尺寸
	var slot_w = Global.ph(0.105) if Global.landscape_canvas else Global.pw(0.22)
	var slot_h = slot_w * (680.0/480.0)
	
	# 字号缩放（相对于标准卡牌宽度300px，卡面标签统一由 _add_card_labels 生成）
	var scale = slot_w / 300.0
	
	# 手牌区背景
	var hand_bg = ColorRect.new()
	hand_bg.color = Color(0.08, 0.06, 0.051, 0.5)
	hand_bg.anchor_left = 0.0; hand_bg.anchor_top = top
	hand_bg.anchor_right = 1.0; hand_bg.anchor_bottom = bottom
	add_child(hand_bg)
	
	# 手牌标签
	var lbl = Label.new()
	lbl.name = "HandLabel"
	lbl.text = "手牌"
	lbl.add_theme_font_size_override("font_size", 50)
	lbl.add_theme_color_override("font_color", Color(0.6, 0.5, 0.7, 0.6))
	lbl.anchor_left = 0.02; lbl.anchor_top = top
	lbl.anchor_right = 0.0; lbl.anchor_bottom = top
	lbl.offset_bottom = Global.ph(0.05) if Global.landscape_canvas else Global.ph(0.03)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(lbl)
	
	# 水平滚动容器
	var scroll = ScrollContainer.new()
	scroll.name = "HandScroll"
	scroll.anchor_left = 0.0; scroll.anchor_top = top
	scroll.anchor_right = 1.0; scroll.anchor_bottom = bottom
	scroll.offset_left = Global.pw(0.02)
	scroll.offset_top = Global.ph(0.028)
	scroll.offset_right = Global.pw(-0.02)
	scroll.offset_bottom = Global.ph(-0.005)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.scroll_deadzone = 0
	add_child(scroll)
	
	# 内部容器（用普通Control，手动设置内容尺寸，配合偏移定位）
	var card_container = Control.new()
	card_container.name = "HandCardContainer"
	card_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_container.custom_minimum_size = Vector2(10 * slot_w + 9 * gap, slot_h)
	scroll.add_child(card_container)
	
	# 手牌卡牌（可点击Button，使用偏移定位，精确控制尺寸）
	for i in range(10):
		var card_btn = Button.new()
		card_btn.name = "HandCard_" + str(i)
		
		# 卡面底图（羊皮纸墨线卡框），初始为置灰占位
		_apply_all_states(card_btn, _make_card_face_style(Color(0.4, 0.38, 0.45, 0.55)))
		
		# 用偏移定位精确控制位置和尺寸
		card_btn.anchor_left = 0.0; card_btn.anchor_top = 0.0
		card_btn.anchor_right = 0.0; card_btn.anchor_bottom = 0.0
		card_btn.offset_left = i * (slot_w + gap)
		card_btn.offset_top = 0
		card_btn.offset_right = i * (slot_w + gap) + slot_w
		card_btn.offset_bottom = slot_h
		card_btn.mouse_filter = Control.MOUSE_FILTER_PASS
		card_btn.text = ""  # 空文字
		card_btn.disabled = true
		
		# 卡面文字组：文字摆到卡框对应分区（费用蜡印/名称条/描述区/攻血角标）
		_add_card_labels(card_btn, scale)
		
		card_btn.gui_input.connect(_on_hand_card_drag.bind(i))
		
		card_container.add_child(card_btn)
		cards.append(card_btn)
	
	return cards


# ===== 敌方手牌区（紧凑显示卡背，左右滑动） =====
func _add_enemy_hand_area(top: float, bottom: float) -> Array:
	var cards := []
	var gap = Global.pw(0.01)
	
	# 卡牌缩小一点，紧凑显示（横屏按高度基准取尺寸）
	var card_w = Global.ph(0.040) if Global.landscape_canvas else Global.pw(0.075)
	var card_h = card_w * 1.4
	
	# 背景
	var bg = ColorRect.new()
	bg.color = Color(0.10, 0.06, 0.051, 0.4)
	bg.anchor_left = 0.0; bg.anchor_top = top
	bg.anchor_right = 1.0; bg.anchor_bottom = bottom
	add_child(bg)
	
	# 标签（放在底部——第二排）
	var mid_y = (top + bottom) / 2.0
	var lbl = Label.new()
	lbl.name = "EnemyHand"
	lbl.text = "敌方手牌"
	lbl.add_theme_font_size_override("font_size", 40)
	lbl.add_theme_color_override("font_color", Color(0.5, 0.3, 0.6, 0.6))
	if Global.landscape_canvas:
		lbl.anchor_left = 0.01; lbl.anchor_top = top
		lbl.anchor_right = 0.10; lbl.anchor_bottom = bottom
	else:
		lbl.anchor_left = 0.02; lbl.anchor_top = mid_y
		lbl.anchor_right = 0.0; lbl.anchor_bottom = bottom
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(lbl)
	
	# 水平滚动（第一排：卡牌区）
	var scroll = ScrollContainer.new()
	scroll.name = "EnemyHandScroll"
	scroll.anchor_left = 0.0; scroll.anchor_top = top
	scroll.anchor_right = 1.0
	if Global.landscape_canvas:
		scroll.anchor_bottom = bottom
		scroll.offset_left = Global.pw(0.10)
	else:
		scroll.anchor_bottom = mid_y
		scroll.offset_left = Global.pw(0.02)
	scroll.offset_top = Global.ph(0.002)
	scroll.offset_right = Global.pw(-0.02)
	scroll.offset_bottom = Global.ph(-0.002)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	
	var wrapper = Control.new()
	wrapper.name = "EnemyHandWrapper"
	var total_w = 10 * card_w + 9 * gap
	wrapper.custom_minimum_size = Vector2(total_w, 0)
	wrapper.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(wrapper)
	
	for i in range(10):
		var card_panel = Panel.new()
		card_panel.name = "EnemyHandCard_" + str(i)
		
		var s = StyleBoxFlat.new()
		s.bg_color = Color(0.15, 0.10, 0.22)
		s.border_width_left = 1; s.border_width_right = 1
		s.border_width_top = 1; s.border_width_bottom = 1
		s.border_color = Color(0.3, 0.2, 0.4, 0.5)
		s.corner_radius_top_left = 4; s.corner_radius_top_right = 4
		s.corner_radius_bottom_left = 4; s.corner_radius_bottom_right = 4
		card_panel.add_theme_stylebox_override("panel", s)
		
		card_panel.custom_minimum_size = Vector2(card_w, card_h)
		card_panel.position = Vector2(i * (card_w + gap), 0)
		card_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		
		# 卡背
		var back = ColorRect.new()
		back.color = Color(0.10, 0.06, 0.051)
		back.anchor_left = 0.0; back.anchor_top = 0.0
		back.anchor_right = 1.0; back.anchor_bottom = 1.0
		back.offset_left = 2; back.offset_top = 2
		back.offset_right = -2; back.offset_bottom = -2
		card_panel.add_child(back)
		
		# ? 图案
		var pattern = Label.new()
		pattern.text = ""
		pattern.add_theme_font_size_override("font_size", 50)
		pattern.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pattern.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		pattern.anchor_left = 0.0; pattern.anchor_top = 0.0
		pattern.anchor_right = 1.0; pattern.anchor_bottom = 1.0
		card_panel.add_child(pattern)
		
		wrapper.add_child(card_panel)
		cards.append(card_panel)
	
	return cards


# ===== 底部操作栏 =====
func _add_bottom_bar(top: float, bottom: float):
	var bar = ColorRect.new()
	bar.color = Color(0.08, 0.06, 0.051)
	bar.anchor_left = 0.0; bar.anchor_top = top
	bar.anchor_right = 1.0; bar.anchor_bottom = bottom
	add_child(bar)
	
	# 顶边线
	var line = ColorRect.new()
	line.color = Color(0.3, 0.2, 0.17, 0.5)
	line.anchor_left = 0.0; line.anchor_top = top
	line.anchor_right = 1.0; line.anchor_bottom = top
	line.offset_bottom = 2
	add_child(line)
	
	# ★ 退出按钮（最左侧）
	var exit_btn = Button.new()
	exit_btn.name = "BattleExitBtn"
	exit_btn.text = "退出"
	exit_btn.add_theme_font_size_override("font_size", 26 if Global.landscape_canvas else 40)
	var exit_s = StyleBoxFlat.new()
	exit_s.bg_color = Color(0.2, 0.08, 0.08)
	exit_s.border_width_left = 1; exit_s.border_width_right = 1
	exit_s.border_width_top = 1; exit_s.border_width_bottom = 1
	exit_s.border_color = Color(0.6, 0.2, 0.2)
	exit_s.corner_radius_top_left = 10; exit_s.corner_radius_top_right = 10
	exit_s.corner_radius_bottom_left = 10; exit_s.corner_radius_bottom_right = 10
	exit_s.content_margin_left = 8; exit_s.content_margin_right = 8
	exit_btn.add_theme_stylebox_override("normal", exit_s)
	exit_btn.add_theme_stylebox_override("hover", exit_s)
	exit_btn.add_theme_stylebox_override("pressed", exit_s)
	exit_btn.add_theme_stylebox_override("focus", exit_s)
	exit_btn.add_theme_color_override("font_color", Color("#e74c3c"))
	exit_btn.anchor_left = 0.0; exit_btn.anchor_top = top
	exit_btn.anchor_right = 0.12; exit_btn.anchor_bottom = bottom
	exit_btn.offset_left = Global.pw(0.02); exit_btn.offset_right = 0
	exit_btn.offset_top = Global.ph(0.01); exit_btn.offset_bottom = -Global.ph(0.01)
	exit_btn.pressed.connect(_on_battle_exit_btn)
	add_child(exit_btn)
	
	# 阶段标签已移到中间分隔区
	
	# 右侧——下一阶段按钮
	_end_btn = Button.new()
	_end_btn.name = "EndTurnBtn"
	_end_btn.text = "⏭ 结束回合"
	_end_btn.add_theme_font_size_override("font_size", 30 if Global.landscape_canvas else 50)
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.15, 0.12, 0.22)
	s.border_width_left = 2; s.border_width_right = 2
	s.border_width_top = 2; s.border_width_bottom = 2
	s.border_color = Color("#f9d371")
	s.corner_radius_top_left = 12; s.corner_radius_top_right = 12
	s.corner_radius_bottom_left = 12; s.corner_radius_bottom_right = 12
	s.content_margin_left = 12; s.content_margin_right = 12
	_end_btn.add_theme_stylebox_override("normal", s)
	_end_btn.add_theme_stylebox_override("hover", s)
	_end_btn.add_theme_stylebox_override("pressed", s)
	_end_btn.add_theme_stylebox_override("focus", s)
	_end_btn.add_theme_color_override("font_color", Color("#f9d371"))
	_end_btn.anchor_left = 0.5; _end_btn.anchor_top = top
	_end_btn.anchor_right = 1.0; _end_btn.anchor_bottom = bottom
	_end_btn.offset_left = Global.pw(0.02); _end_btn.offset_right = -Global.pw(0.04)
	_end_btn.offset_top = Global.ph(0.005); _end_btn.offset_bottom = -Global.ph(0.005)
	_end_btn.pressed.connect(_on_end_turn_btn)
	add_child(_end_btn)


# ===== 初始化战斗系统（BattleManager驱动） =====
func _init_battle() -> void:
	var deck_id = Global.current_deck_id
	if deck_id == "":
		print("[战斗] 未选择卡组，使用默认卡组")
		deck_id = "starter_deck"
	
	# 创建BattleManager
	_battle_manager = BattleManager.new()

	# 创建战斗节奏驱动器（横竖屏共用同一驱动协议；本场景只保留 2D 表现层）
	_battle_driver = BattleDriver.new()
	_battle_driver.name = "BattleDriver"
	add_child(_battle_driver)
	_battle_driver.attach(_battle_manager)
	_battle_driver.enemy_summon_animation_requested.connect(_on_driver_enemy_summon)
	_battle_driver.enemy_attack_animation_requested.connect(_on_driver_enemy_attack)

	# 连接管理器信号
	_battle_manager.phase_changed.connect(_on_phase_changed)
	_battle_manager.turn_changed.connect(_on_turn_changed)
	_battle_manager.battle_state_changed.connect(_on_battle_state_changed)
	_battle_manager.action_result.connect(_on_action_result)
	_battle_manager.effect_triggered.connect(_on_effect_triggered)
	_battle_manager.deck_search_requested.connect(_on_deck_search_requested)
	_battle_manager.discard_requested.connect(_on_discard_requested)
	_battle_manager.discard_animation_requested.connect(_on_discard_animation_requested)
	_battle_manager.chain_response_requested.connect(_on_chain_response_requested)
	_battle_manager.chain_built.connect(_on_chain_built)
	_battle_manager.chain_resolved.connect(_on_chain_resolved)
	_battle_manager.card_effect_activated.connect(_on_card_effect_activated)
	_battle_manager.effect_line_fromto.connect(_on_effect_line_fromto)
	_battle_manager.element_boost_triggered.connect(_on_element_boost_triggered)
	# 回合结束效果播完（数据层）后推进弃牌阶段（本场景无回合结束视角动画，收到即推进）
	_battle_manager.end_phase_effects_pending_discard.connect(_on_end_phase_effects_pending_discard)
	
	# 连接玩家信号（通过BattleManager获取的玩家引用）
	# 这些会在start_battle之后连接
	
	# 开始战斗
	_battle_manager.start_battle(deck_id, _enemy_name)
	
	# 连接玩家信号（在start_battle后玩家已创建）
	_battle_manager.player_self.hand_changed.connect(_on_player_hand_changed)
	_battle_manager.player_self.field_changed.connect(_on_player_field_changed)
	_battle_manager.player_self.energy_changed.connect(_on_player_energy_changed)
	_battle_manager.player_self.hp_changed.connect(_on_player_hp_changed)
	_battle_manager.player_self.deck_count_changed.connect(_on_player_deck_changed)
	_battle_manager.player_self.grave_changed.connect(_on_player_grave_changed)
	
	_battle_manager.player_self.banish_changed.connect(_on_player_banish_changed)
	
	_battle_manager.player_opponent.hand_changed.connect(_on_enemy_hand_changed)
	_battle_manager.player_opponent.field_changed.connect(_on_enemy_field_changed)
	_battle_manager.player_opponent.energy_changed.connect(_on_enemy_energy_changed)
	_battle_manager.player_opponent.hp_changed.connect(_on_enemy_hp_changed)
	_battle_manager.player_opponent.deck_count_changed.connect(_on_enemy_deck_changed)
	_battle_manager.player_opponent.grave_changed.connect(_on_enemy_grave_changed)
	_battle_manager.player_opponent.banish_changed.connect(_on_enemy_banish_changed)
	
	# 初始刷新敌方手牌显示
	_on_enemy_hand_changed()
	
	# 首次更新UI
	_refresh_all_ui()
	
	# 初始化旧值数组（用于浮动数字特效检测）
	_prev_player_atk = []
	_prev_player_hp = []
	_prev_enemy_atk = []
	_prev_enemy_hp = []
	for i in range(_player_slots.size()):
		var card = _battle_manager.player_self.field[i] if i < _battle_manager.player_self.field.size() else null
		_prev_player_atk.append(card.current_atk if card else 0)
		_prev_player_hp.append(card.current_hp if card else 0)
	for i in range(_enemy_slots.size()):
		var card = _battle_manager.player_opponent.field[i] if i < _battle_manager.player_opponent.field.size() else null
		_prev_enemy_atk.append(card.current_atk if card else 0)
		_prev_enemy_hp.append(card.current_hp if card else 0)
	
	print("[战斗] ========== BattleManager战斗开始 ==========")
	_battle_manager.print_all_status()


# ===== 全面刷新UI =====
func _refresh_all_ui() -> void:
	if _battle_manager == null:
		return
	var self_p = _battle_manager.player_self
	var enemy_p = _battle_manager.player_opponent
	
	# 英雄信息
	_update_label("PlayerHP", " " + str(self_p.hp) + "/" + str(self_p.max_hp))
	_update_label("PlayerEnergy", " " + str(self_p.energy) + "/" + str(self_p.max_energy))
	_update_label("EnemyHP", " " + str(enemy_p.hp) + "/" + str(enemy_p.max_hp))
	_update_label("EnemyEnergy", " " + str(enemy_p.energy) + "/" + str(enemy_p.max_energy))
	
	# 卡组/墓地/除外
	_update_label("PlayerGrave", "\n" + str(self_p.grave.size()))
	_update_label("PlayerDeck", "\n" + str(self_p.deck.size()))
	_update_label("PlayerBanish", "\n" + str(self_p.banished.size()))
	_update_label("EnemyGrave", "\n" + str(enemy_p.grave.size()))
	_update_label("EnemyDeck", "\n" + str(enemy_p.deck.size()))
	_update_label("EnemyBanish", "\n" + str(enemy_p.banished.size()))
	
	# 手牌
	_refresh_hand_ui()
	
	# 场地
	_refresh_field_ui()
	
	# 阶段信息
	_update_phase_ui()


# ===== 刷新手牌UI =====
func _refresh_hand_ui() -> void:
	if _battle_manager == null:
		return
	var self_p = _battle_manager.player_self
	
	# 更新手牌标签
	var hand_label = get_node_or_null("HandLabel")
	if hand_label:
		hand_label.text = "手牌 (" + str(self_p.hand.size()) + "张)"
	
	# 更新手牌卡槽
	for i in range(_hand_cards.size()):
		var btn = _hand_cards[i] as Button
		if btn == null:
			continue
		
		# 获取子Label引用
		var elem_lbl = btn.get_node_or_null("ElemLabel") as Label
		var cost_lbl = btn.get_node_or_null("CostLabel") as Label
		var name_lbl = btn.get_node_or_null("NameLabel") as Label
		var desc_lbl = btn.get_node_or_null("DescLabel") as Label
		var atk_lbl = btn.get_node_or_null("AtkLabel") as Label
		var hp_lbl = btn.get_node_or_null("HpLabel") as Label
		
		if i < self_p.hand.size():
			var card = self_p.hand[i] as BattleCard
			
			# 元素-右上角（当前元素图标已清空，保留分区）
			if elem_lbl:
				elem_lbl.text = ""
			
			# 费用-左上角蜡印
			if cost_lbl:
				cost_lbl.text = str(card.base_cost)
			
			# 名称条
			if name_lbl:
				name_lbl.text = card.card_name
			
			# 描述区：字段 | 效果数
			if desc_lbl:
				var desc_text = ""
				if card.fields.size() > 0:
					desc_text += "|".join(card.fields)
				if card.effects.size() > 0:
					if desc_text != "":
						desc_text += "\n"
					desc_text += str(card.effects.size()) + "效果"
				desc_lbl.text = desc_text
			
			# 攻击-左下角
			if atk_lbl:
				atk_lbl.text = str(card.current_atk)
			
			# 生命-右下角
			if hp_lbl:
				hp_lbl.text = str(card.current_hp)
			
			btn.disabled = false
			
			# 卡面底图 + 功能高亮描边（可召唤绿框 / 费用不足置灰）
			var can_summon_now: bool = _battle_manager.current_phase == BattleManager.Phase.MAIN and _battle_manager.is_player_turn()
			if can_summon_now and card.base_cost <= self_p.energy:
				_apply_all_states(btn, _make_card_face_style())
				_set_card_highlight(btn, Color(0.13, 0.75, 0.25, 0.95))
			elif can_summon_now:
				_apply_all_states(btn, _make_card_face_style(Color(0.55, 0.53, 0.60)))
				_clear_card_highlight(btn)
			else:
				_apply_all_states(btn, _make_card_face_style())
				_clear_card_highlight(btn)
		else:
			# 无手牌，隐藏/清空子Label
			for l in [elem_lbl, cost_lbl, name_lbl, desc_lbl, atk_lbl, hp_lbl]:
				if l:
					l.text = ""
			btn.disabled = true
			_apply_all_states(btn, _make_card_face_style(Color(0.35, 0.32, 0.40, 0.5)))
			_clear_card_highlight(btn)


# ===== 刷新场地UI（通过子Label布局，同手牌卡面） =====
func _refresh_field_ui() -> void:
	if _battle_manager == null:
		return
	var self_p = _battle_manager.player_self
	var enemy_p = _battle_manager.player_opponent
	
	# 己方场地
	for i in range(_player_slots.size()):
		var btn = _player_slots[i] as Button
		if btn == null:
			continue
		var elem_lbl = btn.get_node_or_null("ElemLabel") as Label
		var cost_lbl = btn.get_node_or_null("CostLabel") as Label
		var name_lbl = btn.get_node_or_null("NameLabel") as Label
		var desc_lbl = btn.get_node_or_null("DescLabel") as Label
		var atk_lbl = btn.get_node_or_null("AtkLabel") as Label
		var hp_lbl = btn.get_node_or_null("HpLabel") as Label
		
		var card = self_p.field[i] if i < self_p.field.size() else null
		if card != null:
			# 卡牌存在，显示信息
			# 如果之前是空位现在有卡，恢复按钮状态
			btn.disabled = false
			btn.scale = Vector2(1.0, 1.0)
			btn.modulate = Color(1.0, 1.0, 1.0, 1.0)
			# 元素（右上角，当前图标已清空，保留分区）
			if elem_lbl:
				elem_lbl.text = ""
			# 费用（左上角蜡印）
			if cost_lbl: cost_lbl.text = str(card.base_cost)
			# 名称条
			if name_lbl: name_lbl.text = card.card_name
			# 描述区（字段 | 效果数）
			if desc_lbl:
				var dt = ""
				if card.fields.size() > 0:
					dt += "|".join(card.fields)
				if card.effects.size() > 0:
					if dt != "":
						dt += "\n"
					dt += str(card.effects.size()) + "效果"
				desc_lbl.text = dt
			# 攻击（左下角）
			if atk_lbl: atk_lbl.text = str(card.current_atk)
			# 生命（右下角）
			if hp_lbl: hp_lbl.text = str(card.current_hp)
			
			# 护盾遮罩 + 护盾数值
			var shield_overlay = btn.get_node_or_null("ShieldOverlay") as ColorRect
			var shield_lbl = btn.get_node_or_null("ShieldLabel") as Label
			if card.shield_points > 0:
				if shield_overlay: shield_overlay.visible = true
				if shield_lbl:
					shield_lbl.visible = true
					shield_lbl.text = "" + str(card.shield_points)
			else:
				if shield_overlay: shield_overlay.visible = false
				if shield_lbl: shield_lbl.visible = false
			
			# 数值变化检测 → 浮动数字特效 + 卡牌动画
			if i < _prev_player_atk.size():
				var old_atk = _prev_player_atk[i]
				var diff_atk = card.current_atk - old_atk
				if diff_atk != 0:
					_show_float_number(btn, diff_atk, Color("#e74c3c") if diff_atk < 0 else Color("#f9d371"))
					if diff_atk < 0:
						_play_hit_animation(btn)
					else:
						_play_buff_animation(btn)
				var old_hp = _prev_player_hp[i]
				var diff_hp = card.current_hp - old_hp
				if diff_hp != 0:
					_show_float_number(btn, diff_hp, Color("#e74c3c") if diff_hp < 0 else Color("#2ecc71"))
					if diff_hp < 0:
						_play_hit_animation(btn)
					else:
						_play_buff_animation(btn)
			# 更新旧值
			while i >= _prev_player_atk.size():
				_prev_player_atk.append(0)
				_prev_player_hp.append(0)
			_prev_player_atk[i] = card.current_atk
			_prev_player_hp[i] = card.current_hp
			
			# 攻击选择模式高亮
			_apply_all_states(btn, _make_card_face_style())
			_clear_card_highlight(btn)
			if not (_attack_target_mode and _selected_attacker_slot >= 0) \
					and _battle_manager.current_phase == BattleManager.Phase.BATTLE and _battle_manager.is_player_turn():
				if card.can_attack():
					# 可攻击：金色描边
					_set_card_highlight(btn, Color(0.98, 0.80, 0.20, 0.95))
		else:
			# 卡牌离场：检测是否刚离场，先播放破坏动画
			var was_occupied = false
			if i < _prev_player_atk.size() and (_prev_player_atk[i] != 0 or _prev_player_hp[i] != 0):
				was_occupied = true
			
			if was_occupied:
				# 播放破坏动画（延迟清空）
				_play_destroy_animation(btn, 0.5)
				# 旧值在动画结束后才清空，防止重复触发
				# 但标记为即将离场，下次刷新时不会再触发
			else:
				# 已经是空位，直接清空
				for l in [elem_lbl, cost_lbl, name_lbl, desc_lbl, atk_lbl, hp_lbl]:
					if l:
						l.text = ""
				var shield_overlay = btn.get_node_or_null("ShieldOverlay") as ColorRect
				var shield_lbl = btn.get_node_or_null("ShieldLabel") as Label
				if shield_overlay: shield_overlay.visible = false
				if shield_lbl: shield_lbl.visible = false
				btn.disabled = true
				_apply_all_states(btn, _make_slot_recess_style())
				_clear_card_highlight(btn)
			
			# 清空旧值（卡牌离场）
			if i < _prev_player_atk.size():
				_prev_player_atk[i] = 0
				_prev_player_hp[i] = 0
	
	# 敌方场地
	for i in range(_enemy_slots.size()):
		var btn = _enemy_slots[i] as Button
		if btn == null:
			continue
		var elem_lbl = btn.get_node_or_null("ElemLabel") as Label
		var cost_lbl = btn.get_node_or_null("CostLabel") as Label
		var name_lbl = btn.get_node_or_null("NameLabel") as Label
		var desc_lbl = btn.get_node_or_null("DescLabel") as Label
		var atk_lbl = btn.get_node_or_null("AtkLabel") as Label
		var hp_lbl = btn.get_node_or_null("HpLabel") as Label
		
		var card = enemy_p.field[i] if i < enemy_p.field.size() else null
		if card != null:
			# 敌方卡牌显示完整信息
			if elem_lbl:
				elem_lbl.text = ""
			if cost_lbl: cost_lbl.text = str(card.base_cost)
			if name_lbl: name_lbl.text = card.card_name
			if desc_lbl:
				var dt = ""
				if card.fields.size() > 0:
					dt += "|".join(card.fields)
				if card.effects.size() > 0:
					if dt != "":
						dt += "\n"
					dt += str(card.effects.size()) + "效果"
				desc_lbl.text = dt
			if atk_lbl: atk_lbl.text = str(card.current_atk)
			if hp_lbl: hp_lbl.text = str(card.current_hp)
			
			# 护盾遮罩 + 护盾数值（敌方）
			var shield_overlay = btn.get_node_or_null("ShieldOverlay") as ColorRect
			var shield_lbl = btn.get_node_or_null("ShieldLabel") as Label
			if card.shield_points > 0:
				if shield_overlay: shield_overlay.visible = true
				if shield_lbl:
					shield_lbl.visible = true
					shield_lbl.text = "" + str(card.shield_points)
			else:
				if shield_overlay: shield_overlay.visible = false
				if shield_lbl: shield_lbl.visible = false
			
			# 数值变化检测 → 浮动数字特效 + 卡牌动画（敌方）
			if i < _prev_enemy_atk.size():
				var old_atk = _prev_enemy_atk[i]
				var diff_atk = card.current_atk - old_atk
				if diff_atk != 0:
					_show_float_number(btn, diff_atk, Color("#e74c3c") if diff_atk < 0 else Color("#f9d371"))
					if diff_atk < 0:
						_play_hit_animation(btn)
					else:
						_play_buff_animation(btn)
				var old_hp = _prev_enemy_hp[i]
				var diff_hp = card.current_hp - old_hp
				if diff_hp != 0:
					_show_float_number(btn, diff_hp, Color("#e74c3c") if diff_hp < 0 else Color("#2ecc71"))
					if diff_hp < 0:
						_play_hit_animation(btn)
					else:
						_play_buff_animation(btn)
			while i >= _prev_enemy_atk.size():
				_prev_enemy_atk.append(0)
				_prev_enemy_hp.append(0)
			_prev_enemy_atk[i] = card.current_atk
			_prev_enemy_hp[i] = card.current_hp
			
			# 攻击目标模式高亮
			_apply_all_states(btn, _make_card_face_style())
			_clear_card_highlight(btn)
			if _attack_target_mode and _selected_attacker_slot >= 0:
				# 可选目标：红色描边
				_set_card_highlight(btn, Color(0.91, 0.30, 0.24, 0.95))
		else:
			# 卡牌离场：检测是否刚离场，先播放破坏动画（敌方）
			var was_occupied = false
			if i < _prev_enemy_atk.size() and (_prev_enemy_atk[i] != 0 or _prev_enemy_hp[i] != 0):
				was_occupied = true
			
			if was_occupied:
				_play_destroy_animation(btn, 0.5)
			else:
				for l in [elem_lbl, cost_lbl, name_lbl, desc_lbl, atk_lbl, hp_lbl]:
					if l:
						l.text = ""
				var shield_overlay = btn.get_node_or_null("ShieldOverlay") as ColorRect
				var shield_lbl = btn.get_node_or_null("ShieldLabel") as Label
				if shield_overlay: shield_overlay.visible = false
				if shield_lbl: shield_lbl.visible = false
				btn.disabled = true
				_apply_all_states(btn, _make_slot_recess_style())
				_clear_card_highlight(btn)
			# 清空旧值（敌方卡牌离场）
			if i < _prev_enemy_atk.size():
				_prev_enemy_atk[i] = 0
				_prev_enemy_hp[i] = 0


# ===== 更新阶段UI =====
func _update_phase_ui() -> void:
	if _battle_manager == null:
		return
	var phase_name = _battle_manager.get_phase_name()
	
	# 左侧：当前阶段文字
	if _phase_label:
		if _battle_manager.is_player_turn():
			_phase_label.text = "" + phase_name
		else:
			_phase_label.text = "⏳ 敌方回合 - " + phase_name
	
	# 右侧：下一阶段按钮
	if _end_btn:
		if _battle_manager.is_player_turn():
			if _battle_manager.current_phase == BattleManager.Phase.MAIN:
				_end_btn.text = "进入战斗阶段"
				_end_btn.disabled = false
			elif _battle_manager.current_phase == BattleManager.Phase.BATTLE:
				_end_btn.text = "⏭ 结束回合"
				_end_btn.disabled = false
			else:
				_end_btn.disabled = true
				_end_btn.text = "⏳ 等待..."
		else:
			_end_btn.disabled = true
			_end_btn.text = "⏳ 等待敌方..."


# ===== 信号回调 =====
func _on_phase_changed(phase: int, player_index: int) -> void:
	print("[UI] 阶段变化: ", _battle_manager.get_phase_name() if _battle_manager else "?")
	_update_phase_ui()
	_refresh_hand_ui()
	_refresh_field_ui()

## 弃牌请求信号处理（由BattleManager的discard_requested信号触发）
func _on_discard_requested(count: int, callback_id: int, reason: String) -> void:
	# ★ 弹窗已存在时，请求入队等待（不丢弃！），当前弹窗结束后依次弹出
	if _discard_mode:
		print("[UI] 弃牌弹窗忙，请求入队: 回调ID=", callback_id, " 需弃", count, "张")
		_discard_request_queue.append({"count": count, "callback_id": callback_id, "reason": reason})
		return
	print("[UI] 收到弃牌请求: ", count, "张, 原因: ", reason)
	_discard_callback_id = callback_id
	_discard_need = count
	_show_discard_ui()
## ★ 弹出队列中下一个弃牌弹窗（由弃牌动画完成后调用）
func _process_next_discard_request() -> void:
	if _discard_request_queue.is_empty():
		return
	var req = _discard_request_queue.pop_front()
	print("[UI] 处理队列中的弃牌请求: 回调ID=", req.callback_id, " 需弃", req.count, "张")
	_discard_callback_id = req.callback_id
	_discard_need = req.count
	_show_discard_ui()

## 弃牌动画请求：数据已弃，播放飞入墓地特效，播完通知BattleManager
func _on_discard_animation_requested(callback_id: int, is_player_side: bool, discard_indices: Array) -> void:
	print("[UI] 播放弃牌飞入墓地动画: 回调ID=", callback_id, " 己方=", is_player_side, " 弃", discard_indices.size(), "张")
	_play_discard_animation(callback_id, is_player_side, discard_indices)
func _on_turn_changed(turn_count: int) -> void:
	print("[UI] 回合变化: 第", turn_count, "回合")
	_update_phase_ui()

func _on_battle_state_changed(state: int) -> void:
	var state_names = {0: "进行中", 1: "胜利！", 2: "败北...", 3: "平局"}
	var sname = state_names.get(state, "未知")
	print("[UI]  战斗状态: ", sname)
	if _phase_label:
		_phase_label.text = "" + sname
	
	# 胜利时：触发辅材掉落
	if state == 1:
		var boss_extra: Array = []      # BOSS 首通金币等额外展示条目（已提前入账）
		var boss_bonus := false         # BOSS 掉落加成（素材 3-5 件）
		# 教学战胜利 → 推进教程，回主界面找老陈（与 3D 端 BattleScene3D 一致）
		if Global.is_tutorial_battle:
			_exit_to_main = true
			print("[战斗]  教学战胜利！推进教程")
			TutorialManager.advance()
			# 教学战保底掉落：制作第一张卡所需的最低级卡基+卡墨素材
			var craft_drops = _give_tutorial_craft_materials()
			# 直接显示胜利结算（含保底素材 + 常规掉落）
			_handle_victory_rewards(craft_drops)
			return
		# BOSS战胜利 → 标记地图通关，结束后回主界面
		if Global.current_is_boss and Global.current_map_id != "":
			# 裂隙局（GDD §7.3.3）：BOSS 击杀 → 回裂隙图走 EXIT 撤离领首通奖励，不直接结束
			if Global.rift_active:
				Global.rift_boss_killed = true
				Global.current_is_boss = false
				_exit_to_main = false
				print("[裂隙] BOSS 击杀！可前往撤离点结算（首通奖励待领）")
			else:
				var first_clear := not PlayerManager.is_map_cleared(Global.current_map_id)
				PlayerManager.set_map_cleared(Global.current_map_id)
				Global.current_is_boss = false
				_exit_to_main = true
				print("[战斗]  BOSS战胜利！地图通关：", Global.current_map_id)
				# 首通金币 = 100 × 区域序号（仅首次通关，[PLACEHOLDER] L4 校准）
				if first_clear:
					var amt := int(BOSS_FIRST_CLEAR_GOLD.get(Global.current_map_id, 0))
					if amt > 0:
						PlayerManager.set_gold(PlayerManager.get_gold() + amt)
						boss_extra.append({"material_id": "GOLD", "name": "首通金币", "rarity": "奖励", "amount": amt})
						print("[战斗]  BOSS 首通奖励：金币 +", amt)
				boss_bonus = true
				# 检查纹路解锁状态
				var new_unlocks = CircuitManager.check_and_apply_unlocks()
				if new_unlocks.size() > 0:
					print("[战斗] 解锁了 ", new_unlocks.size(), " 个纹路组件")
		else:
			# ★ 普通战斗胜利 → 回地图内继续探索
			_exit_to_main = false
		_handle_victory_rewards(boss_extra, boss_bonus)
	# 败北/平局时：显示退出按钮，回主界面
	elif state == 2 or state == 3:
		_exit_to_main = true
		# 裂隙局（GDD §7.3.3）：全灭 → 素材折损 50% 携出（不清零），本局结束
		if Global.rift_active:
			var r = Global.rift_settle_wipe()
			print("[裂隙] 全灭结算：折损携带 %d 件，损失 %d 件" % [r["kept"], r["lost"]])
			if _phase_label:
				_phase_label.text = "素材折损 %d 件，剩余 %d 件已携出" % [r["lost"], r["kept"]]
		_show_battle_exit_btn()


# ============================
#  胜利奖励：辅材掉落
# ============================
func _handle_victory_rewards(extra_drops: Array = [], boss_bonus: bool = false) -> void:
	var enemy_data = Global.current_enemy_data
	if enemy_data.is_empty():
		_show_battle_exit_btn()
		return
	
	# 获取地形公共掉落 = 该层采集素材
	var terrain = Global.current_battle_terrain
	var map_id = Global.current_map_id
	var common_drops := []
	if map_id != "" and terrain != "":
		common_drops = Global.get_gather_materials(map_id, terrain)
	
	# 获取卡兽专属掉落
	var aux_drops = enemy_data.get("aux_drops", [])
	
	# 按概率判定掉落
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	var gained_aux := []
	
	# 合并公共掉落池和专属掉落池
	var all_drops := []
	
	# 1. 公共掉落（采集素材）
	for drop in common_drops:
		all_drops.append({
			"type": "material",
			"id": drop.get("material_id", ""),
			"name": drop.get("name", ""),
			"rarity": drop.get("rarity", "普通"),
			"min": drop.get("min", 1),
			"max": drop.get("max", 1),
		})
	
	# 2. 专属掉落（辅材）
	for drop in aux_drops:
		var aux_id = drop.get("id", "")
		if aux_id == "":
			continue
		var aux_data = Global.get_aux_by_id(aux_id)
		if not aux_data.is_empty():
			all_drops.append({
				"type": "aux",
				"id": aux_id,
				"name": aux_data.get("name", aux_id),
				"rarity": aux_data.get("rarity", "普通"),
				"min": 1,
				"max": 1,
			})
	
	# 从合并池中随机掉落（按概率判定；BOSS 加成 3~5 件，普通 1~3，保底至少1个）
	if all_drops.size() > 0:
		var drop_count = rng.randi_range(3, 5) if boss_bonus else rng.randi_range(1, 3)
		
		# 按概率判定每个素材是否掉落
		var passed := []
		for item in all_drops:
			# 如果是原公共掉落素材，获取其概率
			var prob = 0.5  # 默认概率
			# 在 common_drops 中找对应素材的概率
			for cd in common_drops:
				if cd.get("material_id", "") == item["id"]:
					prob = cd.get("prob", 0.5)
					break
			# 在 aux_drops 中找对应辅材的概率
			if prob == 0.5:
				for ad in aux_drops:
					if ad.get("id", "") == item["id"]:
						prob = ad.get("prob", 0.5)
						break
			if rng.randf() < prob:
				passed.append(item)
		
		# 如果通过的素材太多，随机选drop_count个
		if passed.size() > drop_count:
			passed.shuffle()
			passed.resize(drop_count)
		# 如果通过的素材太少（甚至0个），保底
		elif passed.size() == 0:
			# 从全部可用池中按概率权重选一个
			var weights := []
			var total_weight := 0.0
			for item in all_drops:
				var w = 0.5
				for cd in common_drops:
					if cd.get("material_id", "") == item["id"]:
						w = cd.get("prob", 0.5)
						break
				if w == 0.5:
					for ad in aux_drops:
						if ad.get("id", "") == item["id"]:
							w = ad.get("prob", 0.5)
							break
				weights.append(w)
				total_weight += w
			var r = rng.randf() * total_weight
			var cum := 0.0
			for idx in range(all_drops.size()):
				cum += weights[idx]
				if r <= cum:
					passed.append(all_drops[idx])
					break
		
		# 发放掉落
		for item in passed:
			var amount = 1
			if item.get("min", 1) != item.get("max", 1):
				amount = rng.randi_range(item["min"], item["max"])
			if item["type"] == "material":
				WarehouseManager.add_material(item["id"], amount)
			else:
				WarehouseManager.add_aux(item["id"], amount)
			gained_aux.append({
				"material_id": item["id"],
				"name": item["name"],
				"rarity": item["rarity"],
				"amount": amount,
			})
			print("[战斗] 掉落: ", item["name"], " x", amount)
	
		# 合并保底掉落（如教学战卡基/卡墨素材，已提前入库）
		for drop in extra_drops:
			gained_aux.append({
				"material_id": drop.get("material_id", ""),
				"name": drop.get("name", ""),
				"rarity": drop.get("rarity", "普通"),
				"amount": drop.get("amount", 1),
			})


func _give_tutorial_craft_materials() -> Array:
	var drops := [
		{"id": "F01", "name": "白麻纤维", "rarity": "普通", "cat": "卡基"},
		{"id": "M01", "name": "石灰矿粉", "rarity": "普通", "cat": "卡基"},
		{"id": "R01", "name": "普通松脂", "rarity": "普通", "cat": "卡基"},
		{"id": "E01", "name": "清水", "rarity": "普通", "cat": "卡墨"},
		{"id": "P01", "name": "炭黑", "rarity": "普通", "cat": "卡墨"},
		{"id": "B01", "name": "骨胶", "rarity": "普通", "cat": "卡墨"},
	]
	var gained := []
	for d in drops:
		WarehouseManager.add_material(d["id"], 2)
		print("[战斗] 教学战保底掉落: [", d["cat"], "] ", d["name"], " x2")
		gained.append({
			"material_id": d["id"],
			"name": d["name"],
			"rarity": d["rarity"],
			"amount": 2,
		})
	print("[战斗] 教学战保底素材发放完毕（6种×2）")
	return gained


func _show_battle_reward_popup(gained_aux: Array) -> void:
	# 遮罩
	var overlay = ColorRect.new()
	overlay.name = "BattleRewardOverlay"
	overlay.color = Color(0.0, 0.0, 0.0, 0.65)
	overlay.anchor_left = 0.0; overlay.anchor_top = 0.0
	overlay.anchor_right = 1.0; overlay.anchor_bottom = 1.0
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.gui_input.connect(_on_reward_overlay_clicked.bind(overlay))
	add_child(overlay)
	
	# 弹窗面板
	var panel = Panel.new()
	panel.name = "RewardPanel"
	var ps = StyleBoxFlat.new()
	ps.bg_color = Color(0.12, 0.10, 0.18)
	ps.corner_radius_top_left = 20; ps.corner_radius_top_right = 20
	ps.corner_radius_bottom_left = 20; ps.corner_radius_bottom_right = 20
	ps.border_width_left = 2; ps.border_width_right = 2
	ps.border_width_top = 2; ps.border_width_bottom = 2
	ps.border_color = Color(0.5, 0.4, 0.7)
	panel.add_theme_stylebox_override("panel", ps)
	panel.anchor_left = 0.0; panel.anchor_top = 0.0
	panel.anchor_right = 1.0; panel.anchor_bottom = 1.0
	panel.offset_left = Global.pw(0.08); panel.offset_top = Global.ph(0.22)
	panel.offset_right = Global.pw(-0.08); panel.offset_bottom = -Global.ph(0.22)
	overlay.add_child(panel)
	
	# 标题
	var title = Label.new()
	title.text = "战斗胜利！"
	title.add_theme_font_size_override("font_size", 55)
	title.add_theme_color_override("font_color", Color("#f9d371"))
	title.add_theme_color_override("font_shadow_color", Color("#000000"))
	title.add_theme_constant_override("shadow_offset_x", 2)
	title.add_theme_constant_override("shadow_offset_y", 2)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.anchor_left = 0.0; title.anchor_top = 0.0
	title.anchor_right = 1.0; title.anchor_bottom = 0.0
	title.offset_left = 0; title.offset_top = Global.ph(0.02)
	title.offset_right = 0; title.offset_bottom = Global.ph(0.08)
	panel.add_child(title)
	
	# 分隔线
	var line = ColorRect.new()
	line.color = Color(1.0, 1.0, 1.0, 0.15)
	line.anchor_left = 0.0; line.anchor_top = 0.0
	line.anchor_right = 1.0; line.anchor_bottom = 0.0
	line.offset_left = Global.pw(0.05); line.offset_top = Global.ph(0.085)
	line.offset_right = Global.pw(-0.05); line.offset_bottom = Global.ph(0.09)
	panel.add_child(line)
	
	if gained_aux.size() == 0:
		var empty = Label.new()
		empty.text = "本次战斗没有获得额外掉落物"
		empty.add_theme_font_size_override("font_size", 42)
		empty.add_theme_color_override("font_color", Color("#5a5a6e"))
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty.anchor_left = 0.0; empty.anchor_top = 0.0
		empty.anchor_right = 1.0; empty.anchor_bottom = 0.0
		empty.offset_left = 0; empty.offset_top = Global.ph(0.12)
		empty.offset_right = 0; empty.offset_bottom = Global.ph(0.35)
		panel.add_child(empty)
	else:
		# 掉落物副标题
		var sub = Label.new()
		sub.text = "掉落辅材："
		sub.add_theme_font_size_override("font_size", 44)
		sub.add_theme_color_override("font_color", Color("#e8d5b7"))
		sub.anchor_left = 0.0; sub.anchor_top = 0.0
		sub.anchor_right = 1.0; sub.anchor_bottom = 0.0
		sub.offset_left = Global.pw(0.06); sub.offset_top = Global.ph(0.10)
		sub.offset_right = 0; sub.offset_bottom = Global.ph(0.15)
		panel.add_child(sub)
		
		# 辅材列表（可滚动）
		var scroll = ScrollContainer.new()
		scroll.name = "RewardScroll"
		scroll.anchor_left = 0.0; scroll.anchor_top = 0.0
		scroll.anchor_right = 1.0; scroll.anchor_bottom = 1.0
		scroll.offset_left = Global.pw(0.03); scroll.offset_top = Global.ph(0.15)
		scroll.offset_right = Global.pw(-0.03); scroll.offset_bottom = -Global.ph(0.15)
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
		panel.add_child(scroll)
		
		var vbox = VBoxContainer.new()
		vbox.name = "RewardVBox"
		vbox.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
		vbox.custom_minimum_size = Vector2(Global.pw(0.70), 0)
		scroll.add_child(vbox)
		
		var row_idx := 0
		for aux in gained_aux:
			var rarity_color = Color("#e8d5b7")
			match aux.get("rarity", "普通"):
				"传说": rarity_color = Color("#f9d371")
				"史诗": rarity_color = Color("#c084fc")
				"稀有": rarity_color = Color("#60a5fa")
			
			var row = Panel.new()
			var rs = StyleBoxFlat.new()
			rs.bg_color = Color(0.17, 0.15, 0.22) if row_idx % 2 == 0 else Color(0.13, 0.11, 0.17)
			rs.corner_radius_top_left = 8; rs.corner_radius_top_right = 8
			rs.corner_radius_bottom_left = 8; rs.corner_radius_bottom_right = 8
			row.add_theme_stylebox_override("panel", rs)
			row.custom_minimum_size = Vector2(0, Global.ph(0.065))
			row.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
			vbox.add_child(row)
			
			var hbox = HBoxContainer.new()
			hbox.anchor_left = 0.0; hbox.anchor_top = 0.0
			hbox.anchor_right = 1.0; hbox.anchor_bottom = 1.0
			hbox.offset_left = Global.pw(0.03)
			hbox.mouse_filter = MOUSE_FILTER_IGNORE
			row.add_child(hbox)
			
			var name_label = Label.new()
			name_label.text = aux.get("name", "未知")
			name_label.add_theme_font_size_override("font_size", 42)
			name_label.add_theme_color_override("font_color", rarity_color)
			name_label.size_flags_horizontal = Control.SIZE_EXPAND
			hbox.add_child(name_label)
			
			var count_label = Label.new()
			count_label.text = "x1"
			count_label.add_theme_font_size_override("font_size", 42)
			count_label.add_theme_color_override("font_color", rarity_color)
			count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			count_label.custom_minimum_size = Vector2(Global.pw(0.1), 0)
			hbox.add_child(count_label)
			
			row_idx += 1
		
		# 底部留白
		var spacer = Control.new()
		spacer.custom_minimum_size = Vector2(0, Global.ph(0.02))
		vbox.add_child(spacer)
	
	# 确认按钮（底部居中，小巧）
	var confirm_btn = Button.new()
	confirm_btn.text = "返回地图"
	confirm_btn.add_theme_font_size_override("font_size", 45)
	var cs = StyleBoxFlat.new()
	cs.bg_color = Color(0.2, 0.15, 0.3)
	cs.border_width_left = 2; cs.border_width_right = 2
	cs.border_width_top = 2; cs.border_width_bottom = 2
	cs.border_color = Color(0.5, 0.4, 0.7)
	cs.corner_radius_top_left = 12; cs.corner_radius_top_right = 12
	cs.corner_radius_bottom_left = 12; cs.corner_radius_bottom_right = 12
	cs.content_margin_left = 30; cs.content_margin_right = 30
	confirm_btn.add_theme_stylebox_override("normal", cs)
	confirm_btn.add_theme_color_override("font_color", Color("#e8d5b7"))
	confirm_btn.anchor_left = 0.0; confirm_btn.anchor_top = 1.0
	confirm_btn.anchor_right = 1.0; confirm_btn.anchor_bottom = 1.0
	confirm_btn.offset_left = Global.pw(0.25); confirm_btn.offset_top = -Global.ph(0.08)
	confirm_btn.offset_right = Global.pw(-0.25); confirm_btn.offset_bottom = -Global.ph(0.02)
	confirm_btn.pressed.connect(_on_reward_confirm.bind(overlay))
	panel.add_child(confirm_btn)


func _on_reward_confirm(overlay: ColorRect) -> void:
	overlay.queue_free()
	_go_back_to_map()


func _on_reward_overlay_clicked(event: InputEvent, overlay: ColorRect) -> void:
	if event is InputEventScreenTouch and not event.pressed:
		_on_reward_confirm(overlay)


func _show_battle_exit_btn() -> void:
	# 显示退出弹窗（败北/平局时用）
	var overlay = ColorRect.new()
	overlay.name = "BattleExitOverlay"
	overlay.color = Color(0.0, 0.0, 0.0, 0.65)
	overlay.anchor_left = 0.0; overlay.anchor_top = 0.0
	overlay.anchor_right = 1.0; overlay.anchor_bottom = 1.0
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	
	var panel = Panel.new()
	panel.name = "ExitPanel"
	var ps = StyleBoxFlat.new()
	ps.bg_color = Color(0.12, 0.10, 0.18)
	ps.corner_radius_top_left = 20; ps.corner_radius_top_right = 20
	ps.corner_radius_bottom_left = 20; ps.corner_radius_bottom_right = 20
	ps.border_width_left = 2; ps.border_width_right = 2
	ps.border_width_top = 2; ps.border_width_bottom = 2
	ps.border_color = Color(0.5, 0.4, 0.7)
	panel.add_theme_stylebox_override("panel", ps)
	panel.anchor_left = 0.0; panel.anchor_top = 0.0
	panel.anchor_right = 1.0; panel.anchor_bottom = 1.0
	panel.offset_left = Global.pw(0.15); panel.offset_top = Global.ph(0.35)
	panel.offset_right = Global.pw(-0.15); panel.offset_bottom = -Global.ph(0.35)
	overlay.add_child(panel)
	
	var title = Label.new()
	title.text = "战斗结束"
	title.add_theme_font_size_override("font_size", 55)
	title.add_theme_color_override("font_color", Color("#e74c3c"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.anchor_left = 0.0; title.anchor_top = 0.0
	title.anchor_right = 1.0; title.anchor_bottom = 1.0
	title.offset_left = 0; title.offset_top = 0
	title.offset_right = 0; title.offset_bottom = -Global.ph(0.08)
	panel.add_child(title)
	
	var exit_btn = Button.new()
	exit_btn.text = "返回地图"
	exit_btn.add_theme_font_size_override("font_size", 45)
	var cs = StyleBoxFlat.new()
	cs.bg_color = Color(0.2, 0.15, 0.3)
	cs.border_width_left = 2; cs.border_width_right = 2
	cs.border_width_top = 2; cs.border_width_bottom = 2
	cs.border_color = Color(0.5, 0.4, 0.7)
	cs.corner_radius_top_left = 12; cs.corner_radius_top_right = 12
	cs.corner_radius_bottom_left = 12; cs.corner_radius_bottom_right = 12
	cs.content_margin_left = 30; cs.content_margin_right = 30
	exit_btn.add_theme_stylebox_override("normal", cs)
	exit_btn.add_theme_color_override("font_color", Color("#e8d5b7"))
	exit_btn.anchor_left = 0.0; exit_btn.anchor_top = 1.0
	exit_btn.anchor_right = 1.0; exit_btn.anchor_bottom = 1.0
	exit_btn.offset_left = Global.pw(0.25); exit_btn.offset_top = -Global.ph(0.1)
	exit_btn.offset_right = Global.pw(-0.25); exit_btn.offset_bottom = -Global.ph(0.03)
	exit_btn.pressed.connect(_on_reward_confirm.bind(overlay))
	panel.add_child(exit_btn)


## 退出按钮回调：显示确认弹窗
func _on_battle_exit_btn() -> void:
	var overlay = ColorRect.new()
	overlay.name = "BattleExitConfirmOverlay"
	overlay.color = Color(0.0, 0.0, 0.0, 0.7)
	overlay.anchor_left = 0.0; overlay.anchor_top = 0.0
	overlay.anchor_right = 1.0; overlay.anchor_bottom = 1.0
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	
	var panel = Panel.new()
	panel.name = "ExitConfirmPanel"
	var ps = StyleBoxFlat.new()
	ps.bg_color = Color(0.12, 0.10, 0.18)
	ps.corner_radius_top_left = 20; ps.corner_radius_top_right = 20
	ps.corner_radius_bottom_left = 20; ps.corner_radius_bottom_right = 20
	ps.border_width_left = 2; ps.border_width_right = 2
	ps.border_width_top = 2; ps.border_width_bottom = 2
	ps.border_color = Color(0.6, 0.2, 0.2)
	panel.add_theme_stylebox_override("panel", ps)
	panel.anchor_left = 0.0; panel.anchor_top = 0.0
	panel.anchor_right = 1.0; panel.anchor_bottom = 1.0
	panel.offset_left = Global.pw(0.15); panel.offset_top = Global.ph(0.35)
	panel.offset_right = Global.pw(-0.15); panel.offset_bottom = -Global.ph(0.35)
	overlay.add_child(panel)
	
	var title = Label.new()
	title.text = "退出战斗"
	title.add_theme_font_size_override("font_size", 50)
	title.add_theme_color_override("font_color", Color("#e74c3c"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.anchor_left = 0.0; title.anchor_top = 0.0
	title.anchor_right = 1.0; title.anchor_bottom = 0.5
	panel.add_child(title)
	
	var tip = Label.new()
	tip.text = "退出将返回主界面\n确定要退出吗？"
	tip.add_theme_font_size_override("font_size", 35)
	tip.add_theme_color_override("font_color", Color("#b0a0c0"))
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tip.anchor_left = 0.0; tip.anchor_top = 0.3
	tip.anchor_right = 1.0; tip.anchor_bottom = 0.7
	panel.add_child(tip)
	
	# 确认按钮
	var confirm_btn = Button.new()
	confirm_btn.text = "确认退出"
	confirm_btn.add_theme_font_size_override("font_size", 40)
	var cs = StyleBoxFlat.new()
	cs.bg_color = Color(0.2, 0.08, 0.08)
	cs.border_width_left = 2; cs.border_width_right = 2
	cs.border_width_top = 2; cs.border_width_bottom = 2
	cs.border_color = Color(0.6, 0.2, 0.2)
	cs.corner_radius_top_left = 12; cs.corner_radius_top_right = 12
	cs.corner_radius_bottom_left = 12; cs.corner_radius_bottom_right = 12
	cs.content_margin_left = 20; cs.content_margin_right = 20
	confirm_btn.add_theme_stylebox_override("normal", cs)
	confirm_btn.add_theme_color_override("font_color", Color("#e74c3c"))
	confirm_btn.anchor_left = 0.0; confirm_btn.anchor_top = 0.7
	confirm_btn.anchor_right = 0.5; confirm_btn.anchor_bottom = 1.0
	confirm_btn.offset_left = Global.pw(0.05); confirm_btn.offset_top = Global.ph(0.02)
	confirm_btn.offset_right = Global.pw(-0.02); confirm_btn.offset_bottom = -Global.ph(0.04)
	confirm_btn.pressed.connect(func():
		_exit_to_main = true
		overlay.queue_free()
		_go_back_to_map()
	)
	panel.add_child(confirm_btn)
	
	# 取消按钮
	var cancel_btn = Button.new()
	cancel_btn.text = "取消"
	cancel_btn.add_theme_font_size_override("font_size", 40)
	var cs2 = StyleBoxFlat.new()
	cs2.bg_color = Color(0.15, 0.12, 0.22)
	cs2.border_width_left = 2; cs2.border_width_right = 2
	cs2.border_width_top = 2; cs2.border_width_bottom = 2
	cs2.border_color = Color(0.5, 0.4, 0.7)
	cs2.corner_radius_top_left = 12; cs2.corner_radius_top_right = 12
	cs2.corner_radius_bottom_left = 12; cs2.corner_radius_bottom_right = 12
	cs2.content_margin_left = 20; cs2.content_margin_right = 20
	cancel_btn.add_theme_stylebox_override("normal", cs2)
	cancel_btn.add_theme_color_override("font_color", Color("#a0a0b0"))
	cancel_btn.anchor_left = 0.5; cancel_btn.anchor_top = 0.7
	cancel_btn.anchor_right = 1.0; cancel_btn.anchor_bottom = 1.0
	cancel_btn.offset_left = Global.pw(0.02); cancel_btn.offset_top = Global.ph(0.02)
	cancel_btn.offset_right = Global.pw(-0.05); cancel_btn.offset_bottom = -Global.ph(0.04)
	cancel_btn.pressed.connect(func():
		overlay.queue_free()
	)
	panel.add_child(cancel_btn)

## 返回主界面或地图内继续探索
func _go_back_to_map() -> void:
	# 退出横屏视角（竖屏模式下幂等，无副作用）
	Global.exit_landscape_canvas()
	# 清理战斗数据
	Global.current_enemy_data = {}
	Global.current_battle_terrain = ""

	# 教学战：无论胜负都回主界面找老陈（与 3D 端 BattleScene3D 一致）
	if Global.is_tutorial_battle:
		Global.is_tutorial_battle = false
		Global.change_scene("res://Main.tscn")
		return

	# 决斗场（地图ID为空）无论胜负都回选择地图界面
	if Global.current_map_id == "":
		Global.change_scene("res://Exploration.tscn")
		return
	
	if _exit_to_main:
		Global.change_scene("res://Main.tscn")
	else:
		Global.change_scene("res://MapNodeScene.tscn")

func _on_action_result(action_type: String, success: bool, data: Dictionary) -> void:
	if not success:
		print("[UI] 操作失败: ", action_type, " - ", data.get("reason", "未知"))
	else:
		print("[UI] 操作成功: ", action_type)

## 效果触发：显示飘字 + 闪烁
func _on_effect_triggered(action_type: String, value: int, is_player_side: bool, source_slot: int, desc: String) -> void:
	print("[飘字] 收到信号: action=", action_type, " value=", value, " is_player=", is_player_side, " slot=", source_slot, " desc=", desc)
	# 1. 飘字效果（在卡牌上方显示）
	var slots = _player_slots if is_player_side else _enemy_slots
	print("[飘字] slots.size=", slots.size(), " source_slot=", source_slot)
	if source_slot >= 0 and source_slot < slots.size():
		var slot_btn = slots[source_slot] as Button
		print("[飘字] slot_btn=", slot_btn, " valid=", (is_instance_valid(slot_btn) if slot_btn else false))
		if slot_btn and is_instance_valid(slot_btn):
			print("[飘字] slot_btn.global_pos=", slot_btn.global_position)
			# 闪烁效果
			_flash_slot(slot_btn)
			# 飘字
			_show_float_text(slot_btn, action_type, value, desc)
		else:
			print("[飘字] slot_btn无效，尝试在场景中心显示")
			_show_float_text_center(action_type, value, desc)
	else:
		print("[飘字] source_slot越界，在场景中心显示")
		_show_float_text_center(action_type, value, desc)

## 卡组检索弹窗请求
func _on_deck_search_requested(cards: Array, max_select: int, callback_id: int) -> void:
	_set_driver_busy(true)
	var popup = DeckSearchPopup.new()
	add_child(popup)
	var title = "卡组检索"
	if max_select == 1:
		title = "选择一张卡牌"
	else:
		title = "选择 " + str(max_select) + " 张卡牌"
	popup.show_search(cards, title, max_select, func(selected: Array):
		_battle_manager._on_deck_search_result(callback_id, selected)
		_set_driver_busy(false)
	)

# ===== 连锁系统 =====
## 请求玩家连锁响应（敌方回合触发效果时）
func _on_chain_response_requested(callback_id: int) -> void:
	_chain_callback_id = callback_id
	_chain_awaiting_response = true
	_set_driver_busy(true)
	_show_chain_prompt()
## 连锁构建完成
func _on_chain_built(chain_count: int) -> void:
	_chain_awaiting_response = false
	_hide_chain_prompt()
	print("[UI] 连锁构建完成，共", chain_count, "链，开始结算")
## 单个连锁链结算完成
func _on_chain_resolved(link_id: int) -> void:
	print("[UI] 连锁链 #", link_id, " 结算完成")

## 效果发动通知：在屏幕上方显示飘窗（自动消失）
func _on_card_effect_activated(card_name: String, effect_desc: String, action_type: String, target_id: String, value: int, target_card_name: String = "", source_slot: int = -1, is_player_side: bool = true, target_slot: int = -1, target_is_player: bool = true) -> void:
	# 暂停游戏（飘窗期间所有战斗暂停）
	get_tree().paused = true
	
	# 生成飘窗文字（多行格式）
	var target_text = ""
	match target_id:
		"T01": target_text = "自身"
		"T02": target_text = "敌方单体"
		"T03": target_text = "己方单体"
		"T04": target_text = "敌方全体"
		"T05": target_text = "己方全体"
		"T06": target_text = "全场"
		"T07": target_text = "敌方英雄"
		"T08": target_text = "己方英雄"
		_: target_text = ""
	
	# 第一行：卡牌名 → 发动效果
	var line1 = "【" + card_name + "】发动效果"
	# 第二行：效果描述
	var line2 = effect_desc
	# 第三行：目标信息
	var line3 = ""
	if target_text != "":
		if target_card_name != "" and target_card_name != card_name:
			# 有具体目标卡牌名：只显示"→ 目标卡牌名"
			line3 = "→ " + target_card_name
		else:
			# 没有具体目标卡牌名：显示"目标：xxx"
			line3 = "目标：" + target_text
			# 如果目标本身就是卡牌名（比如"自身"且有目标卡牌名），显示"→ 卡牌名"
			if target_card_name != "":
				line3 += " → " + target_card_name
	
	# 创建飘窗（加高，支持多行文字）
	var notification = ColorRect.new()
	notification.name = "EffectNotification"
	notification.color = Color(0.0, 0.0, 0.0, 0.8)
	notification.anchor_left = 0.0; notification.anchor_top = 0.0
	notification.anchor_right = 1.0; notification.anchor_bottom = 0.0
	notification.offset_left = Global.pw(0.04)
	notification.offset_right = Global.pw(-0.04)
	notification.offset_top = Global.ph(0.05)
	notification.offset_bottom = Global.ph(0.18)  # 加高到18%屏幕高度，容纳3行文字
	notification.z_index = 300
	notification.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(notification)
	
	# 画连接线：从发动卡牌到目标卡牌（精确信号，由BattleManager逐卡发射）
	var effect_lines: Array[Line2D] = []
	if source_slot >= 0:
		# 源卡牌位置
		var source_slots_arr = _player_slots if is_player_side else _enemy_slots
		var source_btn = source_slots_arr[source_slot] if source_slot < source_slots_arr.size() else null
		
		# 收集目标节点列表
		var target_nodes: Array[Node] = []
		if target_slot >= 0:
			# 单体效果：指向指定槽位
			var target_slots_arr = _player_slots if target_is_player else _enemy_slots
			var target_node = target_slots_arr[target_slot] if target_slot < target_slots_arr.size() else null
			if target_node: target_nodes.append(target_node)
		else:
			# 英雄目标
			var hp_name = "PlayerHP" if target_is_player else "EnemyHP"
			var hp_node = get_node_or_null(hp_name)
			if hp_node: target_nodes.append(hp_node)
		
		# 画线（从源到每个目标）
		if source_btn and is_instance_valid(source_btn):
			for tn in target_nodes:
				if is_instance_valid(tn):
					var line = _create_effect_line(source_btn, tn, action_type)
					if line:
						effect_lines.append(line)
	
	# 用VBoxContainer纵向排列多行文字
	var vbox = VBoxContainer.new()
	vbox.anchor_left = 0.0; vbox.anchor_top = 0.0
	vbox.anchor_right = 1.0; vbox.anchor_bottom = 1.0
	vbox.offset_left = Global.pw(0.02); vbox.offset_right = Global.pw(-0.02)
	vbox.offset_top = Global.ph(0.005); vbox.offset_bottom = Global.ph(-0.005)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	notification.add_child(vbox)
	
	# 第一行：卡牌名发动（金色大字）
	var lbl1 = Label.new()
	lbl1.text = line1
	lbl1.add_theme_font_size_override("font_size", 40)
	lbl1.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	lbl1.add_theme_constant_override("shadow_offset_x", 1)
	lbl1.add_theme_constant_override("shadow_offset_y", 1)
	lbl1.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	lbl1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl1.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl1.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl1.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
	vbox.add_child(lbl1)
	
	# 第二行：效果描述（白色）
	var lbl2 = Label.new()
	lbl2.text = line2
	lbl2.add_theme_font_size_override("font_size", 32)
	lbl2.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	lbl2.add_theme_constant_override("shadow_offset_x", 1)
	lbl2.add_theme_constant_override("shadow_offset_y", 1)
	lbl2.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.6))
	lbl2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl2.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl2.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
	vbox.add_child(lbl2)
	
	# 第三行：目标信息（淡金色）——简洁显示目标卡牌名
	if line3 != "":
		var lbl3 = Label.new()
		lbl3.text = line3
		lbl3.add_theme_font_size_override("font_size", 28)
		lbl3.add_theme_color_override("font_color", Color(0.9, 0.8, 0.6))
		lbl3.add_theme_constant_override("shadow_offset_x", 1)
		lbl3.add_theme_constant_override("shadow_offset_y", 1)
		lbl3.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.5))
		lbl3.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl3.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl3.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl3.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
		vbox.add_child(lbl3)
	
	# 如果有效果约束，加一行提示（淡红色小字）
	if target_card_name != "" and target_card_name != card_name:
		# 已经有目标卡牌名了，不需要额外行
		pass
	
	# 淡入淡出动画（忽略暂停，继续播放）
	notification.modulate = Color(1.0, 1.0, 1.0, 0.0)
	var tween = create_tween().set_parallel(false)
	tween.set_pause_mode(2)  # TWEEN_PAUSE_MODE_PROCESS = 2，忽略暂停继续播放
	tween.tween_property(notification, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.15)
	tween.tween_callback(func():
		# 停留后淡出
		var t2 = create_tween().set_parallel(false)
		t2.set_pause_mode(2)  # TWEEN_PAUSE_MODE_PROCESS
		t2.tween_interval(1.5)  # 多行停留时间稍长
		t2.tween_property(notification, "modulate", Color(1.0, 1.0, 1.0, 0.0), 0.3)
		t2.tween_callback(func():
			notification.queue_free()
			# 清理连接线
			for li in effect_lines:
				if li != null and is_instance_valid(li):
					li.queue_free()
			# 恢复游戏
			get_tree().paused = false
		)
	)

## 精确画线信号：群体效果每张卡单独发射
## 由 BattleManager 在 _execute_damage_action/_execute_heal_action 中逐卡发射
func _on_effect_line_fromto(from_slot: int, from_is_player: bool, to_slot: int, to_is_player: bool, action_type: String) -> void:
	var from_slots = _player_slots if from_is_player else _enemy_slots
	var to_slots = _player_slots if to_is_player else _enemy_slots
	
	if from_slot < 0 or from_slot >= from_slots.size(): return
	if to_slot < 0 or to_slot >= to_slots.size(): return
	
	var from_btn = from_slots[from_slot]
	var to_btn = to_slots[to_slot]
	
	if not is_instance_valid(from_btn) or not is_instance_valid(to_btn):
		return
	
	var line = _create_effect_line(from_btn, to_btn, action_type)
	if line:
		add_child(line)
		# 自动清理：1.5秒后淡出并删除
		var tween = create_tween().set_parallel(false)
		tween.set_pause_mode(2)
		tween.tween_interval(1.0)
		tween.tween_property(line, "modulate", Color(1, 1, 1, 0), 0.3)
		tween.tween_callback(func():
			if is_instance_valid(line):
				line.queue_free()
		)

## 元素加成/克制飘字动画
func _on_element_boost_triggered(boost_type: String, atk_elem: String, def_elem: String, from_value: int, to_value: int, is_player_side: bool, source_slot: int) -> void:
	# 确定飘字位置
	var slots = _player_slots if is_player_side else _enemy_slots
	var slot_btn = null
	if source_slot >= 0 and source_slot < slots.size():
		slot_btn = slots[source_slot]
	
	if not is_instance_valid(slot_btn):
		return
	
	# 生成飘字文本
	var text = ""
	var color = Color.WHITE
	var atk_emoji = Global.get_element_emoji(atk_elem)
	var def_emoji = Global.get_element_emoji(def_elem)
	
	if boost_type == "affinity":
		# 克制：💧克制🔥 1-2
		text = atk_emoji + "克制" + def_emoji + " " + str(from_value) + "-" + str(to_value)
		color = Color(1.0, 0.8, 0.2)  # 金色
	elif boost_type == "power":
		# 加成：🔥加成 1-2
		text = atk_emoji + "加成 " + str(from_value) + "-" + str(to_value)
		color = Color(0.3, 0.8, 1.0)  # 蓝色
	
	# 创建飘字Label
	var float_lbl = Label.new()
	float_lbl.text = text
	float_lbl.add_theme_font_size_override("font_size", 32)
	float_lbl.add_theme_color_override("font_color", color)
	float_lbl.add_theme_constant_override("shadow_offset_x", 2)
	float_lbl.add_theme_constant_override("shadow_offset_y", 2)
	float_lbl.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	float_lbl.z_index = 260
	# 定位在卡牌上方偏右（避免和效果飘字重叠）
	float_lbl.global_position = slot_btn.global_position - Vector2(0, slot_btn.size.y * 0.8)
	float_lbl.global_position.x += slot_btn.size.x * 0.3
	add_child(float_lbl)
	
	# 向上飘动并淡出
	var ft = create_tween().set_parallel(true)
	ft.set_pause_mode(2)
	ft.tween_property(float_lbl, "global_position", float_lbl.global_position - Vector2(0, 50), 0.8).set_ease(Tween.EASE_OUT)
	ft.tween_property(float_lbl, "modulate", Color(1.0, 1.0, 1.0, 0.0), 0.6).set_delay(0.3)
	ft.tween_callback(func(): 
		if is_instance_valid(float_lbl):
			float_lbl.queue_free()
	)
	# 轻微缩放闪烁
	float_lbl.scale = Vector2(0.5, 0.5)
	var st = create_tween().set_parallel(true)
	st.set_pause_mode(2)
	st.tween_property(float_lbl, "scale", Vector2(1.2, 1.2), 0.15)
	st.tween_property(float_lbl, "scale", Vector2(1.0, 1.0), 0.1).set_delay(0.15)
## 画效果连接线：从发动卡牌到目标卡牌
func _create_effect_line(from_node: Node, to_node: Node, action_type: String = "") -> Line2D:
	if not is_instance_valid(from_node) or not is_instance_valid(to_node):
		return null
	# 计算两点坐标（取按钮中心，相对于本场景）
	var from_ctrl = from_node as Control
	var to_ctrl = to_node as Control
	if not from_ctrl or not to_ctrl:
		return null
	# 根据效果类型选择颜色
	var line_color = Color(1.0, 0.85, 0.3, 0.8)  # 默认金色
	match action_type:
		"A01": line_color = Color(1.0, 0.2, 0.2, 0.8)    # 伤害→红色
		"A02": line_color = Color(0.2, 1.0, 0.4, 0.8)    # 恢复→绿色
		"A03": line_color = Color(1.0, 0.3, 0.0, 0.8)    # 破坏→橙红
		"A04": line_color = Color(0.6, 0.2, 1.0, 0.8)    # 除外→紫色
		"A06": line_color = Color(0.3, 0.8, 1.0, 0.8)    # 弹回→蓝色
		"A07": line_color = Color(0.3, 0.8, 1.0, 0.8)    # 弹回→蓝色
		"A09": line_color = Color(0.4, 0.8, 1.0, 0.8)    # 抽牌→天蓝
		"A15","A16","A17","A18": line_color = Color(1.0, 0.6, 0.0, 0.8)  # 特召→橙色
		"A19": line_color = Color(1.0, 0.6, 0.0, 0.8)    # 衍生物→橙色
		"A20","A21","A22","A23": line_color = Color(1.0, 0.9, 0.2, 0.8)  # 增减→亮金
		"A30": line_color = Color(1.0, 0.2, 0.6, 0.8)    # 无效→粉红
		_: line_color = Color(1.0, 0.85, 0.3, 0.8)       # 默认金色
	
	# 相对于父节点（self）的坐标
	var from_local = from_ctrl.position + from_ctrl.size * 0.5
	var to_local = to_ctrl.position + to_ctrl.size * 0.5
	
	var line = Line2D.new()
	line.points = PackedVector2Array([from_local, to_local])
	line.width = 3.0
	line.default_color = line_color
	line.antialiased = true
	line.z_index = 400  # 在飘窗和卡牌之间
	line.show_behind_parent = false
	add_child(line)
	# 动画：从源到目标逐渐生长
	var tween = create_tween()
	tween.set_pause_mode(2)
	var start_pt = from_local
	var end_pt = to_local
	# 先设终点为起点，再渐变到终点
	line.points = PackedVector2Array([start_pt, start_pt])
	tween.tween_method(func(t: float):
		line.points = PackedVector2Array([start_pt, start_pt.lerp(end_pt, t)])
	, 0.0, 1.0, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	return line
## 卡牌受伤动画：震动 + 红色闪烁
func _play_hit_animation(btn: Button) -> void:
	if not is_instance_valid(btn):
		return
	# 红色闪烁
	var flash = ColorRect.new()
	flash.size = btn.size
	flash.color = Color(1.0, 0.2, 0.2, 0.6)
	flash.z_index = 200
	flash.global_position = btn.global_position
	add_child(flash)
	var ft = create_tween().set_parallel(true)
	ft.set_pause_mode(2)
	ft.tween_property(flash, "modulate", Color(1.0, 0.2, 0.2, 0.0), 0.4)
	ft.tween_callback(func(): flash.queue_free())
	# 震动
	var orig_pos = btn.position
	var st = create_tween().set_parallel(true)
	st.set_pause_mode(2)
	st.tween_property(btn, "position", orig_pos + Vector2(8, 0), 0.05)
	st.tween_property(btn, "position", orig_pos - Vector2(8, 0), 0.05).set_delay(0.05)
	st.tween_property(btn, "position", orig_pos + Vector2(4, 0), 0.05).set_delay(0.1)
	st.tween_property(btn, "position", orig_pos, 0.05).set_delay(0.15)

## 卡牌增益动画：绿色闪烁
func _play_buff_animation(btn: Button) -> void:
	if not is_instance_valid(btn):
		return
	var flash = ColorRect.new()
	flash.size = btn.size
	flash.color = Color(0.2, 1.0, 0.2, 0.5)
	flash.z_index = 200
	flash.global_position = btn.global_position
	add_child(flash)
	var ft = create_tween()
	ft.set_pause_mode(2)
	ft.tween_property(flash, "modulate", Color(0.2, 1.0, 0.2, 0.0), 0.5)
	ft.tween_callback(func(): flash.queue_free())

## 卡牌破坏动画：红色闪烁 + 缩小消失
func _play_destroy_animation(btn: Button, delay: float = 0.5) -> void:
	if not is_instance_valid(btn):
		return
	_is_animating = true
	get_tree().paused = true
	# 红色闪烁
	var flash = ColorRect.new()
	flash.size = btn.size * 1.2
	flash.color = Color(1.0, 0.0, 0.0, 0.7)
	flash.z_index = 200
	flash.global_position = btn.global_position - (flash.size - btn.size) / 2.0
	add_child(flash)
	var dt = create_tween().set_parallel(false)
	dt.set_pause_mode(2)
	# 先闪烁0.3秒
	dt.tween_property(flash, "modulate", Color(1.0, 0.0, 0.0, 0.0), 0.3)
	dt.tween_callback(func(): flash.queue_free())
	# 再缩小消失
	dt.tween_interval(delay)
	dt.tween_property(btn, "scale", Vector2(0.1, 0.1), 0.3).set_ease(Tween.EASE_IN)
	dt.tween_property(btn, "modulate", Color(1.0, 1.0, 1.0, 0.0), 0.2)
	dt.tween_callback(func():
		btn.scale = Vector2(1.0, 1.0)
		btn.modulate = Color(1.0, 1.0, 1.0, 1.0)
		# 真正清空内容和旧值
		btn.text = ""
		for child in btn.get_children():
			var lbl = child as Label
			if lbl:
				lbl.text = ""
		if _discard_mode:
			# ★ 弹窗开着时不得越权恢复暂停
			_is_animating = true
			return
		_is_animating = false
		get_tree().paused = false
	)
## 浮动数字特效：在指定位置显示 +N/-N 并上飘消失
func _show_float_number(btn: Button, value: int, color: Color) -> void:
	# 暂停游戏（浮动数字动画期间暂停）
	if _float_counter == 0:
		get_tree().paused = true
	_float_counter += 1
	
	var label = Label.new()
	label.text = ("+" if value > 0 else "") + str(value)
	label.add_theme_font_size_override("font_size", 48)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.z_index = 500
	# 定位在按钮中央
	label.anchor_left = 0.0; label.anchor_top = 0.0
	label.anchor_right = 1.0; label.anchor_bottom = 1.0
	label.offset_left = 0; label.offset_top = 0
	label.offset_right = 0; label.offset_bottom = 0
	btn.add_child(label)
	# 上飘 + 淡出动画（忽略暂停，继续播放）
	var tween = create_tween().set_parallel(true)
	tween.set_pause_mode(2)
	tween.tween_property(label, "offset_top", -40, 0.8).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(label, "modulate", Color(1.0, 1.0, 1.0, 0.0), 0.8).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func():
		label.queue_free()
		_float_counter -= 1
		# 所有浮动数字都结束后才恢复游戏
		if _float_counter <= 0:
			_float_counter = 0
			get_tree().paused = false
	)
## 显示连锁响应提示
func _show_chain_prompt() -> void:
	if _chain_overlay != null:
		return
	# 创建遮罩层
	_chain_overlay = ColorRect.new()
	_chain_overlay.name = "ChainOverlay"
	_chain_overlay.color = Color(0.0, 0.0, 0.0, 0.55)
	_chain_overlay.anchor_left = 0.0; _chain_overlay.anchor_top = 0.0
	_chain_overlay.anchor_right = 1.0; _chain_overlay.anchor_bottom = 1.0
	_chain_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_chain_overlay)
	
	# 提示面板
	var panel = Panel.new()
	panel.name = "ChainPanel"
	panel.anchor_left = 0.15; panel.anchor_top = 0.35
	panel.anchor_right = 0.85; panel.anchor_bottom = 0.65
	_chain_overlay.add_child(panel)
	
	# 标题
	var title = Label.new()
	title.text = "连锁响应！"
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.anchor_left = 0.0; title.anchor_top = 0.0
	title.anchor_right = 1.0; title.anchor_bottom = 0.4
	panel.add_child(title)
	
	# 说明文字
	var desc = Label.new()
	desc.text = "敌方发动了效果，是否连锁响应？\n（使用己方场上具有「连锁响应」能力的卡牌）"
	desc.add_theme_font_size_override("font_size", 22)
	desc.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.9))
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.anchor_left = 0.05; desc.anchor_top = 0.35
	desc.anchor_right = 0.95; desc.anchor_bottom = 0.65
	panel.add_child(desc)
	
	# 按钮行容器
	var btn_container = HBoxContainer.new()
	btn_container.anchor_left = 0.1; btn_container.anchor_top = 0.7
	btn_container.anchor_right = 0.9; btn_container.anchor_bottom = 0.95
	btn_container.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(btn_container)
	
	# 连锁按钮
	var chain_btn = Button.new()
	chain_btn.text = "连锁"
	chain_btn.add_theme_font_size_override("font_size", 28)
	chain_btn.custom_minimum_size = Vector2(180, 60)
	chain_btn.pressed.connect(_on_chain_yes)
	btn_container.add_child(chain_btn)
	
	# 放弃按钮
	var pass_btn = Button.new()
	pass_btn.text = "放弃"
	pass_btn.add_theme_font_size_override("font_size", 28)
	pass_btn.custom_minimum_size = Vector2(180, 60)
	pass_btn.pressed.connect(_on_chain_no)
	btn_container.add_child(pass_btn)
## 玩家选择连锁 → 高亮可连锁的卡牌
func _on_chain_yes() -> void:
	if _battle_manager == null:
		return
	# 移除旧提示，切换为卡牌选择模式
	_hide_chain_prompt()
	
	# 扫描己方场上具有TR16（连锁响应时触发）效果的卡牌
	var self_p = _battle_manager.player_self
	var chainable_cards = []  # [{slot, card, effect}]
	for i in range(self_p.max_field_size):
		var c = self_p.field[i] as BattleCard
		if c == null or not c.is_alive():
			continue
		for eff in c.effects:
			var parsed = Global.parse_circuit(eff)
			if parsed.is_valid and parsed.trigger == "TR16":
				chainable_cards.append({"slot": i, "card": c, "effect": eff})
				break
	
	if chainable_cards.is_empty():
		# 没有可连锁的卡牌，提示后自动放弃
		_show_chain_result("没有可连锁的卡牌，自动放弃")
		_battle_manager.on_player_chain_response(false)
		return
	
	# 显示可连锁卡牌选择界面
	_show_chain_card_selection(chainable_cards)
## 显示可连锁卡牌选择
func _show_chain_card_selection(chainable_cards: Array) -> void:
	if _chain_overlay != null:
		_chain_overlay.queue_free()
		_chain_overlay = null
	
	_chain_overlay = ColorRect.new()
	_chain_overlay.name = "ChainCardSelectOverlay"
	_chain_overlay.color = Color(0.0, 0.0, 0.0, 0.55)
	_chain_overlay.anchor_left = 0.0; _chain_overlay.anchor_top = 0.0
	_chain_overlay.anchor_right = 1.0; _chain_overlay.anchor_bottom = 1.0
	_chain_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_chain_overlay)
	
	var panel = Panel.new()
	panel.name = "ChainSelectPanel"
	panel.anchor_left = 0.1; panel.anchor_top = 0.25
	panel.anchor_right = 0.9; panel.anchor_bottom = 0.75
	_chain_overlay.add_child(panel)
	
	var title = Label.new()
	title.text = "选择连锁的卡牌"
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.anchor_left = 0.0; title.anchor_top = 0.0
	title.anchor_right = 1.0; title.anchor_bottom = 0.15
	panel.add_child(title)
	
	# 卡牌列表
	var card_container = HBoxContainer.new()
	card_container.anchor_left = 0.05; card_container.anchor_top = 0.18
	card_container.anchor_right = 0.95; card_container.anchor_bottom = 0.85
	card_container.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(card_container)
	
	for item in chainable_cards:
		var c = item.card as BattleCard
		var slot = item.slot
		var effect = item.effect
		
		var card_btn = Button.new()
		card_btn.text = c.get_display_name() + "\n连锁"
		card_btn.add_theme_font_size_override("font_size", 22)
		card_btn.custom_minimum_size = Vector2(140, 160)
		card_btn.pressed.connect(func():
			_hide_chain_prompt()
			_battle_manager.on_player_chain_response(true, {"card": c, "effect": effect, "slot": slot})
		)
		card_container.add_child(card_btn)
	
	# 放弃按钮
	var pass_btn = Button.new()
	pass_btn.text = "放弃连锁"
	pass_btn.add_theme_font_size_override("font_size", 24)
	pass_btn.custom_minimum_size = Vector2(160, 50)
	pass_btn.anchor_left = 0.35; pass_btn.anchor_top = 0.88
	pass_btn.anchor_right = 0.65; pass_btn.anchor_bottom = 0.98
	pass_btn.pressed.connect(_on_chain_no)
	panel.add_child(pass_btn)
## 玩家放弃连锁
func _on_chain_no() -> void:
	_hide_chain_prompt()
	_battle_manager.on_player_chain_response(false)
	_show_chain_result("已放弃连锁")
## 模态开关同步到驱动器闸门（暂停树对 PROCESS_MODE_ALWAYS 的驱动器无效，必须显式通知）
func _set_driver_busy(busy: bool) -> void:
	if _battle_driver:
		_battle_driver.set_ui_busy(busy)

## 隐藏连锁提示
func _hide_chain_prompt() -> void:
	if _chain_overlay != null:
		_chain_overlay.queue_free()
		_chain_overlay = null
	_chain_awaiting_response = false
	_set_driver_busy(false)
## 显示连锁结果提示（短暂显示后自动消失）
func _show_chain_result(text: String) -> void:
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 32)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.anchor_left = 0.2; lbl.anchor_top = 0.4
	lbl.anchor_right = 0.8; lbl.anchor_bottom = 0.6
	lbl.z_index = 300
	add_child(lbl)
	var t = create_tween()
	t.tween_property(lbl, "modulate", Color(1.0, 0.9, 0.3, 0.0), 1.2).set_delay(0.5)
	t.tween_callback(func(): lbl.queue_free())
func _show_float_text_center(action_type: String, value: int, desc: String) -> void:
	var text := ""
	var color := Color.WHITE
	match action_type:
		"A01": text = " -" + str(value); color = Color(1.0, 0.3, 0.3)
		"A02": text = " +" + str(value); color = Color(0.3, 1.0, 0.3)
		"A09": text = " +" + str(value) + "张"; color = Color(0.3, 0.6, 1.0)
		# "A19": text = "✨ 召唤"; color = Color(1.0, 0.8, 0.3)  # 已注释
		"A20": text = " " + ("+" if value > 0 else "") + str(value); color = Color(1.0, 0.6, 0.2)
		"A21": text = " " + ("+" if value > 0 else "") + str(value); color = Color(0.3, 0.8, 0.3)
		# "A22": text = "⚔️🛡️ +" + str(value); color = Color(1.0, 0.9, 0.3)  # 已注释
		_: text = desc if desc.length() > 0 else "效果"; color = Color.WHITE
	var float_lbl = Label.new()
	float_lbl.text = text
	float_lbl.add_theme_font_size_override("font_size", 48)
	float_lbl.add_theme_color_override("font_color", color)
	float_lbl.add_theme_constant_override("shadow_offset_x", 2)
	float_lbl.add_theme_constant_override("shadow_offset_y", 2)
	float_lbl.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	float_lbl.z_index = 250
	float_lbl.global_position = self.size / 2.0 - Vector2(60, 0)
	add_child(float_lbl)
	var ft = create_tween().set_parallel(true)
	ft.tween_property(float_lbl, "global_position", float_lbl.global_position - Vector2(0, 60), 1.0).set_ease(Tween.EASE_OUT)
	ft.tween_property(float_lbl, "modulate", Color(1.0, 1.0, 1.0, 0.0), 0.8).set_delay(0.2)
	ft.tween_callback(func(): float_lbl.queue_free())

func _flash_slot(slot_btn: Button) -> void:
	var flash = ColorRect.new()
	flash.size = slot_btn.size * 1.2
	flash.color = Color(1.0, 1.0, 0.6, 0.5)
	flash.z_index = 200
	flash.global_position = slot_btn.global_position - (flash.size - slot_btn.size) / 2.0
	add_child(flash)
	var ft = create_tween()
	ft.tween_property(flash, "modulate", Color(1.0, 1.0, 0.6, 0.0), 0.4)
	ft.tween_callback(func(): flash.queue_free())

func _show_float_text(slot_btn: Button, action_type: String, value: int, desc: String) -> void:
	# 根据动作类型生成飘字文本和颜色
	var text := ""
	var color := Color.WHITE
	match action_type:
		"A01":  # 伤害
			text = " -" + str(value)
			color = Color(1.0, 0.3, 0.3)
		"A02":  # 治疗
			text = " +" + str(value)
			color = Color(0.3, 1.0, 0.3)
		"A09":  # 抽牌
			text = " +" + str(value) + "张"
			color = Color(0.3, 0.6, 1.0)
		"A19":  # 召唤
			text = " 召唤"
			color = Color(1.0, 0.8, 0.3)
		"A20":  # 攻增益
			text = " " + ("+" if value > 0 else "") + str(value)
			color = Color(1.0, 0.6, 0.2)
		"A21":  # 命增益
			text = " " + ("+" if value > 0 else "") + str(value)
			color = Color(0.3, 0.8, 0.3)
		"A22":  # 双增益
			text = " +" + str(value)
			color = Color(1.0, 0.9, 0.3)
		_:
			text = desc if desc.length() > 0 else "效果"
			color = Color.WHITE
	
	var float_lbl = Label.new()
	float_lbl.text = text
	float_lbl.add_theme_font_size_override("font_size", 36)
	float_lbl.add_theme_color_override("font_color", color)
	float_lbl.add_theme_constant_override("shadow_offset_x", 2)
	float_lbl.add_theme_constant_override("shadow_offset_y", 2)
	float_lbl.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	float_lbl.z_index = 250
	# 定位在卡牌上方
	float_lbl.global_position = slot_btn.global_position - Vector2(0, slot_btn.size.y * 0.5)
	float_lbl.global_position.x += slot_btn.size.x * 0.5 - 40
	add_child(float_lbl)
	# 向上飘动并淡出
	var ft = create_tween().set_parallel(true)
	ft.tween_property(float_lbl, "global_position", float_lbl.global_position - Vector2(0, 50), 0.8).set_ease(Tween.EASE_OUT)
	ft.tween_property(float_lbl, "modulate", Color(1.0, 1.0, 1.0, 0.0), 0.6).set_delay(0.2)
	ft.tween_callback(func(): float_lbl.queue_free())

# 玩家状态变化
func _on_player_hand_changed() -> void:
	_refresh_hand_ui()

func _on_player_field_changed() -> void:
	if _last_summon_hand_idx >= 0 and _last_summon_slot_idx >= 0:
		# 入场动画：从手牌飞向场地
		_play_summon_animation(_last_summon_hand_idx, _last_summon_slot_idx)
		_last_summon_hand_idx = -1
		_last_summon_slot_idx = -1
	else:
		_refresh_field_ui()
		_refresh_hand_ui()

func _on_player_energy_changed(old_val: int, new_val: int) -> void:
	var p = _battle_manager.player_self
	_update_label("PlayerEnergy", " " + str(p.energy) + "/" + str(p.max_energy))

func _on_player_hp_changed(old_hp: int, new_hp: int) -> void:
	var p = _battle_manager.player_self
	_update_label("PlayerHP", " " + str(p.hp) + "/" + str(p.max_hp))

func _on_player_deck_changed() -> void:
	var p = _battle_manager.player_self
	_update_label("PlayerDeck", "\n" + str(p.deck.size()))

func _on_player_grave_changed() -> void:
	var p = _battle_manager.player_self
	_update_label("PlayerGrave", "\n" + str(p.grave.size()))

# 敌方状态变化
func _on_enemy_hand_changed() -> void:
	# 敌方手牌只显示数量
	var p = _battle_manager.player_opponent
	var hand_size = p.hand.size()
	for i in range(_enemy_hand_cards.size()):
		if i < hand_size:
			_enemy_hand_cards[i].show()
		else:
			_enemy_hand_cards[i].hide()
	# 更新手牌数标签
	_update_label("EnemyHand", " 敌方手牌 " + str(hand_size))

func _on_enemy_field_changed() -> void:
	# 敌方召唤入场动画由 BattleDriver.enemy_summon_animation_requested 信号驱动（横竖屏共用协议）
	_refresh_field_ui()

func _on_enemy_energy_changed(old_val: int, new_val: int) -> void:
	var p = _battle_manager.player_opponent
	_update_label("EnemyEnergy", " " + str(p.energy) + "/" + str(p.max_energy))

func _on_enemy_hp_changed(old_hp: int, new_hp: int) -> void:
	var p = _battle_manager.player_opponent
	_update_label("EnemyHP", " " + str(p.hp) + "/" + str(p.max_hp))

func _on_enemy_deck_changed() -> void:
	var p = _battle_manager.player_opponent
	_update_label("EnemyDeck", "\n" + str(p.deck.size()))

func _on_enemy_grave_changed() -> void:
	var p = _battle_manager.player_opponent
	_update_label("EnemyGrave", "\n" + str(p.grave.size()))

# 除外区变化
func _on_player_banish_changed() -> void:
	var p = _battle_manager.player_self
	_update_label("PlayerBanish", "\n" + str(p.banished.size()))

func _on_enemy_banish_changed() -> void:
	var p = _battle_manager.player_opponent
	_update_label("EnemyBanish", "\n" + str(p.banished.size()))


# ============================
#  墓地弹窗
# ============================
func _on_player_grave_clicked() -> void:
	if _battle_manager == null:
		return
	_show_grave_popup(_battle_manager.player_self, false, " 己方墓地")
func _on_enemy_grave_clicked() -> void:
	if _battle_manager == null:
		return
	_show_grave_popup(_battle_manager.player_opponent, false, " 敌方墓地")
func _on_player_banish_clicked() -> void:
	if _battle_manager == null:
		return
	_show_grave_popup(_battle_manager.player_self, true, " 己方除外区")
func _on_enemy_banish_clicked() -> void:
	if _battle_manager == null:
		return
	_show_grave_popup(_battle_manager.player_opponent, true, " 敌方除外区")


func _show_grave_popup(player_ref: BattlePlayer, is_banish: bool, title_text: String) -> void:
	# 遮罩
	var overlay = ColorRect.new()
	overlay.name = "GraveOverlay"
	overlay.color = Color(0.0, 0.0, 0.0, 0.7)
	overlay.anchor_left = 0.0; overlay.anchor_top = 0.0
	overlay.anchor_right = 1.0; overlay.anchor_bottom = 1.0
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			overlay.queue_free()
	)
	add_child(overlay)
	
	# 面板（居中，宽75%，高65%）
	var panel = Panel.new()
	panel.name = "GravePanel"
	var ps = StyleBoxFlat.new()
	ps.bg_color = Color(0.08, 0.06, 0.14)
	ps.corner_radius_top_left = 16; ps.corner_radius_top_right = 16
	ps.corner_radius_bottom_left = 16; ps.corner_radius_bottom_right = 16
	ps.border_width_left = 2; ps.border_width_right = 2
	ps.border_width_top = 2; ps.border_width_bottom = 2
	ps.border_color = Color(0.4, 0.3, 0.6)
	panel.add_theme_stylebox_override("panel", ps)
	panel.anchor_left = 0.0; panel.anchor_top = 0.0
	panel.anchor_right = 0.0; panel.anchor_bottom = 0.0
	panel.offset_left = Global.pw(0.12)
	panel.offset_top = Global.ph(0.15)
	panel.offset_right = Global.pw(-0.12)
	panel.offset_bottom = Global.ph(0.85)
	overlay.add_child(panel)
	
	# 标题
	var title = Label.new()
	title.name = "PopupTitle"
	title.add_theme_font_size_override("font_size", 50)
	title.add_theme_color_override("font_color", Color("#c0a0d0"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.anchor_left = 0.0; title.anchor_top = 0.0
	title.anchor_right = 1.0; title.anchor_bottom = 0.0
	title.offset_left = Global.pw(0.08); title.offset_top = Global.ph(0.02)
	title.offset_right = Global.pw(-0.08); title.offset_bottom = Global.ph(0.08)
	panel.add_child(title)
	
	# 切换按钮（右上角）
	var toggle_btn = Button.new()
	toggle_btn.name = "ToggleBtn"
	toggle_btn.text = "墓地" if is_banish else " 除外"
	toggle_btn.add_theme_font_size_override("font_size", 32)
	var toggle_s = StyleBoxFlat.new()
	toggle_s.bg_color = Color(0.2, 0.15, 0.3)
	toggle_s.border_width_left = 1; toggle_s.border_width_right = 1
	toggle_s.border_width_top = 1; toggle_s.border_width_bottom = 1
	toggle_s.border_color = Color(0.5, 0.3, 0.6)
	toggle_s.corner_radius_top_left = 6; toggle_s.corner_radius_top_right = 6
	toggle_s.corner_radius_bottom_left = 6; toggle_s.corner_radius_bottom_right = 6
	toggle_btn.add_theme_stylebox_override("normal", toggle_s)
	toggle_btn.add_theme_color_override("font_color", Color("#c0a0d0"))
	toggle_btn.anchor_left = 1.0; toggle_btn.anchor_top = 0.0
	toggle_btn.anchor_right = 1.0; toggle_btn.anchor_bottom = 0.0
	toggle_btn.offset_left = Global.pw(-0.18); toggle_btn.offset_top = Global.ph(0.02)
	toggle_btn.offset_right = Global.pw(-0.03); toggle_btn.offset_bottom = Global.ph(0.065)
	panel.add_child(toggle_btn)
	
	# 分割线
	var line = ColorRect.new()
	line.color = Color(0.4, 0.3, 0.255, 0.3)
	line.anchor_left = 0.0; line.anchor_top = 0.0
	line.anchor_right = 1.0; line.anchor_bottom = 0.0
	line.offset_left = Global.pw(0.05); line.offset_top = Global.ph(0.09)
	line.offset_right = Global.pw(-0.05); line.offset_bottom = Global.ph(0.091)
	panel.add_child(line)
	
	# 滚动列表区域容器（用于刷新时替换）
	var scroll_container = Panel.new()
	scroll_container.name = "ScrollContainerWrapper"
	scroll_container.anchor_left = 0.0; scroll_container.anchor_top = 0.0
	scroll_container.anchor_right = 1.0; scroll_container.anchor_bottom = 1.0
	scroll_container.offset_left = 0; scroll_container.offset_top = Global.ph(0.1)
	scroll_container.offset_right = 0; scroll_container.offset_bottom = 0
	var sc_s = StyleBoxFlat.new()
	sc_s.bg_color = Color(0, 0, 0, 0)
	scroll_container.add_theme_stylebox_override("panel", sc_s)
	panel.add_child(scroll_container)
	
	# 当前显示模式（闭包变量）
	var current_is_banish = is_banish
	
	# 构建列表函数
	var _build_list = func(_is_banish: bool):
		# 清空旧内容
		for c in scroll_container.get_children():
			c.queue_free()
		
		var list = player_ref.banished if _is_banish else player_ref.grave
		var tag = "" if _is_banish else ""
		var list_name = "除外区" if _is_banish else "墓地"
		
		title.text = tag + " " + list_name + "  (" + str(list.size()) + "张)"
		toggle_btn.text = "墓地" if _is_banish else " 除外"
		
		if list.size() == 0:
			var empty = Label.new()
			empty.text = "（空）"
			empty.add_theme_font_size_override("font_size", 42)
			empty.add_theme_color_override("font_color", Color("#5a5a6e"))
			empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			empty.anchor_left = 0.0; empty.anchor_top = 0.0
			empty.anchor_right = 1.0; empty.anchor_bottom = 1.0
			empty.offset_left = 0; empty.offset_top = 0
			empty.offset_right = 0; empty.offset_bottom = 0
			scroll_container.add_child(empty)
			return
		
		# 滚动列表
		var scroll = ScrollContainer.new()
		scroll.anchor_left = 0.0; scroll.anchor_top = 0.0
		scroll.anchor_right = 1.0; scroll.anchor_bottom = 1.0
		scroll.offset_left = Global.pw(0.03); scroll.offset_top = 0
		scroll.offset_right = Global.pw(-0.03); scroll.offset_bottom = Global.ph(-0.06)
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll_container.add_child(scroll)
		
		var vbox = VBoxContainer.new()
		vbox.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
		vbox.custom_minimum_size = Vector2(Global.pw(0.70), 0)
		scroll.add_child(vbox)
		
		var row_idx := 0
		for card in list:
			var c = card as BattleCard
			if c == null:
				continue
			
			# 行背景
			var row = Panel.new()
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var rs = StyleBoxFlat.new()
			rs.bg_color = Color(0.15, 0.12, 0.20) if row_idx % 2 == 0 else Color(0.11, 0.09, 0.16)
			rs.corner_radius_top_left = 6; rs.corner_radius_top_right = 6
			rs.corner_radius_bottom_left = 6; rs.corner_radius_bottom_right = 6
			row.add_theme_stylebox_override("panel", rs)
			row.custom_minimum_size = Vector2(0, Global.ph(0.06))
			row.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
			vbox.add_child(row)
			
			# 行内容（HBox）
			var hbox = HBoxContainer.new()
			hbox.anchor_left = 0.0; hbox.anchor_top = 0.0
			hbox.anchor_right = 1.0; hbox.anchor_bottom = 1.0
			hbox.offset_left = Global.pw(0.03)
			row.add_child(hbox)
			
			# 品质颜色
			var q_color = Color("#e8d5b7")
			match c.quality:
				"传说": q_color = Color("#f9d371")
				"史诗": q_color = Color("#c084fc")
				"稀有": q_color = Color("#60a5fa")
			
			# 卡牌名称
			var name_label = Label.new()
			name_label.text = c.get_display_name()
			name_label.add_theme_font_size_override("font_size", 38)
			name_label.add_theme_color_override("font_color", q_color)
			name_label.size_flags_horizontal = Control.SIZE_EXPAND
			name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
			hbox.add_child(name_label)
			
			# 攻防信息
			var stats_label = Label.new()
			stats_label.text = "" + str(c.current_atk) + " " + str(c.current_hp)
			stats_label.add_theme_font_size_override("font_size", 34)
			stats_label.add_theme_color_override("font_color", Color("#7a8a7a"))
			stats_label.custom_minimum_size = Vector2(Global.pw(0.12), 0)
			stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			hbox.add_child(stats_label)
			
			# 详情按钮（点击弹窗查看卡牌详情，不拦截滑动）
			var card_ref = c
			var detail_btn = Button.new()
			detail_btn.text = "详情"
			detail_btn.add_theme_font_size_override("font_size", 30)
			var dbs2 = StyleBoxFlat.new()
			dbs2.bg_color = Color(0.25, 0.2, 0.32)
			dbs2.border_width_left = 1; dbs2.border_width_right = 1
			dbs2.border_width_top = 1; dbs2.border_width_bottom = 1
			dbs2.border_color = Color(0.5, 0.4, 0.6, 0.6)
			dbs2.corner_radius_top_left = 6; dbs2.corner_radius_top_right = 6
			dbs2.corner_radius_bottom_left = 6; dbs2.corner_radius_bottom_right = 6
			dbs2.content_margin_left = 12; dbs2.content_margin_right = 12
			detail_btn.add_theme_stylebox_override("normal", dbs2)
			detail_btn.add_theme_color_override("font_color", Color("#c0b0d0"))
			detail_btn.pressed.connect(func():
				var popup = CardDetailPopup.new()
				add_child(popup)
				popup.show_card(card_ref, "view")
			)
			hbox.add_child(detail_btn)
			row_idx += 1
	
	# 初始构建
	_build_list.call(current_is_banish)
	
	# 切换按钮点击事件
	toggle_btn.pressed.connect(func():
		current_is_banish = not current_is_banish
		_build_list.call(current_is_banish)
	)
	
	# 关闭按钮
	var close_btn = Button.new()
	close_btn.text = "关闭"
	close_btn.add_theme_font_size_override("font_size", 38)
	var cs = StyleBoxFlat.new()
	cs.bg_color = Color(0.15, 0.10, 0.20)
	cs.border_width_left = 2; cs.border_width_right = 2
	cs.border_width_top = 2; cs.border_width_bottom = 2
	cs.border_color = Color(0.4, 0.3, 0.5, 0.6)
	cs.corner_radius_top_left = 10; cs.corner_radius_top_right = 10
	cs.corner_radius_bottom_left = 10; cs.corner_radius_bottom_right = 10
	cs.content_margin_left = 20; cs.content_margin_right = 20
	close_btn.add_theme_stylebox_override("normal", cs)
	close_btn.add_theme_color_override("font_color", Color("#a0a0b0"))
	close_btn.anchor_left = 0.0; close_btn.anchor_top = 1.0
	close_btn.anchor_right = 1.0; close_btn.anchor_bottom = 1.0
	close_btn.offset_left = Global.pw(0.30); close_btn.offset_top = Global.ph(-0.12)
	close_btn.offset_right = Global.pw(-0.30); close_btn.offset_bottom = Global.ph(-0.02)
	close_btn.pressed.connect(overlay.queue_free)
	panel.add_child(close_btn)


# ===== 更新信息显示（兼容旧代码） =====
func _update_all_info():
	_refresh_all_ui()


func _update_label(name: String, text: String):
	var node = get_node_or_null(name)
	if node:
		node.text = text

# ===== 长按检测（用于显示卡牌详情） =====

var _press_start_time: float = 0.0
var _press_hand_index: int = -1
var _press_slot_index: int = -1
var _press_is_enemy: bool = false
var _long_press_triggered: bool = false
const LONG_PRESS_DURATION: float = 0.4  # 400ms

## 手牌拖拽启动（替代旧点击召唤）
func _on_hand_card_drag(event: InputEvent, hand_index: int) -> void:
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			# 弃牌阶段：点击手牌切换选中
			if _discard_mode:
				_toggle_discard_selection(hand_index)
				return
			
			# 记录长按（用于显示详情）
			_press_start_time = Time.get_ticks_msec() / 1000.0
			_press_hand_index = hand_index
			_press_slot_index = -1
			_press_is_enemy = false
			_long_press_triggered = false
			
			# 检查是否可以拖拽召唤
			if _battle_manager == null:
				return
			if _battle_manager.current_phase != BattleManager.Phase.MAIN or not _battle_manager.is_player_turn():
				return
			
			var self_p = _battle_manager.player_self
			if hand_index >= self_p.hand.size():
				return
			var card = self_p.hand[hand_index] as BattleCard
			if card == null or card.base_cost > self_p.energy:
				return
			if self_p.get_empty_slots().is_empty():
				return
			
			# 记录拖拽起点，但还不开始拖拽（等移动超过阈值）
			_drag_hand_index = hand_index
			_drag_start_global = get_global_mouse_position()
			# 注意：不设置 _is_dragging = true，也不设置 _long_press_triggered = true
			# 让长按有机会触发
		
		elif not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			# 手指抬起
			if not _is_dragging and not _long_press_triggered:
				# 没拖拽也没长按，只是点击了一下
				_press_hand_index = -1
				_drag_hand_index = -1

## 己方场地长按检测
func _on_player_slot_gui_input(event: InputEvent, slot: int) -> void:
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_press_start_time = Time.get_ticks_msec() / 1000.0
			_press_hand_index = -1
			_press_slot_index = slot
			_press_is_enemy = false
			_long_press_triggered = false
			
			# 检查是否处于BATTLE阶段且该卡牌可攻击
			var can_drag_attack = false
			if _battle_manager != null and _battle_manager.current_phase == BattleManager.Phase.BATTLE and _battle_manager.is_player_turn():
				if slot < _battle_manager.player_self.field.size():
					var card = _battle_manager.player_self.field[slot]
					if card != null and card.is_alive() and card.can_attack():
						can_drag_attack = true
			
			if can_drag_attack:
				_drag_attack_press_slot = slot
				_drag_attack_press_pos = get_global_mouse_position()
			else:
				_drag_attack_press_slot = -1
		elif not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if not _long_press_triggered and not _is_dragging_attack:
				_press_slot_index = -1
				# 点击释放不做任何事（攻击只能通过拖拽攻击或长按弹窗→攻击按钮）
			_drag_attack_press_slot = -1

## 敌方场地长按检测
func _on_enemy_slot_gui_input(event: InputEvent, slot: int) -> void:
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_press_start_time = Time.get_ticks_msec() / 1000.0
			_press_hand_index = -1
			_press_slot_index = slot
			_press_is_enemy = true
			_long_press_triggered = false
		elif not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if not _long_press_triggered:
				_press_slot_index = -1

func _process(delta: float) -> void:
	# 敌方AI驱动已迁移至 BattleDriver（battle_core/BattleDriver.gd），此处不再轮询
	
	# 检查长按触发
	if _press_hand_index >= 0 or _press_slot_index >= 0:
		if _long_press_triggered:
			return
		var now = Time.get_ticks_msec() / 1000.0
		if now - _press_start_time >= LONG_PRESS_DURATION:
			_long_press_triggered = true
			# 如果已经在拖拽攻击中，说明玩家意图是拖拽，不弹窗
			if _is_dragging_attack:
				return
			# 长按触发时：先显示详情（读取当前 _press_slot_index），再清理拖拽状态
			# 注意：_cleanup_drag_attack 会重置 _press_slot_index，所以必须先调用 _show_card_detail
			_show_card_detail()
			_cleanup_drag_attack()

## 显示卡牌详情弹窗
func _show_card_detail() -> void:
	if _battle_manager == null:
		_reset_press()
		return
	
	var card: BattleCard = null
	var mode: String = "view"
	var hand_idx: int = -1
	var slot_idx: int = -1
	
	if _press_hand_index >= 0:
		# 手牌
		var self_p = _battle_manager.player_self
		if _press_hand_index < self_p.hand.size():
			card = self_p.hand[_press_hand_index] as BattleCard
			hand_idx = _press_hand_index
			# 手牌显示召唤按钮
			mode = "hand_summon"
	elif _press_slot_index >= 0:
		if _press_is_enemy:
			var enemy_p = _battle_manager.player_opponent
			if _press_slot_index < enemy_p.field.size():
				card = enemy_p.field[_press_slot_index] as BattleCard
			# 敌方场地只用查看模式
			mode = "view"
		else:
			var self_p = _battle_manager.player_self
			if _press_slot_index < self_p.field.size():
				card = self_p.field[_press_slot_index] as BattleCard
				slot_idx = _press_slot_index
				# 己方场地显示攻击按钮
				mode = "field_attack"
	
	if card != null:
		var popup = CardDetailPopup.new()
		add_child(popup)
		
		if mode == "hand_summon":
			# 召唤回调：打开SlotSelectPopup选择空格
			popup.show_card(card, "hand_summon", _battle_manager, hand_idx, -1, 
				_on_summon_from_popup.bind(hand_idx, popup), Callable())
		elif mode == "field_attack":
			# 攻击回调：打开SlotSelectPopup选择敌方目标
			popup.show_card(card, "field_attack", _battle_manager, -1, slot_idx, Callable(),
				_on_attack_from_popup.bind(slot_idx, popup))
		else:
			popup.show_card(card, "view")
	
	_reset_press()


## 从弹窗点击召唤按钮 → 打开SlotSelectPopup选择空格
func _on_summon_from_popup(hand_idx: int, detail_popup) -> void:
	# 关闭详情弹窗
	if detail_popup != null and is_instance_valid(detail_popup):
		detail_popup.close()
	
	# 打开SlotSelectPopup选择空格
	var slot_popup = SlotSelectPopup.new()
	add_child(slot_popup)
	slot_popup.show_select(_battle_manager, false, true, "选择召唤位置",
		_on_summon_slot_selected.bind(hand_idx))


## SlotSelectPopup选择召唤位置后的回调
func _on_summon_slot_selected(slot_index: int, hand_idx: int) -> void:
	# 执行召唤（先不设 _last_summon_*，避免信号中途误触发）
	_prev_player_field_count = _battle_manager.player_self.get_field_count()
	var result = _battle_manager.do_action("summon", {
		"hand_index": hand_idx,
		"slot_index": slot_index
	})
	if result.success:
		# 召唤成功后才设标记，让 field_changed 信号触发动画
		_last_summon_hand_idx = hand_idx
		_last_summon_slot_idx = slot_index
		# 手动触发 field_changed 来播放动画（因为信号可能已经在 do_action 内部发过了）
		_play_summon_animation(hand_idx, slot_index)
		_last_summon_hand_idx = -1
		_last_summon_slot_idx = -1
	else:
		print("[UI] 弹窗召唤失败: ", result.get("reason", ""))


## 从弹窗点击攻击按钮 → 打开SlotSelectPopup选择敌方目标
func _on_attack_from_popup(slot_idx: int, detail_popup) -> void:
	# 关闭详情弹窗
	if detail_popup != null and is_instance_valid(detail_popup):
		detail_popup.close()
	
	# 检查敌方场上是否有卡牌
	var enemy_p = _battle_manager.player_opponent
	var has_enemy_cards = enemy_p.get_field_count() > 0
	
	if has_enemy_cards:
		# 有敌方卡牌 → 打开SlotSelectPopup选择目标
		var slot_popup = SlotSelectPopup.new()
		add_child(slot_popup)
		slot_popup.show_select(_battle_manager, true, false, "选择攻击目标",
			_on_attack_slot_selected.bind(slot_idx))
	else:
		# 没有敌方卡牌 → 直接攻击英雄
		_execute_attack_hero(slot_idx)


## SlotSelectPopup选择攻击目标后的回调
func _on_attack_slot_selected(target_slot: int, attacker_slot: int) -> void:
	_execute_attack(attacker_slot, target_slot)

func _reset_press() -> void:
	_press_hand_index = -1
	_press_slot_index = -1
	_long_press_triggered = false
	# 兜底：清理可能残留的拖拽攻击状态
	if _is_dragging_attack or _drag_attack_press_slot >= 0:
		_cleanup_drag_attack()

# ===== 弃牌阶段UI =====
## 切换弃牌选中
func _toggle_discard_selection(hand_index: int) -> void:
	if _battle_manager == null:
		return
	var self_p = _battle_manager.player_self
	if hand_index < 0 or hand_index >= self_p.hand.size():
		return
	var need_discard = _discard_need
	
	if _discard_selected.has(hand_index):
		# 取消选中
		_discard_selected.erase(hand_index)
	else:
		# 选中（不超过需要弃的数量）
		if _discard_selected.size() < need_discard:
			_discard_selected.append(hand_index)
	
	_refresh_discard_hand_ui()

## 显示弃牌弹窗
func _show_discard_ui() -> void:
	if _battle_manager == null:
		return
	_discard_mode = true
	_discard_selected.clear()
	
	# ★ 弹窗期间必须暂停游戏树 + 置 _is_animating，并关闭驱动器闸门，
	# 否则敌方AI队列仍会继续推进（驱动器是 PROCESS_MODE_ALWAYS，不受暂停树影响）
	_is_animating = true
	_set_driver_busy(true)
	get_tree().paused = true
	print("[UI] 弃牌弹窗: 暂停游戏树等待玩家选择")
	
	var player = _battle_manager.player_self
	var need_discard = _discard_need
	print("[UI] 弃牌阶段: 手牌", player.hand.size(), "张，需要弃", need_discard, "张")
	
	# 面板（中上部小面板，不加遮罩，不遮挡手牌区）
	# ★ PROCESS_MODE_ALWAYS：暂停状态下面板及子节点（确认按钮等）仍可交互
	_discard_panel = Panel.new()
	_discard_panel.name = "DiscardPanel"
	_discard_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	var ps = StyleBoxFlat.new()
	ps.bg_color = Color(0.08, 0.06, 0.14, 0.95)
	ps.corner_radius_top_left = 16; ps.corner_radius_top_right = 16
	ps.corner_radius_bottom_left = 16; ps.corner_radius_bottom_right = 16
	ps.border_width_left = 2; ps.border_width_right = 2
	ps.border_width_top = 2; ps.border_width_bottom = 2
	ps.border_color = Color(0.4, 0.3, 0.6)
	_discard_panel.add_theme_stylebox_override("panel", ps)
	_discard_panel.anchor_left = 0.0; _discard_panel.anchor_top = 0.0
	_discard_panel.anchor_right = 1.0; _discard_panel.anchor_bottom = 0.0
	_discard_panel.offset_left = Global.pw(0.15)
	_discard_panel.offset_top = Global.ph(0.16)
	_discard_panel.offset_right = Global.pw(-0.15)
	_discard_panel.offset_bottom = Global.ph(0.42)
	add_child(_discard_panel)
	
	# 标题
	var title = Label.new()
	title.text = "弃牌阶段"
	title.add_theme_font_size_override("font_size", 45)
	title.add_theme_color_override("font_color", Color("#e0c0f0"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.anchor_left = 0.0; title.anchor_top = 0.0
	title.anchor_right = 1.0; title.anchor_bottom = 0.0
	title.offset_top = Global.ph(0.01); title.offset_bottom = Global.ph(0.06)
	_discard_panel.add_child(title)
	
	# 已选提示
	_discard_count_label = Label.new()
	_discard_count_label.text = "已选：0 / " + str(need_discard) + " 张"
	_discard_count_label.add_theme_font_size_override("font_size", 35)
	_discard_count_label.add_theme_color_override("font_color", Color("#f0d060"))
	_discard_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_discard_count_label.anchor_left = 0.0; _discard_count_label.anchor_top = 0.0
	_discard_count_label.anchor_right = 1.0; _discard_count_label.anchor_bottom = 0.0
	_discard_count_label.offset_top = Global.ph(0.06); _discard_count_label.offset_bottom = Global.ph(0.10)
	_discard_panel.add_child(_discard_count_label)
	
	# 确认按钮
	_discard_confirm_btn = Button.new()
	_discard_confirm_btn.text = "确认弃牌"
	_discard_confirm_btn.disabled = true
	_discard_confirm_btn.add_theme_font_size_override("font_size", 35)
	_discard_confirm_btn.anchor_left = 0.0; _discard_confirm_btn.anchor_top = 0.0
	_discard_confirm_btn.anchor_right = 0.0; _discard_confirm_btn.anchor_bottom = 0.0
	_discard_confirm_btn.offset_left = Global.pw(0.25)
	_discard_confirm_btn.offset_top = Global.ph(0.08)
	_discard_confirm_btn.offset_right = Global.pw(0.25)
	_discard_confirm_btn.offset_bottom = Global.ph(0.13)
	_discard_confirm_btn.pressed.connect(_on_confirm_discard)
	_discard_panel.add_child(_discard_confirm_btn)
	
	# 刷新手牌UI（可点击选择）
	_refresh_discard_hand_ui()

## 刷新弃牌阶段手牌（可选中的高亮）
func _refresh_discard_hand_ui() -> void:
	if _battle_manager == null:
		return
	var self_p = _battle_manager.player_self
	var need_discard = _discard_need
	
	for i in range(_hand_cards.size()):
		var btn = _hand_cards[i] as Button
		if btn == null:
			continue
		# ★ 弃牌弹窗期间游戏树已暂停，手牌按钮需 ALWAYS 才能继续接收点击
		btn.process_mode = Node.PROCESS_MODE_ALWAYS
		if i < self_p.hand.size():
			btn.show()
			var is_selected = _discard_selected.has(i)
			# 卡面底图 + 选中红框高亮
			_apply_all_states(btn, _make_card_face_style())
			if is_selected:
				_set_card_highlight(btn, Color(1.0, 0.4, 0.4, 0.95))
			else:
				_clear_card_highlight(btn)
			btn.disabled = false
		else:
			btn.hide()
	
	# 更新已选计数
	_discard_count_label.text = "已选：" + str(_discard_selected.size()) + " / " + str(need_discard) + " 张"
	_discard_confirm_btn.disabled = (_discard_selected.size() < need_discard)

## 隐藏弃牌UI
func _hide_discard_ui() -> void:
	_discard_mode = false
	_discard_selected.clear()
	_discard_need = 0
	_set_driver_busy(false)
	# ★ 还原手牌按钮的暂停模式（恢复普通输入）
	for i in range(_hand_cards.size()):
		var hb = _hand_cards[i] as Button
		if hb:
			hb.process_mode = Node.PROCESS_MODE_INHERIT
	if _discard_panel:
		_discard_panel.queue_free()
		_discard_panel = null
	_discard_count_label = null
	_discard_confirm_btn = null
## ★ 动画完成统一恢复暂停的守卫：
## 若弃牌弹窗仍开着（_discard_mode），不解除暂停、不放开AI闸门，
## 避免入场/攻击动画的 tween（忽略暂停）完成回调把弹窗暂停越权解除。
## 弹窗关闭后由弃牌动画完成回调正常恢复。
func _resume_after_animation() -> void:
	if _discard_mode:
		return
	_is_animating = false
	get_tree().paused = false

## 确认弃牌
func _on_confirm_discard() -> void:
	if _battle_manager == null:
		return
	if _discard_callback_id < 0 or _discard_selected.size() == 0:
		return
	# 通知BattleManager执行弃牌（内部会 _do_discard + 发动画信号）
	_battle_manager._on_discard_result(_discard_callback_id, _discard_selected)
	print("[UI] 弃牌提交，回调ID: ", _discard_callback_id)
	_discard_callback_id = -1
	_hide_discard_ui()

## 播放弃牌飞入墓地动画（卡牌从手牌位置飞向墓地，播完通知BattleManager执行回调）
## 注意：数据已在 _do_discard 中移除，这里用记录的位置做视觉特效
func _play_discard_animation(callback_id: int, is_player_side: bool, discard_indices: Array) -> void:
	var grave_btn = _player_grave_btn if is_player_side else _enemy_grave_btn
	if grave_btn == null or discard_indices.is_empty():
		# 没有墓地按钮或没有弃牌索引，直接完成动画（跳过特效）
		# ★ 弹窗已暂停游戏树，这里必须先恢复暂停+_is_animating，再回调，否则会卡死
		_resume_after_animation()
		_battle_manager._on_discard_animation_finished(callback_id)
		# ★ 早退路径同样要处理队列中下一个弃牌请求
		_process_next_discard_request()
		return
	
	# 目标位置：墓地按钮中心
	var end_global = grave_btn.global_position + grave_btn.size / 2.0
	
	# 收集起始位置（对应手牌按钮当前位置）
	var start_positions := []
	var hand_ref = _hand_cards if is_player_side else _enemy_hand_cards
	for idx in discard_indices:
		var hand_idx = int(idx)
		if hand_idx >= 0 and hand_idx < hand_ref.size():
			var hand_btn = hand_ref[hand_idx] as Button if is_player_side else hand_ref[hand_idx] as Control
			if hand_btn and hand_btn.visible:
				start_positions.append(hand_btn.global_position + hand_btn.size / 2.0)
			else:
				# 手牌按钮不可见，用墓地按钮上方作为起始
				start_positions.append(end_global + Vector2(0, -Global.ph(0.3)))
		else:
			# 索引无效，用墓地上方作为起始
			start_positions.append(end_global + Vector2(0, -Global.ph(0.3)))
	
	# 暂停游戏等待动画（和召唤动画一致）
	_is_animating = true
	get_tree().paused = true
	
	# 每张牌依次飞入墓地（带轻微延迟错开）
	var fly_nodes := []
	for i in range(start_positions.size()):
		var fly_card = ColorRect.new()
		fly_card.size = Vector2(Global.pw(0.10), Global.pw(0.10) * 1.4)
		fly_card.color = Color(0.4, 0.3, 0.255, 0.9)
		fly_card.z_index = 300 + i
		var start_pos = start_positions[i]
		fly_card.global_position = start_pos - fly_card.size / 2.0
		add_child(fly_card)
		fly_nodes.append(fly_card)
	
	# 刷新手牌/墓地显示（数据已改）
	_refresh_hand_ui()
	_refresh_grave_labels()
	
	var tween = create_tween().set_parallel(false).set_pause_mode(2)
	tween.tween_interval(0.15)
	for i in range(fly_nodes.size()):
		var fly_card = fly_nodes[i]
		var start_pos = start_positions[i]
		# 先轻微上浮再飞向墓地（抛物线效果）
		tween.tween_property(fly_card, "global_position", start_pos - fly_card.size / 2.0 + Vector2(0, -Global.ph(0.06)), 0.12).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tween.tween_property(fly_card, "global_position", end_global - fly_card.size / 2.0, 0.35).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
		tween.parallel().tween_property(fly_card, "modulate", Color(0.4, 0.3, 0.7, 0.0), 0.35)
		tween.tween_interval(0.08)
	
	# 落点闪烁
	tween.tween_callback(func():
		var flash = ColorRect.new()
		flash.size = grave_btn.size * 1.2
		flash.color = Color(0.6, 0.4, 1.0, 0.5)
		flash.z_index = 400
		flash.global_position = grave_btn.global_position - (flash.size - grave_btn.size) / 2.0
		add_child(flash)
		var ft = create_tween().set_pause_mode(2)
		ft.tween_property(flash, "modulate", Color(0.6, 0.4, 1.0, 0.0), 0.25)
		ft.tween_callback(func(): flash.queue_free())
	)
	
	# 动画结束：清理节点，恢复暂停，通知BattleManager执行回调
	tween.tween_interval(0.2)
	tween.tween_callback(func():
		for node in fly_nodes:
			node.queue_free()
		_resume_after_animation()
		print("[动画] 弃牌飞入墓地完成, 回调ID=", callback_id)
		_battle_manager._on_discard_animation_finished(callback_id)
		# ★ 完成第一个弃牌后，若还有排队中的弃牌请求，立即弹出下一个弹窗（此时暂停保持，AI不会乱动）
		_process_next_discard_request()
	)

## 刷新墓地按钮显示
func _refresh_grave_labels() -> void:
	if _battle_manager == null:
		return
	if _player_grave_btn:
		_player_grave_btn.text = "\n" + str(_battle_manager.player_self.grave.size())
	if _enemy_grave_btn:
		_enemy_grave_btn.text = "\n" + str(_battle_manager.player_opponent.grave.size())

## 点击结束回合/结束战斗阶段按钮
func _on_end_turn_btn() -> void:
	if _battle_manager == null:
		return
	
	if _battle_manager.current_phase == BattleManager.Phase.MAIN:
		# 从主要阶段进入战斗阶段
		var result = _battle_manager.do_action("end_main_phase")
		if result.success:
			print("[UI] 进入战斗阶段")
		else:
			print("[UI] 无法进入战斗阶段: ", result.get("reason", ""))
	
	elif _battle_manager.current_phase == BattleManager.Phase.BATTLE:
		# 从战斗阶段进入结束阶段
		var result = _battle_manager.do_action("end_battle_phase")
		if result.success:
			print("[UI] 进入结束阶段")
		else:
			print("[UI] 无法结束战斗阶段: ", result.get("reason", ""))


## 点击手牌卡牌 -> 尝试召唤
## 点击己方场地卡牌 -> 选择攻击者
func _on_player_slot_clicked(slot: int) -> void:
	if _battle_manager == null:
		return
	if _is_dragging_attack:
		return
	# 如果正在选择攻击目标，点击己方场地取消选择
	if _attack_target_mode:
		_attack_target_mode = false
		_selected_attacker_slot = -1
		_refresh_field_ui()
		print("[UI] 取消攻击选择")


## 点击敌方场地卡牌 -> 选择攻击目标
func _on_enemy_slot_clicked(slot: int) -> void:
	if _battle_manager == null:
		return
	
	if not _attack_target_mode or _selected_attacker_slot < 0:
		return
	
	var card = _battle_manager.player_opponent.field[slot]
	if card == null or not card.is_alive():
		return
	
	# 执行攻击
	_execute_attack(_selected_attacker_slot, slot)
	_attack_target_mode = false
	_selected_attacker_slot = -1


## 执行攻击（卡牌 vs 卡牌）
func _execute_attack(attacker_slot: int, target_slot: int) -> void:
	# 播放攻击动画（攻击方飞向目标 → 撞击 → 飞回）
	_play_attack_animation(attacker_slot, target_slot, false)
## 执行直接攻击英雄
func _execute_attack_hero(attacker_slot: int) -> void:
	# 播放攻击英雄动画（攻击方飞向上方 → 撞击 → 飞回）
	_play_attack_animation(attacker_slot, -1, true)


func _debug_print_layout():
	print("\n========== 战斗场景布局调试（运行时实际控件） ==========")
	print("屏幕尺寸: " + str(DisplayServer.window_get_size()))
	print("")
	
	# 遍历所有直接子控件，打印它们的实际位置
	print("--- 所有直接子控件 ---")
	for child in get_children():
		if not (child is Control):
			continue  # 跳过非控件子节点（如 BattleDriver 逻辑节点，无 anchor/offset 属性）
		var cname = child.name if child.name != "" else child.get_class()
		var ar = "anchor[l=" + str(child.anchor_left) + " t=" + str(child.anchor_top) + " r=" + str(child.anchor_right) + " b=" + str(child.anchor_bottom) + "]"
		var off = "offset[l=" + str(child.offset_left) + " t=" + str(child.offset_top) + " r=" + str(child.offset_right) + " b=" + str(child.offset_bottom) + "]"
		
		# 实际像素位置
		var pos_x = child.position.x
		var pos_y = child.position.y
		var size_x = child.size.x
		var size_y = child.size.y
		
		# 如果是Label或Button，获取文字
		var text_info = ""
		if "text" in child and child.text != "":
			text_info = "  text=\"" + child.text + "\""
		elif child.get_class() == "ColorRect":
			text_info = "  color=" + str(child.color)
		
		print("  " + cname + " " + ar + " " + off + "  pos=(" + str(int(pos_x)) + "," + str(int(pos_y)) + ") size=(" + str(int(size_x)) + "x" + str(int(size_y)) + ")" + text_info)
		
		# 递归检查子控件（ScrollContainer里的）
		if child.get_child_count() > 0 and (child.get_class() == "ScrollContainer" or child.get_class() == "HBoxContainer"):
			_print_children_recursive(child, "    ")
	
	print("")
	
	# 检查所有Label和Button的文字
	print("--- 所有文字控件 ---")
	_print_all_labels(self, "")
	
	print("")
	
	# 关键重叠检测：实际像素坐标
	print("--- 关键重叠检测（基于实际像素） ---")
	var rects = []
	for child in get_children():
		if child is ColorRect or child is Panel or child is Button:
			var r = Rect2(child.position.x, child.position.y, child.size.x, child.size.y)
			if r.size.x > 0 and r.size.y > 0:
				rects.append({"name": child.name if child.name != "" else child.get_class(), "rect": r})
	
	# 检测ColorRect之间的重叠
	for i in range(len(rects)):
		for j in range(i+1, len(rects)):
			if rects[i]["rect"].intersects(rects[j]["rect"], true):
				print(" 控件重叠: " + rects[i]["name"] + " ↔ " + rects[j]["name"])
				print("   " + str(rects[i]["rect"]) + "  vs  " + str(rects[j]["rect"]))
	
	print("")
	print("========================================\n")

func _print_children_recursive(node: Node, indent: String):
	for child in node.get_children():
		var cname = child.name if child.name != "" else child.get_class()
		var pos_x = child.position.x
		var pos_y = child.position.y
		var size_x = child.size.x
		var size_y = child.size.y
		var text_info = ""
		if "text" in child and child.text != "":
			text_info = "  text=\"" + child.text + "\""
		print(indent + cname + " pos=(" + str(int(pos_x)) + "," + str(int(pos_y)) + ") size=(" + str(int(size_x)) + "x" + str(int(size_y)) + ")" + text_info)
		if child.get_child_count() > 0:
			_print_children_recursive(child, indent + "  ")

func _print_all_labels(node: Node, indent: String):
	for child in node.get_children():
		if child is Label:
			var cname = child.name if child.name != "" else "Label"
			var pos_x = child.position.x
			var pos_y = child.position.y
			var size_x = child.size.x
			var size_y = child.size.y
			var font_size = 0
			if child.has_theme_font_size_override("font_size"):
				font_size = child.get_theme_font_size("font_size")
			print(indent + cname + " text=\"" + child.text + "\" font_size=" + str(font_size) + " pos=(" + str(int(pos_x)) + "," + str(int(pos_y)) + ") size=(" + str(int(size_x)) + "x" + str(int(size_y)) + ")")
		elif child is Button:
			var cname = child.name if child.name != "" else "Button"
			var pos_x = child.position.x
			var pos_y = child.position.y
			var size_x = child.size.x
			var size_y = child.size.y
			var font_size = 0
			if child.has_theme_font_size_override("font_size"):
				font_size = child.get_theme_font_size("font_size")
			print(indent + cname + " text=\"" + child.text + "\" font_size=" + str(font_size) + " pos=(" + str(int(pos_x)) + "," + str(int(pos_y)) + ") size=(" + str(int(size_x)) + "x" + str(int(size_y)) + ")")
		if child.get_child_count() > 0:
			_print_all_labels(child, indent + "  ")

# ============================================================
# 拖拽召唤系统
# ============================================================
## 全局输入事件处理（拖拽跟踪 + 释放检测）
func _input(event: InputEvent) -> void:
	# === 拖拽召唤处理 ===
	if _is_dragging and _drag_hand_index >= 0:
		_input_handle_drag_summon(event)
		return
	# 还没开始拖拽，但有潜在拖拽起点（手指按下但未移动）
	if not _is_dragging and _drag_hand_index >= 0:
		_input_handle_drag_summon(event)
		return
	
	# === 拖拽攻击处理 ===
	if _drag_attack_press_slot >= 0:
		_input_handle_drag_attack(event)
		return

## 处理拖拽召唤的鼠标移动和释放
func _input_handle_drag_summon(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		# 如果还没正式拖拽，检查位移阈值
		if not _is_dragging and _drag_hand_index >= 0:
			var mouse_global = get_global_mouse_position()
			var dist = mouse_global.distance_to(_drag_start_global)
			if dist < 20.0:
				return  # 还没超过拖拽阈值，保持等待长按
			
			# 超过阈值！正式启动拖拽
			_is_dragging = true
			_long_press_triggered = true  # 拖拽中不触发长按详情
			
			# 创建半透明预览
			_drag_preview = ColorRect.new()
			_drag_preview.color = Color(0.3, 0.5, 0.425, 0.4)
			_drag_preview.size = Vector2(Global.pw(0.25), Global.pw(0.25) * 1.4)
			_drag_preview.z_index = 100
			_drag_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_drag_preview.position = mouse_global - _drag_preview.size / 2.0
			add_child(_drag_preview)
			
			# 复制手牌子Label到预览
			var src_btn = _hand_cards[_drag_hand_index]
			if src_btn:
				for child in src_btn.get_children():
					if child is Label:
						var c = Label.new()
						c.text = child.text
						c.add_theme_font_size_override("font_size", child.get_theme_font_size("font_size"))
						c.horizontal_alignment = child.horizontal_alignment
						c.vertical_alignment = child.vertical_alignment
						c.autowrap_mode = child.autowrap_mode
						match child.name:
							"CostLabel": c.add_theme_color_override("font_color", Color("#f9d371"))
							"AtkLabel": c.add_theme_color_override("font_color", Color("#e74c3c"))
							"HpLabel": c.add_theme_color_override("font_color", Color("#2ecc71"))
							_: c.add_theme_color_override("font_color", Color("#e8d5b7"))
						c.anchor_left = child.anchor_left; c.anchor_top = child.anchor_top
						c.anchor_right = child.anchor_right; c.anchor_bottom = child.anchor_bottom
						c.offset_left = child.offset_left; c.offset_top = child.offset_top
						c.offset_right = child.offset_right; c.offset_bottom = child.offset_bottom
						_drag_preview.add_child(c)
			
			print("[拖拽] 开始拖拽手牌 #" + str(_drag_hand_index))
			return
		
		# 更新预览位置跟随鼠标
		if _drag_preview != null:
			var mouse_pos = get_global_mouse_position()
			_drag_preview.position = mouse_pos - _drag_preview.size / 2.0
		
		# 高亮悬停的空卡槽
		if _battle_manager != null:
			var self_p = _battle_manager.player_self
			var mouse_global = get_global_mouse_position()
			var empty_slots = self_p.get_empty_slots()
			for i in range(_player_slots.size()):
				var slot_btn = _player_slots[i] as Button
				if slot_btn == null:
					continue
				if i in empty_slots:
					var slot_rect = Rect2(slot_btn.global_position, slot_btn.size)
					if slot_rect.has_point(mouse_global):
						# 悬停高亮：绿色边框
						_set_card_highlight(slot_btn, Color(0.2, 1.0, 0.2, 0.9))
					else:
						# 非悬停空位恢复默认（墨线凹槽，无高亮）
						_clear_card_highlight(slot_btn)
	
	elif event is InputEventMouseButton:
		if not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			# 鼠标释放 -> 检测是否丢到空卡槽上
			var dropped_on_slot = -1
			if _battle_manager != null:
				var self_p = _battle_manager.player_self
				var empty_slots = self_p.get_empty_slots()
				var mouse_global = get_global_mouse_position()
				for i in empty_slots:
					if i < _player_slots.size():
						var slot_btn = _player_slots[i] as Button
						if slot_btn != null:
							var slot_rect = Rect2(slot_btn.global_position, slot_btn.size)
							if slot_rect.has_point(mouse_global):
								dropped_on_slot = i
								break
			
			if dropped_on_slot >= 0 and _is_dragging and _drag_hand_index >= 0:
				# 执行召唤！先do_action，成功后记录入场动画信息
				print("[拖拽] 释放到卡槽 #" + str(dropped_on_slot) + "，执行召唤")
				var result = _battle_manager.do_action("summon", {
					"hand_index": _drag_hand_index,
					"slot_index": dropped_on_slot
				})
				if result.success:
					print("[拖拽] 召唤成功！")
					_last_summon_hand_idx = _drag_hand_index
					_last_summon_slot_idx = dropped_on_slot
					_prev_player_field_count = _battle_manager.player_self.get_field_count()
					_play_summon_animation(_drag_hand_index, dropped_on_slot)
				else:
					print("[拖拽] 召唤失败: ", result.get("reason", ""))
			else:
				print("[拖拽] 未释放到有效卡槽，取消")
			
			_cleanup_drag()

## 处理拖拽攻击的鼠标移动和释放
func _input_handle_drag_attack(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var mouse_global = get_global_mouse_position()
		
		# 如果还没开始拖拽攻击，检查是否移动了足够距离
		if not _is_dragging_attack:
			var dist = mouse_global.distance_to(_drag_attack_press_pos)
			if dist < 20.0:
				return  # 还没超过拖拽阈值
			
			# 再次校验阶段和可攻击性（防御性，防止阶段切换）
			var can_attack_check = false
			if _battle_manager != null and _battle_manager.current_phase == BattleManager.Phase.BATTLE and _battle_manager.is_player_turn():
				if _drag_attack_press_slot >= 0 and _drag_attack_press_slot < _battle_manager.player_self.field.size():
					var card = _battle_manager.player_self.field[_drag_attack_press_slot]
					if card != null and card.is_alive() and card.can_attack():
						can_attack_check = true
			if not can_attack_check:
				_cleanup_drag_attack()
				return
			
			# 开始拖拽攻击！
			_is_dragging_attack = true
			_long_press_triggered = true  # 防止长按弹窗
			
			# 创建攻击预览（红色半透明）
			_drag_attack_preview = ColorRect.new()
			_drag_attack_preview.color = Color(0.8, 0.2, 0.17, 0.4)
			_drag_attack_preview.size = Vector2(Global.pw(0.25), Global.pw(0.25) * 1.4)
			_drag_attack_preview.z_index = 100
			_drag_attack_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_drag_attack_preview.position = mouse_global - _drag_attack_preview.size / 2.0
			add_child(_drag_attack_preview)
			
			# 复制卡牌信息到预览
			var src_btn = _player_slots[_drag_attack_press_slot] as Button
			if src_btn:
				for child in src_btn.get_children():
					if child is Label:
						var c = Label.new()
						c.text = child.text
						c.add_theme_font_size_override("font_size", child.get_theme_font_size("font_size"))
						c.horizontal_alignment = child.horizontal_alignment
						c.vertical_alignment = child.vertical_alignment
						c.autowrap_mode = child.autowrap_mode
						match child.name:
							"CostLabel": c.add_theme_color_override("font_color", Color("#f9d371"))
							"AtkLabel": c.add_theme_color_override("font_color", Color("#e74c3c"))
							"HpLabel": c.add_theme_color_override("font_color", Color("#2ecc71"))
							_: c.add_theme_color_override("font_color", Color("#e8d5b7"))
						c.anchor_left = child.anchor_left; c.anchor_top = child.anchor_top
						c.anchor_right = child.anchor_right; c.anchor_bottom = child.anchor_bottom
						c.offset_left = child.offset_left; c.offset_top = child.offset_top
						c.offset_right = child.offset_right; c.offset_bottom = child.offset_bottom
						_drag_attack_preview.add_child(c)
			
			_drag_attack_slot = _drag_attack_press_slot
			print("[拖拽攻击] 开始拖拽，己方场地卡槽 #" + str(_drag_attack_slot))
		
		# 更新预览位置
		if _drag_attack_preview != null:
			_drag_attack_preview.position = mouse_global - _drag_attack_preview.size / 2.0
		
		# 高亮敌方有效目标
		if _battle_manager != null:
			var enemy_p = _battle_manager.player_opponent
			var middle_y = self.size.y * 0.35  # 中间分隔区上沿
			
			for i in range(_enemy_slots.size()):
				var slot_btn = _enemy_slots[i] as Button
				if slot_btn == null:
					continue
				var has_card = i < enemy_p.field.size() and enemy_p.field[i] != null and enemy_p.field[i].is_alive()
				var slot_rect = Rect2(slot_btn.global_position, slot_btn.size)
				var is_hovering = slot_rect.has_point(mouse_global)
				
				if has_card and is_hovering:
					# 可攻击目标：金色高亮边框
					_set_card_highlight(slot_btn, Color(1.0, 0.8, 0.0, 1.0))
				elif not has_card:
					# 空敌方卡槽恢复默认（墨线凹槽，无高亮）
					_clear_card_highlight(slot_btn)
				else:
					# 有卡牌但没悬停，恢复默认样式
					# 由 _refresh_field_ui 管理，但我们简单恢复
					_clear_card_highlight(slot_btn)
			
			# 检查是否悬停在敌方英雄区域（上半屏）
			var is_over_hero = mouse_global.y < middle_y
			# 目前没有UI反馈，后续可以加英雄高亮
	
	elif event is InputEventMouseButton:
		if not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			# 鼠标释放 -> 检测攻击目标
			if _is_dragging_attack and _drag_attack_slot >= 0:
				var mouse_global = get_global_mouse_position()
				var release_dist = mouse_global.distance_to(_drag_attack_press_pos)
				if release_dist < 20.0:
					print("[拖拽攻击] 释放距离过近，取消攻击")
					_cleanup_drag_attack()
					return
				
				var target_enemy_slot = -1
				var middle_y = self.size.y * 0.35
				
				if _battle_manager != null:
					var enemy_p = _battle_manager.player_opponent
					# 检查是否释放到敌方卡牌上
					for i in range(_enemy_slots.size()):
						var slot_btn = _enemy_slots[i] as Button
						if slot_btn == null:
							continue
						var has_card = i < enemy_p.field.size() and enemy_p.field[i] != null and enemy_p.field[i].is_alive()
						if has_card:
							var slot_rect = Rect2(slot_btn.global_position, slot_btn.size)
							if slot_rect.has_point(mouse_global):
								target_enemy_slot = i
								break
				
				if target_enemy_slot >= 0:
					# 攻击敌方卡牌
					print("[拖拽攻击] 攻击敌方卡槽 #" + str(target_enemy_slot))
					_execute_attack(_drag_attack_slot, target_enemy_slot)
				elif mouse_global.y < middle_y:
					# 检查敌方场上是否有活着的卡牌
					var enemy_has_card = false
					if _battle_manager != null:
						var enemy_p = _battle_manager.player_opponent
						for i in range(enemy_p.max_field_size):
							if enemy_p.field[i] != null and enemy_p.field[i].is_alive():
								enemy_has_card = true
								break
					if not enemy_has_card:
						# 敌方场上没有卡牌，才能攻击英雄
						print("[拖拽攻击] 直接攻击英雄")
						_execute_attack_hero(_drag_attack_slot)
					else:
						print("[拖拽攻击] 敌方场上有卡牌，不能攻击英雄，取消")
				else:
					print("[拖拽攻击] 未释放到有效目标，取消")
			
			_cleanup_drag_attack()


## 清理拖拽状态
func _cleanup_drag() -> void:
	# 删除预览
	if _drag_preview != null and _drag_preview.get_parent() != null:
		_drag_preview.queue_free()
	_drag_preview = null
	
	# 重置状态
	_is_dragging = false
	_drag_hand_index = -1
	
	# 恢复所有己方场地卡槽样式
	if _battle_manager != null:
		var self_p = _battle_manager.player_self
		for i in range(_player_slots.size()):
			var slot_btn = _player_slots[i] as Button
			if slot_btn == null:
				continue
			var slot_has_card = i < self_p.field.size() and self_p.field[i] != null and self_p.field[i].is_alive()
			if slot_has_card:
				# 有卡牌的卡槽恢复卡面底图
				_apply_all_states(slot_btn, _make_card_face_style())
				_clear_card_highlight(slot_btn)
			else:
				# 空卡槽恢复墨线凹槽
				_apply_all_states(slot_btn, _make_slot_recess_style())
				_clear_card_highlight(slot_btn)
	
	print("[拖拽] 清理完成")

## 清理拖拽攻击状态
func _cleanup_drag_attack() -> void:
	# 删除预览
	if _drag_attack_preview != null and _drag_attack_preview.get_parent() != null:
		_drag_attack_preview.queue_free()
	_drag_attack_preview = null
	
	# 重置状态
	_is_dragging_attack = false
	_drag_attack_slot = -1
	_drag_attack_press_slot = -1
	_long_press_triggered = false
	_press_slot_index = -1
	
	# 恢复所有敌方卡槽样式
	if _battle_manager != null:
		var enemy_p = _battle_manager.player_opponent
		for i in range(_enemy_slots.size()):
			var slot_btn = _enemy_slots[i] as Button
			if slot_btn == null:
				continue
			var enemy_slot_has_card = i < enemy_p.field.size() and enemy_p.field[i] != null and enemy_p.field[i].is_alive()
			if enemy_slot_has_card:
				_apply_all_states(slot_btn, _make_card_face_style())
				_clear_card_highlight(slot_btn)
			else:
				_apply_all_states(slot_btn, _make_slot_recess_style())
				_clear_card_highlight(slot_btn)
	
	print("[拖拽攻击] 清理完成")



# ============================================================
#  动画系统
# ============================================================

## 入场动画：手牌 → 场地
func _play_summon_animation(hand_idx: int, slot_idx: int) -> void:
	if _battle_manager == null or hand_idx < 0 or hand_idx >= _hand_cards.size() or slot_idx < 0 or slot_idx >= _player_slots.size():
		_refresh_field_ui()
		_refresh_hand_ui()
		return
	_is_animating = true
	get_tree().paused = true
	var hand_btn = _hand_cards[hand_idx] as Button
	var field_btn = _player_slots[slot_idx] as Button
	if hand_btn == null or field_btn == null:
		_resume_after_animation()
		_refresh_field_ui()
		_refresh_hand_ui()
		return
	var start_global = hand_btn.global_position + hand_btn.size / 2.0
	var end_global = field_btn.global_position + field_btn.size / 2.0
	var fly_card = ColorRect.new()
	fly_card.size = hand_btn.size * 0.6
	fly_card.color = Color(0.3, 0.6, 1.0, 0.85)
	fly_card.z_index = 200
	fly_card.global_position = start_global - fly_card.size / 2.0
	add_child(fly_card)
	var glow = ColorRect.new()
	glow.size = fly_card.size + Vector2(8, 8)
	glow.color = Color(0.6, 0.9, 1.0, 0.3)
	glow.z_index = 199
	glow.global_position = fly_card.global_position - Vector2(4, 4)
	add_child(glow)
	_refresh_field_ui()
	_refresh_hand_ui()
	var tween = create_tween().set_parallel(false).set_pause_mode(2)  # 忽略暂停继续播放
	tween.tween_callback(func(): print("[动画] 入场飞行开始"))
	tween.tween_property(fly_card, "global_position", end_global - fly_card.size / 2.0, 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.parallel().tween_property(glow, "global_position", end_global - glow.size / 2.0, 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_callback(func():
		var flash = ColorRect.new()
		flash.size = field_btn.size * 1.3
		flash.color = Color(1.0, 1.0, 1.0, 0.6)
		flash.z_index = 201
		flash.global_position = field_btn.global_position - (flash.size - field_btn.size) / 2.0
		add_child(flash)
		var ft = create_tween().set_pause_mode(2)  # 忽略暂停继续播放
		ft.tween_property(flash, "modulate", Color(1.0, 1.0, 1.0, 0.0), 0.2)
		ft.tween_callback(func(): flash.queue_free())
		fly_card.queue_free()
		glow.queue_free()
		# 玩家召唤入场动画与弃牌弹窗互斥（召唤时不可能弹弃牌窗），直接恢复
		get_tree().paused = false
		_is_animating = false
		print("[动画] 入场完成")
	)

## 攻击动画：攻击方飞向目标 → 撞击 → 飞回
func _play_attack_animation(attacker_slot: int, target_slot: int, is_hero: bool) -> void:
	if _battle_manager == null:
		return
	_is_animating = true
	get_tree().paused = true
	if attacker_slot < 0 or attacker_slot >= _player_slots.size():
		_resume_after_animation()
		return
	var attacker_btn = _player_slots[attacker_slot] as Button
	if attacker_btn == null:
		_resume_after_animation()
		return
	var start_pos = attacker_btn.global_position + attacker_btn.size / 2.0
	var target_pos: Vector2
	if is_hero:
		target_pos = Vector2(self.size.x / 2.0, self.size.y * 0.03)
	else:
		if target_slot < 0 or target_slot >= _enemy_slots.size():
			_resume_after_animation()
			return
		var target_btn = _enemy_slots[target_slot] as Button
		if target_btn == null:
			_resume_after_animation()
			return
		target_pos = target_btn.global_position + target_btn.size / 2.0
	var fly_card = ColorRect.new()
	fly_card.size = attacker_btn.size * 0.7
	fly_card.color = Color(1.0, 0.7, 0.2, 0.9)
	fly_card.z_index = 200
	fly_card.global_position = start_pos - fly_card.size / 2.0
	add_child(fly_card)
	var trail = ColorRect.new()
	trail.size = Vector2(fly_card.size.x * 0.5, 4)
	trail.color = Color(1.0, 0.8, 0.3, 0.4)
	trail.z_index = 199
	add_child(trail)
	print("[动画] 攻击飞行开始 (slot=" + str(attacker_slot) + ")")
	var tween = create_tween().set_parallel(false).set_pause_mode(2)  # 忽略暂停继续播放
	tween.tween_callback(func():
		trail.global_position = fly_card.global_position + Vector2(fly_card.size.x * 0.25, fly_card.size.y / 2.0 - 2)
	)
	tween.tween_property(fly_card, "global_position", target_pos - fly_card.size / 2.0, 0.25).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.parallel().tween_property(trail, "global_position", target_pos - fly_card.size / 2.0 + Vector2(fly_card.size.x * 0.25, fly_card.size.y / 2.0 - 2), 0.25).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(func():
		var hit_flash = ColorRect.new()
		hit_flash.size = Vector2(80, 80)
		hit_flash.color = Color(1.0, 1.0, 0.6, 0.8)
		hit_flash.z_index = 201
		hit_flash.global_position = target_pos - hit_flash.size / 2.0
		add_child(hit_flash)
		var orig_pos = self.position
		var shake = create_tween().set_parallel(true).set_pause_mode(2)  # 忽略暂停继续播放
		shake.tween_property(self, "position", orig_pos + Vector2(4, 0), 0.03)
		shake.tween_property(self, "position", orig_pos + Vector2(-4, 2), 0.06)
		shake.tween_property(self, "position", orig_pos + Vector2(2, -2), 0.09)
		shake.tween_property(self, "position", orig_pos, 0.12)
		var ht = create_tween().set_pause_mode(2)  # 忽略暂停继续播放
		ht.tween_property(hit_flash, "modulate", Color(1.0, 1.0, 0.6, 0.0), 0.15)
		ht.tween_callback(func(): hit_flash.queue_free())
		if is_hero:
			var result = _battle_manager.do_action("attack_hero", {"slot": attacker_slot})
			if result.success:
				print("[UI] 直接攻击英雄成功！")
			else:
				print("[UI] 直接攻击失败: ", result.get("reason", ""))
			_attack_target_mode = false
			_selected_attacker_slot = -1
		else:
			var result = _battle_manager.do_action("attack", {"slot": attacker_slot, "target_slot": target_slot})
			if result.success:
				print("[UI] 攻击成功！")
				var data = result.get("data", {})
				if data.get("attacker_destroyed", false):
					print("[UI] 攻击者被破坏！")
				if data.get("defender_destroyed", false):
					print("[UI] 防御者被破坏！")
			else:
				print("[UI] 攻击失败: ", result.get("reason", ""))
		var fly_back = create_tween().set_parallel(false).set_pause_mode(2)  # 忽略暂停继续播放
		fly_back.tween_property(fly_card, "global_position", start_pos - fly_card.size / 2.0, 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		fly_back.parallel().tween_property(trail, "global_position", start_pos - fly_card.size / 2.0 + Vector2(fly_card.size.x * 0.25, fly_card.size.y / 2.0 - 2), 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		fly_back.tween_callback(func():
			fly_card.queue_free()
			trail.queue_free()
			_resume_after_animation()
			print("[动画] 攻击完成")
			_refresh_field_ui()
			_refresh_hand_ui()
		)
	)

## 敌方AI驱动已迁移至 BattleDriver（battle_core/BattleDriver.gd，横竖屏共用）
## 本场景只保留表现层：以下回调由驱动器信号触发，播完动画后通知驱动器继续

## 回合结束效果已发完（数据层）：本场景无回合结束视角动画，直接推进弃牌/切回合
func _on_end_phase_effects_pending_discard(_need_discard: int) -> void:
	if _battle_manager:
		_battle_manager.proceed_to_discard_after_end_effects()

## 敌方召唤入场：由 BattleDriver.enemy_summon_animation_requested 触发
func _on_driver_enemy_summon(slot_idx: int) -> void:
	_play_enemy_summon_animation(slot_idx)

## 敌方攻击：由 BattleDriver.enemy_attack_animation_requested 触发
func _on_driver_enemy_attack(attacker_slot: int, target_slot: int, is_hero: bool) -> void:
	_play_enemy_attack_animation(attacker_slot, target_slot, is_hero)

## 敌方动画结束：恢复游戏树并通知驱动器推进回合
func _resume_after_enemy_animation() -> void:
	_resume_after_animation()
	if _battle_driver:
		_battle_driver.report_animation_done()

## 敌方入场动画：卡牌从上方飞入敌方场地卡槽
func _play_enemy_summon_animation(slot_idx: int) -> void:
	if _battle_manager == null or slot_idx < 0 or slot_idx >= _enemy_slots.size():
		_refresh_field_ui()
		_resume_after_enemy_animation()
		return
	_is_animating = true
	get_tree().paused = true
	var field_btn = _enemy_slots[slot_idx] as Button
	if field_btn == null:
		_resume_after_enemy_animation()
		_refresh_field_ui()
		return
	# 起始位置：屏幕上方中央
	var start_global = Vector2(self.size.x / 2.0, -Global.pw(0.15))
	var end_global = field_btn.global_position + field_btn.size / 2.0
	var fly_card = ColorRect.new()
	fly_card.size = Vector2(Global.pw(0.15), Global.pw(0.15) * 1.4)
	fly_card.color = Color(1.0, 0.3, 0.3, 0.85)
	fly_card.z_index = 200
	fly_card.global_position = start_global - fly_card.size / 2.0
	add_child(fly_card)
	var glow = ColorRect.new()
	glow.size = fly_card.size + Vector2(8, 8)
	glow.color = Color(1.0, 0.6, 0.6, 0.3)
	glow.z_index = 199
	glow.global_position = fly_card.global_position - Vector2(4, 4)
	add_child(glow)
	_refresh_field_ui()
	var tween = create_tween().set_parallel(false).set_pause_mode(2)  # 忽略暂停继续播放
	tween.tween_callback(func(): print("[动画] 敌方入场飞行开始"))
	tween.tween_property(fly_card, "global_position", end_global - fly_card.size / 2.0, 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.parallel().tween_property(glow, "global_position", end_global - glow.size / 2.0, 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_callback(func():
		var flash = ColorRect.new()
		flash.size = field_btn.size * 1.3
		flash.color = Color(1.0, 0.6, 0.6, 0.6)
		flash.z_index = 201
		flash.global_position = field_btn.global_position - (flash.size - field_btn.size) / 2.0
		add_child(flash)
		var ft = create_tween().set_pause_mode(2)  # 忽略暂停继续播放
		ft.tween_property(flash, "modulate", Color(1.0, 0.6, 0.6, 0.0), 0.2)
		ft.tween_callback(func(): flash.queue_free())
		fly_card.queue_free()
		glow.queue_free()
		_resume_after_enemy_animation()
		print("[动画] 敌方入场完成")
	)

## 敌方攻击动画：从敌方场地飞向己方目标，撞击后飞回
func _play_enemy_attack_animation(attacker_slot: int, target_slot: int, is_hero: bool) -> void:
	if _battle_manager == null:
		_resume_after_enemy_animation()
		return
	_is_animating = true
	get_tree().paused = true
	if attacker_slot < 0 or attacker_slot >= _enemy_slots.size():
		_resume_after_enemy_animation()
		return
	var attacker_btn = _enemy_slots[attacker_slot] as Button
	if attacker_btn == null:
		_resume_after_enemy_animation()
		return
	var start_pos = attacker_btn.global_position + attacker_btn.size / 2.0
	var target_pos: Vector2
	if is_hero:
		target_pos = Vector2(self.size.x / 2.0, self.size.y * 0.94)
	else:
		if target_slot < 0 or target_slot >= _player_slots.size():
			_resume_after_enemy_animation()
			return
		var target_btn = _player_slots[target_slot] as Button
		if target_btn == null:
			_resume_after_enemy_animation()
			return
		target_pos = target_btn.global_position + target_btn.size / 2.0
	var fly_card = ColorRect.new()
	fly_card.size = attacker_btn.size * 0.7
	fly_card.color = Color(1.0, 0.4, 0.2, 0.9)
	fly_card.z_index = 200
	fly_card.global_position = start_pos - fly_card.size / 2.0
	add_child(fly_card)
	var trail = ColorRect.new()
	trail.size = Vector2(fly_card.size.x * 0.5, 4)
	trail.color = Color(1.0, 0.5, 0.2, 0.4)
	trail.z_index = 199
	add_child(trail)
	print("[动画] 敌方攻击飞行开始 (slot=" + str(attacker_slot) + ")")
	var tween = create_tween().set_parallel(false).set_pause_mode(2)  # 忽略暂停继续播放
	tween.tween_callback(func():
		trail.global_position = fly_card.global_position + Vector2(fly_card.size.x * 0.25, fly_card.size.y / 2.0 - 2)
	)
	tween.tween_property(fly_card, "global_position", target_pos - fly_card.size / 2.0, 0.25).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.parallel().tween_property(trail, "global_position", target_pos - fly_card.size / 2.0 + Vector2(fly_card.size.x * 0.25, fly_card.size.y / 2.0 - 2), 0.25).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(func():
		var hit_flash = ColorRect.new()
		hit_flash.size = Vector2(80, 80)
		hit_flash.color = Color(1.0, 0.6, 0.3, 0.8)
		hit_flash.z_index = 201
		hit_flash.global_position = target_pos - hit_flash.size / 2.0
		add_child(hit_flash)
		var orig_pos = self.position
		var shake = create_tween().set_parallel(true).set_pause_mode(2)  # 忽略暂停继续播放
		shake.tween_property(self, "position", orig_pos + Vector2(-4, 0), 0.03)
		shake.tween_property(self, "position", orig_pos + Vector2(4, 2), 0.06)
		shake.tween_property(self, "position", orig_pos + Vector2(-2, -2), 0.09)
		shake.tween_property(self, "position", orig_pos, 0.12)
		var ht = create_tween().set_pause_mode(2)  # 忽略暂停继续播放
		ht.tween_property(hit_flash, "modulate", Color(1.0, 0.6, 0.3, 0.0), 0.15)
		ht.tween_callback(func(): hit_flash.queue_free())
		# 撞击瞬间：通知驱动器结算伤害（由驱动器调用 BattleManager._execute_pending_enemy_attack）
		if _battle_driver:
			_battle_driver.report_attack_impact()
		# 飞回
		var fly_back = create_tween().set_parallel(false).set_pause_mode(2)  # 忽略暂停继续播放
		fly_back.tween_property(fly_card, "global_position", start_pos - fly_card.size / 2.0, 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		fly_back.parallel().tween_property(trail, "global_position", start_pos - fly_card.size / 2.0 + Vector2(fly_card.size.x * 0.25, fly_card.size.y / 2.0 - 2), 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		fly_back.tween_callback(func():
			fly_card.queue_free()
			trail.queue_free()
			_resume_after_enemy_animation()
			print("[动画] 敌方攻击完成")
			_refresh_field_ui()
			_refresh_hand_ui()
		)
	)
# ===== PvP对战初始化 =====
# func _check_pvp_setup() -> void:
# 	"""检查是否是PvP对战，并初始化相关设置"""
# 	# 从场景树中查找NetworkBattleManager
# 	var mgr = get_node_or_null("/root/NetworkBattleManager")
# 	if mgr == null:
# 		# 也可能挂在当前场景下
# 		mgr = get_node_or_null("../NetworkBattleManager")
# 	if mgr == null:
# 		# 搜索整个场景树
# 		for child in get_tree().root.get_children():
# 			if child is NetworkBattleManager:
# 				mgr = child
# 				break
# 	
# 	if mgr != null:
# 		_is_pvp_battle = true
# 		_network_mgr = mgr
# 		print("[战斗] PvP对战模式已激活")
# 		
# 		# 连接网络管理器的信号
# 		_network_mgr.opponent_action_received.connect(_on_opponent_action_received)
# 		_network_mgr.turn_timer_updated.connect(_on_pvp_turn_timer_updated)
# 		_network_mgr.turn_timeout.connect(_on_pvp_turn_timeout)
# 		
# 		# 设置倒计时标签可见
# 		if _turn_timer_label:
# 			_turn_timer_label.text = "等待对手..."
# 			_turn_timer_label.add_theme_color_override("font_color", Color("#f9d371"))
# 	else:
# 		_is_pvp_battle = false
# 		print("[战斗] 单人模式继续")
# 
# 
# func _on_pvp_turn_timer_updated(time_left: int) -> void:
# 	"""PvP回合倒计时更新"""
# 	if _turn_timer_label:
# 		var seconds = time_left / 1000
# 		var text = "⏱ " + str(seconds) + "s"
# 		_turn_timer_label.text = text
# 		if seconds < 10:
# 			_turn_timer_label.add_theme_color_override("font_color", Color("#e74c3c"))
# 		elif seconds < 30:
# 			_turn_timer_label.add_theme_color_override("font_color", Color("#f9d371"))
# 
# 
# func _on_pvp_turn_timeout() -> void:
# 	"""PvP回合超时处理"""
# 	print("[战斗] PvP回合超时，强制结束回合")
# 	if _turn_timer_label:
# 		_turn_timer_label.text = "⏰ 超时!"
# 		_turn_timer_label.add_theme_color_override("font_color", Color("#e74c3c"))
# 	_on_end_turn_btn()
# 
# 
# func _on_opponent_action_received(action: Dictionary) -> void:
# 	"""收到对手操作后的处理"""
# 	print("[战斗] 收到对手操作: ", action)
# 	if _battle_manager:
# 		_battle_manager.on_opponent_action(action)
