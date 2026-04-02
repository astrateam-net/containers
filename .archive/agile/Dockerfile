# syntax=docker/dockerfile:1

ARG VERSION
FROM docker.io/atlassian/jira-software:${VERSION}

ARG AGENT_VERSION

ENV AGENT_PATH=/var/agent
ENV AGENT_FILENAME=atlassian-agent.jar
ENV JAVA_OPTS="-javaagent:${AGENT_PATH}/${AGENT_FILENAME} ${JAVA_OPTS}"

USER root
RUN mkdir -p ${AGENT_PATH} \
    && curl -fsSL -o ${AGENT_PATH}/${AGENT_FILENAME} \
       https://github.com/haxqer/confluence/releases/download/v${AGENT_VERSION}/atlassian-agent.jar
USER jira
