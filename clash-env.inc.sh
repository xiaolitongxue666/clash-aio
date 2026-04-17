#!/usr/bin/env bash
# 由宿主机脚本在项目根目录 source（勿直接执行）。
# 解析 CONTROL_PANEL_PORT、ALL_PROXY_PORT、SUBCONVERTER_HOST_PORT：键优先来自 .env，缺项再读 .env.example，最后与 .env.example 默认一致。
# clash_require_env_ports_free_for_compose_up：在 compose up 前检测上述宿主机端口；已被占用且非当前 clash-with-ui / subconverter 发布映射则打印醒目标记并 exit 1。
# 设置 CLASH_HOST_RUNTIME=podman 时改用 podman port（供 vps-clash-aio-bootstrap.sh）；未设置时默认 docker。
# shellcheck shell=bash

_clash_port_from_files() {
  local key="$1"
  local def="$2"
  local v=""
  local f
  for f in .env .env.example; do
    [ ! -f "$f" ] && continue
    v=$(grep -E "^${key}=" "$f" 2>/dev/null | head -1 | cut -d= -f2-)
    v="${v%%$'\r'}"
    [ -n "$v" ] && printf '%s' "$v" && return
  done
  printf '%s' "$def"
}

CONTROL_PANEL_PORT=$(_clash_port_from_files CONTROL_PANEL_PORT 9090)
ALL_PROXY_PORT=$(_clash_port_from_files ALL_PROXY_PORT 7891)
SUBCONVERTER_HOST_PORT=$(_clash_port_from_files SUBCONVERTER_HOST_PORT 25500)
unset -f _clash_port_from_files

# 宿主机 TCP 端口是否有进程在监听（与 clash-compose-up-verify 原逻辑一致）
clash_host_tcp_port_busy() {
  local port=$1
  if bash -c "echo >/dev/tcp/127.0.0.1/$port" 2>/dev/null; then
    return 0
  fi
  if command -v netstat >/dev/null 2>&1; then
    netstat -an 2>/dev/null | grep -qE "[.:]${port}[^0-9].*LISTEN" && return 0
  fi
  return 1
}

clash_runtime_published_host_port() {
  local engine="${1:-docker}"
  local ctn="$2"
  local inner="$3"
  case "$engine" in
    docker)
      command -v docker >/dev/null 2>&1 || return 1
      docker port "${ctn}" "${inner}" 2>/dev/null | head -1 | awk -F: '{print $NF}'
      ;;
    podman)
      command -v podman >/dev/null 2>&1 || return 1
      podman port "${ctn}" "${inner}" 2>/dev/null | head -1 | awk -F: '{print $NF}'
      ;;
    *)
      return 1
      ;;
  esac
}

clash_docker_published_host_port() {
  local ctn="$1"
  local inner="$2"
  clash_runtime_published_host_port docker "${ctn}" "${inner}"
}

clash__emit_port_conflict() {
  local label="$1"
  local port="$2"
  echo "" >&2
  echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>" >&2
  echo ">>  端口冲突：${label}=${port}" >&2
  echo ">>  该端口在宿主机已被占用，且不是当前 compose 栈的预期映射。" >&2
  echo ">>  请编辑 .env：修改 ALL_PROXY_PORT / CONTROL_PANEL_PORT / SUBCONVERTER_HOST_PORT 为空闲端口，或结束占用进程后再启动。" >&2
  echo ">>  期望配置：ALL_PROXY_PORT=${ALL_PROXY_PORT}  CONTROL_PANEL_PORT=${CONTROL_PANEL_PORT}  SUBCONVERTER_HOST_PORT=${SUBCONVERTER_HOST_PORT}" >&2
  echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>" >&2
  echo "" >&2
}

# 在 compose up 之前调用：.env 中的宿主机端口须空闲，或为当前容器已发布的同一映射
clash_require_env_ports_free_for_compose_up() {
  local p mapped
  local engine="${CLASH_HOST_RUNTIME:-docker}"
  case "$engine" in
    docker | podman) ;;
    *)
      echo "错误：CLASH_HOST_RUNTIME 须为 docker 或 podman，当前: ${engine}" >&2
      exit 1
      ;;
  esac

  echo "宿主机端口预检（CLASH_HOST_RUNTIME=${engine}）：ALL_PROXY_PORT=${ALL_PROXY_PORT} CONTROL_PANEL_PORT=${CONTROL_PANEL_PORT} SUBCONVERTER_HOST_PORT=${SUBCONVERTER_HOST_PORT}"

  p="$ALL_PROXY_PORT"
  if clash_host_tcp_port_busy "$p"; then
    mapped=$(clash_runtime_published_host_port "$engine" clash-with-ui 7890/tcp)
    if [ -z "$mapped" ] || [ "$mapped" != "$p" ]; then
      clash__emit_port_conflict "ALL_PROXY_PORT" "$p"
      exit 1
    fi
  fi
  p="$CONTROL_PANEL_PORT"
  if clash_host_tcp_port_busy "$p"; then
    mapped=$(clash_runtime_published_host_port "$engine" clash-with-ui 9090/tcp)
    if [ -z "$mapped" ] || [ "$mapped" != "$p" ]; then
      clash__emit_port_conflict "CONTROL_PANEL_PORT" "$p"
      exit 1
    fi
  fi
  p="$SUBCONVERTER_HOST_PORT"
  if clash_host_tcp_port_busy "$p"; then
    mapped=$(clash_runtime_published_host_port "$engine" subconverter 25500/tcp)
    if [ -z "$mapped" ] || [ "$mapped" != "$p" ]; then
      clash__emit_port_conflict "SUBCONVERTER_HOST_PORT" "$p"
      exit 1
    fi
  fi

  echo "宿主机端口预检通过。"
}
