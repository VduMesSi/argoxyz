#!/bin/bash

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Check Root Privileges
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Error: This script must be run as root!${NC}"
   exit 1
fi

echo -e "${GREEN}Starting Installation: Sing-box (VLESS-XHTTP-REALITY) - v1.12.0+ Standard${NC}"

# 1. Install Dependencies
echo -e "${YELLOW}Installing dependencies...${NC}"
apt update && apt install -y curl tar wget jq openssl

# 2. Determine Architecture and Download Sing-box
ARCH=$(uname -m)
case $ARCH in
    x86_64) BIN_ARCH="linux-amd64" ;;
    aarch64) BIN_ARCH="linux-arm64" ;;
    *) echo -e "${RED}Error: Unsupported architecture: $ARCH${NC}"; exit 1 ;;
esac

TAG=$(curl -s "https://api.github.com/repos/SagerNet/sing-box/releases/latest" | jq -r .tag_name)
VERSION=${TAG#v}
echo -e "${YELLOW}Downloading Sing-box ${TAG} for ${BIN_ARCH}...${NC}"

wget "https://github.com/SagerNet/sing-box/releases/download/${TAG}/sing-box-${VERSION}-${BIN_ARCH}.tar.gz" -O sing-box.tar.gz

tar -zxvf sing-box.tar.gz
cp "sing-box-${VERSION}-${BIN_ARCH}/sing-box" /usr/local/bin/
chmod +x /usr/local/bin/sing-box
rm -rf sing-box.tar.gz "sing-box-${VERSION}-${BIN_ARCH}"

# 3. Generate Random Credentials
echo -e "${YELLOW}Generating unique security credentials...${NC}"
UUID=$(sing-box generate uuid)
KEYS=$(sing-box generate reality-keypair)
PRIV_KEY=$(echo "$KEYS" | grep "Private key" | awk '{print $3}')
PUB_KEY=$(echo "$KEYS" | grep "Public key" | awk '{print $3}')
SHORT_ID=$(openssl rand -hex 8)
RANDOM_PATH="/$(openssl rand -hex 6)"

# 4. Create Sing-box Configuration (Migrated to 1.12.0 DNS and 1.11.0 Rule-Actions)
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
    ],
    "strategy": "prefer_ipv4"
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
          "short_id": ["$SHORT_ID"]
        }
      },
      "transport": {
        "type": "http",
        "host": ["www.microsoft.com"],
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

# 5. Setup Systemd Service
echo -e "${YELLOW}Configuring systemd service...${NC}"
cat <<EOF > /etc/systemd/system/sing-box.service
[Unit]
Description=Sing-box Service
After=network.target nss-lookup.target

[Service]
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
Restart=on-failure
RestartSec=10
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF

# 6. Enable and Start Service
systemctl daemon-reload
systemctl enable sing-box
systemctl restart sing-box

# 7. Generate v2rayN Link
IP=$(curl -s ifconfig.me)
ENCODED_PATH=$(echo $RANDOM_PATH | sed 's/\//%2F/g')
REMARK="VLESS_XHTTP_REALITY"
VLESS_LINK="vless://$UUID@$IP:443?encryption=none&security=reality&sni=www.microsoft.com&fp=chrome&pbk=$PUB_KEY&sid=$SHORT_ID&type=http&host=www.microsoft.com&path=$ENCODED_PATH#$REMARK"

# Output Results
clear
echo -e "${GREEN}Deployment Successful!${NC}"
echo -e "${YELLOW}------------------------------------------------------------${NC}"
echo -e "Server IP      : ${CYAN}$IP${NC}"
echo -e "Port           : ${CYAN}443${NC}"
echo -e "UUID           : ${CYAN}$UUID${NC}"
echo -e "Path           : ${CYAN}$RANDOM_PATH${NC}"
echo -e "Reality PubKey : ${CYAN}$PUB_KEY${NC}"
echo -e "Short ID       : ${CYAN}$SHORT_ID${NC}"
echo -e "${YELLOW}------------------------------------------------------------${NC}"
echo -e "${GREEN}VLESS Link for v2rayN / Sing-box Core:${NC}"
echo -e "${CYAN}$VLESS_LINK${NC}"
echo -e "${YELLOW}------------------------------------------------------------${NC}"
echo -e "Service Status : $(systemctl is-active sing-box)"
