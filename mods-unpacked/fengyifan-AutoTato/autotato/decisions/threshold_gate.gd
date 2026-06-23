extends Reference
class_name AT_ThresholdGate

# ============================================================================
# AutoTato — Threshold Gate (三模式阈值闸门 + 联动闭包扫描)
# ----------------------------------------------------------------------------
# 职责:
#   判断一个物品 (或升级项) 是否应因"全部相关 stat 都触达限制"被反转 (从
#   "应购买"翻成"应丢弃"). 这是决策层最后一道闸门, 评分器已认为该物品对玩家
#   有正向收益, 但用户可能不希望某个 stat 超过上限 (如 stat_armor 上限 30),
#   或低于某个下限 (如 stat_speed 下限 30, 任何会再降 speed 的物品都丢).
#
# 三种 mode 的语义:
#   upper     —— 该 stat 当前值 >= value 即触达上限; current < value 表示
#                "还有空间增长", 该 stat 视为"未触达".
#   lower     —— 该 stat 当前值 <  value 即触达下限; current >= value 表示
#                "还可以再降", 该 stat 视为"未触达".
#   unlimited —— 永远不触达限制. 等价于"用户对该 stat 不设限".
#
# 反转规则 (用户给的核心规则):
#   1. 任一 related stat 未触达, 不反转 (should_reject = false).
#   2. 任一 related stat 配成 unlimited, 不反转 (因永远不触达 = 未触达).
#   3. 仅当全部 related stat 都触达限制, 才反转 (should_reject = true).
#   这是 B 项语义 (用户在 P0 设计中明确): "任一未触达即不反转".
#
# 联动闭包扫描:
#   有些物品本身并不直接修饰用户配阈值的那个 stat, 但通过 vanilla 的联动
#   机制 (Padding / Esty's Couch 等) 间接影响. 例如:
#     gain_stat_for_every_stat: stat_armor 每点带来 stat_max_hp +1
#   若玩家身上已有此联动, 物品给 stat_armor 也会"通过联动"加到 stat_max_hp.
#   因此判断该物品是否真正"被阈值闸门拦下", 必须把玩家身上的联动 effect 也
#   纳入相关 stat 闭包.
#
#   闭包扫描策略:
#     - 只扫一轮 (与 vanilla 实际行为一致: vanilla 也不递归二次传播)
#     - 扫 3 类联动 bucket: gain_stat_for_every_stat / gain_stat_for_every_perm_stat / convert_stat
#     - 双向: in_stat 在 related 时加 out_stat; out_stat 在 related 时加 in_stat
#     - 非 stat_* 端点 (如 Vampire 的 percent_missing_hp → lifesteal) 不入闭包,
#       _hash_to_stat_key 会过滤掉这种 hash
#
# 与 P0 数据层对接点:
#   - ItemU.get_raw_effects(item) 拿 vanilla Effect 数组
#   - Parser.parse_list(effects) 解析成 EffectInfo
#   - info.is_stat_modifier() 过滤出"直接 stat 加成"
#   - info.stat_key 即关心的 stat key
#   - Keys.hash_to_string / Object.get 单参版做 hash <-> string 反查
# ============================================================================


const Parser = preload("res://mods-unpacked/fengyifan-AutoTato/autotato/data/effect_parser.gd")
const Schema = preload("res://mods-unpacked/fengyifan-AutoTato/autotato/data/effect_schema.gd")
const EKeys  = preload("res://mods-unpacked/fengyifan-AutoTato/autotato/data/effect_keys.gd")
const ItemU  = preload("res://mods-unpacked/fengyifan-AutoTato/autotato/data/item_data_util.gd")

const LOG_NAME := "fengyifan-AutoTato:ThresholdGate"

# 三种 mode 标识 (字符串形式, 与 session_config.json 直接对齐)
const MODE_UNLIMITED := "unlimited"
const MODE_UPPER     := "upper"
const MODE_LOWER     := "lower"

