# Clash 懒人全家桶

[中文](README-zh.md) [English](README.md)

## 概述

Clash 懒人全家桶是一个基于 Docker Compose 的 Clash 一键部署方案，它可以帮助你快速搭建一个自定更新订阅的 Clash 代理服务。 —— by ChatGPT

个人使用场景
- 路由器/Nas 无痛快速部署
- 服务器上快速部署临时使用，用完即删

## 工作区中的层级与相关仓库

与同目录 [`README.md`](README.md) 中 **「Workspace context」** / **「工作区中的定位（中文摘要）」** 一致，以下为中文展开。

**本仓库职责**：在目标 Linux 上以 **Docker Compose** 提供 **Clash + subconverter + Web 控制台（YACD）**；约定宿主机端口契约（`ALL_PROXY_PORT`、`CONTROL_PANEL_PORT`、`SUBCONVERTER_HOST_PORT`），并提供本机脚本（如 `clash-aio-local.sh`、`clash-compose-up-verify.sh`、`clash-verify-mixed-proxy-portmap.sh` 等）及可选 **远端交付**：`deploy-remote.sh`（构建并导出镜像 + 打包工程）→ 上传 → 目标机执行 `vps-clash-aio-bootstrap.sh`（按需安装 Docker、`docker load`、`compose up` 与连通性校验）。Linux 上 Docker CE 相关逻辑见 `clash-docker-prereq.inc.sh`，部署细节见 [DEPLOYMENT.md](DEPLOYMENT.md)。

**在工作区整体层级中的位置**：处于 **中层（跑在目标机上的边缘代理 / 订阅编排服务）**；前提是一台 **可 SSH** 的主机，且多数场景需要 **Docker**。**不依赖** `vps_construct_scripts` 源码；若目标机曾用 vps 脚本做过基线，需自行协调 UFW、Tailscale、已占用端口等与 `docker compose up` 的关系。

**与相邻仓库的衔接（非子模块）**：底层可用 **`qemu_test_vm`** 在本机拉起可丢弃的 **Ubuntu 访客机** 做联调；同机还可运行 **`vps_construct_scripts`** 做系统初始化——三者为 **独立 Git 仓库**，工作区根目录 **无** 总控编排脚本，由你自行决定执行顺序与 SSH 目标。英文版说明见 [`README.md`](README.md)。

## 独立前置代理平面（与 vps_construct 等消费者）

本仓库可作为与业务/装机**解耦**的**出站代理平面**：对外只承诺 **`.env` 中的端口契约**（`ALL_PROXY_PORT`、`CONTROL_PANEL_PORT`、`SUBCONVERTER_HOST_PORT`）与启动前**宿主机端口预检**（见 `clash-env.inc.sh`）；不替消费者自动改端口。消费者可选设置 `HTTP_PROXY` / `HTTPS_PROXY` / `ALL_PROXY` 指向本栈 mixed 口。**生命周期**在本仓库内完成（`clash-aio-local.sh`、`deploy-remote.sh`、`vps-clash-aio-bootstrap.sh` 等），**不必**作为其它仓库的子模块。

与 **vps_construct_scripts** QEMU 严格路径常用的离线包命名（`clash-aio-main.zip` + `clash-aio-images.tar`）和本仓库 **`deploy-remote.sh pack`** 产物（`dist/clash-aio-bundle.zip` + `dist/clash-aio-images.tar.gz`）是**两条线**，勿混为一种「真理」；衔接方式见 [DEPLOYMENT.md](DEPLOYMENT.md) 一点五节。

**Docker 引擎**：`clash-docker-prereq.inc.sh` 会在本机一键与 `vps-clash-aio-bootstrap.sh`（`VPS_DEPLOY_CONTAINER_ENGINE=docker`）中按需检测/安装 Docker CE 与 compose 插件（Linux）；平台说明见 [DEPLOYMENT.md](DEPLOYMENT.md)「一点二五」下 Docker 前置段落。

## 功能

- 基于 Clash 的 proxy-providers 自动更新订阅
- 基于 subconverter 统一代理服务格式和自动分组
- 内置 YACD Web 控制台
- 使用 Docker Compose 一行命令完成部署

