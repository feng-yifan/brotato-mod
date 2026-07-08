extends Reference

# ============================================================================
# AutoTato - UpgradeAutomation
# ----------------------------------------------------------------------------
# 升级自动化流程编排, 对齐 shop_automation.gd 结构与设计原则。
#
# 数据流:
#   upgrade_data_reader -> candidates {options, visible_uis}
#   _decide_one (内联决策) -> {chosen: bool, idx: int}
#   upgrade_automation -> 调用 upgrades_ui 的 at_* executor 方法
#
# 决策流程 (内联, 不依赖 autotato/decisions/):
#   [A] tier 过滤   tier >= min_tier (-1 = 不限)
#   [B] forbid 过滤 命中 forbid_stats -> 跳过
#   [C] 阈值过滤    respect_thresholds 时, shop/threshold_gate 拦截 -> 跳过
#   [D] 品质排序    quality_first=true -> tier 降序
#   [E] 优先级排序  stat_priority 在 top tier 内排序
#   结果            取首个 or NO_PICK
#
# 与商店 shop_automation 的差异:
#   - 商店多物品逐个决策 (intent: purchase/lock/manual/skip)
#   - 升级 4 选 1, 一次选一个或 NO_PICK -> reroll
#   - 升级无 manual 停止条件 (4 选 1 无 manual 意图)
#   - 升级有 fallback: ignore_forbid_on_stuck=true 时选品质最优
#
# 刷新循环继续条件 (用户确认的逻辑):
#   一轮无合格 -> 先刷新 (消耗金币摇新候选) -> 再判断自动化开关:
#     开启 -> 继续下一轮;  关闭 -> 停止循环走兜底。
#   这样自动化关闭时玩家每按一次 AutoTato 按钮就推进一轮 (含一次刷新),
#   下次触发看到的是刷新后的新候选。
# ============================================================================

const _Config = preload("res://mods-unpacked/fengyifan-AutoTato/config/config.gd")
const _Data = preload("res://mods-unpacked/fengyifan-AutoTato/shop/upgrade_data_reader.gd")
const _Gate = preload("res://mods-unpacked/fengyifan-AutoTato/shop/threshold_gate.gd")
const _Logger = preload("res://mods-unpacked/fengyifan-AutoTato/utils/logger.gd")

const _LOG_NAME := "UpgradeAutomation"

const NO_PICK: int = -1
const TIER_NAMES := {0: "普通", 1: "精良", 2: "稀有", 3: "传说"}

# ============================================================================
# 公开 API
# ============================================================================

