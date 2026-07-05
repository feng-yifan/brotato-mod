extends Control

# ============================================================================
# AutoTato — Weapons Tab (v6 武器规则编辑器)
# ----------------------------------------------------------------------------
# 武器按 weapon_id (升级链 ID) 去重, 同链不同 tier 算同一把武器.
# 按武器类别分组, 每组可折叠 7 列网格, 标题栏右侧有类别规则下拉.
# 卡片: 图标 + 两行文字 (自身规则 / 生效结果), 边框=生效颜色.
# 颜色: skip=绿色, manual=红色, follow_set_rule=灰色.
# ============================================================================

const LOG_NAME := "fengyifan-AutoTato:WeaponsTab"
const _Config = preload("res://mods-unpacked/fengyifan-AutoTato/config/config.gd")

const WEAPON_SELF_OPTIONS := [
	["follow_set_rule", "AUTOTATO_FOLLOW_SET_RULE"],
	["manual",          "AUTOTATO_ACTION_MANUAL"],
	["skip",             "AUTOTATO_ACTION_SKIP"],
]

const SET_RULE_OPTIONS := [
	["manual", "AUTOTATO_ACTION_MANUAL"],
	["skip",   "AUTOTATO_ACTION_SKIP"],
]

const GRID_COLUMNS := 7
const CARD_ICON_SIZE := 80
const CARD_MIN_HEIGHT := 80
const GRID_HSEP := 6
const GRID_VSEP := 6
const CARD_BORDER := 2
const CARD_TEXT_FONT := preload("res://resources/fonts/actual/base/font_22.tres")

# 生效颜色: skip=绿, manual=红, follow=灰
const COLOR_SKIP    := Color(0.35, 1.0, 0.45, 1.0)
const COLOR_MANUAL  := Color(1.0, 0.35, 0.35, 1.0)
const COLOR_FOLLOW  := Color(1, 1, 1, 0.35)

var _groups: VBoxContainer = null
var _card_refs: Dictionary = {}          # chain_id → {own_label, result_label, button}
var _set_blocks: Dictionary = {}          # set_id → {header, grid, rule_opt, ...}
var _weapon_set_map: Dictionary = {}      # chain_id → Array[set_id]
var _refreshing := false

var _popup: Popup = null
var _editing_chain_id: String = ""
var _editing_weapon_name: String = ""
var _self_option: OptionButton = null
var _set_rule_vbox: VBoxContainer = null
var _min_tier_opt: OptionButton = null
var _popup_title: Label = null
var _popup_save_btn: Button = null


func _ready() -> void:
	_build_ui()
	_refresh()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not visible:
		if _popup and _popup.visible:
			_popup.hide()
			_enable_config_input()


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.name = "RootVBox"
	root.anchor_right = 1.0
	root.anchor_bottom = 1.0
	add_child(root)

	# 全局设置
	var settings := HBoxContainer.new()
	settings.name = "SettingsBar"
	settings.rect_min_size = Vector2(0, 40)
	settings.add_constant_override("separation", 12)
	root.add_child(settings)

	settings.add_child(_label(tr("AUTOTATO_MIN_WEAPON_TIER")))
	_min_tier_opt = OptionButton.new()
	_min_tier_opt.name = "MinTierOpt"
	_min_tier_opt.rect_min_size.x = 80
	for i in range(4):
		_min_tier_opt.add_item("0" if i == 0 else "≥ %d" % i)
	_min_tier_opt.connect("item_selected", self, "_on_min_tier_changed")
	settings.add_child(_min_tier_opt)

	var scroll := ScrollContainer.new()
	scroll.name = "ScrollContainer"
	scroll.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.follow_focus = true
	root.add_child(scroll)

	var cm := MarginContainer.new()
	cm.size_flags_horizontal = SIZE_EXPAND_FILL
	cm.add_constant_override("margin_left", 8)
	cm.add_constant_override("margin_right", 8)
	scroll.add_child(cm)

	_groups = VBoxContainer.new()
	_groups.name = "GroupsVBox"
	_groups.size_flags_horizontal = SIZE_EXPAND_FILL
	cm.add_child(_groups)


