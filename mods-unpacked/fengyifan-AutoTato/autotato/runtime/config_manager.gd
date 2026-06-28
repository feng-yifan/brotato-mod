extends Reference
class_name AT_ConfigManager

# ============================================================================
# AutoTato — Config Manager (配置持久化层)
# ----------------------------------------------------------------------------
# 职责:
#   把 Bridge 内存里的 _config dict 与磁盘 session_config.json 互相搬运. 只
#   暴露 load_config(defaults) / save_config(config) 两个静态入口, Bridge 调
#   一次完成读/写.
#
# 路径:
#   user://AutoTato/session_config.json
#   Brotato 运行时 user:// = ~/.local/share/Brotato/, 因此实际磁盘路径是
#   ~/.local/share/Brotato/AutoTato/session_config.json (CLAUDE.md 第 4 节
#   "AutoTato 配置文件" 约定的位置).
#
# 原子写策略:
#   先写 session_config.json.tmp, flush + close, 再 Directory.rename(tmp, real).
#   Godot 3 Directory.rename 是 POSIX rename(2) 的 wrapper, 同分区原子.
#   读者要么看到完整旧文件, 要么看到完整新文件, 不会撞上半截 JSON.
#
# Schema 迁移:
#   load 时递归 merge defaults 补缺字段 (玩家已配的永远不丢; mod 升级新增
#   字段也能自动补默认). 玩家手编多余字段保留, 类型不匹配时相信玩家.
#
# 损坏文件兜底:
#   读失败 / 文件空 / JSON parse 失败 / 顶层非 Dict → 一律返回 null.
#   调用方 (Bridge) 收到 null 后用 defaults 起手, 不让破文件阻塞 mod 启动.
#
# 设计取舍:
#   - 不感知 schema 细节: defaults 由 Bridge 单一注入, 这里保持哑.
#   - 静态类, 不持任何状态; hook 层不直接调, 只 Bridge 调.
#   - 不依赖 Bridge 或其它 P 阶段类 (纯独立 IO 层).
# ============================================================================


const LOG_NAME := "fengyifan-AutoTato:ConfigManager"
const CONFIG_DIR_NAME := "AutoTato"
const CONFIG_FILE_NAME := "session_config.json"
const TMP_SUFFIX := ".tmp"

# 防御恶意手编超深嵌套 dict 导致 _merge_with_defaults 栈溢出.
# 当前 schema 最深 2 层 (thresholds.<stat>.value), 留 8 层裕度足够.
const MAX_MERGE_DEPTH := 8


# ============================================================================
# 路径 helpers
# ============================================================================

# 拼路径: user://AutoTato/session_config.json
static func get_config_path() -> String:
	return "user://".plus_file(CONFIG_DIR_NAME).plus_file(CONFIG_FILE_NAME)


# 临时文件路径 (原子写)
static func get_tmp_path() -> String:
	return get_config_path() + TMP_SUFFIX


# 目录路径 (mkdir 用)
static func get_config_dir() -> String:
	return "user://".plus_file(CONFIG_DIR_NAME)


# ============================================================================
# 主入口
# ============================================================================

# 从磁盘读取 config 并与 defaults 递归合并 (缺字段补默认).
# 返回:
#   Dictionary: 成功 (合并后的完整 config; 文件不存在时返回 defaults 深拷贝)
#   null:       异常 (调用方应用 defaults 起始, 不阻塞 mod 启动)
static func load_config(defaults: Dictionary):
	var path: String = get_config_path()
	var file = File.new()

	# 1. 文件不存在 = 首次启动, 不是错误
	if not file.file_exists(path):
		_log("config 文件不存在, 使用默认 config (首次启动): %s" % path)
		return defaults.duplicate(true)

	# 2. 打开
	var err = file.open(path, File.READ)
	if err != OK:
		_log_error("打开 config 失败 path=%s err=%d" % [path, err])
		return null
	var content: String = file.get_as_text()
	file.close()

	# 3. 空文件
	if content.strip_edges() == "":
		_log_error("config 文件为空 path=%s" % path)
		return null

	# 4. JSON parse
	var parse_result = JSON.parse(content)
	if parse_result.error != OK:
		_log_error("config JSON parse 失败: %s (line %d, path=%s)" % [parse_result.error_string, parse_result.error_line, path])
		return null

	# 5. 顶层类型必须 Dict
	if typeof(parse_result.result) != TYPE_DICTIONARY:
		_log_error("config 顶层不是 Dictionary, 实得 type=%d" % typeof(parse_result.result))
		return null

	# 6. 递归合并 defaults 补缺字段
	var merged: Dictionary = _merge_with_defaults(parse_result.result, defaults, 0)

	# 7. 后处理: v6/v6.1 → v7 schema 迁移
	_migrate_v6_to_v7(merged)

	_log("config 加载成功 path=%s 顶层 keys=%d" % [path, merged.size()])
	return merged