# 升级决策唯一入口。
# ui_adapter: upgrades_ui 实例, 需实现:
#   at_get_upgrade_candidates(pi) -> Dictionary {options, visible_uis}
#   at_choose_upgrade(idx, pi) -> void
#   at_reroll_upgrade(pi) -> bool
#   at_get_upgrade_reroll_price(pi) -> int
#   at_wait_before_next_decision() -> void
#   at_fallback_upgrade(pi) -> bool
#
# force=true: 绕过升级自动化开关 (手动按 AutoTato 按钮用), 执行完整决策会话。
# force=false: 受开关控制, 未开启则直接返回空 summary。
static func run_upgrade_decision(ui_adapter, player_index: int, force: bool = false) -> Dictionary:
	var cfg = _Config.get_instance()
	if cfg == null:
		_Logger.warning("Config 未初始化, 跳过升级决策", _LOG_NAME)
		return _empty_summary()

	# force=false 时受升级自动化开关控制; force=true 绕过 (手动触发)。
	if not force and not cfg.is_upgrade_automation_enabled():
		_Logger.info("升级自动化未启用, 跳过 玩家=%d" % player_index, _LOG_NAME)
		return _empty_summary()

	var turbo: bool = cfg.is_turbo_mode()
	var general: Dictionary = cfg.get_general()
	var reroll_spent := 0
	var round_num := 0
	var chosen := false
	# stopped_by_switch: 自动化开关关闭导致的循环停止 (刷新后停, 等玩家手动再触发).
	# 此种停止不应走 fallback -- 玩家手动按一次只想推进一轮看新候选, 不希望自动选.
	var stopped_by_switch := false

	_log("")
	_log("┌─ 升级决策 玩家=%d 波次=%d ──────────────────" % [player_index, _Data.get_current_wave()])

	# reroll 循环: 决策 -> 选中则结束 -> 否则能刷新就刷新 -> 刷新后判断开关。
	while true:
		round_num += 1
		var candidates: Dictionary = ui_adapter.at_get_upgrade_candidates(player_index)
		var options: Array = candidates.get("options", [])

		if options.empty():
			_log("│ 停止: 无候选 轮数=%d" % round_num)
			break

		var idx: int = _decide_one(options, cfg, player_index, round_num)
		if idx != NO_PICK:
			ui_adapter.at_choose_upgrade(idx, player_index)
			chosen = true
			var t: int = int(options[idx].get("tier"))
			_log("│ 选中 idx=%d 等级=%s 轮数=%d" % [idx, TIER_NAMES.get(t, "?"), round_num])
			break

		# NO_PICK -> 检查能否刷新
		var reroll_check: Dictionary = _can_reroll(ui_adapter, player_index, general)
		if not bool(reroll_check.get("ok", false)):
			_log("│ 停止: 无法刷新(%s) 轮数=%d" % [reroll_check.get("reason", ""), round_num])
			break

		# 执行刷新
		if not ui_adapter.at_reroll_upgrade(player_index):
			_Logger.warning("reroll 执行失败, 停止", _LOG_NAME)
			break

		reroll_spent += int(reroll_check.get("price", 0))
		_log("│ 刷新 (第 %d 轮) 累计=%d gold=%d" % [round_num, reroll_spent, _Data.get_player_gold(player_index)])

		if not turbo:
			ui_adapter.at_wait_before_next_decision()

		# 刷新后判断自动化开关: 关闭则停止循环, 等玩家下次手动触发看新候选.
		# 此种停止标记 stopped_by_switch, 跳过 fallback (玩家只想推进一轮, 不希望自动选).
		if not cfg.is_upgrade_automation_enabled():
			stopped_by_switch = true
			_log("│ 停止: 自动化关闭, 刷新后等待手动再触发 轮数=%d" % round_num)
			break

	# 循环结束未选中 -> fallback (仅当非开关关闭导致, 即真·循环耗尽时才兜底)
	var fallback_used := false
	if not chosen and not stopped_by_switch:
		fallback_used = ui_adapter.at_fallback_upgrade(player_index)
		chosen = fallback_used
		_log("│ fallback: %s" % ("选品质最优" if fallback_used else "未触发 (ignore_forbid_on_stuck=false)"))
	elif not chosen and stopped_by_switch:
		_log("│ 跳过 fallback: 自动化关闭, 交还玩家手动选")

	_log("└─ 会话结束: chosen=%s 轮数=%d reroll=%d fallback=%s" % [
		str(chosen), round_num, reroll_spent, str(fallback_used)])
	return {
		"chosen": chosen,
		"rounds": round_num,
		"reroll_spent": reroll_spent,
		"fallback_used": fallback_used,
	}


# ============================================================================
# 单次决策 (内联, 对齐原 upgrade_decider 5 步但完全自包含, 不依赖 autotato/)
# ============================================================================

