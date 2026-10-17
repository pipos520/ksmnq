extends ThemedControl

# ============================
#  刻画卡牌 - 主界面
#  流程：选卡基→选卡墨→填攻防→填字段→选纹路（占位）→选辅材（占位）→自动计算→封卡保存
# ============================

const MAX_FIELDS := 3
const MAX_AUX := 3
var _selected_card_base: Dictionary = {}
var _selected_ink: Dictionary = {}
# 教程引导状态：-1=未开始，0=进场，1=等选卡基，2=等选卡墨，3=等填攻防，4=等卡名，5=可封卡
var _tutorial_step: int = -1
var _tutorial_done: bool = false
var _attack: int = 0
var _health: int = 0
var _card_name: String = ""  # 自定义卡名，为空时自动拼接
var _fields: Array[String] = ["", "", ""]
var _aux_items: Array = []
var _card_description: String = ""  # 卡牌描述
var _card_rarity: String = "普通"   # 稀有度：普通/稀有/史诗/传说
var _preview_labels := {}

# 纹路槽位系统
var _max_slots: int = 0          # 卡基提供的最大纹路槽位数（可放置的纹路组件总数）
var _slots: Array[String] = []         # 每个元素 = 组件ID（如"TR01"），空字符串""表示空槽位
var _slot_buttons: Array[Button] = []  # 每个槽位的按钮引用
var _slot_params: Array[Dictionary] = []  # 每个槽位的参数（如 {"value": 5}），无参数为 {}
var _effect_names: Array[String] = []   # 每个效果块的自定义名称（索引=block_idx），空字符串=未命名
# 音游品质弹窗状态
var _quality_weights: Array = []
var _engrave_active: bool = false
var _engrave_marker: float = 0.0
var _engrave_dir: int = 1
var _engrave_speed: float = 1.0
var _engrave_overlay: ColorRect = null
var _engrave_bar: Control = null
var _engrave_marker_node: ColorRect = null
var _engrave_bar_width: float = 0.0
var _pending_final_load: float = 0.0
var _pending_tendency: Dictionary = {}
# 敲击定品质 → 确认弹窗（封卡/看广告重敲）
var _pending_quality: String = ""       # 敲击暂存的品质，未确认前不落卡
var _confirm_overlay: ColorRect = null  # 品质确认弹窗
# 激励广告（复用灰鲸 HJAdsNode，模式同 Shop.gd）
var _hj_ads = null                      # HJAdsNode 实例
var _ad_ready: bool = false             # 当前是否可播广告
var _pending_q_range: String = ""       # 重敲所需参数（卡基品质区间）
var _pending_title_level: int = 1
var _pending_quality_stab: float = 0.0
var _retry_waiting = null               # 广告看完标记（null=未看完，{"waiting":true}=可重敲）
var _ad_status_hint: Label = null       # 品质确认窗里的广告状态小字引用


func _ready():
	super._ready()
	var back := get_node_or_null("BackBtn")
	if back is Button: back.pressed.connect(_on_back)
	var help := get_node_or_null("HelpBtn")
	if help is Button: help.pressed.connect(_on_help)
	call_deferred("_build_dynamic_content")

func _build_base_selection(parent: VBoxContainer):
	var panel = _make_section_container()
	parent.add_child(panel)
	var vbox = panel.get_child(0)
	
	var title = Label.new()
	title.text = "🃏 ① 选择卡基"
	title.add_theme_font_size_override("font_size", 50)
	title.add_theme_color_override("font_color", Global.current.title)
	vbox.add_child(title)
	
	var select_btn = Button.new()
	select_btn.name = "SelectBaseBtn"
	select_btn.text = "点击选择卡基"
	select_btn.add_theme_font_size_override("font_size", 45)
	var s = StyleBoxFlat.new()
	s.bg_color = Global.current.btn_bg
	s.border_width_left = 2
	s.border_width_right = 2
	s.border_width_top = 2
	s.border_width_bottom = 2
	s.border_color = Color("#e8a838")
	s.corner_radius_top_left = 8
	s.corner_radius_top_right = 8
	s.corner_radius_bottom_left = 8
	s.corner_radius_bottom_right = 8
	s.content_margin_left = 16
	s.content_margin_right = 16
	select_btn.add_theme_stylebox_override("normal", s)
	select_btn.add_theme_color_override("font_color", Global.current.btn_text)
	select_btn.pressed.connect(_on_select_base)
	select_btn.size_flags_horizontal = SIZE_FILL
	select_btn.custom_minimum_size = Vector2(0, Global.ph(0.07))
	vbox.add_child(select_btn)
	
	var info = Label.new()
	info.name = "BaseInfo"
	info.text = "未选择卡基"
	info.add_theme_font_size_override("font_size", 40)
	info.add_theme_color_override("font_color", Global.current.btn_text)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(info)
	
	_preview_labels["base_info"] = info
	_preview_labels["select_base_btn"] = select_btn


func _make_section_container() -> PanelContainer:
	var pc = PanelContainer.new()
	var ps = StyleBoxFlat.new()
	ps.bg_color = Global.current.topbar_bg
	ps.corner_radius_top_left = 8
	ps.corner_radius_top_right = 8
	ps.corner_radius_bottom_left = 8
	ps.corner_radius_bottom_right = 8
	ps.content_margin_left = Global.pw(0.03)
	ps.content_margin_right = Global.pw(0.03)
	ps.content_margin_top = Global.ph(0.01)
	ps.content_margin_bottom = Global.ph(0.01)
	pc.add_theme_stylebox_override("panel", ps)
	pc.size_flags_horizontal = SIZE_FILL
	pc.mouse_filter = MOUSE_FILTER_PASS
	
	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = SIZE_FILL
	vbox.mouse_filter = MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", Global.ph(0.005))
	pc.add_child(vbox)
	return pc


# ============================
#  步骤2：选择卡墨
# ============================
func _build_ink_selection(parent: VBoxContainer):
	var panel = _make_section_container()
	parent.add_child(panel)
	var vbox = panel.get_child(0)
	
	var title = Label.new()
	title.text = "🎨 ② 选择卡墨"
	title.add_theme_font_size_override("font_size", 50)
	title.add_theme_color_override("font_color", Global.current.title)
	vbox.add_child(title)
	
	var select_btn = Button.new()
	select_btn.name = "SelectInkBtn"
	select_btn.text = "点击选择卡墨"
	select_btn.add_theme_font_size_override("font_size", 45)
	var s = StyleBoxFlat.new()
	s.bg_color = Global.current.btn_bg
	s.border_width_left = 2; s.border_width_right = 2; s.border_width_top = 2; s.border_width_bottom = 2
	s.border_color = Color("#6c9bcf")
	s.corner_radius_top_left = 8; s.corner_radius_top_right = 8; s.corner_radius_bottom_left = 8; s.corner_radius_bottom_right = 8
	s.content_margin_left = 16; s.content_margin_right = 16
	select_btn.add_theme_stylebox_override("normal", s)
	select_btn.add_theme_color_override("font_color", Global.current.btn_text)
	select_btn.pressed.connect(_on_select_ink)
	select_btn.size_flags_horizontal = SIZE_FILL
	select_btn.custom_minimum_size = Vector2(0, Global.ph(0.07))
	vbox.add_child(select_btn)
	
	var info = Label.new()
	info.name = "InkInfo"
	info.text = "未选择卡墨"
	info.add_theme_font_size_override("font_size", 40)
	info.add_theme_color_override("font_color", Global.current.btn_text)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(info)
	
	_preview_labels["ink_info"] = info
	_preview_labels["select_ink_btn"] = select_btn


# ============================
#  步骤3：填写攻防
# ============================
func _build_stat_input(parent: VBoxContainer):
	var panel = _make_section_container()
	parent.add_child(panel)
	var vbox = panel.get_child(0)
	
	var title = Label.new()
	title.text = "💪 ③ 填写基础数值"
	title.add_theme_font_size_override("font_size", 50)
	title.add_theme_color_override("font_color", Global.current.title)
	vbox.add_child(title)
	
	var hint = Label.new()
	hint.text = "攻击和生命值由玩家自由填写，能量消耗将自动计算"
	hint.add_theme_font_size_override("font_size", 45)
	hint.add_theme_color_override("font_color", Global.current.btn_text)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(hint)
	
	# 攻击行
	var atk_hbox = HBoxContainer.new()
	atk_hbox.size_flags_horizontal = SIZE_FILL
	vbox.add_child(atk_hbox)
	
	var atk_label = Label.new()
	atk_label.text = "⚔️ 攻击："
	atk_label.add_theme_font_size_override("font_size", 45)
	atk_label.add_theme_color_override("font_color", Global.current.title)
	atk_label.size_flags_horizontal = SIZE_EXPAND
	atk_hbox.add_child(atk_label)
	
	var atk_input = _make_number_input("AtkInput", 0, 0, 99)
	atk_hbox.add_child(atk_input)
	
	# 生命行
	var hp_hbox = HBoxContainer.new()
	hp_hbox.size_flags_horizontal = SIZE_FILL
	vbox.add_child(hp_hbox)
	
	var hp_label = Label.new()
	hp_label.text = "❤️ 生命："
	hp_label.add_theme_font_size_override("font_size", 45)
	hp_label.add_theme_color_override("font_color", Global.current.title)
	hp_label.size_flags_horizontal = SIZE_EXPAND
	hp_hbox.add_child(hp_label)
	
	var hp_input = _make_number_input("HpInput", 0, 0, 99)
	hp_hbox.add_child(hp_input)


func _make_number_input(name: String, default_val: int, min_val: int, max_val: int) -> HBoxContainer:
	var hbox = HBoxContainer.new()
	hbox.name = name + "HBox"
	hbox.custom_minimum_size = Vector2(Global.pw(0.35), 0)
	
	var dec_btn = Button.new()
	dec_btn.text = "−"
	dec_btn.add_theme_font_size_override("font_size", 50)
	var ds = StyleBoxFlat.new()
	ds.bg_color = Global.current.btn_bg
	ds.border_width_left = 2; ds.border_width_right = 2; ds.border_width_top = 2; ds.border_width_bottom = 2
	ds.border_color = Color("#888888")
	ds.corner_radius_top_left = 8; ds.corner_radius_bottom_left = 8
	ds.content_margin_left = 12; ds.content_margin_right = 12
	dec_btn.add_theme_stylebox_override("normal", ds)
	dec_btn.add_theme_color_override("font_color", Global.current.btn_text)
	dec_btn.custom_minimum_size = Vector2(Global.pw(0.08), Global.ph(0.06))
	dec_btn.pressed.connect(_on_num_btn.bind(name, -1, min_val, max_val))
	hbox.add_child(dec_btn)
	
	var value_label = Label.new()
	value_label.name = name + "Val"
	value_label.text = str(default_val)
	value_label.add_theme_font_size_override("font_size", 50)
	value_label.add_theme_color_override("font_color", Global.current.title)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value_label.custom_minimum_size = Vector2(Global.pw(0.12), Global.ph(0.06))
	hbox.add_child(value_label)
	
	var inc_btn = Button.new()
	inc_btn.text = "+"
	inc_btn.add_theme_font_size_override("font_size", 50)
	var is_ = StyleBoxFlat.new()
	is_.bg_color = Global.current.btn_bg
	is_.border_width_left = 2; is_.border_width_right = 2; is_.border_width_top = 2; is_.border_width_bottom = 2
	is_.border_color = Color("#888888")
	is_.corner_radius_top_right = 8; is_.corner_radius_bottom_right = 8
	is_.content_margin_left = 12; is_.content_margin_right = 12
	inc_btn.add_theme_stylebox_override("normal", is_)
	inc_btn.add_theme_color_override("font_color", Global.current.btn_text)
	inc_btn.custom_minimum_size = Vector2(Global.pw(0.08), Global.ph(0.06))
	inc_btn.pressed.connect(_on_num_btn.bind(name, 1, min_val, max_val))
	hbox.add_child(inc_btn)
	
	_preview_labels[name + "Val"] = value_label
	return hbox


func _on_num_btn(name: String, delta: int, min_val: int, max_val: int):
	var label = _preview_labels.get(name + "Val")
	if not label:
		return
	var val = int(label.text) + delta
	val = clampi(val, min_val, max_val)
	label.text = str(val)
	if name == "AtkInput":
		_attack = val
	elif name == "HpInput":
		_health = val
	_update_preview()
	# 教程引导：攻防都填了以后推进
	if _attack > 0 and _health > 0:
		_tutorial_advance("stats_filled")


# ============================
#  步骤4：填写卡名与字段
# ============================
func _build_field_input(parent: VBoxContainer):
	var panel = _make_section_container()
	parent.add_child(panel)
	var vbox = panel.get_child(0)
	
	var title = Label.new()
	title.text = "🏷️ ④ 填写卡名与字段"
	title.add_theme_font_size_override("font_size", 50)
	title.add_theme_color_override("font_color", Global.current.title)
	vbox.add_child(title)
	
	# 卡名输入行
	var name_hbox = HBoxContainer.new()
	name_hbox.size_flags_horizontal = SIZE_FILL
	vbox.add_child(name_hbox)
	
	var name_label = Label.new()
	name_label.text = "📛 卡名："
	name_label.add_theme_font_size_override("font_size", 40)
	name_label.add_theme_color_override("font_color", Global.current.title)
	name_label.custom_minimum_size = Vector2(Global.pw(0.12), 0)
	name_hbox.add_child(name_label)
	
	var name_input = LineEdit.new()
	name_input.name = "CardNameInput"
	name_input.placeholder_text = "留空则自动生成"
	name_input.custom_minimum_size = Vector2(0, Global.ph(0.055))
	name_input.size_flags_horizontal = SIZE_EXPAND
	name_input.add_theme_font_size_override("font_size", 40)
	name_input.text_changed.connect(_on_card_name_changed)
	name_hbox.add_child(name_input)
	_preview_labels["card_name_input"] = name_input
	
	# 字段提示
	var hint = Label.new()
	hint.text = "字段是自定义字符串，用于卡牌之间的联动检索"
	hint.add_theme_font_size_override("font_size", 45)
	hint.add_theme_color_override("font_color", Global.current.btn_text)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(hint)
	
	_preview_labels["field_inputs"] = []
	for i in range(MAX_FIELDS):
		var hbox = HBoxContainer.new()
		hbox.size_flags_horizontal = SIZE_FILL
		vbox.add_child(hbox)
		
		var idx_label = Label.new()
		idx_label.text = "字段" + str(i + 1) + "："
		idx_label.add_theme_font_size_override("font_size", 40)
		idx_label.add_theme_color_override("font_color", Global.current.btn_text)
		idx_label.custom_minimum_size = Vector2(Global.pw(0.12), 0)
		hbox.add_child(idx_label)
		
		var line_edit = LineEdit.new()
		line_edit.name = "FieldInput_" + str(i)
		line_edit.placeholder_text = "可选"
		line_edit.custom_minimum_size = Vector2(0, Global.ph(0.055))
		line_edit.size_flags_horizontal = SIZE_EXPAND
		line_edit.add_theme_font_size_override("font_size", 40)
		line_edit.text_changed.connect(_on_field_changed.bind(i))
		hbox.add_child(line_edit)
		_preview_labels["field_inputs"].append(line_edit)


func _on_field_changed(_new_text: String, idx: int):
	var inputs = _preview_labels.get("field_inputs", [])
	if idx < inputs.size():
		_fields[idx] = inputs[idx].text
	_update_preview()


func _on_card_name_changed(new_text: String):
	_card_name = new_text
	_update_preview()
	# 教程引导：填好卡名后推进
	if new_text.strip_edges() != "":
		_tutorial_advance("name_filled")


# ============================
#  步骤4.5：卡牌详情
# ============================
func _build_card_detail(parent: VBoxContainer):
	var panel = _make_section_container()
	parent.add_child(panel)
	var vbox = panel.get_child(0)
	
	var title = Label.new()
	title.text = "📝 ⑤ 卡牌描述"
	title.add_theme_font_size_override("font_size", 50)
	title.add_theme_color_override("font_color", Global.current.title)
	vbox.add_child(title)
	
	# 卡牌描述（多行）
	var desc_input = TextEdit.new()
	desc_input.name = "DescInput"
	desc_input.placeholder_text = "输入卡牌描述（限40字）"
	desc_input.custom_minimum_size = Vector2(0, Global.ph(0.12))
	desc_input.size_flags_horizontal = SIZE_FILL
	desc_input.add_theme_font_size_override("font_size", 40)
	desc_input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	desc_input.text_changed.connect(_on_desc_changed)
	vbox.add_child(desc_input)
	_preview_labels["desc_input"] = desc_input


func _on_desc_changed():
	var input = _preview_labels.get("desc_input")
	if input:
		# 文本截断用call_deferred避免在渲染帧内修改TextEdit导致引擎报错
		if input.text.length() > 40:
			var truncated = input.text.substr(0, 40)
			call_deferred("_truncate_desc_input", input, truncated)
		else:
			_card_description = input.text
			# 教程引导：描述填写完成 → 推进step5→6
			if not _tutorial_done and _tutorial_step == 5 and _card_description != "":
				_tutorial_advance("desc_filled")
	_update_preview()

func _truncate_desc_input(input: TextEdit, text: String) -> void:
	if not is_instance_valid(input):
		return
	input.text = text
	input.set_caret_column(40)
	_card_description = text
	# 教程引导：描述填写完成 → 推进step5→6
	if not _tutorial_done and _tutorial_step == 5 and _card_description != "":
		_tutorial_advance("desc_filled")
	_update_preview()


# ============================
#  步骤5：辅材选择
# ============================
func _build_aux_section(parent: VBoxContainer):
	var panel = _make_section_container()
	parent.add_child(panel)
	var vbox = panel.get_child(0)
	
	var title = Label.new()
	title.text = "🧪 ⑥ 辅材（可选，最多" + str(MAX_AUX) + "种）"
	title.add_theme_font_size_override("font_size", 50)
	title.add_theme_color_override("font_color", Global.current.title)
	vbox.add_child(title)
	
	var hint = Label.new()
	hint.text = "从仓库中选择已拥有的辅材，附在卡牌上增强效果（战斗中掉落获得）"
	hint.add_theme_font_size_override("font_size", 45)
	hint.add_theme_color_override("font_color", Global.current.btn_text)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(hint)
	
	var select_btn = Button.new()
	select_btn.name = "SelectAuxBtn"
	select_btn.text = "点击选择辅材 (" + str(_aux_items.size()) + "/" + str(MAX_AUX) + ")"
	select_btn.add_theme_font_size_override("font_size", 45)
	var s = StyleBoxFlat.new()
	s.bg_color = Global.current.btn_bg
	s.border_width_left = 2; s.border_width_right = 2; s.border_width_top = 2; s.border_width_bottom = 2
	s.border_color = Color("#9b59b6")
	s.corner_radius_top_left = 8; s.corner_radius_top_right = 8; s.corner_radius_bottom_left = 8; s.corner_radius_bottom_right = 8
	s.content_margin_left = 16; s.content_margin_right = 16
	select_btn.add_theme_stylebox_override("normal", s)
	select_btn.add_theme_color_override("font_color", Global.current.btn_text)
	select_btn.pressed.connect(_on_select_aux)
	select_btn.size_flags_horizontal = SIZE_FILL
	select_btn.custom_minimum_size = Vector2(0, Global.ph(0.07))
	vbox.add_child(select_btn)
	_preview_labels["select_aux_btn"] = select_btn
	
	var aux_row = HBoxContainer.new()
	aux_row.name = "AuxSelectedRow"
	aux_row.size_flags_horizontal = SIZE_FILL
	aux_row.custom_minimum_size = Vector2(0, Global.ph(0.06))
	vbox.add_child(aux_row)
	_preview_labels["aux_row"] = aux_row
	
	_update_aux_display()


func _update_aux_display():
	var row = _preview_labels.get("aux_row")
	if not row:
		return
	# 清空旧标签
	for child in row.get_children():
		row.remove_child(child)
		child.queue_free()
	
	if _aux_items.size() == 0:
		var empty = Label.new()
		empty.text = "未选择辅材"
		empty.add_theme_font_size_override("font_size", 40)
		empty.add_theme_color_override("font_color", Global.current.btn_text)
		row.add_child(empty)
		return
	
	for aux_data in _aux_items:
		var aid = aux_data.get("id", "")
		var aname = aux_data.get("name", "未知")
		var rarity = aux_data.get("rarity", "普通")
		
		var tag = Button.new()
		tag.text = aname
		tag.add_theme_font_size_override("font_size", 40)
		var ts = StyleBoxFlat.new()
		ts.bg_color = Global.current.btn_bg
		ts.border_width_left = 1; ts.border_width_right = 1; ts.border_width_top = 1; ts.border_width_bottom = 1
		ts.border_color = _get_rarity_color(rarity)
		ts.corner_radius_top_left = 6; ts.corner_radius_top_right = 6; ts.corner_radius_bottom_left = 6; ts.corner_radius_bottom_right = 6
		ts.content_margin_left = 8; ts.content_margin_right = 8
		tag.add_theme_stylebox_override("normal", ts)
		tag.add_theme_color_override("font_color", Global.current.btn_text)
		tag.pressed.connect(_on_remove_aux.bind(aux_data))
		row.add_child(tag)
	
	# 更新按钮文字
	var select_btn = _preview_labels.get("select_aux_btn")
	if select_btn:
		select_btn.text = "点击选择辅材 (" + str(_aux_items.size()) + "/" + str(MAX_AUX) + ")"
		select_btn.disabled = _aux_items.size() >= MAX_AUX


func _on_select_aux():
	if _aux_items.size() >= MAX_AUX:
		_show_popup("最多只能选择 " + str(MAX_AUX) + " 种辅材", Color("#FF6B6B"))
		return
	
	var warehouse = get_node("/root/WarehouseManager")
	var aux_inv = warehouse.get_aux_items()
	
	# 过滤掉已选的
	var available := []
	for aid in aux_inv.keys():
		var count = aux_inv[aid]
		if count <= 0:
			continue
		# 检查是否已选
		var already_selected = false
		for item in _aux_items:
			if item.get("id", "") == aid:
				already_selected = true
				break
		if already_selected:
			continue
		var aux_data = Global.get_aux_by_id(aid)
		if not aux_data.is_empty():
			available.append(aux_data)
	
	if available.size() == 0:
		_show_popup("仓库中没有可用的辅材，请先击败卡兽获取", Color("#FF6B6B"))
		return
	
	_show_aux_picker(available)


