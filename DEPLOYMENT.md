# clash-aio 部署流程完整指南

## 一、部署概述

本项目是一个基于 Docker/Podman 的 Clash 代理服务，包含：
- **Clash** - 代理核心服务
- **Subconverter** - 订阅转换服务
- **YACD** - Web 控制面板

部署环境要求：
- 服务器：Linux（支持 Podman）
- 本地：macOS/Linux（支持 Docker）

---

## 二、文件上传清单

### 2.1 上传到用户目录 (~leonli/)

**通过 SFTP 上传以下文件到 `~leonli/` 目录：**

```bash
# 镜像文件（压缩后）
clash-with-ui.tar.gz          # clash 镜像（~11MB）
subconverter.tar.gz            # subconverter 镜像（~7.5MB）

# 配置文件
subconverter-files.tar.gz      # subconverter 配置目录（包含 all_base.tpl 和 pref.toml）
.env                           # 环境变量配置
Dockerfile                     # 构建文件（备用）
preprocess.sh                  # 启动脚本
podman-compose.yaml            # Podman Compose 配置文件
deploy-server.sh               # 自动部署脚本（可选）
```

**上传命令示例：**
```bash
# 从本地执行
scp clash-with-ui.tar.gz subconverter.tar.gz subconverter-files.tar.gz \
    .env Dockerfile preprocess.sh podman-compose.yaml deploy-server.sh \
    leonli@alchemy-studio.cn:~/
```

### 2.2 部署到 /opt/clash-aio/

**部署脚本会自动将文件从 `~leonli/` 复制到 `/opt/clash-aio/`，包括：**

- `clash-with-ui.tar` - 解压后的 clash 镜像
- `subconverter.tar` - 解压后的 subconverter 镜像
- `.env` - 环境变量配置
- `Dockerfile` - 构建文件
- `preprocess.sh` - 启动脚本
- `podman-compose.yaml` - Podman Compose 配置
- `subconverter/` - 解压后的配置目录（包含 all_base.tpl 和 pref.toml）

---

## 三、完整部署流程

### 步骤 1: 本地打包镜像

```bash
# 进入项目目录
cd /Users/liyong/Code/AlchemyStudio/clash-cotainer/clash-aio

# 构建镜像
docker compose build

# 保存镜像为 tar 文件
docker save clash-aio_clash-with-ui:latest -o clash-with-ui.tar
docker save tindy2013/subconverter:latest -o subconverter.tar

# 压缩镜像文件（减少传输大小）
gzip clash-with-ui.tar subconverter.tar

# 打包 subconverter 配置文件
tar czf subconverter-files.tar.gz subconverter/
```

### 步骤 2: 上传文件到服务器

```bash
# 上传所有必需文件到用户目录
scp clash-with-ui.tar.gz subconverter.tar.gz subconverter-files.tar.gz \
    .env Dockerfile preprocess.sh podman-compose.yaml deploy-server.sh \
    leonli@alchemy-studio.cn:~/
```

### 步骤 3: SSH 到服务器并切换到 root

```bash
# SSH 连接
ssh leonli@alchemy-studio.cn

# 切换到 root 用户（Podman 需要 root 权限）
sudo su -
```

### 步骤 4: 执行部署脚本

```bash
# 执行自动部署脚本
bash ~leonli/deploy-server.sh
```

**或者手动执行部署步骤：**

