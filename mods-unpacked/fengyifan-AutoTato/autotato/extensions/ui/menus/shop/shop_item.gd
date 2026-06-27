extends "res://ui/menus/shop/shop_item.gd"

# ============================================================================
# AutoTato — shop_item Script Extension (商店规则按钮 + 弹窗 + 卡片角标)
# ----------------------------------------------------------------------------
# 替换 BanButton 为"规则"按钮, 继承 BanButton 的字体和尺寸.
# 卡片右上角添加规则说明文字 (PanelContainer 内, anchor 定位).
# 弹窗: 物品配 shop/chest action, 武器配 self rule + set rules.
# v7 fix: 武器规则使用 weapon_id (chain ID), 与决策器/武器面板一致.
# ============================================================================

const LOG_NAME := "fengyifan-AutoTato:ShopItemExt"

const SHOP_ACTIONS := [
	["manual",            "AUTOTATO_ACTION_MANUAL"],
	["get",               "AUTOTATO_SHOP_GET"],
	["lock_until_cursed", "AUTOTATO_SHOP_LOCK_UNTIL_CURSED"],
	["cursed_only",       "AUTOTATO_SHOP_CURSED_ONLY"],
	["reject",            "AUTOTATO_SHOP_REJECT"],
]
const CHEST_ACTIONS := [
	["manual",       "AUTOTATO_ACTION_MANUAL"],
	["take",         "AUTOTATO_CHEST_TAKE"],
	["cursed_only",  "AUTOTATO_SHOP_CURSED_ONLY"],
	["reject",       "AUTOTATO_SHOP_REJECT"],
]
const WEAPON_SELF_OPTIONS := [
	["follow_set_rule", "AUTOTATO_FOLLOW_SET_RULE"],
	["manual",          "AUTOTATO_ACTION_MANUAL"],
	["skip",             "AUTOTATO_ACTION_SKIP"],
]

# 武器规则颜色 (与 weapons_tab.gd 一致)
const COLOR_SKIP    := Color(0.35, 1.0, 0.45, 1.0)   # 跳过 (绿)
const COLOR_MANUAL  := Color(1.0, 0.35, 0.35, 1.0)   # 手动 (红) — 武器专用
const COLOR_FOLLOW  := Color(1, 1, 1, 0.35)          # 受类别控制 (白)

# 物品规则颜色 (与 items_tab.gd 一致; 物品的"手动"是白色, 与武器的"手动"红色不同)
const COLOR_ACTION_MANUAL   := Color(1, 1, 1, 0.35)         # 手动 (白)
const COLOR_ACTION_POSITIVE := Color(0.35, 1.0, 0.45, 1.0)  # 购买/拿取 (绿)
const COLOR_ACTION_WAIT     := Color(1.0, 0.78, 0.25, 1.0)  # 锁定等诅咒 (橙)
const COLOR_ACTION_CURSED   := Color(0.8, 0.45, 1.0, 1.0)   # 仅诅咒 (紫)
const COLOR_ACTION_NEGATIVE := Color(1.0, 0.35, 0.35, 1.0)  # 拒绝 (红)

var _at_popup: Popup = null
var _at_shop_opt: OptionButton = null
var _at_chest_opt: OptionButton = null
var _at_self_opt: OptionButton = null
var _at_set_vbox: VBoxContainer = null
var _at_item_vbox: VBoxContainer = null
var _at_weapon_vbox: VBoxContainer = null
var _at_is_weapon := false

# 字体: 规则按钮用 LockButton 的 (font_26 大号, 与锁定按钮一致),
#        角标用 BanButton 的小号字体 (不抢眼)
var _at_rule_font = null
var _at_corner_font = null
# 卡片角标 (商店规则 + 箱子规则两条) + 弹窗标题
var _at_corner_vbox: VBoxContainer = null
var _at_corner_shop: Label = null
var _at_corner_chest: Label = null
var _at_popup_title: Label = null