func _show_aux_picker(available: Array):
	var overlay = ColorRect.new()
	overlay.name = "AuxPickerOverlay"
	overlay.color = Color(0.0, 0.0, 0.0, 0.6)
	overlay.anchor_left = 0.0; overlay.anchor_top = 0.0; overlay.anchor_right = 1.0; overlay.anchor_bottom = 1.0
	overlay.mouse_filter = MOUSE_FILTER_STOP
	overlay.gui_input.connect(_on_picker_overlay_clicked.bind(overlay))
	add_child(overlay)

	var panel = Panel.new()
	panel.name = "AuxPickerPanel"
	panel.anchor_left = 0.05; panel.anchor_top = 0.15; panel.anchor_right = 0.95; panel.anchor_bottom = 0.85
	panel.clip_contents = true
	var ps = StyleBoxFlat.new()
	ps.bg_color = Global.current.bg
	ps.border_width_left = 3; ps.border_width_right = 3; ps.border_width_top = 3; ps.border_width_bottom = 3
	ps.border_color = Global.current.topbar_border
	ps.corner_radius_top_left = 16; ps.corner_radius_top_right = 16
	ps.corner_radius_bottom_left = 16; ps.corner_radius_bottom_right = 16
	panel.add_theme_stylebox_override("panel", ps)
	overlay.add_child(panel)

	var title = Label.new()
	title.text = "🧪 选择辅材"
	title.add_theme_font_size_override("font_size", 55)
	title.add_theme_color_override("font_color", Global.current.title)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.anchor_left = 0.0; title.anchor_top = 0.0; title.anchor_right = 1.0; title.anchor_bottom = 0.0
	title.offset_left = 0; title.offset_top = Global.ph(0.02); title.offset_right = 0; title.offset_bottom = Global.ph(0.08)
	panel.add_child(title)

	var scroll = ScrollContainer.new()
	scroll.name = "AuxPickerScroll"
	scroll.anchor_left = 0.0; scroll.anchor_top = 0.0; scroll.anchor_right = 1.0; scroll.anchor_bottom = 1.0
	scroll.offset_left = 0; scroll.offset_top = Global.ph(0.08); scroll.offset_right = 0; scroll.offset_bottom = -Global.ph(0.1)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	var vbox = VBoxContainer.new()
	vbox.name = "PickerVBox"
	vbox.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	scroll.add_child(vbox)

	var row_index := 0
	for aux in available:
		var aid = aux.get("id", "")
		var aname = aux.get("name", "")
		var rarity = aux.get("rarity", "普通")
		var desc = aux.get("description", "")

		var row_panel = PanelContainer.new()
		var rps = StyleBoxFlat.new()
		rps.bg_color = Global.current.topbar_bg if row_index % 2 == 0 else Color.TRANSPARENT
		rps.content_margin_left = Global.pw(0.02)
		rps.content_margin_right = Global.pw(0.02)
		rps.content_margin_top = Global.ph(0.005)
		rps.content_margin_bottom = Global.ph(0.005)
		row_panel.add_theme_stylebox_override("panel", rps)
		row_panel.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
		row_panel.mouse_filter = MOUSE_FILTER_PASS
		vbox.add_child(row_panel)

		var row_vbox = VBoxContainer.new()
		row_vbox.size_flags_horizontal = SIZE_FILL
		row_vbox.mouse_filter = MOUSE_FILTER_IGNORE
		row_vbox.add_theme_constant_override("separation", 2)
		row_panel.add_child(row_vbox)

		var left_vbox = VBoxContainer.new()
		left_vbox.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
		left_vbox.add_theme_constant_override("separation", 2)
		row_vbox.add_child(left_vbox)

		var name_label = Label.new()
		name_label.text = aname
		name_label.add_theme_font_size_override("font_size", 45)
		name_label.add_theme_color_override("font_color", _get_rarity_color(rarity))
		left_vbox.add_child(name_label)

		var info_label = Label.new()
		info_label.text = desc
		info_label.add_theme_font_size_override("font_size", 40)
		info_label.add_theme_color_override("font_color", Global.current.btn_text)
		info_label.size_flags_horizontal = SIZE_FILL
		info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		left_vbox.add_child(info_label)

		var btn_hbox = HBoxContainer.new()
		btn_hbox.size_flags_horizontal = SIZE_FILL
		btn_hbox.mouse_filter = MOUSE_FILTER_IGNORE
		row_vbox.add_child(btn_hbox)
		var select_btn = Button.new()
		select_btn.text = "选择"
		select_btn.add_theme_font_size_override("font_size", 40)
		select_btn.custom_minimum_size = Vector2(Global.pw(0.12), 0)
		select_btn.pressed.connect(_on_pick_aux.bind(aid, aux, overlay))
		btn_hbox.add_child(select_btn)
		var spacer = Control.new()
		spacer.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
		btn_hbox.add_child(spacer)
		row_index += 1

	var close_btn = Button.new()
	close_btn.text = "✕ 关闭"
	close_btn.add_theme_font_size_override("font_size", 45)
	var cs = StyleBoxFlat.new()
	cs.bg_color = Global.current.btn_bg
	cs.border_width_left = 2; cs.border_width_right = 2; cs.border_width_top = 2; cs.border_width_bottom = 2
	cs.border_color = Color("#888888")
	cs.corner_radius_top_left = 12; cs.corner_radius_top_right = 12
	cs.corner_radius_bottom_left = 12; cs.corner_radius_bottom_right = 12
	cs.content_margin_left = 24; cs.content_margin_right = 24
	close_btn.add_theme_stylebox_override("normal", cs)
	close_btn.add_theme_color_override("font_color", Global.current.btn_text)
	close_btn.anchor_left = 0.3; close_btn.anchor_top = 1.0; close_btn.anchor_right = 0.7; close_btn.anchor_bottom = 1.0
	close_btn.offset_left = 0; close_btn.offset_top = Global.ph(-0.08); close_btn.offset_right = 0; close_btn.offset_bottom = Global.ph(-0.02)
	close_btn.pressed.connect(_close_picker.bind(overlay))
	panel.add_child(close_btn)
func _on_pick_aux(aux_id: String, aux_data: Dictionary, overlay: ColorRect):
	_aux_items.append(aux_data)
	# 辅材不在选择时消耗，刻录成功时才从仓库扣除（防止退出制卡界面导致辅材丢失）
	_update_aux_display()
	_update_preview()
	_close_picker(overlay)


func _on_remove_aux(aux_data: Dictionary):
	# 选择时未扣库存，移除时也无需退回仓库
	_aux_items.erase(aux_data)
	_update_aux_display()
	_update_preview()


func _show_popup(text: String, color: Color):
	var existing = get_node_or_null("PopupOverlay")
	if existing:
		existing.queue_free()
	
	var overlay = ColorRect.new()
	overlay.name = "PopupOverlay"
	overlay.color = Color(0, 0, 0, 0.5)
	overlay.anchor_left = 0.0; overlay.anchor_top = 0.0; overlay.anchor_right = 1.0; overlay.anchor_bottom = 1.0
	overlay.mouse_filter = MOUSE_FILTER_STOP
	overlay.gui_input.connect(_on_popup_click.bind(overlay))
	add_child(overlay)
	
	var panel = Panel.new()
	panel.anchor_left = 0.2; panel.anchor_top = 0.35; panel.anchor_right = 0.8; panel.anchor_bottom = 0.65
	var ps = StyleBoxFlat.new()
	ps.bg_color = Global.current.bg
	ps.border_width_left = 3; ps.border_width_right = 3; ps.border_width_top = 3; ps.border_width_bottom = 3
	ps.border_color = color
	ps.corner_radius_top_left = 16; ps.corner_radius_top_right = 16
	ps.corner_radius_bottom_left = 16; ps.corner_radius_bottom_right = 16
	panel.add_theme_stylebox_override("panel", ps)
	overlay.add_child(panel)
	
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 50)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.anchor_left = 0.0; label.anchor_top = 0.0; label.anchor_right = 1.0; label.anchor_bottom = 1.0
	panel.add_child(label)
	
	var timer = get_tree().create_timer(1.5)
	timer.timeout.connect(_close_picker.bind(overlay))


func _on_popup_click(event: InputEvent, overlay: ColorRect):
	if event is InputEventMouseButton and event.pressed:
		_close_picker(overlay)


# ============================
#  教程 · 刻画卡牌对话式引导（操作驱动·一步步来）
# ============================
## 仅制卡幕（进度==2）触发；完成后不再弹（存档标记防重进）
func _start_tutorial_if_needed() -> void:
	if _tutorial_done or TutorialManager.get_progress() != TutorialManager.PROGRESS_FIRST_BATTLE:
		return
	# 已看过刻画引导则跳过
	if SaveManager.get_value("tutorial", "card_engrave_guide_seen", false):
		_tutorial_done = true
		return
	SaveManager.set_value("tutorial", "card_engrave_guide_seen", true)
	SaveManager.save_to_disk()
	_tutorial_step = 0
	_show_tutorial_dialogue([
		{"speaker": "老陈", "text": "这就是刻画台。卡基是身板，卡墨是灵魂，再加点自己的想法，就是一张卡。"},
		{"speaker": "你", "text": "（看着卡基和卡墨）所以现在把它们合起来？"},
		{"speaker": "老陈", "text": "别急，一步步来。先点上面【①选择卡基】。"},
	])

## 操作驱动推进：trigger 匹配当前步骤
func _tutorial_advance(trigger: String) -> void:
	if _tutorial_done:
		return
	match _tutorial_step:
		0:
			return  # 开场对话点完按钮直接推进（对话回调里处理）
		1:
			if trigger == "base_picked":
				_tutorial_step = 2
				_show_tutorial_dialogue([
					{"speaker": "老陈", "text": "身板挑好了。看旁边那栏，槽位、负荷、品质都标着。"},
					{"speaker": "你", "text": "嗯，这个卡基……槽位还行。"},
					{"speaker": "老陈", "text": "接下来【②选择卡墨】——上次调的那瓶，正好用上。"},
				], func():
					_tutorial_step = 2  # 保持等卡墨
				)
		2:
			if trigger == "ink_picked":
				_tutorial_step = 3
				_show_tutorial_dialogue([
					{"speaker": "老陈", "text": "墨也备好了。现在【③填写基础数值】——攻击、生命，按你的想法填。"},
					{"speaker": "你", "text": "攻防怎么配比较好？"},
					{"speaker": "老陈", "text": "别贪心，数值越高能耗越高。先凑一张能打的。"},
				], func():
					_tutorial_step = 3  # 等填攻防
				)
		3:
			if trigger == "stats_filled":
				_tutorial_step = 4
				_show_tutorial_dialogue([
					{"speaker": "老陈", "text": "有模有样了。再【④填个卡名】——你的第一张卡，得起个响亮的名儿。"},
					{"speaker": "你", "text": "（想名字）得起个有气势的……"},
					{"speaker": "老陈", "text": "不填也行，系统会帮你拼一个。"},
				], func():
					_tutorial_step = 4  # 等卡名
				)
		4:
			if trigger == "name_filled":
				_tutorial_step = 5
				_show_tutorial_dialogue([
					{"speaker": "老陈", "text": "名字不错！再往下翻，【⑤卡牌描述】写两句——让人知道你这卡是干嘛的。"},
					{"speaker": "你", "text": "描述……写点什么好呢。"},
					{"speaker": "老陈", "text": "随便写，别人看到你的卡第一眼就是这行字。填好了告诉我。"},
				], func():
					_tutorial_step = 5  # 等填描述
					# 如果描述已经填好了，直接推进
					if _card_description != "":
						_tutorial_advance("desc_filled")
				)
		5:
			if trigger == "desc_filled":
				_tutorial_step = 6
				_show_tutorial_dialogue([
					{"speaker": "你", "text": "写好了！接下来呢？"},
					{"speaker": "老陈", "text": "好的，现在说最关键的——**纹路效果**。一张卡的效果由三部分组成："},
					{"speaker": "老陈", "text": "① **⚡触发器（TR）**——什么时候触发？比如「入场时」「攻击时」「回合开始」。"},
					{"speaker": "老陈", "text": "② **🎯动作（A）**——触发后做什么？比如「造成伤害」「恢复生命」「抽牌」。"},
					{"speaker": "老陈", "text": "③ **🎯目标（T）**——对谁生效？比如「敌方单体」「己方全场」。"},
					{"speaker": "老陈", "text": "一个完整的效果 = 触发器 + 动作 + 目标，缺一不可。先到下面【⑦纹路槽位】点「＋ 添加新效果」创建一个效果条，然后点效果条里的「触发器槽位」选一个触发器。放好了告诉我。"},
				], func():
					_tutorial_step = 6  # 等纹路·触发器
				)
		6:
			if trigger == "slot_trigger":
				_tutorial_step = 7
				_show_tutorial_dialogue([
					{"speaker": "老陈", "text": "触发器放好了！现在装一个**动作**——再点一个空槽，选「🎯动作」。如果动作要填数值，随便填一个就行。"},
					{"speaker": "你", "text": "动作和触发器配成一组？"},
					{"speaker": "老陈", "text": "对。效果组就是触发器+动作+目标，三样凑齐才算一条完整的效果。放好了跟我说。"},
				], func():
					_tutorial_step = 7  # 等纹路·动作
				)
		7:
			if trigger == "slot_action":
				_tutorial_step = 8
				_show_tutorial_dialogue([
					{"speaker": "老陈", "text": "动作和触发器配上了！但还差一样——**目标（T）**，对谁生效？"},
					{"speaker": "你", "text": "对哦，没目标的话不知道打谁……"},
					{"speaker": "老陈", "text": "再点一个空槽，选「🎯目标」，指定是打敌方还是奶自己。放好了告诉我。"},
				], func():
					_tutorial_step = 8  # 等纹路·目标
				)
		8:
			if trigger == "slot_target":
				_tutorial_step = 9
				_show_tutorial_dialogue([
					{"speaker": "老陈", "text": "好！一组完整效果（TR+A+T）成型了。不过你注意到负荷了吗？——效果越强负荷越重。"},
					{"speaker": "老陈", "text": "想减负荷？以后可以装**条件（C）**或**约束（CO）**——条件限制触发时机，约束加额外代价，都能降低能耗。不过你现在还没解锁，以后再说。"},
					{"speaker": "你", "text": "懂了，以后打架多了自然解锁更多纹路。"},
					{"speaker": "老陈", "text": "没错。现在看看右边【📊卡牌属性预览】的负荷——基础负荷（攻击×1.0 + 生命×0.5）+ 纹路负荷（组件基础值 + 参数×1.7），再减去卡墨减免。不超过承载力就行。"},
					{"speaker": "老陈", "text": "超载就封不了卡。滚到底，点【💾封卡保存】！"},
				], func():
					_tutorial_step = 9  # 可封卡
				)
		9:
			return  # 封卡成功时由专门回调处理收尾

## 弹对话式引导弹窗
func _show_tutorial_dialogue(lines: Array, on_finish: Callable = Callable()) -> void:
	_close_tutorial_overlay()
	var popup = preload("res://TutorialDialoguePopup.gd").new()
	popup.setup(lines, func():
		# 开场对话（step0）点完 → 进入 step1（等选卡基）
		if _tutorial_step == 0:
			_tutorial_step = 1
		elif on_finish.is_valid():
			on_finish.call()
	)
	add_child(popup)

func _close_tutorial_overlay() -> void:
	for child in get_children():
		if child is TutorialDialoguePopup:
			child.queue_free()


# ============================
#  教程 · 制卡完成对话
# ============================
func _show_tutorial_done_dialogue(card_name: String) -> void:
	var popup = preload("res://TutorialDialoguePopup.gd").new()
	popup.setup([
		{"speaker": "老陈", "text": "「" + card_name + "」？哟，有模有样，是个能打的样儿。"},
		{"speaker": "你", "text": "（看着刚做好的卡）成了……我的第一张卡。"},
		{"speaker": "老陈", "text": "头一张卡成了，往后路子就宽了。先回主界面，我教你配卡组。"},
	], func():
		Global.change_scene("res://Main.tscn")
	)
	add_child(popup)


func _get_rarity_color(rarity: String) -> Color:
	match rarity:
		"传说":
			return Color("#f9d371")  # 金色
		"史诗":
			return Color("#c084fc")  # 紫色
		"稀有":
			return Color("#60a5fa")  # 蓝色
		_:
			return Global.current.btn_text  # 普通=默认文本色


# ============================
#  步骤6：纹路槽位（占位）
# ============================
func _build_effect_slots(parent: VBoxContainer):
	var panel = _make_section_container()
	parent.add_child(panel)
	var vbox = panel.get_child(0)
	
	var title = Label.new()
	title.text = "🔮 ⑦ 纹路槽位"
	title.add_theme_font_size_override("font_size", 50)
	title.add_theme_color_override("font_color", Global.current.title)
	vbox.add_child(title)
	
	# 槽位计数标签（青色主题）
	var count_label = Label.new()
	count_label.name = "SlotCountLabel"
	count_label.text = "槽位（0/0）"
	count_label.add_theme_font_size_override("font_size", 55)
	count_label.add_theme_color_override("font_color", Color("#00BCD4"))
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(count_label)
	
	# 槽位容器（用于动态重建效果块）
	var slot_container = VBoxContainer.new()
	slot_container.name = "SlotContainer"
	slot_container.size_flags_horizontal = SIZE_FILL
	slot_container.add_theme_constant_override("separation", Global.ph(0.015))
	vbox.add_child(slot_container)
	
	# 添加效果块按钮
	var add_btn = Button.new()
	add_btn.name = "AddEffectBtn"
	add_btn.text = "＋ 添加新效果"
	add_btn.add_theme_font_size_override("font_size", 48)
	add_btn.size_flags_horizontal = SIZE_FILL
	add_btn.custom_minimum_size = Vector2(0, Global.ph(0.08))
	var abs = StyleBoxFlat.new()
	abs.bg_color = Color("#00BCD4")
	abs.bg_color.a = 0.25
	abs.corner_radius_top_left = 10; abs.corner_radius_top_right = 10
	abs.corner_radius_bottom_left = 10; abs.corner_radius_bottom_right = 10
	add_btn.add_theme_stylebox_override("normal", abs)
	add_btn.add_theme_color_override("font_color", Color("#00BCD4"))
	add_btn.pressed.connect(_on_add_effect_block)
	vbox.add_child(add_btn)
	
	# 校验提示标签
	var validate_label = Label.new()
	validate_label.name = "SlotValidate"
	validate_label.text = ""
	validate_label.add_theme_font_size_override("font_size", 40)
	validate_label.add_theme_color_override("font_color", Color("#00BCD4"))
	validate_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(validate_label)
	
	_preview_labels["slot_container"] = slot_container
	_preview_labels["slot_count_label"] = count_label
	_preview_labels["slot_validate"] = validate_label
	_preview_labels["add_effect_btn"] = add_btn

	# 如果已选卡基，自动初始化槽位
	if not _selected_card_base.is_empty():
		var slot_count = _selected_card_base.get("slots", 0)
		_init_slots(slot_count)
		_rebuild_slot_ui()

# ============================
#  纹路槽位系统
# ============================

## 初始化槽位上限（不预填充，效果块由用户动态添加）
## 卡基 slots=N → 最多可添加 N 个效果块，每块含 TR/C/A/T/CO 五行
func _init_slots(count: int):
	_max_slots = count
	_slots.clear()
	_slot_buttons.clear()
	_slot_params.clear()
	_effect_names.clear()

