bash start_reality.sh -u test.taoziyoyo.com,taoziyoyo@taoziyoyo.com -r ALPSHA -p 50199 -i KCL2EJQ1 -e 20231231 -n alpo9drrm5l1d7uopaguucnxohzc3ul2yazxrldzpuoduu.taoziyoyo.com
bash start_reality.sh -u taoziyoyo@taoziyoyo.com -r ALPSHA -p 50199 -i KCL2EJQ1 -e 20231231 -n alpo9drrm5l1d7uopaguucnxohzc3ul2yazxrldzpuoduu.taoziyoyo.com

bash start_reality.sh -f taoziyoyo.json -n alp

bash start_reality.sh -n alp -d client


docker rm $(docker ps -a --filter "name=^reality_" -q)