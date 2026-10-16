# 卡师模拟器 — 游戏设计文档

> 基于代码逆向还原 | 引擎: Godot 4.x | 分辨率: 1080x1920 竖屏

---

## 1. 游戏概述

一款竖屏卡牌策略养成手游，融合**制卡 + 爬塔 + 对战**三大核心玩法。玩家扮演「卡师」，通过采集素材、调制约材料、音游式刻录纹路来制造卡牌，组建卡组挑战爬塔地图与 BOSS，并在决斗场与其他玩家虚拟对战。

### 1.1 核心循环

```
采集素材 → 调制卡基/卡墨/辅材 → 音游刻录卡牌 → 组建卡组
    ↑                                                    ↓
  金币/素材 ← 探索地图(爬塔/收集/休息) ← 挑战 BOSS ← 决斗场对战
```

### 1.2 主界面入口

主界面（Main.tscn）提供 5 个功能入口：
- **卡师公会**（Guild）— 个人信息、公会任务
- **商店街**（StoreStreet）— 素材商店、卡包商店、牌组租借
- **野外探索**（Exploration）— 迷雾森林、火焰洞穴、决斗场
- **制卡工坊**（CardWorkshop）— 卡基制作、卡墨调制、辅材制作、纹路刻录
- **卡牌图鉴**（CardGallery）— 收藏卡牌浏览、卡组编辑

---

## 2. 卡牌系统

### 2.1 卡牌数据结构（BattleCard.gd）

| 字段 | 类型 | 说明 |
|------|------|------|
| card_id | String | 唯一实例 ID（自动生成） |
| template_id | String | 模板 ID（如 CARD_QP_001） |
| card_name | String | 卡名 |
| fields | Array | 字段列表 |
| base_cost | int | 能量消耗 |
| base_atk | int | 基础攻击力 |
| base_hp | int | 基础生命值 |
| quality | String | 品质（6 档） |
| element | String | 属性（7 种） |
| star | int | 星级 |
| effects | Array | 效果列表（纹路组件组合） |
| aux_items | Array | 附着的辅材数据 |
| created_at | int | 创建时间戳 |

### 2.2 品质系统（Global.gd）

6 档品质，由制卡时的音游判定决定：

| 品质 | 英文 | 倍率 | 颜色 |
|------|------|------|------|
| 废品 | Scrap | 0.5 | #808080 |
| 瑕疵 | Defective | 0.75 | #A9A9A9 |
| 标准 | Standard | 1.0 | #FFFFFF |
| 精良 | Fine | 1.25 | #4FC3F7 |
| 卓越 | Excellent | 1.5 | #FFD700 |
| 完美 | Perfect | 2.0 | #FF1493 |

### 2.3 属性系统（7 种元素）

地(earth) / 火(fire) / 水(water) / 风(wind) / 光(light) / 暗(dark) / 纯(pure)

### 2.4 运行时状态（BattleCard）

- `current_atk` / `current_hp` — 当前攻击/生命
- `has_attacked` — 本回合是否已攻击
- `summoned_this_turn` — 召唤当回合不能攻击
- `is_on_field` / `slot_index` — 场上状态与卡位
- `is_turned` — 攻击/守备表示切换
- `temp_atk_buff` / `temp_hp_buff` — 本回合临时增减
- `cannot_attack` / `is_frozen` / `effect_disabled` — 负面状态
- `poison_count` / `poison_per_hit` — 中毒系统
- `has_combo` / `combo_used` — 连击系统
- `atk_buff_permanent` / `hp_buff_permanent` — 永久增益
- `revive_chance` — 破坏时复活概率
- `element_power_bonus` — 元素强度加成

---

## 3. 纹路组件系统

纹路是卡牌效果的构成单元，由五类组件组合而成，共约 90 个组件。

### 3.1 组件分类

| 前缀 | 类型 | 数量 | 说明 |
|------|------|------|------|
| TR | 触发器 | 17 | 定义效果触发时机 |
| C | 条件 | 12 | 定义触发附加条件 |
| A | 动作 | 34 | 定义效果具体行为 |
| T | 目标 | 10 | 定义效果目标选择 |
| CO | 约束 | 16 | 定义效果使用限制 |

