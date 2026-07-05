extends Control

# ============================================================================
# AutoTato — General Tab (v7 通用配置)
# ----------------------------------------------------------------------------
# 自动化设置: 商店自动化 / 升级自动化
# 预算设置: 最低金币保留 / 物品价格上限 / 刷新金额上限
# 行为设置: 自动开始下一关 / 失焦保持运行
# ============================================================================

const LOG_NAME := "fengyifan-AutoTato:GeneralTab"
const _Config = preload("res://mods-unpacked/fengyifan-AutoTato/config/config.gd")


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "ScrollContainer"
	scroll.anchor_right = 1.0
	scroll.anchor_bottom = 1.0
	scroll.scroll_horizontal_enabled = false
	scroll.follow_focus = true
	add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.name = "GeneralVBox"
	vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	vbox.margin_left = 16.0
	vbox.margin_right = 16.0
	vbox.margin_top = 8.0
	vbox.add_constant_override("separation", 16)
	scroll.add_child(vbox)

	# ---- 自动化设置 (置顶) ----
	var auto_label := Label.new()
	auto_label.text = tr("AUTOTATO_SECTION_AUTOMATION")
	auto_label.modulate = Color(0.35, 0.8, 1.0, 1.0)
	vbox.add_child(auto_label)

	vbox.add_child(_build_toggle("shop_automation", tr("AUTOTATO_SHOP_AUTOMATION"), tr("AUTOTATO_SHOP_AUTO_DESC"), "_on_auto_bool_toggled"))
	vbox.add_child(_build_toggle("upgrade_automation", tr("AUTOTATO_UPGRADE_AUTOMATION"), tr("AUTOTATO_UPGRADE_AUTO_DESC"), "_on_auto_bool_toggled"))

	vbox.add_child(HSeparator.new())

	# ---- 预算设置 ----
	var budget_label := Label.new()
	budget_label.text = tr("AUTOTATO_SECTION_BUDGET")
	budget_label.modulate = Color(0.35, 0.8, 1.0, 1.0)
	vbox.add_child(budget_label)

	vbox.add_child(_build_number_input("min_gold_balance", tr("AUTOTATO_MIN_GOLD_BALANCE"), tr("AUTOTATO_MIN_GOLD_DESC")))
	vbox.add_child(_build_number_input("item_price_threshold", tr("AUTOTATO_ITEM_PRICE_LIMIT"), tr("AUTOTATO_ITEM_PRICE_DESC")))
	vbox.add_child(_build_number_input("reroll_budget", tr("AUTOTATO_REROLL_BUDGET"), tr("AUTOTATO_REROLL_BUDGET_DESC")))

	vbox.add_child(HSeparator.new())

	# ---- 行为设置 ----
	var behavior_label := Label.new()
	behavior_label.text = tr("AUTOTATO_SECTION_BEHAVIOR")
	behavior_label.modulate = Color(0.35, 0.8, 1.0, 1.0)
	vbox.add_child(behavior_label)

	vbox.add_child(_build_toggle("auto_start_wave", tr("AUTOTATO_AUTO_START_WAVE"), tr("AUTOTATO_AUTO_START_WAVE_DESC"), "_on_general_bool_toggled"))
	vbox.add_child(_build_toggle("keep_running", tr("AUTOTATO_KEEP_RUNNING"), tr("AUTOTATO_KEEP_RUNNING_DESC"), "_on_general_bool_toggled"))
	vbox.add_child(_build_toggle("turbo_mode", tr("AUTOTATO_TURBO_MODE"), tr("AUTOTATO_TURBO_MODE_DESC"), "_on_general_bool_toggled"))

	_refresh()


func _build_toggle(meta_key: String, title: String, desc: String, callback: String) -> Control:
	var group := VBoxContainer.new()

	var cb := CheckButton.new()
	cb.name = "%sCheck" % meta_key
	cb.text = title
	cb.size_flags_horizontal = SIZE_EXPAND_FILL
	cb.connect("toggled", self, callback, [meta_key])
	group.add_child(cb)

	var desc_label := Label.new()
	desc_label.text = desc
	desc_label.modulate = Color(1, 1, 1, 0.5)
	desc_label.size_flags_horizontal = SIZE_EXPAND_FILL
	desc_label.autowrap = true
	group.add_child(desc_label)

	return group


