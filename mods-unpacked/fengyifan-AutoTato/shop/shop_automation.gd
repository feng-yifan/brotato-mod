extends Reference

# ============================================================================
# AutoTato — ShopAutomation
# ----------------------------------------------------------------------------
# 商店自动化流程编排。
# turbo 同步入口 run_shop_decision_sync() 一口气跑完决策+reroll 循环。
# 非 turbo 由 base_shop Timer 链逐步调用下面的原子方法。
#
# 数据流:
#   shop_data_reader → entry
#   item_decider → decision {intent}  (纯决策意图,不含余额事实)
#   shop_automation → 调用 base_shop.at_execute_action(intent, shop_item, player_index)
#   base_shop 返回执行结果(RESULT_*) → shop_automation 累积最终状态
#   shop_automation → 重读 currency/price 自算 is_affordable,供 reroll 停止条件使用
# ============================================================================

const _Config = preload("res://mods-unpacked/fengyifan-AutoTato/config/config.gd")
const _Data = preload("res://mods-unpacked/fengyifan-AutoTato/shop/shop_data_reader.gd")
const _ItemDecider = preload("res://mods-unpacked/fengyifan-AutoTato/shop/item_decider.gd")
const _ExecuteResult = preload("res://mods-unpacked/fengyifan-AutoTato/shop/execute_result.gd")
const _Logger = preload("res://mods-unpacked/fengyifan-AutoTato/utils/logger.gd")

const _LOG_NAME := "ShopAutomation"

# ============================================================================
# 公开 API
# ============================================================================

# 商店决策同步入口 (turbo 急速路径)。
# 一口气跑完 while+for 嵌套循环并返回 summary, 无延迟。turbo 模式专用。
# 非 turbo 路径由 base_shop 的 Timer 链驱动, 逐步调用下面的原子方法。
# ui_adapter: base_shop 实例，需实现 at_execute_action() / at_reroll_shop()
static func run_shop_decision_sync(ui_adapter, player_index: int) -> Dictionary:
	var cfg = _Config.get_instance()
	if cfg == null:
		_Logger.warning("Config 未初始化，跳过商店决策", _LOG_NAME)
		return _empty_summary()

	var auto_enabled: bool = cfg.is_shop_automation_enabled()
	var general: Dictionary = cfg.get_general()

	var round_num := 0
	var total_purchases := 0
	var total_locks := 0
	var total_skips := 0
	var total_manuals := 0
	var session_has_manual := false
	var reroll_spent := 0

	# 统一 reroll 循环:第一轮与后续轮共用同一套逻辑。
	# 流程:决策一轮 → 出现手动则 break → 否则判断能否刷新 →
	#       能刷新则刷新继续,不能刷新则按 auto_start_wave 决定是否进波后 break。
	var cur_round: Dictionary = {}
	var should_auto_start := false
	while true:
		round_num += 1
		cur_round = _run_one_round(ui_adapter, player_index)
		total_purchases += int(cur_round.get("purchases", 0))
		total_locks += int(cur_round.get("locks", 0))
		total_skips += int(cur_round.get("skips", 0))
		total_manuals += int(cur_round.get("manuals", 0))
		if bool(cur_round.get("has_manual", false)):
			session_has_manual = true

		# 停止条件:出现手动直接 break(不进波判断)
		if _has_manual(cur_round):
			_Logger.info("停止: 出现 manual 玩家=%d" % player_index, _LOG_NAME)
			break

		# 能否刷新检查:全买不起 / 客观不能 reroll 都算不能刷新。
		# 全买不起 → reroll 也买不起,浪费钱;
		# 客观不能 → 金币/预算/全锁死(_can_reroll 内部判断)。
		var reroll_check := _can_reroll(ui_adapter, player_index, reroll_spent)
		var cannot_reroll := false
		var cannot_reason := ""
		if _all_unpurchased_insufficient(cur_round):
			cannot_reroll = true
			cannot_reason = "所有未购买商品都余额不足"
		elif not bool(reroll_check.get("ok", false)):
			cannot_reroll = true
			cannot_reason = str(reroll_check.get("reason", ""))

		if cannot_reroll:
			# 不能刷新:按 auto_start_wave 配置决定是否进波
			should_auto_start = bool(general["auto_start_wave"])
			_Logger.info("停止: 无法刷新(%s) 玩家=%d auto_start=%s" % [
				cannot_reason, player_index, str(should_auto_start)
			], _LOG_NAME)
			break

		# 能刷新:执行刷新 (_internal=true: 不绑回 F, 循环结束后由 summary 统一切换)
		if not ui_adapter.at_reroll_shop(player_index, true):
			_Logger.warning("reroll 执行失败，停止", _LOG_NAME)
			break

		reroll_spent += int(reroll_check.get("price", 0))
		_Logger.info("刷新 (第 %d 轮) 累计=%d gold=%d budget=%d" % [
			round_num, reroll_spent,
			_Data.get_player_gold(player_index), general["reroll_budget"]
		], _LOG_NAME)

		# 自动化开关作为循环退出条件:未开启则只循环一次(第一轮后退出)
		if not auto_enabled:
			break

	var summary := {
		"purchases": total_purchases,
		"locks": total_locks,
		"skips": total_skips,
		"manuals": total_manuals,
		"rounds": round_num,
		"reroll_spent": reroll_spent,
		"should_auto_start": should_auto_start,
		# 本会话是否出现过 manual 决策 -> 留待玩家手动处理。
		# base_shop 据此把 Y/F 快捷键归属在 AutoTato 决策与 reroll 间切换。
		"has_manual_pending": session_has_manual,
	}
	_Logger.info("会话结束: 购买=%d 锁定=%d 跳过=%d 手动=%d 轮数=%d auto_start=%s" % [
		total_purchases, total_locks, total_skips, total_manuals, round_num, str(should_auto_start)
	], _LOG_NAME)
	return summary


