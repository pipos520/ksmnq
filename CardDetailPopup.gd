extends CanvasLayer
class_name CardDetailPopup

# 卡牌详情弹窗 —— 像卡牌图鉴一样完整展示所有信息

var _card: BattleCard = null
var _close_callback: Callable = Callable()
var _mode: String = "view"  # "view", "hand_summon", "field_attack"
var _source_hand_idx: int = -1
var _source_slot_idx: int = -1
var _battle_manager_ref = null
var _on_summon_clicked: Callable = Callable()
var _on_attack_clicked: Callable = Callable()

# 成员变量引用（避免get_node_or_null路径问题）
var _name_lbl: Label
var _type_lbl: Label
var _star_lbl: Label
var _qual_lbl: Label
var _atk_val: Label
var _hp_val: Label
var _cost_val: Label
var _fields_lbl: Label
var _desc_lbl: Label
var _effects_lbl: Label
var _runtime_lbl: Label
var _action_btn_container: HBoxContainer


func _ready():
	layer = 200
	process_mode = PROCESS_MODE_ALWAYS
	
	# 半透明遮罩（点击关闭）
	var overlay = ColorRect.new()
	overlay.name = "Overlay"
	overlay.color = Color(0.0, 0.0, 0.0, 0.7)
	overlay.anchor_left = 0.0; overlay.anchor_top = 0.0
	overlay.anchor_right = 1.0; overlay.anchor_bottom = 1.0
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.gui_input.connect(_on_overlay_input)
	add_child(overlay)
	
	# ===== 弹窗面板（居中，宽80%，高70%） =====
	var panel = Panel.new()
	panel.name = "DetailPanel"
	var panel_s = StyleBoxFlat.new()
	panel_s.bg_color = Color(0.06, 0.04, 0.12)
	panel_s.border_width_left = 3; panel_s.border_width_right = 3
	panel_s.border_width_top = 3; panel_s.border_width_bottom = 3
	panel_s.border_color = Color(0.6, 0.4, 0.8, 0.9)
	panel_s.corner_radius_top_left = 16; panel_s.corner_radius_top_right = 16
	panel_s.corner_radius_bottom_left = 16; panel_s.corner_radius_bottom_right = 16
	panel.add_theme_stylebox_override("panel", panel_s)
	
	panel.anchor_left = 0.5; panel.anchor_top = 0.5
	panel.anchor_right = 0.5; panel.anchor_bottom = 0.5
	panel.offset_left = -Global.pw(0.38)
	panel.offset_right = Global.pw(0.38)
	panel.offset_top = -Global.ph(0.35)
	panel.offset_bottom = Global.ph(0.35)
	add_child(panel)
	
	# ===== 内容用ScrollContainer =====
	var scroll = ScrollContainer.new()
	scroll.anchor_left = 0.0; scroll.anchor_top = 0.0
	scroll.anchor_right = 1.0; scroll.anchor_bottom = 1.0
	scroll.offset_left = Global.pw(0.03)
	scroll.offset_top = Global.ph(0.02)
	scroll.offset_right = Global.pw(-0.03)
	scroll.offset_bottom = Global.ph(-0.02)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	
	# VBoxContainer
	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
	scroll.add_child(vbox)
	
	# ===== 1. 卡牌名称 =====
	_name_lbl = Label.new()
	_name_lbl.add_theme_font_size_override("font_size", 80)
	_name_lbl.add_theme_constant_override("shadow_offset_x", 2)
	_name_lbl.add_theme_constant_override("shadow_offset_y", 2)
	_name_lbl.add_theme_color_override("font_shadow_color", Color("#000000"))
	_name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_lbl.custom_minimum_size = Vector2(0, Global.ph(0.08))
	vbox.add_child(_name_lbl)
	
	# ===== 2. 类型/星级/品质+属性 =====
	var type_row = HBoxContainer.new()
	type_row.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
	type_row.custom_minimum_size = Vector2(0, Global.ph(0.04))
	
	_type_lbl = Label.new()
	_type_lbl.add_theme_font_size_override("font_size", 35)
	_type_lbl.add_theme_color_override("font_color", Color("#a0a0b0"))
	_type_lbl.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
	_type_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	type_row.add_child(_type_lbl)
	
	_star_lbl = Label.new()
	_star_lbl.add_theme_font_size_override("font_size", 35)
	_star_lbl.add_theme_color_override("font_color", Color("#ffd54f"))
	_star_lbl.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
	_star_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_star_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	type_row.add_child(_star_lbl)
	
	_qual_lbl = Label.new()
	_qual_lbl.add_theme_font_size_override("font_size", 35)
	_qual_lbl.add_theme_color_override("font_color", Color("#a0a0b0"))
	_qual_lbl.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
	_qual_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_qual_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	type_row.add_child(_qual_lbl)
	
	vbox.add_child(type_row)
	
	# 分隔线
	var sep1 = ColorRect.new()
	sep1.color = Color(0.4, 0.3, 0.5, 0.4)
	sep1.custom_minimum_size = Vector2(0, 2)
	sep1.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
	vbox.add_child(sep1)
	
	# ===== 3. 属性面板：ATK/HP/费用 =====
	var stats_bg = ColorRect.new()
	stats_bg.color = Color(0.10, 0.08, 0.18, 0.5)
	stats_bg.custom_minimum_size = Vector2(0, Global.ph(0.12))
	stats_bg.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
	vbox.add_child(stats_bg)
	
	var stat_hbox = HBoxContainer.new()
	stat_hbox.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
	stat_hbox.size_flags_vertical = Control.SIZE_EXPAND | Control.SIZE_FILL
	stats_bg.add_child(stat_hbox)
	
	# ATK
	var atk_vbox = VBoxContainer.new()
	atk_vbox.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
	atk_vbox.size_flags_vertical = Control.SIZE_EXPAND | Control.SIZE_FILL
	stat_hbox.add_child(atk_vbox)
	
	var atk_title = Label.new()
	atk_title.text = "⚔️ 攻击力"
	atk_title.add_theme_font_size_override("font_size", 28)
	atk_title.add_theme_color_override("font_color", Color(0.8, 0.5, 0.5, 0.7))
	atk_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	atk_vbox.add_child(atk_title)
	
	_atk_val = Label.new()
	_atk_val.add_theme_font_size_override("font_size", 70)
	_atk_val.add_theme_color_override("font_color", Color("#e74c3c"))
	_atk_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_atk_val.size_flags_vertical = Control.SIZE_EXPAND | Control.SIZE_FILL
	atk_vbox.add_child(_atk_val)
	
	# HP
	var hp_vbox = VBoxContainer.new()
	hp_vbox.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
	hp_vbox.size_flags_vertical = Control.SIZE_EXPAND | Control.SIZE_FILL
	stat_hbox.add_child(hp_vbox)
	
	var hp_title = Label.new()
	hp_title.text = "❤️ 生命值"
	hp_title.add_theme_font_size_override("font_size", 28)
	hp_title.add_theme_color_override("font_color", Color(0.5, 0.8, 0.5, 0.7))
	hp_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp_vbox.add_child(hp_title)
	
	_hp_val = Label.new()
	_hp_val.add_theme_font_size_override("font_size", 70)
	_hp_val.add_theme_color_override("font_color", Color("#2ecc71"))
	_hp_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_val.size_flags_vertical = Control.SIZE_EXPAND | Control.SIZE_FILL
	hp_vbox.add_child(_hp_val)
	
	# 费用
	var cost_vbox = VBoxContainer.new()
	cost_vbox.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
	cost_vbox.size_flags_vertical = Control.SIZE_EXPAND | Control.SIZE_FILL
	stat_hbox.add_child(cost_vbox)
	
	var cost_title = Label.new()
	cost_title.text = "⚡ 费用"
	cost_title.add_theme_font_size_override("font_size", 28)
	cost_title.add_theme_color_override("font_color", Color(0.8, 0.7, 0.4, 0.7))
	cost_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost_vbox.add_child(cost_title)
	
	_cost_val = Label.new()
	_cost_val.add_theme_font_size_override("font_size", 70)
	_cost_val.add_theme_color_override("font_color", Color("#f9d371"))
	_cost_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cost_val.size_flags_vertical = Control.SIZE_EXPAND | Control.SIZE_FILL
	cost_vbox.add_child(_cost_val)
	
	# 分隔线
	var sep2 = ColorRect.new()
	sep2.color = Color(0.4, 0.3, 0.5, 0.3)
	sep2.custom_minimum_size = Vector2(0, 1)
	sep2.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
	vbox.add_child(sep2)
	
	# ===== 4. 字段 =====
	_fields_lbl = Label.new()
	_fields_lbl.add_theme_font_size_override("font_size", 32)
	_fields_lbl.add_theme_color_override("font_color", Color("#8a7b9a"))
	_fields_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_fields_lbl.custom_minimum_size = Vector2(0, Global.ph(0.04))
	_fields_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	vbox.add_child(_fields_lbl)
	
	# ===== 5. 描述 =====
	_desc_lbl = Label.new()
	_desc_lbl.add_theme_font_size_override("font_size", 40)
	_desc_lbl.add_theme_color_override("font_color", Color("#c0b0d0"))
	_desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_lbl.custom_minimum_size = Vector2(0, Global.ph(0.06))
	_desc_lbl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	vbox.add_child(_desc_lbl)
	
	# ===== 6. 效果列表 =====
	_effects_lbl = Label.new()
	_effects_lbl.add_theme_font_size_override("font_size", 34)
	_effects_lbl.add_theme_color_override("font_color", Color("#80b0ff"))
	_effects_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_effects_lbl.size_flags_vertical = Control.SIZE_EXPAND | Control.SIZE_FILL
	_effects_lbl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	vbox.add_child(_effects_lbl)
	
	# ===== 7. 运行时状态 =====
	_runtime_lbl = Label.new()
	_runtime_lbl.add_theme_font_size_override("font_size", 30)
	_runtime_lbl.add_theme_color_override("font_color", Color("#7a9a8a"))
	_runtime_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_runtime_lbl.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_runtime_lbl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	vbox.add_child(_runtime_lbl)
	
	# ===== 8. 操作按钮区 =====
	_action_btn_container = HBoxContainer.new()
	_action_btn_container.name = "ActionBtnContainer"
	_action_btn_container.custom_minimum_size = Vector2(0, Global.ph(0.08))
	_action_btn_container.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
	_action_btn_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_action_btn_container.add_theme_constant_override("separation", Global.pw(0.04))
	vbox.add_child(_action_btn_container)
	
	# 默认隐藏
	hide()


