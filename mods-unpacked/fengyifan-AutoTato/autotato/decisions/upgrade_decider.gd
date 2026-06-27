extends Reference
class_name AT_UpgradeDecider

# ============================================================================
# AutoTato — Upgrade Decider (v7: forbid_stats + respect_thresholds)
# ============================================================================
# upgrade.forbid_stats: 含此 stat 的升级项永远跳过
# upgrade.respect_thresholds: 是否检查阈值 (触达时跳过)
# upgrade.stat_priority: 同 tier 内优先级排序
#
# v7 语义: 过滤为空时返回 NO_PICK, 由 hook 层处理 reroll + fallback.
#          ignore_forbid_on_stuck 的 fallback 逻辑在 hook 层而非 decider 内,
#          确保先尝试 reroll 再 fallback.

const ItemU = preload("res://mods-unpacked/fengyifan-AutoTato/autotato/data/item_data_util.gd")
const Gate  = preload("res://mods-unpacked/fengyifan-AutoTato/autotato/decisions/threshold_gate.gd")
const Parser = preload("res://mods-unpacked/fengyifan-AutoTato/autotato/data/effect_parser.gd")

const LOG_NAME := "fengyifan-AutoTato:UpgradeDecider"
const NO_PICK := -1

const TIER_NAMES := {0: "普通", 1: "精良", 2: "稀有", 3: "传说"}


class _QualitySorter:
	func compare_tier_desc(a, b) -> bool:
		var ta: int = int(a.get("tier", 0))
		var tb: int = int(b.get("tier", 0))
		if ta != tb:
			return ta > tb
		return int(a.get("original_index", 0)) < int(b.get("original_index", 0))


class _PrioritySorter:
	var _priority: Array = []
	var _player_index: int = 0

	func _init(priority: Array, player_index: int) -> void:
		_priority = priority
		_player_index = player_index

	func compare_priority(a, b) -> bool:
		var pa: int = _calc_priority(a)
		var pb: int = _calc_priority(b)
		if pa != pb:
			return pa < pb
		return int(a.get("original_index", 0)) < int(b.get("original_index", 0))

	func _calc_priority(candidate) -> int:
		var stats: Array = _collect_stats(candidate.get("data"))
		var best: int = 9999
		for s in stats:
			var idx: int = _priority.find(s)
			if idx >= 0 and idx < best:
				best = idx
		return best

	func _collect_stats(upgrade_data) -> Array:
		var result: Array = []
		var raw = ItemU.get_raw_effects(upgrade_data)
		var parsed = Parser.parse_list(raw, 0)
		for info in parsed:
			if info == null or not info.is_stat_modifier():
				continue
			var sk: String = info.stat_key
			if sk != "" and not result.has(sk):
				result.append(sk)
		return result


# ============================================================================
# 公开 API
# ============================================================================

