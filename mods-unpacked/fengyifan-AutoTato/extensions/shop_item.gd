extends "res://ui/menus/shop/shop_item.gd"

# ============================================================================
# AutoTato — shop_item Script Extension (新商店链路)
# ----------------------------------------------------------------------------
# 在商店物品卡片底部添加规则按钮，完全取代 BanButton。
# 规则按钮插入到 BottomButtonsContainer 中 BanButton 的原位置；
# BanButton 被禁用并隐藏，规则按钮继承其快捷键（ui_ban）。
# 按钮文字按类型区分：武器显示武器规则，物品显示物品规则。
# 焦点兼容 vanilla shop_item_focused 信号链。
#
# 卡片内规则文字（Category 行下方）：
#   武器：Category 文本按武器类别规则着色（RichTextLabel），下一行显示武器自身规则
#   物品：Category 保持原样，下一行显示逗号分隔的 shop/chest 规则
# ============================================================================

const _Logger = preload("res://mods-unpacked/fengyifan-AutoTato/utils/logger.gd")
const _Config = preload("res://mods-unpacked/fengyifan-AutoTato/config/config.gd")
const _LOG_NAME := "ShopItem"

# ============================================================================
# 规则颜色中央定义
# 所有规则相关的颜色都在此处，统一用 bbcode hex（RichTextLabel 着色用）
# ============================================================================

# --- 物品规则颜色 ---
const _HEX_MANUAL  := "#ffffff59"   # 手动 (半透明白)
const _HEX_GET     := "#59ff73"     # 购买/拿取 (绿)
const _HEX_REJECT  := "#ff5959"     # 拒绝/手动 (红)
const _HEX_WAIT    := "#ffc740"     # 锁定等诅咒 (橙)
const _HEX_CURSED  := "#cc73ff"     # 仅诅咒 (紫)
const _HEX_SKIP    := "#59ff73"     # 跳过 (绿)
const _HEX_FOLLOW  := "#ffffff59"   # 受类别控制 (半透明白)

# 手柄 B 键守卫：标记动作是否由手柄 B 键触发
#（B 同时映射 ui_ban + ui_cancel，松开时需跳过重复处理）
var _at_rule_opened_by_gamepad := false

# 卡片内规则文字（RichTextLabel 以支持 bbcode 着色）
var _at_rule_label: RichTextLabel = null

# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	._ready()
	_Logger.info("_ready called", _LOG_NAME)
	_at_add_rule_button()
	_at_add_rule_label()
	_Logger.info("_ready done, rule_label=%s" % str(_at_rule_label != null), _LOG_NAME)


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


# 槽位被清空（买走/ban）时清除规则文字，避免残留
func deactivate() -> void:
	.deactivate()
	if _at_rule_label:
		_at_rule_label.text = ""


# set_shop_item 由 ShopItemsContainer 在配置每个槽位时调用（此时 item_data 才被赋值）。
# _ready 阶段 item_data 还是 null，按钮文字和宽度必须在这里刷新。
func set_shop_item(p_item_data, p_wave_value: int = RunData.current_wave) -> void:
	.set_shop_item(p_item_data, p_wave_value)
	_Logger.info("set_shop_item called, item=%s weapon=%s" % [str(p_item_data.my_id if p_item_data else "?"), str(p_item_data is WeaponData)], _LOG_NAME)
	if _at_rule_btn:
		var is_weapon = p_item_data is WeaponData
		_at_rule_btn.text = tr("AUTOTATO_WEAPON_RULE") if is_weapon else tr("AUTOTATO_ITEM_RULE")
	call_deferred("_at_sync_rule_button_size")
	call_deferred("_at_update_rule_label")


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


# ============================================================================
# 卡片内规则文字
# ============================================================================

