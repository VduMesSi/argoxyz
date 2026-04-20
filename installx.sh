#!/bin/bash
# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${GREEN}Sing-box VLESS + REALITY (TCP) 覆盖安装脚本 - DNS 已修复${NC}"
echo -e "${YELLOW}本脚本将覆盖旧配置，继续吗？(y/n)${NC}"
read -r confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo -e "${RED}已取消${NC}"
    exit 0
fi

# Check Root Privileges
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Error: This script must be run as root!${NC}"
   exit 1
fi

echo -e "${GREEN}开始覆盖安装 Sing-box (VLESS + REALITY TCP)...${NC}"

# 停止旧服务
systemctl stop sing-box 2>/dev/null
systemctl disable sing-box 2>/dev/null

# 1. Install Dependencies
echo -e "${YELLOW}安装依赖...${NC}"
apt update && apt install -y curl tar wget jq openssl

# 2. Download Latest Sing-box
ARCH=$(uname -m)
case $ARCH in
    x86_64) BIN_ARCH="linux-amd64" ;;
    aarch64) BIN_ARCH="linux-arm64" ;;
    *) echo -e "${RED}Error: Unsupported architecture: $ARCH${NC}"; exit 1 ;;
esac

TAG=$(curl -s "https://api.github.com/repos/SagerNet/sing-box/releases/latest" | jq -r .tag_name)
VERSION=${TAG#v}
echo -e "${YELLOW}下载 Sing-box ${TAG} (${BIN_ARCH})...${NC}"
wget "https://github.com/SagerNet/sing-box/releases/download/${TAG}/sing-box-${VERSION}-${BIN_ARCH}.tar.gz" -O sing-box.tar.gz

tar -zxvf sing-box.tar.gz
cp "sing-box-${VERSION}-${BIN_ARCH}/sing-box" /usr/local/bin/
chmod +x /usr/local/bin/sing-box
rm -rf sing-box.tar.gz "sing-box-${VERSION}-${BIN_ARCH}"

# 3. Generate Credentials
echo -e "${YELLOW}生成凭证...${NC}"
UUID=$(sing-box generate uuid)
KEYS=$(sing-box generate reality-keypair)
PRIV_KEY=$(echo "$KEYS" | grep -oP 'PrivateKey:\s*\K\S+')
PUB_KEY=$(echo "$KEYS" | grep -oP 'PublicKey:\s*\K\S+')
SHORT_ID=$(openssl rand -hex 8)

if [[ -z "$PRIV_KEY" || -z "$PUB_KEY" ]]; then
    echo -e "${RED}生成 Reality 密钥失败${NC}"
    exit 1
fi

# 4. Create Configuration - 使用官方新 DNS 格式（已彻底解决 deprecated 问题）
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
        "type": "tls",
        "server": "8.8.8.8"
      },
      {
        "tag": "dns-cloudflare",
        "type": "tls",
        "server": "1.1.1.1"
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

# 5. Systemd Service
echo -e "${YELLOW}配置 systemd 服务...${NC}"
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

# 6. Enable and Start
systemctl daemon-reload
systemctl enable sing-box
systemctl restart sing-box

# 7. Check Configuration
echo -e "${YELLOW}检查配置...${NC}"
if /usr/local/bin/sing-box check -c /etc/sing-box/config.json; then
    echo -e "${GREEN}配置检查通过！${NC}"
else
    echo -e "${RED}配置检查失败！${NC}"
    echo -e "请查看详细错误：journalctl -u sing-box -n 100"
    exit 1
fi

# 8. Generate Client Link
IP=$(curl -s ifconfig.me)
REMARK="VLESS_REALITY_TCP"
VLESS_LINK="vless://$UUID@$IP:443?encryption=none&security=reality&sni=www.microsoft.com&fp=chrome&pbk=$PUB_KEY&sid=$SHORT_ID&type=tcp#$REMARK"

# Final Output
clear
echo -e "${GREEN}覆盖安装成功！DNS deprecated 问题已解决${NC}"
echo -e "${YELLOW}------------------------------------------------------------${NC}"
echo -e "服务器 IP         : ${CYAN}$IP${NC}"
echo -e "端口              : ${CYAN}443${NC}"
echo -e "UUID              : ${CYAN}$UUID${NC}"
echo -e "Public Key        : ${CYAN}$PUB_KEY${NC}"
echo -e "Short ID          : ${CYAN}$SHORT_ID${NC}"
echo -e "${YELLOW}------------------------------------------------------------${NC}"
echo -e "${GREEN}客户端导入链接：${NC}"
echo -e "${CYAN}$VLESS_LINK${NC}"
echo -e "${YELLOW}------------------------------------------------------------${NC}"
echo -e "服务状态          : $(systemctl is-active sing-box)"
echo -e ""
echo -e "常用命令："
echo -e "  查看实时日志  : journalctl -u sing-box -f"
echo -e "  检查配置      : /usr/local/bin/sing-box check -c /etc/sing-box/config.json"
echo -e "  重启服务      : systemctl restart sing-box"
echo -e "${YELLOW}------------------------------------------------------------${NC}"

sleep 3
if systemctl is-active --quiet sing-box; then
    echo -e "${GREEN}Sing-box 服务已正常运行！${NC}"
else
    echo -e "${RED}服务启动可能异常，请查看日志：journalctl -u sing-box -xe${NC}"
fi
