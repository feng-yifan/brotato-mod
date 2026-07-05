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

# ============================================================================
# 规则选项（与 config.gd 的 VALID_*_ACTIONS 保持一致）
# ============================================================================
# 物品商店行为 — 与 VALID_SHOP_ACTIONS 一致
const SHOP_ACTIONS := [
	["manual",            "AUTOTATO_ACTION_MANUAL"],
	["get",               "AUTOTATO_SHOP_GET"],
	["lock_until_cursed", "AUTOTATO_SHOP_LOCK_UNTIL_CURSED"],
	["cursed_only",       "AUTOTATO_SHOP_CURSED_ONLY"],
	["reject",            "AUTOTATO_SHOP_REJECT"],
]
# 物品箱子行为 — 与 VALID_CHEST_ACTIONS 一致 (manual/take/cursed_only/reject)
const CHEST_ACTIONS := [
	["manual",      "AUTOTATO_ACTION_MANUAL"],
	["take",        "AUTOTATO_CHEST_TAKE"],
	["cursed_only", "AUTOTATO_SHOP_CURSED_ONLY"],
	["reject",      "AUTOTATO_SHOP_REJECT"],
]
# 武器自身规则 — 与 VALID_WEAPON_RULE_ACTIONS 一致
const WEAPON_SELF_OPTIONS := [
	["follow_set_rule", "AUTOTATO_FOLLOW_SET_RULE"],
	["manual",          "AUTOTATO_ACTION_MANUAL"],
	["skip",             "AUTOTATO_ACTION_SKIP"],
]

# 手柄 B 键守卫：标记弹窗是否由手柄 B 键打开
#（B 同时映射 ui_ban + ui_cancel，松开时 ui_cancel released 会尝试关闭弹窗，需跳过）
var _at_popup_opened_by_gamepad := false

# 卡片内规则文字（RichTextLabel 以支持 bbcode 着色）
var _at_rule_label: RichTextLabel = null

# ============================================================================
# 规则配置弹窗
# ============================================================================

var _at_popup: Popup = null
var _at_popup_title: Label = null
var _at_shop_opt: OptionButton = null
var _at_chest_opt: OptionButton = null
var _at_self_opt: OptionButton = null
var _at_set_vbox: VBoxContainer = null
var _at_item_vbox: VBoxContainer = null
var _at_weapon_vbox: VBoxContainer = null
var _at_is_weapon := false

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
	# 弹窗打开时: ESC / 手柄 B 关闭弹窗
	if _at_popup and _at_popup.visible:
		if event.is_action_released("ui_cancel"):
			# OptionButton 下拉 (PopupMenu) 打开时不拦截, 让其自然关闭
			if _at_has_visible_popup_menu():
				return
			# 手柄 B 守卫: B 键打开弹窗的那次松开不关闭
			# (手柄 B 同时映射 ui_ban + ui_cancel, 打开弹窗的 press 会伴随一次
			#  ui_cancel released, 必须跳过, 否则弹窗刚开就被关)
			if event is InputEventJoypadButton and _at_popup_opened_by_gamepad:
				_at_popup_opened_by_gamepad = false
				return
			_at_popup.hide()
			get_tree().set_input_as_handled()
		return

	# 弹窗未打开: ui_ban（键盘 R / 手柄 B）重映射到规则按钮
	if _at_rule_btn == null or not _at_rule_btn.visible:
		return

	if event.is_action_pressed("ui_ban"):
		if _at_card_has_focus():
			_at_on_rule_button_pressed()
			_at_popup_opened_by_gamepad = (event is InputEventJoypadButton)
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


