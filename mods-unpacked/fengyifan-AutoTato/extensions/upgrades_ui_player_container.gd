extends "res://ui/menus/ingame/upgrades_ui_player_container.gd"

# ============================================================================
# AutoTato — upgrades_ui_player_container Script Extension
# ----------------------------------------------------------------------------
# 在箱子物品卡片上添加规则文字、规则按钮、AutoTato 按钮。
# 完全取代 BanButton（禁用并隐藏），重映射 ui_ban 快捷键到规则弹窗。
#
# 规则文字插入 ItemDescription 的 Category 之后（与 shop_item.gd 一致）。
# 规则按钮带 R 键图标。
# 弹窗同时编辑 shop_action 和 chest_action。
#
# 交互与焦点参考 extensions/shop_item.gd:
#   - Popup 弹窗（含半透明遮罩 + 居中面板）
#   - ESC/B 关闭弹窗（PopupMenu 守卫 + gamepad 守卫）
#   - PopupMenu 循环导航（上下键首尾循环）
#   - 弹窗打开后 deferred 聚焦第一个 OptionButton
# ============================================================================

const _Logger = preload("res://mods-unpacked/fengyifan-AutoTato/utils/logger.gd")
const _Config = preload("res://mods-unpacked/fengyifan-AutoTato/config/config.gd")
const _LOG_NAME := "CrateCard"

# ============================================================================
# 规则颜色（与 shop_item.gd 一致）
# ============================================================================

const _HEX_MANUAL  := "#ffffff59"
const _HEX_GET     := "#59ff73"
const _HEX_REJECT  := "#ff5959"
const _HEX_WAIT    := "#ffc740"
const _HEX_CURSED  := "#cc73ff"
const _HEX_SKIP    := "#59ff73"
const _HEX_FOLLOW  := "#ffffff59"

# ============================================================================
# 规则选项（与 shop_item.gd / config.gd 保持一致）
# ============================================================================

const SHOP_ACTIONS := [
	["manual",            "AUTOTATO_ACTION_MANUAL"],
	["get",               "AUTOTATO_SHOP_GET"],
	["lock_until_cursed", "AUTOTATO_SHOP_LOCK_UNTIL_CURSED"],
	["cursed_only",       "AUTOTATO_SHOP_CURSED_ONLY"],
	["reject",            "AUTOTATO_SHOP_REJECT"],
]
const CHEST_ACTIONS := [
	["manual",      "AUTOTATO_ACTION_MANUAL"],
	["take",        "AUTOTATO_CHEST_TAKE"],
	["cursed_only", "AUTOTATO_SHOP_CURSED_ONLY"],
	["reject",      "AUTOTATO_SHOP_REJECT"],
]

# 手柄 B 键守卫
var _at_popup_opened_by_gamepad := false

# ---- 规则文字（插入 ItemDescription） ----
var _at_rule_label: RichTextLabel = null

# ---- 按钮 ----
var _at_rule_btn: Button = null
var _at_auto_btn: Button = null

# ---- 弹窗 ----
var _at_popup: Popup = null
var _at_popup_title: Label = null
var _at_shop_opt: OptionButton = null
var _at_chest_opt: OptionButton = null


func _ready() -> void:
	._ready()
	manage_ban_button_visibility()
	_at_add_rule_label()
	_at_setup_buttons()


# ============================================================================
# BanButton 禁用
# ============================================================================

func manage_ban_button_visibility() -> void:
	if _ban_button:
		_ban_button.disable()
		_ban_button.hide()


# 清除 vanilla 按钮防抖
func _autotato_clear_button_guard() -> void:
	if _button_delay_timer:
		_button_delay_timer.stop()
	_button_pressed = false


# 完全禁用 vanilla 的"禁用物品"功能: 覆盖 ban 的两个执行入口, 直接 return 不调父类.
# ban 可能从多条路径触发 (vanilla _input 第 91 行 / BanButton 信号), 与其逐条截断,
# 不如在终点短路. 这是用户需求 "完全禁用禁用物品功能" 的最终保证.
# 注意: 不影响开规则弹窗 (走 _at_rule_pressed, 独立路径).
func _on_BanButton_pressed() -> void:
	return


