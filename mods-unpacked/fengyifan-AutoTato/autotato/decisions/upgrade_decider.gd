extends Reference
class_name AT_UpgradeDecider

# ============================================================================
# AutoTato — Upgrade Decider (升级 4 选 1 决策器)
# ----------------------------------------------------------------------------
# 职责:
#   在玩家升级 (Level-up) 触发的 4 选 1 弹窗中, 根据用户配置自动挑选一项,
#   或返回 NO_PICK (-1) 把决定权交还给玩家手动选.
#
# 与决策层的位置:
#   - 与 P1 物品决策器共享同一份 threshold_config (P1 共识 A),
#     用户在 session_config.json 只配一次阈值, 升级/购物两条链路都消费.
#   - vanilla 的 UpgradeData 直接 extends ItemData (字段 effects / tier 等
#     完全对齐), 因此可直接复用 P0 的 ItemU.get_tier 与 Parser/Schema 抽象.
#
# 5 步决策流程:
#   1. enabled 检查      —— config.enabled == false 直接 NO_PICK
#   2. 候选构建          —— 包装 (original_index, data) 保留原始下标
#   3. tier 过滤         —— 剔除 tier < min_tier 的候选 (min_tier=-1 不过滤)
#   4. threshold 过滤    —— 调 Gate.should_reject_upgrade_by_threshold
#   5. quality 排序      —— quality_first=true 时按 tier 降序 (稳定排序)
#   6. 选第一或卡死回退  —— filtered 空时按 ignore_blacklist_on_stuck 决策
#
# 返回:
#   int — 选中的 0-based 索引 (用于 vanilla 升级 UI 点击); NO_PICK (-1)
#         表示交给玩家手动.
#
# 纯函数:
#   不读 RunData, 不写任何状态 (RunData 读取已封装在 Gate 内部).
#   ctx.current_danger 等字段 P1 未使用, 透传给 Gate 以便未来扩展.
# ============================================================================


const ItemU = preload("res://mods-unpacked/fengyifan-AutoTato/autotato/data/item_data_util.gd")
const Gate  = preload("res://mods-unpacked/fengyifan-AutoTato/autotato/decisions/threshold_gate.gd")

const LOG_NAME := "fengyifan-AutoTato:UpgradeDecider"

# 交给玩家手动的哨兵值, 与 vanilla UI 的 0-based 下标体系不冲突
const NO_PICK := -1


# ============================================================================
# 内部排序器 (Godot 3 sort_custom 的 instance method 派发)
#
# Godot 3 的 sort_custom 必须接收 (instance, method_name) 两个参数,
# 且 callback 必须返回 bool: true 表示 "a 应排在 b 之前".
# 注意: 内部 class 不能用外部 class_name (AT_UpgradeDecider) 自引用,
# 故所有常量直接以裸名引用 (同作用域).
# ============================================================================
class _QualitySorter:
	# 按 tier 降序排, tier 相同时按 original_index 升序 (稳定排序).
	# 这样保证 vanilla 给的 4 个选项在同 tier 时维持原顺序, UI 上不抖动.
	func compare_tier_desc(a, b) -> bool:
		var ta: int = int(a.get("tier", 0))
		var tb: int = int(b.get("tier", 0))
		if ta != tb:
			return ta > tb
		# 稳定 fallback: tier 相同时, 原索引小的排前面
		return int(a.get("original_index", 0)) < int(b.get("original_index", 0))


# ============================================================================
# 公开 API
# ============================================================================

# 主入口: 对一次 4 选 1 升级弹窗做决策.
#
# 输入:
#   option_list — Array<UpgradeData>, vanilla 提供, 通常 4 项 (兼容任意数量)
#   config      — Dictionary, 升级子配置:
#                   enabled                   : bool   未启用返 NO_PICK
#                   min_tier                  : int    0-3; -1 = 不限
#                   quality_first             : bool   true 按 tier 降序
#                   ignore_blacklist_on_stuck : bool   全过滤后是否回退选第一
#   context     — Dictionary, 决策上下文:
#                   player_index     : int
#                   current_danger   : int    P1 未消费但透传保持接口稳定
#                   threshold_config : Dictionary (与物品决策共享)
#
# 返回: int — 选中索引 (0-based) 或 NO_PICK (-1)
static func decide(option_list: Array, config: Dictionary, context: Dictionary) -> int:
	# 1. 总开关
	if not bool(config.get("enabled", false)):
		_log("disabled, NO_PICK")
		return NO_PICK

	# 2. 选项空 (vanilla 异常态)
	if option_list == null or option_list.size() == 0:
		_log("option_list empty, NO_PICK")
		return NO_PICK

	# 3. 解析 config 字段 (容错: 缺字段走保守默认)
	var min_tier: int = int(config.get("min_tier", -1))
	var quality_first: bool = bool(config.get("quality_first", true))
	var ignore_blacklist_on_stuck: bool = bool(config.get("ignore_blacklist_on_stuck", false))

	# 4. 解析 context
	var player_index: int = int(context.get("player_index", 0))
	var threshold_config: Dictionary = context.get("threshold_config", {})
	if typeof(threshold_config) != TYPE_DICTIONARY:
		threshold_config = {}

	# 5. 构建候选数组 (保留 original_index, 排序后仍能反查 vanilla 下标)
	var all_candidates: Array = _build_candidates(option_list)

	# 6. tier 过滤
	var after_tier: Array = _filter_by_tier(all_candidates, min_tier)

	# 7. threshold 过滤
	var after_threshold: Array = _filter_by_threshold(after_tier, threshold_config, player_index)

	# 8. 质量排序 (在 filtered 上排; 卡死回退场景在 _pick_first_or_stuck 内再排 all)
	var sorted_filtered: Array = _sort_by_quality(after_threshold, quality_first)

	# 9. 选第一或卡死回退
	return _pick_first_or_stuck(sorted_filtered, all_candidates, quality_first, ignore_blacklist_on_stuck)


