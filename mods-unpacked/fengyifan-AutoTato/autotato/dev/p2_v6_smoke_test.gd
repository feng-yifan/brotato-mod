extends Reference

# ============================================================================
# AutoTato — P2 v6 烟雾测试 (Bridge schema v6 新增字段)
# ============================================================================
# 触发: mod_main.gd 设置环境变量 AUTOTATO_P2_V6_SMOKE=1
# 用例总览 (10 个):
#   1. 默认 config 含 v6 新顶层 key
#   2. 默认阈值的 limit_upgrade/limit_shop/limit_chest/min_tier 默认值
#   3. weapon_rules CRUD
#   4. weapon_category_rules CRUD
#   5. weapon_config min_tier
#   6. set_threshold 保留已有 limit_* 字段
#   7. set_threshold_field 单独设置 limit 字段
#   8. set_upgrade_array stat_blacklist / stat_priority
#   9. upgrade config 默认含 stat_blacklist/stat_priority
#   10. general 新字段 auto_start_wave / keep_running
# ============================================================================

const LOG_NAME := "fengyifan-AutoTato:P2v6SmokeTest"

const Bridge = preload("res://mods-unpacked/fengyifan-AutoTato/autotato/runtime/bridge.gd")

var _pass := 0
var _fail := 0


func run() -> void:
	_log("════════ P2 v6 烟雾测试开始 ════════")

	_test_1_v6_top_level_keys()
	_test_2_threshold_defaults()
	_test_3_weapon_rules_crud()
	_test_4_weapon_category_rules_crud()
	_test_5_weapon_config_min_tier()
	_test_6_set_threshold_preserves_limits()
	_test_7_set_threshold_field()
	_test_8_set_upgrade_array()
	_test_9_upgrade_default_arrays()
	_test_10_general_new_fields()

	_log("════════ P2 v6 烟雾测试结束 ════════")
	_log("结果: %d 通过 / %d 失败" % [_pass, _fail])
	if _fail > 0:
		ModLoaderLog.error("P2 v6 有 %d 项失败" % _fail, LOG_NAME)


# ----------------------------------------------------------------------------
# 1. 默认 config 含 v6 新顶层 key
# ----------------------------------------------------------------------------
func _test_1_v6_top_level_keys() -> void:
	_section("[1] 默认 config 含 v6 新 key")

	var b = Bridge.new_pristine()
	var cfg = b.get_config()

	_assert(cfg.has("weapon_rules"), "应含 weapon_rules")
	_assert(cfg.has("weapon_category_rules"), "应含 weapon_category_rules")
	_assert(cfg.has("weapon"), "应含 weapon")

	var upg = cfg.get("upgrade", {})
	_assert(upg.has("stat_blacklist"), "upgrade 应含 stat_blacklist")
	_assert(upg.has("stat_priority"), "upgrade 应含 stat_priority")

	var gen = cfg.get("general", {})
	_assert(gen.has("auto_start_wave"), "general 应含 auto_start_wave")
	_assert(gen.has("keep_running"), "general 应含 keep_running")


# ----------------------------------------------------------------------------
# 2. 默认阈值 limit_upgrade/limit_shop/limit_chest/min_tier
# ----------------------------------------------------------------------------
func _test_2_threshold_defaults() -> void:
	_section("[2] 默认阈值 limit_* 默认值")

	var b = Bridge.new_pristine()
	var ths = b.get_thresholds()
	_assert(ths.has("stat_armor"), "应含 stat_armor")

	var t = ths["stat_armor"]
	_assert(bool(t.get("limit_upgrade", false)) == true, "limit_upgrade 默认 true, 实得 %s" % str(t.get("limit_upgrade")))
	_assert(bool(t.get("limit_shop", false)) == true, "limit_shop 默认 true, 实得 %s" % str(t.get("limit_shop")))
	_assert(bool(t.get("limit_chest", true)) == false, "limit_chest 默认 false, 实得 %s" % str(t.get("limit_chest")))
	_assert(int(t.get("min_tier", 99)) == -1, "min_tier 默认 -1, 实得 %s" % str(t.get("min_tier")))


