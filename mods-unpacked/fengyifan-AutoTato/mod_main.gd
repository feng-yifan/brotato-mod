extends Node

# ============================================================================
# fengyifan-AutoTato — Mod 入口
# ============================================================================
#
# 本文件结构遵循 Godot Mod Loader 官方 wiki 的 Godot 3 模板：
#   https://wiki.godotmodding.com/guides/modding/mod_files/
#
# 加载流程：
#   1. ModLoader 扫描 res://mods-unpacked/ 找到本目录
#   2. 读取同级 manifest.json 校验版本兼容性、依赖
#   3. new() 本脚本 → 触发 _init()
#   4. 把节点挂到场景树 → 触发 _ready()
#
# 关键：
#   - _init() 里调用 ModLoaderMod 的 install_*() 系列函数注册扩展（要在游戏
#     场景树构建前完成，否则扩展无效）
#   - _ready() 里做需要场景树就绪后的初始化（如查找节点、连接信号）
#   - 所有日志走 ModLoaderLog，调用时附带本 mod 的唯一 LOG_NAME 作为来源
#
# 当前阶段：P3.6 — 数据层（P0）+ 决策器层（P1）+ Bridge（P2）+ 商店 hook（P3）+ 升级 hook（P3.5）+ 箱子 hook（P3.6）。
#   Script Extension 已挂到 vanilla base_shop 与 upgrades_ui。后者通过 _items_container.visible
#   分支同时处理升级 4 选 1 (P3.5 decide_upgrade) 与箱子单物品 (P3.6 decide_chest_item)。
#   默认无 item_rules + upgrade_automation_enabled=false → 行为等同 vanilla; 配 rule 后才自动化。
#   UI 配置面板留 P5。
# ============================================================================

# Mod ID 拆出来做常量，方便构造资源路径与日志归属
const MOD_DIR := "fengyifan-AutoTato"
const LOG_NAME := "fengyifan-AutoTato:Main"

# ----------------------------------------------------------------------------
# P0 数据层文件路径（暂未接入运行时，仅做路径单点配置 + preload 校验）
# ----------------------------------------------------------------------------
# 这些常量目前的作用：
#   1. 单点配置：将来 _init() 接入决策器时不必到处拼字符串
#   2. preload 校验：见下方 _PRELOADS，强制 Godot 在 mod 加载阶段就解析这些
#      文件，写错路径 / 语法错误立即报错，而不是等运行到才崩
#   3. 烟雾脚本用它们做断言
const PATH_EFFECT_SCHEMA    := "res://mods-unpacked/fengyifan-AutoTato/autotato/data/effect_schema.gd"
const PATH_EFFECT_PARSER    := "res://mods-unpacked/fengyifan-AutoTato/autotato/data/effect_parser.gd"
const PATH_EFFECT_KEYS      := "res://mods-unpacked/fengyifan-AutoTato/autotato/data/effect_keys.gd"
const PATH_ITEM_DATA_UTIL   := "res://mods-unpacked/fengyifan-AutoTato/autotato/data/item_data_util.gd"
const PATH_WEAPON_DATA_UTIL := "res://mods-unpacked/fengyifan-AutoTato/autotato/data/weapon_data_util.gd"
const PATH_DANGER_MODIFIER  := "res://mods-unpacked/fengyifan-AutoTato/autotato/data/danger_modifier.gd"
const PATH_P0_SMOKE_TEST    := "res://mods-unpacked/fengyifan-AutoTato/autotato/dev/p0_smoke_test.gd"

# ----------------------------------------------------------------------------
# P1 决策器层文件路径（同样仅 preload 校验，尚未接入 vanilla hook）
# ----------------------------------------------------------------------------
const PATH_DECISION_RESULT  := "res://mods-unpacked/fengyifan-AutoTato/autotato/decisions/decision_result.gd"
const PATH_THRESHOLD_GATE   := "res://mods-unpacked/fengyifan-AutoTato/autotato/decisions/threshold_gate.gd"
const PATH_ITEM_DECIDER     := "res://mods-unpacked/fengyifan-AutoTato/autotato/decisions/item_decider.gd"
const PATH_UPGRADE_DECIDER  := "res://mods-unpacked/fengyifan-AutoTato/autotato/decisions/upgrade_decider.gd"
const PATH_P1_SMOKE_TEST    := "res://mods-unpacked/fengyifan-AutoTato/autotato/dev/p1_smoke_test.gd"

