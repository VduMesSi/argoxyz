#!/usr/bin/env bash

set -e

# ===== basic params =====
PORT=8443
UUID=$(cat /proc/sys/kernel/random/uuid)

SNI="www.cloudflare.com"
DEST="$SNI"

SHORT_ID_COUNT=5

echo "UUID: $UUID"

# ===== install deps =====
apt update -y
apt install -y curl wget unzip openssl jq

# ===== install sing-box =====
VERSION=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | grep tag_name | cut -d '"' -f4)

wget -O sing-box.tar.gz https://github.com/SagerNet/sing-box/releases/download/${VERSION}/sing-box-${VERSION#v}-linux-amd64.tar.gz

tar -xzf sing-box.tar.gz
cp sing-box-*/sing-box /usr/local/bin/
chmod +x /usr/local/bin/sing-box

# ===== generate reality keypair =====
KEY_JSON=$(sing-box generate reality-keypair --json)
PRIVATE_KEY=$(echo $KEY_JSON | jq -r .private_key)
PUBLIC_KEY=$(echo $KEY_JSON | jq -r .public_key)

echo "Public Key: $PUBLIC_KEY"

# ===== generate multiple short_ids =====
SHORT_IDS=()

for ((i=0; i<$SHORT_ID_COUNT; i++)); do
    SID=$(openssl rand -hex 8)
    SHORT_IDS+=("\"$SID\"")
done

SHORT_IDS_JSON=$(IFS=,; echo "[${SHORT_IDS[*]}]")

# pick random sid for output
RANDOM_SID=$(echo ${SHORT_IDS[@]} | tr ' ' '\n' | shuf -n 1 | tr -d '"')

echo "Short IDs: $SHORT_IDS_JSON"
echo "Selected SID: $RANDOM_SID"

# ===== write config =====
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
          "short_id": $SHORT_IDS_JSON
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

# ===== systemd service =====
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

# ===== start service =====
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable sing-box
systemctl restart sing-box

# ===== get public ip =====
IP=$(curl -s ifconfig.me)

# ===== generate v2rayN link =====
VLESS_LINK="vless://$UUID@$IP:$PORT?encryption=none&security=reality&type=tcp&sni=$SNI&fp=chrome&pbk=$PUBLIC_KEY&sid=$RANDOM_SID&flow=xtls-rprx-vision#sb-reality"

echo ""
echo "===================================="
echo " Installation completed"
echo "===================================="
echo ""
echo "$VLESS_LINK"
echo ""
echo "===================================="
