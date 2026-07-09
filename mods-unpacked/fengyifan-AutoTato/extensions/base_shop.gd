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

# ============================================================================
# Timer 链状态 (非 turbo 步进延迟)
# ----------------------------------------------------------------------------
# 非 turbo 模式下, 商店决策不一口气同步跑完, 而是用 Timer 链逐步驱动:
#   决策+执行单 entry -> 调度 delay -> 下一个 entry -> 本轮结束判断 ->
#   reroll -> 调度 delay -> 下一轮 -> stop 收尾。
# Timer 默认 PAUSE_MODE_STOP, ESC 暂停时链自然冻结 (不计时/不回调),
# 恢复后从中断处继续。链状态全在下面的字段里, 无协程 yield 卡死风险。
# 临界区标志 _at_is_processing 在链期间保持 true, reroll 拦截等语义不变。
# ============================================================================

# 链是否运行中
var _at_chain_active := false
# 当前链服务的玩家
var _at_chain_player_index := -1
# cfg 缓存 (链结束时收尾要用)
var _at_chain_cfg = null
# 当前 pending 的链步 Timer
var _at_chain_timer: Timer = null
# 当前轮的 entries 缓存 (reroll 后重新读)
var _at_chain_entries: Array = []
# 当前轮游标: 下一个待处理的 entry 索引
var _at_chain_entry_idx := 0
# 当前轮统计字典 (new_round_state 产生)
var _at_chain_rd: Dictionary = {}
# 会话累计统计
var _at_chain_totals := {
	"purchases": 0, "locks": 0, "skips": 0, "manuals": 0, "rounds": 0, "reroll_spent": 0,
}
# 本会话是否出现过 manual 决策
var _at_chain_session_has_manual := false
# 是否应进波 (stop_no_reroll 时由 decide_round_outcome 设定)
var _at_chain_should_auto_start := false

# AutoTato 按钮引用
var _at_continue_btn: Button = null

# Y/F (ui_info) 快捷键归属: "auto" -> AutoTato 决策; "reroll" -> 刷新商店。
# 单玩家下 vanilla reroll 按钮已显示 F 图标且 F 触发 reroll (reroll_button.gd),
# AutoTato 接管 F (见 extensions/reroll_button.gd), 并控制两按钮 F 图标互斥显隐:
# auto 态 F 显在决策按钮, reroll 态 F 显在 reroll 按钮 (vanilla 原位)。
var _at_info_owner := "auto"
# AutoTato 决策按钮自带的 F 键图标 (ui_input_icon), auto 态显
var _at_continue_icon: Control = null
# 临界区按钮禁用状态记忆 (边沿触发, 避免每帧重复设 disabled)
var _at_was_locked := false

# ============================================================================
# 生命周期
# ============================================================================