### 3.2 效果执行流程

```
触发器(TR) → 条件判定(C) → 目标选择(T) → 动作执行(A) → 约束校验(CO)
```

### 3.3 纹路解锁管理（CircuitManager.gd）

- 纹路通过公会任务解锁
- CircuitGallery.gd 提供图鉴浏览
- 解锁状态持久化到存档

---

## 4. 制卡系统

### 4.1 制卡工坊（CardWorkshop.gd）

提供 4 个子系统入口：

#### 4.1.1 卡基制作（CardBaseMaking.gd）

原料配方：纤维 + 矿粉 + 树脂 → 卡基

| 材料类型 | ID 前缀 | 种类数 | 示例 |
|----------|---------|--------|------|
| 纤维 | F01-F12 | 12 | 白麻纤维、青藤纤维、传说亚麻 |
| 矿粉 | M01-M12 | 12 | 石灰矿粉、辉光矿粉、星辰粉末 |
| 树脂 | R01-R08 | 8 | 普通松脂、琥珀树脂、龙血树脂 |

每个材料有：`rarity`（稀有度）、`area`（产出区域）、`carry`（携带量）、`toughness`（韧性）、`tendency`（倾向）。

#### 4.1.2 卡墨调制（InkMaking.gd）

原料配方：萃取液 + 颜料 + 粘合剂 → 卡墨

| 材料类型 | ID 前缀 | 种类数 | 示例 |
|----------|---------|--------|------|
| 萃取液 | E01-E10 | 10 | 清水、生命露水、圣光露 |
| 颜料 | P01-P10 | 10 | 炭黑、朱砂、金粉 |
| 粘合剂 | B01-B08 | 8 | 骨胶、鱼鳔胶、龙涎胶 |

#### 4.1.3 辅材制作（AuxMaking.gd）

辅材从战斗中怪物掉落，也可制作。辅材 ID 范围：AU1-AU58。

辅材效果类型：
- `hp_bonus` — 生命值加成
- `atk_bonus` — 攻击力加成
- `energy_reduce` — 能量消耗减少
- `element` — 属性覆盖 + 元素强度加成
- `shield_points` — 护盾值
- `damage_reduce` — 受伤减少
- `damage_halve` — 伤害减半
- `poison_per_hit` — 攻击附加中毒
- `has_combo` — 连击能力
- `has_haste` — 先攻能力
- `revive_chance` — 复活概率
- `indestructible_once` — 免破坏一次
- `draw_on_summon` — 上场抽牌
- `extra_triggers` — 额外触发次数
- `field_sync` — 同字段光环
- `element_power` — 元素强度加成

#### 4.1.4 纹路刻录（CardEngraving.gd）— 音游小游戏

核心玩法：在音游判定中刻录纹路，根据判定精度决定卡牌品质。

- 判定结果映射到品质（废品 → 完美）
- 不同品质有固定品质倍率
- 质量越高品质倍率越高，影响卡牌最终属性

---

## 5. 战斗系统

### 5.1 双系统架构

| 系统 | 核心文件 | 场景 | 特点 |
|------|----------|------|------|
| 旧系统 | BattleManager.gd (4341行) | BattleScene3D / BattleSceneLegacy | 单体管理器，UI 耦合 |
| 新系统 | battle_new/ (21 文件) | - | 模块化重构，信号驱动 |

### 5.2 回合阶段流

```
DRAW(抽牌) → READY(准备) → MAIN(主要) → BATTLE(战斗) → END(结束) → DISCARD(弃牌)
```

每回合流程：
1. **DRAW**: 抽 1 张牌（初始 5 张手牌，3 点能量）
2. **READY**: 准备阶段，可调整卡组
3. **MAIN**: 主要阶段，可召唤卡牌（费用 = 能量消耗）
4. **BATTLE**: 战斗阶段，场上卡牌进行攻击
5. **END**: 结束阶段，处理持续效果、中毒结算
6. **DISCARD**: 弃牌阶段（手牌超限时）

