#!/usr/bin/env bash
# VPS 上一键：从上传目录解压项目 zip、导入镜像、启动 clash-aio（docker 或 podman 由部署目录 .env 决定）。
# 用法：sudo bash vps-clash-aio-bootstrap.sh [STAGING_DIR]
#   STAGING_DIR：含 clash-aio-bundle.zip 与 clash-aio-images.tar.gz 的目录，默认当前目录。
# 依赖：unzip、tar、gunzip；以及 docker 或 podman（与 VPS_DEPLOY_CONTAINER_ENGINE 一致）。

set -euo pipefail

if [ "${EUID:-0}" -ne 0 ]; then
  echo "错误：请使用 root 执行，例如: sudo bash $0" >&2
  exit 1
fi

SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
STAGING_DIR="$(cd "${1:-.}" && pwd)"
ZIP="${STAGING_DIR}/clash-aio-bundle.zip"
IMG_TGZ="${STAGING_DIR}/clash-aio-images.tar.gz"

for need in unzip tar gunzip; do
  command -v "$need" >/dev/null 2>&1 || {
    echo "错误：未找到命令: $need" >&2
    exit 1
  }
done

[ -f "$ZIP" ] || {
  echo "错误：未找到 ${ZIP}" >&2
  exit 1
}
[ -f "$IMG_TGZ" ] || {
  echo "错误：未找到 ${IMG_TGZ}" >&2
  exit 1
}

_clash_kv_from_file() {
  local file="$1"
  local key="$2"
  [ -f "$file" ] || return 0
  grep -E "^${key}=" "$file" 2>/dev/null | head -1 | cut -d= -f2- | sed 's/\r$//' | sed 's/^["'\'']//;s/["'\'']$//'
}

ENV_PREVIEW="$(mktemp)"
IMGTMP=""
cleanup_bootstrap_temp() {
  rm -f "$ENV_PREVIEW"
  if [ -n "${IMGTMP}" ] && [ -d "${IMGTMP}" ]; then
    rm -rf "${IMGTMP}"
  fi
}
trap cleanup_bootstrap_temp EXIT
unzip -p "$ZIP" ".env" >"$ENV_PREVIEW" 2>/dev/null || {
  echo "错误：zip 中缺少 .env，请在本机构建 zip 前准备好 .env" >&2
  exit 1
}

DEPLOY_DIR="$(_clash_kv_from_file "$ENV_PREVIEW" VPS_DEPLOY_DEPLOY_DIR)"
if [ -z "$DEPLOY_DIR" ]; then
  DEPLOY_DIR="/opt/clash-aio"
fi

ENGINE_RAW="$(_clash_kv_from_file "$ENV_PREVIEW" VPS_DEPLOY_CONTAINER_ENGINE)"
ENGINE="$(printf '%s' "${ENGINE_RAW:-podman}" | tr '[:upper:]' '[:lower:]')"
case "$ENGINE" in
  docker | podman) ;;
  *)
    echo "错误：VPS_DEPLOY_CONTAINER_ENGINE 须为 docker 或 podman，当前: ${ENGINE_RAW:-空}" >&2
    exit 1
    ;;
esac

command -v "$ENGINE" >/dev/null 2>&1 || {
  echo "错误：未找到容器命令: $ENGINE" >&2
  exit 1
}

echo "=== clash-aio VPS 一键部署 ==="
echo "STAGING_DIR=${STAGING_DIR}"
echo "DEPLOY_DIR=${DEPLOY_DIR}"
echo "ENGINE=${ENGINE}"
echo ""

echo "1. 解压项目到 ${DEPLOY_DIR} ..."
mkdir -p "$DEPLOY_DIR"
unzip -o -q "$ZIP" -d "$DEPLOY_DIR"

ENV_FILE="${DEPLOY_DIR}/.env"
ENGINE="$(_clash_kv_from_file "$ENV_FILE" VPS_DEPLOY_CONTAINER_ENGINE)"
ENGINE="$(printf '%s' "${ENGINE:-podman}" | tr '[:upper:]' '[:lower:]')"
case "$ENGINE" in
  docker | podman) ;;
  *)
    echo "错误：部署目录 .env 中 VPS_DEPLOY_CONTAINER_ENGINE 无效: ${ENGINE}" >&2
    exit 1
    ;;
esac

IMGTMP="$(mktemp -d)"

