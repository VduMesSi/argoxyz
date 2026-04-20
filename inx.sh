#!/usr/bin/env bash

set -e

# ===== 参数 =====
PORT=8443
UUID=$(cat /proc/sys/kernel/random/uuid)

SNI="www.cloudflare.com"
DEST="$SNI"

echo "UUID: $UUID"

# ===== 安装依赖 =====
apt update -y
apt install -y curl wget unzip openssl

# ===== 安装 sing-box =====
VERSION=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | grep tag_name | cut -d '"' -f4)

wget -O sing-box.tar.gz https://github.com/SagerNet/sing-box/releases/download/${VERSION}/sing-box-${VERSION#v}-linux-amd64.tar.gz

tar -xzf sing-box.tar.gz
cp sing-box-*/sing-box /usr/local/bin/
chmod +x /usr/local/bin/sing-box

# ===== 生成 Reality 密钥 =====
KEY_JSON=$(sing-box generate reality-keypair --json)
PRIVATE_KEY=$(echo $KEY_JSON | grep -oP '"private_key":"\K[^"]+')
PUBLIC_KEY=$(echo $KEY_JSON | grep -oP '"public_key":"\K[^"]+')

echo "Public Key: $PUBLIC_KEY"

# ===== short_id =====
SHORT_ID=$(openssl rand -hex 8)

# ===== 写配置 =====
mkdir -p /etc/sing-box

cat > /etc/sing-box/config.json <<EOF
{
  "log": {
    "level": "warn"
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-reality",
      "listen": "::",
      "listen_port": $PORT,
      "users": [
        {
          "uuid": "$UUID",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "$SNI",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "$DEST",
            "server_port": 443
          },
          "private_key": "$PRIVATE_KEY",
          "short_id": ["$SHORT_ID"]
        }
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct"
    }
  ]
}
EOF

# ===== systemd =====
cat > /etc/systemd/system/sing-box.service <<EOF
[Unit]
Description=sing-box service
After=network.target

[Service]
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
Restart=always
LimitNOFILE=51200

[Install]
WantedBy=multi-user.target
EOF

# ===== 启动 =====
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable sing-box
systemctl restart sing-box

# ===== 获取 IP =====
IP=$(curl -s ifconfig.me)

# ===== 输出 v2rayN 链接 =====
VLESS_LINK="vless://$UUID@$IP:$PORT?encryption=none&security=reality&type=tcp&sni=$SNI&fp=chrome&pbk=$PUBLIC_KEY&sid=$SHORT_ID&flow=xtls-rprx-vision#sb-reality"

echo ""
echo "===================================="
echo " 安装完成（sing-box Reality Vision）"
echo "===================================="
echo ""
echo "$VLESS_LINK"
echo ""
echo "===================================="