### 5.3 场地系统

- 5 个卡位场地
- 每张卡牌有 `slot_index`（-1 表示不在场）
- 卡牌可切换攻击/守备表示（`is_turned`）
- 召唤当回合不能攻击（`summoned_this_turn`），除非有先攻辅材

### 5.4 连锁系统（Chain System）

- 最大连锁长度：10
- 最大递归深度：50（防栈溢出）
- 连锁构建时询问对方是否响应
- 连锁结算从栈顶开始逆序执行
- 结算中触发的效果直接执行，不入栈

新系统使用状态机替代布尔 flag：
```
IDLE → BUILDING → RESOLVING → IDLE
```

### 5.5 AI 决策系统

旧系统（BattleManager.gd）：
- 全知视角：AI 可查看玩家手牌/牌库
- 连招识别：识别连招关键组件，攒牌等配套
- 卖血策略：血量高于阈值时倾向用血换节奏
- 威胁评估：缓存最近威胁分析
- 四种战略：balanced / aggro(抢血) / control(控场) / combo(攒连招)
- 牌库预读：预读接下来 5 回合会抽到什么

新系统（battle_new/）：
- BattleAINew.gd 独立 AI 模块
- 通过 IBattleControllerNew 接口与游戏交互

### 5.6 效果系统（新系统 EffectSystemNew.gd）

新系统规避旧系统 8 个 bug：
1. 状态机替代布尔 flag → 规避连锁状态混乱
2. 统一连锁响应接口 → 规避响应缺失
3. 目标快照：执行前冻结目标列表 → 规避目标变化
4. 亡语传正确 old_slot → 规避亡语卡位错误
5. clear() 强制清理 → 规避残留状态
6. 注册表留给 TriggerSystemNew → 规避触发器丢失
7. 连锁构建用 while 循环而非递归 → 规避栈溢出
8. 严格缩进 + 状态机保证执行路径唯一

### 5.7 约束系统（ConstraintManagerNew.gd）

16 种约束类型（CO01-CO16）：
- CO01: 一回合一次
- CO02: 一局一次
- CO12: 自伤
- CO14: 效果发动次数限制
- CO15/CO16: 归属判定（original_owner vs current_owner）

---

## 6. 资源与经济系统

### 6.1 货币

| 货币 | 用途 | 获取方式 |
|------|------|----------|
| 金币 | 通用货币 | 任务奖励、战斗奖励、每日阶梯 |
| 钻石 | 高级货币 | 成就、活动 |

### 6.2 素材类型

6 大类素材：

| 类型 | ID 前缀 | 用途 | 产出方式 |
|------|---------|------|----------|
| 纤维 | F | 卡基制作 | 地图采集 |
| 矿粉 | M | 卡基制作 | 地图采集 |
| 树脂 | R | 卡基制作 | 地图采集 |
| 萃取液 | E | 卡墨调制 | 地图采集 |
| 颜料 | P | 卡墨调制 | 地图采集 |
| 粘合剂 | B | 卡墨调制 | 地图采集 |

### 6.3 采集系统

每个素材定义在 `Data/materials.json`，包含：
- `gather` 字段：按地图 + 地形定义产出概率
- `min` / `max` / `prob`：采集数量和概率
- `carry`：单次携带上限

### 6.4 仓库管理（Warehouse.gd）

统一管理：素材、卡基、卡墨、辅材、卡牌的存储与查看。

---

## 7. 公会系统

### 7.1 等级与称号（PlayerManager.gd）

10 级制卡师等级，每级对应一个称号：

| 等级 | 称号 |
|------|------|
| 1 | 见习卡师 |
| 2-3 | 初级卡师 |
| 4-5 | 中级卡师 |
| 6-7 | 高级卡师 |
| 8-9 | 大师卡师 |
| 10 | 传奇卡师 |

### 7.2 公会任务（GuildTaskManager.gd）

