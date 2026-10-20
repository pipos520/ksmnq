extends Node3D
class_name BattleScene3D

## BOSS 首通金币 = 100 × 区域序号（野外地图，仅首次通关发放；[PLACEHOLDER] L4 校准）
const BOSS_FIRST_CLEAR_GOLD := {
	"misty_forest": 100,
	"flame_cavern": 200,
	"storm_tower": 300,
	"shadow_swamp": 400,
	"legendary_ruins": 500,
}

const CARD_SCENE = preload("res://battle_new/BattleCard3D.tscn")

var _enemy_slots: Array = []
var _player_slots: Array = []

# 场上卡牌视觉节点引用表（与BM.field[]一一对应，null=空位）
var _player_card_nodes: Array = [null, null, null, null, null]
var _enemy_card_nodes: Array = [null, null, null, null, null]

const CAM_POS_X: float = -0.7
const CAM_POS_Z: Array[float] = [-2.0, 0.0, 2.0]
const CAM_POS_Y: float = 3.5
const CAM_BASE_SIZE: float = 4.3          # 设计基准正交 size（对应1920×1080高度）
const CAM_DESIGN_ASPECT: float = 16.0 / 9.0  # 设计基准宽高比
var _cam_state: int = 2
var _cam_tween: Tween = null
var _cam: Camera3D = null
var _view_btn: Button = null
var _cam_state_before_discard: int = 2  # 弃牌动画前视角，动画结束后恢复
var _prev_cam_state: int = 2  # 效果发动前的视角，用于恢复
var _player_deck_cards: Array = []
var _enemy_deck_cards: Array = []

var _card_front_mat: StandardMaterial3D = null
var _card_back_mat: StandardMaterial3D = null
# 预创建的边框高亮材质（避免运行时动态创建）
var _mat_attack_green: StandardMaterial3D = null
var _mat_attack_gray: StandardMaterial3D = null

var _player_deck_nodes: Array = []
var _enemy_deck_nodes: Array = []
var _player_hand_nodes: Array = []
var _enemy_hand_nodes: Array = []
var _player_hand_cards: Array = []  # BattleCard3D[5]
var _enemy_hand_cards: Array = []  # BattleCard3D[5]
var _player_hand_datas: Array = []  # card data[5]

# 回合信息
var _turn_count: int = 1
var _is_player_turn: bool = true
var _phase_name: String = "主要阶段"
@onready var _turn_info_label: Label3D = $TurnInfoLabel

# BattleManager
var _battle_manager: BattleManager = null
var _player_name: String = "卡师"
var _enemy_name: String = "暗影法师"
var _player_hp: int = 30
var _player_max_hp: int = 30
var _player_energy: int = 3
var _player_max_energy: int = 5
var _enemy_hp: int = 100
var _enemy_max_hp: int = 100
var _enemy_energy: int = 3
var _enemy_max_energy: int = 5

# 战斗结算
var _exit_to_main: bool = true
var _battle_log: Array = []

# 信息栏Label3D引用
@onready var _enemy_name_lbl: Label3D = get_node_or_null("EnemyField/InfoArea/NameLabel")
@onready var _enemy_hp_lbl: Label3D = get_node_or_null("EnemyField/InfoArea/HPLabel")
@onready var _enemy_energy_lbl: Label3D = get_node_or_null("EnemyField/InfoArea/EnergyLabel")
@onready var _player_name_lbl: Label3D = get_node_or_null("PlayerField/InfoArea/NameLabel")
@onready var _player_hp_lbl: Label3D = get_node_or_null("PlayerField/InfoArea/HPLabel")
@onready var _player_energy_lbl: Label3D = get_node_or_null("PlayerField/InfoArea/EnergyLabel")
@onready var _player_deck_lbl: Label3D = get_node_or_null("PlayerField/DeckArea/Label")
@onready var _enemy_deck_lbl: Label3D = get_node_or_null("EnemyField/DeckArea/Label")
# 卡组剩余张数（初始=卡组总数，抽牌后递减）
var _player_deck_count: int = 0
var _enemy_deck_count: int = 0

# 手牌交互
var _selected_hand_index: int = -1
var _hand_press_time: float = -1.0
var _hand_press_index: int = -1
var _long_press_triggered: bool = false
var _detail_panel: Control = null
var _grave_panel: Control = null          # 墓地弹窗独立管理（不污染 _detail_panel）
var _grave_panel_player: bool = true      # 当前墓地面板显示的哪一方
var _grave_press_time: float = -1.0       # 墓地行长按开始时间
var _grave_press_index: int = -1          # 长按的墓地卡 index
var _grave_long_press_triggered: bool = false
const GRAVE_LONG_PRESS_TIME: float = 0.8
const HAND_EXPAND_OFFSET: float = 0.6
const HAND_EXPAND_POS_Y: float = 0.35    # 选中手牌浮起高度
const HAND_EXPAND_POS_Z: float = 0.5     # 选中手牌向镜头方向前移
const LONG_PRESS_TIME: float = 0.8
const FONT_SIZE_DETAIL = 150

# 教学战逐步引导文案（玩家完成当前操作才推进下一步）
var _tutorial_popup_overlay: Control = null
var _tutorial_step: int = 0
const _TUTORIAL_HINTS := [
	" 先看屏幕上方信息栏：是血量，是能量。能量每回合都会回满，上限还会+1——放心大胆地出牌！",
	" 长按一张手牌，可以查看卡牌详情。",
	" 卡面四角：左上属性、右上能量、左下攻击、右下血量。把手牌拖到场上空位即可召唤！",
	" 点右下角「进入战斗阶段」——刚召唤的卡要下回合才能攻击。",
	"⏭ 点右下角「结束回合」，结束本回合轮到对方行动。",
	" 又到你了！点右下角「进入战斗阶段」准备出击！",
	" 把高亮（可攻击）的卡牌拖拽到敌方卡牌上即可攻击",
	" 当敌方场地为空时，拖拽卡牌到敌方场地上，可以直接攻击敌方英雄",
	" 对手生命归零即获胜！",
]

# 弃牌选择
var _discard_mode: bool = false
var _discard_selected: Array = []  # 选中的手牌索引
var _discard_need: int = 0  # 需要弃的张数
var _discard_last_click_frame: int = -1  # 防止同一帧内重复点击
var _discard_callback_id: int = -1  # 当前弃牌回调ID
var _discard_request_queue: Array = []  # 待处理的弃牌请求队列
var _discard_panel: Node = null  # 弃牌弹窗叠加层(CanvasLayer)
var _discard_count_label: Label = null  # 已选计数
var _discard_confirm_btn: Button = null  # 确认按钮

# 拖拽控制器 & 场地管理器
var _drag_ctrl: CardDragController = null
var _field_mgr: FieldSlotManager = null
var _enemy_ai: EnemyAIController = null
var _battle_driver: BattleDriver = null  # 战斗节奏驱动器（横竖屏共用，见 battle_core/BattleDriver.gd）
var _is_dragging_hand: bool = false
var _drag_start_screen: Vector2 = Vector2.ZERO

# 场地卡牌攻击拖拽交互
var _field_press_time: float = -1.0
var _field_press_index: int = -1
var _field_press_is_player: bool = true  # 按下的卡位是玩家方还是敌方
var _field_drag_started: bool = false
var _field_long_press_triggered: bool = false  # 场地长按详情是否已触发
const FIELD_LONG_PRESS_TIME: float = 0.8  # 场地长按时间阈值
const DRAG_CANCEL_DIST: float = 30.0  # 移动超过此距离取消长按详情

# 墓地节点
var _player_grave_node: Node3D = null
var _enemy_grave_node: Node3D = null
var _player_grave_cards: Array = []  # 墓地卡牌节点列表（用于堆叠）
var _enemy_grave_cards: Array = []

# 除外区节点
var _player_exile_node: Node3D = null
var _enemy_exile_node: Node3D = null
var _player_exile_cards: Array = []  # 除外区卡牌节点列表
var _enemy_exile_cards: Array = []

# 手牌动态布局：最左对齐1号卡位(x=-2.4)，最右对齐5号卡位(x=2.4)
const HAND_MIN_X: float = -2.4
const HAND_MAX_X: float = 2.4
const HAND_Z: float = 3.4
const HAND_Y: float = 0.15
const HAND_CARD_WIDTH: float = 1.0       # 卡牌mesh宽度，间距小于此则重叠
const HAND_Z_OVERLAP: float = 0.02       # 左压右时Z偏移步进（左边Z更大=更靠前）
const HAND_SLOT_MAX: int = 8             # 手牌显示槽上限（BM弃牌线6张，留余量）
const ENEMY_HAND_POS: Array = [
	Vector3(-1.000, 0.150, -3.400),
	Vector3(-0.500, 0.190, -3.400),
	Vector3(0.000, 0.230, -3.400),
	Vector3(0.500, 0.270, -3.400),
	Vector3(1.000, 0.310, -3.400),
]
# 敌方手牌动态布局参数（镜像我方，Z方向相反）
const ENEMY_HAND_MIN_X: float = -2.4
const ENEMY_HAND_MAX_X: float = 2.4
const ENEMY_HAND_Z: float = -3.4
const ENEMY_HAND_Y: float = 0.15

# 战斗背景纹理平面尺寸（保持 16:9 纹理比例，覆盖相机 z 平移 [-2,0,2] 全程视野）
# 纵向需 4.3 + 2*2.0 = 8.3，横向等比放大 8.3*16/9 ≈ 14.76
const BATTLE_BG_W: float = 14.76
const BATTLE_BG_H: float = 8.3
const BATTLE_BG_Y: float = 0.01  # 略高于 Floor，避免 Z-fighting

## 动态创建战斗背景纹理平面
func _create_battle_bg() -> void:
	# 按当前牌组的桌布选择加载纹理：
	#   - 租借卡组：按所属系列自动匹配桌布（和卡背共用系列判定）
	#   - 玩家自有卡组：读取牌组的桌布设置，未设置则回退默认
	var cloth_id := "default"
	if Global.current_rented_deck_id != "":
		var rd := Global.get_rented_deck(Global.current_rented_deck_id)
		var rd_name := String(rd.get("name", rd.get("source_deck", "")))
		cloth_id = CardManager.get_back_id_for_deck_name(rd_name)
		print("[BattleScene3D] 租借卡组桌布: ", rd_name, " -> ", cloth_id)
	elif Global.current_deck_id != "":
		cloth_id = CardManager.get_deck_tablecloth(Global.current_deck_id)
		print("[BattleScene3D] 玩家卡组桌布: ", cloth_id)
	var cloth_path := CardManager.get_deck_tablecloth_path(cloth_id)
	var tex = load(cloth_path)
	if not tex:
		push_warning("[BattleScene3D] 战斗背景纹理加载失败: " + cloth_path)
		tex = load("res://assets/3d/battle_bg_default.png")
	if not tex:
		return

	var mat = StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var mesh = PlaneMesh.new()
	mesh.size = Vector2(BATTLE_BG_W, BATTLE_BG_H)

	var bg_node = MeshInstance3D.new()
	bg_node.name = "BattleBG"
	bg_node.mesh = mesh
	bg_node.material_override = mat
	# PlaneMesh 默认在 XZ 平面，中心原点。相机看向 -Y，俯视时 X=右，Z=上（画面）
	# 场景整体以 z=0 为中线（Divider 位置），背景也居中在 z=0
	bg_node.position = Vector3(CAM_POS_X, BATTLE_BG_Y, 0)

	# 放到 Floor 后面（渲染顺序更早），但视觉上覆盖 Floor
	# 用低 render priority 让它在最底层
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA  # 保留可能的 alpha 通道

	add_child(bg_node)


func _ready() -> void:
	# 横屏战斗：连逻辑画布一起切成 1920x1080（只改窗口大小无效，见 Global 里的说明）
	Global.enter_landscape_canvas()

	# 动态创建战斗背景纹理平面（放在 Floor 上方，覆盖相机视野）
	_create_battle_bg()

	_cam = get_node_or_null("BattleCamera") as Camera3D
	if _cam:
		_cam.position = Vector3(CAM_POS_X, CAM_POS_Y, CAM_POS_Z[_cam_state])
		# 确保相机保持俯视角度（场景文件中的默认朝向）
		_cam.rotation_degrees = Vector3(-90, 0, 0)
		# 监听窗口大小变化，动态调整正交摄像机 size
		get_viewport().size_changed.connect(_on_viewport_resized)
		_adjust_camera_size()
	_view_btn = get_node_or_null("UI/ViewBtn") as Button
	if _view_btn:
		_view_btn.pressed.connect(_on_view_switch)
		_view_btn.text = "视角: 己方"
		# 把视角按钮移到更高层，弃牌弹窗遮不住
		var top_layer = CanvasLayer.new()
		top_layer.name = "ViewBtnLayer"
		top_layer.layer = 100
		# ★ 关键：树暂停时（弃牌/特效弹窗）按钮仍要能点，必须设为 ALWAYS
		top_layer.process_mode = Node.PROCESS_MODE_ALWAYS
		_view_btn.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(top_layer)
		_view_btn.get_parent().remove_child(_view_btn)
		top_layer.add_child(_view_btn)
	var back_btn = get_node_or_null("UI/BackBtn") as Button
	if back_btn:
		back_btn.pressed.connect(_on_back)

	var enemy_field = get_node_or_null("EnemyField")
	var player_field = get_node_or_null("PlayerField")
	if enemy_field:
		for i in range(5):
			var slot = enemy_field.get_node_or_null("EnemySlot_" + str(i))
			if slot:
				_enemy_slots.append(slot)
				# 给敌方场地卡位加交互Area（用于长按详情）
				_add_field_slot_area(slot, i, false)
	if player_field:
		for i in range(5):
			var slot = player_field.get_node_or_null("PlayerSlot_" + str(i))
			if slot:
				_player_slots.append(slot)
				# 给玩家场地卡位加交互Area（用于攻击拖拽+长按详情）
				_add_field_slot_area(slot, i, true)
		# 获取墓地节点
		_player_grave_node = player_field.get_node_or_null("GraveArea")
		_player_exile_node = player_field.get_node_or_null("ExileArea")
		# 给墓地节点加交互Area
		if _player_grave_node:
			_add_grave_area(_player_grave_node, true)
	if enemy_field:
		_enemy_grave_node = enemy_field.get_node_or_null("GraveArea")
		_enemy_exile_node = enemy_field.get_node_or_null("ExileArea")
		if _enemy_grave_node:
			_add_grave_area(_enemy_grave_node, false)
	
	_card_front_mat = StandardMaterial3D.new()
	var front_tex = load("res://assets/3d/card_front.png")
	if front_tex:
		_card_front_mat.albedo_texture = front_tex
	_card_front_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_card_front_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_card_front_mat.no_depth_test = false
	_card_front_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	
	_card_back_mat = StandardMaterial3D.new()
	# 按当前牌组的卡背选择加载纹理：
	#   - 租借卡组：按所属系列自动匹配卡背
	#   - 玩家自有卡组：读取牌组的卡背设置，未设置则回退默认
	var back_id := "default"
	if Global.current_rented_deck_id != "":
		var rd := Global.get_rented_deck(Global.current_rented_deck_id)
		var rd_name := String(rd.get("name", rd.get("source_deck", "")))
		back_id = CardManager.get_back_id_for_deck_name(rd_name)
		print("[BattleScene3D] 租借卡组卡背: ", rd_name, " -> ", back_id)
	elif Global.current_deck_id != "":
		back_id = CardManager.get_deck_back(Global.current_deck_id)
		print("[BattleScene3D] 玩家卡组卡背: ", back_id)
	var back_path := CardManager.get_deck_back_path(back_id)
	var back_tex = load(back_path)
	if back_tex == null:
		back_tex = load("res://assets/3d/card_backs/card_back_default.png")
	if back_tex == null:
		back_tex = load("res://assets/3d/card_back.png")
	if back_tex:
		_card_back_mat.albedo_texture = back_tex
	_card_back_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_card_back_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_card_back_mat.no_depth_test = false
	_card_back_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS

	# 预创建边框高亮材质
	_mat_attack_green = StandardMaterial3D.new()
	_mat_attack_green.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_attack_green.albedo_color = Color(0.3, 1.0, 0.3, 0.8)
	_mat_attack_green.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_attack_green.no_depth_test = false
	_mat_attack_gray = StandardMaterial3D.new()
	_mat_attack_gray.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_attack_gray.albedo_color = Color(0.5, 0.5, 0.5, 0.6)
	_mat_attack_gray.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_attack_gray.no_depth_test = false
	
	_load_deck_data()
	_create_hand_nodes()
	# 回合信息Label已预置在tscn中，只需设置字体和更新文字
	var font = load("res://assets/share/font_pixel.ttf")
	if font and _turn_info_label:
		_turn_info_label.font = font
	# 信息栏Label3D也设置字体
	for lbl in [_enemy_name_lbl, _enemy_hp_lbl, _enemy_energy_lbl, _player_name_lbl, _player_hp_lbl, _player_energy_lbl, _player_deck_lbl, _enemy_deck_lbl]:
		if lbl and font:
			lbl.font = font
	# 初始化战斗数据
	_init_battle_data()
	# ★ 从 BM 同步实际使用的卡组数据到场景（覆盖场景独立生成的 _enemy_deck_cards）
	_sync_deck_from_bm()
	_update_all_info_labels()
	_update_turn_info()
	# 初始化场地管理器（先于拖拽控制器）
	_field_mgr = FieldSlotManager.new()
	_field_mgr.setup(self, _player_slots)
	add_child(_field_mgr)
	# 初始化拖拽控制器（注入field_mgr和battle_mgr）
	_drag_ctrl = CardDragController.new()
	_drag_ctrl.setup(self, _cam, _player_slots, _enemy_slots, _player_hand_nodes, _player_hand_cards, _player_hand_datas, _card_front_mat, _field_mgr, _battle_manager, _enemy_card_nodes, _player_card_nodes)
	add_child(_drag_ctrl)
	# 初始化战斗节奏驱动器（横竖屏共用同一驱动协议，见 battle_core/BattleDriver.gd）
	_battle_driver = BattleDriver.new()
	_battle_driver.name = "BattleDriver"
	add_child(_battle_driver)
	_battle_driver.attach(_battle_manager)
	# 初始化敌方AI控制器（已退化为纯 3D 表现层，节奏由驱动器控制）
	_enemy_ai = EnemyAIController.new()
	_enemy_ai.setup(self, _battle_manager, _battle_driver, _cam, _card_front_mat, _card_back_mat, _enemy_slots, _enemy_hand_nodes, _player_slots, _enemy_card_nodes, _player_card_nodes)
	add_child(_enemy_ai)
	_stack_deck_cards()
	# 预热效果VFX材质（效果线/闪光/边框高亮），把shader首次编译前移到读盘期
	_prewarm_battle_vfx()
	_play_start_draw_animation()
	
	# 抽牌动画结束后启动石头剪刀布
	await get_tree().create_timer(2.0).timeout
	_start_rps_select()
	
	print("[BattleScene3D] ready: cam%d p_cards%d e_cards%d" % [_cam_state, _player_deck_cards.size(), _enemy_deck_cards.size()])


func _load_deck_data() -> void:
	# === 己方：从选择的卡组加载 ===
	var deck_id = Global.current_deck_id
	# 租借卡组：直接用存储的完整卡对象（不依赖图鉴/收藏）
	if Global.current_rented_deck_id != "":
		var rd = Global.get_rented_deck(Global.current_rented_deck_id)
		if not rd.is_empty():
			for c in rd.get("card_datas", []):
				_player_deck_cards.append(c.duplicate(true))
			print("[BattleScene3D] 使用租借卡组: ", rd.get("name", ""), " ", _player_deck_cards.size(), "张")
	elif deck_id != "":
		var deck_data = CardManager.get_deck(deck_id)
		var card_ids = deck_data.get("cards", [])
		var all_cards = CardManager.get_all_cards()
		for card_id in card_ids:
			for card_data in all_cards:
				if card_data.get("id", "") == card_id or card_data.get("template_id", "") == card_id:
					_player_deck_cards.append(card_data.duplicate(true))
					break
	else:
		print("[BattleScene3D] 未选择卡组，使用全部卡牌")
		for card_data in CardManager.get_all_cards():
			_player_deck_cards.append(card_data.duplicate(true))
	
	# === 敌方：从卡组池随机选一套 ===
	_enemy_deck_cards = _pick_ai_deck()
	
	print("[BattleScene3D] 我方卡组(初始): %d张, 敌方卡组(初始): %d张" % [_player_deck_cards.size(), _enemy_deck_cards.size()])
	# 初始化卡组剩余张数（抽牌前，后续会被 _sync_deck_from_bm 修正）
	_player_deck_count = _player_deck_cards.size()
	_enemy_deck_count = _enemy_deck_cards.size()

## 从 BattleManager 同步实际使用的卡组数据到场景
## 调用时机：_init_battle_data() 之后、_stack_deck_cards() 之前
## 目的：BM 内部独立生成的敌方卡组可能与场景 _pick_ai_deck 不一致，
##      必须以 BM 为准，确保堆叠的卡牌实体数 = 玩家实际卡组数
func _sync_deck_from_bm() -> void:
	if _battle_manager == null:
		return
	# === 己方 ===
	if _battle_manager.player_self and _battle_manager.player_self.deck:
		var pd = _battle_manager.player_self.deck
		if pd._cards is Array:
			# BM 内部 _cards 是 BattleCard 对象，转 dict 用于 3D 显示
			_player_deck_cards.clear()
			for c in pd._cards:
				if c == null:
					continue
				_player_deck_cards.append(_battle_card_to_dict_for_display(c))
	# === 敌方 ===
	if _battle_manager.player_opponent and _battle_manager.player_opponent.deck:
		var ed = _battle_manager.player_opponent.deck
		if ed._cards is Array:
			_enemy_deck_cards.clear()
			for c in ed._cards:
				if c == null:
					continue
				_enemy_deck_cards.append(_battle_card_to_dict_for_display(c))
	# 更新缓存张数
	_player_deck_count = _player_deck_cards.size()
	_enemy_deck_count = _enemy_deck_cards.size()
	if _player_deck_lbl:
		_player_deck_lbl.text = "%d张" % _player_deck_count
	if _enemy_deck_lbl:
		_enemy_deck_lbl.text = "%d张" % _enemy_deck_count
	print("[BattleScene3D] 同步BM后 我方卡组: %d张, 敌方卡组: %d张" % [_player_deck_count, _enemy_deck_count])