## 重建槽位UI
func _rebuild_slot_ui():
	var container = _preview_labels.get("slot_container")
	if not container:
		return
	
	# 清空旧UI
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
	_slot_buttons.clear()
	
	var max_blocks = _slots.size() / 5  # 当前已添加的效果块数
	var slot_cap = _max_slots          # 卡基提供的纹路槽位总数
	var placed = 0                     # 已放置的纹路组件数
	for i in range(_slots.size()):
		if _slots[i] != "":
			placed += 1
	
	# 更新槽位计数标签
	var count_label = _preview_labels.get("slot_count_label")
	if count_label:
		count_label.text = "纹路槽位（" + str(placed) + "/" + str(slot_cap) + "）"
	
	if slot_cap == 0:
		var empty_label = Label.new()
		empty_label.text = "该卡基无可用槽位"
		empty_label.add_theme_font_size_override("font_size", 45)
		empty_label.add_theme_color_override("font_color", Global.current.btn_text)
		container.add_child(empty_label)
		return
	
	if max_blocks == 0:
		var empty_hint = Label.new()
		empty_hint.text = "暂无效果，点击下方「添加新效果」开始配置纹路"
		empty_hint.add_theme_font_size_override("font_size", 42)
		empty_hint.add_theme_color_override("font_color", Color("#FF9800"))
		empty_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		container.add_child(empty_hint)
		return
	
	# 渲染每个效果块（每5个槽位为一组）
	for bi in range(max_blocks):
		var base = bi * 5
		
		# 效果块面板
		var block_panel = PanelContainer.new()
		var bps = StyleBoxFlat.new()
		bps.bg_color = Color(0.15, 0.2, 0.3, 0.85)  # ★ 不透明背景，不透出下层金色
		bps.border_width_left = 2; bps.border_width_right = 2
		bps.border_width_top = 2; bps.border_width_bottom = 2
		bps.border_color = Color("#00BCD4")
		bps.border_color.a = 0.4
		bps.corner_radius_top_left = 8; bps.corner_radius_top_right = 8
		bps.corner_radius_bottom_left = 8; bps.corner_radius_bottom_right = 8
		bps.content_margin_left = Global.pw(0.02); bps.content_margin_right = Global.pw(0.02)
		bps.content_margin_top = Global.ph(0.01); bps.content_margin_bottom = Global.ph(0.01)
		block_panel.add_theme_stylebox_override("panel", bps)
		block_panel.size_flags_horizontal = SIZE_FILL
		block_panel.mouse_filter = MOUSE_FILTER_PASS
		container.add_child(block_panel)
		
		var block_vbox = VBoxContainer.new()
		block_vbox.size_flags_horizontal = SIZE_FILL
		block_vbox.mouse_filter = MOUSE_FILTER_IGNORE
		block_vbox.add_theme_constant_override("separation", 6)
		block_vbox.name = "EffectBlock_" + str(bi)
		block_panel.add_child(block_vbox)
		# 效果块标题行（标题 + 删除按钮）
		var title_hbox = HBoxContainer.new()
		title_hbox.size_flags_horizontal = SIZE_FILL
		block_vbox.add_child(title_hbox)
		var block_title = Label.new()
		block_title.text = "✦ 效果" + str(bi + 1)
		block_title.add_theme_font_size_override("font_size", 42)
		block_title.add_theme_color_override("font_color", Color("#00BCD4"))
		block_title.size_flags_horizontal = SIZE_EXPAND_FILL
		title_hbox.add_child(block_title)
		# 删除效果块按钮
		var del_btn = Button.new()
		del_btn.text = "🗑️"
		del_btn.add_theme_font_size_override("font_size", 36)
		del_btn.custom_minimum_size = Vector2(Global.ph(0.08), Global.ph(0.06))
		var dbs = StyleBoxFlat.new()
		dbs.bg_color = Color("#FF4444")
		dbs.bg_color.a = 0.2
		dbs.corner_radius_top_left = 8; dbs.corner_radius_top_right = 8
		dbs.corner_radius_bottom_left = 8; dbs.corner_radius_bottom_right = 8
		del_btn.add_theme_stylebox_override("normal", dbs)
		del_btn.add_theme_color_override("font_color", Color("#FF6B6B"))
		del_btn.pressed.connect(_on_delete_effect_block.bind(bi))
		title_hbox.add_child(del_btn)
		
		# 效果名称输入框（7字以内，可选）
		var name_input = LineEdit.new()
		name_input.name = "EffectNameInput_" + str(bi)
		name_input.max_length = 7
		name_input.placeholder_text = "新效果名: 请输入效果名"
		name_input.text = _effect_names[bi] if bi < _effect_names.size() else ""
		name_input.add_theme_font_size_override("font_size", 38)
		name_input.size_flags_horizontal = SIZE_FILL
		name_input.custom_minimum_size = Vector2(0, Global.ph(0.05))
		var nis = StyleBoxFlat.new()
		nis.bg_color = Color(0.1, 0.1, 0.15, 0.5)
		nis.corner_radius_top_left = 6; nis.corner_radius_top_right = 6
		nis.corner_radius_bottom_left = 6; nis.corner_radius_bottom_right = 6
		nis.border_width_left = 1; nis.border_width_right = 1
		nis.border_width_top = 1; nis.border_width_bottom = 1
		nis.border_color = Color("#00BCD4")
		nis.border_color.a = 0.3
		name_input.add_theme_stylebox_override("normal", nis)
		name_input.add_theme_color_override("font_color", Color("#E0E0E0"))
		name_input.add_theme_color_override("placeholder_color", Color(0.5, 0.5, 0.5))
		name_input.text_changed.connect(_on_effect_name_changed.bind(bi))
		block_vbox.add_child(name_input)
		
		
		# 5行组件：触发器/条件/动作/目标/约束
		var row_defs = [
			{"offset": 0, "key": "TR", "label": "触发器槽位", "required": true},
			{"offset": 1, "key": "C", "label": "条件槽位", "required": false},
			{"offset": 2, "key": "A", "label": "动作槽位", "required": true},
			{"offset": 3, "key": "T", "label": "目标槽位", "required": true},
			{"offset": 4, "key": "CO", "label": "约束槽位", "required": false},
		]
		for rd in row_defs:
			var row_btn = Button.new()
			row_btn.name = "Row_" + str(bi) + "_" + rd["key"]
			row_btn.size_flags_horizontal = SIZE_FILL
			row_btn.add_theme_font_size_override("font_size", 40)
			row_btn.custom_minimum_size = Vector2(0, Global.ph(0.055))
			
			var slot_idx = base + rd["offset"]
			var cid = _slots[slot_idx]
			
			# 通用样式：跟卡基按钮一致，有实体背景+青色边框，避免文字飘在深色背景上看不清
			var rbs = StyleBoxFlat.new()
			rbs.corner_radius_top_left = 8
			rbs.corner_radius_top_right = 8
			rbs.corner_radius_bottom_left = 8
			rbs.corner_radius_bottom_right = 8
			rbs.content_margin_left = 16
			rbs.content_margin_right = 16
			rbs.content_margin_top = 6
			rbs.content_margin_bottom = 6
			row_btn.add_theme_stylebox_override("normal", rbs)
			
			if cid != "":
				# 已选择：绿色边框+浅色文字
				rbs.bg_color = Color(0.16, 0.2, 0.16, 0.85)
				rbs.border_width_left = 2; rbs.border_width_right = 2
				rbs.border_width_top = 2; rbs.border_width_bottom = 2
				rbs.border_color = Color("#4CAF50")
				var comp_info = Global.get_circuit_by_id(cid)
				var display_name = comp_info.get("name", cid) if not comp_info.is_empty() else cid
				row_btn.text = rd["label"] + ": " + display_name + " (" + cid + ")"
				row_btn.add_theme_color_override("font_color", Color("#E0E0E0"))
				row_btn.pressed.connect(_open_slot_picker.bind(slot_idx))
				_slot_buttons.append(row_btn)
			else:
				# 未选择-必选：青色系背景（跟纹路系统主色一致），红色仅用于"未选择"文字
				var req_str = "（必选）" if rd["required"] else "（可选）"
				row_btn.text = rd["label"] + ": 未选择" + req_str
				rbs.bg_color = Color(0.12, 0.15, 0.2, 0.85)
				rbs.border_width_left = 2; rbs.border_width_right = 2
				rbs.border_width_top = 2; rbs.border_width_bottom = 2
				if rd["required"]:
					rbs.border_color = Color("#00BCD4")
					row_btn.add_theme_color_override("font_color", Color("#00BCD4"))
				else:
					rbs.border_color = Color("#4A6080")
					row_btn.add_theme_color_override("font_color", Color(0.65, 0.68, 0.72))
				row_btn.pressed.connect(_open_slot_picker.bind(slot_idx))
				_slot_buttons.append(row_btn)
			
			block_vbox.add_child(row_btn)
	
	# 更新校验提示
	var validate_label = _preview_labels.get("slot_validate")
	if validate_label:
		var hints = _validate_slots()
		if hints.size() > 0:
			validate_label.text = "\n".join(hints)
		else:
			validate_label.text = ""

## 效果名称输入框回调：实时保存到 _effect_names 数组
func _on_effect_name_changed(new_text: String, block_idx: int):
	if block_idx < _effect_names.size():
		_effect_names[block_idx] = new_text

## 点击"添加新效果"按钮回调
## 动态添加一个新效果块（5个空槽位），效果条不占槽位，只有放纹路才占
func _on_add_effect_block():
	if _max_slots == 0:
		_show_popup("⚠️ 请先选择卡基", Color("#FF6B6B"))
		return
	# 效果条不占槽位，可以一直添加（每个效果条=5个槽位位置）
	# 但槽位总数已满时提示
	var placed = 0
	for i in range(_slots.size()):
		if _slots[i] != "":
			placed += 1
	if placed >= _max_slots:
		_show_popup("纹路槽位已满，效果条仍可添加但无法放置纹路", Color("#FFD700"))
	# 动态添加5个空槽位（效果条本身不占槽位）
	for i in range(5):
		_slots.append("")
		_slot_buttons.append(null)
		_slot_params.append({})
	_effect_names.append("")
	_rebuild_slot_ui()
	_update_preview()

## 删除效果块（移除该块的5个槽位 + 名称）
func _on_delete_effect_block(block_idx: int):
	var max_blocks = _slots.size() / 5
	if block_idx < 0 or block_idx >= max_blocks:
		return
	var base = block_idx * 5
	# 从扁平数组中移除该块的5个槽位
	for i in range(5):
		_slots.remove_at(base)
		_slot_buttons.remove_at(base)
		_slot_params.remove_at(base)
	# 移除效果名
	if block_idx < _effect_names.size():
		_effect_names.remove_at(block_idx)
	_rebuild_slot_ui()
	_update_preview()

## 校验槽位，返回提示文本列表
## 按固定5槽位一组（每个效果块=TR/C/A/T/CO各1行）
func _validate_slots() -> Array[String]:
	var hints: Array[String] = []
	var max_blocks = _slots.size() / 5
	if max_blocks == 0:
		return hints
	
	for bi in range(max_blocks):
		var base = bi * 5
		# 检查该块是否有任何组件
		var has_any = false
		var has_tr = false
		var has_a = false
		var has_t = false
		for off in range(5):
			if _slots[base + off] != "":
				has_any = true
				if off == 0: has_tr = true
				if off == 2: has_a = true
				if off == 3: has_t = true
		
		if not has_any:
			continue  # 完全空的块不校验
		
		var missing: Array[String] = []
		if not has_tr:
			missing.append("⚡触发器")
		if not has_a:
			missing.append("🎯动作")
		if not has_t:
			missing.append("🎯目标")
		
		if missing.size() > 0:
			hints.append("⚠️ 效果" + str(bi + 1) + "：缺少 " + "、".join(missing))
		else:
			# ★ 检查动作×目标互斥
			var a_cid = _slots[base + 2]
			var t_cid = _slots[base + 3]
			if Global.is_action_target_mutex(a_cid, t_cid):
				var a_name = Global._circuit_map.get(a_cid, {}).get("name", a_cid)
				var t_name = Global._circuit_map.get(t_cid, {}).get("name", t_cid)
				hints.append("❌ 效果" + str(bi + 1) + "：「" + a_name + "」不能配「" + t_name + "」")
			else:
				hints.append("✅ 效果" + str(bi + 1) + "：完整")
	
	return hints


## 构建纹路效果数据（用于封卡保存）
## 按固定5槽位一组构建效果字典，供BattleManager使用
## 每个效果块：[0]=TR, [1]=C, [2]=A, [3]=T, [4]=CO
func _build_effects_data() -> Array:
	var effects := []
	var max_blocks = _slots.size() / 5
	if max_blocks == 0:
		return effects
	
	for bi in range(max_blocks):
		var base = bi * 5
		var effect: Dictionary = {}
		
		# TR (offset 0)
		var tr_cid = _slots[base + 0]
		if tr_cid != "":
			effect["trigger"] = tr_cid
		
		# C (offset 1) — 条件可以有多个，但固定1行只放1个
		var c_cid = _slots[base + 1]
		if c_cid != "":
			var c_params = _slot_params[base + 1] if (base + 1) < _slot_params.size() else {}
			if not effect.has("conditions"):
				effect["conditions"] = []
			var cond = {"id": c_cid}
			for k in c_params.keys():
				cond[k] = c_params[k]
			effect["conditions"].append(cond)
		
		# A (offset 2)
		var a_cid = _slots[base + 2]
		if a_cid != "":
			effect["action"] = a_cid
			var a_params = _slot_params[base + 2] if (base + 2) < _slot_params.size() else {}
			if not a_params.is_empty():
				var val = a_params.get("数值", a_params.get("value", 0))
				effect["value"] = val
				for k in a_params.keys():
					if k != "数值":
						effect[k] = a_params[k]
		
		# T (offset 3)
		var t_cid = _slots[base + 3]
		if t_cid != "":
			effect["target"] = t_cid
		
		# CO (offset 4) — 约束可以有多个，但固定1行只放1个
		var co_cid = _slots[base + 4]
		if co_cid != "":
			if not effect.has("constraints"):
				effect["constraints"] = []
			effect["constraints"].append(co_cid)
			var co_params = _slot_params[base + 4] if (base + 4) < _slot_params.size() else {}
			if not co_params.is_empty():
				if not effect.has("constraint_params"):
					effect["constraint_params"] = {}
				effect["constraint_params"][co_cid] = co_params
		
		# 效果组必须有trigger、action和target才算完整
		if effect.has("trigger") and effect.has("action") and effect.has("target"):
			# 写入效果名称（非空时才添加）
			var eff_name = _effect_names[bi] if bi < _effect_names.size() else ""
			if eff_name.strip_edges() != "":
				effect["name"] = eff_name.strip_edges()
			effect["desc"] = _build_effect_desc(effect)
			effects.append(effect)
	
	return effects


## 生成效果的可读描述文本（参考 starter_data.json 的 desc 格式）
func _build_effect_desc(effect: Dictionary) -> String:
	var trigger_id = effect.get("trigger", "")
	var action_id = effect.get("action", "")
	var target_id = effect.get("target", "T01")
	var value = effect.get("value", 0)
	
	# 查找名称
	var trigger_name = trigger_id
	for t in Global.circuit_triggers:
		if t.id == trigger_id:
			trigger_name = t.name
			break
	
	# 查找动作名称
	var action_name = action_id
	for a in Global.circuit_actions:
		if a.id == action_id:
			action_name = a.name
			break
	
	# 查找目标名称
	var target_name = target_id
	for t in Global.circuit_targets:
		if t.id == target_id:
			target_name = t.name
			break
	
	# 目标描述 (target_pre)
	var target_pre = ""
	if target_name == "全场":
		target_pre = "对所有单位"
	elif target_name == "敌方单体":
		target_pre = "对敌方单体"
	elif target_name == "己方单体":
		target_pre = "对己方单体"
	elif target_name == "自身":
		target_pre = "自身"
	elif target_name == "敌方英雄":
		target_pre = "对敌方英雄"
	elif target_name == "己方英雄":
		target_pre = "对己方英雄"
	elif target_name == "手牌":
		target_pre = "从手牌"
	elif target_name == "墓地":
		target_pre = "从墓地"
	elif target_name == "卡组":
		target_pre = "从卡组"
	elif target_name == "除外区":
		target_pre = "从除外区"
	else:
		target_pre = target_name
	

	# 构建描述
	var parts: Array[String] = []
	
	# 触发描述
	parts.append("【" + trigger_name + "】")
	
	# 条件描述（带参数，如字段名/比较符+数值/纯数值）
	var conds = effect.get("conditions", [])
	if conds.size() > 0:
		var cond_strs := []
		for cond in conds:
			var cond_id = cond.get("id", "")
			var cond_name = cond_id
			for c in Global.circuit_conditions:
				if c.id == cond_id:
					cond_name = c.name
					break
			# 拼接条件参数
			var param_str = ""
			var param_type = ""
			for c in Global.circuit_conditions:
				if c.id == cond_id:
					param_type = c.get("params", "无")
					break
			if param_type == "字段名":
				var field_val = cond.get("字段名", cond.get("field", ""))
				if field_val != "":
					param_str = "「" + field_val + "」"
			elif param_type == "比较符+数值":
				var comp = cond.get("compare", cond.get("comparison", "≥"))
				var val = cond.get("value", cond.get("数值", 0))
				param_str = " " + comp + " " + str(val)
			elif param_type == "数值":
				var val = cond.get("value", cond.get("数值", 0))
				param_str = " " + str(val)
			if param_str != "":
				cond_strs.append(cond_name + param_str)
			else:
				cond_strs.append(cond_name)
		if cond_strs.size() > 0:
			parts.append("（" + "、".join(cond_strs) + "）")
	

	# 动作描述
	if action_name == "破坏":
		parts.append("破坏" + target_pre)
	elif action_name == "效果伤害":
		parts.append("对" + target_pre + "造成" + str(value) + "点伤害")
	elif action_name == "恢复生命":
		parts.append("恢复" + target_pre + str(value) + "点生命")
	elif action_name == "抽牌":
		parts.append("抽牌" + str(value) + "张")
	elif action_name == "检索卡":
		parts.append("检索1张卡牌")
	elif action_name == "检索字段卡":
		parts.append("检索1张字段卡牌")
	elif action_name == "除外":
		parts.append("除外" + target_pre)
	elif action_name == "弹回手牌":
		parts.append("将" + target_pre + "弹回手牌")
	elif action_name == "弹回卡组":
		parts.append("将" + target_pre + "弹回卡组")
	elif action_name == "墓地回收":
		parts.append("回收" + target_pre + "1张卡牌")
	elif action_name == "除外回收":
		parts.append("回收" + target_pre + "1张卡牌")
	elif action_name == "卡组堆墓":
		parts.append("从卡组将" + str(value) + "张卡牌送入墓地")
	elif action_name == "召唤衍生物":
		parts.append("召唤" + str(value) + "个衍生物")
	elif action_name == "攻击力增减(永久)":
		parts.append("攻击力" + ("+" if value >= 0 else "") + str(value))
	elif action_name == "生命值增减(永久)":
		parts.append("生命值" + ("+" if value >= 0 else "") + str(value))
	elif action_name == "回合内攻命增减":
		parts.append("本回合攻命" + ("+" if value >= 0 else "") + str(value))
	elif action_name == "手牌特召":
		parts.append("从手牌特殊召唤")
	elif action_name == "墓地特召":
		parts.append("从墓地特殊召唤")
	elif action_name == "卡组特召":
		parts.append("从卡组特殊召唤")
	elif action_name == "送入墓地(非破坏)":
		parts.append("将" + target_pre + "送入墓地")
	elif action_name == "交换攻防":
		parts.append("交换攻击力与生命值")
	elif action_name == "无法攻击":
		parts.append("使" + target_pre + "无法攻击")
	else:
		parts.append(action_name + "(" + target_name + ")")
		if value != 0:
			parts.append(" 数值:" + str(value))
	
	# 约束（带数值：CO03支付生命×N / CO04舍弃手牌×N / CO12受伤害×N）
	var cons = effect.get("constraints", [])
	if cons.size() > 0:
		var co_strs := []
		for co_id in cons:
			match co_id:
				"CO03":
					co_strs.append("支付生命×" + str(Global.get_constraint_param(effect, "CO03", 10)))
				"CO04":
					co_strs.append("舍弃手牌×" + str(Global.get_constraint_param(effect, "CO04", 1)))
				"CO12":
					co_strs.append("发动后受伤害×" + str(Global.get_constraint_param(effect, "CO12", 5)))
				"CO01":
					co_strs.append("一回合一次")
				"CO02":
					co_strs.append("一局一次")
				_:
					# 兜底：查名称
					var found = false
					for co in Global.circuit_constraints:
						if co.id == co_id:
							co_strs.append(co.name)
							found = true
							break
					if not found:
						co_strs.append(co_id)
		parts.append("（" + "、".join(co_strs) + "）")
	
	return "".join(parts)

## 获取组件前缀（TR/C/A/T/CO）
func _get_component_prefix(cid: String) -> String:
	if cid.begins_with("TR"):
		return "TR"
	elif cid.begins_with("CO"):
		return "CO"
	elif cid.begins_with("C"):
		return "C"
	elif cid.begins_with("A"):
		return "A"
	elif cid.begins_with("T"):
		return "T"
	return ""

## 清空单个槽位
func _clear_slot(idx: int):
	if idx < _slots.size():
		_slots[idx] = ""
		_slot_params[idx] = {}
		_rebuild_slot_ui()
		_update_preview()

## 打开槽位选择（根据槽位位置自动确定类型，直接打开组件列表）
## slot_idx = block_idx * 5 + offset，offset 决定组件类型：
## 0=TR(触发器), 1=C(条件), 2=A(动作), 3=T(目标), 4=CO(约束)
func _open_slot_picker(slot_idx: int):
	if slot_idx >= _slots.size():
		return
	# 如果槽位已经是空的，且纹路槽位已满，不允许再选
	if _slots[slot_idx] == "":
		var placed = 0
		for i in range(_slots.size()):
			if _slots[i] != "":
				placed += 1
		if placed >= _max_slots:
			_show_popup("纹路槽位已满（" + str(_max_slots) + "/" + str(_max_slots) + "）", Color("#FFD700"))
			return
	var offset = slot_idx % 5
	var comp_type = ""
	var type_label = ""
	match offset:
		0: comp_type = "TR"; type_label = "⚡ 触发器"
		1: comp_type = "C";  type_label = "❓ 条件"
		2: comp_type = "A";  type_label = "🎯 动作"
		3: comp_type = "T";  type_label = "🎯 目标"
		4: comp_type = "CO"; type_label = "🔒 约束"
		_: return
	# 直接打开组件选择弹窗（传 null 作为 overlay，_open_comp_picker 会先 _close_picker(null) 安全跳过）
	_open_comp_picker(slot_idx, comp_type, type_label, null)
func _clear_slot_from_picker(slot_idx: int, overlay: ColorRect):
	_clear_slot(slot_idx)
	_close_picker(overlay)

