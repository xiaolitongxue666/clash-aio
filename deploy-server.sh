#!/bin/bash
# clash-aio 服务器部署脚本
# 需要在 root 用户下执行

set -e

echo "=== clash-aio 部署脚本 ==="
echo ""

# 检查是否为 root 用户
if [ "$EUID" -ne 0 ]; then 
    echo "❌ 错误: 请使用 root 用户执行此脚本"
    echo "   执行: sudo su -"
    exit 1
fi

# 设置部署目录
DEPLOY_DIR="/opt/clash-aio"
USER_HOME="/home/leonli"

echo "1. 创建部署目录..."
mkdir -p ${DEPLOY_DIR}/subconverter
cd ${DEPLOY_DIR}

echo "2. 复制文件到部署目录..."
cp ${USER_HOME}/clash-with-ui.tar.gz .
cp ${USER_HOME}/subconverter.tar.gz .
cp ${USER_HOME}/subconverter-files.tar.gz .
cp ${USER_HOME}/.env .
cp ${USER_HOME}/Dockerfile .
cp ${USER_HOME}/preprocess.sh .

echo "3. 解压 subconverter 配置文件..."
tar xzf subconverter-files.tar.gz
rm -f subconverter-files.tar.gz

echo "4. 解压镜像文件..."
gunzip -f clash-with-ui.tar.gz subconverter.tar.gz 2>/dev/null || true

echo "5. 加载镜像到 Podman..."
podman load -i clash-with-ui.tar
podman load -i subconverter.tar

echo "5.1 为镜像打标签..."
# 获取加载后的镜像ID并打标签
CLASH_IMAGE=$(podman images --format "{{.Repository}}:{{.Tag}}" | grep -E "clash-aio_clash-with-ui|clash-with-ui" | head -1)
SUB_IMAGE=$(podman images --format "{{.Repository}}:{{.Tag}}" | grep -E "tindy2013/subconverter|subconverter" | head -1)

# 打上简单的标签
podman tag "${CLASH_IMAGE}" clash-with-ui:latest 2>/dev/null || true
podman tag "${SUB_IMAGE}" subconverter:latest 2>/dev/null || true

echo "6. 设置文件权限..."
chmod +x preprocess.sh

echo "7. 复制 podman-compose.yaml..."
cp ${USER_HOME}/podman-compose.yaml . 2>/dev/null || {
    echo "⚠️  警告: podman-compose.yaml 未找到，将创建默认配置"
    cat > podman-compose.yaml << 'COMPOSE_EOF'
services:
  subconverter: 
    image: localhost/subconverter:latest
    hostname: subconverter
    container_name: subconverter
    volumes:
      - ./subconverter/all_base.tpl:/base/base/all_base.tpl:Z
      - ./subconverter/pref.toml:/base/pref.toml:Z
    ports:
      - "25500:25500"

  clash-with-ui:
    image: localhost/clash-with-ui:latest
    container_name: clash-with-ui
    depends_on:
      - subconverter
    env_file:
      - .env
    ports:
      - "7891:7890"
      - "9099:9090"
COMPOSE_EOF
}

echo ""
echo "8. 使用 podman-compose 启动服务..."
podman-compose -f podman-compose.yaml down 2>/dev/null || true
podman-compose -f podman-compose.yaml up -d

echo ""
echo "等待服务启动..."
sleep 10

# 显示状态
echo ""
echo "=== 服务状态 ==="
podman-compose -f podman-compose.yaml ps

echo ""
echo "=== 访问信息 ==="
SERVER_IP=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "localhost")
echo "代理端口: 7891"
echo "控制面板: http://${SERVER_IP}:9099/ui?hostname=${SERVER_IP}"
echo "或本地访问: http://localhost:9099/ui?hostname=localhost"
echo ""
echo "常用命令:"
echo "  查看日志: podman-compose -f podman-compose.yaml logs -f clash-with-ui"
echo "  重启服务: cd ${DEPLOY_DIR} && podman-compose -f podman-compose.yaml restart"
echo "  停止服务: cd ${DEPLOY_DIR} && podman-compose -f podman-compose.yaml down"

echo ""
echo "✅ 部署完成！"
echo ""
echo "常用命令:"
echo "  查看日志: podman logs -f clash-with-ui"
echo "  重启服务: cd ${DEPLOY_DIR} && ./podman-run.sh"
echo "  停止服务: podman stop clash-with-ui subconverter"

