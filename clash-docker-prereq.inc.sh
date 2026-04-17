#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# clash-aio：Docker Engine + compose 插件前置检测/安装（供本机一键与 vps-clash-aio-bootstrap source）
# 逻辑参考 vps_construct_scripts/scripts/bootstrap/vps-bootstrap-funcs.sh 中 Docker 相关段落（CE apt、镜像加速等）。
# 环境变量：
#   CLASH_SKIP_DOCKER_ENSURE=1     跳过本文件全部逻辑
#   DOCKER_CE_APT_MIRROR           auto|official|ustc|aliyun（默认 auto）
#   DOCKER_ROOT_MIN_AVAIL_MIB      安装前根分区最小可用 MiB（默认 2048；0=跳过）
#   DOCKER_HUB_MIRROR_BASELINE     1=写入 registry-mirrors 基线（默认 1；需 jq）
#   DOCKER_REGISTRY_MIRRORS_CSV    空格分隔，覆盖默认镜像列表
#   CLASH_CHSRC_DOCKER_REGISTRY=1  且已安装 chsrc 时尝试 chsrc docker（默认不启用）
# ---------------------------------------------------------------------------

# shellcheck shell=bash

clash_docker_log() {
  printf '[clash-docker-prereq] %s\n' "$*" >&2
}

# 输出一行：GPG_URL<TAB>DEB_ROOT（仅 stdout）
clash_docker_ce_apt_urls_for_os() {
  local os_key="$1"
  local mode="${DOCKER_CE_APT_MIRROR:-auto}"
  local official_gpg="https://download.docker.com/linux/${os_key}/gpg"
  local official_root="https://download.docker.com/linux/${os_key}"
  case "$mode" in
    official)
      clash_docker_log "Docker CE apt：官方 download.docker.com（${os_key}）"
      printf '%s\t%s\n' "$official_gpg" "$official_root"
      ;;
    ustc)
      clash_docker_log "Docker CE apt：USTC 镜像（${os_key}）"
      printf '%s\t%s\n' \
        "https://mirrors.ustc.edu.cn/docker-ce/linux/${os_key}/gpg" \
        "https://mirrors.ustc.edu.cn/docker-ce/linux/${os_key}"
      ;;
    aliyun)
      clash_docker_log "Docker CE apt：阿里云镜像（${os_key}）"
      printf '%s\t%s\n' \
        "https://mirrors.aliyun.com/docker-ce/linux/${os_key}/gpg" \
        "https://mirrors.aliyun.com/docker-ce/linux/${os_key}"
      ;;
    auto)
      if curl -fsSL --connect-timeout 6 --max-time 20 "$official_gpg" -o /dev/null 2>/dev/null; then
        clash_docker_log "Docker CE apt：官方源可达，使用 download.docker.com（${os_key}）"
        printf '%s\t%s\n' "$official_gpg" "$official_root"
      else
        clash_docker_log "Docker 官方 apt 不可达，改用 USTC Docker CE 镜像（可 export DOCKER_CE_APT_MIRROR=ustc|aliyun|official 固定）"
        printf '%s\t%s\n' \
          "https://mirrors.ustc.edu.cn/docker-ce/linux/${os_key}/gpg" \
          "https://mirrors.ustc.edu.cn/docker-ce/linux/${os_key}"
      fi
      ;;
    *)
      clash_docker_log "错误：未知 DOCKER_CE_APT_MIRROR=${mode}（支持 auto|official|ustc|aliyun）" >&2
      return 1
      ;;
  esac
}

clash_assert_root_fs_avail_mib() {
  local min_mib="$1"
  [[ "$min_mib" == "0" ]] && return 0
  local avail_k avail_mib
  avail_k="$(df -Pk / 2>/dev/null | awk 'NR==2 {print $4}')"
  if [[ -z "$avail_k" || ! "$avail_k" =~ ^[0-9]+$ ]]; then
    clash_docker_log "无法检测根分区可用空间，继续安装 Docker"
    return 0
  fi
  avail_mib=$((avail_k / 1024))
  if (( avail_mib < min_mib )); then
    clash_docker_log "错误：根分区可用约 ${avail_mib} MiB，低于建议下限 ${min_mib} MiB。请扩容或设 DOCKER_ROOT_MIN_AVAIL_MIB=0 跳过检查。" >&2
    return 1
  fi
  clash_docker_log "根分区可用约 ${avail_mib} MiB（下限 ${min_mib} MiB）"
}

clash_default_registry_mirror_candidates() {
  printf '%s\n' \
    "https://docker.xuanyuan.me" \
    "https://docker.1ms.run" \
    "https://docker.m.daocloud.io" \
    "https://docker.nju.edu.cn" \
    "https://docker.mirrors.sjtug.sjtu.edu.cn"
}

