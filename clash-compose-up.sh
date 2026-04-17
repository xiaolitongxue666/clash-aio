#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# clash-aio：启动 Docker Compose 栈（薄封装，逻辑见 clash-aio-local.sh up）
# 用法：./clash-compose-up.sh [PROXY_PORT]
# ---------------------------------------------------------------------------

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$SCRIPT_DIR/clash-aio-local.sh" up "$@"
