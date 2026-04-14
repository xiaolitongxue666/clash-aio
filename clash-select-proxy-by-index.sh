#!/usr/bin/env bash
# 列出节点（含延迟）并交互选择，切换 Clash 当前代理节点；控制面端口来自 clash-env.inc.sh（.env / .env.example）。
# 用法: ./clash-select-proxy-by-index.sh [控制面板端口（默认同 .env/.env.example）] [仅列前 N 个节点，默认 20，0=全部]
# 依赖: curl，纯 Bash 实现

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/clash-env.inc.sh"

# 纯 Bash URL 编码
url_encode() {
  local s="$1"
  echo "$s" | sed -e 's/%/%25/g' -e 's/ /%20/g' -e 's/!/%21/g' -e 's/"/%22/g' -e 's/#/%23/g' \
    -e 's/&/%26/g' -e "s/'/%27/g" -e 's/(/%28/g' -e 's/)/%29/g' -e 's/\*/%2A/g' -e 's/+/%2B/g' \
    -e 's/,/%2C/g' -e 's/\//%2F/g' -e 's/:/%3A/g' -e 's/;/%3B/g' -e 's/=/%3D/g' -e 's/?/%3F/g' \
    -e 's/@/%40/g' -e 's/\[/%5B/g' -e 's/\]/%5D/g'
}

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

before_all="${json%%\"all\":[*}"
GROUP=$(echo "$before_all" | grep -oE '"[^"]+":\s*\{' | tail -1 | sed 's/":.*//;s/"//g')
if [ -z "$GROUP" ]; then
  echo "未解析到代理组。"
  exit 1
fi

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

# 存为数组以便按序号取
NAMES_ARR=()
while IFS= read -r line; do
  [ -n "$line" ] && NAMES_ARR+=("$line")
done <<< "$names"
N=${#NAMES_ARR[@]}
[ "$N" -eq 0 ] && echo "无节点。" && exit 1

echo "节点数: ${N} (可选 1-${N}，输入 0 或 q 取消)"
echo "--- 序号. 节点名 | 延迟(ms) ---"
echo ""

i=1
while IFS= read -r name; do
  [ -z "$name" ] && continue
  enc=$(url_encode "$name")
  resp=$(curl -s "${BASE}/proxies/${enc}/delay?url=${DELAY_URL}&timeout=${TIMEOUT_MS}" 2>/dev/null) || true
  delay=$(echo "$resp" | sed -n 's/.*"delay":\s*\([0-9]*\).*/\1/p')
  [ -z "$delay" ] && delay="-"
  printf "%3d. %-50s %s ms\n" "$i" "$name" "$delay"
  i=$((i + 1))
done <<< "$names"

echo ""
read -p "请输入要切换的序号 (1-${N}，0 取消): " num
num=$(echo "$num" | tr -d ' ')
if [ -z "$num" ] || [ "$num" = "q" ] || [ "$num" = "0" ]; then
  echo "已取消。"
  exit 0
fi
if ! [[ "$num" =~ ^[0-9]+$ ]] || [ "$num" -lt 1 ] || [ "$num" -gt "$N" ]; then
  echo "无效序号。"
  exit 1
fi

selected="${NAMES_ARR[$((num-1))]}"
# 构建 JSON body，转义选中名中的 \ 和 "
escaped=$(echo "$selected" | sed 's/\\/\\\\/g;s/"/\\"/g')
body="{\"name\": \"${escaped}\"}"
code=$(curl -s -o /dev/null -w "%{http_code}" -X PUT "${BASE}/proxies/${GROUP}" -H "Content-Type: application/json" -d "$body" 2>/dev/null)
if [ "$code" = "204" ] || [ "$code" = "200" ]; then
  echo "已切换至: $selected"
else
  echo "切换失败 (HTTP ${code})。"
  exit 1
fi
