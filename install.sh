#!/bin/bash

[ "$#" -lt 5 ] && exit 1

UUID="$1"
ARGO_TOKEN="$2"
PORT="$3"
ARGO_DOMAIN="$4"
WSPATH="$5"
WORKDIR="$HOME/argox"

mkdir -p "$WORKDIR" && cd "$WORKDIR"

# --- 静默安装 ---
apt-get update -y >/dev/null 2>&1
apt-get install -y unzip curl wget >/dev/null 2>&1
arch=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')

# 下载 Xray
v_ver=$(curl -Ls -o /dev/null -w %{url_effective} https://github.com/XTLS/Xray-core/releases/latest | awk -F '/' '{print $NF}')
curl -L -s -o xray.zip "https://github.com/XTLS/Xray-core/releases/download/${v_ver}/Xray-linux-64.zip" >/dev/null 2>&1
unzip -qo xray.zip xray && chmod +x xray && rm -f xray.zip

cat <<EOF > config.json
{
    "inbounds": [{
        "port": $PORT,
        "protocol": "vless",
        "settings": {"clients": [{"id": "$UUID"}], "decryption": "none"},
        "streamSettings": {"network": "ws", "wsSettings": {"path": "$WSPATH"}}
    }],
    "outbounds": [{"protocol": "freedom"}]
}
EOF

# 下载 Cloudflared 并启动
curl -L -s -o cloudflared "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$arch" >/dev/null 2>&1
chmod +x cloudflared

# --- 写入 Systemd 守护 ---
cat <<EOF > /etc/systemd/system/xray-argo.service
[Unit]
Description=Xray Service
After=network.target
[Service]
ExecStart=$WORKDIR/xray -c $WORKDIR/config.json
Restart=always
[Install]
WantedBy=multi-user.target
EOF

cat <<EOF > /etc/systemd/system/cf-tunnel.service
[Unit]
Description=Argo Tunnel
After=network.target
[Service]
ExecStart=$WORKDIR/cloudflared tunnel --no-autoupdate run --token $ARGO_TOKEN
Restart=always
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload >/dev/null 2>&1
systemctl enable xray-argo cf-tunnel >/dev/null 2>&1
systemctl start xray-argo cf-tunnel >/dev/null 2>&1

echo "vless://${UUID}@${ARGO_DOMAIN}:443?encryption=none&security=tls&sni=${ARGO_DOMAIN}&type=ws&host=${ARGO_DOMAIN}&path=${WSPATH}#Linode_Argo"