# 支持阈值的 stat 白名单 (24 项):
#   - 16 主要 stat (与 EffectKeys.STAT_TAGS 字典 + Modding_Notes 16 标签对齐)
#   - 1 个 stat_curse (Curse 角色, 设计上是负向但仍可设阈值)
#   - 7 个常用次要 stat / 杂项数值键 (基于 wiki 常用诉求)
# 决策器调用方不应给这之外的 stat 设阈值, 给了也只会"未匹配 = 不参与判断".
const SUPPORTED_THRESHOLD_STATS := [
	"stat_max_hp", "stat_hp_regeneration", "stat_lifesteal", "stat_damage",
	"stat_melee_damage", "stat_ranged_damage", "stat_elemental_damage",
	"stat_percent_damage", "stat_attack_speed", "stat_crit_chance",
	"stat_engineering", "stat_range", "stat_armor", "stat_dodge",
	"stat_speed", "stat_luck", "stat_harvesting",
	"xp_gain", "pickup_range", "explosion_damage", "pierce_damage",
	"bonus_damage_against_bosses", "structure_attack_speed",
	"chance_double_gold", "stat_curse",
]

# 联动 effect 的 RunData bucket 名字 (作为 Keys 上的 "<name>_hash" 成员探测).
# 注意:
#   - 仅 3 类联动桶, 不包含 weapon_class_bonus (其输入是武器类, 非 stat)
#   - vanilla 的实际桶名/key 在不同子系统略有差异, 拿不到 hash 时 _collect_linkage_stats
#     会安全 skip (容错优先, 不强依赖具体 hash 存在)
const LINKAGE_BUCKETS := [
	"gain_stat_for_every_stat",
	"gain_stat_for_every_perm_stat",
	"convert_stat",
]


# ============================================================================
# 公开 API
# ============================================================================

# 主入口: 判断物品是否应因"全部相关 stat 都触达限制"被反转.
#
# 输入:
#   item_data        — ItemData Resource 或 Dictionary (双形态, 走 ItemU 抽象)
#   threshold_config — Dictionary, 形如:
#                        {
#                          "stat_armor":    {"mode": "upper", "value": 30},
#                          "stat_lifesteal":{"mode": "upper", "value": 50},
#                          "stat_damage":   {"mode": "unlimited", "value": 0},
#                        }
#                      未配的 stat 视为隐式 unlimited (即"不参与阈值判断").
#   player_index     — 本地 1P=0
#
# 返回 Dictionary:
#   should_reject     — bool, 全部 configured stat 触达上下限时为 true
#   related_stats     — Array<String>, 物品涉及的 stat (含联动闭包扩展)
#   configured_stats  — Array<String>, related_stats ∩ threshold_config.keys()
#   reason            — String, 中文原因, 仅日志诊断用
static func should_reject_by_threshold(
		item_data,
		threshold_config: Dictionary,
		player_index: int = 0
	) -> Dictionary:
	var result: Dictionary = {
		"should_reject": false,
		"related_stats": [],
		"configured_stats": [],
		"reason": "",
	}

	# 1. 收集物品自身 stat
	var direct_stats: Array = _collect_item_direct_stats(item_data)

	# 2. 扫一轮玩家身上联动 effect 扩展 related_stats
	var related_stats: Array = _collect_linkage_stats(direct_stats, player_index)
	result["related_stats"] = related_stats

	# 3. 求 related_stats ∩ threshold_config.keys() = configured_stats
	var configured_stats: Array = []
	for stat_key in related_stats:
		if threshold_config.has(stat_key):
			configured_stats.append(stat_key)
	result["configured_stats"] = configured_stats

	# 4. 若 configured_stats 空 -> should_reject=false (用户没给任何相关 stat 设限)
	if configured_stats.size() == 0:
		result["reason"] = "无相关阈值配置, 不反转"
		return result

	# 5. 对 configured_stats 每个 stat 按 mode 检查
	for stat_key in configured_stats:
		var cfg = threshold_config[stat_key]
		if typeof(cfg) != TYPE_DICTIONARY:
			# 配置形态异常, 视为 unlimited (不限) -> 不反转
			result["reason"] = "stat %s 配置非 Dictionary, 视为不限" % stat_key
			return result

		var mode: String = String(cfg.get("mode", MODE_UNLIMITED))
		var value: int = int(cfg.get("value", 0))

		# unlimited -> 立即返回 false (任一不限即不反转)
		if mode == MODE_UNLIMITED:
			result["reason"] = "stat %s 配为 unlimited, 不反转" % stat_key
			return result

		var current: int = _get_current_stat_value(stat_key, player_index)

		# upper, current < value -> 任一未触达上限即不反转
		if mode == MODE_UPPER and current < value:
			result["reason"] = "stat %s upper 未触达 (current=%d < value=%d)" % [stat_key, current, value]
			return result

		# lower, current >= value -> 任一未触达下限即不反转
		if mode == MODE_LOWER and current >= value:
			result["reason"] = "stat %s lower 未触达 (current=%d >= value=%d)" % [stat_key, current, value]
			return result

		# 未知 mode 视为 unlimited (容错: 不反转)
		if mode != MODE_UPPER and mode != MODE_LOWER:
			result["reason"] = "stat %s 未知 mode=%s, 视为不限" % [stat_key, mode]
			return result

	# 6. 所有 configured_stats 都触达 -> should_reject=true
	result["should_reject"] = true
	result["reason"] = "全部 %d 个相关 stat 已触达限制" % configured_stats.size()
	return result