# 接管 vanilla ready：添加 AutoTato 按钮，并在进入商店后尝试自动决策
func _ready() -> void:
	._ready()
	_at_add_continue_button()
	# 初始化 F 图标显隐: 默认 auto 态 (决策按钮显 F, reroll 隐 F)。
	# call_deferred 保证 vanilla reroll 按钮节点就绪可访问。
	call_deferred("_at_switch_info_owner", "auto")
	call_deferred("_at_trigger_auto_shop_decision_all_players")
	# 启用 _process 轮询临界区 (弹窗开关时机不固定, _input 顺带检测有漏洞)
	set_process(true)

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
	# text 留空: 文字由 HBoxContainer 内的 Label 渲染, 让 F 图标参与布局算宽度
	btn.text = ""
	btn.focus_mode = Control.FOCUS_ALL
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.connect("pressed", self, "_at_on_continue_pressed")

	# 内容容器: [Label(文字) + F 图标], 仿 vanilla ButtonWithIcon 的 HBoxContainer 范式,
	# 让 F 图标参与宽度计算 (不再悬浮在文字右上角)。
	var hbox := HBoxContainer.new()
	hbox.name = "Content"
	hbox.anchor_right = 1.0
	hbox.anchor_bottom = 1.0
	hbox.alignment = BoxContainer.ALIGN_CENTER
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(hbox)

	var label := Label.new()
	label.name = "Label"
	label.text = tr("AUTOTATO_AUTOMATION") + " & " + tr("REROLL")
	label.align = Label.ALIGN_CENTER
	label.valign = Label.VALIGN_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(label)

	# F 键图标 (ui_info), auto 态显示。尺寸仿 vanilla reroll 的 AdditionalIcon (约 51x51)。
	var icon_script = load("res://ui/hud/ui_input_icon.gd")
	if icon_script:
		var icon := TextureRect.new()
		icon.set_script(icon_script)
		icon.name = "ATInfoIcon"
		icon.input_string = "ui_info"
		icon.player_index = 0
		icon.expand = true
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.rect_min_size = Vector2(40, 40)
		hbox.add_child(icon)
		_at_continue_icon = icon

	# 按钮高度固定 40, 宽度由内容驱动 (HBoxContainer 算), 设 SIZE_EXPAND 不写死 rect_min_size.x
	btn.rect_min_size = Vector2(0, 40)
	# 内容变化时重算按钮宽度
	hbox.connect("resized", self, "_at_on_continue_content_resized", [btn, hbox])

	var title_idx = title.get_index()
	header_row.add_child(btn)
	header_row.move_child(btn, title_idx + 1)

	_at_continue_btn = btn
	call_deferred("_at_rebuild_header_focus_chain", header_row)

# 决策按钮内容变化时 (F 图标显隐等) 重算按钮宽度, 让宽度跟随内容。
# 累加 HBoxContainer 子节点的自然宽度 (不用 hbox.rect_size.x, 那会被拉伸=按钮宽度, 循环依赖)。
# 仿 vanilla ButtonWithIcon.get_content_size_x 的做法。
func _at_on_continue_content_resized(btn: Button, hbox: HBoxContainer) -> void:
	if btn == null or not is_instance_valid(btn):
		return
	if hbox == null or not is_instance_valid(hbox):
		return
	var content_w: float = 0.0
	for child in hbox.get_children():
		if child is Control:
			var c := child as Control
			# 跳过隐藏子节点 (F 图标 hide 时不计入宽度, 按钮缩窄)
			if not c.visible:
				continue
			content_w += c.rect_size.x
	var padding: float = 24.0
	btn.rect_min_size.x = content_w + padding

# 切换 Y/F (ui_info) 快捷键归属, 控制两按钮 F 图标互斥显隐。
# 双按钮各管自己的 F 图标 (不 reparent), 画面任何时候只有一个 F:
#   "auto":   决策按钮 F 显, reroll 按钮 F 隐 -> 按 F 跑决策
#   "reroll": 决策按钮 F 隐, reroll 按钮 F 显 (vanilla 原位) -> 按 F 刷新
# reroll 按钮用 vanilla 自带的 AdditionalIcon (单玩家下原生显示 F 图标)。
func _at_switch_info_owner(owner: String) -> void:
	_at_log_info_owner(owner)
	_at_info_owner = owner

	# 决策按钮自带 F 图标
	if _at_continue_icon != null and is_instance_valid(_at_continue_icon):
		_at_continue_icon.visible = (owner == "auto")
		# F 图标显隐后 HBoxContainer 重新布局, deferred 重算按钮宽度 (避免时序不准)
		var hbox = _at_continue_icon.get_parent()
		if hbox != null and is_instance_valid(hbox):
			call_deferred("_at_on_continue_content_resized", _at_continue_btn, hbox)

	# reroll 按钮 vanilla AdditionalIcon (单玩家下原生 F 图标)
	var rb = _get_reroll_button(0)
	if rb != null and is_instance_valid(rb):
		var vanilla_icon = rb.get_node_or_null("AdditionalIcon")
		if vanilla_icon != null:
			vanilla_icon.visible = (owner == "reroll")
		# 刷新 reroll 按钮文字前导空格: auto 态 (F 隐藏) 去空格, reroll 态加空格
		if rb.has_method("_at_refresh_text"):
			rb._at_refresh_text()

