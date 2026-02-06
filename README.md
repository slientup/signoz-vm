# 部署命令

```bash

1. download
`git clone -b main https://github.com/slientup/signoz-vm.git && cd signoz-vm/ && chmod +x install.sh`

2. Run the install.sh script

chmod +x install.sh
./install.sh -e "192.168.1.100:4317"

sudo ./install.sh -e "192.168.1.100:4317" -c "otel-collector-postgres-config.yaml"


```




