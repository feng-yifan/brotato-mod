# =============================================================================
# AT_WeaponDataUtil — WeaponData 访问工具
# =============================================================================
# vanilla 中武器数据是 `class_name WeaponData extends ItemParentData`
# (items/global/weapon_data.gd), 与道具 (ItemData) 共享父类, 所以下列字段
# 与 ItemData 一致, 直接复用 AT_ItemDataUtil:
#   - my_id / name / tier / value / effects / is_lockable / is_cursed ...
#
# WeaponData 自身额外的关键字段 (本文件负责的):
#   - weapon_id : String        武器升级链唯一 ID, 如 "weapon_fist"
#                               (与 my_id 不同, my_id 含 tier, 如 "weapon_fist_4")
#   - type      : int (enum)    WeaponData.Type {MELEE = 0, RANGED = 1}
#                               注: WeaponType 全局枚举值与此一致
#   - sets      : Array<SetData> 升级链 / 武器组 (如 "unarmed"), 决定 set 加成
#   - stats     : WeaponStats    武器统计 Resource (damage/range/scaling_stats 等)
#   - scene     : PackedScene    场景预制
#   - upgrades_into : WeaponData 下一 tier 武器引用
#
# vanilla 升级机制: 同一 weapon_id (set 内同条升级链) 同 tier 的 5 把武器
# 可合并升级为更高 tier; 武器槽位上限通过 effect `weapon_slot` (Keys.weapon_slot_hash)
# 维护, 默认初值 6, 受角色 / 道具 effect 增减.
# =============================================================================

class_name AT_WeaponDataUtil
extends Reference


# 复用 ItemData 工具, 避免重复实现 _field / id / tier / value / effects 等
const ITEM = preload("res://mods-unpacked/fengyifan-AutoTato/autotato/data/item_data_util.gd")

# vanilla WeaponType / WeaponData.Type 枚举别名 (避免硬依赖 vanilla class_name)
const CLASS_MELEE: int = 0
const CLASS_RANGED: int = 1


# -----------------------------------------------------------------------------
# 内部: 字段访问 (与 AT_ItemDataUtil._field 同语义, 抄一份避免 cross-class private)
# -----------------------------------------------------------------------------

static func _field(weapon_data, field_name: String, default_value = null):
	if weapon_data == null:
		return default_value
	if weapon_data is Resource:
		var v = weapon_data.get(field_name)
		if v == null:
			return default_value
		return v
	if weapon_data is Dictionary:
		return weapon_data.get(field_name, default_value)
	return default_value


# -----------------------------------------------------------------------------
# 基础字段 (复用 AT_ItemDataUtil)
# -----------------------------------------------------------------------------

# 取 WeaponData.my_id (含 tier, 如 "weapon_fist_4"); 未取到返回空串.
static func get_weapon_id(weapon_data) -> String:
	return ITEM.get_id(weapon_data)


# 取 Tier (0-6 枚举值); 未取到返回 0.
static func get_weapon_tier(weapon_data) -> int:
	return ITEM.get_tier(weapon_data)


# 取基础价格 (value 字段, 不含 shop 修饰); 未取到返回 0.
static func get_base_value(weapon_data) -> int:
	return ITEM.get_base_value(weapon_data)


# -----------------------------------------------------------------------------
# 武器专属字段
# -----------------------------------------------------------------------------

# 取武器近战 / 远程类别. 优先读 vanilla `type` 字段 (WeaponData.Type 枚举: 0=MELEE,
# 1=RANGED, 与全局 WeaponType 一致); 直接读不到则按 my_id 与 scaling_stats 推断;
# 均失败默认 CLASS_MELEE.
static func get_weapon_class(weapon_data) -> int:
	# 1. 首选: vanilla WeaponData.type 字段
	var v = _field(weapon_data, "type", null)
	if v != null and (typeof(v) == TYPE_INT or typeof(v) == TYPE_REAL):
		return int(v)
	# 2. 退化推断: my_id 后缀 / scaling_stats 标签
	var stats = _field(weapon_data, "stats", null)
	if stats != null:
		var scaling = _field(stats, "scaling_stats", [])
		if scaling is Array:
			for entry in scaling:
				var key_str: String = ""
				if entry is Array and entry.size() > 0:
					key_str = str(entry[0])
				elif typeof(entry) == TYPE_STRING:
					key_str = entry
				if "ranged" in key_str:
					return CLASS_RANGED
				if "melee" in key_str:
					return CLASS_MELEE
	return CLASS_MELEE


