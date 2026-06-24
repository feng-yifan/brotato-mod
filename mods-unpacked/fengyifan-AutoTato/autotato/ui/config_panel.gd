extends Control

# ============================================================================
# AutoTato — Config Panel (P5.1 UI 入口)
# ----------------------------------------------------------------------------
# 配置面板根节点 (Control), 结构:
#   ConfigPanel (Control, pause_mode = PAUSE_MODE_PROCESS)
#   ├── Background (ColorRect, 半透明遮罩, mouse_filter = STOP 吞点击)
#   └── CenterContainer
#        └── PanelContainer
#             └── VBoxContainer
#                  ├── HeaderHBox (TitleLabel + CloseButton)
#                  ├── AutoTatoTabs (TabContainer, 预留 P5.2+)
#                  │    └── 通用 (general_tab.gd, P5.1 仅占位 Label)
#                  └── FooterHBox (CancelButton + SaveButton)
#
# P5.1 仅占位 GeneralTab + Save/Cancel/Close 三按钮存根, P5.4 接 Bridge.set_*.
# pause_mode 在 scene 上声明 PAUSE_MODE_PROCESS, 不依赖 INHERIT.
# 由 hook 端 (ingame_main_menu.gd) 懒加载 + show/hide.
# ============================================================================

signal close_requested

onready var _close_button: Button = $CenterContainer/PanelContainer/VBoxContainer/HeaderHBox/CloseButton
onready var _cancel_button: Button = $CenterContainer/PanelContainer/VBoxContainer/FooterHBox/CancelButton
onready var _save_button: Button = $CenterContainer/PanelContainer/VBoxContainer/FooterHBox/SaveButton


func _ready() -> void:
	_close_button.connect("pressed", self, "_on_close")
	_cancel_button.connect("pressed", self, "_on_close")
	_save_button.connect("pressed", self, "_on_save")
	hide()  # 默认隐, 由 hook 显式 show


func _on_close() -> void:
	emit_signal("close_requested")


func _on_save() -> void:
	# P5.1 占位; P5.4+ 接 Bridge.set_* 真实写回配置
	emit_signal("close_requested")


func _input(event: InputEvent) -> void:
	# ESC / B 键关闭面板. 用 released 而非 pressed 与 vanilla PauseMenu 对齐
	# (pause_menu.gd:36 用 is_player_cancel_released): 这样 hook 端在面板 show
	# 阶段 set_process_input(false) PauseMenu, release 那一刻 PauseMenu 还是禁用
	# 状态, 不会跟着我们一起关; call_deferred 下一帧再恢复 PauseMenu input.
	if visible and event.is_action_released("ui_cancel"):
		emit_signal("close_requested")
		get_tree().set_input_as_handled()
