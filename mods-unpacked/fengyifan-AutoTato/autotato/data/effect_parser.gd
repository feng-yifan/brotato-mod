class_name AT_EffectParser
extends Reference

# ============================================================================
# AutoTato — Effect Parser (把 vanilla Effect Resource 压扁为 EffectInfo)
# ----------------------------------------------------------------------------
# 输入:
#   vanilla Effect Resource 实例, 可能是父类 Effect 本体, 或子类:
#     - DoubleKeyValueEffect    (多了 key2 / value2, 应解出 2 条)
#     - DoubleValueEffect       (多了 value2, 同 key 不同 value, 解出 2 条)
#     - EffectWithSubEffects    (含 sub_effects 数组, 递归展开)
#     - 未知子类                (走 _parse_default fallback, 1 条)
#
# 输出:
#   EffectInfo 数组 (parser 接口统一返回 Array, 一个 Effect → 1..N 条)。
#   永远返回 Array, 不返回 null; 解析失败/空输入也只返回 [], 调用方无需判空。
#
# 旧 mod bug 警示 (这里是重构核心动机):
#   旧 AutoTato 决策器只读 effect.key, 完全没看 custom_key 与 storage_method,
#   因此 Anvil 的 effect (key=stat_armor, custom_key=upgrade_random_weapon,
#   storage_method=KEY_VALUE) 被当成 "stat_armor +2", 即给玩家加 2 点护甲,
#   而 vanilla 实际行为是把 [stat_armor, 2] 追加到 upgrade_random_weapon
#   桶里, 代表 "随机升级一把武器, 该武器获得 stat_armor +2"。
#   parser 把四元组 (stat_key, custom_key, value, storage_method) 全部保留,
#   交给决策器结合 EffectKeys 元数据做正确分桶。
#
# custom_key fallback 策略:
#   - SUM / REPLACE 时 custom_key 为空是常态, 不告警;
#   - KEY_VALUE / APPEND_KEY / APPEND_KEY_VALUE 时 custom_key 必须非空,
#     否则 vanilla 的 apply() 会写到 effects[empty_hash] 里 (异常),
#     此时 log warning 一行, 仍按读到的值产出 EffectInfo (容错优先)。
# ============================================================================


const Schema = preload("res://mods-unpacked/fengyifan-AutoTato/autotato/data/effect_schema.gd")
const Keys = preload("res://mods-unpacked/fengyifan-AutoTato/autotato/data/effect_keys.gd")

const LOG_NAME := "fengyifan-AutoTato:EffectParser"


# ============================================================================
# 公开入口
# ============================================================================

# 单个 effect → EffectInfo 数组 (1..N 条)。
# player_index 仅用于将来需要时透传给子 parser, 当前实现不依赖玩家状态。
static func parse(effect: Resource, player_index: int = 0) -> Array:
	if effect == null:
		ModLoaderLog.warning("parse() got null effect, returning []", LOG_NAME)
		return []

	# 用 duck typing 取 get_id(): vanilla class_name (Effect / DoubleKeyValueEffect
	# 等) 在 mod 加载时不一定已经注册到全局, 用 is/as 容易在 _init 阶段炸,
	# 用 has_method + 字符串分派最稳。
	var script_id: String = "effect"
	if effect.has_method("get_id"):
		var raw_id = effect.get_id()
		if raw_id is String:
			script_id = raw_id

	match script_id:
		"double_key_value":
			return _parse_double_key_value(effect)
		"double_value":
			return _parse_double_value(effect)
		"effect_with_sub_effects":
			return _parse_sub_effects(effect, player_index)
		_:
			# 包含 "effect" 与所有未识别的子类, 都按单条 EffectInfo 处理。
			# 未来若发现新的需要特殊解析的子类, 在上面 match 加分支即可。
			return [_parse_default(effect)]


# 批量解析, 按顺序拼接每个 effect 的解析结果。
static func parse_list(effects: Array, player_index: int = 0) -> Array:
	var result := []
	if effects == null or effects.size() == 0:
		return result

	for effect in effects:
		if effect == null:
			continue
		var parsed: Array = parse(effect, player_index)
		for info in parsed:
			result.push_back(info)

	return result


# ============================================================================
# 私有 parser —— 按子类分派
# ============================================================================

# 父类 Effect (及未识别子类) 的默认解析路径, 产出 1 条 EffectInfo。
static func _parse_default(effect: Resource) -> Reference:
	var stat_key := _coerce_str(effect.get("key"))
	var custom_key := _coerce_str(effect.get("custom_key"))
	var value := _coerce_int(effect.get("value"))
	var storage_method := _coerce_int(effect.get("storage_method"))
	var effect_sign := _coerce_int(effect.get("effect_sign"))
	var custom_args := _coerce_array(effect.get("custom_args"))
	var script_id := _get_script_id(effect)

	_warn_custom_key_missing(stat_key, custom_key, storage_method, script_id)

	return Schema.make(
		stat_key,
		custom_key,
		value,
		storage_method,
		effect_sign,
		custom_args,
		script_id
	)


