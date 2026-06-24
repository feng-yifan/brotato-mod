extends Reference

# ============================================================================
# AutoTato — P2 烟雾测试 (Bridge)
# ============================================================================
#
# 目的: 验证 P2 Bridge 层在不接入 vanilla autoload 的前提下行为正确,
#       覆盖默认 config / CRUD / 决策入口 / 总开关 / 深拷贝五个维度.
#
# 与 P0 / P1 烟雾脚本独立:
#   - P0 测数据层 (Effect 解析 / Keys / Util 双形态)
#   - P1 测决策器层 (action 路由 / 阈值闸门 / 升级 4 选 1 排序, static 纯函数)
#   - P2 测 Bridge 胶水层 (持状态的 config + 三个决策入口)
#
# 触发: 默认关闭. mod_main.gd 把 DEV_RUN_P2_SMOKE 改 true 即可在游戏启动时
#       自动 .new() 出实例并调 run(), 结果写到 godot.log.
#       亦可通过 AUTOTATO_P2_SMOKE 环境变量在 mod_main 中读取触发.
#
# 用例总览 (15 个):
#   默认 config / CRUD (5 用例)
#     1. 默认 config 含 5 个预设阈值
#     2. 默认 5 阈值的具体 value 值
#     3. get_config() 返回深拷贝
#     4. set_item_rule + get_item_rule 持久化
#     5. remove_item_rule 后 get 返回 {}
#
#   决策入口 (4 用例)
#     6. decide_shop_item + reject rule -> SKIPPED
#     7. decide_shop_item 无规则 -> MANUAL (回落)
#     8. shop_automation_enabled=false -> MANUAL (短路)
#     9. 默认阈值不阻挡无关 stat -> PURCHASED
#
#   阈值 CRUD + 决策 (3 用例)
#     10. set_threshold + Medal 真实物品阈值触达 -> SKIPPED
#     11. unlimited 模式 + value 字段保留
#     12. decide_upgrade + upgrade_automation_enabled=false -> NO_PICK
#
#   Upgrade / General / Threshold remove (3 用例)
#     13. set_upgrade_config min_tier + quality_first -> 选 tier 最高
#     14. set_general min_gold_balance 透传到决策器
#     15. remove_threshold 后 get 返回 {}
#
# 用例间状态隔离:
#   每个 _test_* 内独立 new 一个 Bridge 实例, 不共享状态.
#   Bridge 继承 Reference, 引用计数自动释放, 无需手动 free.
#
# 物品 mock 策略:
#   - 大部分用例用 mock dict (effects=[], 不触阈值)
#   - 用例 10 用 vanilla Medal .tres 真实跑 EffectParser 解析链路
# ============================================================================

const LOG_NAME := "fengyifan-AutoTato:P2SmokeTest"

const Bridge = preload("res://mods-unpacked/fengyifan-AutoTato/autotato/runtime/bridge.gd")
const Result = preload("res://mods-unpacked/fengyifan-AutoTato/autotato/decisions/decision_result.gd")
const UpgDec = preload("res://mods-unpacked/fengyifan-AutoTato/autotato/decisions/upgrade_decider.gd")

# Medal: 5 stat 物品 (vanilla 1.1.15.4)
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
	_log("════════ P2 烟雾测试开始 ════════")

	# 默认 config / CRUD
	_test_1_default_config()
	_test_2_default_thresholds_values()
	_test_3_get_config_deep_copy()
	_test_4_set_item_rule_persists()
	_test_5_remove_item_rule()

	# 决策入口
	_test_6_decide_shop_with_rule_reject()
	_test_7_decide_shop_no_rule_returns_manual()
	_test_8_decide_shop_disabled_returns_manual()
	_test_9_default_thresholds_no_match_passes()

	# 阈值 CRUD + 决策
	_test_10_threshold_override_blocks()
	_test_11_threshold_unlimited_value_preserved()
	_test_12_decide_upgrade_disabled()

	# Upgrade / General / Threshold remove
	_test_13_decide_upgrade_min_tier()
	_test_14_set_general_passthrough()
	_test_15_remove_threshold_returns_empty()

	_log("════════ P2 烟雾测试结束 ════════")
	_log("结果: %d 通过 / %d 失败 / %d 警告" % [_pass, _fail, _warn])
	if _fail > 0:
		ModLoaderLog.error("P2 Bridge 有 %d 项失败, 请检查上方日志" % _fail, LOG_NAME)


