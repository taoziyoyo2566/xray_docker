#!/bin/bash
set -o pipefail

# 定义日志文件，位于当前目录，带有时间戳
LOGFILE="$(pwd)/script_log_$(date +%Y%m%d%H%M%S).log"

# 日志函数，将输出重定向到日志文件和标准错误
log_info() {
    echo -e "\033[32m[INFO]\033[0m $1" | tee -a "$LOGFILE" >&2
}

log_error() {
    echo -e "\033[31m[ERROR]\033[0m $1" | tee -a "$LOGFILE" >&2
}

# 显示帮助信息的函数，使用 log_info 输出
show_help() {
    log_info "Usage: $0 [options]"
    log_info ""
    log_info "Options:"
    log_info "  -u USERS         设置用户列表（用逗号分隔）"
    log_info "  -p PORT          设置端口号（5位，>20000）"
    log_info "  -i URL_ID        指定 URL ID（8位大写字母和数字）"
    log_info "  -r REGION        设置区域标识（6位大写字母）"
    log_info "  -d DIRECTORY     指定包含 JSON 配置文件的目录"
    log_info "  -m MONTHS        设置有效月数"
    log_info "  -c CPU_LIMIT     设置 CPU 限制（例如，0.5）"
    log_info "  -M MEMORY_LIMIT  设置内存限制（例如，300m）"
    log_info "  -e EXPIRE_DATE   设置过期日期（格式 YYYYMMDD）"
    log_info "  -f CONFIG_FILE   指定 JSON 配置文件"
    log_info "  -h               显示帮助信息"
}

# 生成包含大写字母和数字的随机 URL_ID
generate_url_id() {
    tr -dc 'A-Z0-9' </dev/urandom | head -c8
}

# 随机生成一个不在使用中的端口号
generate_random_port() {
    while true; do
        port=$((RANDOM % 45536 + 20000))
        if [ "$port" -le 65535 ] && ! is_port_in_use "$port"; then
            echo "$port"
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
        if [[ "$choice" =~ ^[Yy]$ ]]; then
            sudo apt-get update
            sudo apt-get install -y "$pkg"
            if [ $? -ne 0 ]; then
                log_error "安装 $pkg 失败。"
                exit 1
            fi
        else
            log_error "$cmd 未安装，脚本无法继续执行。"
            exit 1
        fi
    fi
}

# 使用 Docker 容器生成 X25519 密钥对
generate_x25519_keys() {
    local CONFIG_DIR="$1"
    local CONTAINER_NAME="xray-x25519"

    # 检查容器是否已经运行
    if docker ps --filter "name=${CONTAINER_NAME}" --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        log_info "密钥生成容器 '${CONTAINER_NAME}' 已经在运行。"
    else
        log_info "密钥生成容器 '${CONTAINER_NAME}' 不存在，正在创建..."
        docker run -d --name "${CONTAINER_NAME}" --rm \
            --memory="180m" --memory-swap="200m" --cpus="0.5" \
            teddysun/xray tail -f /dev/null
        if [ $? -ne 0 ]; then
            log_error "无法创建密钥生成容器 '${CONTAINER_NAME}'。"
            exit 1
        fi
        log_info "密钥生成容器 '${CONTAINER_NAME}' 已创建。"
        # 等待容器启动
        sleep 2
    fi

    # 调用 Xray 容器生成 X25519 密钥对
    local output
    output=$(docker exec "${CONTAINER_NAME}" xray x25519 | grep -E "Private key:|Public key:")
    if [ $? -ne 0 ]; then
        log_error "无法在容器内生成密钥。"
        exit 1
    fi

    # 提取私钥和公钥
    local PRIVATEKEY
    local PUBLICKEY
    PRIVATEKEY=$(echo "$output" | grep "Private key:" | awk -F': ' '{print $2}')
    PUBLICKEY=$(echo "$output" | grep "Public key:" | awk -F': ' '{print $2}')

    if [ -z "$PRIVATEKEY" ] || [ -z "$PUBLICKEY" ]; then
        log_error "生成密钥失败。"
        exit 1
    fi

    # 不在日志中输出私钥
    log_info "Public Key: $PUBLICKEY"

    # 设置密钥的权限并保存到 CONFIG_DIR
    echo "$PRIVATEKEY" > "${CONFIG_DIR}/private.key"
    echo "$PUBLICKEY" > "${CONFIG_DIR}/public.key"
    chmod 600 "${CONFIG_DIR}/private.key"
    chmod 600 "${CONFIG_DIR}/public.key"

    log_info "密钥已保存到 ${CONFIG_DIR} 目录。"

    # 返回私钥和公钥
    echo "$PRIVATEKEY|$PUBLICKEY"
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

# URL 编码函数
urlencode() {
    local string="${1}"
    local strlen=${#string}
    local encoded=""
    local pos c o

    for (( pos=0 ; pos<strlen ; pos++ )); do
        c=${string:$pos:1}
        case "$c" in
            [a-zA-Z0-9.~_-]) o="$c" ;;
            *)               printf -v o '%%%02X' "'$c"
        esac
        encoded+="${o}"
    done
    echo "${encoded}"
}

