# CLAUDE.md — brotato-mod 项目 Claude Code 指南

## 1. 项目身份

| 项目 | brotato-mod |
|---|---|
| 定位 | **Brotato mod 集合项目**，在统一工作目录下并行开发多个 mod |
| 目标游戏 | Brotato (Steam app_id `1942280`) |
| Godot 引擎版本 | 3.6.x (GodotSteam 定制版) |
| ModLoader 版本 | 6.3.0（已内嵌在 Brotato vanilla 中） |
| Brotato 游戏版本 | 1.1.15.4 |

### 当前包含的 mod

| Mod ID | 状态  | 简介 |
|---|-----|---|
| `fengyifan-AutoTato` | 已发布 | 自动化与体验增强 |

## 2. 目录结构

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

## 3. 重要参考

- ModLoader Wiki: https://wiki.godotmodding.com/
- Brotato Modding Guide: https://steamcommunity.com/sharedfiles/filedetails/?id=2931079751
- Brotato Modding Help: https://steamcommunity.com/sharedfiles/filedetails/?id=2937226054
- Brotato Wiki Modding Notes: https://brotato.wiki.spellsandguns.com/Modding_Notes
- Brotato Wiki Modding Effects: https://brotato.wiki.spellsandguns.com/Modding_Effects
- Brotato Wiki Items Grid: https://brotato.wiki.spellsandguns.com/Items/Items_Grid
- Godot 3.5 文档: https://docs.godotengine.org/en/3.5/ （注意：搜索默认进 4.x，要手改 URL）
- BrotatoMods GitHub 组织: https://github.com/BrotatoMods
- Brotato Discord (#modding-help): https://discord.com/invite/j39jE6k

## 4. 架构原则

### 配置默认值由 config 层返回

配置的默认值(包括"未配置时的回退值")统一由 `config/` 层负责返回。外部调用方(decider、shop_automation 等)拿到的永远是最终可用值,不需要考虑空值、未配置、字段缺失等情况。

- ✅ 正确:外部调 `cfg.get_xxx(...)` 直接拿到最终动作/值
- ❌ 错误:外部自己处理 `if null` / `if 未配置` / `if follow_set_rule` 这类回退

理由:把"数据缺失处理"收拢到 config 层,降低外部复杂度,默认值变更只需改 config 一处。

典型示例:`config.gd` 的 `get_weapon_action(weapon_data)` 内部完成"武器自身规则 → 类别规则 → 默认 manual"的完整回退链,decider 调用它后直接拿到 `{action: "manual"|"skip"}`,不再做任何回退判断。
