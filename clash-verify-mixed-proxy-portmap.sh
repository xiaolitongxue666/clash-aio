#!/usr/bin/env bash
# 在宿主机上经 Docker 映射端口测试「容器内 Clash」混合代理是否可用
# （流量: 宿主机 127.0.0.1:宿主机端口 -> 容器 mixed-port 7890 -> 外网）
# 用法:
#   ./clash-verify-mixed-proxy-portmap.sh           # 从 .env / .env.example 读 ALL_PROXY_PORT（见 clash-env.inc.sh）
#   ./clash-verify-mixed-proxy-portmap.sh 7892      # 指定宿主机映射端口
#   PROXY_PORT=7892 ./clash-verify-mixed-proxy-portmap.sh  # 环境变量覆盖 .env
# 可选环境变量: PROXY_PORT, TEST_URL（默认 http://ip-api.com/json/，免密钥）

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/clash-env.inc.sh"

if [ -n "$1" ] && [[ "$1" =~ ^[0-9]+$ ]]; then
  PROXY_PORT="$1"
elif [ -n "${PROXY_PORT:-}" ]; then
  :
else
  PROXY_PORT="$ALL_PROXY_PORT"
fi

PROXY_URL="http://127.0.0.1:${PROXY_PORT}"
TEST_URL="${TEST_URL:-http://ip-api.com/json/}"

echo "宿主机映射端口 -> 容器 Clash mixed: ${PROXY_PORT} -> 7890（与 docker-compose 中 ALL_PROXY_PORT 一致）"
echo "代理地址: ${PROXY_URL}"
echo "检测端口: ${PROXY_PORT}"
echo "请求: ${TEST_URL}"
echo ""

# 检查端口是否在监听
if ! bash -c "echo >/dev/tcp/127.0.0.1/${PROXY_PORT}" 2>/dev/null; then
  echo "失败: 端口 ${PROXY_PORT} 未监听，请确认容器已启动且映射了该端口。"
  exit 1
fi
echo "端口 ${PROXY_PORT} 已监听"
echo ""

# 通过代理请求，-w "\n%{http_code}" 使最后一行为状态码
resp=$(curl -x "${PROXY_URL}" -s -w "\n%{http_code}" --connect-timeout 10 "${TEST_URL}" 2>/dev/null) || true
code=$(echo "$resp" | tail -n1)
body=$(echo "$resp" | sed '$d')

echo "--- curl 返回 (HTTP ${code}) ---"
echo "$body"
echo "---"

if [ "$code" = "200" ]; then
  echo "结果: 成功  容器内 Clash 经映射端口工作正常；系统/应用可设 HTTP 代理为 127.0.0.1:${PROXY_PORT}"
  exit 0
else
  echo "结果: 失败  (HTTP ${code} 或请求超时)"
  echo "请检查: docker compose ps / docker compose logs clash-with-ui"
  exit 1
fi
