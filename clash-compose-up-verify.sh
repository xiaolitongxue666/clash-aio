#!/usr/bin/env bash
# clash-aio：检查 .env、启动 Docker Compose 栈、就绪与代理验证（日常推荐）
# 用法：在项目目录执行 ./clash-compose-up-verify.sh
# 流程：source clash-env.inc.sh → 校验 RAW_SUB_URL → clash_require_env_ports_free_for_compose_up
# （ALL_PROXY_PORT / CONTROL_PANEL_PORT / SUBCONVERTER_HOST_PORT 在宿主机被占用且非本栈映射则醒目退出，不自动改 .env）→ compose up -d → 轮询 /version 与代理探测。
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/clash-env.inc.sh"

PROXY_PORT="$ALL_PROXY_PORT"
PANEL_PORT="$CONTROL_PANEL_PORT"

if [ ! -f .env ]; then
  cp .env.example .env
  echo "已从 .env.example 创建 .env，请编辑 .env 填写 RAW_SUB_URL 后重新运行本脚本。"
  exit 1
fi

if ! grep -qE '^RAW_SUB_URL=.+' .env; then
  echo "请在 .env 中设置 RAW_SUB_URL=你的订阅地址 后重新运行本脚本。"
  exit 1
fi

if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  COMPOSE_CMD="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE_CMD="docker-compose"
else
  echo "未找到 docker compose 或 docker-compose，请确保 Docker Desktop 已安装并启动。"
  exit 1
fi

# 与 .env 冲突的宿主机端口：醒目报错并退出（若已是本栈 docker 映射则放行）
clash_require_env_ports_free_for_compose_up

echo "正在启动容器..."
$COMPOSE_CMD up -d

echo "等待服务就绪..."
MAX_WAIT=90
waited=0
while [ $waited -lt $MAX_WAIT ]; do
  if docker inspect -f '{{.State.Running}}' clash-with-ui 2>/dev/null | grep -q 'true'; then
    # Clash external-controller 根路径常非 200；用 REST /version 判断控制面就绪
    code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 "http://127.0.0.1:${PANEL_PORT}/version" 2>/dev/null || true)
    if [ "$code" = "200" ] || [ "$code" = "401" ]; then
      break
    fi
  fi
  sleep 2
  waited=$((waited + 2))
done

if [ $waited -ge $MAX_WAIT ]; then
  echo "等待超时，请检查容器状态：$COMPOSE_CMD ps 与 $COMPOSE_CMD logs clash-with-ui"
fi

echo ""
echo "--- 容器状态 ---"
$COMPOSE_CMD ps

echo ""
if docker exec clash-with-ui test -f /root/.config/clash/config.yaml 2>/dev/null; then
  echo "订阅已拉取：config.yaml 已生成"
else
  echo "若控制面板无法使用，可查看日志：$COMPOSE_CMD logs -f clash-with-ui"
fi

if curl -x "http://127.0.0.1:${PROXY_PORT}" -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "https://www.gstatic.com/generate_204" 2>/dev/null | grep -q '204'; then
  echo "代理验证通过 (127.0.0.1:${PROXY_PORT})"
else
  echo "代理端口: 127.0.0.1:${PROXY_PORT}（可选：用浏览器或 curl 自行验证）"
fi

echo ""
echo "控制面板: http://localhost:${PANEL_PORT}/ui"
echo "  (YACD 中 API 地址可填 host.docker.internal 或 127.0.0.1)"
echo ""

if command -v cmd >/dev/null 2>&1; then
  cmd //c start "http://localhost:${PANEL_PORT}/ui" 2>/dev/null || true
elif command -v start >/dev/null 2>&1; then
  start "http://localhost:${PANEL_PORT}/ui" 2>/dev/null || true
fi
