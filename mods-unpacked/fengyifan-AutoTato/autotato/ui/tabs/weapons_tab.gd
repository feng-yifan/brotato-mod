extends Control

# ============================================================================
# AutoTato — Weapons Tab (P5.4-ext 武器规则编辑器)
# ----------------------------------------------------------------------------
# 武器规则三级: 自身规则 > 类别规则 > 默认(manual)
#
# 武器自身规则: follow_set_rule / manual / skip, 默认 follow_set_rule
# 武器类别规则: manual / skip, 默认 manual
#
# 按武器类别 (ItemService.sets) 分组, 每组可折叠 7 列网格.
# 一把武器属于多个类别的, 在每个类别网格中都出现.
#
# 全局设置: weapon.min_tier (低于此 tier 直接跳过)
#
# 弹窗:
#   配置武器自身规则 + 武器所属类别的规则
# ============================================================================

const LOG_NAME := "fengyifan-AutoTato:WeaponsTab"

const WEAPON_SELF_OPTIONS := [
	["follow_set_rule", "受类别控制"],
	["manual",          "手动"],
	["skip",             "跳过"],
]

const SET_RULE_OPTIONS := [
	["manual", "手动"],
	["skip",   "跳过"],
]

const GRID_COLUMNS := 7
const CARD_ICON_SIZE := 64
const CARD_MIN_HEIGHT := 64
const GRID_HSEP := 6
const GRID_VSEP := 6
const CARD_TEXT_FONT := preload("res://resources/fonts/actual/base/font_22.tres")

const ACTION_COLOR_FOLLOW := Color(1, 1, 1, 0.35)
const ACTION_COLOR_MANUAL  := Color(1.0, 0.35, 0.35, 1.0)
const ACTION_COLOR_SKIP    := Color(0.35, 1.0, 0.45, 1.0)

var _groups: VBoxContainer = null
# _card_refs: weapon_id → {label, button}
var _card_refs: Dictionary = {}
# _set_blocks: set_id → {header, grid, items, ...}
var _set_blocks: Dictionary = {}
var _weapon_set_map: Dictionary = {}  # weapon_id → Array[set_id]
var _refreshing := false

var _popup: Popup = null
var _editing_weapon_id: String = ""
var _self_option: OptionButton = null
var _set_rule_vbox: VBoxContainer = null
var _min_tier_opt: OptionButton = null  # 全局最低武器级别


# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	_build_ui()
	_refresh()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not visible:
		if _popup and _popup.visible:
			_popup.hide()
			_enable_config_input()


# ============================================================================
# UI 构建
# ============================================================================

func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.name = "RootVBox"
	root.anchor_right = 1.0
	root.anchor_bottom = 1.0
	add_child(root)

	# ---- 全局设置栏 ----
	var settings := HBoxContainer.new()
	settings.name = "SettingsBar"
	settings.rect_min_size = Vector2(0, 40)
	settings.add_constant_override("separation", 12)
	root.add_child(settings)

	var min_tier_label := Label.new()
	min_tier_label.text = "最低武器级别:"
	min_tier_label.valign = Label.VALIGN_CENTER
	settings.add_child(min_tier_label)

	var min_tier_opt := OptionButton.new()
	min_tier_opt.name = "MinTierOpt"
	min_tier_opt.rect_min_size.x = 80
	_min_tier_opt = min_tier_opt
	for i in range(5):
		var label: String
		match i:
			0: label = "不限"
			_: label = "≥ %d" % i
		min_tier_opt.add_item(label)
	min_tier_opt.connect("item_selected", self, "_on_min_tier_changed")
	settings.add_child(min_tier_opt)

	# ---- Scroll area ----
	var scroll := ScrollContainer.new()
	scroll.name = "ScrollContainer"
	scroll.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	root.add_child(scroll)

	var content_margin := MarginContainer.new()
	content_margin.size_flags_horizontal = SIZE_EXPAND_FILL
	content_margin.add_constant_override("margin_left", 8)
	content_margin.add_constant_override("margin_right", 8)
	scroll.add_child(content_margin)

	_groups = VBoxContainer.new()
	_groups.name = "GroupsVBox"
	_groups.size_flags_horizontal = SIZE_EXPAND_FILL
	content_margin.add_child(_groups)


# ============================================================================
# 数据刷新
# ============================================================================

