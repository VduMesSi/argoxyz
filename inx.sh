#!/usr/bin/env bash

set -e

# ===== config =====
PORT=443
UUID=$(cat /proc/sys/kernel/random/uuid)

SNI="www.cloudflare.com"
DEST="$SNI"

SHORT_ID_COUNT=4

echo "[INFO] UUID: $UUID"

# ===== install deps =====
apt update -y
apt install -y curl wget unzip openssl

# ===== install sing-box =====
VERSION=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | grep tag_name | cut -d '"' -f4)

wget -O sing-box.tar.gz \
https://github.com/SagerNet/sing-box/releases/download/${VERSION}/sing-box-${VERSION#v}-linux-amd64.tar.gz

tar -xzf sing-box.tar.gz
cp sing-box-*/sing-box /usr/local/bin/
chmod +x /usr/local/bin/sing-box

# ===== generate reality keys =====
KEY_OUTPUT=$(sing-box generate reality-keypair)

PRIVATE_KEY=$(echo "$KEY_OUTPUT" | awk -F': ' '/PrivateKey/ {print $2}' | tr -d '\r\n ')
PUBLIC_KEY=$(echo "$KEY_OUTPUT" | awk -F': ' '/PublicKey/ {print $2}' | tr -d '\r\n ')

if [ -z "$PRIVATE_KEY" ] || [ -z "$PUBLIC_KEY" ]; then
  echo "[ERROR] key generation failed"
  exit 1
fi

echo "[INFO] Public Key OK"

# ===== generate valid short_ids (hex only) =====
SHORT_IDS=()

for ((i=0; i<$SHORT_ID_COUNT; i++)); do
    SID=$(openssl rand -hex 8)
    SHORT_IDS+=("\"$SID\"")
done

SHORT_IDS_JSON=$(IFS=,; echo "[${SHORT_IDS[*]}]")

RANDOM_SID=$(echo ${SHORT_IDS[@]} | tr ' ' '\n' | shuf -n 1 | tr -d '"')

echo "[INFO] short_id: $SHORT_IDS_JSON"

# ===== get ipv4 only =====
IP=$(curl -4 -s https://api.ipify.org)

echo "[INFO] IPv4: $IP"

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

systemctl daemon-reload
systemctl enable sing-box
systemctl restart sing-box

# ===== output link =====
VLESS_LINK="vless://$UUID@$IP:$PORT?encryption=none&security=reality&type=tcp&sni=$SNI&fp=chrome&pbk=$PUBLIC_KEY&sid=$RANDOM_SID&flow=xtls-rprx-vision#sing-box"

echo ""
echo "=============================="
echo " INSTALL DONE"
echo "=============================="
echo ""
echo "$VLESS_LINK"
echo ""
echo "=============================="
