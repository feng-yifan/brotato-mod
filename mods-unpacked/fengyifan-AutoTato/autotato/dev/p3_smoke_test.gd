extends Reference

# ============================================================================
# AutoTato — P3 烟雾测试 (商店 hook)
# ============================================================================
#
# 目的: 验证 P3 把 vanilla base_shop hook 接入 AutoTato 决策器后的核心逻辑.
#       主要面向 Bridge.process_shop 的纯函数行为与容错矩阵.
#
# 为什么不能开真商店:
#   hook 本身 (apply_decision 写回 vanilla _shop_items / 改 ShopItem 节点状态)
#   依赖运行时真实 ShopItem 节点树 + RunData + ItemService, P3 烟雾在主菜单
#   即触发, 无法构造这些上下文, 因此 hook 副作用部分留人手开局回归验证.
#   烟雾的可验证范围 = Bridge.process_shop (纯函数) + 容错矩阵.
#
# 与 P0 / P1 / P2 烟雾独立:
#   - P0 测 schema 层 (Effect / Keys / Util)
#   - P1 测决策器层 (static 纯函数)
#   - P2 测 Bridge config / CRUD / 三个 decide_* 入口
#   - P3 测 Bridge.process_shop 整商店决策 + 容错
#
# 触发: 默认关闭. mod_main 把 DEV_RUN_P3_SMOKE 改 true 即可在游戏启动时自动
#       .new() 出实例并调 run(), 结果写到 godot.log. 亦可通过环境变量
#       AUTOTATO_P3_SMOKE 在 mod_main 中读取触发.
#
# 用例总览 (10 个):
#   1.  Bridge 已注册到 Engine meta
#   2.  Bridge.get_global() 非 null
#   3.  Bridge 含 process_shop 方法
#   4.  null base_shop -> 返回 []
#   5.  base_shop 无 _shop_items -> 返回 []
#   6.  mock 4 slot 无规则 -> 全 manual (decider 回落)
#   7.  mock 4 slot reject 规则 -> 全 SKIPPED, reason 含 "reject"
#   8.  gold=0 主菜单环境 全配 get -> 全 SKIPPED (金币不足)
#   9.  lockable + lock_until_cursed 规则 -> LOCKED
#   10. 多 slot 的 slot_index 保留顺序
#
# 用例间状态隔离: 每个 _test_* 内独立 Bridge.new_pristine() (Reference 引用计数自动释放).
# 用例 1/2 的"全局注册"维度走 Bridge.get_global(), 其余全部 Bridge.new_pristine(),
# 防止污染或依赖 mod_main 的注册时序.
# ============================================================================


const LOG_NAME := "fengyifan-AutoTato:P3SmokeTest"

const Bridge = preload("res://mods-unpacked/fengyifan-AutoTato/autotato/runtime/bridge.gd")
const Result = preload("res://mods-unpacked/fengyifan-AutoTato/autotato/decisions/decision_result.gd")


# 计数: 通过 / 失败 / 警告
var _pass := 0
var _fail := 0
var _warn := 0


# ============================================================================
# Mock 类
# ----------------------------------------------------------------------------
# Godot 3 的纯 Reference.new() 不能动态加任意 var, 必须通过内部类继承的方式
# 显式声明 _shop_items 字段. Bridge.process_shop 内部用 base_shop.get(
# "_shop_items") 取字段, 走 Godot Object.get(prop) 自动查找 var, 不需要
# 显式 override get.
# ============================================================================

class _MockBaseShop:
	extends Reference

	# Array<Array<[ItemData, wave_value]>>
	# 外层 index = player_index, 内层每个元素 = [item_data, wave_value]
	var _shop_items: Array = []


# ============================================================================
# 入口
# ============================================================================

