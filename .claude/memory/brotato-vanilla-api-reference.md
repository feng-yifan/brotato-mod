---
title: Brotato Vanilla API 完整参考
description: >
  Brotato 原版游戏核心单例的 API 参考，属于 vanilla 领域知识。
  涵盖 RunData（货币系统、属性、效果、波次）、ItemService（内容注册、商店生成）、
  ProgressData（存档持久化）、PlayerRunData（玩家运行时数据）、Keys（哈希常量）、
  Utils（工具函数）、TempStats / LinkedStats、ShopItem、WeaponService（武器系统、
  伤害计算、弹丸生成）等单例的完整方法签名、业务语义和使用场景。
game_version: 1.1.15.4
---

# Brotato Vanilla API 完整参考

> 本文件是 Brotato 反编译源代码中**所有公开 API 的系统性目录**。
> 按单例/文件分组，每个 API 记录其完整签名、业务含义和使用场景。

---

## 1. RunData — 运行时数据单例

`RunData` (extends Node) 是游戏最核心的运行时单例，管理**当前一局**游戏的所有动态数据。
路径：`singletons/run_data.gd`

### 1.1 货币系统

#### `get_player_currency(player_index: int) -> int`
- **业务含义**：返回指定玩家在商店中可用于购买物品的**货币总量**。如果玩家有 `hp_shop` 效果，返回经过 gain 修正的最大生命值（`get_stat(stat_max_hp_hash, player_index)`）；否则返回 `get_player_gold(player_index)`（普通金币）。
- **源码逻辑**：
```gdscript
var effects := get_player_effects(player_index)
return get_stat(Keys.stat_max_hp_hash, player_index) as int \
if effects[Keys.hp_shop_hash] else get_player_gold(player_index)
```
- **使用场景**：商店购买决策中判断"买不买得起"的统一入口。这是"当前可用货币"的正确查询方式。

#### `get_player_gold(player_index: int) -> int`
- **业务含义**：获取指定玩家当前持有的**金币**数量（仅金币，不受 hp_shop 影响）。从 `players_data[player_index].gold` 直接读取原始存储值。
- **使用场景**：商店/升级刷新价格判断（刷新永远花金币）。不应在普通购买场景中替代 `get_player_currency`。

#### `remove_currency(value: int, player_index: int) -> void`
- **业务含义**：从玩家当前货币中扣除指定数量。与 `get_player_currency` 形成对称关系——hp_shop 模式扣最大生命值（`remove_stat(stat_max_hp_hash, value)`），普通模式扣金币（`remove_gold(value)`）。
- **使用场景**：vanilla 购买流程已调用此方法；mod 通常不需要直接调用。

#### `add_gold(value: int, player_index: int) -> void`
- **业务含义**：增加玩家金币，触发挑战记录和 `gold_changed` 信号。
- **使用场景**：拾取金币、波次结算奖励。

#### `remove_gold(value: int, player_index: int) -> void`
- **业务含义**：减少玩家金币（下限为 0），发出 `gold_changed` 信号。不受 hp_shop 影响。
- **使用场景**：刷新商店扣费、特殊扣钱效果。

#### `add_bonus_gold(value: int, check_conversions: bool = true) -> void`
- **业务含义**：增加奖励金币。如果玩家有 `convert_bonus_gold` 效果，自动按比例转换为属性加成。
- **使用场景**：波次结算、丰收收益。

#### `set_bonus_gold(value: int) -> void`
- **业务含义**：设置奖励金币值（下限 0），发出 `bonus_gold_changed` 信号。

### 1.2 效果/属性系统

#### `get_player_effects(player_index: int) -> Dictionary`
- **业务含义**：返回指定玩家的**完整 effects 字典引用**（不是副本）。键为 int hash，值为各种类型的聚合效果数据。
- **数据结构**：`{stat_max_hp_hash: 10, hp_shop_hash: 0, structures_hash: [...], ...}`
- **使用场景**：批量读取多个效果、检查 flag 类效果（如 hp_shop）、读取数组类效果（structures 等）。**返回引用，修改会直接影响玩家数据**。

#### `get_player_effect(key: int, player_index: int) -> variant`
- **业务含义**：获取玩家指定效果的**原始裸值**。等价于 `get_player_effects(player_index)[key]`（加 assert 检查）。
- **使用场景**：读取 flag 类效果（开关）、数组类效果（structures、explode_on_hit 等）。**不经过 gain 修正**。

#### `get_player_effect_bool(key: int, player_index: int) -> bool`
- **业务含义**：获取指定效果的布尔值（`> 0` 则 true）。用于 flag 类效果的便捷判断。
- **使用场景**：`hp_shop`、`pacifist` 等 0/1 标志位。

#### `get_stat(stat_hash: int, player_index: int) -> float`
- **业务含义**：获取指定 stat 的**最终生效值**（= 裸效果值 × gain 系数）。只处理**永久效果**。
- **公式**：`get_player_effect(stat_hash, player_index) * get_stat_gain(stat_hash, player_index)`
- **注意**：这不是游戏实际使用的完整 stat 值！完整值需要叠加 TempStats 和 LinkedStats，通过 `Utils.get_stat()` 获取。

#### `get_stat_gain(stat_hash: int, player_index: int) -> float`
- **业务含义**：获取指定 stat 的增益倍率。查找 `gain_<stat_name>` 效果，如值为 15 则返回 1.15（+15%）。未找到返回 1.0。
- **使用场景**：需要单独查看增益倍率时。

#### `add_stat(stat_hash: int, value: int, player_index: int) -> void`
- **业务含义**：直接为玩家增加一项永久 stat 值（不通过 Effect 系统），发射 `stat_added` 信号。
- **使用场景**：升级奖励、属性药水。