static func decide(option_list: Array, config: Dictionary, context: Dictionary) -> int:
	var wave: int = int(context.get("current_wave", 0))
	var seq: int = int(context.get("decision_seq", 0))
	var player_index: int = int(context.get("player_index", 0))
	_log("")
	_log("┌─ 升级决策 波次=%d 决策=%d 玩家=%d ──────────────────────────" % [wave, seq, player_index])
	_log("│ 候选数 %d" % [option_list.size() if option_list else 0])

	if not bool(config.get("enabled", false)):
		_log("└─ 升级自动化未启用 → 不选择")
		return NO_PICK
	if option_list == null or option_list.size() == 0:
		_log("└─ 无候选 → 不选择")
		return NO_PICK

	var min_tier: int = int(config.get("min_tier", -1))
	var quality_first: bool = bool(config.get("quality_first", true))

	var threshold_config: Dictionary = context.get("threshold_config", {})
	if typeof(threshold_config) != TYPE_DICTIONARY:
		threshold_config = {}
	var stat_priority: Array = context.get("stat_priority", [])
	var forbid_stats: Array = context.get("forbid_stats", [])
	var respect_thresholds: bool = bool(context.get("respect_thresholds", true))

	# 配置摘要
	var config_parts: Array = []
	config_parts.append("最低等级%s" % (">=%d" % min_tier if min_tier >= 0 else "不限"))
	config_parts.append("品质优先=%s" % ("是" if quality_first else "否"))
	config_parts.append("受阈值影响=%s" % ("是" if respect_thresholds else "否"))
	_log("│ %s" % ", ".join(config_parts))
	if forbid_stats.size() > 0:
		_log("│ 禁止属性: %d 项 [%s]" % [forbid_stats.size(), ", ".join(_cn_list(forbid_stats))])
	if stat_priority.size() > 0:
		_log("│ 优先级: [%s]" % ", ".join(_cn_list(stat_priority)))

	# [A] 构建候选 + 打印详情
	var all_candidates: Array = _build_candidates(option_list)
	_log("│ [A] 候选列表 (%d 项):" % all_candidates.size())
	for c in all_candidates:
		var t: int = int(c.get("tier", 0))
		var stats: Array = c.get("stats", [])
		_log("│     #%d  等级 %s  |  %s" % [c.get("original_index", 0), TIER_NAMES.get(t, "?"), ", ".join(_cn_list(stats))])

	# [B] tier 过滤
	var after_tier: Array = _filter_by_tier(all_candidates, min_tier)
	if min_tier >= 0:
		_log("│ [B] 等级过滤 (>=%d): %d → %d" % [min_tier, all_candidates.size(), after_tier.size()])
	else:
		_log("│ [B] 等级过滤 (不限): %d 项全部保留" % after_tier.size())

	# [C] forbid/阈值过滤 — 先在外部打印标题, 再调用过滤 (✗ 出现在标题下方)
	_log("│ [C] 禁止/阈值过滤:")
	var after_upgrade: Array = _filter_by_upgrade_action(after_tier, forbid_stats, respect_thresholds, threshold_config, player_index)
	_log("│     结果: %d → %d" % [after_tier.size(), after_upgrade.size()])

	# [D] 品质排序
	var sorted: Array = _sort_by_quality(after_upgrade, quality_first)
	if quality_first:
		if sorted.size() > 0:
			_log("│ [D] 品质排序: %d 项, 最高=%s" % [sorted.size(), TIER_NAMES.get(int(sorted[0].get("tier", 0)), "?")])
		else:
			_log("│ [D] 品质排序: 无候选")

	# [E] 优先级排序
	var sorted_final: Array = _sort_by_priority_within_top_tier(sorted, stat_priority, player_index)
	if stat_priority.size() > 0 and sorted_final.size() > 1:
		_log("│ [E] 优先级排序: 已排序 (%d 项)" % sorted_final.size())
	else:
		_log("│ [E] 优先级排序: 跳过")

	# 结果
	var picked: int = _pick_first_or_stuck(sorted_final)
	if picked == NO_PICK:
		_log("└─ 结果: 无合格候选 (由 hook 层决定 reroll/fallback)")
	else:
		var c = all_candidates[picked]
		var t: int = int(c.get("tier", 0))
		var stats: Array = c.get("stats", [])
		_log("└─ 结果: 选择 #%d | 等级 %s | %s" % [picked, TIER_NAMES.get(t, "?"), ", ".join(_cn_list(stats))])
	return picked


# ============================================================================
# 私有 helpers — 构建/过滤
# ============================================================================

static func _build_candidates(option_list: Array) -> Array:
	var result: Array = []
	for i in range(option_list.size()):
		var data = option_list[i]
		var tier: int = ItemU.get_tier(data)
		var stats: Array = _collect_upgrade_stats(data)
		result.append({"original_index": i, "data": data, "tier": tier, "stats": stats})
	return result


static func _filter_by_tier(candidates: Array, min_tier: int) -> Array:
	if min_tier < 0:
		return candidates.duplicate()
	var result: Array = []
	for c in candidates:
		if int(c.get("tier", 0)) >= min_tier:
			result.append(c)
	return result