# ----------------------------------------------------------------------------
# P2 Bridge 层文件路径
# ----------------------------------------------------------------------------
const PATH_BRIDGE           := "res://mods-unpacked/fengyifan-AutoTato/autotato/runtime/bridge.gd"
const PATH_P2_SMOKE_TEST    := "res://mods-unpacked/fengyifan-AutoTato/autotato/dev/p2_smoke_test.gd"

# ----------------------------------------------------------------------------
# P3 Hook 层文件路径
# ----------------------------------------------------------------------------
# Script Extension 必须镜像 vanilla 路径 (ModLoader 据此匹配父类)
const PATH_HOOK_BASE_SHOP   := "ui/menus/shop/base_shop.gd"
const PATH_P3_SMOKE_TEST    := "res://mods-unpacked/fengyifan-AutoTato/autotato/dev/p3_smoke_test.gd"

# ----------------------------------------------------------------------------
# P3.5 Hook 层文件路径 (升级面板)
# ----------------------------------------------------------------------------
const PATH_HOOK_UPGRADES_UI := "ui/menus/ingame/upgrades_ui.gd"
const PATH_P3_5_SMOKE_TEST  := "res://mods-unpacked/fengyifan-AutoTato/autotato/dev/p3_5_smoke_test.gd"

# ----------------------------------------------------------------------------
# P4 ConfigManager 配置持久化层
# ----------------------------------------------------------------------------
const PATH_CONFIG_MANAGER   := "res://mods-unpacked/fengyifan-AutoTato/autotato/runtime/config_manager.gd"
const PATH_P4_SMOKE_TEST    := "res://mods-unpacked/fengyifan-AutoTato/autotato/dev/p4_smoke_test.gd"

# ----------------------------------------------------------------------------
# P5.1 UI 配置面板入口
# ----------------------------------------------------------------------------
const PATH_HOOK_INGAME_MAIN_MENU := "ui/menus/ingame/ingame_main_menu.gd"
const PATH_CONFIG_PANEL_GD       := "res://mods-unpacked/fengyifan-AutoTato/autotato/ui/config_panel.gd"
const PATH_GENERAL_TAB_GD        := "res://mods-unpacked/fengyifan-AutoTato/autotato/ui/tabs/general_tab.gd"
const PATH_ITEMS_TAB_GD       := "res://mods-unpacked/fengyifan-AutoTato/autotato/ui/tabs/items_tab.gd"
const PATH_THRESHOLDS_TAB_GD  := "res://mods-unpacked/fengyifan-AutoTato/autotato/ui/tabs/thresholds_tab.gd"
const PATH_P5_1_SMOKE_TEST       := "res://mods-unpacked/fengyifan-AutoTato/autotato/dev/p5_1_smoke_test.gd"
const PATH_P2_V6_SMOKE_TEST      := "res://mods-unpacked/fengyifan-AutoTato/autotato/dev/p2_v6_smoke_test.gd"

# preload 一遍所有文件，强制 Godot 在 mod 加载阶段解析它们
# 写错路径或语法错误会在这里直接报错，不会拖到运行期
const _PRELOAD_EFFECT_SCHEMA    := preload("res://mods-unpacked/fengyifan-AutoTato/autotato/data/effect_schema.gd")
const _PRELOAD_EFFECT_KEYS      := preload("res://mods-unpacked/fengyifan-AutoTato/autotato/data/effect_keys.gd")
const _PRELOAD_EFFECT_PARSER    := preload("res://mods-unpacked/fengyifan-AutoTato/autotato/data/effect_parser.gd")
const _PRELOAD_ITEM_DATA_UTIL   := preload("res://mods-unpacked/fengyifan-AutoTato/autotato/data/item_data_util.gd")
const _PRELOAD_WEAPON_DATA_UTIL := preload("res://mods-unpacked/fengyifan-AutoTato/autotato/data/weapon_data_util.gd")
const _PRELOAD_DANGER_MODIFIER  := preload("res://mods-unpacked/fengyifan-AutoTato/autotato/data/danger_modifier.gd")
const _PRELOAD_DECISION_RESULT  := preload("res://mods-unpacked/fengyifan-AutoTato/autotato/decisions/decision_result.gd")
const _PRELOAD_THRESHOLD_GATE   := preload("res://mods-unpacked/fengyifan-AutoTato/autotato/decisions/threshold_gate.gd")
const _PRELOAD_ITEM_DECIDER     := preload("res://mods-unpacked/fengyifan-AutoTato/autotato/decisions/item_decider.gd")
const _PRELOAD_UPGRADE_DECIDER  := preload("res://mods-unpacked/fengyifan-AutoTato/autotato/decisions/upgrade_decider.gd")
# ConfigManager 必须在 Bridge 之前 preload, 因为 Bridge._init 引用 AT_ConfigManager
const _PRELOAD_CONFIG_MANAGER   := preload("res://mods-unpacked/fengyifan-AutoTato/autotato/runtime/config_manager.gd")
const _PRELOAD_BRIDGE           := preload("res://mods-unpacked/fengyifan-AutoTato/autotato/runtime/bridge.gd")
# P5.1 UI 类 preload 校验 (强制启动期解析, 写错路径或语法错立刻报错)
const _PRELOAD_CONFIG_PANEL_GD  := preload("res://mods-unpacked/fengyifan-AutoTato/autotato/ui/config_panel.gd")
const _PRELOAD_GENERAL_TAB_GD   := preload("res://mods-unpacked/fengyifan-AutoTato/autotato/ui/tabs/general_tab.gd")
const _PRELOAD_ITEMS_TAB_GD     := preload("res://mods-unpacked/fengyifan-AutoTato/autotato/ui/tabs/items_tab.gd")
const _PRELOAD_THRESHOLDS_TAB_GD := preload("res://mods-unpacked/fengyifan-AutoTato/autotato/ui/tabs/thresholds_tab.gd")
const _PRELOAD_WEAPONS_TAB_GD    := preload("res://mods-unpacked/fengyifan-AutoTato/autotato/ui/tabs/weapons_tab.gd")