## 组件选择弹窗
func _open_comp_picker(slot_idx: int, comp_type: String, title_text: String, slot_picker_overlay: ColorRect):
	# 先关闭类别选择弹窗
	_close_picker(slot_picker_overlay)
	
	# 获取所有已解锁的对应类别组件
	var all_comps := []
	match comp_type:
		"TR": all_comps = Global.get_all_triggers()
		"C": all_comps = Global.get_all_conditions()
		"A": all_comps = Global.get_all_actions()
		"T": all_comps = Global.get_all_targets()
		"CO": all_comps = Global.get_all_constraints()
	
	# 根据解锁状态过滤
	var available = []
	for comp in all_comps:
		if CircuitManager.is_unlocked(comp["id"]):
			available.append(comp)
	
	# 如果没有可选组件
	if available.size() == 0:
		_show_popup("⚠️ 暂无可用组件（需解锁）", Color("#FF6B6B"))
		return
	
	# 创建弹窗
	var overlay = ColorRect.new()
	overlay.name = "CompPickerOverlay"
	overlay.color = Color(0.0, 0.0, 0.0, 0.6)
	overlay.anchor_left = 0.0; overlay.anchor_top = 0.0; overlay.anchor_right = 1.0; overlay.anchor_bottom = 1.0
	overlay.mouse_filter = MOUSE_FILTER_STOP
	overlay.gui_input.connect(_on_picker_overlay_clicked.bind(overlay))
	add_child(overlay)
	
	var panel = Panel.new()
	panel.name = "CompPickerPanel"
	panel.anchor_left = 0.05; panel.anchor_top = 0.15; panel.anchor_right = 0.95; panel.anchor_bottom = 0.85
	panel.clip_contents = true
	var ps = StyleBoxFlat.new()
	ps.bg_color = Global.current.bg
	ps.border_width_left = 3; ps.border_width_right = 3; ps.border_width_top = 3; ps.border_width_bottom = 3
	ps.border_color = Global.current.topbar_border
	ps.corner_radius_top_left = 16; ps.corner_radius_top_right = 16
	ps.corner_radius_bottom_left = 16; ps.corner_radius_bottom_right = 16
	panel.add_theme_stylebox_override("panel", ps)
	overlay.add_child(panel)
	
	# 标题
	var title = Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 55)
	title.add_theme_color_override("font_color", Global.current.title)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.anchor_left = 0.0; title.anchor_top = 0.0; title.anchor_right = 1.0; title.anchor_bottom = 0.0
	title.offset_left = 0; title.offset_top = Global.ph(0.02); title.offset_right = 0; title.offset_bottom = Global.ph(0.08)
	panel.add_child(title)
	
	# 滚动列表 - 留出底部空间给关闭按钮
	var scroll = ScrollContainer.new()
	scroll.name = "CompPickerScroll"
	scroll.anchor_left = 0.0; scroll.anchor_top = 0.0; scroll.anchor_right = 1.0; scroll.anchor_bottom = 1.0
	scroll.offset_left = Global.pw(0.05); scroll.offset_top = Global.ph(0.08)
	scroll.offset_right = Global.pw(-0.05); scroll.offset_bottom = -Global.ph(0.18)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	panel.add_child(scroll)
	
	var vbox = VBoxContainer.new()
	vbox.name = "PickerVBox"
	vbox.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	scroll.add_child(vbox)
	
	var row_index := 0
	for comp in available:
		var cid = comp.get("id", "")
		var cname = comp.get("name", "未知")
		
		var row_panel = Panel.new()
		var rps = StyleBoxFlat.new()
		rps.bg_color = Global.current.topbar_bg if row_index % 2 == 0 else Color.TRANSPARENT
		row_panel.add_theme_stylebox_override("panel", rps)
		row_panel.custom_minimum_size = Vector2(0, Global.ph(0.09))
		row_panel.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
		row_panel.mouse_filter = MOUSE_FILTER_PASS
		vbox.add_child(row_panel)
		
		var hbox = HBoxContainer.new()
		hbox.size_flags_horizontal = SIZE_FILL
		hbox.size_flags_vertical = SIZE_FILL
		hbox.mouse_filter = MOUSE_FILTER_IGNORE
		row_panel.add_child(hbox)
		
		# 组件信息
		var info_vbox = VBoxContainer.new()
		info_vbox.size_flags_horizontal = SIZE_EXPAND
		hbox.add_child(info_vbox)
		
		var name_label = Label.new()
		name_label.text = cid + " - " + cname
		name_label.add_theme_font_size_override("font_size", 40)
		name_label.add_theme_color_override("font_color", Global.current.title)
		info_vbox.add_child(name_label)
		
		# 额外信息
		var extra = ""
		if comp.has("speed"):
			extra = "速度:" + str(comp.speed)
		elif comp.has("modifier"):
			extra = "修正系数:" + str(comp.modifier)
		elif comp.has("base_energy"):
			extra = "基准能量:" + str(comp.base_energy)
		elif comp.has("energy_adj"):
			extra = "能量调整:" + str(comp.energy_adj)
		
		if extra != "":
			var extra_label = Label.new()
			extra_label.text = extra
			extra_label.add_theme_font_size_override("font_size", 36)
			extra_label.add_theme_color_override("font_color", Global.current.btn_text)
			info_vbox.add_child(extra_label)
		
		var select_btn = Button.new()
		select_btn.text = "选择"
		select_btn.add_theme_font_size_override("font_size", 45)
		select_btn.custom_minimum_size = Vector2(Global.pw(0.1), 0)
		select_btn.pressed.connect(_on_pick_component.bind(slot_idx, cid, overlay))
		hbox.add_child(select_btn)
		
		row_index += 1
	
	# 清空按钮（仅当已有组件时显示）
	if slot_idx < _slots.size() and _slots[slot_idx] != "":
		var clear_btn = Button.new()
		clear_btn.text = "🗑️ 清空"
		clear_btn.add_theme_font_size_override("font_size", 40)
		var cbs = StyleBoxFlat.new()
		cbs.bg_color = Color("#FF4444")
		cbs.bg_color.a = 0.2
		cbs.corner_radius_top_left = 10; cbs.corner_radius_top_right = 10
		cbs.corner_radius_bottom_left = 10; cbs.corner_radius_bottom_right = 10
		clear_btn.add_theme_stylebox_override("normal", cbs)
		clear_btn.add_theme_color_override("font_color", Color("#FF6B6B"))
		clear_btn.anchor_left = 0.05; clear_btn.anchor_top = 1.0; clear_btn.anchor_right = 0.3; clear_btn.anchor_bottom = 1.0
		clear_btn.offset_left = 0; clear_btn.offset_top = Global.ph(-0.15); clear_btn.offset_right = 0; clear_btn.offset_bottom = Global.ph(-0.02)
		clear_btn.pressed.connect(_clear_slot_from_picker.bind(slot_idx, overlay))
		panel.add_child(clear_btn)
	
	# 关闭按钮 - 固定在面板底部，滚动列表下方，不遮挡
	var close_btn = Button.new()
	close_btn.text = "✕ 关闭"
	close_btn.add_theme_font_size_override("font_size", 45)
	var cs = StyleBoxFlat.new()
	cs.bg_color = Global.current.btn_bg
	cs.border_width_left = 2; cs.border_width_right = 2; cs.border_width_top = 2; cs.border_width_bottom = 2
	cs.border_color = Color("#888888")
	cs.corner_radius_top_left = 12; cs.corner_radius_top_right = 12
	cs.corner_radius_bottom_left = 12; cs.corner_radius_bottom_right = 12
	cs.content_margin_left = 24; cs.content_margin_right = 24
	close_btn.add_theme_stylebox_override("normal", cs)
	close_btn.add_theme_color_override("font_color", Global.current.btn_text)
	close_btn.anchor_left = 0.3; close_btn.anchor_top = 1.0; close_btn.anchor_right = 0.7; close_btn.anchor_bottom = 1.0
	close_btn.offset_left = 0; close_btn.offset_top = Global.ph(-0.15); close_btn.offset_right = 0; close_btn.offset_bottom = Global.ph(-0.02)
	close_btn.pressed.connect(_close_picker.bind(overlay))
	panel.add_child(close_btn)
func _on_pick_component(slot_idx: int, comp_id: String, overlay: ColorRect):
	if slot_idx >= _slots.size():
		return
	
	var comp_info = Global.get_circuit_by_id(comp_id)
	if comp_info.is_empty():
		_slots[slot_idx] = comp_id
		_slot_params[slot_idx] = {}
		_rebuild_slot_ui()
		_close_picker(overlay)
		_update_preview()
		return
	
	var prefix = comp_id.substr(0, 2)
	# 处理单字母前缀（A/C/T）vs 双字母前缀（TR/CO）
	if prefix.length() >= 2 and prefix[1] >= "0" and prefix[1] <= "9":
		prefix = prefix[0]

	# A类动作：检查是否需要输入数值
	if prefix == "A":
		var base_energy = comp_info.get("base_energy", 0.0)
		print("[DEBUG] 选中A类组件: ", comp_id, " base_energy=", base_energy, " type=", typeof(base_energy))
		if base_energy is String:
			print("[DEBUG] base_energy是字符串，弹窗!")
			# 从 base_energy 中提取参数名，统一存为"数值"
			var param_key = "数值"  # 默认
			# 需要输入数值，弹窗
			_close_picker(overlay)
			# A20/A21/A23 允许负数（减攻击/减生命/回合内减益）
			var min_val = -99 if comp_id in ["A20", "A21", "A23"] else 1
			var max_val = 99
			_show_value_input(slot_idx, comp_id, param_key, param_key, min_val, max_val)
			return
		else:
			print("[DEBUG] base_energy是数值，直接赋值")

	# C类条件：检查是否需要输入参数
	if prefix == "C":
		var params = comp_info.get("params", "无")
		if params != "无":
			_close_picker(overlay)
			if params == "字段名":
				_show_text_input(slot_idx, comp_id, "字段名", "请输入字段名")
			elif params == "比较符+数值":
				_show_comparison_input(slot_idx, comp_id, "比较符+数值")
			else:
				var cr = _get_condition_range(comp_id)
				_show_value_input(slot_idx, comp_id, params, params, cr.min, cr.max)
			return
	
	# CO类约束：检查 energy_adjust 是否需要数值 X
	if prefix == "CO":
		var energy_adjust = comp_info.get("energy_adjust", 0.0)
		if energy_adjust is String and "X" in energy_adjust:
			print("[DEBUG] 选中CO类组件: ", comp_id, " energy_adjust=", energy_adjust)
			var param_key = "数值"
			if "×" in energy_adjust:
				param_key = energy_adjust.split("×")[0].strip_edges().lstrip("-")
			_close_picker(overlay)
			_show_value_input(slot_idx, comp_id, param_key, param_key, 1, 99)
			return

	# 其他组件：直接赋值
	_slots[slot_idx] = comp_id
	_slot_params[slot_idx] = {}
	_rebuild_slot_ui()
	_close_picker(overlay)
	_update_preview()
	# 教程引导：纹路放置触发器/动作/目标时推进
	if not _tutorial_done:
		if _tutorial_step == 6 and comp_id.begins_with("TR"):
			_tutorial_advance("slot_trigger")
		elif _tutorial_step == 7 and comp_id.begins_with("A"):
			_tutorial_advance("slot_action")
		elif _tutorial_step == 8 and comp_id.begins_with("T"):
			_tutorial_advance("slot_target")

## 数值输入弹窗（用于A类和C类）
func _show_value_input(slot_idx: int, comp_id: String, param_name: String, label_text: String, min_val: int = 1, max_val: int = 99):
	var overlay = ColorRect.new()
	overlay.name = "ValueInputOverlay"
	overlay.color = Color(0.0, 0.0, 0.0, 0.6)
	overlay.anchor_left = 0.0; overlay.anchor_top = 0.0; overlay.anchor_right = 1.0; overlay.anchor_bottom = 1.0
	overlay.mouse_filter = MOUSE_FILTER_STOP
	overlay.gui_input.connect(_on_picker_overlay_clicked.bind(overlay))
	add_child(overlay)

	var panel = PanelContainer.new()
	panel.name = "ValueInputPanel"
	panel.anchor_left = 0.2; panel.anchor_top = 0.3; panel.anchor_right = 0.8; panel.anchor_bottom = 0.7
	panel.clip_contents = true
	var ps = StyleBoxFlat.new()
	ps.bg_color = Global.current.bg
	ps.border_width_left = 3; ps.border_width_right = 3; ps.border_width_top = 3; ps.border_width_bottom = 3
	ps.border_color = Global.current.topbar_border
	ps.corner_radius_top_left = 16; ps.corner_radius_top_right = 16
	ps.corner_radius_bottom_left = 16; ps.corner_radius_bottom_right = 16
	ps.content_margin_left = 16; ps.content_margin_right = 16; ps.content_margin_top = 16; ps.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", ps)
	overlay.add_child(panel)

	var comp_info = Global.get_circuit_by_id(comp_id)
	var comp_name = comp_info.get("name", comp_id)

	var vbox = VBoxContainer.new()
	vbox.name = "ValueInputVBox"
	vbox.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	vbox.size_flags_vertical = SIZE_EXPAND | SIZE_FILL
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	var title = Label.new()
	title.text = "⚙️ " + comp_name + "\n" + label_text
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Global.current.title)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	title.size_flags_vertical = SIZE_EXPAND
	vbox.add_child(title)

	# 数值输入行：[-] 数值 [+]
	var val_hbox = HBoxContainer.new()
	val_hbox.name = "ValHBox"
	val_hbox.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	val_hbox.size_flags_vertical = SIZE_EXPAND
	val_hbox.alignment = 1
	vbox.add_child(val_hbox)

	var dec_btn = Button.new()
	dec_btn.text = "−"
	dec_btn.add_theme_font_size_override("font_size", 50)
	var ds = StyleBoxFlat.new()
	ds.bg_color = Global.current.btn_bg
	ds.border_width_left = 2; ds.border_width_right = 2; ds.border_width_top = 2; ds.border_width_bottom = 2
	ds.border_color = Color("#888888")
	ds.corner_radius_top_left = 8; ds.corner_radius_bottom_left = 8
	ds.content_margin_left = 12; ds.content_margin_right = 12
	dec_btn.add_theme_stylebox_override("normal", ds)
	dec_btn.add_theme_color_override("font_color", Global.current.btn_text)
	dec_btn.custom_minimum_size = Vector2(Global.pw(0.1), Global.ph(0.07))
	val_hbox.add_child(dec_btn)

	var val_input = LineEdit.new()
	val_input.name = "ValueInput"
	val_input.text = "1"
	val_input.add_theme_font_size_override("font_size", 50)
	val_input.add_theme_color_override("font_color", Global.current.title)
	val_input.add_theme_color_override("font_selected_color", Global.current.topbar_border)
	val_input.add_theme_color_override("caret_color", Global.current.topbar_border)
	val_input.add_theme_constant_override("minimum_character_width", 6)
	val_input.placeholder_text = "输入数值"
	val_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	val_input.expand_to_text_length = false
	val_input.custom_minimum_size = Vector2(Global.pw(0.2), Global.ph(0.07))
	val_input.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	# 限制输入为数字
	val_input.text_changed.connect(_on_numeric_input_filter.bind(val_input))
	val_hbox.add_child(val_input)

	var inc_btn = Button.new()
	inc_btn.text = "+"
	inc_btn.add_theme_font_size_override("font_size", 50)
	var is_ = StyleBoxFlat.new()
	is_.bg_color = Global.current.btn_bg
	is_.border_width_left = 2; is_.border_width_right = 2; is_.border_width_top = 2; is_.border_width_bottom = 2
	is_.border_color = Color("#888888")
	is_.corner_radius_top_right = 8; is_.corner_radius_bottom_right = 8
	is_.content_margin_left = 12; is_.content_margin_right = 12
	inc_btn.add_theme_stylebox_override("normal", is_)
	inc_btn.add_theme_color_override("font_color", Global.current.btn_text)
	inc_btn.custom_minimum_size = Vector2(Global.pw(0.1), Global.ph(0.07))
	val_hbox.add_child(inc_btn)

	# 按钮行
	var btn_hbox = HBoxContainer.new()
	btn_hbox.name = "BtnHBox"
	btn_hbox.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	btn_hbox.size_flags_vertical = SIZE_EXPAND
	btn_hbox.alignment = 1
	btn_hbox.add_theme_constant_override("separation", 16)
	vbox.add_child(btn_hbox)

	var confirm_btn = Button.new()
	confirm_btn.text = "✓ 确定"
	confirm_btn.add_theme_font_size_override("font_size", 45)
	var cs = StyleBoxFlat.new()
	cs.bg_color = Color("#2d6a4f")
	cs.border_width_left = 2; cs.border_width_right = 2; cs.border_width_top = 2; cs.border_width_bottom = 2
	cs.border_color = Color("#52b788")
	cs.corner_radius_top_left = 12; cs.corner_radius_top_right = 12
	cs.corner_radius_bottom_left = 12; cs.corner_radius_bottom_right = 12
	cs.content_margin_left = 24; cs.content_margin_right = 24
	confirm_btn.add_theme_stylebox_override("normal", cs)
	confirm_btn.add_theme_color_override("font_color", Color("#d8f3dc"))
	confirm_btn.custom_minimum_size = Vector2(Global.pw(0.15), Global.ph(0.07))
	confirm_btn.pressed.connect(_on_value_input_confirm.bind(slot_idx, comp_id, param_name, val_input, overlay))
	btn_hbox.add_child(confirm_btn)

	var cancel_btn = Button.new()
	cancel_btn.text = "✗ 取消"
	cancel_btn.add_theme_font_size_override("font_size", 45)
	var cs2 = StyleBoxFlat.new()
	cs2.bg_color = Global.current.btn_bg
	cs2.border_width_left = 2; cs2.border_width_right = 2; cs2.border_width_top = 2; cs2.border_width_bottom = 2
	cs2.border_color = Color("#888888")
	cs2.corner_radius_top_left = 12; cs2.corner_radius_top_right = 12
	cs2.corner_radius_bottom_left = 12; cs2.corner_radius_bottom_right = 12
	cs2.content_margin_left = 24; cs2.content_margin_right = 24
	cancel_btn.add_theme_stylebox_override("normal", cs2)
	cancel_btn.add_theme_color_override("font_color", Global.current.btn_text)
	cancel_btn.custom_minimum_size = Vector2(Global.pw(0.15), Global.ph(0.07))
	cancel_btn.pressed.connect(_close_picker.bind(overlay))
	btn_hbox.add_child(cancel_btn)

	# 加减按钮事件
	dec_btn.pressed.connect(_on_value_stepper.bind(val_input, -1, min_val, max_val))
	inc_btn.pressed.connect(_on_value_stepper.bind(val_input, 1, min_val, max_val))
## 数值步进
func _on_value_stepper(input: LineEdit, delta: int, min_val: int, max_val: int):
	var val = int(input.text) + delta
	val = clampi(val, min_val, max_val)
	input.text = str(val)

## 数值输入过滤（允许数字和负号）
func _on_numeric_input_filter(new_text: String, input: LineEdit):
	var filtered = ""
	for i in range(new_text.length()):
		var c = new_text[i]
		if c in "0123456789":
			filtered += c
		elif c == "-" and i == 0:
			# 仅允许在开头输入负号（支持负数，如-5）
			filtered += c
	if filtered != new_text:
		input.text = filtered
		input.caret_column = filtered.length()

## 数值输入确认
func _on_value_input_confirm(slot_idx: int, comp_id: String, param_name: String, val_input: LineEdit, overlay: ColorRect):
	_slots[slot_idx] = comp_id
	_slot_params[slot_idx] = {param_name: int(val_input.text)}
	_rebuild_slot_ui()
	_close_picker(overlay)
	_update_preview()
	# 教程引导：纹路放置动作（A类带数值输入）时推进
	if not _tutorial_done and _tutorial_step == 7 and comp_id.begins_with("A"):
		_tutorial_advance("slot_action")

## 文本输入弹窗（用于C类字段名）
func _show_text_input(slot_idx: int, comp_id: String, param_name: String, label_text: String):
	var overlay = ColorRect.new()
	overlay.name = "TextInputOverlay"
	overlay.color = Color(0.0, 0.0, 0.0, 0.6)
	overlay.anchor_left = 0.0; overlay.anchor_top = 0.0; overlay.anchor_right = 1.0; overlay.anchor_bottom = 1.0
	overlay.mouse_filter = MOUSE_FILTER_STOP
	overlay.gui_input.connect(_on_picker_overlay_clicked.bind(overlay))
	add_child(overlay)
	
	var panel = PanelContainer.new()
	panel.name = "TextInputPanel"
	panel.anchor_left = 0.15; panel.anchor_top = 0.3; panel.anchor_right = 0.85; panel.anchor_bottom = 0.7
	panel.clip_contents = true
	var ps = StyleBoxFlat.new()
	ps.bg_color = Global.current.bg
	ps.border_width_left = 3; ps.border_width_right = 3; ps.border_width_top = 3; ps.border_width_bottom = 3
	ps.border_color = Global.current.topbar_border
	ps.corner_radius_top_left = 16; ps.corner_radius_top_right = 16
	ps.corner_radius_bottom_left = 16; ps.corner_radius_bottom_right = 16
	ps.content_margin_left = 16; ps.content_margin_right = 16; ps.content_margin_top = 16; ps.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", ps)
	overlay.add_child(panel)
	
	var comp_info = Global.get_circuit_by_id(comp_id)
	var comp_name = comp_info.get("name", comp_id)
	
	var vbox = VBoxContainer.new()
	vbox.name = "TextInputVBox"
	vbox.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	vbox.size_flags_vertical = SIZE_EXPAND | SIZE_FILL
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)
	
	var title = Label.new()
	title.text = "⚙️ " + comp_name + "\n" + label_text
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Global.current.title)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	title.size_flags_vertical = SIZE_EXPAND
	vbox.add_child(title)
	
	var line_edit = LineEdit.new()
	line_edit.name = "TextInputField"
	line_edit.placeholder_text = "请输入" + param_name
	line_edit.add_theme_font_size_override("font_size", 40)
	line_edit.add_theme_color_override("font_color", Global.current.title)
	line_edit.add_theme_color_override("font_selected_color", Global.current.topbar_border)
	line_edit.add_theme_color_override("caret_color", Global.current.topbar_border)
	line_edit.custom_minimum_size = Vector2(0, Global.ph(0.06))
	line_edit.size_flags_horizontal = SIZE_FILL
	line_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(line_edit)
	
	# 按钮行
	var btn_hbox = HBoxContainer.new()
	btn_hbox.name = "BtnHBox"
	btn_hbox.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	btn_hbox.size_flags_vertical = SIZE_EXPAND
	btn_hbox.alignment = 1
	btn_hbox.add_theme_constant_override("separation", 16)
	vbox.add_child(btn_hbox)
	
	var confirm_btn = Button.new()
	confirm_btn.text = "✓ 确定"
	confirm_btn.add_theme_font_size_override("font_size", 45)
	var cs = StyleBoxFlat.new()
	cs.bg_color = Color("#2d6a4f")
	cs.border_width_left = 2; cs.border_width_right = 2; cs.border_width_top = 2; cs.border_width_bottom = 2
	cs.border_color = Color("#52b788")
	cs.corner_radius_top_left = 12; cs.corner_radius_top_right = 12
	cs.corner_radius_bottom_left = 12; cs.corner_radius_bottom_right = 12
	cs.content_margin_left = 24; cs.content_margin_right = 24
	confirm_btn.add_theme_stylebox_override("normal", cs)
	confirm_btn.add_theme_color_override("font_color", Color("#d8f3dc"))
	confirm_btn.custom_minimum_size = Vector2(Global.pw(0.15), Global.ph(0.07))
	confirm_btn.pressed.connect(_on_text_input_confirm.bind(slot_idx, comp_id, param_name, line_edit, overlay))
	btn_hbox.add_child(confirm_btn)
	
	var cancel_btn = Button.new()
	cancel_btn.text = "✗ 取消"
	cancel_btn.add_theme_font_size_override("font_size", 45)
	var cs2 = StyleBoxFlat.new()
	cs2.bg_color = Global.current.btn_bg
	cs2.border_width_left = 2; cs2.border_width_right = 2; cs2.border_width_top = 2; cs2.border_width_bottom = 2
	cs2.border_color = Color("#888888")
	cs2.corner_radius_top_left = 12; cs2.corner_radius_top_right = 12
	cs2.corner_radius_bottom_left = 12; cs2.corner_radius_bottom_right = 12
	cs2.content_margin_left = 24; cs2.content_margin_right = 24
	cancel_btn.add_theme_stylebox_override("normal", cs2)
	cancel_btn.add_theme_color_override("font_color", Global.current.btn_text)
	cancel_btn.custom_minimum_size = Vector2(Global.pw(0.15), Global.ph(0.07))
	cancel_btn.pressed.connect(_close_picker.bind(overlay))
	btn_hbox.add_child(cancel_btn)