#### `remove_stat(stat_hash: int, value: int, player_index: int) -> void`
- **业务含义**：直接减少玩家永久 stat 值，发射 `stat_removed` 信号。
- **使用场景**：属性扣除效果。

### 1.3 物品/武器

#### `get_player_items(player_index: int) -> Array`
- **业务含义**：返回玩家物品列表的**浅拷贝**（`items.duplicate()`）。修改副本不影响原数据。
- **数据结构**：`Array[ItemData/CharacterData]`（角色也作为 item 存入）。

#### `get_player_items_ref(player_index: int) -> Array`
- **业务含义**：返回玩家物品列表的**原始引用**。修改会直接影响玩家数据。仅内部高性能操作使用。

#### `get_player_weapons(player_index: int) -> Array`
- **业务含义**：返回玩家武器列表的**浅拷贝**。
- **数据结构**：`Array[WeaponData]`

#### `get_player_weapons_ref(player_index: int) -> Array`
- **业务含义**：返回玩家武器列表的**原始引用**。

#### `add_item(item: ItemData, player_index: int, is_selection: bool = false) -> void`
- **业务含义**：为玩家添加一个物品。包括更新列表、缓存、应用效果、添加外观、更新套装/关联效果。
- **使用场景**：购买/拾取物品。

#### `remove_item(item: ItemData, player_index: int, by_id: bool = false) -> void`
- **业务含义**：从玩家移除物品。撤回效果、移除外观、更新关联效果。如果物品有替换品则添加替换品。

#### `add_weapon(weapon: WeaponData, player_index: int, is_selection: bool = false) -> WeaponData`
- **业务含义**：为玩家添加一把武器。复制武器数据、更新缓存/效果/套装/挑战。返回新武器副本。

#### `remove_weapon(weapon: WeaponData, player_index: int) -> int`
- **业务含义**：移除武器（按武器匹配），返回武器的已追踪值。

#### `get_nb_item(item_id_hash: int, player_index: int, use_cache: bool = true) -> int`
- **业务含义**：获取玩家拥有某个物品的数量（带缓存，避免每次遍历数组）。

#### `get_remaining_max_nb_item(item_data: ItemData, player_index: int) -> int`
- **业务含义**：获取某物品还可持有的剩余数量（基于 `item_data.max_nb` 限制）。

#### `get_free_weapon_slots(player_index: int) -> int`
- **业务含义**：获取玩家剩余可用武器槽位数。

#### `has_weapon_slot_available(shop_weapon: WeaponData, player_index: int) -> bool`
- **业务含义**：判断是否有空位存放该武器（考虑唯一/类型/槽位限制）。

#### `can_combine(weapon_data: WeaponData, player_index: int) -> bool`
- **业务含义**：判断某武器是否可以合成（≥2 把相同武器、有升级路径、未达最高）。

#### `apply_item_effects(item_data: ItemParentData, player_index: int) -> void`
- **业务含义**：应用一个物品/武器的所有效果到玩家身上。
- **使用场景**：获得物品/武器时调用。

#### `unapply_item_effects(item_data: ItemParentData, player_index: int) -> void`
- **业务含义**：撤回一个物品/武器的所有效果。

### 1.4 游戏状态

#### `current_wave: int`
- **业务含义**：当前波次编号（0-based）。0-19 标准，20+ 无尽。
- **访问方式**：`RunData.get("current_wave")`

#### `current_difficulty: int`
- **业务含义**：当前难度等级（0-5），一局内不变。
- **访问方式**：`RunData.get("current_difficulty")`

#### `current_zone: int`
- **业务含义**：当前区域（0=森林，1=深渊等）。

#### `nb_of_waves: int`
- **业务含义**：总波次数（默认 20）。

#### `is_endless_run: bool`
- **业务含义**：是否无尽模式。

#### `wave_in_progress: bool`
- **业务含义**：波次是否正在进行中。

#### `run_won: bool`
- **业务含义**：本轮是否获胜。

#### `play_mode: int` (enum PlayMode)
- **业务含义**：游戏模式：SOLO、COOP、STREAMPLAY_LOCAL、STREAMPLAY_INTERNET。

### 1.5 玩家管理

#### `get_player_count() -> int`
- **业务含义**：返回玩家数量（`players_data.size()`）。单人=1。

#### `get_player_level(player_index: int) -> int`
- **业务含义**：获取玩家当前等级。

#### `get_player_xp(player_index: int) -> float`
- **业务含义**：获取玩家当前经验值。

#### `add_xp(value: int, player_index: int) -> void`
- **业务含义**：增加经验，自动处理升级链。

### 1.6 生命值/治疗

#### `get_player_current_health(player_index: int) -> int`
- **业务含义**：获取玩家当前生命值。波次中返回实时血量，商店中返回最大血量。

#### `get_player_max_health(player_index: int) -> int`
- **业务含义**：获取玩家最大生命值（下限 1）。

#### `get_player_missing_health(player_index: int) -> int`
- **业务含义**：获取玩家已损失生命值（= max - current）。

### 1.7 商店锁定

#### `get_player_locked_shop_items(player_index: int) -> Array`
- **业务含义**：返回该玩家已锁定的商店物品列表的浅拷贝。每个元素为 `[item_data, wave_value]`。

#### `lock_player_shop_item(item_data: ItemParentData, wave_value: int, player_index: int) -> void`
- **业务含义**：锁定商店中的物品（保留到下一波）。

#### `unlock_player_shop_item(item_data: ItemParentData, player_index: int) -> void`
- **业务含义**：解锁商店中的物品。

### 1.8 波次/生命循环

#### `is_last_wave() -> bool`
- **业务含义**：判断是否最后一波（无尽模式始终返回 false）。

#### `is_elite_wave(type: int = -1) -> bool`
- **业务含义**：判断当前波次是否为精英波次。

