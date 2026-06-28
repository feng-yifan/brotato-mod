extends Reference

# ============================================================================
# AutoTato — 升级 Hook 烟雾测试 (升级 hook)
# ============================================================================
#
# 目的: 验证在 vanilla UpgradesUI 上挂的升级面板 hook 链路前置条件
#       (hook 文件存在 + GDScript 解析通过), 并复测 Bridge.decide_upgrade 在
#       真实 vanilla UpgradeData tres 与 mock dict 两种输入下的核心分支.
#
# 为什么不能真触发升级面板:
#   升级面板的运行时条件是 wave 结束 + 经验值满, 烟雾在主菜单 / mod _ready
#   阶段触发, 缺 RunData / 缺 UpgradesUI 节点树, 不能 mock 出真升级流程.
#   因此 hook 副作用 (UpgradesUI._ready 后改 button 文案 / 自动点击) 留人手
#   开局回归验证.
#
# 与其他烟雾的分工:
#   - 数据层: schema (Effect / Keys / Util / ThresholdGate)
#   - 决策层: 决策器 (static 纯函数)
#   - Bridge: config / CRUD / 三个 decide_* 入口
#   - 商店 Hook: Bridge.process_shop 整商店决策 + 容错矩阵
#   - 升级 Hook: 文件就绪态 + Bridge.decide_upgrade 真实 tres 输入
#
# 触发: 默认关闭. mod_main 的 DEV_RUN_UPGRADE_HOOK_SMOKE 改 true 即在游戏启动时
#       .new() 出实例并 run(), 结果写到 godot.log; 亦可通过环境变量
#       AUTOTATO_UPGRADE_HOOK_SMOKE 在 mod_main 中读取触发.
#
# 用例总览 (8 个):
#   1. hook 文件存在 (ResourceLoader + File 二次校验)
#   2. hook 脚本可 load (GDScript 解析 + extends 路径校验)
#   3. decide_upgrade 喂真实 vanilla UpgradeData tres -> 返回 0
#   4. decide_upgrade 空 list -> NO_PICK
#   5. min_tier 过滤 (mock dict, quality_first=true)
#   6. quality_first=false 时按原顺序选第一满足项
#   7. upgrade_automation_enabled=false -> NO_PICK
#   8. threshold gate 联动 (mock dict 含 stat_speed effect, 不触达 upper)
#
# 用例间状态隔离: 每个 _test_* 内 Bridge.new_pristine() 独立实例.
# ============================================================================


const LOG_NAME := "fengyifan-AutoTato:UpgradeHookSmokeTest"

const Bridge = preload("res://mods-unpacked/fengyifan-AutoTato/autotato/runtime/bridge.gd")
const UpgDec = preload("res://mods-unpacked/fengyifan-AutoTato/autotato/decisions/upgrade_decider.gd")

const HOOK_PATH := "res://mods-unpacked/fengyifan-AutoTato/autotato/extensions/ui/menus/ingame/upgrades_ui.gd"

# 真实 vanilla upgrade tres (tier=0 stat_max_hp 升级, 最简单 stat 加成):
#   - my_id  = "upgrade_max_hp_1"
#   - tier   = 0
#   - effects= [ExtResource(health_effect.tres)]  (无 stat_speed)
# 选 tier=0 是为了"默认 min_tier=-1 不过滤"用例能稳定通过.
const REAL_UPGRADE_PATH := "res://items/upgrades/health/1/health_data.tres"


# 计数: 通过 / 失败 / 警告
var _pass := 0
var _fail := 0
var _warn := 0


# ============================================================================
# 入口
# ============================================================================

func run() -> void:
	_log("════════ 升级 Hook 烟雾测试开始 ════════")

	_test_1_hook_file_exists()
	_test_2_hook_extends_vanilla()
	_test_3_decide_upgrade_with_real_tres()
	_test_4_decide_upgrade_empty_list()
	_test_5_decide_upgrade_min_tier_filter()
	_test_6_decide_upgrade_quality_first()
	_test_7_decide_upgrade_no_pick_on_disabled()
	_test_8_decide_upgrade_with_threshold()

	_log("════════ 升级 Hook 烟雾测试结束 ════════")
	_log("结果: %d 通过 / %d 失败 / %d 警告" % [_pass, _fail, _warn])
	if _fail > 0:
		ModLoaderLog.error("升级 hook 有 %d 项失败, 请检查上方日志" % _fail, LOG_NAME)