func run() -> void:
	_log("════════ P3 烟雾测试开始 ════════")

	_test_1_bridge_meta_registered()
	_test_2_get_global_not_null()
	_test_3_has_process_shop_method()
	_test_4_null_base_shop_returns_empty()
	_test_5_no_shop_items_returns_empty()
	_test_6_mock_4_slots_no_rule_all_manual()
	_test_7_mock_4_slots_reject_rule_all_skipped()
	_test_8_zero_gold_all_skipped()
	_test_9_lockable_lock_until_cursed()
	_test_10_slot_index_preserved()

	_log("════════ P3 烟雾测试结束 ════════")
	_log("结果: %d 通过 / %d 失败 / %d 警告" % [_pass, _fail, _warn])
	if _fail > 0:
		ModLoaderLog.error("P3 商店 hook 有 %d 项失败, 请检查上方日志" % _fail, LOG_NAME)


# ============================================================================
# 注册自检 (用例 1-3)
# ============================================================================

# ----------------------------------------------------------------------------
# 用例 1: mod_main 在 _init 末尾应该已经 register_global, 此时 Engine 含 meta
# ----------------------------------------------------------------------------
func _test_1_bridge_meta_registered() -> void:
	_section("[1] Bridge 已注册到 Engine meta")

	var has_meta: bool = Engine.has_meta("fengyifan-AutoTato:Bridge")
	_log("  Engine.has_meta(\"fengyifan-AutoTato:Bridge\")=%s" % str(has_meta))
	_assert(has_meta, "Engine 应含 meta 'fengyifan-AutoTato:Bridge'")


# ----------------------------------------------------------------------------
# 用例 2: Bridge.get_global() 应返回非 null 实例
# ----------------------------------------------------------------------------
func _test_2_get_global_not_null() -> void:
	_section("[2] Bridge.get_global() != null")

	var b = Bridge.get_global()
	_log("  Bridge.get_global()=%s" % str(b))
	_assert(b != null, "Bridge.get_global() 应返回非 null")


# ----------------------------------------------------------------------------
# 用例 3: 全局 Bridge 实例应有 process_shop 方法
# ----------------------------------------------------------------------------
func _test_3_has_process_shop_method() -> void:
	_section("[3] Bridge 含 process_shop 方法")

	var b = Bridge.get_global()
	_assert(b != null, "前置: Bridge.get_global() 非 null")
	if b == null:
		return
	var has_m: bool = b.has_method("process_shop")
	_log("  b.has_method(\"process_shop\")=%s" % str(has_m))
	_assert(has_m, "Bridge 实例应含 process_shop 方法")


# ============================================================================
# 容错矩阵 (用例 4-5)
# ============================================================================

# ----------------------------------------------------------------------------
# 用例 4: process_shop(null, ...) 应安全返回 []
# ----------------------------------------------------------------------------
func _test_4_null_base_shop_returns_empty() -> void:
	_section("[4] null base_shop -> 返回 []")

	var b = Bridge.new_pristine()
	var r = b.process_shop(null, 0)
	_log("  r=%s" % str(r))
	_assert(r is Array, "返回值应为 Array, 实得 %s" % typeof(r))
	if not (r is Array):
		return
	_assert(r.size() == 0, "返回数组应为空, 实得 size=%d" % r.size())


# ----------------------------------------------------------------------------
# 用例 5: base_shop 没有 _shop_items 字段 -> 返回 []
# ----------------------------------------------------------------------------
func _test_5_no_shop_items_returns_empty() -> void:
	_section("[5] base_shop 无 _shop_items -> 返回 []")

	var b = Bridge.new_pristine()
	# 纯 Reference 没有 _shop_items, Object.get("_shop_items") -> null
	var mock = Reference.new()
	var r = b.process_shop(mock, 0)
	_log("  r=%s" % str(r))
	_assert(r is Array, "返回值应为 Array, 实得 %s" % typeof(r))
	if not (r is Array):
		return
	_assert(r.size() == 0, "返回数组应为空, 实得 size=%d" % r.size())


# ============================================================================
# 正常 mock 决策 (用例 6-9)
# ============================================================================

