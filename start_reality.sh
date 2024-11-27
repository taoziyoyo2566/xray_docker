#!/bin/bash
set -e  # 当发生错误时立即退出
#set -u  # 暂时注释掉，防止因未定义变量导致脚本退出
set -o pipefail  # 管道中任一命令失败，则整个管道失败
set -x  # 启用调试模式

# 日志函数
log_info() {
    echo -e "\033[32m[INFO]\033[0m $1"
}

log_warning() {
    echo -e "\033[33m[WARNING]\033[0m $1"
}

log_error() {
    echo -e "\033[31m[ERROR]\033[0m $1"
}

# 显示帮助信息的函数
show_help() {
    echo "Usage: $0 [-u URL_ID] [-p PORT] [-r REGION] [-d DAYS] [-m MONTHS] [-c CPU_LIMIT] [-M MEMORY_LIMIT]"
    echo
    echo "Options:"
    echo "  -u URL_ID        Set the URL_ID (8 alphanumeric characters)"
    echo "  -p PORT          Set the port number (5 digits, >20000)"
    echo "  -r REGION        Set the REGION (6 uppercase letters)"
    echo "  -d DAYS          Set the number of days"
    echo "  -m MONTHS        Set the number of months"
    echo "  -c CPU_LIMIT     Set the CPU limit (e.g., 0.5)"
    echo "  -M MEMORY_LIMIT  Set the memory limit (e.g., 300m)"
    echo "  -h               Show help"
}