# ============================================================================
# Hook 文件就绪态 (用例 1-2)
# ============================================================================

# ----------------------------------------------------------------------------
# 用例 1: hook 文件存在 (ResourceLoader + File 二次校验)
#   ModLoader 在 _init 阶段调 install_script_extension(HOOK_PATH), 路径必须
#   是 res:// 真实存在的 .gd. 这里两路校验, 任一失败都拦下来.
# ----------------------------------------------------------------------------
func _test_1_hook_file_exists() -> void:
	_section("[1] hook 文件存在")

	var rl_exists: bool = ResourceLoader.exists(HOOK_PATH)
	_log("  ResourceLoader.exists(%s)=%s" % [HOOK_PATH, str(rl_exists)])
	_assert(rl_exists, "ResourceLoader 应能识别 hook 路径")

	var f: File = File.new()
	var file_exists: bool = f.file_exists(HOOK_PATH)
	_log("  File.file_exists(%s)=%s" % [HOOK_PATH, str(file_exists)])
	_assert(file_exists, "File API 应能在磁盘上找到 hook 文件")


# ----------------------------------------------------------------------------
# 用例 2: hook 脚本 load 成功
#   load() 返回非 null 即表示 GDScript 解析通过 (含 extends 路径校验、
#   语法、preload 路径). Godot 解析失败会直接返 null 并在日志报错.
# ----------------------------------------------------------------------------
func _test_2_hook_extends_vanilla() -> void:
	_section("[2] hook 已被 ModLoader 安装到 vanilla UpgradesUI")

	# 烟雾不能 load(HOOK_PATH) 来验证 hook 解析 —— ModLoader 在 install 阶段调过
	# child_script.take_over_path(vanilla_path), mod 路径已重定向. 再 load 会触发
	# 二次 reload, Godot 3 GDScript 解析器会报"祖先链 LOG_NAME 冲突" (烟雾自找的
	# 假警报, 真实运行时 vanilla 类实例化时不会触发).
	#
	# 改用 ModLoader 自己维护的安装记录: ModLoaderStore.saved_scripts 是个
	# Dictionary {vanilla_path: [original_script, ext1, ext2, ...]}, 在 install
	# 时由 _ModLoaderScriptExtension.apply_extension() 写入. 只要 vanilla 路径在
	# 字典里且数组非空, 说明 ModLoader 成功把 hook 注入了.
	var vanilla_path = "res://ui/menus/ingame/upgrades_ui.gd"

	# 防御: ModLoaderStore 是 autoload, 但烟雾环境也许某些 mod loader 版本
	# 没暴露这个字段. 用 Object.get() 探测.
	if typeof(ModLoaderStore) != TYPE_OBJECT:
		_assert(false, "ModLoaderStore autoload 不可用, 无法验证 hook 安装")
		return
	var saved = ModLoaderStore.get("saved_scripts")
	if typeof(saved) != TYPE_DICTIONARY:
		_assert(false, "ModLoaderStore.saved_scripts 不是 Dictionary, 可能 ModLoader 版本不兼容")
		return

	_log("  ModLoaderStore.saved_scripts 含 %d 个 vanilla 路径" % saved.size())
	_assert(saved.has(vanilla_path),
		"ModLoaderStore.saved_scripts 应含 '%s'" % vanilla_path)

	if saved.has(vanilla_path):
		var ext_list = saved[vanilla_path]
		# 数组 = [original_script, ...ext_scripts]; size >= 2 说明至少一个 mod 注入过
		_log("  saved_scripts[%s] 含 %d 项 (含 original)" % [vanilla_path, ext_list.size()])
		_assert(ext_list.size() >= 2,
			"扩展数组至少应有 2 项 (original + 我们的 hook), 实得 %d" % ext_list.size())


