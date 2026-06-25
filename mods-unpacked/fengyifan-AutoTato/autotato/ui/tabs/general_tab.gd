extends Control

# ============================================================================
# AutoTato — General Tab (v6 通用配置)
# ----------------------------------------------------------------------------
# 自动化开关:
#   - 升级自动化 / 商店自动化 (Toggle)
# 预算设置:
#   - min_gold_balance (购买后保留金币)
#   - item_price_threshold (单件物品价格上限, 0=不限)
# 行为设置:
#   - auto_start_wave (商店无法刷新时自动开始下一关)
#   - keep_running (窗口失焦时保持运行)
# ============================================================================

const LOG_NAME := "fengyifan-AutoTato:GeneralTab"


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.name = "GeneralVBox"
	vbox.anchor_right = 1.0
	vbox.anchor_bottom = 1.0
	vbox.margin_left = 16.0
	vbox.margin_right = 16.0
	vbox.margin_top = 8.0
	vbox.add_constant_override("separation", 16)
	add_child(vbox)

	# ---- 升级自动化 ----
	vbox.add_child(_build_toggle("upgrade_auto", "升级自动化", "在升级时自动选择最优项", "_on_upgrade_toggled"))

	# ---- 商店自动化 ----
	vbox.add_child(_build_toggle("shop_auto", "商店自动化", "在商店中自动购买 / 锁定 / 拒绝物品", "_on_shop_toggled"))

	vbox.add_child(HSeparator.new())

	# ---- 预算设置 ----
	var budget_label := Label.new()
	budget_label.text = "预算设置"
	vbox.add_child(budget_label)

	vbox.add_child(_build_number_input("min_gold_balance", "最低金币保留", "购买后至少保留的金币数", "_on_general_int_changed"))

	vbox.add_child(_build_number_input("item_price_threshold", "物品价格上限", "单件物品价格超过此值不自动购买 (0=不限)", "_on_general_int_changed"))

	vbox.add_child(HSeparator.new())

	# ---- 行为设置 ----
	var behavior_label := Label.new()
	behavior_label.text = "行为设置"
	vbox.add_child(behavior_label)

	vbox.add_child(_build_toggle("auto_start_wave", "自动开始下一关", "商店无法刷新时自动进入下一波敌袭", "_on_general_bool_toggled"))

	vbox.add_child(_build_toggle("keep_running", "失焦保持运行", "窗口失去焦点时游戏继续运行", "_on_general_bool_toggled"))

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


func _build_number_input(key: String, title: String, desc: String, callback: String) -> Control:
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
	edit.rect_min_size = Vector2(80, 0)
	edit.align = LineEdit.ALIGN_CENTER
	edit.connect("text_changed", self, callback, [key])
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
	var bridge = Engine.get_meta("fengyifan-AutoTato:Bridge")
	if bridge == null:
		return

	# Toggles
	var upgrade_cb = _find_check("upgrade_autoCheck")
	if upgrade_cb:
		upgrade_cb.pressed = bridge.is_upgrade_automation_enabled()

	var shop_cb = _find_check("shop_autoCheck")
	if shop_cb:
		shop_cb.pressed = bridge.is_shop_automation_enabled()

	# Number inputs
	var gen = bridge.get_general()
	var mgb_edit = _find_edit("min_gold_balanceEdit")
	if mgb_edit:
		mgb_edit.text = str(int(gen.get("min_gold_balance", 0)))

	var ipt_edit = _find_edit("item_price_thresholdEdit")
	if ipt_edit:
		ipt_edit.text = str(int(gen.get("item_price_threshold", 0)))

	# Behavior toggles
	var asw_cb = _find_check("auto_start_waveCheck")
	if asw_cb:
		asw_cb.pressed = bool(gen.get("auto_start_wave", false))

	var kr_cb = _find_check("keep_runningCheck")
	if kr_cb:
		kr_cb.pressed = bool(gen.get("keep_running", false))


func _on_upgrade_toggled(pressed: bool, _key: String) -> void:
	var bridge = Engine.get_meta("fengyifan-AutoTato:Bridge")
	if bridge:
		bridge.set_upgrade_automation_enabled(pressed)


func _on_shop_toggled(pressed: bool, _key: String) -> void:
	var bridge = Engine.get_meta("fengyifan-AutoTato:Bridge")
	if bridge:
		bridge.set_shop_automation_enabled(pressed)


func _on_general_int_changed(new_text: String, key: String) -> void:
	if not new_text.is_valid_integer():
		return
	var bridge = Engine.get_meta("fengyifan-AutoTato:Bridge")
	if bridge:
		bridge.set_general(key, int(new_text))


func _on_general_bool_toggled(pressed: bool, key: String) -> void:
	var bridge = Engine.get_meta("fengyifan-AutoTato:Bridge")
	if bridge:
		bridge.set_general(key, pressed)


func _find_check(name: String):
	var vbox = get_node_or_null("GeneralVBox")
	if vbox == null:
		return null
	for child in vbox.get_children():
		var cb = child.get_node_or_null(name)
		if cb:
			return cb
	return null


func _find_edit(name: String):
	var vbox = get_node_or_null("GeneralVBox")
	if vbox == null:
		return null
	for child in vbox.get_children():
		var edit = child.get_node_or_null(name)
		if edit:
			return edit
	return null
