extends "res://ui/menus/ingame/upgrades_ui.gd"

# ============================================================================
# AutoTato - upgrades_ui Script Extension
# ----------------------------------------------------------------------------
# 决策链路:
#   _show_next_player_options -> hook -> 箱子决策分发
#     -> 遍历玩家 -> items_container 可见 -> 读 chest_action -> 执行 take/reject
#
# 升级 AutoTato 按钮 (ATAutoUpgradeButton):
#   _show_next_player_options 创建按钮 (装饰) -> 玩家 pressed 或 E 键 (ui_select)
#   -> _at_upgrade_auto_pressed -> _UpgradeAutomation.run_upgrade_decision(force=true)
#   -> reroll 循环 + fallback (详见 shop/upgrade_automation.gd)
#
# 焦点:
#   upgrades_ui_player_container 扩展接管了 focus(), 定向到 AutoTato 按钮.
# ============================================================================

const _Logger = preload("res://mods-unpacked/fengyifan-AutoTato/utils/logger.gd")
const _Config = preload("res://mods-unpacked/fengyifan-AutoTato/config/config.gd")
const _UpgradeAutomation = preload("res://mods-unpacked/fengyifan-AutoTato/shop/upgrade_automation.gd")
const _UpgradeData = preload("res://mods-unpacked/fengyifan-AutoTato/shop/upgrade_data_reader.gd")
const _LOG_NAME := "UpgradesUI"

# 急速模式关闭时, 阶段推进前的延迟 (秒), 让界面渲染可见.
const _AT_ADVANCE_DELAY := 0.3

var _at_pending_advance: Timer = null


# ----------------------------------------------------------------------------
# 总分发
# ----------------------------------------------------------------------------

func _show_next_player_options() -> bool:
	# 先确保 AutoTato 按钮存在, 再调 vanilla.
	var player_count = RunData.get_player_count()
	for player_index in player_count:
		var pc = _get_player_container(player_index)
		if pc:
			_at_ensure_upgrade_auto_button(pc, player_index)

	var ret = ._show_next_player_options()
	if ret:
		_autotato_process_crate_decisions()
		_autotato_process_upgrade_decisions()
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


