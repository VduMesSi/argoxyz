#!/bin/bash

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check Root Privileges
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Error: This script must be run as root!${NC}"
   exit 1
fi

echo -e "${GREEN}Starting Installation: Sing-box (VLESS-XHTTP-REALITY) - 2026 Edition${NC}"

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
RANDOM_PATH="/$(openssl rand -hex 4)-$(openssl rand -hex 2)"

# 4. Create Sing-box Configuration
mkdir -p /etc/sing-box
cat <<EOF > /etc/sing-box/config.json
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-in",
      "listen": "::",
      "listen_port": 443,
      "sniff": true,
      "users": [
        {
          "uuid": "$UUID",
          "flow": ""
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
    },
    {
      "type": "block",
      "tag": "block"
    }
  ]
}
EOF

# 5. Setup Systemd Service
echo -e "${YELLOW}Configuring systemd service...${NC}"
cat <<EOF > /etc/systemd/system/sing-box.service
[Unit]
Description=Sing-box Service
Documentation=https://sing-box.sagernet.org/
After=network.target nss-lookup.target

[Service]
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
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

# Output Installation Results
clear
echo -e "${GREEN}Installation Successful!${NC}"
echo -e "${YELLOW}----------------------------------------${NC}"
echo -e "Server Address : ${GREEN}$(curl -s ifconfig.me)${NC}"
echo -e "Port           : ${GREEN}443${NC}"
echo -e "UUID           : ${RED}$UUID${NC}"
echo -e "Protocol       : ${GREEN}VLESS${NC}"
echo -e "Transport      : ${GREEN}XHTTP (HTTP/1.1)${NC}"
echo -e "Path           : ${GREEN}$RANDOM_PATH${NC}"
echo -e "SNI/ServerName : ${GREEN}www.microsoft.com${NC}"
echo -e "Reality PubKey : ${RED}$PUB_KEY${NC}"
echo -e "Short ID       : ${RED}$SHORT_ID${NC}"
echo -e "${YELLOW}----------------------------------------${NC}"
echo -e "Keep your credentials private. Access your config at /etc/sing-box/config.json"