# ----------------------------------------------------------------------------
# 3. weapon_rules CRUD
# ----------------------------------------------------------------------------
func _test_3_weapon_rules_crud() -> void:
	_section("[3] weapon_rules 读写")

	var b = Bridge.new_pristine()

	_assert(b.get_weapon_rule("weapon_test") == "follow_set_rule",
		"未配规则应返回 follow_set_rule, 实得 %s" % b.get_weapon_rule("weapon_test"))

	b.set_weapon_rule("weapon_test", "manual")
	_assert(b.get_weapon_rule("weapon_test") == "manual",
		"set manual 后应为 manual, 实得 %s" % b.get_weapon_rule("weapon_test"))

	b.set_weapon_rule("weapon_test", "skip")
	_assert(b.get_weapon_rule("weapon_test") == "skip",
		"set skip 后应为 skip, 实得 %s" % b.get_weapon_rule("weapon_test"))

	b.remove_weapon_rule("weapon_test")
	_assert(b.get_weapon_rule("weapon_test") == "follow_set_rule",
		"remove 后应恢复 follow_set_rule, 实得 %s" % b.get_weapon_rule("weapon_test"))


# ----------------------------------------------------------------------------
# 4. weapon_category_rules CRUD
# ----------------------------------------------------------------------------
func _test_4_weapon_category_rules_crud() -> void:
	_section("[4] weapon_category_rules 读写")

	var b = Bridge.new_pristine()

	_assert(b.get_weapon_category_rule("unarmed") == "manual",
		"未配类别规则应返回 manual, 实得 %s" % b.get_weapon_category_rule("unarmed"))

	b.set_weapon_category_rule("unarmed", "skip")
	_assert(b.get_weapon_category_rule("unarmed") == "skip",
		"set skip 后应为 skip, 实得 %s" % b.get_weapon_category_rule("unarmed"))


# ----------------------------------------------------------------------------
# 5. weapon_config min_tier
# ----------------------------------------------------------------------------
func _test_5_weapon_config_min_tier() -> void:
	_section("[5] weapon.min_tier 默认值 + 读写")

	var b = Bridge.new_pristine()

	_assert(b.get_weapon_min_tier() == 1,
		"weapon.min_tier 默认应为 1, 实得 %d" % b.get_weapon_min_tier())

	b.set_weapon_config("min_tier", 3)
	_assert(b.get_weapon_min_tier() == 3,
		"set min_tier=3 后应为 3, 实得 %d" % b.get_weapon_min_tier())


# ----------------------------------------------------------------------------
# 6. set_threshold 保留已有 limit_* 字段
# ----------------------------------------------------------------------------
func _test_6_set_threshold_preserves_limits() -> void:
	_section("[6] set_threshold 不覆盖 limit_* 字段")

	var b = Bridge.new_pristine()

	b.set_threshold_field("stat_armor", "limit_shop", false)
	var t1 = b.get_threshold("stat_armor")
	_assert(bool(t1.get("limit_shop", true)) == false,
		"limit_shop 应为 false, 实得 %s" % str(t1.get("limit_shop")))

	# set_threshold 只改 mode+value, 不应重置 limit_*
	b.set_threshold("stat_armor", "lower", 5)
	var t2 = b.get_threshold("stat_armor")
	_assert(t2["mode"] == "lower", "mode 应为 lower, 实得 %s" % t2["mode"])
	_assert(int(t2["value"]) == 5, "value 应为 5, 实得 %s" % str(t2["value"]))
	_assert(bool(t2.get("limit_shop", true)) == false,
		"limit_shop 仍应为 false (未被 set_threshold 覆盖), 实得 %s" % str(t2.get("limit_shop")))
	_assert(bool(t2.get("limit_upgrade", false)) == true,
		"limit_upgrade 仍应为 true, 实得 %s" % str(t2.get("limit_upgrade")))


