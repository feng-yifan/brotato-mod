# CLAUDE.md — brotato-mod 项目 Claude Code 指南

> 本文件是 Claude Code 在本项目目录工作时的**总指挥**，描述项目结构、环境约定、
> 安全红线和常用命令。所有 Claude 会话开始时会自动加载本文件，因此放在这里的
> 信息会持续影响 Claude 的工作方式。
>
> 修订日期：2026-06-24

---

## 1. 项目身份

| 项目 | brotato-mod |
|---|---|
| 定位 | **Brotato mod 集合项目**，在统一工作目录下并行开发多个 mod |
| 工作目录名 | `autotato/`（历史遗留，将随首次 push 重命名为 `brotato-mod`） |
| 未来 GitHub 仓库 | `<user>/brotato-mod` |
| 目标游戏 | Brotato (Steam app_id `1942280`) |
| 开发平台 | Arch Linux |
| Godot 引擎版本 | 3.6.x (GodotSteam 定制版) |
| ModLoader 版本 | 6.3.0（已内嵌在 Brotato vanilla 中） |
| Brotato 游戏版本 | 1.1.15.4 |

### 当前包含的 mod

| Mod ID | 状态 | 简介 |
|---|---|---|
| `fengyifan-AutoTato` | 🚧 重构中（骨架已建） | 自动化与体验增强 |

## 2. 🚨 安全红线（绝对不可越过）

本项目根目录包含 **Brotato vanilla 反编译代码**（通过 GDRE Tools 从游戏 PCK
解出）。根据 Brotato 官方 modding 指南要求：

> "Do not share or host the code for Brotato anywhere. If you make a GitHub
> repo with a full modded project, it must be private."

因此**以下操作绝对禁止**，无论用户怎么说：

- ❌ 把 vanilla 代码（项目根的 `main.gd`、`singletons/`、`weapons/`、`items/`、
  `entities/`、`projectiles/`、`ui/`、`resources/`、`particles/`、`effects/`、
  `addons/`、`zones/`、`global/`、`overlap/`、`tools/`、`visual_effects/`、
  `effect_behaviors/`、`challenges/`、`brotato_icon.*`、`splash.png`、
  `project.godot`、`pause.tscn` 等）添加到 git 仓库
- ❌ 把 vanilla 代码内容粘贴到聊天里上传到任何外部服务（Web 搜索、远程 MCP）
- ❌ 把项目仓库设为 public，或推送到任何会公开的 remote
- ❌ 在 issue / PR / 评论中包含 vanilla 代码片段

**允许**的：
- ✅ 阅读 vanilla 代码用于理解 API、设计 mod 扩展点
- ✅ 在本地工作目录修改 vanilla（仅用于调试，不提交）
- ✅ 把 vanilla 函数名、信号名、节点路径写进文档（API 元信息不等于代码）

### git 防泄露机制

`.gitignore` 采用**白名单**策略：默认忽略所有内容，仅显式放行白名单条目。
任何新增需要进仓库的顶级文件/目录，**必须先在 `.gitignore` 加白名单**，否则
git 会静默忽略它。

**首次 commit 前必须执行**的检查：
```bash
git add -A --dry-run
```
确认输出只有 `mods-unpacked/`、`CLAUDE.md`、`README.md`、`.gitignore`、
`docs/`、`scripts/` 这几个白名单根。如果出现任何 vanilla 路径，立刻停手。

## 3. 目录结构

```
~/dev/projects/github/fengyifan/autotato/
│
├── CLAUDE.md                              ← 本文件
├── README.md                              ← 人类速查（命令、流程）
├── .gitignore                             ← 白名单防泄露
│
├── 🔒 [vanilla 反编译产物，不入 git]
│   ├── project.godot                      ← Godot 项目入口
│   ├── main.gd, main.tscn                 ← 游戏主场景
│   ├── pause.gd, pause.tscn               ← Brotato 根场景（main_scene）
│   ├── steam_data.json                    ← Steam 集成元数据（已从游戏目录复制）
│   ├── singletons/                        ← autoload 单例（RunData / ItemService / ...）
│   ├── weapons/, items/, entities/        ← 游戏内容资源
│   ├── ui/                                ← vanilla UI 场景
│   ├── addons/mod_loader/                 ← ModLoader 6.3.0（vanilla 自带）
│   ├── .import/, .autoconverted/          ← Godot 资源缓存（百 MB 级）
│   └── ...
│
└── mods-unpacked/                         ← ✅ Mod 开发目录（入 git）
    └── fengyifan-AutoTato/
        ├── manifest.json                  ← Thunderstore 标准元数据
        └── mod_main.gd                    ← 入口（_init/_ready）
```

