extends "res://ui/menus/title_screen/title_screen.gd"

# ============================================================================
# AutoTato - title_screen Script Extension
# ----------------------------------------------------------------------------
# hook vanilla 主菜单 (title_screen.gd), 进主界面时判断是否弹更新说明。
#
# 触发逻辑 (零版本号比较):
#   1. 取 changelog.json 的 latest 字段 (发版者手写的"应弹版本")
#   2. 读本地 changelog_state.txt (上次关闭弹窗的版本号, 不存在 = "")
#   3. latest != last_seen -> 弹 latest 对应内容; 相等则不弹
#   4. 用户点"不再展示"或 ESC -> latest 写入本地 txt (该版本不再弹)
#
# 时序: vanilla title_screen._ready() 末尾 (line 45-49) 可能已 popup 它自己的
# mod 更新警告。这里 call_deferred 推迟一帧, 避免两个弹窗同帧抢焦点快照
# (get_focus_owner() 会拿到错的 owner)。
#
# 面板挂载: 挂到 get_tree().get_root() (顶层 viewport), 不污染主菜单节点树,
# 层级高于 title_screen 的普通 Control。title_screen 非暂停态, 无需 PAUSE_MODE_PROCESS。
# ============================================================================


const LOG_NAME := "fengyifan-AutoTato:TitleScreenHook"

const PATH_CHANGELOG_POPUP := "res://mods-unpacked/fengyifan-AutoTato/ui/changelog_popup.tscn"
const _ChangelogData = preload("res://mods-unpacked/fengyifan-AutoTato/ui/changelog_data.gd")
const _ChangelogState = preload("res://mods-unpacked/fengyifan-AutoTato/ui/changelog_state.gd")

var _changelog_popup: Popup = null
var _changelog_data := _ChangelogData.new()


func _ready() -> void:
	._ready()  # 调 vanilla 父类 (含它自己的公告弹窗逻辑)
	# 推迟一帧, 让 vanilla 自己的 popup 先完成焦点快照
	call_deferred("_autotato_maybe_show_changelog")


# ----------------------------------------------------------------------------
# AutoTato 流程
# ----------------------------------------------------------------------------

func _autotato_maybe_show_changelog() -> void:
	var latest := _changelog_data.get_latest_version()
	if latest == "":
		return  # JSON 加载失败或无 latest, 静默
	var last_seen := _ChangelogState.get_last_seen_version()
	if latest == last_seen:
		return  # 已关闭过此版本, 不弹
	var body := _changelog_data.get_body(latest)
	if body == "":
		return  # latest 在 JSON 里无内容, 静默 (防御)
	_ensure_popup()
	_changelog_popup.show_for(latest, body)
	_log("Changelog 弹窗已显示: %s" % latest)


func _ensure_popup() -> void:
	if _changelog_popup != null:
		return
	var scene = load(PATH_CHANGELOG_POPUP)
	if scene == null:
		_log("无法 load changelog_popup.tscn: %s" % PATH_CHANGELOG_POPUP)
		return
	_changelog_popup = scene.instance()
	get_tree().get_root().add_child(_changelog_popup)
	_changelog_popup.connect("dont_show_requested", self, "_on_changelog_dont_show")


func _on_changelog_dont_show() -> void:
	var latest := _changelog_data.get_latest_version()
	_ChangelogState.set_last_seen_version(latest)
	_log("用户已 dismiss changelog: %s" % latest)


func _log(msg: String) -> void:
	if typeof(ModLoaderLog) != TYPE_NIL:
		ModLoaderLog.info(msg, LOG_NAME)