# 返回当前 Y/F 归属 (供 reroll_button extension 路由 F 用)
func at_get_info_owner() -> String:
	return _at_info_owner

# (诊断日志在 _at_switch_info_owner 内)
func _at_log_info_owner(owner: String) -> void:
	_Logger.info("_at_switch_info_owner -> %s" % owner, _LOG_NAME)

# ============================================================================
# 临界区 - 防重入与弹窗保护
# ----------------------------------------------------------------------------
# 临界区 = 自动化进行中 (_at_is_processing) OR 任意弹窗可见。
# 临界区内: F/Y 不路由, reroll + 决策按钮禁用。守卫只放手动入口 (F/Y 路由 +
# 决策按钮点击), 执行器 (at_reroll_shop/at_execute_action) 不带守卫, 自动循环
# 是受信任内部调用, 直接调。
# ============================================================================

# 当前是否处于临界区 (输入应被阻断)
func _at_is_input_locked() -> bool:
	if _at_is_processing:
		return true
	# get_modal_stack_top 统一检测 vanilla ItemPopup + AutoTato _at_popup
	# (任何 popup_* 调用的弹窗都进模态栈)
	return get_viewport().get_modal_stack_top() != null

# 禁用/恢复 reroll + 决策按钮。disabled 只挡 GUI 交互, 代码调
# _on_RerollButton_pressed 仍有效 (自动循环靠这个), 故不影响自动化 reroll。
func _at_set_buttons_disabled(disabled: bool) -> void:
	if _at_continue_btn != null and is_instance_valid(_at_continue_btn):
		_at_continue_btn.disabled = disabled
	var rb = _get_reroll_button(0)
	if rb != null and is_instance_valid(rb):
		rb.disabled = disabled

# 临界区状态边沿检测: 状态变化时同步按钮禁用。在 _input 里顺带调用,
# 避免 _process 轮询开销。
# 弹窗打开时 (非自动化临界区) 额外切到 auto 态: F 图标移回决策按钮,
# 让玩家关闭弹窗后按 F 跑决策 (而非 reroll)。
func _at_update_lock_state() -> void:
	var locked := _at_is_input_locked()
	if locked != _at_was_locked:
		_at_was_locked = locked
		_at_set_buttons_disabled(locked)
		# 弹窗打开 (非自动化进行中) -> 切 auto 态 (F 绑回决策按钮)
		if locked and not _at_is_processing:
			_at_switch_info_owner("auto")

# 处理 AutoTato 按钮点击，启动一次手动决策
func _at_on_continue_pressed() -> void:
	# 临界区守卫 (防自动化进行中 / 弹窗打开时鼠标点击重入)
	if _at_is_input_locked():
		return
	_at_trigger_manual_shop_decision_all_players()

# ============================================================================
# 输入 - 临界区边沿检测
# ----------------------------------------------------------------------------
# 本 extension 不覆写 _input。Godot 3 虚方法是 multilevel 的: 引擎对 _input /
# _ready / _process 等会沿继承链自动逐层调用, 子类无法通过"不调 super"阻止
# 父类执行 (见 ModLoader Wiki "Script Extensions" - 虚方法会被调用两次的陷阱)。
# 故 vanilla base_shop._input (暂停 / ban / E-X 锁定 / go 按钮等) 由引擎自动
# 调用一次即可, 无需在此转发。
#
# 切勿在此加 `func _input(event): ._input(event)` -- 那会让 vanilla _input 跑
# 两次, 其中 E/X 锁定逻辑 change_lock_status(not locked) 翻转两次互相抵消,
# 表现为"按 E/X 锁不上物品"。(reroll_button extension 的 _input 正确地未调
# super, 见其注释。)
#
# 临界区按钮禁用的边沿检测改由 _process 轮询负责 (弹窗开关时机不固定, 可靠)。
# ============================================================================

