#!/usr/bin/env bash
set -e

PORT=5225
UUID=$(cat /proc/sys/kernel/random/uuid)
SNI="www.microsoft.com"
DEST="$SNI"

echo "[INFO] UUID: $UUID"

apt update -y
apt install -y curl wget unzip openssl jq

VERSION=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | grep tag_name | cut -d '"' -f4)

wget -O sb.tar.gz \
https://github.com/SagerNet/sing-box/releases/download/${VERSION}/sing-box-${VERSION#v}-linux-amd64.tar.gz

tar -xzf sb.tar.gz
cp sing-box-*/sing-box /usr/local/bin/
chmod +x /usr/local/bin/sing-box

# ======================
# generate keypair (STRICT)
# ======================
KEY_OUTPUT=$(sing-box generate reality-keypair)

PRIVATE_KEY=$(echo "$KEY_OUTPUT" | awk -F': ' '/PrivateKey/ {print $2}' | tr -d '\r\n ')
PUBLIC_KEY=$(echo "$KEY_OUTPUT" | awk -F': ' '/PublicKey/ {print $2}' | tr -d '\r\n ')

# ===== sanity check =====
if [[ -z "$PRIVATE_KEY" || -z "$PUBLIC_KEY" ]]; then
  echo "[ERROR] key generation failed"
  exit 1
fi

echo "[INFO] key OK"
SHORT_ID=$(openssl rand -hex 8)

if ! [[ "$SHORT_ID" =~ ^[0-9a-f]+$ ]]; then
  echo "[ERROR] invalid short_id"
  exit 1
fi

echo "[INFO] short_id=$SHORT_ID"
IP=$(curl -4 -s https://api.ipify.org)

echo "[INFO] IPv4=$IP"

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
      "listen": "0.0.0.0",
      "listen_port": $PORT,

      "users": [
        {
          "uuid": "$UUID",
          "flow": "xtls-rprx-vision"
        }
      ],

      "tls": {
        "enabled": true,
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

jq empty /etc/sing-box/config.json

cat > /etc/systemd/system/sing-box.service <<EOF
[Unit]
Description=sing-box
After=network.target

[Service]
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
Restart=always
LimitNOFILE=51200

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable sing-box
systemctl restart sing-box

VLESS_LINK="vless://${UUID}@${IP}:${PORT}?encryption=none&security=reality&type=tcp&flow=xtls-rprx-vision&sni=${SNI}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}#sing-box"

echo ""
echo "============================"
echo " INSTALL SUCCESS"
echo "============================"
echo ""
echo "$VLESS_LINK"
echo ""
echo "============================"
