# AutoTato Mod 架构

> 来源：mod 源代码全量阅读
> 更新日期：2026-06-25
> Mod 目录：`mods-unpacked/fengyifan-AutoTato/`

---

## 定位

AutoTato 是一个 **Brotato 游戏的智能自动化代理**。它在商店、升级、箱子三个游戏决策点介入，根据用户配置的规则自动做出选择（购买/锁定/丢弃），同时保留玩家手动的最终控制权。

## 分层架构（P0–P5）

```
P3 Hook 层      — Script Extension 挂载点，接 vanilla 信号
P2 Bridge 层    — 配置中心 + 胶水，全局单例
P1 决策层       — 纯函数决策器（ItemDecider / UpgradeDecider / ThresholdGate）
P0 数据层       — Effect 压扁解析 + 物品/武器查询 + 属性元数据
P4 持久化层     — 独立 IO 模块（ConfigManager）
P5 UI 层        — 暂停菜单按钮注入 + 配置面板
```

### 依赖方向
上层依赖下层，不可逆。P3 → P2 → P1 → P0。P4 被 P2 调用。P5 独立。

### 各层状态持有
| 层 | 有状态？ | 读 vanilla？ | 写 vanilla？ |
|---|---|---|---|
| P3 Hook | 不持状态 | ✓ | ✓（通过信号） |
| P2 Bridge | ✓（Config） | ✗ | ✗ |
| P1 Decider | 纯函数 | ✗ | ✗ |
| P0 Data | 静态 util | ✓（封装后） | ✗ |
| P4 ConfigManager | 静态 IO | ✗ | ✗（只写盘） |

---

## 文件结构

```
mods-unpacked/fengyifan-AutoTato/
├── manifest.json
├── mod_main.gd                          # 入口：注册扩展 + 加载 preload
├── autotato/
│   ├── data/                            # P0 数据层
│   │   ├── effect_schema.gd            #   EffectInfo 不可变记录
│   │   ├── effect_keys.gd             #   效果 key 元数据字典（stat 标签 + misc 标签）
│   │   ├── effect_parser.gd           #   把 vanilla Effect 压扁为 EffectInfo
│   │   ├── item_data_util.gd          #   ItemData Resource/Dict 双形态查询
│   │   ├── weapon_data_util.gd        #   WeaponData 专属查询
│   │   └── danger_modifier.gd         #   Danger 曲线权重修正
│   ├── decisions/                      # P1 决策层
│   │   ├── decision_result.gd         #   4 终态 + 工厂
│   │   ├── threshold_gate.gd          #   阈值闸门 + 联动闭包扫描
│   │   ├── item_decider.gd            #   8 步物品决策
│   │   └── upgrade_decider.gd         #   6 步升级决策
│   ├── runtime/                        # P2 Bridge + P4
│   │   ├── bridge.gd                  #   Config 中心 + 全局注册 + 决策入口
│   │   └── config_manager.gd          #   JSON 读写 + 原子写 + Schema 迁移
│   ├── extensions/                     # P3 Hook 层（Script Extension）
│   │   └── ui/menus/
│   │       ├── shop/base_shop.gd      #   商店决策 hook
│   │       └── ingame/
│   │           ├── upgrades_ui.gd     #   升级 + 箱子决策 hook
│   │           └── ingame_main_menu.gd #  暂停菜单按钮注入
│   ├── ui/                             # P5 UI 层
│   │   ├── config_panel.gd            #   配置面板根节点
│   │   ├── config_panel.tscn          #   面板场景
│   │   └── tabs/
│   │       └── general_tab.gd         #   通用 Tab（P5.1 占位）
│   └── dev/                            # 烟雾测试
│       ├── p0_smoke_test.gd
│       ├── p1_smoke_test.gd
│       ├── p2_smoke_test.gd
│       ├── p3_smoke_test.gd
│       ├── p3_5_smoke_test.gd
│       ├── p4_smoke_test.gd
│       └── p5_1_smoke_test.gd
```

---

## P0 — 数据抽象层

### EffectSchema（`effect_schema.gd`）

