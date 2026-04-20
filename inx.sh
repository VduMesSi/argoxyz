#!/bin/bash
set -e

echo "=== 更新系统并安装必要工具 ==="
apt update -y && apt upgrade -y
apt install -y curl wget unzip qrencode openssl

echo "=== 安装 Xray 核心 ==="
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

# 生成必要参数
UUID=$(xray uuid)
KEYS=$(xray x25519)
PRIVATE_KEY=$(echo "$KEYS" | grep "Private key:" | awk '{print $3}')
PUBLIC_KEY=$(echo "$KEYS" | grep "Public key:" | awk '{print $3}')
SHORT_ID=$(openssl rand -hex 8)
SERVER_IP=$(curl -s4 https://ifconfig.me || curl -s4 https://ip.sb)
SNI="www.microsoft.com"          # 可改成其他支持 TLS 1.3 + H2 的域名，如 www.apple.com
PATH_XHTTP="/xhttp-$(openssl rand -hex 4)"   # 随机路径，增加隐蔽性
FP="chrome"

echo "=== 生成 Xray 配置 ==="
cat > /usr/local/etc/xray/config.json <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$UUID",
            "email": "user@vps",
            "level": 0
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "xhttp",
        "xhttpSettings": {
          "path": "$PATH_XHTTP"
        },
        "security": "reality",
        "realitySettings": {
          "dest": "$SNI:443",
          "serverNames": ["$SNI"],
          "privateKey": "$PRIVATE_KEY",
          "shortIds": ["", "$SHORT_ID"],
          "spiderX": ""
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "block"
    }
  ],
  "routing": {
    "rules": [
      {
        "ip": ["geoip:private"],
        "outboundTag": "block"
      }
    ]
  }
}
EOF

echo "=== 重启 Xray 服务 ==="
systemctl restart xray
systemctl enable xray

# 开放防火墙端口（Ubuntu 默认使用 ufw）
if command -v ufw >/dev/null 2>&1; then
  ufw allow 443/tcp
  ufw --force enable || true
else
  apt install -y ufw
  ufw allow 443/tcp
  ufw --force enable
fi

echo "=== 部署完成！ ==="
echo "服务器 IP: $SERVER_IP"
echo "UUID: $UUID"
echo "Public Key (pbk): $PUBLIC_KEY"
echo "Short ID (sid): $SHORT_ID"
echo "SNI: $SNI"
echo "XHTTP Path: $PATH_XHTTP"
echo "Fingerprint: $FP"

# 生成 v2rayN 客户端链接（vless 协议）
LINK="vless://${UUID}@${SERVER_IP}:443?encryption=none&security=reality&sni=${SNI}&fp=${FP}&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=xhttp&path=${PATH_XHTTP}&headerType=none#VLESS-XHTTP-REALITY"

echo -e "\n=== v2rayN 导入链接（直接复制到 v2rayN → 从剪贴板导入）==="
echo "$LINK"

# 生成二维码（方便手机扫码）
echo -e "\n=== 二维码（手机可直接扫描）==="
qrencode -t ansiutf8 "$LINK"

echo -e "\n安装完成！推荐客户端：v2rayN（Windows）、NekoBox / v2rayNG（Android）"
echo "如需修改配置，编辑 /usr/local/etc/xray/config.json 后重启 systemctl restart xray"
