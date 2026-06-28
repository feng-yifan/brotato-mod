---
title: AutoTato ConfigPanel UI 交互流程
description: >
  AutoTato 配置面板的 UI 交互设计，属于 autotato 领域知识。
  覆盖 Vanilla 暂停菜单 UI 树（PauseMenu/IngameMainMenu）、ConfigPanel
  Scene 结构（CanvasLayer/Background/CenterContainer）、完整交互链路
  （打开→注入按钮→焦点链重建→关闭）、ESC 竞态问题的根因与解决方案
  （set_process_input + call_deferred）、手柄导航（GamepadNavigator/
  焦点可视化/肩键切 Tab/弹窗焦点围栏）、时序图、未实现功能 roadmap。
game_version: 1.1.15.4
---

# AutoTato ConfigPanel — UI 交互流程

---

## Vanilla 暂停菜单 UI 树

```
Main (main.tscn)
└── UI
    └── PauseMenu (PanelContainer, pause_menu.tscn — 脚本: pause_menu.gd)
        ├── Menus
        │   ├── MainMenu (ingame_main_menu.tscn — 脚本: ingame_main_menu.gd)
        │   │   └── MarginContainer/VBoxContainer/HBoxContainer
        │   │       ├── [左侧面板]
        │   │       │   └── HBoxContainer/VBoxContainer
        │   │       │       ├── CoopPlayerSelector
        │   │       │       ├── WeaponsContainer
        │   │       │       └── ItemsContainer
        │   │       └── VBoxContainer2
        │   │           ├── StatsContainer      ← 属性面板
        │   │           └── Buttons (VBoxContainer, 600×500, separation=25)
        │   │               ├── ResumeButton     (my_menu_button.gd)
        │   │               ├── RestartButton
        │   │               ├── EndRunButton
        │   │               ├── CodexButton
        │   │               ├── OptionsButton
        │   │               ├── [AutoTatoConfigButton]  ← AutoTato 注入
        │   │               └── QuitButton
        │   ├── MenuOptions (设置子页面)
        │   ├── MenuConfirm (确认弹窗)
        │   ├── MenuRestart
        │   └── MenuEndRun
        └── FocusEmulator (手柄导航模拟器)
```

### PauseMenu 关键行为（pause_menu.gd）

```gdscript
func pause(player_index: int):
    set_process_input(true)          # 开始监听输入（ESC/pause 等）
    get_tree().paused = true         # 冻结游戏逻辑
    show()
    main_menu.init(player_index)     # 初始化 IngameMainMenu

func unpause():
    set_process_input(false)         # 停止监听
    hide()
    get_tree().paused = false
    emit_signal("unpaused")

func _input(event):
    if get_tree().paused:
        if Utils.is_player_cancel_released(event, ...):
            manage_back()            # ESC → 关闭暂停
```

### IngameMainMenu 关键行为（ingame_main_menu.gd）
- `init(player_index)` 填充武器/物品/属性面板、timeline、难度标签
- `_buttons_array = [ResumeButton, CodexButton, RestartButton, EndRunButton, OptionsButton, QuitButton]`
- 按钮通过信号（`resume_button_pressed` 等）向上发射

---

## AutoTato ConfigPanel Scene 树

```
CanvasLayer (layer=128, pause_mode=PAUSE_MODE_PROCESS)
└── ConfigPanel (Control, anchor=全屏, pause_mode=PAUSE_MODE_PROCESS)
    ├── Background (ColorRect, color=#00000080, mouse_filter=STOP)
    │     → 半透明遮罩，吞掉穿透到 PauseMenu 的鼠标事件
    └── CenterContainer
        └── PanelContainer (800×600)
            └── VBoxContainer
                ├── HeaderHBox
                │   ├── TitleLabel "AutoTato 配置"
                │   └── CloseButton "✕" (40×40)
                ├── TabContainer
                │   └── 通用 (Control, script=general_tab.gd)
                │       └── PlaceholderLabel
                └── FooterHBox
                    ├── CancelButton "取消"
                    └── SaveButton "保存"
```