## 把 BM 的 BattleCard 转成 3D 卡牌显示的 dict（供场景层堆叠用）
func _battle_card_to_dict_for_display(c) -> Dictionary:
	var d = {
		"name": "",
		"card_name": "",
		"cost": 0,
		"atk": 0,
		"hp": 0,
		"element": "无",
		"fields": [],
		"quality": "标准",
		"star": 1,
		"effects": [],
	}
	if c == null:
		return d
	var cname = c.card_name
	# 不用 get_display_name()（含属性emoji前缀），左上角 ElemLabel 已单独显示属性
	d["name"] = cname
	d["card_name"] = cname
	d["cost"] = c.base_cost
	d["atk"] = c.base_atk
	d["hp"] = c.base_hp
	d["element"] = c.element if c.element != "" else "无"
	d["fields"] = c.fields if c.fields.size() > 0 else []
	d["quality"] = c.quality if c.quality != "" else "标准"
	d["star"] = c.star if c.star > 0 else 1
	d["effects"] = c.effects if c.effects.size() > 0 else []
	return d


## 从服务器卡组池 + 本地卡组随机选一套作为AI对手卡组
func _pick_ai_deck() -> Array:
	var candidates: Array = []  # 每项为 { "name": String, "card_datas": Array }
	var all_cards = CardManager.get_all_cards()
	
	# 1. 服务器卡组池
	var server_decks = Global.server_decks if Global.server_decks != null else []
	for sdeck in server_decks:
		var deck_data = sdeck.get("deck_data", {})
		if deck_data is Dictionary:
			var sdeck_card_datas = deck_data.get("card_datas", [])
			if sdeck_card_datas is Array and sdeck_card_datas.size() > 0:
				candidates.append({"name": deck_data.get("name", sdeck.get("name", "AI卡组")), "card_datas": sdeck_card_datas})
			else:
				# 兼容旧格式：ID列表
				var sdeck_cards = deck_data.get("cards", [])
				if sdeck_cards is Array and sdeck_cards.size() > 0:
					var parsed := []
					for cid in sdeck_cards:
						for card_data in all_cards:
							if card_data.get("id", "") == cid or card_data.get("template_id", "") == cid:
								parsed.append(card_data.duplicate(true))
								break
					if parsed.size() > 0:
						candidates.append({"name": sdeck.get("name", "服务器卡组"), "card_datas": parsed})
	
	# 2. 本地所有卡组（排除玩家当前使用的）
	var local_decks = CardManager.get_all_decks()
	for local_id in local_decks:
		if local_id == Global.current_deck_id:
			continue
		var local_deck = local_decks[local_id]
		var local_cards = local_deck.get("cards", [])
		if local_cards is Array and local_cards.size() > 0:
			var parsed := []
			for cid in local_cards:
				for card_data in all_cards:
					if card_data.get("id", "") == cid or card_data.get("template_id", "") == cid:
						parsed.append(card_data.duplicate(true))
						break
			if parsed.size() > 0:
				candidates.append({"name": local_deck.get("name", local_id), "card_datas": parsed})
	
	# 3. 也检查 Global.current_enemy_data（决斗场预设敌人）
	var enemy_data = Global.current_enemy_data
	if enemy_data.size() > 0:
		var en_card_datas = enemy_data.get("card_datas", [])
		if en_card_datas.size() > 0:
			candidates.append({"name": enemy_data.get("name", "预设敌人"), "card_datas": en_card_datas})
		else:
			var deck_template_ids = enemy_data.get("deck", [])
			if deck_template_ids.size() > 0:
				var parsed := []
				for tid in deck_template_ids:
					var tmpl = Global.get_enemy_card_template(tid)
					if tmpl.size() > 0:
						parsed.append(tmpl.duplicate(true))
				if parsed.size() > 0:
					candidates.append({"name": enemy_data.get("name", "预设敌人"), "card_datas": parsed})
	
	# 4. 空回退
	if candidates.is_empty():
		print("[BattleScene3D]  卡组池为空，回退到随机卡牌")
		var result := []
		for i in range(20):
			result.append(_generate_filler_card())
		return result
	
	# 随机选一套
	var picked = candidates[randi() % candidates.size()]
	var ai_cards = picked.get("card_datas", [])
	print("[BattleScene3D]  AI对手使用卡组: %s (%d张)" % [picked.get("name", "未知"), ai_cards.size()])
	return ai_cards


func _generate_filler_card() -> Dictionary:
	var elements = ["火", "水", "风", "地", "光", "暗"]
	var elem = elements[randi() % elements.size()]
	var atk = 1 + randi() % 3
	var hp = 1 + randi() % 3
	var cost = 1 + randi() % 2
	return {
		"id": "filler_" + str(randi()),
		"card_name": "空白卡",
		"name": "空白卡",
		"fields": [],
		"attack": atk, "atk": atk,
		"health": hp, "hp": hp,
		"energy_cost": cost, "cost": cost,
		"quality": "普通",
		"description": "", "desc": "",
		"effects": [], "aux_items": [],
		"star": 1,
	}


func _create_hand_nodes() -> void:
	for i in range(5):
		var node = Node3D.new()
		node.name = "PlayerHand_" + str(i)
		node.position = Vector3(HAND_MIN_X + (HAND_MAX_X - HAND_MIN_X) * float(i) / 4.0, HAND_Y, HAND_Z)
		add_child(node)
		_player_hand_nodes.append(node)
		_player_hand_cards.append(null)
		_player_hand_datas.append(null)
		
		# 添加交互区域
		var area = Area3D.new()
		area.name = "HandArea"
		area.input_ray_pickable = true
		# ★ 关键：弃牌阶段 get_tree().paused=true，Area3D 默认 INHERIT 会暂停不响应 input_event
		# 设为 ALWAYS 保证弃牌弹窗时手牌仍可点击选中
		area.process_mode = Node.PROCESS_MODE_ALWAYS
		var col = CollisionShape3D.new()
		col.shape = BoxShape3D.new()
		col.shape.size = Vector3(1.2, 0.1, 1.6)
		area.add_child(col)
		area.input_event.connect(_on_hand_input_event.bind(i, false))
		node.add_child(area)
		
		var node2 = Node3D.new()
		node2.name = "EnemyHand_" + str(i)
		node2.position = ENEMY_HAND_POS[i]
		add_child(node2)
		_enemy_hand_nodes.append(node2)
		_enemy_hand_cards.append(null)


func _stack_deck_cards() -> void:
	_stack_one_side("EnemyField/DeckArea", _enemy_deck_cards, _enemy_deck_nodes, true)
	_stack_one_side("PlayerField/DeckArea", _player_deck_cards, _player_deck_nodes, false)


## 预热战斗VFX材质/shader（效果线/边框高亮/命中闪光/闪白/卡位高亮）
## 避免战斗中首次创建StandardMaterial3D时Mali-G77现场编译shader导致掉帧
func _prewarm_battle_vfx() -> void:
	# 临时根：放在战场中间，2帧后移除（抽牌动画期间几乎不可见）
	var root := Node3D.new()
	root.name = "PrewarmVFXRoot"
	add_child(root)
	root.global_position = Vector3(0, 0.15, 0.5)
	var mk_mi := func(quad_size: Vector2, mat: StandardMaterial3D) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = quad_size
		mi.mesh = quad
		mi.material_override = mat
		root.add_child(mi)
		return mi
	# 1) 效果线三种颜色（金/红/绿，对应_play_effect_line_and_flash）
	var line_colors := [
		Color(1.0, 0.85, 0.2, 0.8),
		Color(1.0, 0.3, 0.3, 0.8),
		Color(0.3, 1.0, 0.3, 0.8),
	]
	for c in line_colors:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = c
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.no_depth_test = true
		mk_mi.call(Vector2(0.6, 0.8), mat)
	# 2) 边框高亮（金闪/绿可攻/灰不可攻）
	var border_colors := [
		Color(1.0, 0.85, 0.2, 0.8),
		Color(0.3, 1.0, 0.3, 0.7),
		Color(0.5, 0.5, 0.5, 0.5),
	]
	for c in border_colors:
		var mat2 := StandardMaterial3D.new()
		mat2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat2.albedo_color = c
		mat2.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat2.no_depth_test = true
		mk_mi.call(Vector2(1.0, 1.4), mat2)
	# 3) 攻击卡闪白 + 命中闪光（橙）
	var white_mat := StandardMaterial3D.new()
	white_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	white_mat.albedo_color = Color.WHITE
	mk_mi.call(Vector2(0.7, 1.0), white_mat)
	var hit_mat := StandardMaterial3D.new()
	hit_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hit_mat.albedo_color = Color(1.0, 0.5, 0.2, 0.8)
	hit_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hit_mat.no_depth_test = true
	mk_mi.call(Vector2(0.5, 0.7), hit_mat)
	# 4) 敌方卡位高亮红（拖拽指向用）
	var hl_mat := StandardMaterial3D.new()
	hl_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hl_mat.albedo_color = Color(1.0, 0.4, 0.4, 0.7)
	hl_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mk_mi.call(Vector2(1.0, 1.4), hl_mat)
	# 渲染2帧确保shader变体编译完成，然后移除
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(root):
		root.queue_free()


func _stack_one_side(deck_path: String, cards: Array, storage: Array, is_enemy: bool) -> void:
	var deck_area = get_node_or_null(deck_path)
	if not deck_area:
		return
	for i in range(cards.size()):
		var card_node = CARD_SCENE.instantiate()
		card_node.name = "DeckCard_" + str(i)
		var z_offset = 0.02 + i * 0.006
		card_node.position = Vector3(0, 0.005, z_offset)
		deck_area.add_child(card_node)
		# setup 必须在 add_child 之后调用，否则 @onready 变量为 null
		card_node.setup(cards[i], _card_front_mat, _card_back_mat)
		storage.append(card_node)


func _play_start_draw_animation() -> void:
	for i in range(5):
		_draw_card_animation(false, i)
		await get_tree().create_timer(0.25).timeout
	await get_tree().create_timer(0.5).timeout
	for i in range(5):
		_draw_card_animation(true, i)
		await get_tree().create_timer(0.25).timeout
	# 初始手牌抽完，以BM.hand为唯一数据源重建显示层（丢弃独立的演示卡组数据）
	_sync_player_hand_from_bm()
	_layout_player_hand(true)
	# 敌方手牌也同步重建
	_sync_enemy_hand_from_bm()
	_layout_enemy_hand(true)


func _draw_card_animation(is_enemy: bool, hand_index: int) -> void:
	var deck_nodes = _enemy_deck_nodes if is_enemy else _player_deck_nodes
	var deck_data = _enemy_deck_cards if is_enemy else _player_deck_cards
	var hand_nodes = _enemy_hand_nodes if is_enemy else _player_hand_nodes
	if deck_nodes.is_empty() or deck_data.is_empty():
		return
	var card_node = deck_nodes.pop_back()
	var card_data = deck_data.pop_back()
	
	if is_enemy:
		card_node.set_face_down(_card_back_mat)
		_enemy_hand_cards[hand_index] = card_node
	else:
		card_node.set_face_up(_card_front_mat)
		_player_hand_cards[hand_index] = card_node
		_player_hand_datas[hand_index] = card_data
	
	var hand_node = hand_nodes[hand_index]
	var global_start = card_node.global_position
	var global_end = hand_node.global_position + Vector3(0, 0.02, 0)
	# 中间抬高点（弧线）
	var mid_pos = (global_start + global_end) * 0.5 + Vector3(0, 1.5, 0)
	
	card_node.reparent(self, true)  # 先摘到场景根，用global_position做动画
	card_node.global_position = global_start
	card_node.visible = true
	
	var tween = create_tween().set_parallel(false)
	Global.play_sfx("draw")
	# 弧线飞行：起点 → 抬高点 → 手牌位置
	var fly_dur = 0.6
	tween.tween_method(func(f: float):
		if not is_instance_valid(card_node):
			return
		# 二次贝塞尔曲线
		var p = global_start.lerp(mid_pos, f).lerp(mid_pos.lerp(global_end, f), f)
		card_node.global_position = p
	, 0.0, 1.0, fly_dur).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	# 飞到后 reparent 到手牌节点
	tween.tween_callback(func():
		if not is_instance_valid(card_node):
			return
		card_node.reparent(hand_node, true)
		card_node.position = Vector3(0, 0, 0.02)
	)


func _on_view_switch() -> void:
	_cam_state = (_cam_state + 1) % 3
	var labels = ["敌方", "中", "己方"]
	if _view_btn:
		_view_btn.text = "视角: " + labels[_cam_state]
	if _cam:
		if _cam_tween and _cam_tween.is_valid():
			_cam_tween.kill()
		_cam_tween = create_tween()
		_cam_tween.tween_property(_cam, "position:z", CAM_POS_Z[_cam_state], 0.5).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)


## 窗口大小变化 → 动态调整正交摄像机 size（保证不裁剪，多余区域留黑边）
func _on_viewport_resized() -> void:
	_adjust_camera_size()


## 根据当前 viewport 宽高比调整正交 size，保证设计基准视野完整可见
func _adjust_camera_size() -> void:
	if not _cam:
		return
	var vp_size = get_viewport().get_visible_rect().size
	if vp_size.y <= 0:
		return
	var current_aspect = vp_size.x / vp_size.y
	# 正交 size 控制可见高度。宽度 = size × aspect
	# 设计基准：size=4.3（高度），aspect=16:9 → 可见宽度 = 4.3 × 1.778 ≈ 7.64
	# 当屏幕更窄（aspect < 16:9）时，需要增大 size 保证宽度不裁 → 高度多出部分为黑边
	# 当屏幕更宽（aspect > 16:9）时，size 保持基准 → 宽度多出部分为黑边
	var target_size = CAM_BASE_SIZE
	if current_aspect < CAM_DESIGN_ASPECT:
		# 屏幕更窄：以宽度为约束，反推 size = 设计宽度 / 当前aspect
		var design_width = CAM_BASE_SIZE * CAM_DESIGN_ASPECT
		target_size = design_width / current_aspect
	_cam.size = target_size


func _on_back() -> void:
	# 战斗中点返回 → 显示退出确认弹窗
	_on_battle_exit_btn()


func _update_turn_info() -> void:
	var who = "己方" if _is_player_turn else "敌方"
	_turn_info_label.text = "第%d回合 | %s | %s" % [_turn_count, who, _phase_name]


## 初始化战斗数据（参照老2D版BattleScene._init_battle）
func _init_battle_data() -> void:
	var deck_id = Global.current_deck_id
	if deck_id == "":
		deck_id = "starter_deck"
	
	_battle_manager = BattleManager.new()
	
	# 连接信号
	_battle_manager.phase_changed.connect(_on_phase_changed)
	_battle_manager.turn_changed.connect(_on_turn_changed)
	_battle_manager.battle_state_changed.connect(_on_battle_state_changed)
	_battle_manager.action_result.connect(_on_action_result)
	
	# 开始战斗
	_battle_manager.start_battle(deck_id, _enemy_name, false)  # auto_start=false，等RPS结束后再启动
	
	# 连接玩家信号
	if _battle_manager.player_self:
		_battle_manager.player_self.energy_changed.connect(_on_player_energy_changed)
		_battle_manager.player_self.hp_changed.connect(_on_player_hp_changed)
		_battle_manager.player_self.hand_changed.connect(_on_player_hand_changed)
		_battle_manager.player_self.card_sent_to_grave.connect(_on_card_sent_to_grave.bind(true))
		_battle_manager.player_self.banish_changed.connect(_on_banish_changed.bind(true))
		_battle_manager.player_self.card_banished.connect(_on_card_banished.bind(true))
		_battle_manager.player_self.revive_chance_triggered.connect(_on_revive_chance_triggered.bind(true))
		# ★ 教程：玩家召唤成功 → 推进 step 2→3
		_battle_manager.player_self.card_summoned.connect(func(_card, _slot):
			_advance_tutorial_step("summon"))
		_player_name = _battle_manager.player_self.player_name
		_player_hp = _battle_manager.player_self.hp
		_player_max_hp = _battle_manager.player_self.max_hp
		_player_energy = _battle_manager.player_self.energy
		_player_max_energy = _battle_manager.player_self.max_energy
	
	if _battle_manager.player_opponent:
		_battle_manager.player_opponent.energy_changed.connect(_on_enemy_energy_changed)
		_battle_manager.player_opponent.hp_changed.connect(_on_enemy_hp_changed)
		_battle_manager.player_opponent.hand_changed.connect(_on_enemy_hand_changed)
		_battle_manager.player_opponent.card_sent_to_grave.connect(_on_card_sent_to_grave.bind(false))
		# ★ 教程：敌方卡牌阵亡（玩家攻击命中）→ 推进 step 6→7
		_battle_manager.player_opponent.card_sent_to_grave.connect(func(_card):
			_advance_tutorial_step("attack"))
		_battle_manager.player_opponent.banish_changed.connect(_on_banish_changed.bind(false))
		_battle_manager.player_opponent.card_banished.connect(_on_card_banished.bind(false))
		_battle_manager.player_opponent.revive_chance_triggered.connect(_on_revive_chance_triggered.bind(false))
		_enemy_name = _battle_manager.player_opponent.player_name
		_enemy_hp = _battle_manager.player_opponent.hp
		_enemy_max_hp = _battle_manager.player_opponent.max_hp
		_enemy_energy = _battle_manager.player_opponent.energy
		_enemy_max_energy = _battle_manager.player_opponent.max_energy
	
	# 添加阶段切换按钮到UI
	_add_phase_button()
	
	# 连接效果发动信号 → 飘窗面板
	if _battle_manager.has_signal("card_effect_activated"):
		_battle_manager.card_effect_activated.connect(_on_card_effect_activated)
	# 连接效果触发信号 → 飘字+闪烁
	if _battle_manager.has_signal("effect_triggered"):
		_battle_manager.effect_triggered.connect(_on_effect_triggered)
	# 连接元素加成/克制信号 → 飘字
	if _battle_manager.has_signal("element_boost_triggered"):
		_battle_manager.element_boost_triggered.connect(_on_element_boost_triggered)
	# 连接逐卡画线信号 → 群体效果逐张目标画线
	if _battle_manager.has_signal("effect_line_fromto"):
		_battle_manager.effect_line_fromto.connect(_on_effect_line_fromto)
		_battle_manager.discard_requested.connect(_on_discard_requested)
		_battle_manager.discard_animation_requested.connect(_on_discard_animation_requested)
	# 连接回合结束效果发完信号 → 等非飘窗动画播完再推进弃牌（避免视角/画线动画与弃牌交错）
	if _battle_manager.has_signal("end_phase_effects_pending_discard"):
		_battle_manager.end_phase_effects_pending_discard.connect(_on_end_phase_effects_pending_discard)
	
	print("[BattleScene3D] 战斗初始化完成: %s vs %s" % [_player_name, _enemy_name])


## 添加阶段切换按钮
func _add_phase_button() -> void:
	var ui = get_node_or_null("UI")
	if not ui:
		return
	var btn = Button.new()
	btn.name = "PhaseBtn"
	btn.text = "进入战斗阶段"
	btn.add_theme_font_size_override("font_size", 48)
	btn.add_theme_color_override("font_color", Color(0.9, 0.8, 0.3, 1))
	# 右下角：尺寸要收着放，否则会压住最右侧的手牌
	btn.anchor_left = 1.0
	btn.anchor_top = 1.0
	btn.anchor_right = 1.0
	btn.anchor_bottom = 1.0
	btn.offset_left = -400.0
	btn.offset_top = -630.0
	btn.offset_right = -20.0
	btn.offset_bottom = -500.0
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.1, 0.18, 1)
	sb.border_width_left = 3
	sb.border_width_right = 3
	sb.border_width_top = 3
	sb.border_width_bottom = 3
	sb.border_color = Color(0.4, 0.3, 0.5, 0.8)
	sb.corner_radius_top_left = 12
	sb.corner_radius_top_right = 12
	sb.corner_radius_bottom_left = 12
	sb.corner_radius_bottom_right = 12
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("pressed", sb)
	btn.add_theme_stylebox_override("hover", sb)
	btn.add_theme_stylebox_override("focus", sb)
	btn.pressed.connect(_on_phase_btn_pressed)
	ui.add_child(btn)


## 更新所有信息栏Label3D
func _update_all_info_labels() -> void:
	if _enemy_name_lbl:
		_enemy_name_lbl.text = _enemy_name
	if _enemy_hp_lbl:
		_enemy_hp_lbl.text = "" + str(_enemy_hp) + "/" + str(_enemy_max_hp)
	if _enemy_energy_lbl:
		_enemy_energy_lbl.text = _format_energy_display(_enemy_energy, _enemy_max_energy)
	if _player_name_lbl:
		_player_name_lbl.text = _player_name
	if _player_hp_lbl:
		_player_hp_lbl.text = "" + str(_player_hp) + "/" + str(_player_max_hp)
	if _player_energy_lbl:
		_player_energy_lbl.text = _format_energy_display(_player_energy, _player_max_energy)
	# ★ 卡组剩余张数（从 BM 拿实际数据，兜底用场景缓存）
	if _player_deck_lbl:
		var p_cnt = _player_deck_count
		if _battle_manager and _battle_manager.player_self and _battle_manager.player_self.deck:
			var pd = _battle_manager.player_self.deck
			if pd.has_method("size"):
				p_cnt = pd.size()
			elif pd.has_method("get_card_count"):
				p_cnt = pd.get_card_count()
		_player_deck_lbl.text = "%d张" % p_cnt
	if _enemy_deck_lbl:
		var e_cnt = _enemy_deck_count
		if _battle_manager and _battle_manager.player_opponent and _battle_manager.player_opponent.deck:
			var ed = _battle_manager.player_opponent.deck
			if ed.has_method("size"):
				e_cnt = ed.size()
			elif ed.has_method("get_card_count"):
				e_cnt = ed.get_card_count()
		_enemy_deck_lbl.text = "%d张" % e_cnt