func _ready() -> void:
	._ready()

	var ban_btn = _find_node("BanButton")
	var lock_btn = get_node_or_null("%LockButton")

	# 字体: 规则按钮用 LockButton 的 (font_26, 与锁定按钮一致), 角标用 BanButton 的小号字体
	if lock_btn:
		_at_rule_font = lock_btn.get_font("font")
	if ban_btn:
		_at_corner_font = ban_btn.get_font("font")

	# 1. 替换 BanButton 为规则按钮 — 与 LockButton 同字体, 居中
	#    (BanButton 原本用 font_smallest_text 小号, 与 LockButton 的 font_26 不一致)
	#    宽度不写死, 由 _at_sync_rule_button_width 延迟同步到 LockButton 的实际宽度
	if ban_btn and ban_btn is Button and ban_btn.get_parent():
		var btn_parent = ban_btn.get_parent()
		var ban_idx = ban_btn.get_index()
		ban_btn.visible = false
		var btn := Button.new()
		btn.name = "AutoTatoRuleButton"
		btn.text = tr("AUTOTATO_ITEM_RULE")
		btn.align = Button.ALIGN_CENTER
		btn.focus_mode = Control.FOCUS_NONE
		if _at_rule_font:
			btn.add_font_override("font", _at_rule_font)
		btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		# 插到 BanButton 原位置 (empty_space_l 与 empty_space_r 之间).
		# add_child 默认追加到末尾 (empty_space_r 之后), 两个占位都在按钮左侧 → 按钮偏右.
		btn_parent.add_child(btn)
		btn_parent.move_child(btn, ban_idx)
		btn.connect("pressed", self, "_at_rule_pressed")

	# 2. LockButton 恢复原始 size_flags (EXPAND+SHRINK_CENTER=7), 不强制宽度
	#    (之前强制 220 比原始窄; 宽度交给布局, 规则按钮延迟同步到它的实际宽度)
	if lock_btn:
		lock_btn.size_flags_horizontal = Control.SIZE_FILL | Control.SIZE_EXPAND | Control.SIZE_SHRINK_CENTER

	# 3. 卡片右上角规则说明 (商店规则 + 箱子规则两条, 各自颜色, 与 items_tab 一致)
	# PanelContainer 是 Container 会拉伸子节点并忽略 anchor/margin,
	# 所以先放 Control overlay (被拉满整个卡片), 再在 overlay 内 anchor 定位 VBox
	var panel = _find_node("PanelContainer")
	if panel:
		var overlay = Control.new()
		overlay.name = "ATCornerOverlay"
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(overlay)
		_at_corner_vbox = VBoxContainer.new()
		_at_corner_vbox.name = "ATCornerVBox"
		_at_corner_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_at_corner_vbox.anchor_left = 1.0
		_at_corner_vbox.anchor_right = 1.0
		_at_corner_vbox.margin_left = -180
		_at_corner_vbox.margin_right = -8
		_at_corner_vbox.margin_top = 6
		_at_corner_vbox.add_constant_override("separation", 0)
		overlay.add_child(_at_corner_vbox)
		_at_corner_shop = _at_make_corner_label()
		_at_corner_vbox.add_child(_at_corner_shop)
		_at_corner_chest = _at_make_corner_label()
		_at_corner_vbox.add_child(_at_corner_chest)

	_at_update_corner_label()


# set_shop_item 由 ShopItemsContainer 在配置每个槽位时调用 (此时 item_data 才被赋值).
# _ready 阶段 item_data 还是 null, _at_update_corner_label 会提前 return, 角标文字必须在这里刷新.
# reroll 时容器会用新数据再次调用 set_shop_item, 角标随之更新.
func set_shop_item(p_item_data, p_wave_value: int = RunData.current_wave) -> void:
	.set_shop_item(p_item_data, p_wave_value)
	_at_update_corner_label()
	# LockButton 此时已布局, 延迟一帧同步规则按钮宽度到它的实际宽度
	call_deferred("_at_sync_rule_button_width")


func deactivate() -> void:
	.deactivate()
	# 槽位被清空 (买走/ban) 时清除角标, 避免残留旧规则文字
	if _at_corner_shop:
		_at_corner_shop.text = ""
	if _at_corner_chest:
		_at_corner_chest.text = ""