func _refresh() -> void:
	_clear()

	var bridge = _get_bridge()
	var self_rules: Dictionary = {}
	var set_rules: Dictionary = {}
	var min_tier: int = 1
	if bridge:
		self_rules = bridge.get_weapon_rules()
		set_rules = bridge.get_weapon_category_rules()
		min_tier = bridge.get_weapon_min_tier()

	# 同步全局 min_tier 下拉
	if _min_tier_opt:
		match min_tier:
			-1, 0: _min_tier_opt.select(0)
			_: _min_tier_opt.select(min_tier)

	# 加载武器数据
	var weapons: Array = _load_weapons()
	if weapons.empty():
		_show_empty("武器数据不可用")
		return

	# 加载 set 数据
	var sets: Array = _load_sets()
	if sets.empty():
		_show_empty("武器类别数据不可用")
		return

	# 构建 set → weapons 映射
	var set_to_weapons := {}
	for s in sets:
		var sid: String = s.get("my_id")
		set_to_weapons[sid] = {"set_data": s, "weapons": []}

	for w in weapons:
		var ws = w.get("sets")
		if not ws is Array:
			continue
		for s in ws:
			var sid: String = s.get("my_id")
			if set_to_weapons.has(sid):
				set_to_weapons[sid]["weapons"].append(w)
				var wid: String = w.get("my_id")
				if not _weapon_set_map.has(wid):
					_weapon_set_map[wid] = []
				if not _weapon_set_map[wid].has(sid):
					_weapon_set_map[wid].append(sid)

	# 构建分组网格
	for s in sets:
		var sid: String = s.get("my_id")
		var entry = set_to_weapons[sid]
		var set_weapons: Array = entry["weapons"]
		if set_weapons.empty():
			continue
		_build_set_block(s, set_weapons, self_rules, set_rules)


func _clear() -> void:
	for child in _groups.get_children():
		child.queue_free()
	_set_blocks.clear()
	_card_refs.clear()
	_weapon_set_map.clear()


func _show_empty(msg: String) -> void:
	var label := Label.new()
	label.text = msg
	label.align = Label.ALIGN_CENTER
	label.valign = Label.VALIGN_CENTER
	label.anchor_right = 1.0
	label.anchor_bottom = 1.0
	_groups.add_child(label)


func _load_weapons() -> Array:
	if typeof(ItemService) != TYPE_OBJECT:
		return []
	var weapons = ItemService.get("weapons")
	if typeof(weapons) != TYPE_ARRAY:
		return []
	# 滤掉不可掉落武器
	var result := []
	for w in weapons:
		if w.get("can_be_looted") != false:
			result.append(w)
	return result


func _load_sets() -> Array:
	if typeof(ItemService) != TYPE_OBJECT:
		return []
	var sets = ItemService.get("sets")
	if typeof(sets) != TYPE_ARRAY:
		return []
	return sets


# ============================================================================
# Set block
# ============================================================================

func _build_set_block(set_data, weapons: Array, self_rules: Dictionary, set_rules: Dictionary) -> void:
	var sid: String = set_data.get("my_id")
	var sname: String = set_data.get("name")

	var gap := Control.new()
	gap.rect_min_size = Vector2(0, 6)
	_groups.add_child(gap)

	# Header
	var header_btn := Button.new()
	header_btn.flat = true
	header_btn.align = Button.ALIGN_LEFT
	header_btn.size_flags_horizontal = SIZE_EXPAND_FILL
	header_btn.rect_min_size = Vector2(0, 28)

	var header_inner := HBoxContainer.new()
	header_inner.anchor_right = 1.0
	header_inner.anchor_bottom = 1.0
	header_inner.mouse_filter = MOUSE_FILTER_IGNORE
	header_inner.alignment = BoxContainer.ALIGN_CENTER

	var arrow := Label.new()
	arrow.text = "▼"
	arrow.valign = Label.VALIGN_CENTER
	arrow.rect_min_size = Vector2(20, 28)
	header_inner.add_child(arrow)

	var name_label := Label.new()
	name_label.text = sname
	name_label.valign = Label.VALIGN_CENTER
	header_inner.add_child(name_label)

	header_btn.add_child(header_inner)
	_groups.add_child(header_btn)

	# Grid
	var grid := GridContainer.new()
	grid.columns = GRID_COLUMNS
	grid.add_constant_override("hseparation", GRID_HSEP)
	grid.add_constant_override("vseparation", GRID_VSEP)
	grid.size_flags_horizontal = SIZE_EXPAND_FILL
	_groups.add_child(grid)

	_set_blocks[sid] = {
		"header": header_btn,
		"grid": grid,
		"arrow": arrow,
		"weapons": weapons,
	}
	header_btn.connect("pressed", self, "_on_set_header_toggled", [sid])

	# Cards
	for w in weapons:
		_build_card(grid, w, self_rules, set_rules)