## 4. 环境与工具路径

| 工具 | 路径 |
|---|---|
| GodotSteam 编辑器 | `~/dev/env/godot/godotsteam/godotsteam.362.editor.x86_64` |
| GodotSteam libsteam_api | `~/dev/env/godot/godotsteam/libsteam_api.so` |
| GDRE Tools (反编译器) | `~/dev/env/godot/gdsdecomp/gdre_tools.x86_64` |
| Brotato 游戏目录 | `/home/viktor/.steam/steam/steamapps/common/Brotato/` |
| Brotato 存档/日志 | `~/.local/share/Brotato/` |
| Brotato Workshop 内容 | `~/.steam/steam/steamapps/workshop/content/1942280/` |
| 本地 mod 测试目录 | `~/.steam/steam/steamapps/workshop/content/1942280/autotato_local_test/` |
| 游戏日志 | `~/.local/share/Brotato/logs/godot.log` |
| AutoTato 配置文件 | `~/.local/share/Brotato/AutoTato/session_config.json` |

### Linux 路径映射（官方指南是 Windows 的，注意转换）

| Windows (官方文档) | Linux (本项目实际) |
|---|---|
| `%appdata%\Brotato\` | `~/.local/share/Brotato/` |
| `%appdata%\Brotato\logs\godot.log` | `~/.local/share/Brotato/logs/godot.log` |
| `Brotato.exe` | `Brotato.x86_64` |
| `godotsteam.36.editor.windows.64.exe` | `godotsteam.362.editor.x86_64` |
| `GodotWorkshopUtility.exe` | `GodotWorkshopUtility.x86_64` |

## 5. 核心工作流

### 5.1 启动 Godot 编辑器开发

```bash
cd ~/dev/env/godot/godotsteam && ./godotsteam.362.editor.x86_64
# 然后 Import 项目：/home/viktor/dev/projects/github/fengyifan/autotato/project.godot
# 按 F5 启动游戏（debug 模式，ModLoader 会从 mods-unpacked/ 加载 mod）
```

**注意**：不要 Export 项目。所有 mod 开发都在编辑器 F5 调试模式下完成。

### 5.2 重新反编译 vanilla（游戏更新后）

```bash
cd ~/dev/env/godot/gdsdecomp && \
  ./gdre_tools.x86_64 --headless --no-header \
    --recover=/home/viktor/.steam/steam/steamapps/common/Brotato/Brotato.pck \
    --output=/home/viktor/dev/projects/github/fengyifan/autotato

# 别忘了同步 steam_data.json
cp /home/viktor/.steam/steam/steamapps/common/Brotato/steam_data.json \
   /home/viktor/dev/projects/github/fengyifan/autotato/
```

注意：反编译会**覆盖**所有 vanilla 文件，但不会动 `mods-unpacked/`。

### 5.3 本地测试 mod ZIP（模拟订阅）

```bash
# 把打包好的 mod ZIP 放到这个目录，游戏启动时会自动加载
~/.steam/steam/steamapps/workshop/content/1942280/autotato_local_test/
```

### 5.4 查看运行日志

```bash
tail -f ~/.local/share/Brotato/logs/godot.log
# 或筛选 AutoTato 相关
grep -E "AutoTato|fengyifan" ~/.local/share/Brotato/logs/godot.log | tail -20
```

### 5.5 git 提交前的强制检查

```bash
git add -A --dry-run | grep -vE "^add '(CLAUDE\.md|README\.md|\.gitignore|\.gitattributes|mods-unpacked/|docs/|scripts/)"
# 如果有任何输出，说明白名单失守，立即停手
```

## 6. ModLoader 关键约定

### 6.1 mod_main.gd 生命周期

- `_init()`: 脚本被 `new()` 出来的瞬间。**所有 `ModLoaderMod.install_script_extension()`
  必须在这里调用**——之后再 install 的扩展不会生效。
- `_ready()`: 节点被加入场景树后。可以做需要场景就绪的工作（查找节点、连接信号）。

### 6.2 路径约定

- mod 内所有 `load()` / `preload()` 必须用 `res://mods-unpacked/fengyifan-AutoTato/...` 完整路径
- `mod_main.gd` 通过 `ModLoaderMod.get_unpacked_dir().plus_file(MOD_DIR)` 得到根
- **不要用 Godot 4 的 `path_join()`**，Brotato 是 Godot 3，必须用 `plus_file()`