# ============================================================================
# 单步原子 API (供 base_shop Timer 链逐步调用, 非 turbo 路径)
# ----------------------------------------------------------------------------
# shop_automation 只管"做什么" (决策+执行+判断), base_shop 管"何时做" (Timer 调度)。
# 链状态 (游标/累计统计) 由 base_shop 持有, 通过 rd 字典在步间传递。
# ============================================================================

# 读取本轮商店 entries。reroll 后节点重建, 每轮开始必须重新读。
static func get_shop_entries(ui_adapter, player_index: int) -> Array:
	return _Data.get_shop_entries(ui_adapter, player_index)

# 创建一轮统计字典 (链每轮开始时调用)。
static func new_round_state() -> Dictionary:
	return {
		"purchases": 0,
		"locks": 0,
		"skips": 0,
		"manuals": 0,
		"has_skipped": false,
		"has_manual": false,
		"has_locked": false,
		"actions": [],
	}

# 决策+执行单个 entry, 累计进 rd。返回是否执行了需要 UI 停顿的动作 (purchase/lock)。
# manual/skip 返回 false: 无 UI 动作, 链 while 循环同步连续处理下一个, 不延迟。
# 无论返回值如何, rd 记账 (actions/manuals/has_manual/...) 在返回前已完成。
# 注意: turbo 同步路径 (_run_one_round) 忽略返回值, 本改动只影响非 turbo Timer 链。
static func process_one_entry(ui_adapter, player_index: int, entry, rd: Dictionary) -> bool:
	var shop_item = entry.get("shop_item")
	if not _Data.is_shop_item_active(shop_item):
		return false

	# 决策(纯 intent,不含余额事实)
	var decision: Dictionary = _ItemDecider.decide_shop_entry(entry, player_index)
	# IntentResult.make 保证 intent 字段必然存在,直接索引信任契约 -
	# 字段缺失即决策器违约,应报错暴露。
	var intent: String = String(decision["intent"])

	# 即时执行 -> 消费执行结果
	var executed: String = ui_adapter.at_execute_action(intent, shop_item, player_index)

	# 重读 currency/price 自算 is_affordable(currency >= price),与决策正交,
	# 用于 reroll 停止条件。在执行之后读,反映循环中前序 purchase 扣减后的最新余额。
	var price: int = _Data.get_item_price(shop_item)
	var currency: int = _Data.get_player_currency(player_index)
	var is_affordable: bool = currency >= price

	# 保存用于 reroll 停止条件判断(action 记录 = 执行结果 + 自算事实)
	rd["actions"].append({
		"intent": intent,
		"is_affordable": is_affordable,
		"executed": executed,
		"shop_item": shop_item,
	})

	# 统计(用执行结果,不是决策意图)
	# 返回值语义: 是否执行了需要 UI 停顿的动作 (purchase/lock)。
	#   - purchase/lock: true  -> 链起 0.3s Timer 让 UI 渲染可见 (扣币/物品消失/锁框亮起)
	#   - manual/skip:   false -> 无 UI 动作, 链 while 循环同步连续处理下一个 entry, 不延迟
	# 统计 (rd 记账) 在返回前已完成, 与返回值无关, 故 manual/skip 仍被 has_manual/
	# actions[] 完整记录, decide_round_outcome 的停止条件不受影响。
	match executed:
		_ExecuteResult.RESULT_PURCHASED:
			rd["purchases"] += 1
			return true
		_ExecuteResult.RESULT_LOCKED:
			rd["locks"] += 1
			rd["has_locked"] = true
			return true
		_ExecuteResult.RESULT_MANUAL:
			rd["manuals"] += 1
			rd["has_manual"] = true
			return false
		_:
			rd["skips"] += 1
			rd["has_skipped"] = true
			return false