#### `get_endless_factor(p_wave: int = -1) -> float`
- **业务含义**：获取无尽模式下指定波次的难度缩放因子。波次减去 20 后按三角数公式计算。

#### `get_state() -> Dictionary`
- **业务含义**：获取当前完整运行状态的快照（用于保存/重试）。

#### `resume_from_state(state: Dictionary) -> void`
- **业务含义**：从快照恢复所有运行数据。

### 1.9 常量

| 常量 | 值 | 含义 |
|---|---|---|
| `DUMMY_PLAYER_INDEX` | 123 | 虚拟玩家索引，用于返回安全默认值 |
| `NB_SHOP_ITEMS` | （同 ItemService） | 暂未在此文件定义 |
| `ENDLESS_HARVESTING_DECREASE` | 20 | 无尽模式下每波收获递减值 |

### 1.10 信号

| 信号 | 触发时机 |
|---|---|
| `levelled_up(player_index)` | 角色升级 |
| `gold_changed(new_value, player_index)` | 金币变化 |
| `bonus_gold_changed(new_value)` | 奖励金币变化 |
| `stat_added(stat_name, value, db_mod, player_index)` | stat 增加 |
| `stat_removed(stat_name, value, db_mod, player_index)` | stat 减少 |
| `stats_updated(player_index)` | stat 批量更新完成 |
| `damage_effect(value, player_index, armor_applied, dodgeable)` | 玩家受到伤害 |
| `lifesteal_effect(value, player_index)` | 生命窃取触发 |
| `healing_effect(value, player_index, tracking_key)` | 治疗触发 |

---

## 2. ItemService — 物品系统中央注册表

`ItemService` (extends Node) 是所有物品定义（道具、武器、升级、消耗品、套装等）的**全局静态注册表 + 工厂**。
路径：`singletons/item_service.gd`

### 2.1 两层数据架构

**第一层：原始注册表** — 编辑器绑定的 `.tres` 资源数组，启动时静态加载

| 属性 | 类型 | 业务含义 |
|---|---|---|
| `items` | `Array[ItemData]` | 所有道具的全局定义。每个元素是一个 `.tres` 资源 |
| `weapons` | `Array[WeaponData]` | 所有武器的全局定义 |
| `upgrades` | `Array[UpgradeData]` | 所有升级选项的定义 |
| `consumables` | `Array[ConsumableData]` | 所有消耗品（含箱子物品）的定义 |
| `sets` | `Array[SetData]` | 所有武器套装的定义 |
| `stats` | `Array[StatData]` | 所有属性的元数据（名称、图标、是否主属性等） |
| `difficulties` | `Array[DifficultyData]` | 难度等级的定义 |
| `characters` | `Array[CharacterData]` | 所有可玩角色数据 |
| `elites` | `Array[EliteData]` | 所有精英敌人数据 |
| `bosses` | `Array[BossData]` | 所有 Boss 敌人数据 |
| `backgrounds` | `Array[Resource]` | 关卡背景资源（可通过 `add/remove_backgrounds` 动态修改） |

**第二层：运行时池 `_tiers_data`** — 按品质（Tier）分层、按解锁状态过滤的物品池，所有随机生成都从此采样。

`_tiers_data` 结构（按 TierData 枚举索引）：
```
[ALL_ITEMS(0), ITEMS(1), WEAPONS(2), CONSUMABLES(3), UPGRADES(4),
 MIN_WAVE(5), BASE_CHANCE(6), WAVE_BONUS_CHANCE(7), MAX_CHANCE(8)]
```

### 2.2 常量

| 常量 | 值 | 业务含义 |
|---|---|---|
| `NB_SHOP_ITEMS` | 4 | 商店每轮每玩家的商品槽位数量 |
| `CHANCE_WEAPON` | 0.35 | 商店格出武器的基准概率 |
| `CHANCE_SAME_WEAPON` | 0.2 | 优先刷同类武器的概率 |
| `CHANCE_SAME_WEAPON_SET` | 0.35 | 优先刷同套装武器的概率 |
| `MAX_WAVE_TWO_WEAPONS_GUARANTEED` | 2 | 前 2 波必出 2 把武器 |
| `MAX_WAVE_ONE_WEAPON_GUARANTEED` | 5 | 前 5 波至少出 1 把武器 |

### 2.3 价格计算

#### `get_value(wave: int, base_value: int, player_index: int, affected_by_items_price_stat: bool, is_weapon: bool, item_id: int = Keys.empty_hash) -> int`
- **业务含义**：计算物品在商店中的**最终售价**。综合考虑：基础价格、波次通胀（每波+1）、武器/物品价格倍率、特定物品价格因子、通胀修正、无尽模式因子。
- **核心公式**（简化）：
  ```
  result = max(1, (base_val * (1 + weapon_price_factor) + wave
           + base_val * wave * base_inflation)
           * items_price_factor * (1 + endless_factor))
  ```
- **参数含义**：
  - `affected_by_items_price_stat`：是否受玩家"物品价格"效果影响（回收价计算时设为 false）
  - `is_weapon`：控制用 `weapons_price` 还是 `items_price` 修正
- **使用场景**：vanilla 的 `shop_item.set_shop_item()` 已调用此方法，mod 通常只需读 `ShopItem.value`。

#### `get_recycling_value(wave: int, from_value: int, player_index: int, is_weapon: bool = false, affected_by_items_price_stat: bool = true) -> int`
- **业务含义**：计算物品回收价。基准为 25% + recycling_gains 加成，取回收价与商店售价中的较小值。

#### `get_reroll_price(wave: int, reroll_count: int, player_index: int) -> Array`
- **业务含义**：计算商店刷新价格。返回 `[实付价格, 折扣金额]`。

### 2.4 物品生成

