# builder
FROM golang:alpine as builder
LABEL maintainer="taoziyoyo2566 <taoziyoyo2566@gmail.com>"
LABEL version="2.0.0"


#ENV GOPROXY=https://goproxy.cn,direct
WORKDIR /app

RUN apk add --no-cache git  && git clone https://github.com/XTLS/Xray-core.git . && \
    go mod download && \
    go build -o xray /app/main/

# runner
FROM alpine:latest as runner


ENV UUID=""
ENV DEST=""
ENV SERVERNAMES=""
ENV PRIVATEKEY=""
ENV SHORTIDS=""
ENV NETWORK=""
ENV INTERNAL_PORT=""
ENV HOSTMODE_PORT=""
ENV TZ=Asia/Shanghai

WORKDIR /

COPY ./entrypoint.sh /
COPY ./config.json /

COPY --from=builder /app/xray /
RUN mkdir -p /etc/wireguard &&\
    wget -N -P /etc/wireguard https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh &&\
    chmod +x /etc/wireguard/menu.sh &&\
    ln -sf /etc/wireguard/menu.sh /usr/bin/warp

RUN apk update && \
    apk add --no-cache tzdata ca-certificates jq curl openssl libqrencode coreutils wget && \
    mkdir -p /var/log/xray &&\
    wget -O /geosite.dat https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat && \
    wget -O /geoip.dat https://github.com/v2fly/geoip/releases/latest/download/geoip.dat && \
    chmod +x /entrypoint.sh

ENTRYPOINT ["./entrypoint.sh"]
EXPOSE 443