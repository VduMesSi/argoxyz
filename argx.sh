#!/bin/bash

export LANG=en_US.UTF-8

# apt update 
apt install curl coreutils util-linux sed jq -y >/dev/null 2>&1

VERSION=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | grep tag_name | cut -d '"' -f4)
wget -O sb.tar.gz \
https://github.com/SagerNet/sing-box/releases/download/${VERSION}/sing-box-${VERSION#v}-linux-amd64.tar.gz
tar -xzf sb.tar.gz
cp sing-box-*/sing-box /usr/local/bin/
chmod +x /usr/local/bin/sing-box
v4=$(curl -4 -s --max-time 5 https://api.ipify.org || curl -4 -s --max-time 5 https://icanhazip.com)

uuid=$(./sing-box generate uuid)
key_pair=$(./sing-box generate reality-keypair)
private_key=$(echo "$key_pair" | awk '/PrivateKey/ {print $2}' | tr -d '"')
public_key=$(echo "$key_pair" | awk '/PublicKey/ {print $2}' | tr -d '"')
short_id=$(./sing-box generate rand --hex 4)
sni="apple.com"
port=443

cat > config.json <<EOF
{
  "log": { "level": "info", "timestamp": true },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-in",
      "listen": "::",
      "listen_port": $port,
      "users": [{ "uuid": "$uuid" }],
      "transport": { "type": "xhttp", "path": "/$uuid-xh", "host": "$sni" },
      "tls": {
        "enabled": true,
        "server_name": "$sni",
        "reality": {
          "enabled": true,
          "handshake": { "server": "$sni", "server_port": 443 },
          "private_key": "$private_key",
          "short_id": ["$short_id"]
        }
      }
    }
  ],
  "outbounds": [{ "type": "direct", "tag": "direct" }]
}
EOF

pkill -f sing-box
nohup ./sing-box run -c config.json > singbox.log 2>&1 &

echo "-------------------------------------------------------"
echo "部署完成！"
echo "vless://$uuid@$v4:$port?security=reality&sni=$sni&fp=chrome&pbk=$public_key&sid=$short_id&type=xhttp&path=%2F$uuid-xh#Linode-xHTTP"
echo "-------------------------------------------------------"