func _on_BanButton_button_up() -> void:
	return


# ============================================================================
# 规则文字 — 插入 ItemDescription 的 Category 之后（与 shop_item.gd 一致）
# ============================================================================

func _at_add_rule_label() -> void:
	var desc = get_node_or_null("ItemsContainer/VBoxContainer/ItemPanelContainer/MarginContainer/ItemDescription")
	if desc == null:
		return
	var cat = desc.get_node_or_null("HBoxContainer/ScrollContainer/VBoxContainer/Category")
	if cat == null:
		return
	var cat_parent = cat.get_parent()
	if cat_parent == null:
		return
	var cat_idx = cat.get_index()

	var label := RichTextLabel.new()
	label.name = "AutoTatoRuleLabel"
	label.bbcode_enabled = true
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.fit_content_height = true
	label.scroll_active = false
	var cat_font = cat.get_font("font")
	if cat_font:
		label.add_font_override("normal_font", cat_font)
	cat_parent.add_child(label)
	cat_parent.move_child(label, cat_idx + 1)
	_at_rule_label = label


func _at_update_rule_label() -> void:
	if _at_rule_label == null or _item_data == null:
		return
	var config = _Config.get_instance()
	if config == null:
		_at_rule_label.bbcode_text = ""
		return

	var rule = config.get_item_rule(_item_data.my_id)
	var sa: String = String(rule.get("shop_action", "manual"))
	var ca: String = String(rule.get("chest_action", "manual"))
	var sa_text = _at_shop_action_text(sa)
	var ca_text = _at_chest_action_text(ca)
	_at_rule_label.bbcode_text = "[color=%s]%s[/color], [color=%s]%s[/color]" % [
		_at_shop_action_hex(sa), sa_text,
		_at_chest_action_hex(ca), ca_text
	]


# ============================================================================
# 按钮
# ============================================================================

func _at_setup_buttons() -> void:
	if _take_button == null:
		return
	var btn_row = _take_button.get_parent()
	if btn_row == null:
		return
	var btn_font = _take_button.get_font("font")

	# 1. 规则按钮（带 R 键图标）
	_at_rule_btn = Button.new()
	_at_rule_btn.name = "ATRuleButton"
	_at_rule_btn.text = tr("AUTOTATO_ITEM_RULE")
	_at_rule_btn.align = Button.ALIGN_CENTER
	_at_rule_btn.expand_icon = true
	_at_rule_btn.focus_mode = Control.FOCUS_ALL
	if btn_font:
		_at_rule_btn.add_font_override("font", btn_font)
	_at_rule_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_at_rule_btn.connect("pressed", self, "_at_rule_pressed")
	# R 键图标 — 与 DiscardButton 的 button_y_icon 样式完全一致
	var icon_script = load("res://ui/hud/ui_input_icon.gd")
	if icon_script:
		var xicon := TextureRect.new()
		xicon.set_script(icon_script)
		xicon.input_string = "ui_coop_ban"
		xicon.player_index = 0
		xicon.rect_min_size = Vector2(61, 61)
		xicon.margin_left = 5.0
		xicon.margin_top = 2.0
		xicon.margin_right = 66.0
		xicon.margin_bottom = 63.0
		xicon.expand = true
		xicon.mouse_filter = MOUSE_FILTER_IGNORE
		_at_rule_btn.add_child(xicon)
	btn_row.add_child(_at_rule_btn)

	# 2. AutoTato 按钮
	_at_auto_btn = Button.new()
	_at_auto_btn.name = "ATAutoButton"
	_at_auto_btn.text = tr("AUTOTATO_AUTOMATION")
	_at_auto_btn.align = Button.ALIGN_CENTER
	_at_auto_btn.focus_mode = Control.FOCUS_ALL
	if btn_font:
		_at_auto_btn.add_font_override("font", btn_font)
	_at_auto_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_at_auto_btn.connect("pressed", self, "_at_auto_pressed")
	btn_row.add_child(_at_auto_btn)

	# 3. 手柄焦点邻居
	_at_rule_btn.focus_neighbour_bottom = _at_rule_btn.get_path_to(_at_auto_btn)
	_at_auto_btn.focus_neighbour_top = _at_auto_btn.get_path_to(_at_rule_btn)
	_at_auto_btn.focus_neighbour_bottom = _at_auto_btn.get_path_to(_take_button)
	_take_button.focus_neighbour_top = _take_button.get_path_to(_at_auto_btn)