# 把规则按钮宽度同步到 LockButton 的实际渲染宽度, 保证两个按钮上下同宽.
# 延迟调用 (call_deferred / set_shop_item 后), 确保 LockButton 已完成布局.
func _at_sync_rule_button_width() -> void:
	var lock_btn = get_node_or_null("%LockButton")
	var rule_btn = _find_node("AutoTatoRuleButton")
	if lock_btn == null or rule_btn == null:
		return
	var w: float = lock_btn.rect_size.x
	if w > 1.0:
		rule_btn.rect_min_size = Vector2(w, 0)


func _at_update_corner_label() -> void:
	if _at_corner_shop == null or _at_corner_chest == null or item_data == null:
		return
	var bridge = _at_bridge()
	if bridge == null:
		_at_corner_shop.text = ""
		_at_corner_chest.text = ""
		return
	var is_weapon: bool = (item_data.get("weapon_id") != null and item_data.get("weapon_id") != "")

	# 同步规则按钮文字 (reroll 后物品/武器类型可能切换, 按钮文字不能停留在旧值)
	var rule_btn = _find_node("AutoTatoRuleButton")
	if rule_btn:
		rule_btn.text = tr("AUTOTATO_WEAPON_RULE") if is_weapon else tr("AUTOTATO_ITEM_RULE")

	if is_weapon:
		# 武器: 只显示武器规则 (单条), 隐藏箱子行
		_at_corner_chest.visible = false
		var wid: String = item_data.get("weapon_id")
		var action = _at_resolve_weapon_action(wid, bridge.get_weapon_rules(), bridge.get_weapon_category_rules())
		match action:
			"skip":
				_at_corner_shop.text = tr("AUTOTATO_ACTION_SKIP")
				_at_corner_shop.modulate = COLOR_SKIP
			"manual", "follow_set_rule":
				_at_corner_shop.text = tr("AUTOTATO_ACTION_MANUAL")
				_at_corner_shop.modulate = COLOR_MANUAL
			_:
				_at_corner_shop.text = tr("AUTOTATO_FOLLOW_SET_RULE")
				_at_corner_shop.modulate = COLOR_FOLLOW
	else:
		# 物品: 同时显示商店规则 + 箱子规则, 文字/颜色与 items_tab 一致
		_at_corner_chest.visible = true
		var rule = bridge.get_item_rule(item_data.my_id)
		var sa: String = String(rule.get("shop_action", "manual"))
		var ca: String = String(rule.get("chest_action", "manual"))
		_at_corner_shop.text = tr("AUTOTATO_CORNER_SHOP") + _at_shop_action_text(sa)
		_at_corner_shop.modulate = _at_shop_action_color(sa)
		_at_corner_chest.text = tr("AUTOTATO_CORNER_CHEST") + _at_chest_action_text(ca)
		_at_corner_chest.modulate = _at_chest_action_color(ca)


func _at_make_corner_label() -> Label:
	var l := Label.new()
	l.align = Label.ALIGN_RIGHT
	l.valign = Label.VALIGN_TOP
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.size_flags_horizontal = Control.SIZE_FILL
	if _at_corner_font:
		l.add_font_override("font", _at_corner_font)
	return l


func _at_shop_action_text(a: String) -> String:
	match a:
		"manual": return tr("AUTOTATO_ACTION_MANUAL")
		"get": return tr("AUTOTATO_SHOP_GET")
		"lock_until_cursed": return tr("AUTOTATO_SHOP_LOCK_UNTIL_CURSED")
		"cursed_only": return tr("AUTOTATO_SHOP_CURSED_ONLY")
		"reject": return tr("AUTOTATO_SHOP_REJECT")
		_: return tr("AUTOTATO_ACTION_MANUAL")


func _at_shop_action_color(a: String) -> Color:
	match a:
		"manual": return COLOR_ACTION_MANUAL
		"get": return COLOR_ACTION_POSITIVE
		"lock_until_cursed": return COLOR_ACTION_WAIT
		"cursed_only": return COLOR_ACTION_CURSED
		"reject": return COLOR_ACTION_NEGATIVE
		_: return COLOR_ACTION_MANUAL


