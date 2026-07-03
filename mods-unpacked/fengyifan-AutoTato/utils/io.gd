const _Logger = preload("res://mods-unpacked/fengyifan-AutoTato/utils/logger.gd")

const _LOG_NAME := "IO"

static func ensure_dir(dir_path: String, module: String = _LOG_NAME) -> bool:
	var dir := Directory.new()
	if dir.dir_exists(dir_path):
		return true

	var err := dir.make_dir_recursive(dir_path)
	if err != OK:
		_Logger.error("创建目录失败 path=%s err=%d" % [dir_path, err], module)
		return false

	_Logger.info("已创建目录: %s" % dir_path, module)
	return true

static func write_file(path: String, content: String, module: String = _LOG_NAME) -> bool:
	var file := File.new()
	var err := file.open(path, File.WRITE)
	if err != OK:
		_Logger.error("打开写入文件失败 path=%s err=%d" % [path, err], module)
		return false

	file.store_string(content)
	file.close()
	return true

static func rename_atomic(tmp_path: String, real_path: String, module: String = _LOG_NAME) -> bool:
	var dir := Directory.new()
	var err := dir.rename(tmp_path, real_path)
	if err != OK:
		_Logger.error("rename 失败 tmp=%s real=%s err=%d" % [tmp_path, real_path, err], module)
		return false
	return true