## 能量显示：用⚡符号 + 数值，如 ⚡⚡⚡⚡（4/5）
func _format_energy_display(current: int, maximum: int) -> String:
	var filled = "".repeat(max(0, current))
	var empty = "·".repeat(max(0, maximum - current))
	return filled + empty + "（" + str(current) + "/" + str(maximum) + "）"


## 玩家能量变化信号
func _on_player_energy_changed(_old_val: int, _new_val: int) -> void:
	if _battle_manager and _battle_manager.player_self:
		_player_energy = _battle_manager.player_self.energy
		_player_max_energy = _battle_manager.player_self.max_energy  # ★ 同步上限（回合+1）
		if _player_energy_lbl:
			_player_energy_lbl.text = _format_energy_display(_player_energy, _player_max_energy)


## 玩家血量变化信号
func _on_player_hp_changed(_old_hp: int, _new_hp: int) -> void:
	if _battle_manager and _battle_manager.player_self:
		_player_hp = _battle_manager.player_self.hp
		if _player_hp_lbl:
			_player_hp_lbl.text = "" + str(_player_hp) + "/" + str(_player_max_hp)
	# 受伤时切到己方视角，1秒后切回
	if _new_hp < _old_hp:
		_switch_camera(2)
		await get_tree().create_timer(1.0).timeout
		_restore_camera_after_damage()


## 敌方能量变化信号
func _on_enemy_energy_changed(_old_val: int, _new_val: int) -> void:
	if _battle_manager and _battle_manager.player_opponent:
		_enemy_energy = _battle_manager.player_opponent.energy
		_enemy_max_energy = _battle_manager.player_opponent.max_energy  # ★ 同步上限（回合+1）
		if _enemy_energy_lbl:
			_enemy_energy_lbl.text = _format_energy_display(_enemy_energy, _enemy_max_energy)


## 敌方血量变化信号
func _on_enemy_hp_changed(_old_hp: int, _new_hp: int) -> void:
	if _battle_manager and _battle_manager.player_opponent:
		_enemy_hp = _battle_manager.player_opponent.hp
		if _enemy_hp_lbl:
			_enemy_hp_lbl.text = "" + str(_enemy_hp) + "/" + str(_enemy_max_hp)
	# ★ 教程：敌方英雄受伤 → 推进 step 6→7
	if _new_hp < _old_hp:
		_advance_tutorial_step("attack")
	# 受伤时切到敌方视角，1秒后切回
	if _new_hp < _old_hp:
		_switch_camera(0)
		await get_tree().create_timer(1.0).timeout
		_restore_camera_after_damage()


## 受伤后恢复视角（根据当前回合方决定）
func _restore_camera_after_damage() -> void:
	if _battle_manager:
		var target_cam = 2 if _battle_manager.is_player_turn() else 0
		if _battle_manager.current_phase == BattleManager.Phase.BATTLE:
			target_cam = 1
		_switch_camera(target_cam)


## 阶段变化信号
func _on_phase_changed(_phase: int, _player_index: int) -> void:
	if _battle_manager:
		_phase_name = _battle_manager.get_phase_name()
		_is_player_turn = _battle_manager.is_player_turn()
		# 自动切换视角
		var target_cam = 2 if _is_player_turn else 0  # 默认：我方→2, 敌方→0
		if _battle_manager.current_phase == BattleManager.Phase.BATTLE:
			target_cam = 1  # 战斗阶段→中间
			# 战斗阶段：高亮可攻击/不可攻击边框
			_highlight_attack_slots()
		else:
			# 非战斗阶段：清除边框高亮
			_clear_slot_border_highlights()
		_switch_camera(target_cam)
	_update_turn_info()
	_update_phase_button()
	# 刷新敌方场地显示
	_refresh_enemy_field_display()


## 自动切换摄像头视角（带动画）
func _switch_camera(target_state: int) -> void:
	if _cam_state == target_state:
		return
	_cam_state = target_state
	if _cam:
		if _cam_tween and _cam_tween.is_valid():
			_cam_tween.kill()
		_cam_tween = create_tween()
		_cam_tween.tween_property(_cam, "position:z", CAM_POS_Z[_cam_state], 0.2).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	var labels = ["敌方", "中", "己方"]
	if _view_btn:
		_view_btn.text = "视角: " + labels[_cam_state]


# ===== 效果发动飘窗系统 =====
# 飘窗列表：多条同时存在，自动堆叠，新条目从上方插入推旧条目到底部
var _effect_panels: Array = []  # [{panel, tween}]
const PANEL_STAY_TIME: float = 2.5  # 停留时间
const PANEL_MAX_COUNT: int = 5  # 最多同时显示5条

## 效果发动信号回调：飘窗显示（不切视角，避免和攻击动画冲突）
func _on_card_effect_activated(card_name: String, effect_desc: String, action_type: String, target_id: String, value: int, target_card_name: String, source_slot: int, is_player_side: bool, target_slot: int, target_is_player: bool, full_effect: Dictionary = {}) -> void:
	var side = "我方" if is_player_side else "敌方"
	var target_side = "我方" if target_is_player else "敌方"
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
		_: target_text = target_id
	print("[BattleScene3D] 效果发动: %s【%s】%s → %s" % [side, card_name, effect_desc, target_text])
	# 效果发动音效
	Global.play_sfx("effect_cast")
	# 源卡牌边框闪烁
	_flash_slot_border(source_slot, is_player_side, 1.2)
	# 生成完整纹路描述（触发器+条件+动作+目标+约束）
	var full_desc = effect_desc
	if full_effect is Dictionary and not full_effect.is_empty():
		var parsed = Global.parse_circuit(full_effect)
		if parsed.is_valid:
			full_desc = Global.format_effect_description(parsed)
	# 获取源和目标的3D位置
	var source_pos = _get_effect_node_pos(source_slot, is_player_side)
	var target_pos = _get_effect_target_pos(target_slot, target_is_player, target_id)
	# 画3D抛物线连线 + 闪烁
	if source_pos and target_pos:
		_play_effect_line_and_flash(source_pos, target_pos, action_type)
	# 显示飘窗（切中间视角，堆叠式）
	_prev_cam_state = _cam_state
	_switch_camera(1)
	_show_effect_panel(card_name, full_desc, target_text, target_card_name, side, target_side, value, true, action_type)

## 攻击飘窗（供攻击动画调用，不切视角）
func show_attack_popup(attacker_name: String, target_name: String, damage: int, is_player_side: bool) -> void:
	var side = "我方" if is_player_side else "敌方"
	var target_side = "敌方" if is_player_side else "我方"
	var target_text = target_name if target_name != "" else "英雄"
	_show_effect_panel(attacker_name, " 攻击", "目标", target_text, side, target_side, damage, false, "ATTACK")


## 获取效果发动源的3D位置
func _get_effect_node_pos(slot: int, is_player: bool) -> Vector3:
	var slots = _player_slots if is_player else _enemy_slots
	if slot >= 0 and slot < slots.size() and slots[slot]:
		return slots[slot].global_position + Vector3(0, 0.15, 0)
	# fallback：英雄区
	var hero_node = get_node_or_null("PlayerField/InfoArea") if is_player else get_node_or_null("EnemyField/InfoArea")
	if hero_node:
		return hero_node.global_position + Vector3(0, 0.15, 0)
	return Vector3(0, 0.15, 0)


## 获取效果目标的3D位置
func _get_effect_target_pos(slot: int, is_player: bool, target_id: String) -> Vector3:
	if slot >= 0:
		var slots = _player_slots if is_player else _enemy_slots
		if slot < slots.size() and slots[slot]:
			return slots[slot].global_position + Vector3(0, 0.15, 0)
	# 英雄目标
	var hero_node = get_node_or_null("PlayerField/InfoArea") if is_player else get_node_or_null("EnemyField/InfoArea")
	if hero_node:
		return hero_node.global_position + Vector3(0, 0.15, 0)
	return Vector3(0, 0.15, 0)


## 画3D效果连线 + 源/目标闪烁（参考拖拽连线的画法）
func _play_effect_line_and_flash(from_pos: Vector3, to_pos: Vector3, action_type: String) -> void:
	# 连线颜色
	var line_color = Color(1.0, 0.85, 0.2, 0.8)  # 金色
	if action_type == "damage" or action_type == "attack":
		line_color = Color(1.0, 0.3, 0.3, 0.8)  # 红色
	elif action_type == "heal":
		line_color = Color(0.3, 1.0, 0.3, 0.8)  # 绿色
	# 创建连线
	var line_node = MeshInstance3D.new()
	var line_mesh = ImmediateMesh.new()
	line_node.mesh = line_mesh
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = line_color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	line_node.material_override = mat
	add_child(line_node)
	# 抛物线（中间抬高）
	var mid = (from_pos + to_pos) * 0.5
	mid.y += 1.0
	# 用动画驱动连线淡入淡出，同时每帧重绘连线
	var flash_node = MeshInstance3D.new()
	var flash_quad = QuadMesh.new()
	flash_quad.size = Vector2(0.6, 0.8)
	flash_node.mesh = flash_quad
	var flash_mat = StandardMaterial3D.new()
	flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_mat.albedo_color = line_color
	flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash_mat.no_depth_test = true
	flash_node.material_override = flash_mat
	add_child(flash_node)
	flash_node.global_position = to_pos
	if not from_pos.is_equal_approx(to_pos):
		flash_node.look_at(from_pos)
	# 画连线
	var _draw_line = func():
		line_mesh.clear_surfaces()
		line_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		var segments = 20
		for i in range(segments + 1):
			var f = float(i) / float(segments)
			var p = from_pos.lerp(mid, f).lerp(mid.lerp(to_pos, f), f)
			line_mesh.surface_add_vertex(p)
		line_mesh.surface_end()
	_draw_line.call()
	# 动画：连线停留 → 闪烁 → 淡出 → 删除
	var tween = create_tween().set_parallel(false)
	# 连线+闪烁停留0.8s
	tween.tween_interval(0.8)
	# 闪烁淡出0.4s
	tween.tween_property(flash_mat, "albedo_color:a", 0.0, 0.4)
	tween.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.4)
	# 删除节点
	tween.tween_callback(func():
		if is_instance_valid(line_node):
			line_node.queue_free()
		if is_instance_valid(flash_node):
			flash_node.queue_free()
	)


## 显示效果飘窗面板（左侧1/4，堆叠式，新条目推旧条目到底部）
func _show_effect_panel(card_name: String, effect_desc: String, target_text: String, target_card_name: String, side: String, target_side: String, value: int, switch_camera: bool = true, action_id: String = "") -> void:
	var ui = get_node_or_null("UI")
	if not ui:
		return
	# 超出上限：移除最旧的
	if _effect_panels.size() >= PANEL_MAX_COUNT:
		var oldest = _effect_panels.pop_front()
		if oldest and is_instance_valid(oldest.panel):
			if oldest.tween and oldest.tween.is_valid():
				oldest.tween.kill()
			oldest.panel.queue_free()
	# 面板尺寸和位置（固定大小，确保能装下内容）
	var screen_size = DisplayServer.screen_get_size()
	var panel_w = screen_size.x * 0.55
	var panel_h = 800.0  # 固定高度，足够装下4行文字
	var panel_margin = 16.0
	var panel_top = screen_size.y * 0.08
	# 创建面板容器（圆角背景框）
	var panel = Panel.new()
	panel.name = "EffectPanel_" + str(Time.get_ticks_msec())
	panel.position = Vector2(16, panel_top)
	panel.size = Vector2(panel_w, panel_h)
	panel.z_index = 300
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 圆角背景样式（深色底+紫色描边）
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.06, 0.14, 0.92)
	style.border_color = Color(0.5, 0.4, 0.8, 0.9)
	style.set_border_width_all(3)
	style.set_corner_radius_all(16)
	style.content_margin_left = 36.0
	style.content_margin_right = 36.0
	style.content_margin_top = 28.0
	style.content_margin_bottom = 28.0
	panel.add_theme_stylebox_override("panel", style)
	ui.add_child(panel)
	# 内容容器（VBox自动排版防重叠）
	var vbox = VBoxContainer.new()
	vbox.position = Vector2(36, 28)
	vbox.size = Vector2(panel_w - 72, panel_h - 56)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	panel.add_child(vbox)
	# 第一行：归属方 + 卡牌名 + 数值（金色，大）
	var lbl1 = Label.new()
	var title_text = "【" + side + "】" + card_name
	if value != 0:
		var prefix = "+" if (effect_desc.contains("治疗") or effect_desc.contains("回复")) else "-"
		title_text += "  " + prefix + str(value)
	lbl1.text = title_text
	lbl1.add_theme_font_size_override("font_size", 92)  # 115 × 0.8 = 92
	lbl1.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	lbl1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl1.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl1.custom_minimum_size = Vector2(0, 115)  # 144 × 0.8 ≈ 115
	lbl1.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
	lbl1.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vbox.add_child(lbl1)
	# 第二行：效果类型标签（大）
	var lbl2 = Label.new()
	var effect_type = ""
	match action_id:
		"ATTACK": effect_type = " 攻击"
		"A01": effect_type = " 伤害"
		"A02": effect_type = " 治疗"
		"A03": effect_type = " 破坏"
		"A04": effect_type = " 破坏"
		"A05": effect_type = " 除外"
		"A06": effect_type = "↩ 弹回手牌"
		"A07": effect_type = "↩ 弹回卡组"
		"A08": effect_type = " 送墓"
		"A09": effect_type = " 抽牌"
		"A10": effect_type = " 检索字段"
		"A11": effect_type = " 检索卡"
		"A12": effect_type = " 墓地回收"
		"A13": effect_type = " 除外回收"
		"A14": effect_type = " 卡组堆墓"
		"A15": effect_type = " 手牌特召"
		"A16": effect_type = " 墓地特召"
		"A17": effect_type = " 卡组特召"
		"A18": effect_type = " 除外特召"
		"A20": effect_type = "⬆ 攻击增益"
		"A21": effect_type = "⬆ 生命增益"
		"A22": effect_type = "⬆ 攻防增益"
		"A23": effect_type = "⬆ 回合增益"
		"A24": effect_type = "⬆ 全场增益"
		"A25": effect_type = " 交换攻防"
		"A26": effect_type = " 暂时控制"
		"A27": effect_type = " 永久控制"
		"A28": effect_type = "⬇ 减益"
		"A31": effect_type = " 控制变更"
		"A32": effect_type = " 控制变更"
		"A33": effect_type = " 禁用效果"
		_: effect_type = " 效果"
	lbl2.text = effect_type
	lbl2.add_theme_font_size_override("font_size", 116)  # 77 × 1.5 = 115.5 ≈ 116
	lbl2.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))
	lbl2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl2.custom_minimum_size = Vector2(0, 120)  # 80 × 1.5 = 120
	lbl2.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
	lbl2.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vbox.add_child(lbl2)
	# 第三行：完整纹路描述（白色，中）
	var lbl3 = Label.new()
	lbl3.text = effect_desc
	lbl3.add_theme_font_size_override("font_size", 87)  # 58 × 1.5 = 87
	lbl3.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	lbl3.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl3.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl3.custom_minimum_size = Vector2(0, 192)  # 128 × 1.5 = 192
	lbl3.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
	lbl3.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vbox.add_child(lbl3)
	# 第四行：目标信息（淡金色，小）
	if target_text != "" or target_card_name != "":
		var lbl4 = Label.new()
		var target_str = ""
		if target_card_name != "" and target_card_name != card_name:
			target_str = " " + target_side + "【" + target_card_name + "】"
		else:
			target_str = " " + target_text
			if target_side != side:
				target_str += "（" + target_side + "）"
		lbl4.text = target_str
		lbl4.add_theme_font_size_override("font_size", 72)  # 48 × 1.5 = 72
		lbl4.add_theme_color_override("font_color", Color(0.9, 0.8, 0.6))
		lbl4.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl4.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl4.custom_minimum_size = Vector2(0, 84)  # 56 × 1.5 = 84
		lbl4.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
		lbl4.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		vbox.add_child(lbl4)
	
	# 加入列表（最新的在最下面）
	_effect_panels.append({"panel": panel, "tween": null})
	# 淡入动画
	panel.modulate = Color(1.0, 1.0, 1.0, 0.0)
	var fade_tween = create_tween()
	fade_tween.tween_property(panel, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.15)
	# 重排所有面板位置（自动滚到底部）
	_restack_effect_panels()
	# 停留 → 淡出 → 移除
	var panel_ref = weakref(panel)
	var stay_tween = create_tween().set_parallel(false)
	stay_tween.tween_interval(PANEL_STAY_TIME)
	stay_tween.tween_property(panel, "modulate", Color(1.0, 1.0, 1.0, 0.0), 0.3)
	stay_tween.tween_callback(func():
		_remove_effect_panel(panel)
		# 效果飘窗：所有飘窗消失后切回原视角（但攻击动画中不切，避免干扰）
		if switch_camera and _effect_panels.is_empty():
			var drag_ctrl = get_node_or_null("CardDragController")
			var enemy_ai = get_node_or_null("EnemyAIController")
			var is_attacking = (drag_ctrl and drag_ctrl._is_attack_animating) or (enemy_ai and enemy_ai._is_animating)
			if not is_attacking:
				_switch_camera(_prev_cam_state)
	)
	# 保存tween引用
	for entry in _effect_panels:
		if entry.panel == panel:
			entry.tween = stay_tween
			break

## 重排所有飘窗位置（最新的在底部，依次往上堆，自动滚到底部）
func _restack_effect_panels() -> void:
	var screen_size = DisplayServer.screen_get_size()
	var panel_h = 800.0
	var panel_margin = 16.0
	var panel_bottom_margin = 100.0  # 距离屏幕底部的边距
	var panel_w = screen_size.x * 0.55
	
	# 计算所有面板的总高度
	var total_height = _effect_panels.size() * (panel_h + panel_margin) - panel_margin
	
	# 计算起始位置（让最新的面板显示在屏幕底部）
	var start_y = screen_size.y - panel_bottom_margin - total_height
	if start_y < screen_size.y * 0.08:  # 不要超出顶部
		start_y = screen_size.y * 0.08
	
	# 从底部往上排列（最新的在最下面）
	var current_y = start_y
	for i in range(_effect_panels.size()):
		var entry = _effect_panels[i]
		if not entry or not is_instance_valid(entry.panel):
			continue
		var p = entry.panel
		# 平滑移动到新位置
		var move_tween = create_tween()
		move_tween.tween_property(p, "position:y", current_y, 0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		current_y += panel_h + panel_margin

## 移除指定飘窗
func _remove_effect_panel(panel: Control) -> void:
	for i in range(_effect_panels.size() - 1, -1, -1):
		if _effect_panels[i].panel == panel:
			_effect_panels.remove_at(i)
			break
	if is_instance_valid(panel):
		panel.queue_free()
	# 重排剩余面板
	_restack_effect_panels()


## ===== 边框效果系统 =====

## 获取场地槽位的Border节点
func _get_slot_border(slot_idx: int, is_player: bool) -> MeshInstance3D:
	var slots = _player_slots if is_player else _enemy_slots
	if slot_idx >= 0 and slot_idx < slots.size() and slots[slot_idx]:
		var border = slots[slot_idx].get_node_or_null("Border") as MeshInstance3D
		if border:
			return border
	return null


## 源卡牌边框闪烁（效果发动时）
func _flash_slot_border(slot_idx: int, is_player: bool, duration: float = 1.2) -> void:
	var border = _get_slot_border(slot_idx, is_player)
	if not border:
		return
	# 创建临时金色闪烁材质
	var flash_mat = StandardMaterial3D.new()
	flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_mat.albedo_color = Color(1.0, 0.85, 0.2, 0.9)
	flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash_mat.no_depth_test = false
	border.material_override = flash_mat
	# tween闪烁3次（透明度0.9→0.3→0.9→0.3→0.9）
	var tween = create_tween().set_parallel(false)
	var blink_count = 3
	for i in range(blink_count):
		tween.tween_property(flash_mat, "albedo_color:a", 0.3, duration / float(blink_count * 2))
		tween.tween_property(flash_mat, "albedo_color:a", 0.9, duration / float(blink_count * 2))
	# 完成后恢复默认材质（null = 用场景原始材质）
	tween.tween_callback(func():
		if is_instance_valid(border):
			border.material_override = null
	)


## 战斗阶段：高亮可攻击/不可攻击的卡牌边框
## Border比卡牌略大(1.06×1.46 vs 1.0×1.4)，只给Border上色=发光描边效果
func _highlight_attack_slots() -> void:
	if not _battle_manager:
		return
	var player = _battle_manager.player_self
	if not player:
		return
	for i in range(min(5, _player_slots.size())):
		var border = _get_slot_border(i, true)
		if not border:
			continue
		var card = null
		if i < player.field.size():
			card = player.field[i]
		if card and card.is_alive():
			if card.can_attack():
				# 可攻击 → 绿色发光描边
				border.material_override = _mat_attack_green
			else:
				# 不可攻击 → 灰色描边
				border.material_override = _mat_attack_gray
		else:
			# 无卡牌 → 恢复默认
			border.material_override = null


## 退出战斗阶段：清除所有边框高亮
func _clear_slot_border_highlights() -> void:
	for i in range(_player_slots.size()):
		var border = _get_slot_border(i, true)
		if border and border.material_override != null:
			border.material_override = null
	for i in range(_enemy_slots.size()):
		var border = _get_slot_border(i, false)
		if border and border.material_override != null:
			border.material_override = null


# ===== 效果飘字 & 元素克制 & 逐卡画线 =====

## 效果触发信号：源卡牌位置飘字 + 闪烁
func _on_effect_triggered(action_type: String, value: int, is_player_side: bool, source_slot: int, desc: String) -> void:
	# 根据效果类型播放对应音效
	match action_type:
		"A01": Global.play_sfx("damage")
		"A02": Global.play_sfx("heal")
		"A03": Global.play_sfx("destroy")
	# 源卡牌边框闪烁（短闪）
	if source_slot >= 0:
		_flash_slot_border(source_slot, is_player_side, 0.6)
	# 3D飘字（在源卡牌上方）
	var slots = _player_slots if is_player_side else _enemy_slots
	if source_slot >= 0 and source_slot < slots.size() and slots[source_slot]:
		var pos = slots[source_slot].global_position + Vector3(0, 0.8, 0)
		_show_3d_float_text(pos, desc, value, action_type)
	# 刷新双方场地（数值变化）
	_refresh_player_field_display()
	_refresh_enemy_field_display()


## 元素加成/克制飘字
func _on_element_boost_triggered(boost_type: String, atk_elem: String, def_elem: String, from_value: int, to_value: int, is_player_side: bool, source_slot: int) -> void:
	var slots = _player_slots if is_player_side else _enemy_slots
	if source_slot >= 0 and source_slot < slots.size() and slots[source_slot]:
		var pos = slots[source_slot].global_position + Vector3(0, 1.0, 0)
		var text = ""
		if boost_type == "affinity":
			text = "%s克制%s" % [atk_elem, def_elem]
		else:
			text = "%s加成" % atk_elem
		text += " %d→%d" % [from_value, to_value]
		_show_3d_float_text(pos, text, 0, "element")


## 逐卡画线（群体效果每张目标发一次）
func _on_effect_line_fromto(from_slot: int, from_is_player: bool, to_slot: int, to_is_player: bool, action_type: String) -> void:
	if from_slot < 0 or to_slot < 0:
		return
	var from_slots = _player_slots if from_is_player else _enemy_slots
	var to_slots = _player_slots if to_is_player else _enemy_slots
	if from_slot >= from_slots.size() or to_slot >= to_slots.size():
		return
	if not from_slots[from_slot] or not to_slots[to_slot]:
		return
	var from_pos = from_slots[from_slot].global_position + Vector3(0, 0.15, 0)
	var to_pos = to_slots[to_slot].global_position + Vector3(0, 0.15, 0)
	_play_effect_line_and_flash(from_pos, to_pos, action_type)


## 3D飘字（Label3D，自动消失）
func _show_3d_float_text(pos: Vector3, text: String, value: int, action_type: String) -> void:
	var label = Label3D.new()
	label.text = text
	label.font_size = 48
	label.position = pos
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	# 颜色
	var color = Color(1.0, 0.85, 0.2)  # 金色默认
	if action_type == "A01" or action_type == "damage":
		color = Color(1.0, 0.3, 0.3)  # 红色
	elif action_type == "A02" or action_type == "heal":
		color = Color(0.3, 1.0, 0.3)  # 绿色
	elif action_type == "element":
		color = Color(0.4, 0.8, 1.0)  # 蓝色
	label.modulate = color
	add_child(label)
	# 飘字动画：上飘 + 淡出
	var tween = create_tween()
	tween.tween_property(label, "position:y", pos.y + 0.8, 1.0).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 1.0).set_ease(Tween.EASE_IN)
	tween.tween_callback(func():
		if is_instance_valid(label):
			label.queue_free()
	)


