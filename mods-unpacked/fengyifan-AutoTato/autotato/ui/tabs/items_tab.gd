extends Control

# ============================================================================
# AutoTato — Items Tab (P5.2 物品规则编辑器)
# ----------------------------------------------------------------------------
# 将全部物品按 Tier（传说→稀有→精良→普通）分组展示为 7 列可折叠网格。
# 每张卡片左侧图标、右侧两行显示当前商店/箱子规则文字。
# 点击卡片弹出弹窗配置该物品的 shop_action / chest_action。
#
# 筛选栏:
#   顶部 3 个 OptionButton 实现 AND 筛选 — 类型(不限/独特/限制/其他)
#   商店规则(不限+5) × 箱子规则(不限+4). 任意非"不限"即生效.
#
# 数据流:
#   面板加载 → _refresh()
#     → Bridge.get_item_rules()      # 读取已配置规则
#     → ItemService.items            # 全部物品 Array[ItemParentData]
#     → 按 tier 分组, 每组 7 列 GridContainer
#     → 每格 Button 包裹 icon + 规则文字
#
# 弹窗:
#   保存: 两 action 都是 manual → 从 _dirty_rules 删除此 item
#         否则 → _dirty_rules[item_id] = {shop_action, chest_action}
#         然后刷新卡片显示
#   取消: 关闭弹窗, 不修改任何数据
#   点击弹窗外灰色遮罩 → 取消
#
# ESC 竞态: 弹窗打开时禁用 ConfigPanel._input, 关闭时恢复.
# 与 PauseMenu/ConfigPanel 的 ESC 竞态修复模式一致.
#
# P5.2 仅在内存操作 _dirty_rules. 关闭面板数据丢弃.
# P5.4 在弹窗保存处加 Bridge.set_item_rule / remove_item_rule 写回.
# ============================================================================

const LOG_NAME := "fengyifan-AutoTato:ItemsTab"

# Tier 定义: 从高到低排列, 与 ItemParentData.Tier enum 值一一对应.
# 颜色从 ItemService.get_color_from_tier() 动态获取 (来源于 ProgressData.settings),
# 与 vanilla 商店/库存/物品栏完全一致.
const TIERS := [
	{"value": 3, "key": "传说"},    # LEGENDARY
	{"value": 2, "key": "稀有"},    # RARE
	{"value": 1, "key": "精良"},    # UNCOMMON
	{"value": 0, "key": "普通"},    # COMMON
]

# shop_action 选项: [value_key, display_text]
const SHOP_ACTIONS := [
	["manual",            "手动"],
	["get",               "购买"],
	["reject",            "拒绝"],
	["lock_until_cursed", "锁定等诅咒"],
	["cursed_only",       "仅诅咒"],
]

# chest_action 选项
const CHEST_ACTIONS := [
	["manual",       "手动"],
	["take",         "拿取"],
	["reject",       "拒绝"],
	["cursed_only",  "仅诅咒"],
]

const GRID_COLUMNS := 7
const CARD_ICON_SIZE := 80
const CARD_MIN_HEIGHT := 80  # 图标高度与卡片高度一致
const GRID_HSEP := 8
const GRID_VSEP := 8
const CARD_TEXT_FONT := preload("res://resources/fonts/actual/base/font_22.tres")
const CARD_BORDER_WIDTH := 2

# 卡片规则文字语义色: 用颜色表达 action, 背景保持透明.
const ACTION_COLOR_MANUAL := Color(1, 1, 1, 0.35)
const ACTION_COLOR_POSITIVE := Color(0.35, 1.0, 0.45, 1.0)
const ACTION_COLOR_NEGATIVE := Color(1.0, 0.35, 0.35, 1.0)
const ACTION_COLOR_WAIT := Color(1.0, 0.78, 0.25, 1.0)
const ACTION_COLOR_CURSED := Color(0.8, 0.45, 1.0, 1.0)

# ---- 类型筛选 (基于 max_nb) ----
enum TypeFilter { ALL = 0, UNIQUE = 1, LIMITED = 2, OTHER = 3 }
const TYPE_FILTER_NAMES := ["类型: 不限", "类型: 独特", "类型: 限制", "类型: 其他"]

