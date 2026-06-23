class_name AT_EffectSchema
extends Reference

# ============================================================================
# AutoTato — Effect Schema (解析后效果的不可变记录定义)
# ============================================================================
#
# 为什么不直接用 vanilla Effect Resource:
#   1. vanilla Effect 是 Resource, 字段散落在 .tres 文件里, 还和 PNG 图标、
#      i18n text_key 翻译耦合, 决策器只关心数值与目标桶, 不需要这些外围。
#   2. vanilla Effect.apply() 把 storage_method 的语义藏在分支里
#      (SUM 写主表 effects[key_hash] / REPLACE 覆盖主表 / KEY_VALUE 写到
#      custom_key 对应的二级桶 / APPEND_KEY / APPEND_KEY_VALUE), 决策器
#      想理解"这个 effect 影响哪个统计字段"必须复刻这段逻辑。
#   3. 决策器需要稳定、可哈希、可序列化的纯数据字段, Resource 的生命周期与
#      ModLoader 加载顺序耦合, 不便缓存。
#
# 因此 parser 阶段把 vanilla Effect 压扁成四元组:
#     (stat_key, custom_key, value, storage_method)
# 对应 vanilla 行为:
#     SUM               -> 写主表 effects[stat_key] += value
#     REPLACE           -> 覆盖主表 effects[stat_key] = value
#     KEY_VALUE         -> 写到 effects[custom_key] 的桶里, 子项 key=stat_key
#     APPEND_KEY        -> 把 stat_key 追加到 effects[custom_key] 数组
#     APPEND_KEY_VALUE  -> 把 [stat_key, value] 追加到 effects[custom_key]
#
# 同时保留 effect_sign: 评分阶段需要它判断正负向 ——
#   FROM_VALUE 时按 value 正负判断; POSITIVE/NEGATIVE 直接给定;
#   FROM_ARG / OVERRIDE / NEUTRAL 由 custom_args 或上下文决定, 保守按 value 判断。
# ============================================================================


# ---- vanilla 枚举的可读别名 (避免 EffectInfo.gd 必须加载 vanilla 全局类) ----
# 与 effects/enums/storage_method.gd / sign.gd 完全一致, 顺序敏感, 勿改。

const SM_SUM              := 0
const SM_KEY_VALUE        := 1
const SM_REPLACE          := 2
const SM_APPEND_KEY       := 3
const SM_APPEND_KEY_VALUE := 4

const SIGN_POSITIVE       := 0
const SIGN_NEGATIVE       := 1
const SIGN_NEUTRAL        := 2
const SIGN_FROM_VALUE     := 3
const SIGN_FROM_ARG       := 4
const SIGN_OVERRIDE       := 5


