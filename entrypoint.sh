#!/bin/sh
#set -e
set -o pipefail

# 主函数
main() {
    # 检查是否存在配置文件
    if [ ! -f /config.json ]; then
        echo "配置文件 /config.json 不存在，退出。"
        exit 1
    fi

    # 获取服务器的公网 IP
    IPV4=$(curl -s https://api.ipify.org)
    if [ -z "$IPV4" ]; then
        echo "无法获取公网 IP。"
        exit 1
    fi

    # 将 IP 信息写入 vless_info.json
    echo "{\"IPV4\":\"$IPV4\"}" > /vless_info.json

    # 运行 xray
    exec /xray -config /config.json
}

# 执行主函数
main "$@"