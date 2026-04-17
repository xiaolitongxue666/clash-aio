# Lazy Clash

[中文](README-zh.md) [English](README.md)

Lazy Clash is a one-click deployment solution for Clash based on Docker Compose. It can help you quickly set up a Clash proxy service with automatically updated subscriptions. —— by ChatGPT

## Workspace context (multi-repo layout)

**What this repo is (scope)**: A **Docker Compose** stack for **Clash + subconverter + web UI (YACD)** with a clear host port contract (`ALL_PROXY_PORT`, `CONTROL_PANEL_PORT`, `SUBCONVERTER_HOST_PORT`), local helpers (`clash-aio-local.sh`, `clash-compose-up-verify.sh`, `clash-verify-mixed-proxy-portmap.sh`, …), and an optional **remote bundle** path: `deploy-remote.sh` (build/save images + zip) → upload → `vps-clash-aio-bootstrap.sh` on the target (install/load/start/verify). Linux targets may pull Docker CE via `clash-docker-prereq.inc.sh` (see [DEPLOYMENT.md](DEPLOYMENT.md)).

**Where it sits in a typical multi-repo workspace**: **Middle layer (edge proxy / subscription plane)** on top of **any SSH-reachable Linux** (a local QEMU VM, a NAS, or a VPS). It does **not** embed `vps_construct_scripts`; it may run on a host that was (or was not) prepared by those scripts.

**Related repos (integration, not submodules)**: Use **`qemu_test_vm`** when you need a disposable Ubuntu for dry-runs. Coordinate UFW/Tailscale/Docker policies with whatever ran on the host before `docker compose up`. There is **no** workspace-root orchestrator; you wire SSH targets and order manually.

### 工作区中的定位（中文摘要）

**本仓库职责**：在目标 Linux 上以容器方式提供 **Clash 代理平面**（订阅、subconverter、控制面与 Web UI），支持本机 Compose 与 **远端打包上传 + 目标机一键 bootstrap** 两种交付路径。

**层级**：**中层（跑在目标机上的服务）**；依赖可 SSH 的主机及（多数场景下）Docker，**不依赖** `vps_construct_scripts` 源码，但常与该机已由 vps 脚本配置过的 Docker/UFW 等共存。

**与相邻仓库**：底层可用 **`qemu_test_vm`** 提供测试用 Ubuntu；同机可再运行 **`vps_construct_scripts`** 做系统基线——三者独立 Git 仓库，由执行顺序衔接。部署边界与产物命名见 [DEPLOYMENT.md](DEPLOYMENT.md)；中文说明见 [README-zh.md](README-zh.md)。

Personal usage scenarios:

- Quick and painless deployment on router/NAS devices
- Quick deployment on servers for temporary use, and can be deleted after use.

## Features

- Automatic update Clash subscription (based on Clash proxy-providers)
- Unified proxy service based on subconverter format and automatic grouping.
- On-line deployment with Docker Compose
- Embedded YACD web control panel

## Usage
0. Clone this repo

```bash
git clone https://github.com/pandazki/clash-aio.git
```

1. Set your clash subscription URL in `.env`, and optionally `ALL_PROXY_PORT`, `CONTROL_PANEL_PORT`, `SUBCONVERTER_HOST_PORT` (see `.env.example`), or mount your config file to `/root/.config/clash/config.yaml`

```bash
cd clash-aio
cp .env.example .env
# Set RAW_SUB_URL="your clash subscription url" in .env
```

or

```docker-compose
...
    volumes:
      - /path/to/your/config.yaml:/root/.config/clash/config.yaml
...
```

2. Run docker-compose

```bash
docker compose up -d
```

**Helper scripts** (same as raw Compose; run from project root):

| Action | Script | Notes |
|--------|--------|--------|
| Local one-shot | `./clash-aio-local.sh` | `pull` (`compose pull` + `build --pull`), `up` (same as next row), `shell` (exec into `clash-with-ui`), `all` (`pull` then `up`); optional port: `./clash-aio-local.sh up 7891` |
| Start stack | `./clash-compose-up.sh` | Delegates to `clash-aio-local.sh up`: `docker compose down` then `up -d`; **before `up`**, `clash_require_env_ports_free_for_compose_up` (from `clash-env.inc.sh`) must pass; optional arg updates `ALL_PROXY_PORT` in `.env` first |
| Stop stack | `./clash-compose-down.sh` | `docker compose -f docker-compose.yaml down` |
| Start + verify | `./clash-compose-up-verify.sh` | Same port preflight as above, then `compose up -d`, readiness on `/version`, proxy probe (**recommended** on Windows Git Bash) |

On Windows (Git Bash) you can run `./clash-compose-up-verify.sh` in the project directory to check `.env`, start services, and verify. Before `compose up`, host ports from `.env` (`ALL_PROXY_PORT`, `CONTROL_PANEL_PORT`, `SUBCONVERTER_HOST_PORT`) must be free or already bound by this stack; otherwise the script prints a clear error and exits.