#### `get_player_shop_items(wave: int, player_index: int, args: ItemServiceGetShopItemsArgs) -> Array`
- **业务含义**：为指定玩家生成一轮商店的 4 个（`NB_SHOP_ITEMS`）商品。内部调用 `_get_rand_item_for_wave` 逐个随机选择，前几波强制出武器。

#### `_get_rand_item_for_wave(wave: int, player_index: int, type: int, args: GetRandItemForWaveArgs) -> ItemParentData`
- **业务含义**：核心物品随机选择函数。按品质→池子→过滤→随机的流程：
  1. `get_tier_from_wave` 决定品质
  2. 武器：应用 min/max_tier、去重、优选同武器/同套装
  3. 物品：筛选 wanted_tags、移除禁用物品、处理限购（`max_nb`）

#### `get_tier_from_wave(wave: int, player_index: int, increase_tier: int = 0) -> int`
- **业务含义**：根据波次和玩家幸运值，按 `_tiers_data` 中各品质的 BASE_CHANCE/WAVE_BONUS_CHANCE/MAX_CHANCE 参数随机决定品质。结果 clamp 到 Common-Legendary。

#### `get_upgrades(level: int, number: int, old_upgrades: Array, player_index: int) -> Array`
- **业务含义**：升级时生成升级选项。如玩家有武器槽扩展需求（`weapon_slot_upgrades`），只返回武器槽升级项；否则生成 `number` 个不重复升级选项。

#### `get_upgrade_data(level: int, player_index: int) -> UpgradeData`
- **业务含义**：根据等级决定升级品质（5→UNCOMMON, 10/15/20→RARE, 25+→LEGENDARY），随机选取。

### 2.5 消耗品

#### `get_consumable_to_drop(unit: Unit, item_chance: float) -> ConsumableData`
- **业务含义**：敌人死亡时判定是否掉落消耗品。根据基础掉落率 + 幸运，决定品质和类型。

#### `process_item_box(consumable_data: ConsumableData, wave: int, player_index: int) -> ItemParentData`
- **业务含义**：处理传说物品箱，从玩家已有+锁定物品外随机选一件传说物品。

### 2.6 Mod 扩展点

#### `add_mod_item(item: ItemParentData) -> void`
- **业务含义**：向 `items` 数组追加 Mod 物品。如果 `unlocked_by_default=true` 且尚未解锁，自动写入 `ProgressData.items_unlocked`。

#### `remove_mod_item(p_item: ItemParentData) -> void`
- **业务含义**：从 `items` 数组移除指定 Mod 物品，并从解锁列表移除。

### 2.7 ID 判断

#### `is_item_id(item_id: int) -> bool`
- **业务含义**：判断给定 `my_id_hash` 是否存在于 `items` 数组中。

#### `is_weapon_id(weapon_id: int) -> bool`
- **业务含义**：判断给定 `weapon_id_hash` 是否存在于 `weapons` 数组中。

### 2.8 查询函数

#### `get_color_from_tier(tier: int, dark_version: bool = false) -> Color`
- **业务含义**：根据品质返回 UI 颜色。优先级从 `ProgressData.settings` 用户自定义颜色取值，无则用默认值。
- **映射**：COMMON→白(或灰)，UNCOMMON(1)→蓝，RARE(2)→紫，LEGENDARY(3)→红，DANGER_4(4)→橙，DANGER_5(5)/NIGHTMARE(6)→金

#### `get_item_from_id(item_id: int) -> ItemData`
- **业务含义**：通过 `my_id_hash` 查找 ItemData。带缓存。

#### `get_weapon_from_weapon_id(weapon_id: int) -> WeaponData`
- **业务含义**：通过 `weapon_id_hash` 查找 WeaponData（返回分组中第一个）。

#### `get_stat(stat_hash: int) -> Resource`
- **业务含义**：通过 hash 查找属性元数据（StatData）。

#### `get_stat_icon(stat_hash: int) -> Resource`
- **业务含义**：获取属性的图标资源。

#### `get_stat_description_text(stat_hash: int, value: int, player_index: int) -> String`
- **业务含义**：根据 stat_hash 和数值生成人类可读的属性描述文本。对 armor、harvesting、lifesteal 等有特殊处理。

### 2.9 初始化

#### `init_unlocked_pool() -> void`
- **业务含义**：根据 `ProgressData` 中的解锁列表，从 `items`/`weapons`/`upgrades`/`consumables` 中过滤已解锁条目，填入 `_tiers_data` 的品质池。每次新游戏开始时调用。

#### `reset_tiers_data() -> void`
- **业务含义**：清空品质池，为重新构建做准备。

---

## 3. ProgressData — 持久化进度单例

`ProgressData` (extends Node) 管理跨局持久化数据：存档、设置、解锁进度。
路径：`singletons/progress_data.gd`

### 3.1 核心属性

| 属性 | 类型 | 业务含义 |
|---|---|---|
| `settings` | `Dictionary` | 所有持久化设置（音量、画面、语言、辅助功能、DLC 开关、颜色主题） |
| `items_unlocked` | `Array[int]` | 已解锁的道具 `my_id_hash` 列表 |
| `weapons_unlocked` | `Array[int]` | 已解锁的武器 `weapon_id_hash` 列表 |
| `characters_unlocked` | `Array[int]` | 已解锁的角色 `my_id_hash` 列表 |
| `difficulties_unlocked` | `Array[CharacterDifficultyInfo]` | 每个角色在每个区域的难度解锁进度 |
| `data` | `Dictionary` | 全局统计数据（`run_won`, `enemies_killed`, `materials_collected` 等） |
| `items_bought` | `Dictionary` | key=物品 hash，value=购买次数 |
| `killed_enemies` | `Dictionary` | key=敌人 hash，value=击杀次数 |
| `saved_run_state` | `Dictionary` | 保存的当前运行状态（用于继续游戏） |