```bash
# 1. 创建部署目录
mkdir -p /opt/clash-aio/subconverter
cd /opt/clash-aio

# 2. 复制文件从用户目录到部署目录
cp ~leonli/clash-with-ui.tar.gz .
cp ~leonli/subconverter.tar.gz .
cp ~leonli/subconverter-files.tar.gz .
cp ~leonli/.env .
cp ~leonli/Dockerfile .
cp ~leonli/preprocess.sh .
cp ~leonli/podman-compose.yaml .

# 3. 解压配置文件
tar xzf subconverter-files.tar.gz
rm -f subconverter-files.tar.gz

# 4. 解压镜像文件
gunzip -f clash-with-ui.tar.gz subconverter.tar.gz

# 5. 加载镜像到 Podman
podman load -i clash-with-ui.tar
podman load -i subconverter.tar

# 6. 为镜像打标签
CLASH_IMAGE=$(podman images --format "{{.Repository}}:{{.Tag}}" | grep -E "clash-aio_clash-with-ui|clash-with-ui" | head -1)
SUB_IMAGE=$(podman images --format "{{.Repository}}:{{.Tag}}" | grep -E "tindy2013/subconverter|subconverter" | head -1)
podman tag "${CLASH_IMAGE}" clash-with-ui:latest
podman tag "${SUB_IMAGE}" subconverter:latest

# 7. 设置权限
chmod +x preprocess.sh

# 8. 使用 podman-compose 启动服务
podman-compose -f podman-compose.yaml down 2>/dev/null || true
podman-compose -f podman-compose.yaml up -d
```

---

## 四、启动流程说明

### 4.1 服务启动顺序

1. **Subconverter 启动**
   - 监听端口：25500
   - 功能：订阅转换服务
   - 等待时间：约 5 秒

2. **Clash-with-ui 启动**
   - 监听端口：7891（代理）、9099（控制面板）
   - 功能：Clash 代理服务 + Web UI
   - 自动从 subconverter 下载配置文件

### 4.2 启动验证

```bash
# 检查容器状态
sudo podman-compose -f /opt/clash-aio/podman-compose.yaml ps

# 查看日志
sudo podman-compose -f /opt/clash-aio/podman-compose.yaml logs clash-with-ui
sudo podman-compose -f /opt/clash-aio/podman-compose.yaml logs subconverter

# 测试 API
curl http://localhost:9099/version
# 应该返回: {"version":"v1.18.0"}
```

---

## 五、Web UI 访问说明

### 5.1 重要提示 ⚠️

**Web UI 需要手动配置 API Base URL 才能正常使用！**

### 5.2 访问步骤

1. **打开 Web UI**
   ```
   http://localhost:9099/ui/
   ```
   或从外部访问：
   ```
   http://[服务器IP]:9099/ui/
   ```

2. **配置 API Base URL**
   - 页面会显示一个猫猫头（YACD 默认界面）
   - **点击右上角的设置图标（齿轮）**
   - 在 "API Base URL" 输入框中输入：
     ```
     http://localhost:9099
     ```
     或从外部访问时输入：
     ```
     http://[服务器IP]:9099
     ```
   - **Secret 字段留空**（不填写任何内容）
   - 点击保存/连接按钮

3. **进入详细页面**
   - 配置完成后，页面会自动刷新
   - 现在可以正常查看代理节点、流量统计等详细信息
   - 可以访问 `/proxies`、`/rules`、`/logs` 等页面

### 5.3 为什么需要手动配置？

- YACD 前端默认尝试连接 `http://127.0.0.1:9090`（容器内地址）
- 但实际访问需要通过 `localhost:9099`（外部映射端口）
- 因此需要在 YACD 设置中手动指定正确的 API 地址

### 5.4 访问地址总结

| 访问方式 | Web UI 地址 | API Base URL 配置 |
|---------|------------|------------------|
| 服务器本地 | `http://localhost:9099/ui/` | `http://localhost:9099` |
| 外部访问 | `http://[服务器IP]:9099/ui/` | `http://[服务器IP]:9099` |
| 域名访问 | `http://alchemy-studio.cn:9099/ui/` | `http://alchemy-studio.cn:9099` |

---

## 六、文件位置映射表

