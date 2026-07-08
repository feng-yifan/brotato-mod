extends "res://ui/menus/ingame/upgrades_ui.gd"

# ============================================================================
# AutoTato — upgrades_ui Script Extension
# ----------------------------------------------------------------------------
# 决策链路:
#   _show_next_player_options → hook → 箱子决策分发
#     → 遍历玩家 → items_container 可见 → 读 chest_action → 执行 take/reject
#
# 焦点:
#   upgrades_ui_player_container 扩展接管了 focus(), 定向到 AutoTato 按钮.
#   本扩展仅在需要时创建升级面板的 ATAutoUpgradeButton (装饰占位).
# ============================================================================

const _Logger = preload("res://mods-unpacked/fengyifan-AutoTato/utils/logger.gd")
const _Config = preload("res://mods-unpacked/fengyifan-AutoTato/config/config.gd")
const _LOG_NAME := "UpgradesUI"

# 急速模式关闭时, 阶段推进前的延迟 (秒), 让界面渲染可见.
const _AT_ADVANCE_DELAY := 0.3

var _at_pending_advance: Timer = null


# ----------------------------------------------------------------------------
# 总分发
# ----------------------------------------------------------------------------

func _show_next_player_options() -> bool:
	# 先确保 AutoTato 按钮存在 (装饰占位)
	var player_count = RunData.get_player_count()
	for player_index in player_count:
		var pc = _get_player_container(player_index)
		if pc:
			_at_ensure_upgrade_auto_button(pc, player_index)

	var ret = ._show_next_player_options()
	if ret:
		_autotato_process_crate_decisions()
	return ret


func _autotato_process_crate_decisions() -> void:
	var config = _Config.get_instance()
	if config == null:
		return

	var auto_enabled: bool = config.is_shop_automation_enabled()
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

		var items_container = pc.get("_items_container")
		if items_container != null and items_container.visible:
			if auto_enabled:
				_autotato_process_crate_item(config, pc, player_index)


# ----------------------------------------------------------------------------
# 箱子物品决策 (简化: 直接读 chest_action 配置)
# ----------------------------------------------------------------------------

func _autotato_process_crate_item(config, pc, player_index: int) -> void:
	var item_data = pc.get("_item_data")
	if item_data == null:
		_Logger.info("箱子场景但 _item_data == null, 跳过 玩家=%d" % player_index, _LOG_NAME)
		return

	var rule = config.get_item_rule(item_data.my_id)
	var chest_action: String = String(rule.get("chest_action", "manual"))
	_Logger.info("箱子自动决策 玩家=%d 物品=%s chest_action=%s" % [player_index, item_data.my_id, chest_action], _LOG_NAME)

	if chest_action == "manual":
		return

	# 清除 vanilla 按钮防抖
	if pc.has_method("_autotato_clear_button_guard"):
		pc._autotato_clear_button_guard()

	var is_turbo: bool = config.is_turbo_mode()

	match chest_action:
		"take":
			var take_btn = pc.get("_take_button")
			if take_btn != null:
				if is_turbo:
					take_btn.call_deferred("emit_signal", "pressed")
					_Logger.info("已调度箱子拿取 玩家=%d (急速)" % player_index, _LOG_NAME)
				else:
					_at_schedule_advance(_AT_ADVANCE_DELAY, "_at_deferred_take", [player_index])
					_Logger.info("已调度箱子拿取 玩家=%d (延迟 %.1fs)" % [player_index, _AT_ADVANCE_DELAY], _LOG_NAME)
		"reject":
			var discard_btn = pc.get("_discard_button")
			if discard_btn != null:
				if is_turbo:
					discard_btn.call_deferred("emit_signal", "pressed")
					_Logger.info("已调度箱子丢弃 玩家=%d (急速)" % player_index, _LOG_NAME)
				else:
					_at_schedule_advance(_AT_ADVANCE_DELAY, "_at_deferred_discard", [player_index])
					_Logger.info("已调度箱子丢弃 玩家=%d (延迟 %.1fs)" % [player_index, _AT_ADVANCE_DELAY], _LOG_NAME)
		"cursed_only":
			var is_cursed: bool = (item_data.get("cursed") != null and item_data.get("cursed"))
			if is_cursed:
				var take_btn = pc.get("_take_button")
				if take_btn != null:
					if is_turbo:
						take_btn.call_deferred("emit_signal", "pressed")
					else:
						_at_schedule_advance(_AT_ADVANCE_DELAY, "_at_deferred_take", [player_index])
			else:
				var discard_btn = pc.get("_discard_button")
				if discard_btn != null:
					if is_turbo:
						discard_btn.call_deferred("emit_signal", "pressed")
					else:
						_at_schedule_advance(_AT_ADVANCE_DELAY, "_at_deferred_discard", [player_index])


