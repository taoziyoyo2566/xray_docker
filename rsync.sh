#!/bin/bash
set -o pipefail

# 定义固定的日志文件名
LOGFILE="rsync.log"

# 日志函数，将输出重定向到日志文件和标准错误，并添加时间戳
log_info() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" | tee -a "$LOGFILE" >&2
}

log_error() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" | tee -a "$LOGFILE" >&2
}

# 显示帮助信息的函数，使用 log_info 输出
show_help() {
    log_info "Usage: $0 -s server1,server2,server3"
    log_info ""
    log_info "Options:"
    log_info "  -s|--server       设置源服务器列表，用逗号分隔 (必需)"
    log_info "  -h|--help         显示帮助信息"
}

# Function to generate a random port number greater than 20000
generate_random_port() {
    echo $((20000 + RANDOM % 45535))
}

# Function to generate a random 8-character alphanumeric string
generate_random_id() {
    tr -dc 'A-Z0-9' </dev/urandom | head -c 8
}

# Function to calculate the expiration date one year from today
calculate_expiration_date() {
    date -d "+1 year" +%Y%m%d
}

# Function to dynamically get source server's reality directories
get_reality_dirs() {
    local server=$1
    ssh $SSH_OPTS "$server" "find /opt/docker/reality/nodeInfo/ -maxdepth 1 -type d -name 'reality_*' -printf '%f\n'"
}

# 解析命令行参数
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -s|--server)
            IFS=',' read -ra SOURCE_SERVERS <<< "$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            log_error "未知的选项: $1"
            show_help
            exit 1
            ;;
    esac
done

# 检查是否提供了服务器列表
if [ ${#SOURCE_SERVERS[@]} -eq 0 ]; then
    log_error "请通过 -s 参数指定源服务器列表，例如：$0 -s server1,server2,server3"
    exit 1
fi

# 定义同步的目标目录
TARGET_DIR="/opt/docker/reality/nodeInfo/"

# 定义 SSH 密钥文件
SSH_KEY="$HOME/.ssh/id_rsa"
SSH_OPTS="-o ConnectTimeout=10 -i $SSH_KEY"

# 定义 rsync 超时时间
RSYNC_TIMEOUT=30

# 检查本地是否安装 rsync
if ! command -v rsync >/dev/null 2>&1; then
    log_error "本地未安装 rsync，请先安装 rsync。"
    exit 1
fi

# 检查本地是否有 SSH 密钥文件
if [ ! -f "$SSH_KEY" ]; then
    log_error "SSH 密钥文件不存在: $SSH_KEY"
    exit 1
fi

# 循环遍历每个源服务器进行同步
for SERVER in "${SOURCE_SERVERS[@]}"; do
    log_info "开始从 $SERVER 同步数据到 $TARGET_DIR ..."

    # 检查远程服务器是否安装 rsync
    ssh $SSH_OPTS "$SERVER" "command -v rsync &>/dev/null"
    if [ $? -ne 0 ]; then
        log_error "远程服务器 $SERVER 未安装 rsync 或路径错误，请检查。"
        continue
    fi

    # 动态获取目录列表
    SYNC_SUBDIRS=($(get_reality_dirs "$SERVER"))
    if [ ${#SYNC_SUBDIRS[@]} -eq 0 ]; then
        log_info "未从 $SERVER 检测到匹配的子目录。"
        continue
    fi

    # 遍历子目录
    for SUBDIR in "${SYNC_SUBDIRS[@]}"; do
        log_info "同步 $SERVER 的目录 $SUBDIR..."

        # 使用 rsync 同步特定的 JSON 文件
        rsync_output=$(rsync -avz --progress --timeout=$RSYNC_TIMEOUT -e "ssh $SSH_OPTS" \
            --include="$SUBDIR/" \
            --include="*.json" \
            --exclude="*" \
            "$SERVER:/opt/docker/reality/nodeInfo/" \
            "$TARGET_DIR" 2>&1)

        rsync_exit_code=$?

        if [ $rsync_exit_code -eq 0 ]; then
            log_info "成功从 $SERVER 的 $SUBDIR 同步数据。"
            log_info "rsync 输出:\n$rsync_output"
        else
            log_error "从 $SERVER 的 $SUBDIR 同步数据时出错。"
            log_error "rsync 错误输出:\n$rsync_output"
        fi
    done

    log_info "$SERVER rsync 完成。"
done

log_info "所有服务器同步任务完成！"