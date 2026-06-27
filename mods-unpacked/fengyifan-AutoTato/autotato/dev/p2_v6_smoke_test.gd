extends Reference

# ============================================================================
# AutoTato — P2 v7 烟雾测试 (v7 schema)
# ============================================================================
# 用例总览 (10 个):
#   1. 默认 config 不含 v6.1 旧字段 (upgrade_action/shop_action/chest_action)
#   2. 默认阈值的条目只含 mode + value
#   3. weapon_rules CRUD
#   4. weapon_category_rules CRUD
#   5. weapon_config min_tier
#   6. set_threshold 只写 mode + value
#   7. forbid_stats 读写
#   8. set_upgrade_priority 批量写入
#   9. upgrade 默认值 (forbid_stats=[], respect_thresholds=true)
#   10. general 新字段 (shop_respect_thresholds, chest_respect_thresholds)
# ============================================================================

const LOG_NAME := "fengyifan-AutoTato:P2v7SmokeTest"
const Bridge = preload("res://mods-unpacked/fengyifan-AutoTato/autotato/runtime/bridge.gd")

var _pass := 0
var _fail := 0


func run() -> void:
	_log("════════ P2 v7 烟雾测试开始 ════════")
	_test_1_v7_no_old_fields()
	_test_2_thresholds_mode_value_only()
	_test_3_weapon_rules()
	_test_4_weapon_cat_rules()
	_test_5_weapon_min_tier()
	_test_6_set_threshold()
	_test_7_forbid_stats()
	_test_8_upgrade_priority()
	_test_9_upgrade_default()
	_test_10_general()
	_log("════════ P2 v7 烟雾测试结束 ════════")
	_log("结果: %d 通过 / %d 失败" % [_pass, _fail])
	if _fail > 0:
		ModLoaderLog.error("P2 v7 有 %d 项失败" % _fail, LOG_NAME)


func _test_1_v7_no_old_fields() -> void:
	_section("[1] 默认 config 不含 v6.1 旧字段")
	var b = Bridge.new_pristine()
	var cfg = b.get_config()

	var upg = cfg.get("upgrade", {})
	_assert(not upg.has("stat_blacklist"), "不应含旧字段 stat_blacklist")
	_assert(not upg.has("ignore_blacklist_on_stuck"), "不应含旧字段 ignore_blacklist_on_stuck")

	var ths = cfg.get("thresholds", {})
	var t = ths.get("stat_armor", {})
	_assert(not t.has("upgrade_action"), "不应含旧字段 upgrade_action")
	_assert(not t.has("shop_action"), "不应含旧字段 shop_action")
	_assert(not t.has("chest_action"), "不应含旧字段 chest_action")
	_assert(not t.has("min_tier"), "不应含旧字段 min_tier")
	_assert(not t.has("limit_upgrade"), "不应含旧字段 limit_upgrade")
	_assert(not t.has("limit_shop"), "不应含旧字段 limit_shop")
	_assert(not t.has("limit_chest"), "不应含旧字段 limit_chest")


func _test_2_thresholds_mode_value_only() -> void:
	_section("[2] 默认阈值条目只含 mode + value")
	var b = Bridge.new_pristine()
	var ths = b.get_thresholds()
	var t = ths["stat_armor"]
	var keys = t.keys()
	_assert(keys.size() == 2, "阈值条目应有 2 个字段, 实得 %d: %s" % [keys.size(), str(keys)])
	_assert(t.get("mode") == "upper", "mode 应为 upper, 实得 %s" % t.get("mode"))
	_assert(t.get("value") == 10, "value 应为 10, 实得 %d" % int(t.get("value")))


func _test_3_weapon_rules() -> void:
	_section("[3] weapon_rules 读写")
	var b = Bridge.new_pristine()
	_assert(b.get_weapon_rule("w") == "follow_set_rule", "未配→follow_set_rule")
	b.set_weapon_rule("w", "manual")
	_assert(b.get_weapon_rule("w") == "manual", "set→manual")
	b.remove_weapon_rule("w")
	_assert(b.get_weapon_rule("w") == "follow_set_rule", "remove→follow_set_rule")