### ConfigPanel 脚本关键逻辑

```gdscript
extends Control
signal close_requested

# Save/Cancel/Close 全部仅 emit close_requested
# 后续：SaveButton 会调用 Bridge.set_* 写回配置
func _on_close(): emit_signal("close_requested")
func _on_save(): emit_signal("close_requested")  # 后续接 Bridge.set_*

func _input(event):
    # ESC/B 键关闭面板（用 released 与 vanilla PauseMenu 对齐）
    if visible and event.is_action_released("ui_cancel"):
        emit_signal("close_requested")
        get_tree().set_input_as_handled()
```

---

## 完整用户交互流程

### 打开链路

```
1. 按 ESC/Pause → PauseMenu.pause(0)
   → set_process_input(true)          # PauseMenu 开始监听按键
   → get_tree().paused = true         # 游戏逻辑冻结
   → MainMenu.show() + init(0)        # 填充暂停菜单内容

2. IngameMainMenu._ready()
   → AutoTato 扩展脚本._ready()
     → _autotato_inject_button()       # 创建 AutoTatoConfigButton
     → _autotato_rebuild_focus_chain() # 重建按钮焦点闭环

3. 玩家点击/选中 AutoTato 按钮
   → _on_autotato_config_pressed()
     if _config_panel == null:         # 懒加载（首次）
       → CanvasLayer.new(layer=128)
       → load + instance config_panel.tscn
       → connect close_requested
     _config_panel.show()              # 面板显示
     PauseMenu.set_process_input(false) # 禁用 PauseMenu 输入
```

### 关闭链路

```
4. 玩家按 ESC / 点 CloseButton ✕ / 点 CancelButton "取消"
   → ConfigPanel._input() 或 _on_close()
     → emit_signal("close_requested")

5. _on_panel_close_requested()
   → _config_panel.hide()                     # 实例保留（下次 show 复用）
   → call_deferred("_set_pause_menu_input_enabled", true)
        ↑ 延迟到下一帧恢复 PauseMenu 输入
```

### 玩家交互矩阵

| 操作 | 触发者 | 最终行为 |
|---|---|---|
| 按 ESC（暂停） | `main._process()` | `PauseMenu.pause(0)` → 暂停菜单显示 |
| 按 ESC（关面板） | `ConfigPanel._input()` | `close_requested` → 面板关闭 |
| 按 B（手柄，关面板） | `ConfigPanel._input()` | 同上 |
| 点 ✕ CloseButton | `_on_close()` | `close_requested` → 面板关闭 |
| 点 "取消" CancelButton | `_on_close()` | `close_requested` → 面板关闭 |
| 点 "保存" SaveButton | `_on_save()` | 同 close |
| 点半透明背景 | 无逻辑 | 不响应（纯遮罩） |
| 点 ResumeButton（暂停菜单） | `PauseMenu.unpause()` | 游戏继续 |

---

## 关键工程问题与解决方案

### 1. CanvasLayer 为什么必须存在

**问题**：PauseMenu 是 `PanelContainer`（普通 Control），Godot 3 中同父节点下的 Control 按子节点添加顺序绘制。PauseMenu 在 `pause()` 时才 `show()`，时机晚于 ConfigPanel 创建。如果 ConfigPanel 直接挂 root，可能被 PauseMenu 覆盖。

**解决**：CanvasLayer 用独立 `layer=128` 跨越普通 Control 的 z-order 系统。vanilla 最高 layer 一般 < 100，128 保安全。

### 2. ESC 竞态窗口

**问题**：面板显示时用户按 ESC。如果 PauseMenu 和 ConfigPanel 同时监听：
- PauseMenu `_input()` → `manage_back()` → `unpause()` → 游戏恢复
- ConfigPanel `_input()` → 面板关闭
- 结果：面板关了但游戏也恢复了 → 用户体验灾难

**解决方案分两步**：

**关闭 PauseMenu 输入**（同步，面板 show 时）：
```gdscript
// _set_pause_menu_input_enabled(false)
pm.set_process_input(false)
```

