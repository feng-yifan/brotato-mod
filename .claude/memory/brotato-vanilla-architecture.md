# Brotato Vanilla 架构

> 来源：游戏源代码深度分析
> 更新日期：2026-06-25
> 项目根：`/home/viktor/dev/projects/github/fengyifan/brotato-mod/`

---

## 目录结构

```
项目根/
├── main.gd / main.tscn       # 主 gameplay 场景
├── project.godot              # Godot 项目设置
├── singletons/                # ~60 个 autoload 单例
├── items/                     # 物品/武器/角色/升级/消耗品数据定义
├── weapons/                   # 武器场景、属性、射击行为
├── entities/                  # 实体：敌人、玩家、建筑（炮塔/地雷）
├── effects/                   # 效果脚本类（物品效果 + 武器效果）
├── effect_behaviors/          # 效果行为（场景/敌人/玩家级）
├── challenges/                # 挑战定义
├── ui/                        # 所有 UI：HUD、菜单（商店/暂停/标题）、弹窗
├── zones/                     # 区域/波次定义和背景
├── projectiles/               # 弹丸场景（子弹/火箭/火焰等）
├── resources/                 # 字体/着色器/声音/翻译/主题
├── addons/mod_loader/         # ModLoader 6.3.0
└── mods-unpacked/             # 安装的 mod
```

---

## 核心单例（Autoload Singletons）

| 单例 | 文件 | 规模 | 职责 |
|---|---|---|---|
| `RunData` | `singletons/run_data.gd` | 2053 行 | 运行时游戏状态中心。管理玩家数据、波次、金币、经验、效果字典 |
| `ItemService` | `singletons/item_service.gd` | ~38KB | 内容注册表。管理所有物品、武器、角色、消耗品、升级、套装的注册和商店生成 |
| `ProgressData` | `singletons/progress_data.gd` | ~大 | 存档持久化。解锁进度、挑战完成、设置存储 |
| `WeaponService` | `singletons/weapon_service.gd` | ~27KB | 武器系统。伤害计算、弹丸生成、命中检测、爆炸 |
| `Keys` | `singletons/keys.gd` | ~29KB | 哈希常量表。所有字符串 ID 预计算为整数哈希 |
| `Utils` | `singletons/utils.gd` | ~26KB | 工具函数。属性获取、概率判定、随机数等 |
| `Text` | `singletons/text.gd` | ~ | 文本/翻译处理。效果描述生成、BBCode 颜色 |
| `ZoneService` | `singletons/zone_service.gd` | ~ | 区域/波次数据。关卡定义和无尽波次生成 |
| `ChallengeService` | `singletons/challenge_service.gd` | ~29KB | 挑战系统。解锁追踪和完成判定 |
| `EffectBehaviorService` | `singletons/effect_behavior_service.gd` | ~ | 效果行为管理 |
| `LinkedStats` | `singletons/linked_stats.gd` | ~ | 属性联动系统 |
| `TempStats` | `singletons/temp_stats.gd` | ~ | 临时属性修改（条件触发） |
| `InputService` | `singletons/input_service.gd` | ~ | 输入处理、手柄管理 |
| `SkinManager` | `singletons/skin_manager.gd` | ~ | 物品图标皮肤系统 |

---

## 效果系统（Effect System）— 最核心的架构概念

### 效果字典（Effects Dictionary）

每个玩家的所有属性、状态、特殊能力都存储在一个**扁平字典**中。属性和效果**不是分开存储的**——`stat_max_hp` 就在这个字典里，和 `structures`、`burn_chance` 等特殊效果平级。

```gdscript
PlayerRunData.effects: Dictionary
  "stat_max_hp"         → 15          # 整数：属性值
  "stat_melee_damage"   → 3
  "stat_attack_speed"   → 0.10        # 百分比用小数
  "structures"          → [turret1]   # 数组：建筑列表
  "burn_chance"         → BurningData # 对象：特殊效果数据
  # ...约 200 个键
```

### Effect 资源（`items/global/effect.gd`）

每个物品/武器/角色效果由 Effect 资源定义：

| 字段 | 说明 |
|---|---|
| `key: String` | 效果键（如 `"stat_melee_damage"`） |
| `value: int` | 效果数值（可正可负） |
| `custom_key: String` | 自定义效果类型（如 `"upgrade_random_weapon"`） |
| `storage_method: Enum` | 存储方式（决定如何累加到效果字典） |
| `effect_sign: Enum` | 符号处理方式 |

### 5 种存储方式（Storage Method）

| 方式 | 代码 | 行为 | 示例 |
|---|---|---|---|
| SUM（默认） | 0 | `effects[key] += value` | 大多数属性增减 |
| KEY_VALUE | 1 | `effects[custom_key].append([key, value])` | Anvil 的效果追加到 upgrade_random_weapon 桶 |
| REPLACE | 2 | `effects[key] = value` | 替换当前值 |
| APPEND_KEY | 3 | `effects[custom_key].append(key)` | 追加键到列表 |
| APPEND_KEY_VALUE | 4 | `effects[custom_key].append([key, value])` | 追加键值对到列表 |

### custom_key ≠ key 的关键区别