# 升级选择场景自动触发入口 (对齐箱子场景的 _autotato_process_crate_decisions).
# 自动化开关关闭时不触发, 留给手动按钮 (force=true).
# 自动化开关开启时, 对处于"升级选择"状态的玩家触发一次 force=false 决策会话.
func _autotato_process_upgrade_decisions() -> void:
	var config = _Config.get_instance()
	if config == null:
		return
	if not config.is_upgrade_automation_enabled():
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
		# 升级选择场景: items_container 不可见, upgrades_container 可见
		var items_container = pc.get("_items_container")
		if items_container != null and items_container.visible:
			continue  # 箱子场景, 已由 _autotato_process_crate_decisions 处理
		var upgrades_container = pc.get("_upgrades_container")
		if upgrades_container == null or not upgrades_container.visible:
			continue
		_Logger.info("升级自动化触发 玩家=%d" % player_index, _LOG_NAME)
		_UpgradeAutomation.run_upgrade_decision(self, player_index, false)


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
# 升级界面 AutoTato 按钮
# - 焦点链用: ChooseButton -> RerollButton -> ATAutoUpgradeButton
# - 按钮文字/字体/宽度与 RerollButton 一致 (宽度 deferred 同步 RerollButton 实际宽度)
# - E 键 (ui_select) 图标: 样式 100% 模仿 RerollButton 的 AdditionalIcon
#   (垂直居中, margin_left=14, 51px 宽), 与箱子卡片 AutoTato 按钮同键
# - pressed / E 键 -> upgrade_automation 完整决策会话 (reroll 循环 + fallback)
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
	# 宽度跟随 RerollButton (ButtonWithIcon 按内容+MARGIN 自适应, 非 500 固定).
	# 先给一个 500 初始值, deferred 读取 RerollButton 真实宽度后覆盖.
	btn.rect_min_size = Vector2(500, 0)
	btn.set_meta("player_index", player_index)
	btn.connect("pressed", self, "_at_upgrade_auto_pressed", [btn])
	var reroll_font = reroll_btn.get_font("font")
	if reroll_font:
		btn.add_font_override("font", reroll_font)
	# E 键 (ui_select, 商店锁定键) 图标 - 与 RerollButton 的 AdditionalIcon 样式完全一致.
	# 箱子卡片 AutoTato 按钮也用 ui_select, 跨场景快捷键统一.
	var icon_script = load("res://ui/hud/ui_input_icon.gd")
	if icon_script:
		var aicon := TextureRect.new()
		aicon.set_script(icon_script)
		aicon.input_string = "ui_select"
		aicon.player_index = 0
		aicon.anchor_top = 0.5
		aicon.anchor_bottom = 0.5
		aicon.margin_left = 14.0
		aicon.margin_top = -25.5
		aicon.margin_right = 65.0
		aicon.margin_bottom = 25.5
		aicon.rect_min_size = Vector2(51, 0)
		aicon.expand = true
		aicon.mouse_filter = MOUSE_FILTER_IGNORE
		btn.add_child(aicon)
	wrapper.add_child(btn)

	var spacer_right := Control.new()
	spacer_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.add_child(spacer_right)

	upgrades_container.add_child(wrapper)
	upgrades_container.move_child(wrapper, row_idx + 1)

	# 手柄焦点邻居
	reroll_btn.focus_neighbour_bottom = reroll_btn.get_path_to(btn)
	btn.focus_neighbour_top = btn.get_path_to(reroll_btn)

	# 宽度同步: RerollButton 的 ButtonWithIcon 按内容自适应宽度 (内容+MARGIN),
	# 非固定 500. deferred 到当前帧布局完成后, 读取 RerollButton 真实宽度覆盖.
	call_deferred("_at_sync_upgrade_button_width", btn, reroll_btn)


# 同步 AutoTato 按钮宽度到 RerollButton 实际宽度.
# RerollButton (ButtonWithIcon) 每帧按内容重算 rect_size.x, 这里取其当前值.
func _at_sync_upgrade_button_width(btn: Button, reroll_btn) -> void:
	if btn == null or not is_instance_valid(btn):
		return
	if reroll_btn == null or not is_instance_valid(reroll_btn):
		return
	var w: float = reroll_btn.rect_size.x
	if w > 1.0:
		btn.rect_min_size.x = w


func _at_upgrade_auto_pressed(btn: Button) -> void:
	var player_index: int = int(btn.get_meta("player_index"))
	var pc = _get_player_container(player_index)
	if pc == null or not is_instance_valid(pc):
		return
	if pc.has_method("_autotato_clear_button_guard"):
		pc._autotato_clear_button_guard()
	_Logger.info("升级 AutoTato 触发 玩家=%d" % player_index, _LOG_NAME)
	# force=true: 绕过升级自动化开关, 执行完整决策会话 (reroll 循环 + fallback).
	# 开关关闭时由 upgrade_automation 在刷新后停止循环, 实现"每按一次推进一轮".
	_UpgradeAutomation.run_upgrade_decision(self, player_index, true)


