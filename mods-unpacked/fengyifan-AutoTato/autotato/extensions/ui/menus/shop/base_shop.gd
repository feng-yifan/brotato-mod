extends "res://ui/menus/shop/base_shop.gd"

# ============================================================================
# AutoTato — base_shop Script Extension (P3)
# ----------------------------------------------------------------------------
# 这是 ModLoader v6 的 Script Extension. mod_main._init() 通过
# `ModLoaderMod.install_script_extension()` 把本脚本注入为 vanilla
# `res://ui/menus/shop/base_shop.gd` 的运行时子类, 路径必须镜像 vanilla
# (extensions/ui/menus/shop/base_shop.gd), ModLoader 据此找父类.
#
# 仅 hook 两个方法, 都遵循 "调 ._super_method() 父类 → 跑 AutoTato 流程" 顺序:
#   - _ready                  : vanilla 填好 _shop_items / 连完信号后, 跑首批决策
#   - _on_RerollButton_pressed: vanilla 扣完金币、重填 slot 后, 对该玩家槽重决策
#
# v7: 在波次按钮旁添加"继续决策"按钮, 解决手动购买后如何恢复自动化的问题.
#
# 故意不 hook 的方法 (避免重入死循环 / 收益太小):
#   - on_shop_item_bought   : 我们的购买流程就是 emit buy_button_pressed →
#                             container 内 on_shop_item_buy_button_pressed →
#                             base_shop.on_shop_item_bought, 在这里再触发决策
#                             会无限套娃
#   - _on_GoButton_pressed  : Go 按钮是玩家明确意图, 不应被自动化打断
#   - _on_gold_changed      : 每次扣钱都重决策性能炸 + 也会触发上面那条链
#
# MANUAL / SKIPPED 终态 = 玩家保留手动权, 本扩展不动作.
#
# 两阶段决策模式:
#   1) Bridge.process_shop 内部读 _shop_items snapshot, 累计 gold, 返回
#      immutable Array<Dictionary> (纯只读输出, 不在遍历期写 _shop_items)
#   2) hook 遍历 results 按 slot_index 顺序对 ShopItem 节点 emit 信号 / 调
#      change_lock_status. 严格分开两阶段防止 vanilla 重入抹掉我们的结果.
#
# 与 Bridge 通过 Engine.get_meta 拿全局, 不持引用避免 ReferenceCounted 循环
# (Bridge extends Reference, 引用计数; 保留成员引用会延长生命周期).
# ============================================================================


const LOG_NAME := "fengyifan-AutoTato:ShopHook"

# 急速模式关闭时, 阶段推进前的延迟 (秒), 让界面渲染可见.
const _AT_ADVANCE_DELAY := 0.3
# pending 推进 timer (至多一个, 新调度前 stop 旧的去重)
var _at_pending_advance: Timer = null


func _ready() -> void:
	._ready()  # vanilla 父类: 填 _shop_items / 设 UI / 连接所有信号
	_autotato_add_continue_button()
	_autotato_run_all_players()


func _on_RerollButton_pressed(player_index: int) -> void:
	._on_RerollButton_pressed(player_index)  # vanilla 父类: 扣金币 + reroll + 重填 _shop_items
	_autotato_process_shop(player_index)


# ----------------------------------------------------------------------------
# "继续决策" 按钮 — v7
# ----------------------------------------------------------------------------

