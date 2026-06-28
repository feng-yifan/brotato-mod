# ============================================================================
# AT_DangerModifier — Danger 难度对 stat 评分权重的修正曲线
# ----------------------------------------------------------------------------
# vanilla 字段名实际是 `RunData.current_difficulty: int` (取值 0-5),
# 但游戏 UI 上显示为 "Danger 0" 到 "Danger 5". 本文件统一对外用 "danger".
#
# 设计要点 (与 vanilla 难度曲线对齐):
#   - Danger 0-2: 标准难度, 评分权重不修正 (multiplier = 1.0).
#   - Danger 3+: 敌人显著变强 (vanilla enemy_strength: D3=12, D4=26, D5=40),
#                此时玩家防御不够会先死, 评分器应抬高防御类 stat 权重
#                (armor / dodge / max_hp / hp_regen / lifesteal), 同时
#                适度下调纯进攻 stat 权重.
#   - Danger 5: vanilla 还会触发 double_boss, 但那是 boss 关的特殊处理,
#               不在本文件职责内; 这里只对 stat 权重做一刀切修正.
#
# 本曲线是经验值, 评分器接入后可基于实际胜率回归再调整.
# 本文件为纯静态查询 (无运行时缓存 / 无信号), 上层每次询问即时读 RunData.
# ============================================================================

extends Reference
class_name AT_DangerModifier

const Keys = preload("res://mods-unpacked/fengyifan-AutoTato/autotato/data/effect_keys.gd")

# ---- 类别标签 --------------------------------------------------------------
const CAT_DEFENSIVE := "def"
const CAT_OFFENSIVE := "off"
const CAT_NEUTRAL   := "neu"

# ---- 难度乘子曲线 ----------------------------------------------------------
# 防御类 stat → 高难度抬权重
const DEFENSIVE_CURVE := {
	0: 1.0,
	1: 1.0,
	2: 1.05,
	3: 1.15,
	4: 1.25,
	5: 1.35,
}

# 进攻类 stat → 高难度略下调 (防御不够会先死, 进攻优先级让位)
const OFFENSIVE_CURVE := {
	0: 1.0,
	1: 1.0,
	2: 0.98,
	3: 0.95,
	4: 0.92,
	5: 0.90,
}

# 中性 stat (luck / harvesting / range / engineering / speed 等) 永远 1.0,
# 不随 Danger 变化.

# ---- stat 名单 -------------------------------------------------------------
# 防御类: 直接影响"少死"的属性
const DEFENSIVE_STATS := [
	"stat_max_hp",
	"stat_hp_regeneration",
	"stat_armor",
	"stat_dodge",
	"stat_lifesteal",
]

# 进攻类: 直接转化为输出 / 击杀效率的属性
const OFFENSIVE_STATS := [
	"stat_damage",
	"stat_melee_damage",
	"stat_ranged_damage",
	"stat_elemental_damage",
	"stat_percent_damage",
	"stat_attack_speed",
	"stat_crit_chance",
]

const _MIN_DANGER := 0
const _MAX_DANGER := 5


# ============================================================================
# 公开 API
# ============================================================================

# 安全读取当前 Danger 等级.
# RunData 是 autoload 单例, 但主菜单 / 未进 run 时 current_difficulty 可能为 0
# 或字段不存在. 任何异常情况一律退化为 0.
#
# 实现细节: Godot 3 静态解析器不识别 mod 里的 autoload `RunData` 名字, 写
# `"current_difficulty" in RunData` 会被报为 "String in null". 解决办法是
# 用 Object.get() 单参版 —— 字段不存在时返回 null, 不抛错.
static func get_danger_level() -> int:
	# 主菜单或冷启动: RunData 可能还没初始化好 current_difficulty
	if typeof(RunData) != TYPE_OBJECT:
		return 0
	var raw = RunData.get("current_difficulty")
	if raw == null:
		return 0
	if typeof(raw) != TYPE_INT and typeof(raw) != TYPE_REAL:
		return 0
	return int(clamp(raw, _MIN_DANGER, _MAX_DANGER))


# 获取指定 stat 在当前 (或指定) Danger 下的评分权重乘子.
# danger_level == -1 表示自动读当前 RunData.
static func get_stat_weight_multiplier(stat_key: String, danger_level: int = -1) -> float:
	if danger_level < 0:
		danger_level = get_danger_level()
	danger_level = int(clamp(danger_level, _MIN_DANGER, _MAX_DANGER))

	var category := _category_of(stat_key)
	match category:
		CAT_DEFENSIVE:
			return float(DEFENSIVE_CURVE.get(danger_level, 1.0))
		CAT_OFFENSIVE:
			return float(OFFENSIVE_CURVE.get(danger_level, 1.0))
		_:
			return 1.0


# 是否为防御类 stat
static func is_defensive(stat_key: String) -> bool:
	return stat_key in DEFENSIVE_STATS


# 是否为进攻类 stat
static func is_offensive(stat_key: String) -> bool:
	return stat_key in OFFENSIVE_STATS


# ============================================================================
# 私有
# ============================================================================

# 优先级: DEFENSIVE > OFFENSIVE > NEUTRAL
# (理论上两个名单互斥, 这里仍按优先级判定以防未来增删时撞名)
static func _category_of(stat_key: String) -> String:
	if stat_key in DEFENSIVE_STATS:
		return CAT_DEFENSIVE
	if stat_key in OFFENSIVE_STATS:
		return CAT_OFFENSIVE
	return CAT_NEUTRAL
