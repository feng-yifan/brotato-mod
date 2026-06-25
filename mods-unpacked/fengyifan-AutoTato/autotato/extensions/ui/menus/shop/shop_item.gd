extends "res://ui/menus/shop/shop_item.gd"

# ============================================================================
# AutoTato — shop_item Script Extension (商店规则按钮 + 弹窗)
# ----------------------------------------------------------------------------
# 替换 BanButton 为"规则"按钮. 点击弹窗: 物品则配 shop/chest action,
# 武器则配 weapon self rule + set rules.
# ============================================================================

const LOG_NAME := "fengyifan-AutoTato:ShopItemExt"

const SHOP_ACTIONS := [
	["manual",            "手动"],
	["get",               "购买"],
	["lock_until_cursed", "锁定等诅咒"],
	["cursed_only",       "仅诅咒"],
	["reject",            "拒绝"],
]
const CHEST_ACTIONS := [
	["manual",       "手动"],
	["take",         "拿取"],
	["cursed_only",  "仅诅咒"],
	["reject",       "拒绝"],
]
const WEAPON_SELF_OPTIONS := [
	["follow_set_rule", "受类别控制"],
	["manual",          "手动"],
	["skip",             "跳过"],
]
const SET_RULE_OPTIONS := [
	["manual", "手动"],
	["skip",   "跳过"],
]

var _at_popup: Popup = null
var _at_shop_opt: OptionButton = null
var _at_chest_opt: OptionButton = null
var _at_self_opt: OptionButton = null
var _at_set_vbox: VBoxContainer = null
var _at_item_vbox: VBoxContainer = null
var _at_weapon_vbox: VBoxContainer = null
var _at_is_weapon := false


func _ready() -> void:
	._ready()
	var ban_btn = _find_node("BanButton")
	if ban_btn and ban_btn is Button:
		ban_btn.visible = false
		if ban_btn.get_parent():
			var btn := Button.new()
			btn.name = "AutoTatoRuleButton"
			btn.text = "规则"
			btn.focus_mode = Control.FOCUS_ALL
			ban_btn.get_parent().add_child(btn)
			btn.connect("pressed", self, "_at_rule_pressed")


func _at_rule_pressed() -> void:
	if item_data == null:
		return
	_at_is_weapon = (item_data.get("weapon_id") != null and item_data.get("weapon_id") != "")
	_at_ensure_popup()

	# 更新按钮文字
	# 找按钮并更新文字
	var btn = _find_node("AutoTatoRuleButton")
	if btn:
		btn.text = "武器规则" if _at_is_weapon else "物品规则"

	var bridge = _at_bridge()
	if bridge == null:
		return

	if _at_is_weapon:
		# 武器弹窗
		var wid: String = item_data.my_id
		var sr: String = bridge.get_weapon_rule(wid)
		_at_set_option(_at_self_opt, sr, WEAPON_SELF_OPTIONS)
		_at_build_set_rows(bridge.get_weapon_category_rules())
		_at_weapon_vbox.show()
		_at_item_vbox.hide()
	else:
		# 物品弹窗
		var rule = bridge.get_item_rule(item_data.my_id)
		_at_set_option(_at_shop_opt, rule.get("shop_action", "manual"), SHOP_ACTIONS)
		_at_set_option(_at_chest_opt, rule.get("chest_action", "manual"), CHEST_ACTIONS)
		_at_item_vbox.show()
		_at_weapon_vbox.hide()

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
		opt.add_item("手动")
		opt.add_item("跳过")
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
# Popup
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
	panel.rect_min_size = Vector2(360, 240)
	panel.mouse_filter = MOUSE_FILTER_STOP
	center.add_child(panel)

	var panel_vbox := VBoxContainer.new()
	panel_vbox.add_constant_override("separation", 6)
	panel.add_child(panel_vbox)

	var margin := MarginContainer.new()
	margin.add_constant_override("margin_left", 16)
	margin.add_constant_override("margin_right", 16)
	margin.add_constant_override("margin_top", 10)
	margin.add_constant_override("margin_bottom", 10)
	var content := VBoxContainer.new()
	content.add_constant_override("separation", 6)
	margin.add_child(content)
	panel_vbox.add_child(margin)

	# ---- 物品配置区域 ----
	_at_item_vbox = VBoxContainer.new()
	_at_item_vbox.name = "ItemContent"
	_at_item_vbox.add_constant_override("separation", 4)

	_at_item_vbox.add_child(_at_label("商店行为"))
	_at_shop_opt = OptionButton.new()
	_at_shop_opt.size_flags_horizontal = SIZE_EXPAND_FILL
	for pair in SHOP_ACTIONS:
		_at_shop_opt.add_item(pair[1])
	_at_item_vbox.add_child(_at_shop_opt)

	_at_item_vbox.add_child(_at_label("箱子行为"))
	_at_chest_opt = OptionButton.new()
	_at_chest_opt.size_flags_horizontal = SIZE_EXPAND_FILL
	for pair in CHEST_ACTIONS:
		_at_chest_opt.add_item(pair[1])
	_at_item_vbox.add_child(_at_chest_opt)

	content.add_child(_at_item_vbox)

	# ---- 武器配置区域 ----
	_at_weapon_vbox = VBoxContainer.new()
	_at_weapon_vbox.name = "WeaponContent"
	_at_weapon_vbox.add_constant_override("separation", 4)

	_at_weapon_vbox.add_child(_at_label("武器自身规则"))
	_at_self_opt = OptionButton.new()
	_at_self_opt.size_flags_horizontal = SIZE_EXPAND_FILL
	for pair in WEAPON_SELF_OPTIONS:
		_at_self_opt.add_item(pair[1])
	_at_weapon_vbox.add_child(_at_self_opt)

	_at_weapon_vbox.add_child(HSeparator.new())
	_at_weapon_vbox.add_child(_at_label("类别规则"))

	var set_scroll := ScrollContainer.new()
	set_scroll.rect_min_size = Vector2(0, 80)
	_at_set_vbox = VBoxContainer.new()
	_at_set_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	_at_set_vbox.add_constant_override("separation", 2)
	set_scroll.add_child(_at_set_vbox)
	_at_weapon_vbox.add_child(set_scroll)

	content.add_child(_at_weapon_vbox)

	_at_weapon_vbox.hide()

	# Buttons
	content.add_child(HSeparator.new())
	var btn_hbox := HBoxContainer.new()
	btn_hbox.alignment = BoxContainer.ALIGN_END

	var cancel_btn := Button.new()
	cancel_btn.text = "取消"
	cancel_btn.connect("pressed", self, "_at_popup_cancel")
	btn_hbox.add_child(cancel_btn)

	var save_btn := Button.new()
	save_btn.text = "保存"
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
		var wid: String = item_data.my_id
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