# 定义 get_country 方法
get_country() {
    # 获取本机外网IP地址
    local ip=$(curl -s https://api.ipify.org)

    if [ -z "$ip" ]; then
        log_error "无法获取本机外网IP地址"
        return 1
    fi

    # 使用ipinfo.io API获取IP地址的地理位置
    local country=$(curl -s "https://ipinfo.io/$ip" | jq -r '.country')

    if [ -z "$country" ]; then
        log_error "无法获取国家信息 for IP: $ip"
        return 1
    fi

    # 输出国家信息
    echo "$country"
}

# 显示节点信息并生成二维码的函数
display_node_info_with_qr() {
    local node_info_file="$1"

    if [ ! -f "$node_info_file" ]; then
        log_error "文件 $node_info_file 不存在。"
        exit 1
    fi

    # 使用 jq 格式化输出 nodeInfo-<n>.json
    log_info "以下是 $(basename "$node_info_file") 的内容："
    jq . "$node_info_file" | tee -a "$LOGFILE"

    # 遍历 JSON 文件，逐个用户输出二维码
    local users
    users=$(jq -c '.[]' "$node_info_file")
    for user in $users; do
        local email
        local sub_link

        email=$(echo "$user" | jq -r '.user')
        sub_link=$(echo "$user" | jq -r '.subscription')

        log_info "用户: $email"
        log_info "订阅链接: $sub_link"

        # 使用 qrencode 输出二维码到控制台
        qrencode -t ANSIUTF8 "$sub_link"

        echo
    done
}

# 处理单个配置文件的函数
process_config_file() {
    local CONFIG_FILE="$1"
    local USERS PORT URL_ID EXPIRE_DATE_ISO EXPIRE_DATE
    local CLIENTS_JSON USER_UUID_LIST USER_INFO_LIST NODE_INFO_LIST
    local CONTAINER_NAME CONFIG_DIR
    local PRIVATEKEY PUBLICKEY
    local REGION_VAR DOMAIN_SUFFIX
    local FLOW NETWORK DEST SERVERNAMES SNI FINGERPRINT SHORTID
    local CPU_LIMIT="$CPU_LIMIT"       # 使用全局 CPU_LIMIT
    local MEMORY_LIMIT="$MEMORY_LIMIT" # 使用全局 MEMORY_LIMIT
    local n u

    # 解析 JSON 文件
    USERS=$(jq -r '.u' "$CONFIG_FILE")
    USERS="${USERS}@taoziyoyo.com"
    PORT=$(jq -r '.p' "$CONFIG_FILE")
    URL_ID=$(jq -r '.i' "$CONFIG_FILE")
    EXPIRE_DATE=$(jq -r '.e' "$CONFIG_FILE")
    REGION_VAR=$(jq -r '.r' "$CONFIG_FILE")
    DOMAIN_NAME=$(jq -r '.s' "$CONFIG_FILE")  # 从 JSON 文件中读取 "n"

    # 获取 "u" 字段的值，用于目录名
    u=$(jq -r '.u' "$CONFIG_FILE")
    s=$(jq -r '.s' "$CONFIG_FILE")

    # 添加域名后缀
    DOMAIN_SUFFIX="o9drrm5l1d7uopaguucnxohzc3ul2yazxrldzpuoduu.taoziyoyo.com"
    DOMAIN_NAME_FULL="${DOMAIN_NAME}${DOMAIN_SUFFIX}"

    # 如果命令行没有提供 REGION，从配置文件获取
    # REGION="${REGION:-TESTUS}"  # 已移除，因为 'r' 从 JSON 文件中读取

    # 验证 USERS
    if [ -z "$USERS" ]; then
        log_error "必须指定用户列表，使用 -u 参数或在配置文件中指定。"
        exit 1
    fi

    # 验证 DOMAIN_NAME
    if [ -z "$DOMAIN_NAME_FULL" ]; then
        log_error "必须指定域名，使用 -n 参数或在配置文件中指定。"
        exit 1
    fi

    # 验证 DOMAIN_NAME 是否包含非法字符
    if echo "$DOMAIN_NAME_FULL" | grep -q '@'; then
        log_error "域名不能包含 '@' 符号，请提供有效的域名。"
        exit 1
    fi

    # 将 USERS 转换为数组
    IFS=',' read -ra USER_ARRAY <<< "$USERS"

    # 为每个用户生成 UUID，并构建用户 JSON 对象
    USER_UUID_LIST=()
    USER_INFO_LIST=()
    NODE_INFO_LIST=()
    for user in "${USER_ARRAY[@]}"; do
        uuid=$(uuidgen)
        if [ -z "$uuid" ]; then
            log_error "生成 UUID 失败。"
            exit 1
        fi
        # 验证并处理 EXPIRE_DATE
        if [ -n "$EXPIRE_DATE" ]; then
            # 验证日期格式 YYYYMMDD
            if ! date -d "${EXPIRE_DATE}" +"%Y%m%d" &>/dev/null; then
                log_error "无效的日期格式，请使用 YYYYMMDD 格式，例如 20231231"
                exit 1
            fi
            # 将日期转换为 ISO 8601 格式
            EXPIRE_DATE_ISO=$(date -d "${EXPIRE_DATE}" -u +"%Y-%m-%dT%H:%M:%SZ")
        fi

        # 使用 jq 构建用户 JSON 对象
        user_json=$(jq -n \
            --arg email "$user" \
            --arg uuid "$uuid" \
            --arg flow "xtls-rprx-vision" \
            --arg level "0" \
            --arg alterId "0" \
            --arg expire "${EXPIRE_DATE_ISO:-}" \
            '{
                user: $email,
                id: $uuid,
                flow: $flow,
                level: ($level | tonumber),
                alterId: ($alterId | tonumber)
            } | if $expire != "" then . + { expire: $expire } else . end')

        USER_UUID_LIST+=("$user_json")
        USER_INFO_LIST+=("$user|$uuid")
    done

    # 将用户列表转换为 JSON 数组字符串
    CLIENTS_JSON=$(printf '%s\n' "${USER_UUID_LIST[@]}" | jq -s '.')

    # 设置其他默认值
    PORT="${PORT:-$(generate_random_port)}"

    # 验证 URL_ID，如果提供了 URL_ID，验证它是否正确
    if [ -n "$URL_ID" ]; then
        if ! echo "$URL_ID" | grep -qE '^[A-Z0-9]{8}$'; then
            log_error "URL ID 必须是8位大写字母和数字的组合。"
            exit 1
        fi
    else
        # 如果没有指定 URL_ID，生成一个
        URL_ID=$(generate_url_id)
    fi
    REGION="${REGION_VAR:-TESTUS}"
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
    # 修改目录为 /opt/docker/reality/nodeInfo/reality_<u>
    CONFIG_DIR="/opt/docker/reality/nodeInfo/reality_${u}"
    mkdir -p "${CONFIG_DIR}/log"

    # 将 CLIENTS_JSON 写入 users.json
    echo "$CLIENTS_JSON" > "${CONFIG_DIR}/users.json"

    # 设置文件权限
    chmod 600 "${CONFIG_DIR}/users.json"

    # 显示生成的用户信息
    log_info "已生成 users.json，内容如下："
    jq . "${CONFIG_DIR}/users.json" | tee -a "$LOGFILE"

    # 生成密钥
    local key_pair
    key_pair=$(generate_x25519_keys "${CONFIG_DIR}")
    PRIVATEKEY=$(echo "$key_pair" | cut -d'|' -f1)
    PUBLICKEY=$(echo "$key_pair" | cut -d'|' -f2)

    # 更新配置文件
    cp ./config.json "${CONFIG_DIR}/config.json"
    chmod 600 "${CONFIG_DIR}/config.json"

    # 生成 SERVERNAMES 数组
    SERVERNAMES_JSON=$(echo "$SERVERNAMES" | jq -R 'split(" ")')

    # 生成随机的 shortId（16个十六进制字符，代表8字节）
    SHORTID=$(head -c8 /dev/urandom | xxd -ps -c8)

    # 设置 SNI 和指纹
    SNI="www.apple.com"
    FINGERPRINT="chrome"

    # 添加 flow 参数
    FLOW="xtls-rprx-vision"

    # 更新配置文件中的参数
    jq --argjson clients "$CLIENTS_JSON" \
       --arg privateKey "$PRIVATEKEY" \
       --arg dest "$DEST" \
       --argjson serverNames "$SERVERNAMES_JSON" \
       --arg network "$NETWORK" \
       --arg shortId "$SHORTID" \
       '.inbounds[0].settings.clients = $clients |
        .inbounds[0].streamSettings.realitySettings.privateKey = $privateKey |
        .inbounds[0].streamSettings.realitySettings.dest = $dest |
        .inbounds[0].streamSettings.realitySettings.serverNames = $serverNames |
        .inbounds[0].streamSettings.network = $network |
        .inbounds[0].streamSettings.realitySettings.shortIds = [$shortId]' \
       "${CONFIG_DIR}/config.json" > "${CONFIG_DIR}/config_tmp.json" && mv "${CONFIG_DIR}/config_tmp.json" "${CONFIG_DIR}/config.json"

    # 构建 DOCKER_RUN_CMD
    DOCKER_RUN_CMD=(docker run -d --name "$CONTAINER_NAME" \
      --restart=always \
      --log-opt max-size=50m \
      --cpus="$CPU_LIMIT" \
      --memory="$MEMORY_LIMIT" \
      -p "$PORT:443" \
      -e EXTERNAL_PORT="$PORT" \
      --env REGION="$REGION" \
      --env URL_ID="$URL_ID" \
      -v "${CONFIG_DIR}/config.json:/config.json:ro" \
      -v "${CONFIG_DIR}/users.json:/users.json:ro" \
      -v "${CONFIG_DIR}/log:/var/log/xray" \
      "$IMAGE_NAME")

    # 执行 docker run 命令
    log_info "正在启动 Docker 容器：$CONTAINER_NAME"
    "${DOCKER_RUN_CMD[@]}"
    if [ $? -ne 0 ]; then
        log_error "启动 Docker 容器失败。"
        exit 1
    fi

    # 检查容器是否启动成功
    sleep 3
    CONTAINER_STATUS=$(docker ps -a --filter "name=$CONTAINER_NAME" --format "{{.Status}}")
    if [[ $CONTAINER_STATUS == *"Up"* ]]; then
        log_info "容器 $CONTAINER_NAME 启动成功。"
    else
        log_error "容器 $CONTAINER_NAME 启动失败。"
        # 输出容器日志
        log_error "容器日志："
        docker logs "$CONTAINER_NAME" | tee -a "$LOGFILE"
        exit 1
    fi

    # 等待容器内应用程序启动
    sleep 5

    # 生成订阅链接并构建 nodeInfo-<n>.json
    NODE_INFO_LIST=()
    for user_info in "${USER_INFO_LIST[@]}"; do
        email=$(echo "$user_info" | cut -d'|' -f1)
        uuid=$(echo "$user_info" | cut -d'|' -f2)
        encoded_email=$(urlencode "$email")
        SUB_LINK="vless://${uuid}@${DOMAIN_NAME_FULL}:${PORT}?encryption=none&security=reality&pbk=${PUBLICKEY}&sid=${SHORTID}&flow=${FLOW}&sni=${SNI}&fp=${FINGERPRINT}&type=${NETWORK}#${encoded_email}"

        # 调用 get_country 方法并打印结果
        COUNTRY=$(get_country)

        # 添加到 nodeInfo-<n>.json 数据中
        node_info_json=$(jq -n \
            --arg user "$email" \
            --arg id "$uuid" \
            --arg expire "${EXPIRE_DATE_ISO:-}" \
            --arg subscription "$SUB_LINK" \
            --arg country "$COUNTRY" \
            --arg server "$DOMAIN_NAME" \
            --arg uid "$URL_ID" \
            '{
                user: $user,
                id: $id,
                expire: $expire,
                subscription: $subscription,
                country: $country,
                server: $server,
                uid: $uid
            }')
        NODE_INFO_LIST+=("$node_info_json")
    done

    # 定义 nodeInfo 文件名为 nodeInfo-<n>.json
    NODE_INFO_FILENAME="nodeInfo-${s}.json"

    # 生成 nodeInfo-<n>.json 文件
    NODE_INFO_JSON=$(printf '%s\n' "${NODE_INFO_LIST[@]}" | jq -s '.')
    echo "$NODE_INFO_JSON" > "${CONFIG_DIR}/${NODE_INFO_FILENAME}"

    # 验证 nodeInfo-<n>.json 是否成功创建
    if [ ! -s "${CONFIG_DIR}/${NODE_INFO_FILENAME}" ]; then
        log_error "${NODE_INFO_FILENAME} 文件创建失败或为空。"
        exit 1
    fi
    log_info "${NODE_INFO_FILENAME} 文件已成功创建。"

    # 将 nodeInfo-<n>.json 拷贝到容器根目录
    docker cp "${CONFIG_DIR}/${NODE_INFO_FILENAME}" "${CONTAINER_NAME}:/nodeInfo-${s}.json"
    if [ $? -ne 0 ]; then
        log_error "将 ${NODE_INFO_FILENAME} 拷贝到容器失败。"
        exit 1
    fi

    # 检查是否成功拷贝
    if docker exec "${CONTAINER_NAME}" test -f /nodeInfo-"${s}".json; then
        log_info "已成功将 ${NODE_INFO_FILENAME} 拷贝到容器的根目录。"
    else
        log_error "将 ${NODE_INFO_FILENAME} 拷贝到容器失败。"
        exit 1
    fi

    log_info "已生成 ${NODE_INFO_FILENAME}，内容如下："
    jq . "${CONFIG_DIR}/${NODE_INFO_FILENAME}" | tee -a "$LOGFILE"

    # 设置文件权限
    chmod 600 "${CONFIG_DIR}/${NODE_INFO_FILENAME}"

    # 新增：将 nodeInfo-<n>.json 放入共享卷的 node-info/<u>/ 目录中
    docker run --rm \
        -v shared-data:/node-data \
        -v "${CONFIG_DIR}:/config" \
        busybox sh -c "mkdir -p /node-data/node-info/${u} && cp /config/${NODE_INFO_FILENAME} /node-data/node-info/${u}/${NODE_INFO_FILENAME} && chmod 600 /node-data/node-info/${u}/${NODE_INFO_FILENAME}"

    # 验证复制是否成功
    docker run --rm -v shared-data:/node-data busybox sh -c "test -f /node-data/node-info/${u}/${NODE_INFO_FILENAME}"
    if [ $? -eq 0 ]; then
        log_info "${NODE_INFO_FILENAME} 已成功复制到共享卷的 node-info/${u}/ 目录。"
    else
        log_error "将 ${NODE_INFO_FILENAME} 复制到共享卷失败。"
        exit 1
    fi

    # 输出节点信息和生成二维码
    display_node_info_with_qr "${CONFIG_DIR}/${NODE_INFO_FILENAME}"
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
    check_and_install rsync rsync

    # 初始化变量，设置默认值
    USERS=""
    PORT=""
    MONTH_COUNT=""
    REGION=""  # 移除 -r 参数
    CPU_LIMIT="0.5"    # 默认 CPU 限制
    MEMORY_LIMIT="300m" # 默认内存限制
    EXPIRE_DATE=""      # 用户有效期
    URL_ID=""           # URL ID, 默认为空
    CONFIG_FILE=""
    DIRECTORY=""

    # 使用 getopts 解析命令行参数，移除 -r 参数
    while getopts "u:i:p:d:m:c:M:e:f:h" opt; do
        case $opt in
            u) USERS="$OPTARG";;
            i) URL_ID="$OPTARG";;
            p) PORT="$OPTARG";;
            d) DIRECTORY="$OPTARG";;
            c) CPU_LIMIT="$OPTARG";;
            M) MEMORY_LIMIT="$OPTARG";;
            e) EXPIRE_DATE="$OPTARG";;
            f) CONFIG_FILE="$OPTARG";;
            h)
                show_help
                exit 0;;
            *)
                log_error "未知的选项: -$opt"
                show_help
                exit 1;;
        esac
    done

    # 设置镜像名称
    TIMESTAMP=$(date +"%Y%m%d%H%M%S")
    IMAGE_BASE_NAME="vless_reality"
    NEW_VERSION=$(get_latest_version "$IMAGE_BASE_NAME")
    IMAGE_VERSION="v${NEW_VERSION}_${TIMESTAMP}"
    IMAGE_NAME="${IMAGE_BASE_NAME}:${IMAGE_VERSION}"

    # 添加构建 Docker 镜像的提示
    read -p "是否生成新的 Docker 镜像？(y/n): " build_choice
    if [[ "$build_choice" =~ ^[Yy]$ ]]; then
        # 构建 Docker 镜像
        log_info "正在构建 Docker 镜像：$IMAGE_NAME"
        docker build -t "$IMAGE_NAME" .
        if [ $? -ne 0 ]; then
            log_error "Docker 镜像构建失败。"
            exit 1
        fi
    else
        log_info "跳过 Docker 镜像构建，使用现有镜像。"
        # 使用最新的已存在的镜像
        EXISTING_IMAGE=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep "^${IMAGE_BASE_NAME}:" | head -n1)
        if [ -z "$EXISTING_IMAGE" ]; then
            log_error "没有找到现有的镜像，请先构建一个。"
            exit 1
        else
            IMAGE_NAME="$EXISTING_IMAGE"
            log_info "使用现有的镜像：$IMAGE_NAME"
        fi
    fi

    if [ -n "$DIRECTORY" ]; then
        # 检查目录是否存在
        if [ ! -d "$DIRECTORY" ]; then
            log_error "目录 $DIRECTORY 不存在。"
            exit 1
        fi
        # 处理目录下的所有 JSON 文件
        for CONFIG_FILE in "$DIRECTORY"/*.json; do
            if [ -f "$CONFIG_FILE" ]; then
                log_info "正在处理配置文件: $CONFIG_FILE"
                process_config_file "$CONFIG_FILE"
            fi
        done
    else
        if [ -n "$CONFIG_FILE" ]; then
            process_config_file "$CONFIG_FILE"
        else
            log_error "必须指定配置文件 (-f) 或目录 (-d)。"
            exit 1
        fi
    fi

    log_info "操作成功完成。"
}

# 执行主函数
main "$@"