# ----------------------------------------------------------------------------
# 烟雾测试开关（开发期自检用，默认全部关闭）
# ----------------------------------------------------------------------------
# 推荐用环境变量临时启用，跑完不留痕：
#   P0:  AUTOTATO_SMOKE=1    ./Brotato.x86_64   (兼容旧名)
#   P1:  AUTOTATO_P1_SMOKE=1 ./Brotato.x86_64
#   P2:  AUTOTATO_P2_SMOKE=1 ./Brotato.x86_64
#   P3:   AUTOTATO_P3_SMOKE=1 ./Brotato.x86_64
#   P3.5: AUTOTATO_P3_5_SMOKE=1 ./Brotato.x86_64
# 多个开关可以叠加（同时跑 P0+P1+P2+P3+P3.5 验证全栈）
const DEV_RUN_P0_SMOKE := false
const DEV_RUN_P1_SMOKE := false
const DEV_RUN_P2_SMOKE := false
const DEV_RUN_P3_SMOKE := false
const DEV_RUN_P3_5_SMOKE := false
const DEV_RUN_P4_SMOKE := false
const DEV_RUN_P5_1_SMOKE := false
DEV_RUN_P2_V6_SMOKE := false

# 各子目录路径在 _init() 里组装，避免每个 install 调用都重复写一遍前缀
var mod_dir_path := ""
var extensions_dir_path := ""
var translations_dir_path := ""

# Bridge 全局实例（P2 引入）。在 _init() 末尾 new 出来并注册到 Engine.set_meta，
# Hook 层（P3 任务）通过 AT_Bridge.get_global() 拿到。
# 不写 `: AT_Bridge` 类型注解，因为 Godot 3 解析期可能还未注册 class_name。
var bridge


# ----------------------------------------------------------------------------
# 生命周期
# ----------------------------------------------------------------------------

# _init() 由 ModLoader 在场景树构建之前调用
# 此时所有 install_* 注册必须完成，之后再 install 的扩展不会生效
func _init() -> void:
	mod_dir_path = ModLoaderMod.get_unpacked_dir().plus_file(MOD_DIR)

	install_script_extensions()
	add_translations()

	# P2: 创建 Bridge 实例并注册到 Engine 元数据
	# Hook 层（P3 任务）通过 AT_Bridge.get_global() 拿到，一行接入
	bridge = _PRELOAD_BRIDGE.new()
	_PRELOAD_BRIDGE.register_global(bridge)


