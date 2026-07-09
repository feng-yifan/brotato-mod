extends Popup

# ============================================================================
# AutoTato - Changelog Popup (更新说明弹窗)
# ----------------------------------------------------------------------------
# 单按钮弹窗: "不再展示"。点按钮或按 ESC 都视为"已知晓", 写入本地记录,
# 该版本不再弹 (直到 changelog.json 的 latest 变化)。
#
# 标题/按钮文案走 tr() (固定 UI 文本, 进 csv 翻译管线); 正文走 JSON (发版才变)。
#
# 范式照搬 vanilla popup_anouncement.gd:
#   - popup() 时快照当前焦点, _close() 时恢复 (手柄用户不丢焦点)
#   - _input 拦截 ui_cancel, 与点按钮等价 (vanilla popup 同款语义)
#   - 正文 [center] 在 _ready 动态拼 (与 popup_anouncement.gd:10 一致)
#
# 注意: 主题在 .tscn 已挂 base_theme.tres, 这里不重复挂; 字体复用 vanilla
# font_32_outline (保证中文 glyph 覆盖, 与 popup_anouncement.tscn 同源)。
# ============================================================================

onready var _title_label: Label = $"%title_label"
onready var _rich_text: RichTextLabel = $"%rich_text_description"
onready var _btn_dont_show: Button = $"%DontShowButton"

var focus_before_created: Control = null

signal dont_show_requested


func _ready() -> void:
	# 按钮文案固定, 在 _ready 设; 标题含动态版本号, 在 show_for 里设
	_btn_dont_show.text = tr("AUTOTATO_CHANGELOG_DONT_SHOW")
	_btn_dont_show.connect("pressed", self, "_on_dont_show")


# 由 owner 调用: 填充标题(带版本号)与正文并居中弹出
func show_for(version: String, body: String) -> void:
	# 标题 = 固定文案 + 版本号, 如 "AutoTato 更新说明 · 2.0.0"
	_title_label.text = tr("AUTOTATO_CHANGELOG_TITLE") + " · " + version
	# [center] 动态拼, 与 popup_anouncement.gd:10 一致 (正文运行时来自 JSON)
	_rich_text.bbcode_text = "[center]" + body
	focus_before_created = get_focus_owner()
	popup_centered()
	if is_instance_valid(_btn_dont_show):
		_btn_dont_show.grab_focus()


func _input(event) -> void:
	if visible and event.is_action_released("ui_cancel"):
		_on_dont_show()
		get_tree().set_input_as_handled()


func _on_dont_show() -> void:
	emit_signal("dont_show_requested")
	_close()


func _close() -> void:
	if is_instance_valid(focus_before_created):
		focus_before_created.grab_focus()
	hide()