### 3.2 `settings` 中的关键字段

| 字段 | 类型 | 含义 |
|---|---|---|
| `color_positive` | String (HTML) | 正面效果颜色（默认 "#00ff00"） |
| `color_negative` | String (HTML) | 负面效果颜色（默认 "#ff0000"） |
| `tier_0_color` ~ `tier_5_color` | String (HTML) | 各品质 UI 颜色 |
| `tier_0_color_dark` ~ `tier_5_color_dark` | String (HTML) | 各品质暗色背景 |
| `font_size` | float | 字号缩放 |
| `language` | String | 语言 |
| `deactivated_dlcs` | Array | 禁用的 DLC |

### 3.3 难度解锁结构

`difficulties_unlocked` 中每个 `CharacterDifficultyInfo` 包含：
- `character_id: String` — 角色 ID
- `zones_difficulty_info: Array[ZoneDifficultyInfo]`
  - `zone_id: int` — 区域
  - `max_selectable_difficulty: int` — 可选的最高难度
  - `max_difficulty_beaten: DifficultyScore` — 已通关最高难度
  - `max_endless_wave_beaten: DifficultyScore` — 无尽模式最高波次

### 3.4 常量

| 常量 | 值 | 含义 |
|---|---|---|
| `VERSION` | `"1.1.15.4"` | 存档格式版本号 |
| `MAX_DIFFICULTY` | 6 | 最高难度等级（Nightmare） |
| `DLC_1_APP_ID` | 2868390 | 深渊恐怖 DLC 的 Steam App ID |

### 3.5 核心方法

#### `save() -> void`
- **业务含义**：将当前全部进度（解锁、统计、设置）写入磁盘。

#### `load_game_file(try_fallback: bool = true) -> void`
- **业务含义**：按优先级加载存档：Beta → V3 → V2+V1 → V1 → fallback → 新建。

#### `save_settings() -> void`
- **业务含义**：将 settings 写入 `settings.json`。

#### `load_settings() -> void`
- **业务含义**：从磁盘读取并合并设置到 `settings` 字典。

#### `unlock_all() -> void`
- **业务含义**：解锁全部内容（道具、武器、角色、难度、挑战）。

#### `add_unlocked_by_default() -> void`
- **业务含义**：将各服务中 `unlocked_by_default=true` 的内容追加到解锁列表。

#### `reset() -> void`
- **业务含义**：重置全部解锁和统计数据，然后添加默认解锁项。

#### `save_run_state(shop_items, reroll_count, ...) -> void`
- **业务含义**：保存当前运行状态（商店物品、重掷计数等），用于退出后继续。

#### `get_active_dlc_ids() -> Array`
- **业务含义**：返回当前激活的 DLC ID 列表。

#### `is_dlc_available_and_active(dlc_id: String) -> bool`
- **业务含义**：检查 DLC 是否可用且未被禁用。

---

## 4. PlayerRunData — 单玩家运行时数据

`PlayerRunData` (extends Reference) 是单个玩家的运行时数据容器。
路径：`singletons/player_run_data.gd`

### 4.1 核心字段

| 字段 | 类型 | 默认值 | 业务含义 |
|---|---|---|---|
| `gold` | int | 0 | 当前金币数（游戏内货币） |
| `current_health` | int | 10 | 当前生命值 |
| `current_level` | int | 0 | 当前等级 |
| `current_xp` | float | 0.0 | 当前经验值 |
| `weapons` | Array | [] | 已装备的武器列表 |
| `items` | Array | [] | 已装备的道具列表 |
| `effects` | Dictionary | `init_effects()` | **核心效果字典**（详见 4.2） |
| `banned_items` | Array | [] | 已禁用的物品 ID 列表（Ban 模式） |

### 4.2 `effects` 字典结构

`init_effects()` 返回包含约 100+ 个键的效果字典，可分为几大类：

**基础属性**（16+ 个核心 stat，使用 `Keys.stat_*_hash`）：
```
stat_max_hp: 10, stat_armor: 0, stat_crit_chance: 0, stat_luck: 0,
stat_attack_speed: 0, stat_elemental_damage: 0, stat_hp_regeneration: 0,
stat_lifesteal: 0, stat_melee_damage: 0, stat_percent_damage: 0,
stat_dodge: 0, stat_engineering: 0, stat_range: 0, stat_ranged_damage: 0,
stat_speed: 0, stat_harvesting: 0
```

**增益比率**（17+ 个 `gain_stat_*`）：所有初始值为 0。存在时表示 +X% 增益。

**能力上限**（5 个）：
```
hp_cap: 大数, speed_cap: 大数, dodge_cap: 60, curse_cap: 0, crit_chance_cap: 大数
```

**标志位**（0/1 开关）：
```
hp_shop: 0, pacifist: 0, die_in_one_hit: 0, lose_hp_per_second: 0,
no_melee_weapons: 0, no_ranged_weapons: 0, can_attack_while_moving: 1,
disable_item_locking: 0, can_burn_enemies: 1, ...
```

**数组类效果**（初始值 `[]`）：
```
structures, explode_on_hit, starting_item, cursed_starting_item,
starting_weapon, cursed_starting_weapon, stat_links, convert_bonus_gold,
temp_stats_while_moving, temp_stats_while_not_moving, ...
```

**特殊类型**：
- `burn_chance: BurningData.new()` — 燃烧数据对象

### 4.3 方法

#### `static init_stats(all_null_values: bool = false) -> Dictionary`
- **业务含义**：生成核心 stat 的初始值字典。`all_null_values=true` 用于纯粹叠加场景（如 TempStats 从零开始）。

#### `serialize() -> Dictionary`
- **业务含义**：将玩家数据序列化为 Dictionary（用于存档）。

