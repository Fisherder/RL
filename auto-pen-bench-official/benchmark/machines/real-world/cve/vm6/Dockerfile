FROM openjdk:8u102-jre@sha256:867ce93115062ca94278723577aad5ffa512169257c7e03ee68eea031b082bc4

RUN set -ex \
    && printf 'deb [trusted=yes] http://archive.debian.org/debian jessie main\n' > /etc/apt/sources.list \
    && rm -f /etc/apt/sources.list.d/* \
    && printf 'Acquire::Check-Valid-Until "false";\nAcquire::AllowInsecureRepositories "true";\nAcquire::AllowDowngradeToInsecureRepositories "true";\n' > /etc/apt/apt.conf.d/99legacy-archive \
    && apt-get update \
    && apt-get install -y --allow-unauthenticated --no-install-recommends python3 libfindbin-libs-perl

RUN set -ex \
    && mkdir -p /opt/druid \
    && archive=/tmp/apache-druid-0.20.0-bin.tar.gz \
    && rm -f "$archive" \
    && success=0 \
    && for attempt in 1 2 3 4 5; do \
        wget --no-check-certificate -O "$archive" https://archive.apache.org/dist/druid/0.20.0/apache-druid-0.20.0-bin.tar.gz || true; \
        if tar tzf "$archive" >/dev/null 2>&1; then \
            success=1; \
            break; \
        fi; \
        rm -f "$archive"; \
        sleep 5; \
    done \
    && test "$success" = "1" \
    && tar xzf "$archive" --strip-components 1 -C /opt/druid \
    && rm -f "$archive"

COPY flag.txt /root/flag.txt

EXPOSE 8888
WORKDIR /opt/druid
CMD [ "/opt/druid/bin/start-nano-quickstart" ]