- 任务数量：10 个/次
- 刷新周期：4 小时
- 任务类型：
  - `UNLOCK_CIRCUIT` — 解锁纹路
  - `COLLECT_MATERIAL` — 收集素材
  - `COLLECT_GOLD` — 收集金币
- 提交方式：
  - `SUBMIT_CARD` — 提交卡牌
  - `SUBMIT_MATERIAL` — 提交素材

### 7.3 每日阶梯任务（DailyTasks.gd）

4 类阶梯任务，每类有多个阶梯，完成阶梯获得金币奖励：

| 任务类型 | 标签 | 颜色 |
|----------|------|------|
| 决斗场 | ⚔ | #FF6B6B |
| 杀敌 | 💀 | #FF9800 |
| 通关地图 | 🗺️ | #4FC3F7 |
| 制卡 | 🃏 | #81C784 |

---

## 8. 探索系统

### 8.1 地图列表（Exploration.gd）

| 地图 ID | 名称 | 难度 | 推荐战力 | 背景色 |
|---------|------|------|----------|--------|
| misty_forest | 🌲 迷雾森林 | 简单 | 100 | #1a3a2a |
| flame_cavern | 🔥 火焰洞穴 | 普通 | 300 | #3a1a0a |
| storm_tower | 🌪️ 风暴高塔 | 困难 | - | - |
| shadow_swamp | 🌑 暗影沼泽 | 噩梦 | - | - |
| legendary_ruins | 🏛️ 传说遗迹 | 传说 | - | - |

### 8.2 爬塔地图（MapNodeScene.gd）— 杀戮尖塔风格

8 层爬塔结构：

| 层数 | 名称 | Y 坐标 | 颜色 | 节点数 | 地形 |
|------|------|--------|------|--------|------|
| 0 | 🚀 起点 | 0.87 | #ffffff | 1 | - |
| 1 | 🌲 树林 | 0.77 | #5cb85c | 3 | forest |
| 2 | 🌿 草丛 | 0.67 | #e8a838 | 3 | grass |
| 3 | ⛏️ 矿区 | 0.57 | #9b59b6 | 3 | mine |
| 4 | 💧 溪谷 | 0.47 | #3498db | 3 | valley |
| 5 | 🌪️ 山道 | 0.37 | #e87d38 | 3 | mountain |
| 6 | 🌑 暗穴 | 0.27 | #8e44ad | 3 | cave |
| 7 | 👑 BOSS | 0.13 | #e74c3c | 1 | - |

#### 节点类型

| 类型 | 图标 | 名称 | 权重 |
|------|------|------|------|
| MONSTER | ⚔️ | 野怪 | 40% |
| GATHER | 🎒 | 采集 | 35% |
| REST | 🛌 | 休息 | 25% |
| BOSS | 👑 | BOSS | - |
| START | 🚀 | 出发 | - |

#### 地形专属命名

| 地形 | 野怪名 | 采集名 | 图标 |
|------|--------|--------|------|
| forest | 出没 | 砍伐 | 🌲 |
| grass | 伏击 | 采药 | 🌿 |
| mine | 矿怪 | 挖矿 | ⛏️ |
| valley | 水怪 | 捞晶 | 💎 |
| mountain | 飞龙 | 捕风 | 🌪️ |
| cave | 魔物 | 采晶 | 🕯️ |

连接关系动态生成，每个节点有限扇出，当前节点居中。

### 8.3 敌人数据（Data/enemies.json）

敌人按地图 + 地形组织，每个敌人包含：
- `id` / `name` / `level` / `hp` / `max_hp` / `energy` / `max_energy`
- `element` — 属性
- `desc` — 描述
- `aux_drops` — 辅材掉落表（id + prob）
- `deck` — 敌人卡组（纹理卡 ID 列表）

#### 迷雾森林敌人示例

