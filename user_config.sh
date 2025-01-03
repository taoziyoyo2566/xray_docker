#!/bin/bash
set -o pipefail

# 定义固定的日志文件名
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
LOG_DIR="${SCRIPT_DIR}/logs"
LOGFILE="${LOG_DIR}/user_config_$(date '+%Y%m%d').log"

# 确保日志目录存在
mkdir -p "$LOG_DIR"

# 日志函数，将输出重定向到日志文件和标准错误，并添加时间戳
log_info() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" | tee -a "$LOGFILE" >&2
}

log_error() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" | tee -a "$LOGFILE" >&2
}

# 显示帮助信息的函数，使用 log_info 输出
show_help() {
    log_info "Usage: $0 [options]"
    log_info ""
    log_info "Options:"
    log_info "  -s|--server       设置服务器 (必需)"
    log_info "  -u|--users        设置用户列表（用逗号分隔，创建新文件或添加用户时必需）"
    log_info "  -d|--directory    指定目录路径 (创建新文件时为输出目录的基准名, 修改现有文件时为源目录)"
    log_info "  -g|--group         设置组名（仅在 --new 和 --transfer 模式下使用，拼接到生成的目录名上）"
    log_info "  --new             创建新的 JSON 配置文件"
    log_info "  --transfer        修改现有的 JSON 配置文件"
    log_info "  --add             向指定目录添加多个用户的 JSON 配置文件"
    log_info "  --force           强制覆盖文件，不提示用户确认"
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
    date -d "+100 year" +%Y%m%d
}

# Create directory with server, group (optional), and date part
create_directory() {
    local base_dir="$1"
    local group="$2"
    local date_part
    local server_extracted

    # 移除尾部斜杠
    base_dir="${base_dir%/}"

    if [[ -n "$group" ]]; then
        # Group is provided, use it directly
        date_part=$(echo "$base_dir" | grep -oE '[0-9]{12}')
        if [[ -z "$date_part" ]]; then
            date_part=$(date +%Y%m%d%H%M)
            log_info "未在基准目录名中找到日期部分，使用当前时间: $date_part"
        else
            log_info "提取到的日期部分: $date_part"
        fi
        local dir_name="client_${server}_${group}_${date_part}"
    else
        # Try to extract group and server from base_dir
        if [[ "$base_dir" =~ ^client_([^_]+)_([^_]+)_([0-9]{12})$ ]]; then
            server_extracted="${BASH_REMATCH[1]}"
            group="${BASH_REMATCH[2]}"
            date_part="${BASH_REMATCH[3]}"
            log_info "从目录名中提取到组名: $group 和服务器: $server_extracted"
            local dir_name="client_${server}_${group}_${date_part}"
        else
            date_part=$(echo "$base_dir" | grep -oE '[0-9]{12}')
            if [[ -z "$date_part" ]]; then
                date_part=$(date +%Y%m%d%H%M)
                log_info "未在基准目录名中找到日期部分，使用当前时间: $date_part"
            else
                log_info "提取到的日期部分: $date_part"
            fi
            local dir_name="client_${server}_${date_part}"
        fi
    fi

    mkdir -p "$dir_name"
    if [[ $? -ne 0 ]]; then
        log_error "无法创建目标目录: $dir_name"
        exit 1
    fi
    log_info "已创建目录: $dir_name"
    echo "$dir_name"
}

# Modify the "r" and "s" fields in existing JSON files
modify_json_files() {
    local user="$1"
    local source_dir="$2"
    local target_dir="$3"
    local file="${source_dir}/${user}.json"

    if [ -f "$file" ]; then
        log_info "正在处理文件: $file"
        # 提取用户名前三个字符并转换为大写
        user_prefix_upper=$(echo "${user:0:3}" | tr '[:lower:]' '[:upper:]')
        # 使用 jq 修改 "r" 和 "s" 字段
        jq --arg ref "${server^^}${user_prefix_upper}" \
           --arg server "$server" \
           '.r = $ref | .s = $server' \
           "$file" > "${target_dir}/${user}.json"

        if [ $? -eq 0 ]; then
            log_info "已修改并保存文件: ${target_dir}/${user}.json"
        else
            log_error "修改文件失败: $file"
        fi
    else
        log_error "文件不存在: $file"
    fi
}