| 文件/目录 | 用户目录 (~leonli/) | 部署目录 (/opt/clash-aio/) | 说明 |
|----------|-------------------|-------------------------|------|
| clash-with-ui.tar.gz | ✅ 上传 | ✅ 复制并解压 | clash 镜像 |
| subconverter.tar.gz | ✅ 上传 | ✅ 复制并解压 | subconverter 镜像 |
| subconverter-files.tar.gz | ✅ 上传 | ✅ 复制并解压 | 配置文件包 |
| .env | ✅ 上传 | ✅ 复制 | 环境变量 |
| Dockerfile | ✅ 上传 | ✅ 复制 | 构建文件（备用） |
| preprocess.sh | ✅ 上传 | ✅ 复制 | 启动脚本 |
| podman-compose.yaml | ✅ 上传 | ✅ 复制 | Podman Compose 配置 |
| deploy-server.sh | ✅ 上传 | ❌ 不复制 | 部署脚本（仅执行） |
| subconverter/ | ❌ 不直接上传 | ✅ 从 tar.gz 解压 | 配置目录 |

---

## 七、常用管理命令

### 7.1 服务管理

```bash
# 进入部署目录
cd /opt/clash-aio

# 启动服务
sudo podman-compose -f podman-compose.yaml up -d

# 停止服务
sudo podman-compose -f podman-compose.yaml down

# 重启服务
sudo podman-compose -f podman-compose.yaml restart

# 查看服务状态
sudo podman-compose -f podman-compose.yaml ps
```

### 7.2 日志查看

```bash
# 查看 clash-with-ui 日志
sudo podman-compose -f podman-compose.yaml logs -f clash-with-ui

# 查看 subconverter 日志
sudo podman-compose -f podman-compose.yaml logs -f subconverter

# 查看所有日志
sudo podman-compose -f podman-compose.yaml logs -f
```

### 7.3 代理使用

```bash
# 设置代理环境变量
export http_proxy=http://localhost:7891
export https_proxy=http://localhost:7891
export all_proxy=socks5://localhost:7891

# 测试代理
curl --proxy http://localhost:7891 http://httpbin.org/ip

# 取消代理
unset http_proxy https_proxy all_proxy
```

---

## 八、端口说明

| 端口 | 服务 | 说明 |
|------|------|------|
| 7891 | Clash 代理 | HTTP/HTTPS/SOCKS5 代理端口 |
| 9099 | Clash Web UI | Web 控制面板端口 |
| 25500 | Subconverter | 订阅转换服务端口（通常不需要外网访问） |

**注意：** 如果本地已有 ClashX 占用 7890 和 9090 端口，clash-aio 使用 7891 和 9099 端口，可以同时运行。

---

## 九、使用 podman-compose 的优势

✅ **自动网络管理**：podman-compose 创建 pod，容器共享网络，DNS 解析正常  
✅ **简化部署**：一条命令启动所有服务  
✅ **配置清晰**：使用 YAML 配置文件，易于维护  
✅ **解决 DNS 问题**：容器间可以通过主机名（subconverter）正常通信

---

## 十、常见问题

### 问题 1: 容器间无法通信（DNS 解析失败）

**症状：** clash-with-ui 无法连接到 subconverter

**解决方案：** 使用 podman-compose，它会自动创建 pod 并配置网络，容器间可以通过主机名通信。

### 问题 2: Web UI 显示猫猫头但无法查看详细信息

**症状：** 访问 Web UI 只显示默认界面，无法查看代理节点

**解决方案：** 
1. 点击右上角设置图标（齿轮）
2. 在 "API Base URL" 中输入 `http://localhost:9099`（或对应的服务器地址）
3. Secret 留空
4. 点击保存/连接

### 问题 3: 配置文件下载失败

**症状：** clash-with-ui 日志显示 "wget: bad address 'subconverter:25500'"

**解决方案：** podman-compose 创建的 pod 中，容器共享网络，`subconverter` 主机名可以正常解析。如果仍有问题，检查容器是否在同一 pod 中。

### 问题 4: 端口冲突

**症状：** 启动失败，提示端口已被占用

**解决方案：** 
- 检查端口占用：`sudo netstat -tlnp | grep 9099`
- 修改 `.env` 文件中的端口配置
- 或停止占用端口的服务

---

## 十一、服务器重启后的服务管理

### 11.1 服务器重启后重启服务

**服务器重启后，容器不会自动启动，需要手动重启服务：**

