extends "res://ui/menus/shop/shop_item.gd"

# ============================================================================
# AutoTato — shop_item Script Extension (新商店链路)
# ----------------------------------------------------------------------------
# 在商店物品卡片上添加规则按钮。
# 规则按钮以 LockButton 为样式基准，放入 TopButtonsContainer 中
# 与 LockButton 同级；焦点兼容 vanilla shop_item_focused 信号链。
# ============================================================================

const _Logger = preload("res://mods-unpacked/fengyifan-AutoTato/utils/logger.gd")
const _LOG_NAME := "ShopItem"

# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	._ready()
	_at_add_rule_button()

# ============================================================================
# 规则按钮
# ============================================================================

func _at_add_rule_button() -> void:
	var lock_btn = get_node_or_null("%LockButton")
	if lock_btn == null:
		_Logger.warning("LockButton not found, skip rule button", _LOG_NAME)
		return

	var btn_parent = lock_btn.get_parent()
	if btn_parent == null:
		return

	var lock_idx = lock_btn.get_index()

	# 以 LockButton 为样式基准
	var btn := Button.new()
	btn.name = "AutoTatoRuleButton"
	btn.text = tr("AUTOTATO_ITEM_RULE")
	btn.align = Button.ALIGN_CENTER
	btn.focus_mode = Control.FOCUS_ALL
	btn.rect_min_size.y = lock_btn.rect_min_size.y
	_at_configure_rule_button_from_lock_button(btn, lock_btn)

	# 插入到 LockButton 之后，作为兄弟节点
	btn_parent.add_child(btn)
	btn_parent.move_child(btn, lock_idx + 1)

	# 焦点信号链 — 复用 vanilla shop_item_focused / shop_item_unfocused
	btn.connect("focus_entered", self, "_at_on_rule_button_focus_entered")
	btn.connect("focus_exited", self, "_at_on_rule_button_focus_exited")
	btn.connect("pressed", self, "_at_on_rule_button_pressed")

	# 左侧输入图标 + 右侧锁图标占位
	_at_add_rule_button_input_icon(btn, lock_btn)
	_at_add_rule_button_lock_icon_spacer(btn, lock_btn)

	call_deferred("_at_sync_rule_button_size")
	_at_rule_btn = btn


var _at_rule_btn: Button = null


# 从 LockButton 复制字体和布局属性
func _at_configure_rule_button_from_lock_button(rule_btn: Button, lock_btn: Button) -> void:
	var font = lock_btn.get_font("font")
	if font:
		rule_btn.add_font_override("font", font)
	rule_btn.size_flags_horizontal = lock_btn.size_flags_horizontal
	rule_btn.size_flags_vertical = lock_btn.size_flags_vertical
	rule_btn.expand_icon = lock_btn.expand_icon


# 左侧输入图标 — 参考 LockButton AdditionalIcon / ui_input_icon.gd
func _at_add_rule_button_input_icon(rule_btn: Button, _lock_btn: Button) -> void:
	var icon_script = load("res://ui/hud/ui_input_icon.gd")
	if icon_script == null:
		return
	var icon := TextureRect.new()
	icon.set_script(icon_script)
	icon.input_string = "ui_auto_tato_rule" if InputMap.has_action("ui_auto_tato_rule") else "ui_coop_ban"
	icon.player_index = 0
	icon.rect_min_size = Vector2(51, 0)
	icon.margin_right = 51.0
	icon.expand = true
	icon.mouse_filter = MOUSE_FILTER_IGNORE
	rule_btn.add_child(icon)


# 右侧锁图标占位 — 参考 LockButton LockIcon 的右侧锚定和宽度
func _at_add_rule_button_lock_icon_spacer(rule_btn: Button, lock_btn: Button) -> void:
	var lock_icon = lock_btn.get_node_or_null("LockIcon") if lock_btn.has_node("LockIcon") else null
	var spacer := TextureRect.new()
	spacer.name = "LockIconSpacer"
	spacer.mouse_filter = MOUSE_FILTER_IGNORE
	spacer.visible = false
	spacer.anchor_left = 1.0
	spacer.anchor_right = 1.0
	spacer.anchor_bottom = 1.0
	spacer.rect_min_size = Vector2(51, 0)
	spacer.margin_left = -51.0
	spacer.expand = true
	spacer.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rule_btn.add_child(spacer)


# 延迟同步规则按钮宽度到 LockButton 实际布局宽度
func _at_sync_rule_button_size() -> void:
	if _at_rule_btn == null:
		return
	var lock_btn = get_node_or_null("%LockButton")
	if lock_btn == null:
		return
	var w: float = lock_btn.rect_size.x
	if w > 1.0:
		_at_rule_btn.rect_min_size.x = w


# 规则按钮获得焦点 → 让 vanilla BaseShop._input() 知道当前卡片
func _at_on_rule_button_focus_entered() -> void:
	emit_signal("shop_item_focused", self)


# 规则按钮失焦 → 通知 vanilla
func _at_on_rule_button_focus_exited() -> void:
	emit_signal("shop_item_unfocused", self)


# 点击规则按钮 → 目前的占位行为
func _at_on_rule_button_pressed() -> void:
	_Logger.info("rule button pressed item=%s" % str(item_data.my_id if item_data else "?"), _LOG_NAME)