func _test_4_weapon_cat_rules() -> void:
	_section("[4] weapon_category_rules 读写")
	var b = Bridge.new_pristine()
	_assert(b.get_weapon_category_rule("u") == "manual", "未配→manual")
	b.set_weapon_category_rule("u", "skip")
	_assert(b.get_weapon_category_rule("u") == "skip", "set→skip")


func _test_5_weapon_min_tier() -> void:
	_section("[5] weapon.min_tier")
	var b = Bridge.new_pristine()
	_assert(b.get_weapon_min_tier() == 1, "默认 1")
	b.set_weapon_config("min_tier", 3)
	_assert(b.get_weapon_min_tier() == 3, "set→3")


func _test_6_set_threshold() -> void:
	_section("[6] set_threshold 只写 mode + value")
	var b = Bridge.new_pristine()
	b.set_threshold("stat_armor", "lower", 5)
	var t = b.get_threshold("stat_armor")
	_assert(t["mode"] == "lower", "mode→lower")
	_assert(t["value"] == 5, "value→5")
	_assert(t.keys().size() == 2, "阈值条目应只有 2 个字段, 实得 %d" % t.keys().size())


func _test_7_forbid_stats() -> void:
	_section("[7] forbid_stats 读写")
	var b = Bridge.new_pristine()
	var fb = b.get_upgrade_forbid_stats()
	_assert(fb.size() == 0, "forbid_stats 默认空, 实得 %d" % fb.size())

	b.set_upgrade_forbid_stats(["stat_luck", "stat_harvesting"])
	var fb2 = b.get_upgrade_forbid_stats()
	_assert(fb2.size() == 2, "size=2 实得 %d" % fb2.size())
	_assert(fb2.has("stat_luck"), "应含 stat_luck")
	_assert(fb2.has("stat_harvesting"), "应含 stat_harvesting")


func _test_8_upgrade_priority() -> void:
	_section("[8] set_upgrade_priority")
	var b = Bridge.new_pristine()
	b.set_upgrade_priority(["stat_damage", "stat_attack_speed"])
	var pri = b.get_upgrade_config().get("stat_priority", [])
	_assert(pri.size() == 2, "size=2 实得 %d" % pri.size())
	_assert(pri[0] == "stat_damage", "pri[0]=damage 实得 %s" % pri[0])


func _test_9_upgrade_default() -> void:
	_section("[9] upgrade 默认值")
	var b = Bridge.new_pristine()
	var cfg = b.get_upgrade_config()
	_assert(bool(cfg.get("respect_thresholds", false)) == true, "respect_thresholds 默认 true")
	_assert(bool(cfg.get("ignore_forbid_on_stuck", false)) == true, "ignore_forbid_on_stuck 默认 true")

	var fb = b.get_upgrade_forbid_stats()
	_assert(typeof(fb) == TYPE_ARRAY and fb.size() == 0, "forbid_stats 默认 []")

	var pri = cfg.get("stat_priority", [])
	_assert(typeof(pri) == TYPE_ARRAY and pri.size() == 0, "stat_priority 默认 []")


func _test_10_general() -> void:
	_section("[10] general 阈值开关字段")
	var b = Bridge.new_pristine()
	var g = b.get_general()
	_assert(bool(g.get("shop_respect_thresholds", false)) == true, "shop_respect_thresholds 默认 true")
	_assert(bool(g.get("chest_respect_thresholds", true)) == false, "chest_respect_thresholds 默认 false")

	b.set_general("shop_respect_thresholds", false)
	_assert(bool(b.get_general().get("shop_respect_thresholds", true)) == false, "set→false")

	b.set_general("chest_respect_thresholds", true)
	_assert(bool(b.get_general().get("chest_respect_thresholds", false)) == true, "set→true")


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
