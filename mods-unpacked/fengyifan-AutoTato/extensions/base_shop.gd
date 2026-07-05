extends "res://ui/menus/shop/base_shop.gd"

# ============================================================================
# AutoTato — base_shop Script Extension (新商店链路)
# ----------------------------------------------------------------------------
# 商店 UI adapter。
# 只负责 vanilla Script Extension 接入、按钮 UI、触发入口、
# 购买/锁定/reroll/进下一波等 UI 动作的执行。
#
# 不做: 业务规则判断、预算/阈值/配置读取 — 这些都交给 shop_automation.
# ============================================================================

const _ShopAutomation = preload("res://mods-unpacked/fengyifan-AutoTato/shop/shop_automation.gd")
const _Config = preload("res://mods-unpacked/fengyifan-AutoTato/config/config.gd")
const _Data = preload("res://mods-unpacked/fengyifan-AutoTato/shop/shop_data_reader.gd")
const _DecisionResult = preload("res://mods-unpacked/fengyifan-AutoTato/shop/decision_result.gd")
const _ExecuteResult = preload("res://mods-unpacked/fengyifan-AutoTato/shop/execute_result.gd")
const _Logger = preload("res://mods-unpacked/fengyifan-AutoTato/utils/logger.gd")

const _LOG_NAME := "ShopHook"

# ============================================================================
# 运行时状态
# ============================================================================

# 防止自动 reroll / 处理循环重入
var _at_is_processing := false

# pending 推进 Timer
var _at_pending_advance: Timer = null

# AutoTato 按钮引用
var _at_continue_btn: Button = null

# ============================================================================
# 生命周期
# ============================================================================

# 接管 vanilla ready：添加 AutoTato 按钮，并在进入商店后尝试自动决策
func _ready() -> void:
	._ready()
	_at_add_continue_button()
	call_deferred("_at_trigger_auto_shop_decision_all_players")

# ============================================================================
# AutoTato 按钮
# ============================================================================

# 添加标题栏 AutoTato 手动决策按钮
func _at_add_continue_button() -> void:
	var title = get_node_or_null("%Title")
	if title == null:
		return

	var header_row = title.get_parent()
	if header_row == null:
		return

	# Title 收缩到文字宽度，避免挤压
	title.size_flags_horizontal = Control.SIZE_FILL

	var btn := Button.new()
	btn.name = "AutoTatoContinueBtn"
	btn.text = tr("AUTOTATO_AUTOMATION") + " & " + tr("REROLL")
	btn.focus_mode = Control.FOCUS_ALL
	btn.rect_min_size = Vector2(160, 40)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.connect("pressed", self, "_at_on_continue_pressed")

	var title_idx = title.get_index()
	header_row.add_child(btn)
	header_row.move_child(btn, title_idx + 1)

	_at_continue_btn = btn
	call_deferred("_at_rebuild_header_focus_chain", header_row)

# 处理 AutoTato 按钮点击，启动一次手动决策
func _at_on_continue_pressed() -> void:
	_at_trigger_manual_shop_decision_all_players()

# ============================================================================
# 焦点链 — 智能适配其他 mod 插入的按钮
# ============================================================================

# 根据同一行可聚焦控件的屏幕位置重建左右焦点链
func _at_rebuild_header_focus_chain(header_row: Control) -> void:
	var controls: Array = _at_collect_focusable_header_controls(header_row)
	if controls.size() < 2:
		return

	# 按 X 坐标排序
	controls.sort_custom(self, "_at_sort_by_x")

	for i in controls.size():
		var ctrl: Control = controls[i]
		if i > 0:
			ctrl.focus_neighbour_left = controls[i - 1].get_path()
		else:
			ctrl.focus_neighbour_left = NodePath()

		if i < controls.size() - 1:
			ctrl.focus_neighbour_right = controls[i + 1].get_path()
		else:
			ctrl.focus_neighbour_right = NodePath()

# 收集同一标题行中可见、可聚焦、未禁用的控件
func _at_collect_focusable_header_controls(header_row: Control) -> Array:
	var result := []
	for child in header_row.get_children():
		if not child is Control:
			continue
		var ctrl: Control = child as Control
		if not ctrl.visible:
			continue
		if ctrl.focus_mode == Control.FOCUS_NONE:
			continue
		if ctrl.disabled:
			continue
		result.append(ctrl)
	return result

static func _at_sort_by_x(a: Control, b: Control) -> bool:
	return a.rect_global_position.x < b.rect_global_position.x

# ============================================================================
# 触发入口
# ============================================================================

# 自动入口: 进入商店 / reroll 后调用。
# 受商店自动化开关控制 —— 未开启则静默跳过。
func at_start_shop_decision_automatically(player_index: int) -> void:
	_at_trigger_auto_shop_decision(player_index)

# 手动入口: 玩家主动点击 AutoTato 时调用。
# 即使自动化关闭也强制执行一轮。
func at_start_shop_decision_manually(player_index: int) -> void:
	_at_trigger_manual_shop_decision(player_index)

# 自动触发 (单玩家): 受开关控制
func _at_trigger_auto_shop_decision(player_index: int) -> void:
	var cfg = _Config.get_instance()
	if cfg == null or not cfg.is_shop_automation_enabled():
		return
	_at_run_shop_decision(cfg, player_index)

# 自动触发 (全部玩家)
func _at_trigger_auto_shop_decision_all_players() -> void:
	for i in _at_get_player_count():
		_at_trigger_auto_shop_decision(i)

