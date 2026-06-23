extends Reference

# ============================================================================
# AutoTato — P0 烟雾测试
# ============================================================================
#
# 目的：验证 P0 数据层（effect_schema / effect_parser / effect_keys /
#       item_data_util / weapon_data_util / danger_modifier）能正确解析
#       vanilla Brotato 1.1.15.4 的真实资源。本脚本只读，不改任何状态。
#
# 触发：默认关闭。开发期通过下面任一方式启用：
#   1. 编辑 mod_main.gd 把 DEV_RUN_SMOKE_TEST 改 true
#   2. 用环境变量启动：AUTOTATO_SMOKE=1 ./Brotato.x86_64
# 启用后游戏启动会自动跑 run()，结果写到 godot.log。
#
# 验收的 7 条标准（与 P0 规划文档对应）：
#   ✅1. Anvil (KEY_VALUE) 正确解析为 stat_armor@upgrade_random_weapon
#   ✅2. stat_damage 与 stat_percent_damage 在 effect_keys 中单位不同
#   ✅3. EffectInfo.is_replace() 与 is_stat_modifier() 区分正确
#   ✅4. effect_keys 字典体量合理 (16+ stat / 大量 misc)
#   ✅5. ItemDataUtil Resource 与 Dictionary 双形态返回值一致
#   ✅6. DangerModifier 在 D5 给 armor 高权重、给 damage 低权重
#   ✅7. mod 加载不报错（启动到主菜单这条本身已通过）
# ============================================================================

const LOG_NAME := "fengyifan-AutoTato:SmokeTest"

const Schema = preload("res://mods-unpacked/fengyifan-AutoTato/autotato/data/effect_schema.gd")
const Parser = preload("res://mods-unpacked/fengyifan-AutoTato/autotato/data/effect_parser.gd")
const EKeys  = preload("res://mods-unpacked/fengyifan-AutoTato/autotato/data/effect_keys.gd")
const ItemU  = preload("res://mods-unpacked/fengyifan-AutoTato/autotato/data/item_data_util.gd")
const WpnU   = preload("res://mods-unpacked/fengyifan-AutoTato/autotato/data/weapon_data_util.gd")
const DangerU = preload("res://mods-unpacked/fengyifan-AutoTato/autotato/data/danger_modifier.gd")

# Anvil 的 effect 资源（vanilla 1.1.15.4）
const ANVIL_EFFECT_TRES := "res://items/all/anvil/anvil_effect_0.tres"
const ANVIL_DATA_TRES := "res://items/all/anvil/anvil_data.tres"

# 计数：通过/失败/警告
var _pass := 0
var _fail := 0
var _warn := 0


# ----------------------------------------------------------------------------
# 入口
# ----------------------------------------------------------------------------
func run() -> void:
	_log("════════ P0 烟雾测试开始 ════════")

	_test_1_anvil_parse()
	_test_2_damage_units_distinct()
	_test_3_effect_info_helpers()
	_test_4_keys_dict_size()
	_test_5_item_util_dual_form()
	_test_6_danger_weight()

	_log("════════ P0 烟雾测试结束 ════════")
	_log("结果: %d 通过 / %d 失败 / %d 警告" % [_pass, _fail, _warn])
	if _fail > 0:
		ModLoaderLog.error("P0 数据层有 %d 项失败，请检查上方日志" % _fail, LOG_NAME)