## 复活概率检定（骰子音效+飘窗）
func _on_revive_chance_triggered(chance: float, success: bool, slot: int, is_player: bool) -> void:
	# 播放骰子音效
	Global.play_sfx("dice")
	# 飘窗显示
	var slots = _player_slots if is_player else _enemy_slots
	if slot >= 0 and slot < slots.size() and slots[slot]:
		var pos = slots[slot].global_position + Vector3(0, 1.0, 0)
		var text = "骰子检定 " + str(int(chance * 100)) + "% "
		if success:
			text += " 复活成功！"
			_show_3d_float_text(pos, text, 0, "heal")
		else:
			text += " 复活失败"
			_show_3d_float_text(pos, text, 0, "damage")
		print("[复活] 飙窗: chance=", chance, " success=", success, " slot=", slot, " is_player=", is_player)
	else:
		print("[复活] slot无效: chance=", chance, " success=", success)

## 回合变化信号
func _on_turn_changed(turn_count: int) -> void:
	_turn_count = turn_count
	_update_turn_info()


## 战斗状态变化信号
func _on_battle_state_changed(state: int) -> void:
	var state_names = {0: "进行中", 1: "胜利！", 2: "败北...", 3: "平局"}
	var sname = state_names.get(state, "未知")
	if _turn_info_label:
		_turn_info_label.text = "" + sname
	print("[BattleScene3D]  战斗状态: ", sname)
	
	# 胜利时：触发辅材掉落
	if state == 1:
		var boss_extra: Array = []      # BOSS 首通金币等额外展示条目（已提前入账）
		# 教学战胜利 → 推进教程，回主界面找老陈
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
		var was_boss = Global.current_is_boss
		if was_boss and Global.current_map_id != "":
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
				# 检查纹路解锁状态
				var new_unlocks = CircuitManager.check_and_apply_unlocks()
				if new_unlocks.size() > 0:
					print("[战斗] 解锁了 ", new_unlocks.size(), " 个纹路组件")
		else:
			# ★ 普通战斗胜利 → 回地图内继续探索
			_exit_to_main = false
		_handle_victory_rewards(boss_extra)
		
		# ★ 决斗场胜利 → 记录每日阶梯任务
		if Global.current_map_name == " 决斗场":
			var result = PlayerManager.record_duel_win()
			if result.get("completed", false):
				print("[战斗]  每日决斗场阶梯完成！金币+" + str(result.get("reward", 0)))
		else:
			# ★ 非决斗场胜利 → 记录杀敌阶梯
			var kill_result = PlayerManager.record_kill()
			if kill_result.get("completed", false):
				print("[战斗]  每日杀敌阶梯完成！金币+" + str(kill_result.get("reward", 0)))
			# ★ BOSS战胜利 → 额外记录通关地图阶梯
			if was_boss:
				var map_result = PlayerManager.record_map_clear()
				if map_result.get("completed", false):
					print("[战斗]  每日通关地图阶梯完成！金币+" + str(map_result.get("reward", 0)))
	# 败北/平局时：显示退出按钮，回主界面
	elif state == 2 or state == 3:
		_exit_to_main = true
		# 裂隙局（GDD §7.3.3）：全灭 → 素材折损 50% 携出（不清零），本局结束
		if Global.rift_active:
			var r = Global.rift_settle_wipe()
			print("[裂隙] 全灭结算：折损携带 %d 件，损失 %d 件" % [r["kept"], r["lost"]])
		_show_battle_exit_btn(state)


## BM action_result信号：捕获战斗动作结果
func _on_action_result(_action_type: String, _success: bool, _data: Dictionary) -> void:
	# 敌方召唤/攻击由EnemyAIController直接检测BM内部状态驱动
	# 此处仅用于扩展：如需要根据动作结果做额外UI反馈
	pass


## 刷新敌方场地显示（由EnemyAIController调用）
func _refresh_enemy_field_display() -> void:
	if not _battle_manager or not _battle_manager.player_opponent:
		return
	var enemy = _battle_manager.player_opponent
	for i in range(5):
		if i >= _enemy_slots.size():
			break
		var slot_node = _enemy_slots[i]
		if not slot_node:
			continue
		var card = enemy.field[i] if i < enemy.field.size() else null
		if card:
			# 有卡牌 → 显示卡牌信息
			_show_enemy_card_on_slot(i, card)
		else:
			# 无卡牌 → 清除显示
			_clear_enemy_card_on_slot(i)


## 在敌方卡位上显示卡牌
func _show_enemy_card_on_slot(slot_idx: int, card) -> void:
	var slot_node = _enemy_slots[slot_idx]
	if not slot_node:
		return
	var card_data = {
		"name": card.card_name,
		"atk": card.current_atk,
		"hp": card.current_hp,
		"cost": card.base_cost,
		"element": card.get_effective_element(),
		"poison_count": card.poison_count if "poison_count" in card else 0,
		"shield_points": card.shield_points if "shield_points" in card else 0,
	}
	# 优先用引用表
	var existing = _enemy_card_nodes[slot_idx] if slot_idx < _enemy_card_nodes.size() else null
	if existing and is_instance_valid(existing):
		# 已有节点 → 更新数据
		if existing.has_method("update_data"):
			existing.update_data(card_data)
		return
	# 创建新的卡牌节点
	var card_node = CARD_SCENE.instantiate() as Node3D
	if not card_node:
		return
	slot_node.add_child(card_node)
	card_node.name = "EnemyCard"
	card_node.position = Vector3(0, 0.15, 0)
	if card_node.has_method("setup"):
		card_node.setup(card_data, _card_front_mat, _card_back_mat)
	if card_node.has_method("set_face_up"):
		card_node.set_face_up()
	# 写入引用表
	_enemy_card_nodes[slot_idx] = card_node


## 清除敌方卡位上的卡牌显示
func _clear_enemy_card_on_slot(slot_idx: int) -> void:
	# 优先用引用表
	var existing = _enemy_card_nodes[slot_idx] if slot_idx < _enemy_card_nodes.size() else null
	if existing and is_instance_valid(existing):
		if existing.get_parent() == _enemy_slots[slot_idx]:
			existing.queue_free()
		_enemy_card_nodes[slot_idx] = null
		return
	# fallback
	var slot_node = _enemy_slots[slot_idx]
	if not slot_node:
		return
	var node = slot_node.get_node_or_null("EnemyCard")
	if node:
		if node.get_parent() == slot_node:
			node.queue_free()


## 刷新己方场地显示（敌方攻击后可能有卡牌被送墓）
func _refresh_player_field_display() -> void:
	if not _battle_manager or not _battle_manager.player_self:
		return
	var player = _battle_manager.player_self
	for i in range(min(5, _player_slots.size())):
		var slot_node = _player_slots[i]
		if not slot_node:
			continue
		var card = player.field[i] if i < player.field.size() else null
		if card:
			# 有卡牌 → 检查引用表
			var existing = _player_card_nodes[i] if i < _player_card_nodes.size() else null
			if not existing or not is_instance_valid(existing):
				# 引用表空但场上可能有遗留节点（兼容旧路径）
				existing = slot_node.get_node_or_null("PlayerCard")
			if not existing or not is_instance_valid(existing):
				# 没有就创建
				var card_node = CARD_SCENE.instantiate() as Node3D
				if not card_node:
					continue
				slot_node.add_child(card_node)
				card_node.name = "PlayerCard"
				card_node.position = Vector3(0, 0.15, 0)
				var card_data = {
					"name": card.card_name,
					"atk": card.current_atk,
					"hp": card.current_hp,
					"cost": card.base_cost,
					"element": card.get_effective_element(),
		"poison_count": card.poison_count if "poison_count" in card else 0,
		"shield_points": card.shield_points if "shield_points" in card else 0,
				}
				if card_node.has_method("setup"):
					card_node.setup(card_data, _card_front_mat, _card_back_mat)
				if card_node.has_method("set_face_up"):
					card_node.set_face_up()
				# 写入引用表
				_player_card_nodes[i] = card_node
			else:
				# 已有节点 → 更新数据
				if existing.has_method("update_data"):
					var card_data = {
						"name": card.card_name,
						"atk": card.current_atk,
						"hp": card.current_hp,
						"cost": card.base_cost,
						"element": card.get_effective_element(),
		"poison_count": card.poison_count if "poison_count" in card else 0,
		"shield_points": card.shield_points if "shield_points" in card else 0,
					}
					existing.update_data(card_data)
		else:
			# 无卡牌 → 清除显示
			var existing = _player_card_nodes[i] if i < _player_card_nodes.size() else null
			if existing and is_instance_valid(existing):
				if existing.get_parent() == slot_node:
					existing.queue_free()
				_player_card_nodes[i] = null
			else:
				# fallback
				var node = slot_node.get_node_or_null("PlayerCard")
				if node and node.get_parent() == slot_node:
					node.queue_free()


## 卡牌送入墓地的视觉反馈
func _on_card_sent_to_grave(card, is_player: bool) -> void:
	if card == null:
		return
	var card_name = card.card_name
	print("[BattleScene3D] 送墓动画: %s (%s)" % [card_name, "己方" if is_player else "敌方"])
	# 送墓音效
	Global.play_sfx("card_death")
	var grave_node = _player_grave_node if is_player else _enemy_grave_node
	if not grave_node:
		return
	# 用 card.slot_index 从引用表直接定位卡牌节点
	var card_slot: int = card.slot_index if "slot_index" in card else -1
	var card_node: Node3D = null
	var found_slot = card_slot
	# 直接从引用表取
	if card_slot >= 0 and card_slot < 5:
		if is_player:
			card_node = _player_card_nodes[card_slot]
		else:
			card_node = _enemy_card_nodes[card_slot]
	# 清除引用表中的记录（卡牌要飞走了）
	if card_node and is_instance_valid(card_node):
		if is_player:
			_player_card_nodes[card_slot] = null
		else:
			_enemy_card_nodes[card_slot] = null
	# 更新卡牌数据（攻防可能变化过）
	var card_data = {
		"name": card_name,
		"atk": card.current_atk,
		"hp": card.current_hp,
		"cost": card.base_cost,
		"element": card.get_effective_element() if card.has_method("get_effective_element") else "",
		"poison_count": card.poison_count if "poison_count" in card else 0,
		"shield_points": card.shield_points if "shield_points" in card else 0,
	}
	if card_node:
		# 卡牌自己飞向墓地
		if is_player and _field_mgr and found_slot >= 0:
			_field_mgr.remove_card(found_slot)
		# 立即 reparent 到场景根，防止 _refresh_player_field_display 误删
		var scene_root = get_tree().current_scene
		if card_node.get_parent() != scene_root:
			card_node.reparent(scene_root, true)
		if card_node.has_method("update_data"):
			card_node.update_data(card_data)
		var grave_arr = _player_grave_cards if is_player else _enemy_grave_cards
		card_node.fly_to_grave(grave_node, grave_arr.size())
		grave_arr.append(card_node)
		print("[BattleScene3D] 送墓飞行: 从槽位%d → 墓地" % found_slot)
	else:
		# 找不到卡牌节点 → 卡牌可能已被移走或还未到达
		# 不创建新卡，仅记录日志
		print("[BattleScene3D] 送墓: 未找到卡牌视觉节点（可能已被其他流程处理）")


## 卡牌除外动画：从场上/手牌飞向除外区
func _on_card_banished(card, is_player: bool) -> void:
	if card == null:
		return
	var card_name = card.card_name
	print("[BattleScene3D] 除外动画: %s (%s)" % [card_name, "己方" if is_player else "敌方"])
	# 除外音效（复用destroy音效）
	Global.play_sfx("destroy")
	var exile_node = _player_exile_node if is_player else _enemy_exile_node
	if not exile_node:
		return
	# 用 card.slot_index 从引用表直接定位卡牌节点
	var card_slot: int = card.slot_index if "slot_index" in card else -1
	var card_node: Node3D = null
	# 直接从引用表取
	if card_slot >= 0 and card_slot < 5:
		if is_player:
			card_node = _player_card_nodes[card_slot]
			_player_card_nodes[card_slot] = null
		else:
			card_node = _enemy_card_nodes[card_slot]
			_enemy_card_nodes[card_slot] = null
	# 更新卡牌数据
	var card_data = {
		"name": card_name,
		"atk": card.current_atk,
		"hp": card.current_hp,
		"cost": card.base_cost,
		"element": card.get_effective_element() if card.has_method("get_effective_element") else "",
		"poison_count": card.poison_count if "poison_count" in card else 0,
		"shield_points": card.shield_points if "shield_points" in card else 0,
	}
	if card_node and is_instance_valid(card_node):
		# 从FieldSlotManager移除
		if is_player and _field_mgr and card_slot >= 0:
			_field_mgr.remove_card(card_slot)
		# reparent到场景根
		var scene_root = get_tree().current_scene
		if card_node.get_parent() != scene_root:
			card_node.reparent(scene_root, true)
		if card_node.has_method("update_data"):
			card_node.update_data(card_data)
		# 飞向除外区
		var exile_arr = _player_exile_cards if is_player else _enemy_exile_cards
		var target_pos = exile_node.global_position + Vector3(0, 0.03 * exile_arr.size(), 0)
		var start_pos = card_node.global_position
		var mid_pos = (start_pos + target_pos) * 0.5 + Vector3(0, 1.5, 0)
		var tween = create_tween()
		tween.tween_method(func(t: float):
			if is_instance_valid(card_node):
				var p = start_pos.bezier_interpolate(target_pos, mid_pos, mid_pos, t)
				card_node.global_position = p
		, 0.0, 1.0, 0.5).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		tween.tween_callback(func():
			if is_instance_valid(card_node) and exile_node:
				card_node.reparent(exile_node, true)
				card_node.position = Vector3(0, 0.03 * exile_arr.size(), 0)
		)
		exile_arr.append(card_node)
		print("[BattleScene3D] 除外飞行: 从槽位%d → 除外区" % card_slot)
	else:
		print("[BattleScene3D] 除外: 未找到卡牌视觉节点（可能从手牌/墓地除外）")


## 除外区变化（刷新计数等）
func _on_banish_changed(is_player: bool) -> void:
	# 除外区数量变化时可以更新UI计数，当前无需额外处理
	pass


## 阶段按钮点击
func _on_phase_btn_pressed() -> void:
	if _battle_manager == null:
		return
	if _battle_manager.current_phase == BattleManager.Phase.MAIN:
		var result = _battle_manager.do_action("end_main_phase")
		if result.success:
			print("[BattleScene3D] 进入战斗阶段")
			_advance_tutorial_step("end_turn")
		else:
			print("[BattleScene3D] 无法进入战斗阶段: ", result.get("reason", ""))
	elif _battle_manager.current_phase == BattleManager.Phase.BATTLE:
		var result = _battle_manager.do_action("end_battle_phase")
		if result.success:
			print("[BattleScene3D] 结束回合")
			_advance_tutorial_step("end_turn")
		else:
			print("[BattleScene3D] 无法结束战斗阶段: ", result.get("reason", ""))


## 更新阶段按钮文字
func _update_phase_button() -> void:
	var btn = get_node_or_null("UI/PhaseBtn") as Button
	if not btn or not _battle_manager:
		return
	if _battle_manager.is_player_turn():
		if _battle_manager.current_phase == BattleManager.Phase.MAIN:
			btn.text = "进入战斗阶段"
			btn.disabled = false
		elif _battle_manager.current_phase == BattleManager.Phase.BATTLE:
			btn.text = "⏭ 结束回合"
			btn.disabled = false
		else:
			btn.text = "⏳ 等待..."
			btn.disabled = true
	else:
		btn.text = "⏳ 等待敌方..."
		btn.disabled = true


# ===== 石头剪刀布先攻选择 =====
var _rps_panel: Control = null
var _rps_font: Font = null  # RPS字体缓存（避免load偶发失败）
var _rps_player_choice: int = -1  # 0=石头 1=剪刀 2=布
var _rps_enemy_choice: int = -1
const RPS_ICONS = ["", "", ""]
const RPS_NAMES = ["石头", "剪刀", "布"]
const RPS_FONT_SIZE = 200


## 模态弹窗层：必须高于「视角」按钮所在的 ViewBtnLayer(layer=100)。
## 视角按钮为了在弃牌弹窗时仍可点，被放到了 100 层；但猜拳/结算这类全屏模态
## 如果再往 UI(layer=1) 里塞，视角按钮就会浮在遮罩上面（截图里能看到）。
func _modal_root() -> Node:
	var n = get_node_or_null("ModalLayer")
	if n == null:
		var cl := CanvasLayer.new()
		cl.name = "ModalLayer"
		cl.layer = 150
		cl.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(cl)
		n = cl
	return n


## 挂一个全屏模态遮罩：同时把「视角」按钮藏掉。
## 按钮在 ViewBtnLayer(layer=100)，理论上比 ModalLayer(150) 低，
## 但实测仍会画在遮罩之上，所以这里显式隐藏，遮罩消失后自动恢复。
func _add_modal(overlay: Control) -> void:
	_modal_root().add_child(overlay)
	overlay.tree_exited.connect(_sync_view_btn)
	if _view_btn:
		_view_btn.visible = false


func _sync_view_btn() -> void:
	# tree_exited 也可能在整场景退出时触发，此时 SceneTree 已经在销毁，
	# await get_tree().process_frame 会拿到失效对象直接报错。
	# 改用 call_deferred：节点已销毁时调用会被自动丢弃，不会崩。
	call_deferred("_apply_view_btn_visibility")


func _apply_view_btn_visibility() -> void:
	if not is_inside_tree() or not is_instance_valid(_view_btn):
		return
	var m = get_node_or_null("ModalLayer")
	var live := 0
	if m:
		for c in m.get_children():
			if not c.is_queued_for_deletion():
				live += 1
	_view_btn.visible = (live == 0)


func _rps_font_size(scale_factor: float = 1.0) -> int:
	# 猜拳面板的元素全用固定字号，但面板高度来自视口比例。
	# 原来写死 200/400，在 1080 高的横屏画布上「你/对手」会压住底部按钮、
	# 结果文字直接溢出画布。这里统一按画布高度换算。
	var h: float = 1080.0
	if get_viewport():
		h = get_viewport().get_visible_rect().size.y
	return int(clamp(h * 0.09 * scale_factor, 24.0, 220.0))


func _start_rps_select() -> void:
	_rps_player_choice = -1
	_rps_enemy_choice = -1
	_show_rps_panel()