# DoubleKeyValueEffect: 同一个 custom_key 下挂 2 个 [key_hash, value_hash, ...]
# 子项 —— vanilla apply() 写的是 [key_hash, value, key2_hash, value2] 四元组,
# 决策器视角下这是两个独立的 stat 修饰, 都属于 custom_key 桶。
static func _parse_double_key_value(effect: Resource) -> Array:
	var custom_key := _coerce_str(effect.get("custom_key"))
	var storage_method := _coerce_int(effect.get("storage_method"))
	var effect_sign := _coerce_int(effect.get("effect_sign"))
	var custom_args := _coerce_array(effect.get("custom_args"))

	var stat_key := _coerce_str(effect.get("key"))
	var value := _coerce_int(effect.get("value"))
	var stat_key2 := _coerce_str(effect.get("key2"))
	var value2 := _coerce_int(effect.get("value2"))

	_warn_custom_key_missing(stat_key, custom_key, storage_method, "double_key_value")

	var first = Schema.make(
		stat_key, custom_key, value,
		storage_method, effect_sign, custom_args,
		"double_key_value"
	)
	var second = Schema.make(
		stat_key2, custom_key, value2,
		storage_method, effect_sign, custom_args,
		"double_key_value"
	)
	return [first, second]


# DoubleValueEffect: 同一个 key 用两个 value (e.g. [key_hash, value, value2]),
# 决策器视角下也拆成两条 EffectInfo, stat_key 共用, value 不同。
static func _parse_double_value(effect: Resource) -> Array:
	var stat_key := _coerce_str(effect.get("key"))
	var custom_key := _coerce_str(effect.get("custom_key"))
	var storage_method := _coerce_int(effect.get("storage_method"))
	var effect_sign := _coerce_int(effect.get("effect_sign"))
	var custom_args := _coerce_array(effect.get("custom_args"))

	var value := _coerce_int(effect.get("value"))
	var value2 := _coerce_int(effect.get("value2"))

	_warn_custom_key_missing(stat_key, custom_key, storage_method, "double_value")

	var first = Schema.make(
		stat_key, custom_key, value,
		storage_method, effect_sign, custom_args,
		"double_value"
	)
	var second = Schema.make(
		stat_key, custom_key, value2,
		storage_method, effect_sign, custom_args,
		"double_value"
	)
	return [first, second]


# EffectWithSubEffects: 主 effect 一条 + 递归展开 sub_effects 数组。
# 主条标记 source_script_id="effect_with_sub_effects", 子条由递归 parse() 决定
# 它们自己的 source_script_id (保持祖先类型, 便于诊断溯源)。
static func _parse_sub_effects(effect: Resource, player_index: int) -> Array:
	var result := []

	# 主 effect 自身: 复用 _parse_default 拿字段, 但改写 source_script_id。
	var stat_key := _coerce_str(effect.get("key"))
	var custom_key := _coerce_str(effect.get("custom_key"))
	var value := _coerce_int(effect.get("value"))
	var storage_method := _coerce_int(effect.get("storage_method"))
	var effect_sign := _coerce_int(effect.get("effect_sign"))
	var custom_args := _coerce_array(effect.get("custom_args"))

	_warn_custom_key_missing(stat_key, custom_key, storage_method, "effect_with_sub_effects")

	var head = Schema.make(
		stat_key, custom_key, value,
		storage_method, effect_sign, custom_args,
		"effect_with_sub_effects"
	)
	result.push_back(head)

	# 递归展开子 effects。
	var sub_effects := _coerce_array(effect.get("sub_effects"))
	for sub in sub_effects:
		if sub == null:
			continue
		var parsed: Array = parse(sub, player_index)
		for info in parsed:
			result.push_back(info)

	return result


# ============================================================================
# 工具函数
# ============================================================================

# 取 effect.get_id() 字符串, 失败回落 "effect"。
static func _get_script_id(effect: Resource) -> String:
	if effect != null and effect.has_method("get_id"):
		var raw = effect.get_id()
		if raw is String:
			return raw
	return "effect"


# KEY_VALUE 类 storage_method 需要 custom_key, 缺失则告警 (但仍输出, 容错优先)。
static func _warn_custom_key_missing(
	stat_key: String,
	custom_key: String,
	storage_method: int,
	source_id: String
) -> void:
	var needs_custom_key: bool = (
		storage_method == Schema.SM_KEY_VALUE
		or storage_method == Schema.SM_APPEND_KEY
		or storage_method == Schema.SM_APPEND_KEY_VALUE
	)
	if needs_custom_key and custom_key == "":
		ModLoaderLog.warning(
			"effect %s (key=%s) uses KEY_VALUE-family storage but custom_key is empty" % [source_id, stat_key],
			LOG_NAME
		)


# raw → int 安全转换 (Resource.get() 可能返回 null)。
static func _coerce_int(raw) -> int:
	if raw == null:
		return 0
	if raw is int:
		return raw
	if raw is float:
		return int(raw)
	if raw is String:
		return int(raw)
	return 0


# raw → String 安全转换。
static func _coerce_str(raw) -> String:
	if raw == null:
		return ""
	if raw is String:
		return raw
	return str(raw)


# raw → Array 安全转换 (null / 非 Array 视作空数组)。
static func _coerce_array(raw) -> Array:
	if raw == null:
		return []
	if raw is Array:
		return raw
	return []
