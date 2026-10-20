extends Control

# ============================================================
#  节点爬塔地图 —— 参考杀戮尖塔
# 8层爬塔：起点 → 树林 → 草丛 → 矿区 → 溪谷 → 山道 → 暗穴 → BOSS
#  每层节点点击后，只有相邻的可达节点才能继续前进，当前节点居中
# ============================================================

enum NodeType { MONSTER, GATHER, REST, BOSS, START, EMPTY, EXIT }

# 8层（起点 + 7层），每层有独立地形
# y 坐标在 [0.13, 0.87] 范围内（避开 TopBar 0~0.083 和 BottomBar 0.917~1.0）
# 裂隙局模式下会被 _build_rift_layer_config() 整体替换（GDD §7.3 v1.3）
var LAYER_CONFIG: Array = [
	{"name": " 起点", "y": 0.87, "color": Color("#ffffff"), "node_count": 1, "is_start": true},
	{"name": " 树林", "y": 0.77, "color": Color("#5cb85c"), "node_count": 3, "terrain": "forest"},
	{"name": " 草丛", "y": 0.67, "color": Color("#e8a838"), "node_count": 3, "terrain": "grass"},
	{"name": " 矿区", "y": 0.57, "color": Color("#9b59b6"), "node_count": 3, "terrain": "mine"},
	{"name": " 溪谷", "y": 0.47, "color": Color("#3498db"), "node_count": 3, "terrain": "valley"},
	{"name": " 山道", "y": 0.37, "color": Color("#e87d38"), "node_count": 3, "terrain": "mountain"},
	{"name": " 暗穴", "y": 0.27, "color": Color("#8e44ad"), "node_count": 3, "terrain": "cave"},
	{"name": " BOSS", "y": 0.13, "color": Color("#e74c3c"), "node_count": 1},
]

# ===== 裂隙局（GDD §7.3 v1.3：入口化裂隙局，外层包装，节点事件逻辑全部复用）=====
var _is_rift := false
# 裂隙中层节点权重（GDD §7.3.2，归一化自 40/25/10/15；EVENT 复用 EMPTY 承载）
const RIFT_TYPE_WEIGHTS := [
	{"t": NodeType.MONSTER, "w": 0.444},
	{"t": NodeType.GATHER, "w": 0.278},
	{"t": NodeType.REST, "w": 0.111},
	{"t": NodeType.EMPTY, "w": 0.167},
]
const RIFT_TERRAINS := ["forest", "grass", "mine", "valley", "mountain", "cave"]

# 连接关系改为动态生成（杀戮尖塔风格，每个节点有限扇出）
# 不再使用硬编码 CONNECTIONS，由 _generate_connections() 生成

# 节点X基准位置（3个节点时）
const NODE_X_POSITIONS := [0.15, 0.50, 0.85]
# 随机偏移范围
const X_RANDOM_RANGE := 0.07
const Y_RANDOM_RANGE := 0.008

# 节点类型权重
const TYPE_WEIGHTS := {"monster": 0.40, "gather": 0.35, "rest": 0.25}

# 节点图标
const NODE_ICONS := {
	NodeType.MONSTER: "",
	NodeType.GATHER: "",
	NodeType.REST: "",
	NodeType.BOSS: "",
	NodeType.START: "",
	NodeType.EMPTY: "",
	NodeType.EXIT: "",
}
const NODE_NAMES := {
	NodeType.MONSTER: "野怪",
	NodeType.GATHER: "采集",
	NodeType.REST: "休息",
	NodeType.BOSS: "BOSS",
	NodeType.START: "出发",
	NodeType.EMPTY: "异事",
	NodeType.EXIT: "撤离",
}

# 地形专属名称
const TERRAIN_MONSTER_NAMES := {
	"forest": "出没",
	"grass": "伏击",
	"mine": "矿怪",
	"valley": "水怪",
	"mountain": "飞龙",
	"cave": "魔物",
}

const TERRAIN_GATHER_NAMES := {
	"forest": "砍伐",
	"grass": "采药",
	"mine": "挖矿",
	"valley": "捞晶",
	"mountain": "捕风",
	"cave": "采晶",
}

const TERRAIN_ICONS := {
	"forest": "",
	"grass": "",
	"mine": "",
	"valley": "",
	"mountain": "",
	"cave": "",
}

# 地形ID → 中文名（对应LAYER_CONFIG中的地形层名）
const TERRAIN_NAMES := {
	"forest": "树林",
	"grass": "草丛",
	"mine": "矿区",
	"valley": "溪谷",
	"mountain": "山道",
	"cave": "暗穴",
}

# 地图ID → 中文名
const MAP_NAMES := {
	"misty_forest": " 沉雾植物园",
	"flame_cavern": " 烬燃热电厂",
	"storm_tower": " 雷鸣电视塔",
	"shadow_swamp": " 沉陷湿地公园",
	"legendary_ruins": " 圮城博物馆",
}

# 传入的地图数据
var _map_id: String = ""
var _map_name: String = ""
# 节点数据 [layer][index] = {type, x, y, available, completed, current}
var _node_data := []
# 动态连接关系 [layer][src_index] = [tgt_index...]
var _connections := []
# 当前层和节点索引
var _current_layer: int = -1
var _current_node: int = -1
var _completed_nodes := []  # 已完成节点列表
# ===== 怪物名缓存 [已废弃：改用节点内 monster_data] =====
# 旧版用全局数组缓存怪物名用于显示，但重新生成时未清空导致索引错位
# 现改为节点 Dictionary 内缓存完整怪物数据，显示/战斗统一读取

# ===== 素材名称→ID映射（用于指南弹窗长按详情） =====
const MATERIAL_NAME_TO_ID := {
	"骨胶": "B01", "鱼鳔胶": "B02", "树汁胶": "B03", "精灵胶": "B04",
	"炎胶": "B05", "风凝胶": "B06", "冰胶": "B07", "龙涎胶": "B08",
	"清水": "E01", "生命露水": "E02", "月光露": "E03",
	"火焰精华": "E04", "熔岩之息": "E05", "风之灵息": "E06",
	"雷暴精华": "E07", "冰霜精华": "E08", "虚空精华": "E09", "圣光露": "E10",
	"白麻纤维": "F01", "青藤纤维": "F02", "枯草纤维": "F03",
	"月光麻": "F04", "火焰苔藓": "F05", "熔岩藤": "F06",
	"风暴棉": "F07", "雷纹藤": "F08", "冰霜亚麻": "F09",
	"暗影藤": "F10", "光之丝": "F11", "传说亚麻": "F12",
	"石灰矿粉": "M01", "辉光矿粉": "M02", "砂金石粉": "M03",
	"月长石粉": "M04", "熔核矿粉": "M05", "炎晶粉末": "M06",
	"雷击矿砂": "M07", "风暴晶尘": "M08", "冰晶粉末": "M09",
	"暗铁砂": "M10", "圣光石粉": "M11", "星辰粉末": "M12",
	"炭黑": "P01", "朱砂": "P02", "赭石": "P03",
	"石青": "P04", "硫磺黄": "P05", "云母粉": "P06",
	"雷晶粉": "P07", "冰蓝": "P08", "暗晶粉": "P09", "金粉": "P10",
	"普通松脂": "R01", "琥珀树脂": "R02",
	"古树树脂": "R03", "熔岩树脂": "R04", "龙血树脂": "R05",
	"风泪树脂": "R06", "冰霜琥珀": "R07", "暗影树脂": "R08",
}

# ===== 辅材名称→ID映射 =====
const AUX_NAME_TO_ID := {
	"新生嫩芽": "AU16", "木质纤维": "AU17", "鹿角碎片": "AU18",
	"雾绒": "AU19", "孢子囊": "AU20", "蘑菇伞盖": "AU21",
	"灼背蜥鳞片": "AU22", "蜥蜴尾": "AU23", "螳螂刀臂": "AU24",
	"螳螂翅膜": "AU25", "蛇鳞片": "AU26", "毒液囊": "AU27",
	"岩石核心": "AU28", "矿脉石鳞": "AU29", "熔岩核心": "AU30",
	"火鳞粉": "AU31", "暗晶尾刺": "AU32", "暗晶碎片": "AU33",
	"纯净水心": "AU34", "水纹护符": "AU35", "风蝶翅粉": "AU36",
	"轻羽": "AU37", "棱镜碎片": "AU38", "圣光余晖": "AU39",
	"巨人之心": "AU40", "山岩石板": "AU41", "暗影翎羽": "AU42",
	"夜喙碎片": "AU43", "风暴羽": "AU44", "雷电之眼": "AU45",
	"蛛丝囊": "AU46", "毒牙": "AU47", "锅炉龟甲": "AU48",
	"火核": "AU49", "幻光翅粉": "AU50", "圣光蝶翼": "AU51",
	"迷雾结晶": "AU52", "守护之核": "AU53",
}

# ===== 卡兽名称→数据 =====
const ENEMY_NAME_TO_DATA := {
	"催芽藓偶": {"id": "MF_FOREST_M1", "level": 2, "hp": 20, "element": "地", "desc": "沉雾植物园催芽箱里冒出来的苔藓傀儡，见苗就缠。", "aux_drops": ["AU16", "AU17"]},
	"雾栖鹿偶": {"id": "MF_FOREST_M2", "level": 3, "hp": 25, "element": "风", "desc": "园区里的雕塑鹿，大裂断之后开始在雾里自己挪位。", "aux_drops": ["AU18", "AU19"]},
	"霉斑菌傀": {"id": "MF_FOREST_M3", "level": 4, "hp": 30, "element": "地", "desc": "菌房的霉斑一夜之间凝成的人形，孢子随呼吸散开。", "aux_drops": ["AU20", "AU21"]},
	"灼背蜥": {"id": "MF_GRASS_M1", "level": 5, "hp": 30, "element": "火", "desc": "贴着地暖管道晒背的蜥蜴，背脊烫得能点燃落叶。", "aux_drops": ["AU22", "AU23"]},
	"刈草螳": {"id": "MF_GRASS_M2", "level": 6, "hp": 35, "element": "风", "desc": "捡走园丁镰刀的螳螂，双臂快得像一台割草机。", "aux_drops": ["AU24", "AU25"]},
	"灌渠鳞蛇": {"id": "MF_GRASS_M3", "level": 7, "hp": 40, "element": "水", "desc": "在灌溉渠底潜行的青鳞长虫，水面只留一圈涟漪。", "aux_drops": ["AU26", "AU27"]},
	"假山傀儡": {"id": "MF_MINE_M1", "level": 8, "hp": 50, "element": "地", "desc": "枯山水假山站起来了，走路时碎石哗啦作响。", "aux_drops": ["AU28", "AU29"]},
	"暖管蠕虫": {"id": "MF_MINE_M2", "level": 9, "hp": 50, "element": "火", "desc": "钻进地暖管网里的蠕虫，所过之处管道发烫。", "aux_drops": ["AU30", "AU31"]},
	"沥青蝎": {"id": "MF_MINE_M3", "level": 10, "hp": 55, "element": "暗", "desc": "从步道裂缝析出的蝎子，甲壳是半融的沥青。", "aux_drops": ["AU32", "AU33"]},
	"喷泉水灵": {"id": "MF_VALLEY_M1", "level": 11, "hp": 55, "element": "水", "desc": "喷泉池里活过来的水，水柱就是它的拳头。", "aux_drops": ["AU34", "AU35"]},
	"玻璃翼蝶": {"id": "MF_VALLEY_M2", "level": 12, "hp": 55, "element": "风", "desc": "翅膀透明得像温室玻璃，落在哪哪就跟着消失。", "aux_drops": ["AU36", "AU37"]},
	"聚光蜮": {"id": "MF_VALLEY_M3", "level": 13, "hp": 65, "element": "光", "desc": "会聚光的小怪，被它盯上的叶子十秒冒烟。", "aux_drops": ["AU38", "AU39"]},
	"叠石巨人": {"id": "MF_MOUNTAIN_M1", "level": 14, "hp": 65, "element": "地", "desc": "叠石景观一块块码起来的巨人，倒下就散回石头。", "aux_drops": ["AU40", "AU41"]},
	"掠影寒鸦": {"id": "MF_MOUNTAIN_M2", "level": 15, "hp": 60, "element": "暗", "desc": "只在影子的落点停留的鸦，数它的影子比数它容易。", "aux_drops": ["AU42", "AU43"]},
	"贯雾鹰": {"id": "MF_MOUNTAIN_M3", "level": 16, "hp": 70, "element": "风", "desc": "俯冲时能把雾墙撕开一道口的鹰。", "aux_drops": ["AU44", "AU45"]},
	"井穴蜘蛛": {"id": "MF_CAVE_M1", "level": 17, "hp": 70, "element": "暗", "desc": "地下井道里的织网者，井盖就是它的门。", "aux_drops": ["AU46", "AU47"]},
	"锅炉龟": {"id": "MF_CAVE_M2", "level": 18, "hp": 75, "element": "火", "desc": "背甲就是一台小锅炉的龟，生气时压力阀会响。", "aux_drops": ["AU48", "AU49"]},
	"灯诱光蝶": {"id": "MF_CAVE_M3", "level": 19, "hp": 80, "element": "光", "desc": "被园区夜景灯诱变的蝶，绕着灯能转到天亮。", "aux_drops": ["AU50", "AU51"]},
	"古荫": {"id": "MF_BOSS_1", "level": 20, "hp": 100, "element": "地", "desc": "沉雾植物园最深处那棵老树，整座园子的雾都听它的。", "aux_drops": ["AU52", "AU53"]},
	"炉心": {"id": "MF_BOSS_2", "level": 20, "hp": 100, "element": "火", "desc": "温室锅炉里长出的园主分体，把整条暖路烧成火网。", "aux_drops": ["AU52", "AU53"]},
	"夜幕": {"id": "MF_BOSS_3", "level": 20, "hp": 100, "element": "暗", "desc": "只在闭园后睁眼的园主分体，黑暗里所有影子都是它的枝。", "aux_drops": ["AU52", "AU53"]},
	"炎宰": {"id": "FC_BOSS_1", "level": 30, "hp": 150, "element": "火", "desc": "烬燃热电厂自封的主人，炉温就是它的心跳。", "aux_drops": []},
	"熔核": {"id": "FC_BOSS_2", "level": 30, "hp": 150, "element": "火", "desc": "整台熔核机组拼成的巨像，格隆是机身铭牌上的编号。", "aux_drops": []},
	"过热": {"id": "FC_BOSS_3", "level": 30, "hp": 150, "element": "火", "desc": "过热蒸汽凝成的领主，压力表爆表才是它的常态。", "aux_drops": []},
	"过载": {"id": "ST_BOSS_1", "level": 40, "hp": 200, "element": "风", "desc": "雷鸣电视塔的塔主之一，永远处在放电的边缘。", "aux_drops": []},
	"失真": {"id": "ST_BOSS_2", "level": 40, "hp": 200, "element": "风", "desc": "塔主之一，它出现时信号里全是不该有的声音。", "aux_drops": []},
	"惊蛰": {"id": "ST_BOSS_3", "level": 40, "hp": 200, "element": "风", "desc": "塔主之一，每年第一声春雷其实是它在换班。", "aux_drops": []},
	"淤眠": {"id": "SS_BOSS_2", "level": 50, "hp": 250, "element": "暗", "desc": "沉陷湿地公园最深处的沼主，它睡着的这些年湿地又陷了半米。", "aux_drops": []},
	"雾溺": {"id": "SS_BOSS_3", "level": 50, "hp": 250, "element": "暗", "desc": "沼主之一，它吐出的雾能让游泳的人忘记上岸。", "aux_drops": []},
	"典守": {"id": "LR_BOSS_1", "level": 60, "hp": 300, "element": "光", "desc": "圮城博物馆的馆主之一，守着没人来借的档案。", "aux_drops": []},
	"断代": {"id": "LR_BOSS_2", "level": 60, "hp": 300, "element": "光", "desc": "馆主之一，它路过的展柜年代都会错乱。", "aux_drops": []},
	"镇馆": {"id": "LR_BOSS_3", "level": 60, "hp": 300, "element": "光", "desc": "馆主之一，严格来说它自己就是镇馆之宝。", "aux_drops": []},
}