# ============================================================================
# 默认 config / CRUD 用例
# ============================================================================

# ----------------------------------------------------------------------------
# 用例 1: 新建 Bridge 默认 thresholds 含 5 个预设 stat, 全部 mode=upper
# ----------------------------------------------------------------------------
func _test_1_default_config() -> void:
	_section("[1] 默认 config 含 5 个预设阈值")

	var b = Bridge.new()
	var ths: Dictionary = b.get_thresholds()
	_log("  thresholds.size=%d keys=%s" % [ths.size(), str(ths.keys())])

	_assert(ths.size() >= 5, "thresholds 字典大小应 >= 5, 实得 %d" % ths.size())
	_assert(ths.has("stat_speed"), "应含 stat_speed")
	_assert(ths.has("stat_armor"), "应含 stat_armor")
	_assert(ths.has("stat_dodge"), "应含 stat_dodge")
	_assert(ths.has("stat_hp_regeneration"), "应含 stat_hp_regeneration")
	_assert(ths.has("stat_crit_chance"), "应含 stat_crit_chance")

	for k in ths.keys():
		var t: Dictionary = ths[k]
		_assert(String(t.get("mode", "")) == "upper",
			"%s.mode 应为 'upper', 实得 '%s'" % [k, str(t.get("mode", ""))])


# ----------------------------------------------------------------------------
# 用例 2: 默认 5 阈值的具体 value 值
# ----------------------------------------------------------------------------
func _test_2_default_thresholds_values() -> void:
	_section("[2] 默认阈值 value 取值正确")

	var b = Bridge.new()
	var ths: Dictionary = b.get_thresholds()

	_assert(int(ths.get("stat_speed", {}).get("value", -1)) == 20,
		"stat_speed.value 应为 20, 实得 %s" % str(ths.get("stat_speed", {}).get("value", -1)))
	_assert(int(ths.get("stat_armor", {}).get("value", -1)) == 10,
		"stat_armor.value 应为 10, 实得 %s" % str(ths.get("stat_armor", {}).get("value", -1)))
	_assert(int(ths.get("stat_dodge", {}).get("value", -1)) == 60,
		"stat_dodge.value 应为 60, 实得 %s" % str(ths.get("stat_dodge", {}).get("value", -1)))
	_assert(int(ths.get("stat_hp_regeneration", {}).get("value", -1)) == 10,
		"stat_hp_regeneration.value 应为 10, 实得 %s" % str(ths.get("stat_hp_regeneration", {}).get("value", -1)))
	_assert(int(ths.get("stat_crit_chance", {}).get("value", -1)) == 100,
		"stat_crit_chance.value 应为 100, 实得 %s" % str(ths.get("stat_crit_chance", {}).get("value", -1)))


# ----------------------------------------------------------------------------
# 用例 3: get_config() 返回深拷贝 (上层篡改不会污染内部 _config)
# ----------------------------------------------------------------------------
func _test_3_get_config_deep_copy() -> void:
	_section("[3] get_config() 返回深拷贝")

	var b = Bridge.new()
	var cfg1: Dictionary = b.get_config()
	# 在 cfg1 里植入一个污染 key
	(cfg1.get("thresholds", {}) as Dictionary)["stat_INJECTED"] = {"mode": "upper", "value": 99}

	var cfg2: Dictionary = b.get_config()
	var ths2: Dictionary = cfg2.get("thresholds", {})
	_log("  cfg2.thresholds.has(stat_INJECTED)=%s" % str(ths2.has("stat_INJECTED")))

	_assert(not ths2.has("stat_INJECTED"),
		"内部 _config 不应被外部篡改污染")


# ----------------------------------------------------------------------------
# 用例 4: set_item_rule + get_item_rule 持久化字段
# ----------------------------------------------------------------------------
func _test_4_set_item_rule_persists() -> void:
	_section("[4] set_item_rule 持久化 + get_item_rule 读回")

	var b = Bridge.new()
	b.set_item_rule("test_x", {"shop_action": "reject", "chest_action": "take"})
	var got: Dictionary = b.get_item_rule("test_x")
	_log("  got=%s" % str(got))

	_assert(String(got.get("shop_action", "")) == "reject",
		"shop_action 应为 'reject', 实得 '%s'" % str(got.get("shop_action", "")))
	_assert(String(got.get("chest_action", "")) == "take",
		"chest_action 应为 'take', 实得 '%s'" % str(got.get("chest_action", "")))


