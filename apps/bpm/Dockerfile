# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom

ARG VERSION
FROM docker.io/atlassian/jira-software:${VERSION}

ENV AGENT_PATH=/var/agent
ENV AGENT_FILENAME=atlassian-agent.jar
ENV JAVA_OPTS="-javaagent:${AGENT_PATH}/${AGENT_FILENAME} ${JAVA_OPTS}"

USER root

COPY jira.jar ${AGENT_PATH}/${AGENT_FILENAME}
RUN chmod 444 ${AGENT_PATH}/${AGENT_FILENAME}

COPY entrypoint-wrapper.sh /entrypoint-wrapper.sh
RUN chmod 555 /entrypoint-wrapper.sh

# Prepare directories for optional CA certs
RUN mkdir -p /opt/atlassian/certificates /var/ssl

CMD ["/entrypoint-wrapper.sh"]
