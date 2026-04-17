#!/usr/bin/env bash
# VPS 上一键：从上传目录解压项目 zip、导入镜像、启动 clash-aio（docker 或 podman 由部署目录 .env 决定）。
# 用法：sudo bash vps-clash-aio-bootstrap.sh [STAGING_DIR]
#   STAGING_DIR：含 clash-aio-bundle.zip 与 clash-aio-images.tar.gz 的目录，默认当前目录。
# 依赖：unzip、tar、gunzip；容器引擎为 docker 时由 clash-docker-prereq.inc.sh 按需安装/启动 Docker；
# 为 podman 时远端须已安装 podman、podman-compose（与 VPS_DEPLOY_CONTAINER_ENGINE 一致）。

set -euo pipefail

if [ "${EUID:-0}" -ne 0 ]; then
  echo "错误：请使用 root 执行，例如: sudo bash $0" >&2
  exit 1
fi

BOOTSTRAP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="${BOOTSTRAP_DIR}/$(basename "${BASH_SOURCE[0]}")"
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

_clash_detect_ubuntu_codename() {
  local codename=""
  if [ -r /etc/os-release ]; then
    codename="$(awk -F= '$1=="VERSION_CODENAME"{gsub(/"/,"",$2);print $2}' /etc/os-release)"
  fi
  if [ -z "$codename" ] && command -v lsb_release >/dev/null 2>&1; then
    codename="$(lsb_release -cs 2>/dev/null || true)"
  fi
  printf '%s' "$codename"
}

_clash_write_ubuntu_sources_list() {
  local mirror_root="$1"
  local codename="$2"
  cat > /etc/apt/sources.list <<EOF
deb ${mirror_root} ${codename} main restricted universe multiverse
deb ${mirror_root} ${codename}-updates main restricted universe multiverse
deb ${mirror_root} ${codename}-backports main restricted universe multiverse
deb ${mirror_root} ${codename}-security main restricted universe multiverse
EOF
}

_clash_try_cn_apt_mirror_for_ubuntu() {
  local mirror_root="$1"
  local codename="$2"
  _clash_write_ubuntu_sources_list "$mirror_root" "$codename"
  apt-get update \
    -o Acquire::Retries=1 \
    -o Acquire::http::Timeout=8 \
    -o Acquire::https::Timeout=8 >/tmp/clash-aio-apt-update.log 2>&1
}

_clash_prepare_cn_apt_mirror_for_docker() {
  [ "${CLASH_SKIP_CN_APT_MIRROR:-0}" = "1" ] && return 0
  [ -x /usr/bin/apt-get ] || return 0
  [ -f /etc/os-release ] || return 0

  local distro_id codename backup_path
  distro_id="$(awk -F= '$1=="ID"{gsub(/"/,"",$2);print $2}' /etc/os-release)"
  if [ "$distro_id" != "ubuntu" ]; then
    echo "提示：当前发行版 ID=${distro_id:-unknown}，仅对 Ubuntu 执行大陆 apt 源探测。" >&2
    return 0
  fi

  codename="$(_clash_detect_ubuntu_codename)"
  [ -n "$codename" ] || {
    echo "错误：无法识别 Ubuntu codename，跳过 apt 源切换。" >&2
    return 1
  }

  backup_path="/etc/apt/sources.list.clash-aio.bak"
  cp -f /etc/apt/sources.list "$backup_path"

  # 优先大陆常用镜像，最后回退官方源，避免网络波动导致无法安装 Docker。
  local mirror_roots mirror_root
  mirror_roots="${CLASH_CN_APT_MIRROR_ROOTS:-http://mirrors.ustc.edu.cn/ubuntu http://mirrors.aliyun.com/ubuntu http://mirrors.tuna.tsinghua.edu.cn/ubuntu http://archive.ubuntu.com/ubuntu}"
  for mirror_root in $mirror_roots; do
    echo "尝试 apt 源: ${mirror_root} (${codename})"
    if _clash_try_cn_apt_mirror_for_ubuntu "$mirror_root" "$codename"; then
      echo "已切换可用 apt 源: ${mirror_root}"
      return 0
    fi
  done

  cp -f "$backup_path" /etc/apt/sources.list
  echo "错误：大陆/回退 apt 源探测均失败，已恢复原始 /etc/apt/sources.list。" >&2
  [ -f /tmp/clash-aio-apt-update.log ] && sed -n '1,120p' /tmp/clash-aio-apt-update.log >&2
  return 1
}

if [ "$ENGINE" = "docker" ] && [ "${CLASH_SKIP_DOCKER_ENSURE:-0}" != "1" ]; then
  _clash_prepare_cn_apt_mirror_for_docker || exit 1
  if [ ! -f "${BOOTSTRAP_DIR}/clash-docker-prereq.inc.sh" ]; then
    echo "错误：缺少 ${BOOTSTRAP_DIR}/clash-docker-prereq.inc.sh（请用新版 ./deploy-remote.sh upload 一并上传，或与 vps-clash-aio-bootstrap.sh 同目录放置该文件）。" >&2
    exit 1
  fi
  # shellcheck disable=SC1091
  . "${BOOTSTRAP_DIR}/clash-docker-prereq.inc.sh"
  clash_ensure_docker_engine || exit 1
fi

command -v "$ENGINE" >/dev/null 2>&1 || {
  echo "错误：未找到容器命令: $ENGINE" >&2
  exit 1
}

echo "=== clash-aio VPS 一键部署 ==="
echo "STAGING_DIR=${STAGING_DIR}"
echo "DEPLOY_DIR=${DEPLOY_DIR}"
echo "ENGINE=${ENGINE}"
echo ""

IMGTMP="$(mktemp -d)"

echo "1. 解压并加载镜像 (${ENGINE} load) ..."
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

echo "2. 解压项目到 ${DEPLOY_DIR} ..."
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

echo ""
echo "=== 代理连通性校验 ==="
if ! command -v curl >/dev/null 2>&1; then
  echo "错误：未找到 curl，无法执行代理验证。" >&2
  exit 1
fi
VERIFY_TEST_URL="${CLASH_VERIFY_TEST_URL:-http://ip-api.com/json/}"
VERIFY_PROXY_URL="http://127.0.0.1:${ALL_PROXY_PORT}"
verify_ok=0
for attempt in 1 2 3; do
  verify_resp="$(curl -x "${VERIFY_PROXY_URL}" -sS -w "\n%{http_code}" --connect-timeout 10 "${VERIFY_TEST_URL}" || true)"
  verify_code="${verify_resp##*$'\n'}"
  if [ "$verify_code" = "200" ]; then
    verify_ok=1
    break
  fi
  echo "第 ${attempt} 次代理验证失败（HTTP ${verify_code:-NA}），重试中..."
  sleep 2
done
if [ "$verify_ok" -ne 1 ]; then
  echo "错误：代理验证失败，未通过 ${VERIFY_PROXY_URL} 访问 ${VERIFY_TEST_URL}（期望 HTTP 200）。" >&2
  exit 1
fi
echo "代理验证通过（${VERIFY_PROXY_URL} -> ${VERIFY_TEST_URL}）。"

SERVER_IP="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
[ -n "$SERVER_IP" ] || SERVER_IP="localhost"

echo ""
echo "=== 访问信息（端口来自 .env）==="
echo "代理端口: ${ALL_PROXY_PORT}"
echo "控制面板: http://${SERVER_IP}:${CONTROL_PANEL_PORT}/ui?hostname=${SERVER_IP}"
echo ""
echo "bootstrap 脚本路径（供参考）: ${SCRIPT_PATH}"
echo "完成。"
