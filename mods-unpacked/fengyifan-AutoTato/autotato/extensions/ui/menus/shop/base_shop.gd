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
#
# vanilla container._is_delay_active (0.05s 限流) 约束:
#   同一次调用里连续 emit 多个 buy_button_pressed, 第 1 次会触发, 后续被丢弃.
#   P3 接受此行为, 日志告知玩家; 剩余决策等下次 reroll 后再尝试.
# ============================================================================


const LOG_NAME := "fengyifan-AutoTato:ShopHook"

# 不用 preload AT_Bridge (它已 class_name AT_Bridge, 直接调静态方法即可)


func _ready() -> void:
	._ready()  # vanilla 父类: 填 _shop_items / 设 UI / 连接所有信号
	_autotato_run_all_players()


func _on_RerollButton_pressed(player_index: int) -> void:
	._on_RerollButton_pressed(player_index)  # vanilla 父类: 扣金币 + reroll + 重填 _shop_items
	_autotato_process_shop(player_index)


# ----------------------------------------------------------------------------
# AutoTato 流程 (前缀 _autotato_ 防与 vanilla / 其他 mod 撞名)
# ----------------------------------------------------------------------------

# 对所有玩家槽各跑一次, 仅 _ready 调用.
func _autotato_run_all_players() -> void:
	# 容错: RunData 必须就绪 (._ready() 已完成 vanilla 初始化, 这里只做防御)
	if typeof(RunData) != TYPE_OBJECT:
		return
	var count: int = 1
	if RunData.has_method("get_player_count"):
		count = int(RunData.get_player_count())
	elif RunData.get("gold") is Array:
		count = (RunData.gold as Array).size()
	for player_index in count:
		_autotato_process_shop(player_index)


# 单玩家槽决策 + 执行的统一入口, 两阶段流程.
func _autotato_process_shop(player_index: int) -> void:
	var bridge = AT_Bridge.get_global()
	if bridge == null:
		_log("Bridge 未注册, 跳过商店决策 (player_index=%d)" % player_index)
		return
	if not bridge.has_method("process_shop"):
		_log("Bridge 没有 process_shop 方法 (P2 老版本?), 跳过 (player_index=%d)" % player_index)
		return
	# 阶段 1: 决策 (Bridge 内部累计 gold, 输出只读 Array)
	var results: Array = bridge.process_shop(self, player_index)
	_log("商店决策完成 player_index=%d, slot 数=%d" % [player_index, results.size()])
	# 阶段 2: 按结果顺序执行
	var purchase_emit_count: int = 0
	for r in results:
		var applied: String = _autotato_apply_decision(r, player_index)
		if applied == "purchased":
			purchase_emit_count += 1
	# vanilla 0.05s 限流可能丢掉同调用内的后续买入, 提示玩家
	if purchase_emit_count > 1:
		_log("发出 %d 个购买信号; vanilla 0.05s 限流可能只生效 1 个, 剩余等下次 reroll" % purchase_emit_count)


# 把单条决策结果转成对 ShopItem 节点的真实调用.
# 返回执行的动作类型 ("purchased" / "locked" / "noop"), 供调用方统计.
# 安全规则:
#   - slot_index 越界 / 节点不在 / 已 deactivate → 静默 noop
#   - "purchased" → emit buy_button_pressed (走 vanilla 完整校验链)
#   - "locked"    → change_lock_status(true), 仅在当前未锁定 且 item_data.is_lockable
#   - "manual" / "skipped" / 未知 → noop
func _autotato_apply_decision(result: Dictionary, player_index: int) -> String:
	var slot_index: int = int(result.get("slot_index", -1))
	var state: String = String(result.get("terminal_state", ""))
	if slot_index < 0:
		return "noop"
	var container = _get_shop_items_container(player_index)
	if container == null:
		return "noop"
	var node = container.get_shop_item_node(slot_index)
	if node == null:
		return "noop"
	# active=false 表示已被买/偷/ban, 不应再触发
	if not node.active:
		return "noop"
	match state:
		"purchased":
			node.emit_signal("buy_button_pressed", node)
			return "purchased"
		"locked":
			if node.item_data != null and node.item_data.is_lockable and not node.locked:
				node.change_lock_status(true)
				return "locked"
			return "noop"
		_:
			return "noop"


func _log(msg: String) -> void:
	if typeof(ModLoaderLog) != TYPE_NIL:
		ModLoaderLog.info(msg, LOG_NAME)