# ----------------------------------------------------------------------------
# 用例 6: 4 个 slot, 没配任何 item_rule -> ItemDecider 回落 manual
#   不依赖 RunData (烟雾环境 gold=0), 走 decider 路径的 rule 缺失分支
# ----------------------------------------------------------------------------
func _test_6_mock_4_slots_no_rule_all_manual() -> void:
	_section("[6] 4 slot 无规则 -> 全 MANUAL")

	var b = Bridge.new_pristine()
	var slots: Array = []
	for i in 4:
		slots.append([_make_mock_item("mock_no_rule_%d" % i), 10])
	var mock = _make_mock_base_shop(slots)

	var r = b.process_shop(mock, 0)
	_log("  r.size=%d" % r.size())
	_assert(r is Array, "返回值应为 Array")
	if not (r is Array):
		return
	_assert(r.size() == 4, "应返回 4 个结果, 实得 %d" % r.size())
	if r.size() != 4:
		return

	for i in 4:
		var entry: Dictionary = r[i]
		_log("  slot[%d]=%s" % [i, str(entry)])
		_assert(String(entry.get("terminal_state", "")) == Result.STATE_MANUAL,
			"slot[%d].terminal_state 应为 MANUAL, 实得 '%s'" %
				[i, str(entry.get("terminal_state", ""))])


# ----------------------------------------------------------------------------
# 用例 7: 4 个 slot 全配 reject -> 全 SKIPPED, reason 含 "reject"
# ----------------------------------------------------------------------------
func _test_7_mock_4_slots_reject_rule_all_skipped() -> void:
	_section("[7] 4 slot reject 规则 -> 全 SKIPPED")

	var b = Bridge.new_pristine()
	var slots: Array = []
	for i in 4:
		var iid: String = "mock_reject_%d" % i
		slots.append([_make_mock_item(iid), 10])
		b.set_item_rule(iid, {"shop_action": "reject"})
	var mock = _make_mock_base_shop(slots)

	var r = b.process_shop(mock, 0)
	_log("  r.size=%d" % r.size())
	_assert(r is Array, "返回值应为 Array")
	if not (r is Array):
		return
	_assert(r.size() == 4, "应返回 4 个结果, 实得 %d" % r.size())
	if r.size() != 4:
		return

	for i in 4:
		var entry: Dictionary = r[i]
		_log("  slot[%d]=%s" % [i, str(entry)])
		_assert(String(entry.get("terminal_state", "")) == Result.STATE_SKIPPED,
			"slot[%d].terminal_state 应为 SKIPPED, 实得 '%s'" %
				[i, str(entry.get("terminal_state", ""))])
		_assert(String(entry.get("reason", "")).find("reject") >= 0,
			"slot[%d].reason 应含 'reject', 实得 '%s'" %
				[i, str(entry.get("reason", ""))])


# ----------------------------------------------------------------------------
# 用例 8: gold=0 (主菜单/烟雾环境 RunData 不可用) + 全配 get
#   预算墙 _ensure_enough_gold 会判定金币不足 -> 全 SKIPPED
#   (本来设计中要测累减, 但真累减需要 mock RunData.gold 数组, 涉及全局 autoload,
#    复杂度不值; 这里改测"零预算 + get 规则" 的预算墙路径, 同样覆盖 process_shop
#    的预算判定环节)
# ----------------------------------------------------------------------------
func _test_8_zero_gold_all_skipped() -> void:
	_section("[8] gold=0 + 全 get 规则 -> 全 SKIPPED")

	var b = Bridge.new_pristine()
	var slots: Array = []
	for i in 4:
		var iid: String = "mock_cum_%d" % i
		slots.append([_make_mock_item(iid), 10])
		b.set_item_rule(iid, {"shop_action": "get"})
	var mock = _make_mock_base_shop(slots)

	var r = b.process_shop(mock, 0)
	_log("  r.size=%d" % r.size())
	_assert(r is Array, "返回值应为 Array")
	if not (r is Array):
		return
	_assert(r.size() == 4, "应返回 4 个结果, 实得 %d" % r.size())
	if r.size() != 4:
		return

	for i in 4:
		var entry: Dictionary = r[i]
		_log("  slot[%d]=%s" % [i, str(entry)])
		_assert(String(entry.get("terminal_state", "")) == Result.STATE_SKIPPED,
			"slot[%d].terminal_state 应为 SKIPPED, 实得 '%s' (reason=%s)" %
				[i, str(entry.get("terminal_state", "")),
					str(entry.get("reason", ""))])


