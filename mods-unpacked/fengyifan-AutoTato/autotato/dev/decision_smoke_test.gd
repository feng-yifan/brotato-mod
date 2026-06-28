extends Reference

# ============================================================================
# AutoTato — 决策层烟雾测试
# ============================================================================
#
# 目的: 验证决策器层 (decision_result / threshold_gate / item_decider /
#       upgrade_decider) 在不接入运行时的纯函数语义下行为正确.
#
# 与数据层烟雾脚本独立: 数据层测的是数据解析 (Effect 解析 / Keys 字典 / Util 双形态),
# 决策层测的是决策器 (action 路由 / 阈值闸门 / 升级 4 选 1 排序).
#
# 触发: 默认关闭. mod_main.gd 把 DEV_RUN_DECISION_SMOKE 改 true 即可在游戏启动时
#       自动跑 run(), 结果写到 godot.log.
#
# 用例总览 (13 个):
#   Item Decider 部分 (8 用例)
#     1.  reject 动作 -> 立即 SKIPPED
#     2.  正常 get 通过预算墙 -> PURCHASED
#     3.  get 但预算墙不通过 -> SKIPPED, reason 含 "预算"
#     4.  lock_until_cursed + 非诅咒 -> LOCKED
#     5.  lock_until_cursed + 诅咒版 -> PURCHASED
#     6.  Medal 多 stat 部分阈值未全触达 -> NOT SKIPPED
#     7.  Medal 多 stat 全部阈值触达 -> SKIPPED, reason 含 "阈值"
#     8.  非法 action 字符串 -> MANUAL (回落)
#
#   Threshold Gate 部分 (3 用例)
#     9.  configured_stats 只取物品 effects ∩ config (不含的 stat 不参与)
#     10. 无血手联动闭包 -> 单 stat upper 触达即反转
#     11. unlimited 模式短路 -> should_reject=false 且 value 保留
#
#   Upgrade Decider 部分 (2 用例)
#     12. min_tier + quality_first -> 选 tier 最高且 >= min_tier 的 original_index
#     13. enabled=false -> 返回 -1 (NO_PICK)
#
# 物品 mock 策略:
#   - 简单单 stat / 边界路径用 mock dict (effects=[]), 走纯路由分支
#   - 多 stat 阈值用例用 vanilla Medal (5 stat: max_hp/percent_damage/armor/
#     speed/crit_chance), 真实跑 EffectParser 解析链路
# ============================================================================

const LOG_NAME := "fengyifan-AutoTato:DecisionSmokeTest"

const Result   = preload("res://mods-unpacked/fengyifan-AutoTato/autotato/decisions/decision_result.gd")
const Gate     = preload("res://mods-unpacked/fengyifan-AutoTato/autotato/decisions/threshold_gate.gd")
const ItemDec  = preload("res://mods-unpacked/fengyifan-AutoTato/autotato/decisions/item_decider.gd")
const UpgDec   = preload("res://mods-unpacked/fengyifan-AutoTato/autotato/decisions/upgrade_decider.gd")

# Medal: 5 stat 物品 (vanilla 1.1.15.4)
#   tier=1, value=55, max_nb=-1, is_cursed=false
#   effects: stat_max_hp +3, stat_percent_damage +3, stat_armor +1,
#            stat_speed +3, stat_crit_chance -4
const MEDAL_DATA_TRES := "res://items/all/medal/medal_data.tres"

# 计数: 通过/失败/警告
var _pass := 0
var _fail := 0
var _warn := 0


