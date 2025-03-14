
docker stop $(docker ps -a --filter "name=^reality_" -q)
docker rm $(docker ps -a --filter "name=^reality_" -q)

使用 jq 修改 JSON 文件
for file in client/*.json; do jq '.r = "SPTSHA" | .n = "spt"' "$file" > tmp && mv tmp "$file"; done
如果 JSON 文件没有复杂嵌套且字段格式固定：
for file in client/*.json; do sed -i 's/"r": "ALPSHA"/"r": "SPTSHA"/g; s/"n": "alp"/"n": "spt"/g' "$file"; done

如果文件数量较多且需要备份，您可以在 sed 中添加备份选项，例如 -i.bak，生成备份文件：
for file in client/*.json; do sed -i.bak 's/"r": "ALPSHA"/"r": "SPTSHA"/g; s/"n": "alp"/"n": "spt"/g' "$file"; done


bash user_config.sh --new -s spt -u cpp,frank,shm,szm,yinlu
bash user_config.sh --new -s spt -u han,kyler,iceberg,qin,ceci,night,jack -g chatgpt 
bash user_config.sh --new -s spt -u cpp,frank,shm,szm,yinlu -g me 

bash user_config.sh --new -s spt -u cpp,frank,shm,szm,yinlu -d client_alp_202412021515

-- add users to specified folder
bash user_config.sh -s alp --add -u test,test2,test -d client_spt_202412041016

--- transfer
bash user_config.sh --transfer -n spt -d client_alp_202412021515
bash user_config.sh -n alp  --transfer

---run
bash start_reality.sh -d client_alp_202412021515
bash start_reality.sh -f taoziyoyo.json

ssh-keygen -t rsa -b 2048 -C "spartan@taoziyoyo.com"
ssh-copy-id -i ~/.ssh/id_rsa.pub zgo

---execute
bash rsync.sh -s dcc,bwh,alpha


replace
for file in *.json; do
jq 'with_entries(if .key == "n" then .key = "s" else . end)' "$file" > temp && mv temp "$file"
done


delete latest 5 docker instances
docker rm -f $(docker ps -a --filter "name=^reality_" -q)
docker ps -a --format "{{.CreatedAt}}\t{{.ID}}" | sort -r | head -n 7 | cut -f2 | xargs docker rm

# get ipv6 address local
ip -6 addr show scope global | grep -v temporary | grep -oP '(?<=inet6\s)[0-9a-f:]+(?=\/)'

sudo cp xxd /usr/bin/
# permission
sudo chown -R ${USER}:${USER} /opt/docker/reality/

# remote specified element
for file in client_spt_{me,sub,chatgpt}_202412041334/*.json; do jq 'del(.r)' "$file" > "$file.tmp" && mv "$file.tmp" "$file"; done

# 执行命令
#20250308
#TARGET=dcc
# Check if TARGET is exactly 3 English letters
if [[ ! $TARGET =~ ^[a-zA-Z]{3}$ ]]; then
  echo "Error: TARGET must be exactly 3 English letters"
  exit 1
fi
for i in {me,sub,chatgpt}; do
  bash user_config.sh -s spt -d $i -to $TARGET
done

# rsync from server[dcc,zgo]
bash rsync.sh -s dc,zgo

rm -rf /opt/docker/reality/nodeInfo/reality_*_spt/

#20250308
# run
server=dcc
patterns="me sub chatgpt"

for pattern in $patterns; do
  latest_dir=$(find . -maxdepth 1 -type d -name "client_${server}_${pattern}_*" | sort -r | head -n 1)
  if [ -n "$latest_dir" ]; then
    echo "Processing directory: $latest_dir"
    bash start_reality.sh -d "$latest_dir"
  else
    echo "No directory found matching pattern: client_${server}_${pattern}_*"
  fi
done

