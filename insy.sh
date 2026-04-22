#!/usr/bin/env bash
set -euo pipefail

# VLESS + XHTTP + REALITY one-click installer for Debian/Ubuntu (Linode friendly)
# Usage:
#   bash install_vless_xhttp_reality.sh
# Optional env vars:
#   PORT=443 SNI=www.cloudflare.com PATH_XHTTP=/xhttp SPIDERX=/ SERVER_ADDR=<ip-or-domain> REMARK=linode-xhttp


export DEBIAN_FRONTEND=noninteractive

PORT="${PORT:-443}"
SNI="${SNI:-www.cloudflare.com}"
PATH_XHTTP="${PATH_XHTTP:-/$(openssl rand -hex 6)}"
SPIDERX="${SPIDERX:-/}"
REMARK="${REMARK:-linode-vless-xhttp-reality}"

command -v curl >/dev/null 2>&1 || (apt-get update -y && apt-get install -y curl)
apt-get update -y
apt-get install -y ca-certificates jq openssl unzip uuid-runtime

if ! command -v xray >/dev/null 2>&1; then
  bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
fi

UUID="$(xray uuid)"
X25519_OUT="$(xray x25519)"
PRIVATE_KEY="$(awk '/Private key:/ {print $3}' <<<"$X25519_OUT")"
PUBLIC_KEY="$(awk '/Public key:/ {print $3}' <<<"$X25519_OUT")"
SHORT_ID="$(openssl rand -hex 8)"

# Detect best server address for sharing link (prefer user-defined)
SERVER_ADDR="${SERVER_ADDR:-}"
if [[ -z "$SERVER_ADDR" ]]; then
  SERVER_ADDR="$(curl -4 -s --max-time 8 https://api.ipify.org || true)"
fi
if [[ -z "$SERVER_ADDR" ]]; then
  SERVER_ADDR="$(curl -s --max-time 8 https://ifconfig.me || true)"
fi
if [[ -z "$SERVER_ADDR" ]]; then
  echo "[ERR] Cannot detect public IP. Set SERVER_ADDR manually." >&2
  exit 1
fi

install -d -m 755 /usr/local/etc/xray

cat > /usr/local/etc/xray/config.json <<JSON
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": ${PORT},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${UUID}",
            "flow": ""
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "xhttp",
        "security": "reality",
        "xhttpSettings": {
          "path": "${PATH_XHTTP}"
        },
        "realitySettings": {
          "target": "${SNI}:443",
          "serverNames": [
            "${SNI}"
          ],
          "privateKey": "${PRIVATE_KEY}",
          "shortIds": [
            "${SHORT_ID}"
          ]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls",
          "quic"
        ]
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
  ]
}
JSON

xray run -test -c /usr/local/etc/xray/config.json
systemctl enable xray >/dev/null 2>&1 || true
systemctl restart xray

# firewall best effort
if command -v ufw >/dev/null 2>&1; then
  ufw allow "${PORT}/tcp" >/dev/null 2>&1 || true
fi

urlencode() {
  local s="$1" out="" c
  for ((i=0; i<${#s}; i++)); do
    c="${s:i:1}"
    case "$c" in
      [a-zA-Z0-9.~_-]) out+="$c" ;;
      *) printf -v out '%s%%%02X' "$out" "'${c}" ;;
    esac
  done
  printf '%s' "$out"
}

ENC_PATH="$(urlencode "$PATH_XHTTP")"
ENC_SPX="$(urlencode "$SPIDERX")"
ENC_REMARK="$(urlencode "$REMARK")"

V2RAYN_LINK="vless://${UUID}@${SERVER_ADDR}:${PORT}?encryption=none&security=reality&sni=${SNI}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&spx=${ENC_SPX}&type=xhttp&path=${ENC_PATH}&host=${SNI}#${ENC_REMARK}"

cat <<EOF

[OK] Installed VLESS + XHTTP + REALITY

Server Addr : ${SERVER_ADDR}
Port        : ${PORT}
UUID        : ${UUID}
SNI/Target  : ${SNI}
XHTTP Path  : ${PATH_XHTTP}
Public Key  : ${PUBLIC_KEY}
Short ID    : ${SHORT_ID}
SpiderX     : ${SPIDERX}

v2rayN link:
${V2RAYN_LINK}

EOF
