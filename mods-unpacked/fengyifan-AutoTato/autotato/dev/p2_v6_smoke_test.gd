extends Reference

# ============================================================================
# AutoTato — P2 v6.1 烟雾测试 (阈值 *_action 字段)
# ============================================================================
# 用例总览 (10 个):
#   1. 默认 config 不含旧 stat_blacklist 字段
#   2. 默认阈值的 upgrade_action/shop_action/chest_action
#   3. weapon_rules CRUD
#   4. weapon_category_rules CRUD
#   5. weapon_config min_tier
#   6. set_threshold 保留已有 *_action 字段
#   7. set_threshold_field upgrade_action/shop_action/chest_action
#   8. set_upgrade_priority 批量写入
#   9. upgrade.stat_priority 默认空数组
#   10. general 新字段
# ============================================================================

const LOG_NAME := "fengyifan-AutoTato:P2v6SmokeTest"
const Bridge = preload("res://mods-unpacked/fengyifan-AutoTato/autotato/runtime/bridge.gd")

var _pass := 0
var _fail := 0


func run() -> void:
	_log("════════ P2 v6.1 烟雾测试开始 ════════")
	_test_1_v6_no_old_fields()
	_test_2_threshold_actions()
	_test_3_weapon_rules()
	_test_4_weapon_cat_rules()
	_test_5_weapon_min_tier()
	_test_6_set_threshold_preserves()
	_test_7_set_threshold_field()
	_test_8_upgrade_priority()
	_test_9_upgrade_default()
	_test_10_general()
	_log("════════ P2 v6.1 烟雾测试结束 ════════")
	_log("结果: %d 通过 / %d 失败" % [_pass, _fail])
	if _fail > 0:
		ModLoaderLog.error("P2 v6.1 有 %d 项失败" % _fail, LOG_NAME)


func _test_1_v6_no_old_fields() -> void:
	_section("[1] 默认 config 不含 v6 旧字段")
	var b = Bridge.new_pristine()
	var cfg = b.get_config()

	var upg = cfg.get("upgrade", {})
	_assert(not upg.has("stat_blacklist"), "不应含旧字段 stat_blacklist")

	var ths = cfg.get("thresholds", {})
	var t = ths.get("stat_armor", {})
	_assert(not t.has("limit_upgrade"), "不应含旧字段 limit_upgrade")
	_assert(not t.has("limit_shop"), "不应含旧字段 limit_shop")
	_assert(not t.has("limit_chest"), "不应含旧字段 limit_chest")


func _test_2_threshold_actions() -> void:
	_section("[2] 默认阈值 *_action 默认值")
	var b = Bridge.new_pristine()
	var ths = b.get_thresholds()
	var t = ths["stat_armor"]
	_assert(t.get("upgrade_action") == "limit", "upgrade_action 默认 limit, 实得 %s" % t.get("upgrade_action"))
	_assert(t.get("shop_action") == "limit", "shop_action 默认 limit, 实得 %s" % t.get("shop_action"))
	_assert(t.get("chest_action") == "none", "chest_action 默认 none, 实得 %s" % t.get("chest_action"))


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


func _test_6_set_threshold_preserves() -> void:
	_section("[6] set_threshold 保留 *_action")
	var b = Bridge.new_pristine()
	b.set_threshold_field("stat_armor", "shop_action", "none")
	var t1 = b.get_threshold("stat_armor")
	_assert(t1.get("shop_action") == "none", "shop_action→none")
	b.set_threshold("stat_armor", "lower", 5)
	var t2 = b.get_threshold("stat_armor")
	_assert(t2["mode"] == "lower", "mode→lower")
	_assert(t2.get("shop_action") == "none", "shop_action 保留 none")
	_assert(t2.get("upgrade_action") == "limit", "upgrade_action 保留 limit")


func _test_7_set_threshold_field() -> void:
	_section("[7] set_threshold_field *_action")
	var b = Bridge.new_pristine()
	b.set_threshold_field("stat_speed", "chest_action", "limit")
	b.set_threshold_field("stat_speed", "upgrade_action", "forbid")
	var t = b.get_threshold("stat_speed")
	_assert(t.get("chest_action") == "limit", "chest_action→limit")
	_assert(t.get("upgrade_action") == "forbid", "upgrade_action→forbid")


func _test_8_upgrade_priority() -> void:
	_section("[8] set_upgrade_priority")
	var b = Bridge.new_pristine()
	b.set_upgrade_priority(["stat_damage", "stat_attack_speed"])
	var pri = b.get_upgrade_config().get("stat_priority", [])
	_assert(pri.size() == 2, "size=2 实得 %d" % pri.size())
	_assert(pri[0] == "stat_damage", "pri[0]=damage 实得 %s" % pri[0])


func _test_9_upgrade_default() -> void:
	_section("[9] upgrade 默认")
	var b = Bridge.new_pristine()
	var cfg = b.get_upgrade_config()
	var pri = cfg.get("stat_priority", [])
	_assert(typeof(pri) == TYPE_ARRAY and pri.size() == 0, "stat_priority 默认 []")


func _test_10_general() -> void:
	_section("[10] general 新字段")
	var b = Bridge.new_pristine()
	var g = b.get_general()
	_assert(bool(g.get("auto_start_wave", true)) == false, "auto_start_wave 默认 false")
	_assert(bool(g.get("keep_running", true)) == false, "keep_running 默认 false")
	b.set_general("auto_start_wave", true)
	_assert(bool(b.get_general().get("auto_start_wave", false)) == true, "set→true")


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