# ----------------------------------------------------------------------------
# 急速模式关闭时的延迟推进
# ----------------------------------------------------------------------------

func _at_schedule_advance(delay: float, method: String, args: Array) -> void:
	if _at_pending_advance != null and is_instance_valid(_at_pending_advance):
		_at_pending_advance.stop()
		_at_pending_advance.queue_free()
	var t = Timer.new()
	t.one_shot = true
	t.wait_time = delay
	t.connect("timeout", self, method, args)
	add_child(t)
	t.start()
	_at_pending_advance = t


func _at_deferred_take(player_index: int) -> void:
	_at_pending_advance = null
	if not is_inside_tree():
		return
	var pc = _get_player_container(player_index)
	if pc == null or not is_instance_valid(pc):
		return
	var take_btn = pc.get("_take_button")
	if take_btn == null or not is_instance_valid(take_btn):
		return
	take_btn.call_deferred("emit_signal", "pressed")


func _at_deferred_discard(player_index: int) -> void:
	_at_pending_advance = null
	if not is_inside_tree():
		return
	var pc = _get_player_container(player_index)
	if pc == null or not is_instance_valid(pc):
		return
	var discard_btn = pc.get("_discard_button")
	if discard_btn == null or not is_instance_valid(discard_btn):
		return
	discard_btn.call_deferred("emit_signal", "pressed")


# ----------------------------------------------------------------------------
# 升级界面 AutoTato 按钮 (装饰占位)
# - 焦点链用: ChooseButton → RerollButton → ATAutoUpgradeButton
# - pressed 时仅记录日志, 升级决策后续实现
# ----------------------------------------------------------------------------

func _at_ensure_upgrade_auto_button(pc, player_index: int) -> void:
	if pc.find_node("ATAutoUpgradeButton", true, false) != null:
		return
	var reroll_btn = pc.get("_reroll_button")
	if reroll_btn == null:
		return

	var reroll_row = reroll_btn.get_parent()
	if reroll_row == null:
		return
	var upgrades_container = reroll_row.get_parent()
	if upgrades_container == null:
		return
	var row_idx: int = reroll_row.get_index()

	var wrapper := HBoxContainer.new()
	var spacer_left := Control.new()
	spacer_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.add_child(spacer_left)

	var btn := Button.new()
	btn.name = "ATAutoUpgradeButton"
	btn.text = tr("AUTOTATO_AUTOMATION")
	btn.focus_mode = Control.FOCUS_ALL
	btn.align = Button.ALIGN_CENTER
	btn.rect_min_size = Vector2(500, 0)
	btn.set_meta("player_index", player_index)
	btn.connect("pressed", self, "_at_upgrade_auto_pressed", [btn])
	var reroll_font = reroll_btn.get_font("font")
	if reroll_font:
		btn.add_font_override("font", reroll_font)
	wrapper.add_child(btn)

	var spacer_right := Control.new()
	spacer_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.add_child(spacer_right)

	upgrades_container.add_child(wrapper)
	upgrades_container.move_child(wrapper, row_idx + 1)

	# 手柄焦点邻居
	reroll_btn.focus_neighbour_bottom = reroll_btn.get_path_to(btn)
	btn.focus_neighbour_top = btn.get_path_to(reroll_btn)


func _at_upgrade_auto_pressed(btn: Button) -> void:
	var player_index: int = int(btn.get_meta("player_index"))
	var pc = _get_player_container(player_index)
	if pc == null or not is_instance_valid(pc):
		return
	if pc.has_method("_autotato_clear_button_guard"):
		pc._autotato_clear_button_guard()
	_Logger.info("升级 AutoTato 触发 玩家=%d (占位, 决策待实现)" % player_index, _LOG_NAME)