# ============================================================================
# Card
# ============================================================================

func _build_card(grid: GridContainer, weapon_data, self_rules: Dictionary, set_rules: Dictionary) -> void:
	var wid: String = weapon_data.get("my_id")

	var btn := Button.new()
	btn.size_flags_horizontal = SIZE_EXPAND_FILL
	btn.rect_min_size = Vector2(90, CARD_MIN_HEIGHT)
	btn.focus_mode = Control.FOCUS_NONE

	var hbox := HBoxContainer.new()
	hbox.anchor_right = 1.0
	hbox.anchor_bottom = 1.0
	hbox.mouse_filter = MOUSE_FILTER_IGNORE
	hbox.add_constant_override("separation", 4)

	# Icon
	var icon_rect := TextureRect.new()
	icon_rect.rect_min_size = Vector2(CARD_ICON_SIZE, CARD_MIN_HEIGHT)
	icon_rect.expand = true
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.mouse_filter = MOUSE_FILTER_IGNORE
	var tex
	if weapon_data.has_method("get_icon"):
		tex = weapon_data.get_icon()
	elif weapon_data.get("icon") != null:
		tex = weapon_data.icon
	if tex:
		icon_rect.texture = tex
	hbox.add_child(icon_rect)

	# Rule label
	var rule_label := Label.new()
	rule_label.align = Label.ALIGN_LEFT
	rule_label.valign = Label.VALIGN_CENTER
	rule_label.clip_text = true
	rule_label.size_flags_horizontal = SIZE_EXPAND_FILL
	rule_label.add_font_override("font", CARD_TEXT_FONT)
	rule_label.mouse_filter = MOUSE_FILTER_IGNORE
	hbox.add_child(rule_label)

	btn.add_child(hbox)
	grid.add_child(btn)

	_card_refs[wid] = {
		"label": rule_label,
		"button": btn,
	}

	btn.connect("pressed", self, "_on_card_pressed", [wid])

	_apply_card_style(wid, rule_label, self_rules, set_rules)


func _resolve_weapon_action(weapon_id: String, self_rules: Dictionary, set_rules: Dictionary) -> String:
	# 三层优先级: 自身规则 > 类别规则 > 默认 manual
	if self_rules.has(weapon_id):
		var r = self_rules[weapon_id]
		if r == "manual" or r == "skip":
			return r
	# 查类别规则 (武器所属的全部类别)
	var set_ids = _weapon_set_map.get(weapon_id, [])
	var all_skip := true
	var has_rule := false
	for sid in set_ids:
		var sr = set_rules.get(sid, "manual")
		if sr == "manual":
			all_skip = false
			has_rule = true
		elif sr == "skip":
			has_rule = true
	if has_rule and all_skip:
		return "skip"
	return "manual"


func _apply_card_style(weapon_id: String, label: Label, self_rules: Dictionary, set_rules: Dictionary) -> void:
	var action: String = _resolve_weapon_action(weapon_id, self_rules, set_rules)
	var color: Color
	match action:
		"skip":   color = ACTION_COLOR_SKIP
		"manual": color = ACTION_COLOR_MANUAL
		_:        color = ACTION_COLOR_FOLLOW
	label.modulate = color

	var display: String
	var sr = self_rules.get(weapon_id, "")
	match sr:
		"manual": display = "手动"
		"skip":   display = "跳过"
		_:
			# 受类别控制 → 显示类别名
			display = "类别:手动"
			var set_ids = _weapon_set_map.get(weapon_id, [])
			var all_skip := true
			var has_rule := false
			for sid in set_ids:
				var cr = set_rules.get(sid, "manual")
				if cr == "manual":
					all_skip = false
					has_rule = true
				else:
					has_rule = true
			if has_rule and all_skip:
				display = "类别:跳过"
	label.text = display


