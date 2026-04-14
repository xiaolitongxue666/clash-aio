#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# clash-aio 一键停止
# 用法：在 clash-aio 目录执行 ./stop.sh
# ---------------------------------------------------------------------------

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  COMPOSE_CMD="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE_CMD="docker-compose"
else
  echo "错误：未找到 docker compose 或 docker-compose。"
  exit 1
fi

COMPOSE_FILE="docker-compose.yaml"
[ -f "$COMPOSE_FILE" ] || { echo "错误：未找到 $COMPOSE_FILE"; exit 1; }

echo "正在停止容器..."
$COMPOSE_CMD -f "$COMPOSE_FILE" down 2>/dev/null || true
echo "已停止。"
