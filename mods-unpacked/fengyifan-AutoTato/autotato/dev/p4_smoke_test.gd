extends Reference

# ============================================================================
# AutoTato — P4 烟雾测试 (ConfigManager 配置持久化)
# ============================================================================
#
# 目的: 验证 P4 把内存 _config 接入磁盘 session_config.json 后的核心逻辑.
#   - 前 9 用例: ConfigManager 的 IO / Schema 迁移 / 损坏兜底 / 原子写
#   - 后 3 用例: Bridge 整合 (set_* 触发 _persist; 新建实例 _init 走 load)
#
# 与 P0 / P1 / P2 / P3 烟雾独立:
#   - P0 测 schema 层 (Effect / Keys / Util)
#   - P1 测决策器层 (static 纯函数)
#   - P2 测 Bridge config / CRUD / 三个 decide_* 入口
#   - P3 测 Bridge.process_shop 整商店决策 + 容错
#   - P4 测 ConfigManager (IO/迁移/兜底/原子) + Bridge 持久化集成
#
# 关键警示:
#   ConfigManager.get_config_path() 写死 user://AutoTato/session_config.json,
#   也就是玩家真实存档目录 ~/.local/share/Brotato/AutoTato/session_config.json.
#   烟雾测试会反复写/删/写坏数据到此路径, 必须在 run() 开头备份, 结尾还原,
#   否则会污染玩家真实配置. 备份/还原走 .smoke_backup 后缀, 即使中途 _assert
#   失败也会执行 _restore_real_config (放在 run 末尾, 无 early return).
#
# 触发:
#   默认关闭, mod_main 把 DEV_RUN_P4_SMOKE 改 true 即可在游戏启动时自动
#   .new() 出实例并调 run(), 结果写到 godot.log. 亦可通过环境变量
#   AUTOTATO_P4_SMOKE 在 mod_main 中读取触发.
#
# 用例总览 (12 个):
#   1.  get_config_path 返回值非空 + 含 "AutoTato/session_config.json"
#   2.  load 文件不存在 -> 返回 defaults 深拷贝 (defaults 未被污染)
#   3.  save 后再 load 应得相同内容
#   4.  save 后 .tmp 文件不残留 (rename 已搬走)
#   5.  损坏 JSON -> load 返回 null
#   6.  扁平 schema 迁移: parsed 缺 key 用 defaults 补
#   7.  嵌套 schema 迁移: parsed 缺嵌套子 key 用 defaults 补
#   8.  顶层非 dict (Array) -> load 返回 null
#   9.  空文件 -> load 返回 null
#   10. Bridge.set_item_rule -> _persist -> 新实例可读回
#   11. Bridge.set_threshold -> _persist -> 新实例可读回
#   12. Bridge 首次启动 (无 config 文件) -> 默认值齐全, 不崩
# ============================================================================


const LOG_NAME := "fengyifan-AutoTato:P4SmokeTest"

const ConfigManager = preload("res://mods-unpacked/fengyifan-AutoTato/autotato/runtime/config_manager.gd")
const Bridge        = preload("res://mods-unpacked/fengyifan-AutoTato/autotato/runtime/bridge.gd")


# 计数: 通过 / 失败 / 警告
var _pass := 0
var _fail := 0
var _warn := 0

# 备份/还原玩家真实 config 文件路径 (避免烟雾污染)
var _backup_path: String = ""
var _had_real_config: bool = false


# ============================================================================
# 入口
# ============================================================================

func run() -> void:
	_backup_real_config()
	_log("════════ P4 烟雾测试开始 ════════")

	_test_1_get_config_path()
	_test_2_load_file_not_exists()
	_test_3_save_then_load()
	_test_4_atomic_write_no_tmp_residue()
	_test_5_corrupted_json()
	_test_6_schema_migration_flat()
	_test_7_schema_migration_nested()
	_test_8_type_mismatch()
	_test_9_empty_file()
	_test_10_bridge_persist_set_item_rule()
	_test_11_bridge_persist_set_threshold()
	_test_12_bridge_first_launch_no_file()

	_log("════════ P4 烟雾测试结束 ════════")
	_log("结果: %d 通过 / %d 失败 / %d 警告" % [_pass, _fail, _warn])
	if _fail > 0:
		ModLoaderLog.error("P4 ConfigManager 有 %d 项失败, 请检查上方日志" % _fail, LOG_NAME)

	# 关键: 还原放最末. _assert 不抛异常仅累 _fail, run 不会 early return,
	# 所以这里一定会执行, 玩家真实 config 不被烟雾污染.
	_restore_real_config()