# ---- State ----
var _dirty_rules: Dictionary = {}
# _card_refs: item_id → {shop_label, chest_label, button}
var _card_refs: Dictionary = {}
# _tier_blocks: tier_value → {header, grid, header_label, arrow, items}
var _tier_blocks: Dictionary = {}
# 每个 item 属于哪个 tier_value
var _item_tier: Dictionary = {}

# ---- Filter state ----
var _filter_type: int = TypeFilter.ALL
var _filter_shop: int = 0  # 0=不限, 1-5 对应 SHOP_ACTIONS index+1
var _filter_chest: int = 0

# ---- Popup ----
var _popup: Popup = null
var _editing_item_id: String = ""
var _shop_option: OptionButton = null
var _chest_option: OptionButton = null
var _popup_title: Label = null

# ---- 动态创建的节点引用 ----
var _groups: VBoxContainer = null
var _filter_shop_opt: OptionButton = null
var _filter_chest_opt: OptionButton = null


# ========================================================================
# Lifecycle
# ========================================================================

func _ready() -> void:
	_build_static_ui()
	_refresh()


# 切换到其他 Tab 时自动关闭弹窗, 同时恢复 ConfigPanel 输入
func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not visible:
		if _popup and _popup.visible:
			_popup.hide()
			_enable_config_input()


# ========================================================================
# Data access
# ========================================================================

func _load_bridge():
	var Bridge = load("res://mods-unpacked/fengyifan-AutoTato/autotato/runtime/bridge.gd")
	return Bridge.get_global()


func _load_all_items() -> Array:
	if typeof(ItemService) != TYPE_OBJECT:
		return []
	var items = ItemService.get("items")
	if typeof(items) != TYPE_ARRAY:
		return []
	# 排除不可主动获取的物品 (如 item_broken_hourglass, can_be_looted = false).
	# 这类物品只作为其他物品的 replaced_by 产物出现, 不出现在商店/掉落中.
	# 与 vanilla ItemService.init_unlocked_pool() 条件一致.
	var result := []
	for item in items:
		if item.get("can_be_looted") != false:
			result.append(item)
	return result


# ========================================================================
# Static UI (built once)
# ========================================================================

func _build_static_ui() -> void:
	# ---- Root VBox ----
	# 子节点不能直接挂 Control 下 (Godot 3 不做自动布局, 会塌缩为 0 高度).
	# 用 VBoxContainer 包住 FilterBar + ScrollContainer.
	var root := VBoxContainer.new()
	root.name = "RootVBox"
	root.anchor_right = 1.0
	root.anchor_bottom = 1.0
	add_child(root)

	# ---- Filter bar ----
	var filter_bar := HBoxContainer.new()
	filter_bar.name = "FilterBar"
	filter_bar.add_constant_override("separation", 12)
	filter_bar.rect_min_size = Vector2(0, 40)
	root.add_child(filter_bar)

	var type_opt := OptionButton.new()
	type_opt.rect_min_size = Vector2(120, 0)
	for name in TYPE_FILTER_NAMES:
		type_opt.add_item(name)
	type_opt.connect("item_selected", self, "_on_filter_type_changed")
	filter_bar.add_child(type_opt)

	_filter_shop_opt = OptionButton.new()
	_filter_shop_opt.rect_min_size = Vector2(140, 0)
	_filter_shop_opt.add_item("商店: 不限")
	for pair in SHOP_ACTIONS:
		_filter_shop_opt.add_item("商店: %s" % pair[1])
	_filter_shop_opt.connect("item_selected", self, "_on_filter_shop_changed")
	filter_bar.add_child(_filter_shop_opt)

	_filter_chest_opt = OptionButton.new()
	_filter_chest_opt.rect_min_size = Vector2(140, 0)
	_filter_chest_opt.add_item("箱子: 不限")
	for pair in CHEST_ACTIONS:
		_filter_chest_opt.add_item("箱子: %s" % pair[1])
	_filter_chest_opt.connect("item_selected", self, "_on_filter_chest_changed")
	filter_bar.add_child(_filter_chest_opt)

	# ---- Scroll area ----
	var scroll := ScrollContainer.new()
	scroll.name = "ScrollContainer"
	scroll.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	root.add_child(scroll)

	var content_margin := MarginContainer.new()
	content_margin.size_flags_horizontal = SIZE_EXPAND_FILL
	content_margin.add_constant_override("margin_left", 12)
	content_margin.add_constant_override("margin_right", 12)
	scroll.add_child(content_margin)

	var groups := VBoxContainer.new()
	groups.name = "GroupsVBox"
	groups.size_flags_horizontal = SIZE_EXPAND_FILL
	content_margin.add_child(groups)
	_groups = groups


