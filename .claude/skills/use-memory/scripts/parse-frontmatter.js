#!/usr/bin/env node
/**
 * parse-frontmatter.js
 *
 * 解析 .claude/memory/*.md 文件的 YAML frontmatter，输出 JSON 到 stdout。
 *
 * 用法: node parse-frontmatter.js [--path <memory-dir>]
 */

const fs = require("fs");
const path = require("path");

// ── 简易 YAML 解析（仅支持 string key/value，支持 YAML 多行 > 折叠） ──

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

            // YAML ">" 折叠多行标记：后续缩进行是连续文本
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

        // 多行续行（缩进后的文本）
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

// ── 主逻辑 ──

function parseFrontmatter(content) {
    const lines = content.split("\n");
    if (lines[0].trim() !== "---") return null;

    const endIdx = lines.indexOf("---", 1);
    if (endIdx === -1) return null;

    const yamlBlock = lines.slice(1, endIdx).join("\n");
    return parseSimpleYaml(yamlBlock);
}

function main() {
    const args = process.argv.slice(2);
    let memoryDir = path.join(process.cwd(), ".claude", "memory");

    for (let i = 0; i < args.length; i++) {
        if (args[i] === "--path" && i + 1 < args.length) {
            memoryDir = args[++i];
        }
    }

    if (!fs.existsSync(memoryDir)) {
        console.error(`Memory directory not found: ${memoryDir}`);
        process.exit(1);
    }

    const files = fs.readdirSync(memoryDir).filter(f => f.endsWith(".md"));
    const results = [];

    for (const file of files) {
        const filePath = path.join(memoryDir, file);
        const content = fs.readFileSync(filePath, "utf-8");
        const meta = parseFrontmatter(content);

        if (meta) {
            meta._file = file;
            meta._path = filePath;
            results.push(meta);
        }
    }

    console.log(JSON.stringify(results, null, 2));
}

main();