func _autotato_add_continue_button() -> void:
	# Title 在 shop.tscn 中有 unique_name_in_owner=true, 显示 "商店（第N波）"
	# 用 % 唯一名精确命中 shop 自己的 Title (find_node owned=false 可能误命中实例化子树,
	# stat_popup.tscn 等内部也有名为 Title 的节点)
	var title = get_node_or_null("%Title")
	if title == null:
		_log("未找到 Title, 跳过添加继续决策按钮")
		return
	var header_row = title.get_parent()
	if header_row == null:
		return

	# Title 默认 size_flags=EXPAND_FILL 会撑满左侧, 把按钮挤到展开矩形最右端
	# (紧贴 GoldUI), 离 "商店（第N波）" 文字很远, 看起来像波次右边没按钮.
	# 改成 SIZE_FILL 让 Title 收缩到文字宽度, 按钮才能紧贴文字右侧.
	title.size_flags_horizontal = Control.SIZE_FILL

	var btn := Button.new()
	btn.name = "AutoTatoContinueBtn"
	btn.text = "AutoTato"
	btn.focus_mode = Control.FOCUS_NONE
	btn.rect_min_size = Vector2(110, 40)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.connect("pressed", self, "_autotato_continue_pressed")
	# 插入到 Title 之后 (GoldUI 之前)
	var title_idx = title.get_index()
	header_row.add_child(btn)
	header_row.move_child(btn, title_idx + 1)
	_log("已添加继续决策按钮 (标题右侧)")


func _autotato_continue_pressed() -> void:
	_autotato_run_all_players(true)


# ----------------------------------------------------------------------------
# AutoTato 流程 (前缀 _autotato_ 防与 vanilla / 其他 mod 撞名)
# ----------------------------------------------------------------------------

# 对所有玩家槽各跑一次, 仅 _ready 调用.
func _autotato_run_all_players(force: bool = false) -> void:
	if typeof(RunData) != TYPE_OBJECT:
		return
	var count: int = 1
	if RunData.has_method("get_player_count"):
		count = int(RunData.get_player_count())
	elif RunData.get("gold") is Array:
		count = (RunData.gold as Array).size()
	for player_index in count:
		_autotato_process_shop(player_index, force)


# 单玩家槽决策 + 执行. 委托给 bridge.run_shop_session (含完整刷新循环).
# 自动入口和手动按钮 (force=true) 都走同一个 bridge 方法.
func _autotato_process_shop(player_index: int, force: bool = false) -> void:
	var bridge = AT_Bridge.get_global()
	if bridge == null:
		_log("Bridge 未注册, 跳过商店决策 (玩家=%d)" % player_index)
		return
	if not bridge.has_method("run_shop_session"):
		_log("Bridge 没有 run_shop_session 方法, 跳过 (玩家=%d)" % player_index)
		return
	var summary: Dictionary = bridge.run_shop_session(self, player_index, force)
	if bool(summary.get("should_auto_start", false)):
		_autotato_maybe_start_next_wave(bridge, player_index)


# auto_start_wave 开启时, 按 Go 按钮进入下一关 (vanilla _on_GoButton_pressed).
# 延迟 emit, 避免在商店 hook 处理过程中同步切场景.
func _autotato_maybe_start_next_wave(bridge, player_index: int) -> void:
	var gen = bridge.get_general()
	if not bool(gen.get("auto_start_wave", false)):
		return
	var go_button = _get_go_button(player_index)
	if go_button == null:
		return
	_log("商店有跳过项无法继续刷新, 自动开始下一关 玩家=%d" % player_index)
	if bridge.is_turbo_mode():
		go_button.call_deferred("emit_signal", "pressed")
	else:
		_at_schedule_advance(_AT_ADVANCE_DELAY, "_at_deferred_go", [player_index])


# --- Bridge executor 方法 (bridge.run_shop_session 回调) ---

# 返回商店槽位数据 (vanilla 格式)
func _at_get_shop_slots(_player_index: int) -> Array:
	return _shop_items

# 执行一轮决策: 遍历 results, 调用 _autotato_apply_decision
func _at_execute_shop_round(results: Array, player_index: int) -> Dictionary:
	var purchases := 0
	var locks := 0
	var skips := 0
	var manuals := 0
	for r in results:
		var st: String = String(r.get("terminal_state", ""))
		_autotato_apply_decision(r, player_index)
		match st:
			"purchased": purchases += 1
			"locked": locks += 1
			"skipped": skips += 1
			"manual": manuals += 1
	if purchases > 0:
		_log("执行: 购买 %d 项" % purchases)
	if locks > 0:
		_log("执行: 锁定 %d 项" % locks)
	return {"purchases": purchases, "locks": locks, "skips": skips, "manuals": manuals}