func _show_rps_panel() -> void:
	# 先清旧的
	if _rps_panel:
		_rps_panel.queue_free()
		_rps_panel = null
	
	var ui = get_node_or_null("UI")
	if not ui:
		return
	
	# === 半透明遮罩 ===
	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.7)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	
	# === 主面板 ===
	var panel = Panel.new()
	panel.anchor_left = 0.0
	panel.anchor_top = 0.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 0.0
	panel.offset_top = 0.0
	panel.offset_right = 0.0
	panel.offset_bottom = 0.0
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.04, 0.12, 0.95)
	panel.add_theme_stylebox_override("panel", sb)
	
	var font = _get_safe_rps_font()
	if not is_instance_valid(font):
		return  # 字体加载失败，静默返回避免崩溃
	# === 标题 ===
	var title = Label.new()
	title.text = "选择石头剪刀布！决定先攻"
	title.add_theme_font_override("font", font)
	# RPS_FONT_SIZE=200 时 12 个字要 2400px，标题两侧会被屏幕直接裁掉。
	# 标题单独用一个能放下的字号，并允许换行兜底，避免再出现「选」和「攻」被切掉。
	title.add_theme_font_size_override("font_size", 72)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_color_override("font_color", Color(0.976, 0.827, 0.443, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.anchor_left = 0.0
	title.anchor_top = 0.0
	title.anchor_right = 1.0
	title.anchor_bottom = 0.0
	title.offset_top = 100.0
	title.offset_bottom = 350.0
	panel.add_child(title)
	
	# === 左边玩家选择区 ===
	var player_slot = Label.new()
	player_slot.name = "PlayerSlot"
	player_slot.add_theme_font_override("font", font)
	player_slot.add_theme_font_size_override("font_size", _rps_font_size(2.2))
	player_slot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	player_slot.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	player_slot.anchor_left = 0.0
	player_slot.anchor_top = 0.35
	player_slot.anchor_right = 0.5
	player_slot.anchor_bottom = 0.75
	player_slot.text = ""
	player_slot.add_theme_color_override("font_color", Color(0.3, 0.8, 0.4, 1.0))
	panel.add_child(player_slot)
	
	var player_label = Label.new()
	player_label.text = "你"
	player_label.add_theme_font_override("font", font)
	player_label.add_theme_font_size_override("font_size", _rps_font_size(1.0))
	player_label.add_theme_color_override("font_color", Color(0.3, 0.8, 0.4, 1.0))
	player_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	player_label.anchor_left = 0.0
	player_label.anchor_top = 0.75
	player_label.anchor_right = 0.5
	player_label.anchor_bottom = 0.85
	panel.add_child(player_label)
	
	# === 右边敌方选择区 ===
	var enemy_slot = Label.new()
	enemy_slot.name = "EnemySlot"
	enemy_slot.add_theme_font_override("font", font)
	enemy_slot.add_theme_font_size_override("font_size", _rps_font_size(2.2))
	enemy_slot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	enemy_slot.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	enemy_slot.anchor_left = 0.5
	enemy_slot.anchor_top = 0.35
	enemy_slot.anchor_right = 1.0
	enemy_slot.anchor_bottom = 0.75
	enemy_slot.text = ""
	enemy_slot.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3, 1.0))
	panel.add_child(enemy_slot)
	
	var enemy_label = Label.new()
	enemy_label.text = "对手"
	enemy_label.add_theme_font_override("font", font)
	enemy_label.add_theme_font_size_override("font_size", _rps_font_size(1.0))
	enemy_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3, 1.0))
	enemy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	enemy_label.anchor_left = 0.5
	enemy_label.anchor_top = 0.75
	enemy_label.anchor_right = 1.0
	enemy_label.anchor_bottom = 0.85
	panel.add_child(enemy_label)
	
	# === 中间VS ===
	var vs_label = Label.new()
	vs_label.text = "VS"
	vs_label.add_theme_font_override("font", font)
	vs_label.add_theme_font_size_override("font_size", _rps_font_size(1.6))
	vs_label.add_theme_color_override("font_color", Color(0.8, 0.7, 0.3, 0.8))
	vs_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vs_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	vs_label.anchor_left = 0.4
	vs_label.anchor_top = 0.4
	vs_label.anchor_right = 0.6
	vs_label.anchor_bottom = 0.7
	panel.add_child(vs_label)
	
	# === 底部三个选择按钮 ===
	# 按钮高度来自锚点 0.88~0.99（1080 高的画布上只有 119px），
	# 而 200px 字号会把按钮最小高度撑到 209px，底边直接被画布裁掉。
	# 字号跟着画布高度走：0.10 * 1080 ≈ 108，按钮最小高度刚好落进锚点框。
	var rps_btn_fs: int = _rps_font_size(0.9)
	for i in range(3):
		var btn = Button.new()
		btn.text = RPS_ICONS[i]
		btn.add_theme_font_override("font", font)
		btn.add_theme_font_size_override("font_size", rps_btn_fs)
		btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		btn.anchor_top = 0.88
		btn.anchor_bottom = 0.99
		btn.anchor_left = 0.1 + i * 0.28
		btn.anchor_right = 0.1 + i * 0.28 + 0.22
		btn.offset_left = 0.0
		btn.offset_top = 0.0
		btn.offset_right = 0.0
		btn.offset_bottom = 0.0
		var btn_sb = StyleBoxFlat.new()
		btn_sb.bg_color = Color(0.15, 0.1, 0.2, 0.9)
		btn_sb.border_width_left = 4
		btn_sb.border_width_right = 4
		btn_sb.border_width_top = 4
		btn_sb.border_width_bottom = 4
		btn_sb.border_color = Color(0.5, 0.4, 0.6, 0.8)
		btn_sb.corner_radius_top_left = 12
		btn_sb.corner_radius_top_right = 12
		btn_sb.corner_radius_bottom_left = 12
		btn_sb.corner_radius_bottom_right = 12
		btn.add_theme_stylebox_override("normal", btn_sb)
		btn.add_theme_stylebox_override("hover", btn_sb)
		btn.add_theme_stylebox_override("pressed", btn_sb)
		btn.add_theme_stylebox_override("focus", btn_sb)
		btn.pressed.connect(_on_rps_selected.bind(i))
		panel.add_child(btn)
	
	overlay.add_child(panel)
	_add_modal(overlay)
	_rps_panel = overlay


func _on_rps_selected(choice: int) -> void:
	if _rps_player_choice >= 0:
		return  # 已选过
	_rps_player_choice = choice
	# 更新左边显示玩家的选择
	var panel = _rps_panel.get_child(0) if _rps_panel else null
	if panel:
		var player_slot = panel.get_node_or_null("PlayerSlot") as Label
		if player_slot:
			player_slot.text = RPS_ICONS[choice]
	# 隐藏底部按钮
	if panel:
		for child in panel.get_children():
			if child is Button:
				child.visible = false
	# 延迟后翻开敌方选择
	await get_tree().create_timer(1.0).timeout
	_rps_reveal_enemy()


## 获取RPS字体（缓存，避免load偶发失败）
func _get_rps_font() -> Font:
	if _rps_font == null or not is_instance_valid(_rps_font):
		_rps_font = load("res://assets/share/font_pixel.ttf") as Font
	return _rps_font


func _get_safe_rps_font() -> Font:
	var font = _get_rps_font()
	if not is_instance_valid(font):
		font = preload("res://assets/share/font_pixel.ttf")
	return font


func _rps_reveal_enemy() -> void:
	_rps_enemy_choice = randi() % 3
	var panel = _rps_panel.get_child(0) if _rps_panel else null
	if panel:
		var enemy_slot = panel.get_node_or_null("EnemySlot") as Label
		if enemy_slot:
			enemy_slot.text = RPS_ICONS[_rps_enemy_choice]
	# 等待1.5秒后判定
	await get_tree().create_timer(1.5).timeout
	_rps_judge()


func _rps_judge() -> void:
	var result = _rps_compare(_rps_player_choice, _rps_enemy_choice)
	var result_text = ""
	var result_color = Color(1, 1, 1, 1)
	match result:
		1:  # 玩家胜
			result_text = "胜利！我方先攻"
			result_color = Color(0.3, 0.9, 0.4, 1.0)
			_is_player_turn = true
		-1:  # 玩家败
			result_text = "失败！敌方先攻"
			result_color = Color(0.9, 0.3, 0.3, 1.0)
			_is_player_turn = false
		0:  # 平局
			result_text = "平局！再来一次"
			result_color = Color(0.9, 0.8, 0.3, 1.0)
	
	# 显示结果文字
	var panel = _rps_panel.get_child(0) if _rps_panel else null
	if panel:
		var font = _get_safe_rps_font()
		if not is_instance_valid(font):
			return
		var result_label = Label.new()
		result_label.text = result_text
		result_label.add_theme_font_override("font", font)
		result_label.add_theme_font_size_override("font_size", _rps_font_size(0.9))
		result_label.add_theme_color_override("font_color", result_color)
		result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		result_label.anchor_left = 0.0
		result_label.anchor_top = 0.86
		result_label.anchor_right = 1.0
		result_label.anchor_bottom = 0.99
		panel.add_child(result_label)
	
	await get_tree().create_timer(2.0).timeout
	
	if result == 0:
		# 平局，重来
		if _rps_panel:
			_rps_panel.queue_free()
			_rps_panel = null
		_start_rps_select()
	else:
		# 分出胜负，关闭面板，开始战斗
		if _rps_panel:
			_rps_panel.queue_free()
			_rps_panel = null
		# 根据RPS结果启动BM第一回合（先手抽牌→准备→主要阶段）
		if _battle_manager:
			_battle_manager.start_first_turn(result == 1)
		_update_turn_info()
		_update_phase_button()
		# 教学战：战斗开始后弹出第一步引导
		if Global.is_tutorial_battle:
			call_deferred("_show_tutorial_step_popup")


func _rps_compare(a: int, b: int) -> int:
	# 0=石头 1=剪刀 2=布
	# 石头胜剪刀，剪刀胜布，布胜石头
	if a == b:
		return 0
	if (a == 0 and b == 1) or (a == 1 and b == 2) or (a == 2 and b == 0):
		return 1  # a胜
	return -1  # a败


func _process(_delta: float) -> void:
	# 敌方AI驱动已迁移至 BattleDriver（battle_core/BattleDriver.gd），此处不再轮询
	# 手牌长按检测（弃牌模式下也弹详情，方便确认卡牌效果）
	if _hand_press_time > 0 and not _long_press_triggered and not _is_dragging_hand:
		var now = Time.get_ticks_msec() / 1000.0
		if now - _hand_press_time >= LONG_PRESS_TIME:
			# 超过长按时间 → 显示详情面板
			_long_press_triggered = true
			_on_hand_long_pressed(_hand_press_index)
	# 场地卡牌长按检测
	if _field_press_time > 0 and not _field_long_press_triggered and not _field_drag_started:
		var now2 = Time.get_ticks_msec() / 1000.0
		if now2 - _field_press_time >= FIELD_LONG_PRESS_TIME:
			_field_long_press_triggered = true
			_on_field_long_pressed(_field_press_index, _field_press_is_player)
	# 墓地行长按检测
	if _grave_press_time > 0 and not _grave_long_press_triggered:
		var now3 = Time.get_ticks_msec() / 1000.0
		if now3 - _grave_press_time >= GRAVE_LONG_PRESS_TIME:
			_grave_long_press_triggered = true
			_on_grave_long_pressed(_grave_press_index)


func _on_hand_input_event(_camera, event: InputEvent, _position, _normal, _shape_idx, hand_idx: int, is_enemy: bool) -> void:
	if is_enemy:
		return
	
	# 弃牌模式：点击手牌切换选中（不走拖拽逻辑）
	if _discard_mode:
		# 记录按下状态用于长按检测
		if event is InputEventMouseButton:
			var btn = event as InputEventMouseButton
			if btn.button_index == MOUSE_BUTTON_LEFT:
				if btn.pressed:
					_hand_press_time = Time.get_ticks_msec() / 1000.0
					_hand_press_index = hand_idx
					_long_press_triggered = false
					_drag_start_screen = btn.position
				else:
					# 松手：如果不是长按触发，则切换选中
					if not _long_press_triggered and _hand_press_time > 0:
						# 防止同一帧内重复
						if _discard_last_click_frame != Engine.get_process_frames():
							_discard_last_click_frame = Engine.get_process_frames()
							_toggle_discard_selection(hand_idx)
					_hand_press_time = -1.0
					_hand_press_index = -1
			return
		
		# 触屏事件
		if event is InputEventScreenTouch:
			var touch = event as InputEventScreenTouch
			if touch.pressed:
				_hand_press_time = Time.get_ticks_msec() / 1000.0
				_hand_press_index = hand_idx
				_long_press_triggered = false
				_drag_start_screen = touch.position
			else:
				# 松手：如果不是长按触发，则切换选中
				if not _long_press_triggered and _hand_press_time > 0:
					# 防止同一帧内重复
					if _discard_last_click_frame != Engine.get_process_frames():
						_discard_last_click_frame = Engine.get_process_frames()
						_toggle_discard_selection(hand_idx)
				_hand_press_time = -1.0
				_hand_press_index = -1
			return
		
		# 其他事件（motion等）直接返回
		return
	
	# 鼠标事件
	if event is InputEventMouseButton:
		var btn = event as InputEventMouseButton
		if btn.button_index == MOUSE_BUTTON_LEFT:
			if btn.pressed:
				_hand_press_time = Time.get_ticks_msec() / 1000.0
				_hand_press_index = hand_idx
				_long_press_triggered = false
				_drag_start_screen = btn.position
				_is_dragging_hand = false
			else:
				# 松手
				if _is_dragging_hand and _drag_ctrl:
					# 拖拽中松手 → 判定是否落在卡位上
					_drag_ctrl.end_drag(btn.position)
					_is_dragging_hand = false
				elif not _long_press_triggered:
					_on_hand_clicked(hand_idx)
				_hand_press_time = -1.0
				_hand_press_index = -1
	
	# 触屏事件
	if event is InputEventScreenTouch:
		var touch = event as InputEventScreenTouch
		if touch.pressed:
			_hand_press_time = Time.get_ticks_msec() / 1000.0
			_hand_press_index = hand_idx
			_long_press_triggered = false
			_drag_start_screen = touch.position
			_is_dragging_hand = false
		else:
			# 松手
			if _is_dragging_hand and _drag_ctrl:
				_drag_ctrl.end_drag(touch.position)
				_is_dragging_hand = false
			elif not _long_press_triggered:
				_on_hand_clicked(hand_idx)
			_hand_press_time = -1.0
			_hand_press_index = -1


## 触屏拖拽移动事件
func _unhandled_input(event: InputEvent) -> void:
	# ★ 弃牌模式下禁止拖拽出牌（只能点击选中）
	if _discard_mode:
		return
	# 检测移动距离启动拖拽（按住手牌+移动超过阈值 → 进入拖拽模式）
	if _hand_press_time > 0 and not _is_dragging_hand and _hand_press_index >= 0:
		var move_pos = Vector2.ZERO
		var has_move = false
		if event is InputEventMouseMotion:
			move_pos = (event as InputEventMouseMotion).position
			has_move = true
		elif event is InputEventScreenDrag:
			move_pos = (event as InputEventScreenDrag).position
			has_move = true
		if has_move:
			var dist = move_pos.distance_to(_drag_start_screen)
			# 任何移动都取消长按计时（防止手指微抖触发弹窗）
			if dist > 10.0 and not _long_press_triggered:
				_hand_press_time = -1.0
			if dist > DRAG_CANCEL_DIST:
				# 移动距离过大
				if _long_press_triggered:
					# 长按详情已弹出 → 关掉详情，进入拖拽
					_close_detail_panel()
					_long_press_triggered = false
				if not _is_dragging_hand:
					var ok = _drag_ctrl.start_drag(_hand_press_index)
					if ok:
						_is_dragging_hand = true
					else:
						_is_dragging_hand = false
						_hand_press_time = -1.0
						_hand_press_index = -1
	
	# 拖拽中，更新指示线
	if _is_dragging_hand and _drag_ctrl:
		if event is InputEventMouseMotion:
			_drag_ctrl.update_drag((event as InputEventMouseMotion).position)
		elif event is InputEventScreenDrag:
			_drag_ctrl.update_drag((event as InputEventScreenDrag).position)
	
	# 场地卡牌攻击拖拽移动检测（鼠标InputEventMouseMotion不会触发Area3D的input_event）
	if _field_press_index >= 0 and not _field_drag_started:
		var move_pos = Vector2.ZERO
		var has_move = false
		if event is InputEventMouseMotion:
			move_pos = (event as InputEventMouseMotion).position
			has_move = true
		elif event is InputEventScreenDrag:
			move_pos = (event as InputEventScreenDrag).position
			has_move = true
		if has_move:
			var dist = move_pos.distance_to(_drag_start_screen)
			# 任何移动都取消长按计时（防止手指微抖触发弹窗）
			if dist > 10.0 and not _field_long_press_triggered:
				_field_press_time = -1.0
			if dist > DRAG_CANCEL_DIST:
				# 移动距离过大
				if _field_long_press_triggered:
					# 长按详情已弹出 → 关掉详情，进入攻击拖拽
					_close_detail_panel()
					_field_long_press_triggered = false
				if _field_press_is_player:
					_field_drag_started = true
					if _drag_ctrl:
						_drag_ctrl.start_attack_drag(_field_press_index)
				else:
					_field_press_time = -1.0
	
	# 攻击拖拽中更新指示线（鼠标移动）
	if _field_drag_started and _drag_ctrl:
		if event is InputEventMouseMotion:
			_drag_ctrl.update_attack_drag((event as InputEventMouseMotion).position)
	
	# ★ 松手事件处理（真机上手指拖出手牌Area3D后，release走_unhandled_input）
	if _is_dragging_hand and _drag_ctrl:
		if event is InputEventMouseButton:
			var btn = event as InputEventMouseButton
			if not btn.pressed and btn.button_index == MOUSE_BUTTON_LEFT:
				_drag_ctrl.end_drag(btn.position)
				_is_dragging_hand = false
		elif event is InputEventScreenTouch:
			var touch = event as InputEventScreenTouch
			if not touch.pressed:
				_drag_ctrl.end_drag(touch.position)
				_is_dragging_hand = false
	
	# ★ 场地卡牌攻击拖拽松手
	if _field_drag_started and _drag_ctrl:
		if event is InputEventMouseButton:
			var btn = event as InputEventMouseButton
			if not btn.pressed and btn.button_index == MOUSE_BUTTON_LEFT:
				_drag_ctrl.end_drag(btn.position)
				_field_drag_started = false
				_field_press_time = -1.0
				_field_press_index = -1
		elif event is InputEventScreenTouch:
			var touch = event as InputEventScreenTouch
			if not touch.pressed:
				_drag_ctrl.end_drag(touch.position)
				_field_drag_started = false
				_field_press_time = -1.0
				_field_press_index = -1


## 墓地节点交互Area
func _add_grave_area(grave_node: Node3D, is_player: bool) -> void:
	var area = Area3D.new()
	area.name = "GraveArea_%s" % ("P" if is_player else "E")
	var shape = CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(1.0, 0.3, 1.0)
	area.add_child(shape)
	grave_node.add_child(area)
	area.input_event.connect(_on_grave_input_event.bind(is_player))


## 墓地点击 → 展开墓地卡牌列表
func _on_grave_input_event(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_idx: int, is_player: bool) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_show_grave_panel(is_player)
	elif event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		_show_grave_panel(is_player)


