bash start_reality.sh -u test.taoziyoyo.com,taoziyoyo@taoziyoyo.com -r ALPSHA -p 50199 -i KCL2EJQ1 -e 20231231 -n alpo9drrm5l1d7uopaguucnxohzc3ul2yazxrldzpuoduu.taoziyoyo.com
bash start_reality.sh -u taoziyoyo@taoziyoyo.com -r ALPSHA -p 50199 -i KCL2EJQ1 -e 20231231 -n alpo9drrm5l1d7uopaguucnxohzc3ul2yazxrldzpuoduu.taoziyoyo.com

bash start_reality.sh -f taoziyoyo.json -n alp

bash start_reality.sh -n alp -d client

docker stop $(docker ps -a --filter "name=^reality_" -q)
docker rm $(docker ps -a --filter "name=^reality_" -q)

使用 jq 修改 JSON 文件
for file in client/*.json; do jq '.r = "SPTSHA" | .n = "spt"' "$file" > tmp && mv tmp "$file"; done
如果 JSON 文件没有复杂嵌套且字段格式固定：
for file in client/*.json; do sed -i 's/"r": "ALPSHA"/"r": "SPTSHA"/g; s/"n": "alp"/"n": "spt"/g' "$file"; done

如果文件数量较多且需要备份，您可以在 sed 中添加备份选项，例如 -i.bak，生成备份文件：
for file in client/*.json; do sed -i.bak 's/"r": "ALPSHA"/"r": "SPTSHA"/g; s/"n": "alp"/"n": "spt"/g' "$file"; done

bash user_config.sh -n alp -u cpp,frank,taoziyoyo,shm,szm,yinlu --new

bash user_config.sh --new -n alp -u cpp,frank,taoziyoyo,shm,szm,yinlu
bash user_config.sh --new -n spt -u cpp,frank,taoziyoyo,shm,szm,yinlu -d client_alp_202412021515

bash user_config.sh --transfer -n spt -d client_alp_202412021515

bash user_config.sh -n alp  --transfer

bash start_reality.sh -d client_date


ssh-keygen -t rsa -b 2048 -C "spartan@taoziyoyo.com"
ssh-copy-id -i ~/.ssh/id_rsa.pub zgo

0 2 * * * /home/spartan/workspace/xray_docker.sh >> /var/log/sync_reality.log 2>&1


replace
for file in *.json; do
jq 'with_entries(if .key == "n" then .key = "s" else . end)' "$file" > temp && mv temp "$file"
done