# 升级 (Level-up 选项) 专用入口.
# UpgradeData extends ItemData, 字段相同 (effects / tier 等都在),
# 直接委托 should_reject_by_threshold 即可.
static func should_reject_upgrade_by_threshold(
		upgrade_data,
		threshold_config: Dictionary,
		player_index: int = 0
	) -> Dictionary:
	return should_reject_by_threshold(upgrade_data, threshold_config, player_index)


# ============================================================================
# 私有 helper
# ============================================================================

# 从 item.effects 解析出"该物品直接涉及"的 stat 集合.
# 流程: ItemU.get_raw_effects -> Parser.parse_list -> filter is_stat_modifier
#       -> 收集 info.stat_key (去重).
static func _collect_item_direct_stats(item_data) -> Array:
	var result: Array = []
	if item_data == null:
		return result
	var raw_effects: Array = ItemU.get_raw_effects(item_data)
	if raw_effects.size() == 0:
		return result
	var parsed: Array = Parser.parse_list(raw_effects, 0)
	for info in parsed:
		if info == null:
			continue
		# 仅认 SUM + stat_* 直接修饰, 排除 KEY_VALUE / REPLACE 类
		if not info.is_stat_modifier():
			continue
		var stat_key: String = info.stat_key
		if stat_key == "":
			continue
		if not result.has(stat_key):
			result.append(stat_key)
	return result


# 扫一轮玩家身上的联动 effect, 扩展 related_stats 集合.
# 不修改入参 seed_stats, 返回新数组 (含原集合 + 联动扩展).
#
# 容错策略:
#   - RunData / Keys 任一未就绪 -> 直接返回 seed.duplicate(), 不做扫描
#   - 某 bucket 在 Keys 上没有对应 <name>_hash -> skip 该 bucket
#   - bucket 不是 Array -> skip
#   - entry 不是 Array 或 size < 2 -> skip
#   - 非 stat_* 端点 (_hash_to_stat_key 返回 "") 不入闭包
#
# 双向传播规则:
#   entry 形如 [in_stat_hash, in_value, out_stat_hash, out_value, ...]
#   - in 在 related && out 是 stat_* && out 不在 related -> 加 out
#   - out 在 related && in 是 stat_* && in 不在 related -> 加 in
# 只扫一轮, 不二次传播 (与 vanilla 行为一致).
static func _collect_linkage_stats(seed_stats: Array, player_index: int) -> Array:
	var result: Array = seed_stats.duplicate()

	# RunData / Keys 都是 vanilla autoload, 任一缺失就放弃扫描
	if typeof(RunData) != TYPE_OBJECT:
		return result
	if typeof(Keys) != TYPE_OBJECT:
		return result
	if not RunData.has_method("get_player_effect"):
		return result

	for bucket_name in LINKAGE_BUCKETS:
		# 用 Object.get 单参版探测 Keys.<bucket_name>_hash 是否存在
		# (Godot 3 静态解析器看不到 autoload 字段, 这是访问 Keys 唯一稳妥姿势)
		var hash_field: String = "%s_hash" % bucket_name
		var hash_key = Keys.get(hash_field)
		if hash_key == null:
			# 该联动桶在当前 vanilla 版本无预定义 hash, 安全跳过
			continue

		var bucket = RunData.get_player_effect(hash_key, player_index)
		if not bucket is Array:
			continue

		for entry in bucket:
			if not entry is Array:
				continue
			if entry.size() < 2:
				continue

			# entry[0] 是 in_stat_hash, entry[2] (若存在) 是 out_stat_hash
			var in_stat: String = _hash_to_stat_key(entry[0])
			var out_stat: String = ""
			if entry.size() >= 3:
				out_stat = _hash_to_stat_key(entry[2])

			# 双向: in 在 related && out 是 stat_* -> 加 out
			if in_stat != "" and result.has(in_stat) and out_stat != "" and not result.has(out_stat):
				result.append(out_stat)
			# 双向: out 在 related && in 是 stat_* -> 加 in
			if out_stat != "" and result.has(out_stat) and in_stat != "" and not result.has(in_stat):
				result.append(in_stat)

	return result


