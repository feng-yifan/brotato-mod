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
# CanvasLayer 包装 ConfigPanel, 用高 layer 值确保面板永远绘制在 vanilla PauseMenu 上方.
# 不用 CanvasLayer 时, 面板挂在 root 也会被 vanilla 主场景里晚加入的 PauseMenu 覆盖
# (PauseMenu 是 PanelContainer 不是 CanvasLayer, 按场景树添加顺序绘制).
var _canvas_layer: CanvasLayer = null
const PANEL_CANVAS_LAYER := 128  # vanilla 最高 layer 一般 < 100, 128 保安全

# vanilla PauseMenu 节点的绝对路径 (main.tscn:930 — UI/PauseMenu).
# 面板显示时需要把 PauseMenu._input 临时关掉, 否则 ESC/B 同时关掉两层 UI:
# Godot 3 的 set_input_as_handled() 只阻断 _unhandled_input, 不阻断同帧其他 _input 节点.
const PAUSE_MENU_PATH := "/root/Main/UI/PauseMenu"


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
	btn.text = tr("AUTOTATO_AUTOMATION")
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
		# 用 CanvasLayer 包装, 确保面板永远绘制在 vanilla 暂停菜单上方.
		# PauseMenu 是 PanelContainer (普通 Control 节点树), CanvasLayer 用高 layer 值
		# 跨越普通 Control 的 z-order; 玩家在暂停菜单按下 AutoTato 后, 面板正常显示.
		_canvas_layer = CanvasLayer.new()
		_canvas_layer.layer = PANEL_CANVAS_LAYER
		_canvas_layer.pause_mode = Node.PAUSE_MODE_PROCESS
		get_tree().get_root().add_child(_canvas_layer)
		_config_panel = scene.instance()
		_config_panel.pause_mode = Node.PAUSE_MODE_PROCESS
		_canvas_layer.add_child(_config_panel)
		if _config_panel.has_signal("close_requested"):
			_config_panel.connect("close_requested", self, "_on_panel_close_requested")
	_config_panel.show()
	# 关闭 PauseMenu 的输入处理, 避免 ESC/B 同时关闭两层 UI.
	# Godot 3 的 set_input_as_handled() 不能阻断同帧其他 _input, 必须从源头切断.
	_set_pause_menu_input_enabled(false)
	_log("ConfigPanel 已显示")


func _on_panel_close_requested() -> void:
	if _config_panel != null:
		_config_panel.hide()
	# 延迟一帧再恢复 PauseMenu 输入: 当前 ESC 事件还在分发链上, 立刻打开会让 PauseMenu
	# 接到同一次 ESC 并执行 manage_back() 关掉暂停菜单. call_deferred 跳到下一帧.
	call_deferred("_set_pause_menu_input_enabled", true)
	call_deferred("_grab_focus_on_autotato_button")
	_log("ConfigPanel 已关闭")


# 恢复焦点到 AutoTato 按钮, 防止手柄用户关闭面板后丢失焦点
func _grab_focus_on_autotato_button() -> void:
	var buttons = get_node_or_null(BUTTONS_NODE_PATH)
	if buttons == null:
		return
	var btn = buttons.get_node_or_null(BUTTON_NAME)
	if btn:
		btn.grab_focus()


# 切换 vanilla PauseMenu 的 _input 开关. PauseMenu (pause_menu.gd:32) 自身用
# set_process_input(false/true) 控制暂停时是否监听 ui_cancel/pause; 我们借用同一开关.
func _set_pause_menu_input_enabled(enabled: bool) -> void:
	var pm = get_tree().get_root().get_node_or_null(_strip_root(PAUSE_MENU_PATH))
	if pm == null:
		# 安全兜底: 找不到就放弃, 不阻塞玩家. 真实游戏里 PauseMenu 必然存在.
		_log("找不到 PauseMenu (%s), 跳过 input 切换" % PAUSE_MENU_PATH)
		return
	pm.set_process_input(enabled)


# get_node 不接受以 "/root/" 开头的路径 (那是 get_tree().get_root() 自身),
# 剥掉首段返回相对路径.
func _strip_root(absolute_path: String) -> String:
	if absolute_path.begins_with("/root/"):
		return absolute_path.substr(6)
	return absolute_path


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
