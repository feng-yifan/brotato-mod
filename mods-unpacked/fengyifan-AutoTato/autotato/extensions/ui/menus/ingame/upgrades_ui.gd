extends "res://ui/menus/ingame/upgrades_ui.gd"

# ============================================================================
# AutoTato — upgrades_ui Script Extension (P3.5 + P3.6)
# ----------------------------------------------------------------------------
# ModLoader v6 Script Extension. 同一 vanilla 路径只能 install 一次, P3.5 和
# P3.6 必须在同一文件内分支处理两种场景.
#
# 仅 hook 1 个方法: _show_next_player_options() -> bool
#   这是 vanilla 升级状态机的"准备下一组选项"内部入口. 升级面板弹出 / 玩家
#   选完后 vanilla 都会调它. _show_options 是外部入口, 一波内多次升级时只调
#   一次, hook 不到 (P3.5 v1 bug).
#
# 内部按 pc._items_container.visible 分支:
#   - true  → 箱子物品场景: _autotato_process_crate_item (P3.6, decide_chest_item)
#   - false → 升级 4 选 1 场景: _autotato_process_single_upgrade (P3.5, decide_upgrade)
#
# 与 P3 商店 hook 风格一致:
#   - AT_Bridge.get_global() 取桥, has_method 防御
#   - 不持 Bridge 引用为成员变量 (避免循环引用)
#   - 不主动 disconnect 任何信号
#   - 不用 Timer
#   - 全程 Object.get() 读 vanilla 私有字段, 防字段缺失崩
#
# 多人 coop: vanilla `_player_is_choosing: [bool; 4]` 标记当前正在选项的玩家.
# 遍历 0..get_player_count(), 跳过 false 的.
#
# 守卫:
#   - pc._button_pressed (vanilla 防双击锁) 守卫两个分支
#   - 决策器返 manual / locked / 未知 / NO_PICK → 不动作, 等玩家手动
#   - 箱子不支持 lock, locked 状态对 chest 等同 manual
# ============================================================================

const LOG_NAME := "fengyifan-AutoTato:UpgradeHook"


# hook _show_next_player_options: vanilla 升级状态机内部入口.
# 每次 vanilla 准备好下一组 upgrade_ui 时调用 (进面板 / 玩家选完后).
# 签名: -> bool (是否有玩家正在选).
func _show_next_player_options() -> bool:
	var ret = ._show_next_player_options()
	if ret:
		_autotato_process_upgrades()
	return ret


# ----------------------------------------------------------------------------
# AutoTato 流程 (前缀 _autotato_ 防止与 vanilla 撞名)
# ----------------------------------------------------------------------------

# 总分发: 遍历所有玩家, 按 player_container 场景分发到对应处理方法.
func _autotato_process_upgrades() -> void:
	var bridge = AT_Bridge.get_global()
	if bridge == null:
		return

	var player_count: int = RunData.get_player_count()
	for player_index in player_count:
		var choosing_arr = self.get("_player_is_choosing")
		if choosing_arr == null:
			return
		if player_index >= choosing_arr.size() or not bool(choosing_arr[player_index]):
			continue

		var pc = _get_player_container(player_index)
		if pc == null:
			continue

		# 区分场景: items_container 可见 → 箱子物品; 否则 → 升级 4 选 1
		var items_container = pc.get("_items_container")
		if items_container != null and items_container.visible:
			_autotato_process_crate_item(bridge, pc, player_index)
		else:
			_autotato_process_single_upgrade(bridge, pc, player_index)


# 升级 4 选 1 决策 (P3.5).
# vanilla 路径: show_upgrades_for_level → 4 个 UpgradeUI 显示 → button.pressed
func _autotato_process_single_upgrade(bridge, pc, player_index: int) -> void:
	if not bridge.has_method("decide_upgrade"):
		return

	# 取 4 个 visible 的 upgrade option
	var ui_list: Array = pc._get_upgrade_uis()
	var options: Array = []
	var visible_uis: Array = []
	for ui in ui_list:
		if ui.visible and ui.upgrade_data != null:
			options.append(ui.upgrade_data)
			visible_uis.append(ui)
	if options.empty():
		return

	var idx: int = int(bridge.decide_upgrade(options, player_index))
	_log("升级决策完成 player=%d 候选=%d 选中 idx=%d" % [player_index, options.size(), idx])
	if idx < 0 or idx >= visible_uis.size():
		return  # -1 (NO_PICK) 或越界, 玩家手动

	# 防 vanilla 按钮锁 (上次点击未解锁, 跳过本次)
	var button_pressed = pc.get("_button_pressed")
	if button_pressed != null and bool(button_pressed):
		_log("按钮被锁 player=%d, 跳过本次自动选择" % player_index)
		return

	# emit click signal, 走 vanilla 完整链路:
	#   UpgradeUI.button.pressed → _on_ChooseButton_pressed → emit choose_button_pressed
	#   → pc._on_choose_button_pressed → emit pc.choose_button_pressed
	#   → UpgradesUI._on_choose_button_pressed → apply upgrade + _show_next_player_options
	var target_ui = visible_uis[idx]
	target_ui.button.emit_signal("pressed")


# 箱子物品决策 (P3.6). 单 player_container, 单 item.
# vanilla 路径: show_consumable_data → show_item → _items_container.show()
# 玩家手动: take / discard / ban 三种, mod 只接管 take 和 skip (discard).
func _autotato_process_crate_item(bridge, pc, player_index: int) -> void:
	if not bridge.has_method("decide_chest_item"):
		return

	# 取当前箱子物品
	var item_data = pc.get("_item_data")
	if item_data == null:
		_log("crate 场景但 _item_data == null, 跳过 player=%d" % player_index)
		return

	# 决策
	var result = bridge.decide_chest_item(item_data, player_index)
	if result == null:
		return
	var state: String = String(result.terminal_state)
	var item_id: String = String(result.item_id)
	_log("箱子决策完成 player=%d item=%s 终态=%s reason=%s" % [player_index, item_id, state, result.reason])

	# 防 vanilla 按钮锁
	var button_pressed = pc.get("_button_pressed")
	if button_pressed != null and bool(button_pressed):
		_log("按钮被锁 player=%d, 跳过本次自动操作" % player_index)
		return

	# 派发: purchased→take, skipped→discard, 其余 (manual/locked/未知) 不动作
	# 箱子不支持 lock, locked 状态对 chest 等同 manual, 都让玩家手动处理
	match state:
		"purchased":
			var take_btn = pc.get("_take_button")
			if take_btn != null:
				take_btn.emit_signal("pressed")
		"skipped":
			var discard_btn = pc.get("_discard_button")
			if discard_btn != null:
				discard_btn.emit_signal("pressed")
		_:
			pass


func _log(msg: String) -> void:
	if typeof(ModLoaderLog) != TYPE_NIL:
		ModLoaderLog.info(msg, LOG_NAME)