# 对 4 个候选做一次决策, 返回 idx (0..n-1) 或 NO_PICK。
# round_num 仅用于日志前缀, 标识第几轮决策。
static func _decide_one(options: Array, cfg, player_index: int, round_num: int) -> int:
	var upg: Dictionary = cfg.get_upgrade_config()
	var min_tier: int = int(upg.get("min_tier", -1))
	var quality_first: bool = bool(upg.get("quality_first", false))
	var forbid_stats: Array = cfg.get_upgrade_forbid_stats()
	var stat_priority: Array = cfg.get_upgrade_priority()
	var respect_thresholds: bool = bool(upg.get("respect_thresholds", true))

	# 配置摘要
	_log("│ [轮 %d 决策] 候选 %d 个 | min_tier=%s 品质优先=%s 受阈值=%s 禁止=%d项 优先级=%d项" % [
		round_num, options.size(),
		(">=%d" % min_tier) if min_tier >= 0 else "不限",
		"是" if quality_first else "否",
		"是" if respect_thresholds else "否",
		forbid_stats.size(), stat_priority.size()
	])

	# [A] 构建候选 + tier 过滤 (低于 min_tier 直接丢弃)
	var after_tier: Array = []
	for i in options.size():
		var t: int = int(options[i].get("tier"))
		var c_stats: Array = _collect_stats(options[i])
		var c_name: String = _upgrade_name(options[i])
		if min_tier < 0 or t >= min_tier:
			after_tier.append({
				"idx": i,
				"data": options[i],
				"tier": t,
				"stats": c_stats,
				"name": c_name,
			})
			_log("│   [A] 保留 #%d 等级=%s 属性=[%s] %s" % [i, TIER_NAMES.get(t, "?"), _short_stats(c_stats), c_name])
		else:
			_log("│   [A] 丢弃 #%d 等级=%s (< min_tier=%d) %s" % [i, TIER_NAMES.get(t, "?"), min_tier, c_name])

	if after_tier.empty():
		_log("│   [A] 结果: tier 过滤后无候选")
		return NO_PICK

	# [B] forbid 过滤 + [C] 阈值过滤
	var after_filter: Array = []
	for c in after_tier:
		if _hits_forbid(c, forbid_stats):
			_log("│   [BC] 丢弃 #%d (命中禁止属性) %s" % [c["idx"], c["name"]])
			continue
		if respect_thresholds and _hits_threshold(c, player_index):
			_log("│   [BC] 丢弃 #%d (阈值拦截) %s" % [c["idx"], c["name"]])
			continue
		after_filter.append(c)

	if after_filter.empty():
		_log("│   [BC] 结果: forbid+阈值过滤后无候选")
		return NO_PICK
	_log("│   [BC] 结果: 过滤后剩 %d 个" % after_filter.size())

	# [D] 品质排序 (tier 降序, 等级相同按原 idx 保持稳定)
	if quality_first and after_filter.size() > 1:
		var qs = _QualitySorter.new()
		after_filter.sort_custom(qs, "compare")
		_log("│   [D] 品质排序后顺序: %s" % _short_order(after_filter))

	# [E] 优先级排序 (top tier 内按 stat_priority)
	if stat_priority.size() > 0 and after_filter.size() > 1:
		after_filter = _sort_by_priority(after_filter, stat_priority)
		_log("│   [E] 优先级排序后顺序: %s" % _short_order(after_filter))

	var picked: int = int(after_filter[0]["idx"])
	var picked_tier: int = int(after_filter[0]["tier"])
	_log("│   结果: 选 #%d 等级=%s %s" % [picked, TIER_NAMES.get(picked_tier, "?"), after_filter[0]["name"]])
	return picked


# 收集升级项涉及的 stat key (直接读 effects, 不依赖 autotato/effect_parser)。
# 只认直接 stat modifier (key 以 "stat_" 开头), 与 shop/threshold_gate 风格一致。
static func _collect_stats(upgrade_data) -> Array:
	var stats: Array = []
	if upgrade_data == null:
		return stats
	var effects = upgrade_data.get("effects")
	if typeof(effects) != TYPE_ARRAY:
		return stats
	for eff in effects:
		if typeof(eff) != TYPE_OBJECT and typeof(eff) != TYPE_DICTIONARY:
			continue
		var key = ""
		if eff.has_method("get"):
			key = eff.get("key")
		else:
			key = eff.get("key", "")
		key = str(key) if key != null else ""
		if key.begins_with("stat_") and not stats.has(key):
			stats.append(key)
	return stats


# forbid 命中: 升级项任一 stat 在 forbid_stats 中。
static func _hits_forbid(candidate: Dictionary, forbid_stats: Array) -> bool:
	var stats: Array = candidate.get("stats", [])
	for s in stats:
		if forbid_stats.has(s):
			return true
	return false


# 阈值拦截: 复用 shop/threshold_gate.should_reject_item。
# UpgradeData extends ItemData 有 effects 字段, 该方法通用, 零 autotato 依赖。
static func _hits_threshold(candidate: Dictionary, player_index: int) -> bool:
	var gate: Dictionary = _Gate.should_reject_item(candidate["data"], player_index)
	return bool(gate.get("reject", false))