# ========================================================================
# Refresh — rebuilds all tier blocks from data
# ========================================================================

func _refresh() -> void:
	_clear()

	var bridge = _load_bridge()
	if bridge:
		_dirty_rules = bridge.get_item_rules()
	else:
		_dirty_rules = {}

	var all_items: Array = _load_all_items()
	if all_items.empty():
		_show_empty("物品数据不可用")
		return

	# Group by tier
	var tier_groups := {}
	for tier_def in TIERS:
		tier_groups[tier_def["value"]] = []

	for item in all_items:
		var t: int = int(item.get("tier"))
		if tier_groups.has(t):
			tier_groups[t].append(item)

	# Build blocks in order
	for tier_def in TIERS:
		var items_in_tier: Array = tier_groups[tier_def["value"]]
		if items_in_tier.empty():
			continue
		_build_tier_block(tier_def, items_in_tier)

	# Apply current filters
	_apply_filters()


func _clear() -> void:
	for child in _groups.get_children():
		child.queue_free()
	_tier_blocks.clear()
	_card_refs.clear()
	_item_tier.clear()


func _show_empty(msg: String) -> void:
	var label := Label.new()
	label.text = msg
	label.align = Label.ALIGN_CENTER
	label.valign = Label.VALIGN_CENTER
	label.anchor_right = 1.0
	label.anchor_bottom = 1.0
	_groups.add_child(label)


# ========================================================================
# Tier block
# ========================================================================

func _build_tier_block(tier_def: Dictionary, items: Array) -> void:
	var tier_value: int = tier_def["value"]
	var tier_name: String = tier_def["key"]
	var tier_color: Color = _vanilla_tier_color(tier_value)

	# Gap before header
	var gap := Control.new()
	gap.rect_min_size = Vector2(0, 8)
	_groups.add_child(gap)

	# ---- Header button ----
	var header_btn := Button.new()
	header_btn.flat = true
	header_btn.align = Button.ALIGN_LEFT
	header_btn.size_flags_horizontal = SIZE_EXPAND_FILL
	header_btn.rect_min_size = Vector2(0, 32)

	var header_inner := HBoxContainer.new()
	header_inner.anchor_right = 1.0
	header_inner.anchor_bottom = 1.0
	header_inner.mouse_filter = MOUSE_FILTER_IGNORE
	header_inner.alignment = BoxContainer.ALIGN_CENTER
	header_inner.size_flags_horizontal = SIZE_EXPAND_FILL
	header_inner.size_flags_vertical = SIZE_EXPAND_FILL

	var arrow := Label.new()
	arrow.text = "▼"
	arrow.modulate = tier_color
	arrow.valign = Label.VALIGN_CENTER
	arrow.rect_min_size = Vector2(24, 32)
	header_inner.add_child(arrow)

	var name_label := Label.new()
	name_label.text = tier_name
	name_label.modulate = tier_color
	name_label.valign = Label.VALIGN_CENTER
	name_label.rect_min_size = Vector2(0, 32)
	header_inner.add_child(name_label)

	header_btn.add_child(header_inner)
	_groups.add_child(header_btn)

	# ---- Grid container ----
	var grid := GridContainer.new()
	grid.columns = GRID_COLUMNS
	grid.add_constant_override("hseparation", GRID_HSEP)
	grid.add_constant_override("vseparation", GRID_VSEP)
	grid.size_flags_horizontal = SIZE_EXPAND_FILL
	_groups.add_child(grid)

	# Track
	_tier_blocks[tier_value] = {
		"block_root": gap,
		"header": header_btn,
		"grid": grid,
		"header_label": name_label,
		"arrow": arrow,
		"items": items,
		"tier_name": tier_name,
	}

	header_btn.connect("pressed", self, "_on_tier_header_toggled", [tier_value])

	# Build cards & track item→tier mapping
	for item in items:
		var item_id: String = item.get("my_id")
		_item_tier[item_id] = tier_value
		_build_card(grid, item)


