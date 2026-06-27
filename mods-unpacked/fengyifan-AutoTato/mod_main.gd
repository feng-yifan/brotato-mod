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
const PATH_HOOK_UPGRADES_UI_PC := "ui/menus/ingame/upgrades_ui_player_container.gd"
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
const PATH_HOOK_SHOP_ITEM       := "ui/menus/shop/shop_item.gd"
const PATH_CONFIG_PANEL_GD       := "res://mods-unpacked/fengyifan-AutoTato/autotato/ui/config_panel.gd"
const PATH_GENERAL_TAB_GD        := "res://mods-unpacked/fengyifan-AutoTato/autotato/ui/tabs/general_tab.gd"
const PATH_ITEMS_TAB_GD       := "res://mods-unpacked/fengyifan-AutoTato/autotato/ui/tabs/items_tab.gd"
const PATH_THRESHOLDS_TAB_GD  := "res://mods-unpacked/fengyifan-AutoTato/autotato/ui/tabs/thresholds_tab.gd"
const PATH_WEAPONS_TAB_GD      := "res://mods-unpacked/fengyifan-AutoTato/autotato/ui/tabs/weapons_tab.gd"
const PATH_UPGRADE_TAB_GD      := "res://mods-unpacked/fengyifan-AutoTato/autotato/ui/tabs/upgrade_tab.gd"
const PATH_P5_1_SMOKE_TEST       := "res://mods-unpacked/fengyifan-AutoTato/autotato/dev/p5_1_smoke_test.gd"
const PATH_P2_V7_SMOKE_TEST      := "res://mods-unpacked/fengyifan-AutoTato/autotato/dev/p2_v6_smoke_test.gd"

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
const _PRELOAD_UPGRADE_TAB_GD    := preload("res://mods-unpacked/fengyifan-AutoTato/autotato/ui/tabs/upgrade_tab.gd")

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
const DEV_RUN_P2_V7_SMOKE := false

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
	var run_p2_v6 := DEV_RUN_P2_V7_SMOKE or OS.has_environment("AUTOTATO_P2_V6_SMOKE")

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
		call_deferred("_run_smoke_test", PATH_P2_V7_SMOKE_TEST, "P2v6")

		

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
	# v7: 升级玩家容器扩展 (按钮防抖管理, 同步 reroll)
	ModLoaderMod.install_script_extension(
		extensions_dir_path.plus_file(PATH_HOOK_UPGRADES_UI_PC)
	)
	# P5.1: 暂停菜单 UI 入口 hook
	ModLoaderMod.install_script_extension(
		extensions_dir_path.plus_file(PATH_HOOK_INGAME_MAIN_MENU)
	)
	# P5.4-ext: 商店物品规则按钮 (替换 BanButton)
	ModLoaderMod.install_script_extension(
		extensions_dir_path.plus_file(PATH_HOOK_SHOP_ITEM)
	)


# ----------------------------------------------------------------------------
# 注册器：翻译
# ----------------------------------------------------------------------------

# P5.5: 注册中英双语翻译.
# translations/autotato.csv 是翻译源文件，可在 Godot 编辑器中导入生成 .translation 二进制文件.
# 这里用 GDScript 字典直接注册翻译，确保 mod 不依赖编辑器导入也能完整显示.
func add_translations() -> void:
	translations_dir_path = mod_dir_path.plus_file("translations")

	# 优先尝试加载 Godot 编辑器导入的 .translation 文件（如果存在）
	var en_path = translations_dir_path.plus_file("autotato.en.translation")
	var zh_path = translations_dir_path.plus_file("autotato.zh.translation")
	var dir = Directory.new()
	var has_imported := false
	if dir.file_exists(en_path):
		ModLoaderMod.add_translation(en_path)
		has_imported = true
	if dir.file_exists(zh_path):
		ModLoaderMod.add_translation(zh_path)
		has_imported = true

	if has_imported:
		ModLoaderLog.info("AutoTato 已加载导入的 .translation 文件", LOG_NAME)

	# 始终注册 GDScript 翻译（作为导入文件的补充或 fallback）
	# 如果导入文件存在，GDScript 注册会填充缺失的 key；如果不存在，GDScript 是完整的备用方案
	_register_gdscript_translations()