# ============================================================================
# Set header toggle
# ============================================================================

func _on_set_header_toggled(set_id: String) -> void:
	var block = _set_blocks.get(set_id)
	if block == null:
		return
	var grid: GridContainer = block["grid"]
	grid.visible = !grid.visible
	block["arrow"].text = "▶" if !grid.visible else "▼"


# ============================================================================
# Card click → Popup
# ============================================================================

func _on_card_pressed(weapon_id: String) -> void:
	_editing_weapon_id = weapon_id
	_ensure_popup()

	var bridge = _get_bridge()
	var self_rules: Dictionary = {}
	var set_rules: Dictionary = {}
	if bridge:
		self_rules = bridge.get_weapon_rules()
		set_rules = bridge.get_weapon_category_rules()

	# 自身规则
	var sr: String = self_rules.get(weapon_id, "follow_set_rule")
	_set_option_by_value(_self_option, sr, WEAPON_SELF_OPTIONS)

	# 重建类别规则控件
	_build_set_rule_controls(set_rules)

	_popup.popup_centered_ratio(1.0)
	_disable_config_input()


func _build_set_rule_controls(set_rules: Dictionary) -> void:
	# 清空旧控件
	for child in _set_rule_vbox.get_children():
		child.queue_free()

	var set_ids = _weapon_set_map.get(_editing_weapon_id, [])
	if set_ids.empty():
		var no_set := Label.new()
		no_set.text = "此武器不属于任何类别"
		_set_rule_vbox.add_child(no_set)
		return

	var sets = _load_sets()
	var set_map := {}
	for s in sets:
		set_map[s.get("my_id")] = s.get("name")

	for sid in set_ids:
		var row := HBoxContainer.new()
		row.rect_min_size.y = 28

		var name_label := Label.new()
		name_label.text = set_map.get(sid, sid)
		name_label.valign = Label.VALIGN_CENTER
		name_label.size_flags_horizontal = SIZE_EXPAND_FILL
		name_label.clip_text = true
		row.add_child(name_label)

		var opt := OptionButton.new()
		opt.name = "Set_%s" % sid
		opt.rect_min_size.x = 80
		for pair in SET_RULE_OPTIONS:
			opt.add_item(pair[1])
		var cr: String = set_rules.get(sid, "manual")
		_set_option_by_value(opt, cr, SET_RULE_OPTIONS)
		row.add_child(opt)

		_set_rule_vbox.add_child(row)


# ============================================================================
# Popup construction
# ============================================================================

func _ensure_popup() -> void:
	if _popup:
		return

	_popup = Popup.new()
	_popup.name = "EditWeaponRulePopup"
	_popup.popup_exclusive = true
	add_child(_popup)

	var dimmer := ColorRect.new()
	dimmer.color = Color(0, 0, 0, 0.5)
	dimmer.anchor_right = 1.0
	dimmer.anchor_bottom = 1.0
	dimmer.mouse_filter = MOUSE_FILTER_STOP
	dimmer.connect("gui_input", self, "_on_popup_dimmer_clicked")
	_popup.add_child(dimmer)

	var center := CenterContainer.new()
	center.anchor_right = 1.0
	center.anchor_bottom = 1.0
	center.mouse_filter = MOUSE_FILTER_PASS
	_popup.add_child(center)

	var panel := PanelContainer.new()
	panel.rect_min_size = Vector2(400, 300)
	panel.mouse_filter = MOUSE_FILTER_STOP
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_constant_override("separation", 8)
	panel.add_child(vbox)

	var margin := MarginContainer.new()
	margin.add_constant_override("margin_left", 16)
	margin.add_constant_override("margin_right", 16)
	margin.add_constant_override("margin_top", 12)
	margin.add_constant_override("margin_bottom", 12)
	var content_vbox := VBoxContainer.new()
	content_vbox.add_constant_override("separation", 8)
	margin.add_child(content_vbox)
	vbox.add_child(margin)

	# Title
	var title := Label.new()
	title.name = "PopupTitle"
	title.align = Label.ALIGN_CENTER
	title.valign = Label.VALIGN_CENTER
	content_vbox.add_child(title)

	content_vbox.add_child(HSeparator.new())

	# 自身规则
	var self_label := Label.new()
	self_label.text = "武器自身规则:"
	self_label.valign = Label.VALIGN_CENTER
	content_vbox.add_child(self_label)

	_self_option = OptionButton.new()
	_self_option.size_flags_horizontal = SIZE_EXPAND_FILL
	for pair in WEAPON_SELF_OPTIONS:
		_self_option.add_item(pair[1])
	content_vbox.add_child(_self_option)

	content_vbox.add_child(HSeparator.new())

	# 类别规则区域
	var set_label := Label.new()
	set_label.text = "所属类别规则:"
	content_vbox.add_child(set_label)

	var scroll := ScrollContainer.new()
	scroll.rect_min_size = Vector2(0, 100)
	_set_rule_vbox = VBoxContainer.new()
	_set_rule_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	_set_rule_vbox.add_constant_override("separation", 4)
	scroll.add_child(_set_rule_vbox)
	content_vbox.add_child(scroll)

	content_vbox.add_child(HSeparator.new())

	# Buttons
	var btn_hbox := HBoxContainer.new()
	btn_hbox.alignment = BoxContainer.ALIGN_END

	var cancel_btn := Button.new()
	cancel_btn.text = "取消"
	cancel_btn.connect("pressed", self, "_on_popup_cancel")
	btn_hbox.add_child(cancel_btn)

	var save_btn := Button.new()
	save_btn.text = "保存"
	save_btn.connect("pressed", self, "_on_popup_save")
	btn_hbox.add_child(save_btn)

	content_vbox.add_child(btn_hbox)


