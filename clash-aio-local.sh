#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# clash-aio：本地 Docker 一键（对齐 VPS 流程语义：拉取/构建 → 预检 → 启动 → 进容器）
# 用法：./clash-aio-local.sh pull | up [PROXY_PORT] | shell | all [PROXY_PORT]
#   pull：compose pull + build --pull（含 dreamacro/clash 等基础层）
#   up：  与原 clash-compose-up 相同（.env、RAW_SUB_URL、端口预检、down、up -d）
#   shell：进入 clash-with-ui 容器（优先 sh，失败则 bash）
#   all： pull 后 up
# ---------------------------------------------------------------------------

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# shellcheck disable=SC1091
. "${SCRIPT_DIR}/clash-compose-cmd.inc.sh"

usage() {
  echo "用法: $0 pull | up [PROXY_PORT] | shell | all [PROXY_PORT]" >&2
  exit 1
}

cmd_pull() {
  clash_compose_require || exit 1
  echo "正在 pull 镜像（compose pull）..."
  $COMPOSE_CMD -f "$COMPOSE_FILE" pull
  echo "正在 build --pull（更新 Dockerfile 基础镜像）..."
  $COMPOSE_CMD -f "$COMPOSE_FILE" build --pull
  echo "pull / build 完成。"
}

cmd_up() {
  local proxy_port="${1:-}"

  clash_compose_require || exit 1

  if [ -n "$proxy_port" ]; then
    [ -f .env ] || { [ -f .env.example ] && cp .env.example .env; }
    if grep -q '^ALL_PROXY_PORT=' .env 2>/dev/null; then
      sed -i.bak "s/^ALL_PROXY_PORT=.*/ALL_PROXY_PORT=${proxy_port}/" .env
    else
      echo "ALL_PROXY_PORT=${proxy_port}" >> .env
    fi
    echo "使用代理端口: ${proxy_port}"
  fi

  if [ ! -f .env ]; then
    [ -f .env.example ] && cp .env.example .env
    echo "已从 .env.example 创建 .env，请编辑 .env 填写 RAW_SUB_URL 后重新运行。"
    exit 1
  fi
  if ! grep -qE '^RAW_SUB_URL=.+' .env 2>/dev/null; then
    echo "请在 .env 中设置 RAW_SUB_URL=你的订阅地址 后重新运行。"
    exit 1
  fi

  # shellcheck disable=SC1091
  . "${SCRIPT_DIR}/clash-env.inc.sh"
  clash_require_env_ports_free_for_compose_up

  echo "正在启动容器..."
  $COMPOSE_CMD -f "$COMPOSE_FILE" down 2>/dev/null || true
  $COMPOSE_CMD -f "$COMPOSE_FILE" up -d

  echo "已启动。宿主机端口（见 .env）：ALL_PROXY_PORT=${ALL_PROXY_PORT}，CONTROL_PANEL_PORT=${CONTROL_PANEL_PORT}，SUBCONVERTER_HOST_PORT=${SUBCONVERTER_HOST_PORT}。"
  echo "验证可执行: ./clash-compose-up-verify.sh 或 $COMPOSE_CMD -f $COMPOSE_FILE ps"
}

cmd_shell() {
  clash_compose_require || exit 1
  $COMPOSE_CMD -f "$COMPOSE_FILE" exec -it clash-with-ui sh || \
    $COMPOSE_CMD -f "$COMPOSE_FILE" exec -it clash-with-ui bash
}

cmd_all() {
  cmd_pull
  cmd_up "$@"
}

main() {
  [ $# -ge 1 ] || usage
  local sub="$1"
  shift
  case "$sub" in
    pull) cmd_pull ;;
    up) cmd_up "${1:-}" ;;
    shell) cmd_shell ;;
    all) cmd_all "$@" ;;
    *) usage ;;
  esac
}

main "$@"
