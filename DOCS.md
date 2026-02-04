# Claude Code Agent - Home Assistant Add-on

Run Claude Code as an automated agent inside Home Assistant with c3po multi-agent coordination.

## What This Add-on Does

This add-on runs a Claude Code agent continuously in the background, connected to a c3po coordinator. The agent can:

- Execute tasks assigned by the c3po coordinator
- Communicate with other Claude Code agents
- Access and modify your Home Assistant configuration files
- Respond to automation triggers via c3po integration

This is designed for **agent mode** - automated, scheduled tasks coordinated through c3po. It does NOT provide an interactive chat interface.

## Prerequisites

Before installing this add-on, you need:

1. **Claude Code OAuth Token** - Get this by running `claude setup-token` on your desktop
2. **c3po Coordinator Access** - URL and admin token for your c3po coordinator

### Getting Your OAuth Token

On your desktop machine (not in Home Assistant):

```bash
# Install Claude Code (if not already installed)
npm install -g @anthropic-ai/claude-code

# Generate OAuth token
claude setup-token
```

This will open a browser and generate a token starting with `sk-ant-` or `sk-at-`. Save this token for the add-on configuration.

### Setting Up c3po Coordinator

You need access to a c3po coordinator server. If you don't have one:

1. Use the public coordinator at `https://mcp.qerk.be` (requires admin token)
2. Or deploy your own c3po coordinator (see c3po documentation)

You'll need:
- **Coordinator URL**: e.g., `https://mcp.qerk.be`
- **Admin Token**: Required for first-time enrollment only

## Installation

1. Add this repository to your Home Assistant add-on store
2. Install the "Claude Code Agent" add-on
3. Configure the add-on (see Configuration section)
4. Start the add-on
5. Check logs to verify successful startup

## Configuration

### Required Configuration

```yaml
oauth_token: "sk-ant-api03-xxx..."
c3po_coordinator_url: "https://mcp.qerk.be"
c3po_admin_token: "your-admin-token"
work_dir: "/config"
project_name: "homeassistant"
machine_name: "homeassistant"
```

### Configuration Options

| Option | Description | Default |
|--------|-------------|---------|
| `oauth_token` | Claude Code OAuth token (from `claude setup-token`) | *required* |
| `c3po_coordinator_url` | URL of your c3po coordinator | *required* |
| `c3po_admin_token` | Admin token for c3po enrollment (only needed first time) | *optional after enrollment* |
| `work_dir` | Working directory for the agent | `/config` |
| `project_name` | Project name for Claude sessions | `homeassistant` |
| `machine_name` | Machine identifier for c3po (should be unique) | `homeassistant` |

### After First Run

After the add-on starts successfully for the first time:

1. Machine credentials are stored in `/data/claude/c3po-credentials.json`
2. The agent is enrolled with the c3po coordinator
3. You can **remove** `c3po_admin_token` from the configuration (it's no longer needed)

## Usage

### Verifying Agent Registration

After starting the add-on, verify your agent is registered:

```bash
# On your desktop with c3po CLI access
c3po list-agents
```

You should see your Home Assistant agent listed (with the name from `machine_name` config).

### Sending Tasks to Your Agent

From another Claude Code instance with c3po:

```bash
claude -p "/c3po send <machine-name> Check my automations for errors"
```

Or use the c3po coordinator's web interface to assign tasks.

### Example Workflows

#### 1. Check Configuration from Desktop

On your desktop:
```bash
claude -p "/c3po send homeassistant List all automation files in /config"
```

Your HA agent executes the task and replies through c3po.

#### 2. Automated Configuration Validation

Set up a scheduled task in c3po coordinator to have the agent:
- Check `automations.yaml` for syntax errors
- Validate `configuration.yaml`
- Report any issues

#### 3. Multi-Agent Coordination

Have multiple agents work together:
- Desktop agent plans changes
- HA agent validates against current config
- Desktop agent applies approved changes

### Viewing Logs

Check the add-on logs in Home Assistant:
1. Go to Settings → Add-ons
2. Click "Claude Code Agent"
3. Click "Log" tab

All Claude Code output appears here, including:
- Agent startup messages
- Task execution logs
- c3po communication logs

## File Access

The agent has access to:

- `/config` - Home Assistant configuration (read-write)
- `/share` - Shared storage between add-ons (read-write)
- `/media` - Media files (read-only)

The agent's working directory is `/config` by default, so it can directly access:
- `configuration.yaml`
- `automations.yaml`
- `scripts.yaml`
- All other HA config files

## Security Notes

- The add-on runs as a non-root user (UID 1000)
- OAuth token is stored securely by Home Assistant Supervisor
- No Docker socket access required
- No privileged mode required
- Agent can modify files in `/config` - use with caution

## Troubleshooting

### Add-on Won't Start

Check logs for error messages:

**"OAuth token required"**
- Add your OAuth token to configuration

**"Invalid token format"**
- Token must start with `sk-ant-` or `sk-at-`
- Generate new token with `claude setup-token`

**"c3po admin token required for first-time setup"**
- Add `c3po_admin_token` to configuration for initial enrollment

**"c3po enrollment failed"**
- Check coordinator URL is correct
- Verify admin token is valid
- Check network connectivity

### Agent Not Receiving Tasks

1. Verify agent is registered:
   ```bash
   c3po list-agents
   ```

2. Check agent status in c3po coordinator

3. Review add-on logs for connection errors

### Re-enrolling Agent

If you need to re-enroll (e.g., coordinator was reset):

1. Stop the add-on
2. In SSH or Terminal add-on, run:
   ```bash
   rm /data/.c3po-setup-complete
   rm /data/claude/c3po-credentials.json
   ```
3. Add `c3po_admin_token` back to configuration
4. Start the add-on

## Advanced Configuration

### Custom Working Directory

To work in a different directory:

```yaml
work_dir: "/share/projects"
```

The agent will start in this directory and execute all tasks there.

### Multiple Agents

To run multiple agents (e.g., for different projects), install multiple instances of this add-on with different:
- `machine_name` - Must be unique per instance
- `work_dir` - Different working directories
- `project_name` - Different project contexts

## Support

For issues and feature requests:
- GitHub: [claude-code-homeassistant issues](https://github.com/your-org/claude-code-homeassistant/issues)
- c3po Documentation: [c3po docs](https://github.com/michaelansel/claude-code-plugins)

## Credits

- Built on [Claude Code](https://github.com/anthropics/claude-code)
- Uses [c3po plugin](https://github.com/michaelansel/claude-code-plugins) for coordination
- Based on [Home Assistant Add-on Base](https://github.com/hassio-addons/base)