# ===== 采集弹窗长按 =====
var _gather_press_timer: float = 0.0
var _gather_pressed_overlay = null
var _gather_press_start_pos: Vector2 = Vector2.ZERO
var _gather_press_index: int = -1
const GATHER_LONG_PRESS_TIME := 0.5
const GATHER_DRAG_THRESHOLD := 30.0

# ===== 指南弹窗长按 =====
var _guide_press_timer: float = 0.0
var _guide_pressed_label = null
var _guide_press_start_pos: Vector2 = Vector2.ZERO
var _guide_press_index: int = -1
const GUIDE_LONG_PRESS_TIME := 0.5
const GUIDE_DRAG_THRESHOLD := 30.0

# 节点按钮引用
var _node_buttons := []
# 连线专用容器（重画时只需清这个，不影响按钮）
var _line_container: Control = null

# ===== 初始化 =====

func init_map(map_id: String, map_name: String) -> void:
	_map_id = map_id
	_map_name = map_name
	_is_rift = Global.rift_active  # 裂隙局：外层包装换成随机节点图（节点事件全部复用）
	if _is_rift:
		_build_rift_layer_config()
	_generate_nodes()

## 数据侧地图 ID：裂隙局按深度映射区域（怪物池/采集表/BOSS 池全走区域数据）
func _loot_map_id() -> String:
	if _is_rift:
		return Global.rift_depth_to_map(Global.rift_depth)
	return _map_id

## 构建裂隙局层配置：START + 4 个随机中层（总节点 8–12）+ BOSS + EXIT（BOSS 后必连）
## 权重/层数 [PLACEHOLDER]：L4 监控「平均每局战斗数 ∈ [2,3]」与「采集点访问率」
func _build_rift_layer_config() -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = Global.rift_seed  # 局内布局按局种子确定：战斗往返后重建同图（randomize 会覆盖 seed，勿调）
	var target_total := rng.randi_range(8, 12)
	var middle_total := clampi(target_total - 2, 4, 9)  # 去掉 START/BOSS/EXIT 后保底 4 层各 ≥1
	# 把 middle_total 拆成 4 层，每层 1–3
	var counts := [1, 1, 1, 1]
	var extra := middle_total - 4
	for i in range(extra):
		var l := rng.randi_range(0, 3)
		if counts[l] < 3:
			counts[l] += 1
		else:
			counts[(l + 1) % 4] += 1
	var layer_colors := [Color("#5cb85c"), Color("#e8a838"), Color("#3498db"), Color("#8e44ad")]
	var cfg := []
	cfg.append({"name": " 裂隙入口", "y": 0.88, "color": Color("#b07fd4"), "node_count": 1, "is_start": true})
	for i in range(4):
		cfg.append({
			"name": " 虚渊 %d" % (i + 1),
			"y": 0.735 - 0.155 * i,
			"color": layer_colors[i],
			"node_count": counts[i],
			"terrain": RIFT_TERRAINS[(int(Global.rift_depth) + i) % RIFT_TERRAINS.size()],
			"rift_pool": true,
		})
	cfg.append({"name": " 异兽巢穴", "y": 0.13, "color": Color("#e74c3c"), "node_count": 1, "fixed_type": NodeType.BOSS})
	cfg.append({"name": " 撤离点", "y": 0.045, "color": Color("#f0c948"), "node_count": 1, "fixed_type": NodeType.EXIT})
	LAYER_CONFIG = cfg
	print("[裂隙] 深度 ", Global.rift_depth, " 生成节点图：目标 ", target_total, " 实际 ", 2 + middle_total + 1)

func _generate_nodes() -> void:
	_node_data.clear()
	_node_buttons.clear()

	var rng = RandomNumberGenerator.new()
	if _is_rift:
		rng.seed = Global.rift_seed + 1  # 节点类型同局确定（战斗往返不变）
	else:
		rng.randomize()
	
	# 休息层集合：BOSS上一层(暗穴, index 6)固定1个休息点；
	# 第2-3层(树林 index 1 / 草丛 index 2)随机选一层，50%概率生成1个（可能没有）
	var rest_layer_set := {}
	rest_layer_set[LAYER_CONFIG.size() - 2] = true  # BOSS上一层固定
	if rng.randf() < 0.5:
		var early_layer = rng.randi_range(1, 2)  # 树林或草丛
		rest_layer_set[early_layer] = true
	
	print("[MapNode] ===== 开始生成节点 =====")
	print("[MapNode] root Control rect = ", get_rect())
	print("[MapNode] 屏幕 Global.pw(1.0)= ", Global.pw(1.0), " ph(1.0)= ", Global.ph(1.0))
	
	for layer_idx in range(LAYER_CONFIG.size()):
		var layer = LAYER_CONFIG[layer_idx]
		var node_count = layer["node_count"]
		var layer_nodes := []
		var layer_buttons := []
		var is_start_layer = layer.get("is_start", false)
		
		# 普通层类型分配：每层必含1战斗+1采集，第3个随机（战斗/采集）洗牌到左/中/右
		# 若该层是休息层，则把随机位替换为休息点（仍保证1战斗+1采集）
		var layer_types := []
		var x_pos := -1
		if not is_start_layer and node_count > 1:
			layer_types = [NodeType.MONSTER, NodeType.GATHER, NodeType.GATHER]
			x_pos = 2
			if rng.randf() < 0.5:
				layer_types[2] = NodeType.MONSTER
			# Fisher-Yates 洗牌（同步跟踪随机位 x_pos）
			for i in range(layer_types.size() - 1, 0, -1):
				var j = rng.randi_range(0, i)
				if i == x_pos:
					x_pos = j
				elif j == x_pos:
					x_pos = i
				var tmp = layer_types[i]
				layer_types[i] = layer_types[j]
				layer_types[j] = tmp
			if rest_layer_set.has(layer_idx):
				layer_types[x_pos] = NodeType.REST
		
		for node_idx in range(node_count):
			var node_type: NodeType
			var x: float

			if is_start_layer:
				# 起点层
				x = 0.50
				node_type = NodeType.START
			elif node_count == 1:
				# 单节点层：显式 fixed_type 优先（裂隙 EXIT/BOSS），
				# 裂隙中层随机到 1 节点时按权重掷点，普通图保持 BOSS
				x = 0.50
				if layer.has("fixed_type"):
					node_type = layer["fixed_type"]
				elif layer.get("rift_pool", false):
					node_type = _rift_weighted_type(rng)
				else:
					node_type = NodeType.BOSS
			else:
				x = NODE_X_POSITIONS[node_idx]
				# 随机偏移
				x += rng.randf_range(-X_RANDOM_RANGE, X_RANDOM_RANGE)
				x = clamp(x, 0.05, 0.95)
				# 裂隙中层：按 GDD §7.3.2 权重独立掷点（MONSTER/GATHER/REST/EVENT）
				if layer.get("rift_pool", false):
					node_type = _rift_weighted_type(rng)
				else:
					# 从该层已洗牌的类型中取节点类型（必含1战斗+1采集）
					node_type = layer_types[node_idx]
			
			# Y轴随机偏移
			var y_offset = rng.randf_range(-Y_RANDOM_RANGE, Y_RANDOM_RANGE) if not is_start_layer and node_count > 1 else 0.0
			
			# 怪物名预选（缓存完整怪物数据到节点，确保点击时名称与战斗怪物一致）
			var monster_data := {}  # 完整怪物数据（进战斗时直接用，不再重新随机）
			var terrain = layer.get("terrain", "")
			if node_type == NodeType.MONSTER and terrain != "":
				var monsters = Global.get_map_monsters(_loot_map_id(), terrain)
				if monsters.size() > 0:
					var chosen = monsters[rng.randi_range(0, monsters.size() - 1)]
					monster_data = chosen.duplicate(true)
			
			var nd = {
				"type": node_type,
				"x": x,
				"y": layer["y"] + y_offset,
				"layer": layer_idx,
				"index": node_idx,
				"available": false,
				"completed": false,
				"current": false,
				"color": layer["color"],
				"monster_data": monster_data,  # 战斗怪物数据缓存（显示与实际一致）
			}
			layer_nodes.append(nd)
			layer_buttons.append(null)
		
		_node_data.append(layer_nodes)
		_node_buttons.append(layer_buttons)
	
	# 生成动态连接（杀戮尖塔风格，有限扇出）
	_generate_connections()
	
	# 起点标记为已完成（已出发），树林层全部可用
	for node_idx in range(_node_data[0].size()):
		_node_data[0][node_idx]["available"] = true
		_node_data[0][node_idx]["completed"] = true
		_node_data[0][node_idx]["current"] = false
	
	# 第一层（树林）直接可用
	for node_idx in range(_node_data[1].size()):
		_node_data[1][node_idx]["available"] = true

## 生成动态连接（杀戮尖塔风格：每个节点有限扇出，且不交叉）
## 裂隙中层权重掷点（GDD §7.3.2：MONSTER 40 / GATHER 25 / REST 10 / EVENT 15）
func _rift_weighted_type(rng: RandomNumberGenerator) -> NodeType:
	var r := rng.randf()
	var cum := 0.0
	for e in RIFT_TYPE_WEIGHTS:
		cum += e["w"]
		if r <= cum:
			return e["t"]
	return NodeType.MONSTER

func _generate_connections() -> void:
	_connections.clear()
	var rng = RandomNumberGenerator.new()
	if _is_rift:
		rng.seed = Global.rift_seed + 2  # 连接拓扑同局确定（战斗往返不变）
	else:
		rng.randomize()

	for layer_idx in range(LAYER_CONFIG.size() - 1):
		var src_count = _node_data[layer_idx].size()
		var tgt_count = _node_data[layer_idx + 1].size()
		var layer_conn := {}

		for src_idx in range(src_count):
			var targets := []

			if tgt_count == 1:
				# BOSS 层：所有源都连过去
				targets = [0]
			elif src_count == 1:
				# 只有 1 个源（起点/BOSS），全部连到下一层
				for t in range(tgt_count):
					targets.append(t)
			else:
				# 杀戮尖塔风格：每个源节点连 1~2 个目标，带随机偏移
				var base_offset = src_idx  # 0, 1, 2
				var rng_offset = rng.randi_range(-1, 1)
				var start_tgt = clampi(base_offset + rng_offset, 0, tgt_count - 1)
				var conn_count = 2 if start_tgt < tgt_count - 1 else 1
				for i in range(conn_count):
					var tgt = start_tgt + i
					if tgt < tgt_count and not targets.has(tgt):
						targets.append(tgt)

			if targets.size() > 0:
				layer_conn[src_idx] = targets

		_connections.append(layer_conn)

	# 修复死胡同：确保下一层每个节点至少有一条入边
	_fix_dead_ends()


 ## 修复死胡同：从最近且靠右的源节点连过来（尽量避免长交叉线）