# 点击规则按钮 → 打开规则配置弹窗
func _at_on_rule_button_pressed() -> void:
	if item_data == null:
		return
	_at_is_weapon = (item_data.get("weapon_id") != null and item_data.get("weapon_id") != "")
	_at_ensure_popup()

	var config = _Config.get_instance()
	if config == null:
		return

	# 标题: 物品/武器名称
	_at_popup_title.text = item_data.get_name_text()

	if _at_is_weapon:
		var wid: String = item_data.get("weapon_id")
		var sr: String = config.get_weapon_rule(wid)
		_at_set_option(_at_self_opt, sr, WEAPON_SELF_OPTIONS)
		_at_build_set_rows(config.get_weapon_category_rules())
		_at_item_vbox.hide()
		_at_weapon_vbox.show()
	else:
		var rule = config.get_item_rule(item_data.my_id)
		_at_set_option(_at_shop_opt, rule.get("shop_action", "manual"), SHOP_ACTIONS)
		_at_set_option(_at_chest_opt, rule.get("chest_action", "manual"), CHEST_ACTIONS)
		_at_weapon_vbox.hide()
		_at_item_vbox.show()

	_at_popup.popup_centered_ratio(1.0)
	# 手柄: 弹窗打开后给初始焦点
	call_deferred("_at_grab_popup_focus")


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
# config 层 VALID_CHEST_ACTIONS = ["manual", "take", "cursed_only", "reject"]
func _at_chest_action_hex(a: String) -> String:
	match a:
		"manual": return _HEX_MANUAL
		"take": return _HEX_GET
		"cursed_only": return _HEX_CURSED
		"reject": return _HEX_REJECT
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
		"cursed_only": return tr("AUTOTATO_SHOP_CURSED_ONLY")
		"reject": return tr("AUTOTATO_SHOP_REJECT")
		_: return tr("AUTOTATO_ACTION_MANUAL")


# ============================================================================
# 规则配置弹窗 — 构建/事件
# 参考 autotato/ui/tabs/items_tab.gd 的 _ensure_popup 结构
# ============================================================================

# 懒构建弹窗节点树 (Popup + 半透明遮罩 + 居中面板)
# popup_exclusive = true 让 Popup 独占输入, 可见时拦截焦点
func _at_ensure_popup() -> void:
	if _at_popup:
		return

	_at_popup = Popup.new()
	_at_popup.name = "ATRulePopup"
	_at_popup.popup_exclusive = true
	add_child(_at_popup)

	# 半透明遮罩 — 点击空白处关闭
	var dimmer := ColorRect.new()
	dimmer.color = Color(0, 0, 0, 0.5)
	dimmer.anchor_right = 1.0
	dimmer.anchor_bottom = 1.0
	dimmer.mouse_filter = MOUSE_FILTER_STOP
	dimmer.connect("gui_input", self, "_at_dimmer_clicked")
	_at_popup.add_child(dimmer)

	# 居中容器
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

	# 标题
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

	_at_item_vbox.add_child(actions_grid)
	content.add_child(_at_item_vbox)

	# ---- 武器配置区域 ----
	_at_weapon_vbox = VBoxContainer.new()
	_at_weapon_vbox.name = "WeaponContent"
	_at_weapon_vbox.add_constant_override("separation", 8)

	var self_grid := GridContainer.new()
	self_grid.columns = 2
	self_grid.add_constant_override("hseparation", 12)
	var self_label := _at_label(tr("AUTOTATO_WEAPON_SELF_RULE"))
	self_label.rect_min_size = Vector2(80, 0)
	self_grid.add_child(self_label)
	_at_self_opt = OptionButton.new()
	_at_self_opt.size_flags_horizontal = SIZE_EXPAND_FILL
	_at_self_opt.focus_mode = Control.FOCUS_ALL
	for pair in WEAPON_SELF_OPTIONS:
		_at_self_opt.add_item(tr(pair[1]))
	self_grid.add_child(_at_self_opt)
	_at_weapon_vbox.add_child(self_grid)

	_at_weapon_vbox.add_child(HSeparator.new())
	_at_weapon_vbox.add_child(_at_label(tr("AUTOTATO_CATEGORY_RULE")))

	# 类别规则动态行容器 (打开弹窗时按武器所属 set 重建)
	_at_set_vbox = VBoxContainer.new()
	_at_set_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	_at_set_vbox.add_constant_override("separation", 2)
	_at_weapon_vbox.add_child(_at_set_vbox)

	content.add_child(_at_weapon_vbox)
	_at_weapon_vbox.hide()

	# ---- 按钮行 ----
	content.add_child(HSeparator.new())
	var btn_hbox := HBoxContainer.new()
	btn_hbox.alignment = BoxContainer.ALIGN_END

	# 保存在前, 取消在后: 从上方下移时空间导航默认命中保存
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

	# 手柄导航: Save ↔ Cancel 水平邻居
	save_btn.focus_neighbour_right = save_btn.get_path_to(cancel_btn)
	cancel_btn.focus_neighbour_left = cancel_btn.get_path_to(save_btn)
	# 手柄: 从最后一个下拉向下 → 保存按钮
	_at_chest_opt.focus_neighbour_bottom = _at_chest_opt.get_path_to(save_btn)
	_at_self_opt.focus_neighbour_bottom = _at_self_opt.get_path_to(save_btn)

	content.add_child(btn_hbox)