```bash
# SSH 到服务器
ssh leonli@alchemy-studio.cn

# 切换到 root 用户
sudo su -

# 进入部署目录
cd /opt/clash-aio

# 启动服务
sudo podman-compose -f podman-compose.yaml up -d

# 验证服务状态
sudo podman-compose -f podman-compose.yaml ps

# 检查服务是否正常
curl http://localhost:9099/version
```

### 11.2 配置开机自启动（可选）

如果需要服务器重启后自动启动 clash-aio 服务，可以创建 systemd 服务：

**创建 systemd 服务文件：**

```bash
sudo cat > /etc/systemd/system/clash-aio.service << 'EOF'
[Unit]
Description=Clash AIO Service
After=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/clash-aio
ExecStart=/usr/bin/podman-compose -f /opt/clash-aio/podman-compose.yaml up -d
ExecStop=/usr/bin/podman-compose -f /opt/clash-aio/podman-compose.yaml down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF
```

**启用并启动服务：**

```bash
# 重新加载 systemd 配置
sudo systemctl daemon-reload

# 启用开机自启动
sudo systemctl enable clash-aio.service

# 启动服务
sudo systemctl start clash-aio.service

# 检查服务状态
sudo systemctl status clash-aio.service
```

**管理 systemd 服务：**

```bash
# 启动服务
sudo systemctl start clash-aio

# 停止服务
sudo systemctl stop clash-aio

# 重启服务
sudo systemctl restart clash-aio

# 查看服务状态
sudo systemctl status clash-aio

# 查看服务日志
sudo journalctl -u clash-aio -f

# 禁用开机自启动
sudo systemctl disable clash-aio
```

### 11.3 快速重启脚本

可以创建一个快速重启脚本：

```bash
# 创建重启脚本
sudo cat > /opt/clash-aio/restart.sh << 'EOF'
#!/bin/bash
cd /opt/clash-aio
sudo podman-compose -f podman-compose.yaml restart
echo "服务已重启"
sudo podman-compose -f podman-compose.yaml ps
EOF

# 设置执行权限
sudo chmod +x /opt/clash-aio/restart.sh
```

**使用重启脚本：**

```bash
sudo /opt/clash-aio/restart.sh
```

---

## 十二、环境变量配置 (.env)

```bash
RAW_SUB_URL="https://your-subscription-url"
ALLOW_LAN=true
BIND_ADDRESS="*"
MODE=rule
ALL_PROXY_PORT=7891        # 代理端口（避免与本地 ClashX 冲突）
CONTROL_PANEL_PORT=9099    # 控制面板端口（避免与本地 ClashX 冲突）
```

---

## 十三、部署检查清单

- [ ] 本地已构建并打包镜像
- [ ] 所有文件已上传到 `~leonli/` 目录
- [ ] 已 SSH 到服务器并切换到 root
- [ ] 已执行部署脚本或手动部署
- [ ] 容器已成功启动（`podman ps` 检查）
- [ ] API 可以访问（`curl http://localhost:9099/version`）
- [ ] Web UI 可以打开（`http://localhost:9099/ui/`）
- [ ] 已在 YACD 设置中配置 API Base URL
- [ ] 可以正常查看代理节点和详细信息

---

## 十四、回滚和更新

### 更新服务

```bash
cd /opt/clash-aio

# 停止服务
sudo podman-compose -f podman-compose.yaml down

# 重新加载镜像（如果有新镜像）
sudo podman load -i clash-with-ui.tar
sudo podman load -i subconverter.tar

# 重新打标签
podman tag [镜像ID] clash-with-ui:latest
podman tag [镜像ID] subconverter:latest

# 启动服务
sudo podman-compose -f podman-compose.yaml up -d
```

### 清理部署

```bash
# 停止并删除容器
cd /opt/clash-aio
sudo podman-compose -f podman-compose.yaml down

# 删除镜像（可选）
sudo podman rmi clash-with-ui:latest subconverter:latest

# 删除部署目录（可选）
sudo rm -rf /opt/clash-aio
```
