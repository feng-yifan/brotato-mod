extends Reference
class_name AT_UpgradeDecider

# ============================================================================
# AutoTato — Upgrade Decider (v6.1: upgrade_action 统一下拉)
# ============================================================================
# threshold[stat].upgrade_action ∈ {forbid, limit, none}
#   forbid → 含此 stat 的升级项永远跳过
#   limit  → 阈值触达时跳过
#   none   → 不限制

const ItemU = preload("res://mods-unpacked/fengyifan-AutoTato/autotato/data/item_data_util.gd")
const Gate  = preload("res://mods-unpacked/fengyifan-AutoTato/autotato/decisions/threshold_gate.gd")
const Parser = preload("res://mods-unpacked/fengyifan-AutoTato/autotato/data/effect_parser.gd")

const LOG_NAME := "fengyifan-AutoTato:UpgradeDecider"
const NO_PICK := -1


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
	if not bool(config.get("enabled", false)):
		return NO_PICK
	if option_list == null or option_list.size() == 0:
		return NO_PICK

	var min_tier: int = int(config.get("min_tier", -1))
	var quality_first: bool = bool(config.get("quality_first", true))
	var ignore_blacklist_on_stuck: bool = bool(config.get("ignore_blacklist_on_stuck", false))

	var player_index: int = int(context.get("player_index", 0))
	var threshold_config: Dictionary = context.get("threshold_config", {})
	if typeof(threshold_config) != TYPE_DICTIONARY:
		threshold_config = {}
	var stat_priority: Array = context.get("stat_priority", [])

	var all_candidates: Array = _build_candidates(option_list)
	var after_tier: Array = _filter_by_tier(all_candidates, min_tier)
	var after_upgrade: Array = _filter_by_upgrade_action(after_tier, threshold_config, player_index)
	var sorted: Array = _sort_by_quality(after_upgrade, quality_first)
	var sorted_final: Array = _sort_by_priority_within_top_tier(sorted, stat_priority, player_index)
	return _pick_first_or_stuck(sorted_final, all_candidates, quality_first, ignore_blacklist_on_stuck)


# ============================================================================
# 私有 helpers — 构建/过滤
# ============================================================================

static func _build_candidates(option_list: Array) -> Array:
	var result: Array = []
	for i in range(option_list.size()):
		var data = option_list[i]
		var tier: int = ItemU.get_tier(data)
		result.append({"original_index": i, "data": data, "tier": tier})
	return result


static func _filter_by_tier(candidates: Array, min_tier: int) -> Array:
	if min_tier < 0:
		return candidates.duplicate()
	var result: Array = []
	for c in candidates:
		if int(c.get("tier", 0)) >= min_tier:
			result.append(c)
	return result


# v6.1: 统一处理 upgrade_action → forbid/limit/none
static func _filter_by_upgrade_action(candidates: Array, threshold_config: Dictionary, player_index: int) -> Array:
	var result: Array = []
	for c in candidates:
		var stats: Array = _collect_upgrade_stats(c.get("data"))
		var tier: int = int(c.get("tier", 0))
		var blocked := false
		for s in stats:
			var cfg = threshold_config.get(s, {})
			if typeof(cfg) != TYPE_DICTIONARY:
				continue
			var ua: String = str(cfg.get("upgrade_action", "none"))
			match ua:
				"forbid":
					blocked = true
					break
				"limit":
					var verdict = Gate.should_reject_upgrade_by_threshold(c.get("data"), {s: cfg}, player_index)
					if bool(verdict.get("should_reject", false)):
						blocked = true
						break
				_:  # "none" — no restriction
					pass
			# stat min_tier 检查
			var stat_min_tier: int = int(cfg.get("min_tier", -1))
			if stat_min_tier >= 0 and tier < stat_min_tier:
				blocked = true
				break
		if not blocked:
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


static func _pick_first_or_stuck(
		filtered: Array, all_candidates: Array,
		quality_first: bool, ignore_blacklist_on_stuck: bool
	) -> int:
	if filtered.size() > 0:
		return int(filtered[0].get("original_index", NO_PICK))
	if not ignore_blacklist_on_stuck:
		return NO_PICK
	if all_candidates.size() == 0:
		return NO_PICK
	var fallback: Array = _sort_by_quality(all_candidates, quality_first)
	if fallback.size() == 0:
		return NO_PICK
	return int(fallback[0].get("original_index", NO_PICK))


static func _log(msg: String) -> void:
	if typeof(ModLoaderLog) != TYPE_NIL:
		ModLoaderLog.debug(msg, LOG_NAME)
