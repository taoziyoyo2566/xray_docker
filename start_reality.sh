#!/bin/bash
#set -e
set -o pipefail

# 日志函数
log_info() {
    echo -e "\033[32m[INFO]\033[0m $1"
}

log_error() {
    echo -e "\033[31m[ERROR]\033[0m $1"
}

# 显示帮助信息的函数
show_help() {
    echo "Usage: $0 -u user1@example.com,user2@example.com [options]"
    echo
    echo "Options:"
    echo "  -u USERS         Set the users (comma-separated list)"
    echo "  -p PORT          Set the port number (5 digits, >20000)"
    echo "  -r REGION        Set the REGION (6 uppercase letters)"
    echo "  -d DAYS          Set the number of days"
    echo "  -m MONTHS        Set the number of months"
    echo "  -c CPU_LIMIT     Set the CPU limit (e.g., 0.5)"
    echo "  -M MEMORY_LIMIT  Set the memory limit (e.g., 300m)"
    echo "  -e EXPIRE_DATE   Set the expiration date (YYYYMMDD format)"
    echo "  -h               Show help"
}

# 生成包含大写字母和数字的随机 URL_ID
generate_url_id() {
    tr -dc 'A-Z0-9' </dev/urandom | head -c8
}

# 随机生成一个不在使用中的端口号
generate_random_port() {
    while true; do
        port=$((RANDOM % 45536 + 20000))
        if [ $port -le 65535 ] && ! is_port_in_use $port; then
            echo $port
            return
        fi
    done
}

# 检查端口是否在使用中
is_port_in_use() {
    local port=$1
    if netstat -tuln | grep -q -E "[:.]$port\s"; then
        return 0
    else
        return 1
    fi
}

# 检查并安装必要的软件
check_and_install() {
    local cmd=$1
    local pkg=$2
    if ! command -v "$cmd" >/dev/null 2>&1; then
        read -p "$cmd 未安装，是否安装 $pkg？(y/n): " choice
        if [ "$choice" = "y" ] || [ "$choice" = "Y" ]; then
            sudo apt-get update
            sudo apt-get install -y $pkg
        else
            log_error "$cmd 未安装，脚本无法继续执行。"
            exit 1
        fi
    fi
}

# 使用 Docker 容器生成 X25519 密钥对
generate_x25519_keys() {
    local CONTAINER_NAME="xray-x25519"

    # 检查容器是否已经运行
    if docker ps --filter "name=${CONTAINER_NAME}" --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        log_info "密钥生成容器 '${CONTAINER_NAME}' 已经在运行。"
    else
        log_info "密钥生成容器 '${CONTAINER_NAME}' 不存在，正在创建..."
        docker run -d --name "${CONTAINER_NAME}" --rm \
            --memory="180m" --memory-swap="200m" --cpus="0.5" \
            teddysun/xray tail -f /dev/null
        log_info "密钥生成容器 '${CONTAINER_NAME}' 已创建。"
        # 等待容器启动
        sleep 2
    fi

    # 调用 Xray 容器生成 X25519 密钥对
    # 清理非密钥输出，仅保留 "Private key:" 和 "Public key:" 行
    local output
    output=$(docker exec "${CONTAINER_NAME}" xray x25519 | grep -E "Private key:|Public key:")

    # 提取私钥和公钥
    PRIVATEKEY=$(echo "$output" | grep "Private key:" | awk -F': ' '{print $2}')
    PUBLICKEY=$(echo "$output" | grep "Public key:" | awk -F': ' '{print $2}')

    if [ -z "$PRIVATEKEY" ] || [ -z "$PUBLICKEY" ]; then
        log_error "生成密钥失败。"
        exit 1
    fi

    log_info "Private Key: $PRIVATEKEY"
    log_info "Public Key: $PUBLICKEY"

    # 停止并移除密钥生成容器
    docker stop "${CONTAINER_NAME}" >/dev/null 2>&1
}

# 获取最新的镜像版本号
get_latest_version() {
    local base_name=$1
    local versions=($(docker images --format "{{.Repository}}:{{.Tag}}" | grep "^${base_name}:" | awk -F: '{print $2}'))
    local max_version=0
    for ver in "${versions[@]}"; do
        if [[ $ver =~ ^v([0-9]+)_ ]]; then
            num=${BASH_REMATCH[1]}
            if (( num > max_version )); then
                max_version=$num
            fi
        fi
    done
    echo $((max_version + 1))
}