## 展示墓地卡牌列表面板（可滑动 + 长按详情）
func _show_grave_panel(is_player: bool) -> void:
	if _battle_manager == null:
		return
	var player = _battle_manager.player_self if is_player else _battle_manager.player_opponent
	if player == null:
		return
	var grave_cards = player.grave
	if grave_cards.is_empty():
		return  # 墓地为空，不弹面板
	# 先关旧墓地面板
	_close_grave_panel()
	var ui = get_node_or_null("UI")
	if not ui:
		return
	_grave_panel_player = is_player
	# 半透明遮罩（拦截点击，防止穿透误触战场；点击遮罩本身也可关闭）
	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.6)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.z_index = 350
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.add_child(overlay)
	_grave_panel = overlay
	# 点击遮罩空白处 → 关闭弹窗（防止"卡住"）
	overlay.gui_input.connect(func(ev: InputEvent) -> void:
		if _grave_panel == null:
			return
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			_close_grave_panel()
		elif ev is InputEventScreenTouch and (ev as InputEventScreenTouch).pressed:
			_close_grave_panel()
	)
	# 面板容器（居中，占屏幕 90%×94%）
	var panel = ColorRect.new()
	panel.color = Color(0.08, 0.06, 0.051, 0.95)
	var sw = float(DisplayServer.screen_get_size().x)
	var sh = float(DisplayServer.screen_get_size().y)
	panel.offset_left = sw * 0.05
	panel.offset_top = sh * 0.03
	panel.offset_right = sw * 0.95
	panel.offset_bottom = sh * 0.97
	panel.z_index = 360
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(panel)
	# 标题
	var title = Label.new()
	title.text = (" 我的墓地（%d）" % grave_cards.size()) if is_player else (" 敌方墓地（%d）" % grave_cards.size())
	title.add_theme_font_size_override("font_size", 120)
	title.add_theme_color_override("font_color", Color("#FFD700"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(title)
	# 可滑动列表
	var scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND | Control.SIZE_FILL
	scroll.position = Vector2(40, 140)
	scroll.size = Vector2(sw * 0.88 - 80, sh * 0.72)
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_child(scroll)
	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
	vbox.add_theme_constant_override("separation", 20)
	scroll.add_child(vbox)
	# 逐条渲染墓地卡牌
	for i in range(grave_cards.size()):
		var card = grave_cards[i]
		if card == null:
			continue
		var row = Button.new()
		row.text = "%d. %s  攻%d 血%d 费%d" % [i + 1, card.card_name, card.current_atk, card.current_hp, card.base_cost]
		row.add_theme_font_size_override("font_size", 90)
		row.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
		var rs = StyleBoxFlat.new()
		rs.bg_color = Color(0.15, 0.12, 0.2, 0.6)
		rs.corner_radius_top_left = 15; rs.corner_radius_top_right = 15
		rs.corner_radius_bottom_left = 15; rs.corner_radius_bottom_right = 15
		row.add_theme_stylebox_override("normal", rs)
		row.mouse_filter = Control.MOUSE_FILTER_PASS  # 让滑动事件穿透到 ScrollContainer
		row.focus_mode = Control.FOCUS_NONE
		# 长按显示详情（短按不做事）
		var idx = i
		row.gui_input.connect(_grave_row_input.bind(idx))
		vbox.add_child(row)

	# 关闭按钮（只创建一个，避免循环内重复叠加导致点不到）
	var close_btn = Button.new()
	close_btn.text = "关闭"
	close_btn.add_theme_font_size_override("font_size", 100)
	close_btn.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
	close_btn.position = Vector2(40, sh * 0.75 + 160)
	close_btn.size = Vector2(sw * 0.88 - 80, 160)
	close_btn.pressed.connect(_close_grave_panel)
	panel.add_child(close_btn)


## 墓地行输入处理（从 lambda 抽出，避免 lambda capture freed）
func _grave_row_input(ev: InputEvent, idx: int) -> void:
	if ev is InputEventScreenTouch:
		var touch = ev as InputEventScreenTouch
		if touch.pressed:
			_grave_press_time = Time.get_ticks_msec() / 1000.0
			_grave_press_index = idx
			_grave_long_press_triggered = false
		else:
			if _grave_long_press_triggered:
				_grave_long_press_triggered = false
			_grave_press_time = -1.0
			_grave_press_index = -1
	elif ev is InputEventScreenDrag:
		if _grave_press_time > 0 and not _grave_long_press_triggered:
			_grave_press_time = -1.0
			_grave_press_index = -1
	elif ev is InputEventMouseButton:
		var btn = ev as InputEventMouseButton
		if btn.button_index == MOUSE_BUTTON_LEFT:
			if btn.pressed:
				_grave_press_time = Time.get_ticks_msec() / 1000.0
				_grave_press_index = idx
				_grave_long_press_triggered = false
			else:
				if _grave_long_press_triggered:
					_grave_long_press_triggered = false
				_grave_press_time = -1.0
				_grave_press_index = -1


## 给场地卡位添加交互Area
## is_player=true: 玩家卡位（攻击拖拽+长按详情）; is_player=false: 敌方卡位（仅长按详情）
func _add_field_slot_area(slot: Node3D, idx: int, is_player: bool = true) -> void:
	var area = Area3D.new()
	area.name = "FieldSlotArea_%d_%s" % [idx, "P" if is_player else "E"]
	var shape = CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(1.2, 0.1, 1.6)
	area.add_child(shape)
	slot.add_child(area)
	# 绑定输入事件
	area.input_event.connect(_on_field_slot_input_event.bind(idx, is_player))

## 场地卡位输入事件
## is_player=true: 玩家卡位（攻击拖拽+长按详情）; is_player=false: 敌方卡位（仅长按详情）
func _on_field_slot_input_event(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_idx: int, slot_idx: int, is_player: bool = true) -> void:
	# 鼠标事件
	if event is InputEventMouseButton:
		var btn = event as InputEventMouseButton
		if btn.button_index == MOUSE_BUTTON_LEFT:
			if btn.pressed:
				_field_press_time = Time.get_ticks_msec() / 1000.0
				_field_press_index = slot_idx
				_field_press_is_player = is_player
				_field_drag_started = false
				_field_long_press_triggered = false
				_drag_start_screen = btn.position
			else:
				if _field_drag_started and _drag_ctrl:
					_drag_ctrl.end_drag(btn.position)
				_field_press_time = -1.0
				_field_press_index = -1
				_field_drag_started = false
				_field_long_press_triggered = false
	
	# 触屏事件
	if event is InputEventScreenTouch:
		var touch = event as InputEventScreenTouch
		if touch.pressed:
			_field_press_time = Time.get_ticks_msec() / 1000.0
			_field_press_index = slot_idx
			_field_press_is_player = is_player
			_field_drag_started = false
			_field_long_press_triggered = false
			_drag_start_screen = touch.position
		else:
			if _field_drag_started and _drag_ctrl:
				_drag_ctrl.end_drag(touch.position)
			_field_press_time = -1.0
			_field_press_index = -1
			_field_drag_started = false
			_field_long_press_triggered = false
	
	# 拖拽移动检测（仅玩家卡位才进入攻击拖拽；敌方卡位只取消长按）
	if event is InputEventScreenDrag:
		if _field_press_index >= 0 and not _field_drag_started:
			var drag = event as InputEventScreenDrag
			var dist = drag.position.distance_to(_drag_start_screen)
			if dist > DRAG_CANCEL_DIST:
				if _field_long_press_triggered:
					_close_detail_panel()
					_field_long_press_triggered = false
				if is_player:
					_field_drag_started = true
					if _drag_ctrl:
						_drag_ctrl.start_attack_drag(slot_idx)
				else:
					# 敌方卡位不拖拽，仅取消长按
					_field_press_time = -1.0
		if _field_drag_started and _drag_ctrl:
			_drag_ctrl.update_attack_drag((event as InputEventScreenDrag).position)


## BM手牌变化信号：从BM.hand重建显示层 + 动态布局
## 这是手牌显示的唯一入口 —— BM hand（BattleCard动态数组）是数据源，
## 3D手牌槽（_player_hand_cards/_player_hand_datas）只是它的投影
func _on_player_hand_changed() -> void:
	_sync_player_hand_from_bm()
	_layout_player_hand(true)
	_sync_deck_visual_count()
	_update_all_info_labels()  # ★ 刷新卡组剩余张数


## 敌方手牌变化信号
func _on_enemy_hand_changed() -> void:
	_sync_enemy_hand_from_bm()
	_layout_enemy_hand(true)
	_sync_deck_visual_count()
	_update_all_info_labels()  # ★ 刷新卡组剩余张数


## 同步 3D 牌堆堆叠数量与 BM 实际卡组数一致
func _sync_deck_visual_count() -> void:
	# 玩家
	if _battle_manager and _battle_manager.player_self and _battle_manager.player_self.deck:
		var target = _battle_manager.player_self.deck.size()
		while _player_deck_nodes.size() > target:
			var n = _player_deck_nodes.pop_back()
			if is_instance_valid(n):
				n.queue_free()
		while _player_deck_nodes.size() < target:
			# 理论上不会增加（除非洗回牌堆），兜底补一张
			var card_node = CARD_SCENE.instantiate()
			var deck_area = get_node_or_null("PlayerField/DeckArea")
			if deck_area:
				deck_area.add_child(card_node)
				card_node.position = Vector3(0, 0.005, 0.02 + _player_deck_nodes.size() * 0.006)
				card_node.setup({"name":"?","card_name":"?","cost":0,"atk":0,"hp":0,"element":"无","fields":[],"quality":"标准","star":1,"effects":[]}, _card_front_mat, _card_back_mat)
				card_node.set_face_down(_card_back_mat)
			_player_deck_nodes.append(card_node)
	# 敌方
	if _battle_manager and _battle_manager.player_opponent and _battle_manager.player_opponent.deck:
		var target_e = _battle_manager.player_opponent.deck.size()
		while _enemy_deck_nodes.size() > target_e:
			var n = _enemy_deck_nodes.pop_back()
			if is_instance_valid(n):
				n.queue_free()
		while _enemy_deck_nodes.size() < target_e:
			var card_node = CARD_SCENE.instantiate()
			var deck_area = get_node_or_null("EnemyField/DeckArea")
			if deck_area:
				deck_area.add_child(card_node)
				card_node.position = Vector3(0, 0.005, 0.02 + _enemy_deck_nodes.size() * 0.006)
				card_node.setup({"name":"?","card_name":"?","cost":0,"atk":0,"hp":0,"element":"无","fields":[],"quality":"标准","star":1,"effects":[]}, _card_front_mat, _card_back_mat)
				card_node.set_face_down(_card_back_mat)
			_enemy_deck_nodes.append(card_node)


## 确保敌方手牌槽位足够（动态扩容，镜像我方）
func _ensure_enemy_hand_slots(need: int) -> void:
	while _enemy_hand_nodes.size() < need and _enemy_hand_nodes.size() < HAND_SLOT_MAX:
		var idx = _enemy_hand_nodes.size()
		var node = Node3D.new()
		node.name = "EnemyHand_" + str(idx)
		node.position = Vector3(0, ENEMY_HAND_Y, ENEMY_HAND_Z)
		add_child(node)
		_enemy_hand_nodes.append(node)
		_enemy_hand_cards.append(null)


## 从BM同步敌方手牌显示（复用已存在的BattleCard3D节点）
func _sync_enemy_hand_from_bm() -> void:
	if _battle_manager == null or _battle_manager.player_opponent == null:
		return
	var bm_hand = _battle_manager.player_opponent.hand
	var need = mini(bm_hand.size(), HAND_SLOT_MAX)
	_ensure_enemy_hand_slots(need)
	for i in range(need):
		var card = bm_hand[i]
		var display = _battle_card_to_dict(card)
		if display.is_empty():
			_set_enemy_hand_slot_empty(i)
			continue
		var card_node = _enemy_hand_cards[i] if i < _enemy_hand_cards.size() else null
		if card_node == null:
			# 新建卡牌节点
			card_node = CARD_SCENE.instantiate()
			card_node.name = "EnemyHandCard_" + str(i)
			var hand_node = _enemy_hand_nodes[i]
			if hand_node:
				hand_node.add_child(card_node)
				card_node.position = Vector3(0, 0, 0.02)
				hand_node.visible = true
			card_node.setup(display, _card_front_mat, _card_back_mat)
			card_node.set_face_down(_card_back_mat)  # 敌方手牌背面朝上
			_enemy_hand_cards[i] = card_node
		else:
			# 复用节点，仅更新数据
			if card_node.has_method("update_data"):
				card_node.update_data(display)
			card_node.set_face_down(_card_back_mat)
			var hand_node = _enemy_hand_nodes[i]
			if hand_node and hand_node.visible == false:
				hand_node.visible = true
	# 超出BM手牌数的槽位 → 隐藏/清空
	for i in range(need, _enemy_hand_cards.size()):
		_set_enemy_hand_slot_empty(i)


## 清空敌方手牌槽位
func _set_enemy_hand_slot_empty(i: int) -> void:
	if i < 0 or i >= _enemy_hand_cards.size():
		return
	var old_card = _enemy_hand_cards[i]
	if old_card and old_card != null and old_card.is_inside_tree():
		old_card.queue_free()
	_enemy_hand_cards[i] = null
	var hand_node = _enemy_hand_nodes[i] if i < _enemy_hand_nodes.size() else null
	if hand_node:
		hand_node.visible = false


## 动态排列敌方手牌（镜像我方布局，Z在-3.4侧）
func _layout_enemy_hand(is_animated: bool = false) -> void:
	var hand_indices: Array[int] = []
	for i in range(_enemy_hand_cards.size()):
		if _enemy_hand_nodes[i] and _enemy_hand_cards[i] != null:
			hand_indices.append(i)
	var count = hand_indices.size()
	if count == 0:
		return
	var span = ENEMY_HAND_MAX_X - ENEMY_HAND_MIN_X
	var spacing: float
	if count == 1:
		spacing = 0.0
	else:
		spacing = span / float(count - 1)
	var overlap = spacing < HAND_CARD_WIDTH
	for j in range(count):
		var hand_idx = hand_indices[j]
		var hand_node = _enemy_hand_nodes[hand_idx]
		if not hand_node:
			continue
		var target_x: float
		var target_y: float = ENEMY_HAND_Y
		var target_z: float = ENEMY_HAND_Z
		if count == 1:
			target_x = 0.0
		elif overlap:
			# 重叠模式：从左到右排（和玩家一致），每张间距固定
			target_x = ENEMY_HAND_MIN_X + spacing * j
			# 右压左：越靠右越上层。正交俯视相机下层叠必须用Y偏移（深度方向），Z偏移只产生屏幕错位
			target_y = ENEMY_HAND_Y + (j + 1) * HAND_Z_OVERLAP
			target_z = ENEMY_HAND_Z
		else:
			target_x = ENEMY_HAND_MIN_X + spacing * j
		var target_pos = Vector3(target_x, target_y, target_z)
		if is_animated:
			var tween = create_tween()
			tween.tween_property(hand_node, "position", target_pos, 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		else:
			hand_node.position = target_pos


## 将 BattleCard 运行时对象转为 BattleCard3D 显示需要的 Dictionary
## BM.hand/deck/field 里存的是 BattleCard 对象（RefCounted），其字段是直接属性
func _battle_card_to_dict(card) -> Dictionary:
	if card == null:
		return {}
	if card is Dictionary:
		return card
	# BattleCard 对象 → Dictionary
	var d := {}
	d["id"] = card.card_id
	d["name"] = card.card_name
	d["card_name"] = card.card_name
	d["atk"] = card.current_atk
	d["attack"] = card.current_atk
	d["hp"] = card.current_hp
	d["health"] = card.current_hp
	d["cost"] = card.base_cost
	d["energy_cost"] = card.base_cost
	d["base_cost"] = card.base_cost
	d["fields"] = card.fields if card.fields != null else []
	d["effects"] = card.effects if card.effects != null else []
	d["element"] = card.get_effective_element()
	d["quality"] = card.quality
	d["star"] = card.star
	d["desc"] = card.desc
	d["aux_items"] = card.aux_items if card.aux_items != null else []
	return d


## 确保手牌槽位数量足够（动态扩容，最多 HAND_SLOT_MAX）
func _ensure_hand_slots(need: int) -> void:
	while _player_hand_nodes.size() < need and _player_hand_nodes.size() < HAND_SLOT_MAX:
		var idx = _player_hand_nodes.size()
		var node = Node3D.new()
		node.name = "PlayerHand_" + str(idx)
		node.position = Vector3(0, HAND_Y, HAND_Z)
		add_child(node)
		_player_hand_nodes.append(node)
		# 添加交互区域（与 _create_hand_nodes 一致）
		var area = Area3D.new()
		area.name = "HandArea"
		area.input_ray_pickable = true
		var col = CollisionShape3D.new()
		col.shape = BoxShape3D.new()
		col.shape.size = Vector3(1.2, 0.1, 1.6)
		area.add_child(col)
		area.input_event.connect(_on_hand_input_event.bind(idx, false))
		node.add_child(area)
		_player_hand_cards.append(null)
		_player_hand_datas.append(null)


## 从BM.hand重建手牌显示（复用已存在的BattleCard3D节点避免重复创建）
func _sync_player_hand_from_bm() -> void:
	if _battle_manager == null or _battle_manager.player_self == null:
		return
	var bm_hand = _battle_manager.player_self.hand
	var need = mini(bm_hand.size(), HAND_SLOT_MAX)
	# 确认槽位足够
	_ensure_hand_slots(need)
	# 同步每张卡：复用节点 → update_data，不足则新建
	for i in range(need):
		var card = bm_hand[i]
		var display = _battle_card_to_dict(card)
		if display.is_empty():
			# 数据缺失：空槽
			_set_hand_slot_empty(i)
			continue
		var card_node = _player_hand_cards[i] if i < _player_hand_cards.size() else null
		if card_node == null:
			# 新建卡牌节点
			card_node = CARD_SCENE.instantiate()
			card_node.name = "HandCard_" + str(i)
			var hand_node = _player_hand_nodes[i]
			if hand_node:
				hand_node.add_child(card_node)
				card_node.position = Vector3(0, 0, 0.02)
				hand_node.visible = true
			# setup 必须在 add_child 之后调用（需要子节点已存在）
			card_node.setup(display, _card_front_mat, _card_back_mat)
			card_node.set_face_up(_card_front_mat)  # 手牌正面朝上显示
			_player_hand_cards[i] = card_node
			_player_hand_datas[i] = display
		else:
			# 复用节点，仅更新数据
			if card_node.has_method("update_data"):
				card_node.update_data(display)
			card_node.set_face_up(_card_front_mat)
			_player_hand_datas[i] = display
			var hand_node = _player_hand_nodes[i]
			if hand_node and hand_node.visible == false:
				hand_node.visible = true
	# 超出BM手牌数的槽位 → 隐藏/清空
	for i in range(need, _player_hand_cards.size()):
		_set_hand_slot_empty(i)


## 清空手牌槽位（隐藏卡牌与节点）
func _set_hand_slot_empty(i: int) -> void:
	if i < 0 or i >= _player_hand_cards.size():
		return
	var old_card = _player_hand_cards[i]
	if old_card and old_card != null and old_card.is_inside_tree():
		old_card.queue_free()
	_player_hand_cards[i] = null
	_player_hand_datas[i] = null
	var hand_node = _player_hand_nodes[i] if i < _player_hand_nodes.size() else null
	if hand_node:
		hand_node.visible = false


func _on_hand_clicked(hand_idx: int) -> void:
	if _selected_hand_index == hand_idx:
		# 点击同一张，收起
		_reset_hand_positions()
		_selected_hand_index = -1
		return
	
	# 先归位
	_reset_hand_positions()
	
	# 浮起式展开：选中的手牌向正上方浮起（Y=靠近相机方向，俯视视角下屏幕上方）
	# 不改Z（Z偏移在俯视相机下是屏幕左右/下方移动，会超出屏幕）
	_selected_hand_index = hand_idx
	var hand_node = _player_hand_nodes[hand_idx]
	if hand_node and hand_node.visible and _player_hand_cards[hand_idx] != null:
		var tween = create_tween()
		tween.tween_property(hand_node, "position:y", HAND_Y + HAND_EXPAND_POS_Y, 0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)


func _reset_hand_positions() -> void:
	# 归位改为动态布局
	_layout_player_hand(true)


## 动态排列手牌：最左对齐1号卡位，最右对齐5号卡位
## 手牌少时均匀分布；手牌多放不下时左压右重叠（左边Z更大=更靠前）
## is_animated=true 时带0.15秒过渡动画
func _layout_player_hand(is_animated: bool = false) -> void:
	# 收集当前手牌（按原始索引顺序，保留空洞）
	var hand_indices: Array[int] = []
	for i in range(_player_hand_cards.size()):
		if _player_hand_nodes[i] and _player_hand_cards[i] != null:
			hand_indices.append(i)
	
	var count = hand_indices.size()
	if count == 0:
		return
	
	var span = HAND_MAX_X - HAND_MIN_X
	var spacing: float
	if count == 1:
		spacing = 0.0
	else:
		spacing = span / float(count - 1)
	
	# 是否重叠：间距小于卡宽
	var overlap = spacing < HAND_CARD_WIDTH
	
	# 计算每张手牌的目标位置
	for j in range(count):
		var hand_idx = hand_indices[j]
		var hand_node = _player_hand_nodes[hand_idx]
		if not hand_node:
			continue
		# 弃牌模式下，跳过已选中的卡（由 _refresh_discard_hand_highlight 单独处理位置）
		if _discard_mode and _discard_selected.has(hand_idx):
			continue
		var target_x: float
		var target_y: float = HAND_Y
		var target_z: float = HAND_Z
		
		if count == 1:
			# 只有一张：放中间
			target_x = 0.0
		elif overlap:
			# 重叠模式：从左到右排（BM[0]在最左），每张间距固定
			target_x = HAND_MIN_X + spacing * j
			# 右压左：越靠右越上层。正交俯视相机下层叠必须用Y偏移（深度方向），Z偏移只产生屏幕错位
			target_y = HAND_Y + (j + 1) * HAND_Z_OVERLAP
			target_z = HAND_Z
		else:
			# 均匀分布
			target_x = HAND_MIN_X + spacing * j
		
		var target_pos = Vector3(target_x, target_y, target_z)
		if is_animated:
			var tween = create_tween()
			tween.tween_property(hand_node, "position", target_pos, 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		else:
			hand_node.position = target_pos


func _on_hand_long_pressed(hand_idx: int) -> void:
	var card_data = _get_player_hand_card_data(hand_idx)
	if card_data.is_empty():
		return
	_show_card_detail(card_data)
	_advance_tutorial_step("detail")


## 场地卡牌长按 → 显示卡牌详情（支持玩家/敌方）
func _on_field_long_pressed(slot_idx: int, is_player: bool = true) -> void:
	if _battle_manager == null:
		return
	var player = _battle_manager.player_self if is_player else _battle_manager.player_opponent
	if player == null:
		return
	if slot_idx < 0 or slot_idx >= player.field.size():
		return
	var card = player.field[slot_idx]
	if card == null:
		return
	_show_card_detail(_battle_card_to_dict(card))


## 关闭详情面板
func _close_detail_panel() -> void:
	if _detail_panel:
		_detail_panel.queue_free()
		_detail_panel = null

## 关闭墓地面板（不影响详情面板）
func _close_grave_panel() -> void:
	_grave_press_time = -1.0
	_grave_press_index = -1
	_grave_long_press_triggered = false
	if _grave_panel:
		_grave_panel.queue_free()
		_grave_panel = null

## 墓地行长按触发 → 显示该卡详情
func _on_grave_long_pressed(idx: int) -> void:
	if _battle_manager == null:
		return
	var player = _battle_manager.player_self if _grave_panel_player else _battle_manager.player_opponent
	if player == null:
		return
	if idx < 0 or idx >= player.grave.size():
		return
	var card = player.grave[idx]
	if card == null:
		return
	_show_card_detail(_battle_card_to_dict(card))


func _show_card_detail(data: Dictionary) -> void:
	# 先关旧的
	if _detail_panel:
		_detail_panel.queue_free()
		_detail_panel = null
	
	var ui = get_node_or_null("UI")
	if not ui:
		return
	
	# === 半透明遮罩 ===
	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.5)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	
	# === 详情面板（右半边屏幕，用anchors比例适配）===
	var panel = Panel.new()
	# 半透明深色背景
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.06, 0.14, 0.95)
	sb.border_width_left = 4
	sb.border_color = Color(0.976, 0.827, 0.443, 0.8)
	sb.corner_radius_top_left = 0
	sb.corner_radius_bottom_left = 0
	panel.add_theme_stylebox_override("panel", sb)
	# 用anchors占右半边屏幕（0.5→1.0），适配任何分辨率
	panel.anchor_left = 0.5
	panel.anchor_top = 0.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 0.0
	panel.offset_top = 0.0
	panel.offset_right = 0.0
	panel.offset_bottom = 0.0
	
	# === ScrollContainer 内放内容（用anchors填满panel内部）===
	var scroll = ScrollContainer.new()
	scroll.anchor_left = 0.0
	scroll.anchor_top = 0.0
	scroll.anchor_right = 1.0
	scroll.anchor_bottom = 1.0
	# 留出顶部关闭按钮空间和四周边距（字号放大后边距也加大）
	scroll.offset_left = 80.0
	scroll.offset_top = 220.0
	scroll.offset_right = -80.0
	scroll.offset_bottom = -80.0
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	
	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 30)
	
	var font = load("res://assets/share/font_pixel.ttf")
	
	# 卡名
	var name_lbl = _make_detail_label(data.get("name", data.get("card_name", "未命名")), font, FONT_SIZE_DETAIL, Color(0.976, 0.827, 0.443, 1.0))
	vbox.add_child(name_lbl)
	
	# 字段（始终显示）
	var fields: Array = data.get("fields", [])
	var field_text = " · ".join(fields) if fields.size() > 0 else "无"
	vbox.add_child(_make_detail_label("字段: " + field_text, font, FONT_SIZE_DETAIL - 10, Color(0.63, 0.71, 0.86, 0.9)))
	
	# 分隔线
	vbox.add_child(_make_sep(font))
	
	# 攻击/生命/费用
	var stats = HBoxContainer.new()
	stats.add_theme_constant_override("separation", 60)
	
	var atk_val = data.get("atk", data.get("attack", 0))
	var hp_val = data.get("hp", data.get("health", 0))
	var cost_val = data.get("cost", data.get("energy_cost", 0))
	
	stats.add_child(_make_stat_box("攻击", str(atk_val), Color(0.86, 0.24, 0.24, 1.0), font))
	stats.add_child(_make_stat_box("生命", str(hp_val), Color(0.24, 0.86, 0.31, 1.0), font))
	stats.add_child(_make_stat_box("费用", str(cost_val), Color(0.24, 0.47, 0.86, 1.0), font))
	vbox.add_child(stats)
	
	# 品质 + 元素 + 星级
	var qual = data.get("quality", "普通")
	var element = data.get("element", CardManager.get_card_element(data))
	var elem_map := {"火": "[火]", "水": "[水]", "风": "[风]", "暗": "[暗]", "光": "[光]", "地": "[地]", "无": ""}
	if element != "" and elem_map.has(element):
		qual += "  " + elem_map[element]
	var star = data.get("star", 1)
	var star_str = ""
	for i in range(star):
		star_str += "★"
	qual += "  " + star_str
	vbox.add_child(_make_detail_label(qual, font, FONT_SIZE_DETAIL - 10, Color(0.7, 0.7, 0.7, 1.0)))
	
	vbox.add_child(_make_sep(font))
	
	# 效果（始终显示标题，无效果显示"无"）
	vbox.add_child(_make_detail_label("效果", font, FONT_SIZE_DETAIL - 10, Color(0.78, 0.63, 0.25, 1.0)))
	var effects_raw: Array = data.get("effects", [])
	var eff_texts := []
	for e in effects_raw:
		if e is Dictionary:
			var eff_desc = Global.get_effect_desc(e)
			if eff_desc != "":
				eff_texts.append("- " + eff_desc)
		elif e is String:
			var comp = Global.get_circuit_by_id(e)
			if comp and comp.has("name"):
				eff_texts.append("- " + comp["name"])
			elif e != "":
				eff_texts.append("- " + e)
	if eff_texts.size() > 0:
		vbox.add_child(_make_detail_label("\n".join(eff_texts), font, FONT_SIZE_DETAIL - 15, Color(0.78, 0.78, 0.78, 1.0)))
	else:
		vbox.add_child(_make_detail_label("无", font, FONT_SIZE_DETAIL - 15, Color(0.5, 0.5, 0.5, 0.8)))
	
	# 描述（始终显示标题，无描述显示"无"）
	vbox.add_child(_make_detail_label("描述", font, FONT_SIZE_DETAIL - 10, Color(0.78, 0.63, 0.25, 1.0)))
	var desc = data.get("desc", data.get("description", ""))
	if desc != "":
		vbox.add_child(_make_detail_label(desc, font, FONT_SIZE_DETAIL - 15, Color(0.63, 0.63, 0.63, 1.0)))
	else:
		vbox.add_child(_make_detail_label("无", font, FONT_SIZE_DETAIL - 15, Color(0.5, 0.5, 0.5, 0.8)))
	
	# 辅材（始终显示标题，无辅材显示"无"）
	vbox.add_child(_make_detail_label("辅材", font, FONT_SIZE_DETAIL - 10, Color(0.78, 0.63, 0.25, 1.0)))
	var aux_items: Array = data.get("aux_items", [])
	if aux_items.size() > 0:
		var aux_texts := []
		for aux in aux_items:
			var an: String = aux.get("name", "")
			var ae = _describe_aux_effect(aux)
			aux_texts.append(an + "  " + ae if ae != "" else an)
		vbox.add_child(_make_detail_label("\n".join(aux_texts), font, FONT_SIZE_DETAIL - 15, Color(0.55, 0.71, 0.78, 1.0)))
	else:
		vbox.add_child(_make_detail_label("无", font, FONT_SIZE_DETAIL - 15, Color(0.5, 0.5, 0.5, 0.8)))
	
	scroll.add_child(vbox)
	panel.add_child(scroll)
	
	# 关闭按钮（右上角，用anchor适配）
	var close_btn = Button.new()
	close_btn.text = ""
	close_btn.anchor_left = 1.0
	close_btn.anchor_top = 0.0
	close_btn.anchor_right = 1.0
	close_btn.anchor_bottom = 0.0
	close_btn.offset_left = -200.0
	close_btn.offset_top = 20.0
	close_btn.offset_right = -20.0
	close_btn.offset_bottom = 200.0
	close_btn.add_theme_font_size_override("font_size", 125)
	close_btn.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3, 1))
	close_btn.pressed.connect(_close_card_detail)
	panel.add_child(close_btn)
	
	overlay.add_child(panel)
	# 提高 z_index 确保在墓地弹窗（z_index=350）之上
	overlay.z_index = 400
	ui.add_child(overlay)
	_detail_panel = overlay