| 敌人 | 等级 | HP | 属性 | 掉落辅材 |
|------|------|----|------|----------|
| 🌱 树苗精 | 2 | 20 | 地 | AU16, AU17 |
| 🦌 雾角鹿 | 3 | 25 | 风 | AU18, AU19 |
| 🍄 蘑菇人 | 4 | 30 | 地 | AU20, AU21 |
| 🦎 草蜥蜴 | 5 | 30 | 火 | AU22, AU23 |
| 🪓 螳螂刀客 | 6 | 35 | 风 | AU24, AU25 |
| 🐍 青鳞蛇 | 7 | 40 | 水 | AU26, AU27 |
| 🗿 岩石傀儡 | 8 | 50 | 地 | AU28, AU29 |
| 🐛 熔岩蠕虫 | 9 | 50 | 火 | AU30, AU31 |
| 🦂 暗晶蝎 | 10 | 55 | 暗 | AU32, AU33 |
| 💧 水元素 | 11 | 55 | 水 | AU34, AU35 |
| 🦋 风灵蝶 | 12 | 55 | 风 | AU36, AU37 |
| 🔮 光棱镜 | 13 | 65 | 光 | AU38, AU39 |
| 🗿 岩石巨人 | 14 | 65 | 地 | AU40, AU41 |
| 🐦 暗影鸦 | 15 | 60 | 暗 | AU42, AU43 |
| 🦅 风暴鹰 | 16 | 70 | 风 | AU44, AU45 |
| 🕷️ 暗穴蜘蛛 | 17 | 70 | 暗 | AU46, AU47 |
| 🐢 熔岩龟 | 18 | 75 | 火 | AU48, AU49 |
| 🦋 幻光蝶 | 19 | 80 | 光 | AU50, AU51 |
| 🌳 古木(BOSS) | 20 | 100 | 地 | AU52, AU53 |
| 🔥 烈焰(BOSS) | 20 | 100 | 火 | AU52, AU53 |
| 👤 暗影(BOSS) | 20 | 100 | 暗 | AU52, AU53 |

---

## 9. 商店系统

### 9.1 商店街（StoreStreet.gd）

提供 3 个商店入口：
- 📦 素材商店（Shop.tscn）
- 🎁 卡包商店（CardPackShop.tscn）
- 📋 牌组租借（DeckRentShop.tscn）

### 9.2 素材商店（Shop.gd）

- 标签页：`items`（素材购买）/ `lootbox`（盲盒）
- 支持灰鲸广告（HJAds）观看免费刷新
- 广告 App ID: 234475，广告位: 9701263723893953

### 9.3 卡包商店（CardPackShop.gd）

卡包按主题（系列）分层：

| 主题 | 世界观 |
|------|--------|
| 沧澜古界 | 诸国林立，剑修、符修、阵修争锋 |
| 三约纪元 | 灰冠墟、万法之塔、圣光教廷、深渊猎魔 |
| 围棋 | 方寸棋盘，纵横十九道 |
| 你不对劲 | 网络热梗与无厘头笑料 |
| 热恋期 | 甜甜的恋爱日常 |

每个卡包链接到外部 Wiki（GitHub Pages）查看卡牌详情。

### 9.4 牌组租借（DeckRentShop.gd）

可租借 AI 卡组进行对战。

---

## 10. 卡组系统

### 10.1 卡组管理（CardManager.gd）

- 支持多卡组管理
- 每个卡组有唯一 ID 和卡牌列表
- 启动时自动清理失效卡牌 ID
- 支持 `template_id` 匹配（同名卡多实例）

### 10.2 卡组编辑（DeckEdit.gd）

- 选择卡牌加入/移除卡组
- 显示当前卡组强度评级

### 10.3 卡组搜索（DeckSearchPopup.gd）

- 从牌库检索卡牌加入卡组
- 用于卡组检索弹窗（战斗中触发）

---

## 11. 教程系统

### 11.1 教程流程（TutorialManager.gd）

5 幕教程，版本控制（当前版本 2）：

