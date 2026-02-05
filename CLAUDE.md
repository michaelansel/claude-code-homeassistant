# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Home Assistant add-on that runs Claude Code as an automated agent with c3po multi-agent coordination. The add-on uses S6 process supervision to run `claude -p "/c3po auto"` in a container, enabling background task execution coordinated through c3po.

Design philosophy: "Radical simplicity" — only 3 core implementation files, no Docker-in-Docker, no Python orchestration layer.

## Build Commands

```bash
# Build locally (use finch instead of docker on this machine)
finch build -t claude-code-agent:test .

# Verify build
finch run --rm claude-code-agent:test which claude
finch run --rm claude-code-agent:test node --version

# Tag a release (triggers GitHub Actions build + GitHub release)
git tag -a v0.x.0 -m "Release v0.x.0"
git push --follow-tags
```

There are no tests, linters, or formatters configured. Testing is manual per TESTING.md.

## Architecture

### Core Files (the entire implementation)

- **`config.yaml`** — Add-on metadata, version, and configuration schema (options the user sets in HA UI)
- **`Dockerfile`** — Alpine-based container: installs Node.js, npm, Claude Code, creates non-root `node` user (UID 1000)
- **`rootfs/etc/services.d/claude-agent/run`** — S6 service script: validates config, handles first-run c3po enrollment, launches Claude
- **`rootfs/etc/services.d/claude-agent/finish`** — S6 cleanup script

### Runtime Flow

1. S6 starts the `run` script
2. Validates OAuth token format (`sk-ant-*` or `sk-at-*`) and c3po URL using `bashio`
3. On first run only: installs c3po plugin, runs enrollment with admin token, sets flag `/data/.c3po-setup-complete`
4. Executes `claude --dangerously-skip-permissions -p "/c3po auto"` as the `node` user
5. S6 auto-restarts on crash; health check runs `pgrep -f "claude.*c3po"` every 30s

### Storage Mapping

- `/config` → Home Assistant configuration (read-write)
- `/data` → Persistent add-on storage (credentials survive restarts via symlink `/home/node/.claude` → `/data/claude`)
- `/share` → Shared storage between add-ons (read-write)
- `/media` → Media files (read-only)

### CI/CD

GitHub Actions workflow (`.github/workflows/build.yml`) builds with Docker Buildx and pushes to `ghcr.io/michaelansel/claude-code-homeassistant`. Currently x86_64 only (multi-arch disabled for build speed). Triggers on push to main, version tags, and PRs.

## Key Patterns

**Config validation** in the run script uses `bashio` helpers:
```bash
if ! bashio::config.has_value 'option_name'; then
    bashio::log.fatal "Error message"
    exit 1
fi
```

**Running commands as non-root**: `s6-setuidgid node bash <<EOF ... EOF`

**One-time setup**: Uses flag files in `/data/` to skip setup on subsequent starts.

## Configuration Options

Required: `oauth_token`, `c3po_coordinator_url`
Optional: `c3po_admin_token` (first run only), `work_dir` (default `/config`), `project_name` (default `homeassistant`), `machine_name` (default `homeassistant`)
