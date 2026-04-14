#!/usr/bin/env bash
# 最小代价更新订阅：宿主机拉取 config，写入容器并触发 Clash 重载，不重启容器。
# 用法: ./refresh-subscription.sh
# 失败时可改用: ./update-subscription.sh 重建容器
# 容器内订阅 yaml 路径（与 preprocess.sh / Clash 一致）
CLASH_CONFIG_PATH="/root/.config/clash/config.yaml"

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

CONTROL_PANEL_PORT=9090
SUBCONVERTER_PORT=25500
ALL_PROXY_PORT=7890
if [ -f .env ]; then
  val=$(grep -E '^CONTROL_PANEL_PORT=' .env 2>/dev/null | cut -d= -f2); [ -n "$val" ] && CONTROL_PANEL_PORT="$val"
  val=$(grep -E '^ALL_PROXY_PORT=' .env 2>/dev/null | cut -d= -f2); [ -n "$val" ] && ALL_PROXY_PORT="$val"
fi

if [ ! -f .env ]; then
  echo "未找到 .env，请先复制 .env.example 为 .env 并设置 RAW_SUB_URL。"
  exit 1
fi
RAW_SUB_URL=$(grep -E '^RAW_SUB_URL=' .env 2>/dev/null | cut -d= -f2-)
if [ -z "$RAW_SUB_URL" ]; then
  echo "请在 .env 中设置 RAW_SUB_URL。"
  exit 1
fi

# URL 编码，与 preprocess.sh 行为一致
if echo "${RAW_SUB_URL}" | grep -q '[:/\?&=]'; then
  ENCODED_URL=$(echo "${RAW_SUB_URL}" | sed -e 's/%/%25/g' \
    -e 's/ /%20/g' -e 's/!/%21/g' -e 's/"/%22/g' -e 's/#/%23/g' -e 's/\$/%24/g' \
    -e 's/&/%26/g' -e "s/'/%27/g" -e 's/(/%28/g' -e 's/)/%29/g' -e 's/\*/%2A/g' \
    -e 's/+/%2B/g' -e 's/,/%2C/g' -e 's/\//%2F/g' -e 's/:/%3A/g' -e 's/;/%3B/g' \
    -e 's/=/%3D/g' -e 's/?/%3F/g' -e 's/@/%40/g' -e 's/\[/%5B/g' -e 's/\]/%5D/g')
else
  ENCODED_URL="${RAW_SUB_URL}"
fi

# 检查 subconverter 与 Clash API 可用
if ! curl -s -o /dev/null -w "%{http_code}" --connect-timeout 3 "http://127.0.0.1:${SUBCONVERTER_PORT}/version" 2>/dev/null | grep -q '200'; then
  echo "无法访问 subconverter (127.0.0.1:${SUBCONVERTER_PORT})，请确认容器已启动。"
  echo "可尝试: ./update-subscription.sh 重建容器"
  exit 1
fi
if ! curl -s -o /dev/null -w "%{http_code}" --connect-timeout 3 "http://127.0.0.1:${CONTROL_PANEL_PORT}/configs" 2>/dev/null | grep -qE '200|401'; then
  echo "无法访问 Clash API (127.0.0.1:${CONTROL_PANEL_PORT})，请确认 clash-with-ui 容器已启动。"
  echo "可尝试: ./update-subscription.sh 重建容器"
  exit 1
fi

TMP_CONFIG=$(mktemp 2>/dev/null || echo "/tmp/clash-config-$$.yaml")
trap 'rm -f "$TMP_CONFIG"' EXIT

echo "正在从 subconverter 拉取订阅..."
if ! curl -s -o "$TMP_CONFIG" --connect-timeout 30 "http://127.0.0.1:${SUBCONVERTER_PORT}/sub?target=clash&url=${ENCODED_URL}"; then
  echo "拉取订阅失败。可尝试: ./update-subscription.sh 重建容器"
  exit 1
fi
if [ ! -s "$TMP_CONFIG" ]; then
  echo "拉取结果为空。可尝试: ./update-subscription.sh 重建容器"
  exit 1
fi

echo "正在写入容器并重载 Clash..."
if ! docker cp "$TMP_CONFIG" clash-with-ui:"${CLASH_CONFIG_PATH}" 2>/dev/null; then
  echo "写入容器失败，请确认 clash-with-ui 容器在运行。可尝试: ./update-subscription.sh 重建容器"
  exit 1
fi
# Dreamacro Clash 要求 PUT /configs 带 body 指定 config 路径
code=$(curl -s -o /dev/null -w "%{http_code}" -X PUT "http://127.0.0.1:${CONTROL_PANEL_PORT}/configs" \
  -H "Content-Type: application/json" \
  -d "{\"path\":\"${CLASH_CONFIG_PATH}\"}" 2>/dev/null)
if [ "$code" != "204" ] && [ "$code" != "200" ]; then
  echo "Clash 重载失败 (PUT /configs, HTTP ${code})。可尝试: ./update-subscription.sh 重建容器"
  exit 1
fi

echo "订阅已更新，Clash 已重载（无重启）。"
echo ""
echo "--- 更新后验证（经容器代理 ${ALL_PROXY_PORT} 访问 ipinfo.io）---"
if curl -x "http://127.0.0.1:${ALL_PROXY_PORT}" -s --connect-timeout 10 "https://ipinfo.io" 2>/dev/null | head -20; then
  echo "---"
  echo "容器代理可用。可再执行 ./test-proxy.sh ${ALL_PROXY_PORT} 做完整验证。"
else
  echo "（经代理请求未返回，请检查端口或执行 ./test-proxy.sh ${ALL_PROXY_PORT}）"
fi