3. (Optional) Management

- **Web control panel**: `http://[server-ip]:<CONTROL_PANEL_PORT>/ui?hostname=...` (port from `.env`, default in `.env.example` is 9090)
- **CLI scripts** (run in project directory; require curl, pure Bash, no jq):
  - **List proxies and delay**: `./clash-list-proxies-latency.sh [CONTROL_PANEL_PORT] [count]` — control port defaults from `.env` / `.env.example` when the first argument is omitted (pass a port only if it differs from `.env`).  
    e.g. `./clash-list-proxies-latency.sh` or `./clash-list-proxies-latency.sh 9095 20` for first 20 nodes; use `0` as count for all.
  - **Select proxy by index**: `./clash-select-proxy-by-index.sh [CONTROL_PANEL_PORT] [count]` — same port rules as above.  
    e.g. `./clash-select-proxy-by-index.sh` or `./clash-select-proxy-by-index.sh 9095 10`
  - **Verify mixed proxy via port map**: `./clash-verify-mixed-proxy-portmap.sh [host-mapped-port]`; default `ALL_PROXY_PORT` from `.env` / `.env.example` (see `clash-env.inc.sh`). Traffic: host mapped port → container Clash mixed (container internal 7890).

4. (Optional) Export proxy

```bash
# Replace <ALL_PROXY_PORT> with the value from your .env (host-mapped mixed port)
export https_proxy=http://[server-ip]:<ALL_PROXY_PORT>
export http_proxy=http://[server-ip]:<ALL_PROXY_PORT>
export all_proxy=socks5://[server-ip]:<ALL_PROXY_PORT>
```

5. (Optional) Manual subscription update

The stack fetches the subscription only when the container **starts for the first time and has no config**; it does not auto-update afterward.

- **Recommended (no restart)**: Run `./clash-subscription-hot-reload.sh` in the project directory to pull new config from subconverter, copy into the container, and reload via Clash API.
- **Fallback**: If hot-reload fails (e.g. API unavailable), run `./clash-subscription-rebuild.sh` or `docker compose up -d --force-recreate clash-with-ui` to recreate the container and re-fetch. A plain `restart` does not re-fetch; the container must be **recreated**.

6. (Optional) Scheduled subscription update

Run `./clash-subscription-hot-reload.sh` on a schedule (cron on Linux/WSL/Git Bash, or Windows Task Scheduler with Git Bash).

## Script index

| Script | Purpose | Example |
|--------|---------|---------|
| `clash-aio-local.sh` | Local `pull` / `up` / `shell` / `all` | `./clash-aio-local.sh all` |
| `clash-compose-up.sh` | Start stack (delegates to `clash-aio-local.sh up`); host port preflight before `up` | `./clash-compose-up.sh` |
| `clash-compose-down.sh` | Stop and remove the stack | `./clash-compose-down.sh` |
| `clash-compose-up-verify.sh` | Start + `.env` / host port preflight / readiness / proxy checks | `./clash-compose-up-verify.sh` |
| `clash-verify-mixed-proxy-portmap.sh` | Verify Clash mixed proxy through Compose host port map | `./clash-verify-mixed-proxy-portmap.sh` |
| `clash-list-proxies-latency.sh` | List proxies and latency | `./clash-list-proxies-latency.sh`（控制面端口来自 `.env`） |
| `clash-select-proxy-by-index.sh` | Switch proxy by menu index | `./clash-select-proxy-by-index.sh` |
| `clash-subscription-hot-reload.sh` | Hot-reload subscription (no container rebuild) | `./clash-subscription-hot-reload.sh` |
| `clash-subscription-rebuild.sh` | Recreate Clash container to re-fetch subscription | `./clash-subscription-rebuild.sh` |

Also: `deploy-remote.sh`, `vps-clash-aio-bootstrap.sh` (VPS one-shot), `deploy-server.sh`, `fix-images.sh` (deploy / image fixes); `clash-env.inc.sh` and `clash-compose-cmd.inc.sh` are sourced by host scripts (not run directly). Optional dev: copy `docker-compose.override.example.yaml` to `docker-compose.override.yaml` to bind-mount `preprocess.sh`. Container entrypoint is `preprocess.sh` (do not rename).

## Dependencies

- [Clash](https://github.com/Dreamacro/clash)
- [YACD Control Panel](https://github.com/haishanh/yacd)
- [Subconverter](https://github.com/tindy2013/subconverter)

## FAQ

- Why emmbedded web control panel?

  In many usage scenarios, there are no conditions to use a public control panel (such as [yacd.haishan.me](http://yacd.haishan.me/)) to manage Clash.If conditions permit, you can still use your own management tool.

- What should I do if I fail to build the project because I can't access Dockerhub / Github on the server?

  This project in itself exists for engineering purposes, and as a project contributor, I cannot provide dependencies that can be used in various complex internal and external network environments. I suggest that you fork this project and modify the Dockerfile and docker-compose yourself, pointing the dependencies to an accessible image source.