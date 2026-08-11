#!/bin/bash
set -e

[ "$#" -eq 5 ] || exit 1

UUID="$1"
WS_PATH="$2"
PORT="$3"
ARGO_DOMAIN="$4"
ARGO_AUTH="$5"
BASE="${HOME}/vless-argo"

[ "$(id -u)" -eq 0 ] || exit 1
[ -n "$UUID" ] && [ -n "$WS_PATH" ] && [ -n "$PORT" ] && [ -n "$ARGO_DOMAIN" ] && [ -n "$ARGO_AUTH" ] || exit 1

case "$PORT" in
  ''|*[!0-9]*) exit 1 ;;
esac

case "$(uname -m)" in
  x86_64|amd64) CPU=amd64 ;;
  aarch64|arm64) CPU=arm64 ;;
  *) exit 1 ;;
esac

command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 || exit 1
mkdir -p "$BASE"

if [ ! -x "$BASE/xray" ]; then
  URL="https://github.com/yonggekkk/argosbx/releases/download/argosbx/xray-${CPU}"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --retry 3 -o "$BASE/xray" "$URL"
  else
    wget -qO "$BASE/xray" "$URL"
  fi
  chmod +x "$BASE/xray"
fi

if [ ! -x "$BASE/cloudflared" ]; then
  URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${CPU}"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --retry 3 -o "$BASE/cloudflared" "$URL"
  else
    wget -qO "$BASE/cloudflared" "$URL"
  fi
  chmod +x "$BASE/cloudflared"
fi

cat > "$BASE/xray.json" <<JSON
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
JSON

if command -v systemctl >/dev/null 2>&1 && [ "$(ps -p 1 -o comm= 2>/dev/null)" = systemd ]; then
  cat > /etc/systemd/system/vless-argo-xray.service <<UNIT
[Unit]
After=network.target

[Service]
Type=simple
ExecStart=${BASE}/xray run -c ${BASE}/xray.json
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
UNIT

  cat > /etc/systemd/system/vless-argo.service <<UNIT
[Unit]
After=network.target vless-argo-xray.service
Requires=vless-argo-xray.service

[Service]
Type=simple
ExecStart=${BASE}/cloudflared tunnel --no-autoupdate --edge-ip-version auto --protocol http2 run --token ${ARGO_AUTH}
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
UNIT

  systemctl daemon-reload >/dev/null 2>&1
  systemctl enable --now vless-argo-xray.service >/dev/null 2>&1
  systemctl enable --now vless-argo.service >/dev/null 2>&1
else
  pkill -f "${BASE}/xray run -c ${BASE}/xray.json" 2>/dev/null || true
  pkill -f "${BASE}/cloudflared tunnel" 2>/dev/null || true
  nohup "$BASE/xray" run -c "$BASE/xray.json" >/dev/null 2>&1 &
  nohup "$BASE/cloudflared" tunnel --no-autoupdate --edge-ip-version auto --protocol http2 run --token "$ARGO_AUTH" >/dev/null 2>&1 &
fi

ENCODED_PATH=$(printf '%s' "$WS_PATH" | sed 's#^/##; s#/#%2F#g')

printf 'vless://%s@%s:443?encryption=none&security=tls&type=ws&host=%s&sni=%s&path=/%s#vless-ws-tls-argo\n' \
  "$UUID" "$ARGO_DOMAIN" "$ARGO_DOMAIN" "$ARGO_DOMAIN" "$ENCODED_PATH"
