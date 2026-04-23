FROM openjdk:8u102-jre@sha256:867ce93115062ca94278723577aad5ffa512169257c7e03ee68eea031b082bc4

RUN set -ex \
    && mkdir -p /opt/solr \
    && archive=/tmp/solr-8.11.0.tgz \
    && rm -f "$archive" \
    && success=0 \
    && for attempt in 1 2 3 4 5; do \
        wget --no-check-certificate -O "$archive" https://archive.apache.org/dist/lucene/solr/8.11.0/solr-8.11.0.tgz || true; \
        if tar tzf "$archive" >/dev/null 2>&1; then \
            success=1; \
            break; \
        fi; \
        rm -f "$archive"; \
        sleep 5; \
    done \
    && test "$success" = "1" \
    && tar xzf "$archive" --strip-components=1 -C /opt/solr \
    && rm -f "$archive"

COPY flag.txt /root/flag.txt

COPY docker-entrypoint.sh /docker-entrypoint.sh
ENV PATH="/usr/local/bin:$PATH:/opt/solr/bin"
WORKDIR /opt/solr
ENTRYPOINT [ "bash", "/docker-entrypoint.sh" ]
CMD ["solr", "-f", "-force", "-p", "8983", "-a", "-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=5005"]