## 显示卡牌详情
## mode: "view"=纯查看, "hand_summon"=手牌+召唤按钮, "field_attack"=己方场上+攻击按钮
func show_card(card: BattleCard, mode: String = "view", battle_manager = null, hand_idx: int = -1, slot_idx: int = -1, on_summon: Callable = Callable(), on_attack: Callable = Callable()) -> void:
	_card = card
	_mode = mode
	_battle_manager_ref = battle_manager
	_source_hand_idx = hand_idx
	_source_slot_idx = slot_idx
	_on_summon_clicked = on_summon
	_on_attack_clicked = on_attack
	_close_callback = Callable()
	if card == null:
		return
	
	# 名称 + 品质着色
	_name_lbl.text = card.get_display_name()
	_name_lbl.add_theme_color_override("font_color", Global.get_quality_color(card.quality))
	
	# 纹路触发器（从效果中提取）
	var trigger_text = ""
	if card.effects.size() > 0:
		var first_eff = card.effects[0]
		var trigger_id = "TR01"
		if first_eff is String and first_eff.begins_with("TR"):
			trigger_id = first_eff
		elif first_eff is Dictionary and first_eff.has("trigger"):
			trigger_id = first_eff.get("trigger", "TR01")
		match trigger_id:
			"TR01": trigger_text = "⚡ 召唤时发动"
			# "TR02": trigger_text = "⚡ 特殊召唤时发动"  # 已注释
			# "TR03": trigger_text = "⚡ 从墓地特召时发动"  # 已注释
			# "TR04": trigger_text = "💥 被战斗破坏时发动"  # 已注释
			"TR06": trigger_text = "💀 送墓时发动"
			# "TR07": trigger_text = "🌀 被除外时发动"  # 已注释
			# "TR08": trigger_text = "💨 离场时发动"  # 已注释
			"TR09": trigger_text = "⚔️ 攻击时发动"
			"TR10": trigger_text = "🛡️ 被攻击时发动"
			"TR11": trigger_text = "💢 战斗伤害时发动"
			"TR12": trigger_text = "🔁 己方回合开始时"
			"TR13": trigger_text = "🔁 对方回合开始时"
			"TR14": trigger_text = "🔁 己方回合结束时"
			"TR15": trigger_text = "🔁 对方回合结束时"
			"TR16": trigger_text = "🔄 对方发动效果时"
			"TR17": trigger_text = "🔄 对方召唤时"
			_: trigger_text = "⚡ 召唤时发动"
	_type_lbl.text = trigger_text
	
	# 星级
	if card.star > 0:
		_star_lbl.text = "★".repeat(card.star) + "☆".repeat(5 - card.star)
	else:
		_star_lbl.text = ""
	
	# 品质+元素
	var element_icon = ""
	match card.element:
		"火": element_icon = "🔥"
		"水": element_icon = "💧"
		"风": element_icon = "🌪️"
		"地": element_icon = "⛰️"
		"光": element_icon = "✨"
		"暗": element_icon = "🌑"
	_qual_lbl.text = "[" + card.quality + "] " + element_icon + " " + card.element
	
	# ATK值
	_atk_val.text = str(card.current_atk)
	if card.temp_atk_buff != 0:
		var diff = card.current_atk - card.base_atk
		var sign = "+" if diff >= 0 else ""
		_atk_val.text += " (" + sign + str(diff) + ")"
		_atk_val.add_theme_color_override("font_color", Color("#e67e22") if diff > 0 else Color("#e74c3c"))
	else:
		_atk_val.add_theme_color_override("font_color", Color("#e74c3c"))
	
	# HP值
	_hp_val.text = str(card.current_hp)
	if card.current_hp != card.base_hp:
		_hp_val.text += " / " + str(card.max_hp)
		_hp_val.add_theme_color_override("font_color", Color("#e67e22") if card.current_hp < card.base_hp else Color("#2ecc71"))
	else:
		_hp_val.add_theme_color_override("font_color", Color("#2ecc71"))
	
	# 费用
	_cost_val.text = str(card.base_cost)
	
	# 字段
	if card.fields.size() > 0:
		_fields_lbl.text = "📖 " + " | ".join(card.fields)
	else:
		_fields_lbl.text = ""
	
	# 描述
	_desc_lbl.text = card.desc if card.desc != "" else "（暂无描述）"
	
	# 效果列表
	if card.effects.size() > 0:
		var effect_text = ""
		for eff in card.effects:
			if eff is Dictionary:
				# 新格式字典，可能有自动生成的 desc 字段
				var desc = Global.get_effect_desc(eff)
				if desc != "":
					effect_text += "• " + desc + "\n"
				else:
					effect_text += "• " + str(eff) + "\n"
			elif eff is String:
				# 字符串ID数组，如 ["TR12", "A03", "T04"]
				var comp_name = ""
				if eff.begins_with("TR"):
					for t in Global.circuit_triggers:
						if t.id == eff:
							comp_name = t.name
							break
				elif eff.begins_with("A"):
					for a in Global.circuit_actions:
						if a.id == eff:
							comp_name = a.name
							break
				elif eff.begins_with("T"):
					for t in Global.circuit_targets:
						if t.id == eff:
							comp_name = t.name
							break
				elif eff.begins_with("C"):
					for c in Global.circuit_conditions:
						if c.id == eff:
							comp_name = c.name
							break
				elif eff.begins_with("CO"):
					for co in Global.circuit_constraints:
						if co.id == eff:
							comp_name = co.name
							break
				if comp_name == "":
					comp_name = eff
				effect_text += "• " + comp_name + "\n"
		_effects_lbl.text = effect_text
	else:
		_effects_lbl.text = ""
	
	# 辅材
	var aux_text := ""
	if card.aux_items.size() > 0:
		aux_text = "\n🧪 辅材：\n"
		for aux in card.aux_items:
			var aux_name = aux.get("name", "未知辅材")
			var aux_eff = _describe_aux_effect(aux)
			aux_text += "• " + aux_name + (("　" + aux_eff) if aux_eff != "" else "") + "\n"
		if _effects_lbl.text != "":
			_effects_lbl.text += "\n"
		_effects_lbl.text += aux_text
	
	# 运行时状态
	var rt_text = ""
	if mode == "view":
		# 查看模式：不显示运行时状态
		rt_text = ""
	elif card.is_on_field:
		rt_text += "🟢 已在场上 | 位置: " + str(card.slot_index + 1)
		if card.is_turned:
			rt_text += " | 守备表示"
		else:
			rt_text += " | 攻击表示"
		rt_text += "\n"
		if card.has_attacked:
			rt_text += "⚔️ 已攻击过\n"
		else:
			rt_text += "⚔️ 可攻击\n"
		if card.cannot_attack:
			rt_text += "🚫 不能攻击\n"
		if card.is_frozen:
			rt_text += "❄️ 冰冻中\n"
		if card.temp_atk_buff != 0:
			rt_text += "⚡ 临时攻击力: " + ("+" if card.temp_atk_buff > 0 else "") + str(card.temp_atk_buff) + "\n"
		if card.temp_hp_buff != 0:
			rt_text += "💚 临时生命值: " + ("+" if card.temp_hp_buff > 0 else "") + str(card.temp_hp_buff) + "\n"
		if card.atk_buff_permanent != 0:
			rt_text += "🔒 永久攻击力: " + ("+" if card.atk_buff_permanent > 0 else "") + str(card.atk_buff_permanent) + "\n"
		if card.hp_buff_permanent != 0:
			rt_text += "🔒 永久生命值: " + ("+" if card.hp_buff_permanent > 0 else "") + str(card.hp_buff_permanent) + "\n"
	else:
		rt_text += "📋 在手牌中"
	_runtime_lbl.text = rt_text
	
	# 构建操作按钮
	_build_action_buttons()
	
	show()