# 用 GDScript 字典注册中英双语翻译.
# 以 translations/autotato.csv 为唯一数据源，包含所有 88 个翻译 key.
func _register_gdscript_translations() -> void:
	var en_dict := _get_en_translations()
	var zh_dict := _get_zh_translations()

	# 注册英文翻译
	var t_en = Translation.new()
	t_en.locale = "en"
	for key in en_dict:
		t_en.add_message(key, en_dict[key])
	TranslationServer.add_translation(t_en)

	# Godot 3 的 TranslationServer 对动态注册的 Translation 只做精确 locale 匹配。
	# 虽然内置了 get_language_code() 的 near_match 逻辑，但 res 值会被后续迭代的
	# Translation 覆盖 —— 如果 EN 字典在 ZH 字典之后迭代，near_match 返回 EN 值。
	# 因此为中文注册多个 locale 变体，确保无论游戏用 "zh" / "zh_CN" / "zh_Hans_CN"
	# 都能精确匹配。
	var zh_locales := ["zh", "zh_CN", "zh_Hans_CN", "zh_TW"]
	for loc in zh_locales:
		var t_zh = Translation.new()
		t_zh.locale = loc
		for key in zh_dict:
			t_zh.add_message(key, zh_dict[key])
		TranslationServer.add_translation(t_zh)

	ModLoaderLog.info("AutoTato GDScript 翻译已注册 (en: %d, zh: %d × %d locales)" % [en_dict.size(), zh_dict.size(), zh_locales.size()], LOG_NAME)