func _fix_dead_ends() -> void:
	for layer_idx in range(1, LAYER_CONFIG.size()):
		var tgt_count = _node_data[layer_idx].size()
		if tgt_count <= 1:
			continue
		var reachable := {}
		var prev_conn = _connections[layer_idx - 1]
		for src_idx in prev_conn:
			for tgt_idx in prev_conn[src_idx]:
				reachable[tgt_idx] = true

		if reachable.size() < tgt_count:
			for tgt_idx in range(tgt_count):
				if not reachable.has(tgt_idx):
					# 从编号最接近的源节点连过来
					var best_src = -1
					var best_dist = 999
					var src_count_prev = _node_data[layer_idx - 1].size()
					for src_idx in range(src_count_prev):
						var dist = abs(src_idx - tgt_idx)
						if dist < best_dist:
							best_dist = dist
							best_src = src_idx
					if best_src >= 0:
						if not prev_conn.has(best_src):
							prev_conn[best_src] = []
						if not prev_conn[best_src].has(tgt_idx):
							prev_conn[best_src].append(tgt_idx)
						reachable[tgt_idx] = true
func _ready():
	call_deferred("_apply_theme_styles")
	call_deferred("_build_dynamic_content")
	# 返回按钮信号连接
	var back_btn = get_node_or_null("BackBtn")
	if back_btn is Button:
		back_btn.pressed.connect(_on_back)

func _render_nodes_in_container(container: Control) -> void:
	# 创建连线专用容器（放在按钮下面，重画连线时只需清空这个容器）
	if _line_container:
		_line_container.queue_free()
	_line_container = Control.new()
	_line_container.name = "LineContainer"
	_line_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_line_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(_line_container)
	
	# 先画连线（在按钮下面）
	_draw_connections_in_container(_line_container)
	
	# 再画节点按钮
	for layer_idx in range(_node_data.size()):
		for node_idx in range(_node_data[layer_idx].size()):
			var nd = _node_data[layer_idx][node_idx]
			_create_node_button_in_container(container, nd, layer_idx, node_idx)


## 重画连线（采集/战斗后状态更新时调用）
func _redraw_connections() -> void:
	if not _line_container:
		return
	# 清掉旧的连线节点
	for child in _line_container.get_children():
		child.queue_free()
	# 重新画
	_draw_connections_in_container(_line_container)


func _draw_connections_in_container(container: Control) -> void:
	for layer_idx in range(_connections.size()):
		var conn = _connections[layer_idx]
		for src_idx in range(_node_data[layer_idx].size()):
			var src = _node_data[layer_idx][src_idx]
			var targets = conn.get(src_idx, [])
			for tgt_idx in targets:
				if tgt_idx < _node_data[layer_idx + 1].size():
					var tgt = _node_data[layer_idx + 1][tgt_idx]
					_draw_line_between_in_container(container, src, tgt)


func _draw_line_between_in_container(container: Control, from_node: Dictionary, to_node: Dictionary) -> void:
	# 计算起点和终点的像素坐标
	var x1 = Global.pw(from_node["x"])
	var y1 = Global.ph(from_node["y"])
	var x2 = Global.pw(to_node["x"])
	var y2 = Global.ph(to_node["y"])
	
	# 判断连线状态
	var from_completed = from_node.get("completed", false)
	var from_available = from_node.get("available", false)
	var to_completed = to_node.get("completed", false)
	var to_available = to_node.get("available", false)
	
	# 连线颜色（全部不透明，亮度足够看清）
	var line_color: Color
	if from_completed and to_completed:
		line_color = Color(0.2, 0.7, 0.2, 1.0)  # 深绿（更亮）
	elif (from_completed or from_available) and to_available:
		line_color = Color(0.6, 1.0, 0.5, 1.0)  # 浅绿（更亮）
	else:
		line_color = Color(0.65, 0.65, 0.7, 1.0)  # 亮灰（深色背景上清晰可见）
	
	print("[MapNode] 画连线: (", x1, ",", y1, ") -> (", x2, ",", y2, ") color=", line_color)
	
	# === 弯曲路径：正弦波 S 弯 ===
	var dx = x2 - x1
	var dy = y2 - y1
	var dist = sqrt(dx * dx + dy * dy)
	if dist < 1.0:
		return
	
	# 方向向量 & 垂直向量
	var dir_x = dx / dist
	var dir_y = dy / dist
	var perp_x = -dir_y  # 垂直方向（法线）
	var perp_y = dir_x
	
	# 随机参数：让每条线弯曲不同
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	var curve_amp = rng.randf_range(15.0, 40.0)       # 弯曲幅度（像素）
	var curve_freq = rng.randf_range(1.5, 3.5)         # 弯曲频率（S 弯半个到一个半周期）
	var curve_phase = rng.randf_range(0.0, TAU)        # 随机相位（让弯的方向不固定）
	
	# 沿路径采样点，用正弦波做垂直偏移
	var steps = max(12, int(dist / 8.0))
	var bar_size = 14.0
	for i in range(steps + 1):
		var t = float(i) / float(steps)
		# 基础直线位置
		var base_x = lerp(x1, x2, t)
		var base_y = lerp(y1, y2, t)
		# 正弦波垂直偏移（两端为 0，中间弯曲最大）
		var wave = sin(t * PI * curve_freq + curve_phase) * curve_amp * (1.0 - (2.0 * t - 1.0) ** 2)
		var px = base_x + perp_x * wave
		var py = base_y + perp_y * wave
		
		var dot = ColorRect.new()
		dot.color = line_color
		dot.set_anchors_preset(Control.PRESET_TOP_LEFT)
		dot.position = Vector2(px - bar_size / 2.0, py - bar_size / 2.0)
		dot.size = Vector2(bar_size, bar_size)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		container.add_child(dot)


func _create_node_button_in_container(container: Control, nd: Dictionary, layer_idx: int, node_idx: int) -> void:
	var btn = Button.new()
	btn.name = "NodeBtn_" + str(layer_idx) + "_" + str(node_idx)
	
	# 怪物节点：显示真实怪物名（从节点缓存数据读取，与战斗实际一致）
	var icon = NODE_ICONS[nd["type"]]
	var type_name = NODE_NAMES[nd["type"]]
	
	if nd["type"] == NodeType.MONSTER:
		var mdata = nd.get("monster_data", {})
		if not mdata.is_empty() and mdata.get("name", "") != "":
			type_name = mdata["name"]
	elif nd["type"] == NodeType.GATHER:
		var terrain = LAYER_CONFIG[layer_idx].get("terrain", "")
		if terrain in TERRAIN_GATHER_NAMES:
			type_name = TERRAIN_GATHER_NAMES[terrain]
	
	btn.text = icon + "\n" + type_name
	btn.add_theme_font_size_override("font_size", 30)
	btn.add_theme_constant_override("outline_size", 0)
	
	# 尺寸（固定像素）
	var btn_size = Global.pw(0.14)
	btn.custom_minimum_size = Vector2(btn_size, btn_size)
	
	# 位置：用 set_anchors_preset 先设 anchor=0，再用 position+size
	btn.set_anchors_preset(Control.PRESET_TOP_LEFT)
	var btn_pos = Vector2(Global.pw(nd["x"]) - btn_size / 2.0, Global.ph(nd["y"]) - btn_size / 2.0)
	btn.position = btn_pos
	btn.size = Vector2(btn_size, btn_size)
	print("[MapNode] layer=", layer_idx, " idx=", node_idx, " nd.x=", nd["x"], " nd.y=", nd["y"], " pos=", btn_pos)
	
	# 样式
	_update_button_style(btn, nd)
	
	btn.disabled = not nd["available"]
	btn.pressed.connect(_on_node_pressed.bind(layer_idx, node_idx))
	
	container.add_child(btn)
	_node_buttons[layer_idx][node_idx] = btn


func _update_button_style(btn: Button, nd: Dictionary) -> void:
	var s = StyleBoxFlat.new()
	s.corner_radius_top_left = 50
	s.corner_radius_top_right = 50
	s.corner_radius_bottom_left = 50
	s.corner_radius_bottom_right = 50
	s.border_width_left = 2; s.border_width_right = 2
	s.border_width_top = 2; s.border_width_bottom = 2
	
	if nd["completed"]:
		# 已完成 - 灰色
		s.bg_color = Color(0.2, 0.2, 0.25)
		s.border_color = Color(0.4, 0.4, 0.5)
		btn.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
	elif nd["current"]:
		# 当前节点 - 高亮
		s.bg_color = nd["color"].lightened(0.3)
		s.border_color = Color("#ffffff")
		btn.add_theme_color_override("font_color", Color("#ffffff"))
	elif nd["type"] == NodeType.START:
		# 起点 - 特殊样式
		s.bg_color = Color(0.2, 0.4, 0.2)
		s.border_color = Color("#ffffff")
		btn.add_theme_color_override("font_color", Color("#e8d5b7"))
	elif nd["available"]:
		# 可用 - 正常
		s.bg_color = nd["color"].darkened(0.4)
		s.border_color = nd["color"]
		btn.add_theme_color_override("font_color", Color("#e8d5b7"))
	else:
		# 不可用 - 暗色（字要比底色亮一些，否则在暗背景上完全读不出来）
		s.bg_color = Color(0.1, 0.1, 0.15)
		s.border_color = Color(0.2, 0.2, 0.3)
		btn.add_theme_color_override("font_color", Color(0.56, 0.56, 0.68))
	
	btn.add_theme_stylebox_override("normal", s)
	# 关键：Button 处于 disabled 时画的是 "disabled" 样式。
	# 之前只覆盖了 normal，于是「不可用」这套暗色带边框的配色根本不会生效，
	# 实际显示成主题默认的灰色方块（没有圆角、没有边框，字也灰到看不清）。
	btn.add_theme_stylebox_override("disabled", s)
	btn.add_theme_color_override("font_disabled_color", btn.get_theme_color("font_color"))
	
	# 悬停样式
	var sh = s.duplicate()
	if nd["available"] and not nd["completed"]:
		sh.bg_color = nd["color"].lightened(0.1)
		sh.border_color = Color("#ffffff")
	btn.add_theme_stylebox_override("hover", sh)
	btn.add_theme_stylebox_override("pressed", s)
	btn.add_theme_stylebox_override("focus", s)


func _on_node_pressed(layer_idx: int, node_idx: int) -> void:
	var nd = _node_data[layer_idx][node_idx]
	if not nd["available"] or nd["completed"]:
		return
	
	# 标记为当前节点
	nd["current"] = true
	_current_layer = layer_idx
	_current_node = node_idx
	
	# 更新按钮样式
	var btn = _node_buttons[layer_idx][node_idx]
	_update_button_style(btn, nd)
	
	# 标记为已完成（在切换场景前执行，确保状态保存）
	nd["completed"] = true
	nd["current"] = false
	_update_button_style(btn, nd)
	
	# 禁用同层其他节点（杀戮尖塔式：选了节点后同层其他节点不可用）
	for other_idx in range(_node_data[layer_idx].size()):
		if other_idx != node_idx:
			var other_nd = _node_data[layer_idx][other_idx]
			other_nd["available"] = false
			other_nd["current"] = false
			var other_btn = _node_buttons[layer_idx][other_idx]
			if other_btn:
				other_btn.disabled = true
				_update_button_style(other_btn, other_nd)
	
	# 更新下一层的可用节点（在切换场景前执行）
	_update_next_layer_availability(layer_idx, node_idx)
	
	# 重画连线（采集/战斗后状态已变，连线颜色需要刷新）
	_redraw_connections.call_deferred()
	
	# 更新信息标签
	_update_info_label()
	
	# 滚动到当前层居中
	_scroll_to_layer(layer_idx)
	
	# 根据节点类型触发事件（可能切换场景）
	match nd["type"]:
		NodeType.MONSTER:
			_trigger_monster_event(layer_idx, node_idx)
		NodeType.GATHER:
			_trigger_gather_event(layer_idx, node_idx)
		NodeType.REST:
			_trigger_rest_event(layer_idx, node_idx)
		NodeType.BOSS:
			_trigger_boss_event(layer_idx, node_idx)
		NodeType.EMPTY:
			_trigger_rift_event(layer_idx, node_idx)
		NodeType.EXIT:
			_trigger_exit_event(layer_idx, node_idx)


## 裂隙异事节点（EVENT，复用 EMPTY 承载 · GDD §7.3.2）：
## 随机取舍小事件 [PLACEHOLDER]，L4 依「事件访问率」调内容池。
## v1 三选一：灵质涌动（白拿 1 素材）/ 虚渊赌局（50% 双倍 or 空手）/ 余烬（回复 20% HP）
func _trigger_rift_event(layer_idx: int, node_idx: int) -> void:
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	var roll := rng.randi_range(0, 2)
	match roll:
		0:
			# 灵质涌动：从当前区域采集表随机 1 个素材
			var mats = Global.get_gather_materials(_loot_map_id(), LAYER_CONFIG[layer_idx].get("terrain", ""))
			if mats.size() > 0:
				var m = mats[rng.randi_range(0, mats.size() - 1)]
				var ok := Global.rift_add_loot("material", m.get("material_id", ""), m.get("name", "素材"), 1)
				_show_rift_event_result("灵质涌动", ("拾得 %s x1" % m.get("name", "素材")) if ok else "背包已满，素材消散了")
			else:
				_show_rift_event_result("灵质涌动", "裂缝间只有风声")
		1:
			# 虚渊赌局：50% 双倍最近一堆 / 50% 空手
			if Global.rift_backpack.size() > 0 and rng.randf() < 0.5:
				var it = Global.rift_backpack[rng.randi_range(0, Global.rift_backpack.size() - 1)]
				it["amount"] += it["amount"]
				_show_rift_event_result("虚渊赌局", "赌赢了！%s 翻倍 → x%d" % [it["name"], it["amount"]])
			else:
				_show_rift_event_result("虚渊赌局", "虚渊沉默着，什么也没给")
		2:
			var heal := ceili(Global.current_run_player_max_hp * 0.2)
			var old_hp := Global.current_run_player_hp
			Global.current_run_player_hp = mini(old_hp + heal, Global.current_run_player_max_hp)
			_show_rift_event_result("余烬", "拾起异兽余烬，回复 %d 点生命" % (Global.current_run_player_hp - old_hp))
	_mark_node_completed(layer_idx, node_idx)


