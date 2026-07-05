extends Reference

# ============================================================================
# AutoTato — ShopDataReader
# ----------------------------------------------------------------------------
# 集中读取 Brotato / vanilla 运行时数据，避免读取逻辑散落在
# base_shop / item_decider / shop_automation 中。
#
# 关键经验 (来自旧开发教训):
# - 购买货币: RunData.get_player_currency(player_index) 兼容 hp_shop
# - reroll 金币: RunData.get_player_gold(player_index) 永远用金币
# - 物品价格: ShopItem.value 已是 vanilla UI 同源价格 (含 hp_shop 折算)
# - item_data 兼容 Resource 与 Dictionary 双形态
# - _shop_items / _reroll_price 做防御式检查
# ============================================================================

const _Logger = preload("res://mods-unpacked/fengyifan-AutoTato/utils/logger.gd")

const _LOG_NAME := "ShopDataReader"

# ============================================================================
# 玩家数据
# ============================================================================

static func get_player_count() -> int:
	if typeof(RunData) != TYPE_OBJECT:
		return 1
	if RunData.has_method("get_player_count"):
		return int(RunData.get_player_count())
	var gold = RunData.get("gold")
	if typeof(gold) == TYPE_ARRAY:
		return (gold as Array).size()
	return 1

static func get_player_currency(player_index: int) -> int:
	if typeof(RunData) != TYPE_OBJECT:
		return 0
	if RunData.has_method("get_player_currency"):
		return int(RunData.get_player_currency(player_index))
	if RunData.has_method("get_player_gold"):
		return int(RunData.get_player_gold(player_index))
	return 0

static func get_player_gold(player_index: int) -> int:
	if typeof(RunData) != TYPE_OBJECT:
		return 0
	if RunData.has_method("get_player_gold"):
		return int(RunData.get_player_gold(player_index))
	return 0

static func get_current_wave() -> int:
	if typeof(RunData) == TYPE_OBJECT:
		var w = RunData.get("current_wave")
		if w != null:
			return int(w)
	return 0

static func get_player_stat(stat_key: String, player_index: int) -> float:
	if typeof(Utils) == TYPE_OBJECT and Utils.has_method("get_stat") \
		and typeof(Keys) == TYPE_OBJECT:
		return float(Utils.get_stat(int(Keys.generate_hash(stat_key)), player_index))
	if typeof(RunData) == TYPE_OBJECT and RunData.has_method("get_stat") \
		and typeof(Keys) == TYPE_OBJECT:
		return float(RunData.get_stat(int(Keys.generate_hash(stat_key)), player_index))
	return 0.0

# ============================================================================
# 商店数据
# ============================================================================

# 返回 Array<Dictionary>，每个 entry:
#   {shop_item: Node, item_data: Resource|Dictionary, item_id: String}
#
# 数据来源说明:
# - ShopItem 节点不在 base_shop._shop_items 里 (那里存的是 [item_data, wave_value] 数据快照)。
# - 节点在 shop_items_container._shop_items 里, 由 vanilla set_shop_items() 按索引填充,
#   与 base_shop._shop_items[player_index] 一一对应。
# - 通过 vanilla 虚方法 _get_shop_items_container() 取 container, 再读其 _shop_items 节点数组。
# - 节点自带 item_data / active / value / locked 等字段 (见 ShopItem.gd)。
static func get_shop_entries(base_shop, player_index: int) -> Array:
	var entries := []
	if base_shop == null:
		return entries

	var container = null
	if base_shop.has_method("_get_shop_items_container"):
		container = base_shop._get_shop_items_container(player_index)
	if container == null or not is_instance_valid(container):
		_Logger.warning("无法获取 shop_items_container 玩家=%d" % player_index, _LOG_NAME)
		return entries

	var shop_items = container.get("_shop_items")
	if typeof(shop_items) != TYPE_ARRAY:
		_Logger.warning("container._shop_items 不是 Array", _LOG_NAME)
		return entries

	for i in shop_items.size():
		var shop_item = shop_items[i]
		if shop_item == null or not is_instance_valid(shop_item):
			continue
		if not bool(shop_item.get("active")):
			continue

		var item_data = shop_item.get("item_data")
		var item_id := get_item_id(item_data)
		entries.append({
			"shop_item": shop_item,
			"item_data": item_data,
			"item_id": item_id,
		})

	return entries

