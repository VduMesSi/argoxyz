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

echo -e "${GREEN}Starting Installation: Sing-box (VLESS + REALITY TCP) - Latest Version${NC}"

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
PRIV_KEY=$(echo "$KEYS" | grep -oP 'PrivateKey:\s*\K\S+')
PUB_KEY=$(echo "$KEYS" | grep -oP 'PublicKey:\s*\K\S+')
SHORT_ID=$(openssl rand -hex 8)
RANDOM_PATH="/$(openssl rand -hex 6)"   # 保留路径变量（虽然纯TCP不用，但留作记录）

if [[ -z "$PRIV_KEY" || -z "$PUB_KEY" ]]; then
    echo -e "${RED}Error: Failed to generate Reality keypair${NC}"
    exit 1
fi

# 4. Create Sing-box Configuration (VLESS + TCP + REALITY)
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
        "tag": "dns-remote",
        "address": "tls://8.8.8.8",
        "detour": "direct"
      }
    ],
    "strategy": "ipv4_only"
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
  ],
  "route": {
    "rules": [
      {
        "action": "sniff"
      },
      {
        "protocol": "dns",
        "action": "hijack-dns"
      }
    ]
  }
}
EOF

# 5. Setup Systemd Service
echo -e "${YELLOW}Configuring systemd service...${NC}"
cat <<EOF > /etc/systemd/system/sing-box.service
[Unit]
Description=Sing-box Service (VLESS + REALITY)
After=network.target nss-lookup.target

[Service]
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
Restart=on-failure
RestartSec=10
LimitNOFILE=infinity
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF

# 6. Enable and Start Service
systemctl daemon-reload
systemctl enable sing-box
systemctl restart sing-box

# 7. Check Configuration and Service
echo -e "${YELLOW}Checking configuration...${NC}"
if /usr/local/bin/sing-box check -c /etc/sing-box/config.json; then
    echo -e "${GREEN}Configuration check passed!${NC}"
else
    echo -e "${RED}Configuration check failed! Please check the config file.${NC}"
    exit 1
fi

# 8. Generate v2rayN / Nekobox / v2rayNG Compatible Link
IP=$(curl -s ifconfig.me)
REMARK="VLESS_REALITY_TCP"

VLESS_LINK="vless://$UUID@$IP:443?encryption=none&security=reality&sni=www.microsoft.com&fp=chrome&pbk=$PUB_KEY&sid=$SHORT_ID&type=tcp#$REMARK"

# Output Results
clear
echo -e "${GREEN}Deployment Successful!${NC}"
echo -e "${YELLOW}------------------------------------------------------------${NC}"
echo -e "Server IP          : ${CYAN}$IP${NC}"
echo -e "Port               : ${CYAN}443${NC}"
echo -e "UUID               : ${CYAN}$UUID${NC}"
echo -e "Reality PrivateKey : ${CYAN}$PRIV_KEY${NC}"
echo -e "Reality PublicKey  : ${CYAN}$PUB_KEY${NC}"
echo -e "Short ID           : ${CYAN}$SHORT_ID${NC}"
echo -e "${YELLOW}------------------------------------------------------------${NC}"
echo -e "${GREEN}Copy and import the link below into v2rayN / Nekobox / Shadowrocket:${NC}"
echo -e "${CYAN}$VLESS_LINK${NC}"
echo -e "${YELLOW}------------------------------------------------------------${NC}"
echo -e "Service Status     : $(systemctl is-active sing-box)"
echo -e ""
echo -e "Useful commands:"
echo -e "  Check logs     : journalctl -u sing-box -f"
echo -e "  Check config   : /usr/local/bin/sing-box check -c /etc/sing-box/config.json"
echo -e "  Restart        : systemctl restart sing-box"
echo -e "${YELLOW}------------------------------------------------------------${NC}"

# Final check
sleep 2
if systemctl is-active --quiet sing-box; then
    echo -e "${GREEN}Sing-box is running successfully!${NC}"
else
    echo -e "${RED}Warning: Service may not be running properly. Check logs with: journalctl -u sing-box -xe${NC}"
fi