func _close_card_detail() -> void:
	if _detail_panel:
		_detail_panel.queue_free()
		_detail_panel = null


func _make_detail_label(text: String, font: Font, size: int, color: Color) -> Label:
	var lbl = Label.new()
	lbl.text = text
	if font:
		lbl.add_theme_font_override("font", font)
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", color)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return lbl


func _make_sep(font: Font) -> HSeparator:
	var sep = HSeparator.new()
	sep.add_theme_constant_override("separation", 20)
	return sep


func _make_stat_box(label_text: String, value_text: String, color: Color, font: Font) -> VBoxContainer:
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	var lbl1 = Label.new()
	lbl1.text = label_text
	lbl1.add_theme_font_override("font", font)
	lbl1.add_theme_font_size_override("font_size", FONT_SIZE_DETAIL - 15)
	lbl1.add_theme_color_override("font_color", color.darkened(0.3))
	var lbl2 = Label.new()
	lbl2.text = value_text
	lbl2.add_theme_font_override("font", font)
	lbl2.add_theme_font_size_override("font_size", FONT_SIZE_DETAIL)
	lbl2.add_theme_color_override("font_color", color)
	box.add_child(lbl1)
	box.add_child(lbl2)
	return box


func _describe_aux_effect(aux: Dictionary) -> String:
	var effect = aux.get("effect", {})
	if effect.is_empty():
		return ""
	var parts := []
	if effect.has("atk_bonus"):
		parts.append("攻击+" + str(effect["atk_bonus"]))
	if effect.has("hp_bonus"):
		parts.append("生命+" + str(effect["hp_bonus"]))
	if effect.has("energy_reduce"):
		parts.append("费用-" + str(effect["energy_reduce"]))
	if effect.has("element"):
		parts.append("属性→" + str(effect["element"]))
	if effect.has("shield"):
		parts.append("护盾" + str(effect["shield"]))
	if effect.get("indestructible_once", false):
		parts.append("免毁一次")
	if effect.get("haste", false):
		parts.append("急速")
	if effect.has("damage_reduce"):
		parts.append("减伤" + str(effect["damage_reduce"]))
	if effect.has("poison"):
		parts.append("中毒+" + str(effect["poison"]))
	if effect.get("combo", false):
		parts.append("连击")
	if parts.is_empty():
		return ""
	return "[" + " ".join(parts) + "]"


func _get_player_hand_card_data(hand_idx: int) -> Dictionary:
	if hand_idx >= 0 and hand_idx < _player_hand_datas.size() and _player_hand_datas[hand_idx] != null:
		return _player_hand_datas[hand_idx]
	return {}


func _input(event: InputEvent) -> void:
	# 详情面板打开时，点击面板外区域（遮罩部分）关闭，面板内部不拦截
	if _detail_panel:
		if event is InputEventMouseButton:
			var btn = event as InputEventMouseButton
			if btn.pressed and btn.button_index == MOUSE_BUTTON_LEFT:
				# 获取点击位置
				var mpos = btn.position
				# 判断是否点击在面板内部（右半边）
				var vp_size = get_viewport().get_visible_rect().size
				if mpos.x < vp_size.x * 0.5:
					# 点击在左半边遮罩区域 → 关闭
					_close_card_detail()
				# 点击在右半边面板内 → 不处理，让ScrollContainer/按钮自己响应
		elif event is InputEventScreenTouch:
			var touch = event as InputEventScreenTouch
			if touch.pressed:
				var mpos = touch.position
				var vp_size = get_viewport().get_visible_rect().size
				if mpos.x < vp_size.x * 0.5:
					_close_card_detail()
		return
	
	# 鼠标/触屏点击空白处取消选中
	var is_click2 = false
	if event is InputEventMouseButton:
		var btn = event as InputEventMouseButton
		if btn.pressed and btn.button_index == MOUSE_BUTTON_LEFT:
			is_click2 = true
	elif event is InputEventScreenTouch:
		var touch = event as InputEventScreenTouch
		if touch.pressed:
			is_click2 = true
	
	if is_click2:
		if _selected_hand_index >= 0:
			var hit_hand = false
			for i in range(_player_hand_nodes.size()):
				if _player_hand_nodes[i]:
					var area = _player_hand_nodes[i].get_node_or_null("HandArea") as Area3D
					if area:
						var space = get_world_3d().direct_space_state
						var cam = _cam
						if cam and space:
							var mpos = get_viewport().get_mouse_position()
							var from = cam.project_ray_origin(mpos)
							var dir = cam.project_ray_normal(mpos)
							var params = PhysicsRayQueryParameters3D.new()
							params.from = from
							params.to = from + dir * 20.0
							params.collide_with_areas = true
							var result = space.intersect_ray(params)
							if result:
								var collider = result.get("collider")
								if collider and collider == area:
									hit_hand = true
									break
			if not hit_hand:
				_reset_hand_positions()
				_selected_hand_index = -1


func _exit_tree() -> void:
	# 清空引用表（防止场景复用时残留旧引用）
	for i in range(_player_card_nodes.size()):
		_player_card_nodes[i] = null
	for i in range(_enemy_card_nodes.size()):
		_enemy_card_nodes[i] = null
	_player_exile_cards.clear()
	_enemy_exile_cards.clear()
	Global.exit_landscape_canvas()


# ===== 教学战引导系统 =====

## 教学战：完成当前步骤对应的操作后才推进到下一步提示
## trigger: "detail" 长按查看详情 / "summon" 召唤成功 / "attack" 发动攻击 / "end_turn" 结束回合
func _advance_tutorial_step(trigger: String) -> void:
	if not Global.is_tutorial_battle:
		return
	var should_advance := false
	match _tutorial_step:
		0:
			should_advance = false  # 纯讲解，由按钮直接推进
		1:
			should_advance = (trigger == "detail")
		2:
			should_advance = (trigger == "summon")
		3:
			should_advance = (trigger == "end_turn")  # 第一回合 主→战斗
		4:
			should_advance = (trigger == "end_turn")  # 第一回合 战斗→结束
		5:
			should_advance = (trigger == "end_turn")  # 第二回合 主→战斗
		6:
			should_advance = (trigger == "attack")    # 第二回合 战斗阶段攻击
		7:
			should_advance = false  # 空场直击讲解，纯提示
		8:
			should_advance = false  # 最终胜利提示，无需推进
	if not should_advance:
		return
	_tutorial_step += 1
	_show_tutorial_step_popup()

