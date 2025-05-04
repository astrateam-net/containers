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


FROM alpine:3.21

COPY --from=builder /root/vlmcsd-${VERSION}/bin/vlmcsd /vlmcsd
COPY --from=builder /root/vlmcsd-${VERSION}/etc/vlmcsd.kmd /vlmcsd.kmd

RUN apk add --no-cache \
    tzdata

EXPOSE 1688/tcp

CMD ["/vlmcsd", "-D", "-d", "-t", "3", "-e", "-v"]