# ----------------------------------------------------------------------------
# 用例 9: lockable + lock_until_cursed 规则 -> LOCKED
# ----------------------------------------------------------------------------
func _test_9_lockable_lock_until_cursed() -> void:
	_section("[9] lockable + lock_until_cursed -> LOCKED")

	var b = Bridge.new_pristine()
	var item: Dictionary = _make_mock_item("mock_lockable", 10, true, false)
	var slots: Array = [[item, 10]]
	var mock = _make_mock_base_shop(slots)
	b.set_item_rule("mock_lockable", {"shop_action": "lock_until_cursed"})

	var r = b.process_shop(mock, 0)
	_log("  r=%s" % str(r))
	_assert(r is Array, "返回值应为 Array")
	if not (r is Array):
		return
	_assert(r.size() == 1, "应返回 1 个结果, 实得 %d" % r.size())
	if r.size() != 1:
		return

	var entry: Dictionary = r[0]
	_assert(String(entry.get("terminal_state", "")) == Result.STATE_LOCKED,
		"terminal_state 应为 LOCKED, 实得 '%s' (reason=%s)" %
			[str(entry.get("terminal_state", "")),
				str(entry.get("reason", ""))])


# ----------------------------------------------------------------------------
# 用例 10: 多 slot 的 slot_index 应严格保留 0..n-1 顺序
# ----------------------------------------------------------------------------
func _test_10_slot_index_preserved() -> void:
	_section("[10] slot_index 保留顺序 (0..3)")

	var b = Bridge.new_pristine()
	var slots: Array = []
	for i in 4:
		var iid: String = "mock_order_%d" % i
		slots.append([_make_mock_item(iid), 10])
		b.set_item_rule(iid, {"shop_action": "reject"})
	var mock = _make_mock_base_shop(slots)

	var r = b.process_shop(mock, 0)
	_assert(r is Array, "返回值应为 Array")
	if not (r is Array):
		return
	_assert(r.size() == 4, "应返回 4 个结果, 实得 %d" % r.size())
	if r.size() != 4:
		return

	for i in 4:
		var entry: Dictionary = r[i]
		var idx: int = int(entry.get("slot_index", -1))
		_log("  results[%d].slot_index=%d" % [i, idx])
		_assert(idx == i, "results[%d].slot_index 应为 %d, 实得 %d" % [i, i, idx])


# ============================================================================
# Mock 工厂
# ============================================================================

# 构造一个 mock BaseShop. slots_for_player0 = [[item_data, wave_value], ...]
# 内部 _shop_items 排成 4 玩家槽 (玩家 0 = 传入参数, 其他三个玩家空数组),
# 与 vanilla _shop_items 结构对齐.
func _make_mock_base_shop(slots_for_player0: Array) -> _MockBaseShop:
	var mock: _MockBaseShop = _MockBaseShop.new()
	mock._shop_items = [slots_for_player0, [], [], []]
	return mock


# 通用 mock ItemData dict. 字段与 P1/P2 烟雾保持一致, effects=[] 不触阈值.
# 默认 is_lockable=false, is_cursed=false; lockable 用例需要时显式传 true.
func _make_mock_item(
		my_id: String,
		value: int = 10,
		is_lockable: bool = false,
		is_cursed: bool = false
	) -> Dictionary:
	return {
		"my_id": my_id,
		"name": "MOCK_" + my_id.to_upper(),
		"tier": 1,
		"value": value,
		"max_nb": -1,
		"is_cursed": is_cursed,
		"is_lockable": is_lockable,
		"tags": [],
		"effects": [],
	}


# ============================================================================
# 测试辅助 (照搬 P2 风格)
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


func _warn_case(msg: String) -> void:
	_warn += 1
	ModLoaderLog.warning("  ⚠ %s" % msg, LOG_NAME)


func _log(msg: String) -> void:
	ModLoaderLog.info(msg, LOG_NAME)
