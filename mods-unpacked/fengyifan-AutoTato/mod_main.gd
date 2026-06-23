extends Node

# ============================================================================
# fengyifan-AutoTato — Mod 入口
# ============================================================================
#
# 本文件结构遵循 Godot Mod Loader 官方 wiki 的 Godot 3 模板：
#   https://wiki.godotmodding.com/guides/modding/mod_files/
#
# 加载流程：
#   1. ModLoader 扫描 res://mods-unpacked/ 找到本目录
#   2. 读取同级 manifest.json 校验版本兼容性、依赖
#   3. new() 本脚本 → 触发 _init()
#   4. 把节点挂到场景树 → 触发 _ready()
#
# 关键：
#   - _init() 里调用 ModLoaderMod 的 install_*() 系列函数注册扩展（要在游戏
#     场景树构建前完成，否则扩展无效）
#   - _ready() 里做需要场景树就绪后的初始化（如查找节点、连接信号）
#   - 所有日志走 ModLoaderLog，调用时附带本 mod 的唯一 LOG_NAME 作为来源
# ============================================================================

# Mod ID 拆出来做常量，方便构造资源路径与日志归属
const MOD_DIR := "fengyifan-AutoTato"
const LOG_NAME := "fengyifan-AutoTato:Main"

# 各子目录路径在 _init() 里组装，避免每个 install 调用都重复写一遍前缀
var mod_dir_path := ""
var extensions_dir_path := ""
var translations_dir_path := ""


# ----------------------------------------------------------------------------
# 生命周期
# ----------------------------------------------------------------------------

# _init() 由 ModLoader 在场景树构建之前调用
# 此时所有 install_* 注册必须完成，之后再 install 的扩展不会生效
func _init() -> void:
	mod_dir_path = ModLoaderMod.get_unpacked_dir().plus_file(MOD_DIR)

	install_script_extensions()
	add_translations()


# _ready() 在节点被加到场景树后触发（vanilla 场景已经存在）
# 适合做：查找现有节点、连接信号、注入 UI 控件
func _ready() -> void:
	ModLoaderLog.info("AutoTato 已加载", LOG_NAME)


# ----------------------------------------------------------------------------
# 注册器：脚本扩展
# ----------------------------------------------------------------------------

# 把 extensions/ 下的脚本注册为 vanilla 脚本的运行时子类
# 例如 extensions/singletons/run_data.gd 会扩展 res://singletons/run_data.gd
# 添加扩展时取消下方注释并填入对应路径
func install_script_extensions() -> void:
	extensions_dir_path = mod_dir_path.plus_file("extensions")
	# ModLoaderMod.install_script_extension(extensions_dir_path.plus_file("singletons/run_data.gd"))


# ----------------------------------------------------------------------------
# 注册器：翻译
# ----------------------------------------------------------------------------

# 把 translations/ 下的 .translation 资源合并到 vanilla 翻译表中
# 文件名需符合 ModLoader 的命名约定（key.locale.translation）
func add_translations() -> void:
	translations_dir_path = mod_dir_path.plus_file("translations")
	# ModLoaderMod.add_translation(translations_dir_path.plus_file("autotato.en.translation"))
