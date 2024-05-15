#!/bin/sh
if [ -f /config_info.txt ]; then
  echo "config.json exist"
else
  IPV6=$(curl -6 -sSL --connect-timeout 3 --retry 2  ip.sb || echo "null")
  IPV4=$(curl -4 -sSL --connect-timeout 3 --retry 2  ip.sb || echo "null")
  if [ -z "$UUID" ]; then
    echo "UUID is not set, generate random UUID "
    UUID="$(/xray uuid)"
    echo "UUID: $UUID"
  fi

  if [ -z "$EXTERNAL_PORT" ]; then
    echo "EXTERNAL_PORT is not set, use default value 443"
    EXTERNAL_PORT=443
  fi

  if [ -n "$HOSTMODE_PORT" ];then
    EXTERNAL_PORT=$HOSTMODE_PORT
    jq ".inbounds[0].port=$HOSTMODE_PORT" /config.json >/config.json_tmp && mv /config.json_tmp /config.json
  fi

  if [ -z "$DEST" ]; then
    echo "DEST is not set. default value www.apple.com:443"
    DEST="www.apple.com:443"
  fi

  if [ -z "$SERVERNAMES" ]; then
    echo "SERVERNAMES is not set. use default value [\"www.apple.com\",\"images.apple.com\"]"
    SERVERNAMES="www.apple.com images.apple.com"
  fi

  if [ -z "$PRIVATEKEY" ]; then
    echo "PRIVATEKEY is not set. generate new key"
    /xray x25519 >/key
    PRIVATEKEY=$(cat /key | grep "Private" | awk -F ': ' '{print $2}')
    PUBLICKEY=$(cat /key | grep "Public" | awk -F ': ' '{print $2}')
    echo "Private key: $PRIVATEKEY"
    echo "Public key: $PUBLICKEY"
  fi

  if [ -z "$NETWORK" ]; then
    echo "NETWORK is not set,set default value tcp"
    NETWORK="tcp"
  fi

  if [ -z "$URL_ID" ]; then
    echo "URL_ID is not set,set default value random"
    URL_ID=$(openssl rand -hex 4 | tr -d '\n')
  fi
  
  CREATE_DATETIME=$(date +"%Y-%m-%d %H:%M:%S")
  EXPIRE_DATETIME=NA
  if [ -z "$DAY_COUNT" ]; then
    echo "day not set"
  else 
    EXPIRE_DATETIME=$(date -d "+${DAY_COUNT} day" +"%Y-%m-%d %H:%M:%S")
  fi

  if [ -z "$MONTH_COUNT" ]; then
    echo "month not set"
  else 
    EXPIRE_DATETIME=$(date -d "+${MONTH_COUNT} month" +"%Y-%m-%d %H:%M:%S")
  fi

  # change config
  jq ".inbounds[0].settings.clients[0].id=\"$UUID\"" /config.json >/config.json_tmp && mv /config.json_tmp /config.json
  jq ".inbounds[0].streamSettings.realitySettings.dest=\"$DEST\"" /config.json >/config.json_tmp && mv /config.json_tmp /config.json

  SERVERNAMES_JSON_ARRAY="$(echo "[$(echo $SERVERNAMES | awk '{for(i=1;i<=NF;i++) printf "\"%s\",", $i}' | sed 's/,$//')]")"
  jq --argjson serverNames "$SERVERNAMES_JSON_ARRAY" '.inbounds[0].streamSettings.realitySettings.serverNames = $serverNames' /config.json >/config.json_tmp && mv /config.json_tmp /config.json

  jq ".inbounds[0].streamSettings.realitySettings.privateKey=\"$PRIVATEKEY\"" /config.json >/config.json_tmp && mv /config.json_tmp /config.json
  jq ".inbounds[0].streamSettings.network=\"$NETWORK\"" /config.json >/config.json_tmp && mv /config.json_tmp /config.json




  FIRST_SERVERNAME=$(echo $SERVERNAMES | awk '{print $1}')
  # config info with green color
  echo -e "\033[32m" >/config_info.txt
  echo "IPV6: $IPV6" >>/config_info.txt
  echo "IPV4: $IPV4" >>/config_info.txt
  echo "UUID: $UUID" >>/config_info.txt
  echo "DEST: $DEST" >>/config_info.txt
  echo "PORT: $EXTERNAL_PORT" >>/config_info.txt
  echo "SERVERNAMES: $SERVERNAMES (任选其一)" >>/config_info.txt
  echo "PRIVATEKEY: $PRIVATEKEY" >>/config_info.txt
  echo "PUBLICKEY: $PUBLICKEY" >>/config_info.txt
  echo "NETWORK: $NETWORK" >>/config_info.txt
  if [ "$IPV4" != "null" ]; then
    SUB_IPV4="vless://$UUID@$IPV4:$EXTERNAL_PORT?encryption=none&security=reality&type=$NETWORK&sni=$FIRST_SERVERNAME&fp=chrome&pbk=$PUBLICKEY&flow=xtls-rprx-vision#docker_vless_reality"
    URL_IPV4="vless://$UUID@$IPV4:$EXTERNAL_PORT?encryption=none&security=reality&type=$NETWORK&sni=$FIRST_SERVERNAME&fp=chrome&pbk=$PUBLICKEY&flow=xtls-rprx-vision#vless_reality_$URL_ID"
    echo "IPV4 订阅连接: $SUB_IPV4" >>/config_info.txt
    echo -e "IPV4 订阅二维码:\n$(echo "$SUB_IPV4" | qrencode -o - -t UTF8)" >>/config_info.txt
    cat > vless_info.json <<EOF
    {
      "URL_ID": $URL_ID,
      "IPV4": "$IPV4"
      "UUID": "$UUID",
      "DEST": "$DEST",
      "PORT": "$EXTERNAL_PORT",
      "NETWORK": "$NETWORK",
      "URL_IPV4": "$URL_IPV4",
      "CREATE_DATETIME": "$CREATE_DATETIME",
      "EXPIRE_DATETIME": "$EXPIRE_DATETIME"
    }
EOF
  fi
  if [ "$IPV6" != "null" ];then
    SUB_IPV6="vless://$UUID@$IPV6:$EXTERNAL_PORT?encryption=none&security=reality&type=$NETWORK&sni=$FIRST_SERVERNAME&fp=chrome&pbk=$PUBLICKEY&flow=xtls-rprx-vision#docker_vless_reality_vision_V6"
    URL_IPV6="vless://$UUID@$IPV6:$EXTERNAL_PORT?encryption=none&security=reality&type=$NETWORK&sni=$FIRST_SERVERNAME&fp=chrome&pbk=$PUBLICKEY&flow=xtls-rprx-vision#vless_reality_V6_$URL_ID""
    echo "IPV6 订阅连接: $SUB_IPV6" >>/config_info.txt
    #echo -e "IPV6 订阅二维码:\n$(echo "$SUB_IPV6" | qrencode -o - -t UTF8)" >>/config_info.txt
    cat > vless_info_v6.json <<EOF
    {
      "URL_ID": $URL_ID,
      "IPV6": "$IPV6"
      "UUID": "$UUID",
      "DEST": "$DEST",
      "PORT": "$EXTERNAL_PORT",
      "NETWORK": "$NETWORK",
      "URL_IPV6": "$URL_IPV6",
      "CREATE_DATETIME": "$CREATE_DATETIME",
      "EXPIRE_DATETIME": "$EXPIRE_DATETIME"
    }
EOF
  fi


  echo -e "\033[0m" >>/config_info.txt

fi

# show config info
cat /config_info.txt

# run xray
exec /xray -config /config.json
