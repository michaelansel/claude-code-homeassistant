# Claude Code Agent - Home Assistant Add-on

A Home Assistant add-on that runs Claude Code as an automated agent with c3po multi-agent coordination.

## Overview

This add-on enables running Claude Code continuously inside Home Assistant, connected to a c3po coordinator for multi-agent collaboration. Unlike interactive Claude Code sessions, this focuses on **agent mode** - automated task execution, scheduled work, and coordination with other agents.

## Features

- Runs Claude Code as a long-lived service (not Docker-in-Docker)
- Integrated with c3po for multi-agent coordination
- Non-root execution (runs as UID 1000)
- Read-write access to Home Assistant configuration
- Persistent credential storage
- S6 process supervision
- Health checks and automatic restart on failure

## Architecture

### Simplified Design

The add-on is intentionally simple:

1. **Base Image**: Home Assistant add-on base (Alpine Linux with S6)
2. **Runtime**: Node.js with Claude Code installed globally
3. **Service**: Single S6 service that runs `claude -p "/c3po auto"`
4. **Storage**: Persistent `/data` volume for credentials and state

No Python orchestration, no subprocess management, no complexity. The c3po plugin handles all agent coordination.

### How It Works

```
┌─────────────────────────────────────┐
│   Home Assistant Add-on             │
│                                     │
│  ┌───────────────────────────────┐ │
│  │  S6 Service                   │ │
│  │                               │ │
│  │  claude --dangerously-skip-   │ │
│  │    permissions -p "/c3po auto"│ │
│  │                               │ │
│  │  ↓                            │ │
│  │  c3po plugin:                 │ │
│  │  - Poll coordinator           │ │
│  │  - Receive tasks              │ │
│  │  - Execute & reply            │ │
│  └───────────────────────────────┘ │
│                                     │
│  Storage:                           │
│  /config (HA config, read-write)    │
│  /data/claude (persistent)          │
└─────────────────────────────────────┘
              ↕
    ┌─────────────────────┐
    │  c3po Coordinator   │
    │  (mcp.qerk.be)      │
    └─────────────────────┘
              ↕
    ┌─────────────────────┐
    │  Other Agents       │
    │  (desktop, etc.)    │
    └─────────────────────┘
```

## Development

### Prerequisites

- Home Assistant dev environment or local HA installation
- Docker or Finch for building
- Access to c3po coordinator (for testing)

### Local Development

1. **Clone the repository**:
   ```bash
   git clone https://github.com/your-org/claude-code-homeassistant.git
   cd claude-code-homeassistant
   ```

2. **Build locally**:
   ```bash
   docker build -t local/claude-code-agent .
   ```

3. **Test with Docker directly** (before HA integration):
   ```bash
   docker run --rm \
     -e OAUTH_TOKEN="sk-ant-xxx..." \
     -e C3PO_URL="https://mcp.qerk.be" \
     -e C3PO_TOKEN="admin-token" \
     -e MACHINE_NAME="test-agent" \
     -v /tmp/test-config:/config \
     -v /tmp/test-data:/data \
     local/claude-code-agent
   ```

4. **Install in Home Assistant** (development):
   - Copy entire directory to `/addons/claude-code-agent/`
   - Reload add-ons in HA Supervisor
   - Install from local add-ons list

### Testing

#### Unit Testing (Future)

Currently no unit tests - the add-on is simple enough to test end-to-end.

#### Integration Testing

1. **Verify add-on starts**:
   - Check Supervisor logs for "Starting /c3po auto"
   - No fatal errors

2. **Verify c3po enrollment**:
   - Check logs for "c3po plugin setup complete"
   - Verify credentials file exists: `/data/claude/c3po-credentials.json`

3. **Verify agent registration**:
   ```bash
   # From desktop with c3po access
   c3po list-agents
   ```
   Should show your agent as online.

4. **Send test task**:
   ```bash
   claude -p "/c3po send homeassistant echo 'test'"
   ```
   Check add-on logs for task execution.

5. **Verify file access**:
   ```bash
   claude -p "/c3po send homeassistant ls /config"
   ```
   Should list HA configuration files.

### Directory Structure

```
claude-code-homeassistant/
├── config.yaml                    # Add-on metadata & schema
├── build.yaml                     # Multi-arch build config
├── Dockerfile                     # Container image definition
├── rootfs/                        # Files copied to container root
│   └── etc/
│       └── services.d/
│           └── claude-agent/
│               ├── run           # Main service script
│               └── finish        # Cleanup script
├── DOCS.md                       # User documentation
├── README.md                     # This file (dev guide)
├── CHANGELOG.md                  # Version history
├── icon.png                      # Add-on icon (108x108)
└── logo.png                      # Add-on logo (128x128)
```

