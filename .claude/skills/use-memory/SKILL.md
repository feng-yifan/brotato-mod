---
name: use-memory
description: >
  管理 .claude/memory/ 中的项目长期知识库。
  此技能应在每次开始项目任务时使用——它首先加载所有 memory 文件的 YAML frontmatter 索引，
  然后根据用户意图按需加载相关 memory 文件进入上下文，最后在代码修改后检查版本一致性。
  当用户讨论 brotato-mod 项目、修改代码、查询架构、或任何需要了解项目背景的工作时，
  都必须先调用此技能获取相关记忆。
---

# use-memory — 项目记忆管理

## 概述

`.claude/memory/` 目录存储项目的长期知识，每个 `.md` 文件以 YAML frontmatter 声明其
内容元数据。此技能通过三个步骤管理这些记忆：

1. **加载索引** — 解析所有 frontmatter，获得轻量知识地图
2. **按需加载** — 根据用户意图匹配并加载相关记忆
3. **版本检查** — 代码修改后检查记忆版本一致性

---

## Phase 1: 加载记忆索引

运行 `scripts/parse-frontmatter.js`，扫描 `.claude/memory/*.md` 的所有 YAML frontmatter。

此脚本输出 JSON 数组，每个元素包含：

| 字段 | 说明 |
|---|---|
| `title` | 记忆的人类可读标题 |
| `description` | 此记忆覆盖的知识范围（含领域和关键词） |
| `game_version` | 内容对应的游戏版本 |
| `_file` | 文件名 |
| `_path` | 文件完整路径 |

索引约 1KB，始终保持在工作上下文中。

---

## Phase 2: 按需加载记忆

将用户当前任务意图与索引中每个记忆的 `description` 进行语义匹配。

### 匹配规则

- 任务涉及 `description` 中描述的知识范围 → **加载该 memory 完整内容**
- 任务与所有 memory 均无明确关联 → **不加载**（节约上下文）

### 加载方式

匹配到的 memory 文件，使用 Read 工具读取其**完整 Markdown 内容**。
记忆中的知识应作为本次任务的基础上下文使用。

当用户明确询问某个记忆文件的内容时，也应加载对应的完整 memory。

---

## 记忆维护

代码修改完成后，审视本次修改过程中是否产生了新的认识——这些认识如果不在记忆里，
下次遇到同类问题时可能走同样的弯路。

### 判断是否需要更新

将本次修改中获得的新认识与 Phase 1 索引中每个 memory 的 `description` 做语义匹配：

- 新认识被某个 memory 的 `description` 覆盖 → **更新该 memory**，在文件中追加新内容
- 新认识跨越多个 memory 的范围 → **分别更新对应的 memory**
- 新认识不属于任何 memory 的 `description` 覆盖范围 → **新建 memory 文件**

### 如何更新

追加新内容而非重写，保留历史演变痕迹。`game_version` 仅在内容对应的版本变化时修改。

### 新建模板

```markdown
---
title: <人类可读标题>
description: >
  <知识范围描述，用通顺的文字表达>
game_version: <对应版本>
---

# <标题>

---
```
