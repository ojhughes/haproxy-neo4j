FROM haproxy:2.3-alpine
RUN addgroup -S haproxy && adduser -H -D -G haproxy haproxy
USER haproxy
ENV NEO4J_HTTP="127.0.0.1:7474" \
    NEO4J_BOLT="127.0.0.1:7687"
COPY haproxy.cfg /usr/local/etc/haproxy/haproxy.cfg
