#!/usr/bin/env bash
# 在宿主机上测试容器内 Clash 代理是否可用
# 用法:
#   ./test-proxy.sh           # 默认端口 7890
#   ./test-proxy.sh 7892      # 指定端口
#   PROXY_PORT=7892 ./test-proxy.sh
# 可选环境变量: PROXY_PORT, TEST_URL(默认 https://ipinfo.io)

PROXY_PORT="${PROXY_PORT:-7890}"
[ -n "$1" ] && [[ "$1" =~ ^[0-9]+$ ]] && PROXY_PORT="$1"

PROXY_URL="http://127.0.0.1:${PROXY_PORT}"
TEST_URL="${TEST_URL:-https://ipinfo.io}"

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
  echo "结果: 成功  代理可用，可将系统或应用代理设为 127.0.0.1:${PROXY_PORT}"
  exit 0
else
  echo "结果: 失败  (HTTP ${code} 或请求超时)"
  echo "请检查: docker compose ps / docker compose logs clash-with-ui"
  exit 1
fi
