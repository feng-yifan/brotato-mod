extends Control

# ============================================================================
# AutoTato — Thresholds Tab (P5.4-ext v6 阈值编辑器)
# ----------------------------------------------------------------------------
# 数据源:
#   主要属性 → ItemService.stats (is_primary_stat=true), 16 个
#   次要属性 → 静态清单, 21 个, 与 stats_container.tscn 顺序一致
#   每 3 个属性插入一条分隔线.
#
# 行结构 (v6 重构):
#   [当前值] [模式▾] [☐升级黑名单] [⬆️⬇️] [☑限制升级] [☑限制商店] [☐限制箱子]
#
# 字段归属:
#   模式▾ + 数值  → threshold[stat].mode / value (set_threshold)
#   ☐升级黑名单   → upgrade.stat_blacklist (set_upgrade_array)
#   ⬆️⬇️优先级    → upgrade.stat_priority (set_upgrade_array)
#   ☑限制升级     → threshold[stat].limit_upgrade (set_threshold_field)
#   ☑限制商店     → threshold[stat].limit_shop (set_threshold_field)
#   ☐限制箱子     → threshold[stat].limit_chest (set_threshold_field)
# ============================================================================

const LOG_NAME := "fengyifan-AutoTato:ThresholdsTab"

const MODE_UNLIMITED := "unlimited"
const MODE_UPPER     := "upper"
const MODE_LOWER     := "lower"

const MODE_OPTIONS := [
	["unlimited", "不限"],
	["upper",     "上限"],
	["lower",     "下限"],
]

const SEP_EVERY := 3

# 次要属性清单 (stats_container.tscn 中 21 个可见属性, 游戏默认顺序)
const SECONDARY_STAT_ENTRIES := [
	{"key": "consumable_heal",              "tr_key": "CONSUMABLE_HEAL"},
	{"key": "heal_when_pickup_gold",        "tr_key": "CHANCE_HEAL_ON_GOLD"},
	{"key": "xp_gain",                      "tr_key": "XP_GAIN"},
	{"key": "pickup_range",                 "tr_key": "PICKUP_RANGE"},
	{"key": "items_price",                  "tr_key": "ITEMS_PRICE"},
	{"key": "explosion_damage",             "tr_key": "EXPLOSION_DAMAGE"},
	{"key": "explosion_size",               "tr_key": "EXPLOSION_SIZE"},
	{"key": "bounce",                       "tr_key": "BOUNCE"},
	{"key": "piercing",                     "tr_key": "PIERCING"},
	{"key": "piercing_damage",              "tr_key": "PIERCING_DAMAGE"},
	{"key": "damage_against_bosses",        "tr_key": "DAMAGE_AGAINST_BOSSES"},
	{"key": "structure_attack_speed",       "tr_key": "STRUCTURE_ATTACK_SPEED"},
	{"key": "structure_range",              "tr_key": "STRUCTURE_RANGE"},
	{"key": "burning_cooldown_reduction",   "tr_key": "BURNING_COOLDOWN_REDUCTION"},
	{"key": "burning_spread",               "tr_key": "BURNING_SPREAD"},
	{"key": "knockback",                    "tr_key": "KNOCKBACK"},
	{"key": "chance_double_gold",           "tr_key": "CHANCE_DOUBLE_GOLD"},
	{"key": "free_rerolls",                 "tr_key": "FREE_REROLLS"},
	{"key": "trees",                        "tr_key": "TREES"},
	{"key": "number_of_enemies",            "tr_key": "PCT_NUMBER_OF_ENEMIES"},
	{"key": "enemy_speed",                  "tr_key": "PCT_ENEMY_SPEED"},
]

# ---- 内部状态 ----
var _groups: VBoxContainer = null
# _row_refs: stat_key → {name_label, value_label, mode_btn, value_edit, blacklist_cb,
#                         limit_upgrade_cb, limit_shop_cb, limit_chest_cb, up_btn, down_btn, container}
var _row_refs: Dictionary = {}
var _group_blocks: Dictionary = {}
var _refreshing := false


# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	_build_ui()
	_refresh()


# ============================================================================
# UI 构建
# ============================================================================

func _build_ui() -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "ScrollContainer"
	scroll.anchor_right = 1.0
	scroll.anchor_bottom = 1.0
	scroll.scroll_horizontal_enabled = false
	add_child(scroll)

	_groups = VBoxContainer.new()
	_groups.name = "Groups"
	_groups.size_flags_horizontal = SIZE_EXPAND_FILL
	_groups.margin_left = 8.0
	_groups.margin_right = 8.0
	_groups.margin_top = 4.0
	scroll.add_child(_groups)

	var primary_rows := _collect_primary_rows()
	var secondary_rows := _inject_separators(SECONDARY_STAT_ENTRIES.duplicate(true))

	_build_group("primary", "主要属性", primary_rows)
	_build_group("secondary", "次要属性", secondary_rows)


func _collect_primary_rows() -> Array:
	var result := []
	if typeof(ItemService) != TYPE_OBJECT:
		return result
	var stats = ItemService.get("stats")
	if typeof(stats) != TYPE_ARRAY:
		return result
	for stat in stats:
		if stat.get("is_primary_stat") != true:
			continue
		var sn: String = stat.get("stat_name")
		result.append({"key": sn, "tr_key": sn.to_upper()})
	return _inject_separators(result)


func _inject_separators(rows: Array) -> Array:
	var out := []
	for i in rows.size():
		out.append(rows[i])
		if (i + 1) % SEP_EVERY == 0 and i < rows.size() - 1:
			out.append({"key": "_sep_%d" % i, "tr_key": "", "sep": true})
	return out


# ============================================================================
# 分组构建
# ============================================================================

func _build_group(group_key: String, title: String, stat_rows: Array) -> void:
	var header := Button.new()
	header.name = "%sHeader" % group_key
	header.text = "▼ %s" % title
	header.flat = true
	header.align = Button.ALIGN_LEFT
	header.rect_min_size.y = 32
	header.add_color_override("font_color", Color.white)
	header.add_color_override("font_color_hover", Color.white)
	header.add_color_override("font_color_pressed", Color.white)
	_groups.add_child(header)

	var content := VBoxContainer.new()
	content.name = "%sContent" % group_key
	_groups.add_child(content)

	_group_blocks[group_key] = {
		"header_btn": header,
		"content_vbox": content,
		"expanded": true,
	}
	header.connect("pressed", self, "_on_header_pressed", [group_key])
	_append_rows_to_group(group_key, stat_rows)


