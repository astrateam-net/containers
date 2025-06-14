# syntax=docker/dockerfile:1

ARG BASE_IMAGE=eclipse-temurin:21-noble
FROM $BASE_IMAGE

LABEL maintainer="dc-deployments@atlassian.com"
LABEL securitytxt="https://www.atlassian.com/.well-known/security.txt"

ENV APP_NAME=jira
ENV RUN_USER=jira
ENV RUN_GROUP=jira
ENV RUN_UID=2001
ENV RUN_GID=2001

# https://confluence.atlassian.com/display/JSERVERM/Important+directories+and+files
ENV JIRA_HOME=/var/atlassian/application-data/jira
ENV JIRA_INSTALL_DIR=/opt/atlassian/jira

WORKDIR $JIRA_HOME

# Expose HTTP port
EXPOSE 8080

COPY entrypoint.py \
     shutdown-wait.sh \
     shared-components/image/entrypoint_helpers.py  /
COPY shared-components/support                      /opt/atlassian/support
COPY config/*                                       /opt/atlassian/etc/

RUN apt-get update \
    && apt-get upgrade -y \
    && apt-get install -y --no-install-recommends fontconfig python3 python3-jinja2 tini \
    && apt-get clean autoclean && apt-get autoremove -y && rm -rf /var/lib/apt/lists/*

ARG VERSION
ARG JIRA_VERSION=${VERSION}
ENV JIRA_VERSION=${JIRA_VERSION}
ARG ARTEFACT_NAME=atlassian-jira-software
ENV ARTEFACT_NAME=${ARTEFACT_NAME}
ARG DOWNLOAD_URL=https://product-downloads.atlassian.com/software/jira/downloads/${ARTEFACT_NAME}-${JIRA_VERSION}.tar.gz

RUN groupadd --gid ${RUN_GID} ${RUN_GROUP} \
    && useradd --uid ${RUN_UID} --gid ${RUN_GID} --home-dir ${JIRA_HOME} --shell /bin/bash ${RUN_USER} \
    && echo PATH=$PATH > /etc/environment \
    && mkdir -p ${JIRA_INSTALL_DIR} \
    && curl -fsSL ${DOWNLOAD_URL} -o /tmp/${ARTEFACT_NAME}-${JIRA_VERSION}.tar.gz \
    && curl -fsSL ${DOWNLOAD_URL}.sha256 -o /tmp/${ARTEFACT_NAME}-${JIRA_VERSION}.tar.gz.sha256 \
    && set -e; cd /tmp && sha256sum -c ${ARTEFACT_NAME}-${JIRA_VERSION}.tar.gz.sha256 \
    && tar -xf /tmp/${ARTEFACT_NAME}-${JIRA_VERSION}.tar.gz --strip-components=1 -C "${JIRA_INSTALL_DIR}" \
    && rm /tmp/${ARTEFACT_NAME}* \
    && chmod -R 550                                 ${JIRA_INSTALL_DIR}/ \
    && chown -R ${RUN_USER}:root                    ${JIRA_INSTALL_DIR}/ \
    && mkdir -p ${JIRA_INSTALL_DIR}/conf/Catalina/localhost && chmod 770 ${JIRA_INSTALL_DIR}/conf/Catalina/localhost \
    && for dir in logs temp work; do \
         chmod -R 770 ${JIRA_INSTALL_DIR}/${dir}; \
       done \
    && chmod 770 ${JIRA_INSTALL_DIR}/conf/web.xml \
    && sed -i -e 's/^JVM_SUPPORT_RECOMMENDED_ARGS=""$/: \${JVM_SUPPORT_RECOMMENDED_ARGS:=""}/g' ${JIRA_INSTALL_DIR}/bin/setenv.sh \
    && sed -i -e 's/^JVM_\(.*\)_MEMORY="\(.*\)"$/: \${JVM_\1_MEMORY:=\2}/g' ${JIRA_INSTALL_DIR}/bin/setenv.sh \
    && sed -i -e 's/-XX:ReservedCodeCacheSize=\([0-9]\+[kmg]\)/-XX:ReservedCodeCacheSize=${JVM_RESERVED_CODE_CACHE_SIZE:=\1}/g' ${JIRA_INSTALL_DIR}/bin/setenv.sh \
    \
    && touch /etc/container_id \
    && chown ${RUN_USER}:${RUN_GROUP}               /etc/container_id \
    && chown -R ${RUN_USER}:${RUN_GROUP}            ${JIRA_HOME} \
    && for file in "/opt/atlassian/support /entrypoint.py /entrypoint_helpers.py /shutdown-wait.sh"; do \
       chmod -R "u=rwX,g=rX,o=rX" ${file} && \
       chown -R root ${file}; done


ARG AGENT_VERSION
ARG PSQL_DRIVER_VERSION=42.7.5

ENV AGENT_PATH=/var/agent
ENV AGENT_FILENAME=atlassian-agent.jar
ENV JAVA_OPTS="-javaagent:${AGENT_PATH}/${AGENT_FILENAME} ${JAVA_OPTS}"

RUN mkdir -p                                        ${AGENT_PATH} \
    && curl -o ${AGENT_PATH}/${AGENT_FILENAME} https://github.com/haxqer/confluence/releases/download/v${AGENT_VERSION}/atlassian-agent.jar -L \
    && curl -o ${JIRA_INSTALL_DIR}/lib/postgresql-${PSQL_DRIVER_VERSION}.jar https://jdbc.postgresql.org/download/postgresql-${PSQL_DRIVER_VERSION}.jar -L

# Must be declared after setting perms
VOLUME ["${JIRA_HOME}"]

CMD ["/entrypoint.py"]
ENTRYPOINT ["/usr/bin/tini", "--"]