# ----------------------------------------------------------------------------
# 入口
# ----------------------------------------------------------------------------
func run() -> void:
	_log("════════ 决策层烟雾测试开始 ════════")

	# Item Decider
	_test_1_reject_action()
	_test_2_normal_get_purchased()
	_test_3_get_budget_wall_skipped()
	_test_4_lock_until_cursed_non_cursed_locked()
	_test_5_lock_until_cursed_cursed_purchased()
	_test_6_multi_stat_partial_threshold_not_rejected()
	_test_7_multi_stat_full_threshold_rejected()
	_test_8_invalid_action_falls_back_manual()

	# Threshold Gate
	_test_9_configured_stats_subset()
	_test_10_linkage_closure_without_blood_hand()
	_test_11_unlimited_short_circuit()

	# Upgrade Decider
	_test_12_upgrade_min_tier_quality_first()
	_test_13_upgrade_disabled_returns_minus_one()

	_log("════════ 决策层烟雾测试结束 ════════")
	_log("结果: %d 通过 / %d 失败 / %d 警告" % [_pass, _fail, _warn])
	if _fail > 0:
		ModLoaderLog.error("决策器有 %d 项失败, 请检查上方日志" % _fail, LOG_NAME)


# ============================================================================
# Item Decider 用例
# ============================================================================

# ----------------------------------------------------------------------------
# 用例 1: shop_action=reject -> 立即 SKIPPED, 不论物品/上下文
# ----------------------------------------------------------------------------
func _test_1_reject_action() -> void:
	_section("[1] shop_action=reject 立即 SKIPPED")

	var item := _make_default_item("item_test_reject")
	var rule := {"shop_action": "reject"}
	var context := _make_default_context(100)

	var r = ItemDec.decide(item, rule, context)
	_assert(r != null, "decide() 应返回非 null")
	if r == null:
		return
	_assert(r.terminal_state == Result.STATE_SKIPPED,
		"terminal_state 应为 SKIPPED, 实得 %s" % r.terminal_state)
	_assert(r.reason.find("reject") >= 0,
		"reason 应含 'reject', 实得 '%s'" % r.reason)
	_log("  %s" % r._to_string())


# ----------------------------------------------------------------------------
# 用例 2: shop_action=get + 预算充足 -> PURCHASED
# ----------------------------------------------------------------------------
func _test_2_normal_get_purchased() -> void:
	_section("[2] shop_action=get 预算充足 -> PURCHASED")

	var item := _make_default_item("item_test_get", 20, 1, false, -1)
	var rule := {"shop_action": "get"}
	var context := _make_default_context(100)

	var r = ItemDec.decide(item, rule, context)
	_assert(r != null, "decide() 应返回非 null")
	if r == null:
		return
	_assert(r.terminal_state == Result.STATE_PURCHASED,
		"terminal_state 应为 PURCHASED, 实得 %s (reason=%s)" % [r.terminal_state, r.reason])
	_log("  %s" % r._to_string())


# ----------------------------------------------------------------------------
# 用例 3: shop_action=get + 预算墙挡住 -> SKIPPED, reason 含 "预算"
# ----------------------------------------------------------------------------
func _test_3_get_budget_wall_skipped() -> void:
	_section("[3] shop_action=get 预算不足 -> SKIPPED")

	var item := _make_default_item("item_test_poor", 20, 1, false, -1)
	var rule := {"shop_action": "get"}
	var context := _make_default_context(5)
	context["min_gold_balance"] = 20

	var r = ItemDec.decide(item, rule, context)
	_assert(r != null, "decide() 应返回非 null")
	if r == null:
		return
	_assert(r.terminal_state == Result.STATE_SKIPPED,
		"terminal_state 应为 SKIPPED, 实得 %s" % r.terminal_state)
	_assert(r.reason.find("预算") >= 0,
		"reason 应含 '预算', 实得 '%s'" % r.reason)
	_log("  %s" % r._to_string())


# ----------------------------------------------------------------------------
# 用例 4: shop_action=lock_until_cursed + 非诅咒版本 -> LOCKED
# ----------------------------------------------------------------------------
func _test_4_lock_until_cursed_non_cursed_locked() -> void:
	_section("[4] lock_until_cursed + 非诅咒 -> LOCKED")

	var item := _make_default_item("item_test_lockable", 20, 1, false, -1)
	var rule := {"shop_action": "lock_until_cursed"}
	var context := _make_default_context(100)

	var r = ItemDec.decide(item, rule, context)
	_assert(r != null, "decide() 应返回非 null")
	if r == null:
		return
	_assert(r.terminal_state == Result.STATE_LOCKED,
		"terminal_state 应为 LOCKED, 实得 %s (reason=%s)" % [r.terminal_state, r.reason])
	_log("  %s" % r._to_string())


