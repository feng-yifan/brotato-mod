extends Reference

# ============================================================================
# AutoTato — ShopAutomation
# ----------------------------------------------------------------------------
# 商店自动化流程编排。
# 统一入口 run_shop_decision() 先执行一轮决策，然后根据
# 商店自动化开关决定是否继续自动 reroll。
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

# 商店决策唯一入口。
# ui_adapter: base_shop 实例，需实现 at_execute_action() / at_reroll_shop() / at_wait_before_next_decision()
# 自动化开启 → 执行一轮后进入 reroll 循环; 关闭 → 仅执行一轮。
static func run_shop_decision(ui_adapter, player_index: int) -> Dictionary:
	var cfg = _Config.get_instance()
	if cfg == null:
		_Logger.warning("Config 未初始化，跳过商店决策", _LOG_NAME)
		return _empty_summary()

	var auto_enabled: bool = cfg.is_shop_automation_enabled()
	var turbo: bool = cfg.is_turbo_mode()
	var general: Dictionary = cfg.get_general()
	var delay: float = general["decision_step_delay"]

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
		cur_round = _run_one_round(ui_adapter, player_index, turbo, delay)
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

		# 能刷新:执行刷新
		if not ui_adapter.at_reroll_shop(player_index):
			_Logger.warning("reroll 执行失败，停止", _LOG_NAME)
			break

		reroll_spent += int(reroll_check.get("price", 0))
		_Logger.info("刷新 (第 %d 轮) 累计=%d gold=%d budget=%d" % [
			round_num, reroll_spent,
			_Data.get_player_gold(player_index), general["reroll_budget"]
		], _LOG_NAME)

		if not turbo:
			ui_adapter.at_wait_before_next_decision()

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
	}
	_Logger.info("会话结束: 购买=%d 锁定=%d 跳过=%d 手动=%d 轮数=%d auto_start=%s" % [
		total_purchases, total_locks, total_skips, total_manuals, round_num, str(should_auto_start)
	], _LOG_NAME)
	return summary


# ============================================================================
# 单轮执行
# ============================================================================

# 运行一轮: 逐 entry 决策 → 即时执行 → 汇总
static func _run_one_round(ui_adapter, player_index: int, turbo: bool, delay: float) -> Dictionary:
	var entries: Array = _Data.get_shop_entries(ui_adapter, player_index)

	var rd := {
		"purchases": 0,
		"locks": 0,
		"skips": 0,
		"manuals": 0,
		"has_skipped": false,
		"has_manual": false,
		"has_locked": false,
		"actions": [],
	}

	var performed_action := false

	for entry in entries:
		var shop_item = entry.get("shop_item")
		if not _Data.is_shop_item_active(shop_item):
			continue

		# 决策(纯 intent,不含余额事实)
		var decision: Dictionary = _ItemDecider.decide_shop_entry(entry, player_index)
		# IntentResult.make 保证 intent 字段必然存在,直接索引信任契约 —
		# 字段缺失即决策器违约,应报错暴露。
		var intent: String = String(decision["intent"])

		# 即时执行 → 消费执行结果
		var executed: String = ui_adapter.at_execute_action(intent, shop_item, player_index)

		# 重读 currency/price 自算 is_affordable(currency >= price),与决策正交,
		# 用于 reroll 停止条件。在执行之后读,反映循环中前序 purchase 扣减后的最新余额。
		# 接受两次 _Data 调用(decider 内部已读一次)以保持职责纯净。
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
		performed_action = true

		# 统计(用执行结果,不是决策意图)
		match executed:
			_ExecuteResult.RESULT_PURCHASED:
				rd["purchases"] += 1
			_ExecuteResult.RESULT_LOCKED:
				rd["locks"] += 1
				rd["has_locked"] = true
			_ExecuteResult.RESULT_MANUAL:
				rd["manuals"] += 1
				rd["has_manual"] = true
			_:
				rd["skips"] += 1
				rd["has_skipped"] = true

		# 非急速模式: 动作后延迟，让 UI 渲染可见
		if performed_action and not turbo and delay > 0.0:
			ui_adapter.at_wait_before_next_decision()

	_Logger.info("轮结束 entries=%d | 买=%d 锁=%d 跳=%d 手=%d | has_manual=%s has_locked=%s has_skipped=%s" % [
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
	}