# ----------------------------------------------------------------------------
# 用例 5: remove_item_rule 后 get 返回 {}
# ----------------------------------------------------------------------------
func _test_5_remove_item_rule() -> void:
	_section("[5] remove_item_rule 后查询返回 {}")

	var b = Bridge.new()
	b.set_item_rule("test_x", {"shop_action": "reject"})
	b.remove_item_rule("test_x")
	var got: Dictionary = b.get_item_rule("test_x")
	_log("  got=%s (size=%d)" % [str(got), got.size()])

	_assert(got.size() == 0, "删除后 get_item_rule 应返回空 dict, 实得 size=%d" % got.size())


# ============================================================================
# 决策入口用例
# ============================================================================

# ----------------------------------------------------------------------------
# 用例 6: decide_shop_item + reject rule -> SKIPPED, reason 含 "reject"
# ----------------------------------------------------------------------------
func _test_6_decide_shop_with_rule_reject() -> void:
	_section("[6] decide_shop_item + reject 规则 -> SKIPPED")

	var b = Bridge.new()
	var item := _make_mock_item("mock_reject")
	b.set_item_rule("mock_reject", {"shop_action": "reject"})

	var r = b.decide_shop_item(item, 100)
	_assert(r != null, "decide_shop_item 应返回非 null")
	if r == null:
		return
	_assert(r.terminal_state == Result.STATE_SKIPPED,
		"terminal_state 应为 SKIPPED, 实得 %s" % r.terminal_state)
	_assert(r.reason.find("reject") >= 0,
		"reason 应含 'reject', 实得 '%s'" % r.reason)
	_log("  %s" % r._to_string())


# ----------------------------------------------------------------------------
# 用例 7: 没配规则的物品 -> decider 回落 manual -> STATE_MANUAL
# ----------------------------------------------------------------------------
func _test_7_decide_shop_no_rule_returns_manual() -> void:
	_section("[7] decide_shop_item 无规则 -> MANUAL")

	var b = Bridge.new()
	var item := _make_mock_item("mock_unconfigured")

	var r = b.decide_shop_item(item, 100)
	_assert(r != null, "decide_shop_item 应返回非 null")
	if r == null:
		return
	_assert(r.terminal_state == Result.STATE_MANUAL,
		"terminal_state 应为 MANUAL, 实得 %s (reason=%s)" % [r.terminal_state, r.reason])
	_log("  %s" % r._to_string())


# ----------------------------------------------------------------------------
# 用例 8: shop_automation_enabled=false 时即便配了 reject 也回 MANUAL,
#         reason 应含 "automation disabled" 或 "自动化"
# ----------------------------------------------------------------------------
func _test_8_decide_shop_disabled_returns_manual() -> void:
	_section("[8] shop_automation_enabled=false -> 总开关短路 MANUAL")

	var b = Bridge.new()
	b.set_shop_automation_enabled(false)
	b.set_item_rule("mock_d", {"shop_action": "reject"})
	var item := _make_mock_item("mock_d")

	var r = b.decide_shop_item(item, 100)
	_assert(r != null, "decide_shop_item 应返回非 null")
	if r == null:
		return
	_assert(r.terminal_state == Result.STATE_MANUAL,
		"terminal_state 应为 MANUAL, 实得 %s" % r.terminal_state)
	_assert(r.reason.find("automation disabled") >= 0 or r.reason.find("自动化") >= 0,
		"reason 应含 'automation disabled' 或 '自动化', 实得 '%s'" % r.reason)
	_log("  %s" % r._to_string())


