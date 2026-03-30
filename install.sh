#!/bin/bash

[ "$#" -lt 4 ] && exit 1

UUID="$1"
ARGO_TOKEN="$2"
PORT="$3"
ARGO_DOMAIN="$4"

WORKDIR="$HOME/argox"
mkdir -p "$WORKDIR" && cd "$WORKDIR"

apt-get update -y >/dev/null 2>&1
apt-get install -y unzip curl wget >/dev/null 2>&1

arch=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')

v_ver=$(curl -Ls -o /dev/null -w %{url_effective} https://github.com/XTLS/Xray-core/releases/latest | awk -F '/' '{print $NF}')
curl -L -s -o xray.zip "https://github.com/XTLS/Xray-core/releases/download/${v_ver}/Xray-linux-64.zip" >/dev/null 2>&1

unzip -qo xray.zip xray && chmod +x xray && rm -f xray.zip

cat <<EOF > config.json
{
    "inbounds": [{
        "port": $PORT,
        "protocol": "vless",
        "settings": {
            "clients": [{"id": "$UUID"}],
            "decryption": "none"
        },
        "streamSettings": {
            "network": "ws",
            "wsSettings": {"path": "/vless-ws"}
        }
    }],
    "outbounds": [{"protocol": "freedom"}]
}
EOF

nohup ./xray -c config.json >/dev/null 2>&1 &

curl -L -s -o cloudflared "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$arch" >/dev/null 2>&1
chmod +x cloudflared
nohup ./cloudflared tunnel --no-autoupdate run --token "$ARGO_TOKEN" >/dev/null 2>&1 &

exit 0