# 一轮结束后判断: 停止 / reroll / 进波。返回决策结果供链驱动下一步。
# 返回字典:
#   action: "stop_manual" | "stop_no_reroll" | "reroll"
#   stop_manual: 出现 manual, 留待玩家手动, 不进波
#   stop_no_reroll: 不能 reroll (全买不起/金币不足/预算超/全锁死), 按 auto_start 决定进波
#   reroll: 可刷新, 链执行 reroll 后延迟, 再据 auto_enabled 决定进下一轮或停
#   reroll_price: action=reroll 时的本次价格
#   should_auto_start: action=stop_no_reroll 时是否应进波
#   reason: 停止原因 (日志用)
static func decide_round_outcome(ui_adapter, player_index: int, rd: Dictionary, reroll_spent: int, general: Dictionary) -> Dictionary:
	# 停止条件:出现手动直接停(不进波判断)
	if _has_manual(rd):
		_Logger.info("停止: 出现 manual 玩家=%d" % player_index, _LOG_NAME)
		return {"action": "stop_manual"}

	# 能否刷新检查:全买不起 / 客观不能 reroll 都算不能刷新。
	var reroll_check := _can_reroll(ui_adapter, player_index, reroll_spent)
	var cannot_reroll := false
	var cannot_reason := ""
	if _all_unpurchased_insufficient(rd):
		cannot_reroll = true
		cannot_reason = "所有未购买商品都余额不足"
	elif not bool(reroll_check.get("ok", false)):
		cannot_reroll = true
		cannot_reason = str(reroll_check.get("reason", ""))

	if cannot_reroll:
		var should_auto_start: bool = bool(general["auto_start_wave"])
		_Logger.info("停止: 无法刷新(%s) 玩家=%d auto_start=%s" % [
			cannot_reason, player_index, str(should_auto_start)
		], _LOG_NAME)
		return {"action": "stop_no_reroll", "should_auto_start": should_auto_start, "reason": cannot_reason}

	# 能刷新: 无论自动化开关与否都执行一次 reroll (手动触发时含一次刷新,
	# 让玩家看到刷新后的新候选)。是否进下一轮由链在 reroll 后据 auto_enabled 判断。
	return {"action": "reroll", "reroll_price": int(reroll_check.get("price", 0))}

# 执行 reroll。返回是否成功 (失败则链停止)。
static func execute_reroll(ui_adapter, player_index: int) -> bool:
	return ui_adapter.at_reroll_shop(player_index, true)

# 构造会话 summary (链结束时调用)。
static func build_summary(purchases: int, locks: int, skips: int, manuals: int, rounds: int, reroll_spent: int, should_auto_start: bool, has_manual_pending: bool) -> Dictionary:
	_Logger.info("会话结束: 购买=%d 锁定=%d 跳过=%d 手动=%d 轮数=%d auto_start=%s" % [
		purchases, locks, skips, manuals, rounds, str(should_auto_start)
	], _LOG_NAME)
	return {
		"purchases": purchases,
		"locks": locks,
		"skips": skips,
		"manuals": manuals,
		"rounds": rounds,
		"reroll_spent": reroll_spent,
		"should_auto_start": should_auto_start,
		"has_manual_pending": has_manual_pending,
	}


