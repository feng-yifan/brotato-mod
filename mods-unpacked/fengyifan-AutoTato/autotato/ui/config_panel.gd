extends Control

# ============================================================================
# AutoTato — Config Panel (P5.1 UI 入口)
# ----------------------------------------------------------------------------
# 配置面板根节点 (Control, pause_mode = PAUSE_MODE_PROCESS), 结构:
#   ConfigPanel (Control, pause_mode = PAUSE_MODE_PROCESS)
#   ├── Background (ColorRect, 半透明遮罩, mouse_filter = STOP 吞点击)
#   └── PanelContainer (全屏, anchor 0-1)
#        └── VBoxContainer
#             ├── HeaderHBox (TitleLabel + CloseButton ✕)
#             └── AutoTatoTabs (TabContainer, 预留 P5.2+)
#                  └── 通用 (general_tab.gd, P5.1 仅占位 Label)
#
# P5.1: 全屏面板 + CJK 字体 + 仅标题栏 CloseButton.
# 底部 Save/Cancel 按钮已移除, P5.4 另行设计保存机制.
# pause_mode 在 scene 上声明 PAUSE_MODE_PROCESS, 不依赖 INHERIT.
# 由 hook 端 (ingame_main_menu.gd) 懒加载 + show/hide.
# ============================================================================

signal close_requested

onready var _close_button: Button = $PanelContainer/VBoxContainer/HeaderHBox/CloseButton


func _ready() -> void:
	_close_button.connect("pressed", self, "_on_close")
	_apply_vanilla_theme()
	hide()  # 默认隐, 由 hook 显式 show


func _on_close() -> void:
	emit_signal("close_requested")


func _input(event: InputEvent) -> void:
	# ESC / B 键关闭面板. 用 released 而非 pressed 与 vanilla PauseMenu 对齐
	# (pause_menu.gd:36 用 is_player_cancel_released): 这样 hook 端在面板 show
	# 阶段 set_process_input(false) PauseMenu, release 那一刻 PauseMenu 还是禁用
	# 状态, 不会跟着我们一起关; call_deferred 下一帧再恢复 PauseMenu input.
	if visible and event.is_action_released("ui_cancel"):
		emit_signal("close_requested")
		get_tree().set_input_as_handled()


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