echo "2. 解压并加载镜像 (${ENGINE} load) ..."
tar xzf "$IMG_TGZ" -C "$IMGTMP"
(
  cd "$IMGTMP"
  # 期望文件名 clash-with-ui.tar.gz / subconverter.tar.gz
  for f in clash-with-ui.tar.gz subconverter.tar.gz; do
    if [ -f "$f" ]; then
      gunzip -f "$f"
    fi
  done
  [ -f clash-with-ui.tar ] || {
    echo "错误：镜像包中缺少 clash-with-ui.tar(.gz)" >&2
    exit 1
  }
  [ -f subconverter.tar ] || {
    echo "错误：镜像包中缺少 subconverter.tar(.gz)" >&2
    exit 1
  }
  "$ENGINE" load -i clash-with-ui.tar
  "$ENGINE" load -i subconverter.tar
)

echo "3. 镜像打标签 ..."
if [ "$ENGINE" = "podman" ]; then
  CLASH_LOADED=$("$ENGINE" images --format "{{.Repository}}:{{.Tag}}" | grep -E "clash-aio_clash-with-ui|clash-aio-clash-with-ui" | head -1 || true)
  if [ -z "$CLASH_LOADED" ]; then
    CLASH_LOADED=$("$ENGINE" images --format "{{.Repository}}:{{.Tag}}" | grep "clash-with-ui" | grep -v "localhost/" | head -1 || true)
  fi
  SUB_LOADED=$("$ENGINE" images --format "{{.Repository}}:{{.Tag}}" | grep "tindy2013/subconverter" | head -1 || true)
  if [ -z "$SUB_LOADED" ]; then
    SUB_LOADED=$("$ENGINE" images --format "{{.Repository}}:{{.Tag}}" | grep "subconverter" | grep -v "localhost/" | head -1 || true)
  fi
  if [ -z "$CLASH_LOADED" ] || [ -z "$SUB_LOADED" ]; then
    echo "错误：未在 ${ENGINE} images 中找到已加载的 clash/subconverter 镜像" >&2
    exit 1
  fi
  "$ENGINE" tag "${CLASH_LOADED}" "localhost/clash-with-ui:latest"
  "$ENGINE" tag "${SUB_LOADED}" "localhost/subconverter:latest"
elif [ "$ENGINE" = "docker" ]; then
  # docker compose 使用 clash-aio-clash-with-ui 与 tindy2013/subconverter；load 后一般已具备正确引用名
  :
fi

if [ -f "${DEPLOY_DIR}/preprocess.sh" ]; then
  chmod +x "${DEPLOY_DIR}/preprocess.sh"
fi

cd "$DEPLOY_DIR"

if [ ! -f "${DEPLOY_DIR}/clash-env.inc.sh" ]; then
  echo "错误：部署目录缺少 clash-env.inc.sh（请用新版 ./deploy-remote.sh pack 重新生成 zip）。" >&2
  exit 1
fi
export CLASH_HOST_RUNTIME="$ENGINE"
# shellcheck disable=SC1091
. "${DEPLOY_DIR}/clash-env.inc.sh"
clash_require_env_ports_free_for_compose_up

docker_compose_run() {
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    docker compose -f docker-compose.yaml "$@"
  elif command -v docker-compose >/dev/null 2>&1; then
    docker-compose -f docker-compose.yaml "$@"
  else
    echo "错误：未找到 docker compose 或 docker-compose" >&2
    exit 1
  fi
}

echo "4. 启动栈 (${ENGINE}) ..."
if [ "$ENGINE" = "podman" ]; then
  command -v podman-compose >/dev/null 2>&1 || {
    echo "错误：未找到 podman-compose" >&2
    exit 1
  }
  podman-compose -f podman-compose.yaml down 2>/dev/null || true
  podman-compose -f podman-compose.yaml up -d
elif [ "$ENGINE" = "docker" ]; then
  docker_compose_run down 2>/dev/null || true
  docker_compose_run up -d --no-build
fi

ALL_PROXY_PORT="$(_clash_kv_from_file "$ENV_FILE" ALL_PROXY_PORT)"
CONTROL_PANEL_PORT="$(_clash_kv_from_file "$ENV_FILE" CONTROL_PANEL_PORT)"
ALL_PROXY_PORT="${ALL_PROXY_PORT:-7891}"
CONTROL_PANEL_PORT="${CONTROL_PANEL_PORT:-9090}"

sleep 5
echo ""
echo "=== 服务状态 ==="
if [ "$ENGINE" = "podman" ]; then
  podman-compose -f podman-compose.yaml ps || true
else
  docker_compose_run ps || true
fi

SERVER_IP="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
[ -n "$SERVER_IP" ] || SERVER_IP="localhost"

echo ""
echo "=== 访问信息（端口来自 .env）==="
echo "代理端口: ${ALL_PROXY_PORT}"
echo "控制面板: http://${SERVER_IP}:${CONTROL_PANEL_PORT}/ui?hostname=${SERVER_IP}"
echo ""
echo "bootstrap 脚本路径（供参考）: ${SCRIPT_PATH}"
echo "完成。"