# ============================================================================
# Popup events
# ============================================================================

func _on_popup_dimmer_clicked(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_popup.hide()
		_enable_config_input()


func _on_popup_save() -> void:
	var bridge = _get_bridge()
	if bridge == null:
		return

	# 保存自身规则
	var self_idx = _self_option.selected
	var self_val = WEAPON_SELF_OPTIONS[self_idx][0] if self_idx >= 0 else "follow_set_rule"
	if self_val == "follow_set_rule":
		bridge.remove_weapon_rule(_editing_weapon_id)
	else:
		bridge.set_weapon_rule(_editing_weapon_id, self_val)

	# 保存类别规则
	for row in _set_rule_vbox.get_children():
		# 找 row (HBoxContainer) 中的 OptionButton
		for child in row.get_children():
			if child is OptionButton:
				var opt: OptionButton = child
				var sid: String = opt.name.replace("Set_", "")
				var idx = opt.selected
				var val = SET_RULE_OPTIONS[idx][0] if idx >= 0 else "manual"
				bridge.set_weapon_category_rule(sid, val)
				break

	_popup.hide()
	_enable_config_input()
	_refresh()


func _on_popup_cancel() -> void:
	_popup.hide()
	_enable_config_input()


func _input(event: InputEvent) -> void:
	if _popup and _popup.visible and event.is_action_released("ui_cancel"):
		_popup.hide()
		_enable_config_input()
		get_tree().set_input_as_handled()


# ============================================================================
# 全局设置
# ============================================================================

func _on_min_tier_changed(idx: int) -> void:
	var value: int
	match idx:
		0: value = -1
		_: value = idx
	var bridge = _get_bridge()
	if bridge:
		bridge.set_weapon_config("min_tier", value)
	_refresh()


# ============================================================================
# Helpers
# ============================================================================

func _get_bridge():
	return Engine.get_meta("fengyifan-AutoTato:Bridge")


func _find_child(name: String):
	for c in get_children():
		var node = c.get_node_or_null(name)
		if node:
			return node
	return null


func _set_option_by_value(opt: OptionButton, value: String, actions: Array) -> void:
	for i in actions.size():
		if actions[i][0] == value:
			opt.select(i)
			return
	opt.select(0)


# ============================================================================
# ESC 竞态修复
# ============================================================================

func _disable_config_input() -> void:
	var node: Node = self
	while node:
		if node.get_script() != null:
			var path: String = node.get_script().resource_path
			if path.ends_with("config_panel.gd"):
				node.set_process_input(false)
				return
		node = node.get_parent()


func _enable_config_input() -> void:
	var node: Node = self
	while node:
		if node.get_script() != null:
			var path: String = node.get_script().resource_path
			if path.ends_with("config_panel.gd"):
				node.set_process_input(true)
				return
		node = node.get_parent()
