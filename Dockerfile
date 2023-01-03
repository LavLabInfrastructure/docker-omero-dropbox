FROM ghcr.io/lhns/prometheus-bash-exporter:6fa8c9ed as exporter
FROM eclipse-temurin:11
ARG DEBIAN_FRONTEND=noninteractive

#install runtime libraries
RUN apt-get update \
    && apt-get install -y --no-install-recommends\
    jq \
    git \
    zip \
    curl \
    unzip \
    ssmtp \
    socat \
    netcat \
    dos2unix \
    net-tools \
    mailutils \
    libblosc1 \
    inotify-tools && \
    rm -rf /var/lib/apt/lists/*

# dumb init for process management
RUN mkdir /docker && curl -L -o /docker/dumb-init \
    https://github.com/Yelp/dumb-init/releases/download/v1.2.5/dumb-init_1.2.5_x86_64 && \
    chmod +x /docker/dumb-init

# glencoe bioformats converters
RUN cd / && curl -L -o bf2raw.zip https://github.com/glencoesoftware/bioformats2raw/releases/download/v0.6.0/bioformats2raw-0.6.0.zip && \
    curl -L -o raw2ometiff.zip https://github.com/glencoesoftware/raw2ometiff/releases/download/v0.4.0/raw2ometiff-0.4.0.zip && \
    unzip -qod /tmp "bf2raw.zip" && \
    unzip -qod /tmp "raw2ometiff.zip" && rm *.zip && \
    cp -r /tmp/raw2ometiff*/* /docker && \
    cp -r /tmp/bioformats2raw*/* /docker

COPY --from=exporter prometheus-bash-exporter /docker/
COPY pipe/* .env /docker/
COPY grafana /etc/grafana/panels
COPY rules /etc/prometheus/rules

RUN rm -rf /tmp

# bash pipeline constructor
ENTRYPOINT [ "/docker/entrypoint.sh" ]