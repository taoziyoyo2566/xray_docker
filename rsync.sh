#!/bin/bash

# 定义同步的源服务器列表
SOURCE_SERVERS=("bwh" "alpha")

# 定义同步的目标目录
TARGET_DIR="/opt/docker/reality/nodeInfo/"

# 定义 SSH 密钥文件
SSH_KEY="$HOME/.ssh/id_rsa"
SSH_OPTS="-o ConnectTimeout=10 -i $SSH_KEY"

# 定义 rsync 超时时间
RSYNC_TIMEOUT=30

# 动态获取源服务器上的目录列表
get_reality_dirs() {
    local server=$1
    ssh $SSH_OPTS "$server" "find /opt/docker/reality/nodeInfo/ -maxdepth 1 -type d -name 'reality_*' -printf '%f\n'"
}

# 循环遍历每个源服务器进行同步
for SERVER in "${SOURCE_SERVERS[@]}"; do
    LOG_FILE="rsync_$SERVER_$(date +%F_%T).log"
    echo "开始从 $SERVER 同步数据到 $TARGET_DIR ..." | tee -a $LOG_FILE

    # 检查远程服务器是否安装 rsync
    ssh $SSH_OPTS "$SERVER" "command -v rsync &>/dev/null"
    if [ $? -ne 0 ]; then
        echo "远程服务器 $SERVER 未安装 rsync 或路径错误，请检查。" | tee -a $LOG_FILE
        continue
    fi

    # 动态获取目录列表
    SYNC_SUBDIRS=($(get_reality_dirs "$SERVER"))
    if [ ${#SYNC_SUBDIRS[@]} -eq 0 ]; then
        echo "未从 $SERVER 检测到匹配的子目录。" | tee -a $LOG_FILE
        continue
    fi

    # 遍历子目录
    for SUBDIR in "${SYNC_SUBDIRS[@]}"; do
        echo "同步 $SERVER 的目录 $SUBDIR..." | tee -a $LOG_FILE

        # 使用 rsync 同步特定的 JSON 文件
        rsync -avz --progress --timeout=$RSYNC_TIMEOUT -e "ssh $SSH_OPTS" \
            --include="$SUBDIR/" \
            --exclude="users.json" \
            --exclude="log" \
            --exclude="*.key" \
            --exclude="config.json" \
            "$SERVER:/opt/docker/reality/nodeInfo/" \
            "$TARGET_DIR" 2>&1 | tee -a $LOG_FILE

        if [ $? -eq 0 ]; then
            echo "成功从 $SERVER 的 $SUBDIR 同步数据。" | tee -a $LOG_FILE
        else
            echo "从 $SERVER 的 $SUBDIR 同步数据时出错。" | tee -a $LOG_FILE
        fi
    done
    echo "$SERVER rsync completed" | tee -a $LOG_FILE
done

echo "所有服务器同步任务完成！"