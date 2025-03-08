#!/bin/bash
set -o pipefail

# 定义固定的日志文件名
LOGFILE="start_reality.log"

# 定义日志相关路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
LOG_DIR="${SCRIPT_DIR}/logs"
LOGFILE="${LOG_DIR}/start_reality_$(date '+%Y%m%d').log"

# 确保日志目录存在
mkdir -p "$LOG_DIR"

# 日志函数，将输出重定向到日志文件和标准错误，并添加时间戳
log_info() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" | tee -a "$LOGFILE" >&2
}

log_error() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" | tee -a "$LOGFILE" >&2
}

# 设置数据目录的函数，确保目录存在且当前用户有权限
setup_data_directory() {
    # 获取当前用户
    local current_user=$(whoami)
    
    # 定义基础数据目录
    local reality_dir="/opt/docker/reality/nodeInfo"
    
    # 创建目录结构
    sudo mkdir -p "${reality_dir}"
    
    # 确保权限正确
    sudo chown -R $current_user:$current_user "${reality_dir}"
    log_info "数据目录已设置在: ${reality_dir}"
    
    # 返回创建的目录路径
    echo "${reality_dir}"
}

# 显示帮助信息的函数，使用 log_info 输出
show_help() {
    log_info "Usage: $0 [options]"
    log_info ""
    log_info "Options:"
    log_info "  -f CONFIG_FILE   指定 JSON 配置文件"
    log_info "  -d DIRECTORY     指定包含 JSON 配置文件的目录"
    log_info "  -h               显示帮助信息"
}

# 检查容器是否已经存在并且正在运行
check_container_running() {
    local container_name="$1"
    
    # 检查容器是否存在
    if ! docker ps -a --format '{{.Names}}' | grep -q "^${container_name}$"; then
        return 1
    fi
    
    # 检查容器是否正在运行
    if ! docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
        return 1
    fi
    
    return 0
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

install_xxd(){
    if ! command -v xxd >/dev/null 2>&1; then
      sudo cp ./xxd /usr/bin/
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

    # 检查容器是否已经存在且正在运行
    if check_container_running "${CONTAINER_NAME}"; then
        log_info "密钥生成容器 '${CONTAINER_NAME}' 已经在运行。"
    else
        # 如果容器存在但不在运行，先删除它
        if docker ps -a --filter "name=${CONTAINER_NAME}" --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
            log_info "密钥生成容器 '${CONTAINER_NAME}' 存在但未运行，正在移除..."
            docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1
        fi
        
        log_info "正在创建密钥生成容器..."
        docker run -d --name "${CONTAINER_NAME}" --rm \
            --memory="180m" --memory-swap="200m" --cpus="0.5" \
            teddysun/xray tail -f /dev/null
        
        if [ $? -ne 0 ]; then
            log_error "无法创建密钥生成容器 '${CONTAINER_NAME}'。"
            exit 1
        fi
        
        log_info "密钥生成容器 '${CONTAINER_NAME}' 已创建，等待容器完全启动..."
        
        # 等待容器完全启动，最多等待30秒
        local wait_count=0
        while ! docker exec "${CONTAINER_NAME}" echo "Container is ready" >/dev/null 2>&1; do
            sleep 1
            wait_count=$((wait_count + 1))
            if [ $wait_count -ge 30 ]; then
                log_error "等待容器启动超时，请检查Docker状态。"
                exit 1
            fi
        done
        
        log_info "密钥生成容器已准备就绪。"
    fi

    # 确保容器运行状态，再次检查
    if ! check_container_running "${CONTAINER_NAME}"; then
        log_error "密钥生成容器不在运行状态，无法生成密钥。"
        exit 1
    fi

    # 调用 Xray 容器生成 X25519 密钥对
    local output
    local retry_count=0
    local max_retries=3
    
    while [ $retry_count -lt $max_retries ]; do
        output=$(docker exec "${CONTAINER_NAME}" xray x25519 2>&1)
        
        # 检查命令是否成功执行
        if [ $? -eq 0 ] && echo "$output" | grep -q "Private key:"; then
            break
        fi
        
        log_info "生成密钥重试 ($((retry_count+1))/$max_retries)..."
        retry_count=$((retry_count + 1))
        sleep 2
    done
    
    if [ $retry_count -eq $max_retries ]; then
        log_error "多次尝试生成密钥失败。错误输出: $output"
        exit 1
    fi

    # 提取私钥和公钥
    local PRIVATEKEY
    local PUBLICKEY
    PRIVATEKEY=$(echo "$output" | grep "Private key:" | awk -F': ' '{print $2}')
    PUBLICKEY=$(echo "$output" | grep "Public key:" | awk -F': ' '{print $2}')

    if [ -z "$PRIVATEKEY" ] || [ -z "$PUBLICKEY" ]; then
        log_error "生成密钥失败。输出内容: $output"
        exit 1
    fi

    # 不在日志中输出私钥
    log_info "Public Key: $PUBLICKEY"

    # 设置密钥的权限并保存到 CONFIG_DIR
    echo "$PRIVATEKEY" > "${CONFIG_DIR}/private.key"
    echo "$PUBLICKEY"  > "${CONFIG_DIR}/public.key"
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

# Prompt before overwriting an existing file
prompt_overwrite() {
    local file="$1"
    if [ -f "$file" ]; then
        while true; do
            read -p "文件 $file 已存在，是否覆盖？(y/n): " choice
            case "$choice" in
                y|Y ) return 0 ;;
                n|N )
                    log_info "跳过 $file 文件。"
                    return 1 ;;
                * )
                    log_error "无效的选择，请输入 y 或 n。"
                    ;;
            esac
        done
    else
        return 0
    fi
}

