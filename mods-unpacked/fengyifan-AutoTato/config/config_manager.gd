extends Reference

# ============================================================================
# AutoTato — Config Manager (新配置层 v1 持久化 helper)
# ----------------------------------------------------------------------------
# 职责:
#   读写 user://fengyifan-AutoTato/config.json, 并把磁盘配置更新为当前默认
#   schema。此文件是无状态 helper, 不持有运行时配置, 不负责业务 getter / setter。
#
# 版本策略:
#   新配置层从 v1 重新开始。version 不匹配时不做旧 Bridge 配置字段级迁移,
#   直接使用默认配置作为基座。旧路径 user://AutoTato/session_config.json 的
#   一次性位置迁移由 config/migration/ 调度器负责 (load_config 入口先于读取执行);
#   字段级补缺由 _merge_with_defaults 递归完成。
#
# 写入策略:
#   先写 config.json.tmp, 关闭文件后再 rename 到 config.json。读者要么看到旧的
#   完整配置, 要么看到新的完整配置, 不会读到半截 JSON。
# ============================================================================

const _Logger = preload("res://mods-unpacked/fengyifan-AutoTato/utils/logger.gd")
const _IO = preload("res://mods-unpacked/fengyifan-AutoTato/utils/io.gd")
const _Migrator = preload("res://mods-unpacked/fengyifan-AutoTato/config/migration/migrator.gd")

const _LOG_NAME := "ConfigManager"

const _CONFIG_DIR_NAME := "fengyifan-AutoTato"
const _CONFIG_FILE_NAME := "config.json"
const _CONFIG_TMP_FILE_NAME := "config.json.tmp"

# 防御恶意手编超深嵌套 dict 导致递归 merge 栈过深。
const _MAX_MERGE_DEPTH := 8

# ============================================================================
# 路径 helpers
# ============================================================================

static func config_dir_path() -> String:
	return "user://".plus_file(_CONFIG_DIR_NAME)

static func config_path() -> String:
	return config_dir_path().plus_file(_CONFIG_FILE_NAME)

static func tmp_config_path() -> String:
	return config_dir_path().plus_file(_CONFIG_TMP_FILE_NAME)

# ============================================================================
# 主入口
# ============================================================================

static func load_config(default_config: Dictionary) -> Dictionary:
	var path := config_path()
	var file := File.new()

	# 迁移: 位置迁移 (session_config -> config) + 版本迁移链 (v1->v2->...)
	# 必须在 file_exists 之前, 位置迁移可能产生新文件供后续读取。
	_Migrator.run(path)

	if not file.file_exists(path):
		_Logger.info("配置文件不存在, 使用默认配置: %s" % path, _LOG_NAME)
		return default_config.duplicate(true)

	var err := file.open(path, File.READ)
	if err != OK:
		_Logger.warning("打开配置文件失败, 使用默认配置 err=%d path=%s" % [err, path], _LOG_NAME)
		return default_config.duplicate(true)

	var content: String = file.get_as_text()
	file.close()

	if content.strip_edges() == "":
		_Logger.warning("配置文件为空, 使用默认配置: %s" % path, _LOG_NAME)
		return default_config.duplicate(true)

	var parse_result := JSON.parse(content)
	if parse_result.error != OK:
		_Logger.warning("配置解析失败, 使用默认配置: %s (line %d, path=%s)" % [parse_result.error_string, parse_result.error_line, path], _LOG_NAME)
		return default_config.duplicate(true)

	if typeof(parse_result.result) != TYPE_DICTIONARY:
		_Logger.warning("配置解析失败, 使用默认配置: 顶层类型错误 type=%d" % typeof(parse_result.result), _LOG_NAME)
		return default_config.duplicate(true)

	var updated := update_config(default_config, parse_result.result)
	_Logger.info("配置加载成功 path=%s version=%d 顶层 keys=%d" % [path, int(updated.get("version", 0)), updated.size()], _LOG_NAME)
	return updated

static func save_config(config: Dictionary) -> bool:
	var real_path := config_path()
	var tmp_path := tmp_config_path()

	if not _IO.ensure_dir(config_dir_path(), _LOG_NAME):
		return false

	var json_text := JSON.print(config, "  ")
	if not _IO.write_file(tmp_path, json_text, _LOG_NAME):
		return false

	if not _IO.rename_atomic(tmp_path, real_path, _LOG_NAME):
		_Logger.error("配置保存失败, 保留临时配置文件供下次重试: %s" % tmp_path, _LOG_NAME)
		return false

	_Logger.info("配置保存成功 path=%s 大小=%d 字节" % [real_path, json_text.length()], _LOG_NAME)
	return true

# 把磁盘配置更新为当前 schema。
# 新配置层从 v1 开始；version 不匹配时回到默认配置, 不执行旧字段迁移。
# version 匹配时保留玩家配置, 再递归补齐新增默认字段。
static func update_config(default_config: Dictionary, parsed_config: Dictionary) -> Dictionary:
	var current_version := int(default_config.get("version", 1))
	var parsed_version := int(parsed_config.get("version", 0))
	var config: Dictionary

	if parsed_version != current_version:
		_Logger.warning("配置版本不匹配 parsed=%d current=%d, 使用默认配置后补齐字段" % [parsed_version, current_version], _LOG_NAME)
		config = default_config.duplicate(true)
	else:
		config = parsed_config.duplicate(true)

	var updated := _merge_with_defaults(config, default_config, 0)
	updated["version"] = current_version
	return updated

# ============================================================================
# Schema 补缺核心
# ----------------------------------------------------------------------------
# 递归合并 parsed 与 defaults。规则:
#   - parsed 有 key + 都是 Dict → 递归合并
#   - parsed 有 key + 类型不同 / 非 Dict → 保留 parsed 值
#   - parsed 缺 key → 使用 defaults 深拷贝
#   - parsed 多余 key → 保留
# ============================================================================

static func _merge_with_defaults(parsed: Dictionary, defaults: Dictionary, depth: int) -> Dictionary:
	var result := parsed.duplicate(true)
	if depth >= _MAX_MERGE_DEPTH:
		_Logger.warning("merge 深度超限 (%d), 停止递归" % _MAX_MERGE_DEPTH, _LOG_NAME)
		return result

	for key in defaults:
		if not result.has(key):
			result[key] = _deep_copy_value(defaults[key])
		elif typeof(result[key]) == TYPE_DICTIONARY and typeof(defaults[key]) == TYPE_DICTIONARY:
			result[key] = _merge_with_defaults(result[key], defaults[key], depth + 1)
	return result

static func _deep_copy_value(value):
	if typeof(value) == TYPE_DICTIONARY:
		return (value as Dictionary).duplicate(true)
	elif typeof(value) == TYPE_ARRAY:
		return (value as Array).duplicate(true)
	return value
