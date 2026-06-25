extends Control

# ============================================================================
# AutoTato — General Tab (P5.4 通用配置)
# ----------------------------------------------------------------------------
# 自动化总开关:
#   - 商店自动化 (shop_automation_enabled): 开启后 AutoTato 在商店自动决策
#   - 升级自动化 (upgrade_automation_enabled): 开启后 AutoTato 在升级时自动决策
#
# 两个 Toggle 变化时直接调用 Bridge 写入, 自动持久化.
# ============================================================================

const LOG_NAME := "fengyifan-AutoTato:GeneralTab"


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.name = "GeneralVBox"
	vbox.anchor_right = 1.0
	vbox.anchor_bottom = 1.0
	vbox.margin_left = 12.0
	vbox.margin_right = 12.0
	vbox.margin_top = 8.0
	vbox.add_constant_override("separation", 12)
	add_child(vbox)

	# ---- 升级自动化 ----
	var upgrade_toggle = _build_toggle(
		"upgrade_auto", "升级自动化", "在升级时自动选择最优项",
		"_on_upgrade_toggled"
	)
	vbox.add_child(upgrade_toggle)

	# ---- 商店自动化 ----
	var shop_toggle = _build_toggle(
		"shop_auto", "商店自动化", "在商店中自动购买 / 锁定 / 拒绝物品",
		"_on_shop_toggled"
	)
	vbox.add_child(shop_toggle)

	# ---- 同步当前状态 ----
	_refresh()


func _build_toggle(meta_key: String, title: String, desc: String, callback: String) -> Control:
	var group := VBoxContainer.new()

	# CheckButton — 100% 宽度
	var cb := CheckButton.new()
	cb.name = "%sCheck" % meta_key
	cb.text = title
	cb.size_flags_horizontal = SIZE_EXPAND_FILL
	cb.connect("toggled", self, callback)
	group.add_child(cb)

	# 说明文字 — 开关下一行
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

	var shop_cb = _find_check("shop_autoCheck")
	if shop_cb:
		shop_cb.pressed = bridge.is_shop_automation_enabled()

	var upgrade_cb = _find_check("upgrade_autoCheck")
	if upgrade_cb:
		upgrade_cb.pressed = bridge.is_upgrade_automation_enabled()


func _find_check(name: String):
	var vbox = get_node_or_null("GeneralVBox")
	if vbox == null:
		return null
	for row in vbox.get_children():
		var cb = row.get_node_or_null(name)
		if cb:
			return cb
	return null


func _on_shop_toggled(pressed: bool) -> void:
	var bridge = Engine.get_meta("fengyifan-AutoTato:Bridge")
	if bridge:
		bridge.set_shop_automation_enabled(pressed)


func _on_upgrade_toggled(pressed: bool) -> void:
	var bridge = Engine.get_meta("fengyifan-AutoTato:Bridge")
	if bridge:
		bridge.set_upgrade_automation_enabled(pressed)