# 检查所需软件是否安装的函数
check_required_software() {
    local software_list=("docker" "qrencode" "jq" "git" "curl" "netstat")
    for software in "${software_list[@]}"; do
        if ! command -v "$software" &> /dev/null; then
            log_error "$software 未安装，请先安装。"
            exit 1
        else
            log_info "$software 已安装。"
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

# 生成包含大写字母的随机 URL_ID
generate_url_id() {
    local id
    id=$(tr -dc 'A-Z0-9' </dev/urandom | head -c8)
    echo "$id"
}

# 随机生成一个不在使用中的端口号
generate_random_port() {
    local port
    while true; do
        port=$((RANDOM % 45536 + 20000))
        if [ $port -le 65535 ] && ! is_port_in_use $port; then
            echo $port
            return
        fi
    done
}

# 获取最新版本号和创建时间函数
get_latest_version_and_time() {
    local base_name="$1"
    local latest_image_info
    latest_image_info=$(docker images --format "{{.Repository}}:{{.Tag}} {{.CreatedAt}}" $base_name | sort -r | head -n 1)
    if [[ -z "$latest_image_info" ]]; then
        echo ""
    else
        local latest_version latest_time
        latest_version=$(echo $latest_image_info | awk '{print $1}' | cut -d ':' -f 2)
        latest_time=$(echo $latest_image_info | awk '{print $2, $3, $4, $5, $6}')
        echo "$latest_version $latest_time"
    fi
}

# 主函数
main() {
    check_required_software

    # 初始化变量，设置默认值
    URL_ID=""
    PORT=""
    DAY_COUNT=""
    MONTH_COUNT=""
    REGION=""
    CPU_LIMIT="0.5" # Default CPU limit (0.5 cores)
    MEMORY_LIMIT="300m" # Default memory limit (300 MB)

    # 使用 getopts 解析命令行参数
    while getopts "u:p:r:d:m:c:M:h" opt; do
      case $opt in
        u) URL_ID="$OPTARG";;
        p) PORT="$OPTARG";;
        r) REGION="$OPTARG";;
        d) DAY_COUNT="$OPTARG";;
        m) MONTH_COUNT="$OPTARG";;
        c) CPU_LIMIT="$OPTARG";;
        M) MEMORY_LIMIT="$OPTARG";;
        h)
          show_help
          exit 0;;
        *)
          log_error "未知的选项: -$opt"
          show_help
          exit 1;;
      esac
    done

    # 设置默认值
    URL_ID="${URL_ID:-$(generate_url_id)}"
    PORT="${PORT:-$(generate_random_port)}"
    REGION="${REGION:-TESTUS}"

    # 验证 URL_ID
    if ! [[ "$URL_ID" =~ ^[A-Z0-9]{8}$ ]]; then
        log_error "参数 URL_ID 必须是8位大写英数字。"
        exit 1
    fi

    # 验证 PORT
    if ! [[ "$PORT" =~ ^[0-9]{5}$ ]] || [ "$PORT" -le 20000 ]; then
        log_error "参数 PORT 必须是5位大于20000的端口号。"
        exit 1
    fi

    if is_port_in_use $PORT; then
        log_error "端口号 $PORT 已在使用中。"
        exit 1
    fi

    # 验证 REGION
    if ! [[ "$REGION" =~ ^[A-Z]{6}$ ]]; then
        log_error "参数 REGION 必须是6位大写英文字母。"
        exit 1
    fi

    log_info "URL_ID: $URL_ID"
    log_info "PORT: $PORT"
    log_info "REGION: $REGION"

    BASE_IMAGE_NAME="reality"
    LATEST_INFO=$(get_latest_version_and_time $BASE_IMAGE_NAME)

    if [[ -n "$LATEST_INFO" ]]; then
        LATEST_VERSION=$(echo $LATEST_INFO | awk '{print $1}')
        LATEST_TIME=$(echo $LATEST_INFO | awk '{print $2, $3, $4, $5, $6}')
        log_info "最新镜像版本: $LATEST_VERSION"
        log_info "制作时间: $LATEST_TIME"
    else
        log_warning "没有找到最新镜像的信息。"
    fi

    # 提示是否重新打包一个镜像
    read -p "是否重新打包一个镜像？(Y/N): " REPACK
    if [[ "$REPACK" == "Y" || "$REPACK" == "y" ]]; then
        NEW_VERSION="v$(date +%Y%m%d%H%M%S)"
        IMAGE_NAME="${BASE_IMAGE_NAME}:${NEW_VERSION}"
        log_info "构建新的镜像 $IMAGE_NAME ..."
        docker build -t $IMAGE_NAME ./reality
        if [[ $? -ne 0 ]]; then
            log_error "镜像构建失败。"
            exit 1
        fi
    else
        if [[ -z "$LATEST_VERSION" ]]; then
            log_error "没有可用的镜像。请先构建一个镜像。"
            exit 1
        fi
        IMAGE_NAME="reality:${LATEST_VERSION}"
        log_info "使用现有的最新镜像 $IMAGE_NAME ..."
    fi

    EXTERNAL_PORT=$PORT

    log_info "######################## URL_ID: $URL_ID"

    # 启动 Docker 容器
    CONTAINER_NAME="reality_${REGION}_${URL_ID}"

    # 文件保存路径
    mkdir -p /opt/docker/reality/nodeInfo/${CONTAINER_NAME}/log

    # 构建 docker run 命令
    DOCKER_RUN_CMD="docker run -d --name $CONTAINER_NAME \
      --restart=always \
      --log-opt max-size=50m \
      --cpus=\"$CPU_LIMIT\" \
      --memory=\"$MEMORY_LIMIT\" \
      -p $EXTERNAL_PORT:443 \
      -e EXTERNAL_PORT=$EXTERNAL_PORT \
      --env REGION=${REGION} \
      --env DAY_COUNT=${DAY_COUNT} \
      --env MONTH_COUNT=${MONTH_COUNT} \
      --env URL_ID=${URL_ID} \
      -v /opt/docker/reality/nodeInfo/${CONTAINER_NAME}/log:/var/log/xray \
      $IMAGE_NAME"

    # 执行 docker run 命令
    eval $DOCKER_RUN_CMD

    # 等待容器启动并健康运行
    log_info "等待容器启动..."
    for i in {1..30}; do
        STATUS=$(docker inspect -f '{{.State.Status}}' $CONTAINER_NAME 2>/dev/null || echo "notfound")
        if [ "$STATUS" == "running" ]; then
            log_info "容器已启动。"
            break
        else
            sleep 1
        fi
    done

    # 检查是否成功启动
    if [ "$STATUS" != "running" ]; then
        log_error "容器启动失败。"
        exit 1
    fi

    # 等待应用程序准备就绪
    sleep 5

    # 提取容器内的 JSON 文件对象值并生成二维码
    log_info "从容器中提取 JSON 文件对象值并生成二维码..."

    # 获取容器 ID 或名称
    log_info "容器 ID 或名称: $CONTAINER_NAME"
    log_info "端口: $EXTERNAL_PORT"

    # 提取 JSON 对象值
    docker cp ${CONTAINER_NAME}:/vless_info.json /opt/docker/reality/nodeInfo/${CONTAINER_NAME}/ > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        log_error "未能从容器中提取 vless_info.json 文件。"
        exit 1
    fi

    JSON_OUTPUT=$(cat /opt/docker/reality/nodeInfo/${CONTAINER_NAME}/vless_info.json)
    if [[ -z "$JSON_OUTPUT" ]]; then
        log_error "vless_info.json 文件为空。"
        exit 1
    fi

    URL_OUTPUT=$(echo "$JSON_OUTPUT" | jq -r '.URL_IPV4')
    if [[ -z "$URL_OUTPUT" ]]; then
        log_error "未找到有效的 URL。"
        exit 1
    fi

    echo "link"
    echo "$URL_OUTPUT"

    echo "QR CODE"
    echo "$URL_OUTPUT" | qrencode -o - -t UTF8

    # 将二维码保存到文件
    echo "$URL_OUTPUT" | qrencode -o /opt/docker/reality/nodeInfo/${CONTAINER_NAME}/qrcode.png

    if [ $? -eq 0 ]; then
      log_info "操作成功完成。"
      log_info "运行以下命令以修改日志文件的权限："
      echo "sudo chown -R $(whoami):$(whoami) /opt/docker/reality/nodeInfo/${CONTAINER_NAME}"
    else
      log_error "操作失败。"
    fi
}

# 执行主函数
main "$@"
