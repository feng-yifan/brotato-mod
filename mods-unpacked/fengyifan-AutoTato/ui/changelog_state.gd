extends Reference

# ============================================================================
# AutoTato - Changelog State (本地状态读写)
# ----------------------------------------------------------------------------
# 读写 user://fengyifan-AutoTato/changelog_state.txt, 记录"上次关闭弹窗的版本号"。
#
# 文件格式: 单行版本号字符串 (如 "2.0.0"), 纯文本无 JSON 外壳。
#   - 读: get_last_seen_version() -> 文件不存在/读失败返回 ""
#   - 写: set_last_seen_version(v) -> 原子写 (.tmp + rename), 复用 utils/io.gd
#
# 与 mod 配置 (config.json) 完全解耦:
#   - 用户重置配置不会误清更新说明状态
#   - 反之, dismiss 一个版本不影响其它配置
#   - 路径与 config.json 同目录 (user://fengyifan-AutoTato/), 复用 ensure_dir
# ============================================================================

const STATE_DIR := "user://fengyifan-AutoTato"
const STATE_FILE_NAME := "changelog_state.txt"
const STATE_TMP_FILE_NAME := "changelog_state.txt.tmp"

const _IO = preload("res://mods-unpacked/fengyifan-AutoTato/utils/io.gd")
const _Logger = preload("res://mods-unpacked/fengyifan-AutoTato/utils/logger.gd")

const _LOG_NAME := "ChangelogState"


static func _state_path() -> String:
	return STATE_DIR.plus_file(STATE_FILE_NAME)


static func _tmp_path() -> String:
	return STATE_DIR.plus_file(STATE_TMP_FILE_NAME)


# 读上次关闭的版本号; 文件不存在/读失败返回 "" (视为从未 dismiss 过)
static func get_last_seen_version() -> String:
	var path := _state_path()
	var f := File.new()
	if not f.file_exists(path):
		return ""
	if f.open(path, File.READ) != OK:
		_Logger.warning("无法读取 changelog_state: %s" % path, _LOG_NAME)
		return ""
	var content := f.get_as_text()
	f.close()
	return content.strip_edges()


# 写入已关闭的版本号 (原子写: 先 .tmp 再 rename)
static func set_last_seen_version(version: String) -> void:
	if not _IO.ensure_dir(STATE_DIR, _LOG_NAME):
		return
	var tmp := _tmp_path()
	var real := _state_path()
	if not _IO.write_file(tmp, version, _LOG_NAME):
		return
	if not _IO.rename_atomic(tmp, real, _LOG_NAME):
		_Logger.error("changelog_state 写入失败, 保留临时文件: %s" % tmp, _LOG_NAME)
		return
	_Logger.info("changelog_state 已记录版本: %s" % version, _LOG_NAME)