func _label(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.valign = Label.VALIGN_CENTER
	return l


# ============================================================================
# 数据刷新
# ============================================================================

func _refresh() -> void:
	_clear()

	var bridge = _get_bridge()
	var self_rules: Dictionary = {}
	var set_rules: Dictionary = {}
	var min_tier: int = 0
	if bridge:
		self_rules = bridge.get_weapon_rules()
		set_rules = bridge.get_weapon_category_rules()
		min_tier = bridge.get_weapon_min_tier()

	if _min_tier_opt:
		_min_tier_opt.select(clamp(min_tier, 0, 3))

	var chains: Dictionary = _load_weapon_chains()
	if chains.empty():
		_show_empty(tr("AUTOTATO_WEAPON_DATA_UNAVAILABLE"))
		return

	var sets: Array = _load_sets()
	if sets.empty():
		_show_empty(tr("AUTOTATO_WEAPON_CATEGORY_DATA_UNAVAILABLE"))
		return

	# 构建 set → chain_ids 映射
	var set_to_chains := {}
	for s in sets:
		set_to_chains[s.get("my_id")] = []

	for cid in chains:
		var w = chains[cid]
		var ws = w.get("sets")
		if not ws is Array:
			continue
		for s in ws:
			var sid: String = s.get("my_id")
			if set_to_chains.has(sid):
				if not set_to_chains[sid].has(cid):
					set_to_chains[sid].append(cid)
				if not _weapon_set_map.has(cid):
					_weapon_set_map[cid] = []
				if not _weapon_set_map[cid].has(sid):
					_weapon_set_map[cid].append(sid)

	for s in sets:
		var sid: String = s.get("my_id")
		var chs: Array = set_to_chains[sid]
		if chs.empty():
			continue
		_build_set_block(s, chs, chains, self_rules, set_rules)


func _clear() -> void:
	# remove_child 先摘除旧卡片, 避免 call_deferred(_grab_focus_on_card) 时
	# 旧卡片仍在树里干扰焦点 (Godot 3 MessageQueue flush 先于 _flush_delete_queue;
	# 同 upgrade_tab._refresh_priority_ui 的修复理由).
	for child in _groups.get_children():
		_groups.remove_child(child)
		child.queue_free()
	_set_blocks.clear()
	_card_refs.clear()
	_weapon_set_map.clear()


func _show_empty(msg: String) -> void:
	var l := Label.new()
	l.text = msg
	l.align = Label.ALIGN_CENTER
	l.valign = Label.VALIGN_CENTER
	l.anchor_right = 1.0
	l.anchor_bottom = 1.0
	_groups.add_child(l)


# 按 weapon_id (升级链) 去重, 保留最低 tier 的那个作为代表
func _load_weapon_chains() -> Dictionary:
	if typeof(ItemService) != TYPE_OBJECT:
		return {}
	var weapons = ItemService.get("weapons")
	if typeof(weapons) != TYPE_ARRAY:
		return {}
	var chains := {}
	for w in weapons:
		if w.get("can_be_looted") == false:
			continue
		var cid: String = w.get("weapon_id")
		if cid == "" or cid == null:
			continue
		if not chains.has(cid) or w.get("tier") < chains[cid].get("tier"):
			chains[cid] = w
	return chains


func _load_sets() -> Array:
	if typeof(ItemService) != TYPE_OBJECT:
		return []
	var s = ItemService.get("sets")
	return s if typeof(s) == TYPE_ARRAY else []


# ============================================================================
# Set block
# ============================================================================

func _build_set_block(set_data, chain_ids: Array, chains: Dictionary, self_rules: Dictionary, set_rules: Dictionary) -> void:
	var sid: String = set_data.get("my_id")

	var gap := Control.new()
	gap.rect_min_size = Vector2(0, 6)
	_groups.add_child(gap)

	# 手柄: 用 HBoxContainer 做 header 行, 箭头独立 Button + category OptionButton
	# 各自可聚焦, 避免之前 Button 包裹导致 OptionButton 无法接收焦点
	var hi := HBoxContainer.new()
	hi.rect_min_size = Vector2(0, 28)
	hi.size_flags_horizontal = SIZE_EXPAND_FILL
	hi.alignment = BoxContainer.ALIGN_CENTER
	hi.add_constant_override("separation", 4)

	var arrow_btn := Button.new()
	arrow_btn.text = "▼"
	arrow_btn.flat = true
	arrow_btn.rect_min_size = Vector2(24, 28)
	arrow_btn.focus_mode = Control.FOCUS_ALL
	hi.add_child(arrow_btn)

	var nl := Label.new()
	nl.text = set_data.get("name")
	nl.valign = Label.VALIGN_CENTER
	nl.size_flags_horizontal = SIZE_EXPAND_FILL
	hi.add_child(nl)

	var ro := OptionButton.new()
	ro.name = "SetRule_%s" % sid
	ro.rect_min_size.x = 70
	ro.add_item(tr("AUTOTATO_ACTION_MANUAL"))
	ro.add_item(tr("AUTOTATO_ACTION_SKIP"))
	var cr: String = set_rules.get(sid, "manual")
	ro.select(1 if cr == "skip" else 0)
	ro.connect("item_selected", self, "_on_set_rule_changed", [sid])
	hi.add_child(ro)

	_groups.add_child(hi)

	var grid := GridContainer.new()
	grid.columns = GRID_COLUMNS
	grid.add_constant_override("hseparation", GRID_HSEP)
	grid.add_constant_override("vseparation", GRID_VSEP)
	grid.size_flags_horizontal = SIZE_EXPAND_FILL
	_groups.add_child(grid)

	_set_blocks[sid] = {"header": arrow_btn, "grid": grid, "arrow": arrow_btn, "rule_opt": ro}
	arrow_btn.connect("pressed", self, "_on_set_header_toggled", [sid])

	# 手柄: 箭头按钮 ↔ 类别下拉左右切换
	arrow_btn.focus_neighbour_right = arrow_btn.get_path_to(ro)
	ro.focus_neighbour_left = ro.get_path_to(arrow_btn)

	for cid in chain_ids:
		_build_card(grid, cid, chains[cid], self_rules, set_rules)


func _on_set_rule_changed(idx: int, set_id: String) -> void:
	var bridge = _get_bridge()
	if bridge == null:
		return
	bridge.set_weapon_category_rule(set_id, "skip" if idx == 1 else "manual")
	_refresh()


# ============================================================================
# Card — 边框 = 生效颜色
# ============================================================================

func _build_card(grid: GridContainer, cid: String, weapon_data, self_rules: Dictionary, set_rules: Dictionary) -> void:
	var action: String = _resolve_weapon_action(cid, self_rules, set_rules)
	var action_color: Color = _action_color(action)

	var btn := Button.new()
	btn.size_flags_horizontal = SIZE_EXPAND_FILL
	btn.rect_min_size = Vector2(85, CARD_MIN_HEIGHT)
	btn.focus_mode = Control.FOCUS_ALL

	# 边框 stylebox
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_width_left = CARD_BORDER
	sb.border_width_right = CARD_BORDER
	sb.border_width_top = CARD_BORDER
	sb.border_width_bottom = CARD_BORDER
	sb.border_color = action_color
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_right = 4
	sb.corner_radius_bottom_left = 4
	sb.content_margin_left = 3
	sb.content_margin_right = 3
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	btn.add_stylebox_override("normal", sb)

	var hbox := HBoxContainer.new()
	hbox.anchor_right = 1.0
	hbox.anchor_bottom = 1.0
	hbox.mouse_filter = MOUSE_FILTER_IGNORE
	hbox.add_constant_override("separation", 4)

	# Icon
	var ir := TextureRect.new()
	ir.rect_min_size = Vector2(CARD_ICON_SIZE, CARD_MIN_HEIGHT)
	ir.expand = true
	ir.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ir.mouse_filter = MOUSE_FILTER_IGNORE
	var tex
	if weapon_data.has_method("get_icon"):
		tex = weapon_data.get_icon()
	elif weapon_data.get("icon") != null:
		tex = weapon_data.icon
	if tex:
		ir.texture = tex
	hbox.add_child(ir)

	# 两行文字
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = SIZE_EXPAND_FILL
	tv.size_flags_vertical = SIZE_EXPAND_FILL
	tv.alignment = BoxContainer.ALIGN_CENTER
	tv.mouse_filter = MOUSE_FILTER_IGNORE

	var own_label := Label.new()
	own_label.align = Label.ALIGN_LEFT
	own_label.valign = Label.VALIGN_CENTER
	own_label.clip_text = true
	own_label.size_flags_horizontal = SIZE_EXPAND_FILL
	own_label.add_font_override("font", CARD_TEXT_FONT)
	own_label.mouse_filter = MOUSE_FILTER_IGNORE
	tv.add_child(own_label)

	var result_label := Label.new()
	result_label.align = Label.ALIGN_LEFT
	result_label.valign = Label.VALIGN_CENTER
	result_label.clip_text = true
	result_label.size_flags_horizontal = SIZE_EXPAND_FILL
	result_label.add_font_override("font", CARD_TEXT_FONT)
	result_label.mouse_filter = MOUSE_FILTER_IGNORE
	tv.add_child(result_label)

	hbox.add_child(tv)
	btn.add_child(hbox)
	grid.add_child(btn)

	_card_refs[cid] = {"own_label": own_label, "result_label": result_label, "button": btn}
	btn.connect("pressed", self, "_on_card_pressed", [cid])

	_apply_card_text(cid, own_label, result_label, self_rules, set_rules)


func _resolve_weapon_action(cid: String, self_rules: Dictionary, set_rules: Dictionary) -> String:
	var sr = self_rules.get(cid, "")
	if sr == "manual" or sr == "skip":
		return sr
	var set_ids = _weapon_set_map.get(cid, [])
	var all_skip := true
	var has_rule := false
	for sid in set_ids:
		var r = set_rules.get(sid, "manual")
		if r == "manual":
			all_skip = false
			has_rule = true
		elif r == "skip":
			has_rule = true
	if has_rule and all_skip:
		return "skip"
	return "manual"


func _action_color(action: String) -> Color:
	match action:
		"skip":   return COLOR_SKIP
		"manual": return COLOR_MANUAL
		_:        return COLOR_FOLLOW


func _apply_card_text(cid: String, own_label: Label, result_label: Label, self_rules: Dictionary, set_rules: Dictionary) -> void:
	var action: String = _resolve_weapon_action(cid, self_rules, set_rules)
	var sr = self_rules.get(cid, "")

	# 第一行: 自身规则 — 完整颜色
	var own_text: String
	var own_color: Color
	match sr:
		"manual":
			own_text = tr("AUTOTATO_ACTION_MANUAL")
			own_color = COLOR_MANUAL
		"skip":
			own_text = tr("AUTOTATO_ACTION_SKIP")
			own_color = COLOR_SKIP
		_:
			own_text = tr("AUTOTATO_FOLLOW_SET_RULE")
			own_color = COLOR_FOLLOW
	own_label.text = own_text
	own_label.modulate = own_color

	# 第二行: 生效结果 — 完整颜色
	var result_text: String
	var result_color: Color
	match action:
		"skip":
			result_text = tr("AUTOTATO_ACTION_SKIP")
			result_color = COLOR_SKIP
		"manual":
			result_text = tr("AUTOTATO_ACTION_MANUAL")
			result_color = COLOR_MANUAL
		_:
			result_text = tr("AUTOTATO_FOLLOW_SET_RULE")
			result_color = COLOR_FOLLOW
	result_label.text = result_text
	result_label.modulate = result_color

	# 边框也同步生效颜色
	var btn = _card_refs[cid]["button"]
	var sb = btn.get_stylebox("normal").duplicate() as StyleBoxFlat
	sb.border_color = _action_color(action)
	btn.add_stylebox_override("normal", sb)


# ============================================================================
# Set toggle
# ============================================================================

func _on_set_header_toggled(set_id: String) -> void:
	var block = _set_blocks.get(set_id)
	if block == null:
		return
	block["grid"].visible = !block["grid"].visible
	block["arrow"].text = "▶" if !block["grid"].visible else "▼"


# ============================================================================
# Card click → Popup
# ============================================================================

func _on_card_pressed(cid: String) -> void:
	_editing_chain_id = cid
	_ensure_popup()

	var bridge = _get_bridge()
	var self_rules: Dictionary = {}
	var set_rules: Dictionary = {}
	if bridge:
		self_rules = bridge.get_weapon_rules()
		set_rules = bridge.get_weapon_category_rules()

	# 获取武器名称
	var chains: Dictionary = _load_weapon_chains()
	var weapon_data = chains.get(cid, {})
	if weapon_data.has_method("get_name_text"):
		_editing_weapon_name = weapon_data.get_name_text()
	else:
		_editing_weapon_name = cid

	_popup_title.text = _editing_weapon_name

	var sr: String = self_rules.get(cid, "follow_set_rule")
	_set_opt(_self_option, sr, WEAPON_SELF_OPTIONS)
	_build_set_rule_controls(set_rules)

	_popup.popup_centered_ratio(1.0)
	_disable_config_input()
	# 弹窗打开后将焦点移到第一个控件, 让手柄可以开始导航
	call_deferred("_grab_popup_focus")


func _grab_popup_focus() -> void:
	if _self_option and _self_option.visible:
		_self_option.grab_focus()
	elif _popup_save_btn and _popup_save_btn.visible:
		_popup_save_btn.grab_focus()


func _build_set_rule_controls(set_rules: Dictionary) -> void:
	for child in _set_rule_vbox.get_children():
		child.queue_free()

	var sids = _weapon_set_map.get(_editing_chain_id, [])
	if sids.empty():
		_set_rule_vbox.add_child(_label(tr("AUTOTATO_WEAPON_NO_CATEGORY")))
		return

	var sets = _load_sets()
	var sm := {}
	for s in sets:
		sm[s.get("my_id")] = s.get("name")

	for sid in sids:
		var row := HBoxContainer.new()
		row.rect_min_size.y = 28

		var nl := Label.new()
		nl.text = sm.get(sid, sid)
		nl.valign = Label.VALIGN_CENTER
		nl.size_flags_horizontal = SIZE_EXPAND_FILL
		nl.clip_text = true
		row.add_child(nl)

		var opt := OptionButton.new()
		opt.name = "Set_%s" % sid
		opt.rect_min_size.x = 70
		opt.add_item(tr("AUTOTATO_ACTION_MANUAL"))
		opt.add_item(tr("AUTOTATO_ACTION_SKIP"))
		var cr: String = set_rules.get(sid, "manual")
		opt.select(1 if cr == "skip" else 0)
		row.add_child(opt)

		_set_rule_vbox.add_child(row)


# ============================================================================
# Popup
# ============================================================================

func _ensure_popup() -> void:
	if _popup:
		return

	_popup = Popup.new()
	_popup.name = "EditWeaponRulePopup"
	_popup.popup_exclusive = true
	add_child(_popup)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	dim.mouse_filter = MOUSE_FILTER_STOP
	dim.connect("gui_input", self, "_on_popup_dimmer_clicked")
	_popup.add_child(dim)

	var ctr := CenterContainer.new()
	ctr.anchor_right = 1.0
	ctr.anchor_bottom = 1.0
	ctr.mouse_filter = MOUSE_FILTER_PASS
	_popup.add_child(ctr)

	var panel := PanelContainer.new()
	panel.mouse_filter = MOUSE_FILTER_STOP
	ctr.add_child(panel)

	var pv := VBoxContainer.new()
	pv.add_constant_override("separation", 8)
	panel.add_child(pv)

	var mg := MarginContainer.new()
	mg.add_constant_override("margin_left", 20)
	mg.add_constant_override("margin_right", 20)
	mg.add_constant_override("margin_top", 16)
	mg.add_constant_override("margin_bottom", 16)
	var cv := VBoxContainer.new()
	cv.add_constant_override("separation", 12)
	mg.add_child(cv)
	pv.add_child(mg)

	# Title
	_popup_title = Label.new()
	_popup_title.align = Label.ALIGN_CENTER
	_popup_title.valign = Label.VALIGN_CENTER
	_popup_title.rect_min_size = Vector2(0, 32)
	cv.add_child(_popup_title)

	cv.add_child(HSeparator.new())

	# 武器自身规则 — 同一行
	var self_row := HBoxContainer.new()
	self_row.add_child(_label(tr("AUTOTATO_WEAPON_SELF_RULE")))

	_self_option = OptionButton.new()
	_self_option.size_flags_horizontal = SIZE_EXPAND_FILL
	_self_option.focus_mode = Control.FOCUS_ALL
	for pair in WEAPON_SELF_OPTIONS:
		_self_option.add_item(tr(pair[1]))
	self_row.add_child(_self_option)
	cv.add_child(self_row)

	cv.add_child(HSeparator.new())
	cv.add_child(_label(tr("AUTOTATO_CATEGORY_RULE")))

	# v7: 自适应高度, 无 ScrollContainer
	_set_rule_vbox = VBoxContainer.new()
	_set_rule_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	_set_rule_vbox.add_constant_override("separation", 2)
	cv.add_child(_set_rule_vbox)

	cv.add_child(HSeparator.new())

	var bh := HBoxContainer.new()
	bh.alignment = BoxContainer.ALIGN_END
	# 保存在前, 取消在后: 从上方下移时空间导航默认命中保存
	var sb := Button.new()
	sb.text = tr("AUTOTATO_SAVE")
	sb.focus_mode = Control.FOCUS_ALL
	sb.connect("pressed", self, "_on_popup_save")
	bh.add_child(sb)
	var cb := Button.new()
	cb.text = tr("AUTOTATO_CANCEL")
	cb.focus_mode = Control.FOCUS_ALL
	cb.connect("pressed", self, "_on_popup_cancel")
	bh.add_child(cb)
	_popup_save_btn = sb

	# 手柄导航: Save ↔ Cancel 水平邻居
	sb.focus_neighbour_right = sb.get_path_to(cb)
	cb.focus_neighbour_left = cb.get_path_to(sb)

	# 手柄: 从上方 _self_option 下移至按钮行时默认到保存
	_self_option.focus_neighbour_bottom = _self_option.get_path_to(sb)

	cv.add_child(bh)


func _on_popup_dimmer_clicked(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_popup.hide()
		_enable_config_input()


func _on_popup_save() -> void:
	var bridge = _get_bridge()
	if bridge == null:
		return
	var si = _self_option.selected
	var sv = WEAPON_SELF_OPTIONS[si][0] if si >= 0 else "follow_set_rule"
	if sv == "follow_set_rule":
		bridge.remove_weapon_rule(_editing_chain_id)
	else:
		bridge.set_weapon_rule(_editing_chain_id, sv)
	for row in _set_rule_vbox.get_children():
		for child in row.get_children():
			if child is OptionButton:
				var o: OptionButton = child
				var sid: String = o.name.replace("Set_", "")
				bridge.set_weapon_category_rule(sid, "skip" if o.selected == 1 else "manual")
				break
	_popup.hide()
	_enable_config_input()
	_refresh()
	# 手柄: 保存后 refresh 销毁焦点, 延迟恢复到刚编辑的卡片上
	call_deferred("_grab_focus_on_card", _editing_chain_id)


func _grab_focus_on_card(cid: String) -> void:
	var ref = _card_refs.get(cid)
	if ref and ref["button"]:
		ref["button"].grab_focus()


func _on_popup_cancel() -> void:
	_popup.hide()
	_enable_config_input()


func _input(event: InputEvent) -> void:
	if _popup and _popup.visible and Utils.is_player_cancel_released(event, _get_opener_player_index()):
		# 如果 OptionButton 下拉菜单正在显示, 不关闭弹窗
		if _has_visible_popup_menu_in(_popup):
			return
		_popup.hide()
		_enable_config_input()
		get_tree().set_input_as_handled()


func _has_visible_popup_menu_in(node: Node) -> bool:
	for child in node.get_children():
		if child is PopupMenu:
			var pm: PopupMenu = child as PopupMenu
			if pm.visible:
				return true
		if _has_visible_popup_menu_in(child):
			return true
	return false


# ============================================================================
# Helpers
# ============================================================================

func _on_min_tier_changed(idx: int) -> void:
	var bridge = _get_bridge()
	if bridge:
		bridge.set_weapon_config("min_tier", idx)
	_refresh()


func _get_bridge():
	return _Config.get_instance()


func _set_opt(opt: OptionButton, value: String, actions: Array) -> void:
	for i in actions.size():
		if actions[i][0] == value:
			opt.select(i)
			return
	opt.select(0)


func _disable_config_input() -> void:
	var node: Node = self
	while node:
		if node.get_script() != null and node.get_script().resource_path.ends_with("config_panel.gd"):
			node.set_process_input(false)
			return
		node = node.get_parent()


# 向上查找 ConfigPanel 节点, 读取其 _opener_player_index 字段 (coop 按键归属).
# ConfigPanel 是 TabContainer 的父节点; tab 是其子节点. 单人下返回 0.
# Utils.is_player_xxx 在非 coop 时直接走原生 action, 0 即可.
func _get_opener_player_index() -> int:
	var p = get_parent()
	while p != null:
		var idx = p.get("_opener_player_index")
		if idx != null:
			return idx
		p = p.get_parent()
	return 0


func _enable_config_input() -> void:
	var node: Node = self
	while node:
		if node.get_script() != null and node.get_script().resource_path.ends_with("config_panel.gd"):
			node.set_process_input(true)
			return
		node = node.get_parent()
