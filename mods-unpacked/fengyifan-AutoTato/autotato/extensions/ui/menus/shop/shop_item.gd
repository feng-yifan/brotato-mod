extends "res://ui/menus/shop/shop_item.gd"

# ============================================================================
# AutoTato — shop_item Script Extension (P5.4-ext 商店规则按钮)
# ----------------------------------------------------------------------------
# 用"物品规则"按钮替换 vanilla BanButton (物品禁用按钮).
# 点击后弹出规则配置弹窗: shop_action + chest_action 下拉 + 保存/取消.
# ============================================================================

const LOG_NAME := "fengyifan-AutoTato:ShopItemExt"

const SHOP_ACTIONS := [
	["manual",            "手动"],
	["get",               "购买"],
	["reject",            "拒绝"],
	["lock_until_cursed", "锁定等诅咒"],
	["cursed_only",       "仅诅咒"],
]

const CHEST_ACTIONS := [
	["manual",       "手动"],
	["take",         "拿取"],
	["reject",       "拒绝"],
	["cursed_only",  "仅诅咒"],
]

var _autotato_popup: Popup = null
var _autotato_shop_opt: OptionButton = null
var _autotato_chest_opt: OptionButton = null
var _autotato_rule_btn: Button = null


func _ready() -> void:
	._ready()

	# 找 BanButton 并隐藏
	var ban_btn = _find_node("BanButton")
	if ban_btn and ban_btn is Button:
		ban_btn.visible = false

	# 在 BanButton 的父节点中插入物品规则按钮
	if ban_btn and ban_btn.get_parent():
		_autotato_rule_btn = Button.new()
		_autotato_rule_btn.name = "AutoTatoRuleButton"
		_autotato_rule_btn.text = "规则"
		_autotato_rule_btn.flat = true
		_autotato_rule_btn.rect_min_size = Vector2(32, 24)
		ban_btn.get_parent().add_child(_autotato_rule_btn)
		_autotato_rule_btn.connect("pressed", self, "_on_autotato_rule_pressed")


func _on_autotato_rule_pressed() -> void:
	_autotato_ensure_popup()
	if item_data == null:
		return

	var bridge = _autotato_get_bridge()
	var rule: Dictionary = {}
	if bridge:
		rule = bridge.get_item_rule(item_data.my_id)

	_autotato_set_option(_autotato_shop_opt, rule.get("shop_action", "manual"), SHOP_ACTIONS)
	_autotato_set_option(_autotato_chest_opt, rule.get("chest_action", "manual"), CHEST_ACTIONS)

	_autotato_popup.popup_centered()


func _autotato_ensure_popup() -> void:
	if _autotato_popup:
		return

	_autotato_popup = Popup.new()
	_autotato_popup.name = "AutoTatoRulePopup"
	_autotato_popup.popup_exclusive = true
	add_child(_autotato_popup)

	var panel := PanelContainer.new()
	panel.rect_min_size = Vector2(320, 200)
	_autotato_popup.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_constant_override("separation", 8)
	panel.add_child(vbox)

	var margin := MarginContainer.new()
	margin.add_constant_override("margin_left", 16)
	margin.add_constant_override("margin_right", 16)
	margin.add_constant_override("margin_top", 12)
	margin.add_constant_override("margin_bottom", 12)
	var content := VBoxContainer.new()
	content.add_constant_override("separation", 8)
	margin.add_child(content)
	vbox.add_child(margin)

	# Shop action
	var shop_label := Label.new()
	shop_label.text = "商店行为"
	content.add_child(shop_label)

	_autotato_shop_opt = OptionButton.new()
	_autotato_shop_opt.size_flags_horizontal = SIZE_EXPAND_FILL
	for pair in SHOP_ACTIONS:
		_autotato_shop_opt.add_item(pair[1])
	content.add_child(_autotato_shop_opt)

	# Chest action
	var chest_label := Label.new()
	chest_label.text = "箱子行为"
	content.add_child(chest_label)

	_autotato_chest_opt = OptionButton.new()
	_autotato_chest_opt.size_flags_horizontal = SIZE_EXPAND_FILL
	for pair in CHEST_ACTIONS:
		_autotato_chest_opt.add_item(pair[1])
	content.add_child(_autotato_chest_opt)

	content.add_child(HSeparator.new())

	# Buttons
	var btn_hbox := HBoxContainer.new()
	btn_hbox.alignment = BoxContainer.ALIGN_END

	var cancel_btn := Button.new()
	cancel_btn.text = "取消"
	cancel_btn.connect("pressed", self, "_on_autotato_popup_cancel")
	btn_hbox.add_child(cancel_btn)

	var save_btn := Button.new()
	save_btn.text = "保存"
	save_btn.connect("pressed", self, "_on_autotato_popup_save")
	btn_hbox.add_child(save_btn)

	content.add_child(btn_hbox)


func _on_autotato_popup_save() -> void:
	if item_data == null:
		return
	var bridge = _autotato_get_bridge()
	if bridge == null:
		return

	var si = _autotato_shop_opt.selected
	var ci = _autotato_chest_opt.selected
	var sa = SHOP_ACTIONS[si][0] if si >= 0 else "manual"
	var ca = CHEST_ACTIONS[ci][0] if ci >= 0 else "manual"

	if sa == "manual" and ca == "manual":
		bridge.remove_item_rule(item_data.my_id)
	else:
		bridge.set_item_rule(item_data.my_id, {"shop_action": sa, "chest_action": ca})

	_autotato_popup.hide()


func _on_autotato_popup_cancel() -> void:
	_autotato_popup.hide()


# Helpers

func _find_node(name: String):
	# 递归查找节点 (Godot 3 没有 find_node 按名称递归)
	for child in get_children():
		var found = _find_node_recursive(child, name)
		if found:
			return found
	return null


func _find_node_recursive(node: Node, name: String):
	if node.name == name:
		return node
	for child in node.get_children():
		var found = _find_node_recursive(child, name)
		if found:
			return found
	return null


func _autotato_get_bridge():
	return Engine.get_meta("fengyifan-AutoTato:Bridge")


func _autotato_set_option(opt: OptionButton, value: String, actions: Array) -> void:
	for i in actions.size():
		if actions[i][0] == value:
			opt.select(i)
			return
	opt.select(0)
