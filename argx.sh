#!/bin/bash
set -e

ARGO_DOMAIN="${ARGO_DOMAIN:-}"
ARGO_AUTH="${ARGO_AUTH:-}"
PORT="${PORT:-8080}"
UUID="${UUID:-}"
BASE="${HOME}/vless-argo"

[ "$(id -u)" -eq 0 ] || exit 1

case "$(uname -m)" in
  x86_64|amd64) CPU=amd64 ;;
  aarch64|arm64) CPU=arm64 ;;
  *) exit 1 ;;
esac

command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 || exit 1
mkdir -p "$BASE"

[ -n "$UUID" ] || UUID=$(cat /proc/sys/kernel/random/uuid)

if [ ! -x "$BASE/xray" ]; then
  URL="https://github.com/yonggekkk/argosbx/releases/download/argosbx/xray-${CPU}"
  if command -v curl >/dev/null 2>&1; then curl -fsSL --retry 3 -o "$BASE/xray" "$URL"; else wget -qO "$BASE/xray" "$URL"; fi
  chmod +x "$BASE/xray"
fi

cat > "$BASE/xray.json" <<JSON
{
  "log": {"loglevel": "none"},
  "inbounds": [{
    "listen": "127.0.0.1",
    "port": ${PORT},
    "protocol": "vless",
    "settings": {
      "clients": [{"id": "${UUID}"}],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "ws",
      "security": "none",
      "wsSettings": {"path": "/${UUID}"}
    }
  }],
  "outbounds": [{"protocol": "freedom"}]
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
  systemctl daemon-reload >/dev/null 2>&1
  systemctl enable --now vless-argo-xray.service >/dev/null 2>&1
else
  pkill -f "${BASE}/xray run -c ${BASE}/xray.json" 2>/dev/null || true
  nohup "$BASE/xray" run -c "$BASE/xray.json" >/dev/null 2>&1 &
fi

if [ ! -x "$BASE/cloudflared" ]; then
  URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${CPU}"
  if command -v curl >/dev/null 2>&1; then curl -fsSL --retry 3 -o "$BASE/cloudflared" "$URL"; else wget -qO "$BASE/cloudflared" "$URL"; fi
  chmod +x "$BASE/cloudflared"
fi

if [ -n "$ARGO_AUTH" ] && [ -n "$ARGO_DOMAIN" ]; then
  if command -v systemctl >/dev/null 2>&1 && [ "$(ps -p 1 -o comm= 2>/dev/null)" = systemd ]; then
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
    systemctl enable --now vless-argo.service >/dev/null 2>&1
  else
    pkill -f "${BASE}/cloudflared tunnel" 2>/dev/null || true
    nohup "$BASE/cloudflared" tunnel --no-autoupdate --edge-ip-version auto --protocol http2 run --token "$ARGO_AUTH" >/dev/null 2>&1 &
  fi
  DOMAIN="$ARGO_DOMAIN"
else
  "$BASE/cloudflared" tunnel --url "http://127.0.0.1:${PORT}" --no-autoupdate --edge-ip-version auto --protocol http2 >"$BASE/argo.log" 2>&1 &
  DOMAIN=""
  for _ in $(seq 1 30); do
    DOMAIN=$(grep -oE 'https://[-a-zA-Z0-9]+\.trycloudflare\.com' "$BASE/argo.log" 2>/dev/null | head -n1 | sed 's#https://##')
    [ -n "$DOMAIN" ] && break
    sleep 1
  done
  [ -n "$DOMAIN" ] || exit 1
fi

printf 'vless://%s@%s:443?encryption=none&security=tls&type=ws&host=%s&sni=%s&path=%%2F%s#vless-ws-tls-argo\n' \
  "$UUID" "$DOMAIN" "$DOMAIN" "$DOMAIN" "$UUID"
