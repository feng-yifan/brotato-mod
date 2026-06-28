#!/usr/bin/env bash
# ============================================================================
# pack-mod.sh — 将 mods-unpacked 下的单个 mod 打包为可发布 ZIP
# ============================================================================
#
# 用法:
#   ./scripts/pack-mod.sh <ModName>                    # 从 mods-unpacked/<...>-<ModName>/ 打包
#   ./scripts/pack-mod.sh <ModName> --output <dir>     # 指定输出目录（默认项目根）
#   ./scripts/pack-mod.sh <ModName> --no-dev           # 排除 dev/ 开发文件（默认行为）
#   ./scripts/pack-mod.sh <ModName> --with-dev         # 包含 dev/ 开发文件
#
# 示例:
#   ./scripts/pack-mod.sh AutoTato                     # → fengyifan-AutoTato-0.3.0.zip
#   ./scripts/pack-mod.sh AutoTato --output /tmp       # → /tmp/fengyifan-AutoTato-0.3.0.zip
#
# 输出 ZIP 结构 (符合 ModLoader 标准):
#   fengyifan-AutoTato-0.3.0.zip
#   ├── .import/               ← 自定义资源的导入元数据
#   └── mods-unpacked/
#       └── fengyifan-AutoTato/
#           ├── mod_main.gd
#           ├── manifest.json
#           ├── translations/
#           └── autotato/
#
# ============================================================================

set -euo pipefail

# ── 参数解析 ────────────────────────────────────────────────────────────────

MOD_NAME="${1:-}"
if [[ -z "$MOD_NAME" ]]; then
    echo "用法: $0 <ModName> [--output <dir>] [--with-dev]"
    echo "示例: $0 AutoTato"
    exit 1
fi
shift

OUTPUT_DIR="."
INCLUDE_DEV=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --with-dev)
            INCLUDE_DEV=true
            shift
            ;;
        --no-dev)
            INCLUDE_DEV=false
            shift
            ;;
        *)
            echo "未知参数: $1"
            exit 1
            ;;
    esac
done

# ── 路径计算 ────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MODS_DIR="$PROJECT_ROOT/mods-unpacked"

# 查找匹配 ModName 的目录（格式: <Namespace>-<ModName>）
MOD_DIR=$(find "$MODS_DIR" -maxdepth 1 -type d -name "*-$MOD_NAME" | head -1)
if [[ -z "$MOD_DIR" ]]; then
    echo "错误: 在 $MODS_DIR 下找不到匹配 '*-$MOD_NAME' 的目录"
    exit 1
fi

MOD_DIR_NAME=$(basename "$MOD_DIR")
NAMESPACE="${MOD_DIR_NAME%-$MOD_NAME}"

# 从 manifest.json 读取版本号
MANIFEST="$MOD_DIR/manifest.json"
if [[ ! -f "$MANIFEST" ]]; then
    echo "错误: 找不到 $MANIFEST"
    exit 1
fi

VERSION=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['version_number'])" "$MANIFEST")
ZIP_NAME="${NAMESPACE}-${MOD_NAME}-${VERSION}.zip"
ZIP_OUTPUT="$OUTPUT_DIR/$ZIP_NAME"

echo "═══════════════════════════════════════════════════════════"
echo "  打包 mod: $MOD_NAME"
echo "  命名空间: $NAMESPACE"
echo "  Mod ID:   $MOD_DIR_NAME"
echo "  版本号:   $VERSION"
echo "  源目录:   $MOD_DIR"
echo "  输出:     $ZIP_OUTPUT"
if $INCLUDE_DEV; then
    echo "  开发文件: 包含 (--with-dev)"
else
    echo "  开发文件: 排除 (dev/)"
fi
echo "═══════════════════════════════════════════════════════════"

# ── 构建临时目录 ────────────────────────────────────────────────────────────

TEMP_DIR=$(mktemp -d)
trap '\rm -rf "$TEMP_DIR"' EXIT

# ZIP 顶层结构: mods-unpacked/<ModDirName>/  (符合 ModLoader 标准)
PACK_ROOT="$TEMP_DIR/mods-unpacked/$MOD_DIR_NAME"
mkdir -p "$PACK_ROOT"

# ── 复制 mod 文件 ──────────────────────────────────────────────────────────

RSYNC_EXCLUDE=(
    --exclude '.git'
    --exclude '*.tmp'
    --exclude '*.tmp.gd'
)
if ! $INCLUDE_DEV; then
    RSYNC_EXCLUDE+=(--exclude 'dev/')
    echo "• 排除 dev/ 目录"