## 文本输入确认
func _on_text_input_confirm(slot_idx: int, comp_id: String, param_name: String, line_edit: LineEdit, overlay: ColorRect):
	_slots[slot_idx] = comp_id
	# 清除首尾空格（含全角空格），避免字段名匹配失败导致条件不触发
	var _raw = line_edit.text
	var _clean = _raw.replace("　", " ").strip_edges()
	_slot_params[slot_idx] = {param_name: _clean}
	_rebuild_slot_ui()
	_close_picker(overlay)
	_update_preview()

## 比较符+数值输入弹窗（用于C02/C07/C09/C11/C12）
func _show_comparison_input(slot_idx: int, comp_id: String, label_text: String):
	var overlay = ColorRect.new()
	overlay.name = "CompInputOverlay"
	overlay.color = Color(0.0, 0.0, 0.0, 0.6)
	overlay.anchor_left = 0.0; overlay.anchor_top = 0.0; overlay.anchor_right = 1.0; overlay.anchor_bottom = 1.0
	overlay.mouse_filter = MOUSE_FILTER_STOP
	overlay.gui_input.connect(_on_picker_overlay_clicked.bind(overlay))
	add_child(overlay)
	
	var panel = PanelContainer.new()
	panel.name = "CompInputPanel"
	panel.anchor_left = 0.15; panel.anchor_top = 0.3; panel.anchor_right = 0.85; panel.anchor_bottom = 0.7
	panel.clip_contents = true
	var ps = StyleBoxFlat.new()
	ps.bg_color = Global.current.bg
	ps.border_width_left = 3; ps.border_width_right = 3; ps.border_width_top = 3; ps.border_width_bottom = 3
	ps.border_color = Global.current.topbar_border
	ps.corner_radius_top_left = 16; ps.corner_radius_top_right = 16
	ps.corner_radius_bottom_left = 16; ps.corner_radius_bottom_right = 16
	ps.content_margin_left = 16; ps.content_margin_right = 16; ps.content_margin_top = 16; ps.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", ps)
	overlay.add_child(panel)
	
	var comp_info = Global.get_circuit_by_id(comp_id)
	var comp_name = comp_info.get("name", comp_id)
	
	var vbox = VBoxContainer.new()
	vbox.name = "CompInputVBox"
	vbox.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	vbox.size_flags_vertical = SIZE_EXPAND | SIZE_FILL
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)
	
	var title = Label.new()
	title.text = "⚙️ " + comp_name + "\n" + label_text
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Global.current.title)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	title.size_flags_vertical = SIZE_EXPAND
	vbox.add_child(title)
	
	# 比较符选择行
	var comp_hbox = HBoxContainer.new()
	comp_hbox.name = "CompHBox"
	comp_hbox.size_flags_horizontal = SIZE_FILL
	comp_hbox.alignment = 1
	vbox.add_child(comp_hbox)
# 比较符选择行 - 使用按钮代替下拉菜单
	var comp_label = Label.new()
	comp_label.text = "比较符："
	comp_label.add_theme_font_size_override("font_size", 45)
	comp_label.add_theme_color_override("font_color", Global.current.title)
	comp_label.size_flags_horizontal = SIZE_EXPAND
	comp_hbox.add_child(comp_label)
	
	var selected_comp = "="  # 默认选中
	var comp_btns := []  # 存储按钮引用
	var comp_opts = ["≥", "=", "≤"]
	for opt in comp_opts:
		var cbtn = Button.new()
		cbtn.text = opt
		cbtn.add_theme_font_size_override("font_size", 50)
		cbtn.custom_minimum_size = Vector2(Global.pw(0.08), Global.ph(0.06))
		var is_selected = (opt == selected_comp)
		var cbs = StyleBoxFlat.new()
		cbs.bg_color = Color("#6c9bcf") if is_selected else Global.current.btn_bg
		cbs.border_width_left = 2; cbs.border_width_right = 2; cbs.border_width_top = 2; cbs.border_width_bottom = 2
		cbs.border_color = Color("#6c9bcf")
		cbs.corner_radius_top_left = 8; cbs.corner_radius_top_right = 8
		cbs.corner_radius_bottom_left = 8; cbs.corner_radius_bottom_right = 8
		cbtn.add_theme_stylebox_override("normal", cbs)
		cbtn.add_theme_color_override("font_color", Color("#ffffff") if is_selected else Global.current.btn_text)
		cbtn.pressed.connect(_on_comp_btn_selected.bind(comp_btns, cbtn, opt, comp_id))
		comp_hbox.add_child(cbtn)
		comp_btns.append(cbtn)
	
	# 数值输入行：[-] 数值 [+]
	var val_hbox = HBoxContainer.new()
	val_hbox.name = "ValHBox"
	val_hbox.size_flags_horizontal = SIZE_FILL
	val_hbox.alignment = 1
	vbox.add_child(val_hbox)
	
	var val_label = Label.new()
	val_label.text = "数值："
	val_label.add_theme_font_size_override("font_size", 45)
	val_label.add_theme_color_override("font_color", Global.current.title)
	val_label.size_flags_horizontal = SIZE_EXPAND
	val_hbox.add_child(val_label)
	
	var val_dec_btn = Button.new()
	val_dec_btn.text = "−"
	val_dec_btn.add_theme_font_size_override("font_size", 50)
	var vds = StyleBoxFlat.new()
	vds.bg_color = Global.current.btn_bg
	vds.border_width_left = 2; vds.border_width_right = 2; vds.border_width_top = 2; vds.border_width_bottom = 2
	vds.border_color = Color("#888888")
	vds.corner_radius_top_left = 8; vds.corner_radius_bottom_left = 8
	vds.content_margin_left = 12; vds.content_margin_right = 12
	val_dec_btn.add_theme_stylebox_override("normal", vds)
	val_dec_btn.add_theme_color_override("font_color", Global.current.btn_text)
	val_dec_btn.custom_minimum_size = Vector2(Global.pw(0.08), Global.ph(0.06))
	val_hbox.add_child(val_dec_btn)
	
	var val_spin := Label.new()
	val_spin.name = "CompValueVal"
	# ★ 初始值根据条件类型和比较符自适应
	var init_range = _get_comparison_value_range(comp_id, selected_comp)
	val_spin.text = str(init_range.min)
	val_spin.add_theme_font_size_override("font_size", 45)
	val_spin.add_theme_color_override("font_color", Global.current.title)
	val_spin.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val_spin.custom_minimum_size = Vector2(Global.pw(0.12), Global.ph(0.06))
	val_hbox.add_child(val_spin)
	
	var val_inc_btn = Button.new()
	val_inc_btn.text = "+"
	val_inc_btn.add_theme_font_size_override("font_size", 50)
	var vis = StyleBoxFlat.new()
	vis.bg_color = Global.current.btn_bg
	vis.border_width_left = 2; vis.border_width_right = 2; vis.border_width_top = 2; vis.border_width_bottom = 2
	vis.border_color = Color("#888888")
	vis.corner_radius_top_right = 8; vis.corner_radius_bottom_right = 8
	vis.content_margin_left = 12; vis.content_margin_right = 12
	val_inc_btn.add_theme_stylebox_override("normal", vis)
	val_inc_btn.add_theme_color_override("font_color", Global.current.btn_text)
	val_inc_btn.custom_minimum_size = Vector2(Global.pw(0.08), Global.ph(0.06))
	val_hbox.add_child(val_inc_btn)
	
	val_dec_btn.pressed.connect(_on_comp_value_stepper.bind(val_spin, -1, comp_id, comp_btns))
	val_inc_btn.pressed.connect(_on_comp_value_stepper.bind(val_spin, 1, comp_id, comp_btns))
	
	# 按钮行
	var btn_hbox = HBoxContainer.new()
	btn_hbox.name = "BtnHBox"
	btn_hbox.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	btn_hbox.size_flags_vertical = SIZE_EXPAND
	btn_hbox.alignment = 1
	btn_hbox.add_theme_constant_override("separation", 16)
	vbox.add_child(btn_hbox)
	
	# 确定按钮
	var confirm_btn = Button.new()
	confirm_btn.text = "✓ 确定"
	confirm_btn.add_theme_font_size_override("font_size", 40)
	var cs = StyleBoxFlat.new()
	cs.bg_color = Color("#2d6a4f")
	cs.border_width_left = 2; cs.border_width_right = 2; cs.border_width_top = 2; cs.border_width_bottom = 2
	cs.border_color = Color("#52b788")
	cs.corner_radius_top_left = 12; cs.corner_radius_top_right = 12
	cs.corner_radius_bottom_left = 12; cs.corner_radius_bottom_right = 12
	cs.content_margin_left = 24; cs.content_margin_right = 24
	confirm_btn.add_theme_stylebox_override("normal", cs)
	confirm_btn.add_theme_color_override("font_color", Color("#d8f3dc"))
	confirm_btn.custom_minimum_size = Vector2(Global.pw(0.15), Global.ph(0.07))
	confirm_btn.pressed.connect(_on_comp_input_confirm.bind(slot_idx, comp_id, comp_btns, val_spin, overlay))
	btn_hbox.add_child(confirm_btn)
	
	# 取消按钮
	var cancel_btn = Button.new()
	cancel_btn.text = "✗ 取消"
	cancel_btn.add_theme_font_size_override("font_size", 40)
	var cs2 = StyleBoxFlat.new()
	cs2.bg_color = Global.current.btn_bg
	cs2.border_width_left = 2; cs2.border_width_right = 2; cs2.border_width_top = 2; cs2.border_width_bottom = 2
	cs2.border_color = Color("#888888")
	cs2.corner_radius_top_left = 12; cs2.corner_radius_top_right = 12
	cs2.corner_radius_bottom_left = 12; cs2.corner_radius_bottom_right = 12
	cs2.content_margin_left = 24; cs2.content_margin_right = 24
	cancel_btn.add_theme_stylebox_override("normal", cs2)
	cancel_btn.add_theme_color_override("font_color", Global.current.btn_text)
	cancel_btn.custom_minimum_size = Vector2(Global.pw(0.15), Global.ph(0.07))
	cancel_btn.pressed.connect(_close_picker.bind(overlay))
	btn_hbox.add_child(cancel_btn)
	
## 比较符按钮选择 ★ 同时更新数值范围
func _on_comp_btn_selected(comp_btns: Array, selected_btn: Button, opt: String, comp_id: String):
	"""选中比较符按钮，高亮显示，并更新数值范围"""
	for btn in comp_btns:
		var s = StyleBoxFlat.new()
		if btn == selected_btn:
			s.bg_color = Color("#6c9bcf")
			s.border_color = Color("#6c9bcf")
			btn.add_theme_color_override("font_color", Color("#ffffff"))
		else:
			s.bg_color = Global.current.btn_bg
			s.border_color = Color("#888888")
			btn.add_theme_color_override("font_color", Global.current.btn_text)
		s.border_width_left = 2; s.border_width_right = 2; s.border_width_top = 2; s.border_width_bottom = 2
		s.corner_radius_top_left = 8; s.corner_radius_top_right = 8
		s.corner_radius_bottom_left = 8; s.corner_radius_bottom_right = 8
		btn.add_theme_stylebox_override("normal", s)
	# ★ 切换比较符时，钳制当前数值到新范围
	# 通过按钮向上找到弹窗树中的数值 Label（避免前向声明的 null 问题）
	var val_spin: Label = null
	var node: Node = selected_btn
	while node != null:
		val_spin = node.find_child("CompValueVal", true, false) as Label
		if val_spin != null:
			break
		node = node.get_parent()
	if val_spin == null:
		return
	var new_range = _get_comparison_value_range(comp_id, opt)
	var cur_val = int(val_spin.text)
	cur_val = clampi(cur_val, new_range.min, new_range.max)
	val_spin.text = str(cur_val)

## ★ 获取条件纹路的实际数值范围，用于制卡界面的值输入限制
func _get_condition_range(comp_id: String) -> Dictionary:
	match comp_id:
		"C02":  return {"min": 0, "max": 5}     # 场上怪兽数量（单方最多5）
		"C04":  return {"min": 0, "max": 200}   # 生命值比较（HP上限200）
		"C06":  return {"min": 0, "max": 200}   # 生命值差（差值最大200）
		"C07":  return {"min": 0, "max": 10}    # 手牌数（无上限，但实战通常≤10）
		"C08":  return {"min": 0, "max": 10}     # 能量点（最大能量10，每回合+1）
		"C09":  return {"min": 0, "max": 50}    # 墓地卡牌数量（最多50）
		"C11":  return {"min": 0, "max": 50}    # 除外区卡牌数量
		"C12":  return {"min": 0, "max": 60}    # 卡组数量（最多60）
		"C16":  return {"min": 0, "max": 5}     # 控制权异动卡数量（最多5）
		_:
			# A类动作数值/CO类约束X等，默认1-99
			return {"min": 1, "max": 99}

## ★ 根据条件ID和比较符，计算输入值的合理范围
## 简化后：仅支持 ≥、=、≤ 三种比较符，范围统一为条件本身的 min~max
func _get_comparison_value_range(comp_id: String, _compare_str: String) -> Dictionary:
	var r = _get_condition_range(comp_id)
	return {"min": r.min, "max": r.max}

## 比较符数值步进 ★ 动态读取当前选中的比较符（从按钮高亮判断）
func _on_comp_value_stepper(val_label: Label, delta: int, comp_id: String, comp_btns: Array):
	var cur_compare = "="
	for btn in comp_btns:
		var s = btn.get_theme_stylebox("normal")
		if s and s.bg_color == Color("#6c9bcf"):
			cur_compare = btn.text
			break
	var r = _get_comparison_value_range(comp_id, cur_compare)
	var val = int(val_label.text) + delta
	val = clampi(val, r.min, r.max)
	val_label.text = str(val)

## 比较符输入确认
func _on_comp_input_confirm(slot_idx: int, comp_id: String, comp_btns: Array, val_label: Label, overlay: ColorRect):
	# 找到选中的按钮（高亮背景的）
	var comp_text = "="  # 默认
	for btn in comp_btns:
		var s = btn.get_theme_stylebox("normal")
		if s and s.bg_color == Color("#6c9bcf"):
			comp_text = btn.text
			break
	_slots[slot_idx] = comp_id
	var confirm_range = _get_comparison_value_range(comp_id, comp_text)
	var confirm_val = clampi(int(val_label.text), confirm_range.min, confirm_range.max)
	_slot_params[slot_idx] = {"comparison": comp_text, "value": confirm_val}
	_rebuild_slot_ui()
	_close_picker(overlay)
	_update_preview()


# ============================
#  步骤7：属性预览
# ============================
func _build_preview_section(parent: VBoxContainer):
	var panel = PanelContainer.new()
	panel.name = "PreviewPanel"
	var ps = StyleBoxFlat.new()
	ps.bg_color = Global.current.topbar_bg
	ps.corner_radius_top_left = 8; ps.corner_radius_top_right = 8; ps.corner_radius_bottom_left = 8; ps.corner_radius_bottom_right = 8
	ps.content_margin_left = Global.pw(0.03); ps.content_margin_right = Global.pw(0.03)
	ps.content_margin_top = Global.ph(0.01); ps.content_margin_bottom = Global.ph(0.01)
	panel.add_theme_stylebox_override("panel", ps)
	panel.size_flags_horizontal = SIZE_FILL
	panel.mouse_filter = MOUSE_FILTER_PASS
	parent.add_child(panel)
	
	var vbox = VBoxContainer.new()
	vbox.name = "PreviewVBox"
	vbox.size_flags_horizontal = SIZE_FILL
	vbox.mouse_filter = MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", Global.ph(0.005))
	panel.add_child(vbox)
	
	var title = Label.new()
	title.text = "📊 卡牌属性预览"
	title.add_theme_font_size_override("font_size", 50)
	title.add_theme_color_override("font_color", Global.current.title)
	vbox.add_child(title)
	
	var attrs = [
		{"key": "energy_cost", "label": "能量消耗"},
		{"key": "final_atk", "label": "最终攻击"},
		{"key": "final_hp", "label": "最终生命"},
		{"key": "load", "label": "负荷"},
		{"key": "quality", "label": "品质"},
		{"key": "rarity", "label": "稀有度"},
		{"key": "element", "label": "主属性"},
		{"key": "resistance", "label": "抗性"},
		{"key": "durability", "label": "耐久"},
		{"key": "fields_display", "label": "字段"},
		{"key": "description", "label": "描述"},
	]
	
	for attr in attrs:
		var row = HBoxContainer.new()
		row.size_flags_horizontal = SIZE_FILL
		vbox.add_child(row)
		var name_label = Label.new()
		name_label.text = attr["label"] + "："
		name_label.add_theme_font_size_override("font_size", 45)
		name_label.add_theme_color_override("font_color", Global.current.btn_text)
		name_label.size_flags_horizontal = SIZE_EXPAND
		row.add_child(name_label)
		var val_label = Label.new()
		val_label.text = "—"
		val_label.name = "PreviewVal_" + attr["key"]
		val_label.add_theme_font_size_override("font_size", 45)
		val_label.add_theme_color_override("font_color", Global.current.title)
		val_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		val_label.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
		val_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(val_label)
		_preview_labels[attr["key"]] = val_label


# ============================
#  制作按钮
# ============================
func _build_make_button(parent: VBoxContainer):
	var btn = Button.new()
	btn.name = "MakeBtn"
	btn.text = "💾 封卡保存"
	btn.add_theme_font_size_override("font_size", 60)
	btn.size_flags_horizontal = SIZE_FILL
	btn.custom_minimum_size = Vector2(0, Global.ph(0.08))
	
	var s = StyleBoxFlat.new()
	s.bg_color = Global.current.btn_bg
	s.border_width_left = 3; s.border_width_right = 3; s.border_width_top = 3; s.border_width_bottom = 3
	s.border_color = Color("#5cb85c")
	s.corner_radius_top_left = 16; s.corner_radius_top_right = 16; s.corner_radius_bottom_left = 16; s.corner_radius_bottom_right = 16
	s.content_margin_left = 24; s.content_margin_right = 24
	
	var sh = s.duplicate()
	sh.bg_color = Global.current.btn_bg_hover
	var sp = s.duplicate()
	sp.bg_color = Global.current.btn_bg_pressed
	
	btn.add_theme_stylebox_override("normal", s)
	btn.add_theme_stylebox_override("hover", sh)
	btn.add_theme_stylebox_override("pressed", sp)
	btn.add_theme_color_override("font_color", Global.current.btn_text)
	btn.add_theme_color_override("font_hover_color", Global.current.btn_text_hover)
	btn.pressed.connect(_on_make_card)
	parent.add_child(btn)
	
	var hint = Label.new()
	hint.name = "MakeHint"
	hint.text = "请先选择卡基和卡墨"
	hint.add_theme_font_size_override("font_size", 40)
	hint.add_theme_color_override("font_color", Global.current.btn_text)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.custom_minimum_size = Vector2(0, Global.ph(0.05))
	parent.add_child(hint)
	
	_preview_labels["make_hint"] = hint
# ============================
#  能量计算（按纹路组件）
# ============================

# ============================
#  品质随机（封卡时根据卡基区间+称号+卡墨确定最终品质）
# ============================
var QUALITY_NAMES = Global.QUALITY_ORDER
var QUALITY_MULTS = Global.QUALITY_MULTS

