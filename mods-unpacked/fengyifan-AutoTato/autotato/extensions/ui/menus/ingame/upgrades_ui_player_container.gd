extends "res://ui/menus/ingame/upgrades_ui_player_container.gd"

# ============================================================================
# AutoTato — upgrades_ui_player_container 扩展
# ----------------------------------------------------------------------------
# 职责:
#   1. 暴露 _autotato_clear_button_guard(): 升级 reroll 循环清除按钮防抖
#      (upgrades_ui.gd 的 _autotato_reroll_loop 调用)
#   2. 箱子物品卡: 右上角规则文字 + 物品规则按钮 + AutoTato 按钮
#      (与商店 shop_item.gd 卡片对齐: 角标颜色/文字同 items_tab/weapons_tab,
#       物品规则弹窗复用 shop_action/chest_action + 武器 self/category 规则,
#       AutoTato 按钮强制触发箱子决策 take/discard)
# ============================================================================

const LOG_NAME := "fengyifan-AutoTato:CrateCardExt"

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

# 物品规则颜色 (与 items_tab.gd 一致)
const COLOR_ACTION_MANUAL   := Color(1, 1, 1, 0.35)
const COLOR_ACTION_POSITIVE := Color(0.35, 1.0, 0.45, 1.0)
const COLOR_ACTION_WAIT     := Color(1.0, 0.78, 0.25, 1.0)
const COLOR_ACTION_CURSED   := Color(0.8, 0.45, 1.0, 1.0)
const COLOR_ACTION_NEGATIVE := Color(1.0, 0.35, 0.35, 1.0)
# 武器规则颜色 (与 weapons_tab.gd 一致)
const COLOR_SKIP   := Color(0.35, 1.0, 0.45, 1.0)
const COLOR_MANUAL := Color(1.0, 0.35, 0.35, 1.0)
const COLOR_FOLLOW := Color(1, 1, 1, 0.35)

const _STATE_CN := {
	"purchased": "拿取",
	"skipped": "丢弃",
	"locked": "锁定",
	"manual": "手动",
}

var _at_corner_vbox: VBoxContainer = null
var _at_corner_shop: Label = null
var _at_corner_chest: Label = null
var _at_popup: Popup = null
var _at_shop_opt: OptionButton = null
var _at_chest_opt: OptionButton = null
var _at_self_opt: OptionButton = null
var _at_set_vbox: VBoxContainer = null
var _at_item_vbox: VBoxContainer = null
var _at_weapon_vbox: VBoxContainer = null
var _at_popup_title: Label = null
var _at_is_weapon := false
var _at_corner_font = null
var _at_btn_font = null


func _ready() -> void:
	._ready()
	_at_setup_corner_label()
	_at_setup_buttons()


# 清除 vanilla 按钮防抖: 停 timer + 重置 _button_pressed.
# 升级 reroll 循环 / AutoTato 按钮触发箱子决策时都调用, 绕过 vanilla 0.1s 守卫.
func _autotato_clear_button_guard() -> void:
	if _button_delay_timer:
		_button_delay_timer.stop()
	_button_pressed = false


# ----------------------------------------------------------------------------
# 箱子卡片角标
# ----------------------------------------------------------------------------

func _at_setup_corner_label() -> void:
	if _item_panel_container == null:
		return
	if _ban_button:
		_at_corner_font = _ban_button.get_font("font")
	# PanelContainer 是 Container 会拉伸子节点, 先放 Control overlay (被拉满), 再在 overlay 内 anchor 定位 VBox
	var overlay = Control.new()
	overlay.name = "ATCornerOverlay"
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_item_panel_container.add_child(overlay)
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


# ----------------------------------------------------------------------------
# 箱子卡片按钮 (物品规则 + AutoTato)
# ----------------------------------------------------------------------------