# ----------------------------------------------------------------------------
# 7. set_threshold_field 单独设置字段
# ----------------------------------------------------------------------------
func _test_7_set_threshold_field() -> void:
	_section("[7] set_threshold_field 单独字段")

	var b = Bridge.new_pristine()

	b.set_threshold_field("stat_speed", "limit_chest", true)
	b.set_threshold_field("stat_speed", "min_tier", 2)

	var t = b.get_threshold("stat_speed")
	_assert(bool(t.get("limit_chest", false)) == true, "limit_chest 应为 true, 实得 %s" % str(t.get("limit_chest")))
	_assert(int(t.get("min_tier", -1)) == 2, "min_tier 应为 2, 实得 %s" % str(t.get("min_tier")))
	_assert(t["mode"] == "upper", "mode 应保留 upper, 实得 %s" % t["mode"])


# ----------------------------------------------------------------------------
# 8. set_upgrade_array stat_blacklist / stat_priority
# ----------------------------------------------------------------------------
func _test_8_set_upgrade_array() -> void:
	_section("[8] set_upgrade_array 批量写入数组")

	var b = Bridge.new_pristine()

	var bl = ["stat_range", "stat_luck"]
	b.set_upgrade_array("stat_blacklist", bl)
	var cfg = b.get_upgrade_config()
	var bl2 = cfg.get("stat_blacklist", [])
	_assert(bl2.size() == 2, "stat_blacklist size 应为 2, 实得 %d" % bl2.size())
	_assert(bl2.has("stat_range"), "应含 stat_range")

	var pri = ["stat_damage", "stat_attack_speed", "stat_melee_damage"]
	b.set_upgrade_array("stat_priority", pri)
	var cfg2 = b.get_upgrade_config()
	var pri2 = cfg2.get("stat_priority", [])
	_assert(pri2.size() == 3, "stat_priority size 应为 3, 实得 %d" % pri2.size())
	_assert(pri2[0] == "stat_damage", "priority[0] 应为 stat_damage, 实得 %s" % pri2[0])


# ----------------------------------------------------------------------------
# 9. upgrade config 默认含空数组
# ----------------------------------------------------------------------------
func _test_9_upgrade_default_arrays() -> void:
	_section("[9] upgrade.stat_blacklist 默认空数组")

	var b = Bridge.new_pristine()
	var cfg = b.get_upgrade_config()
	var bl = cfg.get("stat_blacklist", [])
	var pri = cfg.get("stat_priority", [])
	_assert(typeof(bl) == TYPE_ARRAY and bl.size() == 0, "stat_blacklist 默认应为 [ ], 实得 %s" % str(bl))
	_assert(typeof(pri) == TYPE_ARRAY and pri.size() == 0, "stat_priority 默认应为 [ ], 实得 %s" % str(pri))


# ----------------------------------------------------------------------------
# 10. general 新字段
# ----------------------------------------------------------------------------
func _test_10_general_new_fields() -> void:
	_section("[10] general auto_start_wave / keep_running")

	var b = Bridge.new_pristine()
	var g = b.get_general()

	_assert(bool(g.get("auto_start_wave", true)) == false, "auto_start_wave 默认 false")
	_assert(bool(g.get("keep_running", true)) == false, "keep_running 默认 false")

	b.set_general("auto_start_wave", true)
	b.set_general("keep_running", true)
	var g2 = b.get_general()
	_assert(bool(g2.get("auto_start_wave", false)) == true, "set 后 auto_start_wave 应为 true")
	_assert(bool(g2.get("keep_running", false)) == true, "set 后 keep_running 应为 true")


# ============================================================================
# 辅助
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


func _log(msg: String) -> void:
	if typeof(ModLoaderLog) != TYPE_NIL:
		ModLoaderLog.info(msg, LOG_NAME)
