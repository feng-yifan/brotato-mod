extends Control

# ============================================================================
# AutoTato — Upgrade Tab (v7 升级配置面板)
# ----------------------------------------------------------------------------
# 集中管理升级相关的所有配置 (自动化开关已移至通用面板):
#   1. 受阈值影响 + 最低等级 + 品质优先
#   2. 禁止属性列表 (仅主要属性, 多选)
#   3. 卡住时忽略禁止列表
#   4. 优先级排序 (⬆⬇ 移除)
# ============================================================================

const LOG_NAME := "fengyifan-AutoTato:UpgradeTab"
const _Config = preload("res://mods-unpacked/fengyifan-AutoTato/config/config.gd")

var _respect_thresholds_cb: CheckButton = null
var _min_tier_opt: OptionButton = null
var _quality_first_cb: CheckButton = null
var _ignore_forbid_cb: CheckButton = null

# forbid: stat_key → CheckButton
var _forbid_checkboxes: Dictionary = {}

# priority: stat_key → {row, up_btn, down_btn, remove_btn}
var _priority_rows: Dictionary = {}
var _priority_vbox: VBoxContainer = null
var _unprioritized_vbox: VBoxContainer = null

# stat_key → 中文显示名称 (从 vanilla i18n 获取)
var _stat_names: Dictionary = {}

var _refreshing := false
var _pending_focus_stat: String = ""  # 手柄: 按钮按下后待恢复焦点的 stat_key
var _pending_focus_action: String = ""  # "up", "down", "remove", "add"
var _pending_remove_idx: int = -1  # remove 前的索引


func _ready() -> void:
	_load_stat_names()
	_build_ui()
	_refresh()


func _load_stat_names() -> void:
	_stat_names.clear()
	if typeof(ItemService) != TYPE_OBJECT:
		return
	var stats = ItemService.get("stats")
	if typeof(stats) != TYPE_ARRAY:
		return
	for stat in stats:
		var sn: String = stat.get("stat_name")
		if sn == "":
			continue
		var tr_name = tr(sn.to_upper())
		if tr_name != sn.to_upper():
			_stat_names[sn] = tr_name
		else:
			_stat_names[sn] = sn.replace("stat_", "").capitalize()


func _build_ui() -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "ScrollContainer"
	scroll.anchor_right = 1.0
	scroll.anchor_bottom = 1.0
	scroll.scroll_horizontal_enabled = false
	scroll.follow_focus = true
	add_child(scroll)

	# MarginContainer 确保内容不超出视口
	var margin := MarginContainer.new()
	margin.name = "ContentMargin"
	margin.size_flags_horizontal = SIZE_EXPAND_FILL
	margin.size_flags_vertical = SIZE_EXPAND
	margin.add_constant_override("margin_left", 16)
	margin.add_constant_override("margin_right", 16)
	margin.add_constant_override("margin_top", 8)
	margin.add_constant_override("margin_bottom", 8)
	scroll.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.name = "UpgradeVBox"
	vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	vbox.add_constant_override("separation", 12)
	margin.add_child(vbox)

	# ---- 1. 升级策略 ----
	vbox.add_child(_section_header(tr("AUTOTATO_UPGRADE_STRATEGY")))

	_respect_thresholds_cb = _make_check(tr("AUTOTATO_RESPECT_THRESHOLDS"))
	_respect_thresholds_cb.connect("toggled", self, "_on_respect_toggled")
	vbox.add_child(_respect_thresholds_cb)

	vbox.add_child(_desc(tr("AUTOTATO_RESPECT_THRESHOLDS_DESC")))

	# 最低等级
	var tier_row := HBoxContainer.new()
	tier_row.rect_min_size.y = 32
	tier_row.add_child(_label(tr("AUTOTATO_MIN_TIER")))

	_min_tier_opt = OptionButton.new()
	_min_tier_opt.name = "MinTierOpt"
	_min_tier_opt.rect_min_size.x = 80
	for i in range(4):
		_min_tier_opt.add_item("≥ %d" % (i + 1))
	_min_tier_opt.connect("item_selected", self, "_on_min_tier_changed")
	tier_row.add_child(_min_tier_opt)

	var tier_spacer := Control.new()
	tier_spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	tier_row.add_child(tier_spacer)
	vbox.add_child(tier_row)

	_quality_first_cb = _make_check(tr("AUTOTATO_QUALITY_FIRST"))
	_quality_first_cb.connect("toggled", self, "_on_quality_toggled")
	vbox.add_child(_quality_first_cb)

	vbox.add_child(_desc(tr("AUTOTATO_QUALITY_FIRST_DESC")))
	vbox.add_child(HSeparator.new())

	# ---- 2. 禁止属性 (仅主要属性) ----
	vbox.add_child(_section_header(tr("AUTOTATO_FORBID_STATS")))
	vbox.add_child(_desc(tr("AUTOTATO_FORBID_STATS_DESC")))

	var forbid_grid := GridContainer.new()
	forbid_grid.name = "ForbidGrid"
	forbid_grid.columns = 3
	forbid_grid.size_flags_horizontal = SIZE_EXPAND_FILL
	forbid_grid.add_constant_override("hseparation", 8)
	forbid_grid.add_constant_override("vseparation", 2)
	vbox.add_child(forbid_grid)

	var primary_stats = _get_primary_stats()
	for sk in primary_stats:
		var cb := _make_check(_stat_names.get(sk, sk))
		cb.name = "Forbid_%s" % sk
		cb.connect("toggled", self, "_on_forbid_toggled", [sk])
		forbid_grid.add_child(cb)
		_forbid_checkboxes[sk] = cb

	vbox.add_child(HSeparator.new())

	# ---- 3. 卡住时忽略 ----
	_ignore_forbid_cb = _make_check(tr("AUTOTATO_IGNORE_FORBID_ON_STUCK"))
	_ignore_forbid_cb.connect("toggled", self, "_on_ignore_forbid_toggled")
	vbox.add_child(_ignore_forbid_cb)

	vbox.add_child(_desc(tr("AUTOTATO_IGNORE_FORBID_ON_STUCK_DESC")))
	vbox.add_child(HSeparator.new())

	# ---- 4. 优先级排序 ----
	vbox.add_child(_section_header(tr("AUTOTATO_STAT_PRIORITY")))
	vbox.add_child(_desc(tr("AUTOTATO_STAT_PRIORITY_DESC")))

	var pri_label := Label.new()
	pri_label.text = tr("AUTOTATO_PRIORITIZED")
	pri_label.modulate = Color(1, 1, 1, 0.7)
	vbox.add_child(pri_label)

	_priority_vbox = VBoxContainer.new()
	_priority_vbox.add_constant_override("separation", 2)
	vbox.add_child(_priority_vbox)

	vbox.add_child(HSeparator.new())

	var unpri_label := Label.new()
	unpri_label.text = tr("AUTOTATO_NOT_PRIORITIZED")
	unpri_label.modulate = Color(1, 1, 1, 0.7)
	vbox.add_child(unpri_label)

	_unprioritized_vbox = VBoxContainer.new()
	_unprioritized_vbox.add_constant_override("separation", 2)
	vbox.add_child(_unprioritized_vbox)