# ----------------------------------------------------------------------------
# 用例 9: 默认 5 阈值不含 mock 物品的 stat (effects=[]),
#         configured_stats 为空集 -> 阈值不阻挡 -> PURCHASED
# ----------------------------------------------------------------------------
func _test_9_default_thresholds_no_match_passes() -> void:
	_section("[9] 默认阈值无 stat 相交 + 预算够 -> PURCHASED")

	var b = Bridge.new()
	var item := _make_mock_item("mock_e", 20, [])  # effects=[] 不参与阈值
	b.set_item_rule("mock_e", {"shop_action": "get"})

	var r = b.decide_shop_item(item, 100)
	_assert(r != null, "decide_shop_item 应返回非 null")
	if r == null:
		return
	_assert(r.terminal_state == Result.STATE_PURCHASED,
		"terminal_state 应为 PURCHASED, 实得 %s (reason=%s)" % [r.terminal_state, r.reason])
	_log("  %s" % r._to_string())


# ============================================================================
# 阈值 CRUD + 决策用例
# ============================================================================

# ----------------------------------------------------------------------------
# 用例 10: set_threshold 让 Medal 单 stat 触达 + remove 掉 Medal 其他默认阈值
#   Medal 含 max_hp / percent_damage / armor / speed / crit_chance,
#   默认阈值含 speed / armor / crit_chance / dodge / hp_regeneration.
#   交集 = {armor, speed, crit_chance}, 这三个默认 upper=20/10/100 主菜单 0 不触达.
#   为了实现"单 stat_max_hp 触达即反转", 先 remove 这三个默认阈值,
#   再 set stat_max_hp upper=0 (current=0 主菜单 0 >= 0 触达) -> 全部 configured 触达
# ----------------------------------------------------------------------------
func _test_10_threshold_override_blocks() -> void:
	_section("[10] set_threshold + Medal 单 stat 触达 -> SKIPPED")

	var medal_res = load(MEDAL_DATA_TRES)
	if medal_res == null:
		_warn_case("无法 load %s, 跳过本用例" % MEDAL_DATA_TRES)
		return

	var b = Bridge.new()
	# 把 Medal 涉及的默认阈值清掉, 留 stat_max_hp 单独触达
	b.remove_threshold("stat_armor")
	b.remove_threshold("stat_speed")
	b.remove_threshold("stat_crit_chance")
	# stat_dodge / stat_hp_regeneration 不在 Medal 涉及的 stat 内, 留着无影响
	b.set_threshold("stat_max_hp", "upper", 0)

	b.set_item_rule("item_medal", {"shop_action": "get"})
	var r = b.decide_shop_item(medal_res, 1000)
	_assert(r != null, "decide_shop_item 应返回非 null")
	if r == null:
		return
	_assert(r.terminal_state == Result.STATE_SKIPPED,
		"terminal_state 应为 SKIPPED, 实得 %s (reason=%s)" %
			[r.terminal_state, r.reason])
	_assert(r.reason.find("阈值") >= 0,
		"reason 应含 '阈值', 实得 '%s'" % r.reason)
	_log("  %s" % r._to_string())


# ----------------------------------------------------------------------------
# 用例 11: set_threshold("stat_armor", "unlimited", 999) 后 mode/value 保留
# ----------------------------------------------------------------------------
func _test_11_threshold_unlimited_value_preserved() -> void:
	_section("[11] unlimited 模式 + value 字段保留")

	var b = Bridge.new()
	b.set_threshold("stat_armor", "unlimited", 999)
	var t: Dictionary = b.get_threshold("stat_armor")
	_log("  t=%s" % str(t))

	_assert(String(t.get("mode", "")) == "unlimited",
		"mode 应为 'unlimited', 实得 '%s'" % str(t.get("mode", "")))
	_assert(int(t.get("value", -1)) == 999,
		"value 应为 999, 实得 %s" % str(t.get("value", -1)))


# ----------------------------------------------------------------------------
# 用例 12: upgrade_automation_enabled=false -> decide_upgrade 短路 NO_PICK
# ----------------------------------------------------------------------------
func _test_12_decide_upgrade_disabled() -> void:
	_section("[12] upgrade_automation_enabled=false -> NO_PICK")

	var b = Bridge.new()
	b.set_upgrade_automation_enabled(false)
	var opts: Array = [
		_make_mock_upgrade(0),
		_make_mock_upgrade(1),
		_make_mock_upgrade(2),
		_make_mock_upgrade(3),
	]

	var picked: int = b.decide_upgrade(opts)
	_log("  picked=%d (期望 %d / NO_PICK)" % [picked, UpgDec.NO_PICK])
	_assert(picked == UpgDec.NO_PICK,
		"应返回 NO_PICK (%d), 实得 %d" % [UpgDec.NO_PICK, picked])


