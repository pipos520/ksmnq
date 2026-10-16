extends Node

## ============================================================
##  Global.gd — 兼容性转发层（Facade）
##  实际逻辑已拆分到 core/ 目录下的专注模块：
##    QualityConfig / ElementSystem / ThemeManager / SceneManager
##    AudioManager / DeckRentService / CircuitDatabase / DataCache
##    BattleContext
##  本文件仅做一行转发，保持 Global.xxx API 不变
## ============================================================

# ===== 枚举（保留在 Global 以兼容 Global.ThemeMode / Global.Phase）=====
enum ThemeMode { NIGHT, DAY }
enum Phase { NONE, DRAW, READY, MAIN, BATTLE, END, DISCARD }

func _ready() -> void:
	# 转发 theme_changed 信号
	ThemeManager.theme_changed.connect(func(m): theme_changed.emit(m))

# ============================================================
#  信号
# ============================================================

signal theme_changed(mode: ThemeMode)

# ============================================================
#  坐标辅助（转发到 ThemeManager）
# ============================================================

static func ph(ratio: float) -> float:
	return ThemeManager.ph(ratio)

static func pw(ratio: float) -> float:
	return ThemeManager.pw(ratio)

# ============================================================
#  品质系统（转发到 QualityConfig）
# ============================================================

var QUALITY_ORDER:
	get: return QualityConfig.QUALITY_ORDER
var QUALITY_MULTS:
	get: return QualityConfig.QUALITY_MULTS
var QUALITY_LEVELS:
	get: return QualityConfig.QUALITY_LEVELS
var QUALITY_COLORS:
	get: return QualityConfig.QUALITY_COLORS
var QUALITY_ENCODE:
	get: return QualityConfig.QUALITY_ENCODE
var QUALITY_DECODE:
	get: return QualityConfig.QUALITY_DECODE

static func get_quality_rank(quality: String) -> int:
	return QualityConfig.get_quality_rank(quality)

static func get_quality_color(quality: String) -> Color:
	return QualityConfig.get_quality_color(quality)

static func get_quality_mult(quality: String) -> float:
	return QualityConfig.get_quality_mult(quality)

# ============================================================
#  元素系统（转发到 ElementSystem）
# ============================================================

static func get_element_emoji(element: String) -> String:
	return ElementSystem.get_element_emoji(element)

static func get_element_affinity(atk_element: String, def_element: String) -> float:
	return ElementSystem.get_element_affinity(atk_element, def_element)

static func get_element_power_multiplier(element: String, power_bonus: float, effect_type: String = "") -> float:
	return ElementSystem.get_element_power_multiplier(element, power_bonus, effect_type)

# ============================================================
#  主题系统（转发到 ThemeManager）
# ============================================================

var current_mode:
	get: return ThemeManager.current_mode
	set(v): ThemeManager.current_mode = v

var current:
	get: return ThemeManager.current

var use_legacy_battle:
	get: return ThemeManager.use_legacy_battle
	set(v): ThemeManager.use_legacy_battle = v

func switch_theme(mode) -> void:
	ThemeManager.switch_theme(mode)

func toggle_theme() -> void:
	ThemeManager.toggle_theme()

func get_battle_scene_path() -> String:
	return ThemeManager.get_battle_scene_path()

func save_battle_mode() -> void:
	ThemeManager.save_battle_mode()

func apply_bg(node: Node) -> void:
	ThemeManager.apply_bg(node)

func make_topbar(top_ratio: float = 0.083) -> ColorRect:
	return ThemeManager.make_topbar(top_ratio)

func make_topbar_bottom_line(top_ratio: float = 0.083) -> ColorRect:
	return ThemeManager.make_topbar_bottom_line(top_ratio)

func make_bg() -> TextureRect:
	return ThemeManager.make_bg()

func make_title(text: String, font_size: int = 200, bottom_ratio: float = 0.135) -> Label:
	return ThemeManager.make_title(text, font_size, bottom_ratio)

func make_version(text: String, font_size: int = 50) -> Label:
	return ThemeManager.make_version(text, font_size)

func make_bordered_btn(text: String, border_color: Color, font_size: int = 55) -> Button:
	return ThemeManager.make_bordered_btn(text, border_color, font_size)

func make_gear_btn() -> Button:
	return ThemeManager.make_gear_btn()

func make_back_btn() -> Button:
	return ThemeManager.make_back_btn()

func show_global_toast(text: String, color: Color = Color("#FFD700")) -> void:
	ThemeManager.show_global_toast(text, color)

# ============================================================
#  场景管理（转发到 SceneManager）
# ============================================================

var preloaded_scenes:
	get: return SceneManager.preloaded_scenes
	set(v): SceneManager.preloaded_scenes = v

func change_scene(path: String) -> void:
	SceneManager.change_scene(path)

func start_background_loading(scenes_to_preload: Array, total_tasks: int) -> void:
	SceneManager.start_background_loading(scenes_to_preload, total_tasks)

# ============================================================
#  音效系统（转发到 AudioManager）
# ============================================================