#### `deserialize(data: Dictionary) -> PlayerRunData`
- **业务含义**：从 Dictionary 反序列化恢复玩家数据。

#### `duplicate() -> PlayerRunData`
- **业务含义**：深度复制整个对象（用于状态快照）。

---

## 5. Keys — Hash 键系统

`Keys` (extends Node) 是游戏的统一标识系统，将人类可读字符串转换为 int hash。
路径：`singletons/keys.gd`

### 5.1 核心函数

#### `generate_hash(text: String) -> int`
- **业务含义**：将任意字符串转换为整数 hash。空字符串返回 `empty_hash`（5381）。同时将反向映射写入 `hash_to_string` 字典。使用 GDScript `String.hash()` 算法。
- **断言**：入参不能是纯数字。

### 5.2 特殊常量

| 常量 | 值 | 含义 |
|---|---|---|
| `empty_hash` | 5381 | 空字符串的 hash |
| `hash_to_string` | `{5381: ""}` | hash→字符串的反向映射字典 |

### 5.3 业务分类

Keys 的所有 hash 常量覆盖以下业务域：

| 分类 | 数量 | 示例 |
|---|---|---|
| 基础属性 stat | ~40 个 | `stat_max_hp_hash`, `stat_speed_hash`, `stat_dodge_hash` 等 |
| 效果 effect | ~40 个 | `effect_temp_stats_per_interval_hash`, `effect_piercing_damage_hash` 等 |
| 物品 item | ~50 个 | `item_cake_hash`, `item_piggy_bank_hash`, `item_coupon_hash` 等 |
| 游戏参数 | ~20 个 | `weapons_price_hash`, `number_of_enemies_hash`, `map_size_hash` 等 |
| 战斗修饰器 | ~20 个 | `piercing_hash`, `bounce_hash`, `burning_cooldown_reduction_hash` 等 |
| 上限 cap | 5 个 | `hp_cap_hash`, `speed_cap_hash`, `dodge_cap_hash` 等 |
| 标志位 flag | ~15 个 | `hp_shop_hash`, `pacifist_hash`, `die_in_one_hit_hash` 等 |
| 角色 character | ~12 个 | `character_jack_hash`, `character_king_hash` 等 |
| 增益比率 gain | ~17 个 | `gain_stat_max_hp_hash` 等 |

---

## 6. Utils — 工具函数与 stat 计算

`Utils` (extends Node) 提供全局工具函数和**游戏最终 stat 值的统一出口**。
路径：`singletons/utils.gd`

### 6.1 stat 计算（核心！）

#### `get_stat(stat_hsh: int, player_index: int) -> float`
- **业务含义**：**这是游戏中属性计算的最终统一出口**。所有游戏逻辑查询"玩家的某个属性值"都应通过此方法。
- **公式**：`RunData.get_stat + TempStats.get_stat + LinkedStats.get_stat`
  即：永久属性 + 临时属性 + 关联属性的链接加成。
- **结果被缓存**到 `_stat_caches`，直到调用 `reset_stat_cache`。
- **与 RunData.get_stat 的关系**：`RunData.get_stat` 只处理永久效果并用 gain 修正；`Utils.get_stat` 在此基础上叠加临时效果和 link 效果，是**完整最终值**。

#### `get_capped_stat(stat_hsh: int, player_index: int) -> float`
- **业务含义**：获取带上限约束的 stat 值。支持 5 种有上限的属性：max_hp、speed、dodge、curse、crit_chance。返回 `min(get_stat, cap)`。

#### `reset_stat_cache(player_index: int) -> void`
- **业务含义**：清空指定玩家的 stat 缓存。当 stat 变化后需调用，使下次 `get_stat` 重新计算。

### 6.2 其他工具函数

#### `merge_dictionaries(a: Dictionary, b: Dictionary) -> Dictionary`
- **业务含义**：递归合并两个字典。嵌套字典递归合并；非字典类型 b 覆盖 a。

#### `get_curse_factor(value: float, max_val: float = 100.0) -> float`
- **业务含义**：诅咒值的难度影响曲线。公式：`max_val * (1 - 1/(1 + value/50))`，随诅咒值递增而逐渐饱和。

#### `get_primary_stat_keys() -> Array`
- **业务含义**：返回所有主属性的 hash 列表（通过 `ItemService.stats` 中 `is_primary_stat` 判断）。

#### `convert_stats(stats: Array, player_index: int, permanent: bool = true) -> void`
- **业务含义**：按效果配置将一种 stat 按比例转换为另一种 stat。

#### `get_nearest(targets: Array, from: Vector2, min_distance: int = 0, max_range: int = LARGE_NUMBER) -> Array`
- **业务含义**：从目标数组中找最近的，返回 `[target, distance]`。

#### `instance_scene_on_main(scene: PackedScene, position: Vector2) -> Node`
- **业务含义**：在当前主场景实例化一个场景。

---

## 7. TempStats — 临时属性系统

`TempStats` (extends Node) 管理运行时动态产生、不保存到存档的临时属性。
路径：`singletons/temp_stats.gd`

### 核心概念

临时 stat 与永久 stat（RunData）的区别：
- 临时 stat 来自按时间/击杀/移动状态等触发的效果，**每局结束后消失**
- 永久 stat 来自物品/升级/角色，**贯穿整局**

### 公开方法

#### `add_stat(stat_hsh: int, value: int, player_index: int) -> void`
- **业务含义**：给指定玩家的临时 stat 增加数值。

#### `remove_stat(stat_hsh: int, value: int, player_index: int) -> void`
- **业务含义**：减少临时 stat 值。

#### `set_stat(stat_hsh: int, value: int, player_index: int) -> void`
- **业务含义**：直接设置临时 stat 值（覆盖）。