# _process 轮询临界区状态 (弹窗开关时机不固定, 可靠检测)。
# _at_update_lock_state 有边沿检测, 状态不变时几乎无开销。
func _process(_delta: float) -> void:
	_at_update_lock_state()

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
	# 进入自动化临界区: 禁用 reroll + 决策按钮 (防鼠标/手柄点击干扰)
	_at_set_buttons_disabled(true)
	_at_was_locked = true

	var general: Dictionary = cfg.get_general()
	var delay: float = general["decision_step_delay"]
	if cfg.is_turbo_mode() or delay <= 0.0:
		# turbo 或 delay=0: 同步一口气跑完, 无延迟 (delay=0 时链会同步递归, 退化同步更安全)
		var summary: Dictionary = _ShopAutomation.run_shop_decision_sync(self, player_index)
		_at_finalize_shop_decision(cfg, player_index, summary)
	else:
		# 非 turbo 且 delay>0: 启动 Timer 链, 逐步决策+执行, 每步间延迟让 UI 渲染可见
		_at_chain_start(cfg, player_index)

# 收尾: 解除临界区 + 据 summary 切 Y/F 归属 + 按 auto_start 决定进波。
# turbo 同步路径与 Timer 链结束路径共用此方法。
func _at_finalize_shop_decision(cfg, player_index: int, summary: Dictionary) -> void:
	_at_is_processing = false
	# 退出临界区: 重新评估锁定状态 (弹窗可能仍开着), 据此恢复按钮
	_at_update_lock_state()

	# 据 manual 标志切换 Y/F 归属: 出现 manual (留待玩家手动处理) -> F 移到 reroll;
	# 否则 F 留在决策按钮。coop 下以玩家 0 的 reroll 按钮为图标宿主 (首版简化)。
	var has_manual: bool = bool(summary.get("has_manual_pending", false))
	_at_switch_info_owner("reroll" if has_manual else "auto")

	if bool(summary.get("should_auto_start", false)):
		_at_maybe_start_next_wave(cfg, player_index)

# ============================================================================
# Timer 链 - 非 turbo 步进延迟
# ----------------------------------------------------------------------------
# 把同步 while+for 循环展开为 Timer 链状态机:
#   _at_chain_start -> _at_chain_begin_round -> 处理 entry -> _at_chain_advance(延迟)
#                       -> _at_chain_step -> 下一个 entry / _at_chain_end_round
#   _at_chain_end_round: manual/不能reroll -> _at_chain_finish; reroll -> 延迟进下一轮
# 链状态在 _at_chain_* 字段里, Timer 默认 PAUSE_MODE_STOP, ESC 暂停即冻结。
# ============================================================================

# 链启动: 初始化会话累计, 进入第一轮。
func _at_chain_start(cfg, player_index: int) -> void:
	_at_chain_active = true
	_at_chain_player_index = player_index
	_at_chain_cfg = cfg
	_at_chain_timer = null
	_at_chain_totals = {
		"purchases": 0, "locks": 0, "skips": 0, "manuals": 0, "rounds": 0, "reroll_spent": 0,
	}
	_at_chain_session_has_manual = false
	_at_chain_should_auto_start = false
	_at_chain_begin_round()

# 开始一轮: 轮数+1, 重读 entries (reroll 后节点重建), 重置游标, 处理第一个 entry。
func _at_chain_begin_round() -> void:
	if not _at_chain_guard():
		return
	_at_chain_totals["rounds"] += 1
	var pi: int = _at_chain_player_index
	_at_chain_entries = _ShopAutomation.get_shop_entries(self, pi)
	_at_chain_entry_idx = 0
	_at_chain_rd = _ShopAutomation.new_round_state()
	_Logger.info("链: 开始第 %d 轮 entries=%d 玩家=%d" % [
		_at_chain_totals["rounds"], _at_chain_entries.size(), pi
	], _LOG_NAME)
	_at_chain_process_current_entry()

