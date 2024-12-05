#!/bin/bash

# --------------------------------------------------
# execute_remote_commands.sh
# 通过 SSH 在多个远程服务器上并行执行指定的 Shell 命令，并集中记录日志
# --------------------------------------------------

# ----------------------------
# 函数定义
# ----------------------------

# 显示帮助信息
show_help() {
    echo "Usage: $0 -s server1:server_alias1 server2:server_alias2 [server3:server_alias3 ...]"
    echo ""
    echo "Options:"
    echo "  -s, --servers      指定远程服务器及其对应的 server_alias，格式为 server:alias，多服务器用空格分隔（必需）"
    echo "  -h, --help         显示此帮助信息"
    echo ""
    echo "Examples:"
    echo "  $0 -s alpha:alp beta:bet gamma:gam"
    echo "  $0 --servers alpha:alp beta:bet gamma:gam"
}

# 函数：在远程服务器上执行命令，并实时记录输出
execute_commands() {
    local SSH_ALIAS="$1"
    local SERVER_ALIAS="$2"
    local SERVER_INDEX="$3"
    local TOTAL_SERVERS="$4"

    echo "--------------------------------------------------" | tee -a remote_commands.log
    echo "[$SERVER_INDEX/$TOTAL_SERVERS] 正在连接到服务器: $SSH_ALIAS (Server Alias: $SERVER_ALIAS)" | tee -a remote_commands.log
    echo "--------------------------------------------------" | tee -a remote_commands.log

    # 定义要执行的命令，确保内部双引号被转义
    local COMMANDS="
cd workspace/xray_docker
echo '[$SSH_ALIAS] 进入 workspace/xray_docker 目录'

# 删除以 server_alias 开头的客户端目录
rm -rf client_${SERVER_ALIAS}_*
echo '[$SSH_ALIAS] 删除 client_${SERVER_ALIAS}_* 目录'
rm -rf /opt/docker/reality/nodeInfo/*
echo '[$SSH_ALIAS] 删除 /opt/docker/reality/nodeInfo/reality_* 目录'
# 更新代码库
git pull
echo '[$SSH_ALIAS] 执行 git pull'

# 执行 user_config.sh 脚本
echo '[$SSH_ALIAS] 执行 user_config.sh --transfer -s ${SERVER_ALIAS} -d client_spt_chatgpt_202412041334'
bash user_config.sh --transfer -s ${SERVER_ALIAS} -d client_spt_chatgpt_202412041334

echo '[$SSH_ALIAS] 执行 user_config.sh --transfer -s ${SERVER_ALIAS} -d client_spt_sub_202412041334'
bash user_config.sh --transfer -s ${SERVER_ALIAS} -d client_spt_sub_202412041334

echo '[$SSH_ALIAS] 执行 user_config.sh --transfer -s ${SERVER_ALIAS} -d client_spt_me_202412041334'
bash user_config.sh --transfer -s ${SERVER_ALIAS} -d client_spt_me_202412041334

# 删除以 reality_ 开头的 Docker 容器，确保有容器ID再执行删除
containers=\$(docker ps -a --filter \"name=^reality_\" -q)

if [ -n \"\$containers\" ]; then
    docker rm -f \$containers
    echo '[$SSH_ALIAS] 删除所有以 reality_ 开头的 Docker 容器'
else
    echo '[$SSH_ALIAS] 未找到以 reality_ 开头的 Docker 容器，无需删除'
fi

# 并行执行 start_reality.sh 脚本
echo '[$SSH_ALIAS] 开始并行执行 start_reality.sh 脚本'

bash start_reality.sh -d client_${SERVER_ALIAS}_chatgpt_202412041334 &
bash start_reality.sh -d client_${SERVER_ALIAS}_sub_202412041334 &
bash start_reality.sh -d client_${SERVER_ALIAS}_me_202412041334 &

# 等待所有后台任务完成
wait
echo '[$SSH_ALIAS] 所有 start_reality.sh 脚本执行完成'
"

    # 执行命令并捕捉输出，同时在本地显示实时输出并记录到日志文件
    ssh -o BatchMode=yes "${SSH_ALIAS}" "${COMMANDS}" 2>&1 | while IFS= read -r line; do
        echo "[$SSH_ALIAS] $line" | tee -a remote_commands.log
    done

    if [[ ${PIPESTATUS[0]} -eq 0 ]]; then
        echo "[$SSH_ALIAS] 成功：命令执行完成。" | tee -a remote_commands.log
    else
        echo "[$SSH_ALIAS] 警告：命令执行失败。请检查 remote_commands.log 获取详细信息。" | tee -a remote_commands.log
    fi
}

# ----------------------------
# 主执行逻辑
# ----------------------------

# 检查是否传递了参数
if [[ $# -eq 0 ]]; then
    echo "错误：未提供任何参数。"
    show_help
    exit 1
fi

# 解析命令行参数
SERVERS=()
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -s|--servers)
            shift # past -s/--servers
            while [[ $# -gt 0 && ! "$1" =~ ^- ]]; do
                SERVERS+=("$1")
                shift
            done
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "错误：未知的选项: $1"
            show_help
            exit 1
            ;;
    esac
done

# 验证 -s/--servers 参数是否提供
if [[ ${#SERVERS[@]} -eq 0 ]]; then
    echo "错误：必须通过 -s 或 --servers 参数指定至少一个服务器。"
    show_help
    exit 1
fi

TOTAL_SERVERS=${#SERVERS[@]}
CURRENT_INDEX=1

# 初始化日志文件
echo "========== 执行开始：$(date) ==========" >> remote_commands.log

# 遍历服务器列表并执行命令
for SERVER_PAIR in "${SERVERS[@]}"; do
    # 分割 SSH_ALIAS 和 SERVER_ALIAS
    IFS=':' read -r SSH_ALIAS SERVER_ALIAS <<< "$SERVER_PAIR"

    # 检查是否正确解析
    if [[ -z "$SSH_ALIAS" || -z "$SERVER_ALIAS" ]]; then
        echo "错误：服务器配置格式不正确: $SERVER_PAIR" | tee -a remote_commands.log
        echo "正确格式应为: server:alias" | tee -a remote_commands.log
        CURRENT_INDEX=$((CURRENT_INDEX + 1))
        continue
    fi

    # 执行命令
    execute_commands "$SSH_ALIAS" "$SERVER_ALIAS" "$CURRENT_INDEX" "$TOTAL_SERVERS" &

    CURRENT_INDEX=$((CURRENT_INDEX + 1))
done

# 等待所有后台任务完成
wait

echo "========== 执行完成：$(date) ==========" | tee -a remote_commands.log
echo "--------------------------------------------------" | tee -a remote_commands.log
echo "所有命令执行完成。" | tee -a remote_commands.log
echo "--------------------------------------------------" | tee -a remote_commands.log