## 裂隙撤离节点（EXIT · GDD §7.3.3）：素材全额带出 + BOSS 首通奖励
func _trigger_exit_event(layer_idx: int, node_idx: int) -> void:
	var result = Global.rift_settle_exit()
	var lines := ["背包素材全额带出（%d 件）" % result["brought"]]
	if result["first_clear_gold"] > 0:
		lines.append("首通 Rift %d！金币 +%d" % [Global.rift_depth, result["first_clear_gold"]])
	_show_rift_event_result("撤离成功", "\n".join(lines), true)


## 异事/撤离结果弹窗（leave_scene=true 时确认后回主城）
func _show_rift_event_result(title: String, body: String, leave_scene := false) -> void:
	var overlay = ColorRect.new()
	overlay.color = Color(0.0, 0.0, 0.0, 0.65)
	overlay.anchor_left = 0.0; overlay.anchor_top = 0.0
	overlay.anchor_right = 1.0; overlay.anchor_bottom = 1.0
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	var panel = Panel.new()
	panel.anchor_left = 0.5; panel.anchor_top = 0.5
	panel.anchor_right = 0.5; panel.anchor_bottom = 0.5
	panel.offset_left = -Global.pw(0.36); panel.offset_right = Global.pw(0.36)
	panel.offset_top = -Global.ph(0.16); panel.offset_bottom = Global.ph(0.16)
	overlay.add_child(panel)
	var vb = VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.offset_left = 24; vb.offset_right = -24; vb.offset_top = 20; vb.offset_bottom = -20
	vb.add_theme_constant_override("separation", 14)
	panel.add_child(vb)
	var tl = Label.new()
	tl.text = title
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.add_theme_font_size_override("font_size", 44)
	vb.add_child(tl)
	var bl = Label.new()
	bl.text = body
	bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bl.add_theme_font_size_override("font_size", 30)
	vb.add_child(bl)
	var btn = Button.new()
	btn.text = "确定"
	btn.custom_minimum_size = Vector2(0, Global.ph(0.06))
	btn.pressed.connect(func():
		overlay.queue_free()
		if leave_scene:
			Global.change_scene("res://Main.tscn"))
	vb.add_child(btn)


## 标记节点完成并解锁下层（复用现有推进逻辑）
func _mark_node_completed(layer_idx: int, node_idx: int) -> void:
	var nd = _node_data[layer_idx][node_idx]
	nd["completed"] = true
	nd["current"] = false
	var btn = _node_buttons[layer_idx][node_idx]
	if btn != null:
		_update_button_style(btn, nd)
	_update_next_layer_availability(layer_idx, node_idx)
	_update_title_with_progress()


func _update_next_layer_availability(layer_idx: int, node_idx: int) -> void:
	if layer_idx >= _connections.size():
		return  # 已经是最后一层
	
	var conn = _connections[layer_idx]
	var targets = conn.get(node_idx, [])
	
	for tgt_idx in targets:
		if tgt_idx < _node_data[layer_idx + 1].size():
			var nd = _node_data[layer_idx + 1][tgt_idx]
			nd["available"] = true
			var btn = _node_buttons[layer_idx + 1][tgt_idx]
			if btn:
				btn.disabled = false
				_update_button_style(btn, nd)


func _trigger_monster_event(layer_idx: int, node_idx: int) -> void:
	var layer_name = LAYER_CONFIG[layer_idx]["name"]
	var terrain = LAYER_CONFIG[layer_idx].get("terrain", "")
	print("[爬塔] 战斗！在 ", layer_name, " 遭遇野怪！")
	
	# 直接使用节点生成时缓存的怪物数据（保证地图显示与战斗实际一致）
	var node_data = _node_data[layer_idx][node_idx]
	var monster_data = node_data.get("monster_data", {})
	if not monster_data.is_empty():
		Global.current_enemy_data = monster_data.duplicate(true)
		print("[爬塔] 选定卡兽: ", monster_data.get("name", "未知"), " (Lv.", monster_data.get("level", 0), ")")
	else:
		# 兼容旧存档/异常兜底：从敌人数据中随机选一个卡兽
		var monsters = Global.get_map_monsters(_loot_map_id(), terrain)
		if monsters.size() > 0:
			var rng = RandomNumberGenerator.new()
			rng.randomize()
			var chosen = monsters[rng.randi_range(0, monsters.size() - 1)]
			Global.current_enemy_data = chosen.duplicate(true)
			print("[爬塔] 选定卡兽: ", chosen.get("name", "未知"), " (Lv.", chosen.get("level", 0), ")")
		else:
			# 没有找到对应数据时使用默认
			Global.current_enemy_data = {
				"name": "野怪",
				"hp": 20, "max_hp": 20,
				"energy": 3, "max_energy": 3,
				"deck": []
			}
			print("[爬塔] 警告：未找到卡兽数据，使用默认野怪")
	
	# 进入战斗场景
	# 保存节点状态（用于战斗后恢复）
	Global.saved_map_node_data = []
	for li in range(_node_data.size()):
		var layer_save := []
		for ni in range(_node_data[li].size()):
			var nd = _node_data[li][ni]
			layer_save.append({
				"available": nd["available"],
				"completed": nd["completed"],
				"current": nd["current"]
			})
		Global.saved_map_node_data.append(layer_save)
	
	Global.current_map_id = _loot_map_id()
	Global.current_rift_map_id = _map_id
	Global.current_map_name = _map_name + " - " + layer_name
	Global.current_battle_terrain = terrain
	Global.current_map_layer = layer_idx  # 保存当前层数，战斗后返回用
	Global.current_map_node = node_idx   # 保存当前节点索引，战斗后滚动到该节点位置
	Global.current_is_boss = false
	Global.change_scene(Global.get_battle_scene_path())

## 休息节点：恢复50%血量
func _trigger_rest_event(layer_idx: int, node_idx: int) -> void:
	var layer_name = LAYER_CONFIG[layer_idx]["name"]
	print("[爬塔]  在 ", layer_name, " 休息！")
	
	# 恢复50%最大HP
	var heal_amount = ceil(Global.current_run_player_max_hp * 0.5)
	var old_hp = Global.current_run_player_hp
	Global.current_run_player_hp = mini(old_hp + heal_amount, Global.current_run_player_max_hp)
	var actual_heal = Global.current_run_player_hp - old_hp
	print("[爬塔] 恢复 ", actual_heal, " 点HP (", old_hp, "→", Global.current_run_player_hp, ")")
	
	# 显示休息结果弹窗
	_show_rest_result(heal_amount, actual_heal, layer_name)