func _at_chest_action_text(a: String) -> String:
	match a:
		"manual": return tr("AUTOTATO_ACTION_MANUAL")
		"take": return tr("AUTOTATO_CHEST_TAKE")
		"cursed_only": return tr("AUTOTATO_SHOP_CURSED_ONLY")
		"reject": return tr("AUTOTATO_SHOP_REJECT")
		_: return tr("AUTOTATO_ACTION_MANUAL")


func _at_chest_action_color(a: String) -> Color:
	match a:
		"manual": return COLOR_ACTION_MANUAL
		"take": return COLOR_ACTION_POSITIVE
		"cursed_only": return COLOR_ACTION_CURSED
		"reject": return COLOR_ACTION_NEGATIVE
		_: return COLOR_ACTION_MANUAL


func _at_resolve_weapon_action(cid: String, weapon_rules: Dictionary, set_rules: Dictionary) -> String:
	var sr = weapon_rules.get(cid, "")
	if sr == "manual" or sr == "skip":
		return sr
	var weapon_sets = item_data.get("sets")
	if not weapon_sets is Array or weapon_sets.size() == 0:
		return "manual"
	var all_skip := true
	var has_rule := false
	for s in weapon_sets:
		var sid: String = s.get("my_id")
		if sid == "":
			continue
		var cr = set_rules.get(sid, "manual")
		if cr == "manual":
			all_skip = false
			has_rule = true
		elif cr == "skip":
			has_rule = true
	if has_rule and all_skip:
		return "skip"
	return "manual"


func _at_rule_pressed() -> void:
	if item_data == null:
		return
	_at_is_weapon = (item_data.get("weapon_id") != null and item_data.get("weapon_id") != "")
	_at_ensure_popup()

	var btn = _find_node("AutoTatoRuleButton")
	if btn:
		btn.text = tr("AUTOTATO_WEAPON_RULE") if _at_is_weapon else tr("AUTOTATO_ITEM_RULE")

	var bridge = _at_bridge()
	if bridge == null:
		return

	# 标题: 物品/武器名称
	_at_popup_title.text = item_data.get_name_text()

	if _at_is_weapon:
		var wid: String = item_data.get("weapon_id")
		var sr: String = bridge.get_weapon_rule(wid)
		_at_set_option(_at_self_opt, sr, WEAPON_SELF_OPTIONS)
		_at_build_set_rows(bridge.get_weapon_category_rules())
		_at_item_vbox.hide()
		_at_weapon_vbox.show()
	else:
		var rule = bridge.get_item_rule(item_data.my_id)
		_at_set_option(_at_shop_opt, rule.get("shop_action", "manual"), SHOP_ACTIONS)
		_at_set_option(_at_chest_opt, rule.get("chest_action", "manual"), CHEST_ACTIONS)
		_at_weapon_vbox.hide()
		_at_item_vbox.show()

	_at_popup.popup_centered_ratio(1.0)


func _at_build_set_rows(set_rules: Dictionary) -> void:
	for child in _at_set_vbox.get_children():
		child.queue_free()

	var weapon_sets = item_data.get("sets")
	if not weapon_sets is Array or weapon_sets.size() == 0:
		_at_set_vbox.add_child(_at_label("无类别"))
		return

	var all_sets = ItemService.get("sets") if typeof(ItemService) == TYPE_OBJECT else []
	var set_map := {}
	for s in all_sets:
		set_map[s.get("my_id")] = s.get("name")

	for s in weapon_sets:
		var sid: String = s.get("my_id")
		var row := HBoxContainer.new()
		row.rect_min_size.y = 28

		row.add_child(_at_label(set_map.get(sid, sid)))

		var opt := OptionButton.new()
		opt.name = "Set_%s" % sid
		opt.rect_min_size.x = 70
		opt.add_item(tr("AUTOTATO_ACTION_MANUAL"))
		opt.add_item(tr("AUTOTATO_ACTION_SKIP"))
		opt.focus_mode = Control.FOCUS_NONE
		var cr: String = set_rules.get(sid, "manual")
		opt.select(1 if cr == "skip" else 0)
		row.add_child(opt)

		_at_set_vbox.add_child(row)


