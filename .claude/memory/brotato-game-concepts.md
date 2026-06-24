# Brotato 游戏概念与术语

> 来源：游戏源代码分析 + Steam Modding Guide + Brotato Wiki
> 更新日期：2026-06-25

---

## 游戏概览

Brotato 是一款类 Vampire Survivors 的俯视角 roguelite 动作游戏。玩家选择一个**角色**（Character），装备**武器**（Weapon），在由**波次**（Wave）组成的关卡中生存，每波结束后进入**商店**（Shop）购买**物品**（Item）强化自己。标准游戏时长为 20 波，之后可进入无尽模式（Endless Mode）。

## 技术栈

| 项 | 详情 |
|---|---|
| 引擎 | Godot Engine 3.6.x（非 4.x） |
| 语言 | GDScript |
| Steam 集成 | GodotSteam（编译进 Godot 的特殊版本） |
| 资源格式 | `.tscn`（场景）、`.tres`（资源）、`.gd`（脚本）、`.pck`（打包） |
| Mod 框架 | ModLoader 6.3.0（内嵌在 vanilla 游戏中） |

---

## 核心游戏概念

### 属性系统（16+ 种主要属性）

| 英文 Key | 中文 | 单位 | 说明 |
|---|---|---|---|
| `stat_max_hp` | 最大生命值 | flat | 生命值上限 |
| `stat_hp_regeneration` | 生命回复 | flat | 每秒回复 HP |
| `stat_lifesteal` | 吸血 | percent | 攻击回血概率 |
| `stat_damage` | 伤害 | flat | 基础伤害加成（区别于 percentage） |
| `stat_melee_damage` | 近战伤害 | percent | 近战武器伤害加成 |
| `stat_ranged_damage` | 远程伤害 | percent | 远程武器伤害加成 |
| `stat_elemental_damage` | 元素伤害 | percent | 影响燃烧等元素效果 |
| `stat_percent_damage` | 伤害百分比 | percent | 全局伤害百分比乘区 |
| `stat_attack_speed` | 攻击速度 | percent | 攻击冷却缩减 |
| `stat_crit_chance` | 暴击率 | percent | 暴击概率 |
| `stat_engineering` | 工程 | percent | 影响建筑（炮塔、地雷）伤害 |
| `stat_range` | 范围 | flat | 武器攻击距离 |
| `stat_armor` | 护甲 | flat | 减少受到的伤害 |
| `stat_dodge` | 闪避 | percent | 概率闪避攻击 |
| `stat_speed` | 速度 | percent | 移动速度 |
| `stat_luck` | 幸运 | percent | 影响掉落品质和商店物品等级 |
| `stat_harvesting` | 收获 | flat | 影响波次结束金币量 |
| `stat_curse` | 诅咒 | percent | 诅咒值（负向属性） |

### 物品稀有度（Tier）

| Tier | 名称 | 价格范围（物品） |
|---|---|---|
| 0 | Common (I) | 8–30 |
| 1 | Uncommon (II) | 35–65 |
| 2 | Rare (III) | 50–100 |
| 3 | Legendary (IV) | 80–130 |

### 武器分类

- **MELEE (0)** — 近战武器，有 `attack_type` 字段（THRUST 突刺 / SWEEP 横扫）
- **RANGED (1)** — 远程武器，有 `nb_projectiles`、`piercing`、`bounce` 等弹丸属性

### 难度等级（Danger）

| Danger | 敌人强度 |
|---|---|
| 0–2 | 标准难度 |
| 3 | 敌人强度=12 |
| 4 | 敌人强度=26 |
| 5 | 敌人强度=40，double_boss |

---

## 游戏循环

```
开始 Run → 选角色 → Wave 1 → Shop → Wave 2 → Shop → ... → Wave 20 (Boss) → 通关 / 无尽
```

### 波次系统
- `RunData.current_wave`：当前波次（1–20 标准，20+ 无尽）
- `RunData.wave_in_progress`：波次进行中标志
- 波次时长通常 60 秒起，随波次递增
- 波次事件：精英波（Elite Wave）、部落波（Horde Wave）、弹幕地狱（Bullet Hell）、战争迷雾（Fog of War）
- 杀光所有敌人或波次计时器归零 → 波次结束

### 商店系统
- 波次结束后进入商店，生成 4 个物品（早期波次保证武器出现）
- 物品等级概率由波次数和 Luck 属性决定
- 机制：锁定（Lock）、重投（Reroll）、Ban（禁止）
- 价格 = 基础价格 × 价格修正效果 × wave inflation

### 升级系统
- 击杀敌人获得 XP
- 升级所需 XP：`(3 + level)²`
- 升级后弹出 4 选 1 属性升级面板
- 武器合成：2 把同一 weapon_id 同 tier → 合成为下一级（upgrades_into 链）

---

## 专业术语词汇表

| 英文 | 中文 | 说明 |
|---|---|---|
| Wave | 波次 | 一个生存回合 |
| Shop | 商店 | 波次之间的购买环节 |
| Item | 物品 | 被动加成装备（区别于武器） |
| Weapon | 武器 | 主动攻击装备，6 个槽位 |
| Character | 角色 | 初始属性不同、有特殊规则的游戏角色 |
| Tier | 等级 | 物品稀有度（1–4） |
| Danger | 危险等级 | 难度等级（0–5） |
| Consumable | 消耗品 | 战斗中掉落的即时效果物品 |
| Upgrade | 升级 | 升级时选择的属性提升 |
| Material / Gold | 材料 / 金币 | 游戏内货币 |
| Elite | 精英敌人 | 比普通敌人更强的特殊敌人 |
| Boss | Boss | 20 波出现的 Boss 级敌人 |
| Horde | 部落 | 大量低级敌人同时出现 |
| Endless Mode | 无尽模式 | 20 波后继续的游戏模式 |
| Harvesting | 收获 | 影响波次结束时获得的金币量 |
| Luck | 幸运 | 影响掉落品质和商店物品等级 |
| Dodge | 闪避 | 百分比概率闪避攻击 |
| Armor | 护甲 | 减少受到的伤害 |
| Life Steal | 吸血 | 百分比概率攻击回血 |
| HP Regeneration | 生命回复 | 每秒回复 HP |
| Engineering | 工程 | 影响建筑（炮塔、地雷等）的伤害 |
| Range | 范围 | 影响武器的攻击距离 |
| Knockback | 击退 | 攻击推动敌人的力度 |
| Piercing | 穿透 | 弹丸穿透敌人的数量 |
| Bounce | 弹射 | 弹丸弹射到额外敌人 |
| Crit Chance | 暴击率 | 暴击概率 |
| Elemental Damage | 元素伤害 | 影响燃烧等元素效果的伤害 |
| Burning | 燃烧 | 元素伤害的一种类型（DoT） |
