extends Control

# ============================================================================
# AutoTato — Thresholds Tab (P5.3 阈值编辑器)
# ----------------------------------------------------------------------------
# 数据源:
#   主要属性 → ItemService.stats (is_primary_stat=true), 16 个, 游戏默认顺序
#   次要属性 → 静态清单, 21 个, 与 stats_container.tscn 顺序一致
#   每 3 个属性自动插入一条分隔线.
#
# 布局:
#   ScrollContainer → VBoxContainer
#     ├── [主要属性 ▼] header Button
#     ├── 主要属性 Content VBoxContainer
#     │    ├── HBoxContainer (row: 名称 | 当前值 | 模式 OptionButton | 数值 LineEdit)
#     │    ├── HSeparator
#     │    ├── ...
#     ├── [次要属性 ▼] header Button
#     └── 次要属性 Content VBoxContainer
#          └── ...
#
# 每行内联编辑:
#   - OptionButton: 不限 / 上限 / 下限
#   - LineEdit: 数值输入, 不限时禁用 (保留原值供切换回来)
#   - 模式或数值变化时直接调用 Bridge.set_threshold 写入
#
# 触达阈值标色:
#   - 上限 + 当前值 >= 设定值 → color_negative
#   - 下限 + 当前值 <  设定值 → color_negative
#   - 不限 → 不标色
# ============================================================================

const LOG_NAME := "fengyifan-AutoTato:ThresholdsTab"

# Mode 常量 (与 Bridge/ThresholdGate 对齐)
const MODE_UNLIMITED := "unlimited"
const MODE_UPPER     := "upper"
const MODE_LOWER     := "lower"

# OptionButton 选项: [value_key, display_text]
const MODE_OPTIONS := [
	["unlimited", "不限"],
	["upper",     "上限"],
	["lower",     "下限"],
]

# 不需额外设置字体: ConfigPanel 已应用 vanilla base_theme.tres,
# 其 default_font (font_menus) 会通过主题传播到所有子控件.

const SEP_EVERY := 3

# ---- 次要属性清单 (stats_container.tscn 中 21 个可见属性, 游戏默认顺序) ----
# key   = 运行时 stat key (用于 Utils.get_stat hash 查值 + Bridge.set_threshold)
# tr_key = 翻译表 key (用于 Label.text → Godot auto_translate 自动翻译)
#          与 vanilla SecondaryStatContainer 的 key/custom_text_key 一致.
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
var _groups: VBoxContainer = null       # ScrollContainer 下的 VBoxContainer
var _row_refs: Dictionary = {}          # stat_key → {name_label, value_label, mode_btn, value_edit, container}
var _group_blocks: Dictionary = {}      # group_key → {header_btn, content_vbox, expanded}
var _refreshing := false                # 刷新中标记, 防止 set_text 触发 text_changed 回写


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

	# 主要属性: 从 ItemService.stats 动态加载
	var primary_rows := _collect_primary_rows()
	_build_group("primary", "主要属性", primary_rows)

	# 次要属性: 静态清单 (游戏默认顺序)
	var secondary_rows := _inject_separators(SECONDARY_STAT_ENTRIES.duplicate(true))
	_build_group("secondary", "次要属性", secondary_rows)


