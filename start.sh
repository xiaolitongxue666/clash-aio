#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# clash-aio 一键启动（可指定代理端口）
# 用法：./start.sh [PROXY_PORT]
#   例：./start.sh       使用 .env 中的 ALL_PROXY_PORT（默认 7890）
#       ./start.sh 7891  使用代理端口 7891 并写回 .env
# ---------------------------------------------------------------------------

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# 检测 Docker Compose V2
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

# 若传入端口参数，更新 .env 中的 ALL_PROXY_PORT
if [ -n "$1" ]; then
  PROXY_PORT="$1"
  [ -f .env ] || { [ -f .env.example ] && cp .env.example .env; }
  if grep -q '^ALL_PROXY_PORT=' .env 2>/dev/null; then
    sed -i.bak "s/^ALL_PROXY_PORT=.*/ALL_PROXY_PORT=${PROXY_PORT}/" .env
  else
    echo "ALL_PROXY_PORT=${PROXY_PORT}" >> .env
  fi
  echo "使用代理端口: ${PROXY_PORT}"
fi

# 确保 .env 存在且含 RAW_SUB_URL
if [ ! -f .env ]; then
  [ -f .env.example ] && cp .env.example .env
  echo "已从 .env.example 创建 .env，请编辑 .env 填写 RAW_SUB_URL 后重新运行。"
  exit 1
fi
if ! grep -qE '^RAW_SUB_URL=.+' .env 2>/dev/null; then
  echo "请在 .env 中设置 RAW_SUB_URL=你的订阅地址 后重新运行。"
  exit 1
fi

echo "正在启动容器..."
$COMPOSE_CMD -f "$COMPOSE_FILE" down 2>/dev/null || true
$COMPOSE_CMD -f "$COMPOSE_FILE" up -d

echo "已启动。控制面板端口见 .env 中 CONTROL_PANEL_PORT（默认 9090）。"
echo "验证可执行: ./run-and-verify.sh 或 docker compose -f $COMPOSE_FILE ps"
