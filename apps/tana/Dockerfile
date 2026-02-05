# syntax=docker/dockerfile:1

ARG VERSION

FROM ghcr.io/linuxserver/baseimage-selkies:debiantrixie

ARG BUILD_DATE
ARG VERSION
ARG TARGETARCH
LABEL build_version="Linuxserver.io version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="tana-docker"

# title
ENV TITLE=Tana

RUN \
  echo "**** install packages ****" && \
  apt-get update && \
  DEBIAN_FRONTEND=noninteractive \
  apt-get install -y --no-install-recommends \
    chromium \
    chromium-l10n \
    curl \
    dbus-x11 \
    git \
    libgtk-3-0t64 \
    libgtk-3-bin \
    libnotify4 \
    libatspi2.0-0t64 \
    libdrm2 \
    libgbm1 \
    libxcb-dri3-0 \
    libnss3 \
    libasound2t64 \
    libatk1.0-0t64 \
    libatk-bridge2.0-0t64 \
    libglib2.0-bin \
    libsecret-1-0 \
    gnome-keyring \
    socat \
    python3-xdg && \
  echo "**** download and install tana ****" && \
  curl -fsSL -o /tmp/tana.deb \
    "https://github.com/tanainc/tana-desktop-releases/releases/download/v${VERSION}/tana_${VERSION}_${TARGETARCH}.deb" && \
  dpkg -i --force-depends /tmp/tana.deb || true && \
  echo "**** add icon ****" && \
  if [ -f /usr/share/pixmaps/tana.png ]; then \
    cp /usr/share/pixmaps/tana.png /usr/share/selkies/www/icon.png; \
  elif [ -f /opt/Tana/resources/app/icon.png ]; then \
    cp /opt/Tana/resources/app/icon.png /usr/share/selkies/www/icon.png; \
  else \
    curl -o /usr/share/selkies/www/icon.png \
      https://tana.inc/favicon.png 2>/dev/null || \
    touch /usr/share/selkies/www/icon.png; \
  fi && \
  echo "**** setup OAuth browser handling ****" && \
  printf '#!/bin/bash\nURL="$1"\nif [[ "$URL" == tana://* ]]; then\n  exec /usr/bin/tana --no-sandbox "$URL"\nfi\nexec /usr/bin/chromium --no-sandbox "$@"\n' > /usr/local/bin/xdg-open && \
  chmod +x /usr/local/bin/xdg-open && \
  printf '[Desktop Entry]\nName=Tana\nExec=/usr/bin/tana --no-sandbox %%U\nType=Application\nMimeType=x-scheme-handler/tana;\nCategories=Office;\n' > /usr/share/applications/tana.desktop && \
  update-desktop-database /usr/share/applications 2>/dev/null || true && \
  echo "**** cleanup ****" && \
  apt-get autoclean && \
  rm -rf \
    /config/.cache \
    /config/.launchpadlib \
    /var/lib/apt/lists/* \
    /var/tmp/* \
    /tmp/*

# add local files
COPY /root /

# ports and volumes
EXPOSE 3000 18262
VOLUME /config
