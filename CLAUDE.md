# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Home Assistant add-on that runs Claude Code as an automated agent with c3po multi-agent coordination. The add-on uses S6 process supervision to run a Python watcher (`claude-watcher.py`) that keeps the agent registered in c3po and launches Claude sessions on demand.

Design philosophy: "Radical simplicity" — everything runs as root, no user switching, no Python orchestration overhead beyond the watcher.

## Build Commands

```bash
# Build locally (use finch instead of docker on this machine)
finch build -t claude-code-agent:test .

# Verify build
finch run --rm claude-code-agent:test which claude
finch run --rm claude-code-agent:test node --version
finch run --rm claude-code-agent:test python3 /usr/local/bin/claude-watcher.py --help

# Tag a release (triggers GitHub Actions build + GitHub release)
git tag -a v0.x.0 -m "Release v0.x.0"
git push --follow-tags
```

There are no tests, linters, or formatters configured. Testing is manual per TESTING.md.

## Architecture

### Core Files (the entire implementation)

- **`config.yaml`** — Add-on metadata, version, and configuration schema (options the user sets in HA UI)
- **`Dockerfile`** — Alpine-based container: installs Node.js, npm, Claude Code as root; symlinks `/root/.claude` → `/data/claude`
- **`rootfs/etc/cont-init.d/01-setup.sh`** — Oneshot init: validates config, enrollment, plugin updates, credential validation
- **`rootfs/etc/cont-init.d/02-sessions-context.sh`** — Injects `CLAUDE.md` in work_dir with session log location
- **`rootfs/etc/services.d/claude-agent/run`** — Thin S6 launcher: exports env vars, execs `claude-watcher.py`
- **`rootfs/etc/services.d/claude-agent/finish`** — Unregisters agent from c3po on stop
- **`rootfs/usr/local/bin/claude-watcher.py`** — Watcher loop: keeps agent as "watching" in c3po, launches Claude sessions when messages arrive, logs sessions to `/data/sessions/`

### Runtime Flow

1. S6 runs `cont-init.d/` scripts once on container start:
   - `01-setup.sh`: Validates OAuth token format, c3po URL; ensures `/data/claude` and `/data/sessions` exist; handles first-run c3po enrollment (download setup.py, enroll, install plugin); updates plugins every start; validates credentials against coordinator; recovers MCP config if needed; runs user `init_commands`
   - `02-sessions-context.sh`: Writes `.claude/CLAUDE.md` in work_dir with session log context (only if file doesn't exist or has managed marker)
2. S6 starts the `claude-agent` service (the `run` script)
3. `run` exports env vars (`CLAUDE_CODE_OAUTH_TOKEN`, `C3PO_MACHINE_NAME`, etc.) and `exec`s `claude-watcher.py`
4. `claude-watcher.py` claims "watching" state in c3po (register + unregister-with-keep), then enters poll loop
5. On message received: re-registers as active, launches `claude --dangerously-skip-permissions [--model MODEL] -p "/c3po auto"`, logs to `/data/sessions/session-{ISO}.log`, returns to watching state
6. On stop: `finish` script POSTs to `/agent/api/unregister` (full unregister, no keep)
7. Health check runs `pgrep -f "claude-watcher"` every 30s

### Storage Mapping

- `/config` → Home Assistant configuration (read-write)
- `/data` → Persistent add-on storage: `/data/claude` (credentials, plugins), `/data/sessions` (session logs)
- `/share` → Shared storage between add-ons (read-write)
- `/media` → Media files (read-only)
- Symlinks: `/root/.claude` → `/data/claude`, `/root/.claude.json` → `/data/claude-user-config.json`

### CI/CD

GitHub Actions workflow (`.github/workflows/build.yml`) builds with Docker Buildx and pushes to `ghcr.io/michaelansel/claude-code-homeassistant`. Currently x86_64 only (multi-arch disabled for build speed). Triggers on push to main, version tags, and PRs.

## Key Patterns

**Config validation** in init scripts uses `bashio` helpers:
```bash
if ! bashio::config.has_value 'option_name'; then
    bashio::log.fatal "Error message"
    exit 1
fi
```

**Everything runs as root** — no `s6-setuidgid` needed. Claude Code and all tools run as root in the container.

**One-time setup**: Uses flag file `/data/.c3po-setup-complete` to skip enrollment on subsequent starts.

**Watcher pattern**: Agent stays registered as "watching" between sessions so c3po can track it. Sessions are launched on demand when messages arrive, not on a fixed loop.

## Configuration Options

Required: `oauth_token`, `c3po_coordinator_url`
Optional: `c3po_admin_token` (first run only), `work_dir` (default `/config`), `project_name` (default `homeassistant`), `machine_name` (default `homeassistant`), `model` (Claude model override, e.g. `opus`), `env_vars` (list of `KEY=VALUE` strings), `init_commands` (list of shell commands run before launch)
