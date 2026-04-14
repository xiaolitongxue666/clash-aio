#!/usr/bin/env bash
# 手动更新订阅（兜底）：重建 clash-with-ui 容器，使 preprocess 重新从 RAW_SUB_URL 拉取 config。
# 日常推荐优先使用 ./refresh-subscription.sh（无重启、不断连）。
# 用法: ./update-subscription.sh

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  COMPOSE_CMD="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE_CMD="docker-compose"
else
  echo "未找到 docker compose 或 docker-compose。"
  exit 1
fi

echo "正在重建 clash-with-ui 容器以重新拉取订阅..."
$COMPOSE_CMD up -d --force-recreate clash-with-ui
echo "已触发重建，订阅将重新拉取。可用: $COMPOSE_CMD logs -f clash-with-ui 查看进度。"