# ----------------------------------------------------------------------------
# E 键 (ui_select) 交互 - 仅升级选择场景拦截, 箱子场景不拦截.
# 箱子场景的 ui_select 由 upgrades_ui_player_container 扩展处理 (箱子 AutoTato 按钮).
# ----------------------------------------------------------------------------
func _input(event: InputEvent) -> void:
	# 遍历玩家, 找到正处于"升级选择"状态 (upgrades_container 可见, items_container 不可见)
	# 的 player_container, 拦截 ui_select -> 触发其 AutoTato 按钮.
	var player_count = RunData.get_player_count()
	for pi in player_count:
		var pc = _get_player_container(pi)
		if pc == null:
			continue
		# 箱子场景: items_container 可见 -> 跳过 (箱子 E 键由 player_container 扩展处理)
		var items_container = pc.get("_items_container")
		if items_container != null and items_container.visible:
			continue
		# 升级选择场景: upgrades_container 可见才拦截
		var upgrades_container = pc.get("_upgrades_container")
		if upgrades_container == null or not upgrades_container.visible:
			continue
		if event.is_action_pressed("ui_select"):
			var btn = pc.find_node("ATAutoUpgradeButton", true, false)
			if btn and btn.visible:
				_at_upgrade_auto_pressed(btn)
				get_tree().set_input_as_handled()
				return


# ============================================================================
# Bridge executor 方法 (upgrade_automation.run_upgrade_decision 回调)
# ============================================================================

# 读当前可见升级候选.
func at_get_upgrade_candidates(player_index: int) -> Dictionary:
	var pc = _get_player_container(player_index)
	return _UpgradeData.get_upgrade_candidates(pc)


# 执行选择 idx (急速立即 / 非急速延迟, 让 UI 渲染可见).
func at_choose_upgrade(idx: int, player_index: int) -> void:
	var pc = _get_player_container(player_index)
	if pc == null or not is_instance_valid(pc):
		_Logger.warning("at_choose_upgrade: pc 无效 玩家=%d" % player_index, _LOG_NAME)
		return
	var candidates: Dictionary = _UpgradeData.get_upgrade_candidates(pc)
	var visible_uis: Array = candidates.get("visible_uis", [])
	if idx >= visible_uis.size():
		_Logger.warning("at_choose_upgrade: idx=%d 越界 (可见候选 %d 个) 玩家=%d" % [idx, visible_uis.size(), player_index], _LOG_NAME)
		return
	if pc.has_method("_autotato_clear_button_guard"):
		pc._autotato_clear_button_guard()
	var cfg = _Config.get_instance()
	if cfg != null and cfg.is_turbo_mode():
		visible_uis[idx].call_deferred("_on_ChooseButton_pressed")
		_Logger.info("已调度升级选择 玩家=%d idx=%d (急速)" % [player_index, idx], _LOG_NAME)
	else:
		_at_schedule_advance(_AT_ADVANCE_DELAY, "_at_deferred_choose", [player_index, idx])
		_Logger.info("已调度升级选择 玩家=%d idx=%d (延迟 %.1fs)" % [player_index, idx, _AT_ADVANCE_DELAY], _LOG_NAME)


# 触发升级刷新, 返回是否成功.
func at_reroll_upgrade(player_index: int) -> bool:
	var pc = _get_player_container(player_index)
	if pc == null or not is_instance_valid(pc):
		return false
	if pc.has_method("_autotato_clear_button_guard"):
		pc._autotato_clear_button_guard()
	var reroll_btn = pc.get("_reroll_button")
	if reroll_btn == null or not is_instance_valid(reroll_btn):
		return false
	reroll_btn.emit_signal("pressed")
	return true


# 读升级刷新价格.
func at_get_upgrade_reroll_price(player_index: int) -> int:
	var pc = _get_player_container(player_index)
	return _UpgradeData.get_reroll_price(pc)


# 非急速模式动作后等待 (与商店 base_shop.at_wait_before_next_decision 对称).
func at_wait_before_next_decision() -> void:
	var cfg = _Config.get_instance()
	if cfg == null or cfg.is_turbo_mode():
		return
	var delay: float = cfg.get_general()["decision_step_delay"]
	if delay > 0.0:
		_at_schedule_advance(delay, "_at_noop", [])