# ============================================================================
# 备份/还原玩家真实 config (烟雾会写真实路径, 跑完要还原)
# ============================================================================

# 备份真实 config 文件 (如果存在). 把它挪到 .smoke_backup 后缀.
# 用 rename 而非 copy: 烟雾跑完前真实路径必须"为空", 不然用例 2 的
# "文件不存在" 前置条件不成立.
func _backup_real_config() -> void:
	var real_path: String = ConfigManager.get_config_path()
	_backup_path = real_path + ".smoke_backup"

	var dir = Directory.new()

	# 残留的 .smoke_backup 先清掉 (上次烟雾未正常退出可能留下)
	if File.new().file_exists(_backup_path):
		_warn += 1
		ModLoaderLog.warning("发现遗留 .smoke_backup, 删除: %s" % _backup_path, LOG_NAME)
		dir.remove(_backup_path)

	_had_real_config = File.new().file_exists(real_path)
	if _had_real_config:
		var err = dir.rename(real_path, _backup_path)
		if err == OK:
			_log("已备份真实 config: %s -> %s" % [real_path, _backup_path])
		else:
			_warn += 1
			ModLoaderLog.warning("备份真实 config 失败 err=%d, 烟雾可能会覆盖真实文件!" % err, LOG_NAME)
			_had_real_config = false


# 还原真实 config 文件 (run 末尾必调).
# 三步: 删测试残留 real_path -> rename 备份回 real_path -> 兜底删 .tmp 残留.
func _restore_real_config() -> void:
	var real_path: String = ConfigManager.get_config_path()
	var tmp_path: String = ConfigManager.get_tmp_path()
	var dir = Directory.new()

	# 1. 删除测试残留的 real_path (烟雾刚刚写进去的乱七八糟)
	if File.new().file_exists(real_path):
		var err_rm = dir.remove(real_path)
		if err_rm != OK:
			_warn += 1
			ModLoaderLog.warning("删除测试残留 real_path 失败 err=%d" % err_rm, LOG_NAME)

	# 2. 还原备份 (如果有)
	if _had_real_config and File.new().file_exists(_backup_path):
		var err = dir.rename(_backup_path, real_path)
		if err == OK:
			_log("已还原真实 config 从备份: %s -> %s" % [_backup_path, real_path])
		else:
			_warn += 1
			ModLoaderLog.warning("还原真实 config 失败 err=%d, 备份留在: %s" % [err, _backup_path], LOG_NAME)

	# 3. 兜底清理 .tmp 残留 (用例 4 已验证, 这里只是双保险)
	if File.new().file_exists(tmp_path):
		dir.remove(tmp_path)


# ============================================================================
# 测试用例 1-9: ConfigManager 单元
# ============================================================================

# ----------------------------------------------------------------------------
# 用例 1: get_config_path() 返回值合法 (非空, 含 AutoTato/session_config.json)
# ----------------------------------------------------------------------------
func _test_1_get_config_path() -> void:
	_section("[1] get_config_path 返回值合法")

	var path: String = ConfigManager.get_config_path()
	_log("  path=%s" % path)
	_assert(path != "", "返回值不应为空")
	_assert(path.find("AutoTato") >= 0, "path 应含 'AutoTato', 实得 '%s'" % path)
	_assert(path.find("session_config.json") >= 0,
		"path 应含 'session_config.json', 实得 '%s'" % path)


