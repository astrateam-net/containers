# syntax=docker/dockerfile:1
FROM alpine:3.21 as builder
ARG VERSION

WORKDIR /root


RUN apk add --no-cache git make build-base curl tar


RUN curl -fsSL "https://github.com/Wind4/vlmcsd/archive/refs/tags/${VERSION}.tar.gz" \
    | tar -xz && \
    rm -f vlmcsd.tar.gz

WORKDIR /root/vlmcsd-${VERSION}
RUN make


FROM alpine:latest


RUN addgroup -g 1000 nogroup && \
    adduser -D -u 1000 -G nogroup nobody

RUN apk add --no-cache \
    curl \
    git \
    socat \
    tzdata

COPY --from=builder /root/vlmcsd-${VERSION}/bin/vlmcsd /vlmcsd
COPY --from=builder /root/vlmcsd-${VERSION}/etc/vlmcsd.kmd /vlmcsd.kmd

RUN chown nobody:nogroup /vlmcsd /vlmcsd.kmd && \
    chmod 755 /vlmcsd && \
    chmod 644 /vlmcsd.kmd

USER nobody:nogroup
WORKDIR /

EXPOSE 1688/tcp

CMD ["/vlmcsd", "-D", "-d", "-t", "3", "-e", "-v"]
