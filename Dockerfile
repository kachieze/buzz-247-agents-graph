# syntax=docker/dockerfile:1.7
# Agent runtime: buzz-acp + cursor-agent acp + MCP + Playwright Chromium.
# Grafana Alloy is a sidecar (not this image). Never bake secrets.

ARG UBUNTU_VERSION=24.04
ARG BUZZ_RELEASE=desktop-v0.5.20
ARG NODE_VERSION=22
ARG CURSOR_VERSION=latest
ARG GH_CLI_VERSION=2.67.0

FROM rust:bookworm AS buzz-bins
ARG BUZZ_RELEASE
RUN apt-get update && apt-get install -y --no-install-recommends git pkg-config libssl-dev \
  && rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 --branch "${BUZZ_RELEASE}" https://github.com/block/buzz.git /src
WORKDIR /src
RUN cargo build --release -p buzz-cli -p buzz-acp \
  && strip target/release/buzz target/release/buzz-acp

FROM ubuntu:${UBUNTU_VERSION}
ARG BUZZ_RELEASE
ARG NODE_VERSION
ARG CURSOR_VERSION
ARG GH_CLI_VERSION
ARG TARGETARCH

LABEL org.opencontainers.image.source="https://github.com/kachieze/buzz-247-agents-graph" \
      org.opencontainers.image.revision="${BUZZ_RELEASE}" \
      org.opencontainers.image.title="buzz-247-agent-runtime"

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    BUZZ_RELEASE=${BUZZ_RELEASE} \
    NPM_CONFIG_UPDATE_NOTIFIER=false

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git jq python3 python3-pip build-essential \
      gosu gnupg openssl unzip \
      libnss3 libnspr4 libatk1.0-0 libatk-bridge2.0-0 libcups2 libdrm2 \
      libxkbcommon0 libxcomposite1 libxdamage1 libxfixes3 libxrandr2 \
      libgbm1 libasound2t64 libpango-1.0-0 libcairo2 libatspi2.0-0 \
      fonts-liberation xvfb \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL "https://deb.nodesource.com/setup_${NODE_VERSION}.x" | bash - \
    && apt-get update && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

RUN arch="$(dpkg --print-architecture)" \
    && curl -fsSL "https://github.com/cli/cli/releases/download/v${GH_CLI_VERSION}/gh_${GH_CLI_VERSION}_linux_${arch}.tar.gz" \
      | tar -xz -C /tmp \
    && mv "/tmp/gh_${GH_CLI_VERSION}_linux_${arch}/bin/gh" /usr/local/bin/gh \
    && rm -rf "/tmp/gh_${GH_CLI_VERSION}_linux_${arch}"

COPY --from=buzz-bins /src/target/release/buzz /usr/local/bin/buzz
COPY --from=buzz-bins /src/target/release/buzz-acp /usr/local/bin/buzz-acp

# Official Cursor CLI installer; pin with CURSOR_VERSION when the installer honors it.
RUN curl -fsSL https://cursor.com/install | bash \
    && ln -sf /root/.local/bin/cursor-agent /usr/local/bin/cursor-agent || \
       ln -sf /usr/local/bin/cursor /usr/local/bin/cursor-agent || true \
    && (command -v cursor-agent || find /root /usr /opt -name 'cursor-agent' -o -name 'cursor' 2>/dev/null | head)

ENV PLAYWRIGHT_BROWSERS_PATH=/opt/playwright
COPY src/mcp /opt/mcp
RUN cd /opt/mcp && npm install --omit=dev \
    && chmod +x /opt/mcp/server.mjs \
    && mkdir -p /opt/playwright \
    && npx --prefix /opt/mcp --yes playwright@1.50.0 install --with-deps chromium

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY scripts/github-token-refresh.sh /usr/local/bin/github-token-refresh.sh
RUN chmod 0755 /usr/local/bin/entrypoint.sh /usr/local/bin/github-token-refresh.sh

RUN if ! getent passwd agent >/dev/null; then \
      if getent passwd 1000 >/dev/null; then \
        usermod -l agent "$(getent passwd 1000 | cut -d: -f1)"; \
        if getent group 1000 >/dev/null; then groupmod -n agent "$(getent group 1000 | cut -d: -f1)" || true; fi; \
      else \
        useradd --uid 1000 --create-home --shell /bin/bash agent; \
      fi; \
    fi \
    && mkdir -p /agents \
    && chown 1000:1000 /agents \
    && if [ -d /root/.local ]; then mkdir -p /home/agent && cp -a /root/.local /home/agent/.local && chown -R 1000:1000 /home/agent; fi \
    && ln -sf /home/agent/.local/bin/cursor-agent /usr/local/bin/cursor-agent 2>/dev/null || true

USER agent
WORKDIR /home/agent
HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 \
  CMD bash -lc 'pgrep -x buzz-acp >/dev/null'

USER root
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