# ============================================================================
# 内部类 EffectInfo —— parsed effect 的不可变记录
# ============================================================================
class EffectInfo:
	extends Reference

	# 主统计字段 key (对应 vanilla Effect.key, 如 "stat_max_hp" / "stat_armor")。
	# KEY_VALUE 类 storage_method 下, 这个字段是子项 key, 而非真正的桶名。
	var stat_key: String = ""

	# KEY_VALUE / APPEND_* 时的桶名 (对应 vanilla Effect.custom_key,
	# 如 "upgrade_random_weapon"). SUM / REPLACE 时通常为空串。
	var custom_key: String = ""

	# 数值 (对应 vanilla Effect.value). 决策器评分的核心输入之一。
	var value: int = 0

	# storage_method 枚举值, 默认 SM_SUM, 见上方常量。
	var storage_method: int = SM_SUM

	# effect_sign 枚举值, 默认 SM_FROM_VALUE (vanilla 默认).
	var effect_sign: int = SIGN_FROM_VALUE

	# vanilla Effect.custom_args 的浅拷贝 (Array<Resource>),
	# parser 不再深入解析, 评分器需要时自行读取。
	var custom_args: Array = []

	# parser 生成的稳定签名, 用于缓存与去重:
	#   - is_key_value() 为 true: "stat_key@custom_key"
	#   - 否则: "stat_key"
	var signature: String = ""

	# 来源脚本 ID (对应 vanilla Effect.get_id(), 如 "double_key_value"),
	# 仅用于诊断日志, 决策器不应依赖。
	var source_script_id: String = ""


	# ---- 查询函数 ----

	# 是否是普通的 stat_* 加成 (SUM 写主表, 且 key 以 stat_ 开头)。
	# 决策器对这类效果可以直接走"加权求和"的简单评分。
	func is_stat_modifier() -> bool:
		return storage_method == SM_SUM and stat_key.begins_with("stat_")

	# 是否是覆盖型 (REPLACE) —— 评分时不能简单累加, 需要对比 base_value。
	func is_replace() -> bool:
		return storage_method == SM_REPLACE

	# 是否是 KEY_VALUE 系列 (KEY_VALUE / APPEND_KEY / APPEND_KEY_VALUE) ——
	# 这类效果写到 custom_key 对应的二级桶, 决策器需要按桶聚合。
	func is_key_value() -> bool:
		return storage_method == SM_KEY_VALUE \
			or storage_method == SM_APPEND_KEY \
			or storage_method == SM_APPEND_KEY_VALUE

	# 返回该 effect 写入的"逻辑桶"标识:
	#   KEY_VALUE 类 -> custom_key (真正的桶);
	#   其它       -> stat_key (主表 key 即桶)。
	func get_storage_bucket() -> String:
		if is_key_value():
			return custom_key
		return stat_key

	# 该 effect 对玩家是否"正向" —— 评分用。
	# FROM_VALUE 严格按 value 正负判断;
	# FROM_ARG / NEUTRAL / OVERRIDE 没有静态依据, 保守按 value >= 0 视为正向,
	# 避免把已知正向的 +0 数值 (如 "免疫" 一类) 误判为负。
	func is_positive_sign() -> bool:
		if effect_sign == SIGN_POSITIVE:
			return true
		if effect_sign == SIGN_NEGATIVE:
			return false
		if effect_sign == SIGN_FROM_VALUE:
			return value > 0
		# SIGN_FROM_ARG / SIGN_NEUTRAL / SIGN_OVERRIDE
		return value >= 0

	# 调试友好的字符串形式, 形如 [EffectInfo stat_armor@upgrade_random_weapon +2 KV]。
	func _to_string() -> String:
		var head: String = stat_key
		if custom_key != "":
			head = head + "@" + custom_key
		var sign_str: String = "+" if value >= 0 else ""
		var sm_str: String = ""
		match storage_method:
			SM_SUM:               sm_str = "SUM"
			SM_KEY_VALUE:         sm_str = "KV"
			SM_REPLACE:           sm_str = "REPLACE"
			SM_APPEND_KEY:        sm_str = "APP_K"
			SM_APPEND_KEY_VALUE:  sm_str = "APP_KV"
			_:                    sm_str = "?"
		return "[EffectInfo %s %s%d %s]" % [head, sign_str, value, sm_str]


# ============================================================================
# 顶层工厂 —— 供 parser 调用, 集中处理 signature 生成
# ============================================================================
static func make(
	stat_key: String,
	custom_key: String,
	value: int,
	storage_method: int,
	effect_sign: int,
	custom_args: Array,
	source_script_id: String = "effect"
) -> EffectInfo:
	# 创建 EffectInfo 实例, 填字段, 自动计算 signature。
	var info := EffectInfo.new()
	info.stat_key = stat_key
	info.custom_key = custom_key
	info.value = value
	info.storage_method = storage_method
	info.effect_sign = effect_sign
	info.custom_args = custom_args
	info.source_script_id = source_script_id

	# signature 规则:
	#   1. KEY_VALUE 类 -> "stat_key@custom_key";
	#   2. 否则:
	#      a. stat_key 非空 -> "stat_key";
	#      b. stat_key 为空但 custom_key 非空 (异常但可能出现) -> "custom_key";
	#      c. 都为空 -> "" (parser 不应产出这种, 但容错保留)。
	if info.is_key_value():
		info.signature = stat_key + "@" + custom_key
	elif stat_key != "":
		info.signature = stat_key
	elif custom_key != "":
		info.signature = custom_key
	else:
		info.signature = ""

	return info