# Prompt before overwriting an existing file
prompt_overwrite() {
    local file="$1"
    if [ -f "$file" ]; then
        if $force_overwrite; then
            log_info "强制覆盖文件: $file"
            return 0
        fi
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

# Add multiple users to an existing directory
add_users_to_directory() {
    local users="$1"
    local target_dir="$2"
    IFS=',' read -ra USER_ARRAY <<< "$users"
    for user in "${USER_ARRAY[@]}"; do
        local target_file="${target_dir}/${user}.json"
        if prompt_overwrite "$target_file"; then
            port=$(generate_random_port)
            id=$(generate_random_id)
            expiration=$(calculate_expiration_date)
            ref=$(echo "${server}${user:0:3}" | tr '[:lower:]' '[:upper:]')
            # 生成 JSON 文件
            cat > "$target_file" <<EOF
{
  "u": "$user",
  "p": "$port",
  "i": "$id",
  "e": "$expiration",
  "r": "$ref",
  "s": "$server"
}
EOF
            if [ $? -eq 0 ]; then
                log_info "已生成文件: $target_file"
            else
                log_error "生成文件失败: $target_file"
            fi
        fi
    done
}

# 主函数
main() {
    # 初始化变量，设置默认值
    server=""
    users=""
    mode=""
    directory=""
    group=""
    force_overwrite=false

    # 检查 jq 是否安装
    if ! command -v jq >/dev/null 2>&1; then
        log_error "jq 未安装，请先安装 jq。"
        exit 1
    fi

    # 使用 getopts 解析命令行参数
    while [[ "$#" -gt 0 ]]; do
        key="$1"
        case $key in
            -s|--server)
                server="$2"
                shift # past argument
                shift # past value
                ;;
            -u|--users)
                users="$2"
                shift # past argument
                shift # past value
                ;;
            -d|--directory)
                directory="$2"
                shift # past argument
                shift # past value
                ;;
            -g|--group)
                group="$2"
                shift # past argument
                shift # past value
                ;;
            --new)
                if [[ -n "$mode" ]]; then
                    log_error "只能指定一个操作模式（--new, --transfer, --add）。"
                    show_help
                    exit 1
                fi
                mode="new"
                shift # past argument
                ;;
            --transfer)
                if [[ -n "$mode" ]]; then
                    log_error "只能指定一个操作模式（--new, --transfer, --add）。"
                    show_help
                    exit 1
                fi
                mode="transfer"
                shift # past argument
                ;;
            --add)
                if [[ -n "$mode" ]]; then
                    log_error "只能指定一个操作模式（--new, --transfer, --add）。"
                    show_help
                    exit 1
                fi
                mode="add"
                shift # past argument
                ;;
            --force)
                force_overwrite=true
                shift # past argument
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

    # 验证必要参数
    if [[ -z "$server" ]]; then
        log_error "必须指定服务器，使用 -s 或 --server 参数。"
        show_help
        exit 1
    fi

    if [[ -z "$mode" ]]; then
        log_error "必须指定操作模式，使用 --new, --transfer 或 --add。"
        show_help
        exit 1
    fi

    case $mode in
        "new")
            if [[ -z "$users" ]]; then
                log_error "创建新文件时，必须指定用户列表，使用 -u 或 --users 参数。"
                show_help
                exit 1
            fi
            if [[ -z "$directory" ]]; then
                # 自动创建目录，包含服务器、组名（如果有）和时间戳
                dir_name=$(create_directory "" "$group")
            else
                # 使用指定的目录名作为基准，提取日期部分，并包含组名（如果有）
                dir_name=$(create_directory "$directory" "$group")
            fi
            IFS=',' read -ra ADDR <<< "$users"
            for user in "${ADDR[@]}"; do
                target_file="$dir_name/$user.json"
                if prompt_overwrite "$target_file"; then
                    port=$(generate_random_port)
                    id=$(generate_random_id)
                    expiration=$(calculate_expiration_date)
                    ref=$(echo "${server}${user:0:3}" | tr '[:lower:]' '[:upper:]')
                    # 生成 JSON 文件
                    cat > "$target_file" <<EOF
{
  "u": "$user",
  "p": "$port",
  "i": "$id",
  "e": "$expiration",
  "r": "$ref",
  "s": "$server"
}
EOF
                    if [ $? -eq 0 ]; then
                        log_info "已生成文件: $target_file"
                    else
                        log_error "生成文件失败: $target_file"
                    fi
                fi
            done
            ;;
        "transfer")
            if [[ -z "$directory" ]]; then
                log_error "修改现有文件时，必须指定目录路径，使用 -d 或 --directory 参数。"
                show_help
                exit 1
            fi
            if [[ ! -d "$directory" ]]; then
                log_error "指定的目录不存在: $directory"
                exit 1
            fi
            # 提取日期部分
            date_part=$(echo "$directory" | grep -oE '[0-9]{12}')
            if [[ -z "$date_part" ]]; then
                date_part=$(date +%Y%m%d%H%M%S)
                log_info "未在源目录名中找到日期部分，使用当前时间: $date_part"
            else
                log_info "提取到的日期部分: $date_part"
            fi
            # 创建目标目录
            target_dir=$(create_directory "$directory" "$group")
            if [[ $? -ne 0 ]]; then
                log_error "无法创建目标目录: $target_dir"
                exit 1
            fi
            if [[ -n "$users" ]]; then
                # 修改指定用户
                IFS=',' read -ra ADDR <<< "$users"
                for user in "${ADDR[@]}"; do
                    modify_json_files "$user" "$directory" "$target_dir"
                done
            else
                # 修改所有用户
                for file in "$directory"/*.json; do
                    if [[ -f "$file" ]]; then
                        user=$(basename "$file" .json)
                        modify_json_files "$user" "$directory" "$target_dir"
                    fi
                done
            fi
            ;;
        "add")
            if [[ -z "$users" || -z "$directory" ]]; then
                log_error "添加新用户时，必须同时指定用户和目录。"
                show_help
                exit 1
            fi
            if [[ ! -d "$directory" ]]; then
                log_error "指定的目录不存在: $directory"
                exit 1
            fi
            add_users_to_directory "$users" "$directory"
            ;;
        *)
            log_error "未知的操作模式: $mode"
            show_help
            exit 1
            ;;
    esac

    log_info "操作完成。"
}

# 执行主函数
main "$@"