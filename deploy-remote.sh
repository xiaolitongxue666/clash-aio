#!/usr/bin/env bash
# 本地：打包 clash-aio（项目 zip + 镜像 tar.gz）并可选 scp 到 VPS。
# 用法：./deploy-remote.sh pack|upload|all
# 从项目根 .env 读取 VPS_DEPLOY_*（不 source 整文件，避免污染当前 shell）。
# 依赖：bash、docker、docker compose 或 docker-compose、tar、gzip、zip；upload 另需 scp、ssh。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

BUNDLE_ZIP_NAME="clash-aio-bundle.zip"
IMAGES_TGZ_NAME="clash-aio-images.tar.gz"
DIST_DIR="${SCRIPT_DIR}/dist"

usage() {
  echo "用法: $0 pack | upload | all" >&2
  echo "  pack   生成 dist/${BUNDLE_ZIP_NAME} 与 dist/${IMAGES_TGZ_NAME}（需本机 .env）" >&2
  echo "  upload 根据 .env 中 VPS_DEPLOY_* scp 到远端（需已 pack）" >&2
  echo "  all    依次执行 pack 与 upload" >&2
  exit 1
}

deploy_remote_get_env() {
  local key="$1"
  local file="${2:-${SCRIPT_DIR}/.env}"
  [ -f "$file" ] || return 1
  grep -E "^${key}=" "$file" 2>/dev/null | head -1 | cut -d= -f2- | sed 's/\r$//' | sed 's/^["'\'']//;s/["'\'']$//'
}

require_cmds() {
  local missing=""
  for c in "$@"; do
    if ! command -v "$c" >/dev/null 2>&1; then
      missing="${missing} ${c}"
    fi
  done
  if [ -n "$missing" ]; then
    echo "错误：缺少命令:${missing}" >&2
    exit 1
  fi
}

detect_compose_build() {
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    echo "docker compose"
  elif command -v docker-compose >/dev/null 2>&1; then
    echo "docker-compose"
  else
    echo "错误：未找到 docker compose 或 docker-compose。" >&2
    exit 1
  fi
}

