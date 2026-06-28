---
title: Brotato Mod 开发框架
description: >
  Brotato mod 开发的基础知识，属于 modding 领域知识。
  覆盖 ModLoader 6.3.0 机制与 API、Script Extension 扩展模式、
  manifest.json / mod_main.gd 生命周期、注册新内容流程（ItemService）、
  路径约定与日志规范、DebugService 调试选项、开发工作流与安全红线。
game_version: 1.1.15.4
---

# Brotato Mod 开发框架

---

## 开发环境

### 工具路径

| 工具 | 路径 |
|---|---|
| GodotSteam 编辑器 | `~/dev/env/godot/godotsteam/godotsteam.362.editor.x86_64` |
| GDRE Tools (反编译器) | `~/dev/env/godot/gdsdecomp/gdre_tools.x86_64` |
| Brotato 游戏目录 | `~/.steam/steam/steamapps/common/Brotato/` |
| Brotato 存档/日志 | `~/.local/share/Brotato/` |
| Workshop 内容 | `~/.steam/steam/steamapps/workshop/content/1942280/` |
| 本地 mod 测试 | `~/.steam/steam/steamapps/workshop/content/1942280/autotato_local_test/` |
| 游戏日志 | `~/.local/share/Brotato/logs/godot.log` |

### Linux 路径映射（官方指南是 Windows）

| Windows (官方文档) | Linux (实际) |
|---|---|
| `%appdata%\Brotato\` | `~/.local/share/Brotato/` |
| `Brotato.exe` | `Brotato.x86_64` |
| `godotsteam.36.editor.windows.64.exe` | `godotsteam.362.editor.x86_64` |

---

## ModLoader 6.3.0

### 核心机制：Script Extension

ModLoader 的核心扩展机制是 **Script Extension（脚本扩展）**：

1. Mod 在 `extensions/<vanilla 路径>/<vanilla 文件名>` 放置一个 `.gd` 文件
2. 该文件的脚本 `extends` 目标 vanilla 脚本
3. `ModLoaderMod.install_script_extension()` 注册这个扩展
4. ModLoader 在加载时**替换** Godot 资源系统中的原脚本路径——所有使用原脚本的对象都使用扩展脚本

这是 **Godot 资源系统的路径替换**，不是传统的 hook/patch。它替换的是整个类的脚本。

### Mod 目录结构标准

```
mods-unpacked/<命名空间>-<Mod名称>/
├── manifest.json         # 元数据（名称、版本、依赖、兼容性）
├── mod_main.gd           # 入口脚本
├── extensions/           # 脚本扩展（镜像 vanilla 路径）
│   └── ui/menus/shop/base_shop.gd
├── translations/         # 翻译文件
└── <你的代码>/           # 自定义代码
```

### mod_main.gd 生命周期

```gdscript
# 阶段 1: _init() — 脚本被 new() 出来时（场景树构建之前）
# 所有 install_script_extension() 必须在这里调用
# 之后再 install 的扩展不会生效
func _init():
    ModLoaderMod.install_script_extension("path/to/extension.gd")

# 阶段 2: _ready() — 节点被加入场景树后
# 可以做需要场景就绪的工作（查找节点、连接信号）
func _ready():
    pass
```

### Mod API（ModLoaderMod 公开方法）

| 方法 | 用途 |
|---|---|
| `install_script_extension(path)` | 注册脚本扩展（必须在 `_init` 调用） |
| `register_global_classes_from_array(arr)` | 注册新的全局类 |
| `add_translation(path)` | 添加翻译资源 |
| `append_node_in_scene(path, node)` | 向场景添加节点 |
| `save_scene(path)` | 保存修改后的场景 |
| `get_mod_data()` / `get_mod_data_all()` | 获取 mod 元数据 |
| `get_unpacked_dir()` | 获取 `mods-unpacked/` 目录路径 |
| `is_mod_loaded(mod_id)` | 检查某 mod 是否已加载 |

### 路径约定
- mod 内所有 `load()` / `preload()` 必须用 `res://mods-unpacked/fengyifan-AutoTato/...` 完整路径
- Godot 3 用 `plus_file()` 拼接路径，不要用 Godot 4 的 `path_join()`

### 日志规范
```gdscript
const LOG_NAME := "fengyifan-AutoTato:Main"  # 全 mod 唯一
ModLoaderLog.info("消息", LOG_NAME)
```

---

## 注册新内容（ItemService API）

Mod 可以通过 `ItemService` 注册新物品：
- `ItemService.add_mod_item(item_data)` — 注册物品/武器/角色
- `ItemService.remove_mod_item(item_data)` — 移除

### 添加新属性的完整路径

1. 在 `Keys` 类中添加 hash 常量
2. 在 `ItemService.stats` 中注册 `StatData` 资源
3. 在 `PlayerRunData.init_stats()` 中添加该 stat
4. 在 `PlayerRunData.init_effects()` 中为该 stat 添加效果条目

### 物品/武器数据模型继承链

```
ItemParentData (items/global/item_parent_data.gd)
├── ItemData (items/global/item_data.gd)
│   └── CharacterData (items/characters/character_data.gd)
├── WeaponData (items/global/weapon_data.gd)
├── UpgradeData (items/upgrades/upgrade_data.gd)
└── ConsumableData (items/consumables/consumable_data.gd)
```

---

## 开发工作流

### 启动 Godot 编辑器
```bash
cd ~/dev/env/godot/godotsteam && ./godotsteam.362.editor.x86_64
# Import 项目：~/dev/projects/github/fengyifan/autotato/project.godot
# 按 F5 启动游戏（debug 模式，ModLoader 从 mods-unpacked/ 加载 mod）
```
**不要 Export 项目**。所有 mod 开发在编辑器 F5 调试模式下完成。

### 重新反编译 vanilla（游戏更新后）
```bash
cd ~/dev/env/godot/gdsdecomp && \
  ./gdre_tools.x86_64 --headless --no-header \
    --recover=<Brotato.pck 路径> \
    --output=<项目目录>

# 同步 steam_data.json
cp <游戏目录>/steam_data.json <项目目录>/
```
反编译会覆盖所有 vanilla 文件，但不动 `mods-unpacked/`。

### 查看日志
```bash
tail -f ~/.local/share/Brotato/logs/godot.log
```

---

## 安全红线

根据 Brotato 官方 modding 指南：
> "Do not share or host the code for Brotato anywhere."

- ❌ 不把 vanilla 代码加入 git
- ❌ 不把 vanilla 代码粘贴到外部服务
- ❌ 不把项目仓库设为 public
- ✅ 可以阅读 vanilla 代码用于理解 API
- ✅ 可以本地修改 vanilla（仅调试，不提交）
- ✅ 可以记录函数名、信号名、节点路径（API 元信息）

### git 白名单策略
`.gitignore` 默认忽略所有内容，仅显式放行：
- `mods-unpacked/`
- `CLAUDE.md`、`README.md`、`.gitignore`
- `docs/`、`scripts/`

---

## DebugService（开发调试）

单例 `singletons/debug_service.tscn`，提供调试选项：

| 选项 | 效果 |
|---|---|
| Starting Wave | 设置初始波次 |
| Starting Gold | 设置初始金币 |
| Invulnerable | 无敌 |
| Instant Waves | 1 秒波次（快速测试商店） |
| Debug Weapons | 添加特定武器 |
| Debug Items | 添加特定物品 |
| Add All Weapons | 添加所有武器 |
| Add All Items | 添加所有物品 |
| Disable Saving | 禁用存档（保护真实存档） |
| Unlock All Chars / Challenges | 解锁全部（临时） |
| No Enemies | 无敌人 |