# 把 config 原子写入磁盘. 返回 true 成功 / false 失败.
# 任意步失败保留 .tmp 文件, 下次 save 会覆盖, 不污染 real 文件.
static func save_config(config: Dictionary) -> bool:
	var real_path: String = get_config_path()
	var tmp_path: String = get_tmp_path()

	# 1. mkdir -p
	if not _ensure_dir(get_config_dir()):
		return false

	# 2. 写 tmp 文件 (JSON.print 第 2 参是 indent 字符串, 2 空格便于玩家手编)
	var json_text: String = JSON.print(config, "  ")
	if not _write_file(tmp_path, json_text):
		return false

	# 3. 原子 rename
	if not _rename_atomic(tmp_path, real_path):
		_log_error("rename 失败, 保留 .tmp 文件供下次重试: %s" % tmp_path)
		return false

	_log("config 保存成功 path=%s 大小=%d 字节" % [real_path, json_text.length()])
	return true


# ============================================================================
# Schema 迁移核心
# ----------------------------------------------------------------------------
# 递归合并 parsed 与 defaults. 规则:
#   - parsed 有 key + 都是 Dict → 递归合并 (用户只改了部分嵌套字段也不丢默认)
#   - parsed 有 key + 类型不同 / 非 Dict → 用 parsed 值 (相信玩家手改)
#   - parsed 缺 key → 用 defaults 深拷贝
#   - parsed 多余 key → 保留 (玩家自定义扩展不丢)
#
# depth 防御恶意嵌套, 超 MAX_MERGE_DEPTH 不再递归 (用 parsed 原值).
# ============================================================================

static func _merge_with_defaults(parsed: Dictionary, defaults: Dictionary, depth: int) -> Dictionary:
	var result: Dictionary = parsed.duplicate(true)
	if depth >= MAX_MERGE_DEPTH:
		_log_error("merge 深度超限 (%d), 停止递归, 用 parsed 原值" % MAX_MERGE_DEPTH)
		return result
	for key in defaults:
		if not result.has(key):
			result[key] = _deep_copy_value(defaults[key])
		elif typeof(result[key]) == TYPE_DICTIONARY and typeof(defaults[key]) == TYPE_DICTIONARY:
			result[key] = _merge_with_defaults(result[key], defaults[key], depth + 1)
		# 否则保留 parsed[key]
	return result


# 深拷贝单个值. Dict / Array 走 duplicate(true), 基本类型直接返回.
static func _deep_copy_value(value):
	if typeof(value) == TYPE_DICTIONARY:
		return (value as Dictionary).duplicate(true)
	elif typeof(value) == TYPE_ARRAY:
		return (value as Array).duplicate(true)
	else:
		return value


# ============================================================================
# IO helpers
# ============================================================================

# mkdir -p, 已存在不报错
static func _ensure_dir(dir_path: String) -> bool:
	var dir = Directory.new()
	if dir.dir_exists(dir_path):
		return true
	var err = dir.make_dir_recursive(dir_path)
	if err != OK:
		_log_error("mkdir 失败 path=%s err=%d" % [dir_path, err])
		return false
	_log("已创建 config 目录: %s" % dir_path)
	return true


# 写文件: open + store_string + close.
# Godot 3 File 无 flush() 方法; close() 内部会 flush, 关闭后即落盘.
static func _write_file(path: String, content: String) -> bool:
	var file = File.new()
	var err = file.open(path, File.WRITE)
	if err != OK:
		_log_error("打开写文件失败 path=%s err=%d" % [path, err])
		return false
	file.store_string(content)
	file.close()
	return true


# POSIX 原子 rename. user:// 内部都在同一分区, 不需要跨分区 fallback.
# Directory.rename 在 Godot 3 是 POSIX rename(2) wrapper, 同分区原子替换;
# 不需要先删除 real_path, rename 会原子覆盖.
static func _rename_atomic(tmp_path: String, real_path: String) -> bool:
	var dir = Directory.new()
	var err = dir.rename(tmp_path, real_path)
	if err != OK:
		_log_error("rename 失败 tmp=%s real=%s err=%d" % [tmp_path, real_path, err])
		return false
	return true


