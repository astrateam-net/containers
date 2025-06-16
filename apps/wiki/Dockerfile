# syntax=docker/dockerfile:1

ARG BASE_IMAGE=eclipse-temurin:21-noble
FROM $BASE_IMAGE

LABEL maintainer="dc-deployments@atlassian.com"
LABEL securitytxt="https://www.atlassian.com/.well-known/security.txt"

ENV APP_NAME=confluence
ENV RUN_USER=confluence
ENV RUN_GROUP=confluence
ENV RUN_UID=2002
ENV RUN_GID=2002

# https://confluence.atlassian.com/doc/confluence-home-and-other-important-directories-590259707.html
ENV CONFLUENCE_HOME=/var/atlassian/application-data/confluence
ENV CONFLUENCE_INSTALL_DIR=/opt/atlassian/confluence

ENV CONFLUENCE_LOG_STDOUT=false

WORKDIR $CONFLUENCE_HOME

# Expose HTTP and Synchrony ports
EXPOSE 8090
EXPOSE 8091

COPY entrypoint.py \
     shutdown-wait.sh \
     wait-for-catalina-shutdown.sh \     
     shared-components/image/entrypoint_helpers.py  /
COPY shared-components/support /opt/atlassian/support
COPY config/*                 /opt/atlassian/etc/

RUN apt-get update \
    && apt-get upgrade -y \
    && apt-get install -y --no-install-recommends fontconfig fonts-noto python3 python3-jinja2 tini \
    && apt-get clean autoclean && apt-get autoremove -y && rm -rf /var/lib/apt/lists/*


ARG VERSION
ARG CONFLUENCE_VERSION=${VERSION}
ARG DOWNLOAD_URL=https://product-downloads.atlassian.com/software/confluence/downloads/atlassian-confluence-${CONFLUENCE_VERSION}.tar.gz

ENV CONFLUENCE_VERSION=${CONFLUENCE_VERSION}

RUN groupadd --gid ${RUN_GID} ${RUN_GROUP} \
    && useradd --uid ${RUN_UID} --gid ${RUN_GID} --home-dir ${CONFLUENCE_HOME} --shell /bin/bash ${RUN_USER} \
    && echo PATH=$PATH > /etc/environment \
    && mkdir -p                                     ${CONFLUENCE_INSTALL_DIR} \
    && curl -fsSL ${DOWNLOAD_URL} -o /tmp/atlassian-confluence-${CONFLUENCE_VERSION}.tar.gz \
    && curl -fsSL ${DOWNLOAD_URL}.sha256 -o /tmp/atlassian-confluence-${CONFLUENCE_VERSION}.tar.gz.sha256 \
    && set -e; cd /tmp && sha256sum -c atlassian-confluence-${CONFLUENCE_VERSION}.tar.gz.sha256 \
    && tar -xf /tmp/atlassian-confluence-${CONFLUENCE_VERSION}.tar.gz --strip-components=1 -C "${CONFLUENCE_INSTALL_DIR}" \
    && rm /tmp/atlassian-confluence* \
    && chmod -R 550                                 ${CONFLUENCE_INSTALL_DIR}/ \
    && chown -R ${RUN_USER}:root                    ${CONFLUENCE_INSTALL_DIR}/ \
    && for dir in logs temp work; do \
         chmod -R 770 ${CONFLUENCE_INSTALL_DIR}/${dir}; \
       done \
    && chown -R ${RUN_USER}:${RUN_GROUP} ${CONFLUENCE_HOME} \
    && for file in "/opt/atlassian/support /entrypoint.py /entrypoint_helpers.py /shutdown-wait.sh"; do \
       chmod -R "u=rwX,g=rX,o=rX" ${file} && \
       chown -R root ${file}; done \
    && sed -i -e 's/-Xms\([0-9]\+[kmg]\) -Xmx\([0-9]\+[kmg]\)/-Xms\${JVM_MINIMUM_MEMORY:=\1} -Xmx\${JVM_MAXIMUM_MEMORY:=\2} -Dconfluence.home=\${CONFLUENCE_HOME}/g' ${CONFLUENCE_INSTALL_DIR}/bin/setenv.sh \
    && sed -i -e 's/-XX:ReservedCodeCacheSize=\([0-9]\+[kmg]\)/-XX:ReservedCodeCacheSize=${JVM_RESERVED_CODE_CACHE_SIZE:=\1}/g' ${CONFLUENCE_INSTALL_DIR}/bin/setenv.sh \
    && sed -i -e 's/export CATALINA_OPTS/CATALINA_OPTS="\${CATALINA_OPTS} \${JVM_SUPPORT_RECOMMENDED_ARGS} -DConfluenceHomeLogAppender.disabled=${CONFLUENCE_LOG_STDOUT}"\n\nexport CATALINA_OPTS/g' ${CONFLUENCE_INSTALL_DIR}/bin/setenv.sh \
    \
    && mkdir -p /opt/java/openjdk/lib/fonts/fallback/ \
    && ln -sf /usr/share/fonts/truetype/noto/* /opt/java/openjdk/lib/fonts/fallback/


ARG AGENT_VERSION
ARG PSQL_DRIVER_VERSION=42.7.5

ENV AGENT_PATH=/var/agent
ENV AGENT_FILENAME=atlassian-agent.jar
ENV LIB_PATH=/confluence/WEB-INF/lib
ENV JAVA_OPTS="-javaagent:${AGENT_PATH}/${AGENT_FILENAME} ${JAVA_OPTS}"

RUN mkdir -p                                            ${AGENT_PATH} \
    && curl -o ${AGENT_PATH}/${AGENT_FILENAME} https://github.com/haxqer/confluence/releases/download/v${AGENT_VERSION}/atlassian-agent.jar -L \
    && curl -o ${CONFLUENCE_INSTALL_DIR}/lib/postgresql-${PSQL_DRIVER_VERSION}.jar https://jdbc.postgresql.org/download/postgresql-${PSQL_DRIVER_VERSION}.jar -L \
    && cp ${CONFLUENCE_INSTALL_DIR}/lib/postgresql-${PSQL_DRIVER_VERSION}.jar ${CONFLUENCE_INSTALL_DIR}${LIB_PATH}/postgresql-${PSQL_DRIVER_VERSION}.jar

# Must be declared after setting perms
VOLUME ["${CONFLUENCE_HOME}"]

CMD ["/entrypoint.py"]
ENTRYPOINT ["/usr/bin/tini", "--"]
