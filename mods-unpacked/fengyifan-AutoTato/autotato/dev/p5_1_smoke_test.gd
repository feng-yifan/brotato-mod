extends Reference

# ============================================================================
# AutoTato — P5.1 烟雾测试 (UI 入口)
# ============================================================================
#
# 目的: 验证 P5.1 在 vanilla IngameMainMenu 上挂的"配置面板按钮入口"链路前置
#       条件 — hook 文件存在 + ModLoader 安装记录证据 + config_panel 场景与
#       脚本能 load + general_tab 脚本能 load, 并复测 Bridge P0-P4 行为没被
#       P5.1 改动碰坏 (decide_shop_item / decide_chest_item 仍可达).
#
# 为什么不能真触发 UI 交互:
#   按钮注入到 IngameMainMenu / 面板真弹出 / pause_mode 真生效, 都依赖运行时
#   场景树 + 玩家点击 (ESC 暂停 -> 找到主菜单容器 -> 按钮 _pressed). 烟雾在
#   mod _ready 阶段触发, 主菜单尚未实例化, 也没有 InputEvent 来源. 因此 UI
#   交互留人手开局回归 (打开游戏 -> 进局 -> 按 ESC -> 看按钮 -> 点开面板).
#
# 与其他烟雾的分工:
#   - P0: schema (Effect / Keys / Util / ThresholdGate)
#   - P1: 决策器层 (static 纯函数)
#   - P2: Bridge config / CRUD / 三个 decide_* 入口
#   - P3: Bridge.process_shop 整商店决策 + 商店 hook 容错矩阵
#   - P3.5: 升级 hook 文件就绪态 + Bridge.decide_upgrade 真实 tres 输入
#   - P5.1: UI 入口 hook 文件就绪 + config_panel scene/script 解析就绪
#
# 触发: 默认关闭. mod_main 的 DEV_RUN_P5_1_SMOKE 改 true 或环境变量
#       AUTOTATO_P5_1_SMOKE 触发.
#
# 用例总览 (6 个):
#   1. hook 文件存在 (ResourceLoader + File 二次校验)
#   2. ModLoader 已把 hook 注入 vanilla IngameMainMenu (saved_scripts 证据)
#   3. config_panel.tscn 文件存在
#   4. config_panel.gd 可 load + 可 .new() 实例化
#   5. general_tab.gd 可 load + 可 .new() 实例化
#   6. P0-P4 回归: Bridge.get_global() 仍暴露 decide_shop_item / decide_chest_item
# ============================================================================


const LOG_NAME := "fengyifan-AutoTato:P5_1SmokeTest"

const Bridge = preload("res://mods-unpacked/fengyifan-AutoTato/autotato/runtime/bridge.gd")

const HOOK_PATH := "res://mods-unpacked/fengyifan-AutoTato/autotato/extensions/ui/menus/ingame/ingame_main_menu.gd"
const VANILLA_PATH := "res://ui/menus/ingame/ingame_main_menu.gd"
const CONFIG_PANEL_TSCN := "res://mods-unpacked/fengyifan-AutoTato/autotato/ui/config_panel.tscn"
const CONFIG_PANEL_GD := "res://mods-unpacked/fengyifan-AutoTato/autotato/ui/config_panel.gd"
const GENERAL_TAB_GD := "res://mods-unpacked/fengyifan-AutoTato/autotato/ui/tabs/general_tab.gd"


# 计数: 通过 / 失败 / 警告
var _pass := 0
var _fail := 0
var _warn := 0


# ============================================================================
# 入口
# ============================================================================

func run() -> void:
	_log("════════ P5.1 烟雾测试开始 ════════")

	_test_1_hook_file_exists()
	_test_2_hook_extends_vanilla()
	_test_3_config_panel_tscn_exists()
	_test_4_config_panel_gd_loads()
	_test_5_general_tab_gd_loads()
	_test_6_no_regression_on_bridge()

	_log("════════ P5.1 烟雾测试结束 ════════")
	_log("结果: %d 通过 / %d 失败 / %d 警告" % [_pass, _fail, _warn])
	if _fail > 0:
		ModLoaderLog.error("P5.1 UI 入口有 %d 项失败, 请检查上方日志" % _fail, LOG_NAME)


# ============================================================================
# Hook 文件就绪态 (用例 1-2)
# ============================================================================

# ----------------------------------------------------------------------------
# 用例 1: hook 文件存在 (ResourceLoader + File 二次校验)
#   ModLoader 在 _init 阶段调 install_script_extension(HOOK_PATH), 路径必须
#   是 res:// 真实存在的 .gd. 两路校验, 任一失败都拦下来.
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
# 用例 2: ModLoader 已把 hook 注入 vanilla IngameMainMenu
#   烟雾不能 load(HOOK_PATH) 来验证 — ModLoader install 阶段调过
#   take_over_path(vanilla_path), 再 load 会触发二次 reload, Godot 3 GDScript
#   解析器会报"祖先链 LOG_NAME 冲突" (烟雾自找的假警报).
#
#   改用 ModLoaderStore.saved_scripts 安装记录: Dictionary
#   {vanilla_path: [original_script, ext1, ext2, ...]}, 只要 vanilla 路径在
#   字典里且数组 size >= 2, 说明至少一个 hook 注入成功.
# ----------------------------------------------------------------------------
func _test_2_hook_extends_vanilla() -> void:
	_section("[2] hook 已被 ModLoader 安装到 vanilla IngameMainMenu")

	# 防御: ModLoaderStore 是 autoload, 但某些 mod loader 版本也许没暴露这个字段
	if typeof(ModLoaderStore) != TYPE_OBJECT:
		_assert(false, "ModLoaderStore autoload 不可用, 无法验证 hook 安装")
		return
	var saved = ModLoaderStore.get("saved_scripts")
	if typeof(saved) != TYPE_DICTIONARY:
		_assert(false, "ModLoaderStore.saved_scripts 不是 Dictionary, 可能 ModLoader 版本不兼容")
		return

	_log("  ModLoaderStore.saved_scripts 含 %d 个 vanilla 路径" % saved.size())
	_assert(saved.has(VANILLA_PATH),
		"ModLoaderStore.saved_scripts 应含 '%s'" % VANILLA_PATH)

	if saved.has(VANILLA_PATH):
		var ext_list = saved[VANILLA_PATH]
		# 数组 = [original_script, ...ext_scripts]; size >= 2 说明至少一个 mod 注入过
		_log("  saved_scripts[%s] 含 %d 项 (含 original)" % [VANILLA_PATH, ext_list.size()])
		_assert(ext_list.size() >= 2,
			"扩展数组至少应有 2 项 (original + 我们的 hook), 实得 %d" % ext_list.size())


