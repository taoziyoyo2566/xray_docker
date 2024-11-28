#!/bin/sh
set -o pipefail

# 主函数
main() {
    # 检查是否存在配置文件
    if [ ! -f /config.json ]; then
        echo "配置文件 /config.json 不存在，退出。"
        exit 1
    fi

    # 运行 xray
    exec /xray -config /config.json
}

# 执行主函数
main "$@"