# 在 ItemDescription 的 VBoxContainer（Name/Category 所在容器）中插入规则标签
# 插入到 Category 节点之后
func _at_add_rule_label() -> void:
	# ItemDescription 的 unique_name_in_owner 在 shop_item.tscn 中设置，
	# 但通过 get_node 可能在当前脚本的作用域内找不到，先用路径回退
	var desc = get_node_or_null("PanelContainer/MarginContainer/VBoxContainer/ItemDescription")
	if desc == null:
		desc = get_node_or_null("%ItemDescription")
	_Logger.info("_at_add_rule_label desc=%s" % str(desc != null), _LOG_NAME)
	if desc == null:
		return

	# Category 的 unique_name_in_owner 在 item_description.tscn 中设置，
	# 从 shop_item 作用域无法通过 %Category 找到，用绝对路径
	var cat = desc.get_node_or_null("HBoxContainer/ScrollContainer/VBoxContainer/Category")
	_Logger.info("_at_add_rule_label cat=%s" % str(cat != null), _LOG_NAME)
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
	label.text = "[test]"
	var cat_font = cat.get_font("font")
	if cat_font:
		label.add_font_override("normal_font", cat_font)
	cat_parent.add_child(label)
	cat_parent.move_child(label, cat_idx + 1)
	_at_rule_label = label
	_Logger.info("_at_add_rule_label done idx=%d" % cat_idx, _LOG_NAME)


# 刷新规则文字
func _at_update_rule_label() -> void:
	_Logger.info("_at_update_rule_label entered label=%s data=%s" % [str(_at_rule_label != null), str(item_data != null)], _LOG_NAME)
	if _at_rule_label == null or item_data == null:
		return

	var config = _Config.get_instance()
	_Logger.info("_at_update_rule_label config=%s" % str(config != null), _LOG_NAME)
	if config == null:
		_at_rule_label.text = ""
		return

	if item_data is WeaponData:
		_at_update_weapon_rule_label(config)
	else:
		_at_update_item_rule_label(config)


# 武器：对 Category 中每个类别按规则着色，然后附加自身规则文字
func _at_update_weapon_rule_label(config) -> void:
	_Logger.info("_at_update_weapon_rule_label", _LOG_NAME)
	var cat = _at_find_category_node()
	_Logger.info("weapon cat=%s" % str(cat != null), _LOG_NAME)
	if cat == null:
		return

	var weapon_sets = item_data.get("sets")
	var weapon_rules = config.get_weapon_rules()
	var set_rules = config.get_weapon_category_rules()
	var wid: String = item_data.get("weapon_id")

	# 1. 用 RichTextLabel 替换 Category，给每个类别词单独上色
	var rich = _at_ensure_rich_category(cat)
	if rich == null:
		return

	var bbcode := ""
	if weapon_sets is Array and weapon_sets.size() > 0:
		var parts := []
		for s in weapon_sets:
			# weapon_sets 元素是 SetData 资源（非 Dictionary），用属性访问
			var sid: String = s.my_id if s.get("my_id") != null else ""
			var sname: String = tr(s.name) if s.get("name") != null else sid
			var cr = set_rules.get(sid, "manual")
			parts.push_back("[color=%s]%s[/color]" % [_at_set_color_hex(cr), sname])
		bbcode = ", ".join(parts)
	else:
		bbcode = cat.text
	rich.bbcode_text = bbcode

	# 2. 设置武器自身规则文字（用 bbcode 着色，与物品分支统一）
	var action = _at_resolve_weapon_action(wid, weapon_rules, set_rules)
	var text := ""
	var hex := _HEX_FOLLOW
	match action:
		"skip":
			text = tr("AUTOTATO_ACTION_SKIP")
			hex = _HEX_SKIP
		"manual":
			text = tr("AUTOTATO_ACTION_MANUAL")
			hex = _HEX_REJECT
		_:
			text = tr("AUTOTATO_FOLLOW_SET_RULE")
			hex = _HEX_FOLLOW
	_at_rule_label.bbcode_text = "[color=%s]%s[/color]" % [hex, text]


# 物品：显示逗号分隔的 shop_action, chest_action，各自上色
func _at_update_item_rule_label(config) -> void:
	_Logger.info("_at_update_item_rule_label", _LOG_NAME)
	var rule = config.get_item_rule(item_data.my_id)
	_Logger.info("item rule=%s" % str(rule), _LOG_NAME)
	var sa: String = String(rule.get("shop_action", "manual"))
	var ca: String = String(rule.get("chest_action", "manual"))

	var sa_text = _at_shop_action_text(sa)
	var ca_text = _at_chest_action_text(ca)

	# 用 bbcode 实现各自上色
	_at_rule_label.bbcode_text = "[color=%s]%s[/color], [color=%s]%s[/color]" % [
		_at_shop_action_hex(sa), sa_text,
		_at_chest_action_hex(ca), ca_text
	]