### Key Files Explained

#### config.yaml
Defines the add-on interface:
- Metadata (name, version, description)
- Architecture support
- Configuration schema
- Volume mounts
- API access requirements

#### Dockerfile
Multi-stage build:
1. Use HA base image (Alpine with S6)
2. Install Node.js and dependencies
3. Create non-root user
4. Install Claude Code via npm
5. Set up persistent storage symlink
6. Copy S6 service scripts

#### rootfs/etc/services.d/claude-agent/run
The entire add-on logic:
1. Validate configuration (OAuth token, c3po URL)
2. First-run setup: install c3po plugin, enroll with coordinator
3. Run `claude -p "/c3po auto"` as the main process
4. S6 supervises and restarts on crash

That's it. No Python, no complexity.

### Building for Production

#### Local Build
```bash
docker build \
  --build-arg BUILD_FROM=ghcr.io/hassio-addons/base:15.0.1 \
  --build-arg CLAUDE_CODE_VERSION=latest \
  -t claude-code-agent:dev .
```

#### Multi-Architecture Build

Uses Home Assistant's builder:

```bash
docker run --rm --privileged \
  -v ~/.docker:/root/.docker \
  -v $(pwd):/data \
  homeassistant/amd64-builder \
  --all -t /data
```

This builds for aarch64, amd64, and armv7 simultaneously.

### Release Process

1. Update version in `config.yaml`
2. Update `CHANGELOG.md`
3. Commit changes
4. Tag release: `git tag -a v0.1.0 -m "Release v0.1.0"`
5. Push: `git push --follow-tags`
6. CI builds and publishes multi-arch images

### Debugging

#### View Logs
In Home Assistant:
- Settings → Add-ons → Claude Code Agent → Log tab

Or via CLI:
```bash
ha addons logs claude-code-agent
```

#### Shell Access
Enable SSH or Terminal add-on, then:
```bash
# View service status
s6-svstat /run/service/claude-agent

# View real-time logs
tail -f /var/log/claude-agent/current

# Check process
ps aux | grep claude

# View persistent storage
ls -la /data/claude/
```

#### Common Issues

**"Permission denied" errors**:
- Check file ownership: `ls -la /home/node/`
- Verify symlink: `ls -la /home/node/.claude`

**"c3po enrollment failed"**:
- Test coordinator connectivity: `curl -v https://mcp.qerk.be/health`
- Verify admin token is correct
- Check for network policy restrictions

**Claude process not starting**:
- Check PATH: `echo $PATH`
- Verify claude installed: `which claude`
- Test manually: `s6-setuidgid node claude --version`

### Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test locally (see Testing section)
5. Submit a pull request

### Design Decisions

#### Why Not Docker-in-Docker?
- Requires privileged mode (security risk)
- Complex volume management
- Root permission issues
- HA Supervisor doesn't recommend it

#### Why Not Python Service?
- Unnecessary complexity
- Claude Code already has built-in c3po support
- S6 provides process supervision
- Keep it simple

#### Why S6?
- Standard for HA add-ons
- Automatic restart on failure
- Proper signal handling
- Integrates with HA Supervisor

#### Why Node User (UID 1000)?
- Matches Claude Code's expected environment
- Avoids root permission issues
- Compatible with npm global installs
- Standard HA add-on practice

### Future Enhancements

Potential improvements (not committed):

1. **Web UI**: View agent status, recent tasks, conversation history
2. **HA Sensors**: Expose metrics (tasks completed, errors, uptime)
3. **Event Integration**: Trigger HA events when tasks complete
4. **Multiple Agents**: Support running multiple agents with different configs
5. **Log Rotation**: Archive claude session logs
6. **Metrics**: Prometheus endpoint for monitoring

### Resources

- [Home Assistant Add-on Documentation](https://developers.home-assistant.io/docs/add-ons/)
- [S6 Overlay Documentation](https://github.com/just-containers/s6-overlay)
- [Claude Code Repository](https://github.com/anthropics/claude-code)
- [c3po Plugin Documentation](https://github.com/michaelansel/claude-code-plugins)
- [Bashio Documentation](https://github.com/hassio-addons/bashio)

## License

MIT License - see LICENSE file for details

## Credits

- Built on [Claude Code](https://github.com/anthropics/claude-code) by Anthropic
- Uses [c3po plugin](https://github.com/michaelansel/claude-code-plugins) for coordination
- Based on [Home Assistant Add-on Base](https://github.com/hassio-addons/base)
