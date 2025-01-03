#!/bin/bash
set -e  # 遇到错误立即退出
set -o pipefail  # 管道命令中的错误也会导致脚本退出

# 定义日志相关路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
LOG_DIR="${SCRIPT_DIR}/logs"
LOGFILE="${LOG_DIR}/rsync_$(date '+%Y%m%d').log"

# 确保日志目录存在
mkdir -p "$LOG_DIR"

# 日志函数
log_info() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" | tee -a "$LOGFILE" >&2
}

log_error() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" | tee -a "$LOGFILE" >&2
}

# 显示帮助信息
show_help() {
    log_info "Usage: $0 -s server1,server2,server3"
    log_info "Options:"
    log_info "  -s|--server       设置目标服务器列表，用逗号分隔 (必需)"
    log_info "  -h|--help         显示帮助信息"
}

# 解析命令行参数
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -s|--server)
            IFS=',' read -ra TARGET_SERVERS <<< "$2"
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
if [ ${#TARGET_SERVERS[@]} -eq 0 ]; then
    log_error "请通过 -s 参数指定目标服务器列表，例如：$0 -s server1,server2,server3"
    exit 1
fi

# 定义源目录和目标目录
SOURCE_DIR="/opt/docker/reality/nodeInfo/"
TARGET_DIR="/opt/docker/reality/nodeInfo/"
# 定义备份目录
BACKUP_DIR="/opt/docker/reality/nodeInfo_backup"

# 定义 SSH 参数
SSH_KEY="$HOME/.ssh/id_rsa"
SSH_OPTS="-o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -i $SSH_KEY"

# 基础检查
if ! command -v rsync >/dev/null 2>&1; then
    log_error "本地未安装 rsync，请先安装 rsync。"
    exit 1
fi

if [ ! -f "$SSH_KEY" ]; then
    log_error "SSH 密钥文件不存在: $SSH_KEY"
    exit 1
fi

if [ ! -d "$SOURCE_DIR" ]; then
    log_error "源目录不存在: $SOURCE_DIR"
    exit 1
fi

# 清理一个月前的日志文件
find "$LOG_DIR" -name "rsync_*.log" -mtime +30 -delete

# 循环遍历每个目标服务器进行同步
for SERVER in "${TARGET_SERVERS[@]}"; do
    log_info "开始向 $SERVER 同步数据..."

    # 检查远程服务器连接性和rsync
    if ! ssh $SSH_OPTS "$SERVER" "command -v rsync &>/dev/null"; then
        log_error "无法连接到服务器 $SERVER 或该服务器未安装 rsync"
        continue
    fi

    # 确保目标目录和备份目录存在
    if ! ssh $SSH_OPTS "$SERVER" "mkdir -p $TARGET_DIR $BACKUP_DIR"; then
        log_error "在服务器 $SERVER 上创建目录失败"
        continue
    fi

    # 在目标服务器上执行备份（排除log目录）
    BACKUP_NAME="nodeInfo_$(date '+%Y%m%d_%H%M%S').tar.gz"
    log_info "在服务器 $SERVER 上创建备份: $BACKUP_NAME"
    if ! ssh $SSH_OPTS "$SERVER" "cd $TARGET_DIR/.. && tar --exclude='*/log/*' -czf $BACKUP_DIR/$BACKUP_NAME nodeInfo/"; then
        log_error "在服务器 $SERVER 上创建备份失败"
        continue
    fi

    # 首先执行 rsync 的 dry-run 来检查将要更新的文件
    log_info "检查需要更新的文件..."
    rsync -ainv --timeout=30 -e "ssh $SSH_OPTS" \
        --exclude="*/log/*" \
        "$SOURCE_DIR" "$SERVER:$TARGET_DIR" 2>&1 | grep -v "^$" | tee -a "$LOGFILE"

    # 使用 rsync 同步文件，添加了一些优化参数
    if rsync -avz --timeout=30 -e "ssh $SSH_OPTS" \
        --exclude="*/log/*" \
        --checksum \
        "$SOURCE_DIR" "$SERVER:$TARGET_DIR" 2>&1 | tee -a "$LOGFILE"; then
        log_info "成功同步到 $SERVER"
    else
        log_error "同步到 $SERVER 失败"
    fi

    # 检查并清理旧备份（可选，保留最近30天的备份）
    log_info "清理超过30天的旧备份..."
    ssh $SSH_OPTS "$SERVER" "find $BACKUP_DIR -name '*.tar.gz' -mtime +30 -delete"
done

log_info "同步任务完成！"