# ============================================================================
# show_item / focus 重写
# ============================================================================

func show_item(item_data) -> void:
	.show_item(item_data)
	_at_update_rule_label()
	call_deferred("_at_grab_default_focus")


func focus() -> void:
	if _items_container.visible:
		if _at_auto_btn and _at_auto_btn.visible:
			_at_auto_btn.call_deferred("grab_focus")
			return
	.focus()


func _at_grab_default_focus() -> void:
	if _at_auto_btn and _at_auto_btn.visible:
		_at_auto_btn.grab_focus()


# ============================================================================
# AutoTato 按钮 — 读取 chest_action 执行决策
# ============================================================================

func _at_auto_pressed() -> void:
	if _item_data == null:
		return
	var config = _Config.get_instance()
	if config == null:
		return

	var rule = config.get_item_rule(_item_data.my_id)
	var ca: String = String(rule.get("chest_action", "manual"))
	_Logger.info("箱子 AutoTato 触发 玩家=%d 物品=%s chest_action=%s" % [player_index, _item_data.my_id, ca], _LOG_NAME)

	_autotato_clear_button_guard()
	match ca:
		"take":
			if _take_button and is_instance_valid(_take_button):
				_take_button.emit_signal("pressed")
		"reject":
			if _discard_button and is_instance_valid(_discard_button):
				_discard_button.emit_signal("pressed")
		"cursed_only":
			var is_cursed: bool = (_item_data.get("cursed") != null and _item_data.get("cursed"))
			if is_cursed:
				if _take_button and is_instance_valid(_take_button):
					_take_button.emit_signal("pressed")
			else:
				if _discard_button and is_instance_valid(_discard_button):
					_discard_button.emit_signal("pressed")
		_:
			pass


# ============================================================================
# 规则按钮 → 弹窗
# ============================================================================

func _at_rule_pressed() -> void:
	if _item_data == null:
		return
	_at_ensure_popup()

	var config = _Config.get_instance()
	if config == null:
		return
	_at_popup_title.text = _item_data.get_name_text()

	var rule = config.get_item_rule(_item_data.my_id)
	_at_set_option(_at_shop_opt, rule.get("shop_action", "manual"), SHOP_ACTIONS)
	_at_set_option(_at_chest_opt, rule.get("chest_action", "manual"), CHEST_ACTIONS)

	_at_popup.popup_centered_ratio(1.0)
	call_deferred("_at_grab_popup_focus")