# 取武器所属升级链 / 武器组 (Array<SetData>); 未取到返回 [].
# 真实 .tres 字段名为 `sets` (WeaponData.sets, ExtResource 数组).
static func get_weapon_sets(weapon_data) -> Array:
	var v = _field(weapon_data, "sets", [])
	if v is Array:
		return v
	return []


# 取武器统计 Resource (WeaponStats / MeleeWeaponStats / RangedWeaponStats), 无则 null.
# 真实 .tres 字段名为 `stats` (WeaponData.stats).
static func get_weapon_stats(weapon_data):
	return _field(weapon_data, "stats", null)


# 取 weapon_id (升级链 ID, 同链同 weapon_id, 与 my_id 不同).
# 例如 "weapon_fist" (而 my_id 为 "weapon_fist_4").
static func get_weapon_chain_id(weapon_data) -> String:
	var v = _field(weapon_data, "weapon_id", "")
	return str(v) if v != null else ""


# 武器加成的属性数组 (来自 WeaponStats.scaling_stats);
# 形如 [["stat_melee_damage", 1.0], ...]. 失败返回 [].
static func get_scaling_stats(weapon_data) -> Array:
	var stats = get_weapon_stats(weapon_data)
	if stats == null:
		return []
	var v = _field(stats, "scaling_stats", [])
	if v is Array:
		return v
	return []


# 是否为唯一武器: vanilla WeaponData 没有显式 is_unique 字段, 沿用 ItemData 的
# max_nb == 1 推断. 注: 大多数武器 max_nb = -1 (无限), 唯一武器 max_nb = 1.
static func is_unique_weapon(weapon_data) -> bool:
	return ITEM.get_max_amount(weapon_data) == 1


# -----------------------------------------------------------------------------
# 运行时查询 (与 vanilla RunData 交互)
# -----------------------------------------------------------------------------

# 玩家当前持有的武器数组 (复制副本, 决策器只读).
# 失败 (RunData 未就绪) 返回 [].
static func get_player_weapons(player_index: int = 0) -> Array:
	if typeof(RunData) == TYPE_NIL:
		return []
	if not RunData.has_method("get_player_weapons"):
		return []
	var result = RunData.get_player_weapons(player_index)
	if result is Array:
		return result
	return []


# 统计玩家手上与 weapon_data 同 set 同 tier 的武器数量 (含自身定义那把, 不含外部传入).
# vanilla 升级机制: 同 weapon_id 同 tier 5 把可升级为更高 tier.
# 这里按 "同 weapon_id (升级链) + 同 tier" 计数, 用于预测下一关能否升级.
# 失败返回 0.
static func count_same_set_same_tier(weapon_data, player_index: int = 0) -> int:
	var target_chain_id: String = get_weapon_chain_id(weapon_data)
	var target_tier: int = get_weapon_tier(weapon_data)
	if target_chain_id == "":
		return 0
	var weapons: Array = get_player_weapons(player_index)
	var count: int = 0
	for w in weapons:
		if get_weapon_chain_id(w) == target_chain_id and get_weapon_tier(w) == target_tier:
			count += 1
	return count


# 武器槽位上限. vanilla 通过 effect key `weapon_slot` (Keys.weapon_slot_hash)
# 维护, 玩家初值 6, 受角色与道具 effect 增减.
# RunData / Keys 缺失返回默认 6.
# 注: Godot 3 解析器不识别 mod 里的 autoload 名字, 用 Object.get() 单参版探测字段
# 比 `"xxx" in Keys` 更安全 (后者在解析期会因 Keys 推为 null 而报错).
static func get_max_weapons(player_index: int = 0) -> int:
	if typeof(RunData) == TYPE_NIL or not RunData.has_method("get_player_effect"):
		return 6
	if typeof(Keys) == TYPE_NIL:
		return 6
	var hash_value = Keys.get("weapon_slot_hash")
	if hash_value == null:
		return 6
	var raw = RunData.get_player_effect(hash_value, player_index)
	if typeof(raw) == TYPE_INT or typeof(raw) == TYPE_REAL:
		return int(raw)
	return 6
