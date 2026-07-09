extends "res://ui/menus/shop/reroll_button.gd"

# ============================================================================
# AutoTato - RerollButton Script Extension
# ----------------------------------------------------------------------------
# 接管 vanilla reroll 按钮的 F/Y (ui_info) 处理。
#
# 背景: vanilla 单玩家模式下, reroll 按钮显示 F 图标且 F 键直接触发 reroll
# (reroll_button.gd:29-39, 含 holding_button 长按蓄力)。AutoTato 要让 F 在
# "auto" 态触发决策, 故必须接管此处, 否则 F 总是被 vanilla reroll 抢走。
#
# 路由 (据 base_shop._at_info_owner):
#   "auto"   -> 吞掉 F, 不触发 reroll; 通知 base_shop 跑手动决策
#   "reroll" -> 放行 ._input(event), 完整保留 vanilla 蓄力/触发逻辑
# ============================================================================

const _Logger = preload("res://mods-unpacked/fengyifan-AutoTato/utils/logger.gd")
const _LOG_NAME := "RerollBtnExt"

# 缓存的 base_shop 祖先引用 (避免每次 _input 向上遍历)
var _at_base_shop: Node = null
# F 键 + auto 态时置 true: 标记本次 pressed 信号 (vanilla _input 独立 emit) 应被
# base_shop 拦截, 不触发 reroll。鼠标点击不设此标志 -> 放行 reroll。
# 解决: auto 态按 F 跑决策不 reroll, 但鼠标点 reroll 按钮仍能 reroll。
var _at_f_key_block_reroll := false
# base_shop 真正放行 reroll 时置 true: 标记本次 pressed 确实 reroll 了。
# _at_on_reroll_pressed 据此判断是否绑回 auto (只在实际 reroll 后绑回, 被拦截的不绑)。
var _at_did_reroll := false

func _ready() -> void:
	._ready()
	# ready 后向上查找 base_shop 祖先 (拥有 at_start_shop_decision_manually 方法的节点)
	call_deferred("_at_cache_base_shop")
	# 监听 pressed: 手动 reroll (鼠标点击 / F 键) 真正发生时绑回 "auto",
	# 让玩家可继续按 F 跑决策。自动循环调 ._on_RerollButton_pressed 不 emit pressed,
	# 故此回调只被手动触发, 无需抑制标志。
	connect("pressed", self, "_at_on_reroll_pressed")

# 供 base_shop._at_switch_info_owner 调用: 切换 F 显隐后刷新文字前导空格。
# auto 态 (F 隐藏) 去前导空格, reroll 态 (F 显示) 加前导空格 (vanilla 默认)。
func _at_refresh_text() -> void:
	if RunData.is_coop_run:
		return
	if _at_base_shop == null or not is_instance_valid(_at_base_shop):
		return
	var txt := (tr("REROLL") + " - " + str(_value)).to_upper()
	if _at_base_shop.at_get_info_owner() == "auto":
		set_text(txt)
	else:
		set_text("      " + txt)

# 覆写 vanilla init: vanilla 单玩家设文字 "      " + txt (6 空格给左侧 F 图标留位)。
# auto 态 (F 图标隐藏) 时去掉前导空格, 避免左侧留白。
# reroll 态 (F 显示) 保留前导空格 (vanilla 默认)。
func init(value: int, player_index: int) -> void:
	.init(value, player_index)
	if RunData.is_coop_run:
		return
	# auto 态: F 隐藏, 文字去前导空格
	if _at_base_shop != null and is_instance_valid(_at_base_shop) \
			and _at_base_shop.at_get_info_owner() == "auto":
		var txt := (tr("REROLL") + " - " + str(value)).to_upper()
		set_text(txt)

# 覆写 vanilla get_content_size_x: 跳过 visible=false 的子节点。
# vanilla 原版累加所有子节点 rect_size.x (含隐藏的), 导致 hide AdditionalIcon (F 图标)
# 后按钮宽度不缩 (左侧留空白)。跳过隐藏子节点后, 宽度随 F 图标显隐自动缩放。
func get_content_size_x() -> int:
	var size_x := 0
	var content = get_node_or_null("HBoxContainer")
	if content == null:
		return .get_content_size_x()
	for child in content.get_children():
		if not child is Control:
			continue
		var c := child as Control
		if not c.visible:
			continue
		size_x += int(c.rect_size.x)
	return size_x

func _at_cache_base_shop() -> void:
	var node = get_parent()
	while node != null:
		# 用公开方法探测 base_shop extension (has_method 不抛错, 比 get 属性安全)
		if node.has_method("at_start_shop_decision_manually"):
			_at_base_shop = node
			_Logger.info("找到 base_shop 祖先: %s" % str(node.name), _LOG_NAME)
			return
		node = node.get_parent()
	_Logger.warning("未找到 base_shop 祖先, F 路由将回退 vanilla", _LOG_NAME)

