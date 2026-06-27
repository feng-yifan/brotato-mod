extends "res://ui/menus/ingame/upgrades_ui.gd"

# ============================================================================
# AutoTato — upgrades_ui Script Extension (P3.5 + P3.6)
# v7: 同步 reroll 循环 + guard 管理
# ----------------------------------------------------------------------------
# 决策链路:
#   _show_next_player_options → hook → decide
#     → 有效 idx: clear guard → call_deferred choose (延迟到下一 idle)
#     → NO_PICK: _autotato_reroll_loop
#         → while 可刷新: clear guard → 同步 emit reroll → decide
#         → 找到: clear guard → call_deferred choose
#         → 不可刷新: _autotato_fallback_pick
#
# 关键修复 (v7):
#   - call_deferred 链被替换为同步 while 循环, 消除无限自循环
#   - player_container 扩展暴露 _autotato_clear_button_guard(), 直接操作
#     _button_pressed / _button_delay_timer, 绕过 vanilla 0.1s 防抖
#   - call_deferred 仅用于最终的 choose 信号延迟 (等 main.gd yield 就位)
# ============================================================================

const LOG_NAME := "fengyifan-AutoTato:UpgradeHook"

# 急速模式关闭时, 阶段推进前的延迟 (秒), 让界面渲染可见.
const _AT_ADVANCE_DELAY := 0.3
# pending 推进 timer (至多一个, 新调度前 stop 旧的去重)
var _at_pending_advance: Timer = null

# 箱子决策终态 → 中文 (仅日志展示用; match 仍用英文 state 字符串匹配)
const _CHEST_STATE_CN := {
	"purchased": "拿取",
	"skipped": "丢弃",
	"locked": "锁定",
	"manual": "手动",
}


func _show_next_player_options() -> bool:
	var ret = ._show_next_player_options()
	if ret:
		_autotato_process_upgrades()
	return ret


# ----------------------------------------------------------------------------
# 总分发
# ----------------------------------------------------------------------------

func _autotato_process_upgrades() -> void:
	var bridge = AT_Bridge.get_global()
	if bridge == null:
		return

	var auto_enabled: bool = bridge.is_upgrade_automation_enabled()
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
				_autotato_process_crate_item(bridge, pc, player_index)
		else:
			_at_ensure_upgrade_auto_button(pc, player_index)
			if auto_enabled:
				_autotato_process_single_upgrade(bridge, pc, player_index)


# ----------------------------------------------------------------------------
# 升级 4 选 1 — 单次决策 + reroll 循环
# ----------------------------------------------------------------------------

func _autotato_process_single_upgrade(bridge, _pc, player_index: int) -> void:
	if not bridge.has_method("run_upgrade_session"):
		return
	bridge.run_upgrade_session(self, player_index)


# --- Bridge executor 方法 (bridge.run_upgrade_session 回调) ---

# 读当前可见升级候选
func _at_get_upgrade_candidates(player_index: int) -> Dictionary:
	var pc = _get_player_container(player_index)
	if pc == null:
		return {"options": [], "visible_uis": []}
	return _get_visible_options(pc)


# 执行选择 (包含 turbo 模式延迟, 复用 _autotato_do_choose)
func _at_choose_upgrade(idx: int, player_index: int) -> void:
	var pc = _get_player_container(player_index)
	if pc == null:
		return
	var options_data = _get_visible_options(pc)
	if idx >= options_data["visible_uis"].size():
		return
	_autotato_do_choose(pc, options_data["visible_uis"], idx, player_index)


# 触发升级刷新, 返回是否成功
func _at_reroll_upgrade(player_index: int) -> bool:
	var pc = _get_player_container(player_index)
	if pc == null:
		return false
	pc._autotato_clear_button_guard()
	var reroll_btn = pc.get("_reroll_button")
	if reroll_btn:
		reroll_btn.emit_signal("pressed")
		return true
	return false


# 读升级刷新价格
func _at_get_upgrade_reroll_price(player_index: int) -> int:
	var pc = _get_player_container(player_index)
	if pc == null:
		return 0
	return int(pc.get("_reroll_price"))