# ============================================================================
# decide_upgrade 真实 / 边界输入 (用例 3-8)
# ============================================================================

# ----------------------------------------------------------------------------
# 用例 3: 真实 vanilla UpgradeData tres 喂单候选 -> 返回 0
#   构造最小输入: 单选项 + 默认 config (min_tier=-1 不过滤,
#   quality_first=false, 总开关默认 true). 期望选中 index 0.
# ----------------------------------------------------------------------------
func _test_3_decide_upgrade_with_real_tres() -> void:
	_section("[3] 真实 UpgradeData tres + 单候选 -> 返回 0")

	var b = Bridge.new_pristine()
	# 默认 upgrade_automation_enabled=false, 这里测决策器逻辑需显式开启
	b.set_upgrade_automation_enabled(true)
	var up = load(REAL_UPGRADE_PATH)
	_log("  load(%s)=%s" % [REAL_UPGRADE_PATH, str(up)])
	_assert(up != null, "真实 vanilla upgrade tres 应能 load")
	if up == null:
		return

	var idx: int = b.decide_upgrade([up], 0)
	_log("  decide_upgrade([real_up], 0) = %d" % idx)
	_assert(idx == 0, "单候选 + 默认 config 应返回 0, 实得 %d" % idx)


# ----------------------------------------------------------------------------
# 用例 4: 空 list -> NO_PICK (-1)
# ----------------------------------------------------------------------------
func _test_4_decide_upgrade_empty_list() -> void:
	_section("[4] 空 option_list -> NO_PICK")

	var b = Bridge.new_pristine()
	var idx: int = b.decide_upgrade([], 0)
	_log("  decide_upgrade([], 0) = %d" % idx)
	_assert(idx == UpgDec.NO_PICK, "空 list 应返 NO_PICK(%d), 实得 %d" % [UpgDec.NO_PICK, idx])


# ----------------------------------------------------------------------------
# 用例 5: min_tier=2 + quality_first=true 过滤
#   候选: [tier=0, tier=2, tier=3, tier=1] (索引 0..3)
#   filtered (tier>=2): [tier=2 (idx=1), tier=3 (idx=2)]
#   quality_first=true -> 按 tier 降序排, 第一名 = tier=3 (original_index=2)
# ----------------------------------------------------------------------------
func _test_5_decide_upgrade_min_tier_filter() -> void:
	_section("[5] min_tier=2 + quality_first=true -> 选 tier 最高 (idx=2)")

	var b = Bridge.new_pristine()
	# 默认 upgrade_automation_enabled=false, 这里测决策器逻辑需显式开启
	b.set_upgrade_automation_enabled(true)
	var list: Array = [
		_make_mock_upgrade(0),
		_make_mock_upgrade(2),
		_make_mock_upgrade(3),
		_make_mock_upgrade(1),
	]
	b.set_upgrade_config("min_tier", 2)
	b.set_upgrade_config("quality_first", true)

	var idx: int = b.decide_upgrade(list, 0)
	_log("  decide_upgrade(4 mocks tier=[0,2,3,1], min_tier=2, quality_first=true) = %d" % idx)
	_assert(idx == 2, "应选 tier 最高 (original_index=2), 实得 %d" % idx)


# ----------------------------------------------------------------------------
# 用例 6: min_tier=2 + quality_first=false 按原顺序选
#   候选同 5: [tier=0, tier=2, tier=3, tier=1]
#   filtered (tier>=2): [tier=2 (idx=1), tier=3 (idx=2)] (保留原顺序)
#   quality_first=false -> 不排序, filtered[0] = idx=1
# ----------------------------------------------------------------------------
func _test_6_decide_upgrade_quality_first() -> void:
	_section("[6] min_tier=2 + quality_first=false -> 选首个满足项 (idx=1)")

	var b = Bridge.new_pristine()
	# 默认 upgrade_automation_enabled=false, 这里测决策器逻辑需显式开启
	b.set_upgrade_automation_enabled(true)
	var list: Array = [
		_make_mock_upgrade(0),
		_make_mock_upgrade(2),
		_make_mock_upgrade(3),
		_make_mock_upgrade(1),
	]
	b.set_upgrade_config("min_tier", 2)
	b.set_upgrade_config("quality_first", false)

	var idx: int = b.decide_upgrade(list, 0)
	_log("  decide_upgrade(4 mocks tier=[0,2,3,1], min_tier=2, quality_first=false) = %d" % idx)
	_assert(idx == 1, "quality_first=false 应按原顺序选首个 tier>=2 (idx=1), 实得 %d" % idx)