# 手动触发 (单玩家): 强制执行
func _at_trigger_manual_shop_decision(player_index: int) -> void:
	var cfg = _Config.get_instance()
	if cfg == null:
		return
	_at_run_shop_decision(cfg, player_index)

# 手动触发 (全部玩家)
func _at_trigger_manual_shop_decision_all_players() -> void:
	for i in _at_get_player_count():
		_at_trigger_manual_shop_decision(i)

# 执行单个玩家的一次商店决策 session。
# 是否进入 reroll 循环由 shop_automation 依据商店自动化开关决定。
func _at_run_shop_decision(cfg, player_index: int) -> void:
	if _at_is_processing:
		return

	_at_is_processing = true
	var summary: Dictionary = _ShopAutomation.run_shop_decision(self, player_index)
	_at_is_processing = false

	if bool(summary.get("should_auto_start", false)):
		_at_maybe_start_next_wave(cfg, player_index)

# 探测当前玩家数量 (coop 兼容)
func _at_get_player_count() -> int:
	return _Data.get_player_count()

# 自动开始下一波
func _at_maybe_start_next_wave(cfg, player_index: int) -> void:
	var general: Dictionary = cfg.get_general()
	if not general["auto_start_wave"]:
		return
	var go_button = _get_go_button(player_index)
	if go_button == null:
		return

	if cfg.is_turbo_mode():
		go_button.call_deferred("emit_signal", "pressed")
	else:
		var delay: float = general["decision_step_delay"]
		_at_schedule_advance(delay, "_at_deferred_go", [player_index])

# ============================================================================
# 公开给 shop_automation 的执行器 API
# ============================================================================

# 执行单个 UI action。intent 来自 decider,返回执行事实(RESULT_*)。
func at_execute_action(intent: String, shop_item, player_index: int) -> String:
	if shop_item == null or not is_instance_valid(shop_item):
		return _ExecuteResult.RESULT_SKIPPED

	if not bool(shop_item.get("active")):
		return _ExecuteResult.RESULT_SKIPPED

	match intent:
		_DecisionResult.DECISION_PURCHASE:
			return _at_purchase_item(shop_item, player_index)
		_DecisionResult.DECISION_LOCK:
			return _at_lock_item(shop_item)
		_DecisionResult.DECISION_MANUAL:
			return _ExecuteResult.RESULT_MANUAL
		_DecisionResult.DECISION_SKIP:
			return _ExecuteResult.RESULT_SKIPPED
		_:
			return _ExecuteResult.RESULT_SKIPPED

# 触发 vanilla 商店刷新
func at_reroll_shop(player_index: int) -> bool:
	if not is_inside_tree():
		return false
	._on_RerollButton_pressed(player_index)
	return true

# 非急速模式动作后等待
func at_wait_before_next_decision() -> void:
	var cfg = _Config.get_instance()
	if cfg == null or cfg.is_turbo_mode():
		return
	var general: Dictionary = cfg.get_general()
	var delay: float = general["decision_step_delay"]
	if delay <= 0.0:
		return
	_at_schedule_advance(delay, "_at_noop", [])

func _at_noop() -> void:
	_at_pending_advance = null

# ============================================================================
# UI 动作 — 购买
# ============================================================================

# 购买一个 ShopItem 节点
func _at_purchase_item(shop_item, player_index: int) -> String:
	if shop_item == null or not is_instance_valid(shop_item):
		return _ExecuteResult.RESULT_SKIPPED

	var container = _get_shop_items_container(player_index)
	_at_clear_buy_delay(container)

	shop_item.emit_signal("buy_button_pressed", shop_item)

	# vanilla 购买成功会把 shop_item.active 置 false
	var post_active: bool = bool(shop_item.get("active"))
	if not post_active:
		return _ExecuteResult.RESULT_PURCHASED

	return _ExecuteResult.RESULT_SKIPPED

# ============================================================================
# UI 动作 — 锁定
# ============================================================================

# 锁定一个 ShopItem 节点
func _at_lock_item(shop_item) -> String:
	if shop_item == null or not is_instance_valid(shop_item):
		return _ExecuteResult.RESULT_SKIPPED

	var item_data = shop_item.get("item_data")
	if item_data == null:
		return _ExecuteResult.RESULT_SKIPPED
	if not bool(item_data.get("is_lockable")):
		return _ExecuteResult.RESULT_SKIPPED
	if bool(shop_item.get("locked")):
		return _ExecuteResult.RESULT_SKIPPED

	shop_item.change_lock_status(true)
	return _ExecuteResult.RESULT_LOCKED

# ============================================================================
# 购买防抖
# ============================================================================

# 清除 vanilla 购买防抖，允许连续自动购买
func _at_clear_buy_delay(container) -> void:
	if container == null:
		return
	if container.get("_is_delay_active") == true:
		container.set("_is_delay_active", false)
	var timer = container.get("_buy_delay_timer")
	if timer != null and timer is Timer and not timer.is_stopped():
		timer.stop()

# ============================================================================
# 延迟推进
# ============================================================================

# 调度一个延迟动作，至多一个 pending
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

# 延迟触发 Go 按钮进入下一波
func _at_deferred_go(player_index: int) -> void:
	_at_pending_advance = null
	if not is_inside_tree():
		return
	var go_button = _get_go_button(player_index)
	if go_button == null or not is_instance_valid(go_button):
		return
	go_button.emit_signal("pressed")