# ========================================================================
# Card
# ========================================================================

func _build_card(grid: GridContainer, item) -> void:
	var item_id: String = item.get("my_id")

	var btn := Button.new()
	btn.size_flags_horizontal = SIZE_EXPAND_FILL
	btn.rect_min_size = Vector2(100, CARD_MIN_HEIGHT)
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_filter = MOUSE_FILTER_STOP

	# Button 不是 Container, 不会自动布局子节点.
	# 因此内部 HBox 必须显式锚定到 Button 全区域.
	var hbox := HBoxContainer.new()
	hbox.anchor_right = 1.0
	hbox.anchor_bottom = 1.0
	hbox.mouse_filter = MOUSE_FILTER_IGNORE
	hbox.add_constant_override("separation", 6)

	# Icon: 与卡片高度一致, 固定宽高 80×80.
	var icon_rect := TextureRect.new()
	icon_rect.rect_min_size = Vector2(CARD_ICON_SIZE, CARD_MIN_HEIGHT)
	icon_rect.expand = true
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.mouse_filter = MOUSE_FILTER_IGNORE

	var tex
	if item.has_method("get_icon"):
		tex = item.get_icon()
	elif item.get("icon") != null:
		tex = item.icon
	if tex:
		icon_rect.texture = tex

	hbox.add_child(icon_rect)

	# 右侧两行文字: 只显示规则结果.
	var rule_vbox := VBoxContainer.new()
	rule_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	rule_vbox.size_flags_vertical = SIZE_EXPAND_FILL
	rule_vbox.alignment = BoxContainer.ALIGN_CENTER
	rule_vbox.mouse_filter = MOUSE_FILTER_IGNORE

	var shop_label := Label.new()
	shop_label.align = Label.ALIGN_LEFT
	shop_label.valign = Label.VALIGN_CENTER
	shop_label.clip_text = true
	shop_label.size_flags_horizontal = SIZE_EXPAND_FILL
	shop_label.add_font_override("font", CARD_TEXT_FONT)
	shop_label.mouse_filter = MOUSE_FILTER_IGNORE
	rule_vbox.add_child(shop_label)

	var chest_label := Label.new()
	chest_label.align = Label.ALIGN_LEFT
	chest_label.valign = Label.VALIGN_CENTER
	chest_label.clip_text = true
	chest_label.size_flags_horizontal = SIZE_EXPAND_FILL
	chest_label.add_font_override("font", CARD_TEXT_FONT)
	chest_label.mouse_filter = MOUSE_FILTER_IGNORE
	rule_vbox.add_child(chest_label)

	hbox.add_child(rule_vbox)
	btn.add_child(hbox)
	grid.add_child(btn)

	_card_refs[item_id] = {
		"shop_label": shop_label,
		"chest_label": chest_label,
		"button": btn,
	}

	btn.connect("pressed", self, "_on_card_pressed", [item_id])

	_apply_card_style(item_id, shop_label, chest_label, btn)