# ----------------------------------------------------------------------------
# 用例 5: shop_action=lock_until_cursed + 诅咒版本 + 预算够 -> PURCHASED
# ----------------------------------------------------------------------------
func _test_5_lock_until_cursed_cursed_purchased() -> void:
	_section("[5] lock_until_cursed + 诅咒版 -> PURCHASED")

	var item := _make_default_item("item_test_cursed", 20, 1, true, -1)
	var rule := {"shop_action": "lock_until_cursed"}
	var context := _make_default_context(100)

	var r = ItemDec.decide(item, rule, context)
	_assert(r != null, "decide() 应返回非 null")
	if r == null:
		return
	_assert(r.terminal_state == Result.STATE_PURCHASED,
		"terminal_state 应为 PURCHASED, 实得 %s (reason=%s)" % [r.terminal_state, r.reason])
	_log("  %s" % r._to_string())


# ----------------------------------------------------------------------------
# 用例 6: Medal 多 stat + 阈值仅 stat_max_hp 配 upper=1 (其他未配)
#   规则: configured_stats = related_stats ∩ config.keys() = {stat_max_hp},
#         即便 stat_max_hp 触达, 也只是 1 个 stat 全部触达 -> should_reject=true
#   --> 因此本用例应**反过来验证**: 仅 stat_max_hp 配置且触达, 全部 configured
#       stat 都触达 -> 决策应被反转为 SKIPPED.
#   但用户给的设计意图: 只看物品涉及的多 stat 是否全部触达, 未配的 stat 不参与.
#   因此把 stat_max_hp 配为 upper=value 远大于当前 (current=0 < value=999),
#   "未触达" -> NOT SKIPPED 的语义最直观.
# ----------------------------------------------------------------------------
func _test_6_multi_stat_partial_threshold_not_rejected() -> void:
	_section("[6] Medal 部分 stat 配阈值且未触达 -> NOT SKIPPED")

	var medal_res = load(MEDAL_DATA_TRES)
	if medal_res == null:
		_warn_case("无法 load %s, 跳过本用例" % MEDAL_DATA_TRES)
		return

	var rule := {"shop_action": "get"}
	var context := _make_default_context(200)
	# 主菜单 current stat 值都是 0; upper=999 远大于 0, 未触达
	context["threshold_config"] = {
		"stat_max_hp": {"mode": "upper", "value": 999},
	}

	var r = ItemDec.decide(medal_res, rule, context)
	_assert(r != null, "decide() 应返回非 null")
	if r == null:
		return
	# 至少不应是阈值反转导致的 SKIPPED;
	# 预算够 (Medal value=55, gold=200), 应走到 PURCHASED
	_assert(r.terminal_state == Result.STATE_PURCHASED,
		"应通过阈值闸门 + 预算墙 -> PURCHASED, 实得 %s (reason=%s)" %
		[r.terminal_state, r.reason])
	_log("  %s" % r._to_string())


