#!/usr/bin/env bash
# 列出当前容器中 Clash 订阅的代理节点并测延迟（ms）
# 用法: ./list-proxy-delay.sh [控制面板端口] [仅测前 N 个节点，默认 20，0=全部]
# 依赖: curl，纯 Bash 实现

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# 纯 Bash URL 编码
url_encode() {
  local s="$1"
  echo "$s" | sed -e 's/%/%25/g' -e 's/ /%20/g' -e 's/!/%21/g' -e 's/"/%22/g' -e 's/#/%23/g' \
    -e 's/&/%26/g' -e "s/'/%27/g" -e 's/(/%28/g' -e 's/)/%29/g' -e 's/\*/%2A/g' -e 's/+/%2B/g' \
    -e 's/,/%2C/g' -e 's/\//%2F/g' -e 's/:/%3A/g' -e 's/;/%3B/g' -e 's/=/%3D/g' -e 's/?/%3F/g' \
    -e 's/@/%40/g' -e 's/\[/%5B/g' -e 's/\]/%5D/g'
}

CONTROL_PANEL_PORT=9090
if [ -f .env ]; then
  val=$(grep -E '^CONTROL_PANEL_PORT=' .env 2>/dev/null | cut -d= -f2); [ -n "$val" ] && CONTROL_PANEL_PORT="$val"
fi
[ -n "$1" ] && [[ "$1" =~ ^[0-9]+$ ]] && CONTROL_PANEL_PORT="$1"
if [ -n "$2" ] && [[ "$2" =~ ^[0-9]+$ ]]; then
  LIMIT=$2
else
  LIMIT=20
fi

BASE="http://127.0.0.1:${CONTROL_PANEL_PORT}"
DELAY_URL="http://www.gstatic.com/generate_204"
TIMEOUT_MS=10000

json=$(curl -s "${BASE}/proxies" 2>/dev/null) || true
if [ -z "$json" ] || [[ ! "$json" =~ \"proxies\" ]]; then
  echo "无法连接 Clash API (${BASE})，请确认 clash-with-ui 已启动。"
  exit 1
fi

# 解析组名：最后一个 "key":{ 在 "all":[ 之前
before_all="${json%%\"all\":[*}"
GROUP=$(echo "$before_all" | grep -oE '"[^"]+":\s*\{' | tail -1 | sed 's/":.*//;s/"//g')
if [ -z "$GROUP" ]; then
  echo "未解析到代理组。"
  exit 1
fi

# 解析 all 数组：从 "all":[ 到第一个 ]
after_all="${json#*\"all\":[}"
segment="${after_all%%]*}"
names=$(echo "$segment" | sed 's/","/\
/g' | sed 's/^"//;s/"$//' | grep -v -E '^(DIRECT|REJECT)$')
if [ -z "$names" ]; then
  echo "未解析到代理节点。"
  exit 1
fi

if [ "$LIMIT" -gt 0 ]; then
  names=$(echo "$names" | head -n "$LIMIT")
fi
count=$(echo "$names" | wc -l)
echo "节点数: ${count}"$([ "$LIMIT" -gt 0 ] && echo " (仅测前 ${LIMIT} 个)" || echo "")
echo "--- 节点名 | 延迟(ms) ---"
echo ""

while IFS= read -r name; do
  [ -z "$name" ] && continue
  enc=$(url_encode "$name")
  resp=$(curl -s "${BASE}/proxies/${enc}/delay?url=${DELAY_URL}&timeout=${TIMEOUT_MS}" 2>/dev/null) || true
  delay=$(echo "$resp" | sed -n 's/.*"delay":\s*\([0-9]*\).*/\1/p')
  [ -z "$delay" ] && delay="-"
  printf "%-50s %s ms\n" "$name" "$delay"
done <<< "$names"

echo ""
echo "--- 完成 ---"
