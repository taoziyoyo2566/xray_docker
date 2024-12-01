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