func _make_check(text: String) -> CheckButton:
	var cb := CheckButton.new()
	cb.text = text
	cb.size_flags_horizontal = SIZE_EXPAND_FILL
	cb.clip_text = true
	return cb


func _section_header(title: String) -> Label:
	var l := Label.new()
	l.text = title
	l.modulate = Color(0.35, 0.8, 1.0, 1.0)
	return l


func _desc(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.modulate = Color(1, 1, 1, 0.5)
	l.size_flags_horizontal = SIZE_EXPAND_FILL
	l.autowrap = true
	return l


func _label(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.valign = Label.VALIGN_CENTER
	return l


# ============================================================================
# 数据刷新
# ============================================================================

func _refresh() -> void:
	_refreshing = true

	var bridge = _get_bridge()
	if bridge == null:
		_refreshing = false
		return

	var upg = bridge.get_upgrade_config()
	_respect_thresholds_cb.pressed = bool(upg.get("respect_thresholds", true))
	_min_tier_opt.select(max(int(upg.get("min_tier", -1)), 0))
	_quality_first_cb.pressed = bool(upg.get("quality_first", false))
	_ignore_forbid_cb.pressed = bool(upg.get("ignore_forbid_on_stuck", false))

	# Forbid 复选框
	var forbid_stats = bridge.get_upgrade_forbid_stats()
	for sk in _forbid_checkboxes:
		_forbid_checkboxes[sk].pressed = forbid_stats.has(sk)

	# 优先级列表 (仅主要属性)
	var priority = upg.get("stat_priority", [])
	if typeof(priority) != TYPE_ARRAY:
		priority = []
	_refresh_priority_ui(priority, bridge)

	_refreshing = false
	# 手柄: 按钮按下后 refresh 会销毁焦点控件, 延迟恢复
	call_deferred("_grab_focus_after_refresh")


func _grab_focus_after_refresh() -> void:
	if _pending_focus_stat != "":
		match _pending_focus_action:
			"up":
				# 焦点跟踪到上移后的行
				var row_ref = _priority_rows.get(_pending_focus_stat)
				if row_ref and row_ref["up_btn"] and row_ref["up_btn"].visible:
					row_ref["up_btn"].grab_focus()
			"down":
				# 焦点跟踪到下移后的行 — down 按钮
				var row_ref_d = _priority_rows.get(_pending_focus_stat)
				if row_ref_d and row_ref_d["down_btn"] and row_ref_d["down_btn"].visible:
					row_ref_d["down_btn"].grab_focus()
			"remove":
				# 找最近的移除按钮: 优先上方, 其次下方, 最后第一个加入按钮
				var bridge = _get_bridge()
				var priority = _get_priority_array(bridge) if bridge else []
				var focus_done := false
				if _pending_remove_idx < priority.size():
					var neighbor_stat: String = priority[_pending_remove_idx]
					var nr = _priority_rows.get(neighbor_stat)
					if nr and nr["remove_btn"] and nr["remove_btn"].visible:
						nr["remove_btn"].grab_focus()
						focus_done = true
				if not focus_done and priority.size() > 0:
					var last_stat: String = priority[priority.size() - 1]
					var lr = _priority_rows.get(last_stat)
					if lr and lr["remove_btn"] and lr["remove_btn"].visible:
						lr["remove_btn"].grab_focus()
						focus_done = true
				if not focus_done:
					# 没有优先项了, 回到第一个加入按钮
					_grab_first_add_button()
			"add":
				# 焦点到新加入行的 up 按钮
				var ar = _priority_rows.get(_pending_focus_stat)
				if ar and ar["up_btn"] and ar["up_btn"].visible:
					ar["up_btn"].grab_focus()
				else:
					_grab_first_add_button()
		_pending_focus_stat = ""
		_pending_focus_action = ""
		_pending_remove_idx = -1
		return
	var first := _find_first_focusable_in(self)
	if first:
		first.grab_focus()


func _grab_first_add_button() -> void:
	for child in _unprioritized_vbox.get_children():
		if child is HBoxContainer and not child.is_queued_for_deletion():
			for c in child.get_children():
				if c is Button and c.name == "AddToPriorityBtn" and c.visible and not c.is_queued_for_deletion():
					c.grab_focus()
					return
	var first := _find_first_focusable_in(self)
	if first:
		first.grab_focus()


func _find_first_focusable_in(from: Node) -> Control:
	for child in from.get_children():
		if child is Control:
			var ctrl: Control = child as Control
			if ctrl.focus_mode == Control.FOCUS_ALL and ctrl.visible and not ctrl.is_queued_for_deletion():
				return ctrl
		var found := _find_first_focusable_in(child)
		if found:
			return found
	return null


func _refresh_priority_ui(priority: Array, bridge) -> void:
	# 先 remove_child 立即摘除旧节点, 再 queue_free 释放对象.
	# 原因: Godot 3 帧内 MessageQueue flush (执行 call_deferred) 先于 _flush_delete_queue
	# (真正释放 queue_free 节点), 所以 _refresh 末尾的 call_deferred(_grab_focus_after_refresh)
	# 执行时, 旧节点仍在树里 — 会干扰焦点恢复 (grab 到即将释放的按钮, 释放后焦点丢失).
	# remove_child 让旧节点立即脱离父节点, get_children() 不再返回它. 对齐 vanilla
	# coop_player_selector.gd:7-8 的同一模式.
	for child in _priority_vbox.get_children():
		_priority_vbox.remove_child(child)
		child.queue_free()
	for child in _unprioritized_vbox.get_children():
		_unprioritized_vbox.remove_child(child)
		child.queue_free()
	_priority_rows.clear()

	var primary_stats = _get_primary_stats()

	# 已优先行
	for i in priority.size():
		var sk: String = priority[i]
		var row := HBoxContainer.new()
		row.rect_min_size.y = 28

		var name_label := Label.new()
		name_label.text = "%d. %s" % [i + 1, _stat_names.get(sk, sk)]
		name_label.valign = Label.VALIGN_CENTER
		name_label.size_flags_horizontal = SIZE_EXPAND_FILL
		name_label.clip_text = true
		row.add_child(name_label)

		var up_btn := Button.new()
		up_btn.text = "⬆"
		up_btn.rect_min_size = Vector2(24, 24)
		up_btn.disabled = (i <= 0)
		up_btn.focus_mode = Control.FOCUS_ALL
		up_btn.connect("pressed", self, "_on_priority_up", [sk])
		row.add_child(up_btn)

		var down_btn := Button.new()
		down_btn.text = "⬇"
		down_btn.rect_min_size = Vector2(24, 24)
		down_btn.disabled = (i >= priority.size() - 1)
		down_btn.focus_mode = Control.FOCUS_ALL
		down_btn.connect("pressed", self, "_on_priority_down", [sk])
		row.add_child(down_btn)

		var remove_btn := Button.new()
		remove_btn.text = tr("AUTOTATO_REMOVE")
		remove_btn.rect_min_size = Vector2(48, 24)
		remove_btn.focus_mode = Control.FOCUS_ALL
		remove_btn.connect("pressed", self, "_on_priority_remove", [sk])
		row.add_child(remove_btn)

		_priority_vbox.add_child(row)
		_priority_rows[sk] = {"row": row, "up_btn": up_btn, "down_btn": down_btn, "remove_btn": remove_btn}

	# 未优先行
	for sk in primary_stats:
		if priority.has(sk):
			continue
		var row := HBoxContainer.new()
		row.rect_min_size.y = 26

		var name_label := Label.new()
		name_label.text = _stat_names.get(sk, sk)
		name_label.valign = Label.VALIGN_CENTER
		name_label.size_flags_horizontal = SIZE_EXPAND_FILL
		name_label.clip_text = true
		row.add_child(name_label)

		var add_btn := Button.new()
		add_btn.name = "AddToPriorityBtn"
		add_btn.text = tr("AUTOTATO_ADD_TO_PRIORITY")
		add_btn.rect_min_size = Vector2(72, 24)
		add_btn.focus_mode = Control.FOCUS_ALL
		add_btn.connect("pressed", self, "_on_priority_add", [sk])
		row.add_child(add_btn)

		_unprioritized_vbox.add_child(row)


# ============================================================================
# 事件处理
# ============================================================================

func _on_respect_toggled(pressed: bool) -> void:
	var bridge = _get_bridge()
	if bridge:
		bridge.set_upgrade_respect_thresholds(pressed)


func _on_min_tier_changed(idx: int) -> void:
	var bridge = _get_bridge()
	if bridge:
		bridge.set_upgrade_config("min_tier", idx)


func _on_quality_toggled(pressed: bool) -> void:
	var bridge = _get_bridge()
	if bridge:
		bridge.set_upgrade_config("quality_first", pressed)


func _on_ignore_forbid_toggled(pressed: bool) -> void:
	var bridge = _get_bridge()
	if bridge:
		bridge.set_upgrade_config("ignore_forbid_on_stuck", pressed)


func _on_forbid_toggled(_pressed: bool, _stat_key: String) -> void:
	if _refreshing:
		return
	var bridge = _get_bridge()
	if bridge == null:
		return
	var new_list := []
	for sk in _forbid_checkboxes:
		if _forbid_checkboxes[sk].pressed:
			new_list.append(sk)
	bridge.set_upgrade_forbid_stats(new_list)


func _on_priority_up(stat_key: String) -> void:
	var bridge = _get_bridge()
	if bridge == null:
		return
	var priority = _get_priority_array(bridge)
	var idx = priority.find(stat_key)
	if idx <= 0:
		return
	var tmp = priority[idx]
	priority[idx] = priority[idx - 1]
	priority[idx - 1] = tmp
	bridge.set_upgrade_priority(priority)
	_pending_focus_stat = stat_key
	_pending_focus_action = "up"
	_refresh()


func _on_priority_down(stat_key: String) -> void:
	var bridge = _get_bridge()
	if bridge == null:
		return
	var priority = _get_priority_array(bridge)
	var idx = priority.find(stat_key)
	if idx < 0 or idx >= priority.size() - 1:
		return
	var tmp = priority[idx]
	priority[idx] = priority[idx + 1]
	priority[idx + 1] = tmp
	bridge.set_upgrade_priority(priority)
	_pending_focus_stat = stat_key
	_pending_focus_action = "down"
	_refresh()


func _on_priority_remove(stat_key: String) -> void:
	var bridge = _get_bridge()
	if bridge == null:
		return
	var priority = _get_priority_array(bridge)
	_pending_remove_idx = priority.find(stat_key)
	priority.erase(stat_key)
	bridge.set_upgrade_priority(priority)
	_pending_focus_stat = stat_key
	_pending_focus_action = "remove"
	_refresh()


func _on_priority_add(stat_key: String) -> void:
	var bridge = _get_bridge()
	if bridge == null:
		return
	var priority = _get_priority_array(bridge)
	if not priority.has(stat_key):
		priority.append(stat_key)
	bridge.set_upgrade_priority(priority)
	_pending_focus_stat = stat_key
	_pending_focus_action = "add"
	_refresh()


# ============================================================================
# Helpers
# ============================================================================

func _get_bridge():
	return _Config.get_instance()


func _get_priority_array(bridge) -> Array:
	var upg = bridge.get_upgrade_config()
	var priority = upg.get("stat_priority", [])
	if typeof(priority) != TYPE_ARRAY:
		priority = []
	return priority


func _get_primary_stats() -> Array:
	var result := []
	if typeof(ItemService) != TYPE_OBJECT:
		return result
	var stats = ItemService.get("stats")
	if typeof(stats) != TYPE_ARRAY:
		return result
	for stat in stats:
		if stat.get("is_primary_stat") == true:
			var sn: String = stat.get("stat_name")
			if sn != "":
				result.append(sn)
	return result
