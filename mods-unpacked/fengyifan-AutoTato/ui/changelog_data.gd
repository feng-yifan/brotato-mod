extends Reference

# ============================================================================
# AutoTato - Changelog Data (只读数据加载器)
# ----------------------------------------------------------------------------
# 加载 res:// 下的 data/changelog.json, 提供:
#   - get_latest_version(): 返回 JSON 的 latest 字段 (发版者手写的"应弹版本")
#   - get_body(version):   返回指定版本的本地化富文本 (BBCode)
#
# 语言匹配 (TranslationServer.get_locale() 与 tr() 同源, 反映游戏内语言设置,
# 而非 OS.get_locale() 那样的系统区域。返回如 "zh" / "en" / "zh_TW"):
#   1. 精确匹配 locale key
#   2. 前缀匹配 (zh_TW -> zh)
#   3. 兜底 "default"
#
# 设计要点:
#   - changelog.json 是只读资源 (打包进 PCK 后 res:// 只读), 运行时绝不写它
#   - 解析结果缓存在实例上, 避免每次进主菜单重复读盘
#   - 任何加载/解析失败都静默降级 (get_latest_version 返回 "", 调用方据此跳过弹窗)
# ============================================================================

const CHANGELOG_PATH := "res://mods-unpacked/fengyifan-AutoTato/data/changelog.json"
const _Logger = preload("res://mods-unpacked/fengyifan-AutoTato/utils/logger.gd")

const _LOG_NAME := "ChangelogData"

var _cache: Dictionary = {}
var _loaded: bool = false


# 加载并缓存 JSON; 失败时 _cache 保持空 Dictionary, _loaded 置 true 避免重试
func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var f := File.new()
	if f.open(CHANGELOG_PATH, File.READ) != OK:
		_Logger.warning("无法打开 changelog.json: %s" % CHANGELOG_PATH, _LOG_NAME)
		return
	var content := f.get_as_text()
	f.close()
	var parsed = JSON.parse(content)
	if parsed.error != OK:
		_Logger.warning(
			"changelog.json 解析失败 (line %d): %s" % [parsed.error_line, parsed.error_string],
			_LOG_NAME)
		return
	if not parsed.result is Dictionary:
		_Logger.warning("changelog.json 顶层不是 Dictionary", _LOG_NAME)
		return
	_cache = parsed.result


# 返回 JSON 的 latest 版本号; 加载失败或无 latest 返回 "" (调用方据此跳过弹窗)
func get_latest_version() -> String:
	_load()
	return _cache.get("latest", "")


# 返回指定版本的本地化富文本; 版本不存在或无可用语言返回 ""
func get_body(version: String) -> String:
	_load()
	var entry = _cache.get(version, {})
	if not entry is Dictionary:
		return ""
	# 读游戏内语言 (与 tr() 同源); 玩家在 Brotato 设置里切语言改的是
	# TranslationServer locale, 而非 OS.get_locale() 那样的系统区域。
	var locale := TranslationServer.get_locale()
	# 1. 精确匹配 (如 "zh_TW")
	if entry.has(locale):
		return String(entry[locale])
	# 2. 前缀匹配 (zh_TW 没有 -> 取 "zh")
	for key in entry.keys():
		if key == "default":
			continue
		if locale.begins_with(String(key)):
			return String(entry[key])
	# 3. 兜底 default
	if entry.has("default"):
		return String(entry["default"])
	return ""
