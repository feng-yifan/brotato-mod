---
name: Brotato mod 输入与焦点处理优先复用 vanilla 模式
description: 在 Brotato mod 开发中处理输入事件（ESC/手柄 B/ui_cancel）和焦点导航（PopupMenu 循环、focus_neighbour）时，用户认可复用 vanilla 已有模式而非自造轮子
type: 反馈
created_at: 2026-07-05
---

在 Brotato mod 开发中处理输入事件和焦点导航时，优先研究并复用 vanilla 已有的处理模式，而非自己实现新逻辑。

原因：2026-07-05 在 shop_item 规则配置弹窗的开发中，用户两次明确认可了这种做法——(1) input 事件处理复用 vanilla ItemPopup 的 `_input` + `set_input_as_handled` 模式，并配合手柄 B 键守卫（B 同时映射 ui_cancel + ui_ban，打开弹窗的 press 会伴随 ui_cancel released，需跳过防止"打开即关"）；(2) PopupMenu 菜单项循环导航复用 FocusEmulator._handle_popup_menu_input 的模运算模式（focus_emulator.gd:206-214）。用户在需求中明确要求"尽量使用已有的方式处理"。vanilla 模式经过游戏自身验证，与原生行为兼容性好。

如何运用：遇到输入/焦点问题时，先研究 vanilla 如何处理类似场景，找到现成模式再复用——输入处理参考 `ui/menus/shop/item_popup.gd`（`_input` + `is_player_cancel_pressed` + `set_input_as_handled` + `NOTIFICATION_VISIBILITY_CHANGED` 控制是否处理输入）；焦点循环参考 `ui/menus/global/focus_emulator.gd` 的 `_handle_popup_menu_input`（模运算 `(current ± 1 + count) % count`）、`ui/menus/shop/stats_container.gd` 的 `set_focus_neighbours`（`loop_focus_top/bottom` + `focus_neighbour_*`）。关键事实：`set_input_as_handled()` 在 `_input` 层调用可阻止 Godot 原生默认导航（FocusEmulator 已验证此模式可行）；Godot 3 PopupMenu 默认不循环，需模运算手动实现；`focus_neighbour_X = NodePath(".")` 自指可防止焦点逃逸弹窗外。
