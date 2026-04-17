#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# clash-aio：停止并移除本仓库 docker-compose.yaml 定义的栈（docker compose down）
# 用法：在 clash-aio 目录执行 ./clash-compose-down.sh
# ---------------------------------------------------------------------------

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# shellcheck disable=SC1091
. "${SCRIPT_DIR}/clash-compose-cmd.inc.sh"
clash_compose_require || exit 1

echo "正在停止容器..."
$COMPOSE_CMD -f "$COMPOSE_FILE" down 2>/dev/null || true
echo "已停止。"
