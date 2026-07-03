extends Reference

# ============================================================================
# AutoTato — ThresholdGate (保守版)
# ----------------------------------------------------------------------------
# 判断物品是否应该被阈值规则拒绝。
# 初版只识别直接的 stat_* effect；复杂 effect 默认不拒绝，
# 避免误拒绝玩家想买的物品。后续再补独立 effect_reader.gd。
# ============================================================================

const _Config = preload("res://mods-unpacked/fengyifan-AutoTato/config/config.gd")
const _Data = preload("res://mods-unpacked/fengyifan-AutoTato/shop/shop_data_reader.gd")
const _Logger = preload("res://mods-unpacked/fengyifan-AutoTato/utils/logger.gd")

const _LOG_NAME := "ThresholdGate"

# ============================================================================
# 公开 API
# ============================================================================

# 返回 {reject: bool, stats: Array<String>}
static func should_reject_item(item_data, player_index: int) -> Dictionary:
	var cfg = _Config.get_instance()
	if cfg == null:
		return {"reject": false, "stats": []}

	var related_stats: Array = _collect_related_stats(item_data)
	# 物品不涉及任何配置过的 stat → 不拒绝
	if related_stats.empty():
		return {"reject": false, "stats": []}

	# 全或无: 所有相关 stat 都触达阈值才拒绝。
	# 未配置 stat → get_threshold 返回默认 unlimited → _is_threshold_reached 返回 false → 不拒绝。
	for stat_key in related_stats:
		var threshold: Dictionary = cfg.get_threshold(stat_key)
		var mode: String = threshold["mode"]
		var limit: float = float(threshold["value"])
		if not _is_threshold_reached(stat_key, player_index, mode, limit):
			return {"reject": false, "stats": []}

	return {"reject": true, "stats": related_stats.duplicate()}


# ============================================================================
# 私有: 收集物品涉及的 stat
# ============================================================================

static func _collect_related_stats(item_data) -> Array:
	var stats := []
	if item_data == null:
		return stats

	var effects: Array = _get_item_effects(item_data)

	for eff in effects:
		if typeof(eff) != TYPE_DICTIONARY and typeof(eff) != TYPE_OBJECT:
			continue

		var key: String = _effect_stat_key(eff)
		if key == "":
			continue

		if key.begins_with("stat_") and not stats.has(key):
			stats.append(key)

	return stats


# 提取 effect 的 stat key。
# 只处理直接 stat modifier；bucket (APPEND_KEY)、非 stat 类 effect 返回空。
static func _effect_stat_key(eff) -> String:
	var key: String = _eff_get(eff, "key")
	if key == "" or not key.begins_with("stat_"):
		# 尝试 custom_key (特殊桶效果等) — 保守模式下不深入
		return ""

	# storage_method: 跳过桶效果
	# 0=KEY_MODIFY, 1=KEY_VALUE, 2=APPEND_KEY, 3=APPEND_KEY_VALUE
	var storage_method: int = _eff_get_int(eff, "storage_method", 0)
	if storage_method == 2 or storage_method == 3:
		# APPEND_KEY / APPEND_KEY_VALUE: 保守跳过
		return ""

	# KEY_MODIFY (0) 或 KEY_VALUE (1) 是直接 stat 修改
	return key


# ============================================================================
# 私有: 阈值判断
# ============================================================================

static func _is_threshold_reached(stat_key: String, player_index: int, mode: String, limit: float) -> bool:
	var current: float = _Data.get_player_stat(stat_key, player_index)

	match mode:
		"upper":
			return current >= limit
		"lower":
			return current < limit
		"unlimited":
			return false
		_:
			return false


# ============================================================================
# 私有: 工具
# ============================================================================

static func _get_item_effects(item_data) -> Array:
	if item_data == null:
		return []
	var effs
	if typeof(item_data) == TYPE_DICTIONARY:
		effs = item_data.get("effects", [])
	else:
		effs = item_data.get("effects")
	if typeof(effs) == TYPE_ARRAY:
		return effs as Array
	return []


static func _eff_get(eff, key: String):
	var val
	if typeof(eff) == TYPE_DICTIONARY:
		val = eff.get(key, "")
	else:
		val = eff.get(key)
	return str(val) if val != null else ""


static func _eff_get_int(eff, key: String, default: int) -> int:
	var val
	if typeof(eff) == TYPE_DICTIONARY:
		val = eff.get(key, default)
	else:
		val = eff.get(key)
	return int(val) if val != null else default