# 触发 vanilla 商店刷新
func _at_reroll_shop(player_index: int) -> void:
	._on_RerollButton_pressed(player_index)

# 读当前刷新价格
func _at_get_reroll_price(player_index: int) -> int:
	return int(_reroll_price[player_index]) if player_index < _reroll_price.size() else 0


# 把单条决策结果转成对 ShopItem 节点的真实调用.
# 用 item_id 查找节点 (而非 slot_index): 购买后 _shop_items 数据数组会收缩 (被买项 erase),
# 但 ShopItem 节点不重新编号 (中间留空), slot_index (数据索引) 与节点索引错位会买错物品.
func _autotato_apply_decision(result: Dictionary, player_index: int) -> String:
	var state: String = String(result.get("terminal_state", ""))
	var item_id: String = String(result.get("item_id", ""))
	var slot_index: int = int(result.get("slot_index", -1))
	var container = _get_shop_items_container(player_index)
	if container == null:
		return "noop"
	var node = _at_find_shop_item_by_id(container, item_id)
	if node == null:
		_log("未找到物品节点 item_id=%s slot=%d, 跳过" % [item_id, slot_index])
		return "noop"
	# active=false 表示已被买/偷/ban, 不应再触发
	if not bool(node.get("active")):
		return "noop"
	match state:
		"purchased":
			var pre_active: bool = bool(node.get("active"))
			var pre_currency: int = RunData.get_player_currency(player_index)
			# 清除容器 0.05s 购买限流 (_is_delay_active + _buy_delay_timer), 否则连续购买只有第一个生效
			_at_clear_buy_delay(container)
			node.emit_signal("buy_button_pressed", node)
			# 诊断: 触发后 active 变 false = 购买成功; 仍 true = 被容器拒绝 (货币不足/武器检查)
			_log("购买触发 玩家=%d 物品=%s value=%d currency=%d 触发前active=%s 触发后active=%s" % [player_index, item_id, node.value, pre_currency, pre_active, node.active])
			return "purchased"
		"locked":
			if node.item_data != null and node.item_data.is_lockable and not node.locked:
				node.change_lock_status(true)
				return "locked"
			return "noop"
		_:
			return "noop"


# 用 item_id 在容器的 ShopItem 节点中查找 (active + item_data.my_id 匹配).
# 用 get() 动态访问, 兼容节点未类型标注的情况.
func _at_find_shop_item_by_id(container, item_id: String):
	if container == null or item_id == "":
		return null
	var nodes = container.get("_shop_items")
	if typeof(nodes) != TYPE_ARRAY:
		return null
	for n in nodes:
		if n == null:
			continue
		if not bool(n.get("active")):
			continue
		var idata = n.get("item_data")
		if idata == null:
			continue
		if idata.get("my_id") == item_id:
			return n
	return null


# 清除 shop_items_container 的 0.05s 购买限流 (_is_delay_active + _buy_delay_timer),
# 让自动模式连续购买不被限流拦住 (与箱子 _autotato_clear_button_guard 同理).
func _at_clear_buy_delay(container) -> void:
	if container == null:
		return
	if container.get("_is_delay_active") == true:
		container.set("_is_delay_active", false)
	var timer = container.get("_buy_delay_timer")
	if timer != null and timer is Timer and not timer.is_stopped():
		timer.stop()


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


# 延迟按 Go (急速关). 重新查找 go_button + is_instance_valid 守卫, 防场景切走后失效.
func _at_deferred_go(player_index: int) -> void:
	_at_pending_advance = null
	if not is_inside_tree():
		return
	var go_button = _get_go_button(player_index)
	if go_button == null or not is_instance_valid(go_button):
		return
	go_button.emit_signal("pressed")


func _log(msg: String) -> void:
	if typeof(ModLoaderLog) != TYPE_NIL:
		ModLoaderLog.info(msg, LOG_NAME)
