# syntax=docker/dockerfile:1
ARG VERSION

FROM node:20 AS build

ARG TARGETARCH


WORKDIR /tmp


RUN git clone https://github.com/OpenMaxIO/openmaxio-object-browser . && \
    git checkout ${VERSION}

WORKDIR /tmp/web-app
RUN corepack enable && corepack prepare yarn@4.4.0 --activate

RUN yarn install && yarn build

WORKDIR /tmp
COPY . .


RUN apt-get update && apt-get install -y make curl \
    && GO_VERSION=1.23.0 \
    && if [ "$TARGETARCH" = "amd64" ]; then GOARCH=amd64; else GOARCH=$TARGETARCH; fi \
    && curl -LO https://go.dev/dl/go${GO_VERSION}.linux-${GOARCH}.tar.gz \
    && rm -rf /usr/local/go && tar -C /usr/local -xzf go${GO_VERSION}.linux-${GOARCH}.tar.gz \
    && export PATH=$PATH:/usr/local/go/bin \
    && /usr/local/go/bin/go version \
    && make console 

# Final image
FROM python:alpine

WORKDIR /tmp

# Copy everything from the build stage to the final image
COPY --from=build /tmp /tmp

EXPOSE 9090

# Adjust command as needed
CMD ["./console", "server"]