# ----------------------------------------------------------------------------
# 用例 7: Medal 多 stat + 全部相关 stat 都配 upper=0 (current 0 >= 0 触达)
#   预期: 5 个 stat (max_hp/percent_damage/armor/speed/crit_chance) 全部触达
#         -> should_reject=true -> SKIPPED, reason 含 "阈值"
# ----------------------------------------------------------------------------
func _test_7_multi_stat_full_threshold_rejected() -> void:
	_section("[7] Medal 全部 stat 配阈值且触达 -> SKIPPED")

	var medal_res = load(MEDAL_DATA_TRES)
	if medal_res == null:
		_warn_case("无法 load %s, 跳过本用例" % MEDAL_DATA_TRES)
		return

	var rule := {"shop_action": "get"}
	var context := _make_default_context(200)
	# 把 Medal 涉及的 5 个 stat 全部配 upper=0
	# 主菜单 current=0, 0 >= 0 触达 -> 全部触达 -> 反转
	context["threshold_config"] = {
		"stat_max_hp":         {"mode": "upper", "value": 0},
		"stat_percent_damage": {"mode": "upper", "value": 0},
		"stat_armor":          {"mode": "upper", "value": 0},
		"stat_speed":          {"mode": "upper", "value": 0},
		"stat_crit_chance":    {"mode": "upper", "value": 0},
	}

	var r = ItemDec.decide(medal_res, rule, context)
	_assert(r != null, "decide() 应返回非 null")
	if r == null:
		return
	_assert(r.terminal_state == Result.STATE_SKIPPED,
		"terminal_state 应为 SKIPPED, 实得 %s (reason=%s)" %
		[r.terminal_state, r.reason])
	_assert(r.reason.find("阈值") >= 0,
		"reason 应含 '阈值', 实得 '%s'" % r.reason)
	_log("  %s" % r._to_string())


# ----------------------------------------------------------------------------
# 用例 8: 非法 action 字符串 -> 回落 manual -> STATE_MANUAL
# ----------------------------------------------------------------------------
func _test_8_invalid_action_falls_back_manual() -> void:
	_section("[8] 非法 action -> MANUAL")

	var item := _make_default_item("item_test_invalid")
	var rule := {"shop_action": "bogus_action_xyz"}
	var context := _make_default_context(100)

	var r = ItemDec.decide(item, rule, context)
	_assert(r != null, "decide() 应返回非 null")
	if r == null:
		return
	_assert(r.terminal_state == Result.STATE_MANUAL,
		"terminal_state 应为 MANUAL, 实得 %s" % r.terminal_state)
	_assert(r.reason.find("manual") >= 0,
		"reason 应含 'manual', 实得 '%s'" % r.reason)
	_log("  %s" % r._to_string())


# ============================================================================
# Threshold Gate 用例
# ============================================================================

# ----------------------------------------------------------------------------
# 用例 9: configured_stats 只含 (related ∩ config.keys()),
#   物品自己不含的 stat 即便配了阈值也不参与判断.
#   Medal 含 stat_max_hp/percent_damage/armor/speed/crit_chance,
#   不含 stat_lifesteal. 配 stat_lifesteal 与 stat_max_hp 两个阈值,
#   should_reject 应只看 stat_max_hp 是否触达 (stat_lifesteal 被排除).
# ----------------------------------------------------------------------------
func _test_9_configured_stats_subset() -> void:
	_section("[9] configured_stats 只取物品涉及的 stat")

	var medal_res = load(MEDAL_DATA_TRES)
	if medal_res == null:
		_warn_case("无法 load %s, 跳过本用例" % MEDAL_DATA_TRES)
		return

	# stat_lifesteal 配但 Medal 不含; stat_max_hp 配且 Medal 含且触达
	var threshold_config := {
		"stat_lifesteal": {"mode": "upper", "value": 0},
		"stat_max_hp":    {"mode": "upper", "value": 0},
	}

	var verdict: Dictionary = Gate.should_reject_by_threshold(medal_res, threshold_config, 0)
	_log("  related_stats=%s" % str(verdict.get("related_stats", [])))
	_log("  configured_stats=%s" % str(verdict.get("configured_stats", [])))
	_log("  should_reject=%s reason=%s" % [str(verdict.get("should_reject", false)), str(verdict.get("reason", ""))])

	var configured_stats: Array = verdict.get("configured_stats", [])
	_assert(configured_stats.has("stat_max_hp"),
		"configured_stats 应含 stat_max_hp")
	_assert(not configured_stats.has("stat_lifesteal"),
		"configured_stats 不应含 stat_lifesteal (物品自身不修饰该 stat)")