# ============================================================================
# 单轮执行 (turbo 同步路径专用)
# ============================================================================

# 运行一轮 (turbo 同步路径): 逐 entry 决策+执行, 复用 process_one_entry。
# turbo 无延迟, for 循环一口气跑完。
static func _run_one_round(ui_adapter, player_index: int) -> Dictionary:
	var entries: Array = _Data.get_shop_entries(ui_adapter, player_index)
	var rd := new_round_state()

	for entry in entries:
		process_one_entry(ui_adapter, player_index, entry, rd)

	_Logger.info("轮结束 entries=%d | 买=%d 锁=%d 跳过=%d 手动=%d | has_manual=%s has_locked=%s has_skipped=%s" % [
		entries.size(), rd["purchases"], rd["locks"], rd["skips"], rd["manuals"],
		rd["has_manual"], rd["has_locked"], rd["has_skipped"]
	], _LOG_NAME)
	return rd


# ============================================================================
# 停止条件
# ============================================================================

static func _has_manual(rd: Dictionary) -> bool:
	return bool(rd.get("has_manual", false))


static func _has_skipped(rd: Dictionary) -> bool:
	return bool(rd.get("has_skipped", false))


# 所有未购买商品都不可负担(currency < price)。
# 只看自算的 is_affordable(客观可执行性),不管执行结果。
static func _all_unpurchased_insufficient(rd: Dictionary) -> bool:
	var actions: Array = rd.get("actions", [])
	if actions.empty():
		return false

	var has_unpurchased := false
	for a in actions:
		var executed: String = String(a.get("executed", ""))
		if executed == _ExecuteResult.RESULT_PURCHASED:
			continue
		has_unpurchased = true
		if bool(a.get("is_affordable", false)):
			return false

	return has_unpurchased


# ============================================================================
# Reroll 判断
# ============================================================================

static func _can_reroll(ui_adapter, player_index: int, reroll_spent: int) -> Dictionary:
	var cfg = _Config.get_instance()
	if cfg == null:
		return {"ok": false, "price": 0, "reason": "no config"}

	var price: int = _Data.get_reroll_price(ui_adapter, player_index)
	var gold: int = _Data.get_player_gold(player_index)
	var general: Dictionary = cfg.get_general()

	if gold < price:
		return {"ok": false, "price": price, "reason": "金币不足 gold=%d price=%d" % [gold, price]}

	# reroll_budget = 0 表示不限制(无限预算),只受 gold >= price 约束。
	# > 0 时作为单次 reroll 价格上限:本次 reroll 价格超过 budget 则拒绝。
	# (与 AUTOTATO_REROLL_BUDGET_DESC 文案 "单次刷新价格的上限, 超过此值不自动刷新 (0=不限)" 一致)
	var budget: int = general["reroll_budget"]
	if budget > 0 and price > budget:
		return {"ok": false, "price": price, "reason": "单次价格超 reroll_budget price=%d budget=%d" % [price, budget]}

	# 锁定项上限
	if typeof(RunData) == TYPE_OBJECT and typeof(ItemService) == TYPE_OBJECT:
		if RunData.has_method("get_player_locked_shop_items"):
			var locked = RunData.get_player_locked_shop_items(player_index)
			if typeof(locked) == TYPE_ARRAY and locked.size() >= ItemService.NB_SHOP_ITEMS:
				return {"ok": false, "price": price, "reason": "全部锁定, 无法刷新"}

	return {"ok": true, "price": price, "reason": ""}


# ============================================================================
# 私有 helpers
# ============================================================================

static func _empty_summary() -> Dictionary:
	return {
		"purchases": 0,
		"locks": 0,
		"skips": 0,
		"manuals": 0,
		"rounds": 0,
		"reroll_spent": 0,
		"should_auto_start": false,
		"has_manual_pending": false,
	}