func _apply_card_style(item_id: String, shop_label: Label, chest_label: Label, btn: Button) -> void:
	var rule = _dirty_rules.get(item_id, {})
	var sa = rule.get("shop_action", "manual")
	var ca = rule.get("chest_action", "manual")

	shop_label.text = _action_display(sa, SHOP_ACTIONS)
	chest_label.text = _action_display(ca, CHEST_ACTIONS)
	shop_label.modulate = _action_color(sa)
	chest_label.modulate = _action_color(ca)

	# 背景保持透明; 信息表达交给规则文字颜色.
	# 边框使用 vanilla tier color, 2px 宽度. 未配置 alpha=0.35, 已配置 alpha=0.65.
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_right = 4
	sb.corner_radius_bottom_left = 4
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4

	var tier_color: Color = _tier_color_for(item_id)
	sb.border_width_left = CARD_BORDER_WIDTH
	sb.border_width_right = CARD_BORDER_WIDTH
	sb.border_width_top = CARD_BORDER_WIDTH
	sb.border_width_bottom = CARD_BORDER_WIDTH

	btn.flat = false
	if sa == "manual" and ca == "manual":
		sb.border_color = Color(tier_color.r, tier_color.g, tier_color.b, 0.35)
	else:
		sb.border_color = tier_color
	btn.add_stylebox_override("normal", sb)


# ========================================================================
# Tier header toggle (expand / collapse)
# ========================================================================

func _on_tier_header_toggled(tier_value: int) -> void:
	var block = _tier_blocks.get(tier_value)
	if block == null:
		return
	var grid: GridContainer = block["grid"]
	grid.visible = !grid.visible
	block["arrow"].text = "▶" if !grid.visible else "▼"


# ========================================================================
# Filters
# ========================================================================

func _on_filter_type_changed(idx: int) -> void:
	_filter_type = idx
	_apply_filters()


func _on_filter_shop_changed(idx: int) -> void:
	_filter_shop = idx
	_apply_filters()


func _on_filter_chest_changed(idx: int) -> void:
	_filter_chest = idx
	_apply_filters()


# 筛选只控制卡片可见性. 不动 Tier header/grid 的折叠状态.
func _apply_filters() -> void:
	for tier_value in _tier_blocks:
		var block = _tier_blocks[tier_value]
		var items: Array = block["items"]

		for item in items:
			var item_id: String = item.get("my_id")
			var visible := _matches_filters(item_id, item)
			var ref = _card_refs.get(item_id)
			if ref:
				ref["button"].visible = visible


func _matches_filters(item_id: String, item) -> bool:
	# Type filter
	if _filter_type != TypeFilter.ALL:
		var max_nb: int = int(item.get("max_nb"))
		match _filter_type:
			TypeFilter.UNIQUE:
				# 独特: 物品自身 max_nb == 1, 只能获取 1 个
				if max_nb != 1:
					return false
			TypeFilter.LIMITED:
				# 限制: 物品自身 max_nb > 1, 可获取有限多个
				if max_nb <= 1:
					return false
			TypeFilter.OTHER:
				# 其他: max_nb <= 0, vanilla 默认 -1 表示无限制
				if max_nb > 0:
					return false

	# Shop action filter
	if _filter_shop > 0:
		var expected_shop: String = SHOP_ACTIONS[_filter_shop - 1][0]
		var rule = _dirty_rules.get(item_id, {})
		if rule.get("shop_action", "manual") != expected_shop:
			return false

	# Chest action filter
	if _filter_chest > 0:
		var expected_chest: String = CHEST_ACTIONS[_filter_chest - 1][0]
		var rule = _dirty_rules.get(item_id, {})
		if rule.get("chest_action", "manual") != expected_chest:
			return false

	return true


# ========================================================================
# Card click → Popup
# ========================================================================

func _on_card_pressed(item_id: String) -> void:
	_editing_item_id = item_id
	_ensure_popup()

	var item_data = null
	for tier_value in _tier_blocks:
		for item in _tier_blocks[tier_value]["items"]:
			if item.get("my_id") == item_id:
				item_data = item
				break
		if item_data:
			break

	if item_data == null:
		return

	_popup_title.text = item_data.get_name_text()

	var rule = _dirty_rules.get(item_id, {})
	_set_option_by_value(_shop_option, rule.get("shop_action", "manual"), SHOP_ACTIONS)
	_set_option_by_value(_chest_option, rule.get("chest_action", "manual"), CHEST_ACTIONS)

	_popup.popup_centered_ratio(1.0)
	_disable_config_input()