func _calc_energy_cost() -> int:
	# 基础能量 = 按攻防计算（可为0）
	var base_energy = floor((_attack + _health) / 2.0)
	
	var circuit_energy := 0.0
	
	# 按固定5槽位一组（与 _build_effects_data 一致）
	var max_blocks = _slots.size() / 5
	if max_blocks == 0:
		return max(1, base_energy)
	
	# 计算每个效果块的能量
	# 公式：每组能量 = (TR能量 + C能量 + A能量) × T倍率 + CO调整
	# ★ 只有同时包含 TR 和 A 的合法组才计算能量
	for bi in range(max_blocks):
		var base = bi * 5
		var tr_energy := 0.0
		var c_energy := 0.0
		var a_energy := 0.0
		var t_modifier := 1.0
		var co_adjust := 0.0
		var has_tr := false
		var has_a := false
		
		# TR (offset 0)
		var tr_cid = _slots[base + 0]
		if tr_cid != "":
			var comp = Global.get_circuit_by_id(tr_cid)
			if not comp.is_empty():
				tr_energy = comp.get("base_energy", 0.0)
				has_tr = true
		
		# C (offset 1)
		var c_cid = _slots[base + 1]
		if c_cid != "":
			var comp = Global.get_circuit_by_id(c_cid)
			if not comp.is_empty():
				var ce = comp.get("base_energy", 0.0)
				var params_type = comp.get("params", "无")
				var c_idx = base + 1
				if params_type == "数值":
					var param_val = _slot_params[c_idx].get("数值", 0)
					c_energy -= float(param_val) * float(ce)
				elif params_type == "比较符+数值":
					var param_val = _slot_params[c_idx].get("value", 0)
					c_energy -= float(param_val) * float(ce)
				else:
					c_energy -= float(ce)
		
		# A (offset 2)
		var a_cid = _slots[base + 2]
		if a_cid != "":
			var comp = Global.get_circuit_by_id(a_cid)
			if not comp.is_empty():
				has_a = true
				var ab = comp.get("base_energy", 0.0)
				if ab is float or ab is int:
					a_energy = float(ab)
				elif ab is String:
					var parts = ab.split("×")
					if parts.size() == 2:
						var param_key = parts[0].strip_edges()
						var multiplier = float(parts[1].strip_edges())
						var a_idx = base + 2
						var param_val = _slot_params[a_idx].get(param_key, 0)
						a_energy = float(param_val) * multiplier
		
		# T (offset 3)
		var t_cid = _slots[base + 3]
		if t_cid != "":
			var comp = Global.get_circuit_by_id(t_cid)
			if not comp.is_empty():
				t_modifier = comp.get("modifier", 1.0)
		
		# CO (offset 4)
		var co_cid = _slots[base + 4]
		if co_cid != "":
			var comp = Global.get_circuit_by_id(co_cid)
			if not comp.is_empty():
				var adj = comp.get("energy_adjust", 0.0)
				var co_idx = base + 4
				if adj is float or adj is int:
					co_adjust += float(adj)
				elif adj is String:
					if "X" in adj and "×" in adj:
						var parts = adj.split("×")
						if parts.size() == 2:
							var param_key = parts[0].strip_edges().lstrip("-")
							var multiplier = float(parts[1].strip_edges())
							var param_val = _slot_params[co_idx].get(param_key, 0)
							co_adjust += -float(param_val) * multiplier
					else:
						var trimmed = adj.strip_edges()
						if trimmed.is_valid_float():
							co_adjust += float(trimmed)
		
		# ★ 跳过非法组：没有 TR 或没有 A 的组不计能量
		if not has_tr or not has_a:
			continue
		var group_energy = (tr_energy + c_energy + a_energy) * t_modifier + co_adjust
		if group_energy > 0.0:
			circuit_energy += group_energy
	
	# 总能量 = 基础能量 + 纹路能量
	var total_energy = base_energy + circuit_energy
	return max(1, ceil(total_energy))
# ============================
#  属性预览更新
# ============================
func _update_preview():
	# 能量消耗 = 根据纹路组件计算，无效果则按攻防
	var energy_cost = _calc_energy_cost()
	_set_preview("energy_cost", str(energy_cost))
	
	var quality_mult_low := 1.0
	var quality_mult_high := 1.0
	var quality_str := "—"
	if not _selected_card_base.is_empty():
		var q_range = _selected_card_base.get("quality", "—")
		quality_str = q_range
		var parts = q_range.split(" ~ ")
		var q_lower = parts[0] if parts.size() > 0 else ""
		var q_upper = parts[1] if parts.size() > 1 else q_lower
		quality_mult_low = Global.get_quality_mult(q_lower)
		quality_mult_high = Global.get_quality_mult(q_upper)
		_set_preview("quality", q_range)
	else:
		_set_preview("quality", "—")
	
	var final_atk_low = floor(_attack * quality_mult_low)
	var final_atk_high = floor(_attack * quality_mult_high)
	var final_hp_low = floor(_health * quality_mult_low)
	var final_hp_high = floor(_health * quality_mult_high)
	
	if final_atk_low == final_atk_high:
		_set_preview("final_atk", str(final_atk_low))
	else:
		_set_preview("final_atk", str(final_atk_low) + " ~ " + str(final_atk_high))
	
	if final_hp_low == final_hp_high:
		_set_preview("final_hp", str(final_hp_low))
	else:
		_set_preview("final_hp", str(final_hp_low) + " ~ " + str(final_hp_high))
	
	if not _selected_card_base.is_empty():
		var base_load = _attack * 1.0 + _health * 0.5
		var load_cap = _selected_card_base.get("load_cap", 0)
		var tendency = _selected_card_base.get("tendency", {})
		var discount_rate := 0.0
		if not tendency.is_empty():
			var max_tend = 0
			for k in tendency.keys():
				max_tend = max(max_tend, tendency[k])
			discount_rate = min(max_tend * 0.1, 0.5)
		var ink_reduce = _selected_ink.get("load_reduce", 0.0)
		# 计算纹路组件负荷（含参数值负荷）
		var circuit_load := 0.0
		for i in range(_slots.size()):
			var cid = _slots[i]
			if cid == "": continue
			var comp = Global.get_circuit_by_id(cid)
			if not comp.is_empty():
				circuit_load += comp.get("base_load", 0.0)
				# 数值参数也参与负荷：每点数值 +1.7（基础卡基≈只装0/0+4伤）
				var params = _slot_params[i] if i < _slot_params.size() else {}
				if not params.is_empty():
					for key in params.keys():
						var val = params[key]
						if val is int or val is float:
							circuit_load += float(val) * 1.7
		var total_load = base_load + circuit_load
		var final_load = max(0.5, total_load * (1.0 - discount_rate) - ink_reduce)
		_set_preview("load", str(final_load) + " / " + str(load_cap))
	else:
		_set_preview("load", "— / —")
	
	if not _selected_card_base.is_empty():
		var tendency = _selected_card_base.get("tendency", {})
		if tendency.is_empty():
			_set_preview("element", "无")
		else:
			var max_elem = ""
			var max_val = 0
			for k in tendency.keys():
				if tendency[k] > max_val:
					max_val = tendency[k]
					max_elem = k
			var elem_names = {"火": "🔥火", "水": "💧水", "风": "🌪️风", "暗": "🌑暗", "光": "☀️光"}
			_set_preview("element", elem_names.get(max_elem, max_elem))
	else:
		_set_preview("element", "—")
	
	if not _selected_ink.is_empty():
		var resistance = _selected_ink.get("resistance", {})
		_set_preview("resistance", _format_resistance_str(resistance))
	else:
		_set_preview("resistance", "—")
	
	if not _selected_card_base.is_empty():
		var dur = _selected_card_base.get("durability", 0)
		_set_preview("durability", str(dur))
	else:
		_set_preview("durability", "—")
	
	var field_strs := []
	for f in _fields:
		if f != "":
			field_strs.append(f)
	if field_strs.size() == 0:
		_set_preview("fields_display", "无")
	else:
		_set_preview("fields_display", "、".join(field_strs))
	
	# 稀有度
	var rarity_icons = {"普通": "", "稀有": "🔵", "史诗": "🟣", "传说": "🟡"}
	_set_preview("rarity", rarity_icons.get(_card_rarity, "") + _card_rarity)
	
	# 卡牌描述
	if _card_description != "":
		var desc_display = _card_description.substr(0, 40)
		if _card_description.length() > 40:
			desc_display += "..."
		_set_preview("description", desc_display)
	else:
		_set_preview("description", "无")
	
	var hint = _preview_labels.get("make_hint")
	if hint:
		if _selected_card_base.is_empty() or _selected_ink.is_empty():
			hint.text = "请先选择卡基和卡墨"
			hint.add_theme_color_override("font_color", Color("#FF6B6B"))
		else:
			hint.text = "✅ 可以封卡保存了！"
			hint.add_theme_color_override("font_color", Color("#81C784"))


func _set_preview(key: String, val: String):
	var label = _preview_labels.get(key)
	if label:
		label.text = val


func _format_resistance_str(resistance: Dictionary) -> String:
	if resistance.is_empty():
		return "无"
	var parts := []
	for k in resistance.keys():
		var elem_name := ""
		match k:
			"火": elem_name = "🔥火"
			"水": elem_name = "💧水"
			"风": elem_name = "🌪️风"
			"暗": elem_name = "🌑暗"
			"光": elem_name = "☀️光"
			"all": elem_name = "全属性"
			_: elem_name = k
		parts.append(elem_name + "+" + str(resistance[k]) + "%")
	return " ".join(parts)


# ============================
#  选择卡基弹窗
# ============================
func _on_select_base():
	var bases = WarehouseManager.get_card_bases()
	if bases.size() == 0:
		_show_popup("⚠️ 暂无可用卡基，请先制作卡基", Color("#FF6B6B"))
		return
	
	var overlay = ColorRect.new()
	overlay.name = "PickerOverlay"
	overlay.color = Color(0.0, 0.0, 0.0, 0.6)
	overlay.anchor_left = 0.0; overlay.anchor_top = 0.0; overlay.anchor_right = 1.0; overlay.anchor_bottom = 1.0
	overlay.mouse_filter = MOUSE_FILTER_STOP
	overlay.gui_input.connect(_on_picker_overlay_clicked.bind(overlay))
	add_child(overlay)
	
	var panel = Panel.new()
	panel.name = "PickerPanel"
	panel.anchor_left = 0.05; panel.anchor_top = 0.15; panel.anchor_right = 0.95; panel.anchor_bottom = 0.85
	panel.clip_contents = true
	var ps = StyleBoxFlat.new()
	ps.bg_color = Global.current.bg
	ps.border_width_left = 3; ps.border_width_right = 3; ps.border_width_top = 3; ps.border_width_bottom = 3
	ps.border_color = Global.current.topbar_border
	ps.corner_radius_top_left = 16; ps.corner_radius_top_right = 16
	ps.corner_radius_bottom_left = 16; ps.corner_radius_bottom_right = 16
	panel.add_theme_stylebox_override("panel", ps)
	overlay.add_child(panel)
	
	var title = Label.new()
	title.text = "🠿 选择卡基"
	title.add_theme_font_size_override("font_size", 55)
	title.add_theme_color_override("font_color", Global.current.title)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.anchor_left = 0.0; title.anchor_top = 0.0; title.anchor_right = 1.0; title.anchor_bottom = 0.0
	title.offset_left = 0; title.offset_top = Global.ph(0.02); title.offset_right = 0; title.offset_bottom = Global.ph(0.08)
	panel.add_child(title)
	
	var scroll = ScrollContainer.new()
	scroll.name = "PickerScroll"
	scroll.anchor_left = 0.0; scroll.anchor_top = 0.0; scroll.anchor_right = 1.0; scroll.anchor_bottom = 1.0
	scroll.offset_left = 0; scroll.offset_top = Global.ph(0.08); scroll.offset_right = 0; scroll.offset_bottom = -Global.ph(0.1)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	panel.add_child(scroll)
	
	var vbox = VBoxContainer.new()
	vbox.name = "PickerVBox"
	vbox.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	scroll.add_child(vbox)
	
	var row_index := 0
	for key in bases.keys():
		var base = bases[key]
		var name_str = WarehouseManager.get_card_base_display_name(base)
		var load_cap = base.get("load_cap", 0)
		var slots = base.get("slots", 0)
		var quality = base.get("quality", "—")
		var tendency = base.get("tendency", {})
		var dur = base.get("durability", 0)
		
		# 用 PanelContainer 让卡片高度随内容自适应，避免换行后溢出被下方卡片遮挡
		var row_panel = PanelContainer.new()
		var rps = StyleBoxFlat.new()
		rps.bg_color = Global.current.topbar_bg if row_index % 2 == 0 else Color.TRANSPARENT
		rps.content_margin_left = Global.pw(0.02)
		rps.content_margin_right = Global.pw(0.02)
		rps.content_margin_top = Global.ph(0.005)
		rps.content_margin_bottom = Global.ph(0.005)
		row_panel.add_theme_stylebox_override("panel", rps)
		row_panel.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
		row_panel.mouse_filter = MOUSE_FILTER_PASS
		vbox.add_child(row_panel)
		
		var row_vbox = VBoxContainer.new()
		row_vbox.size_flags_horizontal = SIZE_FILL
		row_vbox.mouse_filter = MOUSE_FILTER_IGNORE
		row_vbox.add_theme_constant_override("separation", 2)
		row_panel.add_child(row_vbox)
		
		var left_vbox = VBoxContainer.new()
		left_vbox.size_flags_horizontal = SIZE_EXPAND
		left_vbox.add_theme_constant_override("separation", 2)
		row_vbox.add_child(left_vbox)
		
		var name_label = Label.new()
		name_label.text = name_str
		name_label.add_theme_font_size_override("font_size", 45)
		name_label.add_theme_color_override("font_color", Global.current.title)
		left_vbox.add_child(name_label)
		
		var info_label = Label.new()
		var tend_str := "无"
		if not tendency.is_empty():
			var parts := []
			for k in tendency.keys():
				parts.append(k + str(tendency[k]))
			tend_str = " ".join(parts)
		info_label.text = "负荷:" + str(load_cap) + " 槽位:" + str(slots) + " 品质:" + quality + " 倾向:" + tend_str
		info_label.add_theme_font_size_override("font_size", 40)
		info_label.add_theme_color_override("font_color", Global.current.btn_text)
		info_label.size_flags_horizontal = SIZE_FILL
		info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		left_vbox.add_child(info_label)
		
		var btn_hbox = HBoxContainer.new()
		btn_hbox.size_flags_horizontal = SIZE_FILL
		btn_hbox.mouse_filter = MOUSE_FILTER_IGNORE
		row_vbox.add_child(btn_hbox)
		var select_btn = Button.new()
		select_btn.text = "选择"
		select_btn.add_theme_font_size_override("font_size", 40)
		select_btn.custom_minimum_size = Vector2(Global.pw(0.12), 0)
		select_btn.pressed.connect(_on_pick_base.bind(key, overlay))
		btn_hbox.add_child(select_btn)
		var spacer = Control.new()
		spacer.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
		btn_hbox.add_child(spacer)
		row_index += 1
	
	var close_btn = Button.new()
	close_btn.text = "✕ 关闭"
	close_btn.add_theme_font_size_override("font_size", 45)
	var cs = StyleBoxFlat.new()
	cs.bg_color = Global.current.btn_bg
	cs.border_width_left = 2; cs.border_width_right = 2; cs.border_width_top = 2; cs.border_width_bottom = 2
	cs.border_color = Color("#888888")
	cs.corner_radius_top_left = 12; cs.corner_radius_top_right = 12
	cs.corner_radius_bottom_left = 12; cs.corner_radius_bottom_right = 12
	cs.content_margin_left = 24; cs.content_margin_right = 24
	close_btn.add_theme_stylebox_override("normal", cs)
	close_btn.add_theme_color_override("font_color", Global.current.btn_text)
	close_btn.anchor_left = 0.3; close_btn.anchor_top = 1.0; close_btn.anchor_right = 0.7; close_btn.anchor_bottom = 1.0
	close_btn.offset_left = 0; close_btn.offset_top = Global.ph(-0.08); close_btn.offset_right = 0; close_btn.offset_bottom = Global.ph(-0.02)
	close_btn.pressed.connect(_close_picker.bind(overlay))
	panel.add_child(close_btn)


func _on_pick_base(key: String, overlay: ColorRect):
	var bases = WarehouseManager.get_card_bases()
	var base = bases.get(key, {})
	if base.is_empty():
		return
	_selected_card_base = base
	
	var btn = _preview_labels.get("select_base_btn")
	if btn:
		btn.text = "已选择卡基 ✓"
	
	var info = _preview_labels.get("base_info")
	if info:
		var name_str = WarehouseManager.get_card_base_display_name(base)
		var load_cap = base.get("load_cap", 0)
		var slots = base.get("slots", 0)
		var quality = base.get("quality", "—")
		info.text = name_str + " | 负荷:" + str(load_cap) + " 槽位:" + str(slots) + " 品质:" + quality
	
	# 初始化纹路槽位
	var slot_count = base.get("slots", 0)
	_init_slots(slot_count)
	_rebuild_slot_ui()
	_close_picker(overlay)
	_update_preview()
	# 教程引导：选中卡基后推进
	_tutorial_advance("base_picked")


# ============================
#  选择卡墨弹窗
# ============================
func _on_select_ink():
	var inks = WarehouseManager.get_ink_inventory()
	if inks.size() == 0:
		_show_popup("⚠️ 暂无可用卡墨，请先调制卡墨", Color("#FF6B6B"))
		return
	
	var overlay = ColorRect.new()
	overlay.name = "PickerOverlay"
	overlay.color = Color(0.0, 0.0, 0.0, 0.6)
	overlay.anchor_left = 0.0; overlay.anchor_top = 0.0; overlay.anchor_right = 1.0; overlay.anchor_bottom = 1.0
	overlay.mouse_filter = MOUSE_FILTER_STOP
	overlay.gui_input.connect(_on_picker_overlay_clicked.bind(overlay))
	add_child(overlay)
	
	var panel = Panel.new()
	panel.name = "PickerPanel"
	panel.anchor_left = 0.05; panel.anchor_top = 0.15; panel.anchor_right = 0.95; panel.anchor_bottom = 0.85
	panel.clip_contents = true
	var ps = StyleBoxFlat.new()
	ps.bg_color = Global.current.bg
	ps.border_width_left = 3; ps.border_width_right = 3; ps.border_width_top = 3; ps.border_width_bottom = 3
	ps.border_color = Global.current.topbar_border
	ps.corner_radius_top_left = 16; ps.corner_radius_top_right = 16
	ps.corner_radius_bottom_left = 16; ps.corner_radius_bottom_right = 16
	panel.add_theme_stylebox_override("panel", ps)
	overlay.add_child(panel)
	
	var title = Label.new()
	title.text = "🎨 选择卡墨"
	title.add_theme_font_size_override("font_size", 55)
	title.add_theme_color_override("font_color", Global.current.title)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.anchor_left = 0.0; title.anchor_top = 0.0; title.anchor_right = 1.0; title.anchor_bottom = 0.0
	title.offset_left = 0; title.offset_top = Global.ph(0.02); title.offset_right = 0; title.offset_bottom = Global.ph(0.08)
	panel.add_child(title)
	
	var scroll = ScrollContainer.new()
	scroll.name = "PickerScroll"
	scroll.anchor_left = 0.0; scroll.anchor_top = 0.0; scroll.anchor_right = 1.0; scroll.anchor_bottom = 1.0
	scroll.offset_left = 0; scroll.offset_top = Global.ph(0.08); scroll.offset_right = 0; scroll.offset_bottom = -Global.ph(0.1)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	panel.add_child(scroll)
	
	var vbox = VBoxContainer.new()
	vbox.name = "PickerVBox"
	vbox.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	scroll.add_child(vbox)
	
	var row_index := 0
	for data in inks:
		var ink_name = data.get("name", "未知卡墨")
		var load_reduce = data.get("load_reduce", 0)
		var effect_power = data.get("effect_power", 0)
		var quality_stab = data.get("quality_stab", 0)
		var resistance = data.get("resistance", {})
		
		var row_panel = PanelContainer.new()
		var rps = StyleBoxFlat.new()
		rps.bg_color = Global.current.topbar_bg if row_index % 2 == 0 else Color.TRANSPARENT
		rps.content_margin_left = Global.pw(0.02)
		rps.content_margin_right = Global.pw(0.02)
		rps.content_margin_top = Global.ph(0.005)
		rps.content_margin_bottom = Global.ph(0.005)
		row_panel.add_theme_stylebox_override("panel", rps)
		row_panel.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
		row_panel.mouse_filter = MOUSE_FILTER_PASS
		vbox.add_child(row_panel)
		
		var row_vbox = VBoxContainer.new()
		row_vbox.size_flags_horizontal = SIZE_FILL
		row_vbox.mouse_filter = MOUSE_FILTER_IGNORE
		row_vbox.add_theme_constant_override("separation", 2)
		row_panel.add_child(row_vbox)
		
		var left_vbox = VBoxContainer.new()
		left_vbox.size_flags_horizontal = SIZE_EXPAND
		left_vbox.add_theme_constant_override("separation", 2)
		row_vbox.add_child(left_vbox)
		
		var name_label = Label.new()
		name_label.text = ink_name
		name_label.add_theme_font_size_override("font_size", 45)
		name_label.add_theme_color_override("font_color", Global.current.title)
		left_vbox.add_child(name_label)
		
		var info_label = Label.new()
		var res_str := _format_resistance_str(resistance)
		info_label.text = "减免:" + str(load_reduce) + " 效果:" + str(effect_power) + "% 稳定:" + str(quality_stab) + "% 抗性:" + res_str
		info_label.add_theme_font_size_override("font_size", 40)
		info_label.add_theme_color_override("font_color", Global.current.btn_text)
		info_label.size_flags_horizontal = SIZE_FILL
		info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		left_vbox.add_child(info_label)
		
		var btn_hbox = HBoxContainer.new()
		btn_hbox.size_flags_horizontal = SIZE_FILL
		btn_hbox.mouse_filter = MOUSE_FILTER_IGNORE
		row_vbox.add_child(btn_hbox)
		var select_btn = Button.new()
		select_btn.text = "选择"
		select_btn.add_theme_font_size_override("font_size", 40)
		select_btn.custom_minimum_size = Vector2(Global.pw(0.12), 0)
		select_btn.pressed.connect(_on_pick_ink.bind(data, overlay))
		btn_hbox.add_child(select_btn)
		var spacer = Control.new()
		spacer.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
		btn_hbox.add_child(spacer)
		row_index += 1
	
	var close_btn = Button.new()
	close_btn.text = "✕ 关闭"
	close_btn.add_theme_font_size_override("font_size", 45)
	var cs = StyleBoxFlat.new()
	cs.bg_color = Global.current.btn_bg
	cs.border_width_left = 2; cs.border_width_right = 2; cs.border_width_top = 2; cs.border_width_bottom = 2
	cs.border_color = Color("#888888")
	cs.corner_radius_top_left = 12; cs.corner_radius_top_right = 12
	cs.corner_radius_bottom_left = 12; cs.corner_radius_bottom_right = 12
	cs.content_margin_left = 24; cs.content_margin_right = 24
	close_btn.add_theme_stylebox_override("normal", cs)
	close_btn.add_theme_color_override("font_color", Global.current.btn_text)
	close_btn.anchor_left = 0.3; close_btn.anchor_top = 1.0; close_btn.anchor_right = 0.7; close_btn.anchor_bottom = 1.0
	close_btn.offset_left = 0; close_btn.offset_top = Global.ph(-0.08); close_btn.offset_right = 0; close_btn.offset_bottom = Global.ph(-0.02)
	close_btn.pressed.connect(_close_picker.bind(overlay))
	panel.add_child(close_btn)


