FROM ghcr.io/lhns/prometheus-bash-exporter:6fa8c9ed as exporter
FROM eclipse-temurin:11
ARG DEBIAN_FRONTEND=noninteractive
ENV SCRIPT_METRICS=/docker/prometheus.sh
ENV SERVER_PORT=19090
LABEL prometheus-scrape.enabled=true
LABEL prometheus-scrape.job_name=docker-omero-dropbox
LABEL prometheus-scrape.port=${SERVER_PORT:-19090}

#install runtime libraries
RUN apt-get update \
    && apt-get install -y --no-install-recommends\
    jq \
    git \
    zip \
    curl \
    unzip \
    socat \
    redis \
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
COPY pipe/* /docker/
COPY configs /configs

RUN rm -rf /tmp && mkdir /tmp

# bash pipeline constructor
ENTRYPOINT [ "/docker/entrypoint.sh" ]