# 用 Keys.hash_to_string 字典反查 hash -> stat key 字符串.
# 仅当反查结果以 "stat_" 开头时返回, 否则返回空串.
#
# 为什么过滤非 stat_:
#   vanilla 的联动 effect 允许 in_stat / out_stat 是非 stat 的 misc key
#   (例如 Vampire 的 percent_missing_hp -> lifesteal). 这种端点不应进入
#   "相关 stat 闭包", 否则会把非 stat 的 percent_missing_hp 当 stat 处理,
#   后续 _get_current_stat_value / threshold_config 查询全部错位.
static func _hash_to_stat_key(key_hash) -> String:
	if typeof(Keys) != TYPE_OBJECT:
		return ""
	# Keys.hash_to_string 是 vanilla 在 generate_hash 时同步维护的 hash -> string
	# 字典 (singletons/keys.gd 第 8 行 var hash_to_string = {empty_hash: ""}).
	# 用 Object.get 单参版安全探测.
	var hash_dict = Keys.get("hash_to_string")
	if typeof(hash_dict) != TYPE_DICTIONARY:
		return ""
	var raw = hash_dict.get(key_hash, "")
	var as_str: String = String(raw)
	if as_str.begins_with("stat_"):
		return as_str
	return ""


# 读玩家当前 stat 值, 走 RunData.get_player_effect(Keys.<stat>_hash, player_index).
#
# 步骤:
#   1. 在 SUPPORTED_THRESHOLD_STATS 白名单内才查 (其他直接返回 0)
#   2. 用 Object.get 探测 Keys 上的 "<stat>_hash" 成员
#   3. 调 RunData.get_player_effect 拿当前值
#   4. 转 int 返回
#
# 任一步出问题 (autoload 未就绪 / hash 字段不存在 / 返回非数值) 都返回 0.
# 0 在 upper 模式下意味着"还没增长, 未触达上限", 在 lower 模式下意味着"已经
# 在底", 这是相对保守的 fallback.
static func _get_current_stat_value(stat_key: String, player_index: int) -> int:
	if stat_key == "":
		return 0
	if not SUPPORTED_THRESHOLD_STATS.has(stat_key):
		return 0
	if typeof(RunData) != TYPE_OBJECT:
		return 0
	if typeof(Keys) != TYPE_OBJECT:
		return 0
	if not RunData.has_method("get_player_effect"):
		return 0

	var hash_field: String = "%s_hash" % stat_key
	var hash_key = Keys.get(hash_field)
	if hash_key == null:
		# 该 stat 在当前 vanilla 版本无预定义 hash (例如 pierce_damage /
		# bonus_damage_against_bosses 这类次要 stat 可能未挂 _hash 成员),
		# 保守返回 0
		return 0

	var raw = RunData.get_player_effect(hash_key, player_index)
	if typeof(raw) == TYPE_INT:
		return int(raw)
	if typeof(raw) == TYPE_REAL:
		return int(raw)
	return 0


# 判断当前值是否已"触达限制":
#   mode == "upper"     -> current >= value (触达上限)
#   mode == "lower"     -> current <  value (触达下限)
#   mode == "unlimited" -> 永远 false (不触达)
#   其他未知 mode       -> 永远 false (视同 unlimited, 容错)
static func _is_at_limit(mode: String, current: int, value: int) -> bool:
	if mode == MODE_UPPER:
		return current >= value
	if mode == MODE_LOWER:
		return current < value
	# MODE_UNLIMITED 与 未知 mode
	return false
