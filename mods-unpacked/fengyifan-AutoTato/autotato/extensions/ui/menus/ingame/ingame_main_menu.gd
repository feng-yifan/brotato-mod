extends "res://ui/menus/ingame/ingame_main_menu.gd"

# ============================================================================
# AutoTato — ingame_main_menu Script Extension (P5.1)
# ----------------------------------------------------------------------------
# 这是 ModLoader v6 Script Extension, hook vanilla 暂停菜单 (战斗 + shop 共用).
#
# 注入策略:
#   - _ready 阶段查找 vanilla Buttons 容器, 注入一个 "AutoTato" 配置按钮,
#     位置插在 QuitButton 之前 (玩家手感上最后才是退出, 配置入口更显眼).
#   - 按钮挂 vanilla my_menu_button.gd 复用主题动效, 颜色 / hover / focus
#     与 ResumeButton / QuitButton 完全一致, 没有 mod 突兀感.
#
# 面板挂载:
#   - 按钮 pressed → 懒加载 config_panel.tscn → 实例化 → 挂到
#     get_tree().get_root() (顶层 viewport), 不污染暂停菜单 scene 树.
#   - 面板节点的 pause_mode = PAUSE_MODE_PROCESS, 即使 SceneTree 暂停也能交互.
#
# 重入防御 + 焦点链重建:
#   - 已注入则 return, 防 init() / scene 切换重复 _ready 时塞多个按钮.
#   - 重建 top/bottom 焦点闭环, 让手柄 / 方向键能命中新按钮.
#
# 注意: vanilla IngameMainMenu 没有定义 _ready (走 Control 默认空实现),
# 所以 hook `._ready()` 安全 ((vanilla 主要逻辑都在 init()).
# ============================================================================


const LOG_NAME := "fengyifan-AutoTato:UIHook"

const PATH_CONFIG_PANEL := "res://mods-unpacked/fengyifan-AutoTato/autotato/ui/config_panel.tscn"
const MY_MENU_BUTTON_SCRIPT := preload("res://ui/menus/global/my_menu_button.gd")
const BUTTONS_NODE_PATH := "MarginContainer/VBoxContainer/HBoxContainer/VBoxContainer2/Buttons"
const BUTTON_NAME := "AutoTatoConfigButton"

var _config_panel: Control = null


func _ready() -> void:
	._ready()  # 调 vanilla 父类 (Control 默认实现, 兜底安全)
	if has_node(BUTTON_NAME):
		return  # 重入防御: 已经注入过, 直接跳过
	var buttons = get_node_or_null(BUTTONS_NODE_PATH)
	if buttons == null:
		_log("vanilla Buttons 容器未找到: %s" % BUTTONS_NODE_PATH)
		return
	_autotato_inject_button(buttons)
	_autotato_rebuild_focus_chain(buttons)


# ----------------------------------------------------------------------------
# AutoTato 流程
# ----------------------------------------------------------------------------

func _autotato_inject_button(buttons: Node) -> void:
	var btn = Button.new()
	btn.name = BUTTON_NAME
	btn.text = "AutoTato"  # TODO P5.5 接 tr_key
	btn.set_script(MY_MENU_BUTTON_SCRIPT)
	btn.focus_mode = Control.FOCUS_ALL

	# 找 QuitButton 索引, 把新按钮插在它前面
	var quit_idx: int = -1
	for i in buttons.get_child_count():
		if buttons.get_child(i).name == "QuitButton":
			quit_idx = i
			break
	buttons.add_child(btn)
	if quit_idx >= 0:
		buttons.move_child(btn, quit_idx)

	btn.connect("pressed", self, "_on_autotato_config_pressed")
	_log("AutoTato 按钮已注入暂停菜单")


func _on_autotato_config_pressed() -> void:
	if _config_panel == null:
		var scene = load(PATH_CONFIG_PANEL)
		if scene == null:
			_log("无法 load config_panel.tscn: %s" % PATH_CONFIG_PANEL)
			return
		_config_panel = scene.instance()
		_config_panel.pause_mode = Node.PAUSE_MODE_PROCESS
		get_tree().get_root().add_child(_config_panel)
		if _config_panel.has_signal("close_requested"):
			_config_panel.connect("close_requested", self, "_on_panel_close_requested")
	_config_panel.show()
	_log("ConfigPanel 已显示")


func _on_panel_close_requested() -> void:
	if _config_panel != null:
		_config_panel.hide()
	_log("ConfigPanel 已关闭")


# 重建焦点链: top/bottom 闭环, 让手柄 / 方向键能命中所有可见按钮.
# vanilla 的 ResumeButton.focus_neighbour_top = QuitButton, QuitButton.focus_neighbour_bottom = ResumeButton
# 我们插入新按钮后, 把整个链按当前 child 顺序重建一遍.
func _autotato_rebuild_focus_chain(buttons: Node) -> void:
	var children: Array = []
	for i in buttons.get_child_count():
		var c = buttons.get_child(i)
		if c is Button and c.visible:
			children.append(c)
	if children.empty():
		return
	var n: int = children.size()
	for i in n:
		var prev = children[(i - 1 + n) % n]
		var next = children[(i + 1) % n]
		children[i].focus_neighbour_top = children[i].get_path_to(prev)
		children[i].focus_neighbour_bottom = children[i].get_path_to(next)


func _log(msg: String) -> void:
	if typeof(ModLoaderLog) != TYPE_NIL:
		ModLoaderLog.info(msg, LOG_NAME)
