## xray_docker_reality
xray reality docker 镜像

tar zxf ~/reality_stage.tar.gz -C /opt/docker/

DAY_COUNT=5
MONTH_COUNT=3
URL_ID=$(openssl rand -hex 4 | tr -d '\n')
docker run -d --name vless_reality_$URL_ID --restart=always --log-opt max-size=50m --cpuset-cpus="0-1" --cpu-shares=512 -m=100m -p $EXTERNAL_PORT:443 -e EXTERNAL_PORT=$EXTERNAL_PORT -e URL_ID=$URL_ID -e DAY_COUNT=$DAY_COUNT -e MONTH_COUNT=$MONTH_COUNT reality:v4

docker build -t reality:v6 .
docker exec -it vless_reality_$URL_ID more vless_info.json 
docker logs vless_reality_$URL_ID