# 处理当前游标处的 entry, 然后推进游标并按需延迟。
func _at_chain_process_current_entry() -> void:
	if not _at_chain_guard():
		return
	var pi: int = _at_chain_player_index
	# 同步连续处理 entry, 直到遇到需要 UI 停顿的动作 (purchase/lock) 才延迟 return。
	# process_one_entry 对失效 entry / manual / skip 返回 false (无 UI 动作),
	# 这些 entry 在同一帧内完成决策+记账后直接跳过, 不起 Timer 延迟。
	# 故"全 manual"等无 purchase/lock 的轮次会同步跑完 while, 瞬时进入 _at_chain_end_round。
	while _at_chain_entry_idx < _at_chain_entries.size():
		var entry = _at_chain_entries[_at_chain_entry_idx]
		_at_chain_entry_idx += 1
		var performed: bool = _ShopAutomation.process_one_entry(self, pi, entry, _at_chain_rd)
		if performed:
			# purchase/lock 后延迟 0.3s 让 UI 渲染可见, 然后处理下一个 entry
			_at_chain_advance()
			return
	# 本轮 entry 耗尽 -> 进入轮结束判断
	_at_chain_end_round()

# 调度一个链步延迟, 到期回调 _at_chain_step。
# 专用调度器, 不与 _at_schedule_advance (延迟进波单次调度) 共用, 避免覆盖语义切断链。
func _at_chain_advance() -> void:
	if not _at_chain_guard():
		return
	var delay: float = _at_chain_cfg.get_general()["decision_step_delay"]
	if delay <= 0.0:
		# 无延迟直接进下一步 (仍走 _at_chain_step 保持链状态一致)
		_at_chain_step()
		return
	if _at_chain_timer != null and is_instance_valid(_at_chain_timer):
		_at_chain_timer.stop()
		_at_chain_timer.queue_free()
	var t = Timer.new()
	t.one_shot = true
	t.wait_time = delay
	t.connect("timeout", self, "_at_chain_step", [])
	add_child(t)
	t.start()
	_at_chain_timer = t

# Timer 回调: 处理下一个 entry (游标已在前一次 process 时推进)。
func _at_chain_step() -> void:
	_at_chain_timer = null
	if not _at_chain_guard():
		return
	_at_chain_process_current_entry()

# 一轮结束判断: manual/不能 reroll -> 收尾; reroll -> 执行刷新后延迟进下一轮。
func _at_chain_end_round() -> void:
	if not _at_chain_guard():
		return
	var pi: int = _at_chain_player_index
	# 累计本轮统计进会话总计
	_at_chain_totals["purchases"] += int(_at_chain_rd.get("purchases", 0))
	_at_chain_totals["locks"] += int(_at_chain_rd.get("locks", 0))
	_at_chain_totals["skips"] += int(_at_chain_rd.get("skips", 0))
	_at_chain_totals["manuals"] += int(_at_chain_rd.get("manuals", 0))
	if bool(_at_chain_rd.get("has_manual", false)):
		_at_chain_session_has_manual = true
	_Logger.info("链: 轮结束 entries=%d | 买=%d 锁=%d 跳过=%d 手动=%d" % [
		_at_chain_entries.size(), _at_chain_rd.get("purchases", 0),
		_at_chain_rd.get("locks", 0), _at_chain_rd.get("skips", 0), _at_chain_rd.get("manuals", 0)
	], _LOG_NAME)

	var general: Dictionary = _at_chain_cfg.get_general()
	var outcome: Dictionary = _ShopAutomation.decide_round_outcome(
		self, pi, _at_chain_rd, _at_chain_totals["reroll_spent"], general
	)
	match outcome.get("action"):
		"stop_manual":
			_at_chain_finish()
		"stop_no_reroll":
			_at_chain_should_auto_start = bool(outcome.get("should_auto_start", false))
			_at_chain_finish()
		"reroll":
			_at_chain_do_reroll(int(outcome.get("reroll_price", 0)))
		_:
			_Logger.warning("链: 未知 outcome action=%s, 收尾" % str(outcome.get("action")), _LOG_NAME)
			_at_chain_finish()