fi

echo "• 复制 mod 文件 → mods-unpacked/$MOD_DIR_NAME/"
rsync -a "${RSYNC_EXCLUDE[@]}" "$MOD_DIR/" "$PACK_ROOT/"

# ── 收集自定义资源的 .import 元数据 ────────────────────────────────────────

# Godot 3 在项目根 .import/ 目录下为每个导入资源生成 <name>-<hash>.md5 元数据文件。
# 发布 ZIP 需要包含 mod 自定义资源的 import 记录，否则终端用户的 Godot 不知道
# 这些资源已被导入。
#
# 查找策略：扫描 mod 内所有有 .import 伴生文件的资源，在 .import/ 中匹配对应的
# <basename>-<hash>.md5 文件。.import 文件名前缀 = 资源的 base name（不含路径）。

IMPORT_DIR="$PROJECT_ROOT/.import"
IMPORT_TEMP="$TEMP_DIR/.import"
IMPORT_COUNT=0

if [[ -d "$IMPORT_DIR" ]]; then
    mkdir -p "$IMPORT_TEMP"

    # 收集 mod 内所有 .import 伴生文件的资源名
    # 例如 translations/autotato.csv → basename = autotato.csv
    while IFS= read -r -d '' companion; do
        companion_name="$(basename "$companion")"
        # 去掉尾部的 .import 得到原始资源名: autotato.csv.import → autotato.csv
        resource_name="${companion_name%.import}"

        # 在 .import/ 中查找以此资源名开头的 .md5 文件
        # 格式: <resource_name>-<hash>.md5
        for imp_file in "$IMPORT_DIR"/"$resource_name"-*.md5; do
            if [[ -f "$imp_file" ]]; then
                \cp "$imp_file" "$IMPORT_TEMP/"
                IMPORT_COUNT=$((IMPORT_COUNT + 1))
                echo "  + .import/$(basename "$imp_file")"
            fi
        done
    done < <(find "$MOD_DIR" -type f -name "*.import" -print0)
fi

if [[ $IMPORT_COUNT -gt 0 ]]; then
    echo "• 已包含 $IMPORT_COUNT 个 .import 元数据文件"
else
    echo "• 无自定义 .import 元数据需要包含"
    # 清理空的 .import 目录
    rmdir "$IMPORT_TEMP" 2>/dev/null || true
fi

# ── 生成 ZIP ────────────────────────────────────────────────────────────────

echo "• 创建 ZIP ..."
ZIP_ABS_PATH="$(cd "$OUTPUT_DIR" && pwd)/$ZIP_NAME"
\rm -f "$ZIP_ABS_PATH"

cd "$TEMP_DIR"
# 从 TEMP_DIR 打包，顶层就是 mods-unpacked/ 和（可选的）.import/
zip -r "$ZIP_ABS_PATH" mods-unpacked/ .import/ 2>/dev/null || zip -r "$ZIP_ABS_PATH" mods-unpacked/
cd "$PROJECT_ROOT"

# ── 输出摘要 ────────────────────────────────────────────────────────────────

FILE_COUNT=$(unzip -l "$ZIP_ABS_PATH" | tail -1 | awk '{print $2}')
SIZE=$(du -h "$ZIP_ABS_PATH" | cut -f1)

echo ""
echo "✅ 打包完成: $ZIP_NAME"
echo "   文件数: $FILE_COUNT"
echo "   大小:   $SIZE"
echo "   路径:   $ZIP_ABS_PATH"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  📦 如何测试此 ZIP："
echo ""
echo "  方法 1 — Godot 编辑器 (日常开发):"
echo "    编辑器 F5 → 自动从 mods-unpacked/ 加载，无需 ZIP"
echo ""
echo "  方法 2 — 借用已订阅 Workshop 插槽 (快速验证 ZIP 结构):"
echo "    cd ~/.local/share/Steam/steamapps/workshop/content/1942280/<数字ID>/"
echo "    \\mv mod.zip mod.zip.bak"
echo "    \\cp $ZIP_ABS_PATH mod.zip"
echo "    启动游戏 → 检查日志 ~/.local/share/Brotato/logs/godot.log"
echo "    验证完后: \\mv mod.zip.bak mod.zip"
echo ""
echo "  方法 3 — Steam Workshop 上传 (发布前最终验证):"
echo "    在 Steamworks 中上传为 unlisted，通过 Steam 客户端订阅加载"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