# _ready() 在节点被加到场景树后触发（vanilla 场景已经存在）
# 适合做：查找现有节点、连接信号、注入 UI 控件
func _ready() -> void:
	ModLoaderLog.info("AutoTato 已加载（P0+P1+P2+P3+P3.5+P3.6+P4+P5.1 UI 入口）", LOG_NAME)

	# 开发期烟雾测试：常量开关 + 环境变量 双触发
	# 用 deferred 避免在 _ready 链上做长 IO，让其他 mod 先加载完
	# AUTOTATO_SMOKE 兼容 P0 旧名（等同 AUTOTATO_P0_SMOKE）
	var run_p0 := DEV_RUN_P0_SMOKE \
		or OS.has_environment("AUTOTATO_SMOKE") \
		or OS.has_environment("AUTOTATO_P0_SMOKE")
	var run_p1 := DEV_RUN_P1_SMOKE or OS.has_environment("AUTOTATO_P1_SMOKE")
	var run_p2 := DEV_RUN_P2_SMOKE or OS.has_environment("AUTOTATO_P2_SMOKE")
	var run_p3 := DEV_RUN_P3_SMOKE or OS.has_environment("AUTOTATO_P3_SMOKE")
	var run_p3_5 := DEV_RUN_P3_5_SMOKE or OS.has_environment("AUTOTATO_P3_5_SMOKE")
	var run_p4 := DEV_RUN_P4_SMOKE or OS.has_environment("AUTOTATO_P4_SMOKE")
	var run_p5_1 := DEV_RUN_P5_1_SMOKE or OS.has_environment("AUTOTATO_P5_1_SMOKE")
	var run_p2_v6 := DEV_RUN_P2_V6_SMOKE or OS.has_environment("AUTOTATO_P2_V6_SMOKE")

	if run_p0:
		call_deferred("_run_smoke_test", PATH_P0_SMOKE_TEST, "P0")
	if run_p1:
		call_deferred("_run_smoke_test", PATH_P1_SMOKE_TEST, "P1")
	if run_p2:
		call_deferred("_run_smoke_test", PATH_P2_SMOKE_TEST, "P2")
	if run_p3:
		call_deferred("_run_smoke_test", PATH_P3_SMOKE_TEST, "P3")
	if run_p3_5:
		call_deferred("_run_smoke_test", PATH_P3_5_SMOKE_TEST, "P3.5")
	if run_p4:
		call_deferred("_run_smoke_test", PATH_P4_SMOKE_TEST, "P4")
	if run_p5_1:
		call_deferred("_run_smoke_test", PATH_P5_1_SMOKE_TEST, "P5.1")
	if run_p2_v6:
		call_deferred("_run_smoke_test", PATH_P2_V6_SMOKE_TEST, "P2v6")


# 通用烟雾脚本入口。脚本路径通过 path 传入，stage_label 仅用于日志区分
func _run_smoke_test(path: String, stage_label: String) -> void:
	var SmokeTest = load(path)
	if SmokeTest == null:
		ModLoaderLog.error("找不到 %s 烟雾脚本: %s" % [stage_label, path], LOG_NAME)
		return
	# 用 .new() 而不是 .run() 直接静态调用，是为了让烟雾脚本内部能用 self 持状态
	var test = SmokeTest.new()
	test.run()


# ----------------------------------------------------------------------------
# 注册器：脚本扩展
# ----------------------------------------------------------------------------

# 把 extensions/ 下的脚本注册为 vanilla 脚本的运行时子类
# 例如 autotato/extensions/ui/menus/shop/base_shop.gd 会扩展 res://ui/menus/shop/base_shop.gd
# 路径必须镜像 vanilla 路径，ModLoader 据此匹配父类
func install_script_extensions() -> void:
	# 注意：extensions/ 在 autotato/ 子目录下（统一所有 mod 代码放 autotato/ 命名空间）
	extensions_dir_path = mod_dir_path.plus_file("autotato/extensions")
	# P3: 商店决策 hook
	ModLoaderMod.install_script_extension(
		extensions_dir_path.plus_file(PATH_HOOK_BASE_SHOP)
	)
	# P3.5: 升级面板决策 hook
	ModLoaderMod.install_script_extension(
		extensions_dir_path.plus_file(PATH_HOOK_UPGRADES_UI)
	)
	# P5.1: 暂停菜单 UI 入口 hook
	ModLoaderMod.install_script_extension(
		extensions_dir_path.plus_file(PATH_HOOK_INGAME_MAIN_MENU)
	)


# ----------------------------------------------------------------------------
# 注册器：翻译
# ----------------------------------------------------------------------------

# 把 translations/ 下的 .translation 资源合并到 vanilla 翻译表中
# 文件名需符合 ModLoader 的命名约定（key.locale.translation）
func add_translations() -> void:
	translations_dir_path = mod_dir_path.plus_file("translations")
	# ModLoaderMod.add_translation(translations_dir_path.plus_file("autotato.en.translation"))
