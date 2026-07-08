extends Reference

# ============================================================================
# AutoTato - 位置迁移: session_config.json -> config.json
# ----------------------------------------------------------------------------
# 特殊迁移: 不依赖配置版本号, 仅凭文件位置判断。
#
# 触发条件 (三者同时满足):
#   1. 新配置 user://fengyifan-AutoTato/config.json 不存在
#   2. 旧配置 user://AutoTato/session_config.json 存在
#   3. 旧配置可成功 JSON 解析
#
# 这是一次性迁移: 命中"首次从旧版 mod 升级到新版的玩家"。
# 迁移成功后删除旧文件, 保证单一数据源 (避免旧版 mod 残留启动时与新配置混淆)。
#
# 版本改写: 旧版 schema_version=7, 新配置层从 v1 起步。
#   迁移时把 version 改写为 1, 字段层面新旧几乎一致 (唯一新增字段
#   general.decision_step_delay 由 config_manager._merge_with_defaults 补齐)。
# ============================================================================

const _Logger = preload("res://mods-unpacked/fengyifan-AutoTato/utils/logger.gd")
const _IO = preload("res://mods-unpacked/fengyifan-AutoTato/utils/io.gd")

const _LOG_NAME := "ConfigMigration:SessionToConfig"

# 旧版遗留路径 (与 config_manager.gd 注释中提到的历史路径一致)
const _LEGACY_DIR := "user://AutoTato"
const _LEGACY_FILE_NAME := "session_config.json"
const _LEGACY_CONFIG_TMP_FILE_NAME := "session_config.json.tmp"

# 新配置层起步版本。旧版 schema_version=7 在新体系里是非法值, 必须在搬运时改写。
const _NEW_VERSION := 1

# ============================================================================
# 主入口
# ============================================================================

# 返回 true 表示已执行迁移 (新文件已产生); false 表示未触发或迁移失败。
# 由 migrator.gd 在 config_manager.load_config 读取前调用。
static func try_migrate(new_config_path: String) -> bool:
	var legacy_path := legacy_config_path()
	var file := File.new()

	# 哨兵 1: 新文件已存在 -> 非首次升级, 不迁移
	if file.file_exists(new_config_path):
		return false
	# 哨兵 2: 旧文件不存在 -> 全新玩家, 不迁移
	if not file.file_exists(legacy_path):
		return false

	_Logger.info("检测到旧配置, 启动位置迁移 %s -> %s" % [legacy_path, new_config_path], _LOG_NAME)

	# _read_and_parse 返回 Dictionary 或 null (可空), 无法用 := 推断, 用弱类型变量。
	var parsed = _read_and_parse(legacy_path)
	if parsed == null:
		# 旧文件损坏, 保留供玩家手动恢复, 不阻断加载 (走默认值)
		_Logger.warning("旧配置解析失败, 跳过迁移, 保留旧文件: %s" % legacy_path, _LOG_NAME)
		return false

	var migrated := _transform(parsed)
	if not _write_atomic(new_config_path, migrated):
		# 写失败, 保留旧文件供下次重试
		_Logger.warning("迁移写入失败, 保留旧文件供下次重试: %s" % legacy_path, _LOG_NAME)
		return false

	_Logger.info("位置迁移成功, 删除旧配置文件: %s" % legacy_path, _LOG_NAME)
	_delete_legacy_file(legacy_path)
	return true

# ============================================================================
# 路径 helpers
# ============================================================================

static func legacy_config_path() -> String:
	return _LEGACY_DIR.plus_file(_LEGACY_FILE_NAME)

# ============================================================================
# 读取 + 解析
# ============================================================================

# 读取旧文件并 JSON 解析。失败返回 null。
static func _read_and_parse(path: String):
	var file := File.new()
	var err := file.open(path, File.READ)
	if err != OK:
		_Logger.warning("打开旧配置失败 err=%d path=%s" % [err, path], _LOG_NAME)
		return null

	var content: String = file.get_as_text()
	file.close()

	if content.strip_edges() == "":
		_Logger.warning("旧配置为空, 跳过迁移: %s" % path, _LOG_NAME)
		return null

	var parse_result := JSON.parse(content)
	if parse_result.error != OK:
		_Logger.warning("旧配置解析失败 (line %d): %s" % [parse_result.error_line, path], _LOG_NAME)
		return null

	if typeof(parse_result.result) != TYPE_DICTIONARY:
		_Logger.warning("旧配置顶层类型错误 type=%d, 跳过迁移" % typeof(parse_result.result), _LOG_NAME)
		return null

	return parse_result.result

# ============================================================================
# v7 -> v1 字段变换
# ----------------------------------------------------------------------------
# 当前两版 schema 几乎一致, 此处只做:
#   1. version 改写 7 -> 1 (旧值在新体系为非法, 必须修正)
#   2. 字段层面不做映射 / 补缺 - 补缺交给 config_manager._merge_with_defaults
# 未来若有真实字段差异 (重命名 / 结构变化), 在此函数扩展。
# ============================================================================

static func _transform(legacy: Dictionary) -> Dictionary:
	var out: Dictionary = legacy.duplicate(true)
	out["version"] = _NEW_VERSION
	_log_summary(out)
	return out

static func _log_summary(config: Dictionary) -> void:
	var item_rules: Dictionary = config.get("item_rules", {})
	var weapon_rules: Dictionary = config.get("weapon_rules", {})
	var weapon_category_rules: Dictionary = config.get("weapon_category_rules", {})
	var thresholds: Dictionary = config.get("thresholds", {})
	_Logger.info("迁移摘要: item_rules=%d weapon_rules=%d weapon_category_rules=%d thresholds=%d" % [
		item_rules.size(), weapon_rules.size(), weapon_category_rules.size(), thresholds.size(),
	], _LOG_NAME)

# ============================================================================
# 原子写 (与 config_manager.gd 同款 tmp + rename 策略)
# ============================================================================

static func _write_atomic(new_config_path: String, config: Dictionary) -> bool:
	var dir_path := new_config_path.get_base_dir()
	if not _IO.ensure_dir(dir_path, _LOG_NAME):
		return false

	var json_text := JSON.print(config, "  ")
	var tmp_path := new_config_path + ".tmp"
	if not _IO.write_file(tmp_path, json_text, _LOG_NAME):
		return false

	if not _IO.rename_atomic(tmp_path, new_config_path, _LOG_NAME):
		_Logger.error("迁移 rename 失败, 保留临时文件: %s" % tmp_path, _LOG_NAME)
		return false

	return true

# ============================================================================
# 删除旧文件 (单一数据源)
# ----------------------------------------------------------------------------
# 迁移主体已成功 (新文件已写入), 删除旧文件失败仅警告不阻断。
# 失败时玩家可手动删除, 不影响新配置加载。
# ============================================================================

static func _delete_legacy_file(path: String) -> void:
	var dir := Directory.new()
	var err := dir.remove(path)
	if err != OK:
		_Logger.warning("删除旧配置文件失败 err=%d path=%s (可手动删除)" % [err, path], _LOG_NAME)