func _build_number_input(key: String, title: String, desc: String) -> Control:
	var group := VBoxContainer.new()

	var row := HBoxContainer.new()
	row.rect_min_size.y = 32

	var label := Label.new()
	label.text = title
	label.size_flags_horizontal = SIZE_EXPAND_FILL
	label.valign = Label.VALIGN_CENTER
	row.add_child(label)

	var edit := LineEdit.new()
	edit.name = "%sEdit" % key
	edit.text = "0"
	edit.rect_min_size = Vector2(80, 0)
	edit.align = LineEdit.ALIGN_CENTER
	edit.connect("text_changed", self, "_on_general_int_changed", [key])
	row.add_child(edit)

	group.add_child(row)

	var desc_label := Label.new()
	desc_label.text = desc
	desc_label.modulate = Color(1, 1, 1, 0.5)
	desc_label.size_flags_horizontal = SIZE_EXPAND_FILL
	desc_label.autowrap = true
	group.add_child(desc_label)

	return group


func _refresh() -> void:
	var bridge = _Config.get_instance()
	if bridge == null:
		return

	# 自动化开关 (顶层 key, 不在 general dict 内)
	var shop_auto_cb = _find_check("shop_automationCheck")
	if shop_auto_cb:
		shop_auto_cb.pressed = bridge.is_shop_automation_enabled()

	var upgrade_auto_cb = _find_check("upgrade_automationCheck")
	if upgrade_auto_cb:
		upgrade_auto_cb.pressed = bridge.is_upgrade_automation_enabled()

	var gen = bridge.get_general()
	_set_edit_text("min_gold_balanceEdit", str(int(gen.get("min_gold_balance", 0))))
	_set_edit_text("item_price_thresholdEdit", str(int(gen.get("item_price_threshold", 0))))
	_set_edit_text("reroll_budgetEdit", str(int(gen.get("reroll_budget", 0))))

	var asw_cb = _find_check("auto_start_waveCheck")
	if asw_cb:
		asw_cb.pressed = bool(gen.get("auto_start_wave", false))

	var kr_cb = _find_check("keep_runningCheck")
	if kr_cb:
		kr_cb.pressed = bool(gen.get("keep_running", false))

	var turbo_cb = _find_check("turbo_modeCheck")
	if turbo_cb:
		turbo_cb.pressed = bool(gen.get("turbo_mode", false))


func _set_edit_text(name: String, text: String) -> void:
	var edit = _find_edit(name)
	if edit:
		edit.text = text


func _on_general_int_changed(new_text: String, key: String) -> void:
	if not new_text.is_valid_integer():
		return
	var bridge = _Config.get_instance()
	if bridge:
		bridge.set_general(key, int(new_text))


func _on_general_bool_toggled(pressed: bool, key: String) -> void:
	var bridge = _Config.get_instance()
	if bridge:
		bridge.set_general(key, pressed)


func _on_auto_bool_toggled(pressed: bool, key: String) -> void:
	var bridge = _Config.get_instance()
	if bridge:
		match key:
			"shop_automation":
				bridge.set_shop_automation_enabled(pressed)
			"upgrade_automation":
				bridge.set_upgrade_automation_enabled(pressed)


# 递归搜索 ScrollContainer 内的子节点
func _find_check(name: String):
	var scroll = get_node_or_null("ScrollContainer")
	if scroll == null:
		return null
	return _find_recursive(scroll, name)


func _find_edit(name: String):
	var scroll = get_node_or_null("ScrollContainer")
	if scroll == null:
		return null
	return _find_recursive(scroll, name)


func _find_recursive(node, name: String):
	if node.name == name:
		return node
	for child in node.get_children():
		var found = _find_recursive(child, name)
		if found:
			return found
	return null
