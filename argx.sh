#!/bin/bash

export LANG=en_US.UTF-8
WORKDIR="/root/singbox"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

# apt update 
apt install curl coreutils util-linux sed jq -y >/dev/null 2>&1

LATEST_TAG=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | jq -r .tag_name)
VERSION=${LATEST_TAG#v}
DOWNLOAD_URL="https://github.com/SagerNet/sing-box/releases/download/${LATEST_TAG}/sing-box-${VERSION}-linux-${cpu}.tar.gz"

curl -Lo sing-box.tar.gz "$DOWNLOAD_URL"
tar -xzf sing-box.tar.gz --strip-components=1
chmod +x sing-box

v4=$(curl -4 -s --max-time 5 https://api.ipify.org || curl -4 -s --max-time 5 https://icanhazip.com)
if [ -z "$v4" ]; then
    echo "错误：无法获取公网 IPv4 地址"
    exit 1
fi

uuid=$(./sing-box generate uuid)
key_pair=$(./sing-box generate reality-keypair)
private_key=$(echo "$key_pair" | awk '/PrivateKey/ {print $2}' | tr -d '"')
public_key=$(echo "$key_pair" | awk '/PublicKey/ {print $2}' | tr -d '"')
short_id=$(./sing-box generate rand --hex 4)
sni="apple.com"
port=443

cat > config.json <<EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-xhttp-reality",
      "listen": "::",
      "listen_port": $port,
      "users": [
        {
          "uuid": "$uuid",
          "flow": ""
        }
      ],
      "transport": {
        "type": "xhttp",
        "path": "/$uuid-xh",
        "host": "$sni"
      },
      "tls": {
        "enabled": true,
        "server_name": "$sni",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "$sni",
            "server_port": 443
          },
          "private_key": "$private_key",
          "short_id": ["$short_id"]
        }
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
EOF

pkill -f sing-box
nohup ./sing-box run -c config.json > singbox.log 2>&1 &

echo "-------------------------------------------------------"
echo "部署完成！"
echo "系统架构: $cpu"
echo "主程序版本: $LATEST_TAG"
echo "IPv4 地址: $v4"
echo ""
echo "vless://$uuid@$v4:$port?security=reality&sni=$sni&fp=chrome&pbk=$public_key&sid=$short_id&type=xhttp&path=%2F$uuid-xh#Linode-xHTTP-$(date +%F)"
echo "-------------------------------------------------------"
