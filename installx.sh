#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# 1. 环境准备与依赖安装
echo -e "${YELLOW}正在安装依赖并下载 Sing-box...${NC}"
apt update && apt install -y curl tar wget jq openssl

ARCH=$(uname -m)
case $ARCH in
    x86_64) BIN_ARCH="linux-amd64" ;;
    aarch64) BIN_ARCH="linux-arm64" ;;
    *) echo -e "${RED}架构不支持: $ARCH${NC}"; exit 1 ;;
esac

TAG=$(curl -s "https://api.github.com/repos/SagerNet/sing-box/releases/latest" | jq -r .tag_name)
VERSION=${TAG#v}
wget "https://github.com/SagerNet/sing-box/releases/download/${TAG}/sing-box-${VERSION}-${BIN_ARCH}.tar.gz" -O sing-box.tar.gz
tar -zxvf sing-box.tar.gz
cp "sing-box-${VERSION}-${BIN_ARCH}/sing-box" /usr/local/bin/
chmod +x /usr/local/bin/sing-box
rm -rf sing-box.tar.gz "sing-box-${VERSION}-${BIN_ARCH}"

# 2. 生成配置变量
UUID=$(sing-box generate uuid)
KEYS=$(sing-box generate reality-keypair)
PRIV_KEY=$(echo "$KEYS" | grep "Private key" | awk '{print $3}')
PUB_KEY=$(echo "$KEYS" | grep "Public key" | awk '{print $3}')
SHORT_ID=$(openssl rand -hex 8)
RANDOM_PATH="/$(openssl rand -hex 6)"

# 3. 写入 1.12.0+ 标准配置文件 (彻底修复 DNS 和 Rule-Actions)
mkdir -p /etc/sing-box
cat <<EOF > /etc/sing-box/config.json
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "dns": {
    "servers": [
      {
        "tag": "google",
        "address": "tls://8.8.8.8"
      },
      {
        "tag": "local",
        "address": "https://1.1.1.1/dns-query",
        "detour": "direct"
      }
    ]
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-in",
      "listen": "::",
      "listen_port": 443,
      "users": [
        {
          "uuid": "$UUID"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "www.microsoft.com",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "www.microsoft.com",
            "server_port": 443
          },
          "private_key": "$PRIV_KEY",
          "short_id": [
            "$SHORT_ID"
          ]
        }
      },
      "transport": {
        "type": "http",
        "host": [
          "www.microsoft.com"
        ],
        "path": "$RANDOM_PATH",
        "method": "POST"
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ],
  "route": {
    "rules": [
      {
        "protocol": "dns",
        "action": "hijack-dns"
      },
      {
        "inbound": "vless-in",
        "action": "sniff"
      }
    ]
  }
}
EOF

# 4. 设置 Systemd 服务
cat <<EOF > /etc/systemd/system/sing-box.service
[Unit]
Description=Sing-box Service
After=network.target nss-lookup.target

[Service]
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
Restart=on-failure
RestartSec=5
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF

# 5. 重启服务
systemctl daemon-reload
systemctl enable sing-box
systemctl restart sing-box

# 6. 生成正确的 v2rayN 链接
IP=$(curl -s ifconfig.me)
ENCODED_PATH=$(echo $RANDOM_PATH | sed 's/\//%2F/g')
REMARK="VLESS_XHTTP_REALITY"

# 修正链接格式：确保 v2rayN 导入后自动识别 sing-box 核心参数
VLESS_LINK="vless://$UUID@$IP:443?encryption=none&security=reality&sni=www.microsoft.com&fp=chrome&pbk=$PUB_KEY&sid=$SHORT_ID&type=http&headerType=none&host=www.microsoft.com&path=$ENCODED_PATH#$REMARK"

# 7. 输出结果
clear
echo -e "${GREEN}部署成功！${NC}"
echo -e "${YELLOW}------------------------------------------------------------${NC}"
echo -e "Server IP      : ${CYAN}$IP${NC}"
echo -e "Reality PubKey : ${CYAN}$PUB_KEY${NC}"
echo -e "${YELLOW}------------------------------------------------------------${NC}"
echo -e "${GREEN}v2rayN 导入链接 (请整行复制):${NC}"
echo -e "${CYAN}$VLESS_LINK${NC}"
echo -e "${YELLOW}------------------------------------------------------------${NC}"
echo -e "服务状态: $(systemctl is-active sing-box)"
echo -e "语法校验: /usr/local/bin/sing-box check -c /etc/sing-box/config.json"