# 主函数
main() {
    # 检查并安装必要的软件
    check_and_install uuidgen uuid-runtime
    check_and_install jq jq
    check_and_install qrencode qrencode
    check_and_install docker docker.io
    check_and_install netstat net-tools
    check_and_install curl curl

    # 初始化变量，设置默认值
    USERS=""
    PORT=""
    DAY_COUNT=""
    MONTH_COUNT=""
    REGION=""
    CPU_LIMIT="0.5"    # Default CPU limit (0.5 cores)
    MEMORY_LIMIT="300m" # Default memory limit (300 MB)
    EXPIRE_DATE=""      # 用户有效期

    # 使用 getopts 解析命令行参数
    while getopts "u:p:r:d:m:c:M:e:h" opt; do
        case $opt in
            u) USERS="$OPTARG";;
            p) PORT="$OPTARG";;
            r) REGION="$OPTARG";;
            d) DAY_COUNT="$OPTARG";;
            m) MONTH_COUNT="$OPTARG";;
            c) CPU_LIMIT="$OPTARG";;
            M) MEMORY_LIMIT="$OPTARG";;
            e) EXPIRE_DATE="$OPTARG";;
            h)
                show_help
                exit 0;;
            *)
                log_error "未知的选项: -$opt"
                show_help
                exit 1;;
        esac
    done

    # 验证 USERS
    if [ -z "$USERS" ]; then
        log_error "必须指定用户列表，使用 -u 参数。"
        exit 1
    fi

    # 将 USERS 转换为数组
    IFS=',' read -ra USER_ARRAY <<< "$USERS"

    # 为每个用户生成 UUID，并构建用户 JSON 对象
    USER_UUID_LIST=()
    USER_INFO_LIST=()
    for user in "${USER_ARRAY[@]}"; do
        uuid=$(uuidgen)
        if [ -z "$uuid" ]; then
            log_error "生成 UUID 失败。"
            exit 1
        fi
        # 如果设置了 EXPIRE_DATE，则添加到用户对象中
        if [ -n "$EXPIRE_DATE" ]; then
            # 验证日期格式 YYYYMMDD
            if ! date -d "${EXPIRE_DATE}" +"%Y%m%d" &>/dev/null; then
                log_error "无效的日期格式，请使用 YYYYMMDD 格式，例如 20231231"
                exit 1
            fi
            # 将日期转换为 ISO 8601 格式
            EXPIRE_DATE_ISO=$(date -d "${EXPIRE_DATE}" -u +"%Y-%m-%dT%H:%M:%SZ")
            USER_UUID_LIST+=("{\"email\":\"$user\",\"id\":\"$uuid\",\"flow\":\"xtls-rprx-vision\",\"level\":0,\"alterId\":0,\"expire\":\"$EXPIRE_DATE_ISO\"}")
        else
            USER_UUID_LIST+=("{\"email\":\"$user\",\"id\":\"$uuid\",\"flow\":\"xtls-rprx-vision\",\"level\":0,\"alterId\":0}")
        fi
        # 保存用户信息，后续生成订阅链接
        USER_INFO_LIST+=("$user|$uuid")
    done

    # 将用户列表转换为 JSON 数组字符串
    CLIENTS_JSON=$(printf '%s\n' "${USER_UUID_LIST[@]}" | paste -sd ',' -)
    CLIENTS_JSON="[$CLIENTS_JSON]"

    # 设置其他默认值
    URL_ID="$(generate_url_id)"
    PORT="${PORT:-$(generate_random_port)}"
    REGION="${REGION:-TESTUS}"
    NETWORK="tcp"
    DEST="www.apple.com:443"
    SERVERNAMES="www.apple.com images.apple.com"

    # 验证 PORT
    if ! echo "$PORT" | grep -qE '^[0-9]{5}$' || [ "$PORT" -le 20000 ]; then
        log_error "参数 PORT 必须是5位大于20000的端口号。"
        exit 1
    fi

    if is_port_in_use "$PORT"; then
        log_error "端口号 $PORT 已在使用中。"
        exit 1
    fi

    # 验证 REGION
    if ! echo "$REGION" | grep -qE '^[A-Z]{6}$'; then
        log_error "参数 REGION 必须是6位大写英文字母。"
        exit 1
    fi

    # 设置 CONTAINER_NAME
    CONTAINER_NAME="reality_${REGION}_${URL_ID}"

    # 创建用户配置文件目录
    CONFIG_DIR="/opt/docker/reality/nodeInfo/${CONTAINER_NAME}"
    mkdir -p "${CONFIG_DIR}/log"

    # 将 CLIENTS_JSON 写入 users.json
    echo "$CLIENTS_JSON" > "${CONFIG_DIR}/users.json"

    # 检查 users.json 是否成功创建
    if [ ! -f "${CONFIG_DIR}/users.json" ]; then
        log_error "users.json 文件创建失败。"
        exit 1
    fi

    # 显示生成的用户信息
    log_info "已生成 users.json，内容如下："
    cat "${CONFIG_DIR}/users.json"

    # 生成密钥
    generate_x25519_keys

    # 更新配置文件
    cp ./config.json "${CONFIG_DIR}/config.json"

    # 生成 SERVERNAMES 数组
    SERVERNAMES_JSON=$(echo "$SERVERNAMES" | jq -R 'split(" ")')

    jq --argjson clients "$CLIENTS_JSON" \
       --arg privateKey "$PRIVATEKEY" \
       --arg dest "$DEST" \
       --argjson serverNames "$SERVERNAMES_JSON" \
       --arg network "$NETWORK" \
       '.inbounds[0].settings.clients = $clients |
        .inbounds[0].streamSettings.realitySettings.privateKey = $privateKey |
        .inbounds[0].streamSettings.realitySettings.dest = $dest |
        .inbounds[0].streamSettings.realitySettings.serverNames = $serverNames |
        .inbounds[0].streamSettings.network = $network' \
       "${CONFIG_DIR}/config.json" > "${CONFIG_DIR}/config_tmp.json" && mv "${CONFIG_DIR}/config_tmp.json" "${CONFIG_DIR}/config.json"

    # 设置镜像名称
    TIMESTAMP=$(date +"%Y%m%d%H%M%S")
    IMAGE_BASE_NAME="vless_reality"
    NEW_VERSION=$(get_latest_version "$IMAGE_BASE_NAME")
    IMAGE_VERSION="v${NEW_VERSION}_${TIMESTAMP}"
    IMAGE_NAME="${IMAGE_BASE_NAME}:${IMAGE_VERSION}"

    # 构建 Docker 镜像
    log_info "正在构建 Docker 镜像：$IMAGE_NAME"
    docker build -t $IMAGE_NAME .

    # 构建 DOCKER_RUN_CMD
    DOCKER_RUN_CMD="docker run -d --name $CONTAINER_NAME \
      --restart=always \
      --log-opt max-size=50m \
      --cpus=\"$CPU_LIMIT\" \
      --memory=\"$MEMORY_LIMIT\" \
      -p $PORT:443 \
      -e EXTERNAL_PORT=$PORT \
      --env REGION=${REGION} \
      --env URL_ID=${URL_ID} \
      -v ${CONFIG_DIR}/config.json:/config.json \
      -v ${CONFIG_DIR}/users.json:/users.json \
      -v ${CONFIG_DIR}/log:/var/log/xray \
      $IMAGE_NAME"

    # 执行 docker run 命令
    log_info "正在启动 Docker 容器：$CONTAINER_NAME"
    eval $DOCKER_RUN_CMD

    # 检查容器是否启动成功
    sleep 3
    CONTAINER_STATUS=$(docker ps -a --filter "name=$CONTAINER_NAME" --format "{{.Status}}")
    if [[ $CONTAINER_STATUS == *"Up"* ]]; then
        log_info "容器 $CONTAINER_NAME 启动成功。"
    else
        log_error "容器 $CONTAINER_NAME 启动失败。"
        # 输出容器日志
        log_error "容器日志："
        docker logs $CONTAINER_NAME
        exit 1
    fi

    # 等待容器内应用程序启动
    sleep 5

    # 从容器中提取配置信息
    log_info "从容器中提取配置信息..."

    # 提取容器内的 vless_info.json
    docker cp ${CONTAINER_NAME}:/vless_info.json "${CONFIG_DIR}/vless_info.json" > /dev/null 2>&1 || true
    if [ ! -f "${CONFIG_DIR}/vless_info.json" ]; then
        log_error "未能从容器中提取 vless_info.json 文件。"
        exit 1
    fi

    JSON_OUTPUT=$(cat "${CONFIG_DIR}/vless_info.json")
    if [[ -z "$JSON_OUTPUT" ]]; then
        log_error "vless_info.json 文件为空。"
        exit 1
    fi

    IPV4=$(echo "$JSON_OUTPUT" | jq -r '.IPV4')
    if [[ -z "$IPV4" ]]; then
        log_error "未找到有效的 IP。"
        exit 1
    fi

    # 输出节点信息和生成二维码
    echo "节点信息：" > "${CONFIG_DIR}/node_info.txt"
    for user_info in "${USER_INFO_LIST[@]}"; do
        email=$(echo "$user_info" | cut -d'|' -f1)
        uuid=$(echo "$user_info" | cut -d'|' -f2)
        SUB_LINK="vless://${uuid}@${IPV4}:${PORT}?encryption=none&security=reality&type=${NETWORK}&sni=www.apple.com&fp=chrome&pbk=${PUBLICKEY}&flow=xtls-rprx-vision#${email}"
        echo "用户：$email" | tee -a "${CONFIG_DIR}/node_info.txt"
        echo "订阅链接：" | tee -a "${CONFIG_DIR}/node_info.txt"
        echo "$SUB_LINK" | tee -a "${CONFIG_DIR}/node_info.txt"
        echo "$SUB_LINK" | qrencode -o "${CONFIG_DIR}/${email}_qr.png"
        echo "二维码已保存为：${CONFIG_DIR}/${email}_qr.png"
        echo "" | tee -a "${CONFIG_DIR}/node_info.txt"
    done

    # 显示节点信息
    cat "${CONFIG_DIR}/node_info.txt"

    log_info "操作成功完成。"
}

# 执行主函数
main "$@"