static func _filter_by_upgrade_action(
		candidates: Array,
		forbid_stats: Array,
		respect_thresholds: bool,
		threshold_config: Dictionary,
		player_index: int
	) -> Array:
	var result: Array = []
	for c in candidates:
		var stats: Array = c.get("stats", [])
		var blocked := false
		var block_reason := ""
		for s in stats:
			if forbid_stats.has(s):
				blocked = true
				block_reason = "禁止: " + _cn_stat(s)
				break
			if respect_thresholds and threshold_config.has(s):
				var verdict = Gate.should_reject_upgrade_by_threshold(c.get("data"), {s: threshold_config[s]}, player_index)
				if bool(verdict.get("should_reject", false)):
					blocked = true
					block_reason = "阈值: " + _cn_stat(s)
					break
		if blocked:
			_log("│     ✗ #%d 过滤 (%s)" % [c.get("original_index", -1), block_reason])
		else:
			result.append(c)
	return result


static func _collect_upgrade_stats(upgrade_data) -> Array:
	var result: Array = []
	var raw = ItemU.get_raw_effects(upgrade_data)
	var parsed = Parser.parse_list(raw, 0)
	for info in parsed:
		if info == null or not info.is_stat_modifier():
			continue
		var sk: String = info.stat_key
		if sk != "" and not result.has(sk):
			result.append(sk)
	return result


# ============================================================================
# 私有 helpers — 排序/选择
# ============================================================================

static func _sort_by_quality(candidates: Array, quality_first: bool) -> Array:
	var result: Array = candidates.duplicate()
	if not quality_first or result.size() <= 1:
		return result
	var sorter = _QualitySorter.new()
	result.sort_custom(sorter, "compare_tier_desc")
	return result


static func _sort_by_priority_within_top_tier(candidates: Array, stat_priority: Array, player_index: int) -> Array:
	if candidates.size() <= 1 or stat_priority.size() == 0:
		return candidates
	var result := candidates.duplicate()
	var top_tier: int = -1
	for c in result:
		var t: int = int(c.get("tier", 0))
		if t > top_tier:
			top_tier = t
	var top_count := 0
	for c in result:
		if int(c.get("tier", 0)) == top_tier:
			top_count += 1
	if top_count < 2:
		return result
	var ps = _PrioritySorter.new(stat_priority, player_index)
	result.sort_custom(ps, "compare_priority")
	return result


static func _pick_first_or_stuck(filtered: Array) -> int:
	if filtered.size() > 0:
		return int(filtered[0].get("original_index", NO_PICK))
	return NO_PICK


# ============================================================================
# 中文名称映射
# ============================================================================

const _STAT_CN := {
	"stat_max_hp":             "最大生命",
	"stat_hp_regeneration":    "生命回复",
	"stat_lifesteal":          "生命偷取",
	"stat_damage":            "伤害",
	"stat_melee_damage":       "近战伤害",
	"stat_ranged_damage":      "远程伤害",
	"stat_elemental_damage":   "元素伤害",
	"stat_engineering":        "工程学",
	"stat_attack_speed":       "攻击速度",
	"stat_crit_chance":        "暴击率",
	"stat_percent_damage":     "百分比伤害",
	"stat_range":              "范围",
	"stat_armor":              "护甲",
	"stat_dodge":              "闪避",
	"stat_speed":              "速度",
	"stat_luck":               "幸运",
	"stat_harvesting":         "收获",
}

static func _cn_stat(key: String) -> String:
	if _STAT_CN.has(key):
		return _STAT_CN[key]
	return key.replace("stat_", "")


static func _cn_list(keys: Array) -> Array:
	var result: Array = []
	for k in keys:
		result.append(_cn_stat(k))
	return result


# ============================================================================
# 日志
# ============================================================================

static func _log(msg: String) -> void:
	if typeof(ModLoaderLog) != TYPE_NIL:
		ModLoaderLog.info(msg, LOG_NAME)