# 执行 reroll, 成功则延迟, 然后据自动化开关决定进下一轮或收尾。
# 自动化开 -> 进下一轮; 关 -> 停 (手动触发只推进一轮含一次刷新)。
func _at_chain_do_reroll(price: int) -> void:
	if not _at_chain_guard():
		return
	var pi: int = _at_chain_player_index
	if not _ShopAutomation.execute_reroll(self, pi):
		_Logger.warning("链: reroll 执行失败, 收尾", _LOG_NAME)
		_at_chain_finish()
		return
	_at_chain_totals["reroll_spent"] += price
	_Logger.info("链: 刷新 累计=%d gold=%d" % [
		_at_chain_totals["reroll_spent"], _Data.get_player_gold(pi)
	], _LOG_NAME)
	# reroll 后延迟, 然后判断是否继续
	_at_chain_advance_after_reroll()

# 调度延迟后判断自动化开关: 开则进下一轮, 关则收尾。
func _at_chain_advance_after_reroll() -> void:
	if not _at_chain_guard():
		return
	var delay: float = _at_chain_cfg.get_general()["decision_step_delay"]
	if delay <= 0.0:
		_at_chain_post_reroll_decide()
		return
	if _at_chain_timer != null and is_instance_valid(_at_chain_timer):
		_at_chain_timer.stop()
		_at_chain_timer.queue_free()
	var t = Timer.new()
	t.one_shot = true
	t.wait_time = delay
	t.connect("timeout", self, "_at_chain_post_reroll_decide", [])
	add_child(t)
	t.start()
	_at_chain_timer = t

# reroll 后判断: 自动化开 -> 进下一轮; 关 -> 收尾 (手动触发只推进一轮)。
func _at_chain_post_reroll_decide() -> void:
	_at_chain_timer = null
	if not _at_chain_guard():
		return
	if _at_chain_cfg.is_shop_automation_enabled():
		_at_chain_begin_round()
	else:
		_Logger.info("链: 自动化关闭, reroll 后停止 玩家=%d" % _at_chain_player_index, _LOG_NAME)
		_at_chain_should_auto_start = bool(_at_chain_cfg.get_general()["auto_start_wave"])
		_at_chain_finish()

# 链结束: 构造 summary, 清理链状态, 调收尾。
func _at_chain_finish() -> void:
	var pi: int = _at_chain_player_index
	var cfg = _at_chain_cfg
	var summary: Dictionary = _ShopAutomation.build_summary(
		_at_chain_totals["purchases"], _at_chain_totals["locks"], _at_chain_totals["skips"],
		_at_chain_totals["manuals"], _at_chain_totals["rounds"], _at_chain_totals["reroll_spent"],
		_at_chain_should_auto_start, _at_chain_session_has_manual
	)
	_at_chain_clear_timer()
	_at_chain_active = false
	_at_chain_player_index = -1
	_at_chain_cfg = null
	_at_chain_entries = []
	_at_chain_rd = {}
	_at_finalize_shop_decision(cfg, pi, summary)

# 链守卫: 节点失效/不在树中/链未激活时安全收尾, 防止状态泄漏。
# 返回 false 表示已收尾, 调用方应立即 return。
func _at_chain_guard() -> bool:
	if not _at_chain_active:
		return false
	if not is_inside_tree():
		_Logger.warning("链: 节点已离开树, 中止收尾", _LOG_NAME)
		_at_chain_abort()
		return false
	return true