func _get_en_translations() -> Dictionary:
	return {
		"AUTOTATO_SAVE": "Save",
		"AUTOTATO_CANCEL": "Cancel",
		"AUTOTATO_ACTION_MANUAL": "Manual",
		"AUTOTATO_ACTION_SKIP": "Skip",
		"AUTOTATO_SHOP_GET": "Buy",
		"AUTOTATO_SHOP_LOCK_UNTIL_CURSED": "Lock Until Cursed",
		"AUTOTATO_SHOP_CURSED_ONLY": "Cursed Only",
		"AUTOTATO_SHOP_REJECT": "Reject",
		"AUTOTATO_CHEST_TAKE": "Take",
		"AUTOTATO_CHEST_DISCARD": "Discard",
		"AUTOTATO_FOLLOW_SET_RULE": "Follow Set Rule",
		"AUTOTATO_RULE": "Rule",
		"AUTOTATO_SECTION_AUTOMATION": "Automation Settings",
		"AUTOTATO_SHOP_AUTOMATION": "Shop Automation",
		"AUTOTATO_SHOP_AUTO_DESC": "Auto-decide buy/lock when entering shop",
		"AUTOTATO_UPGRADE_AUTOMATION": "Upgrade Automation",
		"AUTOTATO_UPGRADE_AUTO_DESC": "Auto-choose the best upgrade option",
		"AUTOTATO_SECTION_BUDGET": "Budget Settings",
		"AUTOTATO_MIN_GOLD_BALANCE": "Minimum Gold Balance",
		"AUTOTATO_MIN_GOLD_DESC": "Minimum gold to keep after purchase",
		"AUTOTATO_ITEM_PRICE_LIMIT": "Item Price Limit",
		"AUTOTATO_ITEM_PRICE_DESC": "Max single item price for auto-buy (0=unlimited)",
		"AUTOTATO_REROLL_BUDGET": "Reroll Budget",
		"AUTOTATO_REROLL_BUDGET_DESC": "Max reroll price (0=unlimited)",
		"AUTOTATO_SECTION_BEHAVIOR": "Behavior Settings",
		"AUTOTATO_AUTO_START_WAVE": "Auto Start Next Wave",
		"AUTOTATO_AUTO_START_WAVE_DESC": "Auto-enter next wave when shop can't reroll",
		"AUTOTATO_KEEP_RUNNING": "Keep Running Unfocused",
		"AUTOTATO_KEEP_RUNNING_DESC": "Game continues when window loses focus",
		"AUTOTATO_TURBO_MODE": "Turbo Mode",
		"AUTOTATO_TURBO_MODE_DESC": "On: skip UI and advance instantly; Off: pause 0.3s before advance",
		"AUTOTATO_MIN_WEAPON_TIER": "Minimum Weapon Tier:",
		"AUTOTATO_WEAPON_DATA_UNAVAILABLE": "Weapon data unavailable",
		"AUTOTATO_WEAPON_CATEGORY_DATA_UNAVAILABLE": "Weapon category data unavailable",
		"AUTOTATO_WEAPON_NO_CATEGORY": "This weapon belongs to no category",
		"AUTOTATO_WEAPON_SELF_RULE": "Weapon Self Rule",
		"AUTOTATO_CATEGORY_RULE": "Category Rules",
		"AUTOTATO_THRESHOLD_UNLIMITED": "Unlimited",
		"AUTOTATO_THRESHOLD_UPPER": "Upper Limit",
		"AUTOTATO_THRESHOLD_LOWER": "Lower Limit",
		"AUTOTATO_PRIMARY_STATS": "Primary Stats",
		"AUTOTATO_SECONDARY_STATS": "Secondary Stats",
		"AUTOTATO_UPGRADE_STRATEGY": "Upgrade Strategy",
		"AUTOTATO_RESPECT_THRESHOLDS": "Respect Thresholds",
		"AUTOTATO_RESPECT_THRESHOLDS_DESC": "Evaluate all configured thresholds; filter only when ALL related stats exceed limits",
		"AUTOTATO_MIN_TIER": "Minimum Tier",
		"AUTOTATO_QUALITY_FIRST": "Quality First",
		"AUTOTATO_QUALITY_FIRST_DESC": "Prioritize higher tier (rarity) options",
		"AUTOTATO_FORBID_STATS": "Forbidden Stats",
		"AUTOTATO_FORBID_STATS_DESC": "Upgrade options with these stats will be filtered out",
		"AUTOTATO_IGNORE_FORBID_ON_STUCK": "Ignore Forbid When Stuck",
		"AUTOTATO_IGNORE_FORBID_ON_STUCK_DESC": "When all candidates are filtered, fall back to unfiltered sort",
		"AUTOTATO_STAT_PRIORITY": "Stat Priority",
		"AUTOTATO_STAT_PRIORITY_DESC": "Within same tier, prioritize options with these stats in order",
		"AUTOTATO_PRIORITIZED": "Prioritized",
		"AUTOTATO_NOT_PRIORITIZED": "Not Prioritized",
		"AUTOTATO_REMOVE": "Remove",
		"AUTOTATO_ADD_TO_PRIORITY": "Add to Priority",
		"AUTOTATO_ITEM_TYPE_ALL": "Type: All",
		"AUTOTATO_ITEM_TYPE_UNIQUE": "Type: Unique",
		"AUTOTATO_ITEM_TYPE_LIMITED": "Type: Limited",
		"AUTOTATO_ITEM_TYPE_OTHER": "Type: Other",
		"AUTOTATO_SHOP_FILTER_ALL": "Shop: All",
		"AUTOTATO_CHEST_FILTER_ALL": "Chest: All",
		"AUTOTATO_SHOP_RESPECT_THRESHOLDS": "Shop Respects Thresholds",
		"AUTOTATO_CHEST_RESPECT_THRESHOLDS": "Chest Respects Thresholds",
		"AUTOTATO_ITEM_DATA_UNAVAILABLE": "Item data unavailable",
		"AUTOTATO_SHOP_BEHAVIOR": "Shop Behavior",
		"AUTOTATO_CHEST_BEHAVIOR": "Chest Behavior",
		"AUTOTATO_WEAPON_RULE": "Weapon Rule",
		"AUTOTATO_ITEM_RULE": "Item Rule",
		"AUTOTATO_NO_CATEGORY": "No Category",
		"AUTOTATO_TAB_GENERAL": "General",
		"AUTOTATO_TAB_UPGRADE": "Upgrade",
		"AUTOTATO_TAB_ITEMS": "Items",
		"AUTOTATO_TAB_WEAPONS": "Weapons",
		"AUTOTATO_TAB_THRESHOLDS": "Thresholds",
		"AUTOTATO_CORNER_SHOP": "",
		"AUTOTATO_CORNER_CHEST": "",
		"AUTOTATO_PANEL_TITLE": "AutoTato Configuration",
		"AUTOTATO_AUTOMATION": "AutoTato",
		"AUTOTATO_TIER_COMMON": "Common",
		"AUTOTATO_TIER_RARE": "Rare",
		"AUTOTATO_TIER_EPIC": "Epic",
		"AUTOTATO_TIER_LEGENDARY": "Legendary",
		"AUTOTATO_SHOP_FILTER_FMT": "Shop: %s",
		"AUTOTATO_CHEST_FILTER_FMT": "Chest: %s",
		"AUTOTATO_UNKNOWN": "Unknown",
	}