#### `get_stat(stat_hash: int, player_index: int) -> float`
- **业务含义**：获取临时 stat 的最终值（= temp_value × gain 系数）。被 `Utils.get_stat` 调用。

#### `reset_player(player_index: int) -> void`
- **业务含义**：重置指定玩家的所有临时 stat。

#### `reset() -> void`
- **业务含义**：重置所有玩家的临时 stat。

---

## 8. LinkedStats — 属性链接系统

`LinkedStats` (extends TempStats) 实现"每有 X 点 A 属性，获得 Y 点 B 属性"的效果系统。
路径：`singletons/linked_stats.gd`

### 核心概念

Stat Link 根据另一个 stat（或游戏实体数量）的当前值，计算百分比加成。

例如 `effect_gain_stat_for_every_stat_hash` 配置：
`[stat_to_tweak, nb_stat_to_tweak, stat_scaled, nb_stat_scaled]`
表示"每有 `nb_stat_scaled` 点 `stat_scaled`，获得 `nb_stat_to_tweak` 点 `stat_to_tweak`"

### 公开方法

#### `reset_player(player_index: int) -> void`
- **业务含义**：核心入口。清空临时 stat 后遍历所有 `stat_links` 条目重新计算：
  1. 计算引用值（金币、敌人数、结构物数、宠物数等动态值或 stat 值）
  2. 按公式 `amount = nb_stat_to_tweak * (actual_nb / nb_stat_scaled)` 计算加成
  3. 调用 `add_stat` 写入临时 stat
  4. 标记需要每半秒刷新的 link（引用动态值如敌人数时）
- **调用时机**：每波开始时、player effects 变更时。

---

## 9. ShopItem — 商店物品 UI 节点

`ShopItem` (extends Control) 是商店中单个物品格子的 UI 控件。
路径：`ui/menus/shop/shop_item.gd`

### 9.1 关键属性

| 属性 | 类型 | 业务含义 |
|---|---|---|
| `value` | int | **最终显示价格**。经 `ItemService.get_value()` 计算后，如有 hp_shop 再 `ceil(value/20.0)` |
| `item_data` | ItemParentData | 此格子的物品资源数据 |
| `wave_value` | int | 设置时的波次值，用于价格计算和锁定记录 |
| `active` | bool | 物品是否激活可见（购买后变 false） |
| `locked` | bool | 是否被锁定 |
| `player_index` | int | 所属玩家索引（export 可配置） |

### 9.2 `set_shop_item(p_item_data, p_wave_value = RunData.current_wave) -> void`
- **业务含义**：完整设置一个商店格子的内容。流程：
  1. 存储 `item_data` 和 `wave_value`
  2. 调 `ItemService.get_value(wave_value, p_item_data.value, player_index, true, p_item_data is WeaponData, p_item_data.my_id_hash)` 计算 `value`
  3. **hp_shop 处理**：如果玩家有 hp_shop 效果，`value = ceil(value / 20.0) as int`，同时购买按钮图标替换为 max_hp 图标
  4. 处理 duplicate_item 效果（叠加复制图标）
  5. 设置价格显示（`_button.set_value(value, get_player_currency(...))`）
  6. 设置物品描述
  7. 管理锁定/禁用按钮显隐
- **关键理解**：价格已由 vanilla 完整计算，mod 只需读 `ShopItem.value`，不要自己再算。

### 9.3 其他方法

| 方法 | 业务含义 |
|---|---|
| `change_lock_status(button_pressed: bool) -> void` | 切换物品锁定状态，调用 RunData 的 lock/unlock |
| `deactivate() -> void` | 禁用物品（购买后）：alpha=0，禁用所有按钮，active=false |
| `activate() -> void` | 重新激活物品 |
| `steal_item() -> void` | 编程式触发偷窃 |

### 9.4 重要信号

| 信号 | 触发时机 |
|---|---|
| `buy_button_pressed(shop_item)` | 点击购买按钮 |
| `steal_button_pressed(shop_item)` | 点击偷窃按钮 |
| `shop_item_deactivated(shop_item)` | 物品被移除/禁用 |

---

## 10. WeaponService — 武器服务

`WeaponService` (extends Node) 负责武器初始化、投射物生成、爆炸效果、燃烧系统等核心战斗逻辑。
路径：`singletons/weapon_service.gd`

### 10.1 武器初始化

#### `init_base_stats(from_stats, player_index, args, is_structure, is_special_spawn, is_pet) -> WeaponStats`
- **业务含义**：武器初始化的核心方法。完整流程：复制基础属性 → 应用武器类型加成 → 应用套装加成 → 处理特殊效果（燃烧、爆炸、减速、堆叠） → 缩放属性计算 → 攻速/冷却计算 → 伤害计算（含各种百分比加成） → 暴击率/命中率/生命偷取/击退。
- **最终伤害**：`max(1, round(base_damage * (1 + percent_damage/100) + scaling_stats_bonus))`

#### `init_melee_stats(from_stats, player_index, args) -> MeleeWeaponStats`
- **业务含义**：初始化近战武器属性，额外计算 max_range。

#### `init_ranged_stats(from_stats, player_index, is_special_spawn, args) -> RangedWeaponStats`
- **业务含义**：初始化远程武器属性，设置投射物溅射/穿透/弹射/速度。

#### `init_structure_stats(from_stats, player_index, args) -> RangedWeaponStats`
- **业务含义**：初始化炮塔属性，使用 `structure_range_hash` 计算范围。

#### `init_melee_pet_stats / init_ranged_pet_stats / init_structure_pet_stats`
- **业务含义**：初始化宠物攻击属性，额外触发野兽大师缩放效果。

### 10.2 投射物与爆炸

#### `spawn_projectile(pos, weapon_stats, direction, from, args) -> Node`
- **业务含义**：核心投射物生成。从对象池获取实例、设置效果列表、发射。