clash_probe_one_registry_mirror_line() {
  local base="$1"
  local probe wt ct line code
  probe="${base%/}/v2/"
  wt="${DOCKER_REGISTRY_PROBE_TIMEOUT:-20}"
  ct="${DOCKER_REGISTRY_PROBE_CONNECT_TIMEOUT:-12}"
  line="$(curl -o /dev/null -sS -w "%{http_code}\t%{time_total}" --max-time "$wt" --connect-timeout "$ct" "$probe" 2>/dev/null)" || return 1
  code="${line%%	*}"
  [[ "$code" =~ ^[0-9]{3}$ ]] || return 1
  (( code >= 500 && code <= 599 )) && return 1
  [[ "$code" == "000" ]] && return 1
  printf '%s\t%s\n' "${line#*	}" "$base"
}

clash_order_registry_mirrors_by_probe() {
  if [[ "${DOCKER_REGISTRY_PROBE:-1}" != "1" ]]; then
    clash_default_registry_mirror_candidates
    return 0
  fi
  clash_docker_log "探测 Docker Hub registry-mirrors（…/v2/）…"
  local tmp_scored tmp_out u row t b
  tmp_scored="$(mktemp)"
  tmp_out="$(mktemp)"
  cleanup_order_tmp() {
    rm -f "$tmp_scored" "$tmp_out"
  }
  trap cleanup_order_tmp RETURN
  while IFS= read -r u || [[ -n "$u" ]]; do
    [[ -z "$u" ]] && continue
    row="$(clash_probe_one_registry_mirror_line "$u")" || continue
    printf '%s\n' "$row" >>"$tmp_scored"
  done < <(clash_default_registry_mirror_candidates)
  if [[ ! -s "$tmp_scored" ]]; then
    clash_docker_log "registry-mirrors 探测均无有效响应，按默认顺序写入"
    clash_default_registry_mirror_candidates
    cleanup_order_tmp
    trap - RETURN
    return 0
  fi
  while IFS=$'\t' read -r t b; do
    [[ -n "$b" ]] && printf '%s\n' "$b"
  done < <(LC_ALL=C sort -t $'\t' -k1,1n "$tmp_scored") >"$tmp_out"
  while IFS= read -r u || [[ -n "$u" ]]; do
    [[ -z "$u" ]] && continue
    if grep -Fxq "$u" "$tmp_out" 2>/dev/null; then
      continue
    fi
    printf '%s\n' "$u" >>"$tmp_out"
  done < <(clash_default_registry_mirror_candidates)
  cat "$tmp_out"
  cleanup_order_tmp
  trap - RETURN
}

clash_install_docker_write_apt_sources() {
  local os_key="$1"
  local arch="$2"
  local codename="$3"
  local modes=()
  if [[ "${DOCKER_CE_APT_MIRROR:-auto}" == "auto" ]]; then
    modes=(auto ustc aliyun)
  else
    modes=("${DOCKER_CE_APT_MIRROR}")
  fi
  local m gpg_url deb_root tmp
  for m in "${modes[@]}"; do
    IFS=$'\t' read -r gpg_url deb_root < <(DOCKER_CE_APT_MIRROR="$m" clash_docker_ce_apt_urls_for_os "$os_key")
    tmp="/etc/apt/keyrings/docker.gpg.tmp.$$"
    rm -f "$tmp"
    if curl -fsSL --connect-timeout 15 --max-time 120 "$gpg_url" | gpg --batch --no-tty --dearmor -o "$tmp" 2>/dev/null && [[ -s "$tmp" ]]; then
      mv "$tmp" /etc/apt/keyrings/docker.gpg
      chmod a+r /etc/apt/keyrings/docker.gpg
      echo "deb [arch=${arch} signed-by=/etc/apt/keyrings/docker.gpg] ${deb_root} ${codename} stable" \
        >/etc/apt/sources.list.d/docker.list
      return 0
    fi
    rm -f "$tmp"
    clash_docker_log "Docker CE apt GPG 拉取失败（DOCKER_CE_APT_MIRROR=${m}），尝试下一镜像…"
  done
  return 1
}

clash_apt_get_update() {
  DEBIAN_FRONTEND=noninteractive apt-get update -y -qq
}

clash_apt_get_install() {
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$@"
}