cmd_pack() {
  require_cmds docker tar gzip zip
  local compose_cmd
  compose_cmd="$(detect_compose_build)"

  if [ ! -f "${SCRIPT_DIR}/.env" ]; then
    echo "错误：项目根缺少 .env（含 RAW_SUB_URL 与可选 VPS_DEPLOY_*），bootstrap 需要将其打入 zip。" >&2
    exit 1
  fi

  COMPOSE_FILE="docker-compose.yaml"
  [ -f "$COMPOSE_FILE" ] || {
    echo "错误：未找到 ${COMPOSE_FILE}" >&2
    exit 1
  }

  mkdir -p "$DIST_DIR"
  local img_work conf_img
  img_work="$(mktemp -d)"
  conf_img="$(mktemp)"
  cleanup_pack() {
    rm -f "$conf_img"
    rm -rf "$img_work"
  }
  trap cleanup_pack EXIT

  echo "正在构建镜像（${compose_cmd} build）..."
  if [ "$compose_cmd" = "docker compose" ]; then
    docker compose -f "$COMPOSE_FILE" build
    docker compose -f "$COMPOSE_FILE" config --images >"$conf_img"
  else
    docker-compose -f "$COMPOSE_FILE" build
    docker-compose -f "$COMPOSE_FILE" config --images >"$conf_img"
  fi

  local clash_img sub_img line
  clash_img=""
  sub_img=""
  while IFS= read -r line || [ -n "$line" ]; do
    [ -z "$line" ] && continue
    case "$line" in
      *subconverter*) sub_img="$line" ;;
      *clash-with-ui* | *clash*aio* | *clash-aio*) clash_img="$line" ;;
    esac
  done <"$conf_img"

  if [ -z "$clash_img" ] || [ -z "$sub_img" ]; then
    echo "错误：无法从 compose 解析镜像名（clash_img=${clash_img} sub_img=${sub_img}）。" >&2
    exit 1
  fi

  case "$clash_img" in
    *:*) ;;
    *) clash_img="${clash_img}:latest" ;;
  esac
  case "$sub_img" in
    *:*) ;;
    *) sub_img="${sub_img}:latest" ;;
  esac

  echo "导出镜像: ${clash_img} , ${sub_img}"
  docker save "$clash_img" -o "${img_work}/clash-with-ui.tar"
  docker save "$sub_img" -o "${img_work}/subconverter.tar"
  gzip -f "${img_work}/clash-with-ui.tar" "${img_work}/subconverter.tar"
  tar czf "${DIST_DIR}/${IMAGES_TGZ_NAME}" -C "$img_work" clash-with-ui.tar.gz subconverter.tar.gz

  echo "正在生成 ${BUNDLE_ZIP_NAME} ..."
  rm -f "${DIST_DIR}/${BUNDLE_ZIP_NAME}"
  (
    cd "$SCRIPT_DIR"
    set -- \
      docker-compose.yaml \
      docker-compose.override.example.yaml \
      podman-compose.yaml \
      Dockerfile \
      preprocess.sh \
      clash-env.inc.sh \
      clash-compose-cmd.inc.sh \
      clash-docker-prereq.inc.sh \
      clash-aio-local.sh \
      clash-compose-up-verify.sh \
      clash-verify-mixed-proxy-portmap.sh \
      vps-clash-aio-bootstrap.sh \
      deploy-server.sh \
      subconverter \
      .env
    if [ -f fix-images.sh ]; then
      set -- "$@" fix-images.sh
    fi
    zip -q -r "${DIST_DIR}/${BUNDLE_ZIP_NAME}" "$@"
  )

  trap - EXIT
  rm -rf "$img_work"
  rm -f "$conf_img"

  echo "完成: ${DIST_DIR}/${BUNDLE_ZIP_NAME}"
  echo "      ${DIST_DIR}/${IMAGES_TGZ_NAME}"
}

