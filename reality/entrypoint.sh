#!/bin/sh
set -e  # 当发生错误时立即退出
set -u  # 当使用未定义的变量时退出
set -o pipefail  # 管道中任一命令失败，则整个管道失败

# 日志函数
log_info() {
    echo "[INFO] $1"
}

log_warning() {
    echo "[WARNING] $1"
}

log_error() {
    echo "[ERROR] $1"
}

# 主函数
main() {
    if [ -f /config_info.txt ]; then
        log_info "配置文件已存在，跳过初始化。"
    else
        IPV6=$(curl -6 -sSL --connect-timeout 3 --retry 2 ip.sb || echo "null")
        IPV4=$(curl -4 -sSL --connect-timeout 3 --retry 2 ip.sb || echo "null")

        UUID="${UUID:-$(/xray uuid)}"
        log_info "UUID: $UUID"

        EXTERNAL_PORT="${EXTERNAL_PORT:-443}"
        log_info "EXTERNAL_PORT: $EXTERNAL_PORT"

        DEST="${DEST:-www.apple.com:443}"
        log_info "DEST: $DEST"

        SERVERNAMES="${SERVERNAMES:-www.apple.com images.apple.com}"
        log_info "SERVERNAMES: $SERVERNAMES"

        NETWORK="${NETWORK:-tcp}"
        log_info "NETWORK: $NETWORK"

        URL_ID="${URL_ID:-$(openssl rand -hex 4 | tr -d '\n')}"
        log_info "URL_ID: $URL_ID"

        REGION="${REGION:-NA}"
        REGION_ID="${REGION}_${URL_ID}"

        CREATE_DATETIME=$(date +"%Y-%m-%d %H:%M:%S")
        EXPIRE_DATETIME="NA"

        if [ -n "${DAY_COUNT:-}" ] && [ -n "${MONTH_COUNT:-}" ]; then
            EXPIRE_DATETIME=$(date -d "+${DAY_COUNT} day +${MONTH_COUNT} month" +"%Y-%m-%d %H:%M:%S")
        elif [ -n "${DAY_COUNT:-}" ]; then
            EXPIRE_DATETIME=$(date -d "+${DAY_COUNT} day" +"%Y-%m-%d %H:%M:%S")
        elif [ -n "${MONTH_COUNT:-}" ]; then
            EXPIRE_DATETIME=$(date -d "+${MONTH_COUNT} month" +"%Y-%m-%d %H:%M:%S")
        else
            log_warning "未设置过期日期。"
        fi

        # 生成私钥和公钥
        if [ -z "${PRIVATEKEY:-}" ]; then
            log_info "未设置 PRIVATEKEY，生成新的密钥对。"
            KEY_OUTPUT=$(/xray x25519)
            PRIVATEKEY=$(echo "$KEY_OUTPUT" | grep "Private key" | awk -F ': ' '{print $2}')
            PUBLICKEY=$(echo "$KEY_OUTPUT" | grep "Public key" | awk -F ': ' '{print $2}')
            log_info "Private Key: $PRIVATEKEY"
            log_info "Public Key: $PUBLICKEY"
        fi

        # 更新配置文件
        jq --arg uuid "$UUID" \
           --arg dest "$DEST" \
           --argjson serverNames "$(echo "$SERVERNAMES" | jq -R 'split(" ")')" \
           --arg privateKey "$PRIVATEKEY" \
           --arg network "$NETWORK" \
           '.inbounds[0].settings.clients[0].id = $uuid |
            .inbounds[0].streamSettings.realitySettings.dest = $dest |
            .inbounds[0].streamSettings.realitySettings.serverNames = $serverNames |
            .inbounds[0].streamSettings.realitySettings.privateKey = $privateKey |
            .inbounds[0].streamSettings.network = $network' /config.json > /config.json_tmp

        if [ $? -ne 0 ]; then
            log_error "更新配置文件失败。"
            exit 1
        fi

        mv /config.json_tmp /config.json

        FIRST_SERVERNAME=$(echo "$SERVERNAMES" | awk '{print $1}')

        # 配置信息
        {
            echo "IPV6: $IPV6"
            echo "IPV4: $IPV4"
            echo "UUID: $UUID"
            echo "DEST: $DEST"
            echo "PORT: $EXTERNAL_PORT"
            echo "SERVERNAMES: $SERVERNAMES (任选其一)"
            echo "PRIVATEKEY: $PRIVATEKEY"
            echo "PUBLICKEY: $PUBLICKEY"
            echo "NETWORK: $NETWORK"
        } > /config_info.txt

        if [ "$IPV4" != "null" ]; then
            URL_IPV4="vless://$UUID@$IPV4:$EXTERNAL_PORT?encryption=none&security=reality&type=$NETWORK&sni=$FIRST_SERVERNAME&fp=chrome&pbk=$PUBLICKEY&flow=xtls-rprx-vision#vless_reality_$REGION_ID"
            echo "IPV4 订阅连接: $URL_IPV4" >> /config_info.txt

            # 生成 vless_info.json
            cat > /vless_info.json <<EOF
{
  "URL_ID": "$URL_ID",
  "REGION": "$REGION",
  "IPV4": "$IPV4",
  "UUID": "$UUID",
  "DEST": "$DEST",
  "PORT": "$EXTERNAL_PORT",
  "NETWORK": "$NETWORK",
  "URL_IPV4": "$URL_IPV4",
  "CREATE_DATETIME": "$CREATE_DATETIME",
  "EXPIRE_DATETIME": "$EXPIRE_DATETIME",
  "MONTH_COUNT": "${MONTH_COUNT:-}",
  "DAY_COUNT": "${DAY_COUNT:-}"
}
EOF
        fi

        if [ "$IPV6" != "null" ]; then
            URL_IPV6="vless://$UUID@$IPV6:$EXTERNAL_PORT?encryption=none&security=reality&type=$NETWORK&sni=$FIRST_SERVERNAME&fp=chrome&pbk=$PUBLICKEY&flow=xtls-rprx-vision#vless_reality_V6_$REGION_ID"
            echo "IPV6 订阅连接: $URL_IPV6" >> /config_info.txt

            # 生成 vless_info_v6.json
            cat > /vless_info_v6.json <<EOF
{
  "URL_ID": "$URL_ID",
  "REGION": "$REGION",
  "IPV6": "$IPV6",
  "UUID": "$UUID",
  "DEST": "$DEST",
  "PORT": "$EXTERNAL_PORT",
  "NETWORK": "$NETWORK",
  "URL_IPV6": "$URL_IPV6",
  "CREATE_DATETIME": "$CREATE_DATETIME",
  "EXPIRE_DATETIME": "$EXPIRE_DATETIME",
  "MONTH_COUNT": "${MONTH_COUNT:-}",
  "DAY_COUNT": "${DAY_COUNT:-}"
}
EOF
        fi
    fi

    # 显示配置信息
    cat /config_info.txt

    # 运行 xray
    exec /xray -config /config.json
}

# 执行主函数
main "$@"
