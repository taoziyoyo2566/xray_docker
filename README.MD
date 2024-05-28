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

docker ps -a --format "{{.ID}} {{.Names}}" | grep  "qreality_" | cut -d " " -f1 | xargs -r docker rm

docker images -a | grep vless_reality | awk '{print $3}' | xargs -I {} docker rmi {}