# ----------------------------------------------------------------------------
# 用例 1：Anvil (KEY_VALUE) 正确解析
# ----------------------------------------------------------------------------
# 期望：parser 把 vanilla anvil_effect_0.tres 解出来后，
#   stat_key      == "stat_armor"
#   custom_key    == "upgrade_random_weapon"
#   value         == 2
#   storage_method == SM_KEY_VALUE (1)
#   effect_sign   == SIGN_FROM_VALUE (3)
#   signature     == "stat_armor@upgrade_random_weapon"
#   is_key_value() == true
#   is_stat_modifier() == false  (KEY_VALUE 不是普通 stat 加成)
func _test_1_anvil_parse() -> void:
	_section("[1] Anvil KEY_VALUE 解析")

	var effect_res = load(ANVIL_EFFECT_TRES)
	if effect_res == null:
		_fail_case("无法 load %s（Brotato 1.1.15.4 是否完整？）" % ANVIL_EFFECT_TRES)
		return

	var infos: Array = Parser.parse(effect_res)
	_assert(infos.size() == 1, "应解出 1 条 EffectInfo, 实得 %d" % infos.size())
	if infos.size() == 0:
		return

	var info = infos[0]
	_assert(info.stat_key == "stat_armor", "stat_key 应为 stat_armor, 实得 %s" % info.stat_key)
	_assert(info.custom_key == "upgrade_random_weapon", "custom_key 应为 upgrade_random_weapon, 实得 %s" % info.custom_key)
	_assert(info.value == 2, "value 应为 2, 实得 %d" % info.value)
	_assert(info.storage_method == Schema.SM_KEY_VALUE, "storage_method 应为 SM_KEY_VALUE(1), 实得 %d" % info.storage_method)
	_assert(info.effect_sign == Schema.SIGN_FROM_VALUE, "effect_sign 应为 SIGN_FROM_VALUE(3), 实得 %d" % info.effect_sign)
	_assert(info.signature == "stat_armor@upgrade_random_weapon", "signature 应为 stat_armor@upgrade_random_weapon, 实得 %s" % info.signature)
	_assert(info.is_key_value(), "is_key_value() 应为 true")
	_assert(not info.is_stat_modifier(), "is_stat_modifier() 应为 false（KEY_VALUE 不是普通 stat 修饰）")
	_log("  Anvil 解析样本: %s" % info._to_string())


# ----------------------------------------------------------------------------
# 用例 2：stat_damage 与 stat_percent_damage 单位区分
# ----------------------------------------------------------------------------
# 旧 mod 把这两个混为一谈，导致 % 与 flat 错算
func _test_2_damage_units_distinct() -> void:
	_section("[2] stat_damage vs stat_percent_damage 单位区分")

	_assert(EKeys.is_known_stat("stat_damage"), "stat_damage 应该在 STAT_TAGS 中")
	_assert(EKeys.is_known_stat("stat_percent_damage"), "stat_percent_damage 应该在 STAT_TAGS 中")

	var unit_flat := EKeys.get_unit("stat_damage")
	var unit_pct := EKeys.get_unit("stat_percent_damage")
	_log("  stat_damage 单位 = '%s'" % unit_flat)
	_log("  stat_percent_damage 单位 = '%s'" % unit_pct)
	_assert(unit_flat == EKeys.UNIT_FLAT, "stat_damage 应为 flat, 实得 %s" % unit_flat)
	_assert(unit_pct == EKeys.UNIT_PERCENT, "stat_percent_damage 应为 percent, 实得 %s" % unit_pct)


# ----------------------------------------------------------------------------
# 用例 3：EffectInfo 查询 helper 正确性
# ----------------------------------------------------------------------------
# 手工构造 3 种 EffectInfo (SUM/KEY_VALUE/REPLACE), 验证 helper 分类正确
func _test_3_effect_info_helpers() -> void:
	_section("[3] EffectInfo helpers 分类")

	var sum_info = Schema.make("stat_max_hp", "", 8, Schema.SM_SUM, Schema.SIGN_FROM_VALUE, [])
	_assert(sum_info.is_stat_modifier(), "SUM + stat_max_hp 应为 stat_modifier")
	_assert(not sum_info.is_replace(), "SUM 不是 replace")
	_assert(not sum_info.is_key_value(), "SUM 不是 key_value")
	_assert(sum_info.signature == "stat_max_hp", "SUM signature 应等于 stat_key")

	var rep_info = Schema.make("nb_of_waves", "", 20, Schema.SM_REPLACE, Schema.SIGN_NEUTRAL, [])
	_assert(rep_info.is_replace(), "REPLACE 类型判定")
	_assert(not rep_info.is_stat_modifier(), "REPLACE 不算 stat_modifier")
	_assert(rep_info.signature == "nb_of_waves", "REPLACE signature 应等于 stat_key")

	var kv_info = Schema.make("stat_armor", "upgrade_random_weapon", 2, Schema.SM_KEY_VALUE, Schema.SIGN_FROM_VALUE, [])
	_assert(kv_info.is_key_value(), "KEY_VALUE 类型判定")
	_assert(not kv_info.is_stat_modifier(), "KEY_VALUE 不算 stat_modifier")
	_assert(kv_info.signature == "stat_armor@upgrade_random_weapon", "KEY_VALUE signature 形如 key@bucket")


