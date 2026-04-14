#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# 检测宿主机端口是否已被占用（避免与宿主机 proxy 如 localhost:7890 冲突）
port_in_use() {
  local port=$1
  if bash -c "echo >/dev/tcp/127.0.0.1/$port" 2>/dev/null; then
    return 0
  fi
  if command -v netstat >/dev/null 2>&1; then
    netstat -an 2>/dev/null | grep -qE "[.:]${port}[^0-9].*LISTEN" && return 0
  fi
  return 1
}

PROXY_PORT=7890
PANEL_PORT=9090
if [ -f .env ]; then
  val=$(grep -E '^ALL_PROXY_PORT=' .env 2>/dev/null | cut -d= -f2); [ -n "$val" ] && PROXY_PORT="$val"
  val=$(grep -E '^CONTROL_PANEL_PORT=' .env 2>/dev/null | cut -d= -f2); [ -n "$val" ] && PANEL_PORT="$val"
fi

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

# 若宿主机代理端口已被占用，自动选用空闲端口并写回 .env
NEED_RESTART=0
if port_in_use "${PROXY_PORT}"; then
  echo "检测到宿主机端口 ${PROXY_PORT} 已被占用（如宿主机 proxy），正在寻找空闲端口..."
  for p in 7891 7892 7893 7894 7895 7896 7897 7898 7899; do
    if ! port_in_use "$p"; then
      echo "使用端口 ${p} 作为容器代理端口，已更新 .env"
      if sed -i.bak "s/^ALL_PROXY_PORT=.*/ALL_PROXY_PORT=${p}/" .env 2>/dev/null || \
         sed -i.bak "s/^ALL_PROXY_PORT=.*/ALL_PROXY_PORT=${p}/" .env; then
        PROXY_PORT=$p
        NEED_RESTART=1
        break
      fi
    fi
  done
  if [ "$NEED_RESTART" -eq 0 ]; then
    echo "未找到 7891–7899 范围内的空闲端口，请手动在 .env 中设置 ALL_PROXY_PORT 后重试。"
    exit 1
  fi
fi

if [ "$NEED_RESTART" -eq 1 ]; then
  echo "正在重启容器以应用新端口..."
  $COMPOSE_CMD down 2>/dev/null || true
fi

echo "正在启动容器..."
$COMPOSE_CMD up -d

echo "等待服务就绪..."
MAX_WAIT=90
waited=0
while [ $waited -lt $MAX_WAIT ]; do
  if docker inspect -f '{{.State.Running}}' clash-with-ui 2>/dev/null | grep -q 'true'; then
    code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 "http://127.0.0.1:${PANEL_PORT}" 2>/dev/null || true)
    if [ "$code" = "200" ] || [ "$code" = "301" ] || [ "$code" = "302" ]; then
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