func _at_setup_buttons() -> void:
	if _take_button == null:
		return
	var btn_row = _take_button.get_parent()
	if btn_row == null:
		return
	_at_btn_font = _take_button.get_font("font")

	# 两个按钮水平排列, 避免在纵向按钮行里再多占两行
	var pair := HBoxContainer.new()
	pair.add_constant_override("separation", 8)

	var rule_btn := Button.new()
	rule_btn.name = "ATRuleButton"
	rule_btn.text = "物品规则"
	rule_btn.align = Button.ALIGN_CENTER
	rule_btn.focus_mode = Control.FOCUS_NONE
	if _at_btn_font:
		rule_btn.add_font_override("font", _at_btn_font)
	rule_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule_btn.connect("pressed", self, "_at_rule_pressed")
	pair.add_child(rule_btn)

	var auto_btn := Button.new()
	auto_btn.name = "ATAutoButton"
	auto_btn.text = "AutoTato"
	auto_btn.align = Button.ALIGN_CENTER
	auto_btn.focus_mode = Control.FOCUS_NONE
	if _at_btn_font:
		auto_btn.add_font_override("font", _at_btn_font)
	auto_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	auto_btn.connect("pressed", self, "_at_auto_pressed")
	pair.add_child(auto_btn)

	btn_row.add_child(pair)


# vanilla 在展示箱子物品时调用 show_item, 此时 _item_data 已赋值, 刷新角标
func show_item(item_data) -> void:
	.show_item(item_data)
	_at_update_corner_label()


func _at_update_corner_label() -> void:
	if _at_corner_shop == null or _at_corner_chest == null or _item_data == null:
		return
	var bridge = _at_bridge()
	if bridge == null:
		_at_corner_shop.text = ""
		_at_corner_chest.text = ""
		return
	var is_weapon: bool = (_item_data.get("weapon_id") != null and _item_data.get("weapon_id") != "")

	# 同步规则按钮文字
	var rule_btn = get_node_or_null("ATRuleButton")
	if rule_btn:
		rule_btn.text = "武器规则" if is_weapon else "物品规则"

	if is_weapon:
		# 武器: 只显示武器规则 (单条), 隐藏箱子行
		_at_corner_chest.visible = false
		var wid: String = _item_data.get("weapon_id")
		var action = _at_resolve_weapon_action(wid, bridge.get_weapon_rules(), bridge.get_weapon_category_rules())
		match action:
			"skip":
				_at_corner_shop.text = "跳过"
				_at_corner_shop.modulate = COLOR_SKIP
			"manual", "follow_set_rule":
				_at_corner_shop.text = "手动"
				_at_corner_shop.modulate = COLOR_MANUAL
			_:
				_at_corner_shop.text = "受类别控制"
				_at_corner_shop.modulate = COLOR_FOLLOW
	else:
		# 物品: 同时显示商店规则 + 箱子规则, 文字/颜色与 items_tab 一致 (与商店卡片角标相同)
		_at_corner_chest.visible = true
		var rule = bridge.get_item_rule(_item_data.my_id)
		var sa: String = String(rule.get("shop_action", "manual"))
		var ca: String = String(rule.get("chest_action", "manual"))
		_at_corner_shop.text = "商:" + _at_shop_action_text(sa)
		_at_corner_shop.modulate = _at_shop_action_color(sa)
		_at_corner_chest.text = "箱:" + _at_chest_action_text(ca)
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
		"manual": return "手动"
		"get": return "购买"
		"lock_until_cursed": return "锁定等诅咒"
		"cursed_only": return "仅诅咒"
		"reject": return "拒绝"
		_: return "手动"


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
		"manual": return "手动"
		"take": return "拿取"
		"cursed_only": return "仅诅咒"
		"reject": return "拒绝"
		_: return "手动"


func _at_chest_action_color(a: String) -> Color:
	match a:
		"manual": return COLOR_ACTION_MANUAL
		"take": return COLOR_ACTION_POSITIVE
		"cursed_only": return COLOR_ACTION_CURSED
		"reject": return COLOR_ACTION_NEGATIVE
		_: return COLOR_ACTION_MANUAL


