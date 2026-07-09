extends Node

const _logger = preload("res://mods-unpacked/fengyifan-AutoTato/utils/logger.gd")
const _config = preload("res://mods-unpacked/fengyifan-AutoTato/config/config.gd")

const _LOG_NAME := "Main"
func _init() -> void:
	install_script_extensions()
	add_translations()
	_config.initialize()

func _ready() -> void:
	_logger.info("AutoTato 已加载", _LOG_NAME)

func install_script_extensions() -> void:
	# 新商店链路: 商店决策 hook 与规则按钮
	ModLoaderMod.install_script_extension(
		"res://mods-unpacked/fengyifan-AutoTato/extensions/base_shop.gd"
	)
	# 接管 reroll 按钮 F/Y (ui_info): 据 AutoTato 状态决定 F 触发决策还是刷新
	ModLoaderMod.install_script_extension(
		"res://mods-unpacked/fengyifan-AutoTato/extensions/reroll_button.gd"
	)
	ModLoaderMod.install_script_extension(
		"res://mods-unpacked/fengyifan-AutoTato/extensions/shop_item.gd"
	)
	# ESC 暂停菜单: 注入 AutoTato 控制面板入口按钮
	ModLoaderMod.install_script_extension(
		"res://mods-unpacked/fengyifan-AutoTato/extensions/ingame_main_menu.gd"
	)
	# 箱子选择页面: 规则弹窗、AutoTato 按钮、箱子自动决策
	ModLoaderMod.install_script_extension(
		"res://mods-unpacked/fengyifan-AutoTato/extensions/upgrades_ui_player_container.gd"
	)
	ModLoaderMod.install_script_extension(
		"res://mods-unpacked/fengyifan-AutoTato/extensions/upgrades_ui.gd"
	)
	# 主菜单: 进游戏时按需弹更新说明弹窗 (changelog)
	ModLoaderMod.install_script_extension(
		"res://mods-unpacked/fengyifan-AutoTato/extensions/title_screen.gd"
	)
	# 升级面板、升级容器等旧扩展暂不迁移,
	# 避免旧运行路径污染新商店链路

func add_translations() -> void:
	ModLoaderMod.add_translation("res://mods-unpacked/fengyifan-AutoTato/translations/autotato.en.translation")
	ModLoaderMod.add_translation("res://mods-unpacked/fengyifan-AutoTato/translations/autotato.zh_Hans_CN.translation")