# ============================================================================
# v7 迁移: 阈值纯化 + 上下文分离
# ----------------------------------------------------------------------------
# v6.1 → v7:
#   thresholds[stat]: 移除 upgrade_action/shop_action/chest_action/min_tier → 只留 mode+value
#   upgrade_action="forbid" → upgrade.forbid_stats
#   shop_action="limit" (any) → general.shop_respect_thresholds=true
#   chest_action="limit" (any) → general.chest_respect_thresholds=true
#   upgrade.ignore_blacklist_on_stuck → ignore_forbid_on_stuck
# ============================================================================

static func _migrate_v6_to_v7(merged: Dictionary) -> void:
	# 如果已经是 v7+, 跳过
	if int(merged.get("version", 0)) >= 7:
		return

	# Step 1: 提取 per-stat upgrade_action="forbid" → upgrade.forbid_stats
	_migrate_forbid_to_list(merged)

	# Step 2: 推断 shop_respect_thresholds / chest_respect_thresholds
	_migrate_shop_chest_respect(merged)

	# Step 3: 清理 threshold 条目 — 只保留 mode + value
	_migrate_clean_thresholds(merged)

	# Step 4: 重命名 upgrade 字段
	if merged.has("upgrade") and typeof(merged["upgrade"]) == TYPE_DICTIONARY:
		var upg = merged["upgrade"]
		if upg.has("ignore_blacklist_on_stuck"):
			upg["ignore_forbid_on_stuck"] = upg["ignore_blacklist_on_stuck"]
			upg.erase("ignore_blacklist_on_stuck")
		upg.erase("stat_blacklist")  # 清理 v6 残留

	# Step 5: Bump version
	merged["version"] = 7
	_log("v6/v6.1 → v7 迁移完成")


static func _migrate_forbid_to_list(merged: Dictionary) -> void:
	if not merged.has("thresholds"):
		return
	var ths = merged["thresholds"]
	if typeof(ths) != TYPE_DICTIONARY:
		return
	var forbid_list := []
	for sk in ths:
		var entry = ths[sk]
		if typeof(entry) == TYPE_DICTIONARY and str(entry.get("upgrade_action", "")) == "forbid":
			forbid_list.append(sk)
	if forbid_list.size() > 0:
		if not merged.has("upgrade") or typeof(merged["upgrade"]) != TYPE_DICTIONARY:
			merged["upgrade"] = {}
		merged["upgrade"]["forbid_stats"] = forbid_list
		_log("已迁移 forbid_stats: %s" % str(forbid_list))


static func _migrate_shop_chest_respect(merged: Dictionary) -> void:
	if not merged.has("thresholds"):
		return
	var ths = merged["thresholds"]
	if typeof(ths) != TYPE_DICTIONARY:
		return
	var any_shop_limit := false
	var any_chest_limit := false
	for sk in ths:
		var entry = ths[sk]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("shop_action", "")) == "limit":
			any_shop_limit = true
		if str(entry.get("chest_action", "")) == "limit":
			any_chest_limit = true
	if not merged.has("general") or typeof(merged["general"]) != TYPE_DICTIONARY:
		merged["general"] = {}
	merged["general"]["shop_respect_thresholds"] = any_shop_limit
	merged["general"]["chest_respect_thresholds"] = any_chest_limit


static func _migrate_clean_thresholds(merged: Dictionary) -> void:
	if not merged.has("thresholds"):
		return
	var ths = merged["thresholds"]
	if typeof(ths) != TYPE_DICTIONARY:
		return
	for sk in ths:
		var entry = ths[sk]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var clean := {}
		clean["mode"] = str(entry.get("mode", "unlimited"))
		clean["value"] = int(entry.get("value", 0))
		ths[sk] = clean


# ============================================================================
# 日志
# ============================================================================

static func _log(msg: String) -> void:
	if typeof(ModLoaderLog) != TYPE_NIL:
		ModLoaderLog.info(msg, LOG_NAME)


static func _log_error(msg: String) -> void:
	if typeof(ModLoaderLog) != TYPE_NIL:
		ModLoaderLog.error(msg, LOG_NAME)