## 弹出当前步骤的教学提示小窗
func _show_tutorial_step_popup() -> void:
	if _tutorial_popup_overlay and is_instance_valid(_tutorial_popup_overlay):
		_tutorial_popup_overlay.queue_free()
		_tutorial_popup_overlay = null
	if _tutorial_step >= _TUTORIAL_HINTS.size():
		return
	if not Global.is_tutorial_battle:
		return
	if _battle_manager == null or not is_instance_valid(_battle_manager):
		return
	
	var overlay = Control.new()
	overlay.name = "TutorialStepOverlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	_tutorial_popup_overlay = overlay
	
	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	
	var panel = Panel.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.anchor_left = 0.5; panel.anchor_top = 0.5
	panel.anchor_right = 0.5; panel.anchor_bottom = 0.5
	panel.offset_left = Global.pw(-0.48); panel.offset_top = Global.ph(-0.32)
	panel.offset_right = Global.pw(0.48); panel.offset_bottom = Global.ph(0.32)
	var ps = StyleBoxFlat.new()
	ps.bg_color = Color(0.08, 0.07, 0.06, 0.97)
	ps.border_width_left = 8; ps.border_width_right = 8
	ps.border_width_top = 8; ps.border_width_bottom = 8
	ps.border_color = Color("#e8a838")
	ps.corner_radius_top_left = 40; ps.corner_radius_top_right = 40
	ps.corner_radius_bottom_left = 40; ps.corner_radius_bottom_right = 40
	panel.add_theme_stylebox_override("panel", ps)
	overlay.add_child(panel)
	
	var title = Label.new()
	title.text = "新手教学 %d/%d" % [_tutorial_step + 1, _TUTORIAL_HINTS.size()]
	title.add_theme_font_size_override("font_size", 80)
	title.add_theme_color_override("font_color", Color("#f9d371"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.anchor_left = 0.0; title.anchor_top = 0.0
	title.anchor_right = 1.0; title.anchor_bottom = 0.0
	title.offset_top = Global.ph(0.025); title.offset_bottom = Global.ph(0.12)
	panel.add_child(title)
	
	var body = Label.new()
	body.text = _TUTORIAL_HINTS[_tutorial_step]
	body.add_theme_font_size_override("font_size", 84)
	body.add_theme_color_override("font_color", Color("#f0e6d6"))
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.anchor_left = 0.0; body.anchor_top = 0.0
	body.anchor_right = 1.0; body.anchor_bottom = 1.0
	body.offset_left = Global.pw(0.06); body.offset_right = Global.pw(-0.06)
	body.offset_top = Global.ph(0.13); body.offset_bottom = Global.ph(-0.16)
	panel.add_child(body)
	
	var ok_btn = Button.new()
	ok_btn.text = "我知道了"
	ok_btn.add_theme_font_size_override("font_size", 76)
	var bs = StyleBoxFlat.new()
	bs.bg_color = Color(0.2, 0.18, 0.13, 1.0)
	bs.border_width_left = 4; bs.border_width_right = 4
	bs.border_width_top = 4; bs.border_width_bottom = 4
	bs.border_color = Color("#e8a838")
	bs.corner_radius_top_left = 24; bs.corner_radius_top_right = 24
	bs.corner_radius_bottom_left = 24; bs.corner_radius_bottom_right = 24
	ok_btn.add_theme_stylebox_override("normal", bs)
	ok_btn.add_theme_color_override("font_color", Color("#f9d371"))
	ok_btn.anchor_left = 0.5; ok_btn.anchor_top = 1.0
	ok_btn.anchor_right = 0.5; ok_btn.anchor_bottom = 1.0
	ok_btn.offset_left = Global.pw(-0.28); ok_btn.offset_top = Global.ph(-0.115)
	ok_btn.offset_right = Global.pw(0.28); ok_btn.offset_bottom = Global.ph(-0.015)
	ok_btn.pressed.connect(func():
		if _tutorial_popup_overlay and is_instance_valid(_tutorial_popup_overlay):
			_tutorial_popup_overlay.queue_free()
			_tutorial_popup_overlay = null
		# 纯讲解步骤：点按钮直接推进到下一提示
		var is_pure_tip := false
		if _tutorial_step == 0 or _tutorial_step == 7 or _tutorial_step == 8:
			is_pure_tip = true
		if is_pure_tip:
			_tutorial_step += 1
			_show_tutorial_step_popup()
	)
	panel.add_child(ok_btn)
	
	overlay.modulate.a = 0.0
	var tw = create_tween()
	tw.tween_property(overlay, "modulate:a", 1.0, 0.25)

## 回合结束效果已发完（数据层），等非飘窗动画（画线1.2s/闪烁1.2s/视角切换0.2s）播完后再推进弃牌阶段
## 避免回合结束效果的视角切换/画线动画与弃牌视角切换交错打架
func _on_end_phase_effects_pending_discard(need_discard: int) -> void:
	print("[UI] 回合结束效果已发完，等待非飘窗动画播完再进弃牌: 需弃", need_discard, "张")
	# 画线动画=0.8停留+0.4淡出=1.2s，边框闪烁=1.2s，视角切换=0.2s，取安全值1.4s确保全部播完
	# 用scene_tree的timer而非tween，避免被暂停/其他tween干扰
	await get_tree().create_timer(1.4).timeout
	# 二次确认：BM仍处于END阶段才推进（防止动画等待期间状态被其他流程改变）
	if _battle_manager and is_instance_valid(_battle_manager):
		_battle_manager.proceed_to_discard_after_end_effects()

# ===== 弃牌选择系统 =====

## 弃牌请求信号处理（由BattleManager的discard_requested信号触发）
func _on_discard_requested(count: int, callback_id: int, reason: String) -> void:
	if _discard_mode:
		print("[UI] 弃牌弹窗忙，请求入队: 回调ID=", callback_id, " 需弃", count, "张")
		_discard_request_queue.append({"count": count, "callback_id": callback_id, "reason": reason})
		return
	print("[UI] 收到弃牌请求: ", count, "张, 原因: ", reason)
	_discard_callback_id = callback_id
	_discard_need = count
	_show_discard_ui(reason)

## 弹出队列中下一个弃牌弹窗
func _process_next_discard_request() -> void:
	if _discard_request_queue.is_empty():
		return
	var req = _discard_request_queue.pop_front()
	print("[UI] 处理队列中的弃牌请求: 回调ID=", req.callback_id, " 需弃", req.count, "张")
	_discard_callback_id = req.callback_id
	_discard_need = req.count
	_show_discard_ui(req.reason)

## 弃牌动画请求：数据已弃，播放飞向墓地特效，播完通知BM
func _on_discard_animation_requested(callback_id: int, is_player_side: bool, discard_indices: Array) -> void:
	print("[UI] 播放弃牌飞向墓地动画: 回调ID=", callback_id, " 己方=", is_player_side, " 弃", discard_indices.size(), "张")
	# 恢复游戏树（暂停会导致tween不运行，回调死锁）
	get_tree().paused = false
	# 记录弃牌前的视角，动画结束后恢复（避免弃牌后视角永远停在弃牌方）
	# 注：回合结束效果的画线/闪烁动画播完后才进弃牌（见_on_end_phase_effects_pending_discard），此时视角已稳定，直接记录当前视角即可
	_cam_state_before_discard = _cam_state
	# 谁弃牌转谁视角（平滑过渡，从当前位置到目标位置）
	var target_cam = 2 if is_player_side else 0
	var target_cam_z = CAM_POS_Z[target_cam]
	if _cam and abs(_cam.position.z - target_cam_z) > 0.01:
		if _cam_tween and _cam_tween.is_valid():
			_cam_tween.kill()
		_cam_tween = create_tween()
		_cam_tween.tween_property(_cam, "position:z", target_cam_z, 0.3).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		_cam_state = target_cam
		var labels = ["敌方", "中", "己方"]
		if _view_btn:
			_view_btn.text = "视角: " + labels[_cam_state]
	_play_discard_animation_3d(callback_id, is_player_side, discard_indices)

## 切换弃牌选中
func _toggle_discard_selection(hand_index: int) -> void:
	if _battle_manager == null:
		return
	var self_p = _battle_manager.player_self
	if hand_index < 0 or hand_index >= self_p.hand.size():
		return
	if _discard_selected.has(hand_index):
		_discard_selected.erase(hand_index)
	else:
		if _discard_selected.size() < _discard_need:
			_discard_selected.append(hand_index)
	_refresh_discard_hand_highlight()

## 刷新弃牌手牌高亮
func _refresh_discard_hand_highlight() -> void:
	for i in range(_player_hand_nodes.size()):
		var node = _player_hand_nodes[i]
		if node == null or not node.visible:
			continue
		var card_node = _player_hand_cards[i] if i < _player_hand_cards.size() else null
		if card_node == null:
			continue
		var is_selected = _discard_selected.has(i)
		# 选中：上浮+前移+缩放
		if is_selected:
			var tween = create_tween()
			tween.tween_property(node, "position:y", HAND_Y + HAND_EXPAND_POS_Y, 0.15).set_ease(Tween.EASE_OUT)
			# 前移：向相机方向（负Z）移动一个卡牌距离
			tween.parallel().tween_property(node, "position:z", HAND_Z - 1.2, 0.15).set_ease(Tween.EASE_OUT)
			# 选中标记：缩放略大
			tween.parallel().tween_property(card_node, "scale", Vector3(1.15, 1.15, 1.15), 0.15)
		else:
			# 未选中：回到正常布局位置
			_layout_player_hand(true)
			var tween = create_tween()
			tween.tween_property(card_node, "scale", Vector3(1.0, 1.0, 1.0), 0.15)
	# 更新计数
	if _discard_count_label:
		_discard_count_label.text = "已选：%d / %d 张" % [_discard_selected.size(), _discard_need]
	if _discard_confirm_btn:
		_discard_confirm_btn.disabled = (_discard_selected.size() < _discard_need)

## 显示弃牌弹窗（2D UI叠加层）
func _show_discard_ui(reason: String) -> void:
	_discard_mode = true
	_discard_selected.clear()
	# ★ 不暂停树：_discard_mode 标志已拦截手牌点击/拖拽逻辑，
	# 暂停会导致视角切换tween、选中动画tween、手牌Area3D全部失效
	# ★ 但必须关闭驱动器闸门：否则敌方AI队列会在玩家弃牌期间继续推进（横竖屏统一行为）
	if _battle_driver:
		_battle_driver.set_ui_busy(true)
	
	# 创建2D叠加层
	var canvas = CanvasLayer.new()
	canvas.name = "DiscardCanvas"
	canvas.process_mode = Node.PROCESS_MODE_ALWAYS
	_discard_panel = canvas
	
	# 半透明背景遮罩
	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.4)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	# ★ 关键：设置 IGNORE 让鼠标/触屏事件穿透，不吞噬下方 3D 手牌的输入
	# 否则 bg 作为 2D 全屏 Control 会拦截所有输入，手牌的 Area3D 就收不到 input_event
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.process_mode = Node.PROCESS_MODE_ALWAYS
	canvas.add_child(bg)
	
	# 面板
	var panel = Panel.new()
	panel.name = "DiscardPanel"
	panel.process_mode = Node.PROCESS_MODE_ALWAYS
	var ps = StyleBoxFlat.new()
	ps.bg_color = Color(0.08, 0.06, 0.14, 0.95)
	ps.corner_radius_top_left = 16; ps.corner_radius_top_right = 16
	ps.corner_radius_bottom_left = 16; ps.corner_radius_bottom_right = 16
	ps.border_width_left = 2; ps.border_width_right = 2
	ps.border_width_top = 2; ps.border_width_bottom = 2
	ps.border_color = Color(0.4, 0.3, 0.6)
	panel.add_theme_stylebox_override("panel", ps)
	panel.anchor_left = 0.05; panel.anchor_top = 0.05
	panel.anchor_right = 0.95; panel.anchor_bottom = 0.25
	canvas.add_child(panel)
	
	# 标题
	var title = Label.new()
	var title_text = " 弃牌" if reason == "CO04" else " 弃牌阶段"
	title.text = title_text
	title.add_theme_font_size_override("font_size", 70)
	title.add_theme_color_override("font_color", Color("#e0c0f0"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_FULL_RECT)
	title.offset_top = 13
	panel.add_child(title)
	
	# 计数标签
	_discard_count_label = Label.new()
	_discard_count_label.text = "已选：0 / %d 张" % _discard_need
	_discard_count_label.add_theme_font_size_override("font_size", 55)
	_discard_count_label.add_theme_color_override("font_color", Color("#f0d060"))
	_discard_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_discard_count_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_discard_count_label.offset_top = 88
	panel.add_child(_discard_count_label)
	
	# 确认按钮
	_discard_confirm_btn = Button.new()
	_discard_confirm_btn.text = "确认弃牌"
	_discard_confirm_btn.disabled = true
	_discard_confirm_btn.add_theme_font_size_override("font_size", 55)
	_discard_confirm_btn.anchor_left = 0.1; _discard_confirm_btn.anchor_top = 1.0
	_discard_confirm_btn.anchor_right = 0.9; _discard_confirm_btn.anchor_bottom = 1.0
	_discard_confirm_btn.offset_top = -113
	_discard_confirm_btn.offset_bottom = -13
	_discard_confirm_btn.pressed.connect(_on_confirm_discard)
	panel.add_child(_discard_confirm_btn)
	
	add_child(canvas)
	
	# 刷新手牌高亮
	_refresh_discard_hand_highlight()
	print("[UI] 弃牌弹窗: 暂停游戏树等待玩家选择, 需弃", _discard_need, "张, 原因:", reason)

## 隐藏弃牌UI
func _hide_discard_ui() -> void:
	_discard_mode = false
	_discard_selected.clear()
	_discard_need = 0
	# 恢复驱动器闸门（横竖屏统一：弃牌弹窗期间敌方AI暂停推进）
	if _battle_driver:
		_battle_driver.set_ui_busy(false)
	# 恢复手牌正常布局+缩放
	_layout_player_hand(true)
	for i in range(_player_hand_cards.size()):
		var card_node = _player_hand_cards[i]
		if card_node and is_instance_valid(card_node):
			var tween = create_tween()
			tween.tween_property(card_node, "scale", Vector3(1.0, 1.0, 1.0), 0.15)
	if _discard_panel:
		_discard_panel.queue_free()
		_discard_panel = null
	_discard_count_label = null
	_discard_confirm_btn = null

## 确认弃牌
func _on_confirm_discard() -> void:
	if _battle_manager == null:
		return
	if _discard_callback_id < 0 or _discard_selected.size() == 0:
		return
	# 防止重复点击
	if _discard_last_click_frame == Engine.get_process_frames():
		return
	_discard_last_click_frame = Engine.get_process_frames()
	# 先取消暂停，否则后续的布局tween和弃牌动画tween都不会运行
	get_tree().paused = false
	_battle_manager._on_discard_result(_discard_callback_id, _discard_selected)
	print("[UI] 弃牌提交，回调ID:", _discard_callback_id)
	_discard_callback_id = -1
	_hide_discard_ui()

## 播放弃牌飞向墓地动画（3D版：手牌飞向墓地）
func _play_discard_animation_3d(callback_id: int, is_player_side: bool, discard_indices: Array) -> void:
	# 相机切换已在 _on_discard_animation_requested 中完成，这里不再重复
	# 墓地和手牌位置根据弃牌方选择
	var grave_node = get_node_or_null("PlayerField/GraveArea") if is_player_side else get_node_or_null("EnemyField/GraveArea")
	var grave_pos = grave_node.global_position + Vector3(0, 0.15, 0) if grave_node else Vector3(0, 0.15, 3.5)
	
	# 收集手牌当前位置
	var hand_nodes = _player_hand_nodes if is_player_side else _enemy_hand_nodes
	var start_positions := []
	for idx in discard_indices:
		if idx >= 0 and idx < hand_nodes.size():
			var node = hand_nodes[idx]
			if node:
				start_positions.append(node.global_position)
	
	if start_positions.is_empty():
		# 没有可播放的位置，直接完成
		_resume_after_discard_animation()
		_battle_manager._on_discard_animation_finished(callback_id)
		_process_next_discard_request()
		return
	
	# 创建临时飞行卡牌
	var fly_cards := []
	for i in range(start_positions.size()):
		var fly = MeshInstance3D.new()
		var mesh = BoxMesh.new()
		mesh.size = Vector3(0.7, 1.0, 0.01)
		fly.mesh = mesh
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.3, 0.2, 0.5)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		fly.material_override = mat
		# ★ 必须先入树再设 global_position，否则节点不在树内赋值静默失败（弃牌卡会从原点飞出）
		add_child(fly)
		fly.global_position = start_positions[i]
		fly_cards.append(fly)
	
	# 飞向墓地
	var delay = 0.0
	for fly in fly_cards:
		var tween = create_tween()
		tween.tween_interval(delay)
		tween.tween_property(fly, "global_position", grave_pos, 0.4).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
		tween.parallel().tween_property(fly, "scale", Vector3(0.3, 0.3, 0.3), 0.4)
		tween.tween_callback(fly.queue_free)
		delay += 0.1
	
	# 等动画完成后恢复
	var final_tween = create_tween()
	final_tween.tween_interval(delay + 0.5)
	final_tween.tween_callback(func():
		_resume_after_discard_animation()
		_battle_manager._on_discard_animation_finished(callback_id)
		_process_next_discard_request()
	)

## 弃牌动画完成后恢复游戏
func _resume_after_discard_animation() -> void:
	if _discard_mode:
		return
	get_tree().paused = false
	# 恢复弃牌前的视角（弃牌动画播放时切到了弃牌方视角）
	if _cam_state != _cam_state_before_discard:
		_cam_state = _cam_state_before_discard
		if _cam:
			if _cam_tween and _cam_tween.is_valid():
				_cam_tween.kill()
			_cam_tween = create_tween()
			_cam_tween.tween_property(_cam, "position:z", CAM_POS_Z[_cam_state], 0.25).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		var labels = ["敌方", "中", "己方"]
		if _view_btn:
			_view_btn.text = "视角: " + labels[_cam_state]


# ============================
#  胜利奖励：辅材掉落
# ============================
## 教学战保底掉落：制作第一张卡所需的最低级素材
## 卡基：纤维 + 矿粉 + 树脂（各2个）
## 卡墨：萃取液 + 颜料 + 黏合剂（各2个）
## 返回掉落列表（素材已入库），供胜利结算弹窗展示
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

func _handle_victory_rewards(extra_drops: Array = []) -> void:
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
	
	# 合并保底掉落（如教学战卡基/卡墨素材，已提前入库）
	for drop in extra_drops:
		gained_aux.append({
			"material_id": drop.get("material_id", ""),
			"name": drop.get("name", ""),
			"rarity": drop.get("rarity", "普通"),
			"amount": drop.get("amount", 1),
		})
	
	# ★ BOSS战：固定掉落，不经过概率判定
	var is_boss_battle = Global.current_is_boss
	if is_boss_battle:
		# 直接发放所有专属辅材（固定掉落，保底1个）
		for drop in aux_drops:
			var aux_id = drop.get("id", "")
			if aux_id == "":
				continue
			var aux_data = Global.get_aux_by_id(aux_id)
			if not aux_data.is_empty():
				var amount = 1
				if Global.current_is_ambush:
					amount = 2
				WarehouseManager.add_aux(aux_id, amount)
				gained_aux.append({
					"material_id": aux_id,
					"name": aux_data.get("name", aux_id),
					"rarity": aux_data.get("rarity", "普通"),
					"amount": amount,
				})
				print("[战斗] BOSS固定掉落: ", aux_data.get("name", aux_id), " x", amount)
		# 公共采集素材也照常给（按概率）
		for drop in common_drops:
			var prob = drop.get("prob", 0.5)
			if rng.randf() < prob:
				var amount = rng.randi_range(drop.get("min", 1), drop.get("max", 1))
				if Global.current_is_ambush:
					amount *= 2
				WarehouseManager.add_material(drop["material_id"], amount)
				gained_aux.append({
					"material_id": drop["material_id"],
					"name": drop.get("name", ""),
					"rarity": drop.get("rarity", "普通"),
					"amount": amount,
				})
				print("[战斗] 地形掉落: ", drop.get("name", ""), " x", amount)
	else:
		# 普通战斗：按概率随机掉落
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
		
		# 从合并池中随机掉落1~3个（按概率判定，保底至少1个）
		if all_drops.size() > 0:
			var drop_count = rng.randi_range(1, 3)
			
			# 按概率判定每个素材是否掉落
			var passed := []
			for item in all_drops:
				var prob = 0.5
				for cd in common_drops:
					if cd.get("material_id", "") == item["id"]:
						prob = cd.get("prob", 0.5)
						break
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
				if Global.current_is_ambush:
					amount *= 2
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
	
	# 伏击战标记清理（下次战斗前重置）
	var was_ambush = Global.current_is_ambush
	Global.current_is_ambush = false
	
	# 显示掉落结果弹窗
	_show_battle_reward_popup(gained_aux, was_ambush)


func _show_battle_reward_popup(gained_aux: Array, is_ambush: bool = false) -> void:
	var ui = get_node_or_null("UI")
	if not ui:
		return
	# 遮罩
	var overlay = ColorRect.new()
	overlay.name = "BattleRewardOverlay"
	overlay.color = Color(0.0, 0.0, 0.0, 0.65)
	overlay.anchor_left = 0.0; overlay.anchor_top = 0.0
	overlay.anchor_right = 1.0; overlay.anchor_bottom = 1.0
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.gui_input.connect(_on_reward_overlay_clicked.bind(overlay))
	_add_modal(overlay)
	
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
	if is_ambush:
		title.text = "伏击胜利！双倍掉落！"
	else:
		title.text = "战斗胜利！"
	title.add_theme_font_size_override("font_size", 110)
	title.add_theme_color_override("font_color", Color("#f9d371"))
	title.add_theme_color_override("font_shadow_color", Color("#000000"))
	title.add_theme_constant_override("shadow_offset_x", 4)
	title.add_theme_constant_override("shadow_offset_y", 4)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.anchor_left = 0.0; title.anchor_top = 0.0
	title.anchor_right = 1.0; title.anchor_bottom = 0.0
	title.offset_left = 0; title.offset_top = Global.ph(0.04)
	title.offset_right = 0; title.offset_bottom = Global.ph(0.14)
	panel.add_child(title)
	
	# 分隔线
	var line = ColorRect.new()
	line.color = Color(1.0, 1.0, 1.0, 0.15)
	line.anchor_left = 0.0; line.anchor_top = 0.0
	line.anchor_right = 1.0; line.anchor_bottom = 0.0
	line.offset_left = Global.pw(0.05); line.offset_top = Global.ph(0.15)
	line.offset_right = Global.pw(-0.05); line.offset_bottom = Global.ph(0.16)
	panel.add_child(line)
	
	if gained_aux.size() == 0:
		var empty = Label.new()
		empty.text = "本次战斗没有获得额外掉落物"
		empty.add_theme_font_size_override("font_size", 84)
		empty.add_theme_color_override("font_color", Color("#5a5a6e"))
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty.anchor_left = 0.0; empty.anchor_top = 0.0
		empty.anchor_right = 1.0; empty.anchor_bottom = 0.0
		empty.offset_left = 0; empty.offset_top = Global.ph(0.24)
		empty.offset_right = 0; empty.offset_bottom = Global.ph(0.50)
		panel.add_child(empty)
	else:
		# 掉落物副标题
		var sub = Label.new()
		sub.text = "掉落辅材："
		sub.add_theme_font_size_override("font_size", 88)
		sub.add_theme_color_override("font_color", Color("#e8d5b7"))
		sub.anchor_left = 0.0; sub.anchor_top = 0.0
		sub.anchor_right = 1.0; sub.anchor_bottom = 0.0
		sub.offset_left = Global.pw(0.06); sub.offset_top = Global.ph(0.18)
		sub.offset_right = 0; sub.offset_bottom = Global.ph(0.28)
		panel.add_child(sub)
		
		# 辅材列表（可滚动）
		var scroll = ScrollContainer.new()
		scroll.name = "RewardScroll"
		scroll.anchor_left = 0.0; scroll.anchor_top = 0.0
		scroll.anchor_right = 1.0; scroll.anchor_bottom = 1.0
		scroll.offset_left = Global.pw(0.03); scroll.offset_top = Global.ph(0.28)
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
			rs.corner_radius_top_left = 16; rs.corner_radius_top_right = 16
			rs.corner_radius_bottom_left = 16; rs.corner_radius_bottom_right = 16
			row.add_theme_stylebox_override("panel", rs)
			row.custom_minimum_size = Vector2(0, Global.ph(0.10))
			row.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
			vbox.add_child(row)
		
			var hbox = HBoxContainer.new()
			hbox.anchor_left = 0.0; hbox.anchor_top = 0.0
			hbox.anchor_right = 1.0; hbox.anchor_bottom = 1.0
			hbox.offset_left = Global.pw(0.03)
			hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(hbox)
			
			var name_label = Label.new()
			name_label.text = aux.get("name", "未知")
			name_label.add_theme_font_size_override("font_size", 84)
			name_label.add_theme_color_override("font_color", rarity_color)
			name_label.size_flags_horizontal = Control.SIZE_EXPAND
			hbox.add_child(name_label)
			
			var count_label = Label.new()
			count_label.text = "x" + str(int(aux.get("amount", 1)))
			count_label.add_theme_font_size_override("font_size", 84)
			count_label.add_theme_color_override("font_color", rarity_color)
			count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			count_label.custom_minimum_size = Vector2(Global.pw(0.12), 0)
			hbox.add_child(count_label)
			
			row_idx += 1
		
		# 底部留白
		var spacer = Control.new()
		spacer.custom_minimum_size = Vector2(0, Global.ph(0.03))
		vbox.add_child(spacer)
	
	# 确认按钮（底部居中）
	var confirm_btn = Button.new()
	if Global.is_tutorial_battle or _exit_to_main:
		confirm_btn.text = "返回主界面"
	else:
		confirm_btn.text = "返回地图"
	confirm_btn.add_theme_font_size_override("font_size", 90)
	var cs = StyleBoxFlat.new()
	cs.bg_color = Color(0.2, 0.15, 0.3)
	cs.border_width_left = 4; cs.border_width_right = 4
	cs.border_width_top = 4; cs.border_width_bottom = 4
	cs.border_color = Color(0.5, 0.4, 0.7)
	cs.corner_radius_top_left = 24; cs.corner_radius_top_right = 24
	cs.corner_radius_bottom_left = 24; cs.corner_radius_bottom_right = 24
	cs.content_margin_left = 60; cs.content_margin_right = 60
	confirm_btn.add_theme_stylebox_override("normal", cs)
	confirm_btn.add_theme_color_override("font_color", Color("#e8d5b7"))
	confirm_btn.anchor_left = 0.0; confirm_btn.anchor_top = 1.0
	confirm_btn.anchor_right = 1.0; confirm_btn.anchor_bottom = 1.0
	confirm_btn.offset_left = Global.pw(0.24); confirm_btn.offset_top = -Global.ph(0.14)
	confirm_btn.offset_right = Global.pw(-0.06); confirm_btn.offset_bottom = -Global.ph(0.03)
	confirm_btn.pressed.connect(_on_reward_confirm.bind(overlay))
	panel.add_child(confirm_btn)


func _on_reward_confirm(overlay: ColorRect) -> void:
	overlay.queue_free()
	_go_back_to_map()


func _on_reward_overlay_clicked(event: InputEvent, overlay: ColorRect) -> void:
	if event is InputEventScreenTouch and not event.pressed:
		_on_reward_confirm(overlay)


func _show_battle_exit_btn(state: int = 2) -> void:
	var ui = get_node_or_null("UI")
	if not ui:
		return
	# 显示退出弹窗（败北/平局时用）
	var overlay = ColorRect.new()
	overlay.name = "BattleExitOverlay"
	overlay.color = Color(0.0, 0.0, 0.0, 0.65)
	overlay.anchor_left = 0.0; overlay.anchor_top = 0.0
	overlay.anchor_right = 1.0; overlay.anchor_bottom = 1.0
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_add_modal(overlay)
	
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
	match state:
		2: title.text = "战斗失败"
		3: title.text = "平局"
		_: title.text = "战斗结束"
	title.add_theme_font_size_override("font_size", 55)
	title.add_theme_color_override("font_color", Color("#e74c3c") if state == 2 else Color("#f39c12"))
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


## 退出按钮回调：显示确认弹窗（战斗中点返回时触发）
func _on_battle_exit_btn() -> void:
	var ui = get_node_or_null("UI")
	if not ui:
		return
	var overlay = ColorRect.new()
	overlay.name = "BattleExitConfirmOverlay"
	overlay.color = Color(0.0, 0.0, 0.0, 0.7)
	overlay.anchor_left = 0.0; overlay.anchor_top = 0.0
	overlay.anchor_right = 1.0; overlay.anchor_bottom = 1.0
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_add_modal(overlay)
	
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
	panel.offset_left = Global.pw(0.15); panel.offset_top = Global.ph(0.26)
	panel.offset_right = Global.pw(-0.15); panel.offset_bottom = -Global.ph(0.26)
	overlay.add_child(panel)
	
	var title = Label.new()
	title.text = "退出战斗"
	title.add_theme_font_size_override("font_size", 76)
	title.add_theme_color_override("font_color", Color("#e74c3c"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.anchor_left = 0.0; title.anchor_top = 0.0
	title.anchor_right = 1.0; title.anchor_bottom = 0.30
	panel.add_child(title)
	
	var tip = Label.new()
	tip.text = "退出将返回主界面\n确定要退出吗？"
	tip.add_theme_font_size_override("font_size", 48)
	tip.add_theme_color_override("font_color", Color("#b0a0c0"))
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tip.anchor_left = 0.0; tip.anchor_top = 0.30
	tip.anchor_right = 1.0; tip.anchor_bottom = 0.62
	panel.add_child(tip)
	
	# 确认按钮
	var confirm_btn = Button.new()
	confirm_btn.text = "确认退出"
	confirm_btn.add_theme_font_size_override("font_size", 56)
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
	confirm_btn.anchor_left = 0.0; confirm_btn.anchor_top = 0.66
	confirm_btn.anchor_right = 0.5; confirm_btn.anchor_bottom = 1.0
	confirm_btn.offset_left = Global.pw(0.05); confirm_btn.offset_top = Global.ph(0.015)
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
	cancel_btn.add_theme_font_size_override("font_size", 56)
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
	cancel_btn.anchor_left = 0.5; cancel_btn.anchor_top = 0.66
	cancel_btn.anchor_right = 1.0; cancel_btn.anchor_bottom = 1.0
	cancel_btn.offset_left = Global.pw(0.02); cancel_btn.offset_top = Global.ph(0.015)
	cancel_btn.offset_right = Global.pw(-0.05); cancel_btn.offset_bottom = -Global.ph(0.04)
	cancel_btn.pressed.connect(func():
		overlay.queue_free()
	)
	panel.add_child(cancel_btn)


## 返回主界面或地图内继续探索
func _go_back_to_map() -> void:
	# 恢复屏幕方向
	Global.exit_landscape_canvas()
	
	# 保存爬塔持久HP（战斗后更新）
	if Global.current_run_player_hp > 0 and _battle_manager and _battle_manager.player_self:
		Global.current_run_player_hp = _battle_manager.player_self.hp
	
	# 清理战斗数据
	Global.current_enemy_data = {}
	Global.current_battle_terrain = ""
	
	# 教学战：无论胜负都回主界面找老陈
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
