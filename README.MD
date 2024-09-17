## xray_docker_reality
xray reality docker 镜像

tar zxf ~/reality_stage.tar.gz -C /opt/docker/

docker build -t vless_reality:v1 .
DAY_COUNT=15
MONTH_COUNT=13
EXTERNAL_PORT=8443
REGION=HK
URL_ID=$(openssl rand -hex 4 | tr -d '\n')

docker run -d --name vless_reality_$URL_ID --restart=always --log-opt max-size=50m --cpuset-cpus="0-1" --cpu-shares=512 -m=300m -p $EXTERNAL_PORT:443 -e EXTERNAL_PORT=$EXTERNAL_PORT -e URL_ID=$URL_ID -e REGION=$REGION vless_reality:v1

docker run -d --name vless_reality_$URL_ID --restart=always --log-opt max-size=50m --cpuset-cpus="0-1" --cpu-shares=512 -m=300m -p $EXTERNAL_PORT:443 -e EXTERNAL_PORT=$EXTERNAL_PORT -e URL_ID=$URL_ID -e DAY_COUNT=$DAY_COUNT -e MONTH_COUNT=$MONTH_COUNT vless_reality:v1

docker build -t reality:v7 .
docker exec -it vless_reality_$URL_ID more vless_info.json 
docker exec -it vless_reality_$URL_ID more vless_info_v6.json 
docker logs vless_reality_$URL_ID

docker ps -a --format "{{.ID}} {{.Names}}" | grep  "reality" | cut -d " " -f1 | xargs -r docker stop

bash start_vless_reality.sh -e URL_ID=12345679 -e PORT=23457 -e MONTHS=3 -e DAYS=10 -e REGION=TTUS -e CPU=1
### 说明

- **自动生成区域码**: 默认生成一个随机的 4 位字母 `REGION`，但可以通过命令行参数覆盖。

- **命令行参数**:
    - 支持以下参数：
        - `-e URL_ID=12345679`：指定 URL ID。
        - `-e PORT=23457`：指定端口。
        - `-e MONTHS=3`：指定月数。
        - `-e DAYS=10`：指定天数。
        - `-e REGION=TTUS`：指定区域码。
        - `-e CPU=1.0`：指定 CPU 使用限制。
        - `-e MEMORY=512m`：指定内存使用限制。

- **资源配置**: 通过 `CPU` 和 `MEMORY` 参数来控制 Docker 容器的资源使用，确保合理利用系统资源。

# monitor access
python3 monitor.py reality_BWHSHE_96e09393 [1h|1d|1m]