# 优先级排序: top tier 内按 stat_priority 顺序, 越靠前越优。
# top tier 项数 < 2 时不排 (只有一个最高等级项, 排序无意义)。
static func _sort_by_priority(candidates: Array, stat_priority: Array) -> Array:
	var result := candidates.duplicate()
	var top_tier := -1
	for c in result:
		if int(c["tier"]) > top_tier:
			top_tier = int(c["tier"])
	var top_count := 0
	for c in result:
		if int(c["tier"]) == top_tier:
			top_count += 1
	if top_count < 2:
		return result
	var ps = _PrioritySorter.new(stat_priority)
	result.sort_custom(ps, "compare")
	return result


# ============================================================================
# 排序器 (内部类)
# ============================================================================

# 品质排序: tier 降序, 相同则按原 idx 升序 (保持稳定)。
class _QualitySorter:
	func compare(a: Dictionary, b: Dictionary) -> bool:
		if int(a["tier"]) != int(b["tier"]):
			return int(a["tier"]) > int(b["tier"])
		return int(a["idx"]) < int(b["idx"])


# 优先级排序: 候选涉及的 stat 在 stat_priority 中越靠前越优; 无匹配排最后 (9999)。
class _PrioritySorter:
	var _priority: Array

	func _init(priority: Array) -> void:
		_priority = priority

	# a 排在 b 前 return true
	func compare(a: Dictionary, b: Dictionary) -> bool:
		var pa: int = _best_priority(a)
		var pb: int = _best_priority(b)
		if pa != pb:
			return pa < pb
		return int(a["idx"]) < int(b["idx"])

	func _best_priority(c: Dictionary) -> int:
		var best: int = 9999
		for s in c.get("stats", []):
			var i: int = _priority.find(s)
			if i >= 0 and i < best:
				best = i
		return best


# ============================================================================
# Reroll 判断 (对齐 shop_automation._can_reroll)
# ============================================================================

# 返回 {ok: bool, price: int, reason: String}
static func _can_reroll(ui_adapter, player_index: int, general: Dictionary) -> Dictionary:
	var price: int = ui_adapter.at_get_upgrade_reroll_price(player_index)
	var gold: int = _Data.get_player_gold(player_index)

	if gold < price:
		return {"ok": false, "price": price, "reason": "金币不足 gold=%d price=%d" % [gold, price]}

	# reroll_budget = 0 不限制; > 0 时单次价格上限 (与商店语义一致)。
	var budget: int = int(general.get("reroll_budget", 0))
	if budget > 0 and price > budget:
		return {"ok": false, "price": price, "reason": "单次价格超 reroll_budget price=%d budget=%d" % [price, budget]}

	return {"ok": true, "price": price, "reason": ""}


# ============================================================================
# 私有 helpers
# ============================================================================

static func _empty_summary() -> Dictionary:
	return {"chosen": false, "rounds": 0, "reroll_spent": 0, "fallback_used": false}


# 升级项名称 (用于日志). name 是翻译键, 用 TranslationServer.translate 翻译
# (与 vanilla get_name_text 一致; tr() 是实例方法, 静态上下文不可用).
# 翻译失败时返回原 key, 至少不空. 回落 upgrade_id, 再回落 "?".
static func _upgrade_name(upgrade_data) -> String:
	if upgrade_data == null:
		return "?"
	var n = upgrade_data.get("name")
	if n != null and str(n) != "":
		return TranslationServer.translate(str(n))
	var uid = upgrade_data.get("upgrade_id")
	if uid != null and str(uid) != "":
		return str(uid)
	return "?"


# 属性列表简写: ["stat_damage", "stat_armor"] -> "damage,armor"
static func _short_stats(stats: Array) -> String:
	var parts: Array = []
	for s in stats:
		parts.append(str(s).replace("stat_", ""))
	return ", ".join(parts)


# 排序后顺序简写: [{idx, tier, ...}, ...] -> "#2(传说), #0(稀有), #1(普通)"
static func _short_order(candidates: Array) -> String:
	var parts: Array = []
	for c in candidates:
		parts.append("#%d(%s)" % [int(c["idx"]), TIER_NAMES.get(int(c["tier"]), "?")])
	return ", ".join(parts)


static func _log(msg: String) -> void:
	_Logger.info(msg, _LOG_NAME)