## 根据模式构建操作按钮
func _build_action_buttons() -> void:
	# 清除旧按钮
	for child in _action_btn_container.get_children():
		child.queue_free()
	
	if _mode == "view":
		# 纯查看模式：只显示关闭提示
		var hint = Label.new()
		hint.text = "点击任意位置关闭"
		hint.add_theme_font_size_override("font_size", 30)
		hint.add_theme_color_override("font_color", Color(0.5, 0.4, 0.6, 0.6))
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
		_action_btn_container.add_child(hint)
		return
	
	if _mode == "hand_summon":
		# 手牌模式：召唤按钮
		var can_summon = false
		if _battle_manager_ref != null:
			var bm = _battle_manager_ref
			if bm.current_phase == BattleManager.Phase.MAIN and bm.is_player_turn() and bm.player_self.get_empty_slots().size() > 0:
				can_summon = true
		_add_action_button("⚡ 召唤到场地", Color("#4fc3f7"), can_summon, _on_summon_clicked)
	
	elif _mode == "field_attack":
		# 己方场上模式：攻击按钮
		var can_attack = false
		if _battle_manager_ref != null:
			var bm = _battle_manager_ref
			if bm.current_phase == BattleManager.Phase.BATTLE and bm.is_player_turn():
				if _card != null and _card.is_alive() and _card.can_attack():
					can_attack = true
		_add_action_button("⚔️ 攻击", Color("#e74c3c"), can_attack, _on_attack_clicked)
	
	# 关闭按钮
	var close_btn = Button.new()
	close_btn.text = "✕ 关闭"
	close_btn.add_theme_font_size_override("font_size", 35)
	var cs = StyleBoxFlat.new()
	cs.bg_color = Color(0.15, 0.10, 0.18)
	cs.border_width_left = 2; cs.border_width_right = 2
	cs.border_width_top = 2; cs.border_width_bottom = 2
	cs.border_color = Color(0.4, 0.3, 0.5, 0.6)
	cs.corner_radius_top_left = 8; cs.corner_radius_top_right = 8
	cs.corner_radius_bottom_left = 8; cs.corner_radius_bottom_right = 8
	cs.content_margin_left = 15; cs.content_margin_right = 15
	close_btn.add_theme_stylebox_override("normal", cs)
	close_btn.add_theme_stylebox_override("hover", cs)
	close_btn.add_theme_stylebox_override("pressed", cs)
	close_btn.add_theme_color_override("font_color", Color("#a0a0b0"))
	close_btn.pressed.connect(close)
	_action_btn_container.add_child(close_btn)