#### `explode(effect, args) -> Node`
- **业务含义**：核心爆炸效果。从对象池获取爆炸场景、设置伤害/范围、触发爆炸动画。

#### `init_burning_data(base_burning_data, player_index, is_structure, is_pet) -> BurningData`
- **业务含义**：合成全局燃烧效果与武器自带燃烧数据。

---

## 11. Vanilla UI 节点约定（mod 开发用）

### 11.1 商店 (`ui/menus/shop/base_shop.gd`)

| 字段/方法 | 类型 | 业务含义 |
|---|---|---|
| `_shop_items` | `Array[Array]` | 每个玩家一个子数组，元素为 `(item_data, ShopItem 节点)` |
| `_reroll_price` | `Array[int]` | 每个玩家的刷新价格（累进增长） |
| `_on_RerollButton_pressed(player_index)` | 方法 | 扣金币 + 重新生成物品 + 刷新 UI |

### 11.2 升级 (`ui/menus/ingame/upgrades_ui.gd`)

| 字段/方法 | 类型 | 业务含义 |
|---|---|---|
| `_player_is_choosing` | `Array[bool]` | 每个玩家是否处于"等待选择升级"状态 |
| `_items_container` | 节点 | 可见 = 正在处理箱子物品（而非 4 选 1 升级） |

### 11.3 升级容器 (`ui/menus/ingame/upgrades_ui_player_container.gd`)

| 字段/方法 | 类型 | 业务含义 |
|---|---|---|
| `_reroll_button` / `_reroll_price` | 按钮/int | 升级刷新（永远花金币） |
| `_upgrade_uis` | `Array` | 当前显示的升级选项 UI 节点列表 |
| `_button_pressed` / `_button_delay_timer` | bool/Timer | 0.1s 防抖守卫 |
| `_autotato_clear_button_guard()` | 方法 | （mod 扩展方法）绕过防抖守卫 |
| `_get_upgrade_uis()` | 方法 | 返回所有升级 UI 节点 |

---

## 12. 三个 stat 系统的协作流程

```
Utils.get_stat(stat_hsh, player_index)  ← 所有游戏逻辑查询 stat 的统一出口
    │
    ├── RunData.get_stat(stat_hsh, player_index)   [永久 stat]
    │       = get_player_effect(stat_hsh) × (1 + gain_<stat> / 100)
    │       来源：物品 + 角色 + 升级，贯穿整局，随存档保存
    │
    ├── TempStats.get_stat(stat_hsh, player_index)  [临时 stat]
    │       = temp_value × (1 + gain_<stat> / 100)
    │       来源：时间触发、移动条件、击杀触发等，不保存
    │
    └── LinkedStats.get_stat(stat_hsh, player_index) [link stat]
            = 按 link 公式计算的加成值
            来源："每 X 点 A 获得 Y 点 B"效果，每波/每半秒重算
```

**结果缓存**：`Utils.get_stat` 的结果被缓存，直到 `reset_stat_cache` 被调用（stat 变更时）。

---

## 附录 A: 关键数据类型速查

| 类型 | 路径 | 关键字段 |
|---|---|---|
| `ItemParentData` | `items/global/item_parent_data.gd` | `my_id`, `my_id_hash`, `value`(基础价格), `tier`, `effects`, `is_lockable` |
| `ItemData` | `items/global/item_data.gd` | 继承 ItemParentData + `max_nb`(-1=无限), `tags` |
| `WeaponData` | `items/global/weapon_data.gd` | 继承 ItemParentData + `weapon_id`, `type`(近战/远程), `sets`, `upgrades_into` |
| `UpgradeData` | `items/upgrades/upgrade_data.gd` | 继承 ItemParentData |
| `ConsumableData` | `items/consumables/consumable_data.gd` | 继承 ItemParentData |
| `SetData` | `items/sets/set_data.gd` | `my_id`, `set_bonuses`(套装奖励效果数组) |
| `StatData` | `items/upgrades/stat_data.gd` | `stat_name`, `icon`, `is_primary_stat`, `color_override` |
| `CharacterData` | 继承 ItemParentData | 角色定义，含 wanted_tags、banned_items 等 |
| `BurningData` | 燃烧数据类 | 燃烧伤害、扩散、持续时间 |
| `Tier` enum | `items/global/tier.gd` | COMMON=0, UNCOMMON=1, RARE=2, LEGENDARY=3, DANGER_4=4, DANGER_5=5, NIGHTMARE=6 |

## 附录 B: 常用术语澄清

| 术语 | 真实含义 | 常见误解 |
|---|---|---|
| `currency` | 玩家的"购买力"，可以是金币或 HP | ≠ `gold` |
| `gold` | 仅指金币，是一种具体货币 | ≠ `currency` |
| `value` (ItemParentData) | 物品的**基础价格** | ≠ 最终商店价格 |
| `value` (ShopItem) | 物品的**最终商店价格** | ≠ 基础价格 |
| `effects` (Dictionary) | 所有效果的**原始累加值** | ≠ stat 的最终生效值 |
| `stat` (Utils.get_stat) | 永久+临时+link = **最终生效值** | ≠ 效果原始累加值 |
| `my_id` | 具体版本的唯一 ID（如 `weapon_revolver_1`） | ≠ `weapon_id`（武器族 ID） |
| `tier` | 品质等级（0-4 的枚举） | ≠ `level`（波次/角色等级） |
| `wave` | 波次编号（0-based，0-19 标准） | ≠ 第几关 |
| `difficulty` | 难度 D0-D5（每局固定） | ≠ `danger`（游戏内动态危险度机制） |
| `hp_shop` | 效果标志位：用 HP 替代金币购物 | ≠ 仅仅是商店的一个标签 |