# ----------------------------------------------------------------------------
# AutoTato 按钮 — 强制触发箱子决策 (绕过自动化开关)
# ----------------------------------------------------------------------------

func _at_auto_pressed() -> void:
	if _item_data == null:
		return
	var bridge = _at_bridge()
	if bridge == null:
		return
	var result = bridge.decide_chest_item(_item_data, player_index, true)
	if result == null:
		return
	var state: String = String(result.terminal_state)
	_log("箱子 AutoTato 触发 玩家=%d 物品=%s 终态=%s 原因=%s" % [player_index, String(result.item_id), _STATE_CN.get(state, state), result.reason])
	_autotato_clear_button_guard()
	match state:
		"purchased": _take_button.call_deferred("emit_signal", "pressed")
		"skipped": _discard_button.call_deferred("emit_signal", "pressed")
		_: pass


# ----------------------------------------------------------------------------
# 物品规则按钮 + 弹窗 (逻辑与 shop_item.gd 一致)
# ----------------------------------------------------------------------------

func _at_rule_pressed() -> void:
	if _item_data == null:
		return
	_at_is_weapon = (_item_data.get("weapon_id") != null and _item_data.get("weapon_id") != "")
	_at_ensure_popup()

	var bridge = _at_bridge()
	if bridge == null:
		return
	_at_popup_title.text = _item_data.get_name_text()

	if _at_is_weapon:
		var wid: String = _item_data.get("weapon_id")
		var sr: String = bridge.get_weapon_rule(wid)
		_at_set_option(_at_self_opt, sr, WEAPON_SELF_OPTIONS)
		_at_build_set_rows(bridge.get_weapon_category_rules())
		_at_item_vbox.hide()
		_at_weapon_vbox.show()
	else:
		var rule = bridge.get_item_rule(_item_data.my_id)
		_at_set_option(_at_shop_opt, rule.get("shop_action", "manual"), SHOP_ACTIONS)
		_at_set_option(_at_chest_opt, rule.get("chest_action", "manual"), CHEST_ACTIONS)
		_at_weapon_vbox.hide()
		_at_item_vbox.show()

	_at_popup.popup_centered_ratio(1.0)


func _at_build_set_rows(set_rules: Dictionary) -> void:
	for child in _at_set_vbox.get_children():
		child.queue_free()

	var weapon_sets = _item_data.get("sets")
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


