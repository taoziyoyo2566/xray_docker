#!/bin/bash

# 获取最新版本号函数
get_latest_version() {
    local base_name="$1"
    local latest_version=$(docker images --format "{{.Tag}}" $base_name | sort -V | tail -n 1)
    echo "$latest_version"
}

# 计算新版本号函数
increment_version() {
    local version="$1"
    local major_version=$(echo $version | cut -d '.' -f 1)
    local minor_version=$(echo $version | cut -d '.' -f 2)
    minor_version=$((minor_version + 1))
    echo "${major_version}.${minor_version}"
}

# 提示是否重新打包一个镜像
read -p "是否重新打包一个镜像？(Y/N): " REPACK
if [[ "$REPACK" == "Y" || "$REPACK" == "y" ]]; then
    BASE_IMAGE_NAME="vless_reality"
    LATEST_VERSION=$(get_latest_version $BASE_IMAGE_NAME)
    
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
    LATEST_VERSION=$(get_latest_version "vless_reality")
    if [[ -z "$LATEST_VERSION" ]]; then
        echo "没有可用的镜像。请先构建一个镜像。"
        exit 1
    fi
    IMAGE_NAME="vless_reality:${LATEST_VERSION}"
    echo "使用现有的最新镜像 $IMAGE_NAME ..."
fi

# 输入并验证 DAY_COUNT
read -p "请输入天数 (1-30): " DAY_COUNT
if [[ -z "$DAY_COUNT" ]]; then
    echo "天数不能为空。退出。"
    exit 1
elif ! [[ "$DAY_COUNT" =~ ^[1-9]$|^[12][0-9]$|^30$ ]]; then
    echo "输入无效，天数必须在 1-30 之间的数字。"
    exit 1
fi

# 输入并验证 MONTH_COUNT
read -p "请输入月数: " MONTH_COUNT
if [[ -z "$MONTH_COUNT" ]]; then
    echo "月数不能为空。退出。"
    exit 1
elif ! [[ "$MONTH_COUNT" =~ ^[0-9]+$ ]]; then
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
if [[ -z "$EXTERNAL_PORT" ]]; then
    echo "输入无效，外部端口号不能为空。退出。"
    exit 1
elif ! [[ "$EXTERNAL_PORT" =~ ^[0-9]+$ ]] || [ "$EXTERNAL_PORT" -le 20000 ]; then
    echo "输入无效，外部端口号必须是20000以上的数字。"
    exit 1
fi

# 设置 URL_ID
URL_ID=$(openssl rand -hex 4 | tr -d '\n')

# 创建 .env 文件
cat <<EOF > .env
DAY_COUNT=$DAY_COUNT
MONTH_COUNT=$MONTH_COUNT
EXTERNAL_PORT=$EXTERNAL_PORT
REGION=$REGION
URL_ID=$URL_ID
EOF

# 启动 Docker Compose 服务
docker compose up -d

# 等待容器启动完成
sleep 10  # 等待容器内的服务启动

# 提取容器内的 JSON 文件对象值并生成二维码
echo "从容器中提取 JSON 文件对象值并生成二维码..."

# 获取容器 ID 或名称
CONTAINER_NAME="vless_reality_$URL_ID"

# 提取 JSON 对象值（假设 JSON 文件中的 key 为 "url"）
JSON_OUTPUT=$(docker exec -it $CONTAINER_NAME sh -c "cat vless_info.json")
VALUE=$(echo "$JSON_OUTPUT" | jq -r '.url')

if [[ -z "$VALUE" ]]; then
    echo "未找到有效的 URL。"
    exit 1
fi

# 生成二维码并显示
echo "$VALUE" | qrencode -o - -t UTF8

echo "二维码生成完毕。"
