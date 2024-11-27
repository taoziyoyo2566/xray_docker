# builder
FROM golang:1.21-alpine AS builder
LABEL maintainer="your_email@example.com"
LABEL version="1.0.0"

WORKDIR /app

RUN apk add --no-cache git \
    && git clone https://github.com/XTLS/Xray-core.git . \
    && go mod download \
    && CGO_ENABLED=0 go build -o xray -trimpath -ldflags "-s -w" ./main

# runner
FROM alpine:3.18.4 AS runner

ENV TZ=Asia/Shanghai

WORKDIR /

COPY ./entrypoint.sh /
COPY ./config.json /
COPY --from=builder /app/xray /

RUN apk update \
    && apk add --no-cache tzdata ca-certificates jq curl openssl libqrencode coreutils wget \
    && mkdir -p /var/log/xray \
    && chmod +x /entrypoint.sh

ENTRYPOINT ["./entrypoint.sh"]
EXPOSE 443