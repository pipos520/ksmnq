# Phase 4: 战斗系统迁移计划

## 目标
- 删除旧战斗系统：BattleManager.gd(4343行) + BattleSceneLegacy.gd(4446行) + BattleScene3D.gd(4414行) = 13203行
- 迁移到 battle_new/ 新架构：21文件 5879行
- 拆分 BattleScene3D.gd 为 Scene + UIController + AnimationPlayer

## 现状分析

### 旧系统架构（耦合严重）
```
BattleManager.gd (4343行)
├── 战斗状态机（phase/turn管理）
├── AI决策系统（_build_ai_main_phase_queue, _ai_chain_response等）
├── 效果执行系统（_execute_damage_action, _execute_heal_action等 30+函数）
├── 卡牌数据加载
├── 回合流程控制
└── 胜负判定

BattleScene3D.gd (4414行)
├── UI布局/渲染
├── 输入处理
├── 动画播放
├── 场景管理
└── 战斗逻辑调用（调用BattleManager）

BattleSceneLegacy.gd (4446行)
└── 同上（竖屏版）
```

### 新系统架构（职责分离）
```
battle_new/
├── BattleGameNew.gd (429行) - 核心状态机 + 回合流程
├── BattlePlayerNew.gd (396行) - 玩家状态 + 资源管理
├── BattleCardNew.gd (295行) - 卡牌数据 + 状态
├── BattleAINew.gd (427行) - AI决策（独立于游戏逻辑）
├── EffectSystemNew.gd (888行) - 效果执行引擎
├── EnemyAIController.gd (634行) - 敌人AI控制器
├── BattleScene3DNew.gd (392行) - 场景管理（精简版）
├── CardDragController.gd (1118行) - 拖拽交互
├── TriggerSystemNew.gd (330行) - 触发器系统
├── ConstraintManagerNew.gd (213行) - 约束管理
├── BattleDeckNew.gd (139行) - 卡组管理
├── BattleFieldNew.gd (67行) - 战场管理
├── BattleHandNew.gd (63行) - 手牌管理
├── BattleCard3D.gd (193行) - 3D卡牌渲染
├── FieldSlotManager.gd (100行) - 战场槽位
├── IBattleControllerNew.gd (29行) - 控制器接口
├── ActionQueueNew.gd (86行) - 动作队列
├── BattleGraveNew.gd (40行) - 墓地管理
├── BattleBanishNew.gd (40行) - 放逐区管理
└── BattleCard3D.tscn - 卡牌场景
```

## 迁移策略

### 阶段 1: API 桥接（兼容性层）
**目标**: 创建适配器，使旧调用无需修改即可使用新系统

**步骤**:
1. 创建 `BattleManagerBridge.gd` - 包装 BattleGameNew，提供旧 API
2. 创建 `BattleSceneBridge.gd` - 包装 BattleScene3DNew，提供旧 API
3. 修改项目配置，使用桥接层

**风险**: 低（纯包装，不改变逻辑）

### 阶段 2: 场景迁移
**目标**: 逐步迁移 BattleScene3D 和 BattleSceneLegacy 使用新系统

**步骤**:
1. 创建 BattleScene3DUIController.gd - UI 控制器
2. 创建 BattleScene3DAnimationPlayer.gd - 动画播放器
3. 迁移 BattleScene3D.gd 到使用新系统
4. 迁移 BattleSceneLegacy.gd 到使用新系统

**风险**: 中（需要大量 UI/输入逻辑重构）

### 阶段 3: 旧系统清理
**目标**: 删除旧系统文件

**步骤**:
1. 删除 BattleManager.gd
2. 删除 BattleSceneLegacy.gd
3. 删除 BattleScene3D.gd（或保留为旧版兼容）
4. 更新所有引用

**风险**: 高（删除大量代码，需要充分测试）

## 技术挑战

### 1. API 差异
| 旧系统 | 新系统 |
|--------|--------|
| `start_battle(deck_id, enemy_name, auto_start)` | `start_battle(deck_id, enemy_data)` |
| `current_phase` (枚举) | `phase` (枚举) |
| `player_self` (属性) | `players[0]` (数组访问) |
| `_execute_damage_action(...)` | `EffectSystemNew.execute(...)` |

### 2. 信号系统
- 旧系统: 直接函数调用
- 新系统: 信号驱动（player_card_summoned, turn_changed等）

### 3. 状态管理
- 旧系统: BattleManager 集中管理
- 新系统: BattleGameNew + BattlePlayerNew + BattleCardNew 分散管理

### 4. AI 系统
- 旧系统: BattleManager 内置 AI 逻辑（~2000行）
- 新系统: BattleAINew + EnemyAIController 独立实现

## 测试计划

由于环境无 Godot 二进制，采用静态验证：
1. 检查所有函数调用是否有对应实现
2. 检查信号连接是否匹配
3. 检查属性访问是否有效
4. 创建迁移验证脚本检查引用完整性

## 时间估算
- 阶段 1（API桥接）: 1-2天
- 阶段 2（场景迁移）: 3-5天
- 阶段 3（旧系统清理）: 1-2天

总计: 5-9天

## 当前状态
- [ ] 阶段 1: API 桥接
- [ ] 阶段 2: 场景迁移
- [ ] 阶段 3: 旧系统清理

---

## 快速开始

如果时间有限，建议优先执行：
1. 创建 BattleManagerBridge.gd 桥接层
2. 修改 BattleScene3D.gd 使用桥接层
3. 保留旧文件作为备份
4. 逐步验证后删除旧系统