extends Reference

# ============================================================================
# AutoTato — P6 烟雾测试 (手柄支持)
# ============================================================================
#
# 目的: 验证 P6.1–P6.4 手柄支持改造的代码就绪态:
#   - 文件存在 (gamepad_navigator.gd + scene 引用)
#   - 所有 UI tab 控件已启用 FOCUS_ALL (无 FOCUS_NONE 残留)
#   - GamepadNavigator 脚本可 load + 可 .new() 实例化
#   - config_panel.gd 包含焦点相关方法
#   - FocusEmulator 在 vanilla 仍可用 (不受影响)
#
# 为什么不能真触发手柄输入:
#   烟雾在 mod _ready 阶段触发, 配置面板尚未被玩家打开, 没有 InputEvent 来源.
#   手柄导航的实际交互留人手开局回归 (开游戏 → 进局 → 按 ESC → AutoTato 按钮 →
#   手柄 LB/RB 切 Tab → 方向键导航控件 → A 确认 / B 返回).
#
# 用例总览 (5 个):
#   1. gamepad_navigator.gd 文件存在
#   2. 所有 UI tab .gd 文件中不含 FOCUS_NONE (已改为 FOCUS_ALL)
#   3. config_panel.tscn 引用了 gamepad_navigator.gd (load_steps=8 + ExtResource 7)
#   4. config_panel.gd 含 _grab_initial_focus 方法 (P6.2 入口)
#   5. vanilla FocusEmulator 未被误碰 (pause_menu.tscn 仍含 FocusEmulator 子节点)
#
# 触发: 默认关闭. 环境变量 AUTOTATO_P6_SMOKE=1 触发.
# ============================================================================


const LOG_NAME := "fengyifan-AutoTato:P6SmokeTest"

const PATH_GAMEPAD_NAV_GD := "res://mods-unpacked/fengyifan-AutoTato/autotato/ui/gamepad_navigator.gd"
const PATH_CONFIG_PANEL_TSCN := "res://mods-unpacked/fengyifan-AutoTato/autotato/ui/config_panel.tscn"
const PATH_CONFIG_PANEL_GD := "res://mods-unpacked/fengyifan-AutoTato/autotato/ui/config_panel.gd"
const PATH_PAUSE_MENU_TSCN := "res://ui/menus/ingame/pause_menu.tscn"

const TAB_SCRIPTS := [
	"res://mods-unpacked/fengyifan-AutoTato/autotato/ui/tabs/general_tab.gd",
	"res://mods-unpacked/fengyifan-AutoTato/autotato/ui/tabs/upgrade_tab.gd",
	"res://mods-unpacked/fengyifan-AutoTato/autotato/ui/tabs/items_tab.gd",
	"res://mods-unpacked/fengyifan-AutoTato/autotato/ui/tabs/weapons_tab.gd",
	"res://mods-unpacked/fengyifan-AutoTato/autotato/ui/tabs/thresholds_tab.gd",
]

# 计数
var _pass := 0
var _fail := 0
var _warn := 0


func run() -> void:
	_log("════════ P6 烟雾测试开始 ════════")

	_test_1_gamepad_nav_file_exists()
	_test_2_no_focus_none_in_tab_scripts()
	_test_3_tscn_references_navigator()
	_test_4_config_panel_has_focus_methods()
	_test_5_vanilla_focus_emulator_intact()

	_log("════════ P6 烟雾测试结束 ════════")
	_log("结果: %d 通过 / %d 失败 / %d 警告" % [_pass, _fail, _warn])
	if _fail > 0:
		ModLoaderLog.error("P6 手柄支持有 %d 项失败, 请检查上方日志" % _fail, LOG_NAME)


# ----------------------------------------------------------------------------
# 用例 1: gamepad_navigator.gd 文件存在
# ----------------------------------------------------------------------------
func _test_1_gamepad_nav_file_exists() -> void:
	_section("[1] gamepad_navigator.gd 文件存在")

	var rl_exists: bool = ResourceLoader.exists(PATH_GAMEPAD_NAV_GD)
	_log("  ResourceLoader.exists(%s)=%s" % [PATH_GAMEPAD_NAV_GD, str(rl_exists)])
	_assert(rl_exists, "ResourceLoader 应能识别 gamepad_navigator.gd")

	var f: File = File.new()
	var file_exists: bool = f.file_exists(PATH_GAMEPAD_NAV_GD)
	_log("  File.file_exists(%s)=%s" % [PATH_GAMEPAD_NAV_GD, str(file_exists)])
	_assert(file_exists, "File API 应能在磁盘上找到 gamepad_navigator.gd")

	# 脚本应可 load
	var script = load(PATH_GAMEPAD_NAV_GD)
	_assert(script != null, "gamepad_navigator.gd 应能 load (GDScript 解析通过)")
	if script != null:
		var inst = script.new()
		_assert(inst != null, "gamepad_navigator.gd .new() 应非 null")
		if inst != null:
			inst.free()