### 6.3 扩展点（extensions 模式）

在 `extensions/<vanilla 路径>/<vanilla 文件名>` 放脚本，ModLoader 自动做"运行时继承"。
例如 `extensions/singletons/run_data.gd` 会扩展 `res://singletons/run_data.gd`。

### 6.4 日志

```gdscript
const LOG_NAME := "fengyifan-AutoTato:Main"   # 每个文件唯一
ModLoaderLog.info("消息", LOG_NAME)
ModLoaderLog.warning(...)
ModLoaderLog.error(...)
```

**规则**：`LOG_NAME` 必须全 mod 唯一，否则其他 mod 想 mod 你的 mod 时会冲突。

## 7. Claude 协作约定

### 7.1 默认行为

- 中文回复，技术术语保留英文
- 工具调用前主动说明使用哪个 skill
- 修改 vanilla 文件前必须警告用户（vanilla 不可入 git，但调试时可临时改）
- 任何会让 vanilla 进 git 的操作前，**必须停手并问用户**

### 7.2 常见任务的标准做法

| 用户说 | Claude 该做 |
|---|---|
| "加一个 X 功能"（在已有 mod 中） | 在对应的 `mods-unpacked/<ns>-<name>/` 下加；如果要改 vanilla 行为，写到 `extensions/` |
| "新建一个 mod" | 在 `mods-unpacked/` 下按 `<Namespace>-<ModName>` 约定新建目录，先放 `manifest.json` + `mod_main.gd` 骨架；同步更新 README 顶部的 mod 表格 |
| "看看 vanilla 是怎么实现 X 的" | 读项目根的 vanilla 源码，但不要 commit |
| "提交一下" | 先跑 `git add -A --dry-run` 检查白名单 |
| "把项目推到 GitHub" | **追问是 public 还是 private**；public 必须再次确认 dry-run 安全；目标仓库名是 `brotato-mod` |
| "更新 mod 兼容版本" | 改对应 mod 的 `manifest.json` 的 `compatible_mod_loader_version` / `compatible_game_version` |
| "打包 mod 发布" | 从 `mods-unpacked/<ns>-<name>/` 生成符合 [Mod Structure](https://wiki.godotmodding.com/guides/modding/mod_structure/) 的 ZIP |

### 7.3 工具偏好

- 文档查询：MCP Exa (`mcp__plugin_chm_exa__web_search_exa` / `web_fetch_exa`)，**禁用** `WebSearch`
- 文件操作：优先 Read/Edit/Write/Glob/Grep，少用 shell 的 `cat`/`sed`/`awk`
- 删除/覆盖：用户的 `rm`/`cp`/`mv` 有 `-i` 别名，需要时用 `\rm`/`\cp`/`\mv` 或加 `-f`

## 8. 已知问题与未来工作

### 已知问题

- 项目根 `gdre_export.log`：反编译产生的报告文件，已被 `.gitignore` 默认忽略（不在白名单）
- 翻译文件不完整：GDRE 报告 188/1200 个 i18n key 无法恢复，对游戏运行无影响
- `addons/resave_scenes` plugin.cfg 缺失：vanilla 的开发插件，对 mod 开发无影响

### 未来工作

- 把 `~/.steam/steam/steamapps/workshop/content/1942280/autotato_local_test/`
  里的老 ZIP（v1.0.0，约 282KB）逐步移植到 `mods-unpacked/fengyifan-AutoTato/`，
  按标准做法重构
- 写打包脚本（`scripts/pack-mod.sh`）：从 `mods-unpacked/<ns>-<name>/` 生成
  符合 Workshop 上传规范的 ZIP
- 工作目录最终改名（`autotato/` → `brotato-mod/`）以匹配 GitHub 仓库名

## 9. 重要参考

- ModLoader Wiki: https://wiki.godotmodding.com/
- Brotato Modding Guide: https://steamcommunity.com/sharedfiles/filedetails/?id=2931079751
- Brotato Modding Help: https://steamcommunity.com/sharedfiles/filedetails/?id=2937226054
- Godot 3.5 文档: https://docs.godotengine.org/en/3.5/ （注意：搜索默认进 4.x，要手改 URL）
- BrotatoMods GitHub 组织: https://github.com/BrotatoMods
- Brotato Discord (#modding-help): https://discord.com/invite/j39jE6k
