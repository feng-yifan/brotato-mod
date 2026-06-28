extends Control

# ============================================================================
# AutoTato — Thresholds Tab (v7 纯阈值编辑器)
# ----------------------------------------------------------------------------
# 行结构 (v7 简化):
#   [属性名称] [当前值] [模式▾] [数值]
#
# 每行只承载条件表达式 (mode + value), per-context action 移到各自的 tab.
# ============================================================================

const LOG_NAME := "fengyifan-AutoTato:ThresholdsTab"

const MODE_OPTIONS := [
	["unlimited", "AUTOTATO_THRESHOLD_UNLIMITED"],
	["upper",     "AUTOTATO_THRESHOLD_UPPER"],
	["lower",     "AUTOTATO_THRESHOLD_LOWER"],
]

const SEP_EVERY := 3

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

var _groups: VBoxContainer = null
var _row_refs: Dictionary = {}
var _group_blocks: Dictionary = {}
var _refreshing := false


func _ready() -> void:
	_build_ui()
	_refresh()


func _build_ui() -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "ScrollContainer"
	scroll.anchor_right = 1.0
	scroll.anchor_bottom = 1.0
	scroll.scroll_horizontal_enabled = false
	scroll.follow_focus = true
	add_child(scroll)

	_groups = VBoxContainer.new()
	_groups.name = "Groups"
	_groups.size_flags_horizontal = SIZE_EXPAND_FILL
	_groups.margin_left = 8.0
	_groups.margin_right = 8.0
	_groups.margin_top = 4.0
	scroll.add_child(_groups)

	_build_group("primary", tr("AUTOTATO_PRIMARY_STATS"), _collect_primary_rows())
	_build_group("secondary", tr("AUTOTATO_SECONDARY_STATS"), _inject_separators(SECONDARY_STAT_ENTRIES.duplicate(true)))


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

	_group_blocks[group_key] = {"header_btn": header, "content_vbox": content, "expanded": true}
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
			content.add_child(HSeparator.new())
			continue

		var row := HBoxContainer.new()
		row.name = "Row_%s" % entry["key"]
		row.rect_min_size.y = 26
		content.add_child(row)

		# 1. 属性名称
		var name_label := Label.new()
		name_label.text = tr(entry["tr_key"])
		name_label.size_flags_horizontal = SIZE_EXPAND_FILL
		name_label.valign = Label.VALIGN_CENTER
		name_label.clip_text = true
		row.add_child(name_label)

		# 2. 当前值
		var value_label := Label.new()
		value_label.text = "0"
		value_label.rect_min_size.x = 36
		value_label.align = Label.ALIGN_RIGHT
		value_label.valign = Label.VALIGN_CENTER
		row.add_child(value_label)

		# 3. 模式
		var mode_btn := OptionButton.new()
		mode_btn.name = "Mode_%s" % entry["key"]
		mode_btn.rect_min_size.x = 60
		for opt in MODE_OPTIONS:
			mode_btn.add_item(tr(opt[1]))
		mode_btn.connect("item_selected", self, "_on_mode_changed", [entry["key"]])
		row.add_child(mode_btn)

		# 4. 数值
		var value_edit := LineEdit.new()
		value_edit.name = "Value_%s" % entry["key"]
		value_edit.rect_min_size.x = 40
		value_edit.text = "0"
		value_edit.align = LineEdit.ALIGN_CENTER
		value_edit.connect("text_changed", self, "_on_value_changed", [entry["key"]])
		row.add_child(value_edit)

		_row_refs[entry["key"]] = {
			"name_label": name_label, "value_label": value_label,
			"mode_btn": mode_btn, "value_edit": value_edit,
			"container": row,
		}


# ============================================================================
# 数据刷新
# ============================================================================

func _refresh() -> void:
	_refreshing = true

	var bridge = _get_bridge()
	var thresholds := {}
	if bridge:
		thresholds = bridge.get_thresholds()

	var player_index := 0

	for stat_key in _row_refs:
		var ref = _row_refs[stat_key]
		var th = thresholds.get(stat_key, {})

		var mode: String = th.get("mode", "unlimited")
		var value: int = th.get("value", 0)
		var cur_val := _get_current_stat(stat_key, player_index)

		ref["value_label"].text = str(cur_val)

		_select_by_value(ref["mode_btn"], mode, MODE_OPTIONS)
		ref["value_edit"].text = str(value)
		ref["value_edit"].editable = (mode != "unlimited")

		_apply_row_color(ref, mode, value, cur_val)

	_refreshing = false


# v7 修复: 支持 2D 数组 (如 MODE_OPTIONS = [["unlimited","不限"], ...])
func _select_by_value(opt: OptionButton, val: String, actions: Array, labels = null) -> void:
	for i in actions.size():
		var item = actions[i]
		var key: String
		if typeof(item) == TYPE_ARRAY:
			key = str(item[0])
		else:
			key = str(item)
		if key == val:
			opt.select(i)
			return
	opt.select(0)


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


func _apply_row_color(ref: Dictionary, mode: String, threshold_val: int, cur_val: int) -> void:
	var reached := false
	if mode == "upper" and cur_val >= threshold_val:
		reached = true
	elif mode == "lower" and cur_val < threshold_val:
		reached = true
	var color := Color.white
	if reached:
		if ProgressData and ProgressData.settings:
			color = ProgressData.settings.color_negative
		else:
			color = Color(1.0, 0.35, 0.35, 1.0)
	ref["value_label"].add_color_override("font_color", color)
	ref["name_label"].add_color_override("font_color", color)


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
	var old_th = bridge.get_threshold(stat_key)
	var value: int = int(old_th.get("value", 0))
	bridge.set_threshold(stat_key, mode_key, value)
	ref["value_edit"].editable = (mode_key != "unlimited")
	var cur_val := _get_current_stat(stat_key, 0)
	_apply_row_color(ref, mode_key, value, cur_val)


func _on_value_changed(_new_text: String, stat_key: String) -> void:
	if _refreshing:
		return
	var ref = _row_refs.get(stat_key)
	if ref == null:
		return
	if not _new_text.is_valid_integer():
		return
	var value: int = int(_new_text)
	var mode_idx: int = ref["mode_btn"].selected
	var mode_key: String = MODE_OPTIONS[mode_idx][0]
	var bridge = _get_bridge()
	if bridge == null:
		return
	bridge.set_threshold(stat_key, mode_key, value)
	var cur_val := _get_current_stat(stat_key, 0)
	_apply_row_color(ref, mode_key, value, cur_val)


func _on_header_pressed(group_key: String) -> void:
	var block = _group_blocks.get(group_key)
	if block == null:
		return
	block["expanded"] = not block["expanded"]
	block["content_vbox"].visible = block["expanded"]
	var header: Button = block["header_btn"]
	var title: String = "主要属性" if group_key == "primary" else "次要属性"
	header.text = ("▼ " if block["expanded"] else "▶ ") + title
