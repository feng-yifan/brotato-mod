extends "res://ui/menus/shop/shop_item.gd"

# ============================================================================
# AutoTato — shop_item Script Extension (新商店链路)
# ----------------------------------------------------------------------------
# 在商店物品卡片底部添加规则按钮，完全取代 BanButton。
# 规则按钮插入到 BottomButtonsContainer 中 BanButton 的原位置；
# BanButton 被禁用并隐藏，规则按钮继承其快捷键（ui_ban）。
# 按钮文字按类型区分：武器显示武器规则，物品显示物品规则。
# 焦点兼容 vanilla shop_item_focused 信号链。
# ============================================================================

const _Logger = preload("res://mods-unpacked/fengyifan-AutoTato/utils/logger.gd")
const _LOG_NAME := "ShopItem"

# 手柄 B 键守卫：标记动作是否由手柄 B 键触发
#（B 同时映射 ui_ban + ui_cancel，松开时需跳过重复处理）
var _at_rule_opened_by_gamepad := false

# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	._ready()
	_at_add_rule_button()


func _input(event: InputEvent) -> void:
	# 将 ui_ban（键盘 R / 手柄 B）重映射到规则按钮
	if _at_rule_btn == null or not _at_rule_btn.visible:
		return

	if event.is_action_pressed("ui_ban"):
		if _at_card_has_focus():
			_at_on_rule_button_pressed()
			_at_rule_opened_by_gamepad = (event is InputEventJoypadButton)
			get_tree().set_input_as_handled()


# ============================================================================
# Vanilla 覆盖
# ============================================================================

# 完全禁用 BanButton，使其在所有情况下都不可见
func manage_ban_button_visibility() -> void:
	_ban_button.disable()
	_ban_button.hide()


# set_shop_item 由 ShopItemsContainer 在配置每个槽位时调用（此时 item_data 才被赋值）。
# _ready 阶段 item_data 还是 null，按钮文字和宽度必须在这里刷新。
func set_shop_item(p_item_data, p_wave_value: int = RunData.current_wave) -> void:
	.set_shop_item(p_item_data, p_wave_value)
	if _at_rule_btn:
		var is_weapon = p_item_data is WeaponData
		_at_rule_btn.text = tr("AUTOTATO_WEAPON_RULE") if is_weapon else tr("AUTOTATO_ITEM_RULE")
	call_deferred("_at_sync_rule_button_size")


# ============================================================================
# 规则按钮
# ============================================================================

var _at_rule_btn: Button = null


func _at_add_rule_button() -> void:
	var ban_btn = get_node_or_null("%BanButton")
	if ban_btn == null:
		_Logger.warning("BanButton not found, skip rule button", _LOG_NAME)
		return

	# 禁用并隐藏 BanButton 及其子节点
	ban_btn.disabled = true
	ban_btn.visible = false
	var pbar = ban_btn.get_node_or_null("progress_ban")
	if pbar:
		pbar.visible = false
	var aicon = ban_btn.get_node_or_null("AdditionalIcon")
	if aicon:
		aicon.visible = false

	var btn_parent = ban_btn.get_parent()  # → BottomButtonsContainer
	if btn_parent == null:
		return

	var ban_idx = ban_btn.get_index()

	# 以 LockButton 为样式基准
	var lock_btn = get_node_or_null("%LockButton")
	if lock_btn == null:
		_Logger.warning("LockButton not found, skip rule button", _LOG_NAME)
		return

	var btn := Button.new()
	btn.name = "AutoTatoRuleButton"
	# 初始文字设为物品规则，set_shop_item 中会根据 item_data 更新
	btn.text = tr("AUTOTATO_ITEM_RULE")
	btn.align = Button.ALIGN_CENTER
	btn.focus_mode = Control.FOCUS_ALL
	btn.rect_min_size.y = ban_btn.rect_min_size.y
	_at_configure_rule_button_from_lock_button(btn, lock_btn)

	# 插入到 BanButton 原位置（BottomButtonsContainer 中）
	btn_parent.add_child(btn)
	btn_parent.move_child(btn, ban_idx)

	# 焦点信号链 — 复用 vanilla shop_item_focused / shop_item_unfocused
	btn.connect("focus_entered", self, "_at_on_rule_button_focus_entered")
	btn.connect("focus_exited", self, "_at_on_rule_button_focus_exited")
	btn.connect("pressed", self, "_at_on_rule_button_pressed")

	# 左侧输入图标
	_at_add_rule_button_input_icon(btn, lock_btn)

	call_deferred("_at_sync_rule_button_size")
	_at_rule_btn = btn


# 从 LockButton 复制字体和布局属性
func _at_configure_rule_button_from_lock_button(rule_btn: Button, lock_btn: Button) -> void:
	var font = lock_btn.get_font("font")
	if font:
		rule_btn.add_font_override("font", font)
	rule_btn.size_flags_horizontal = lock_btn.size_flags_horizontal
	rule_btn.size_flags_vertical = lock_btn.size_flags_vertical
	rule_btn.expand_icon = lock_btn.expand_icon


# 左侧输入图标 — 参考 BanButton AdditionalIcon 样式
func _at_add_rule_button_input_icon(rule_btn: Button, _lock_btn: Button) -> void:
	var icon_script = load("res://ui/hud/ui_input_icon.gd")
	if icon_script == null:
		return
	var icon := TextureRect.new()
	icon.name = "ui_input_icon"
	icon.set_script(icon_script)
	icon.input_string = "ui_coop_ban"
	icon.player_index = 0
	icon.rect_min_size = Vector2(51, 0)
	icon.margin_right = 51.0
	icon.margin_bottom = 51.0
	icon.expand = true
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = MOUSE_FILTER_IGNORE
	rule_btn.add_child(icon)
	call_deferred("_at_set_fallback_icon", icon)


func _at_set_fallback_icon(icon: TextureRect) -> void:
	if icon.texture == null:
		icon.texture = preload("res://ui/menus/global/key_r.png")


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


# 判断焦点是否在本卡片子树内
func _at_card_has_focus() -> bool:
	var fo: Control = get_focus_owner() as Control
	if fo == null:
		return false
	var node: Node = fo
	while node:
		if node == self:
			return true
		node = node.get_parent()
	return false