# ========================================================================
# Popup construction (lazy, once)
# ========================================================================

func _ensure_popup() -> void:
	if _popup:
		return

	_popup = Popup.new()
	_popup.name = "EditRulePopup"
	_popup.popup_exclusive = true
	add_child(_popup)

	# ---- 全屏半透明遮罩 ----
	var dimmer := ColorRect.new()
	dimmer.color = Color(0, 0, 0, 0.5)
	dimmer.anchor_right = 1.0
	dimmer.anchor_bottom = 1.0
	dimmer.mouse_filter = MOUSE_FILTER_STOP
	dimmer.connect("gui_input", self, "_on_popup_dimmer_clicked")
	_popup.add_child(dimmer)

	# ---- 弹窗主体 (居中) ----
	var center := CenterContainer.new()
	center.anchor_right = 1.0
	center.anchor_bottom = 1.0
	center.mouse_filter = MOUSE_FILTER_PASS
	_popup.add_child(center)

	var panel := PanelContainer.new()
	panel.rect_min_size = Vector2(420, 280)
	panel.mouse_filter = MOUSE_FILTER_STOP
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_constant_override("separation", 8)
	panel.add_child(vbox)

	var content_margin := MarginContainer.new()
	content_margin.add_constant_override("margin_left", 20)
	content_margin.add_constant_override("margin_right", 20)
	content_margin.add_constant_override("margin_top", 16)
	content_margin.add_constant_override("margin_bottom", 16)

	var content_vbox := VBoxContainer.new()
	content_vbox.add_constant_override("separation", 12)
	content_margin.add_child(content_vbox)
	vbox.add_child(content_margin)

	# Title
	_popup_title = Label.new()
	_popup_title.align = Label.ALIGN_CENTER
	_popup_title.valign = Label.VALIGN_CENTER
	_popup_title.rect_min_size = Vector2(0, 32)
	content_vbox.add_child(_popup_title)

	content_vbox.add_child(HSeparator.new())

	# Action rows
	var actions_grid := GridContainer.new()
	actions_grid.columns = 2
	actions_grid.add_constant_override("hseparation", 12)
	actions_grid.add_constant_override("vseparation", 8)

	var shop_label := Label.new()
	shop_label.text = "商店行为"
	shop_label.valign = Label.VALIGN_CENTER
	shop_label.rect_min_size = Vector2(80, 0)
	actions_grid.add_child(shop_label)

	_shop_option = OptionButton.new()
	_shop_option.size_flags_horizontal = SIZE_EXPAND_FILL
	for pair in SHOP_ACTIONS:
		_shop_option.add_item(pair[1])
	actions_grid.add_child(_shop_option)

	var chest_label := Label.new()
	chest_label.text = "箱子行为"
	chest_label.valign = Label.VALIGN_CENTER
	chest_label.rect_min_size = Vector2(80, 0)
	actions_grid.add_child(chest_label)

	_chest_option = OptionButton.new()
	_chest_option.size_flags_horizontal = SIZE_EXPAND_FILL
	for pair in CHEST_ACTIONS:
		_chest_option.add_item(pair[1])
	actions_grid.add_child(_chest_option)

	content_vbox.add_child(actions_grid)

	# Spacer
	var spacer := Control.new()
	spacer.size_flags_vertical = SIZE_EXPAND_FILL
	content_vbox.add_child(spacer)

	# Buttons row
	content_vbox.add_child(HSeparator.new())

	var btn_hbox := HBoxContainer.new()
	btn_hbox.alignment = BoxContainer.ALIGN_END

	var cancel_btn := Button.new()
	cancel_btn.text = "取消"
	cancel_btn.connect("pressed", self, "_on_popup_cancel")
	btn_hbox.add_child(cancel_btn)

	var save_btn := Button.new()
	save_btn.text = "保存"
	save_btn.connect("pressed", self, "_on_popup_save")
	btn_hbox.add_child(save_btn)

	content_vbox.add_child(btn_hbox)


