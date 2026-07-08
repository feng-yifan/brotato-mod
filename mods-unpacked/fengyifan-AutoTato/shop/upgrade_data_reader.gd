extends Reference

# ============================================================================
# AutoTato - UpgradeDataReader
# ----------------------------------------------------------------------------
# 集中读取升级界面 vanilla 运行时数据, 对齐 shop_data_reader.gd 职责划分,
# 避免读取逻辑散落在 upgrades_ui / upgrade_automation 中。
#
# 关键事实:
#   - 升级候选: player_container._get_upgrade_uis() 返回 4 个 UpgradeUI,
#     visible 且 upgrade_data != null 的为有效候选。
#   - reroll 价格: player_container._reroll_price (int, 非数组, 升级界面单值)。
#   - reroll 金币: RunData.get_player_gold(player_index) (与商店一致, 永远金币)。
#   - tier / effects 等字段直接读 vanilla UpgradeData (extends ItemData,
#     字段为原生 export 属性), 不依赖 autotato/ 任何代码。
# ============================================================================

const _Logger = preload("res://mods-unpacked/fengyifan-AutoTato/utils/logger.gd")

const _LOG_NAME := "UpgradeDataReader"

# ============================================================================
# 玩家数据 (与 shop_data_reader 同源, 升级/商店共用)
# ============================================================================

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

# ============================================================================
# 升级候选
# ============================================================================

# 返回 {options: Array<UpgradeData>, visible_uis: Array<UpgradeUI>}
# options 传给决策逻辑, visible_uis 用于执行选择 (同下标对应)。
#
# 数据来源: player_container._get_upgrade_uis() 返回 4 个 UpgradeUI 节点,
# vanilla show_upgrades_for_level() 按可见性设置 upgrade_data。
# 只收 visible 且 upgrade_data != null 的槽位。
static func get_upgrade_candidates(player_container) -> Dictionary:
	var empty := {"options": [], "visible_uis": []}
	if player_container == null or not is_instance_valid(player_container):
		return empty
	if not player_container.has_method("_get_upgrade_uis"):
		return empty

	var ui_list: Array = player_container._get_upgrade_uis()
	var options: Array = []
	var visible_uis: Array = []
	for ui in ui_list:
		if ui == null or not is_instance_valid(ui):
			continue
		if not bool(ui.visible):
			continue
		var udata = ui.get("upgrade_data")
		if udata == null:
			continue
		options.append(udata)
		visible_uis.append(ui)
	return {"options": options, "visible_uis": visible_uis}

# ============================================================================
# reroll
# ============================================================================

# 升级界面的 reroll 价格: player_container._reroll_price (int, 非数组)。
# 容错: 字段缺失或类型异常返回 0。
static func get_reroll_price(player_container) -> int:
	if player_container == null or not is_instance_valid(player_container):
		return 0
	var p = player_container.get("_reroll_price")
	if typeof(p) == TYPE_INT or typeof(p) == TYPE_REAL:
		return int(p)
	return 0