# 手动 reroll (鼠标点击 / F 键) pressed 信号: 仅在实际 reroll 后绑回 "auto"。
# base_shop 拦截的 pressed (auto 态 F 键) 不 reroll, _at_did_reroll=false, 不绑回,
# 并重置按钮 pressed 视觉态 (ButtonWithIcon._pressed 会被 vanilla 设 true 改色, 需复位)。
func _at_on_reroll_pressed() -> void:
	var did_reroll := _at_did_reroll
	_at_did_reroll = false
	if not did_reroll:
		# 本次 pressed 被 base_shop 拦截 (auto 态 F 键), 未实际 reroll。
		# 重置 ButtonWithIcon 的 _pressed 视觉态 (vanilla emit pressed 会设 _pressed=true 改色)
		_reset_pressed_visual()
		return
	if _at_base_shop == null or not is_instance_valid(_at_base_shop):
		return
	# call_deferred 保证 vanilla 重建 _shop_items 后 UI 就绪
	_Logger.info("pressed 触发 -> 绑回 auto", _LOG_NAME)
	_at_base_shop.call_deferred("_at_switch_info_owner", "auto")

# 重置按钮 pressed 视觉态: ButtonWithIcon._on_ButtonWithIcon_pressed 会设 _pressed=true
# (改字体颜色为 font_color_pressed), F 键触发的被拦截 pressed 不该保留此视觉。
func _reset_pressed_visual() -> void:
	if get("_pressed") != null:
		set("_pressed", false)
	if has_method("_update_focus_colors"):
		call("_update_focus_colors")

# 供 base_shop._on_RerollButton_pressed 调用: 检查本次 pressed 是否由 F 键 + auto 态触发。
# 若是, 返回 true 并清零标志 (一次性), base_shop 据此拦截 reroll。
# 鼠标点击或 reroll 态 F 键: 返回 false, 放行 reroll。
func _at_consume_f_key_block() -> bool:
	var block := _at_f_key_block_reroll
	_at_f_key_block_reroll = false
	return block

# 供 base_shop 放行 reroll 时调用: 标记本次 pressed 确实 reroll 了
func _at_set_did_reroll(v: bool) -> void:
	_at_did_reroll = v

# 当前 F 归属是否为 AutoTato 决策 (auto 态)。
# 无 base_shop 引用或不在树中时, 默认放行 vanilla (reroll 态), 安全回退。
func _at_is_info_owned_by_auto() -> bool:
	if _at_base_shop == null or not is_instance_valid(_at_base_shop):
		return false
	if not _at_base_shop.has_method("_at_is_input_locked"):
		return false
	# 临界区 (自动化进行中/弹窗) 时, F 完全失效。临界区时让 vanilla 不响应
	# (auto 态吞掉), 避免 vanilla reroll 在自动化进行中被 F 触发。
	if _at_base_shop._at_is_input_locked():
		return true
	return _at_base_shop.at_get_info_owner() == "auto"

func _input(event: InputEvent) -> void:
	# coop 模式下 vanilla 本就不处理 ui_info (reroll_button.gd:30 仅单玩家),
	# 直接走父类, 不干预。
	if RunData.is_coop_run:
		return

	if not is_visible_in_tree():
		return

	# 注意: Script Extension 下 vanilla _input 仍会被 Godot 独立调用一次 (emit pressed)。
	# 故本 _input 不调 ._input(event) 放行 (否则 vanilla _input 跑两次 = pressed emit 两次 = reroll 两次)。
	# reroll 态: 什么都不做, 让 vanilla _input 独立跑 emit pressed -> base_shop._on_RerollButton_pressed
	#   (base_shop 覆写 _on_RerollButton_pressed 放行 reroll 态)。
	# auto 态: 调决策; vanilla _input 仍 emit pressed, 但 base_shop _on_RerollButton_pressed 拦截。
	if event.is_action_pressed("ui_info"):
		var owned_by_auto := _at_is_info_owned_by_auto()
		if owned_by_auto:
			# auto 态: F 键应跑决策, 不 reroll。设标志让 base_shop 拦截本次 pressed 触发的 reroll。
			# (vanilla _input 独立 emit pressed -> base_shop._on_RerollButton_pressed 检查此标志拦截)
			_at_f_key_block_reroll = true
			if _at_base_shop != null and is_instance_valid(_at_base_shop):
				_at_base_shop.at_start_shop_decision_manually(0)
			get_tree().set_input_as_handled()
			return
		# reroll 态: 不设标志, 让 vanilla emit pressed -> base_shop 放行 reroll
		return