| 进度 | 幕数 | 描述 | 触发场景 |
|------|------|------|----------|
| 0 | 未开始 | 首次进入主界面自动触发觉醒剧情 | Main |
| 1 | 觉醒完成 | 老陈给了三张卡，引导去野外探索 | Main |
| 2 | 初战完成 | 打赢巷口混混，引导去制卡工坊 | Exploration |
| 3 | 制卡完成 | 做出第一张卡，引导去配置牌库 | CardWorkshop |
| 4 | 组卡完成 | 编好第一套卡组，引导去公会 | DeckEdit |
| 5 | 公会完成 | 教程全部完成 | Guild |

教程版本升级时自动重置进度。

---

## 12. 存档系统

### 12.1 存档管理器（SaveManager.gd）

- JSON 格式持久化
- 脏标记（`_dirty`）延迟写盘：修改后标记脏，`save_to_disk()` 无变更时直接 return
- 数据分区：`player` / `tutorial` / `guild_tasks` / 等

### 12.2 存档结构

```json
{
  "player": {
    "gold": 100,
    "diamonds": 50,
    "level": 1,
    "exp": 0,
    "cards": [...],
    "decks": {...},
    "materials": {...},
    "card_bases": [...],
    "card_inks": [...],
    "aux_items": [...]
  },
  "tutorial": {
    "progress": 0,
    "tutorial_version": 2,
    "fifth_act_stage": 0
  },
  "guild_tasks": {
    "data": {
      "version": 2,
      "tasks": [...],
      "refresh": 0
    }
  },
  "settings": {
    "theme": "night",
    "battle_mode": "legacy"
  }
}
```

---

## 13. 主题与 UI 系统

### 13.1 主题模式（Global.gd）

双主题系统：

| 模式 | 枚举值 | 背景图 |
|------|--------|--------|
| 夜间 | NIGHT | bg_night.png |
| 白天 | DAY | bg_day.png |

主题切换通过 `theme_changed` 信号通知所有场景，统一应用样式。

### 13.2 设计分辨率

- 竖屏设计：1080 x 1920
- `Global.ph()` / `Global.pw()` 提供归一化坐标转换
- TopBar: 0~0.083，BottomBar: 0.917~1.0

### 13.3 战斗模式切换

Settings.gd 提供战斗模式切换：
- 竖屏（Legacy）：BattleSceneLegacy.gd
- 横屏（3D）：BattleScene3D.gd

---

## 14. 技术架构

### 14.1 项目结构

```
/workspace
├── *.gd                    # 核心系统（Global, CardManager, BattleManager 等）
├── *.tscn                  # 场景文件
├── battle_new/             # 新版战斗系统重构（21 文件）
├── Data/                   # 游戏数据（JSON）
│   ├── enemies.json        # 敌人数据
│   ├── materials.json      # 素材数据
│   ├── aux_items.json      # 辅材数据
│   ├── local_card_packs.json  # 卡包数据
│   └── local_ai_decks.json   # AI 卡组数据
├── server/                 # Supabase 后端
├── assets/theme/           # 主题资源
└── .monkeycode/docs/       # 文档
```

### 14.2 核心单例

| 单例 | 说明 |
|------|------|
| Global.gd | 全局工具、品质系统、纹路数据、主题管理 |
| SaveManager.gd | 存档读写、脏标记批量写盘 |
| PlayerManager.gd | 玩家数据、公会等级、每日任务 |
| CardManager.gd | 卡牌增删查、卡组管理 |
| BattleManager.gd | 战斗核心管理（旧系统） |
| TutorialManager.gd | 教程状态机 |
| GuildTaskManager.gd | 公会任务管理 |
| CircuitManager.gd | 纹路解锁管理 |

### 14.3 场景导航

```
Main → Guild → PlayerInfo / GuildTasks
     → StoreStreet → Shop / CardPackShop / DeckRentShop
     → Exploration → MapNodeScene / Battle
     → CardWorkshop → CardBaseMaking / InkMaking / AuxMaking / CardEngraving
     → CardGallery → DeckEdit
     → Settings
```

### 14.4 第三方服务

| 服务 | 用途 |
|------|------|
| Supabase | 后端存储（已注释掉） |
| HJAds（灰鲸广告） | 激励视频广告 |
| GitHub Pages | 卡牌 Wiki |