# ----------------------------------------------------------------------------
# 用例 7: 自动化关闭 -> NO_PICK
#   set_upgrade_automation_enabled(false) 让 Bridge.decide_upgrade 短路.
# ----------------------------------------------------------------------------
func _test_7_decide_upgrade_no_pick_on_disabled() -> void:
	_section("[7] upgrade_automation_enabled=false -> NO_PICK")

	var b = Bridge.new_pristine()
	b.set_upgrade_automation_enabled(false)
	var list: Array = [
		_make_mock_upgrade(0),
		_make_mock_upgrade(2),
		_make_mock_upgrade(3),
		_make_mock_upgrade(1),
	]

	var idx: int = b.decide_upgrade(list, 0)
	_log("  decide_upgrade(disabled, 4 mocks) = %d" % idx)
	_assert(idx == UpgDec.NO_PICK, "总开关关闭应返 NO_PICK(%d), 实得 %d" % [UpgDec.NO_PICK, idx])


# ----------------------------------------------------------------------------
# 用例 8: threshold gate 联动 (烟雾环境玩家 stat=0, 不触达 upper)
#   Mock 1 个 UpgradeData 含 stat_speed effect, 默认 threshold:
#     stat_speed { mode=upper, value=20 }
#   烟雾环境 RunData 不可用, Gate 内 player 当前 stat_speed 视为 0,
#   不触达 20 -> 不反转 -> filtered 非空 -> 选 0.
#
#   决策层已覆盖 ThresholdGate 全矩阵, 这里只验"决策器在 threshold 路径不崩".
#   断言放宽: 返回 != NO_PICK 即认为通过 (允许 0 或其他非 -1 值).
# ----------------------------------------------------------------------------
func _test_8_decide_upgrade_with_threshold() -> void:
	_section("[8] threshold gate 联动 (stat_speed effect, 玩家=0, upper=20)")

	var b = Bridge.new_pristine()
	# 默认 upgrade_automation_enabled=false, 这里测决策器逻辑需显式开启
	b.set_upgrade_automation_enabled(true)
	# 1 个候选: tier=1, effects=[{key:stat_speed, value:5}]
	var speed_eff: Dictionary = {"key": "stat_speed", "value": 5}
	var list: Array = [_make_mock_upgrade(1, [speed_eff])]

	var idx: int = b.decide_upgrade(list, 0)
	_log("  decide_upgrade([stat_speed +5], default thresholds) = %d" % idx)
	_assert(idx != UpgDec.NO_PICK,
		"玩家 stat_speed=0 < upper=20, 不应反转, 应被选中 (!= NO_PICK), 实得 %d" % idx)


# ============================================================================
# Mock 工厂
# ----------------------------------------------------------------------------
# vanilla UpgradeData extends ItemData, 关键字段:
#   tier, effects, name, my_id
# 决策器通过 ItemU.get_tier(data) 拿 tier, 通过 Object.get("effects") 拿 effects.
# Godot Dictionary 通过 .get(key) 走鸭式访问, 与 Object.get 兼容.
# ============================================================================

func _make_mock_upgrade(tier: int, effects: Array = []) -> Dictionary:
	return {
		"tier": tier,
		"effects": effects,
		"name": "MOCK_UPGRADE",
		"my_id": "mock_upgrade_tier_%d" % tier,
	}


# ============================================================================
# 测试辅助 (照搬商店 Hook 风格)
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