# ----------------------------------------------------------------------------
# 用例 10: 无血手联动闭包 -> Medal 仅依靠自身 stat 判定
#   主菜单状态下玩家 RunData 一般为空, 联动桶扫描安全 skip;
#   threshold_config 仅给 stat_max_hp upper=0, Medal 自身含 stat_max_hp,
#   全部 configured stat (只有 1 个 max_hp) 都触达 -> should_reject=true.
#
#   说明: 这模拟了"用户没装血手 (gain_stat_for_every_stat 桶为空)" 场景,
#   联动闭包不扩展, 闸门只看直接 stat.
# ----------------------------------------------------------------------------
func _test_10_linkage_closure_without_blood_hand() -> void:
	_section("[10] 无联动闭包 -> 直接 stat 触达即反转")

	var medal_res = load(MEDAL_DATA_TRES)
	if medal_res == null:
		_warn_case("无法 load %s, 跳过本用例" % MEDAL_DATA_TRES)
		return

	var threshold_config := {
		"stat_max_hp": {"mode": "upper", "value": 0},
	}

	var verdict: Dictionary = Gate.should_reject_by_threshold(medal_res, threshold_config, 0)
	_log("  related_stats=%s" % str(verdict.get("related_stats", [])))
	_log("  configured_stats=%s" % str(verdict.get("configured_stats", [])))
	_log("  should_reject=%s reason=%s" % [str(verdict.get("should_reject", false)), str(verdict.get("reason", ""))])

	_assert(bool(verdict.get("should_reject", false)) == true,
		"无联动且 stat_max_hp upper=0 触达 -> should_reject 应为 true")


# ----------------------------------------------------------------------------
# 用例 11: unlimited 模式短路 -> should_reject=false
#   stat_armor 配 unlimited (value 任意), Medal 含 stat_armor,
#   configured_stats 包含 stat_armor 但 mode=unlimited 立刻返回 false.
# ----------------------------------------------------------------------------
func _test_11_unlimited_short_circuit() -> void:
	_section("[11] unlimited 模式短路")

	var medal_res = load(MEDAL_DATA_TRES)
	if medal_res == null:
		_warn_case("无法 load %s, 跳过本用例" % MEDAL_DATA_TRES)
		return

	var threshold_config := {
		"stat_armor": {"mode": "unlimited", "value": 100},
	}

	var verdict: Dictionary = Gate.should_reject_by_threshold(medal_res, threshold_config, 0)
	_log("  related_stats=%s" % str(verdict.get("related_stats", [])))
	_log("  configured_stats=%s" % str(verdict.get("configured_stats", [])))
	_log("  should_reject=%s reason=%s" % [str(verdict.get("should_reject", false)), str(verdict.get("reason", ""))])

	_assert(bool(verdict.get("should_reject", false)) == false,
		"unlimited 应立即返回 should_reject=false")
	var configured_stats: Array = verdict.get("configured_stats", [])
	_assert(configured_stats.has("stat_armor"),
		"configured_stats 应含 stat_armor (说明确实参与了判断, 只是被 unlimited 短路)")


# ============================================================================
# Upgrade Decider 用例
# ============================================================================

# ----------------------------------------------------------------------------
# 用例 12: min_tier + quality_first 排序 -> 选 tier 最高且 >= min_tier
#   option_list 顺序: tier=[0, 2, 3, 1] (index 0..3)
#   min_tier=2 过滤掉 tier=0 与 tier=1, 留下 index 1 (tier=2) 与 index 2 (tier=3)
#   quality_first=true 按 tier 降序 -> tier=3 在前 -> 返回 original_index=2
# ----------------------------------------------------------------------------
func _test_12_upgrade_min_tier_quality_first() -> void:
	_section("[12] Upgrade: min_tier + quality_first")

	var option_list: Array = [
		_make_upgrade_dict("upg_t0", 0),
		_make_upgrade_dict("upg_t2", 2),
		_make_upgrade_dict("upg_t3", 3),
		_make_upgrade_dict("upg_t1", 1),
	]
	var config := {
		"enabled": true,
		"min_tier": 2,
		"quality_first": true,
		"ignore_forbid_on_stuck": false,
	}
	var context := {
		"player_index": 0,
		"current_danger": 0,
		"threshold_config": {},
	}

	var picked: int = UpgDec.decide(option_list, config, context)
	_log("  picked index=%d (期望 2, 即 tier=3 那一项)" % picked)
	_assert(picked == 2, "应选 original_index=2 (tier=3), 实得 %d" % picked)


