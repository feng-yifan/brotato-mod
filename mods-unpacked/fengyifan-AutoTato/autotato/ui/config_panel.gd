extends Control

# ============================================================================
# AutoTato — Config Panel (UI 根节点)
# ----------------------------------------------------------------------------
# 配置面板根节点 (Control, pause_mode = PAUSE_MODE_PROCESS), 结构:
#   ConfigPanel (Control, pause_mode = PAUSE_MODE_PROCESS)
#   ├── Background (ColorRect, 半透明遮罩, mouse_filter = STOP 吞点击)
#   └── PanelContainer (全屏, anchor 0-1)
#        └── VBoxContainer
#             ├── HeaderHBox (TitleLabel + ResetButton ⟳ + CloseButton ✕)
#             └── AutoTatoTabs (TabContainer)
#                  ├── 通用 (general_tab.gd)   — 自动化开关
#                  ├── 升级 (upgrade_tab.gd)   — 升级策略
#                  ├── 物品 (items_tab.gd)      — 物品规则编辑器
#                  ├── 武器 (weapons_tab.gd)    — 武器规则编辑器
#                  └── 阈值 (thresholds_tab.gd) — 阈值编辑器
#
# tab_changed → 调用目标 Tab 的 _refresh() 刷新游戏数据.
# pause_mode 在 scene 上声明 PAUSE_MODE_PROCESS, 不依赖 INHERIT.
# 由 hook 端 (ingame_main_menu.gd) 懒加载 + show/hide.
# ============================================================================

signal close_requested

onready var _title_label: Label = $PanelContainer/VBoxContainer/HeaderHBox/TitleLabel
onready var _close_button: Button = $PanelContainer/VBoxContainer/HeaderHBox/CloseButton
onready var _tabs: TabContainer = $PanelContainer/VBoxContainer/AutoTatoTabs
onready var _gamepad_nav: Node = $GamepadNavigator
var _reset_button: Button = null

# Tab 内部名称 → 翻译 key 映射
const TAB_TRANSLATION_KEYS := {
	"GeneralTab": "AUTOTATO_TAB_GENERAL",
	"UpgradeTab": "AUTOTATO_TAB_UPGRADE",
	"ItemsTab": "AUTOTATO_TAB_ITEMS",
	"WeaponsTab": "AUTOTATO_TAB_WEAPONS",
	"ThresholdsTab": "AUTOTATO_TAB_THRESHOLDS",
}


func _ready() -> void:
	_title_label.text = tr("AUTOTATO_PANEL_TITLE")
	# 设置每个 Tab 的多语言标题
	for i in _tabs.get_child_count():
		var child = _tabs.get_child(i)
		var tab_key = TAB_TRANSLATION_KEYS.get(child.name, "")
		if tab_key:
			_tabs.set_tab_title(i, tr(tab_key))
	_close_button.connect("pressed", self, "_on_close")
	_build_reset_button()
	_tabs.connect("tab_changed", self, "_on_tab_changed")
	_apply_vanilla_theme()
	hide()  # 默认隐, 由 hook 显式 show


func _notification(what: int) -> void:
	# 面板显示时, 延迟一帧给当前 Tab 第一个控件焦点, 让手柄可以开始导航.
	# call_deferred 等所有子控件完成布局和 _refresh 后再 grab_focus.
	if what == NOTIFICATION_VISIBILITY_CHANGED and visible:
		call_deferred("_grab_initial_focus")


func _grab_initial_focus() -> void:
	var tab_idx := _tabs.current_tab
	var tab_ctrl := _tabs.get_child(tab_idx) as Control
	if tab_ctrl == null:
		return
	for child in tab_ctrl.get_children():
		if child is Control:
			var ctrl: Control = child as Control
			if ctrl.focus_mode == Control.FOCUS_ALL:
				ctrl.grab_focus()
				return
	# 如果直接子节点没有可聚焦的, 递归查找
	var first := _find_first_focusable(tab_ctrl)
	if first:
		first.grab_focus()


func _find_first_focusable(from: Node) -> Control:
	for child in from.get_children():
		if child is Control:
			var ctrl: Control = child as Control
			if ctrl.focus_mode == Control.FOCUS_ALL:
				return ctrl
		var found := _find_first_focusable(child)
		if found:
			return found
	return null


func _on_close() -> void:
	emit_signal("close_requested")


func _on_tab_changed(tab: int) -> void:
	# 切到某个 Tab 时调用该 Tab 的 _refresh() 刷新游戏数据.
	var child: Control = _tabs.get_child(tab) as Control
	if child and child.has_method("_refresh"):
		child._refresh()
	# 延迟一帧给新 Tab 首个控件焦点
	call_deferred("_grab_initial_focus")