# 检查IPv6连接
check_ipv6() {
    if ping6 -c 1 -W 2 ipv6.google.com >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# 获取IPv6地址
get_ipv6() {
    local ipv6=$(curl -6 -sSL --connect-timeout 3 --retry 2 ip.sb || echo "null")
    # 如果上面的方法失败，尝试其他方式获取IPv6地址
    if [ -z "$ipv6" ]; then
        ipv6=$(ip -6 addr show scope global | grep -v temporary | grep -oP '(?<=inet6\s)[0-9a-f:]+(?=\/)')
    fi
    
    # 去除地址中可能的接口标识
    ipv6=$(echo "$ipv6" | head -n 1 | sed 's/%.*//g')
    echo "$ipv6"
}

 # 用于创建两种节点（IPv4和IPv6）
create_node_info() {
    local type=$1  # "ipv4"或"ipv6"
    local domain=$2  # 使用的域名
    
    for user_info in "${USER_INFO_LIST[@]}"; do
        local email
        local uuid
        email=$(echo "$user_info" | cut -d'|' -f1)
        uuid=$(echo "$user_info" | cut -d'|' -f2)

        local encoded_email
        encoded_email=$(urlencode "$email")

        local SUB_LINK
        SUB_LINK="vless://${uuid}@${domain}:${PORT}?encryption=none&security=reality&pbk=${PUBLICKEY}&sid=${SHORTID}&flow=${FLOW}&sni=${SNI}&fp=${FINGERPRINT}&type=${NETWORK}#${encoded_email}_${type}"

        local COUNTRY
        COUNTRY=$(get_country)
        local CREATE_TIME
        CREATE_TIME=$(date +"%Y-%m-%dT%H:%M:%S")
        local EXPIRE_DATE_FORMATTED="$EXPIRE_DATE_ISO"

        local node_info_json
        node_info_json=$(jq -n \
            --arg user "$email" \
            --arg id "$uuid" \
            --arg expire "$EXPIRE_DATE_FORMATTED" \
            --arg subscription "$SUB_LINK" \
            --arg country "$COUNTRY" \
            --arg server "$DOMAIN_NAME" \
            --arg updateDate "$CREATE_TIME" \
            --arg uid "$URL_ID" \
            --arg type "$type" \
            '{
                user: $user,
                id: $id,
                expire: $expire,
                subscription: $subscription,
                country: $country,
                server: $server,
                updateDate: $updateDate,
                uid: $uid,
                type: $type
            }')
        NODE_INFO_LIST+=("$node_info_json")
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
    # CPU、内存限制在 main() 中全局设置，这里可直接引用
    local CPU_LIMIT="$CPU_LIMIT"
    local MEMORY_LIMIT="$MEMORY_LIMIT"

    # 解析 JSON 文件
    USERS=$(jq -r '.u' "$CONFIG_FILE")
    PORT=$(jq -r '.p' "$CONFIG_FILE")
    URL_ID=$(jq -r '.i' "$CONFIG_FILE")
    EXPIRE_DATE=$(jq -r '.e' "$CONFIG_FILE")
    REGION_VAR=$(jq -r '.r' "$CONFIG_FILE")
    local DOMAIN_NAME
    DOMAIN_NAME=$(jq -r '.s' "$CONFIG_FILE")  # 从 JSON 文件中读取 "s"
    USERS="${USERS}.${DOMAIN_NAME}@taoziyoyo.com"
    
    # 获取 "u" 字段的值，用于目录名
    local u
    u=$(jq -r '.u' "$CONFIG_FILE")
    local s
    s=$(jq -r '.s' "$CONFIG_FILE")

    # 添加域名后缀 (保持原逻辑)
    DOMAIN_SUFFIX="o9drrm5l1d7uopaguucnxohzc3ul2yazxrldzpuoduu.taoziyoyo.com"
    local DOMAIN_NAME_FULL="${DOMAIN_NAME}${DOMAIN_SUFFIX}"

    # 验证 USERS
    if [ -z "$USERS" ]; then
        log_error "必须指定用户列表，在配置文件中指定。"
        exit 1
    fi

    # 验证域名
    if [ -z "$DOMAIN_NAME_FULL" ]; then
        log_error "必须指定域名，在配置文件中指定。"
        exit 1
    fi

    if echo "$DOMAIN_NAME_FULL" | grep -q '@'; then
        log_error "域名不能包含 '@' 符号，请提供有效的域名。"
        exit 1
    fi

    # 将 USERS 转换为数组
    IFS=',' read -ra USER_ARRAY <<< "$USERS"

    # 验证或生成端口
    if [ -z "$PORT" ]; then
        PORT=$(generate_random_port)
    else
        if ! echo "$PORT" | grep -qE '^[0-9]{5}$' || [ "$PORT" -le 20000 ]; then
            log_error "参数 PORT 必须是5位大于20000的端口号。"
            exit 1
        fi
        if is_port_in_use "$PORT"; then
            log_error "端口号 $PORT 已在使用中。"
            exit 1
        fi
    fi

    # 验证或生成 URL_ID
    if [ -n "$URL_ID" ]; then
        if ! echo "$URL_ID" | grep -qE '^[A-Z0-9]{8}$'; then
            log_error "URL ID 必须是8位大写字母和数字的组合。"
            exit 1
        fi
    else
        URL_ID=$(generate_url_id)
    fi

    # 验证 REGION
    local REGION="${REGION_VAR:-TESTUS}"
    if ! echo "$REGION" | grep -qE '^[A-Z]{6}$'; then
        log_error "参数 REGION 必须是6位大写英文字母。"
        exit 1
    fi

    # 设置 CONTAINER_NAME
    CONTAINER_NAME="reality_${REGION}_${URL_ID}"

    # 设置数据目录
    local BASE_DIR="/opt/docker/reality/nodeInfo"
    
    local CONFIG_DIR="${BASE_DIR}/reality_${u}_${s}"
    mkdir -p "${CONFIG_DIR}/log"
    
    if [ $? -ne 0 ]; then
        log_error "无法创建目录：${CONFIG_DIR}/log"
        return 1
    fi

    #-------------------------------------------
    # 检测目录下是否已有完整配置文件
    # 若同时存在 users.json / private.key / public.key / config.json，
    # 则提示用户是否复用。若选择Y或回车，则复用；否则重新生成
    #-------------------------------------------
    local REUSE_EXISTING="false"
    if [ -f "${CONFIG_DIR}/users.json" ] && \
       [ -f "${CONFIG_DIR}/private.key" ] && \
       [ -f "${CONFIG_DIR}/public.key" ] && \
       [ -f "${CONFIG_DIR}/config.json" ]; then
        # 提示用户选择
        echo -n "检测到 ${CONFIG_DIR} 下已有完整配置文件，是否使用现有配置？ [Y/n]: "
        read -r reuse_choice
        # 兼容大小写与空输入
        if [ -z "$reuse_choice" ] || [[ "$reuse_choice" =~ ^[Yy]$ ]]; then
            REUSE_EXISTING="true"
            log_info "将复用已有配置文件。"
        else
            log_info "将重新生成配置文件。"
        fi
    fi

    # 处理过期日期
    # Improve date validation to check future dates
    if [ -n "$EXPIRE_DATE" ]; then
        if ! date -d "${EXPIRE_DATE}" +"%Y%m%d" &>/dev/null; then
            log_error "无效的日期格式，请使用 YYYYMMDD 格式，例如 20231231"
            return 1
        fi
        
        # Check if date is in the future
        current_date=$(date +"%Y%m%d")
        if [ "$EXPIRE_DATE" -lt "$current_date" ]; then
            log_error "过期日期已经过去，请提供未来的日期"
            return 1
        fi        
        EXPIRE_DATE_ISO=$(date -d "${EXPIRE_DATE}" -u +"%Y-%m-%dT%H:%M:%SZ")
    fi

    # 检查IPv6连接
    local HAS_IPV6=false
    local IPV6_ADDRESS=""
    if check_ipv6; then
        HAS_IPV6=true
        IPV6_ADDRESS=$(get_ipv6)
        if [ -n "$IPV6_ADDRESS" ]; then
            log_info "检测到IPv6地址: $IPV6_ADDRESS"
        else
            log_info "系统支持IPv6但无法获取有效地址，将只使用IPv4"
            HAS_IPV6=false
        fi
    fi

    if [ "$REUSE_EXISTING" = "false" ]; then
        #-------------------------------------------
        # 重新生成配置
        #-------------------------------------------

        # 先为每个用户生成 UUID
        USER_UUID_LIST=()
        USER_INFO_LIST=()
        for user in "${USER_ARRAY[@]}"; do
            local uuid
            uuid=$(uuidgen)
            if [ -z "$uuid" ]; then
                log_error "生成 UUID 失败。"
                exit 1
            fi

            # 构建用户 JSON
            local user_json
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

        # 写入到 users.json
        CLIENTS_JSON=$(printf '%s\n' "${USER_UUID_LIST[@]}" | jq -s '.')
        echo "$CLIENTS_JSON" > "${CONFIG_DIR}/users.json"
        chmod 600 "${CONFIG_DIR}/users.json"
        log_info "已生成 users.json，内容如下："
        jq . "${CONFIG_DIR}/users.json" | tee -a "$LOGFILE"

        # 生成新的 X25519 密钥
        local key_pair
        key_pair=$(generate_x25519_keys "${CONFIG_DIR}")
        PRIVATEKEY=$(echo "$key_pair" | cut -d'|' -f1)
        PUBLICKEY=$(echo "$key_pair" | cut -d'|' -f2)

        # 拷贝模板 config.json 到目标目录（请确保脚本所在目录下有 config.json）
        cp ./config.json "${CONFIG_DIR}/config.json"
        chmod 600 "${CONFIG_DIR}/config.json"

        # 生成随机 shortId
        SHORTID=$(head -c8 /dev/urandom | xxd -ps -c8)
    else
        #-------------------------------------------
        # 复用已有配置
        #-------------------------------------------
        # 读取 users.json 并转成 JSON
        CLIENTS_JSON=$(cat "${CONFIG_DIR}/users.json")
        # 分析已有的用户信息
        USER_INFO_LIST=()
        mapfile -t user_array_temp < <(echo "$CLIENTS_JSON" | jq -c '.[]')
        for entry in "${user_array_temp[@]}"; do
            local email
            local uuid
            email=$(echo "$entry" | jq -r '.user')
            uuid=$(echo "$entry" | jq -r '.id')
            USER_INFO_LIST+=("${email}|${uuid}")
        done

        # 读取 private.key / public.key
        PRIVATEKEY=$(cat "${CONFIG_DIR}/private.key")
        PUBLICKEY=$(cat "${CONFIG_DIR}/public.key")

        # 读取 config.json，获取 shortId
        SHORTID=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0]' "${CONFIG_DIR}/config.json")
        if [ -z "$SHORTID" ] || [ "$SHORTID" == "null" ]; then
            log_error "已存在的 config.json 中未发现 shortIds[0] 字段，无法复用。"
            exit 1
        fi
    fi

    #-------------------------------------------
    # 以下保持原逻辑：更新 config.json、启动容器
    #-------------------------------------------
    NETWORK="tcp"
    DEST="www.apple.com:443"
    SERVERNAMES="www.apple.com images.apple.com"

    local SERVERNAMES_JSON
    SERVERNAMES_JSON=$(echo "$SERVERNAMES" | jq -R 'split(" ")')

    SNI="www.apple.com"
    FINGERPRINT="chrome"
    FLOW="xtls-rprx-vision"

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

    # 获取IPv4地址
    local ipv4
    ipv4=$(curl -4 -sSL --connect-timeout 3 --retry 2 ip.sb || echo "null")
    
    # 准备Docker运行的端口映射参数
    local port_mappings="-p $ipv4:$PORT:443"
    
    # 如果有IPv6地址，添加IPv6端口映射
    if [ "$HAS_IPV6" = true ] && [ -n "$IPV6_ADDRESS" ]; then
        port_mappings="$port_mappings -p $IPV6_ADDRESS:$PORT:443"
    fi

    log_info "正在启动 Docker 容器：$CONTAINER_NAME"
    # 检查容器是否已存在，如果存在则先移除
    if docker ps -a --filter "name=$CONTAINER_NAME" --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        log_info "容器 $CONTAINER_NAME 已存在，正在移除..."
        docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1
    fi
    
    # 启动Docker容器，使用准备好的端口映射参数
    docker run -d --name "$CONTAINER_NAME" \
      --restart=always \
      --log-opt max-size=50m \
      --cpus="$CPU_LIMIT" \
      --memory="$MEMORY_LIMIT" \
      $port_mappings \
      -e EXTERNAL_PORT="$PORT" \
      --env REGION="$REGION" \
      --env URL_ID="$URL_ID" \
      -v "${CONFIG_DIR}/config.json:/config.json:ro" \
      -v "${CONFIG_DIR}/users.json:/users.json:ro" \
      -v "${CONFIG_DIR}/log:/var/log/xray" \
      "$IMAGE_NAME"

    if [ $? -ne 0 ]; then
        log_error "启动 Docker 容器失败。"
        exit 1
    fi

    # 检查容器状态
    sleep 3
    local CONTAINER_STATUS
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

    #-------------------------------------------
    # 生成 nodeInfo-<n>.json（始终重新生成）
    #-------------------------------------------
    NODE_INFO_LIST=()

    # 创建IPv4节点信息
    create_node_info "ipv4" "${DOMAIN_NAME_FULL}"
    
    # 如果有IPv6，创建IPv6节点信息
    if [ "$HAS_IPV6" = true ] && [ -n "$IPV6_ADDRESS" ]; then
        create_node_info "ipv6" "${DOMAIN_NAME_FULL}"
    fi

    local NODE_INFO_FILENAME="nodeInfo-${s}.json"
    local NODE_INFO_JSON
    NODE_INFO_JSON=$(printf '%s\n' "${NODE_INFO_LIST[@]}" | jq -s '.')
    echo "$NODE_INFO_JSON" > "${CONFIG_DIR}/${NODE_INFO_FILENAME}"

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

    # 放入共享卷
    docker run --rm \
        -v shared-data:/node-data \
        -v "${CONFIG_DIR}:/config" \
        busybox sh -c "mkdir -p /node-data/node-info/${u} && cp /config/${NODE_INFO_FILENAME} /node-data/node-info/${u}/${NODE_INFO_FILENAME} && chmod 600 /node-data/node-info/${u}/${NODE_INFO_FILENAME}"

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
    install_xxd

    setup_data_directory

    # 初始化变量，设置默认值
    CPU_LIMIT="0.5"     # 默认 CPU 限制
    MEMORY_LIMIT="300m" # 默认内存限制
    CONFIG_FILE=""
    DIRECTORY=""

    # 使用 getopts 解析命令行参数
    while getopts "f:d:h" opt; do
        case $opt in
            f) CONFIG_FILE="$OPTARG";;
            d) DIRECTORY="$OPTARG";;
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
    local TIMESTAMP
    TIMESTAMP=$(date +"%Y%m%d%H%M%S")
    local IMAGE_BASE_NAME="vless_reality"
    local NEW_VERSION
    NEW_VERSION=$(get_latest_version "$IMAGE_BASE_NAME")
    local IMAGE_VERSION="v${NEW_VERSION}_${TIMESTAMP}"
    local IMAGE_NAME="${IMAGE_BASE_NAME}:${IMAGE_VERSION}"

    # 添加构建 Docker 镜像的提示
    read -p "是否生成新的 Docker 镜像？(y/n): " build_choice
    if [[ "$build_choice" =~ ^[Yy]$ ]]; then
        log_info "正在构建 Docker 镜像：$IMAGE_NAME"
        docker build -t "$IMAGE_NAME" .
        if [ $? -ne 0 ]; then
            log_error "Docker 镜像构建失败。"
            exit 1
        fi
    else
        log_info "跳过 Docker 镜像构建，使用现有镜像。"
        local EXISTING_IMAGE
        EXISTING_IMAGE=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep "^${IMAGE_BASE_NAME}:" | head -n1)
        if [ -z "$EXISTING_IMAGE" ]; then
            log_error "没有找到现有的镜像，请先构建一个。"
            exit 1
        else
            IMAGE_NAME="$EXISTING_IMAGE"
            log_info "使用现有的镜像：$IMAGE_NAME"
        fi
    fi

    # 确保X25519密钥生成容器已经启动
    log_info "预先启动X25519密钥生成容器..."
    local CONTAINER_NAME="xray-x25519"
    
    # 如果容器已存在但未运行，先删除它
    if docker ps -a --filter "name=${CONTAINER_NAME}" --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$" && \
       ! docker ps --filter "name=${CONTAINER_NAME}" --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        log_info "密钥生成容器 '${CONTAINER_NAME}' 存在但未运行，正在移除..."
        docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1
    fi
    
    # 如果容器不存在或不在运行，创建并启动它
    if ! check_container_running "${CONTAINER_NAME}"; then
        log_info "正在创建和启动密钥生成容器 '${CONTAINER_NAME}'..."
        docker run -d --name "${CONTAINER_NAME}" --rm \
            --memory="180m" --memory-swap="200m" --cpus="0.5" \
            teddysun/xray tail -f /dev/null
            
        if [ $? -ne 0 ]; then
            log_error "无法创建密钥生成容器 '${CONTAINER_NAME}'。"
            exit 1
        fi
        
        # 等待容器完全启动
        log_info "等待密钥生成容器启动..."
        local wait_count=0
        while ! docker exec "${CONTAINER_NAME}" echo "Container is ready" >/dev/null 2>&1; do
            sleep 1
            wait_count=$((wait_count + 1))
            if [ $wait_count -ge 30 ]; then
                log_error "等待容器启动超时，请检查Docker状态。"
                exit 1
            fi
        done
        log_info "密钥生成容器已启动并准备就绪。"
    else
        log_info "密钥生成容器 '${CONTAINER_NAME}' 已在运行中。"
    fi
    
    # 验证容器是否能正常生成密钥
    log_info "测试容器是否能正常生成密钥..."
    if ! docker exec "${CONTAINER_NAME}" xray x25519 >/dev/null 2>&1; then
        log_error "密钥生成容器无法正常生成密钥，请检查容器状态。"
        exit 1
    fi
    log_info "密钥生成容器工作正常。"
    
    if [ -n "$DIRECTORY" ]; then
        # 检查目录是否存在
        if [ ! -d "$DIRECTORY" ]; then
            log_error "目录 $DIRECTORY 不存在。"
            exit 1
        fi
        # 批量处理目录下的 JSON 文件
        for CF in "$DIRECTORY"/*.json; do
            if [ -f "$CF" ]; then
                log_info "正在处理配置文件: $CF"
                process_config_file "$CF"
                if [ $? -ne 0 ]; then
                    log_error "处理配置文件 $CF 失败，继续处理下一个文件。"
                    continue
                fi
            fi
        done
    elif [ -n "$CONFIG_FILE" ]; then
        # 检查配置文件是否存在
        if [ ! -f "$CONFIG_FILE" ]; then
            log_error "配置文件 $CONFIG_FILE 不存在。"
            exit 1
        fi
        log_info "正在处理配置文件: $CONFIG_FILE"
        process_config_file "$CONFIG_FILE"
    else
        log_error "必须指定配置文件 (-f) 或目录 (-d)。"
        show_help
        exit 1
    fi

    log_info "操作成功完成。"
}

# 执行主函数
main "$@"
