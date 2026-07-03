const _LOG_NAME_PREFIX = "fengyifan-AutoTato"

static func _get_full_log_tag(module):
	return "%s:%s" % [_LOG_NAME_PREFIX, module]

static func info(msg: String, module: String = "unknow"):
	if typeof(ModLoaderLog) != TYPE_NIL:
		ModLoaderLog.info(msg, _get_full_log_tag(module))

static func warning(msg: String, module: String = "unknow"):
	if typeof(ModLoaderLog) != TYPE_NIL:
		ModLoaderLog.warning(msg, _get_full_log_tag(module))

static func error(msg: String, module: String = "unknow"):
	if typeof(ModLoaderLog) != TYPE_NIL:
		ModLoaderLog.error(msg, _get_full_log_tag(module))