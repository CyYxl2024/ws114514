# syntax=docker/dockerfile:latest
FROM --platform=$BUILDPLATFORM golang:alpine AS build

# Fork 仓库不需要 git clone，直接将当前目录(源码)复制进去
WORKDIR /src
COPY . .

ARG TARGETOS
ARG TARGETARCH
# 编译命令
RUN GOOS=$TARGETOS GOARCH=$TARGETARCH CGO_ENABLED=0 go build -o xray -trimpath -buildvcs=false -gcflags="all=-l=4" -ldflags "-s -w -buildid=" ./main

# 下载 GeoIP 数据
ADD https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/geoip.dat /tmp/geodat/geoip.dat
ADD https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/geosite.dat /tmp/geodat/geosite.dat

RUN mkdir -p /tmp/empty
RUN mkdir -p /tmp/usr/local/etc/xray

# -------------------------------------------------------
# 以下所有配置生成代码完全保持不变
# -------------------------------------------------------

RUN cat <<EOF >/tmp/usr/local/etc/xray/00_log.json
{
  "log": {
    "error": "/var/log/xray/error.log",
    "loglevel": "warning",
    "access": "none",
    "dnsLog": false
  }
}
EOF

RUN echo '{}' >/tmp/usr/local/etc/xray/01_api.json
RUN echo '{}' >/tmp/usr/local/etc/xray/02_dns.json
RUN echo '{}' >/tmp/usr/local/etc/xray/03_routing.json
RUN echo '{}' >/tmp/usr/local/etc/xray/04_policy.json

RUN cat <<'EOF' >/tmp/usr/local/etc/xray/05_inbounds.json
{
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": 8080,
      "protocol": "vless",
      "settings": {
        "decryption": "none",
        "clients": [
          {
            "id": "9cb0a137-68d8-4737-b6fc-537bd70a6dce",
            "level": 0
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/ws114514xray"
        }
      },
      "tag": "Vless-Ws-NoTLS-IN"
    }
  ]
}
EOF

RUN cat <<'EOF' >/tmp/usr/local/etc/xray/06_outbounds.json
{
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ]
}
EOF

RUN echo '{}' >/tmp/usr/local/etc/xray/07_transport.json
RUN echo '{}' >/tmp/usr/local/etc/xray/08_stats.json
RUN echo '{}' >/tmp/usr/local/etc/xray/09_reverse.json

RUN mkdir -p /tmp/var/log/xray && touch \
  /tmp/var/log/xray/access.log \
  /tmp/var/log/xray/error.log

# Final Stage
FROM gcr.io/distroless/static:nonroot

COPY --from=build --chown=0:0 --chmod=755 /src/xray /usr/local/bin/xray
COPY --from=build --chown=0:0 --chmod=755 /tmp/empty /usr/local/share/xray
COPY --from=build --chown=0:0 --chmod=644 /tmp/geodat/*.dat /usr/local/share/xray/
COPY --from=build --chown=0:0 --chmod=755 /tmp/empty /usr/local/etc/xray
COPY --from=build --chown=0:0 --chmod=644 /tmp/usr/local/etc/xray/*.json /usr/local/etc/xray/
COPY --from=build --chown=0:0 --chmod=755 /tmp/empty /var/log/xray
COPY --from=build --chown=65532:65532 --chmod=600 /tmp/var/log/xray/*.log /var/log/xray/

VOLUME /usr/local/etc/xray
VOLUME /var/log/xray

EXPOSE 8080

ARG TZ=Asia/Shanghai
ENV TZ=$TZ

ENTRYPOINT [ "/usr/local/bin/xray" ]
CMD [ "-confdir", "/usr/local/etc/xray/" ]
