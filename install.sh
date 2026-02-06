#!/bin/bash

set -e

# ================= 权限检查 =================
if [ "$EUID" -ne 0 ]; then
  echo "❌ 错误: 此脚本需要 root 权限"
  echo "请使用 sudo 运行: sudo ./install.sh -e <endpoint>"
  exit 1
fi

# ================= 依赖检查 =================
check_command() {
    if ! command -v "$1" &> /dev/null; then
        echo "❌ 错误: 未找到命令 '$1'，请先安装"
        exit 1
    fi
}

echo "检查依赖..."
check_command wget
check_command curl
check_command tar

# ================= 帮助信息 =================
show_help() {
    cat << EOF
使用方法: sudo ./install.sh [选项]

选项:
  -e, --endpoint <address>    SigNoz Collector 端点地址 (必需)
  -c, --config <file1,file2>  要复制的配置文件名，用逗号分隔 (可选，默认自动检测)
  -h, --help                  显示此帮助信息

示例:
  sudo ./install.sh -e "192.168.1.100:4317"
  sudo ./install.sh -e "192.168.1.100:4317" -c "otel-collector-postgres-config.yaml,otel-collector-redis-config.yaml"
  sudo ./install.sh -e "192.168.1.100:4317" -c "otel-collector-postgres-config.yaml"

EOF
}

# ================= 参数解析 =================
SIGNOZ_ENDPOINT=""
CONFIG_FILES="auto"

while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--endpoint)
            SIGNOZ_ENDPOINT="$2"
            shift 2
            ;;
        -c|--config)
            CONFIG_FILES="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "❌ 未知选项: $1"
            show_help
            exit 1
            ;;
    esac
done

# ================= 配置检查 =================
if [ -z "$SIGNOZ_ENDPOINT" ]; then
  echo "❌ 错误: 必需参数 --endpoint 未提供"
  show_help
  exit 1
fi


# OTel Collector 版本配置
ARCH="amd64"
# ===========================================

echo "--- 开始安装 OpenTelemetry Collector Contrib ---"
echo "Target SigNoz Endpoint: $SIGNOZ_ENDPOINT"

# 1. 下载二进制文件
if [ ! -f "/usr/local/bin/otelcol-contrib" ]; then
    echo "正在获取最新的 OTel Collector 版本..."
    OTEL_VERSION=$(curl -s https://api.github.com/repos/open-telemetry/opentelemetry-collector-releases/releases/latest | grep -oP '"tag_name": "v\K[0-9.]+')
    
    if [ -z "$OTEL_VERSION" ]; then
        echo "❌ 错误: 无法获取最新版本号"
        exit 1
    fi
    
    echo "正在下载 OTel Collector v${OTEL_VERSION}..."
    if ! wget -q -O otelcol-contrib_${OTEL_VERSION}_linux_${ARCH}.tar.gz \
        https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v${OTEL_VERSION}/otelcol-contrib_${OTEL_VERSION}_linux_${ARCH}.tar.gz; then
        echo "❌ 错误: 下载失败"
        exit 1
    fi
    
    tar -xzf otelcol-contrib_${OTEL_VERSION}_linux_${ARCH}.tar.gz
    mv otelcol-contrib /usr/local/bin/otelcol-contrib
    chmod +x /usr/local/bin/otelcol-contrib
    rm -f otelcol-contrib_${OTEL_VERSION}_linux_${ARCH}.tar.gz README.md LICENSE
    echo "✅ OTel Collector v${OTEL_VERSION} 安装成功"
else
    echo "OTel Collector 已存在，跳过下载。"
fi

# 2. 准备配置文件
echo "配置 Config 文件..."
mkdir -p /etc/otelcol-contrib/config

# 复制主配置文件
if [ ! -f "otel-collector-config.yaml" ]; then
    echo "❌ 错误: 当前目录下未找到 otel-collector-config.yaml 文件"
    exit 1
fi
cp otel-collector-config.yaml /etc/otelcol-contrib/config/config.yaml
echo "✅ 已复制主配置文件"

# 复制可选的扩展配置文件（PostgreSQL、Redis等）
if [ "$CONFIG_FILES" = "auto" ]; then
    # 自动检测所有 otel-collector-*-config.yaml 文件（除了主config）
    for config_file in otel-collector-*-config.yaml; do
        if [ -f "$config_file" ] && [ "$config_file" != "otel-collector-config.yaml" ]; then
            cp "$config_file" /etc/otelcol-contrib/config/
            echo "✅ 已复制 $config_file"
        fi
    done
else
    # 根据用户指定的文件名复制
    IFS=',' read -ra FILES <<< "$CONFIG_FILES"
    for config_file in "${FILES[@]}"; do
        config_file=$(echo "$config_file" | xargs)  # 移除前后空格
        if [ -f "$config_file" ]; then
            cp "$config_file" /etc/otelcol-contrib/config/
            echo "✅ 已复制 $config_file"
        else
            echo "⚠️  警告: 文件不存在 - $config_file"
        fi
    done
fi

# 3. 创建 Systemd 服务文件
# 注意：这里我们将安装时的环境变量“固化”到 service 文件中
echo "创建 Systemd 服务..."
cat <<EOF > /etc/systemd/system/otelcol-contrib.service
[Unit]
Description=OpenTelemetry Collector Contrib
After=network.target docker.service
Requires=docker.service

[Service]
User=root
Group=root
# 确保可以访问Docker Socket
SupplementaryGroups=docker
# 将安装时传入的变量写入服务配置
Environment="SIGNOZ_ENDPOINT=${SIGNOZ_ENDPOINT}"
ExecStart=/usr/local/bin/otelcol-contrib --config=/etc/otelcol-contrib/config/
Restart=always
RestartSec=5s
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# 检查service文件是否创建成功
if [ ! -f "/etc/systemd/system/otelcol-contrib.service" ]; then
    echo "❌ 错误: Systemd 服务文件创建失败"
    exit 1
fi

# 4. 启动服务
echo "启动服务..."
systemctl daemon-reload
systemctl enable otelcol-contrib
if systemctl restart otelcol-contrib; then
    echo "✅ 服务启动成功"
else
    echo "❌ 服务启动失败，请检查日志: journalctl -u otelcol-contrib -n 50"
    exit 1
fi

echo ""
echo "=========================================="
echo "✅ 安装完成!"
echo "=========================================="
echo "主配置文件: /etc/otelcol-contrib/config/config.yaml"
echo "扩展配置: /etc/otelcol-contrib/config/"
echo ""
echo "常用命令:"
echo "  查看状态: systemctl status otelcol-contrib"
echo "  查看日志: journalctl -u otelcol-contrib -f"
echo "  重启服务: systemctl restart otelcol-contrib"
echo "=========================================="