# ----------------------------------------------------------------------------
# 用例 2: 文件不存在 -> 返回 defaults 深拷贝
# 关键: 验证返回的 dict 与 defaults 是独立对象 (改返回值不会污染 defaults).
# ----------------------------------------------------------------------------
func _test_2_load_file_not_exists() -> void:
	_section("[2] 文件不存在 -> 返回 defaults 深拷贝")

	_delete_config_file()

	var defaults: Dictionary = {"a": 1, "b": 2}
	var r = ConfigManager.load_config(defaults)

	_log("  r=%s" % str(r))
	_assert(r != null, "返回值不应为 null")
	if r == null:
		return
	_assert(r is Dictionary, "返回值应为 Dictionary, 实得 type=%d" % typeof(r))
	if not (r is Dictionary):
		return
	_assert(int(r.get("a", -1)) == 1, "r.a 应为 1, 实得 %s" % str(r.get("a", null)))
	_assert(int(r.get("b", -1)) == 2, "r.b 应为 2, 实得 %s" % str(r.get("b", null)))

	# 深拷贝验证: 改 r 后再 load 应仍得 defaults 原值
	r["a"] = 99
	var r2 = ConfigManager.load_config(defaults)
	_assert(r2 != null and r2 is Dictionary, "二次 load 应返回 Dictionary")
	if r2 is Dictionary:
		_assert(int(r2.get("a", -1)) == 1,
			"defaults 应未被污染, 二次 load 的 a 应为 1, 实得 %s" % str(r2.get("a", null)))


# ----------------------------------------------------------------------------
# 用例 3: save -> load roundtrip
# ----------------------------------------------------------------------------
func _test_3_save_then_load() -> void:
	_section("[3] save 后再 load 应得相同内容")

	_delete_config_file()

	var defaults: Dictionary = {"x": 0}
	var to_save: Dictionary = {"x": 42, "y": "hello"}

	var ok: bool = ConfigManager.save_config(to_save)
	_assert(ok, "save_config 应返回 true")
	if not ok:
		return

	var r = ConfigManager.load_config(defaults)
	_log("  loaded=%s" % str(r))
	_assert(r != null and r is Dictionary, "load 应返回非空 Dictionary")
	if not (r is Dictionary):
		return
	_assert(int(r.get("x", -1)) == 42, "x 应为 42, 实得 %s" % str(r.get("x", null)))
	_assert(String(r.get("y", "")) == "hello",
		"y 应为 'hello', 实得 '%s'" % str(r.get("y", null)))


# ----------------------------------------------------------------------------
# 用例 4: save 后 .tmp 文件不应残留 (rename 已把 .tmp 搬到 .json)
# ----------------------------------------------------------------------------
func _test_4_atomic_write_no_tmp_residue() -> void:
	_section("[4] save 后 .tmp 文件不残留")

	_delete_config_file()
	var tmp_path: String = ConfigManager.get_tmp_path()
	# 先确保 .tmp 也不存在
	if File.new().file_exists(tmp_path):
		Directory.new().remove(tmp_path)

	var ok: bool = ConfigManager.save_config({"k": "v"})
	_assert(ok, "save_config 应返回 true")
	if not ok:
		return

	var tmp_exists: bool = File.new().file_exists(tmp_path)
	_log("  tmp_path=%s exists=%s" % [tmp_path, str(tmp_exists)])
	_assert(not tmp_exists,
		"save 成功后 .tmp 文件不应存在 (rename 已搬走), 实得 exists=%s" % str(tmp_exists))


# ----------------------------------------------------------------------------
# 用例 5: 损坏 JSON -> load 返回 null
# ----------------------------------------------------------------------------
func _test_5_corrupted_json() -> void:
	_section("[5] 损坏 JSON -> load 返回 null")

	_delete_config_file()
	var wrote: bool = _write_raw_to_config_path("{this is not json")
	_assert(wrote, "前置: 写入损坏文件应成功")
	if not wrote:
		return

	var r = ConfigManager.load_config({"a": 1})
	_log("  r=%s" % str(r))
	_assert(r == null, "损坏 JSON 应返回 null, 实得 %s" % str(r))


# ----------------------------------------------------------------------------
# 用例 6: 扁平 schema 迁移
# parsed = {a:9}, defaults = {a:1, b:2} -> 合并后 {a:9, b:2}
# ----------------------------------------------------------------------------
func _test_6_schema_migration_flat() -> void:
	_section("[6] 扁平 schema 迁移 (缺 key 用默认补)")

	_delete_config_file()
	var wrote: bool = _write_raw_to_config_path('{"a": 9}')
	_assert(wrote, "前置: 写入 {a:9} 应成功")
	if not wrote:
		return

	var defaults: Dictionary = {"a": 1, "b": 2}
	var r = ConfigManager.load_config(defaults)
	_log("  r=%s" % str(r))
	_assert(r != null and r is Dictionary, "load 应返回 Dictionary")
	if not (r is Dictionary):
		return
	_assert(int(r.get("a", -1)) == 9, "a 应保留 parsed 值 9, 实得 %s" % str(r.get("a", null)))
	_assert(int(r.get("b", -1)) == 2, "b 应补默认值 2, 实得 %s" % str(r.get("b", null)))


