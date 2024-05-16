#!/bin/bash

docker build -t vless_reality:v1 .

# 输入并验证 DAY_COUNT
read -p "请输入天数 (1-30): " DAY_COUNT
if [[ -z "$DAY_COUNT" ]]; then
    DAY_COUNT=""
elif ! [[ "$DAY_COUNT" =~ ^[1-9]$|^[12][0-9]$|^30$ ]]; then
    echo "输入无效，天数必须在 1-30 之间的数字。"
    exit 1
fi

# 输入并验证 MONTH_COUNT
read -p "请输入月数: " MONTH_COUNT
if [[ -z "$MONTH_COUNT" ]]; then
    MONTH_COUNT=""
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
    echo "输入无效，外部端口号不能为空。"
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
docker-compose up -d