# ----------------------------------------------------------------------------
# 用例 13: enabled=false -> 返回 NO_PICK (-1), 不论 option_list
# ----------------------------------------------------------------------------
func _test_13_upgrade_disabled_returns_minus_one() -> void:
	_section("[13] Upgrade: enabled=false -> NO_PICK")

	var option_list: Array = [
		_make_upgrade_dict("upg_a", 3),
		_make_upgrade_dict("upg_b", 2),
	]
	var config := {
		"enabled": false,
		"min_tier": 0,
		"quality_first": true,
		"ignore_forbid_on_stuck": false,
	}
	var context := {
		"player_index": 0,
		"current_danger": 0,
		"threshold_config": {},
	}

	var picked: int = UpgDec.decide(option_list, config, context)
	_log("  picked index=%d (期望 -1 / NO_PICK)" % picked)
	_assert(picked == UpgDec.NO_PICK, "应返回 NO_PICK(-1), 实得 %d" % picked)


# ============================================================================
# Mock 数据构造器
# ============================================================================

# 通用 context 构造器, 默认值与 ItemDecider 接口契约对齐.
func _make_default_context(gold: int = 100) -> Dictionary:
	return {
		"currency": gold,
		"player_index": 0,
		"is_crate": false,
		"current_danger": 0,
		"threshold_config": {},
		"min_gold_balance": 0,
		"item_price_threshold": 0,
		"shop_respect_thresholds": true,
		"chest_respect_thresholds": false,
	}


# 通用 mock ItemData dict. effects=[] 让 Parser.parse_list 返回 [],
# is_at_limit 不进入 RunData.get_player_items 的真实逻辑 (max_nb<=0 视为无限).
func _make_default_item(
		my_id: String = "test_item",
		value: int = 20,
		tier: int = 1,
		is_cursed: bool = false,
		max_nb: int = -1
	) -> Dictionary:
	return {
		"my_id": my_id,
		"name": "TEST_ITEM",
		"tier": tier,
		"value": value,
		"max_nb": max_nb,
		"is_cursed": is_cursed,
		"is_lockable": true,
		"tags": [],
		"effects": [],
	}


# 升级选项的 mock dict. UpgradeData 与 ItemData 结构对齐, 这里只需 tier 字段
# 真实参与判断, 其余字段保留契约可读性.
func _make_upgrade_dict(my_id: String, tier: int) -> Dictionary:
	return {
		"my_id": my_id,
		"name": "TEST_UPGRADE",
		"tier": tier,
		"value": 0,
		"max_nb": -1,
		"is_cursed": false,
		"is_lockable": false,
		"tags": [],
		"effects": [],
	}


# ============================================================================
# 测试辅助 (照搬数据层风格)
# ============================================================================

func _section(title: String) -> void:
	_log("──── %s ────" % title)


func _assert(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
		_log("  ✓ %s" % msg)
	else:
		_fail += 1
		ModLoaderLog.error("  ✗ %s" % msg, LOG_NAME)


func _fail_case(msg: String) -> void:
	_fail += 1
	ModLoaderLog.error("  ✗ %s" % msg, LOG_NAME)


func _warn_case(msg: String) -> void:
	_warn += 1
	ModLoaderLog.warning("  ⚠ %s" % msg, LOG_NAME)


func _log(msg: String) -> void:
	ModLoaderLog.info(msg, LOG_NAME)