func _on_pick_ink(data: Dictionary, overlay: ColorRect):
	_selected_ink = data
	var btn = _preview_labels.get("select_ink_btn")
	if btn:
		btn.text = "已选择卡墨 \u2713"
	var info = _preview_labels.get("ink_info")
	if info:
		var ink_name = data.get("name", "未知卡墨")
		var load_reduce = data.get("load_reduce", 0)
		var effect_power = data.get("effect_power", 0)
		info.text = ink_name + " | 减免:" + str(load_reduce) + " 效果:" + str(effect_power) + "%"
	_close_picker(overlay)
	_update_preview()
	# 教程引导：选中卡墨后推进
	_tutorial_advance("ink_picked")

# ============================
#  保存卡牌
# ============================
## 校验纹路槽位是否能组成完整效果
## 槽位全部为空 → 通过（纹路可选）
## 有纹路时：每个效果组必须至少包含一个触发器(TR)和一个动作(A)
func _validate_slots_effects() -> bool:
	# 没有槽位或全部为空 → 通过
	var max_blocks = _slots.size() / 5
	if max_blocks == 0:
		return true
	var placed = 0
	var has_any = false
	for cid in _slots:
		if cid != "":
			placed += 1
			has_any = true
	if not has_any:
		return true
	if placed > _max_slots:
		return false
	
	# 按固定5槽位一组校验（每个效果块：[0]=TR, [2]=A 必须同时有）
	for bi in range(max_blocks):
		var base = bi * 5
		var block_has_any = false
		var has_tr = false
		var has_a = false
		for off in range(5):
			if _slots[base + off] != "":
				block_has_any = true
				if off == 0: has_tr = true
				if off == 2: has_a = true
		if block_has_any and (not has_tr or not has_a):
			return false
		# 目标槽位也是必选项
		if block_has_any and _slots[base + 3] == "":
			return false
		# ★ 动作×目标互斥检查（硬校验，互斥直接不允许封卡）
		if block_has_any and has_a and _slots[base + 3] != "":
			var a_cid = _slots[base + 2]
			var t_cid = _slots[base + 3]
			if Global.is_action_target_mutex(a_cid, t_cid):
				return false
	
	return true


func _on_make_card():
	# ===== 校验开始 =====
	# 1. 必填项：卡基
	if _selected_card_base.is_empty():
		_show_popup("⚠️ 请先选择卡基！", Color("#FF6B6B"))
		return
	# 2. 必填项：卡墨
	if _selected_ink.is_empty():
		_show_popup("⚠️ 请先选择卡墨！", Color("#FF6B6B"))
		return
	# 3. 必填项：卡名
	var name_input = _preview_labels.get("card_name_input")
	var card_name_text = name_input.text.strip_edges() if name_input else ""
	if card_name_text == "":
		_show_popup("⚠️ 请填写卡牌名称！", Color("#FF6B6B"))
		return
	# 4. 必填项：描述
	var desc_input = _preview_labels.get("desc_input")
	var desc_text = desc_input.text.strip_edges() if desc_input else ""
	if desc_text == "":
		_show_popup("⚠️ 请填写卡牌描述！", Color("#FF6B6B"))
		return
	# 5. 纹路校验：不为空时必须能组成完整效果，且总数不能超过上限
	var placed = 0
	for cid in _slots:
		if cid != "":
			placed += 1
	if placed > _max_slots:
		_show_popup("⚠️ 纹路槽位超限！已放置 " + str(placed) + " 个，上限为 " + str(_max_slots) + " 个，请删除多余纹路。", Color("#FF6B6B"))
		return
	if not _validate_slots_effects():
		_show_popup("⚠️ 纹路效果不完整！每个效果组需要至少一个触发器、动作和目标，请检查纹路配置！", Color("#FF6B6B"))
		return
	# ===== 校验通过 =====
	
	# 计算总负荷
	var load_cap = _selected_card_base.get("load_cap", 0)
	var base_load = _attack * 1.0 + _health * 0.5
	var circuit_load := 0.0
	for i in range(_slots.size()):
		var cid = _slots[i]
		if cid == "": continue
		var comp = Global.get_circuit_by_id(cid)
		if not comp.is_empty():
			circuit_load += comp.get("base_load", 0.0)
			# 数值参数也参与负荷：每点数值 +1.7 负荷
			var params = _slot_params[i] if i < _slot_params.size() else {}
			if not params.is_empty():
				for key in params.keys():
					var val = params[key]
					if val is int or val is float:
						circuit_load += float(val) * 1.7
	var tendency = _selected_card_base.get("tendency", {})
	var discount_rate := 0.0
	if not tendency.is_empty():
		var max_tend = 0
		for k in tendency.keys():
			max_tend = max(max_tend, tendency[k])
		discount_rate = min(max_tend * 0.1, 0.5)
	var ink_reduce = _selected_ink.get("load_reduce", 0.0)
	var total_load = base_load + circuit_load
	var final_load = max(0.5, total_load * (1.0 - discount_rate) - ink_reduce)
	
	# 超载检查
	if final_load > load_cap:
		_show_popup("⚠️ 负荷超载！当前 " + str(final_load) + " / " + str(load_cap) + "，请减少攻防或纹路组件！", Color("#FF6B6B"))
		return
	
	# 保存到成员变量供 _finish_make_card 使用
	_pending_final_load = final_load
	_pending_tendency = tendency
	
	# 音游敲击确定品质（受卡基品质区间、称号等级、卡墨稳定性影响）
	_start_quality_rhythm(_selected_card_base.get("quality", "标准 ~ 标准"), PlayerManager.get_guild_level(), _selected_ink.get("quality_stab", 0.0))
	return
func _finish_make_card(final_quality: String):
	var q_mult = Global.get_quality_mult(final_quality)
	
	var card_data = {
		"card_name": "",
		"fields": _fields.duplicate(),
		"energy_cost": _calc_energy_cost(),
		"attack": round(_attack * q_mult),
		"health": round(_health * q_mult),
		"effects": _build_effects_data(),
		"aux_items": _aux_items.duplicate(),  # 保存辅材数据
		"circuit_load": _pending_final_load,
		"quality": final_quality,
		"rarity": _card_rarity,           # 稀有度
		"description": _card_description,  # 卡牌描述
		"durability": _selected_card_base.get("durability", 10),
		"max_durability": _selected_card_base.get("durability", 10),
		"main_element": "无",
		"element_resistance": "",
		"energy_core_type": "",
		"materials_used": {
			"card_base": _selected_card_base.get("id", ""),
			"ink": _selected_ink.get("id", "")
		},
		"card_base_data": _selected_card_base.duplicate(),
		"ink_data": _selected_ink.duplicate()
	}
	
	var tendency = _pending_tendency
	if not tendency.is_empty():
		var max_elem = ""
		var max_val = 0
		for k in tendency.keys():
			if tendency[k] > max_val:
				max_val = tendency[k]
				max_elem = k
		card_data["main_element"] = max_elem
	
	var resistance = _selected_ink.get("resistance", {})
	if not resistance.is_empty():
		var parts := []
		for k in resistance.keys():
			parts.append(k + ":" + str(resistance[k]))
		card_data["element_resistance"] = ",".join(parts)
	
	var field_strs := []
	for f in _fields:
		if f != "":
			field_strs.append(f)
	var suffix = "".join(field_strs) if field_strs.size() > 0 else ""
	var base_name = WarehouseManager.get_card_base_display_name(_selected_card_base)
	if _card_name != "":
		card_data["card_name"] = _card_name
	else:
		card_data["card_name"] = base_name + (("·" + suffix) if suffix != "" else "")
	
	CardManager.add_card(card_data)
	PlayerManager.record_card_creation(card_data["quality"])
	# ★ 每日制卡阶梯
	var craft_result = PlayerManager.record_craft()
	if craft_result.get("completed", false):
		print("[制卡] 🎉 每日制卡阶梯完成！金币+" + str(craft_result.get("reward", 0)))
	# 消耗卡基和卡墨（封卡即消耗材料）
	var warehouse = get_node("/root/WarehouseManager")
	if _selected_card_base.has("id"):
		warehouse.remove_card_base(_selected_card_base.get("id", ""))
	if _selected_ink.has("id"):
		warehouse.remove_ink(_selected_ink.get("id", ""))
	# 消耗已选择的辅材（封卡刻录成功时，才从仓库扣除）
	if _aux_items.size() > 0:
		for aux_item in _aux_items:
			var aid = aux_item.get("id", "")
			if aid != "":
				warehouse.consume_aux(aid, 1)
	# 检查纹路解锁状态
	var new_unlocks = CircuitManager.check_and_apply_unlocks()
	if new_unlocks.size() > 0:
		print("[刻画卡牌] 解锁了 ", new_unlocks.size(), " 个纹路组件")
	# 教程引导：第一张卡制作成功 → 标记制卡幕完成（进度2→3），弹完成对话
	# 教程模式下不弹普通成功弹窗，避免叠层盖住完成对话
	if TutorialManager.get_progress() == TutorialManager.PROGRESS_FIRST_BATTLE:
		TutorialManager.advance()
		_show_tutorial_done_dialogue(card_data.get("card_name", "新卡"))
	else:
		_show_popup("✅ 卡牌「" + card_data["card_name"] + "」制作成功！", Color("#81C784"))
	print("[刻画卡牌] 保存卡牌: ", card_data["card_name"])
	
	# 重置选择状态，防止重复封卡
	_reset_engraving_state()
	_update_preview()


# ============================
#  弹窗/遮罩工具（已在第680行定义 _show_popup）
# ============================
# 辅助函数：用于关闭弹窗/选择器
func _process(delta):
	if not _engrave_active:
		return
	_engrave_marker += _engrave_dir * _engrave_speed * delta
	if _engrave_marker >= 1.0:
		_engrave_marker = 1.0
		_engrave_dir = -1
	elif _engrave_marker <= 0.0:
		_engrave_marker = 0.0
		_engrave_dir = 1
	if _engrave_marker_node and _engrave_bar_width > 0:
		var mw = _engrave_marker_node.size.x
		_engrave_marker_node.position.x = _engrave_marker * _engrave_bar_width - mw / 2.0

func _start_quality_rhythm(q_range: String, title_level: int, quality_stab: float):
	# 保存参数供"观看广告重新敲击"复用
	_pending_q_range = q_range
	_pending_title_level = title_level
	_pending_quality_stab = quality_stab
	# 防残留：若确认窗/状态引用还在，先清掉
	if _confirm_overlay and is_instance_valid(_confirm_overlay):
		_confirm_overlay.queue_free()
		_confirm_overlay = null
	_ad_status_hint = null
	_quality_weights = _compute_quality_weights(q_range, title_level, quality_stab)
	_engrave_active = true
	_engrave_marker = 0.0
	_engrave_dir = 1
	# 按卡基品质区间上限调速：上限越高标记越快（好卡基=高奖励但更难敲准）
	# 废品0.6 / 瑕疵0.8 / 标准1.0 / 卓越1.3 / 完美1.6
	var parts = q_range.split(" ~ ")
	var upper_q = QUALITY_NAMES.find(parts[1]) if parts.size() > 1 else -1
	if upper_q < 0:
		upper_q = QUALITY_NAMES.find("标准")
	var speed_map := [0.6, 0.8, 1.0, 1.3, 1.6]
	_engrave_speed = speed_map[clamp(upper_q, 0, 4)]
	# 偶发轻微节奏扰动：品质越高扰动越大，强化"手感难度"（±12%内，不破坏可控性）
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	var jitter = (1.0 + rng.randf_range(-0.12, 0.12)) if upper_q >= 3 else 1.0
	_engrave_speed *= jitter
	set_process(true)
	var overlay = ColorRect.new()
	overlay.name = "QualityRhythmOverlay"
	overlay.color = Color(0.0, 0.0, 0.0, 0.6)
	overlay.anchor_left = 0.0; overlay.anchor_top = 0.0; overlay.anchor_right = 1.0; overlay.anchor_bottom = 1.0
	overlay.mouse_filter = MOUSE_FILTER_STOP
	add_child(overlay)
	_engrave_overlay = overlay
	var panel = PanelContainer.new()
	panel.name = "QualityRhythmPanel"
	panel.anchor_left = 0.15; panel.anchor_top = 0.3; panel.anchor_right = 0.85; panel.anchor_bottom = 0.7
	panel.clip_contents = true
	var ps = StyleBoxFlat.new()
	ps.bg_color = Global.current.bg
	ps.border_width_left = 3; ps.border_width_right = 3; ps.border_width_top = 3; ps.border_width_bottom = 3
	ps.border_color = Global.current.topbar_border
	ps.corner_radius_top_left = 16; ps.corner_radius_top_right = 16
	ps.corner_radius_bottom_left = 16; ps.corner_radius_bottom_right = 16
	ps.content_margin_left = 20; ps.content_margin_right = 20; ps.content_margin_top = 20; ps.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", ps)
	overlay.add_child(panel)
	var vbox = VBoxContainer.new()
	vbox.name = "QualityRhythmVBox"
	vbox.add_theme_constant_override("separation", 14)
	vbox.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	vbox.size_flags_vertical = SIZE_EXPAND | SIZE_FILL
	panel.add_child(vbox)
	var title = Label.new()
	title.text = "🎯 敲击定品质！\n看准时机，点击「敲！」停住标记"
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Global.current.title)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(title)
	# 品质条容器
	var bar = Control.new()
	bar.name = "QualityBar"
	_engrave_bar_width = Global.pw(0.7)
	bar.custom_minimum_size = Vector2(_engrave_bar_width, Global.ph(0.06))
	bar.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	vbox.add_child(bar)
	_engrave_bar = bar
	var total = 0.0
	for w in _quality_weights:
		total += w
	if total <= 0.0:
		total = 1.0
	var cum := 0.0
	var colors := [Color("#9E9E9E"), Color("#4FC3F7"), Color("#81C784"), Color("#FFD54F"), Color("#E53935")]
	for i in range(5):
		var ratio = _quality_weights[i] / total
		if ratio <= 0.0:
			continue
		var seg = ColorRect.new()
		seg.color = colors[i]
		seg.position = Vector2(cum * _engrave_bar_width, 0)
		seg.size = Vector2(ratio * _engrave_bar_width, Global.ph(0.06))
		bar.add_child(seg)
		cum += ratio
	# 标记
	var marker = ColorRect.new()
	marker.name = "QualityMarker"
	marker.color = Color("#FFFFFF")
	marker.size = Vector2(Global.pw(0.015), Global.ph(0.09))
	marker.position = Vector2(-marker.size.x / 2.0, -Global.ph(0.015))
	bar.add_child(marker)
	_engrave_marker_node = marker
	# 品质名称行
	var name_row = HBoxContainer.new()
	name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	name_row.add_theme_constant_override("separation", 4)
	_engrave_bar_width = max(_engrave_bar_width, 1.0)
	var cum2 := 0.0
	for i in range(5):
		var ratio = _quality_weights[i] / total
		if ratio <= 0.0:
			continue
		var name_lbl = Label.new()
		name_lbl.text = QUALITY_NAMES[i]
		name_lbl.add_theme_font_size_override("font_size", 22)
		name_lbl.add_theme_color_override("font_color", colors[i])
		name_lbl.custom_minimum_size = Vector2(ratio * _engrave_bar_width, 0)
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_row.add_child(name_lbl)
		cum2 += ratio
	name_row.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	vbox.add_child(name_row)
	# 敲击按钮
	var tap_btn = Button.new()
	tap_btn.text = "🖱️ 敲！"
	tap_btn.add_theme_font_size_override("font_size", 50)
	tap_btn.custom_minimum_size = Vector2(Global.pw(0.3), Global.ph(0.08))
	tap_btn.size_flags_horizontal = SIZE_EXPAND
	var ts = StyleBoxFlat.new()
	ts.bg_color = Global.current.btn_bg
	ts.border_width_left = 2; ts.border_width_right = 2; ts.border_width_top = 2; ts.border_width_bottom = 2
	ts.border_color = Global.current.topbar_border
	ts.corner_radius_top_left = 12; ts.corner_radius_top_right = 12
	ts.corner_radius_bottom_left = 12; ts.corner_radius_bottom_right = 12
	ts.content_margin_left = 16; ts.content_margin_right = 16; ts.content_margin_top = 12; ts.content_margin_bottom = 12
	tap_btn.add_theme_stylebox_override("normal", ts)
	tap_btn.add_theme_color_override("font_color", Global.current.btn_text)
	tap_btn.pressed.connect(_on_quality_tap)
	var btn_wrap = CenterContainer.new()
	btn_wrap.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	btn_wrap.add_child(tap_btn)
	vbox.add_child(btn_wrap)

func _on_quality_tap():
	if not _engrave_active:
		return
	_engrave_active = false
	set_process(false)
	var total = 0.0
	for w in _quality_weights:
		total += w
	if total <= 0.0:
		total = 1.0
	var pos = clamp(_engrave_marker, 0.0, 1.0) * total
	var cum := 0.0
	var quality = QUALITY_NAMES[4]
	for i in range(5):
		cum += _quality_weights[i]
		if pos <= cum:
			quality = QUALITY_NAMES[i]
			break
	if _engrave_overlay and is_instance_valid(_engrave_overlay):
		_engrave_overlay.queue_free()
	_engrave_overlay = null
	# 不再立即制作：暂存品质，弹出确认窗（封卡 / 观看广告重新敲击）
	_pending_quality = quality
	_show_quality_confirm(quality)
func _show_quality_confirm(quality: String):
	var q_idx = QUALITY_NAMES.find(quality)
	var q_color := Color("#81C784")
	var q_colors := [Color("#9E9E9E"), Color("#4FC3F7"), Color("#81C784"), Color("#FFD54F"), Color("#E53935"), Color("#f9d371")]
	if q_idx >= 0 and q_idx < q_colors.size():
		q_color = q_colors[q_idx]
	# 先清掉旧的确认弹窗（防重复）
	if _confirm_overlay and is_instance_valid(_confirm_overlay):
		_confirm_overlay.queue_free()
		_confirm_overlay = null
	var overlay = ColorRect.new()
	overlay.name = "QualityConfirmOverlay"
	overlay.color = Color(0.0, 0.0, 0.0, 0.65)
	overlay.anchor_left = 0.0; overlay.anchor_top = 0.0; overlay.anchor_right = 1.0; overlay.anchor_bottom = 1.0
	overlay.mouse_filter = MOUSE_FILTER_STOP
	add_child(overlay)
	_confirm_overlay = overlay
	var panel = PanelContainer.new()
	panel.anchor_left = 0.12; panel.anchor_top = 0.25; panel.anchor_right = 0.88; panel.anchor_bottom = 0.75
	var ps = StyleBoxFlat.new()
	ps.bg_color = Global.current.bg
	ps.border_width_left = 4; ps.border_width_right = 4; ps.border_width_top = 4; ps.border_width_bottom = 4
	ps.border_color = q_color
	ps.corner_radius_top_left = 18; ps.corner_radius_top_right = 18
	ps.corner_radius_bottom_left = 18; ps.corner_radius_bottom_right = 18
	ps.content_margin_left = 24; ps.content_margin_right = 24; ps.content_margin_top = 24; ps.content_margin_bottom = 24
	panel.add_theme_stylebox_override("panel", ps)
	overlay.add_child(panel)
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)
	var title = Label.new()
	title.text = "✨ 品质确认"
	title.add_theme_font_size_override("font_size", 52)
	title.add_theme_color_override("font_color", Global.current.title)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	var quality_lbl = Label.new()
	quality_lbl.text = quality
	quality_lbl.add_theme_font_size_override("font_size", 130)
	quality_lbl.add_theme_color_override("font_color", q_color)
	quality_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.4))
	quality_lbl.add_theme_constant_override("shadow_offset_x", 3)
	quality_lbl.add_theme_constant_override("shadow_offset_y", 3)
	quality_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(quality_lbl)
	var hint = Label.new()
	hint.text = "这个品质满意吗？\n不满意可以看广告重新敲一次！"
	hint.add_theme_font_size_override("font_size", 32)
	hint.add_theme_color_override("font_color", Global.current.btn_text)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(hint)
	var btn_row = HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 20)
	vbox.add_child(btn_row)
	var seal_btn = Button.new()
	seal_btn.text = "📦 封卡"
	seal_btn.add_theme_font_size_override("font_size", 44)
	var seal_ts := StyleBoxFlat.new()
	seal_ts.bg_color = Color("#4CAF50")
	seal_ts.border_width_left = 2; seal_ts.border_width_right = 2; seal_ts.border_width_top = 2; seal_ts.border_width_bottom = 2
	seal_ts.border_color = Color("#2E7D32")
	seal_ts.corner_radius_top_left = 12; seal_ts.corner_radius_top_right = 12
	seal_ts.corner_radius_bottom_left = 12; seal_ts.corner_radius_bottom_right = 12
	seal_ts.content_margin_left = 24; seal_ts.content_margin_right = 24; seal_ts.content_margin_top = 10; seal_ts.content_margin_bottom = 10
	seal_btn.add_theme_stylebox_override("normal", seal_ts)
	seal_btn.add_theme_color_override("font_color", Color.WHITE)
	seal_btn.pressed.connect(_on_seal_quality)
	btn_row.add_child(seal_btn)
	var ad_btn = Button.new()
	ad_btn.text = "🎬 看广告重敲"
	ad_btn.add_theme_font_size_override("font_size", 44)
	var ad_ts := StyleBoxFlat.new()
	ad_ts.bg_color = Color("#FF9800")
	ad_ts.border_width_left = 2; ad_ts.border_width_right = 2; ad_ts.border_width_top = 2; ad_ts.border_width_bottom = 2
	ad_ts.border_color = Color("#E65100")
	ad_ts.corner_radius_top_left = 12; ad_ts.corner_radius_top_right = 12
	ad_ts.corner_radius_bottom_left = 12; ad_ts.corner_radius_bottom_right = 12
	ad_ts.content_margin_left = 24; ad_ts.content_margin_right = 24; ad_ts.content_margin_top = 10; ad_ts.content_margin_bottom = 10
	ad_btn.add_theme_stylebox_override("normal", ad_ts)
	ad_btn.add_theme_color_override("font_color", Color.WHITE)
	ad_btn.pressed.connect(_on_watch_ad_retry)
	btn_row.add_child(ad_btn)
	# 广告就绪状态提示（小字）
	var ad_status = Label.new()
	ad_status.name = "AdStatusHint"
	if _hj_ads == null:
		ad_status.text = "📵 当前环境不支持广告"
		ad_status.add_theme_color_override("font_color", Color("#FF5252"))
	else:
		ad_status.text = ("✅ 广告已就绪，可以观看" if _ad_ready else "⏳ 广告加载中，稍后再试…")
		ad_status.add_theme_color_override("font_color", Color("#888888" if not _ad_ready else "#4CAF50"))
	ad_status.add_theme_font_size_override("font_size", 26)
	ad_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ad_status_hint = ad_status
	vbox.add_child(ad_status)