func _append_rows_to_group(group_key: String, stat_rows: Array) -> void:
	var block = _group_blocks.get(group_key)
	if block == null:
		return
	var content: VBoxContainer = block["content_vbox"]

	for i in stat_rows.size():
		var entry: Dictionary = stat_rows[i]

		if entry.get("sep", false):
			var sep := HSeparator.new()
			content.add_child(sep)
			continue

		var row := HBoxContainer.new()
		row.name = "Row_%s" % entry["key"]
		row.rect_min_size.y = 28
		content.add_child(row)

		# 1. 当前值
		var value_label := Label.new()
		value_label.text = "0"
		value_label.rect_min_size.x = 40
		value_label.align = Label.ALIGN_RIGHT
		value_label.valign = Label.VALIGN_CENTER
		row.add_child(value_label)

		# 2. 模式 OptionButton
		var mode_btn := OptionButton.new()
		mode_btn.name = "Mode_%s" % entry["key"]
		mode_btn.rect_min_size.x = 75
		for opt in MODE_OPTIONS:
			mode_btn.add_item(opt[1])
		mode_btn.connect("item_selected", self, "_on_mode_changed", [entry["key"]])
		row.add_child(mode_btn)

		# 3. 升级黑名单 CheckBox
		var blacklist_cb := CheckBox.new()
		blacklist_cb.name = "Blacklist_%s" % entry["key"]
		blacklist_cb.text = ""
		blacklist_cb.connect("toggled", self, "_on_blacklist_toggled", [entry["key"]])
		row.add_child(blacklist_cb)

		# 4. 优先级上下移动按钮
		var up_btn := Button.new()
		up_btn.name = "Up_%s" % entry["key"]
		up_btn.text = "⬆"
		up_btn.flat = true
		up_btn.rect_min_size = Vector2(24, 24)
		up_btn.connect("pressed", self, "_on_priority_up", [entry["key"]])
		row.add_child(up_btn)

		var down_btn := Button.new()
		down_btn.name = "Down_%s" % entry["key"]
		down_btn.text = "⬇"
		down_btn.flat = true
		down_btn.rect_min_size = Vector2(24, 24)
		down_btn.connect("pressed", self, "_on_priority_down", [entry["key"]])
		row.add_child(down_btn)

		# 5. 限制升级 CheckButton
		var limit_upgrade_cb := CheckButton.new()
		limit_upgrade_cb.name = "LimitUpg_%s" % entry["key"]
		limit_upgrade_cb.text = ""
		limit_upgrade_cb.connect("toggled", self, "_on_limit_toggled", [entry["key"], "limit_upgrade"])
		row.add_child(limit_upgrade_cb)

		# 6. 限制商店 CheckButton
		var limit_shop_cb := CheckButton.new()
		limit_shop_cb.name = "LimitShop_%s" % entry["key"]
		limit_shop_cb.text = ""
		limit_shop_cb.connect("toggled", self, "_on_limit_toggled", [entry["key"], "limit_shop"])
		row.add_child(limit_shop_cb)

		# 7. 限制箱子 CheckButton
		var limit_chest_cb := CheckButton.new()
		limit_chest_cb.name = "LimitChest_%s" % entry["key"]
		limit_chest_cb.text = ""
		limit_chest_cb.connect("toggled", self, "_on_limit_toggled", [entry["key"], "limit_chest"])
		row.add_child(limit_chest_cb)

		# 存引用
		_row_refs[entry["key"]] = {
			"value_label": value_label,
			"mode_btn": mode_btn,
			"blacklist_cb": blacklist_cb,
			"up_btn": up_btn,
			"down_btn": down_btn,
			"limit_upgrade_cb": limit_upgrade_cb,
			"limit_shop_cb": limit_shop_cb,
			"limit_chest_cb": limit_chest_cb,
			"container": row,
		}


# ============================================================================
# 数据刷新
# ============================================================================

func _refresh() -> void:
	_refreshing = true

	var bridge = _get_bridge()
	var thresholds := {}
	var blacklist: Array = []
	var priority: Array = []
	if bridge:
		thresholds = bridge.get_thresholds()
		var upg = bridge.get_upgrade_config()
		blacklist = upg.get("stat_blacklist", [])
		priority = upg.get("stat_priority", [])

	var player_index := 0

	for stat_key in _row_refs:
		var ref = _row_refs[stat_key]
		var th = thresholds.get(stat_key, {})

		# 当前游戏值
		var cur_val := _get_current_stat(stat_key, player_index)
		ref["value_label"].text = str(cur_val)

		# 阈值配置
		var mode: String = th.get("mode", MODE_UNLIMITED)
		var value: int = th.get("value", 0)
		var limit_upgrade: bool = bool(th.get("limit_upgrade", true))
		var limit_shop: bool = bool(th.get("limit_shop", true))
		var limit_chest: bool = bool(th.get("limit_chest", false))

		# 同步 mode
		var mode_idx := 0
		for m in MODE_OPTIONS.size():
			if MODE_OPTIONS[m][0] == mode:
				mode_idx = m
				break
		ref["mode_btn"].select(mode_idx)

		# 同步 blacklist
		ref["blacklist_cb"].pressed = blacklist.has(stat_key)

		# 同步 limit checkboxes
		ref["limit_upgrade_cb"].pressed = limit_upgrade
		ref["limit_shop_cb"].pressed = limit_shop
		ref["limit_chest_cb"].pressed = limit_chest

		# 同步优先级箭头状态
		var pri_idx: int = priority.find(stat_key)
		ref["up_btn"].disabled = (pri_idx <= 0)
		ref["down_btn"].disabled = (pri_idx < 0 or pri_idx >= priority.size() - 1)

		# 触达阈值标色
		_apply_row_color(ref, mode, value, cur_val)

	_refreshing = false