## 使用方法

0. 克隆代码

```bash
git clone https://github.com/pandazki/clash-aio.git
# 如果遇到困难的话
# git clone https://ghproxy.com/https://github.com/pandazki/clash-aio.git
```

1. 在 `.env` 中设置 Clash 订阅 URL，并按需设置 `ALL_PROXY_PORT`、`CONTROL_PANEL_PORT`、`SUBCONVERTER_HOST_PORT`（见 `.env.example`）；也可把 Clash 配置文件映射进容器

```bash
cd clash-aio
cp .env.example .env
# 在 .env 文件中设置 RAW_SUB_URL="你自己的 Clash 订阅"
```

或者

```docker-compose
...
    volumes:
      - /path/to/your/config.yaml:/root/.config/clash/config.yaml
...
```

2. 运行 docker-compose

```bash
docker compose up -d
```

与上述等价、便于记忆的**脚本方式**（均在项目根目录执行）：

| 操作 | 脚本 | 说明 |
|------|------|------|
| 本机一键 | `./clash-aio-local.sh` | `pull`（`compose pull` + `build --pull`）、`up`（同下行）、`shell`（进容器）、`all`（先 `pull` 再 `up`）；可选端口：`./clash-aio-local.sh up 7891` |
| 启动栈 | `./clash-compose-up.sh` | 转调 `clash-aio-local.sh up`：`docker compose down` 后 `up -d`；**`up` 前**执行 `clash_require_env_ports_free_for_compose_up`（`clash-env.inc.sh`）；可选参数先写回 `ALL_PROXY_PORT` |
| 停止栈 | `./clash-compose-down.sh` | 对 `docker-compose.yaml` 执行 `docker compose down` |
| 启动并验证 | `./clash-compose-up-verify.sh` | 检查 `.env`、**同上宿主机三端口预检**、`compose up`、探测 `/version` 与代理（**推荐**，尤其 Windows Git Bash） |

Windows 用户（Git Bash）可在项目目录下运行 `./clash-compose-up-verify.sh` 完成 `.env` 检查、启动与验证。启动前会检查 `.env` 中的 `ALL_PROXY_PORT`、`CONTROL_PANEL_PORT`、`SUBCONVERTER_HOST_PORT` 在宿主机是否被占用；若被其它程序占用则醒目报错并退出（已是本 compose 映射的端口则放行）。

3. (可选) 管理代理

- **Web 控制面板**：`http://[服务器IP]:<CONTROL_PANEL_PORT>/ui?hostname=...`（端口见 `.env`，`.env.example` 默认为 9090）
- **命令行脚本**（项目目录下执行，依赖 curl，纯 Bash 无 jq）：
  - **列出节点与延迟**：`./clash-list-proxies-latency.sh [控制面板端口] [数量]` — 省略第一参数时控制面端口来自 `.env` / `.env.example`；与 `.env` 不一致时再显式传入。  
    例：`./clash-list-proxies-latency.sh` 或 `./clash-list-proxies-latency.sh 9095 20`；第二参数为 0 表示测全部节点。
  - **按序号选择节点**：`./clash-select-proxy-by-index.sh [控制面板端口] [数量]` — 端口规则同上。  
    例：`./clash-select-proxy-by-index.sh` 或 `./clash-select-proxy-by-index.sh 9095 10`
  - **验证端口映射下的混合代理**：`./clash-verify-mixed-proxy-portmap.sh [宿主机端口]`；无参数时 `ALL_PROXY_PORT` 来自 `.env` / `.env.example`（`clash-env.inc.sh`）。经 Docker 映射进入容器内 Clash mixed（容器内固定 7890），默认 URL 为 `http://ip-api.com/json/`。

4. (可选) 设置代理环境变量

```bash
# <ALL_PROXY_PORT> 替换为 .env 中宿主机映射的混合代理端口
export https_proxy=http://[服务器IP]:<ALL_PROXY_PORT>
export http_proxy=http://[服务器IP]:<ALL_PROXY_PORT>
export all_proxy=socks5://[服务器IP]:<ALL_PROXY_PORT>
```