# ============================================================================
# Category 节点管理
# ============================================================================

func _at_find_category_node():
	var desc = get_node_or_null("PanelContainer/MarginContainer/VBoxContainer/ItemDescription")
	if desc == null:
		desc = get_node_or_null("%ItemDescription")
	if desc == null:
		return null
	return desc.get_node_or_null("HBoxContainer/ScrollContainer/VBoxContainer/Category")


# 将 Category Button 替换为 RichTextLabel（保留位置和文本）
# 只在第一次调用时替换，之后直接返回已存在的 RichTextLabel
func _at_ensure_rich_category(cat) -> RichTextLabel:
	if cat is RichTextLabel:
		return cat

	var parent = cat.get_parent()
	var idx = cat.get_index()
	var text = cat.text
	var font = cat.get_font("font")
	var size_flags_h = cat.size_flags_horizontal
	var rect_min_size = cat.rect_min_size

	# 找到 ItemDescription 节点，用于修复 _category 引用和悬停信号
	var desc = cat.get_node("../../../../")

	# 保留旧的 Category Button（不 free、不 remove），仅隐藏。
	# 这样 ItemDescription 的 onready var _category 不会指向 freed instance，
	# 后续 vanilla reroll 时调用 _category.show() / .text = 不会崩溃。
	var old_btn = cat
	old_btn.visible = false
	old_btn.name = "Category_old"

	var rich := RichTextLabel.new()
	rich.name = "Category"
	rich.bbcode_enabled = true
	rich.mouse_filter = Control.MOUSE_FILTER_STOP
	rich.fit_content_height = true
	rich.scroll_active = false
	if font:
		rich.add_font_override("normal_font", font)
	rich.size_flags_horizontal = size_flags_h
	rich.rect_min_size = rect_min_size
	rich.text = text

	parent.add_child(rich)
	parent.move_child(rich, idx)

	# 重定向 ItemDescription 的 _category 引用到新的 RichTextLabel
	# 这样后续 vanilla _category.show() / .text = / .hide() 操作的实际是我们的节点
	if desc != null:
		desc.set("_category", rich)
		rich.connect("mouse_entered", desc, "_on_Category_mouse_entered")
		rich.connect("mouse_exited", desc, "_on_Category_mouse_exited")

	return rich


# ============================================================================
# 武器规则链解析
# ============================================================================

# 解析武器规则链：自身规则 → 类别规则 → 最终行为
func _at_resolve_weapon_action(wid: String, weapon_rules: Dictionary, set_rules: Dictionary) -> String:
	var sr = weapon_rules.get(wid, "")
	if sr == "manual" or sr == "skip":
		return sr

	var weapon_sets = item_data.get("sets")
	if not weapon_sets is Array or weapon_sets.size() == 0:
		return "manual"

	var all_skip := true
	var has_rule := false
	for s in weapon_sets:
		var sid: String = s.my_id
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


# ============================================================================
# 颜色映射（所有颜色 hex 都来自上方的中央常量）
# ============================================================================

# 武器类别规则 → 颜色 hex
func _at_set_color_hex(action: String) -> String:
	match action:
		"skip": return _HEX_SKIP
		_: return _HEX_REJECT


# 物品商店规则 → 颜色 hex
func _at_shop_action_hex(a: String) -> String:
	match a:
		"manual": return _HEX_MANUAL
		"get": return _HEX_GET
		"lock_until_cursed": return _HEX_WAIT
		"cursed_only": return _HEX_CURSED
		"reject": return _HEX_REJECT
		_: return _HEX_MANUAL


# 物品箱子规则 → 颜色 hex
# 新 config 层 VALID_CHEST_ACTIONS = ["manual", "take", "skip"]
func _at_chest_action_hex(a: String) -> String:
	match a:
		"manual": return _HEX_MANUAL
		"take": return _HEX_GET
		"skip": return _HEX_SKIP
		_: return _HEX_MANUAL


# ============================================================================
# 规则文字映射
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
		"skip": return tr("AUTOTATO_ACTION_SKIP")
		_: return tr("AUTOTATO_ACTION_MANUAL")
