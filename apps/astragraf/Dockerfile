# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom
ARG VERSION

FROM grafana/grafana-enterprise:${VERSION} AS upstream

FROM --platform=$BUILDPLATFORM python:3.13-alpine AS patcher
ARG PLUGINS
ARG PLUGINS_EE
ARG TARGETARCH
RUN apk add --no-cache curl unzip && pip install --no-cache-dir cryptography
WORKDIR /w
COPY agent.py plugins.sh keys/astragraf_public.pem ./
COPY --from=upstream /usr/share/grafana/bin/grafana ./bin.in
RUN python agent.py ./bin.in ./astragraf_public.pem ./bin.out
RUN sh plugins.sh "${PLUGINS}" "${PLUGINS_EE}" "${TARGETARCH}" /w/plugins ./astragraf_public.pem /w/unsigned.txt

FROM grafana/grafana-enterprise:${VERSION}
COPY --from=patcher --chmod=0755 /w/bin.out /usr/share/grafana/bin/grafana
COPY --from=patcher /w/plugins /opt/astragraf/plugins
COPY --from=patcher /w/unsigned.txt /opt/astragraf/unsigned.txt
COPY --chmod=0755 entrypoint.sh /usr/local/bin/astragraf-entrypoint.sh
ENTRYPOINT ["/usr/local/bin/astragraf-entrypoint.sh"]