# fallback: ignore_forbid_on_stuck=true 时选品质最优 (复用原 _autotato_fallback_pick 逻辑)
func _at_fallback_upgrade(player_index: int) -> bool:
	var bridge = AT_Bridge.get_global()
	if bridge == null:
		return false
	var upg = bridge.get_upgrade_config()
	if not bool(upg.get("ignore_forbid_on_stuck", false)):
		return false
	var pc = _get_player_container(player_index)
	if pc == null:
		return false
	var uis = pc._get_upgrade_uis()
	var best_tier: int = -1
	var best_ui = null
	for ui in uis:
		if ui.visible and ui.upgrade_data != null:
			var t: int = ui.upgrade_data.tier
			if t > best_tier:
				best_tier = t
				best_ui = ui
	if best_ui:
		pc._autotato_clear_button_guard()
		if bridge.is_turbo_mode():
			best_ui.call_deferred("_on_ChooseButton_pressed")
			_log("fallback player=%d: 忽略禁止, 选 tier=%d (急速)" % [player_index, best_tier])
		else:
			_at_schedule_advance(_AT_ADVANCE_DELAY, "_at_deferred_fallback", [player_index])
			_log("fallback player=%d: 忽略禁止, 选 tier=%d (延迟 %.1fs)" % [player_index, best_tier, _AT_ADVANCE_DELAY])
		return true
	return false


# 统一 choice 入口: clear guard + deferred choose
func _autotato_do_choose(pc, visible_uis: Array, idx: int, player_index: int) -> void:
	pc._autotato_clear_button_guard()
	var bridge = AT_Bridge.get_global()
	if bridge != null and bridge.is_turbo_mode():
		visible_uis[idx].call_deferred("_on_ChooseButton_pressed")
		_log("已调度升级选择 player=%d idx=%d (急速, 下一帧执行)" % [player_index, idx])
	else:
		_at_schedule_advance(_AT_ADVANCE_DELAY, "_at_deferred_choose", [player_index, idx])
		_log("已调度升级选择 player=%d idx=%d (延迟 %.1fs)" % [player_index, idx, _AT_ADVANCE_DELAY])


# 收集可见选项
func _get_visible_options(pc) -> Dictionary:
	var ui_list: Array = pc._get_upgrade_uis()
	var options: Array = []
	var visible_uis: Array = []
	for ui in ui_list:
		if ui.visible and ui.upgrade_data != null:
			options.append(ui.upgrade_data)
			visible_uis.append(ui)
	return {"options": options, "visible_uis": visible_uis}


# ----------------------------------------------------------------------------
# 箱子物品决策 (P3.6)
# ----------------------------------------------------------------------------

func _autotato_process_crate_item(bridge, pc, player_index: int) -> void:
	if not bridge.has_method("decide_chest_item"):
		return

	var item_data = pc.get("_item_data")
	if item_data == null:
		_log("箱子场景但 _item_data == null, 跳过 玩家=%d" % player_index)
		return

	var result = bridge.decide_chest_item(item_data, player_index)
	if result == null:
		return
	var state: String = String(result.terminal_state)
	var item_id: String = String(result.item_id)
	var state_cn: String = _CHEST_STATE_CN.get(state, state)
	_log("箱子决策完成 玩家=%d 物品=%s 终态=%s 原因=%s" % [player_index, item_id, state_cn, result.reason])

	# 清除 vanilla 按钮防抖: 上一个箱子动作 (AutoTato 按钮或手动) 的 0.1s ButtonDelayTimer
	# 可能还在跑, _button_pressed=true 会拦住本次自动执行. 自动模式要绕过这个守卫, 不能检查到就跳过.
	pc._autotato_clear_button_guard()

	match state:
		"purchased":
			var take_btn = pc.get("_take_button")
			if take_btn != null:
				if bridge.is_turbo_mode():
					take_btn.call_deferred("emit_signal", "pressed")
					_log("已调度箱子拿取 玩家=%d (急速, 下一帧执行)" % player_index)
				else:
					_at_schedule_advance(_AT_ADVANCE_DELAY, "_at_deferred_take", [player_index])
					_log("已调度箱子拿取 玩家=%d (延迟 %.1fs)" % [player_index, _AT_ADVANCE_DELAY])
		"skipped":
			var discard_btn = pc.get("_discard_button")
			if discard_btn != null:
				if bridge.is_turbo_mode():
					discard_btn.call_deferred("emit_signal", "pressed")
					_log("已调度箱子丢弃 玩家=%d (急速, 下一帧执行)" % player_index)
				else:
					_at_schedule_advance(_AT_ADVANCE_DELAY, "_at_deferred_discard", [player_index])
					_log("已调度箱子丢弃 玩家=%d (延迟 %.1fs)" % [player_index, _AT_ADVANCE_DELAY])
		_:
			pass


