# 部署命令

1. download
git clone -b main git@github.com:slientup/signoz-vm.git && cd signoz-vm/

2. Run the install.sh script

./install.sh -e "192.168.1.100:4317"

```bash
# 安装并启动 Collector（自动检测并复制所有 otel-collector-*-config.yaml）
sudo ./install.sh -e "192.168.1.100:4317"

# 指定要复制的配置文件（逗号分隔）
sudo ./install.sh -e "192.168.1.100:4317" -c "otel-collector-postgres-config.yaml"
sudo ./install.sh -e "192.168.1.100:4317" -c "otel-collector-postgres-config.yaml,otel-collector-redis-config.yaml"

# 查看 systemd 状态 / 日志
systemctl status otelcol-contrib
journalctl -u otelcol-contrib -f
```