func _at_label(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.valign = Label.VALIGN_CENTER
	l.size_flags_horizontal = SIZE_EXPAND_FILL
	l.clip_text = true
	return l


# ============================================================================
# Popup — 与 items_tab.gd 弹窗结构一致
# ============================================================================

func _at_ensure_popup() -> void:
	if _at_popup:
		return

	_at_popup = Popup.new()
	_at_popup.name = "ATRulePopup"
	_at_popup.popup_exclusive = true
	add_child(_at_popup)

	# Dimmer
	var dimmer := ColorRect.new()
	dimmer.color = Color(0, 0, 0, 0.5)
	dimmer.anchor_right = 1.0
	dimmer.anchor_bottom = 1.0
	dimmer.mouse_filter = MOUSE_FILTER_STOP
	dimmer.connect("gui_input", self, "_at_dimmer_clicked")
	_at_popup.add_child(dimmer)

	# Center
	var center := CenterContainer.new()
	center.anchor_right = 1.0
	center.anchor_bottom = 1.0
	center.mouse_filter = MOUSE_FILTER_PASS
	_at_popup.add_child(center)

	var panel := PanelContainer.new()
	panel.rect_min_size = Vector2(360, 0)
	panel.mouse_filter = MOUSE_FILTER_STOP
	center.add_child(panel)

	var panel_vbox := VBoxContainer.new()
	panel_vbox.add_constant_override("separation", 8)
	panel.add_child(panel_vbox)

	var margin := MarginContainer.new()
	margin.add_constant_override("margin_left", 20)
	margin.add_constant_override("margin_right", 20)
	margin.add_constant_override("margin_top", 16)
	margin.add_constant_override("margin_bottom", 16)
	var content := VBoxContainer.new()
	content.add_constant_override("separation", 12)
	margin.add_child(content)
	panel_vbox.add_child(margin)

	# Title
	_at_popup_title = Label.new()
	_at_popup_title.align = Label.ALIGN_CENTER
	_at_popup_title.valign = Label.VALIGN_CENTER
	_at_popup_title.rect_min_size = Vector2(0, 32)
	content.add_child(_at_popup_title)

	content.add_child(HSeparator.new())

	# ---- 物品配置区域 ----
	_at_item_vbox = VBoxContainer.new()
	_at_item_vbox.name = "ItemContent"
	_at_item_vbox.add_constant_override("separation", 8)

	var actions_grid := GridContainer.new()
	actions_grid.columns = 2
	actions_grid.add_constant_override("hseparation", 12)
	actions_grid.add_constant_override("vseparation", 8)

	var shop_label := Label.new()
	shop_label.text = tr("AUTOTATO_SHOP_BEHAVIOR")
	shop_label.valign = Label.VALIGN_CENTER
	shop_label.rect_min_size = Vector2(80, 0)
	actions_grid.add_child(shop_label)

	_at_shop_opt = OptionButton.new()
	_at_shop_opt.size_flags_horizontal = SIZE_EXPAND_FILL
	_at_shop_opt.focus_mode = Control.FOCUS_NONE
	for pair in SHOP_ACTIONS:
		_at_shop_opt.add_item(tr(pair[1]))
	actions_grid.add_child(_at_shop_opt)

	var chest_label := Label.new()
	chest_label.text = tr("AUTOTATO_CHEST_BEHAVIOR")
	chest_label.valign = Label.VALIGN_CENTER
	chest_label.rect_min_size = Vector2(80, 0)
	actions_grid.add_child(chest_label)

	_at_chest_opt = OptionButton.new()
	_at_chest_opt.size_flags_horizontal = SIZE_EXPAND_FILL
	_at_chest_opt.focus_mode = Control.FOCUS_NONE
	for pair in CHEST_ACTIONS:
		_at_chest_opt.add_item(tr(pair[1]))
	actions_grid.add_child(_at_chest_opt)

	_at_item_vbox.add_child(actions_grid)
	content.add_child(_at_item_vbox)

	# ---- 武器配置区域 ----
	_at_weapon_vbox = VBoxContainer.new()
	_at_weapon_vbox.name = "WeaponContent"
	_at_weapon_vbox.add_constant_override("separation", 8)

	# 武器自身规则 — 同一行
	var self_row := HBoxContainer.new()
	self_row.add_child(_at_label("武器自身规则"))
	_at_self_opt = OptionButton.new()
	_at_self_opt.size_flags_horizontal = SIZE_EXPAND_FILL
	_at_self_opt.focus_mode = Control.FOCUS_NONE
	for pair in WEAPON_SELF_OPTIONS:
		_at_self_opt.add_item(tr(pair[1]))
	self_row.add_child(_at_self_opt)
	_at_weapon_vbox.add_child(self_row)

	_at_weapon_vbox.add_child(HSeparator.new())
	_at_weapon_vbox.add_child(_at_label("类别规则"))

	# 类别规则行 — 自适应, 无 ScrollContainer
	_at_set_vbox = VBoxContainer.new()
	_at_set_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	_at_set_vbox.add_constant_override("separation", 2)
	_at_weapon_vbox.add_child(_at_set_vbox)

	content.add_child(_at_weapon_vbox)

	_at_weapon_vbox.hide()

	# Buttons
	content.add_child(HSeparator.new())
	var btn_hbox := HBoxContainer.new()
	btn_hbox.alignment = BoxContainer.ALIGN_END

	var cancel_btn := Button.new()
	cancel_btn.text = tr("AUTOTATO_CANCEL")
	cancel_btn.focus_mode = Control.FOCUS_NONE
	cancel_btn.connect("pressed", self, "_at_popup_cancel")
	btn_hbox.add_child(cancel_btn)

	var save_btn := Button.new()
	save_btn.text = tr("AUTOTATO_SAVE")
	save_btn.focus_mode = Control.FOCUS_NONE
	save_btn.connect("pressed", self, "_at_popup_save")
	btn_hbox.add_child(save_btn)

	content.add_child(btn_hbox)


# ============================================================================
# Popup events
# ============================================================================

func _at_dimmer_clicked(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_at_popup.hide()


func _at_popup_save() -> void:
	var bridge = _at_bridge()
	if bridge == null:
		return

	if _at_is_weapon:
		var wid: String = item_data.get("weapon_id")
		var si = _at_self_opt.selected
		var sv = WEAPON_SELF_OPTIONS[si][0] if si >= 0 else "follow_set_rule"
		if sv == "follow_set_rule":
			bridge.remove_weapon_rule(wid)
		else:
			bridge.set_weapon_rule(wid, sv)
		for row in _at_set_vbox.get_children():
			for child in row.get_children():
				if child is OptionButton:
					var opt: OptionButton = child
					var sid: String = opt.name.replace("Set_", "")
					var val = "skip" if opt.selected == 1 else "manual"
					bridge.set_weapon_category_rule(sid, val)
					break
	else:
		var si = _at_shop_opt.selected
		var ci = _at_chest_opt.selected
		var sa = SHOP_ACTIONS[si][0] if si >= 0 else "manual"
		var ca = CHEST_ACTIONS[ci][0] if ci >= 0 else "manual"
		if sa == "manual" and ca == "manual":
			bridge.remove_item_rule(item_data.my_id)
		else:
			bridge.set_item_rule(item_data.my_id, {"shop_action": sa, "chest_action": ca})

	_at_popup.hide()
	_at_update_corner_label()


func _at_popup_cancel() -> void:
	_at_popup.hide()


func _input(event: InputEvent) -> void:
	if _at_popup and _at_popup.visible and event.is_action_released("ui_cancel"):
		_at_popup.hide()
		get_tree().set_input_as_handled()


# ============================================================================
# Helpers
# ============================================================================

func _find_node(name: String):
	for child in get_children():
		var found = _find_recursive(child, name)
		if found:
			return found
	return null


func _find_recursive(node: Node, name: String):
	if node.name == name:
		return node
	for child in node.get_children():
		var found = _find_recursive(child, name)
		if found:
			return found
	return null


func _at_bridge():
	return Engine.get_meta("fengyifan-AutoTato:Bridge")


func _at_set_option(opt: OptionButton, value: String, actions: Array) -> void:
	for i in actions.size():
		if actions[i][0] == value:
			opt.select(i)
			return
	opt.select(0)
