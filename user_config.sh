#!/bin/bash
set -o pipefail

# 定义固定的日志文件名
LOGFILE="user_config.log"

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
    log_info "  -n|--namespace    设置命名空间 (必需)"
    log_info "  -u|--users        设置用户列表（用逗号分隔，创建新文件时必需）"
    log_info "  -d|--directory    指定目录路径 (创建新文件时为输出目录的基准名, 修改现有文件时为源目录)"
    log_info "  --new             创建新的 JSON 配置文件"
    log_info "  --transfer        修改现有的 JSON 配置文件"
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

# Create directory with namespace and date part
create_directory() {
    local base_dir="$1"
    local date_part
    date_part=$(echo "$base_dir" | grep -oE '[0-9]{12}')
    if [[ -z "$date_part" ]]; then
        date_part=$(date +%Y%m%d%H%M)
        log_info "未在基准目录名中找到日期部分，使用当前时间: $date_part"
    else
        log_info "提取到的日期部分: $date_part"
    fi
    local dir_name="client_${namespace}_${date_part}"
    mkdir -p "$dir_name"
    if [[ $? -ne 0 ]]; then
        log_error "无法创建目标目录: $dir_name"
        exit 1
    fi
    log_info "已创建目录: $dir_name"
    echo "$dir_name"
}

# Modify the "r" and "n" fields in existing JSON files
modify_json_files() {
    local user="$1"
    local source_dir="$2"
    local target_dir="$3"
    local file="${source_dir}/${user}.json"

    if [ -f "$file" ]; then
        log_info "正在处理文件: $file"
        # 提取用户名前三个字符并转换为大写
        user_prefix_upper=$(echo "${user:0:3}" | tr '[:lower:]' '[:upper:]')
        # 使用 jq 修改 "r" 和 "n" 字段
        jq --arg ref "${namespace^^}${user_prefix_upper}" \
           --arg namespace "$namespace" \
           ".r = \$ref | .n = \$namespace" \
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

# 主函数
main() {
    # 初始化变量，设置默认值
    namespace=""
    users=""
    mode=""
    directory=""

    # 检查 jq 是否安装
    if ! command -v jq >/dev/null 2>&1; then
        log_error "jq 未安装，请先安装 jq。"
        exit 1
    fi

    # 使用 getopts 解析命令行参数
    while [[ "$#" -gt 0 ]]; do
        key="$1"
        case $key in
            -n|--namespace)
                namespace="$2"
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
            --new)
                mode="new"
                shift # past argument
                ;;
            --transfer)
                mode="transfer"
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
    if [[ -z "$namespace" ]]; then
        log_error "必须指定命名空间，使用 -n 或 --namespace 参数。"
        show_help
        exit 1
    fi

    if [[ -z "$mode" ]]; then
        log_error "必须指定操作模式，使用 --new 或 --transfer。"
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
                # 自动创建目录，包含命名空间和时间戳
                dir_name=$(create_directory "")
            else
                # 使用指定的目录名作为基准，提取日期部分
                dir_name=$(create_directory "$directory")
            fi
            IFS=',' read -ra ADDR <<< "$users"
            for user in "${ADDR[@]}"; do
                port=$(generate_random_port)
                id=$(generate_random_id)
                expiration=$(calculate_expiration_date)
                ref=$(echo "${namespace}${user:0:3}" | tr '[:lower:]' '[:upper:]')
                # 生成 JSON 文件
                cat > "$dir_name/$user.json" <<EOF
{
  "u": "$user",
  "p": "$port",
  "i": "$id",
  "e": "$expiration",
  "r": "$ref",
  "n": "$namespace"
}
EOF
                if [ $? -eq 0 ]; then
                    log_info "已生成文件: $dir_name/$user.json"
                else
                    log_error "生成文件失败: $dir_name/$user.json"
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
            target_dir="client_${namespace}_${date_part}"
            mkdir -p "$target_dir"
            if [[ $? -ne 0 ]]; then
                log_error "无法创建目标目录: $target_dir"
                exit 1
            fi
            log_info "已创建目标目录: $target_dir"
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