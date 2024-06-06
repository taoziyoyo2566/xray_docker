#!/bin/bash

# Function to check if the software is installed
# Array of software names to check
SOFTWARE_LIST=("docker" "qrencode" "jq" "git" "curl")

# Function to check if software is installed
check_software() {
    local software_name=$1  # Get the software name from the function argument

    if command -v "$software_name" &> /dev/null; then
        echo "$software_name is installed."
    else
        echo "$software_name is not installed."
        exit 1
    fi
}

# Loop through the list and check each software
for software_name in "${SOFTWARE_LIST[@]}"; do
    check_software "$software_name"
done

# 检查端口是否在使用中
is_port_in_use() {
    local port=$1
    if netstat -tuln | grep ":$port\b" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# 随机生成一个不在使用中的端口号
generate_random_port() {
    while true; do
        port=$((RANDOM + 20000))
        if [ $port -le 65535 ] && ! is_port_in_use $port; then
            echo $port
            return
        fi
    done
}

# Initialize variables with default values
URL_ID=$(openssl rand -hex 4 | tr -d '\n')
PORT=$(generate_random_port)
DAY_COUNT=""
MONTH_COUNT=""
REGION="TTUS"  # Default region

# Parse command-line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -e)
            shift
            case $1 in
                URL_ID=*)
                URL_ID="${1#URL_ID=}"
                ;;
                PORT=*)
                PORT="${1#PORT=}"
                ;;
                DAYS=*)
                DAY_COUNT="${1#DAYS=}"
                ;;
                MONTHS=*)
                MONTH_COUNT="${1#MONTHS=}"
                ;;
                REGION=*)
                REGION="${1#REGION=}"
                ;;
                *)
                echo "Unknown environment variable $1"
                exit 1
                ;;
            esac
            ;;
        *)
        echo "Unknown option $1"
        exit 1
        ;;
    esac
    shift
done

# Validate URL_ID
if ! [[ "$URL_ID" =~ ^[A-Za-z0-9]{8}$ ]]; then
    echo "错误：参数 URL_ID 必须是8位英数字。"
    exit 1
fi

# Validate PORT
if ! [[ "$PORT" =~ ^[0-9]{5}$ ]] || [ "$PORT" -le 20000 ]; then
    echo "错误：参数 PORT 必须是5位大于20000的端口号。"
    exit 1
fi

if is_port_in_use $PORT; then
    echo "错误：端口号 $PORT 已在使用中。"
    exit 1
fi

# Validate REGION
if ! [[ "$REGION" =~ ^[A-Za-z]{4}$ ]]; then
    echo "错误：参数 REGION 必须是4位英文字母。"
    exit 1
fi

echo "URL_ID: $URL_ID"
echo "PORT: $PORT"
echo "REGION: $REGION"

# 获取最新版本号和创建时间函数
get_latest_version_and_time() {
    local base_name="$1"
    local latest_image_info=$(docker images --format "{{.Repository}}:{{.Tag}} {{.CreatedAt}}" $base_name | sort -r | head -n 1)
    if [[ -z "$latest_image_info" ]]; then
        echo ""
    else
        local latest_version=$(echo $latest_image_info | awk '{print $1}' | cut -d ':' -f 2)
        local latest_time=$(echo $latest_image_info | awk '{print $2, $3, $4, $5, $6}')
        echo "$latest_version $latest_time"
    fi
}

# 计算新版本号函数
increment_version() {
    local version="$1"
    local major_version=$(echo $version | cut -d '.' -f 1)
    local minor_version=$(echo $version | cut -d '.' -f 2)
    minor_version=$((minor_version + 1))
    echo "${major_version}.${minor_version}"
}

BASE_IMAGE_NAME="reality"
LATEST_INFO=$(get_latest_version_and_time $BASE_IMAGE_NAME)

if [[ -n "$LATEST_INFO" ]]; then
    LATEST_VERSION=$(echo $LATEST_INFO | awk '{print $1}')
    LATEST_TIME=$(echo $LATEST_INFO | awk '{print $2, $3, $4, $5, $6}')
    echo "最新镜像版本: $LATEST_VERSION"
    echo "制作时间: $LATEST_TIME"
else
    echo "没有找到最新镜像的信息。"
fi

# 提示是否重新打包一个镜像
read -p "是否重新打包一个镜像？(Y/N): " REPACK
if [[ "$REPACK" == "Y" || "$REPACK" == "y" ]]; then
    if [[ -z "$LATEST_VERSION" ]]; then
        NEW_VERSION="v1.0"
    else
        NEW_VERSION="v$(increment_version ${LATEST_VERSION#v})"
    fi

    IMAGE_NAME="${BASE_IMAGE_NAME}:${NEW_VERSION}"
    echo "构建新的镜像 $IMAGE_NAME ..."
    docker build -t $IMAGE_NAME ./reality
    if [[ $? -ne 0 ]]; then
        echo "镜像构建失败。"
        exit 1
    fi
else
    if [[ -z "$LATEST_VERSION" ]]; then
        echo "没有可用的镜像。请先构建一个镜像。"
        exit 1
    fi
    IMAGE_NAME="reality:${LATEST_VERSION}"
    echo "使用现有的最新镜像 $IMAGE_NAME ..."
fi

# 输入并验证 EXTERNAL_PORT
EXTERNAL_PORT=$PORT

# 设置 URL_ID
echo "######################## URL_ID: $URL_ID"
# 启动 Docker 容器
CONTAINER_NAME="reality_${REGION}_${URL_ID}"

# 构建 docker run 命令
DOCKER_RUN_CMD="docker run -d --name $CONTAINER_NAME --restart=always --log-opt max-size=50m --cpus=\"0.5\" --cpu-shares=512 -m=300m -p $EXTERNAL_PORT:443 -e EXTERNAL_PORT=$EXTERNAL_PORT --env REGION=${REGION} --env DAY_COUNT=${DAY_COUNT} --env MONTH_COUNT=${MONTH_COUNT} --env URL_ID=${URL_ID} $IMAGE_NAME"

# 执行 docker run 命令
eval $DOCKER_RUN_CMD

# 等待容器启动完成
sleep 5  # 等待容器内的服务启动

# 提取容器内的 JSON 文件对象值并生成二维码
echo "从容器中提取 JSON 文件对象值并生成二维码..."

# 获取容器 ID 或名称
echo "容器 ID 或名称: $CONTAINER_NAME"
echo "端口: $EXTERNAL_PORT"

# 提取 JSON 对象值（假设 JSON 文件中的 key 为 "url"）
JSON_OUTPUT=$(docker exec -it $CONTAINER_NAME sh -c "cat vless_info.json")
if [[ -z "$JSON_OUTPUT" ]]; then
    echo "未能从容器中提取 JSON 文件。"
    exit 1
fi

URL_OUTPUT=$(echo "$JSON_OUTPUT" | jq -r '.URL_IPV4')
if [[ -z "$URL_OUTPUT" ]]; then
    echo "未找到有效的 URL。"
    exit 1
fi

echo "$URL_OUTPUT"
echo "$URL_OUTPUT" | qrencode -o - -t UTF8

mkdir -p /opt/docker/reality/nodeInfo/${CONTAINER_NAME}
docker cp ${CONTAINER_NAME}:vless_info.json /opt/docker/reality/nodeInfo/${CONTAINER_NAME}/
cat /opt/docker/reality/nodeInfo/${CONTAINER_NAME}/vless_info.json
echo "二维码生成完毕。"