5. (可选) 手动更新订阅

本方案只在容器**首次启动且无 config** 时拉取订阅，之后不会自动更新。

- **推荐（无重启）**：在项目目录运行 `./clash-subscription-hot-reload.sh`，从 subconverter 拉取新 config 并写入容器后调用 Clash API 重载，不断连。
- **兜底**：若热重载失败（如 API 不可用），可运行 `./clash-subscription-rebuild.sh` 或执行 `docker compose up -d --force-recreate clash-with-ui` 重建容器以重新拉取。注意：仅 `restart` 不会重新拉取，必须**重建**容器。

6. (可选) 定时更新订阅

复用上述「推荐」方式，由系统定时执行 `./clash-subscription-hot-reload.sh` 即可。

- **Linux / WSL / Git Bash**：用 cron。示例（每天 4 点执行）：将 `cron.example` 中的一行加入 `crontab -e`，或放入 `/etc/cron.d/`，并把路径改为你的项目目录。
- **Windows**：用「任务计划程序」创建基本任务，触发器选「每天」或「每 N 小时」，操作启动程序为 Git Bash 的 `bash.exe`，参数为 `-c "cd /path/to/clash-aio && ./clash-subscription-hot-reload.sh"`（路径按实际修改）。

## 脚本一览

| 脚本 | 用途 | 典型命令 |
|------|------|----------|
| `clash-aio-local.sh` | 本地 pull / up / shell / all | `./clash-aio-local.sh all` |
| `clash-compose-up.sh` | 启动栈（转调 `clash-aio-local.sh up`）；`up` 前宿主机端口预检 | `./clash-compose-up.sh` |
| `clash-compose-down.sh` | 停止并移除栈 | `./clash-compose-down.sh` |
| `clash-compose-up-verify.sh` | 启动 + `.env` / 宿主机端口预检 / 就绪 / 代理验证 | `./clash-compose-up-verify.sh` |
| `clash-verify-mixed-proxy-portmap.sh` | 经 Compose 端口映射验证容器 Clash mixed | `./clash-verify-mixed-proxy-portmap.sh` |
| `clash-list-proxies-latency.sh` | 列出节点与延迟 | `./clash-list-proxies-latency.sh`（控制面端口来自 `.env`） |
| `clash-select-proxy-by-index.sh` | 按序号切换节点 | `./clash-select-proxy-by-index.sh` |
| `clash-subscription-hot-reload.sh` | 订阅热重载（无容器重建） | `./clash-subscription-hot-reload.sh` |
| `clash-subscription-rebuild.sh` | 重建 Clash 容器以重拉订阅 | `./clash-subscription-rebuild.sh` |

另有 `deploy-remote.sh`、`vps-clash-aio-bootstrap.sh`（VPS 一键）、`deploy-server.sh`、`fix-images.sh`（部署与镜像修复）；`clash-env.inc.sh`、`clash-compose-cmd.inc.sh` 供各脚本 `source`，勿单独执行。开发可选：复制 `docker-compose.override.example.yaml` 为 `docker-compose.override.yaml` 挂载 `preprocess.sh`。容器内入口为 `preprocess.sh`（勿改名）。

## 依赖

- [Clash](https://github.com/Dreamacro/clash)
- [Web 控制台](https://github.com/haishanh/yacd)
- [Subconverter](https://github.com/tindy2013/subconverter)

## 常见问题

- 为什么内置 Web 控制台？

  在许多使用场景中，并没有条件使用公网的控制平台（比如 [yacd.haishan.me](http://yacd.haishan.me/)）来管理 Clash。如果条件允许，你依旧可以使用自己的管理工具来控制 Clash。

- 我在服务器上无法访问 Dockerhub / Github，项目构建失败怎么办？

  本身该项目是为了工程存在的，作为项目贡献者我无法提供在各种复杂内外网环境均可使用依赖。建议你 Fork 该项目，并在自行修改 Dockerfile 和 docker-compose，将依赖指向可以访问的镜像源。