# ============================================================================
# ShopItem 节点读取
# ============================================================================

static func get_item_data(shop_item) -> Dictionary:
	if shop_item == null:
		return {}
	var idata = shop_item.get("item_data")
	if idata == null:
		return {}
	if typeof(idata) == TYPE_DICTIONARY:
		return idata as Dictionary
	return idata

static func get_item_price(shop_item) -> int:
	if shop_item == null:
		return 0
	var val = shop_item.get("value")
	if typeof(val) == TYPE_INT or typeof(val) == TYPE_REAL:
		return int(val)
	return 0

static func is_shop_item_active(shop_item) -> bool:
	if shop_item == null:
		return false
	return bool(shop_item.get("active"))

static func is_shop_item_locked(shop_item) -> bool:
	if shop_item == null:
		return false
	return bool(shop_item.get("locked"))

static func is_shop_item_lockable(shop_item) -> bool:
	if shop_item == null:
		return false
	var idata = shop_item.get("item_data")
	if idata == null:
		return false
	return bool(idata.get("is_lockable"))

static func get_reroll_price(base_shop, player_index: int) -> int:
	if base_shop == null:
		return 0
	var prices = base_shop.get("_reroll_price")
	if typeof(prices) == TYPE_ARRAY and player_index < prices.size():
		return int(prices[player_index])
	return 0

# ============================================================================
# ItemData 读取 (兼容 Resource 与 Dictionary)
# ============================================================================

static func get_item_id(item_data) -> String:
	if item_data == null:
		return ""
	if typeof(item_data) == TYPE_DICTIONARY:
		return str(item_data.get("my_id", ""))
	if item_data.has_method("get"):
		var v = item_data.get("my_id")
		return str(v) if v != null else ""
	return ""

static func is_item_cursed(item_data) -> bool:
	if item_data == null:
		return false
	if typeof(item_data) == TYPE_DICTIONARY:
		var cursed = item_data.get("is_cursed", false)
		return bool(cursed) if cursed != null else false
	return bool(item_data.get("is_cursed"))

static func is_at_limit(item_data, player_index: int) -> bool:
	if item_data == null:
		return false
	if typeof(RunData) != TYPE_OBJECT:
		return false

	# 武器没有 max_nb 概念(WeaponData 不继承 ItemData,无该字段)。
	# 武器槽由 get_player_weapons 管理,不受物品限购约束。
	if item_data is WeaponData:
		return false

	# 优先用 vanilla API:get_remaining_max_nb_item 返回"剩余可购数",
	# 内部已处理 max_nb == -1 (无限制) 的情况。<= 0 即到上限。
	# 只对 ItemData 有效(签名要求 ItemData)。
	if item_data is ItemData and RunData.has_method("get_remaining_max_nb_item"):
		var remaining: int = RunData.get_remaining_max_nb_item(item_data, player_index)
		return remaining <= 0

	# 兜底:非 ItemData / vanilla API 不可用时,手动解析 max_nb(兼容 Dictionary 形态)。
	# max_nb 字段在 ItemData 上,不在 ItemParentData 基类;WeaponData 已在上面短路。
	var max_nb := 0
	if typeof(item_data) == TYPE_DICTIONARY:
		var mnb = item_data.get("max_nb", 0)
		max_nb = int(mnb) if mnb != null else 0
	else:
		# Resource.get 在属性不存在时返回 null;int(null) 会崩溃,必须守卫。
		var mnb_raw = item_data.get("max_nb")
		max_nb = int(mnb_raw) if mnb_raw != null else 0
	if max_nb <= 0:
		return false  # 0 / -1 都视为无限制

	var item_id := get_item_id(item_data)
	if item_id == "":
		return false

	if typeof(Keys) != TYPE_OBJECT:
		return false
	var owned := 0
	if RunData.has_method("get_owned_items"):
		owned = int(RunData.get_owned_items(int(Keys.generate_hash(item_id)), player_index))
	if owned >= max_nb:
		return true
	return false
