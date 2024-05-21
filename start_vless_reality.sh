#!/bin/bash

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

BASE_IMAGE_NAME="vless_reality"
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
    IMAGE_NAME="vless_reality:${LATEST_VERSION}"
    echo "使用现有的最新镜像 $IMAGE_NAME ..."
fi

# 输入并验证 DAY_COUNT
read -p "请输入天数 (1-30): " DAY_COUNT
if [[ -n "$DAY_COUNT" && ! "$DAY_COUNT" =~ ^[1-9]$|^[12][0-9]$|^30$ ]]; then
    echo "输入无效，天数必须在 1-30 之间的数字。"
    exit 1
fi

# 输入并验证 MONTH_COUNT
read -p "请输入月数: " MONTH_COUNT
if [[ -n "$MONTH_COUNT" && ! "$MONTH_COUNT" =~ ^[0-9]+$ ]]; then
    echo "输入无效，月数必须是一个数字。"
    exit 1
fi

# 输入并验证 REGION
read -p "请输入区域 (默认为 US, 必须是2位英文字母): " REGION
if [[ -z "$REGION" ]]; then
    REGION="US"
elif ! [[ "$REGION" =~ ^[A-Za-z]{2}$ ]]; then
    echo "输入无效，区域必须是2位英文字母。"
    exit 1
fi

# 输入并验证 EXTERNAL_PORT
read -p "请输入外部端口号 (20000以上): " EXTERNAL_PORT
if [[ -z "$EXTERNAL_PORT" || ! "$EXTERNAL_PORT" =~ ^[0-9]+$ || "$EXTERNAL_PORT" -le 20000 ]]; then
    echo "输入无效，外部端口号必须是20000以上的数字。"
    exit 1
fi

# 设置 URL_ID
URL_ID=$(openssl rand -hex 4 | tr -d '\n')

# 启动 Docker 容器
CONTAINER_NAME="qreality_${REGION}_${URL_ID}"
docker run -d --name $CONTAINER_NAME --restart=always --log-opt max-size=50m --cpuset-cpus="0-1" --cpu-shares=512 -m=300m -p $EXTERNAL_PORT:443 -e EXTERNAL_PORT=$EXTERNAL_PORT --env DAY_COUNT=${DAY_COUNT} --env MONTH_COUNT=${MONTH_COUNT} --env REGION=${REGION} --env URL_ID=${URL_ID} $IMAGE_NAME

# 等待容器启动完成
sleep 5  # 等待容器内的服务启动

# 提取容器内的 JSON 文件对象值并生成二维码
echo "从容器中提取 JSON 文件对象值并生成二维码..."

# 获取容器 ID 或名称
echo "容器 ID 或名称: $CONTAINER_NAME"
echo "EXTERNAL_PORT: $EXTERNAL_PORT"
echo "DAY_COUNT: $DAY_COUNT"
echo "MONTH_COUNT: $MONTH_COUNT"

# JSON_OUTPUT=$(docker exec -it qreality_475eaf05 sh -c "cat vless_info.json")
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

echo "二维码生成完毕。"