# ----------------------------------------------------------------------------
# 用例 4：effect_keys 字典体量
# ----------------------------------------------------------------------------
# STAT_TAGS 至少 16 条（vanilla 16 个 primary stat）+ stat_curse
# MISC_TAGS 至少 50 条（gain_stat_* 16 + 武器/商店/触发 大量）
func _test_4_keys_dict_size() -> void:
	_section("[4] effect_keys 体量")

	var stats_count := EKeys.STAT_TAGS.size()
	var misc_count := EKeys.MISC_TAGS.size()
	_log("  STAT_TAGS = %d 条" % stats_count)
	_log("  MISC_TAGS = %d 条" % misc_count)

	_assert(stats_count >= 16, "STAT_TAGS 应至少 16 条, 实得 %d" % stats_count)
	_assert(misc_count >= 50, "MISC_TAGS 应至少 50 条, 实得 %d" % misc_count)

	# stat_curse 是唯一 positive_is_good=false 的 stat
	_assert(not EKeys.is_positive_good("stat_curse"), "stat_curse 应为 positive_is_good=false")


# ----------------------------------------------------------------------------
# 用例 5：ItemDataUtil 双形态一致性
# ----------------------------------------------------------------------------
# 同样的 Anvil, Resource 形态 与 Dictionary 形态 调 util 应给一致结果
func _test_5_item_util_dual_form() -> void:
	_section("[5] ItemDataUtil 双形态")

	var anvil_res = load(ANVIL_DATA_TRES)
	if anvil_res == null:
		_warn_case("无法 load %s, 跳过本用例" % ANVIL_DATA_TRES)
		return

	var anvil_dict := {
		"my_id": "item_anvil",
		"name": "ITEM_ANVIL",
		"tier": 3,
		"value": 120,
		"max_nb": 1,
		"tags": [],
		"is_lockable": true,
		"is_cursed": false,
		"effects": [],
	}

	_assert(ItemU.get_id(anvil_res) == "item_anvil", "Resource.my_id == item_anvil")
	_assert(ItemU.get_id(anvil_dict) == "item_anvil", "Dict.my_id == item_anvil")
	_assert(ItemU.get_tier(anvil_res) == 3, "Resource.tier == 3")
	_assert(ItemU.get_tier(anvil_dict) == 3, "Dict.tier == 3")
	_assert(ItemU.get_base_value(anvil_res) == 120, "Resource.value == 120")
	_assert(ItemU.get_base_value(anvil_dict) == 120, "Dict.value == 120")
	_assert(ItemU.get_max_amount(anvil_res) == 1, "Resource.max_nb == 1")
	_assert(ItemU.get_max_amount(anvil_dict) == 1, "Dict.max_nb == 1")
	_log("  Anvil 双形态 id/tier/value/max_nb 一致 ✓")


# ----------------------------------------------------------------------------
# 用例 6：DangerModifier 权重曲线
# ----------------------------------------------------------------------------
# Danger 5 时 armor (防御) 权重 > 1, damage (进攻) 权重 < 1
func _test_6_danger_weight() -> void:
	_section("[6] DangerModifier 权重曲线")

	var armor_d0 := DangerU.get_stat_weight_multiplier("stat_armor", 0)
	var armor_d5 := DangerU.get_stat_weight_multiplier("stat_armor", 5)
	var dmg_d0   := DangerU.get_stat_weight_multiplier("stat_damage", 0)
	var dmg_d5   := DangerU.get_stat_weight_multiplier("stat_damage", 5)
	var luck_d5  := DangerU.get_stat_weight_multiplier("stat_luck", 5)

	_log("  stat_armor   D0=%.2f D5=%.2f" % [armor_d0, armor_d5])
	_log("  stat_damage  D0=%.2f D5=%.2f" % [dmg_d0, dmg_d5])
	_log("  stat_luck    D5=%.2f (中性应为 1.0)" % luck_d5)

	_assert(abs(armor_d0 - 1.0) < 0.001, "D0 armor 应 ≈ 1.0")
	_assert(armor_d5 > 1.0, "D5 armor 应 > 1.0（防御类抬权重）")
	_assert(dmg_d5 < 1.0, "D5 damage 应 < 1.0（进攻类降权重）")
	_assert(abs(luck_d5 - 1.0) < 0.001, "D5 luck 应 ≈ 1.0（中性不调）")

	_assert(DangerU.is_defensive("stat_armor"), "stat_armor 应为防御类")
	_assert(DangerU.is_offensive("stat_damage"), "stat_damage 应为进攻类")
	_assert(not DangerU.is_defensive("stat_luck"), "stat_luck 不是防御类")
	_assert(not DangerU.is_offensive("stat_luck"), "stat_luck 不是进攻类")


# ----------------------------------------------------------------------------
# 辅助函数
# ----------------------------------------------------------------------------
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
