# Clash 懒人全家桶

[中文](README-zh.md) [English](README.md)

## 概述

Clash 懒人全家桶是一个基于 Docker Compose 的 Clash 一键部署方案，它可以帮助你快速搭建一个自定更新订阅的 Clash 代理服务。 —— by ChatGPT

个人使用场景
- 路由器/Nas 无痛快速部署
- 服务器上快速部署临时使用，用完即删

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

1. 在 .env 文件中设置 Clash 订阅 URL或者直接把 Clash 文件路径映射进容器

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

Windows 用户（Git Bash）可在项目目录下运行 `./run-and-verify.sh` 完成 .env 检查、启动与验证。

3. (可选) 管理代理

查看控制面板: `http://[服务器IP]:9090/ui?hostname=[服务器IP]`

4. (可选) 设置代理环境变量

```bash
export https_proxy=http://[服务器IP]:7890
export http_proxy=http://[服务器IP]:7890
export all_proxy=socks5://[服务器IP]:7890
```

5. (可选) 手动更新订阅

本方案只在容器**首次启动且无 config** 时拉取订阅，之后不会自动更新。

- **推荐（无重启）**：在项目目录运行 `./refresh-subscription.sh`，从 subconverter 拉取新 config 并写入容器后调用 Clash API 重载，不断连。
- **兜底**：若 refresh 失败（如 API 不可用），可运行 `./update-subscription.sh` 或执行 `docker compose up -d --force-recreate clash-with-ui` 重建容器以重新拉取。注意：仅 `restart` 不会重新拉取，必须**重建**容器。

6. (可选) 定时更新订阅

复用上述「推荐」方式，由系统定时执行 `./refresh-subscription.sh` 即可。

- **Linux / WSL / Git Bash**：用 cron。示例（每天 4 点执行）：将 `cron.example` 中的一行加入 `crontab -e`，或放入 `/etc/cron.d/`，并把路径改为你的项目目录。
- **Windows**：用「任务计划程序」创建基本任务，触发器选「每天」或「每 N 小时」，操作启动程序为 Git Bash 的 `bash.exe`，参数为 `-c "cd /path/to/clash-aio && ./refresh-subscription.sh"`（路径按实际修改）。

## 依赖

- [Clash](https://github.com/Dreamacro/clash)
- [Web 控制台](https://github.com/haishanh/yacd)
- [Subconverter](https://github.com/tindy2013/subconverter)

## 常见问题

- 为什么内置 Web 控制台？

  在许多使用场景中，并没有条件使用公网的控制平台（比如 [yacd.haishan.me](http://yacd.haishan.me/)）来管理 Clash。如果条件允许，你依旧可以使用自己的管理工具来控制 Clash。

- 我在服务器上无法访问 Dockerhub / Github，项目构建失败怎么办？

  本身该项目是为了工程存在的，作为项目贡献者我无法提供在各种复杂内外网环境均可使用依赖。建议你 Fork 该项目，并在自行修改 Dockerfile 和 docker-compose，将依赖指向可以访问的镜像源。