cmd_upload() {
  require_cmds scp ssh

  local envf
  envf="${SCRIPT_DIR}/.env"
  [ -f "$envf" ] || {
    echo "错误：缺少 ${envf}" >&2
    exit 1
  }

  local host port user key remote engine
  host="$(deploy_remote_get_env VPS_DEPLOY_SSH_HOST "$envf")"
  port="$(deploy_remote_get_env VPS_DEPLOY_SSH_PORT "$envf")"
  user="$(deploy_remote_get_env VPS_DEPLOY_SSH_USER "$envf")"
  key="$(deploy_remote_get_env VPS_DEPLOY_SSH_KEY "$envf")"
  remote="$(deploy_remote_get_env VPS_DEPLOY_REMOTE_DIR "$envf")"
  engine="$(deploy_remote_get_env VPS_DEPLOY_CONTAINER_ENGINE "$envf")"

  port="${port:-22}"
  engine="$(printf '%s' "${engine:-podman}" | tr '[:upper:]' '[:lower:]')"

  if [ -z "$host" ] || [ -z "$user" ] || [ -z "$remote" ]; then
    echo "错误：.env 中需设置 VPS_DEPLOY_SSH_HOST、VPS_DEPLOY_SSH_USER、VPS_DEPLOY_REMOTE_DIR。" >&2
    exit 1
  fi

  case "$engine" in
    docker | podman) ;;
    *)
      echo "错误：VPS_DEPLOY_CONTAINER_ENGINE 须为 docker 或 podman。" >&2
      exit 1
      ;;
  esac

  [ -s "${DIST_DIR}/${BUNDLE_ZIP_NAME}" ] && [ -s "${DIST_DIR}/${IMAGES_TGZ_NAME}" ] || {
    echo "错误：请先执行 $0 pack（缺少或空的 dist 产物：${BUNDLE_ZIP_NAME} / ${IMAGES_TGZ_NAME}）。" >&2
    exit 1
  }

  local ssh_opts scp_opts
  ssh_opts=(-p "$port")
  scp_opts=(-P "$port")
  if [ -n "$key" ]; then
    if [ ! -f "$key" ]; then
      echo "错误：VPS_DEPLOY_SSH_KEY 不是可读文件: ${key}" >&2
      exit 1
    fi
    ssh_opts+=(-i "$key" -o "IdentitiesOnly=yes")
    scp_opts+=(-i "$key" -o "IdentitiesOnly=yes")
  fi

  # QEMU/本机回环：常见 host key 轮换导致 StrictHostKeyChecking 失败；远端 VPS 仍保持默认严格校验
  host_lc="$(printf '%s' "$host" | tr '[:upper:]' '[:lower:]')"
  if [ "$host_lc" = "127.0.0.1" ] || [ "$host_lc" = "localhost" ]; then
    ssh_opts+=(-o "StrictHostKeyChecking=accept-new")
    scp_opts+=(-o "StrictHostKeyChecking=accept-new")
  fi

  echo "预检远端命令（engine=${engine}）..."
  if [ "$engine" = "podman" ]; then
    ssh "${ssh_opts[@]}" "${user}@${host}" \
      'command -v unzip >/dev/null && command -v tar >/dev/null && command -v gunzip >/dev/null && command -v podman >/dev/null && command -v podman-compose >/dev/null' || {
      echo "错误：远端预检失败，请安装 unzip、tar、gzip、podman、podman-compose。" >&2
      exit 1
    }
  else
    # docker：Engine 可由 vps-clash-aio-bootstrap 内 clash-docker-prereq 自动安装，此处仅校验基础工具与 curl（apt 源拉 GPG 用）
    ssh "${ssh_opts[@]}" "${user}@${host}" \
      'command -v unzip >/dev/null && command -v tar >/dev/null && command -v gunzip >/dev/null && command -v curl >/dev/null' || {
      echo "错误：远端预检失败，请安装 unzip、tar、gzip、curl（Docker 将由 bootstrap 脚本按需安装）。" >&2
      exit 1
    }
  fi

  echo "正在 scp 到 ${user}@${host}:${remote} ..."
  scp "${scp_opts[@]}" \
    "${DIST_DIR}/${BUNDLE_ZIP_NAME}" \
    "${DIST_DIR}/${IMAGES_TGZ_NAME}" \
    "${SCRIPT_DIR}/vps-clash-aio-bootstrap.sh" \
    "${SCRIPT_DIR}/clash-docker-prereq.inc.sh" \
    "${user}@${host}:${remote}"

  echo "校验远端产物并统一脚本换行符..."
  ssh "${ssh_opts[@]}" "${user}@${host}" "
    set -euo pipefail
    cd ${remote}
    test -s \"${BUNDLE_ZIP_NAME}\"
    test -s \"${IMAGES_TGZ_NAME}\"
    test -s \"vps-clash-aio-bootstrap.sh\"
    test -s \"clash-docker-prereq.inc.sh\"
    sed -i 's/\r\$//' \"vps-clash-aio-bootstrap.sh\" \"clash-docker-prereq.inc.sh\"
  " || {
    echo \"错误：远端上传校验失败（zip/images/脚本缺失，或换行符修复失败）。\" >&2
    exit 1
  }

  echo "上传完成。SSH 登录后进入上传目录（与 VPS_DEPLOY_REMOTE_DIR 一致），执行:"
  echo "  sudo bash vps-clash-aio-bootstrap.sh ."
}

main() {
  local sub
  sub="${1:-}"
  case "$sub" in
    pack) cmd_pack ;;
    upload) cmd_upload ;;
    all)
      cmd_pack
      cmd_upload
      ;;
    *) usage ;;
  esac
}

main "${1:-}"