# fallback: ignore_forbid_on_stuck=true 时选品质最优 (tier 最高).
# 返回是否触发了兜底选择.
func at_fallback_upgrade(player_index: int) -> bool:
	var cfg = _Config.get_instance()
	if cfg == null:
		return false
	var upg: Dictionary = cfg.get_upgrade_config()
	if not bool(upg.get("ignore_forbid_on_stuck", false)):
		return false
	var pc = _get_player_container(player_index)
	if pc == null or not is_instance_valid(pc):
		return false
	if not pc.has_method("_get_upgrade_uis"):
		return false

	var best_ui = null
	var best_tier: int = -1
	var visible_summary: Array = []  # 日志: 所有可见候选的 idx+tier
	for ui in pc._get_upgrade_uis():
		if is_instance_valid(ui) and bool(ui.visible) and ui.get("upgrade_data") != null:
			var t: int = int(ui.upgrade_data.tier)
			visible_summary.append("#%d(%s)" % [ui.get_index(), _tier_cn(t)])
			if t > best_tier:
				best_tier = t
				best_ui = ui
	if best_ui == null:
		_Logger.info("fallback 玩家=%d: 无可见候选, 不选" % player_index, _LOG_NAME)
		return false

	_Logger.info("fallback 玩家=%d: 可见候选=[%s] -> 选 #%d 等级=%s (ignore_forbid_on_stuck)" % [
		player_index, ", ".join(visible_summary), best_ui.get_index(), _tier_cn(best_tier)
	], _LOG_NAME)
	if pc.has_method("_autotato_clear_button_guard"):
		pc._autotato_clear_button_guard()
	if cfg.is_turbo_mode():
		best_ui.call_deferred("_on_ChooseButton_pressed")
		_Logger.info("fallback 玩家=%d: 已调度选择 (急速)" % player_index, _LOG_NAME)
	else:
		_at_schedule_advance(_AT_ADVANCE_DELAY, "_at_deferred_fallback", [player_index])
		_Logger.info("fallback 玩家=%d: 已调度选择 (延迟 %.1fs)" % [player_index, _AT_ADVANCE_DELAY], _LOG_NAME)
	return true


func _at_noop() -> void:
	_at_pending_advance = null


# tier -> 中文名 (仅日志展示用)
static func _tier_cn(t: int) -> String:
	match t:
		0: return "普通"
		1: return "精良"
		2: return "稀有"
		3: return "传说"
		_: return "tier%d" % t


# 延迟选升级 (急速关). 重新查找 pc + 选项, 校验 idx 范围 + is_instance_valid.
func _at_deferred_choose(player_index: int, idx: int) -> void:
	_at_pending_advance = null
	if not is_inside_tree():
		return
	var pc = _get_player_container(player_index)
	if pc == null or not is_instance_valid(pc):
		return
	var candidates: Dictionary = _UpgradeData.get_upgrade_candidates(pc)
	var visible_uis: Array = candidates.get("visible_uis", [])
	if idx >= visible_uis.size():
		return
	var target = visible_uis[idx]
	if not is_instance_valid(target):
		return
	if pc.has_method("_autotato_clear_button_guard"):
		pc._autotato_clear_button_guard()
	target.call_deferred("_on_ChooseButton_pressed")


# 延迟 fallback 选升级 (急速关). 重新查找 best_ui (品质最优) + is_instance_valid.
func _at_deferred_fallback(player_index: int) -> void:
	_at_pending_advance = null
	if not is_inside_tree():
		return
	var pc = _get_player_container(player_index)
	if pc == null or not is_instance_valid(pc):
		return
	if not pc.has_method("_get_upgrade_uis"):
		return
	var best_ui = null
	var best_tier: int = -1
	for ui in pc._get_upgrade_uis():
		if is_instance_valid(ui) and bool(ui.visible) and ui.get("upgrade_data") != null:
			var t: int = int(ui.upgrade_data.tier)
			if t > best_tier:
				best_tier = t
				best_ui = ui
	if best_ui != null and is_instance_valid(best_ui):
		if pc.has_method("_autotato_clear_button_guard"):
			pc._autotato_clear_button_guard()
		best_ui.call_deferred("_on_ChooseButton_pressed")