# ----------------------------------------------------------------------------
# 用例 7: 嵌套 schema 迁移
# parsed = {x:{p:9}}, defaults = {x:{p:1, q:2}} -> 合并后 {x:{p:9, q:2}}
# ----------------------------------------------------------------------------
func _test_7_schema_migration_nested() -> void:
	_section("[7] 嵌套 schema 迁移 (缺嵌套子 key 用默认补)")

	_delete_config_file()
	var wrote: bool = _write_raw_to_config_path('{"x": {"p": 9}}')
	_assert(wrote, "前置: 写入 {x:{p:9}} 应成功")
	if not wrote:
		return

	var defaults: Dictionary = {"x": {"p": 1, "q": 2}}
	var r = ConfigManager.load_config(defaults)
	_log("  r=%s" % str(r))
	_assert(r != null and r is Dictionary, "load 应返回 Dictionary")
	if not (r is Dictionary):
		return
	var x = r.get("x", null)
	_assert(x != null and typeof(x) == TYPE_DICTIONARY,
		"r.x 应为 Dictionary, 实得 type=%d" % typeof(x))
	if typeof(x) != TYPE_DICTIONARY:
		return
	_assert(int(x.get("p", -1)) == 9, "x.p 应保留 parsed 值 9, 实得 %s" % str(x.get("p", null)))
	_assert(int(x.get("q", -1)) == 2, "x.q 应补默认值 2, 实得 %s" % str(x.get("q", null)))


# ----------------------------------------------------------------------------
# 用例 8: 顶层非 Dict (写 Array) -> load 返回 null
# ----------------------------------------------------------------------------
func _test_8_type_mismatch() -> void:
	_section("[8] 顶层非 dict (Array) -> load 返回 null")

	_delete_config_file()
	var wrote: bool = _write_raw_to_config_path('[1, 2, 3]')
	_assert(wrote, "前置: 写入 [1,2,3] 应成功")
	if not wrote:
		return

	var r = ConfigManager.load_config({"a": 1})
	_log("  r=%s" % str(r))
	_assert(r == null, "顶层非 dict 应返回 null, 实得 %s" % str(r))


# ----------------------------------------------------------------------------
# 用例 9: 空文件 -> load 返回 null
# ----------------------------------------------------------------------------
func _test_9_empty_file() -> void:
	_section("[9] 空文件 -> load 返回 null")

	_delete_config_file()
	var wrote: bool = _write_raw_to_config_path("")
	_assert(wrote, "前置: 写入空文件应成功")
	if not wrote:
		return

	var r = ConfigManager.load_config({"a": 1})
	_log("  r=%s" % str(r))
	_assert(r == null, "空文件应返回 null, 实得 %s" % str(r))


# ============================================================================
# 测试用例 10-12: Bridge 持久化集成
# ----------------------------------------------------------------------------
# 这三个用例近似"重启 mod" 的检查: 创建 Bridge 实例 -> set_* -> 销毁实例
# (Reference 引用计数清零) -> 新建 Bridge -> 应读回写过的值.
# 依赖 Bridge 内部 set_* 触发 _persist + _init 走 ConfigManager.load_config.
# ============================================================================

# ----------------------------------------------------------------------------
# 用例 10: set_item_rule 应持久化, 新实例可读回
# ----------------------------------------------------------------------------
func _test_10_bridge_persist_set_item_rule() -> void:
	_section("[10] Bridge.set_item_rule -> 持久化 -> 新实例读回")

	_delete_config_file()

	var b1 = Bridge.new()
	b1.set_item_rule("test_item_10", {"shop_action": "reject"})
	# 销毁 b1 (Reference 引用计数清零, 不会再 set)
	b1 = null

	var b2 = Bridge.new()
	var rule: Dictionary = b2.get_item_rule("test_item_10")
	_log("  b2.get_item_rule('test_item_10')=%s" % str(rule))
	_assert(rule.has("shop_action"),
		"重建 Bridge 后应能读回 rule 的 shop_action, 实得 %s" % str(rule))
	_assert(String(rule.get("shop_action", "")) == "reject",
		"shop_action 应为 'reject', 实得 '%s'" % str(rule.get("shop_action", "")))