clash_read_os_release() {
  CLASH_OS_ID=""
  CLASH_OS_VERSION_CODENAME=""
  [[ -f /etc/os-release ]] || return 1
  CLASH_OS_ID="$(grep -E '^ID=' /etc/os-release | head -1 | cut -d= -f2- | tr -d '"' | tr '[:upper:]' '[:lower:]')"
  CLASH_OS_VERSION_CODENAME="$(grep -E '^VERSION_CODENAME=' /etc/os-release | head -1 | cut -d= -f2- | tr -d '"')"
  if [[ -z "$CLASH_OS_VERSION_CODENAME" ]] && command -v lsb_release >/dev/null 2>&1; then
    CLASH_OS_VERSION_CODENAME="$(lsb_release -cs 2>/dev/null || true)"
  fi
  [[ -n "$CLASH_OS_ID" && -n "$CLASH_OS_VERSION_CODENAME" ]]
}

clash_start_docker_service() {
  if command -v systemctl >/dev/null 2>&1; then
    systemctl enable docker 2>/dev/null || true
    systemctl start docker 2>/dev/null || true
    return 0
  fi
  if command -v service >/dev/null 2>&1; then
    service docker start 2>/dev/null || true
  fi
  return 0
}

clash_chsrc_docker_mirror_optional() {
  [[ "${CLASH_CHSRC_DOCKER_REGISTRY:-0}" != "1" ]] && return 0
  command -v chsrc >/dev/null 2>&1 || return 0
  local stamp_dir="${CLASH_BOOTSTRAP_STATE_DIR:-/var/lib/clash-aio-bootstrap-state}"
  install -d -m 0755 "$stamp_dir" 2>/dev/null || return 0
  local stamp="${stamp_dir}/chsrc-docker-registry.done"
  if [[ -f /etc/docker/daemon.json ]] && command -v jq >/dev/null 2>&1; then
    if jq -e '(.["registry-mirrors"] // []) | type == "array" and length > 0' /etc/docker/daemon.json >/dev/null 2>&1; then
      return 0
    fi
  fi
  clash_docker_log "尝试 chsrc docker/dockerhub 镜像（失败则忽略）…"
  if chsrc set docker first 2>/dev/null || chsrc set dockerhub first 2>/dev/null; then
    : >"$stamp" 2>/dev/null || true
  fi
}

clash_apply_docker_hub_mirror_baseline() {
  [[ "${DOCKER_HUB_MIRROR_BASELINE:-1}" != "1" ]] && return 0
  command -v jq >/dev/null 2>&1 || {
    clash_docker_log "无 jq，跳过 Docker Hub registry-mirrors 基线"
    return 0
  }
  command -v docker >/dev/null 2>&1 || {
    clash_docker_log "未安装 docker，跳过 registry-mirrors 基线"
    return 0
  }

  local urls_line=""
  if [[ -n "${DOCKER_REGISTRY_MIRRORS_CSV:-}" ]]; then
    urls_line=""
    local _mir
    for _mir in ${DOCKER_REGISTRY_MIRRORS_CSV}; do
      urls_line="${urls_line}${_mir}"$'\n'
    done
  else
    urls_line="$(clash_order_registry_mirrors_by_probe)"
  fi
  [[ -n "$urls_line" ]] || {
    clash_docker_log "错误：registry-mirrors 列表为空" >&2
    return 1
  }

  local daemon_json="/etc/docker/daemon.json"
  install -d -m 0755 /etc/docker
  [[ -f "$daemon_json" ]] || echo '{}' >"$daemon_json"
  if ! jq -e . "$daemon_json" >/dev/null 2>&1; then
    clash_docker_log "${daemon_json} 非合法 JSON，已备份并重置"
    cp -a "$daemon_json" "${daemon_json}.bad.$(date +%s)" 2>/dev/null || true
    echo '{}' >"$daemon_json"
  fi

  local tmp merged_json
  tmp="$(mktemp)"
  merged_json="$(printf '%s' "$urls_line" | sed '/^$/d' | jq -R . | jq -s .)"
  if ! jq --argjson mirrors "$merged_json" '.["registry-mirrors"] = $mirrors' "$daemon_json" >"$tmp"; then
    rm -f "$tmp"
    clash_docker_log "错误：jq 合并 registry-mirrors 失败" >&2
    return 1
  fi
  mv "$tmp" "$daemon_json"
  chmod 644 "$daemon_json"
  clash_docker_log "已写入 Docker registry-mirrors（DOCKER_HUB_MIRROR_BASELINE=0 可跳过）"
}

clash_docker_compose_ok() {
  command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1 && return 0
  command -v docker-compose >/dev/null 2>&1 && return 0
  return 1
}

