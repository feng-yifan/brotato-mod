# brotato-mod

> [Brotato](https://store.steampowered.com/app/1942280/Brotato/) mod 开发集合项目
>
> 在统一的工作目录下并行开发多个 mod，共享 Brotato vanilla 反编译环境与
> Godot 工具链，遵循 [Godot Mod Loader](https://wiki.godotmodding.com/)
> 标准结构。

---

## 已包含的 mod

| Mod ID | 状态 | 简介 |
|---|---|---|
| `fengyifan-AutoTato` | 🚧 重构中 | 自动化与体验增强：自动选择升级、武器管理、商店物品过滤 |

> 添加新 mod 时请在此表格补一行，并在 `mods-unpacked/` 下创建对应目录。

---

## 🚨 安全须知 — 阅读前必看

本仓库的**工作目录**会包含 Brotato vanilla 反编译代码（通过 GDRE Tools 从游戏
`.pck` 解出）。根据 Brotato 官方 modding 指南要求：

> Do not share or host the code for Brotato anywhere. If you make a GitHub
> repo with a full modded project, it must be private.
>
> — [Brotato Modding Guide](https://steamcommunity.com/sharedfiles/filedetails/?id=2931079751)

因此本仓库采用**白名单 `.gitignore`** 策略：默认忽略所有内容，仅显式放行你
自己编写的 mod 源码与项目级文档。**任何提交都不应包含 vanilla 代码。**

每次提交前请运行：

```bash
git add -A --dry-run | grep -vE "^add '(CLAUDE\.md|README\.md|\.gitignore|\.gitattributes|mods-unpacked/|docs/|scripts/)"
```

预期输出**空行**。如出现任何 vanilla 路径（`main.gd`、`singletons/`、
`weapons/` 等），立即停止，检查 `.gitignore`。

---

## 快速开始

新成员（或换新机器的你自己）按以下顺序操作：

### 1. 准备工具链

需要三个工具：

| 工具 | 用途 | 下载 |
|---|---|---|
| **GodotSteam 3.6.x** | 带 Steam 集成的 Godot 编辑器（vanilla Godot 不行） | [GitHub Releases](https://github.com/CoaguCo-Industries/GodotSteam/releases) |
| **GDRE Tools** | 从游戏 PCK 反编译出 Godot 项目 | [GitHub Releases](https://github.com/bruvzg/gdsdecomp/releases) |
| **Brotato (Steam 正版)** | 提供 `Brotato.pck` 作为反编译源 | Steam 商店 |

> Brotato 是 Godot **3.6**，不要下载 GodotSteam 4.x 版本。GDRE Tools 用 4.x
> 编译没关系——它支持解码 Godot 3 的字节码。

### 2. 克隆本仓库

```bash
git clone https://github.com/<your-user>/brotato-mod.git
cd brotato-mod
```

仓库初始体积很小（只有 mod 源码和文档）。**vanilla 代码不在仓库里**，下一步生成。

### 3. 反编译 vanilla 到工作目录

```bash
# 替换 <BROTATO> 为你的 Brotato 游戏安装目录
# Linux 默认：~/.steam/steam/steamapps/common/Brotato/
# Windows 默认：C:\Program Files (x86)\Steam\steamapps\common\Brotato\
# Mac 默认：~/Library/Application Support/Steam/steamapps/common/Brotato/

gdre_tools --headless --no-header \
  --recover=<BROTATO>/Brotato.pck \
  --output=$(pwd)

# 复制 Steam 集成元数据
cp <BROTATO>/steam_data.json ./
```

期望输出末尾：
```
Decompiled scripts:                     445
Failed scripts:                         0
Imported resources for export session:  2009
Successfully converted:                 2009
```

如果反编译失败，检查游戏版本：本项目的预期 vanilla 版本见
[`CLAUDE.md`](./CLAUDE.md#1-项目身份) 第 1 节。Brotato 更新后需要重新反编译。

### 4. 在 GodotSteam 中打开项目

```bash
# Linux/Mac：把 godotsteam 编辑器路径替换为你的
<path-to>/godotsteam.362.editor.x86_64

# 在编辑器中：Project Manager → Import → 选本项目根的 project.godot
```

首次打开会扫描 `.import/` 缓存（30 秒到几分钟），等右下角进度条停止再继续。

### 5. 按 F5 启动游戏验证

如果 Brotato 主菜单出现，点 "Mods" 能看到 `mods-unpacked/` 下的所有 mod —— 环境
搭建完成。

> 不需要 Export 项目。所有 mod 开发都在编辑器 F5 调试模式下进行，因为
> ModLoader 在编辑器中会直接读 `mods-unpacked/`，Export 模式下逻辑不同。

---

## 添加一个新 mod

### 1. 创建 mod 目录

```bash
mkdir -p mods-unpacked/<YourNamespace>-<YourModName>
cd mods-unpacked/<YourNamespace>-<YourModName>
```

**命名约定**（强制）：
- `<YourNamespace>` 和 `<YourModName>` 都不能含空格、不能含连字符 `-`
- 只用英文字符 `A-z`、数字 `0-9` 和下划线 `_`
- 全 ID 最终是 `<YourNamespace>-<YourModName>`（这是 Thunderstore + ModLoader 标准）

### 2. 创建 `manifest.json`

```json
{
    "name": "YourModName",
    "namespace": "YourNamespace",
    "version_number": "0.1.0",
    "description": "一句话描述 mod 的功能",
    "website_url": "https://github.com/<user>/brotato-mod",
    "dependencies": [],
    "extra": {
        "godot": {
            "authors": ["YourNamespace"],
            "tags": ["Utilities"],
            "description_rich": "",
            "optional_dependencies": [],
            "load_before": [],
            "incompatibilities": [],
            "compatible_mod_loader_version": ["6.3.0"],
            "compatible_game_version": ["1.1.15.0"],
            "config_schema": {}
        }
    }
}
```

可用的 `tags` 见项目根 `steam_data.json`：`Characters`、`Weapons`、`Items`、
`GUI`、`New Mechanics`、`Reworks`、`Cheats`、`Challenges`、`Utilities`、
`Translations`。

### 3. 创建 `mod_main.gd`

最小可用模板（**Brotato 是 Godot 3，不要用 Godot 4 的 `path_join()`**）：

```gdscript
extends Node

const MOD_DIR := "YourNamespace-YourModName"
const LOG_NAME := "YourNamespace-YourModName:Main"

var mod_dir_path := ""
var extensions_dir_path := ""

func _init() -> void:
    mod_dir_path = ModLoaderMod.get_unpacked_dir().plus_file(MOD_DIR)
    install_script_extensions()

func _ready() -> void:
    ModLoaderLog.info("Loaded", LOG_NAME)

func install_script_extensions() -> void:
    extensions_dir_path = mod_dir_path.plus_file("extensions")
    # ModLoaderMod.install_script_extension(extensions_dir_path.plus_file("singletons/run_data.gd"))
```

### 4. 按 F5 验证

新 mod 应该立即出现在主菜单的 "Mods" 列表里，并在
`~/.local/share/Brotato/logs/godot.log` 输出 `Loaded` 日志。

### 5. 在 README 顶部表格补一行

让其他人知道仓库里多了一个 mod。

---

## 目录结构

```
brotato-mod/                                  ← git 仓库根
│
├── README.md                                 ← 本文件（人类速查）
├── CLAUDE.md                                 ← AI 协作约定（环境/红线/工作流）
├── .gitignore                                ← 白名单防泄露
│
├── 🔒 [vanilla 反编译产物，不入 git]
│   ├── project.godot                         ← Godot 项目入口
│   ├── steam_data.json                       ← Steam 集成元数据
│   ├── main.gd, pause.gd, *.tscn             ← 游戏脚本与场景
│   ├── singletons/                           ← autoload 单例（RunData / ItemService / ...）
│   ├── weapons/, items/, entities/           ← 游戏内容
│   ├── ui/, resources/, ...                  ← UI 与资源
│   ├── addons/mod_loader/                    ← ModLoader（vanilla 内嵌）
│   └── .import/, .autoconverted/             ← Godot 资源缓存
│
└── mods-unpacked/                            ← ✅ 各 mod 开发目录（入 git）
    ├── fengyifan-AutoTato/
    │   ├── manifest.json
    │   └── mod_main.gd
    │
    └── <YourNamespace>-<YourModName>/        ← 新 mod 加在这里
        ├── manifest.json
        └── mod_main.gd
```

---

## 开发工作流

### 实时调试

在编辑器中改 mod 源码 → 按 F5 → 新代码立即生效（mod 在游戏启动时由 ModLoader
加载，所以必须重启游戏才能看到改动，编辑器热重载不适用于 mod）。

### 看日志

```bash
# Linux
tail -f ~/.local/share/Brotato/logs/godot.log

# 按 mod 过滤（替换 YourMod 为你的 LOG_NAME 前缀）
grep "YourMod" ~/.local/share/Brotato/logs/godot.log | tail -50
```

> Windows 路径：`%appdata%\Brotato\logs\godot.log`
> macOS 路径：`~/Library/Application Support/Brotato/logs/godot.log`

### DebugService

`debug_service.tscn` 是 Brotato 内置的开发工具，可以在 Inspector 中：
- **Disable Saving**（强烈推荐开启）— 防止开发过程中污染存档
- 修改起始材料、跳关、强制掉落特定物品

详见 [Brotato Wiki — Modding Notes](https://brotato.wiki.spellsandguns.com/Modding_Notes#DebugService)。

### 测试打包后的 ZIP

构建 mod ZIP（按 ModLoader 规范打包）并放到本地 Workshop 测试目录：

```bash
# Linux
mkdir -p ~/.steam/steam/steamapps/workshop/content/1942280/_local_test/
cp your-mod.zip ~/.steam/steam/steamapps/workshop/content/1942280/_local_test/

# 重启游戏，Brotato 会把 _local_test 当作"已订阅的 mod"加载
```

> ZIP 内部结构必须镜像 `mods-unpacked/`，详见
> [Mod Structure](https://wiki.godotmodding.com/guides/modding/mod_structure/)。

---

## 发布到 Steam Workshop

1. 在 Steam 中：右键 Brotato → Properties → Betas → 选择 **modding** 分支
2. 重启 Brotato，在启动选项中选 "Launch Uploader"（即 `GodotWorkshopUtility`）
3. 在 Uploader 中选你的 mod ZIP 和封面图（推荐 512×512px）
4. **首次发布**：留空 Workshop ID，发布后会自动分配
5. **更新已有 mod**：填入 Workshop ID（在 mod URL `?id=XXXXX` 中找）

> ⚠️ 不能直接双击 `GodotWorkshopUtility` 启动 — 必须从 Steam 启动才能注入
> Steam API。
>
> ⚠️ Workshop 上传账户需要在 Steam 累计消费 $5 USD 才有上传权限。

发布后默认是 Hidden 状态，需要登录 Workshop 网页改为 Public。

---

## 重要参考

### 官方文档
- **ModLoader Wiki** — https://wiki.godotmodding.com/
  - [Mod Files](https://wiki.godotmodding.com/guides/modding/mod_files/)（manifest 字段、mod_main 模板）
  - [Mod Structure](https://wiki.godotmodding.com/guides/modding/mod_structure/)（目录布局、ZIP 打包）
- **Brotato Modding Guide** — https://steamcommunity.com/sharedfiles/filedetails/?id=2931079751
- **Brotato Modding Help** — https://steamcommunity.com/sharedfiles/filedetails/?id=2937226054（mod 使用者向）

### 引擎文档
- **Godot 3.5 文档** — https://docs.godotengine.org/en/3.5/
  > 注意：Google 搜出来默认是 4.x。URL 里的 `/stable/` 替换为 `/3.5/` 才能看
  > 到对应 Brotato 引擎版本的 API。
- **GDScript 基础** — https://docs.godotengine.org/en/3.5/tutorials/scripting/gdscript/gdscript_basics.html

### 社区
- **BrotatoMods GitHub 组织** — https://github.com/BrotatoMods（社区集中地，标杆 mod）
- **Brotato Discord** — https://discord.com/invite/j39jE6k（`#modding-help` 频道）
- **Brotato Wiki — Modding Notes** — https://brotato.wiki.spellsandguns.com/Modding_Notes

### 工具
- **Mod Tool**（可选） — https://github.com/GodotModding/godot-mod-tool
  Godot 编辑器插件，提供 manifest 验证、骨架生成、ZIP 打包等便利功能。

---

## 已知陷阱

| 现象 | 原因 | 解决 |
|---|---|---|
| 用 vanilla Godot 打开报一堆 Steam API 错误 | Brotato 需要 GodotSteam | 改用 GodotSteam 3.6.x |
| 反编译后翻译丢了 188/1200 个 key | GDRE 已知限制 | 不影响游戏运行；如需精确翻译，从原 PCK 拷 CSV 覆盖 |
| F5 后大量 "Failed to load resource" | `.import/` 未扫完 | 等编辑器右下角进度条停止 |
| Mod 列表里没看到新 mod | 目录名不是 `Namespace-Name` 格式 | 检查命名约定（无空格、字符限制） |
| 改了 mod 代码但游戏行为没变 | mod 在启动时加载，无热重载 | 重启游戏（停止 → F5） |
| 切换 mod 列表后游戏崩溃 | 旧存档与新 mod 集不兼容 | 开新存档；备份在 `~/.local/share/Brotato/` |
| 在 git status 看到 vanilla 文件 | `.gitignore` 白名单失守 | 立刻停手，检查根的 `/*` 规则是否被破坏 |

---

## 贡献

如果想给本项目集合添加 mod 或改进现有 mod：

1. 先读 [`CLAUDE.md`](./CLAUDE.md) — 它有更详细的环境约定和安全红线
2. 在 `mods-unpacked/` 下创建你的 mod 目录（按上面"添加一个新 mod"流程）
3. 在 README 顶部 mod 表格补一行
4. 提交前用 `git add -A --dry-run` 验证白名单未失守
5. 提交信息建议遵循 [Conventional Commits](https://www.conventionalcommits.org/)
   （`feat(autotato): ...`、`fix(autotato): ...`、`chore: ...`）

---

## 许可证

各 mod 的许可证由 mod 作者自行声明（建议放在每个 mod 目录的 `LICENSE` 文件中）。

本仓库的项目级文档（README.md、CLAUDE.md、`.gitignore`、`docs/`、`scripts/`）
采用 MIT 许可证除非另有声明。

Brotato vanilla 代码版权归 Blobfish Studio 所有，不在本仓库分发。