func _show_rest_result(max_heal: int, actual_heal: int, layer_name: String) -> void:
	# 遮罩
	var overlay = ColorRect.new()
	overlay.color = Color(0.0, 0.0, 0.0, 0.65)
	overlay.anchor_left = 0.0; overlay.anchor_top = 0.0
	overlay.anchor_right = 1.0; overlay.anchor_bottom = 1.0
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.gui_input.connect(_on_rest_overlay_clicked.bind(overlay))
	add_child(overlay)
	
	var panel = Panel.new()
	var ps = StyleBoxFlat.new()
	ps.bg_color = Color(0.12, 0.10, 0.18)
	ps.corner_radius_top_left = 20; ps.corner_radius_top_right = 20
	ps.corner_radius_bottom_left = 20; ps.corner_radius_bottom_right = 20
	ps.border_width_left = 2; ps.border_width_right = 2
	ps.border_width_top = 2; ps.border_width_bottom = 2
	ps.border_color = Color(0.3, 0.7, 0.3)
	panel.add_theme_stylebox_override("panel", ps)
	panel.anchor_left = 0.0; panel.anchor_top = 0.0
	panel.anchor_right = 1.0; panel.anchor_bottom = 1.0
	panel.offset_left = Global.pw(0.15); panel.offset_top = Global.ph(0.32)
	panel.offset_right = Global.pw(-0.15); panel.offset_bottom = -Global.ph(0.32)
	overlay.add_child(panel)
	
	var title = Label.new()
	title.text = "休息"
	title.add_theme_font_size_override("font_size", 55)
	title.add_theme_color_override("font_color", Color("#7ddf7d"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.anchor_left = 0.0; title.anchor_top = 0.0
	title.anchor_right = 1.0; title.anchor_bottom = 0.0
	title.offset_left = 0; title.offset_top = Global.ph(0.05)
	title.offset_right = 0; title.offset_bottom = Global.ph(0.15)
	panel.add_child(title)
	
	var info = Label.new()
	info.text = "HP恢复 +" + str(actual_heal) + "\n" + str(Global.current_run_player_hp) + "/" + str(Global.current_run_player_max_hp)
	info.add_theme_font_size_override("font_size", 45)
	info.add_theme_color_override("font_color", Color("#e8d5b7"))
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	info.anchor_left = 0.0; info.anchor_top = 0.0
	info.anchor_right = 1.0; info.anchor_bottom = 1.0
	info.offset_left = 0; info.offset_top = Global.ph(0.18)
	info.offset_right = 0; info.offset_bottom = -Global.ph(0.18)
	panel.add_child(info)
	
	var confirm_btn = Button.new()
	confirm_btn.text = "继续前进"
	confirm_btn.add_theme_font_size_override("font_size", 42)
	var cs = StyleBoxFlat.new()
	cs.bg_color = Color(0.2, 0.3, 0.2)
	cs.border_width_left = 2; cs.border_width_right = 2
	cs.border_width_top = 2; cs.border_width_bottom = 2
	cs.border_color = Color(0.3, 0.7, 0.3)
	cs.corner_radius_top_left = 12; cs.corner_radius_top_right = 12
	cs.corner_radius_bottom_left = 12; cs.corner_radius_bottom_right = 12
	cs.content_margin_left = 30; cs.content_margin_right = 30
	confirm_btn.add_theme_stylebox_override("normal", cs)
	confirm_btn.add_theme_color_override("font_color", Color("#e8d5b7"))
	confirm_btn.anchor_left = 0.0; confirm_btn.anchor_top = 1.0
	confirm_btn.anchor_right = 1.0; confirm_btn.anchor_bottom = 1.0
	confirm_btn.offset_left = Global.pw(0.2); confirm_btn.offset_top = -Global.ph(0.12)
	confirm_btn.offset_right = Global.pw(-0.2); confirm_btn.offset_bottom = -Global.ph(0.04)
	confirm_btn.pressed.connect(func(): overlay.queue_free())
	panel.add_child(confirm_btn)

func _trigger_gather_event(layer_idx: int, node_idx: int) -> void:
	var layer_name = LAYER_CONFIG[layer_idx]["name"]
	var terrain = LAYER_CONFIG[layer_idx].get("terrain", "")
	var terrain_icon = TERRAIN_ICONS.get(terrain, "")
	var gather_name = TERRAIN_GATHER_NAMES.get(terrain, "采集")
	
	print("[爬塔] 采集！在 ", layer_name, " 进行", gather_name, "！")
	
	# 彩蛋：10%概率触发伏击（对手从决斗场对手池中随机选，战胜后双倍掉落）
	Global.current_is_ambush = false
	var ambush_rng = RandomNumberGenerator.new()
	ambush_rng.randomize()
	if ambush_rng.randf() < 0.05:
		print("[爬塔]  采集时遭遇伏击！")
		
		# 收集对手池（同决斗场逻辑：服务器卡组 + 本机其他卡组）
		var pool := []
		for sdeck in Global.server_decks:
			var dd = sdeck.get("deck_data", {})
			if dd.size() > 0:
				var has_cards = dd.get("cards", []).size() > 0 or dd.get("card_datas", []).size() > 0
				if has_cards:
					pool.append(dd)
		var local_decks = CardManager.get_all_decks()
		for did in local_decks:
			if did == Global.current_deck_id:
				continue
			var ld = local_decks[did]
			if ld.get("cards", []).size() > 0:
				pool.append(ld)
		
		var fallback_used := false
		if pool.size() == 0:
			var own_deck = CardManager.get_deck(Global.current_deck_id)
			if own_deck.get("cards", []).size() > 0:
				pool.append(own_deck)
				fallback_used = true
				print("[爬塔] 伏击：对手池为空，回退使用自己的卡组作为对手")
			else:
				print("[爬塔] 伏击：没有可用对手卡组，跳过伏击")
		
		if pool.size() > 0:
			var chosen = pool[ambush_rng.randi_range(0, pool.size() - 1)]
			var opp_name = chosen.get("name", "未知卡组")
			if fallback_used:
				opp_name = "镜像·" + opp_name
			
			# 解析对手卡牌
			var card_datas := []
			var full_cards = chosen.get("card_datas", [])
			if full_cards is Array and full_cards.size() > 0:
				card_datas = full_cards.duplicate(true)
			else:
				var card_ids = chosen.get("cards", [])
				var all_cards = CardManager.get_all_cards()
				for cid in card_ids:
					var found = false
					for card_data in all_cards:
						if card_data.get("id", "") == cid or card_data.get("template_id", "") == cid:
							card_datas.append(card_data.duplicate(true))
							found = true
							break
					if not found:
						print("[爬塔] 伏击：找不到卡牌ID: ", cid)
			
			if card_datas.size() > 0:
				Global.current_enemy_data = {
					"name": "伏击者·" + opp_name,
					"hp": 50,
					"max_hp": 50,
					"energy": 3,
					"max_energy": 3,
					"card_datas": card_datas
				}
				Global.current_is_ambush = true
				print("[爬塔] 伏击者: ", opp_name, " (", card_datas.size(), "张卡)")
				
				# 保存节点状态（用于战斗后恢复）
				Global.saved_map_node_data = []
				for li in range(_node_data.size()):
					var layer_save := []
					for ni in range(_node_data[li].size()):
						var nd = _node_data[li][ni]
						layer_save.append({
							"available": nd["available"],
							"completed": nd["completed"],
							"current": nd["current"]
						})
					Global.saved_map_node_data.append(layer_save)
				
				Global.current_map_id = _loot_map_id()
				Global.current_rift_map_id = _map_id
				Global.current_map_name = _map_name + " - " + layer_name + "（伏击）"
				Global.current_battle_terrain = terrain
				Global.current_map_layer = layer_idx
				Global.current_map_node = node_idx
				Global.current_is_boss = false
				Global.change_scene(Global.get_battle_scene_path())
				return
	
	# 获取该地图该地形可采集的素材
	var available_materials = Global.get_gather_materials(_loot_map_id(), terrain)
	
	if available_materials.size() == 0:
		print("[爬塔] 警告：", _map_name, " 的 ", layer_name, " 没有可采集的素材")
		_show_gather_result([], layer_name, terrain_icon, gather_name)
		return
	
	# 随机采集：先roll数量1~3，再按概率判定，保底至少1个
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	var gained := []
	var drop_count = rng.randi_range(1, 3)  # 期望掉落1~3个
	
	# 按概率判定每个素材是否掉落
	var passed := []
	for mat in available_materials:
		var prob = mat.get("prob", 0.5)
		if rng.randf() < prob:
			passed.append(mat)
	
	# 如果通过的素材太多，随机选drop_count个
	if passed.size() > drop_count:
		passed.shuffle()
		passed.resize(drop_count)
	# 如果通过的素材太少（甚至0个），保底
	elif passed.size() == 0:
		# 从全部素材中按概率权重选一个作为保底
		var weights := []
		var total_weight := 0.0
		for mat in available_materials:
			var w = mat.get("prob", 0.5)
			weights.append(w)
			total_weight += w
		var r = rng.randf() * total_weight
		var cum := 0.0
		for idx in range(available_materials.size()):
			cum += weights[idx]
			if r <= cum:
				passed.append(available_materials[idx])
				break
	
	# 发放掉落
	for mat in passed:
		var amount = 1
		var min_amt = mat.get("min", 1)
		var max_amt = mat.get("max", 1)
		if min_amt != max_amt:
			amount = rng.randi_range(min_amt, max_amt)
		WarehouseManager.add_material(mat["material_id"], amount)
		gained.append({
			"material_id": mat["material_id"],
			"name": mat["name"],
			"rarity": mat["rarity"],
			"amount": amount,
		})
		print("[爬塔] 采集获得: ", mat["name"], " x", amount)
	
	# 显示采集结果弹窗
	_show_gather_result(gained, layer_name, terrain_icon, gather_name)

func _trigger_boss_event(layer_idx: int, node_idx: int) -> void:
	print("[爬塔] BOSS战！")
	
	# 加载BOSS数据
	var boss_data = Global.get_map_boss(_loot_map_id())
	if boss_data.size() > 0:
		Global.current_enemy_data = boss_data.duplicate(true)
		print("[爬塔] BOSS: ", boss_data.get("name", "未知"))
	else:
		print("[爬塔] 警告：未找到BOSS数据，使用默认野怪")
		Global.current_enemy_data = {
			"name": "BOSS",
			"hp": 50, "max_hp": 50,
			"energy": 4, "max_energy": 4,
			"deck": []
		}
	
	# 保存节点状态
	Global.saved_map_node_data = []
	for li in range(_node_data.size()):
		var layer_save := []
		for ni in range(_node_data[li].size()):
			var nd = _node_data[li][ni]
			layer_save.append({
				"available": nd["available"],
				"completed": nd["completed"],
				"current": nd["current"]
			})
		Global.saved_map_node_data.append(layer_save)
	
	Global.current_map_id = _loot_map_id()
	Global.current_rift_map_id = _map_id
	Global.current_map_name = _map_name + " - BOSS战"
	Global.current_battle_terrain = ""
	Global.current_map_layer = layer_idx
	Global.current_map_node = node_idx
	Global.current_is_boss = true
	Global.change_scene(Global.get_battle_scene_path())


func _show_gather_result(gained: Array, layer_name: String, terrain_icon: String, gather_name: String) -> void:
	# 遮罩（半透明，关闭点击）
	var overlay = ColorRect.new()
	overlay.name = "GatherOverlay"
	overlay.color = Color(0.0, 0.0, 0.0, 0.65)
	overlay.anchor_left = 0.0; overlay.anchor_top = 0.0
	overlay.anchor_right = 1.0; overlay.anchor_bottom = 1.0
	overlay.mouse_filter = MOUSE_FILTER_STOP
	add_child(overlay)
	
	# 弹窗面板 — 使用Panel+StyleBoxFlat，不透明背景
	var panel = Panel.new()
	panel.name = "GatherPanel"
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.12, 0.10, 0.18)  # 不透明深色背景
	panel_style.corner_radius_top_left = 20; panel_style.corner_radius_top_right = 20
	panel_style.corner_radius_bottom_left = 20; panel_style.corner_radius_bottom_right = 20
	panel_style.border_width_left = 2; panel_style.border_width_right = 2
	panel_style.border_width_top = 2; panel_style.border_width_bottom = 2
	panel_style.border_color = Color(0.5, 0.4, 0.7)
	panel.add_theme_stylebox_override("panel", panel_style)
	panel.anchor_left = 0.0; panel.anchor_top = 0.0
	panel.anchor_right = 1.0; panel.anchor_bottom = 1.0
	panel.offset_left = Global.pw(0.08); panel.offset_top = Global.ph(0.22)
	panel.offset_right = Global.pw(-0.08); panel.offset_bottom = -Global.ph(0.22)
	overlay.add_child(panel)
	
	# 标题
	var title_label = Label.new()
	title_label.text = terrain_icon + " " + layer_name + " · " + gather_name
	title_label.add_theme_font_size_override("font_size", 55)
	title_label.add_theme_color_override("font_color", Color("#f9d371"))
	title_label.add_theme_color_override("font_shadow_color", Color("#000000"))
	title_label.add_theme_constant_override("shadow_offset_x", 2)
	title_label.add_theme_constant_override("shadow_offset_y", 2)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.anchor_left = 0.0; title_label.anchor_top = 0.0
	title_label.anchor_right = 1.0; title_label.anchor_bottom = 0.0
	title_label.offset_left = 0; title_label.offset_top = Global.ph(0.02)
	title_label.offset_right = 0; title_label.offset_bottom = Global.ph(0.08)
	panel.add_child(title_label)
	
	# 分隔线
	var line = ColorRect.new()
	line.color = Color(1.0, 1.0, 1.0, 0.15)
	line.anchor_left = 0.0; line.anchor_top = 0.0
	line.anchor_right = 1.0; line.anchor_bottom = 0.0
	line.offset_left = Global.pw(0.05); line.offset_top = Global.ph(0.085)
	line.offset_right = Global.pw(-0.05); line.offset_bottom = Global.ph(0.09)
	panel.add_child(line)
	
	if gained.size() == 0:
		var empty_label = Label.new()
		empty_label.text = "这里什么也没有..."
		empty_label.add_theme_font_size_override("font_size", 45)
		empty_label.add_theme_color_override("font_color", Color("#5a5a6e"))
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty_label.anchor_left = 0.0; empty_label.anchor_top = 0.0
		empty_label.anchor_right = 1.0; empty_label.anchor_bottom = 0.0
		empty_label.offset_left = 0; empty_label.offset_top = Global.ph(0.12)
		empty_label.offset_right = 0; empty_label.offset_bottom = Global.ph(0.35)
		panel.add_child(empty_label)
	else:
		# 采集结果副标题
		var result_title = Label.new()
		result_title.text = "采集获得："
		result_title.add_theme_font_size_override("font_size", 45)
		result_title.add_theme_color_override("font_color", Color("#e8d5b7"))
		result_title.anchor_left = 0.0; result_title.anchor_top = 0.0
		result_title.anchor_right = 1.0; result_title.anchor_bottom = 0.0
		result_title.offset_left = Global.pw(0.06); result_title.offset_top = Global.ph(0.10)
		result_title.offset_right = 0; result_title.offset_bottom = Global.ph(0.15)
		panel.add_child(result_title)
		
		# 素材列表容器（可滚动）
		var scroll = ScrollContainer.new()
		scroll.name = "GatherScroll"
		scroll.anchor_left = 0.0; scroll.anchor_top = 0.0
		scroll.anchor_right = 1.0; scroll.anchor_bottom = 1.0
		scroll.offset_left = Global.pw(0.03); scroll.offset_top = Global.ph(0.15)
		scroll.offset_right = Global.pw(-0.03); scroll.offset_bottom = -Global.ph(0.15)
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
		panel.add_child(scroll)
		
		var vbox = VBoxContainer.new()
		vbox.name = "GatherVBox"
		vbox.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
		vbox.custom_minimum_size = Vector2(Global.pw(0.70), 0)
		scroll.add_child(vbox)
		
		# 每个素材作为一行可交互Panel
		var row_index := 0
		for g in gained:
			var rarity_color = Color("#e8d5b7")
			match g.get("rarity", "普通"):
				"传说": rarity_color = Color("#f9d371")
				"史诗": rarity_color = Color("#c084fc")
				"稀有": rarity_color = Color("#60a5fa")
			
			var row = Panel.new()
			row.name = "GatherRow"
			var row_style = StyleBoxFlat.new()
			row_style.bg_color = Color(0.17, 0.15, 0.22) if row_index % 2 == 0 else Color(0.13, 0.11, 0.17)
			row_style.corner_radius_top_left = 8; row_style.corner_radius_top_right = 8
			row_style.corner_radius_bottom_left = 8; row_style.corner_radius_bottom_right = 8
			row.add_theme_stylebox_override("panel", row_style)
			row.custom_minimum_size = Vector2(0, Global.ph(0.065))
			row.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
			row.mouse_filter = MOUSE_FILTER_STOP
			# 存储素材数据用于长按
			row.set_meta("material_id", g.get("material_id", ""))
			row.set_meta("gather_data", g)
			row.set_meta("row_index", row_index)
			vbox.add_child(row)
			
			# 行内水平布局
			var hbox = HBoxContainer.new()
			hbox.anchor_left = 0.0; hbox.anchor_top = 0.0
			hbox.anchor_right = 1.0; hbox.anchor_bottom = 1.0
			hbox.offset_left = Global.pw(0.03); hbox.offset_top = 0
			hbox.offset_right = Global.pw(-0.03); hbox.offset_bottom = 0
			hbox.mouse_filter = MOUSE_FILTER_IGNORE
			row.add_child(hbox)
			
			# 素材名称
			var name_label = Label.new()
			name_label.text = g["name"]
			name_label.add_theme_font_size_override("font_size", 42)
			name_label.add_theme_color_override("font_color", rarity_color)
			name_label.size_flags_horizontal = SIZE_EXPAND
			hbox.add_child(name_label)
			
			# 数量
			var count_label = Label.new()
			count_label.text = "x" + str(int(g["amount"]))
			count_label.add_theme_font_size_override("font_size", 42)
			count_label.add_theme_color_override("font_color", rarity_color)
			count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			count_label.custom_minimum_size = Vector2(Global.pw(0.1), 0)
			hbox.add_child(count_label)
			
			row_index += 1
		
		# 底部留白
		var spacer = Control.new()
		spacer.custom_minimum_size = Vector2(0, Global.ph(0.02))
		vbox.add_child(spacer)
	
	# 确认按钮
	var confirm_btn = Button.new()
	confirm_btn.text = "确认"
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
	confirm_btn.pressed.connect(_on_gather_confirm.bind(overlay))
	panel.add_child(confirm_btn)


func _on_gather_confirm(overlay: ColorRect) -> void:
	overlay.queue_free()
	# 弹窗关闭后重画连线（确保颜色更新可见）
	_redraw_connections.call_deferred()
## 休息弹窗点击关闭
func _on_rest_overlay_clicked(event: InputEvent, overlay: ColorRect) -> void:
	if event is InputEventScreenTouch and not event.pressed:
		overlay.queue_free()
		_redraw_connections.call_deferred()
# ===== 采集弹窗长按检测 =====

func _process(_delta: float) -> void:
	if _gather_pressed_overlay != null:
		_gather_press_timer += _delta
		if _gather_press_timer >= GATHER_LONG_PRESS_TIME:
			_show_gather_material_detail(_gather_pressed_overlay)
			_gather_cancel_press()
	if _guide_pressed_label != null:
		_guide_press_timer += _delta
		if _guide_press_timer >= GUIDE_LONG_PRESS_TIME:
			_show_guide_material_detail(_guide_pressed_label)
			_guide_cancel_press()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			# 查找采集弹窗中的素材行
			var row = _find_gather_row_at(event.position)
			if row != null:
				_gather_pressed_overlay = row
				_gather_press_timer = 0.0
				_gather_press_start_pos = event.position
				_gather_press_index = event.index
				# 高亮行
				var sb = StyleBoxFlat.new()
				sb.bg_color = Color(0.25, 0.20, 0.35)
				sb.corner_radius_top_left = 8; sb.corner_radius_top_right = 8
				sb.corner_radius_bottom_left = 8; sb.corner_radius_bottom_right = 8
				row.add_theme_stylebox_override("panel", sb)
			else:
				# 查找指南弹窗中的素材Label
				var label = _find_guide_material_label_at(event.position)
				if label != null:
					_guide_pressed_label = label
					_guide_press_timer = 0.0
					_guide_press_start_pos = event.position
					_guide_press_index = event.index
					label.add_theme_color_override("font_color", Color("#FFD700"))
		else:
			if event.index == _gather_press_index:
				_gather_cancel_press()
			if event.index == _guide_press_index:
				_guide_cancel_press()
	
	elif event is InputEventScreenDrag:
		if _gather_pressed_overlay != null and event.index == _gather_press_index:
			var dist = event.position.distance_to(_gather_press_start_pos)
			if dist > GATHER_DRAG_THRESHOLD:
				_gather_cancel_press()
		if _guide_pressed_label != null and event.index == _guide_press_index:
			var dist = event.position.distance_to(_guide_press_start_pos)
			if dist > GUIDE_DRAG_THRESHOLD:
				_guide_cancel_press()


func _find_gather_row_at(pos: Vector2) -> Control:
	var overlay = get_node_or_null("GatherOverlay")
	if not overlay:
		return null
	var panel = overlay.get_node_or_null("GatherPanel")
	if not panel:
		return null
	var scroll = panel.get_node_or_null("GatherScroll")
	if not scroll:
		return null
	var vbox = scroll.get_node_or_null("GatherVBox")
	if not vbox:
		return null
	for child in vbox.get_children():
		if child is Panel and child.has_meta("material_id"):
			var rect = Rect2(child.get_global_rect().position, child.get_global_rect().size)
			if rect.has_point(pos):
				return child
	return null


func _gather_cancel_press() -> void:
	if _gather_pressed_overlay != null:
		var idx = _gather_pressed_overlay.get_meta("row_index", 0)
		var sb = StyleBoxFlat.new()
		sb.bg_color = Color(0.17, 0.15, 0.22) if idx % 2 == 0 else Color(0.13, 0.11, 0.17)
		sb.corner_radius_top_left = 8; sb.corner_radius_top_right = 8
		sb.corner_radius_bottom_left = 8; sb.corner_radius_bottom_right = 8
		_gather_pressed_overlay.add_theme_stylebox_override("panel", sb)
	_gather_pressed_overlay = null
	_gather_press_timer = 0.0
	_gather_press_index = -1


func _show_gather_material_detail(row: Control) -> void:
	var material_id = row.get_meta("material_id", "")
	if material_id == "":
		return
	
	var mat_data := Global.get_material_by_id(material_id)
	if mat_data.is_empty():
		return
	
	# 获取素材完整信息
	var name_str: String = mat_data.get("name", "未知")
	var rarity: String = mat_data.get("rarity", "普通")
	var area: String = mat_data.get("area", "未知")
	var tendency: String = mat_data.get("tendency", "")
	if tendency == "":
		tendency = "无"
	
	# 确定分类
	var category := "未知"
	if material_id.begins_with("F"): category = "纤维"
	elif material_id.begins_with("M"): category = "矿粉"
	elif material_id.begins_with("R"): category = "树脂"
	elif material_id.begins_with("E"): category = "萃取液"
	elif material_id.begins_with("P"): category = "颜料"
	elif material_id.begins_with("B"): category = "粘合剂"
	
	# 构建属性文本
	var props_text := ""
	match category:
		"纤维":
			var carry = mat_data.get("carry", 0)
			var tough = mat_data.get("toughness", 0)
			props_text = "承载力: " + str(carry) + "  韧性: " + str(tough)
		"矿粉":
			var stab = mat_data.get("stability", 0)
			var hard = mat_data.get("hardness", 0)
			props_text = "稳定性: " + str(stab) + "  硬度: " + str(hard)
		"树脂":
			var bond = mat_data.get("bond", 0)
			var gloss = mat_data.get("gloss", 0)
			props_text = "粘合度: " + str(bond) + "  光泽: " + str(gloss)
		"萃取液":
			var cond = mat_data.get("conductivity", 0)
			var pur = mat_data.get("purity", 0)
			props_text = "传导性: " + str(cond) + "  纯度: " + str(pur)
		"颜料":
			var adh = mat_data.get("adhesion", 0)
			var chr = mat_data.get("chromatography", 0)
			props_text = "附着力: " + str(adh) + "  显色: " + str(chr)
		"粘合剂":
			var har = mat_data.get("harmony", 0)
			props_text = "调和度: " + str(har)
	
	var rarity_color := Color("#e8d5b7")
	match rarity:
		"传说": rarity_color = Color("#f9d371")
		"史诗": rarity_color = Color("#c084fc")
		"稀有": rarity_color = Color("#60a5fa")
	
	# 获取采集地图信息
	var gather_text := ""
	var gather_data = mat_data.get("gather", {})
	for map_id in gather_data.keys():
		for entry in gather_data[map_id]:
			var terrain = entry.get("terrain", "")
			if gather_text != "":
				gather_text += "\n"
			var map_name = MAP_NAMES.get(map_id, map_id)
			var terrain_name = TERRAIN_NAMES.get(terrain, terrain)
			var terrain_icon = TERRAIN_ICONS.get(terrain, "")
			gather_text += map_name + " · " + terrain_icon + " " + terrain_name
	
	# ---- 弹窗控件 ----
	var overlay = ColorRect.new()
	overlay.name = "GatherDetailOverlay"
	overlay.color = Color(0.0, 0.0, 0.0, 0.6)
	overlay.anchor_left = 0.0; overlay.anchor_top = 0.0
	overlay.anchor_right = 1.0; overlay.anchor_bottom = 1.0
	overlay.mouse_filter = MOUSE_FILTER_STOP
	overlay.gui_input.connect(_on_gather_detail_overlay_clicked.bind(overlay))
	add_child(overlay)
	
	# 详情面板
	var panel = ColorRect.new()
	panel.name = "GatherDetailPanel"
	panel.color = Color(0.10, 0.08, 0.15)
	panel.anchor_left = 0.0; panel.anchor_top = 0.0
	panel.anchor_right = 1.0; panel.anchor_bottom = 0.0
	panel.offset_left = Global.pw(0.08); panel.offset_top = Global.ph(0.25)
	panel.offset_right = Global.pw(-0.08); panel.offset_bottom = Global.ph(0.65)
	overlay.add_child(panel)
	
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color.TRANSPARENT
	panel_style.corner_radius_top_left = 20; panel_style.corner_radius_top_right = 20
	panel_style.corner_radius_bottom_left = 20; panel_style.corner_radius_bottom_right = 20
	panel.add_theme_stylebox_override("panel", panel_style)
	
	# 标题
	var title_label = Label.new()
	title_label.text = "" + name_str
	title_label.add_theme_font_size_override("font_size", 55)
	title_label.add_theme_color_override("font_color", rarity_color)
	title_label.add_theme_color_override("font_shadow_color", Color("#000000"))
	title_label.add_theme_constant_override("shadow_offset_x", 2)
	title_label.add_theme_constant_override("shadow_offset_y", 2)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.anchor_left = 0.0; title_label.anchor_top = 0.0
	title_label.anchor_right = 1.0; title_label.anchor_bottom = 0.0
	title_label.offset_left = 0; title_label.offset_top = Global.ph(0.02)
	title_label.offset_right = 0; title_label.offset_bottom = Global.ph(0.08)
	panel.add_child(title_label)
	
	# 分隔线
	var line = ColorRect.new()
	line.color = Color(1.0, 1.0, 1.0, 0.15)
	line.anchor_left = 0.0; line.anchor_top = 0.0
	line.anchor_right = 1.0; line.anchor_bottom = 0.0
	line.offset_left = Global.pw(0.05); line.offset_top = Global.ph(0.085)
	line.offset_right = Global.pw(-0.05); line.offset_bottom = Global.ph(0.09)
	panel.add_child(line)
	
	# 信息行
	var info_y := 0.12
	var info_rows := [
		["分类", category],
		["稀有度", rarity],
		["倾向", tendency],
		["属性", props_text],
	]
	
	if gather_text != "":
		info_rows.append(["采集区域", gather_text])
	
	for info in info_rows:
		var key = info[0]
		var val = info[1]
		
		var key_label = Label.new()
		key_label.text = key + "："
		key_label.add_theme_font_size_override("font_size", 38)
		key_label.add_theme_color_override("font_color", Color("#a090b0"))
		key_label.anchor_left = 0.0; key_label.anchor_top = 0.0
		key_label.anchor_right = 1.0; key_label.anchor_bottom = 0.0
		key_label.offset_left = Global.pw(0.06); key_label.offset_top = Global.ph(info_y)
		key_label.offset_right = Global.pw(-0.5); key_label.offset_bottom = Global.ph(info_y + 0.045)
		panel.add_child(key_label)
		
		var val_label = Label.new()
		val_label.text = val
		val_label.add_theme_font_size_override("font_size", 38)
		val_label.add_theme_color_override("font_color", Color("#e8d5b7"))
		val_label.anchor_left = 0.0; val_label.anchor_top = 0.0
		val_label.anchor_right = 1.0; val_label.anchor_bottom = 0.0
		val_label.offset_left = Global.pw(0.5); val_label.offset_top = Global.ph(info_y)
		val_label.offset_right = Global.pw(-0.06); val_label.offset_bottom = Global.ph(info_y + 0.045)
		val_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		panel.add_child(val_label)
		
		info_y += 0.05
	
	# 关闭按钮
	var close_btn = Button.new()
	close_btn.text = "关闭"
	close_btn.add_theme_font_size_override("font_size", 40)
	var cs = StyleBoxFlat.new()
	cs.bg_color = Color(0.2, 0.15, 0.3)
	cs.border_width_left = 2; cs.border_width_right = 2
	cs.border_width_top = 2; cs.border_width_bottom = 2
	cs.border_color = Color(0.5, 0.4, 0.7)
	cs.corner_radius_top_left = 12; cs.corner_radius_top_right = 12
	cs.corner_radius_bottom_left = 12; cs.corner_radius_bottom_right = 12
	cs.content_margin_left = 24; cs.content_margin_right = 24
	close_btn.add_theme_stylebox_override("normal", cs)
	close_btn.add_theme_color_override("font_color", Color("#e8d5b7"))
	close_btn.anchor_left = 0.0; close_btn.anchor_top = 0.0
	close_btn.anchor_right = 1.0; close_btn.anchor_bottom = 0.0
	close_btn.offset_left = Global.pw(0.25); close_btn.offset_top = Global.ph(0.35)
	close_btn.offset_right = Global.pw(-0.25); close_btn.offset_bottom = Global.ph(0.40)
	close_btn.pressed.connect(func(): overlay.queue_free())
	panel.add_child(close_btn)


func _on_gather_detail_overlay_clicked(event: InputEvent, overlay: ColorRect) -> void:
	if event is InputEventScreenTouch and not event.pressed:
		overlay.queue_free()


func _update_info_label() -> void:
	# 信息整合到 Title（原 InfoLabel 已废弃，会与 BOSS 按钮重叠）
	_update_title_with_progress()


func _update_title_with_progress() -> void:
	var title = get_node_or_null("Title")
	if not title or not (title is Label):
		print("[MapNode] Title 不存在!")
		return
	
	# 计算已完成的层数
	var completed_layers = 0
	for layer_idx in range(_node_data.size()):
		var has_completed = false
		for nd in _node_data[layer_idx]:
			if nd.get("completed", false):
				has_completed = true
				break
		if has_completed:
			completed_layers += 1
	
	var text = _map_name if _map_name != "" else "探索地图"
	text += " · " + str(completed_layers) + "/" + str(LAYER_CONFIG.size())
	title.text = text
	
	# Title 布局：缩小到 TopBar 中间一条，字号 42，居左对齐（避免右侧被遮挡）
	title.set_anchors_preset(Control.PRESET_TOP_LEFT)
	title.position = Vector2(Global.pw(0.35), Global.ph(0.03))
	title.size = Vector2(Global.pw(0.63), Global.ph(0.05))
	title.add_theme_font_size_override("font_size", 42)
	# AUTOWRAP_WORD 对中文不生效（整串被当成一个词）→ 最小宽度被撑到 1058px，
	# 加上 x 偏移后右边界直接超出屏幕。中文必须用 WORD_SMART 才会按字断行。
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	print("[MapNode] Title 更新为: ", text)


func _on_help():
	Global.play_sfx("click")
	_show_help_guide()


## 显示地图层掉落指南弹窗
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
	title.text = "地图层掉落指南"
	title.add_theme_font_size_override("font_size", 60)
	title.add_theme_color_override("font_color", Color("#f9d371"))
	title.add_theme_color_override("font_shadow_color", Color("#000000"))
	title.add_theme_constant_override("shadow_offset_x", 2)
	title.add_theme_constant_override("shadow_offset_y", 2)
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
	close_btn.text = "关闭"
	close_btn.add_theme_font_size_override("font_size", 50)
	var cs = StyleBoxFlat.new()
	cs.bg_color = Color(0.15, 0.13, 0.20)
	cs.border_width_left = 2; cs.border_width_right = 2
	cs.border_width_top = 2; cs.border_width_bottom = 2
	cs.border_color = Color("#888888")
	cs.corner_radius_top_left = 10; cs.corner_radius_top_right = 10
	cs.corner_radius_bottom_left = 10; cs.corner_radius_bottom_right = 10
	close_btn.add_theme_stylebox_override("normal", cs)
	close_btn.add_theme_color_override("font_color", Color("#e8d5b7"))
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
	sep.add_theme_color_override("color", Color(0.3, 0.25, 0.4))
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
	# 1. 地图层简介
	var s1 = _make_help_section(vbox, " ① 地图层简介", Color("#5cb85c"))
	_make_help_label(s1, "爬塔地图共8层，每层有3个节点（起点和BOSS层除外）。", Color("#e8d5b7"), 42)
	_make_help_label(s1, "每层节点类型随机分配为战斗或采集。", Color("#e8d5b7"), 42)
	_make_help_label(s1, "战斗：击败卡兽可获得辅材掉落", Color("#FF5252"), 45)
	_make_help_label(s1, "采集：采集素材用于制作卡基和卡墨", Color("#4CAF50"), 45)
	
	# 2. 层1-树林
	var s2 = _make_help_section(vbox, " ② 树林层", Color("#5cb85c"))
	_make_help_label(s2, " 战斗掉落（辅材，概率5%）：", Color("#FF5252"), 48)
	_make_help_label(s2, "  • 催芽藓偶 → 新生嫩芽、木质纤维", Color("#e8d5b7"))
	_make_help_label(s2, "  • 雾栖鹿偶 → 鹿角碎片、雾绒", Color("#e8d5b7"))
	_make_help_label(s2, " 采集掉落（概率70%）：", Color("#4CAF50"), 48)
	_make_help_label(s2, "  • 白麻纤维 (普通) 70%", Color("#CCCCCC"))
	_make_help_label(s2, "  • 青藤纤维 (普通) 70%", Color("#CCCCCC"))
	_make_help_label(s2, "  • 普通松脂 (普通) 70%", Color("#CCCCCC"))
	_make_help_label(s2, "  • 骨胶 (普通) 70%", Color("#CCCCCC"))
	
	# 3. 层2-草丛
	var s3 = _make_help_section(vbox, " ③ 草丛层", Color("#e8a838"))
	_make_help_label(s3, " 采集掉落（概率70%）：", Color("#4CAF50"), 48)
	_make_help_label(s3, "  • 生命露水 (普通) 70%", Color("#CCCCCC"))
	_make_help_label(s3, "  • 炭黑 (普通) 70%", Color("#CCCCCC"))
	_make_help_label(s3, "  • 朱砂 (普通) 70%", Color("#CCCCCC"))
	
	# 4. 层3-矿区
	var s4 = _make_help_section(vbox, " ④ 矿区层", Color("#9b59b6"))
	_make_help_label(s4, " 采集掉落（概率70%）：", Color("#4CAF50"), 48)
	_make_help_label(s4, "  • 石灰矿粉 (普通) 70%", Color("#CCCCCC"))
	_make_help_label(s4, "  • 辉光矿粉 (普通) 70%", Color("#CCCCCC"))
	
	# 5. 层4-溪谷
	var s5 = _make_help_section(vbox, " ⑤ 溪谷层", Color("#3498db"))
	_make_help_label(s5, " 采集掉落（概率70%）：", Color("#4CAF50"), 48)
	_make_help_label(s5, "  • 砂金石粉 (普通) 70%", Color("#CCCCCC"))
	_make_help_label(s5, "  • 清水 (普通) 70%", Color("#CCCCCC"))
	_make_help_label(s5, "  • 鱼鳔胶 (普通) 70%", Color("#CCCCCC"))
	
	# 6. 层5-山道
	var s6 = _make_help_section(vbox, " ⑥ 山道层", Color("#e87d38"))
	_make_help_label(s6, " 采集掉落（概率70%）：", Color("#4CAF50"), 48)
	_make_help_label(s6, "  • 枯草纤维 (普通) 70%", Color("#CCCCCC"))
	_make_help_label(s6, "  • 赭石 (普通) 70%", Color("#CCCCCC"))
	
	# 7. 层6-暗穴
	var s7 = _make_help_section(vbox, " ⑦ 暗穴层", Color("#8e44ad"))
	_make_help_label(s7, " 采集掉落（概率70%）：", Color("#4CAF50"), 48)
	_make_help_label(s7, "  • 琥珀树脂 (普通) 70%", Color("#CCCCCC"))
	_make_help_label(s7, "  • 树汁胶 (普通) 70%", Color("#CCCCCC"))
	
	# 8. 层7-BOSS
	var s8 = _make_help_section(vbox, " ⑧ BOSS层", Color("#e74c3c"))
	_make_help_label(s8, " 击败BOSS即可通关该地图！", Color("#FFD700"), 45)
	_make_help_label(s8, "每个地图共有3个随机BOSS之一出战：", Color("#e8d5b7"), 42)
	_make_help_label(s8, "  • 沉雾植物园 → 古荫/炉心/夜幕", Color("#e8d5b7"))
	_make_help_label(s8, "  • 烬燃热电厂 → 炎宰/熔核/过热", Color("#e8d5b7"))
	_make_help_label(s8, "  • 雷鸣电视塔 → 过载/失真/惊蛰", Color("#e8d5b7"))
	_make_help_label(s8, "  • 沉陷湿地公园 → 淤眠/雾溺", Color("#e8d5b7"))
	_make_help_label(s8, "  • 圮城博物馆 → 典守/断代/镇馆", Color("#e8d5b7"))
	_make_help_label(s8, " 不同地图的掉落不同，具体见野外探索指南", Color("#FFD700"), 42)
	
	# 底部留白
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, Global.ph(0.02))
	vbox.add_child(spacer)