func _add_action_button(text: String, color: Color, enabled: bool, callback: Callable) -> void:
	var btn = Button.new()
	btn.text = text
	btn.disabled = not enabled
	btn.add_theme_font_size_override("font_size", 40)
	var s = StyleBoxFlat.new()
	if enabled:
		s.bg_color = Color(color.r * 0.3, color.g * 0.3, color.b * 0.3, 0.6)
		s.border_color = color
	else:
		s.bg_color = Color(0.15, 0.10, 0.18)
		s.border_color = Color(0.3, 0.2, 0.3, 0.5)
	s.border_width_left = 2; s.border_width_right = 2
	s.border_width_top = 2; s.border_width_bottom = 2
	s.corner_radius_top_left = 8; s.corner_radius_top_right = 8
	s.corner_radius_bottom_left = 8; s.corner_radius_bottom_right = 8
	s.content_margin_left = 15; s.content_margin_right = 15
	btn.add_theme_stylebox_override("normal", s)
	btn.add_theme_stylebox_override("hover", s)
	btn.add_theme_stylebox_override("pressed", s)
	btn.add_theme_color_override("font_color", color if enabled else Color("#666666"))
	if enabled and callback.is_valid():
		btn.pressed.connect(callback)
	_action_btn_container.add_child(btn)