# 异常收尾: 不构造完整 summary, 用当前累计 + 空 should_auto_start 兜底。
func _at_chain_abort() -> void:
	var pi: int = _at_chain_player_index
	var cfg = _at_chain_cfg
	var summary: Dictionary = _ShopAutomation.build_summary(
		_at_chain_totals["purchases"], _at_chain_totals["locks"], _at_chain_totals["skips"],
		_at_chain_totals["manuals"], _at_chain_totals["rounds"], _at_chain_totals["reroll_spent"],
		_at_chain_should_auto_start, _at_chain_session_has_manual
	)
	_at_chain_clear_timer()
	_at_chain_active = false
	_at_chain_player_index = -1
	_at_chain_cfg = null
	_at_chain_entries = []
	_at_chain_rd = {}
	if cfg != null and pi >= 0:
		_at_finalize_shop_decision(cfg, pi, summary)

func _at_chain_clear_timer() -> void:
	if _at_chain_timer != null and is_instance_valid(_at_chain_timer):
		_at_chain_timer.stop()
		_at_chain_timer.queue_free()
	_at_chain_timer = null

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

# 覆写 vanilla _on_RerollButton_pressed (reroll 按钮 pressed 信号的接收方)。
# 手动按 F / 鼠标点击 reroll 按钮都触发此方法。
# 拦截规则:
#   - 链进行中 (_at_is_processing): 拒绝 (拦截一切 pressed, 见下注)
#   - 临界区 (弹窗): 拒绝 (防误触)
#   - F 键 + auto 态 (reroll_button._at_f_key_block_reroll=true): 拒绝 (auto 态 F 跑决策不 reroll)
#   - 其他 (鼠标点击 / reroll 态 F 键): 放行 vanilla reroll
# 注1: at_reroll_shop 调 .super (_on_RerollButton_pressed), 不经此覆写, 故链内自动
#       reroll 不受 _at_is_processing 拦截影响。
# 注2: 链进行中必须拦截 pressed。Script Extension 下 vanilla 父类 _input 会被 Godot
#       独立调用一次 (emit pressed), 若链进行中放行, 该插队 pressed 会触发真实 reroll,
#       把链正在处理的商品换掉 (非 turbo Timer 链跨帧时暴露, 同步路径因 is_processing
#       已归位而侥幸不触发)。链内自动 reroll 走 at_reroll_shop->.super, 不经此分支。
func _on_RerollButton_pressed(player_index: int) -> void:
	if _at_is_processing:
		# 链进行中: 拦截一切 pressed (含 vanilla 父类 _input 独立 emit 的插队 pressed)。
		# 消费 block 标志: 链中按 F 时子类 _input 已设 block, 不消费会残留到下次鼠标
		# reroll 被误拦截。
		var rb_proc = _get_reroll_button(player_index)
		if rb_proc != null and is_instance_valid(rb_proc) and rb_proc.has_method("_at_consume_f_key_block"):
			rb_proc._at_consume_f_key_block()
		return
	if _at_is_input_locked():
		return
	# F 键 + auto 态: 拦截 (一次性消费标志)。鼠标点击不设标志, 放行。
	var rb = _get_reroll_button(player_index)
	if rb != null and is_instance_valid(rb) and rb.has_method("_at_consume_f_key_block"):
		if rb._at_consume_f_key_block():
			return
	# 真正放行 reroll: 标记本次 pressed 确实 reroll 了, 供 _at_on_reroll_pressed 判断是否绑回
	if rb != null and is_instance_valid(rb) and rb.has_method("_at_set_did_reroll"):
		rb._at_set_did_reroll(true)
	._on_RerollButton_pressed(player_index)

# 触发 vanilla 商店刷新。
# 自动循环 (shop_automation) 调此方法; 手动 F 触发 reroll 走 vanilla pressed 信号
# (不经此), 其绑回由 reroll_button extension 的 pressed 回调负责。
# ._on_RerollButton_pressed 不 emit reroll 按钮 pressed 信号, 故无需抑制标志。
func at_reroll_shop(player_index: int, _internal: bool = false) -> bool:
	if not is_inside_tree():
		return false
	._on_RerollButton_pressed(player_index)
	return true

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