# ===== 指南弹窗长按详情 =====

func _guide_cancel_press() -> void:
	if _guide_pressed_label != null:
		_guide_pressed_label.remove_theme_color_override("font_color")
	_guide_pressed_label = null
	_guide_press_timer = 0.0
	_guide_press_index = -1


func _find_guide_material_label_at(pos: Vector2) -> Label:
	var overlay = get_node_or_null("HelpOverlay")
	if not overlay:
		return null
	var panel = overlay.get_node_or_null("HelpPanel")
	if not panel:
		return null
	var scroll = panel.get_node_or_null("HelpScroll")
	if not scroll:
		return null
	var vbox = scroll.get_node_or_null("HelpVBox")
	if not vbox:
		return null
	# 遍历所有子孙节点
	for child in vbox.get_children(true):
		var found = _find_guide_label_recursive(child, pos)
		if found != null:
			return found
	return null


func _find_guide_label_recursive(node: Node, pos: Vector2) -> Label:
	if node is Label:
		var rect = Rect2(node.get_global_rect().position, node.get_global_rect().size)
		if rect.has_point(pos):
			var text = node.text.strip_edges()
			if text.begins_with("•") or text.begins_with("-"):
				for mat_name in MATERIAL_NAME_TO_ID.keys():
					if mat_name in text:
						node.set_meta("detail_type", "material")
						return node
				for aux_name in AUX_NAME_TO_ID.keys():
					if aux_name in text:
						node.set_meta("detail_type", "aux")
						return node
				for enemy_name in ENEMY_NAME_TO_DATA.keys():
					if enemy_name in text:
						node.set_meta("detail_type", "enemy")
						return node
	for child in node.get_children(true):
		var found = _find_guide_label_recursive(child, pos)
		if found != null:
			return found
	return null