**"压扁"模式**：vanilla Effect Resource 包含 i18n key、PNG 路径等决策器不关心的字段。parser 把 vanilla Effect 压扁为 `EffectInfo` 四元组：

```
(stat_key, custom_key, value, storage_method, effect_sign)
```

| 字段 | 说明 |
|---|---|
| `stat_key` | 主统计字段 key（如 `"stat_armor"`） |
| `custom_key` | KEY_VALUE 类时的桶名 |
| `value` | 效果数值 |
| `storage_method` | SUM/KEY_VALUE/REPLACE/APPEND_KEY/APPEND_KEY_VALUE |
| `effect_sign` | POSITIVE/NEGATIVE/FROM_VALUE/... |
| `signature` | 稳定签名用于缓存（`"stat_key@custom_key"` 或 `"stat_key"`） |

关键查询方法：
- `is_stat_modifier()`：`storage_method == SUM && stat_key.begins_with("stat_")`
- `is_key_value()`：KEY_VALUE / APPEND_KEY / APPEND_KEY_VALUE 类
- `get_storage_bucket()`：KEY_VALUE 类返回 `custom_key`，否则返回 `stat_key`
- `is_positive_sign()`：判断方向（FROM_VALUE 时按 value 正负）

### EffectKeys（`effect_keys.gd`）

为每个 vanilla effect key 标注元数据：

```gdscript
STAT_TAGS = {
    "stat_max_hp": {"unit": "flat", "positive_is_good": true},
    "stat_speed": {"unit": "percent", "positive_is_good": true},
    "stat_curse": {"unit": "percent", "positive_is_good": false},
    ...
}
MISC_TAGS = {
    "upgrade_random_weapon": {"is_bucket": true},
    "structures": {"is_bucket": true},
    "trees": {"is_bucket": false},
    ...
}
```

关键查询：
- `is_bucket(key)`：该 key 在 `init_effects()` 中初始值是否是 `[]`（数组桶）
- `is_known_stat(key)` / `is_known_misc(key)`：已知 key 校验
- `get_unit(key)`：返回 `flat` / `percent` / `boolean`
- `is_positive_good(key)`：该 stat 正向是否有利

### EffectParser（`effect_parser.gd`）

输入 → 输出：
- `Effect` → 1 条 `EffectInfo`
- `DoubleKeyValueEffect` → 2 条（key1+value1, key2+value2）
- `DoubleValueEffect` → 2 条（同一 key 两个 value）
- `EffectWithSubEffects` → 1 条主 + N 条递归子
- 未知子类 → 1 条默认解析（容错）

**旧 mod 致命 bug 的修复**：旧决策器只读 `effect.key`，完全没看 `custom_key` 与 `storage_method`，因此 Anvil 的 effect（`key=stat_armor, custom_key=upgrade_random_weapon, storage_method=KEY_VALUE`）被当成 "stat_armor +2"，实际含义是 "随机升级武器获得 stat_armor +2"。

### ItemDataUtil（`item_data_util.gd`）

ItemData Resource / Dictionary **双形态**访问。vanilla 链路中 item_data 可能以两种形态出现（ModLoader 间接传递/其他 mod 重写缓存/序列化中间态）。

关键方法：
- `get_id(item_data)` → `"item_anvil"`
- `get_tier(item_data)` → 0–6
- `get_base_value(item_data)` → 基础价格
- `get_max_amount(item_data)` → `max_nb`（-1=无限）
- `get_tags(item_data)` → 标签数组
- `get_raw_effects(item_data)` → 原始 Effect 数组（未解析）
- `get_count_owned(item_id, player_index)` → 当前持有数量
- `is_at_limit(item_data, player_index)` → 是否达上限
- `get_real_price(item_data, player_index)` → 轻量估算价格

### WeaponDataUtil（`weapon_data_util.gd`）

WeaponData 专属查询（复用 ItemDataUtil 处理共享字段）：
- `get_weapon_chain_id(w)` → 升级链 ID（如 `"weapon_fist"`，不同于 `my_id`）
- `get_weapon_class(w)` → MELEE(0) / RANGED(1)
- `get_weapon_sets(w)` → 武器组
- `get_scaling_stats(w)` → `[["stat_melee_damage", 1.0], ...]`
- `count_same_set_same_tier(w, player_index)` → 同链同 tier 武器数（用于预测升级）
- `get_max_weapons(player_index)` → 武器槽上限（默认 6）

