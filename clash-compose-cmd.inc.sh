#!/usr/bin/env bash
# 由宿主机脚本在项目根 source（勿直接执行）。
# 调用 clash_compose_require：设置 COMPOSE_CMD，并校验 COMPOSE_FILE 存在。
# shellcheck shell=bash

COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.yaml}"

clash_compose_require() {
  if [ ! -f "$COMPOSE_FILE" ]; then
    echo "错误：未找到 ${COMPOSE_FILE}" >&2
    return 1
  fi
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
  elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE_CMD="docker-compose"
  else
    echo "错误：未找到 docker compose 或 docker-compose。" >&2
    return 1
  fi
  return 0
}