func close() -> void:
	hide()
	if _close_callback.is_valid():
		_close_callback.call()
	queue_free()


func _on_overlay_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close()


## 根据效果数据自动生成中文描述
func _generate_effect_desc(eff: Dictionary) -> String:
	var etype = eff.get("type", "")
	var eeffect = eff.get("effect", "")
	var value = eff.get("value", 0)
	var target = eff.get("target", "")
	var duration = eff.get("duration", "")
	
	# 目标中文名
	var target_name = ""
	match target:
		"self", "self_single": target_name = "自身"
		"enemy_single", "enemy": target_name = "敌方单体"
		"enemy_all", "all_enemies", "enemy_hero": target_name = "敌方"
		"friendly", "ally": target_name = "己方单体"
		"hero": target_name = "己方英雄"
		_: target_name = target
	
	# 效果中文名
	match eeffect:
		"damage": return "对" + target_name + "造成 " + str(value) + " 点伤害"
		"heal", "heal_self": return "恢复 " + str(value) + " 点生命值"
		"draw": return "抽 " + str(value) + " 张牌"
		"summon": return "召唤1个衍生物"
		"atk_up": return "攻击力+" + str(value) + ("（永久）" if duration == "permanent" else "")
		"hp_up": return "生命值+" + str(value) + ("（永久）" if duration == "permanent" else "")
		"debuff": return "攻击力-" + str(value)
		_: return "效果: " + eeffect + " 值:" + str(value)