func _get_current_stat(stat_key: String, player_index: int) -> int:
	var hash_val: int = Keys.generate_hash(stat_key)
	if hash_val == Keys.empty_hash:
		return 0
	var effects = RunData.get_player_effects(player_index)
	if not effects.has(hash_val):
		return 0
	return int(Utils.get_stat(hash_val, player_index))


func _get_bridge():
	return Engine.get_meta("fengyifan-AutoTato:Bridge")


# ============================================================================
# 行颜色
# ============================================================================

func _apply_row_color(ref: Dictionary, mode: String, threshold_val: int, cur_val: int) -> void:
	var reached := false
	if mode == MODE_UPPER and cur_val >= threshold_val:
		reached = true
	elif mode == MODE_LOWER and cur_val < threshold_val:
		reached = true

	var color := Color.white
	if reached:
		if ProgressData and ProgressData.settings:
			color = ProgressData.settings.color_negative
		else:
			color = Color(1.0, 0.35, 0.35, 1.0)

	ref["value_label"].add_color_override("font_color", color)


# ============================================================================
# 事件处理
# ============================================================================

func _on_mode_changed(idx: int, stat_key: String) -> void:
	if _refreshing:
		return
	var ref = _row_refs.get(stat_key)
	if ref == null:
		return
	var mode_key: String = MODE_OPTIONS[idx][0]
	var bridge = _get_bridge()
	if bridge == null:
		return
	# 保留已有的阈值数值, 只改 mode
	var old_th = bridge.get_threshold(stat_key)
	var value: int = int(old_th.get("value", 0))
	bridge.set_threshold(stat_key, mode_key, value)
	var cur_val := _get_current_stat(stat_key, 0)
	_apply_row_color(ref, mode_key, value, cur_val)


func _on_blacklist_toggled(pressed: bool, stat_key: String) -> void:
	if _refreshing:
		return
	var bridge = _get_bridge()
	if bridge == null:
		return
	var upg = bridge.get_upgrade_config()
	var bl = upg.get("stat_blacklist", [])
	if pressed:
		if not bl.has(stat_key):
			bl.append(stat_key)
	else:
		bl.erase(stat_key)
	bridge.set_upgrade_array("stat_blacklist", bl)


func _on_limit_toggled(pressed: bool, stat_key: String, field: String) -> void:
	if _refreshing:
		return
	var bridge = _get_bridge()
	if bridge == null:
		return
	bridge.set_threshold_field(stat_key, field, pressed)


func _on_priority_up(stat_key: String) -> void:
	_move_priority(stat_key, -1)


func _on_priority_down(stat_key: String) -> void:
	_move_priority(stat_key, 1)


func _move_priority(stat_key: String, delta: int) -> void:
	var bridge = _get_bridge()
	if bridge == null:
		return
	var priority = bridge.get_upgrade_config().get("stat_priority", [])
	var idx: int = priority.find(stat_key)
	if idx < 0:
		# stat 不在优先级列表中, 追加到末尾然后上移
		priority.append(stat_key)
		idx = priority.size() - 1

	var new_idx: int = idx + delta
	if new_idx < 0 or new_idx >= priority.size():
		return

	# 交换位置
	var tmp = priority[idx]
	priority[idx] = priority[new_idx]
	priority[new_idx] = tmp

	bridge.set_upgrade_array("stat_priority", priority)
	_refresh()


func _on_header_pressed(group_key: String) -> void:
	var block = _group_blocks.get(group_key)
	if block == null:
		return
	var expanded: bool = block["expanded"]
	expanded = not expanded
	block["expanded"] = expanded
	var content: VBoxContainer = block["content_vbox"]
	content.visible = expanded
	var header: Button = block["header_btn"]
	var title: String = "主要属性" if group_key == "primary" else "次要属性"
	header.text = ("▼ " if expanded else "▶ ") + title