func _on_popup_dimmer_clicked(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_popup.hide()
		_enable_config_input()


# ========================================================================
# Popup save / cancel
# ========================================================================

func _on_popup_save() -> void:
	var shop_idx = _shop_option.selected
	var chest_idx = _chest_option.selected
	var sa = SHOP_ACTIONS[shop_idx][0] if shop_idx >= 0 and shop_idx < SHOP_ACTIONS.size() else "manual"
	var ca = CHEST_ACTIONS[chest_idx][0] if chest_idx >= 0 and chest_idx < CHEST_ACTIONS.size() else "manual"

	if sa == "manual" and ca == "manual":
		_dirty_rules.erase(_editing_item_id)
	else:
		_dirty_rules[_editing_item_id] = {"shop_action": sa, "chest_action": ca}

	# P5.4: var bridge = _load_bridge()
	# P5.4: if bridge:
	# P5.4: 	if sa == "manual" and ca == "manual":
	# P5.4: 		bridge.remove_item_rule(_editing_item_id)
	# P5.4: 	else:
	# P5.4: 		bridge.set_item_rule(_editing_item_id, _dirty_rules[_editing_item_id])

	_popup.hide()
	_enable_config_input()
	_refresh_card_and_apply_filters(_editing_item_id)


func _on_popup_cancel() -> void:
	_popup.hide()
	_enable_config_input()


# ========================================================================
# Refresh after save
# ========================================================================

func _refresh_card_and_apply_filters(item_id: String) -> void:
	var ref = _card_refs.get(item_id)
	if ref:
		_apply_card_style(item_id, ref["shop_label"], ref["chest_label"], ref["button"])
	_apply_filters()


# ========================================================================
# Helpers
# ========================================================================

func _action_display(key: String, actions: Array) -> String:
	for pair in actions:
		if pair[0] == key:
			return pair[1]
	return key


func _set_option_by_value(opt: OptionButton, value: String, actions: Array) -> void:
	for i in actions.size():
		if actions[i][0] == value:
			opt.select(i)
			return
	opt.select(0)


func _action_color(action_key: String) -> Color:
	match action_key:
		"manual":
			return ACTION_COLOR_MANUAL
		"get", "take":
			return ACTION_COLOR_POSITIVE
		"reject":
			return ACTION_COLOR_NEGATIVE
		"lock_until_cursed":
			return ACTION_COLOR_WAIT
		"cursed_only":
			return ACTION_COLOR_CURSED
		_:
			return ACTION_COLOR_MANUAL


func _tier_color_for(item_id: String) -> Color:
	var tv: int = _item_tier.get(item_id, 0)
	return _vanilla_tier_color(tv)


func _vanilla_tier_color(tier_value: int) -> Color:
	if typeof(ItemService) == TYPE_OBJECT:
		return ItemService.get_color_from_tier(tier_value)
	return Color(0.9, 0.9, 0.9, 1.0)


# ========================================================================
# ConfigPanel input gate (ESC 竞态修复)
# ========================================================================
# 弹窗打开时, Godot 3 的 _input 从树根向下派发,
# ConfigPanel._input 在 items_tab 之前触发, 会先吃掉 ESC 关闭整个面板.
# 修复: 弹窗打开时禁用 ConfigPanel 的 _input, 关闭时恢复.
# 与 PauseMenu/ConfigPanel 的 ESC 竞态修复模式完全一致.

func _disable_config_input() -> void:
	var node: Node = self
	while node:
		if node.get_script() != null:
			var path: String = node.get_script().resource_path
			if path.ends_with("config_panel.gd"):
				node.set_process_input(false)
				return
		node = node.get_parent()


func _enable_config_input() -> void:
	var node: Node = self
	while node:
		if node.get_script() != null:
			var path: String = node.get_script().resource_path
			if path.ends_with("config_panel.gd"):
				node.set_process_input(true)
				return
		node = node.get_parent()


func _log(msg: String) -> void:
	if typeof(ModLoaderLog) != TYPE_NIL:
		ModLoaderLog.info(msg, LOG_NAME)
