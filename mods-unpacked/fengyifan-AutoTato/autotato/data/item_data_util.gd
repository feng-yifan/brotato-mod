# =============================================================================
# AT_ItemDataUtil — ItemData / Dict 双形态访问工具
# =============================================================================
# vanilla 中 ItemData extends ItemParentData (items/global/item_data.gd),
# 关键字段:
#   - my_id        : String           道具唯一 ID, 如 "item_anvil"
#   - name         : String           i18n key, 如 "ITEM_ANVIL"
#   - tier         : int (0-6)        稀有度 Tier 枚举值 (COMMON..NIGHTMARE)
#   - value        : int              基础价格 (商店实际价格还要叠加 effect 与 wave inflation)
#   - effects      : Array<Effect>    挂载效果 (Effect Resource)
#   - tags         : Array<String>    标签 (ItemData 自带, 非父类字段)
#   - max_nb       : int              上限张数, -1 = 无限, >0 = Limited
#   - is_lockable  : bool
#   - is_cursed    : bool
#   - curse_factor : float
#
# 然而 mod 链路中 item_data 偶尔以 Dictionary 形态出现 (ModLoader 间接传递 /
# 别的 mod 重写过 base_shop 缓存 / 序列化中间态), 因此本工具每个查询都走
# Resource / Dictionary 双路径, 给上层提供唯一稳定入口.
#
# 注意: vanilla **没有** `get_item_real_price()` 之类直接 API,
# 真实价格在 ItemService.get_value(wave, base_value, player_index, ...) 计算,
# 涉及 wave / inflation_modifier / items_price / specific_items_price 等多重 effect.
# 本工具的 get_real_price 仅做"基础价 × items_price 百分比"的轻量估算, 不包含 wave
# 通胀; 决策器若需要精确价格请直接调用 ItemService.get_value.
# =============================================================================

class_name AT_ItemDataUtil
extends Reference


# -----------------------------------------------------------------------------
# 内部: 统一字段访问
# -----------------------------------------------------------------------------

# 从 Resource 或 Dictionary 形态的 item_data 中取出字段 field_name.
# Godot 3 中 Resource.get(name) 在字段不存在时返回 null, 不会抛错.
static func _field(item_data, field_name: String, default_value = null):
	if item_data == null:
		return default_value
	if item_data is Resource:
		var v = item_data.get(field_name)
		if v == null:
			return default_value
		return v
	if item_data is Dictionary:
		return item_data.get(field_name, default_value)
	return default_value


# -----------------------------------------------------------------------------
# 基础字段查询
# -----------------------------------------------------------------------------

# 取道具唯一 ID, 例如 "item_anvil"; 未取到返回空串.
static func get_id(item_data) -> String:
	var v = _field(item_data, "my_id", "")
	return str(v) if v != null else ""


# 取道具显示名 (i18n key 形式, 如 "ITEM_ANVIL"); 未取到返回空串.
static func get_name(item_data) -> String:
	var v = _field(item_data, "name", "")
	return str(v) if v != null else ""


# 取 Tier (0-6 枚举值 COMMON..NIGHTMARE); 未取到返回 0.
static func get_tier(item_data) -> int:
	var v = _field(item_data, "tier", 0)
	return int(v) if v != null else 0


# 取基础价格 (value 字段, **不含 shop 修饰**); 未取到返回 0.
static func get_base_value(item_data) -> int:
	var v = _field(item_data, "value", 0)
	return int(v) if v != null else 0


# 取最大持有数量 max_nb. vanilla 中 -1 表示无限制, >0 表示 Limited 上限.
# 未取到字段或拿到 -1 都返回 -1 (统一视为"无上限").
static func get_max_amount(item_data) -> int:
	var v = _field(item_data, "max_nb", -1)
	return int(v) if v != null else -1


# 取标签数组 (ItemData.tags, 父类 ItemParentData 无此字段); 未取到返回 [].
static func get_tags(item_data) -> Array:
	var v = _field(item_data, "tags", [])
	if v is Array:
		return v
	return []


# 是否可锁定 (商店锁锁定).
static func is_lockable(item_data) -> bool:
	var v = _field(item_data, "is_lockable", false)
	return bool(v) if v != null else false


# 是否为诅咒道具.
static func is_cursed(item_data) -> bool:
	var v = _field(item_data, "is_cursed", false)
	return bool(v) if v != null else false


# 取原始 effects 数组 (Array<Effect Resource>); 未取到返回 [].
# 注意: 此处不解析 effect, 解析逻辑在 effect_parser.gd.
static func get_raw_effects(item_data) -> Array:
	var v = _field(item_data, "effects", [])
	if v is Array:
		return v
	return []


# -----------------------------------------------------------------------------
# 状态查询 (依赖 vanilla RunData)
# -----------------------------------------------------------------------------

# 玩家 player_index 当前持有 item_id 的数量.
# 失败 (RunData 未就绪 / 玩家不存在) 返回 0.
static func get_count_owned(item_id: String, player_index: int = 0) -> int:
	if item_id == null or item_id == "":
		return 0
	# RunData 是 vanilla autoload 单例, 直接引用即可
	if not Engine.has_singleton("RunData") and typeof(RunData) == TYPE_NIL:
		return 0
	var owned: Array = []
	# 优先用 vanilla 提供的 API, 避免直接戳 players_data
	if RunData.has_method("get_player_items"):
		# get_player_items 内部对 DUMMY_PLAYER_INDEX 已返回 [], 这里再做一次防御
		owned = RunData.get_player_items(player_index)
	else:
		return 0
	var count: int = 0
	for it in owned:
		if get_id(it) == item_id:
			count += 1
	return count


# 玩家 player_index 是否已达到 item_data 的持有上限.
# - max_nb <= 0 视为无限制, 永远返回 false
# - 否则比较已持有数量 >= max_nb
static func is_at_limit(item_data, player_index: int = 0) -> bool:
	var max_amount: int = get_max_amount(item_data)
	if max_amount <= 0:
		return false
	var item_id: String = get_id(item_data)
	if item_id == "":
		return false
	return get_count_owned(item_id, player_index) >= max_amount


# 估算真实价格 = base_value × (1 + items_price_pct / 100).
# TODO: 接入 vanilla 完整价格修正 (ItemService.get_value 包含 wave inflation /
# specific_items_price / endless_factor / weapons_price 等), 当前只做基础百分比.
# RunData / Keys 缺失时回落基础价.
static func get_real_price(item_data, player_index: int = 0) -> int:
	var base: int = get_base_value(item_data)
	if base <= 0:
		return 0
	var pct: float = 0.0
	# 尽量从 vanilla 取 items_price effect, 拿不到就用 base
	# 注: Godot 3 解析器不识别 mod 里的 autoload 名字, 用 Object.get() 单参版
	# 探测字段比 `"xxx" in Keys` 更安全 (后者在解析期会因 Keys 推为 null 而报错)
	if typeof(RunData) != TYPE_NIL and RunData.has_method("get_player_effect"):
		if typeof(Keys) != TYPE_NIL:
			var hash_value = Keys.get("items_price_hash")
			if hash_value != null:
				var raw = RunData.get_player_effect(hash_value, player_index)
				if typeof(raw) == TYPE_INT or typeof(raw) == TYPE_REAL:
					pct = float(raw)
	var final_value: float = float(base) * (1.0 + pct / 100.0)
	return int(max(0.0, final_value))