func _show_guide_material_detail(label: Label) -> void:
	var text = label.text
	var detail_type: String = label.get_meta("detail_type", "material")
	
	match detail_type:
		"material":
			_show_guide_mat_detail_popup(label, text)
		"aux":
			_show_guide_aux_detail_popup(label, text)
		"enemy":
			_show_guide_enemy_detail_popup(label, text)


func _show_guide_mat_detail_popup(label: Label, text: String) -> void:
	# 提取素材名称
	var mat_name := ""
	for name in MATERIAL_NAME_TO_ID.keys():
		if name in text:
			mat_name = name
			break
	if mat_name == "":
		return
	
	var material_id = MATERIAL_NAME_TO_ID.get(mat_name, "")
	if material_id == "":
		return
	
	var mat_data := Global.get_material_by_id(material_id)
	if mat_data.is_empty():
		return
	
	var name_str: String = mat_data.get("name", "未知")
	var rarity: String = mat_data.get("rarity", "普通")
	var area: String = mat_data.get("area", "未知")
	var tendency: String = mat_data.get("tendency", "")
	if tendency == "":
		tendency = "无"
	
	var category := "未知"
	if material_id.begins_with("F"): category = "纤维"
	elif material_id.begins_with("M"): category = "矿粉"
	elif material_id.begins_with("R"): category = "树脂"
	elif material_id.begins_with("E"): category = "萃取液"
	elif material_id.begins_with("P"): category = "颜料"
	elif material_id.begins_with("B"): category = "粘合剂"
	
	var props_text := ""
	match category:
		"纤维":
			var carry = mat_data.get("carry", 0)
			var tough = mat_data.get("toughness", 0)
			props_text = "承载力: " + str(carry) + "  韧性: " + str(tough)
		"矿粉":
			var stab = mat_data.get("stability", 0)
			var hard = mat_data.get("hardness", 0)
			props_text = "稳定性: " + str(stab) + "  硬度: " + str(hard)
		"树脂":
			var bond = mat_data.get("bond", 0)
			var gloss = mat_data.get("gloss", 0)
			props_text = "粘合度: " + str(bond) + "  光泽: " + str(gloss)
		"萃取液":
			var cond = mat_data.get("conductivity", 0)
			var pur = mat_data.get("purity", 0)
			props_text = "传导性: " + str(cond) + "  纯度: " + str(pur)
		"颜料":
			var adh = mat_data.get("adhesion", 0)
			var chr = mat_data.get("chromatography", 0)
			props_text = "附着力: " + str(adh) + "  显色: " + str(chr)
		"粘合剂":
			var har = mat_data.get("harmony", 0)
			props_text = "调和度: " + str(har)
	
	var rarity_color := Color("#e8d5b7")
	match rarity:
		"传说": rarity_color = Color("#f9d371")
		"史诗": rarity_color = Color("#c084fc")
		"稀有": rarity_color = Color("#60a5fa")
	
	var info_rows := [
		["分类", category],
		["稀有度", rarity],
		["倾向", tendency],
		["属性", props_text],
		["产出区域", area],
	]
	_show_detail_popup(" " + name_str, rarity_color, info_rows)


func _show_guide_aux_detail_popup(label: Label, text: String) -> void:
	var aux_name := ""
	for name in AUX_NAME_TO_ID.keys():
		if name in text:
			aux_name = name
			break
	if aux_name == "":
		return
	
	var aux_id = AUX_NAME_TO_ID.get(aux_name, "")
	if aux_id == "":
		return
	
	var aux_data := Global.get_aux_by_id(aux_id)
	if aux_data.is_empty():
		return
	
	var name_str = aux_data.get("name", "未知")
	var type_str = aux_data.get("type", "")
	var rarity = aux_data.get("rarity", "普通")
	var desc = aux_data.get("description", "无描述")
	var effect = aux_data.get("effect", {})
	
	# 类型中文名
	var type_cn: String = type_str
	match type_str:
		"boost": type_cn = "强化"
		"element": type_cn = "元素"
		"protect": type_cn = "守护"
		"special": type_cn = "特殊"
		"poison": type_cn = "剧毒"
		"combo": type_cn = "连击"
	
	var rarity_color := Color("#e8d5b7")
	match rarity:
		"传说": rarity_color = Color("#f9d371")
		"史诗": rarity_color = Color("#c084fc")
		"稀有": rarity_color = Color("#60a5fa")
	
	# 效果文本
	var effect_text := ""
	for key in effect.keys():
		var val = effect[key]
		if effect_text != "":
			effect_text += "\n"
		effect_text += str(key) + ": " + str(val)
	if effect_text == "":
		effect_text = "无"
	
	var info_rows := [
		["类型", type_cn],
		["稀有度", rarity],
		["效果", effect_text],
		["描述", desc],
	]
	_show_detail_popup(" " + name_str, rarity_color, info_rows)