# ----------------------------------------------------------------------------
# 急速模式关闭时的延迟推进 (timer 挂本节点, 场景切走时随节点 free, 不回调死对象)
# ----------------------------------------------------------------------------

# 调度一个延迟推进. delay 秒后调 method(args). 至多一个 pending, 新调度前 stop 旧的.
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


# 延迟选升级 (急速关). 重新查找 pc + 选项, 校验 idx 范围 + is_instance_valid.
func _at_deferred_choose(player_index: int, idx: int) -> void:
	_at_pending_advance = null
	if not is_inside_tree():
		return
	var pc = _get_player_container(player_index)
	if pc == null or not is_instance_valid(pc):
		return
	var options = _get_visible_options(pc)
	if idx >= options["visible_uis"].size():
		return
	var target = options["visible_uis"][idx]
	if not is_instance_valid(target):
		return
	pc._autotato_clear_button_guard()
	target.call_deferred("_on_ChooseButton_pressed")


# 延迟箱子拿取 (急速关). 重新查找 pc + take_button + is_instance_valid.
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


# 延迟箱子丢弃 (急速关). 重新查找 pc + discard_button + is_instance_valid.
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


# 延迟 fallback 选升级 (急速关). 重新查找 best_ui (品质最优) + is_instance_valid.
func _at_deferred_fallback(player_index: int) -> void:
	_at_pending_advance = null
	if not is_inside_tree():
		return
	var pc = _get_player_container(player_index)
	if pc == null or not is_instance_valid(pc):
		return
	var uis = pc._get_upgrade_uis()
	var best_ui = null
	var best_tier: int = -1
	for ui in uis:
		if is_instance_valid(ui) and ui.visible and ui.upgrade_data != null:
			var t: int = ui.upgrade_data.tier
			if t > best_tier:
				best_tier = t
				best_ui = ui
	if best_ui != null and is_instance_valid(best_ui):
		pc._autotato_clear_button_guard()
		best_ui.call_deferred("_on_ChooseButton_pressed")


# ----------------------------------------------------------------------------
# 升级界面 AutoTato 按钮 (升级自动化关闭时, 手动点击触发一次 force 决策)
# 按钮添加在 PC 的 reroll 按钮旁边, 与商店"继续决策"按钮和箱子卡片 AutoTato 按钮同模式.
# ----------------------------------------------------------------------------

func _at_ensure_upgrade_auto_button(pc, player_index: int) -> void:
	if pc.find_node("ATAutoUpgradeButton", true, false) != null:
		return
	var reroll_btn = pc.get("_reroll_button")
	if reroll_btn == null:
		return
	var parent = reroll_btn.get_parent()
	if parent == null:
		return
	var btn := Button.new()
	btn.name = "ATAutoUpgradeButton"
	btn.text = "AutoTato"
	btn.focus_mode = Control.FOCUS_NONE
	btn.set_meta("player_index", player_index)
	btn.connect("pressed", self, "_at_upgrade_auto_pressed", [btn])
	parent.add_child(btn)


func _at_upgrade_auto_pressed(btn: Button) -> void:
	var player_index: int = int(btn.get_meta("player_index"))
	var bridge = AT_Bridge.get_global()
	if bridge == null:
		return
	var pc = _get_player_container(player_index)
	if pc == null or not is_instance_valid(pc):
		return
	pc._autotato_clear_button_guard()
	_log("升级 AutoTato 触发 玩家=%d" % player_index)
	# force=true: 绕过升级自动化开关, 执行完整决策会话 (含 reroll 循环)
	bridge.run_upgrade_session(self, player_index, true)


func _log(msg: String) -> void:
	if typeof(ModLoaderLog) != TYPE_NIL:
		ModLoaderLog.info(msg, LOG_NAME)