# ============================================================================
# UI scene/script 就绪态 (用例 3-5)
# ============================================================================

# ----------------------------------------------------------------------------
# 用例 3: config_panel.tscn 文件存在
#   ResourceLoader + File 二次校验 (.tscn 即使能被 ResourceLoader 识别, 也
#   要确认磁盘真有文件, 防 .import/ 残留误报).
# ----------------------------------------------------------------------------
func _test_3_config_panel_tscn_exists() -> void:
	_section("[3] config_panel.tscn 文件存在")

	var rl_exists: bool = ResourceLoader.exists(CONFIG_PANEL_TSCN)
	_log("  ResourceLoader.exists(%s)=%s" % [CONFIG_PANEL_TSCN, str(rl_exists)])
	_assert(rl_exists, "ResourceLoader 应能识别 config_panel.tscn")

	var f: File = File.new()
	var file_exists: bool = f.file_exists(CONFIG_PANEL_TSCN)
	_log("  File.file_exists(%s)=%s" % [CONFIG_PANEL_TSCN, str(file_exists)])
	_assert(file_exists, "File API 应能在磁盘上找到 config_panel.tscn")


# ----------------------------------------------------------------------------
# 用例 4: config_panel.gd 可 load + 可 .new() 实例化
#   load() 非 null = GDScript 解析通过 (含 extends 路径、preload、语法).
#   不调 script.has_method ("Script.has_method 在 Godot 3 不验证脚本内 func",
#   见 gotchas #7). 改 instance 化验证: 能 .new() 不崩才算"脚本完整可用".
#
#   config_panel extends Control (Node 子类), .new() 返回未挂场景树的实例,
#   直接 free() 即可 (queue_free 用于挂树后延迟释放).
# ----------------------------------------------------------------------------
func _test_4_config_panel_gd_loads() -> void:
	_section("[4] config_panel.gd load + .new() 实例化")

	var script = load(CONFIG_PANEL_GD)
	_log("  load(%s)=%s" % [CONFIG_PANEL_GD, str(script)])
	_assert(script != null, "config_panel.gd 应能 load (GDScript 解析通过)")
	if script == null:
		return

	var inst = script.new()
	_log("  script.new()=%s" % str(inst))
	_assert(inst != null, "config_panel.gd .new() 应非 null")
	if inst != null:
		# Control 是 Node, 未挂树用 free() (不是 queue_free)
		inst.free()


# ----------------------------------------------------------------------------
# 用例 5: general_tab.gd 可 load + 可 .new() 实例化
#   同用例 4: 验证 GDScript 解析通过 + 类可实例化.
# ----------------------------------------------------------------------------
func _test_5_general_tab_gd_loads() -> void:
	_section("[5] general_tab.gd load + .new() 实例化")

	var script = load(GENERAL_TAB_GD)
	_log("  load(%s)=%s" % [GENERAL_TAB_GD, str(script)])
	_assert(script != null, "general_tab.gd 应能 load (GDScript 解析通过)")
	if script == null:
		return

	var inst = script.new()
	_log("  script.new()=%s" % str(inst))
	_assert(inst != null, "general_tab.gd .new() 应非 null")
	if inst != null:
		inst.free()


# ============================================================================
# P0-P4 回归 (用例 6)
# ============================================================================

# ----------------------------------------------------------------------------
# 用例 6: P0-P4 行为零回归
#   P5.1 只动 UI 入口 + 配置面板, 不改 Bridge 决策入口. 这里查 Bridge.get_global()
#   仍能拿到全局实例, 且 decide_shop_item (P3) + decide_chest_item (P3.6) 两个
#   关键 API 仍可达. 任一失败说明 P5.1 不小心改坏了 Bridge.
# ----------------------------------------------------------------------------
func _test_6_no_regression_on_bridge() -> void:
	_section("[6] P0-P4 回归: Bridge 全局 + decide_* API 可达")

	var g = Bridge.get_global()
	_log("  Bridge.get_global()=%s" % str(g))
	_assert(g != null, "Bridge.get_global() 不应为 null (P2 全局单例)")
	if g == null:
		return

	_assert(g.has_method("decide_shop_item"),
		"Bridge.get_global() 应仍暴露 decide_shop_item (P3 API)")
	_assert(g.has_method("decide_chest_item"),
		"Bridge.get_global() 应仍暴露 decide_chest_item (P3.6 API)")


# ============================================================================
# 测试辅助 (照搬 P3.5 风格)
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
