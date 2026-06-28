#!/usr/bin/env node
/**
 * check-staleness.js
 *
 * 检查 .claude/memory/*.md 文件是否可能过期。
 * 对比每个 memory 的 game_version 与当前项目版本。
 *
 * 用法: node check-staleness.js [--path <memory-dir>] [--current-version <ver>]
 */

const fs = require("fs");
const path = require("path");

// ── 简易 YAML 解析（与 parse-frontmatter.js 逻辑一致） ──

function parseSimpleYaml(yaml) {
    const result = {};
    const lines = yaml.split("\n");
    let currentKey = null;

    for (const line of lines) {
        if (line.trim() === "") continue;

        const kvMatch = line.match(/^(\w[\w_]*):\s*(.*)$/);
        if (kvMatch) {
            const key = kvMatch[1];
            let value = kvMatch[2].trim();

            if (value === ">" || value === "|") {
                result[key] = "";
                currentKey = key;
            } else if (value !== "") {
                result[key] = value;
                currentKey = null;
            } else {
                currentKey = null;
            }
            continue;
        }

        if (currentKey !== null) {
            const trimmed = line.trim();
            if (result[currentKey]) {
                result[currentKey] += " " + trimmed;
            } else {
                result[currentKey] = trimmed;
            }
        }
    }

    return result;
}

function parseFrontmatter(content) {
    const lines = content.split("\n");
    if (lines[0].trim() !== "---") return null;

    const endIdx = lines.indexOf("---", 1);
    if (endIdx === -1) return null;

    const yamlBlock = lines.slice(1, endIdx).join("\n");
    return parseSimpleYaml(yamlBlock);
}

// ── 主逻辑 ──

function main() {
    const args = process.argv.slice(2);
    const projectRoot = process.cwd();
    let memoryDir = path.join(projectRoot, ".claude", "memory");
    let currentVersion = null;

    for (let i = 0; i < args.length; i++) {
        if (args[i] === "--path" && i + 1 < args.length) {
            memoryDir = args[++i];
        } else if (args[i] === "--current-version" && i + 1 < args.length) {
            currentVersion = args[++i];
        }
    }

    if (!fs.existsSync(memoryDir)) {
        console.error(`Memory directory not found: ${memoryDir}`);
        process.exit(1);
    }

    if (!currentVersion) {
        currentVersion = "1.1.15.4"; // 已知当前版本，手动维护
    }

    const files = fs.readdirSync(memoryDir).filter(f => f.endsWith(".md"));
    const results = [];

    for (const file of files) {
        const filePath = path.join(memoryDir, file);
        const content = fs.readFileSync(filePath, "utf-8");
        const meta = parseFrontmatter(content);

        if (!meta) continue;

        const issues = [];

        // 检查版本是否匹配
        if (meta.game_version && meta.game_version !== currentVersion) {
            issues.push({
                type: "version_mismatch",
                detail: `记忆版本 ${meta.game_version} ≠ 当前版本 ${currentVersion}`
            });
        }

        results.push({
            file: file,
            title: meta.title || null,
            game_version: meta.game_version || null,
            issues: issues,
            stale: issues.length > 0
        });
    }

    console.log(JSON.stringify(results, null, 2));
}

main();
