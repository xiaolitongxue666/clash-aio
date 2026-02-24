# Lazy Clash

[中文](README-zh.md) [English](README.md)

Lazy Clash is a one-click deployment solution for Clash based on Docker Compose. It can help you quickly set up a Clash proxy service with automatically updated subscriptions. —— by ChatGPT

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

1. Set your clash subscription url in `.env` file or mount your config file to `/root/.config/clash/config.yaml`

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

On Windows (Git Bash) you can run `./run-and-verify.sh` in the project directory to check .env, start services, and verify (port 9090; 7891–7899 used if 7890 is in use).

3. (Optional) Management

- **Web control panel**: `http://[server-ip]:9090/ui?hostname=[server-ip]`
- **CLI scripts** (run in project directory; require curl, pure Bash, no jq):
  - **List proxies and delay**: `./list-proxy-delay.sh [port] [count]`  
    e.g. `./list-proxy-delay.sh 9090 20` for first 20 nodes; use 0 as count for all.
  - **Select proxy by index**: `./select-proxy.sh [port] [count]`  
    Shows numbered list and delay; enter 1–N to switch, 0 or q to cancel.  
    e.g. `./select-proxy.sh 9090 10`
  - **Test proxy on host**: `./test-proxy.sh [port]` (default 7890); hits ipinfo.io to verify proxy.

4. (Optional) Export proxy

```bash
export https_proxy=http://[server-ip]:7890
export http_proxy=http://[server-ip]:7890
export all_proxy=socks5://[server-ip]:7890
```

5. (Optional) Manual subscription update

The stack fetches the subscription only when the container **starts for the first time and has no config**; it does not auto-update afterward.

- **Recommended (no restart)**: Run `./refresh-subscription.sh` in the project directory to pull new config from subconverter, copy into the container, and reload via Clash API.
- **Fallback**: If refresh fails (e.g. API unavailable), run `./update-subscription.sh` or `docker compose up -d --force-recreate clash-with-ui` to recreate the container and re-fetch. A plain `restart` does not re-fetch; the container must be **recreated**.

6. (Optional) Scheduled subscription update

Run `./refresh-subscription.sh` on a schedule (cron on Linux/WSL/Git Bash, or Windows Task Scheduler with Git Bash).

## Dependencies

- [Clash](https://github.com/Dreamacro/clash)
- [YACD Control Panel](https://github.com/haishanh/yacd)
- [Subconverter](https://github.com/tindy2013/subconverter)

## FAQ

- Why emmbedded web control panel?

  In many usage scenarios, there are no conditions to use a public control panel (such as [yacd.haishan.me](http://yacd.haishan.me/)) to manage Clash.If conditions permit, you can still use your own management tool.

- What should I do if I fail to build the project because I can't access Dockerhub / Github on the server?

  This project in itself exists for engineering purposes, and as a project contributor, I cannot provide dependencies that can be used in various complex internal and external network environments. I suggest that you fork this project and modify the Dockerfile and docker-compose yourself, pointing the dependencies to an accessible image source.