func _collect_primary_rows() -> Array:
	# 从 ItemService.stats 收集 is_primary_stat=true 的属性.
	# key   = 运行时 stat key (如 "stat_armor")
	# tr_key = stat_name.to_upper() (如 "STAT_ARMOR"), Godot auto_translate 触发翻译.
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
	# 每 SEP_EVERY 个属性之后插入分隔线占位 (不包括最后一项之后).
	var out := []
	for i in rows.size():
		out.append(rows[i])
		if (i + 1) % SEP_EVERY == 0 and i < rows.size() - 1:
			out.append({"key": "_sep_%d" % i, "name": "", "sep": true})
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

		# 分隔线占位 — 只添加 HSeparator, 不创建数据行
		if entry.get("sep", false):
			var sep := HSeparator.new()
			content.add_child(sep)
			continue

		# 行容器
		var row := HBoxContainer.new()
		row.name = "Row_%s" % entry["key"]
		row.rect_min_size.y = 30
		content.add_child(row)

		# 属性名称 Label — tr_key 触发 Godot auto_translate 翻译为中文
		var name_label := Label.new()
		name_label.text = entry["tr_key"]
		name_label.size_flags_horizontal = SIZE_EXPAND_FILL
		name_label.valign = Label.VALIGN_CENTER
		name_label.clip_text = true
		row.add_child(name_label)

		# 当前值 Label
		var value_label := Label.new()
		value_label.text = "0"
		value_label.rect_min_size.x = 50
		value_label.align = Label.ALIGN_RIGHT
		value_label.valign = Label.VALIGN_CENTER
		row.add_child(value_label)

		# Mode OptionButton
		var mode_btn := OptionButton.new()
		mode_btn.name = "Mode_%s" % entry["key"]
		mode_btn.rect_min_size.x = 90
		for opt in MODE_OPTIONS:
			mode_btn.add_item(opt[1])
		mode_btn.connect("item_selected", self, "_on_mode_changed", [entry["key"]])
		row.add_child(mode_btn)

		# 数值 LineEdit
		var value_edit := LineEdit.new()
		value_edit.name = "Value_%s" % entry["key"]
		value_edit.rect_min_size.x = 55
		value_edit.text = "0"
		value_edit.align = LineEdit.ALIGN_CENTER
		value_edit.connect("text_changed", self, "_on_value_changed", [entry["key"]])
		row.add_child(value_edit)

		# 存引用
		_row_refs[entry["key"]] = {
			"name_label": name_label,
			"value_label": value_label,
			"mode_btn": mode_btn,
			"value_edit": value_edit,
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

		var cur_val := _get_current_stat(stat_key, player_index)
		ref["value_label"].text = str(cur_val)

		var mode: String = th.get("mode", MODE_UNLIMITED)
		var value: int = th.get("value", 0)

		var mode_idx := 0
		for m in MODE_OPTIONS.size():
			if MODE_OPTIONS[m][0] == mode:
				mode_idx = m
				break
		ref["mode_btn"].select(mode_idx)

		ref["value_edit"].text = str(value)
		ref["value_edit"].editable = (mode != MODE_UNLIMITED)

		_apply_row_color(ref, mode, value, cur_val)

	_refreshing = false


func _get_current_stat(stat_key: String, player_index: int) -> int:
	var hash_val: int = Keys.generate_hash(stat_key)
	if hash_val == Keys.empty_hash:
		return 0
	# Utils.get_stat 最终调用 RunData.get_player_effects()[key], 对不存在的
	# key 做 Dictionary 硬索引会报错. 先检查 key 是否存在于 player effects 中.
	var effects = RunData.get_player_effects(player_index)
	if not effects.has(hash_val):
		return 0
	return int(Utils.get_stat(hash_val, player_index))


func _get_bridge():
	return Engine.get_meta("fengyifan-AutoTato:Bridge")


# ============================================================================
# 行颜色 (触达阈值)
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

	ref["name_label"].add_color_override("font_color", color)
	ref["value_label"].add_color_override("font_color", color)


# ============================================================================
# 事件处理
# ============================================================================

func _on_mode_changed(idx: int, stat_key: String) -> void:
	var ref = _row_refs.get(stat_key)
	if ref == null:
		return

	var mode_key: String = MODE_OPTIONS[idx][0]
	var bridge = _get_bridge()
	if bridge == null:
		return

	var value_str: String = ref["value_edit"].text
	var value: int = int(value_str) if value_str.is_valid_integer() else 0

	ref["value_edit"].editable = (mode_key != MODE_UNLIMITED)

	bridge.set_threshold(stat_key, mode_key, value)

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

	var expanded: bool = block["expanded"]
	expanded = not expanded
	block["expanded"] = expanded

	var content: VBoxContainer = block["content_vbox"]
	content.visible = expanded

	var header: Button = block["header_btn"]
	var title: String = "主要属性" if group_key == "primary" else "次要属性"
	header.text = ("▼ " if expanded else "▶ ") + title
