#!/bin/bash

export LANG=en_US.UTF-8
WORKDIR="/root/singbox"
rm -rf "$WORKDIR" && mkdir -p "$WORKDIR"
cd "$WORKDIR"

# 1. 自动检测架构
case $(uname -m) in
    arm64|aarch64) cpu="arm64" ;;
    amd64|x86_64) cpu="amd64" ;;
    *) echo "不支持的架构: $(uname -m)"; exit 1 ;;
esac

# 2. 安装依赖
# apt update 
apt install curl coreutils util-linux sed jq -y >/dev/null 2>&1

# 3. 修复版下载逻辑
echo "正在获取 Sing-box 官方最新版本..."
# 增加 User-Agent 防止被 GitHub 拦截
LATEST_TAG=$(curl -sS -H "User-Agent: Mozilla/5.0" https://api.github.com/repos/SagerNet/sing-box/releases/latest | jq -r .tag_name)
VERSION=${LATEST_TAG#v}

# 构造下载链接
DOWNLOAD_URL="https://github.com/SagerNet/sing-box/releases/download/${LATEST_TAG}/sing-box-${VERSION}-linux-${cpu}.tar.gz"

echo "正在从 $DOWNLOAD_URL 下载..."
curl -Lo sing-box.tar.gz "$DOWNLOAD_URL"

# 检查文件是否下载成功且非空
if [ ! -s sing-box.tar.gz ]; then
    echo "下载失败，请检查网络连接。"
    exit 1
fi

# 4. 修复版解压逻辑：不使用 --strip-components，手动移动二进制文件
tar -xzf sing-box.tar.gz
# 自动寻找解压后目录里的 sing-box 文件
SB_BIN=$(find . -name "sing-box" -type f)
if [ -n "$SB_BIN" ]; then
    mv "$SB_BIN" ./sing-box
    chmod +x ./sing-box
else
    echo "解压失败，未找到二进制文件。"
    exit 1
fi

# 5. 获取 IPv4
v4=$(curl -4 -s --max-time 5 https://api.ipify.org || curl -4 -s --max-time 5 https://icanhazip.com)

# 6. 生成凭据
uuid=$(./sing-box generate uuid)
key_pair=$(./sing-box generate reality-keypair)
private_key=$(echo "$key_pair" | awk '/PrivateKey/ {print $2}' | tr -d '"')
public_key=$(echo "$key_pair" | awk '/PublicKey/ {print $2}' | tr -d '"')
short_id=$(./sing-box generate rand --hex 4)
sni="apple.com"
port=443

# 7. 写入配置
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

# 8. 启动
pkill -f sing-box
nohup ./sing-box run -c config.json > singbox.log 2>&1 &

# 9. 输出
echo "-------------------------------------------------------"
echo "部署完成！"
echo "vless://$uuid@$v4:$port?security=reality&sni=$sni&fp=chrome&pbk=$public_key&sid=$short_id&type=xhttp&path=%2F$uuid-xh#Linode-xHTTP"
echo "-------------------------------------------------------"