# ----------------------------------------------------------------------------
# 用例 11: set_threshold 应持久化, 新实例可读回
# ----------------------------------------------------------------------------
func _test_11_bridge_persist_set_threshold() -> void:
	_section("[11] Bridge.set_threshold -> 持久化 -> 新实例读回")

	_delete_config_file()

	var b1 = Bridge.new()
	b1.set_threshold("stat_speed", "upper", 99)
	b1 = null

	var b2 = Bridge.new()
	var th: Dictionary = b2.get_threshold("stat_speed")
	_log("  b2.get_threshold('stat_speed')=%s" % str(th))
	_assert(th.has("mode") and th.has("value"),
		"重建 Bridge 后应能读回 threshold 的 mode/value, 实得 %s" % str(th))
	_assert(String(th.get("mode", "")) == "upper",
		"mode 应为 'upper', 实得 '%s'" % str(th.get("mode", "")))
	_assert(int(th.get("value", -1)) == 99,
		"value 应为 99, 实得 %s" % str(th.get("value", null)))


# ----------------------------------------------------------------------------
# 用例 12: 首次启动 (无 config 文件) -> 默认值齐全, 不崩
# ----------------------------------------------------------------------------
func _test_12_bridge_first_launch_no_file() -> void:
	_section("[12] Bridge 首次启动 (无 config) -> 默认值齐全")

	_delete_config_file()

	var b = Bridge.new()
	_assert(b != null, "Bridge.new() 不应崩")
	if b == null:
		return

	var ths: Dictionary = b.get_thresholds()
	_log("  thresholds.size=%d" % ths.size())
	_assert(ths.size() >= 5,
		"首次启动应保留 >=5 个默认 thresholds, 实得 %d" % ths.size())

	var rules: Dictionary = b.get_item_rules()
	_log("  item_rules.size=%d" % rules.size())
	_assert(rules.size() == 0,
		"首次启动应无默认 item_rules, 实得 size=%d" % rules.size())


# ============================================================================
# 工具函数 (照搬 P3 风格)
# ============================================================================

# 直接写原始字符串到 config_path. 用于构造损坏 / 不合法 / 空文件场景.
# 绕过 ConfigManager.save_config, 因为后者只接受 dict.
func _write_raw_to_config_path(content: String) -> bool:
	# 确保父目录存在 (首次烟雾真实路径父目录可能未建)
	var dir_path: String = ConfigManager.get_config_dir()
	var dir = Directory.new()
	if not dir.dir_exists(dir_path):
		var err_mkdir = dir.make_dir_recursive(dir_path)
		if err_mkdir != OK:
			ModLoaderLog.error("_write_raw mkdir 失败 path=%s err=%d" % [dir_path, err_mkdir], LOG_NAME)
			return false

	var f = File.new()
	var err = f.open(ConfigManager.get_config_path(), File.WRITE)
	if err != OK:
		ModLoaderLog.error("_write_raw open 失败 err=%d" % err, LOG_NAME)
		return false
	f.store_string(content)
	f.close()
	return true


# 删除 config 文件 (如果存在). 用例间状态隔离.
func _delete_config_file() -> void:
	var path: String = ConfigManager.get_config_path()
	if File.new().file_exists(path):
		Directory.new().remove(path)


func _section(title: String) -> void:
	_log("──── %s ────" % title)


func _assert(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
		_log("  ✓ %s" % msg)
	else:
		_fail += 1
		ModLoaderLog.error("  ✗ %s" % msg, LOG_NAME)


func _warn_case(msg: String) -> void:
	_warn += 1
	ModLoaderLog.warning("  ⚠ %s" % msg, LOG_NAME)


func _log(msg: String) -> void:
	ModLoaderLog.info(msg, LOG_NAME)