func play_sfx(sfx_name: String) -> void:
	AudioManager.play_sfx(sfx_name)

func set_sfx_enabled(enabled: bool) -> void:
	AudioManager.set_sfx_enabled(enabled)

# ============================================================
#  租借卡组（转发到 DeckRentService）
# ============================================================

var current_rented_deck_id:
	get: return DeckRentService.current_rented_deck_id
	set(v): DeckRentService.current_rented_deck_id = v

var current_rented_deck_name:
	get: return DeckRentService.current_rented_deck_name
	set(v): DeckRentService.current_rented_deck_name = v

func get_all_rented_decks() -> Dictionary:
	return DeckRentService.get_all_rented_decks()

func rent_deck(source_deck_data: Dictionary) -> Dictionary:
	return DeckRentService.rent_deck(source_deck_data)

func consume_rented_durability(rid: String, amount: int) -> int:
	return DeckRentService.consume_rented_durability(rid, amount)

func get_rented_deck(rid: String) -> Dictionary:
	return DeckRentService.get_rented_deck(rid)

const RENTED_DECK_MAX_DURABILITY = DeckRentService.RENTED_DECK_MAX_DURABILITY
const RENT_COST_GOLD = DeckRentService.RENT_COST_GOLD
const RENT_DUR_COST_EXPLORE = DeckRentService.RENT_DUR_COST_EXPLORE
const RENT_DUR_COST_DUEL = DeckRentService.RENT_DUR_COST_DUEL

# ============================================================
#  战斗状态传递（转发到 BattleContext）
# ============================================================

var current_map_id:
	get: return BattleContext.current_map_id
	set(v): BattleContext.current_map_id = v

var current_map_name:
	get: return BattleContext.current_map_name
	set(v): BattleContext.current_map_name = v

var current_deck_id:
	get: return BattleContext.current_deck_id
	set(v): BattleContext.current_deck_id = v

var current_deck_name:
	get: return BattleContext.current_deck_name
	set(v): BattleContext.current_deck_name = v

var current_enemy_data:
	get: return BattleContext.current_enemy_data
	set(v): BattleContext.current_enemy_data = v

var current_battle_terrain:
	get: return BattleContext.current_battle_terrain
	set(v): BattleContext.current_battle_terrain = v

var current_map_layer:
	get: return BattleContext.current_map_layer
	set(v): BattleContext.current_map_layer = v

var current_map_node:
	get: return BattleContext.current_map_node
	set(v): BattleContext.current_map_node = v

var current_is_boss:
	get: return BattleContext.current_is_boss
	set(v): BattleContext.current_is_boss = v

var current_is_ambush:
	get: return BattleContext.current_is_ambush
	set(v): BattleContext.current_is_ambush = v

var is_tutorial_battle:
	get: return BattleContext.is_tutorial_battle
	set(v): BattleContext.is_tutorial_battle = v

var current_run_player_hp:
	get: return BattleContext.current_run_player_hp
	set(v): BattleContext.current_run_player_hp = v

var current_run_player_max_hp:
	get: return BattleContext.current_run_player_max_hp
	set(v): BattleContext.current_run_player_max_hp = v

var saved_map_node_data:
	get: return BattleContext.saved_map_node_data
	set(v): BattleContext.saved_map_node_data = v

# ============================================================
#  敌人/素材/辅材/服务器数据（转发到 DataCache）
# ============================================================

var server_decks:
	get: return DataCache.server_decks
	set(v): DataCache.server_decks = v

var server_decks_loaded:
	get: return DataCache.server_decks_loaded
	set(v): DataCache.server_decks_loaded = v

var server_card_packs:
	get: return DataCache.server_card_packs
	set(v): DataCache.server_card_packs = v

var server_card_packs_loaded:
	get: return DataCache.server_card_packs_loaded
	set(v): DataCache.server_card_packs_loaded = v

var material_data:
	get: return DataCache.material_data
var formula_data:
	get: return DataCache.formula_data

func load_enemy_data() -> Dictionary:
	return DataCache.load_enemy_data()

func get_enemy_card_template(template_id: String) -> Dictionary:
	return DataCache.get_enemy_card_template(template_id)

func get_map_monsters(map_id: String, terrain: String) -> Array:
	return DataCache.get_map_monsters(map_id, terrain)

func get_map_boss(map_id: String) -> Dictionary:
	return DataCache.get_map_boss(map_id)

func get_material_by_id(id: String) -> Dictionary:
	return DataCache.get_material_by_id(id)

func get_fiber_list() -> Array:
	return DataCache.get_fiber_list()

func get_mineral_list() -> Array:
	return DataCache.get_mineral_list()

func get_resin_list() -> Array:
	return DataCache.get_resin_list()

func get_extract_list() -> Array:
	return DataCache.get_extract_list()

func get_pigment_list() -> Array:
	return DataCache.get_pigment_list()

func get_binder_list() -> Array:
	return DataCache.get_binder_list()

func get_formulas() -> Dictionary:
	return DataCache.get_formulas()