# ----------------------------------------------------------------------------
# 用例 2: 所有 UI tab .gd 文件中不含 FOCUS_NONE
# ----------------------------------------------------------------------------
func _test_2_no_focus_none_in_tab_scripts() -> void:
	_section("[2] Tab 脚本中无 FOCUS_NONE 残留 (应为 FOCUS_ALL)")

	for path in TAB_SCRIPTS:
		var f: File = File.new()
		if not f.file_exists(path):
			_warn_case("跳过 %s (文件不存在)" % path)
			continue
		f.open(path, File.READ)
		var content: String = f.get_as_text()
		f.close()

		var has_focus_none := "FOCUS_NONE" in content
		_assert(not has_focus_none,
			"%s 不应含 FOCUS_NONE (所有交互控件应使用 FOCUS_ALL 默认值)" % path.get_file())


# ----------------------------------------------------------------------------
# 用例 3: config_panel.tscn 引用了 GamepadNavigator
# ----------------------------------------------------------------------------
func _test_3_tscn_references_navigator() -> void:
	_section("[3] config_panel.tscn 引用 GamepadNavigator")

	var f: File = File.new()
	if not f.file_exists(PATH_CONFIG_PANEL_TSCN):
		_assert(false, "config_panel.tscn 文件不存在")
		return
	f.open(PATH_CONFIG_PANEL_TSCN, File.READ)
	var content: String = f.get_as_text()
	f.close()

	# tscn 应包含 load_steps=8 (比 P5.1 多 1 个 ext_resource)
	var has_load_steps_8 := "load_steps=8" in content
	_assert(has_load_steps_8, "config_panel.tscn load_steps 应为 8 (含 GamepadNavigator)")

	# tscn 应引用 gamepad_navigator.gd
	var has_nav_script := "gamepad_navigator.gd" in content
	_assert(has_nav_script, "config_panel.tscn 应引用 gamepad_navigator.gd")

	# tscn 应包含 GamepadNavigator 节点
	var has_nav_node := "GamepadNavigator" in content
	_assert(has_nav_node, "config_panel.tscn 应包含 GamepadNavigator 子节点")


# ----------------------------------------------------------------------------
# 用例 4: config_panel.gd 含焦点相关方法
# ----------------------------------------------------------------------------
func _test_4_config_panel_has_focus_methods() -> void:
	_section("[4] config_panel.gd 含焦点相关方法")

	var script = load(PATH_CONFIG_PANEL_GD)
	if script == null:
		_assert(false, "config_panel.gd 无法 load")
		return

	var inst = script.new()
	if inst == null:
		_assert(false, "config_panel.gd .new() 失败")
		return

	_assert(inst.has_method("_grab_initial_focus"),
		"config_panel.gd 应含 _grab_initial_focus 方法 (P6.2)")
	_assert(inst.has_method("_find_first_focusable"),
		"config_panel.gd 应含 _find_first_focusable 方法 (P6.2)")

	inst.free()


# ----------------------------------------------------------------------------
# 用例 5: vanilla FocusEmulator 未被误碰
# ----------------------------------------------------------------------------
func _test_5_vanilla_focus_emulator_intact() -> void:
	_section("[5] vanilla FocusEmulator 不受影响")

	var f: File = File.new()
	if not f.file_exists(PATH_PAUSE_MENU_TSCN):
		_warn_case("vanilla pause_menu.tscn 不存在, 可能尚未反编译")
		return
	f.open(PATH_PAUSE_MENU_TSCN, File.READ)
	var content: String = f.get_as_text()
	f.close()

	var has_focus_emulator := "FocusEmulator" in content
	_assert(has_focus_emulator,
		"vanilla pause_menu.tscn 应仍包含 FocusEmulator (P6 不应误碰 vanilla)")


# ============================================================================
# 测试辅助
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