# ============================================================================
# Upgrade / General / Threshold remove 用例
# ============================================================================

# ----------------------------------------------------------------------------
# 用例 13: set_upgrade_config min_tier=2 + quality_first=true
#   选项 tier=[0, 2, 3, 1]: 过滤掉 index 0/3, 剩 index 1 (tier=2) 与 index 2 (tier=3)
#   quality_first -> tier 降序 -> index 2 (tier=3) 排前 -> 返回 2
# ----------------------------------------------------------------------------
func _test_13_decide_upgrade_min_tier() -> void:
	_section("[13] decide_upgrade min_tier + quality_first")

	var b = Bridge.new()
	b.set_upgrade_config("min_tier", 2)
	b.set_upgrade_config("quality_first", true)

	var opts: Array = [
		_make_mock_upgrade(0),
		_make_mock_upgrade(2),
		_make_mock_upgrade(3),
		_make_mock_upgrade(1),
	]

	var picked: int = b.decide_upgrade(opts)
	_log("  picked=%d (期望 2 / tier=3)" % picked)
	_assert(picked == 2,
		"应选 original_index=2 (tier=3), 实得 %d" % picked)


# ----------------------------------------------------------------------------
# 用例 14: set_general("min_gold_balance", 100) 透传到决策器,
#   gold=110, price=20 -> 110 - 20 = 90 < 100 -> SKIPPED, reason 含 "金币"
# ----------------------------------------------------------------------------
func _test_14_set_general_passthrough() -> void:
	_section("[14] set_general min_gold_balance 透传到决策器")

	var b = Bridge.new()
	b.set_general("min_gold_balance", 100)
	var item := _make_mock_item("p", 20, [])
	b.set_item_rule("p", {"shop_action": "get"})

	var r = b.decide_shop_item(item, 110)
	_assert(r != null, "decide_shop_item 应返回非 null")
	if r == null:
		return
	_assert(r.terminal_state == Result.STATE_SKIPPED,
		"terminal_state 应为 SKIPPED, 实得 %s (reason=%s)" % [r.terminal_state, r.reason])
	_assert(r.reason.find("金币") >= 0 or r.reason.find("预算") >= 0,
		"reason 应含 '金币' 或 '预算', 实得 '%s'" % r.reason)
	_log("  %s" % r._to_string())


# ----------------------------------------------------------------------------
# 用例 15: remove_threshold 后 get_threshold 返回 {}
# ----------------------------------------------------------------------------
func _test_15_remove_threshold_returns_empty() -> void:
	_section("[15] remove_threshold 后 get 返回 {}")

	var b = Bridge.new()
	b.remove_threshold("stat_armor")
	var t: Dictionary = b.get_threshold("stat_armor")
	_log("  t=%s (size=%d)" % [str(t), t.size()])

	_assert(t.size() == 0,
		"删除后 get_threshold 应返回空 dict, 实得 size=%d" % t.size())


# ============================================================================
# Mock 数据构造器
# ============================================================================

# 通用 mock ItemData dict. 与 P1 烟雾保持字段一致, 默认 effects=[] 不触阈值.
func _make_mock_item(
		my_id: String,
		value: int = 20,
		effects: Array = []
	) -> Dictionary:
	return {
		"my_id": my_id,
		"name": "MOCK_" + my_id.to_upper(),
		"tier": 1,
		"value": value,
		"max_nb": -1,
		"is_cursed": false,
		"is_lockable": true,
		"tags": [],
		"effects": effects,
	}


# 升级选项 mock dict. UpgradeData 与 ItemData 结构对齐, 这里只需 tier 真实参与排序.
func _make_mock_upgrade(tier: int, effects: Array = []) -> Dictionary:
	return {
		"my_id": "mock_upg_t%d" % tier,
		"name": "MOCK_UPGRADE",
		"tier": tier,
		"value": 0,
		"max_nb": -1,
		"is_cursed": false,
		"is_lockable": false,
		"tags": [],
		"effects": effects,
	}


# ============================================================================
# 测试辅助 (照搬 P1 风格)
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