func _get_zh_translations() -> Dictionary:
	return {
		"AUTOTATO_SAVE": "保存",
		"AUTOTATO_CANCEL": "取消",
		"AUTOTATO_ACTION_MANUAL": "手动",
		"AUTOTATO_ACTION_SKIP": "跳过",
		"AUTOTATO_SHOP_GET": "购买",
		"AUTOTATO_SHOP_LOCK_UNTIL_CURSED": "锁定等诅咒",
		"AUTOTATO_SHOP_CURSED_ONLY": "仅诅咒",
		"AUTOTATO_SHOP_REJECT": "拒绝",
		"AUTOTATO_CHEST_TAKE": "拿取",
		"AUTOTATO_CHEST_DISCARD": "丢弃",
		"AUTOTATO_FOLLOW_SET_RULE": "受类别控制",
		"AUTOTATO_RULE": "规则",
		"AUTOTATO_SECTION_AUTOMATION": "自动化设置",
		"AUTOTATO_SHOP_AUTOMATION": "商店自动化",
		"AUTOTATO_SHOP_AUTO_DESC": "进入商店时自动决策购买/锁定",
		"AUTOTATO_UPGRADE_AUTOMATION": "升级自动化",
		"AUTOTATO_UPGRADE_AUTO_DESC": "升级时自动选择最优项",
		"AUTOTATO_SECTION_BUDGET": "预算设置",
		"AUTOTATO_MIN_GOLD_BALANCE": "最低金币保留",
		"AUTOTATO_MIN_GOLD_DESC": "购买后至少保留的金币数",
		"AUTOTATO_ITEM_PRICE_LIMIT": "物品价格上限",
		"AUTOTATO_ITEM_PRICE_DESC": "单件物品价格超过此值不自动购买 (0=不限)",
		"AUTOTATO_REROLL_BUDGET": "刷新金额上限",
		"AUTOTATO_REROLL_BUDGET_DESC": "单次刷新价格的上限, 超过此值不自动刷新 (0=不限)",
		"AUTOTATO_SECTION_BEHAVIOR": "行为设置",
		"AUTOTATO_AUTO_START_WAVE": "自动开始下一关",
		"AUTOTATO_AUTO_START_WAVE_DESC": "商店无法刷新时自动进入下一波敌袭",
		"AUTOTATO_KEEP_RUNNING": "失焦保持运行",
		"AUTOTATO_KEEP_RUNNING_DESC": "窗口失去焦点时游戏继续运行",
		"AUTOTATO_TURBO_MODE": "急速模式",
		"AUTOTATO_TURBO_MODE_DESC": "开启: 跳过界面停留瞬间推进; 关闭: 每次推进前停留 0.3s 让界面可见",
		"AUTOTATO_MIN_WEAPON_TIER": "最低武器级别:",
		"AUTOTATO_WEAPON_DATA_UNAVAILABLE": "武器数据不可用",
		"AUTOTATO_WEAPON_CATEGORY_DATA_UNAVAILABLE": "武器类别数据不可用",
		"AUTOTATO_WEAPON_NO_CATEGORY": "此武器不属于任何类别",
		"AUTOTATO_WEAPON_SELF_RULE": "武器自身规则",
		"AUTOTATO_CATEGORY_RULE": "类别规则",
		"AUTOTATO_THRESHOLD_UNLIMITED": "不限",
		"AUTOTATO_THRESHOLD_UPPER": "上限",
		"AUTOTATO_THRESHOLD_LOWER": "下限",
		"AUTOTATO_PRIMARY_STATS": "主要属性",
		"AUTOTATO_SECONDARY_STATS": "次要属性",
		"AUTOTATO_UPGRADE_STRATEGY": "升级策略",
		"AUTOTATO_RESPECT_THRESHOLDS": "受阈值影响",
		"AUTOTATO_RESPECT_THRESHOLDS_DESC": "当升级选项含有多个可转换的属性时，会同时判断所有已配置的阈值；只有当全部相关属性都触达限制时，该选项才会被过滤。",
		"AUTOTATO_MIN_TIER": "最低等级",
		"AUTOTATO_QUALITY_FIRST": "品质优先",
		"AUTOTATO_QUALITY_FIRST_DESC": "优先选择高等级 (Tier) 的选项",
		"AUTOTATO_FORBID_STATS": "禁止属性",
		"AUTOTATO_FORBID_STATS_DESC": "含这些属性的升级项将被过滤掉",
		"AUTOTATO_IGNORE_FORBID_ON_STUCK": "卡住时忽略禁止列表",
		"AUTOTATO_IGNORE_FORBID_ON_STUCK_DESC": "所有候选都被过滤时, 回退到不过滤的排序结果",
		"AUTOTATO_STAT_PRIORITY": "优先级排序",
		"AUTOTATO_STAT_PRIORITY_DESC": "同等级内, 按此顺序优先选择含对应属性的升级项",
		"AUTOTATO_PRIORITIZED": "已优先",
		"AUTOTATO_NOT_PRIORITIZED": "未优先",
		"AUTOTATO_REMOVE": "移除",
		"AUTOTATO_ADD_TO_PRIORITY": "加入优先",
		"AUTOTATO_ITEM_TYPE_ALL": "类型: 不限",
		"AUTOTATO_ITEM_TYPE_UNIQUE": "类型: 独特",
		"AUTOTATO_ITEM_TYPE_LIMITED": "类型: 限制",
		"AUTOTATO_ITEM_TYPE_OTHER": "类型: 其他",
		"AUTOTATO_SHOP_FILTER_ALL": "商店: 不限",
		"AUTOTATO_CHEST_FILTER_ALL": "箱子: 不限",
		"AUTOTATO_SHOP_RESPECT_THRESHOLDS": "商店受阈值影响",
		"AUTOTATO_CHEST_RESPECT_THRESHOLDS": "箱子受阈值影响",
		"AUTOTATO_ITEM_DATA_UNAVAILABLE": "物品数据不可用",
		"AUTOTATO_SHOP_BEHAVIOR": "商店行为",
		"AUTOTATO_CHEST_BEHAVIOR": "箱子行为",
		"AUTOTATO_WEAPON_RULE": "武器规则",
		"AUTOTATO_ITEM_RULE": "物品规则",
		"AUTOTATO_NO_CATEGORY": "无类别",
		"AUTOTATO_TAB_GENERAL": "通用",
		"AUTOTATO_TAB_UPGRADE": "升级",
		"AUTOTATO_TAB_ITEMS": "物品",
		"AUTOTATO_TAB_WEAPONS": "武器",
		"AUTOTATO_TAB_THRESHOLDS": "阈值",
		"AUTOTATO_CORNER_SHOP": "商:",
		"AUTOTATO_CORNER_CHEST": "箱:",
		"AUTOTATO_PANEL_TITLE": "AutoTato 配置",
		"AUTOTATO_AUTOMATION": "AutoTato",
		"AUTOTATO_TIER_COMMON": "普通",
		"AUTOTATO_TIER_RARE": "精良",
		"AUTOTATO_TIER_EPIC": "史诗",
		"AUTOTATO_TIER_LEGENDARY": "传说",
		"AUTOTATO_SHOP_FILTER_FMT": "商店: %s",
		"AUTOTATO_CHEST_FILTER_FMT": "箱子: %s",
		"AUTOTATO_UNKNOWN": "未知",
	}