# ============================================================================
# 弹窗 UI 构建
# ============================================================================

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
	_at_shop_opt.focus_mode = Control.FOCUS_ALL
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
	_at_chest_opt.focus_mode = Control.FOCUS_ALL
	for pair in CHEST_ACTIONS:
		_at_chest_opt.add_item(tr(pair[1]))
	actions_grid.add_child(_at_chest_opt)

	content.add_child(actions_grid)

	content.add_child(HSeparator.new())
	var btn_hbox := HBoxContainer.new()
	btn_hbox.alignment = BoxContainer.ALIGN_END

	var save_btn := Button.new()
	save_btn.text = tr("AUTOTATO_SAVE")
	save_btn.focus_mode = Control.FOCUS_ALL
	save_btn.connect("pressed", self, "_at_popup_save")
	btn_hbox.add_child(save_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = tr("AUTOTATO_CANCEL")
	cancel_btn.focus_mode = Control.FOCUS_ALL
	cancel_btn.connect("pressed", self, "_at_popup_cancel")
	btn_hbox.add_child(cancel_btn)

	save_btn.focus_neighbour_right = save_btn.get_path_to(cancel_btn)
	cancel_btn.focus_neighbour_left = cancel_btn.get_path_to(save_btn)
	_at_chest_opt.focus_neighbour_bottom = _at_chest_opt.get_path_to(save_btn)
	_at_shop_opt.focus_neighbour_bottom = _at_shop_opt.get_path_to(save_btn)

	content.add_child(btn_hbox)


func _at_grab_popup_focus() -> void:
	if _at_shop_opt and _at_shop_opt.visible:
		_at_shop_opt.grab_focus()


# ============================================================================
# 弹窗事件
# ============================================================================

func _at_dimmer_clicked(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_at_popup.hide()
		call_deferred("_at_grab_default_focus")


func _at_popup_save() -> void:
	var config = _Config.get_instance()
	if config == null:
		return

	var si = _at_shop_opt.selected
	var ci = _at_chest_opt.selected
	var sa = SHOP_ACTIONS[si][0] if si >= 0 else "manual"
	var ca = CHEST_ACTIONS[ci][0] if ci >= 0 else "manual"
	if sa == "manual" and ca == "manual":
		config.remove_item_rule(_item_data.my_id)
	else:
		config.set_item_rule(_item_data.my_id, {"shop_action": sa, "chest_action": ca})

	_at_popup.hide()
	_at_update_rule_label()
	call_deferred("_at_grab_default_focus")


func _at_popup_cancel() -> void:
	_at_popup.hide()
	call_deferred("_at_grab_default_focus")


func _at_set_option(opt: OptionButton, value: String, actions: Array) -> void:
	for i in actions.size():
		if actions[i][0] == value:
			opt.select(i)
			return
	opt.select(0)


# ============================================================================
# 事件处理（与 shop_item.gd 一致）
# ----------------------------------------------------------------------------
# 关键: 卡片激活期间 (_at_rule_btn 可见), ui_ban (键盘 R / 手柄 B) 的 pressed 与
# released 完全由 AutoTato 接管, 绝不调 ._input(event) 传给 vanilla 父类 —— 否则
# vanilla _input 会调用 _on_BanButton_pressed / _on_BanButton_button_up 禁用物品.
# Godot 3 里 set_input_as_handled() 只挡 _unhandled_input, 挡不住本节点父类的
# _input (本节点父类逻辑只能靠不调 ._input() 来截断).
# ============================================================================

func _input(event: InputEvent) -> void:
	if _at_popup and _at_popup.visible:
		var modal = get_viewport().get_modal_stack_top()
		if modal is PopupMenu and _at_popup.is_a_parent_of(modal):
			if _at_handle_popup_menu_input(event, modal as PopupMenu):
				get_tree().set_input_as_handled()
				return

		if event.is_action_released("ui_cancel"):
			if _at_has_visible_popup_menu():
				return
			if event is InputEventJoypadButton and _at_popup_opened_by_gamepad:
				_at_popup_opened_by_gamepad = false
				return
			_at_popup.hide()
			# 同步设 main._skip_pause_check: ESC 松开同时是 ui_pause 松开, main.gd._process
			# 每帧轮询 Input.is_action_just_released("ui_pause") 会触发 _pause_menu.pause().
			# 该轮询绕过 _input 事件链, set_input_as_handled() 与 set_process_input() 都挡不住.
			# Godot 单帧内 _input 先于 _process, 这里同步设标志, 同帧 _check_for_pause 看到
			# 标志即提前 return (并清零). 下一帧 just_released 已过期, 轮询自然不触发.
			_at_skip_pause_check_this_frame()
			call_deferred("_at_grab_default_focus")
			get_tree().set_input_as_handled()
		return

	# 只在"活跃容器"上接管输入: 用 is_visible_in_tree() 而非 .visible -- 4 人 coop 架构下
	# 4 个 player_container 都在场景树里且 _input 都会触发, 单人模式只激活玩家 0 的容器,
	# 其余容器的 _items_container 隐藏. .visible 只反映按钮自身属性 (恒 true),
	# is_visible_in_tree() 才遍历父链反映真实可见性, 从而让非活跃容器的 _input 走
	# ._input(event) 交给 vanilla (vanilla 自身会因 _items_container 不可见跳过 ban).
	if _at_rule_btn == null or not _at_rule_btn.is_visible_in_tree():
		._input(event)
		return

	# 卡片激活: ui_ban 的 pressed/released 一律吞掉, 不传给 vanilla 父类.
	# pressed → 开规则弹窗 (不检查焦点: 卡片激活即可, 焦点在哪个按钮都该开);
	# released → 仅吞掉 (截断 vanilla button_up, 防禁用物品).
	if event.is_action_pressed("ui_ban") or event.is_action_released("ui_ban"):
		if event.is_action_pressed("ui_ban"):
			_at_rule_pressed()
			_at_popup_opened_by_gamepad = (event is InputEventJoypadButton)
		get_tree().set_input_as_handled()
		return

	._input(event)


# ============================================================================
# PopupMenu 循环导航
# ============================================================================

func _at_handle_popup_menu_input(event: InputEvent, popup: PopupMenu) -> bool:
	var item_count := popup.get_item_count()
	if item_count <= 0:
		return false
	if event.is_action_pressed("ui_up", true):
		var new_idx := (popup.get_current_index() - 1 + item_count) % item_count
		popup.set_current_index(new_idx)
		return true
	elif event.is_action_pressed("ui_down", true):
		var new_idx := (popup.get_current_index() + 1) % item_count
		popup.set_current_index(new_idx)
		return true
	return false


func _at_has_visible_popup_menu() -> bool:
	if _at_popup == null:
		return false
	return _at_find_visible_popup_menu(_at_popup)


func _at_find_visible_popup_menu(node: Node) -> bool:
	for child in node.get_children():
		if child is PopupMenu:
			var pm: PopupMenu = child as PopupMenu
			if pm.visible:
				return true
		if _at_find_visible_popup_menu(child):
			return true
	return false


# 拦截 main.gd 的 ui_pause 轮询: ESC 松开同时是 ui_pause 松开, main._process 每帧
# 轮询 Input.is_action_just_released("ui_pause") 会触发 _pause_menu.pause(). 该轮询
# 绕过 _input 事件链, set_input_as_handled() 挡不住. 借用 vanilla 的 _skip_pause_check
# 标志: Godot 单帧内 _input 先于 _process, 这里同步设 true, 同帧 _check_for_pause 看到
# 标志即提前 return (并清零), 下一帧 just_released 已过期.
func _at_skip_pause_check_this_frame() -> void:
	var main = get_tree().get_root().get_node_or_null("Main")
	if main == null:
		return
	main._skip_pause_check = true


# ============================================================================
# 颜色/文字映射（与 shop_item.gd 一致）
# ============================================================================

func _at_shop_action_text(a: String) -> String:
	match a:
		"manual": return tr("AUTOTATO_ACTION_MANUAL")
		"get": return tr("AUTOTATO_SHOP_GET")
		"lock_until_cursed": return tr("AUTOTATO_SHOP_LOCK_UNTIL_CURSED")
		"cursed_only": return tr("AUTOTATO_SHOP_CURSED_ONLY")
		"reject": return tr("AUTOTATO_SHOP_REJECT")
		_: return tr("AUTOTATO_ACTION_MANUAL")


func _at_chest_action_text(a: String) -> String:
	match a:
		"manual": return tr("AUTOTATO_ACTION_MANUAL")
		"take": return tr("AUTOTATO_CHEST_TAKE")
		"cursed_only": return tr("AUTOTATO_SHOP_CURSED_ONLY")
		"reject": return tr("AUTOTATO_SHOP_REJECT")
		_: return tr("AUTOTATO_ACTION_MANUAL")


func _at_shop_action_hex(a: String) -> String:
	match a:
		"manual": return _HEX_MANUAL
		"get": return _HEX_GET
		"lock_until_cursed": return _HEX_WAIT
		"cursed_only": return _HEX_CURSED
		"reject": return _HEX_REJECT
		_: return _HEX_MANUAL


func _at_chest_action_hex(a: String) -> String:
	match a:
		"manual": return _HEX_MANUAL
		"take": return _HEX_GET
		"cursed_only": return _HEX_CURSED
		"reject": return _HEX_REJECT
		_: return _HEX_MANUAL
