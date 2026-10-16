class_name BattleContext

## ============================================================
##  BattleContext — 战斗/地图状态传递（纯静态变量，无逻辑）
##  各场景通过 BattleContext.xxx 读写战斗前的上下文
## ============================================================

## 地图数据传递（用于爬塔地图）
static var current_map_id: String = ""
static var current_map_name: String = ""

## 卡组选择传递（用于战斗场景）
static var current_deck_id: String = ""
static var current_deck_name: String = ""

## 敌人数据传递（用于爬塔战斗）
static var current_enemy_data: Dictionary = {}
static var current_battle_terrain: String = ""
static var current_map_layer: int = -1
static var current_map_node: int = -1
static var current_is_boss: bool = false
static var current_is_ambush: bool = false
static var is_tutorial_battle: bool = false

## 爬塔持久HP（让休息节点有意义，每次进入地图时重置）
static var current_run_player_hp: int = -1
static var current_run_player_max_hp: int = 0
static var saved_map_node_data: Array = []
