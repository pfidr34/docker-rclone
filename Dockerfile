ARG BASE=alpine:latest
FROM ${BASE}

LABEL maintainer="l4t3b0@gmail.com"

ARG RCLONE_VERSION=v1.53.1
ARG ARCH=amd64

ENV SYNC_SRC=
ENV SYNC_DEST=
ENV SYNC_OPTS=-v
ENV SYNC_OPTS_EVAL=
ENV SYNC_ON_STARTUP=true

ENV RCLONE_CMD=sync
ENV RCLONE_CONFIG="--config /etc/rclone/rclone.conf"

ENV LOG_ENABLED=
ENV ROTATE_LOG=

ENV CRON=
ENV CRON_ABORT=

ENV HEALTHCHECKS_IO_URL=

ENV TZ=
ENV PUID=1000
ENV PGID=1000

RUN apk --no-cache add ca-certificates fuse wget dcron tzdata

RUN URL=https://downloads.rclone.org/${RCLONE_VERSION}/rclone-${RCLONE_VERSION}-linux-${ARCH}.zip ; \
  URL=${URL/\/current/} ; \
  cd /tmp \
  && wget -q $URL \
  && unzip /tmp/rclone-${RCLONE_VERSION}-linux-${ARCH}.zip \
  && mv /tmp/rclone-*-linux-${ARCH}/rclone* /usr/bin \
  && rm -r /tmp/rclone*

COPY entrypoint.sh /
COPY rclone-sync.sh /usr/bin/
COPY rclone-sync-abort.sh /usr/bin/

VOLUME ["/etc/rclone"]
VOLUME ["/var/log/rclone"]
VOLUME ["/data"]

ENTRYPOINT ["/entrypoint.sh"]

CMD [""]