**这是理解 Brotato 效果系统最重要的一点**。例如 Anvil 的效果：
```
key = stat_armor
custom_key = upgrade_random_weapon
storage_method = KEY_VALUE
```
这不代表"给玩家 +2 护甲"，而是"把 [stat_armor, 2] 追加到 upgrade_random_weapon 桶里"，意思是"随机升级一把武器，该武器获得 stat_armor +2"。

### 效果子类型（~50 个）

- **物品效果**（`effects/items/`）：`burn_chance_effect`、`projectile_effect`、`structure_effect`、`convert_stat_effect`、`class_bonus_effect`、`gain_stat_for_every_stat_effect` 等
- **武器效果**（`effects/weapons/`）：`exploding_effect`、`burning_effect`、`weapon_stack_effect`、`weapon_slow_on_hit_effect` 等
- **消耗品效果**（`effects/consumables/`）：`consumable_healing_effect`、`consumable_damage_effect`

### Effect 的 `apply(player_index)` 核心方法

根据 `storage_method` 对 `PlayerRunData.effects` 字典做不同操作：
- SUM → `effects[key_hash] += value`
- KEY_VALUE → `effects[custom_key_hash].append([key_hash, value])`
- REPLACE → `effects[key_hash] = value`
- APPEND_KEY → `effects[custom_key_hash].append(key_hash)`
- APPEND_KEY_VALUE → `effects[custom_key_hash].append([key_hash, value])`

---

## 哈希键系统（Keys System）

所有字符串 ID 在 `Keys` 类中预计算为整数哈希（djb2 变体，起始值 5381）。运行时查找全部通过哈希值进行。

```gdscript
# Keys 类中的定义
const stat_melee_damage_hash := 12345678
const item_medikit_hash := 87654321

# 运行时使用
RunData.add_stat(Keys.stat_melee_damage_hash, 5, player_index)
```

`Keys.hash_to_string` 字典支持反向查找（hash → 字符串）。

---

## 物品/武器/角色数据模型

### ItemParentData（基类）
`items/global/item_parent_data.gd`：
- `my_id: String`（如 `"weapon_fist_1"`、`"item_medikit"`）
- `tier: Enum`（0=COMMON 到 6=NIGHTMARE）
- `value: int`（基础价格）
- `effects: Array[Resource]`（Effect 资源数组）
- `icon: Texture`、`name: String`

### WeaponData
- `weapon_id: String`（升级链 ID，**不同于** `my_id`——例如 `"weapon_fist"` vs `"weapon_fist_4"`）
- `type: Enum`（MELEE=0 / RANGED=1）
- `stats: WeaponStats`（战斗属性 Resource）
- `upgrades_into: WeaponData`（下一级武器引用 → 构成升级链）
- `sets: Array[SetData]`（武器组）
- `scene: PackedScene`（武器场景预制）

武器升级链是一个单向链表：Tier 1 → Tier 2 → Tier 3 → Tier 4。
`previous_upgrade` 反向指针由 `ItemService._ready()` 自动填充。

### WeaponStats
`weapons/weapon_stats/weapon_stats.gd`：
- `cooldown`（tick 为单位，60 ticks = 1 秒）
- `damage`、`accuracy`、`crit_chance`、`crit_damage`
- `min_range`/`max_range`
- `knockback`、`lifesteal`
- `scaling_stats`（伤害缩放，如 `[["stat_melee_damage", 1.0]]`）

子类：
- `MeleeWeaponStats`：`attack_type`（THRUST/SWEEP）
- `RangedWeaponStats`：`nb_projectiles`、`piercing`、`bounce`、`projectile_speed`

### CharacterData
`items/characters/character_data.gd`：
- `wanted_tags[]`：商店中更容易出现的物品类型
- `banned_items[]`、`banned_item_groups[]`：无法获得的物品
- `banned_upgrades[]`：禁用的属性升级
- `starting_weapons[]`、`starting_items[]`：起始装备

---

## 关键 vanilla 文件速查

| 用途 | 路径 |
|---|---|
| 游戏主场景 | `main.gd` (2093 行) |
| 运行时状态 | `singletons/run_data.gd` |
| 玩家数据 | `singletons/player_run_data.gd` |
| 内容注册 | `singletons/item_service.gd` |
| 武器系统 | `singletons/weapon_service.gd` |
| 效果基类 | `items/global/effect.gd` |
| 物品父类 | `items/global/item_parent_data.gd` |
| 武器数据 | `items/global/weapon_data.gd` |
| 角色数据 | `items/characters/character_data.gd` |
| 升级数据 | `items/upgrades/upgrade_data.gd` |
| 武器属性 | `weapons/weapon_stats/weapon_stats.gd` |
| 哈希常量 | `singletons/keys.gd` |
| 存档 | `singletons/progress_data.gd` |
| 商店 UI | `ui/menus/shop/shop.gd` |
| 升级 UI | `ui/menus/ingame/upgrades_ui.gd` |
| 暂停菜单 | `ui/menus/ingame/pause_menu.gd` |
| 暂停主菜单 | `ui/menus/ingame/ingame_main_menu.gd` |
| 菜单按钮 | `ui/menus/global/my_menu_button.gd` |
| 玩家实体 | `entities/units/player/player.gd` |
| 实体基类 | `entities/entity.gd` |