# 在已判定为 Linux 且需安装 Docker 时调用；须 root（EUID=0）
clash_install_docker_linux() {
  if clash_docker_compose_ok; then
    clash_docker_log "Docker 与 compose 已可用"
    clash_start_docker_service
    return 0
  fi

  clash_read_os_release || {
    clash_docker_log "错误：无法读取 /etc/os-release" >&2
    return 1
  }
  case "$CLASH_OS_ID" in
    ubuntu | debian) ;;
    *)
      clash_docker_log "错误：自动安装 Docker 仅支持 ubuntu/debian，当前 ID=${CLASH_OS_ID}" >&2
      return 1
      ;;
  esac

  clash_docker_log "安装 Docker Engine（${CLASH_OS_ID}）…"
  clash_apt_get_install ca-certificates curl gnupg lsb-release

  install -m 0755 -d /etc/apt/keyrings
  rm -f /etc/apt/keyrings/docker.gpg
  local arch codename
  arch="$(dpkg --print-architecture)"
  codename="$CLASH_OS_VERSION_CODENAME"

  if [[ "$CLASH_OS_ID" == "ubuntu" ]]; then
    if ! clash_install_docker_write_apt_sources ubuntu "$arch" "$codename"; then
      clash_docker_log "错误：Docker CE apt 源配置失败。可设 DOCKER_CE_APT_MIRROR=ustc 后重试。" >&2
      return 1
    fi
  else
    if ! clash_install_docker_write_apt_sources debian "$arch" "$codename"; then
      clash_docker_log "错误：Docker CE apt 源配置失败。可设 DOCKER_CE_APT_MIRROR=ustc 后重试。" >&2
      return 1
    fi
  fi

  clash_apt_get_update
  clash_assert_root_fs_avail_mib "${DOCKER_ROOT_MIN_AVAIL_MIB:-2048}" || return 1
  clash_apt_get_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  clash_start_docker_service
  clash_chsrc_docker_mirror_optional
  clash_apply_docker_hub_mirror_baseline || true
  if command -v systemctl >/dev/null 2>&1; then
    systemctl restart docker 2>/dev/null || true
  fi

  if ! clash_docker_compose_ok; then
    clash_docker_log "错误：Docker 安装后仍无法执行 docker compose" >&2
    return 1
  fi
  clash_docker_log "Docker Engine 与 compose 插件已就绪"
}

clash_ensure_docker_engine() {
  if [[ "${CLASH_SKIP_DOCKER_ENSURE:-0}" == "1" ]]; then
    return 0
  fi

  if clash_docker_compose_ok; then
    local uname_s
    uname_s="$(uname -s 2>/dev/null || printf '%s' '')"
    case "$uname_s" in
      Linux) clash_start_docker_service ;;
    esac
    return 0
  fi

  local uname_s
  uname_s="$(uname -s 2>/dev/null || printf '%s' '')"

  case "$uname_s" in
    Linux) ;;
    Darwin)
      clash_docker_log "错误：未检测到可用的 docker compose。请在 macOS 上安装并启动 Docker Desktop：https://docs.docker.com/desktop/" >&2
      return 1
      ;;
    MINGW* | MSYS* | CYGWIN*)
      clash_docker_log "错误：未检测到可用的 docker compose。请在 Windows 上安装 Docker Desktop 并确保当前 shell 能执行 docker。" >&2
      return 1
      ;;
    *)
      clash_docker_log "错误：未检测到可用的 docker compose（uname=${uname_s}）。请手动安装 Docker。" >&2
      return 1
      ;;
  esac

  if [[ "${EUID:-0}" -ne 0 ]]; then
    if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
      clash_docker_log "当前非 root，使用免密 sudo 安装 Docker…"
      local prereq_self="${BASH_SOURCE[0]}"
      sudo env \
        CLASH_DOCKER_PREREQ_INC="$prereq_self" \
        DOCKER_CE_APT_MIRROR="${DOCKER_CE_APT_MIRROR:-}" \
        DOCKER_ROOT_MIN_AVAIL_MIB="${DOCKER_ROOT_MIN_AVAIL_MIB:-}" \
        DOCKER_HUB_MIRROR_BASELINE="${DOCKER_HUB_MIRROR_BASELINE:-}" \
        DOCKER_REGISTRY_MIRRORS_CSV="${DOCKER_REGISTRY_MIRRORS_CSV:-}" \
        DOCKER_REGISTRY_PROBE="${DOCKER_REGISTRY_PROBE:-}" \
        CLASH_CHSRC_DOCKER_REGISTRY="${CLASH_CHSRC_DOCKER_REGISTRY:-}" \
        bash -c 'set -euo pipefail; . "$CLASH_DOCKER_PREREQ_INC"; clash_install_docker_linux' || return 1
      return 0
    fi
    clash_docker_log "错误：需要 root 或免密 sudo 才能在 Linux 上自动安装 Docker。请以 root 执行本脚本，或配置免密 sudo 后重试。" >&2
    return 1
  fi

  clash_install_docker_linux
}