### DangerModifier（`danger_modifier.gd`）

Danger 难度对 stat 评分权重的修正曲线：
- Danger 0–2：权重不修正（1.0）
- Danger 3+：防御类 stat（max_hp/armor/dodge/hp_regen/lifesteal）权重从 1.15 升至 1.35
- 进攻类 stat 权重从 0.98 降至 0.90
- 中性 stat 永远 1.0

---

## P1 — 决策层（纯函数，无状态）

### AT_DecisionResult

4 个终态（用 const String 而非 enum，理由：JSON 持久化兼容 + 调试友好）：

| 终态 | 语义 |
|---|---|
| `STATE_PURCHASED` | 商店买入/箱子拿取 |
| `STATE_LOCKED` | 锁定等下一轮 |
| `STATE_MANUAL` | 不干预，玩家手动 |
| `STATE_SKIPPED` | 拒绝/丢弃 |

工厂 `make(item_id, terminal_state, reason)`。`is_valid_state()` 供校验。

### AT_ItemDecider — 8 步决策流程

```
Step 1: 校验 action        → 非法回落 manual
Step 2: manual             → STATE_MANUAL
Step 3: reject             → STATE_SKIPPED
Step 4: is_at_limit        → STATE_SKIPPED（持有已满）
Step 5: 阈值反转闸门        → STATE_SKIPPED（cursed_only 跳过）
Step 6: 诅咒分支           → 非诅咒版按 action 处理
Step 7: 预算墙             → price≤threshold && gold-price≥min_balance
Step 8: dispatch           → STATE_PURCHASED
```

5 个商店动作：

| Action | 语义 |
|---|---|
| `reject` | 永远拒绝 |
| `lock_until_cursed` | 锁定等诅咒版 |
| `cursed_only` | 只买诅咒版 |
| `get` | 满足预算就买 |
| `manual`（默认） | 不干预 |

### AT_ThresholdGate — 阈值闸门

三模式：`upper`（上限）/ `lower`（下限）/ `unlimited`（不限）。

**反转规则（全或无）**：`should_reject = true` 当且仅当物品涉及的**全部**已配置 stat 都触达限制。任意一个未触达就不反转。

**联动闭包扫描**：玩家身上的 `gain_stat_for_every_stat` / `gain_stat_for_every_perm_stat` / `convert_stat` 联合 effect 会扩展 `related_stats` 集合。扫一轮（与 vanilla 一致，不递归）。双向传播：in_stat 在 related 时加 out_stat，out_stat 在 related 时加 in_stat。

支持阈值白名单：24 个 stat（16 主要 + curse + 7 次要）。

### AT_UpgradeDecider — 6 步决策

```
Step 1: enabled 检查          → config.enabled=false 直接 NO_PICK (-1)
Step 2: 候选构建              → 包装 (original_index, data, tier)
Step 3: tier 过滤             → 剔除 tier < min_tier
Step 4: threshold 过滤        → 调 Gate
Step 5: quality 排序          → 按 tier 降序（稳定排序，用 original_index tie-break）
Step 6: 选第一或卡死回退      → filtered 空时按 ignore_blacklist_on_stuck 回退
```

关键参数：
- `min_tier`：最小 tier（-1=不限）
- `quality_first`：是否按 tier 降序
- `ignore_blacklist_on_stuck`：全过滤后是否回退选全集第一

---

## P2 — Bridge 层（胶水 + 配置中心）

唯一有状态对象（持有 `_config` 字典）。通过 `Engine.set_meta(META_KEY, self)` 注册为全局单例。

### 全局可达

```gdscript
var bridge = AT_Bridge.get_global()
if bridge: bridge.decide_shop_item(item, gold)
```

### Config Schema（顶层 7 个 key）

