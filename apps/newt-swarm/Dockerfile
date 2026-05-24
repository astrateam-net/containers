# syntax=docker/dockerfile:1
# Custom Newt build with Docker Swarm cluster-wide service discovery.
# Tracks the feature branch on the fork until upstream (fosrl/newt) merges it.

FROM public.ecr.aws/docker/library/golang:1.25-alpine AS builder

ARG VERSION
ARG SOURCE_REF
ARG NEWT_REPO=https://github.com/mrkhachaturov/newt.git

RUN apk --no-cache add ca-certificates git tzdata

WORKDIR /src
# Fetch only the requested ref (branch, tag, or SHA) without a full clone.
RUN git init . \
    && git remote add origin "${NEWT_REPO}" \
    && git fetch --depth 1 origin "${SOURCE_REF}" \
    && git checkout FETCH_HEAD \
    && go mod download \
    && CGO_ENABLED=0 GOOS=linux go build \
        -ldflags="-s -w -X main.newtVersion=${VERSION}" \
        -o /newt

FROM public.ecr.aws/docker/library/alpine:3.23 AS runner

RUN apk --no-cache add ca-certificates tzdata iputils

COPY --from=builder /newt /usr/local/bin/
COPY --from=builder /src/entrypoint.sh /

# Admin/metrics endpoint (Prometheus scrape)
EXPOSE 2112

RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
CMD ["newt"]