func _at_ensure_popup() -> void:
	if _at_popup:
		return

	_at_popup = Popup.new()
	_at_popup.name = "ATRulePopup"
	_at_popup.popup_exclusive = true
	add_child(_at_popup)

	var dimmer := ColorRect.new()
	dimmer.color = Color(0, 0, 0, 0.5)
	dimmer.anchor_right = 1.0
	dimmer.anchor_bottom = 1.0
	dimmer.mouse_filter = MOUSE_FILTER_STOP
	dimmer.connect("gui_input", self, "_at_dimmer_clicked")
	_at_popup.add_child(dimmer)

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
	shop_label.text = "商店行为"
	shop_label.valign = Label.VALIGN_CENTER
	shop_label.rect_min_size = Vector2(80, 0)
	actions_grid.add_child(shop_label)

	_at_shop_opt = OptionButton.new()
	_at_shop_opt.size_flags_horizontal = SIZE_EXPAND_FILL
	_at_shop_opt.focus_mode = Control.FOCUS_NONE
	for pair in SHOP_ACTIONS:
		_at_shop_opt.add_item(pair[1])
	actions_grid.add_child(_at_shop_opt)

	var chest_label := Label.new()
	chest_label.text = "箱子行为"
	chest_label.valign = Label.VALIGN_CENTER
	chest_label.rect_min_size = Vector2(80, 0)
	actions_grid.add_child(chest_label)

	_at_chest_opt = OptionButton.new()
	_at_chest_opt.size_flags_horizontal = SIZE_EXPAND_FILL
	_at_chest_opt.focus_mode = Control.FOCUS_NONE
	for pair in CHEST_ACTIONS:
		_at_chest_opt.add_item(pair[1])
	actions_grid.add_child(_at_chest_opt)

	_at_item_vbox.add_child(actions_grid)
	content.add_child(_at_item_vbox)

	# ---- 武器配置区域 ----
	_at_weapon_vbox = VBoxContainer.new()
	_at_weapon_vbox.name = "WeaponContent"
	_at_weapon_vbox.add_constant_override("separation", 8)

	var self_row := HBoxContainer.new()
	self_row.add_child(_at_label("武器自身规则"))
	_at_self_opt = OptionButton.new()
	_at_self_opt.size_flags_horizontal = SIZE_EXPAND_FILL
	_at_self_opt.focus_mode = Control.FOCUS_NONE
	for pair in WEAPON_SELF_OPTIONS:
		_at_self_opt.add_item(pair[1])
	self_row.add_child(_at_self_opt)
	_at_weapon_vbox.add_child(self_row)

	_at_weapon_vbox.add_child(HSeparator.new())
	_at_weapon_vbox.add_child(_at_label("类别规则"))

	_at_set_vbox = VBoxContainer.new()
	_at_set_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	_at_set_vbox.add_constant_override("separation", 2)
	_at_weapon_vbox.add_child(_at_set_vbox)

	content.add_child(_at_weapon_vbox)
	_at_weapon_vbox.hide()

	# ---- 按钮 ----
	content.add_child(HSeparator.new())
	var btn_hbox := HBoxContainer.new()
	btn_hbox.alignment = BoxContainer.ALIGN_END

	var cancel_btn := Button.new()
	cancel_btn.text = "取消"
	cancel_btn.focus_mode = Control.FOCUS_NONE
	cancel_btn.connect("pressed", self, "_at_popup_cancel")
	btn_hbox.add_child(cancel_btn)

	var save_btn := Button.new()
	save_btn.text = "保存"
	save_btn.focus_mode = Control.FOCUS_NONE
	save_btn.connect("pressed", self, "_at_popup_save")
	btn_hbox.add_child(save_btn)

	content.add_child(btn_hbox)


# ----------------------------------------------------------------------------
# 弹窗事件
# ----------------------------------------------------------------------------

func _at_dimmer_clicked(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_at_popup.hide()


func _at_popup_save() -> void:
	var bridge = _at_bridge()
	if bridge == null:
		return

	if _at_is_weapon:
		var wid: String = _item_data.get("weapon_id")
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
			bridge.remove_item_rule(_item_data.my_id)
		else:
			bridge.set_item_rule(_item_data.my_id, {"shop_action": sa, "chest_action": ca})

	_at_popup.hide()
	_at_update_corner_label()


func _at_popup_cancel() -> void:
	_at_popup.hide()


func _input(event: InputEvent) -> void:
	# 弹窗打开时只处理 ESC 关闭, 跳过 vanilla 的 ui_info 丢弃 / ban 输入, 避免背后误触
	if _at_popup and _at_popup.visible:
		if event.is_action_released("ui_cancel"):
			_at_popup.hide()
			get_tree().set_input_as_handled()
		return
	._input(event)


# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------

func _at_resolve_weapon_action(cid: String, weapon_rules: Dictionary, set_rules: Dictionary) -> String:
	var sr = weapon_rules.get(cid, "")
	if sr == "manual" or sr == "skip":
		return sr
	var weapon_sets = _item_data.get("sets")
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


func _at_bridge():
	return Engine.get_meta("fengyifan-AutoTato:Bridge")


func _at_set_option(opt: OptionButton, value: String, actions: Array) -> void:
	for i in actions.size():
		if actions[i][0] == value:
			opt.select(i)
			return
	opt.select(0)


func _log(msg: String) -> void:
	if typeof(ModLoaderLog) != TYPE_NIL:
		ModLoaderLog.info(msg, LOG_NAME)