func get_gather_materials(map_id: String, terrain: String) -> Array:
	return DataCache.get_gather_materials(map_id, terrain)

func get_aux_list() -> Array:
	return DataCache.get_aux_list()

func get_aux_by_id(id: String) -> Dictionary:
	return DataCache.get_aux_by_id(id)

func get_all_decks() -> Dictionary:
	return DataCache.get_all_decks()

func get_random_deck() -> Dictionary:
	return await DataCache.get_random_deck()

func get_all_card_packs() -> Dictionary:
	return DataCache.get_all_card_packs()

func get_server_card_pack(pack_id: String) -> Dictionary:
	return DataCache.get_server_card_pack(pack_id)

func open_card_pack(pack_id: String, count: int = 3) -> Dictionary:
	return await DataCache.open_card_pack(pack_id, count)

func get_player_id() -> String:
	return DataCache.get_player_id()

# ============================================================
#  纹路组件系统（转发到 CircuitDatabase）
# ============================================================

var circuit_triggers:
	get: return CircuitDatabase.circuit_triggers
var circuit_conditions:
	get: return CircuitDatabase.circuit_conditions
var circuit_actions:
	get: return CircuitDatabase.circuit_actions
var circuit_targets:
	get: return CircuitDatabase.circuit_targets
var circuit_constraints:
	get: return CircuitDatabase.circuit_constraints
var circuit_mutex:
	get: return CircuitDatabase.circuit_mutex
var initial_unlocked:
	get: return CircuitDatabase.initial_unlocked
var unlock_paths:
	get: return CircuitDatabase.unlock_paths
var circuit_row_pool:
	get: return CircuitDatabase.circuit_row_pool

func get_all_triggers() -> Array:
	return CircuitDatabase.get_all_triggers()

func get_all_conditions() -> Array:
	return CircuitDatabase.get_all_conditions()

func get_all_actions() -> Array:
	return CircuitDatabase.get_all_actions()

func get_all_targets() -> Array:
	return CircuitDatabase.get_all_targets()

func get_all_constraints() -> Array:
	return CircuitDatabase.get_all_constraints()

func get_circuit_by_id(id: String) -> Dictionary:
	return CircuitDatabase.get_circuit_by_id(id)

func get_effect_desc(eff: Dictionary) -> String:
	return CircuitDatabase.get_effect_desc(eff)

func get_mutex_by_category(cat: String) -> Array:
	return CircuitDatabase.get_mutex_by_category(cat)

func is_action_target_mutex(action_id: String, target_id: String) -> bool:
	return CircuitDatabase.is_action_target_mutex(action_id, target_id)

func get_initial_unlocked() -> Array:
	return CircuitDatabase.get_initial_unlocked()

func get_unlock_paths() -> Array:
	return CircuitDatabase.get_unlock_paths()

func get_target_modifier(target_id: String) -> float:
	return CircuitDatabase.get_target_modifier(target_id)

func can_chain(trigger_id: String, current_chain_speed: int) -> bool:
	return CircuitDatabase.can_chain(trigger_id, current_chain_speed)

func can_activate_circuit(parsed_effect: Dictionary, owner, opponent, source_card, battle_state: int, current_phase: int, player_index: int) -> Dictionary:
	return CircuitDatabase.can_activate_circuit(parsed_effect, owner, opponent, source_card, battle_state, current_phase, player_index)

func format_effect_description(parsed_effect: Dictionary) -> String:
	return CircuitDatabase.format_effect_description(parsed_effect)

static func parse_circuit(effect_data: Dictionary) -> Dictionary:
	return CircuitDatabase.parse_circuit(effect_data)

static func check_condition(condition_data: Dictionary, owner, opponent, source_card = null) -> bool:
	return CircuitDatabase.check_condition(condition_data, owner, opponent, source_card)

static func get_action_cost(action_id: String, value: int) -> float:
	return CircuitDatabase.get_action_cost(action_id, value)

static func check_constraint(constraint_id: String, owner, battle_state: int, current_phase: int, player_index: int) -> bool:
	return CircuitDatabase.check_constraint(constraint_id, owner, battle_state, current_phase, player_index)

static func check_mutex(parsed_effect: Dictionary) -> bool:
	return CircuitDatabase.check_mutex(parsed_effect)

static func get_constraint_param(effect: Dictionary, cid: String, fallback: int = 1) -> int:
	return CircuitDatabase.get_constraint_param(effect, cid, fallback)

static func get_constraint_param_str(effect: Dictionary, cid: String, fallback: String = "") -> String:
	return CircuitDatabase.get_constraint_param_str(effect, cid, fallback)

static func trigger_to_type(trigger_id: String) -> int:
	return CircuitDatabase.trigger_to_type(trigger_id)

# ============================================================
#  私有变量转发（兼容外部直接访问 Global._xxx）
# ============================================================

var _circuit_map:
	get: return CircuitDatabase._circuit_map

func _save_battle_mode() -> void:
	ThemeManager._save_battle_mode()