**恢复 PauseMenu 输入**（延迟，面板 close 时）：
```gdscript
call_deferred("_set_pause_menu_input_enabled", true)
```

**为什么必须 `call_deferred`**：当前 ESC 释放事件还在 Godot 的事件分发链上。如果立刻恢复 PauseMenu `process_input`，同一分发链中 PauseMenu `_input()` 也会收到这个 ESC → `manage_back()` → 暂停错误关闭。

`call_deferred` 把恢复操作推迟到**所有待处理输入事件分发完毕后**的下一帧。

### 3. Godot 3 `set_input_as_handled()` 局限性

`set_input_as_handled()` 只阻断 `_unhandled_input` 链，**不阻断**同帧内其他 `_input()` 节点。每个 Control 的 `_input()` 是引擎独立遍历调用的。因此同帧内关闭一个输入源、打开另一个时，必须用 `call_deferred` 错开一帧。

### 4. 按钮焦点链重建

vanilla Buttons 原始焦点链：
```
ResumeButton  →  focus_neighbour_top = QuitButton
QuitButton    →  focus_neighbour_bottom = ResumeButton
```

AutoTato 注入后完整重建所有按钮的 `focus_neighbour_top/bottom`（循环链表），保证手柄/方向键能命中所用按钮。vvanilla 中按钮间距 25px（`custom_constants/separation = 25`），新按钮继承同一 `my_menu_button.gd` 脚本保持视觉一致。

### 5. 重入防御

```gdscript
if has_node(BUTTON_NAME):
    return  # 已注入过，跳过
```
防止 mod 重载 / 场景切换导致重复添加按钮。

### 6. 面板懒加载

```gdscript
if _config_panel == null:
    _canvas_layer = CanvasLayer.new()
    _config_panel = scene.instance()
    ...
_config_panel.show()
```
第一次按下按钮时才 `load()` + `instance()`，之后 `hide()`/`show()` 复用。不预加载 = 不增加游戏启动时间。`pause_mode = PAUSE_MODE_PROCESS` 确保 SceneTree 暂停时面板仍能交互。

---

## 时序图

```
用户操作         游戏进程                      AutoTato Mod
────────         ────────                      ────────────
按 ESC
  │              main._process()
  │              → PauseMenu.pause(0)
  │                → process_input(true)
  │                → Tree.paused = true
  │                → MainMenu.show()
  │
  │              [暂停菜单显示]             IngameMainMenu._ready()
  │                                           → ._ready()
  │                                           → 查找 Buttons 容器
  │                                           → 创建 AutoTatoConfigButton
  │                                           → 插入 QuitButton 前
  │                                           → 重建焦点闭环
  │
点 AutoTato
  │                                        _on_autotato_config_pressed()
  │                                          → CanvasLayer.new(128)
  │                                          → instance config_panel.tscn
  │                                          → ConfigPanel.show()
  │                                          → PauseMenu.process_input(false)
  │
  │              [面板显示在暂停菜单上方，
  │               PauseMenu 输入已禁用]
  │
按 ESC (关面板)
  │                                        ConfigPanel._input()
  │                                          → emit close_requested
  │                                        _on_panel_close_requested()
  │                                          → ConfigPanel.hide()
  │                                          → call_deferred(恢复PauseMenu输入)
  │
  │              [下一帧]
  │              PauseMenu.process_input(true)
  │              [暂停菜单输入已恢复]
  │
点 ResumeButton
  │              PauseMenu.unpause()
  │                → process_input(false)
  │                → Tree.paused = false
  │              [游戏继续]
```

---

## 后续规划

| 阶段 | 内容 |
|---|---|
| 规则编辑器 | 物品规则编辑器 Tab（item_rules 的增删改 UI） |
| 阈值编辑器 | 阈值编辑器 Tab（thresholds 的 UI） |
| 保存逻辑 | 接通 Bridge.set_* 写回 + SaveButton 真实保存 |
| i18n | 双语支持（tr_key） |
| 手柄支持 | ✅ 已完成 — D-pad 焦点导航 + 肩键切 Tab + 焦点可视化 |