func _show_guide_enemy_detail_popup(label: Label, text: String) -> void:
	var enemy_name := ""
	for name in ENEMY_NAME_TO_DATA.keys():
		if name in text:
			enemy_name = name
			break
	if enemy_name == "":
		return
	
	var enemy_data = ENEMY_NAME_TO_DATA.get(enemy_name, {})
	if enemy_data.is_empty():
		return
	
	# 带emoji的全名列表
	var full_names := {
		"催芽藓偶": "🌱 催芽藓偶", "雾栖鹿偶": "🦌 雾栖鹿偶", "霉斑菌傀": "🍄 霉斑菌傀",
		"灼背蜥": "🦎 灼背蜥", "刈草螳": "🦗 刈草螳", "灌渠鳞蛇": "🐍 灌渠鳞蛇",
		"假山傀儡": "🪨 假山傀儡", "暖管蠕虫": "🔥 暖管蠕虫", "沥青蝎": "🦂 沥青蝎",
		"喷泉水灵": "💧 喷泉水灵", "玻璃翼蝶": "🦋 玻璃翼蝶", "聚光蜮": "🔮 聚光蜮",
		"叠石巨人": "🗻 叠石巨人", "掠影寒鸦": "🐦‍⬛ 掠影寒鸦", "贯雾鹰": "🦅 贯雾鹰",
		"井穴蜘蛛": "🕷️ 井穴蜘蛛", "锅炉龟": "🐢 锅炉龟", "灯诱光蝶": "🦋 灯诱光蝶",
		"古荫": "👑 古荫", "炉心": "👑 炉心", "夜幕": "👑 夜幕",
		"炎宰": "👑 炎宰", "熔核": "👑 熔核", "过热": "👑 过热",
		"过载": "👑 过载", "失真": "👑 失真", "惊蛰": "👑 惊蛰",
		"淤眠": "👑 淤眠", "雾溺": "👑 雾溺", "典守": "👑 典守",
		"断代": "👑 断代", "镇馆": "👑 镇馆",
	}
	
	var display_name = full_names.get(enemy_name, enemy_name)
	var level = enemy_data.get("level", 0)
	var hp = enemy_data.get("hp", 0)
	var element = enemy_data.get("element", "无")
	var desc = enemy_data.get("desc", "无描述")
	var aux_drops = enemy_data.get("aux_drops", [])
	
	# 元素颜色
	var element_color := Color("#ffffff")
	match element:
		"火": element_color = Color("#e74c3c")
		"水": element_color = Color("#3498db")
		"风": element_color = Color("#2ecc71")
		"地": element_color = Color("#e67e22")
		"光": element_color = Color("#f9d371")
		"暗": element_color = Color("#9b59b6")
	
	# 辅材掉落名称
	var aux_str := ""
	for aid in aux_drops:
		var a_data := Global.get_aux_by_id(aid)
		if not a_data.is_empty():
			if aux_str != "":
				aux_str += "、"
			aux_str += a_data.get("name", aid)
	if aux_str == "":
		aux_str = "无"
	
	var title_color := Color("#e8d5b7")
	var info_rows := [
		["等级", "Lv." + str(level)],
		["生命值", str(hp) + " HP"],
		["元素", element],
		["描述", desc],
		["辅材掉落", aux_str],
	]
	_show_detail_popup(" " + display_name, title_color, info_rows)


## 通用详情弹窗模板
func _show_detail_popup(title_text: String, title_color: Color, info_rows: Array) -> void:
	var overlay = ColorRect.new()
	overlay.name = "GuideDetailOverlay"
	overlay.color = Color(0.0, 0.0, 0.0, 0.6)
	overlay.anchor_left = 0.0; overlay.anchor_top = 0.0
	overlay.anchor_right = 1.0; overlay.anchor_bottom = 1.0
	overlay.mouse_filter = MOUSE_FILTER_STOP
	overlay.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventScreenTouch and not ev.pressed:
			overlay.queue_free()
	)
	add_child(overlay)
	
	var panel = ColorRect.new()
	panel.name = "GuideDetailPanel"
	panel.color = Color(0.10, 0.08, 0.15)
	panel.anchor_left = 0.0; panel.anchor_top = 0.0
	panel.anchor_right = 1.0; panel.anchor_bottom = 0.0
	panel.offset_left = Global.pw(0.08); panel.offset_top = Global.ph(0.25)
	panel.offset_right = Global.pw(-0.08); panel.offset_bottom = Global.ph(0.65)
	overlay.add_child(panel)
	
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color.TRANSPARENT
	panel_style.corner_radius_top_left = 20; panel_style.corner_radius_top_right = 20
	panel_style.corner_radius_bottom_left = 20; panel_style.corner_radius_bottom_right = 20
	panel.add_theme_stylebox_override("panel", panel_style)
	
	# 标题
	var title_label = Label.new()
	title_label.text = title_text
	title_label.add_theme_font_size_override("font_size", 55)
	title_label.add_theme_color_override("font_color", title_color)
	title_label.add_theme_color_override("font_shadow_color", Color("#000000"))
	title_label.add_theme_constant_override("shadow_offset_x", 2)
	title_label.add_theme_constant_override("shadow_offset_y", 2)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.anchor_left = 0.0; title_label.anchor_top = 0.0
	title_label.anchor_right = 1.0; title_label.anchor_bottom = 0.0
	title_label.offset_left = 0; title_label.offset_top = Global.ph(0.02)
	title_label.offset_right = 0; title_label.offset_bottom = Global.ph(0.08)
	panel.add_child(title_label)
	
	# 分隔线
	var line = ColorRect.new()
	line.color = Color(1.0, 1.0, 1.0, 0.15)
	line.anchor_left = 0.0; line.anchor_top = 0.0
	line.anchor_right = 1.0; line.anchor_bottom = 0.0
	line.offset_left = Global.pw(0.05); line.offset_top = Global.ph(0.085)
	line.offset_right = Global.pw(-0.05); line.offset_bottom = Global.ph(0.09)
	panel.add_child(line)
	
	# 信息行
	var info_y := 0.12
	for info in info_rows:
		var key = info[0]
		var val = info[1]
		
		var key_label = Label.new()
		key_label.text = key + "："
		key_label.add_theme_font_size_override("font_size", 38)
		key_label.add_theme_color_override("font_color", Color("#a090b0"))
		key_label.anchor_left = 0.0; key_label.anchor_top = 0.0
		key_label.anchor_right = 1.0; key_label.anchor_bottom = 0.0
		key_label.offset_left = Global.pw(0.06); key_label.offset_top = Global.ph(info_y)
		key_label.offset_right = Global.pw(-0.5); key_label.offset_bottom = Global.ph(info_y + 0.045)
		panel.add_child(key_label)
		
		var val_label = Label.new()
		val_label.text = val
		val_label.add_theme_font_size_override("font_size", 38)
		val_label.add_theme_color_override("font_color", Color("#e8d5b7"))
		val_label.anchor_left = 0.0; val_label.anchor_top = 0.0
		val_label.anchor_right = 1.0; val_label.anchor_bottom = 0.0
		val_label.offset_left = Global.pw(0.5); val_label.offset_top = Global.ph(info_y)
		val_label.offset_right = Global.pw(-0.06); val_label.offset_bottom = Global.ph(info_y + 0.045)
		val_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		panel.add_child(val_label)
		
		info_y += 0.05
		# 如果val文本较长，增加行高
		if len(val) > 30:
			info_y += 0.025
	
	# 关闭按钮
	var close_btn = Button.new()
	close_btn.text = "关闭"
	close_btn.add_theme_font_size_override("font_size", 40)
	var cs = StyleBoxFlat.new()
	cs.bg_color = Color(0.2, 0.15, 0.3)
	cs.border_width_left = 2; cs.border_width_right = 2
	cs.border_width_top = 2; cs.border_width_bottom = 2
	cs.border_color = Color(0.5, 0.4, 0.7)
	cs.corner_radius_top_left = 12; cs.corner_radius_top_right = 12
	cs.corner_radius_bottom_left = 12; cs.corner_radius_bottom_right = 12
	cs.content_margin_left = 24; cs.content_margin_right = 24
	close_btn.add_theme_stylebox_override("normal", cs)
	close_btn.add_theme_color_override("font_color", Color("#e8d5b7"))
	close_btn.anchor_left = 0.0; close_btn.anchor_top = 0.0
	close_btn.anchor_right = 1.0; close_btn.anchor_bottom = 0.0
	close_btn.offset_left = Global.pw(0.25); close_btn.offset_top = Global.ph(0.35)
	close_btn.offset_right = Global.pw(-0.25); close_btn.offset_bottom = Global.ph(0.40)
	close_btn.pressed.connect(func(): overlay.queue_free())
	panel.add_child(close_btn)


func _on_back():
	Global.play_sfx("click")
	Global.change_scene("res://Exploration.tscn")


func _add_layer_labels(container: Control) -> void:
	for layer_idx in range(LAYER_CONFIG.size()):
		var layer = LAYER_CONFIG[layer_idx]
		var label = Label.new()
		label.text = layer["name"]
		label.add_theme_font_size_override("font_size", 40)
		label.add_theme_color_override("font_color", layer["color"])
		label.add_theme_color_override("font_shadow_color", Color("#000000"))
		label.add_theme_constant_override("shadow_offset_x", 2)
		label.add_theme_constant_override("shadow_offset_y", 2)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.anchor_left = 0.0; label.anchor_top = 0.0
		label.anchor_right = 1.0; label.anchor_bottom = 0.0
		label.offset_left = 0
		label.offset_top = Global.ph(layer["y"]) - Global.ph(0.09)
		label.offset_right = 0
		label.offset_bottom = Global.ph(layer["y"]) - Global.ph(0.06)
		container.add_child(label)


func _scroll_to_layer(layer_idx: int) -> void:
	var scroll = get_node_or_null("MapScroll")
	if not scroll:
		return
	
	# 计算该层的Y位置，滚动到屏幕中间
	var layer_y = Global.ph(LAYER_CONFIG[layer_idx]["y"])
	var scroll_center = scroll.size.y / 2.0
	var target_scroll = layer_y - scroll_center
	scroll.scroll_vertical = int(max(0, target_scroll))


## 滚动到指定节点位置（居中显示）
func _scroll_to_node_position(node_x: float, node_y: float) -> void:
	var scroll = get_node_or_null("MapScroll")
	if not scroll:
		return
	
	# 计算节点在屏幕上的Y位置，滚动到屏幕中间
	var node_y_pos = Global.ph(node_y)
	var scroll_center = scroll.size.y / 2.0
	var target_scroll = node_y_pos - scroll_center
	scroll.scroll_vertical = int(max(0, target_scroll))


## 恢复保存的节点状态（战斗返回后）
func _restore_map_node_state() -> void:
	var saved = Global.saved_map_node_data
	Global.saved_map_node_data = []  # 清空，防止重复恢复
	_apply_saved_state(saved)
	
## 应用保存的状态到 _node_data（不涉及按钮，由后续渲染统一刷新样式）
func _apply_saved_state(saved: Array) -> void:
	if saved.is_empty():
		return
	for layer_idx in range(min(saved.size(), _node_data.size())):
		for node_idx in range(min(saved[layer_idx].size(), _node_data[layer_idx].size())):
			var save_nd = saved[layer_idx][node_idx]
			var nd = _node_data[layer_idx][node_idx]
			nd["available"] = save_nd["available"]
			nd["completed"] = save_nd["completed"]
			nd["current"] = save_nd["current"]
	print("[爬塔] 已恢复地图节点状态（%d 层）" % saved.size())

func _apply_theme_styles():
	var bg = get_node_or_null("Background")
	Global.apply_bg(bg)
	for n in ["TopBar","BottomBar"]:
		var r = get_node_or_null(n)
		if r is ColorRect: r.color = Global.current.topbar_bg
	for n in ["TopBarLine","BottomBarLine"]:
		var r = get_node_or_null(n)
		if r is ColorRect: r.color = Global.current.topbar_border
	var title = get_node_or_null("Title")
	if title is Label:
		title.add_theme_color_override("font_color", Global.current.title)
		title.add_theme_color_override("font_shadow_color", Global.current.title_shadow)
		title.add_theme_constant_override("shadow_offset_x", Global.current.shadow_offset)
		title.add_theme_constant_override("shadow_offset_y", Global.current.shadow_offset)
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
func _build_dynamic_content():
	print("[MapNode] ===== _build_dynamic_content 开始 =====")
	print("[MapNode] Global.current_map_id=", Global.current_map_id, " name=", Global.current_map_name)
	print("[MapNode] Global.saved_map_node_data.size=", Global.saved_map_node_data.size())
	# 存档大小 > 0 = 战斗返回，需要重生成同布局+应用状态；== 0 = 首次进入
	var saved = Global.saved_map_node_data.duplicate(true)
	var is_returning = saved.size() > 0

	# 地图 ID/名称兜底（从 Global 取，Exploration 切场景前已设置）
	if _map_id == "" or _map_name == "":
		_map_id = Global.current_map_id
		_map_name = Global.current_map_name
		if _map_name == "":
			_map_name = MAP_NAMES.get(_map_id, "探索地图")
			if _map_name == "":
				_map_name = "探索地图"
	print("[MapNode] 准备 init_map(_map_id=", _map_id, ", _map_name=", _map_name, ")")

	# 无论首次进入还是战斗返回，都生成节点数据（战斗返回后同布局重建）
	init_map(_map_id, _map_name)
	print("[MapNode] init_map 完成，_node_data.size=", _node_data.size())

	# 战斗返回：应用保存的 available/completed/current 状态
	if is_returning:
		print("[MapNode] 是战斗返回，调用 _apply_saved_state")
		_apply_saved_state(saved)

	# 清空 Global 存档，防止下次进地图误恢复旧数据
	Global.saved_map_node_data = []

	# 直接把连线、节点按钮加到 self（root Control 是全屏）
	# 不再画层标签（视觉上像圆角框干扰节点按钮识别）
	print("[MapNode] 开始 _render_nodes_in_container")
	_render_nodes_in_container(self)
	print("[MapNode] _render_nodes_in_container 完成")

	# 顶部信息直接整合到 Title（原本单独的 InfoLabel 会遮 BOSS 按钮）
	_update_title_with_progress()
	print("[MapNode] ===== _build_dynamic_content 结束 =====")