func _at_label(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.valign = Label.VALIGN_CENTER
	l.size_flags_horizontal = SIZE_EXPAND_FILL
	l.clip_text = true
	return l


# 弹窗打开后给初始焦点 (手柄导航起点)
func _at_grab_popup_focus() -> void:
	if _at_is_weapon:
		if _at_self_opt and _at_self_opt.visible:
			_at_self_opt.grab_focus()
	else:
		if _at_shop_opt and _at_shop_opt.visible:
			_at_shop_opt.grab_focus()


# 构建武器所属类别的规则下拉行 (每次打开弹窗时重建)
func _at_build_set_rows(set_rules: Dictionary) -> void:
	for child in _at_set_vbox.get_children():
		child.queue_free()

	var weapon_sets = item_data.get("sets")
	if not weapon_sets is Array or weapon_sets.size() == 0:
		_at_set_vbox.add_child(_at_label(tr("AUTOTATO_NO_CATEGORY")))
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
		opt.add_item(tr("AUTOTATO_ACTION_MANUAL"))
		opt.add_item(tr("AUTOTATO_ACTION_SKIP"))
		opt.focus_mode = Control.FOCUS_ALL
		var cr: String = set_rules.get(sid, "manual")
		opt.select(1 if cr == "skip" else 0)
		row.add_child(opt)

		_at_set_vbox.add_child(row)


# 点击遮罩关闭弹窗
func _at_dimmer_clicked(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_at_popup.hide()


# 保存: 通过 _Config 直接写盘, 然后刷新卡片规则文字
func _at_popup_save() -> void:
	var config = _Config.get_instance()
	if config == null:
		return

	if _at_is_weapon:
		var wid: String = item_data.get("weapon_id")
		var si = _at_self_opt.selected
		var sv = WEAPON_SELF_OPTIONS[si][0] if si >= 0 else "follow_set_rule"
		if sv == "follow_set_rule":
			config.remove_weapon_rule(wid)
		else:
			config.set_weapon_rule(wid, sv)
		for row in _at_set_vbox.get_children():
			for child in row.get_children():
				if child is OptionButton:
					var opt: OptionButton = child
					var sid: String = opt.name.replace("Set_", "")
					var val = "skip" if opt.selected == 1 else "manual"
					config.set_weapon_category_rule(sid, val)
					break
	else:
		var si = _at_shop_opt.selected
		var ci = _at_chest_opt.selected
		var sa = SHOP_ACTIONS[si][0] if si >= 0 else "manual"
		var ca = CHEST_ACTIONS[ci][0] if ci >= 0 else "manual"
		if sa == "manual" and ca == "manual":
			config.remove_item_rule(item_data.my_id)
		else:
			config.set_item_rule(item_data.my_id, {"shop_action": sa, "chest_action": ca})

	_at_popup.hide()
	_at_update_rule_label()


func _at_popup_cancel() -> void:
	_at_popup.hide()


# OptionButton 按值选中
func _at_set_option(opt: OptionButton, value: String, actions: Array) -> void:
	for i in actions.size():
		if actions[i][0] == value:
			opt.select(i)
			return
	opt.select(0)


# 检测弹窗内是否有可见的 PopupMenu (OptionButton 下拉) — 守卫 ESC 关闭
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