func _on_seal_quality():
	if _confirm_overlay and is_instance_valid(_confirm_overlay):
		_confirm_overlay.queue_free()
		_confirm_overlay = null
	_ad_status_hint = null
	if _pending_quality == "":
		return
	var final_q = _pending_quality
	_pending_quality = ""
	_finish_make_card(final_q)
func _on_watch_ad_retry():
	if _hj_ads == null:
		_show_popup("📵 当前版本暂不支持广告重敲\n请直接封卡获得当前品质", Color("#FFD54F"))
		return
	if not _ad_ready or not _hj_ads.isRewardedAdReady():
		_show_popup("⏳ 广告还没准备好，请稍后再点", Color("#FFD54F"))
		# 仅当插件可用时预加载（避免无单例时触发 ad_failed 噪音）
		if Engine.has_singleton("HJAds"):
			_hj_ads.loadRewardedAd()
		return
	# 播放激励广告
	_hj_ads.showRewardedAd()
func _on_retry_ad_loaded(_placement_id: String):
	_ad_ready = true
	if _ad_status_hint and is_instance_valid(_ad_status_hint):
		_ad_status_hint.text = "✅ 广告已就绪，可以观看"
		_ad_status_hint.add_theme_color_override("font_color", Color("#4CAF50"))
func _on_retry_video_rewarded(rewarded: bool):
	# 注意：这里是"观看完成但广告可能还没关闭"。为了稳，奖励在 ad_closed 后再结算
	if rewarded:
		var retry_waiting := {"waiting": true}
		_retry_waiting = retry_waiting
func _on_retry_ad_closed(_result: String):
	# 广告关闭：仅当观看完整（有奖励标记）才重开敲击
	var should_retry := false
	if _retry_waiting != null and _retry_waiting.get("waiting", false) == true:
		should_retry = true
	_retry_waiting = null
	# 无论是否重敲，确认窗都要关闭（广告观看结束即返回品质确认，不会卡死）
	if _confirm_overlay and is_instance_valid(_confirm_overlay):
		_confirm_overlay.queue_free()
		_confirm_overlay = null
	_ad_status_hint = null
	if should_retry:
		_restart_quality_rhythm()
	# 预加载下一个广告（延迟1秒，确保SDK清理干净）
	await get_tree().create_timer(1.0).timeout
	if _hj_ads and is_instance_valid(_hj_ads) and Engine.has_singleton("HJAds"):
		_hj_ads.loadRewardedAd()
func _on_retry_ad_failed(error_msg: String):
	_ad_ready = false
	_show_popup("⚠ 广告加载失败：\n" + error_msg, Color("#FF5252"))
	# 不自动重载，避免"失败→重载→再失败→再重载"死循环
	
func _restart_quality_rhythm():
	# 重新敲击：回到音游界面，参数沿用已暂存的卡基品质区间 / 称号等级 / 卡墨稳定性
	if _pending_q_range == "":
		return
	_pending_quality = ""
	var q_range = _pending_q_range
	var title_level = _pending_title_level
	var quality_stab = _pending_quality_stab
	_start_quality_rhythm(q_range, title_level, quality_stab)

func _compute_quality_weights(q_range: String, title_level: int, quality_stab: float) -> Array:
	var parts = q_range.split(" ~ ")
	var lower = QUALITY_NAMES.find(parts[0]) if parts.size() > 0 else -1
	var upper = QUALITY_NAMES.find(parts[1]) if parts.size() > 1 else -1
	if lower < 0 or upper < 0 or lower > upper:
		lower = QUALITY_NAMES.find("标准")
		upper = lower
	var range_size = max(1, upper - lower)
	var mid = (lower + upper) / 2.0
	var weights := []
	for i in range(QUALITY_NAMES.size()):
		if i < lower or i > upper:
			weights.append(0.0)
		else:
			var dist = 1.0 - abs(float(i) - mid) / float(range_size + 1) * 2.0
			var w = max(0.01, 1.0 + dist)
			var title_shift = float(title_level - 1) * 0.05 / float(range_size + 1)
			w += title_shift * (float(i) - mid)
			var stab_factor = quality_stab / 20.0 * 0.5
			w *= (1.0 + stab_factor * (1.0 - abs(float(i) - mid) / float(range_size + 1)))
			weights.append(max(0.01, w))
	return weights

# 重置刻画状态（封卡后清空，防止重复封卡）
func _reset_engraving_state():
	# 只重置素材类状态（卡基/卡墨/辅材/纹路），保留攻防/卡名/描述/字段供连续制卡复用
	_selected_card_base = {}
	_selected_ink = {}
	_aux_items = []
	_card_rarity = "普通"
	_max_slots = 0
	_slots = []
	_slot_params = []
	_slot_buttons = []
	_effect_names = []
	_pending_final_load = 0.0
	_pending_tendency = {}
	# 更新按钮文字
	var base_btn = _preview_labels.get("select_base_btn")
	if base_btn:
		base_btn.text = "选择卡基"
	var ink_btn = _preview_labels.get("select_ink_btn")
	if ink_btn:
		ink_btn.text = "选择卡墨"
	var base_info = _preview_labels.get("base_info")
	if base_info:
		base_info.text = ""
	var ink_info = _preview_labels.get("ink_info")
	if ink_info:
		ink_info.text = ""
	_rebuild_slot_ui()

func _close_popup(overlay: ColorRect):
	if overlay and is_instance_valid(overlay):
		overlay.queue_free()


func _close_picker(overlay):
	if overlay and is_instance_valid(overlay):
		overlay.queue_free()


func _on_picker_overlay_clicked(event: InputEvent, overlay: ColorRect):
	if event is InputEventScreenTouch and not event.pressed:
		_close_picker(overlay)


func _on_popup_clicked(event: InputEvent, overlay: ColorRect):
	if event is InputEventScreenTouch and not event.pressed:
		_close_popup(overlay)


# ============================
#  主题切换
# ============================
func _on_theme_changed(_mode = null):
	super._on_theme_changed(_mode)
	for child in get_children():
		if child is Button:
			child.add_theme_color_override("font_color", Global.current.btn_text)
			child.add_theme_color_override("font_hover_color", Global.current.btn_text_hover)
			for state in ["normal", "hover", "pressed", "focus"]:
				var sb = child.get_theme_stylebox(state)
				if sb and sb is StyleBoxFlat:
					if state == "normal":
						sb.bg_color = Global.current.btn_bg
					elif state == "hover":
						sb.bg_color = Global.current.btn_bg_hover
					elif state == "pressed":
						sb.bg_color = Global.current.btn_bg_pressed
					child.add_theme_stylebox_override(state, sb)

func _apply_theme_custom():
	var back = get_node_or_null("BackBtn")
	if back is Button:
		back.add_theme_color_override("font_color", Global.current.btn_text)
		var s = StyleBoxFlat.new()
		s.bg_color = Global.current.btn_bg
		s.border_width_left = 2; s.border_width_right = 2; s.border_width_top = 2; s.border_width_bottom = 2
		s.border_color = Color("#888888")
		s.corner_radius_top_left = 10; s.corner_radius_top_right = 10
		s.corner_radius_bottom_left = 10; s.corner_radius_bottom_right = 10
		back.add_theme_stylebox_override("normal", s)


func _on_help():
	Global.play_sfx("click")
	_show_help_guide()


## 显示刻画卡牌指南弹窗
func _show_help_guide():
	var overlay = ColorRect.new()
	overlay.name = "HelpOverlay"
	overlay.color = Color(0, 0, 0, 0.7)
	overlay.anchor_left = 0.0; overlay.anchor_top = 0.0
	overlay.anchor_right = 1.0; overlay.anchor_bottom = 1.0
	overlay.mouse_filter = MOUSE_FILTER_STOP
	overlay.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			overlay.queue_free()
	)
	add_child(overlay)
	
	var panel = Panel.new()
	panel.name = "HelpPanel"
	panel.anchor_left = 0.05; panel.anchor_top = 0.05
	panel.anchor_right = 0.95; panel.anchor_bottom = 0.95
	panel.clip_contents = true
	var ps = StyleBoxFlat.new()
	ps.bg_color = Global.current.bg
	ps.border_width_left = 3; ps.border_width_right = 3
	ps.border_width_top = 3; ps.border_width_bottom = 3
	ps.border_color = Color("#5cb85c")
	ps.corner_radius_top_left = 16; ps.corner_radius_top_right = 16
	ps.corner_radius_bottom_left = 16; ps.corner_radius_bottom_right = 16
	panel.add_theme_stylebox_override("panel", ps)
	overlay.add_child(panel)
	
	# 标题
	var title = Label.new()
	title.text = "📖 刻画卡牌指南"
	title.add_theme_font_size_override("font_size", 60)
	title.add_theme_color_override("font_color", Global.current.title)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.anchor_left = 0.0; title.anchor_top = 0.0
	title.anchor_right = 1.0; title.anchor_bottom = 0.0
	title.offset_left = 0; title.offset_top = Global.ph(0.01)
	title.offset_right = 0; title.offset_bottom = Global.ph(0.08)
	panel.add_child(title)
	
	# 滚动区域
	var scroll = ScrollContainer.new()
	scroll.name = "HelpScroll"
	scroll.anchor_left = 0.02; scroll.anchor_top = 0.0
	scroll.anchor_right = 0.98; scroll.anchor_bottom = 1.0
	scroll.offset_left = 0; scroll.offset_top = Global.ph(0.085)
	scroll.offset_right = 0; scroll.offset_bottom = Global.ph(-0.08)
	scroll.scroll_horizontal = false
	panel.add_child(scroll)
	
	var vbox = VBoxContainer.new()
	vbox.name = "HelpVBox"
	vbox.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	vbox.add_theme_constant_override("separation", Global.ph(0.008))
	scroll.add_child(vbox)
	
	# 构建指南内容
	_build_help_content(vbox)
	
	# 延迟一帧设置宽度
	call_deferred("_set_help_vbox_width", vbox, scroll)
	
	# 关闭按钮
	var close_btn = Button.new()
	close_btn.text = "✕ 关闭"
	close_btn.add_theme_font_size_override("font_size", 50)
	var cs = StyleBoxFlat.new()
	cs.bg_color = Global.current.btn_bg
	cs.border_width_left = 2; cs.border_width_right = 2
	cs.border_width_top = 2; cs.border_width_bottom = 2
	cs.border_color = Color("#888888")
	cs.corner_radius_top_left = 10; cs.corner_radius_top_right = 10
	cs.corner_radius_bottom_left = 10; cs.corner_radius_bottom_right = 10
	close_btn.add_theme_stylebox_override("normal", cs)
	close_btn.add_theme_color_override("font_color", Global.current.btn_text)
	close_btn.anchor_left = 0.3; close_btn.anchor_top = 1.0
	close_btn.anchor_right = 0.7; close_btn.anchor_bottom = 1.0
	close_btn.offset_left = 0; close_btn.offset_top = Global.ph(-0.075)
	close_btn.offset_right = 0; close_btn.offset_bottom = Global.ph(-0.01)
	close_btn.pressed.connect(overlay.queue_free)
	panel.add_child(close_btn)


func _set_help_vbox_width(vbox: VBoxContainer, scroll: ScrollContainer):
	if not is_instance_valid(vbox) or not is_instance_valid(scroll):
		return
	var w = scroll.size.x
	if w <= 0:
		w = get_viewport_rect().size.x * 0.85
	vbox.custom_minimum_size = Vector2(w, 0)


func _make_help_section(vbox: VBoxContainer, title_text: String, title_color: Color) -> VBoxContainer:
	var section = VBoxContainer.new()
	section.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	section.add_theme_constant_override("separation", Global.ph(0.005))
	vbox.add_child(section)
	
	var sep = HSeparator.new()
	sep.add_theme_color_override("color", Global.current.topbar_border)
	sep.size_flags_horizontal = SIZE_FILL
	section.add_child(sep)
	
	var lbl = Label.new()
	lbl.text = title_text
	lbl.add_theme_font_size_override("font_size", 50)
	lbl.add_theme_color_override("font_color", title_color)
	lbl.size_flags_horizontal = SIZE_FILL
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	section.add_child(lbl)
	
	return section


func _make_help_label(vbox: VBoxContainer, text: String, color: Color = Color("#FFFFFF"), font_size: int = 45):
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.size_flags_horizontal = SIZE_FILL
	vbox.add_child(lbl)


func _build_help_content(vbox: VBoxContainer):
	# 1. 刻画总览
	var s1 = _make_help_section(vbox, "🔨 ① 刻画卡牌总览", Color("#5cb85c"))
	_make_help_label(s1, "刻画卡牌是将卡基、卡墨和纹路组合，制作成品卡牌的核心步骤。", Global.current.btn_text, 42)
	_make_help_label(s1, "完整流程共6步，按顺序完成即可生成一张强力卡牌！", Color("#CCCCCC"))
	
	# 2. 选择卡基
	var s2 = _make_help_section(vbox, "🃏 ② 选择卡基", Color("#e8a838"))
	_make_help_label(s2, "从仓库中选择一张已制作的卡基作为底材。", Global.current.btn_text, 42)
	_make_help_label(s2, "卡基的选择会影响成品卡牌的：", Color("#CCCCCC"))
	_make_help_label(s2, "  • 承载力（Load Cap）→ 决定纹路能量上限", Color("#FF9800"))
	_make_help_label(s2, "  • 卡槽数（Slots）→ 决定可安装的纹路组件数量", Color("#8BC34A"))
	_make_help_label(s2, "  • 品质（Quality）→ 影响成品卡牌的品质等级", Color("#9B59B6"))
	_make_help_label(s2, "  • 倾向（Tendency）→ 决定卡牌的主元素", Color("#FFD700"))
	_make_help_label(s2, "💡 高品质卡基 = 更强的成品卡牌！", Color("#FFD700"), 42)
	
	# 3. 选择卡墨
	var s3 = _make_help_section(vbox, "🎨 ③ 选择卡墨", Color("#6c9bcf"))
	_make_help_label(s3, "从仓库中选择已调制的卡墨作为墨水。", Global.current.btn_text, 42)
	_make_help_label(s3, "卡墨的属性会附加到刻画过程中：", Color("#CCCCCC"))
	_make_help_label(s3, "  • 负荷减免 → 降低纹路刻画能量消耗", Color("#4FC3F7"))
	_make_help_label(s3, "  • 效果强度 → 提升纹路效果触发成功率", Color("#FF8A65"))
	_make_help_label(s3, "  • 品质稳定性 → 稳定卡基品质波动", Color("#FFD54F"))
	_make_help_label(s3, "  • 倾向折扣 → 按元素降低纹路能量消耗", Color("#FFD700"))
	_make_help_label(s3, "  • 属性抗性 → 提升卡牌元素抗性", Color("#E91E63"))
	_make_help_label(s3, "💡 选择合适的卡墨可以大幅优化卡牌性能！", Color("#FFD700"), 42)
	
	# 4. 填写基础数值
	var s4 = _make_help_section(vbox, "💪 ④ 填写基础数值", Color("#FF9800"))
	_make_help_label(s4, "自由填写攻击和生命值，能量消耗将自动计算。", Global.current.btn_text, 42)
	_make_help_label(s4, "  • 攻击（Attack）：卡牌的攻击力，范围 0 ~ 99", Color("#FF5252"))
	_make_help_label(s4, "  • 生命（Health）：卡牌的生命值，范围 0 ~ 99", Color("#4CAF50"))
	_make_help_label(s4, "  • 0攻0命的效果卡牌也合法，发完入场效果后自动送墓", Color("#FFD700"))
	_make_help_label(s4, "  • 能量消耗公式：有效果卡牌按纹路计算，无效果随从 = floor((攻+命)/2)", Color("#CCCCCC"))
	
	# 5. 填写卡名与字段
	var s5 = _make_help_section(vbox, "🏷️ ⑤ 填写卡名与字段", Color("#3498DB"))
	_make_help_label(s5, "自定义卡牌名称和字段，用于卡牌联动检索。", Global.current.btn_text, 42)
	_make_help_label(s5, "  • 卡名：留空则自动拼接生成", Color("#CCCCCC"))
	_make_help_label(s5, "  • 字段：自定义字符串，最多3个，用于卡牌之间的联动检索", Color("#CCCCCC"))
	_make_help_label(s5, "  • 拥有相同字段的卡牌可以被检索和联动效果触发", Color("#CCCCCC"))
	
	# 6. 卡牌描述
	var s55 = _make_help_section(vbox, "📝 ⑥ 卡牌描述", Color("#FF9800"))
	_make_help_label(s55, "自由输入卡牌的效果说明或背景故事。", Global.current.btn_text, 42)
	_make_help_label(s55, "  • 描述文本限40字，超出自动截断", Color("#CCCCCC"))
	_make_help_label(s55, "  • 内容会展示在卡牌详情中，影响卡牌的故事感和沉浸感", Color("#CCCCCC"))
	
	# 7. 辅材
	var s6 = _make_help_section(vbox, "🧪 ⑦ 辅材（可选）", Color("#9b59b6"))
	_make_help_label(s6, "从仓库中选择已拥有的辅材，附在卡牌上增强效果。", Global.current.btn_text, 42)
	_make_help_label(s6, "  • 辅材在战斗中击败卡兽掉落获得", Color("#CCCCCC"))
	_make_help_label(s6, "  • 最多可附加3种辅材", Color("#CCCCCC"))
	_make_help_label(s6, "  • 辅材效果：攻击加成、生命加成、疾风（首回合可攻击）等", Color("#CCCCCC"))
	_make_help_label(s6, "  • 点击已加的辅材标签可移除并退回仓库", Color("#CCCCCC"))
	
	# 8. 纹路槽位
	var s7 = _make_help_section(vbox, "🔮 ⑧ 纹路槽位", Color("#FFD700"))
	_make_help_label(s7, "在卡基的槽位上安装纹路组件，决定卡牌的效果。", Global.current.btn_text, 42)
	_make_help_label(s7, "纹路组件类型：", Color("#CCCCCC"))
	_make_help_label(s7, "  ⚡ 触发器（TR）→ 触发条件（召唤成功、攻击时、受到伤害等）", Color("#FF9800"))
	_make_help_label(s7, "  🎯 动作（A）→ 执行效果（造成伤害、恢复生命、抽牌等）", Color("#FF5252"))
	_make_help_label(s7, "  🎯 目标（T）→ 效果目标（敌方单体、敌方全体、己方等）", Color("#4FC3F7"))
	_make_help_label(s7, "  ❓ 条件（C）→ 额外条件判断", Color("#9B59B6"))
	_make_help_label(s7, "  🔒 约束（CO）→ 效果约束", Color("#E91E63"))
	_make_help_label(s7, "💡 每个效果组 = 触发器 + 动作 + 目标，缺一不可", Color("#FFD700"), 42)
	_make_help_label(s7, "💡 卡槽数量 = 卡基的卡槽属性，点击空槽位选择纹路组件", Color("#FFD700"), 42)
	
	# 9. 制作步骤
	var s8 = _make_help_section(vbox, "🎯 ⑨ 制作步骤", Color("#4CAF50"))
	_make_help_label(s8, "1. 点击「选择卡基」从仓库中选择卡基", Global.current.btn_text, 42)
	_make_help_label(s8, "2. 点击「选择卡墨」从仓库中选择卡墨", Global.current.btn_text, 42)
	_make_help_label(s8, "3. 用 [-] [+] 调整攻击和生命值", Global.current.btn_text, 42)
	_make_help_label(s8, "4. 填写卡名和字段（可选）", Global.current.btn_text, 42)
	_make_help_label(s8, "5. 输入卡牌描述（限40字）", Global.current.btn_text, 42)
	_make_help_label(s8, "6. 点击「选择辅材」附加辅材（可选）", Global.current.btn_text, 42)
	_make_help_label(s8, "7. 点击空槽位选择纹路组件，装配完整效果", Global.current.btn_text, 42)
	_make_help_label(s8, "8. 在「卡牌预览」中确认最终属性", Global.current.btn_text, 42)
	_make_help_label(s8, "9. 点击「刻画卡牌」消耗能量，完成制作！", Global.current.btn_text, 42)
	_make_help_label(s8, "💡 制作完成的卡牌会存入仓库，可在牌组编辑中使用", Color("#FFD700"), 42)
	
	# 底部留白
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, Global.ph(0.02))
	vbox.add_child(spacer)


# ============================
#  导航
# ============================
func _on_back():
	Global.play_sfx("click")
	Global.change_scene("res://CardWorkshop.tscn")

func _build_dynamic_content():
	var vbox = get_node_or_null("ContentScroll/ContentVBox")
	if not vbox: return
	_build_base_selection(vbox)
	_build_ink_selection(vbox)
	_build_stat_input(vbox)
	_build_field_input(vbox)
	_build_card_detail(vbox)
	_build_aux_section(vbox)
	_build_effect_slots(vbox)
	_build_preview_section(vbox)
	_build_make_button(vbox)
	# ★ 启动刻画教程引导
	_start_tutorial_if_needed()