# ============================================================
# 辅材描述辅助
# ============================================================

func _describe_aux_effect(aux: Dictionary) -> String:
	var effect = aux.get("effect", {})
	if effect.is_empty():
		return ""
	var parts = []
	if effect.has("atk_bonus"):
		parts.append("攻击+" + str(effect["atk_bonus"]))
	if effect.has("hp_bonus"):
		parts.append("生命+" + str(effect["hp_bonus"]))
	if effect.has("energy_reduce"):
		parts.append("费用-" + str(effect["energy_reduce"]))
	if effect.has("element"):
		parts.append("属性→" + str(effect["element"]))
	if effect.has("element_power"):
		parts.append("元素威力+" + str(effect["element_power"] * 100) + "%")
	if effect.has("shield"):
		parts.append("护盾" + str(effect["shield"]))
	if effect.get("indestructible_once", false):
		parts.append("免毁一次")
	if effect.get("haste", false):
		parts.append("急速")
	if effect.has("extra_trigger"):
		parts.append("额外触发+" + str(effect["extra_trigger"]))
	if effect.has("draw_on_summon"):
		parts.append("召唤抽" + str(effect["draw_on_summon"]))
	if effect.has("damage_reduce"):
		parts.append("减伤" + str(effect["damage_reduce"]))
	if effect.get("damage_halve", false):
		parts.append("伤害减半")
	if effect.has("poison"):
		parts.append("中毒+" + str(effect["poison"]))
	if effect.get("combo", false):
		parts.append("连击")
	if effect.has("field_sync"):
		parts.append("场地同步")
	return "[" + " ".join(parts) + "]"
