#!/bin/bash
set -e

[ "$#" -eq 5 ] || exit 1
[ "$(id -u)" -eq 0 ] || exit 1

UUID="$1"
WS_PATH="$2"
PORT="$3"
ARGO_DOMAIN="$4"
ARGO_AUTH="$5"

BASE="/opt/vless-argo"

case "$(uname -m)" in
    x86_64|amd64)
        CPU="amd64"
        XRAY_ARCH="64"
        ;;
    aarch64|arm64)
        CPU="arm64"
        XRAY_ARCH="arm64-v8a"
        ;;
    *) exit 1 ;;
esac

command -v systemctl >/dev/null 2>&1 || exit 1
command -v unzip >/dev/null 2>&1 || exit 1

if command -v curl >/dev/null 2>&1; then
    DOWNLOAD="curl"
elif command -v wget >/dev/null 2>&1; then
    DOWNLOAD="wget"
else
    exit 1
fi

mkdir -p "$BASE"
chmod 700 "$BASE"

# Xray
if [ ! -x "$BASE/xray" ]; then
    TMP="$(mktemp)"
    trap 'rm -f "$TMP"' EXIT

    URL="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${XRAY_ARCH}.zip"

    if [ "$DOWNLOAD" = "curl" ]; then
        curl -fL --retry 3 -o "$TMP" "$URL"
    else
        wget -qO "$TMP" "$URL"
    fi

    unzip -p "$TMP" xray > "$BASE/xray"
    chmod 755 "$BASE/xray"

    rm -f "$TMP"
    trap - EXIT
fi

# Cloudflared
if [ ! -x "$BASE/cloudflared" ]; then
    URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${CPU}"

    if [ "$DOWNLOAD" = "curl" ]; then
        curl -fL --retry 3 -o "$BASE/cloudflared" "$URL"
    else
        wget -qO "$BASE/cloudflared" "$URL"
    fi

    chmod 755 "$BASE/cloudflared"
fi

# Xray config
cat > "$BASE/xray.json" <<EOF
{
  "log": {
    "loglevel": "none"
  },
  "inbounds": [
    {
      "listen": "127.0.0.1",
      "port": ${PORT},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${UUID}"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
          "path": "${WS_PATH}"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom"
    }
  ]
}
EOF

chmod 600 "$BASE/xray.json"

# Cloudflare Tunnel token
printf 'TUNNEL_TOKEN=%s\n' "$ARGO_AUTH" > "$BASE/cloudflared.env"
chmod 600 "$BASE/cloudflared.env"

# Xray service
cat > /etc/systemd/system/vless-argo-xray.service <<EOF
[Unit]
Description=VLESS Xray
Wants=network-online.target
After=network-online.target

[Service]
ExecStart=$BASE/xray run -c $BASE/xray.json
Restart=always
RestartSec=3
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$BASE

[Install]
WantedBy=multi-user.target
EOF

# Cloudflared service
cat > /etc/systemd/system/vless-argo.service <<EOF
[Unit]
Description=Cloudflare Tunnel
Requires=vless-argo-xray.service
After=vless-argo-xray.service network-online.target

[Service]
EnvironmentFile=$BASE/cloudflared.env
ExecStart=$BASE/cloudflared tunnel --no-autoupdate --edge-ip-version auto --protocol http2 run --token \${TUNNEL_TOKEN}
Restart=always
RestartSec=3
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$BASE

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now vless-argo-xray.service
systemctl enable --now vless-argo.service

# VLESS URI
PATH_ENCODED=$(printf '%s' "$WS_PATH" | sed 's#/#%2F#g')

printf '\nvless://%s@%s:443?encryption=none&security=tls&type=ws&host=%s&sni=%s&path=%s#vless-ws-tls-argo\n'