# ============================================================================
# 私有 helpers
# ============================================================================

# 构建候选数组. 每个元素是 Dictionary:
#   {"original_index": int, "data": UpgradeData, "tier": int}
# 把 tier 提前算出来缓存, 后续排序/过滤都直接读, 避免反复进 ItemU.
static func _build_candidates(option_list: Array) -> Array:
	var result: Array = []
	for i in range(option_list.size()):
		var data = option_list[i]
		var tier: int = ItemU.get_tier(data)
		result.append({
			"original_index": i,
			"data": data,
			"tier": tier,
		})
	return result


# 过滤 tier < min_tier 的候选.
# min_tier == -1 表示不限, 直接返回 candidates.duplicate() (副本, 避免上游误改).
static func _filter_by_tier(candidates: Array, min_tier: int) -> Array:
	if min_tier < 0:
		return candidates.duplicate()
	var result: Array = []
	for c in candidates:
		var tier: int = int(c.get("tier", 0))
		if tier >= min_tier:
			result.append(c)
	return result


# 调 Gate.should_reject_upgrade_by_threshold, 过滤被反转 (rejected) 的候选.
# 入参 candidates 是上一步 tier 过滤后的列表.
#
# 容错: threshold_config 空 dict 时, Gate 会快速返回 should_reject=false,
# 故此函数无需特判, 直接交给 Gate.
static func _filter_by_threshold(candidates: Array, threshold_config: Dictionary, player_index: int) -> Array:
	var result: Array = []
	for c in candidates:
		var verdict: Dictionary = Gate.should_reject_upgrade_by_threshold(
			c.get("data"),
			threshold_config,
			player_index
		)
		if not bool(verdict.get("should_reject", false)):
			result.append(c)
	return result


# 按 tier 降序排. quality_first=false 时不排 (保持原顺序).
# Godot 3 的 sort_custom 不保证稳定, 我们在比较器内用 original_index 做 tie-break
# 来手工实现稳定排序.
static func _sort_by_quality(candidates: Array, quality_first: bool) -> Array:
	var result: Array = candidates.duplicate()
	if not quality_first:
		return result
	if result.size() <= 1:
		return result
	# Godot 3 sort_custom 推荐姿势: instance + method name
	var sorter = _QualitySorter.new()
	result.sort_custom(sorter, "compare_tier_desc")
	return result


# 选第一个或卡死回退.
#
# filtered 已按 quality_first 排好序; all_candidates 是未过滤的全集.
# 行为:
#   - filtered 非空 → 返回 filtered[0].original_index
#   - filtered 空 + ignore_blacklist_on_stuck=true → 回到全集, 按 quality_first
#     排序后选第一 (不再过滤, 因为卡死时用户期望"硬选一个")
#   - filtered 空 + ignore_blacklist_on_stuck=false → NO_PICK (交给玩家)
static func _pick_first_or_stuck(
		filtered: Array,
		all_candidates: Array,
		quality_first: bool,
		ignore_blacklist_on_stuck: bool
	) -> int:
	if filtered.size() > 0:
		return int(filtered[0].get("original_index", NO_PICK))

	if not ignore_blacklist_on_stuck:
		_log("filtered empty & no stuck-fallback, NO_PICK")
		return NO_PICK

	# 卡死回退: 全集再排一次, 选第一
	if all_candidates.size() == 0:
		return NO_PICK
	var fallback_sorted: Array = _sort_by_quality(all_candidates, quality_first)
	if fallback_sorted.size() == 0:
		return NO_PICK
	_log("filtered empty, stuck-fallback to all_candidates[0]")
	return int(fallback_sorted[0].get("original_index", NO_PICK))


# 统一日志出口. LOG_NAME 全 mod 唯一, 满足 ModLoader 约定.
static func _log(msg: String) -> void:
	if typeof(ModLoaderLog) != TYPE_NIL:
		ModLoaderLog.debug(msg, LOG_NAME)