---

## 手柄支持（2026-06-28 实施）

### 设计决策

**不重用 vanilla FocusEmulator**。FocusEmulator（720 行）为 coop 多人设计，含
多玩家焦点着色、`focus_base_data` 分区导航、PopupMenu 手柄控制等。配置面板
是单人场景，不需要这些。改用 **Godot 3 内置焦点系统** + 轻量 `GamepadNavigator`。

### 核心组件

**GamepadNavigator**（`autotato/ui/gamepad_navigator.gd`）：
- 继承 `Node`（非 Control），不参与布局系统
- 显式 `set_process_input(true)` 接收 `_input`（Node 默认不接收）
- 职责：肩键切 Tab + 焦点可视化（Theme StyleBox 覆盖）

**焦点可视化策略**：
一次覆盖 Theme 的所有控件类型 focus StyleBox，Godot 3 引擎在绘制时自动套用：
```gdscript
theme.set_stylebox("focus", "Button", focus_stylebox)
theme.set_stylebox("focus", "CheckButton", focus_stylebox)
theme.set_stylebox("focus", "OptionButton", focus_stylebox)
theme.set_stylebox("focus", "LineEdit", focus_stylebox)
```
金色边框（`Color(1.0, 0.85, 0.2, 0.9)`）+ 微白底。

### 控件焦点启用

所有 UI tab 文件中显式 `focus_mode = Control.FOCUS_NONE` 删除 / 改为
`FOCUS_ALL`。原始注释 "FOCUS_NONE 防止焦点窃取导致 hover 失效" 的担忧
实际上不存在——创建控件时不调 `grab_focus()`，焦点只在用户输入（方向键/
鼠标悬停）时转移。

**范围限制**：Extension 覆盖层（`base_shop.gd`、`shop_item.gd`、
`upgrades_ui_player_container.gd`）中的 `FOCUS_NONE` **保持不动**。这些是
游戏内快捷按钮，与 vanilla FocusEmulator 共用场景树，改焦点会干扰
游戏主 UI 的手柄导航。

### 手柄按键映射

| 手柄按键 | Godot action | 功能 |
|---|---|---|
| D-pad / 左摇杆 | `ui_up/down/left/right` | 控件间移动焦点 |
| A (Xbox) / Cross (PS) | `ui_accept` | 触发当前控件 |
| B (Xbox) / Circle (PS) | `ui_cancel` | 逐层退出（弹窗 → 面板 → 暂停菜单） |
| LB / LT | `ltrigger` | 上一个 Tab |
| RB / RT | `rtrigger` | 下一个 Tab |

肩键选择 `ltrigger`/`rtrigger` 是为了与 vanilla `UIBetterTabContainer`
的按键映射保持一致。

### 弹窗焦点管理

ItemsTab / WeaponsTab 卡片弹窗打开时：
1. `call_deferred("_grab_popup_focus")` → 首个 OptionButton 获得焦点
2. Cancel / Save 按钮设置 `focus_neighbour_left/right` 互为邻居
3. 肩键被 `_is_any_popup_open()` 守卫拦截（弹窗存在时 Tab 被锁定）
4. Godot 3 的 `Popup + popup_exclusive=true` 自动提供焦点围栏

### 焦点邻居

大部分布局无需手动设置——Godot 3 的空间焦点检测在 VBoxContainer/HBoxContainer/
GridContainer 中自动计算最近邻居。仅弹窗的 Cancel↔Save（水平排列的两个孤立按钮）
手动设置了 `focus_neighbour_left/right`。

### 未变更的部分

- **vanilla FocusEmulator** 完全不受影响（不改任何 vanilla 文件）
- **config_panel ESC 竞态修复** 不变（`call_deferred` 恢复 PauseMenu 输入
  对手柄 B 按钮同样有效）
- **InputService.using_gamepad** 未被使用——键盘用户也受益于焦点导航
