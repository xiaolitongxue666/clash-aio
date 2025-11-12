#!/bin/bash
# 修复镜像标签脚本
# 在服务器上 root 用户执行

set -e

echo "=== 修复镜像标签 ==="

# 检查是否为 root 用户
if [ "$EUID" -ne 0 ]; then 
    echo "❌ 错误: 请使用 root 用户执行此脚本"
    exit 1
fi

echo "1. 查找已加载的镜像..."
CLASH_IMAGE=$(podman images --format "{{.Repository}}:{{.Tag}}" | grep -E "clash-aio_clash-with-ui|clash-with-ui" | head -1)
SUB_IMAGE=$(podman images --format "{{.Repository}}:{{.Tag}}" | grep -E "tindy2013/subconverter|subconverter" | head -1)

if [ -z "$CLASH_IMAGE" ] || [ -z "$SUB_IMAGE" ]; then
    echo "❌ 错误: 未找到镜像"
    echo "clash 镜像: $CLASH_IMAGE"
    echo "subconverter 镜像: $SUB_IMAGE"
    exit 1
fi

echo "找到 clash 镜像: $CLASH_IMAGE"
echo "找到 subconverter 镜像: $SUB_IMAGE"

echo ""
echo "2. 为镜像打标签..."
podman tag "${CLASH_IMAGE}" clash-with-ui:latest
podman tag "${SUB_IMAGE}" subconverter:latest

echo "✅ 标签已创建"
echo ""
echo "3. 验证镜像..."
podman images | grep -E "clash-with-ui|subconverter" | grep latest

echo ""
echo "✅ 修复完成！"
echo ""
echo "现在可以执行: cd /opt/clash-aio && ./podman-run.sh"

