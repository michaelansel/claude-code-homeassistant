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

# Install Claude Code as root
RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}

# Copy S6 service scripts
COPY rootfs /

# Set up /root/.claude to use persistent storage (/data)
# Also symlink .claude.json (user-scope config where MCP servers are stored)
RUN mkdir -p /data/claude && \
    mkdir -p /data/sessions && \
    ln -sf /data/claude /root/.claude && \
    ln -sf /data/claude-user-config.json /root/.claude.json

# Default working directory (will cd to work_dir in run script)
WORKDIR /data

# Health check - ensure watcher process is running
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s \
    CMD pgrep -f "claude-watcher" || exit 1
