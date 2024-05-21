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


方法一：将用户添加到具有执行权限的用户组中
首先，确保用户属于 root 或具有 sudo 权限的用户之一，因为 tc 命令通常需要特权执行。
创建一个新的用户组，例如 tcusers：
bash
Copy code
sudo groupadd tcusers
将当前用户添加到 tcusers 组中：
bash
Copy code
sudo usermod -aG tcusers $USER
授予 tc 命令以执行权限，并将其所有者更改为 root，并将其所属组更改为 tcusers：
bash
Copy code
sudo chown root:tcusers /usr/sbin/tc
