#!/usr/bin/env bash
# ============================================================================
# reset-changelog-state.sh - 删除更新说明弹窗的"已关闭版本"记录
# ============================================================================
#
# 删除 user://fengyifan-AutoTato/changelog_state.txt, 让下次启动游戏时更新
# 说明弹窗重新弹出。用于反复测试弹窗功能, 无需手动翻找 user 目录。
#
# 用法:
#   ./scripts/reset-changelog-state.sh                # 删除记录(若存在)
#   ./scripts/reset-changelog-state.sh --status       # 仅查看状态, 不删除
#
# 路径说明 (Brotato project.godot: config/name="Brotato", use_custom_user_dir=true):
#   Linux:   ~/.local/share/Brotato/fengyifan-AutoTato/changelog_state.txt
#   macOS:   ~/Library/Application Support/Brotato/fengyifan-AutoTato/changelog_state.txt
#   Windows: %APPDATA%/Brotato/fengyifan-AutoTato/changelog_state.txt
#
# ============================================================================

set -euo pipefail

MOD_DIR="fengyifan-AutoTato"
STATE_FILE="changelog_state.txt"

# ── 探测 Brotato user 目录 ──────────────────────────────────────────────────
detect_user_dir() {
	case "$(uname -s)" in
		Linux*)
			echo "${HOME}/.local/share/Brotato"
			;;
		Darwin*)
			echo "${HOME}/Library/Application Support/Brotato"
			;;
		MINGW*|MSYS*|CYGWIN*)
			echo "${APPDATA}/Brotato"
			;;
		*)
			echo "${HOME}/.local/share/Brotato"
			;;
	esac
}

USER_DIR="$(detect_user_dir)"
STATE_PATH="${USER_DIR}/${MOD_DIR}/${STATE_FILE}"

# ── --status: 仅查看 ────────────────────────────────────────────────────────
if [[ "${1:-}" == "--status" ]]; then
	if [[ -f "${STATE_PATH}" ]]; then
		echo "状态文件存在: ${STATE_PATH}"
		echo "已关闭版本号: $(cat "${STATE_PATH}")"
	else
		echo "状态文件不存在: ${STATE_PATH}"
		echo "(下次启动游戏会弹出更新说明)"
	fi
	exit 0
fi

# ── 删除记录 ─────────────────────────────────────────────────────────────────
if [[ -f "${STATE_PATH}" ]]; then
	\rm -f "${STATE_PATH}"
	echo "已删除: ${STATE_PATH}"
	echo "下次启动游戏将重新弹出更新说明弹窗。"
else
	echo "状态文件本就不存在: ${STATE_PATH}"
	echo "(下次启动游戏本就会弹出更新说明弹窗)"
fi
