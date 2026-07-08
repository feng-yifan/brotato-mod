extends Reference

# ============================================================================
# AutoTato - Config Migration 调度器
# ----------------------------------------------------------------------------
# 职责: 按固定顺序执行两类迁移
#   1. 位置迁移 (跨路径, 一次性, 不依赖版本): session_config.json -> config.json
#   2. 版本迁移链 (同路径, 依赖 version): v1->v2->v3->...
#
# 调用时机: config_manager.load_config 在 file_exists 检查前调用一次。
# 顺序不可颠倒: 位置迁移可能产生新文件, 版本链读取新文件 version, 必须先完成位置迁移。
#
# 版本迁移注册:
#   _VERSION_MIGRATIONS 按 from 升序排列, 调度器从当前 version 开始依次执行。
#   新增版本迁移只需:
#     1. 新建 config/migration/vN_to_vM.gd, 实现 static func migrate(config) -> Dictionary
#     2. 在下方数组追加一条 {from, to, step}
# ============================================================================

const _Logger = preload("res://mods-unpacked/fengyifan-AutoTato/utils/logger.gd")
const _IO = preload("res://mods-unpacked/fengyifan-AutoTato/utils/io.gd")
const _SessionToConfig = preload("res://mods-unpacked/fengyifan-AutoTato/config/migration/session_config_to_config.gd")

const _LOG_NAME := "ConfigMigrator"

# 版本迁移链 (按 from 升序)。
# 当前为空: 新配置层起步于 v1, 暂无版本迁移。未来 schema 升级时在此追加。
# 示例:
#   const _V1ToV2 = preload("res://mods-unpacked/fengyifan-AutoTato/config/migration/v1_to_v2.gd")
#   const _VERSION_MIGRATIONS := [
#       {from: 1, to: 2, step: _V1ToV2},
#   ]
const _VERSION_MIGRATIONS := []

# ============================================================================
# 主入口
# ============================================================================

# 由 config_manager.load_config 调用。
# path = 新配置路径 (user://fengyifan-AutoTato/config.json)
static func run(path: String) -> void:
	# 1. 位置迁移 (一次性, 可能产生新文件)
	_SessionToConfig.try_migrate(path)

	# 2. 版本迁移链 (读取当前 version, 依次推进)
	_run_version_chain(path)

# ============================================================================
# 版本迁移链
# ----------------------------------------------------------------------------
# 读文件 -> 取 version -> 执行匹配的 step -> 写回 -> 循环至无匹配。
# 每个 step.migrate(config) 负责把 config 从 from 版本升到 to 版本,
# 并把 config["version"] 改写为 to。
# ============================================================================

static func _run_version_chain(path: String) -> void:
	if _VERSION_MIGRATIONS.empty():
		return

	var file := File.new()
	if not file.file_exists(path):
		return

	# _read_and_parse 返回 Dictionary 或 null (可空), 无法用 := 推断, 用弱类型变量。
	var config = _read_and_parse(path)
	if config == null:
		return

	var current := int(config.get("version", 0))
	var changed := false

	for entry in _VERSION_MIGRATIONS:
		var from := int(entry.get("from", -1))
		var to := int(entry.get("to", -1))
		if current != from:
			continue
		var step = entry.get("step", null)
		if step == null:
			continue
		config = step.migrate(config)
		current = int(config.get("version", to))
		changed = true
		_Logger.info("版本迁移 v%d->v%d 完成" % [from, to], _LOG_NAME)

	if changed:
		_write_atomic(path, config)

# ============================================================================
# helpers (读取 / 写入, 与 session_config_to_config.gd 同款)
# ============================================================================

static func _read_and_parse(path: String):
	var file := File.new()
	var err := file.open(path, File.READ)
	if err != OK:
		_Logger.warning("版本迁移: 打开配置失败 err=%d path=%s" % [err, path], _LOG_NAME)
		return null

	var content: String = file.get_as_text()
	file.close()

	var parse_result := JSON.parse(content)
	if parse_result.error != OK or typeof(parse_result.result) != TYPE_DICTIONARY:
		_Logger.warning("版本迁移: 配置解析失败, 跳过 path=%s" % path, _LOG_NAME)
		return null
	return parse_result.result

static func _write_atomic(path: String, config: Dictionary) -> void:
	var dir_path := path.get_base_dir()
	var tmp_path := path + ".tmp"
	if not _IO.ensure_dir(dir_path, _LOG_NAME):
		return
	var json_text := JSON.print(config, "  ")
	if not _IO.write_file(tmp_path, json_text, _LOG_NAME):
		return
	if not _IO.rename_atomic(tmp_path, path, _LOG_NAME):
		_Logger.error("版本迁移: rename 失败, 保留临时文件: %s" % tmp_path, _LOG_NAME)
