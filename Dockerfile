ARG BUILD_FROM=ghcr.io/hassio-addons/base:15.0.1
FROM ${BUILD_FROM}

ARG CLAUDE_CODE_VERSION=latest

# Install Node.js and dependencies
RUN apk add --no-cache \
    nodejs \
    npm \
    git \
    curl \
    less \
    procps \
    jq \
    ripgrep \
    python3 \
    bash

# Create non-root user
RUN addgroup -g 1000 node && \
    adduser -D -u 1000 -G node node && \
    mkdir -p /home/node/.npm-global && \
    chown -R node:node /home/node

USER node

# Install Claude Code
ENV NPM_CONFIG_PREFIX=/home/node/.npm-global
ENV NPM_CONFIG_CACHE=/home/node/.npm
ENV PATH=$PATH:/home/node/.npm-global/bin
RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}

# Switch back to root for copying service scripts
USER root

# Copy S6 service scripts
COPY rootfs /

# Set up /home/node/.claude to use persistent storage (/data)
# This matches claude-docker's mount: CONFIG_DIR:/home/node/.claude
RUN mkdir -p /data/claude && \
    chown node:node /data/claude && \
    ln -sf /data/claude /home/node/.claude

# Default working directory (will cd to work_dir in run script)
WORKDIR /data

# Health check - ensure claude process is running
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s \
    CMD pgrep -f "claude.*c3po" || exit 1
