extends "res://ui/menus/ingame/upgrades_ui.gd"

# ============================================================================
# AutoTato — upgrades_ui Script Extension (P3.5)
# ----------------------------------------------------------------------------
# ModLoader v6 Script Extension, hook vanilla 升级 4 选 1 面板.
#
# 仅 hook 1 个方法: _show_next_player_options() -> bool
#   这是 vanilla 升级状态机的"准备好下一组选项"内部入口. 每次 wave 升级面板
#   弹出或玩家选完一个升级后, vanilla 都会调它准备下一组 4 个 upgrade_ui.
#   父类填好 4 个 upgrade_ui.upgrade_data + _player_is_choosing[i] = true
#   并返回 true 后, 跑 AutoTato 决策.
#
# 为什么 hook _show_next_player_options 而不是 show_options:
#   show_options 是升级流程外部入口, 一次 wave 只调一次. 如果玩家一波内升级
#   两次, vanilla 内部用 _on_choose_button_pressed → _show_next_player_options
#   状态机循环切换, show_options 不会再被调到, hook 看不到第二次升级 (P3.5 v1 bug).
#   _show_next_player_options 是真正的"准备 UI"入口, wave 内每次升级都触发.
#
# 与 P3 商店 hook 风格一致 (extensions/ui/menus/shop/base_shop.gd):
#   - AT_Bridge.get_global() 取桥, has_method 防御
#   - 不持 Bridge 引用为成员变量 (避免循环引用)
#   - 不主动 disconnect 任何信号
#   - 不用 Timer
#   - 全程 Object.get() 读 vanilla 私有字段, 防字段缺失崩
#
# 关键: vanilla 多人 coop 同帧并行展示, `_player_is_choosing: [bool; 4]`
#   标记哪些 player 当前正在选项. 遍历 0..get_player_count(), 跳过 false 的.
#
# 守卫:
#   - 跳过 crate 物品场景: pc._items_container.visible == true (P3.6 处理)
#   - 跳过 vanilla 按钮锁: pc._button_pressed (vanilla 防双击)
#   - 决策器返回 -1 (NO_PICK) 表示玩家手动, 不点击
#   - 重要: Bridge.decide_upgrade 默认 upgrade_automation_enabled=false,
#     未显式启用前永远返回 NO_PICK, hook 不会自动点击 (避免 wave 内连点)
# ============================================================================

const LOG_NAME := "fengyifan-AutoTato:UpgradeHook"


# hook _show_next_player_options: vanilla 升级状态机内部入口.
# 每次 vanilla 准备好下一组 upgrade_ui 时调用 (进面板 / 玩家选完后).
# 签名: -> bool (是否有玩家正在选).
func _show_next_player_options() -> bool:
	var ret = ._show_next_player_options()
	# 仅当 vanilla 报告有玩家正在选时, 才跑决策. ret == false 表示无玩家在选,
	# 此时 _player_is_choosing 全 false, 决策也无意义.
	if ret:
		_autotato_process_upgrades()
	return ret


# ----------------------------------------------------------------------------
# AutoTato 流程 (前缀 _autotato_ 防止与 vanilla 撞名)
# ----------------------------------------------------------------------------

func _autotato_process_upgrades() -> void:
	var bridge = AT_Bridge.get_global()
	if bridge == null:
		return
	if not bridge.has_method("decide_upgrade"):
		return

	# 遍历所有玩家. vanilla 多人 coop 同帧并行展示, 用 _player_is_choosing 标记.
	var player_count: int = RunData.get_player_count()
	for player_index in player_count:
		# 读 vanilla 私有数组, 用 Object.get 防御
		var choosing_arr = self.get("_player_is_choosing")
		if choosing_arr == null:
			return
		if player_index >= choosing_arr.size() or not bool(choosing_arr[player_index]):
			continue

		var pc = _get_player_container(player_index)
		if pc == null:
			continue

		# 跳过 crate 物品场景 (UpgradesUIPlayerContainer 复用给 crate, P3.6 才处理)
		var items_container = pc.get("_items_container")
		if items_container != null and items_container.visible:
			_log("跳过 crate 物品场景 player=%d (P3.6 才处理)" % player_index)
			continue

		# 取 4 个 visible 的 upgrade option
		var ui_list: Array = pc._get_upgrade_uis()
		var options: Array = []
		var visible_uis: Array = []
		for ui in ui_list:
			if ui.visible and ui.upgrade_data != null:
				options.append(ui.upgrade_data)
				visible_uis.append(ui)
		if options.empty():
			continue

		# 决策
		var idx: int = int(bridge.decide_upgrade(options, player_index))
		_log("升级决策完成 player=%d 候选=%d 选中 idx=%d" % [player_index, options.size(), idx])
		if idx < 0 or idx >= visible_uis.size():
			continue  # -1 (NO_PICK) 或越界, 玩家手动

		# 防 vanilla 按钮锁 (上次点击未解锁, 跳过本次)
		var button_pressed = pc.get("_button_pressed")
		if button_pressed != null and bool(button_pressed):
			_log("按钮被锁 player=%d, 跳过本次自动选择" % player_index)
			continue

		# emit click signal, 走 vanilla 完整链路:
		#   UpgradeUI.button.pressed → _on_ChooseButton_pressed → emit choose_button_pressed
		#   → pc._on_choose_button_pressed → emit pc.choose_button_pressed
		#   → UpgradesUI._on_choose_button_pressed → apply upgrade + _show_next_player_options
		#     (本 hook 会再次被触发, 处理下一组升级)
		var target_ui = visible_uis[idx]
		target_ui.button.emit_signal("pressed")


func _log(msg: String) -> void:
	if typeof(ModLoaderLog) != TYPE_NIL:
		ModLoaderLog.info(msg, LOG_NAME)