# ----------------------------------------------------------------------------
# Reset 按钮 — 重置所有配置为默认值
# ----------------------------------------------------------------------------
# 在 HeaderHBox 的 CloseButton 之前插入 Reset 按钮.
# 使用 ConfirmationDialog 做二次确认, 防止误操作.
# 确认后调用 Bridge.reset_to_defaults() 并刷新所有 Tab.
func _build_reset_button() -> void:
	var header_hbox := $PanelContainer/VBoxContainer/HeaderHBox
	_reset_button = Button.new()
	_reset_button.name = "ResetButton"
	_reset_button.text = tr("AUTOTATO_RESET_CONFIG")
	_reset_button.rect_min_size = Vector2(40, 40)
	_reset_button.size_flags_horizontal = 0
	_reset_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_reset_button.connect("pressed", self, "_on_reset_pressed")
	# 插入到 CloseButton 之前 (CloseButton 是最后一个子节点)
	var close_idx := _close_button.get_index()
	header_hbox.add_child(_reset_button)
	header_hbox.move_child(_reset_button, close_idx)


func _on_reset_pressed() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.name = "ResetConfirmDialog"
	dialog.dialog_text = tr("AUTOTATO_RESET_CONFIRM_MSG")
	dialog.get_ok().text = tr("AUTOTATO_CONFIRM")
	dialog.get_cancel().text = tr("AUTOTATO_CANCEL")
	dialog.connect("confirmed", self, "_do_reset")
	add_child(dialog)
	# 复用 vanilla 主题, 确保中文正常显示
	var th = load(VANILLA_THEME_PATH)
	if th != null:
		dialog.theme = th
	dialog.popup_centered()


func _do_reset() -> void:
	var bridge = Engine.get_meta("fengyifan-AutoTato:Bridge")
	if bridge == null:
		return
	bridge.reset_to_defaults()
	# 刷新所有 Tab 的 UI
	for i in _tabs.get_child_count():
		var child = _tabs.get_child(i)
		if child.has_method("_refresh"):
			child._refresh()


func _input(event: InputEvent) -> void:
	if not visible:
		return

	# 如果 OptionButton 下拉菜单正在显示, 不处理面板级输入
	if _has_visible_popup_menu():
		return

	# 弹窗打开时不响应肩键
	if _has_visible_any_popup():
		return

	# ESC / B 键关闭面板
	if event.is_action_released("ui_cancel"):
		emit_signal("close_requested")
		get_tree().set_input_as_handled()

	# 肩键切换 Tab
	if event.is_action_pressed("ltrigger"):
		_switch_tab(-1)
		get_tree().set_input_as_handled()
	elif event.is_action_pressed("rtrigger"):
		_switch_tab(1)
		get_tree().set_input_as_handled()


func _switch_tab(direction: int) -> void:
	if _tabs == null:
		return
	var count := _tabs.get_tab_count()
	if count == 0:
		return
	var new_idx := _tabs.current_tab + direction
	if new_idx < 0:
		new_idx = count - 1
	elif new_idx >= count:
		new_idx = 0
	_tabs.current_tab = new_idx
	call_deferred("_grab_initial_focus")


func _has_visible_popup_menu() -> bool:
	return _find_visible_popup_menu(self)


func _find_visible_popup_menu(node: Node) -> bool:
	for child in node.get_children():
		if child is PopupMenu:
			var pm: PopupMenu = child as PopupMenu
			if pm.visible:
				return true
		if _find_visible_popup_menu(child):
			return true
	return false


func _has_visible_any_popup() -> bool:
	return _find_visible_popup(self)


func _find_visible_popup(node: Node) -> bool:
	for child in node.get_children():
		if child is Popup:
			var popup: Popup = child as Popup
			if popup.visible:
				return true
		if _find_visible_popup(child):
			return true
	return false


# ----------------------------------------------------------------------------
# Vanilla 主题
# ----------------------------------------------------------------------------
# ConfigPanel 挂在 CanvasLayer 上, 不在 vanilla 场景树的主题传播链内,
# 所以 Godot 3 的默认字体无法渲染 CJK 字形 (中文显示为 tofu 方块).
# 直接复用 vanilla base_theme.tres, 该资源已包含:
#   - default_font → font_menus (Anybody-Medium + NotoSansSC/TC/KR/JP fallback)
#   - Button/PanelContainer/TabContainer/Label 的完整样式
# 这样面板的颜色、字体大小、间距与游戏暂停菜单完全一致.
const VANILLA_THEME_PATH := "res://resources/themes/base_theme.tres"

func _apply_vanilla_theme() -> void:
	var th = load(VANILLA_THEME_PATH)
	if th != null:
		self.theme = th