```json
{
  "version": 5,
  "shop_automation_enabled": true,       // 商店自动化总开关
  "upgrade_automation_enabled": false,   // 升级自动化总开关（默认关）
  "item_rules": {                        // 物品规则
    "item_crown": {"shop_action": "get", "chest_action": "take"}
  },
  "thresholds": {                        // 阈值配置
    "stat_speed": {"mode": "upper", "value": 20},
    "stat_armor": {"mode": "upper", "value": 10}
  },
  "general": {"min_gold_balance": 0, "item_price_threshold": 0},
  "upgrade": {"min_tier": -1, "quality_first": false, "ignore_blacklist_on_stuck": false}
}
```

### 设计要点

1. **升级自动化默认 `false`**：因为升级决策器没有"无规则 = manual"概念。如果默认 `true`，新装 mod 的玩家一升级就被自动选 idx=0。
2. **所有读取 API 返回深拷贝**（`duplicate(true)`），防止 Hook 层意外篡改内部状态。
3. **`_skip_persistence` 模式**：`new_pristine()` 工厂创建内存版 Bridge，烟雾测试用。避免读玩家真实 config 污染测试、也避免测试数据覆盖玩家文件。

### 决策入口

| 方法 | 场景 | 返回值 |
|---|---|---|
| `decide_shop_item(item, gold, player_index)` | 单个商店物品 | `DecisionResult` |
| `decide_chest_item(item, player_index)` | 箱子物品 | `DecisionResult` |
| `decide_upgrade(options, player_index)` | 升级 4 选 1 | `int`（索引或 -1） |
| `process_shop(base_shop, player_index)` | 整商店批量 | `Array[Dictionary]` |

---

## P4 — ConfigManager（独立 IO）

路径：`user://AutoTato/session_config.json` → `~/.local/share/Brotato/AutoTato/session_config.json`

关键设计：
- **原子写**：写 `.tmp` → flush → `Directory.rename(tmp, real)`（POSIX rename(2)）
- **Schema 迁移**：递归 merge defaults 补缺字段，玩家配置不丢，mod 新增字段自动补默认
- **损坏兜底**：读失败返回 `null`，调用方用 defaults 起手
- **深度保护**：`MAX_MERGE_DEPTH=8` 防止恶意嵌套栈溢出

---

## 烟雾测试系统

每个阶段都有独立烟雾测试文件（`dev/p*_smoke_test.gd`），通过环境变量启用：
```bash
AUTOTATO_P0_SMOKE=1 ./Brotato.x86_64
```

`mod_main._ready()` 通过 `call_deferred("_run_smoke_test", path, label)` 调度，用 deferred 避免在 `_ready` 链上做长 IO，让其他 mod 先加载完。

---

## 默认行为

当前状态下，默认配置中所有物品 action 都是隐式 `manual`（未配 `item_rules`），`upgrade_automation_enabled=false`。**玩家不配规则时，mod 不干预任何操作**，行为等同于 vanilla。

---

## 核心架构模式

### 1. 递归分层（P0→P1→P2→P3）
每层只依赖直接下层，越往下越"纯"（无状态、无副作用）。游戏版本升级时只需适配 Hook 层的 vanilla API 变化，决策核心逻辑不受影响。

### 2. 不可变结果
`DecisionResult` 创建后不修改字段。Hook 层只读取，不修改。终态用 const String 而非 enum。

### 3. 全局注册 → 鸭式访问
Bridge 通过 `Engine.set_meta` 注册，Hook 端不持有 Bridge 引用为成员变量（防止 ReferenceCounted 循环）。

### 4. 阈值闸门 — 最后防线
评分器认为物品正向后，阈值闸门是独立的反转规则。不属于评分体系，是用户偏好的强制约束。

### 5. "压扁"模式
vanilla 复杂 Resource 对象 → 解析为纯数据记录 → 决策器只接触纯数据。

### 6. 两阶段决策（商店 Hook）
阶段 1 只读 snapshot + 输出决策结果。阶段 2 遍历结果执行信号。严格分开防止 vanilla 重入。

### 7. 白名单防御
`SUPPORTED_THRESHOLD_STATS`、`VALID_GENERAL_KEYS` 等阻止未知字段静默成功。
