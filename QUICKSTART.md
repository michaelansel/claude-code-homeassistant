# Quick Start Guide

Get the Claude Code Agent add-on running in 5 minutes.

## Prerequisites

Before you start, have these ready:

1. **Home Assistant** installed and running
2. **Claude Code OAuth Token** - Get it by running:
   ```bash
   npm install -g @anthropic-ai/claude-code
   claude setup-token
   ```
3. **c3po Coordinator Access** - URL and admin token

## Installation Steps

### Step 1: Add Repository to Home Assistant

1. In Home Assistant, go to **Settings → Add-ons → Add-on Store**
2. Click the menu (⋮) in the top right
3. Click **Repositories**
4. Add this URL: `https://github.com/michaelansel/claude-code-homeassistant`
5. Click **Add**

### Step 2: Install the Add-on

1. Refresh the add-on store
2. Find "Claude Code Agent" in the list
3. Click it and click **Install**
4. Wait for installation to complete

### Step 3: Configure the Add-on

1. Go to the **Configuration** tab
2. Enter your settings:

```yaml
oauth_token: "sk-ant-api03-xxxxxxxxxxxx"
c3po_coordinator_url: "https://mcp.qerk.be"
c3po_admin_token: "your-admin-token"
work_dir: "/config"
project_name: "homeassistant"
machine_name: "homeassistant"
```

3. Click **Save**

### Step 4: Start the Add-on

1. Go to the **Info** tab
2. Click **Start**
3. Wait for startup (may take 30-60 seconds first time)

### Step 5: Verify It's Working

1. Go to the **Log** tab
2. Look for these messages:
   ```
   [INFO] Starting Claude Code agent...
   [INFO] Setting up c3po plugin (first run)...
   [INFO] c3po plugin setup complete
   [INFO] Starting /c3po auto in /config...
   ```

3. Verify agent is registered:
   ```bash
   # On your desktop
   c3po list-agents
   ```

   You should see your agent listed!

### Step 6: Send Your First Task

From your desktop (or another c3po agent):

```bash
claude -p "/c3po send homeassistant ls /config"
```

Check the add-on logs - you should see the task execute!

## What Next?

### Remove Admin Token (Optional)

After successful first start, you can remove the `c3po_admin_token` from the configuration:

1. Go to **Configuration** tab
2. Delete the line: `c3po_admin_token: "..."`
3. Click **Save**
4. Restart is not needed

The machine credentials are stored persistently in `/data/claude/c3po-credentials.json`.

### Set Up Automations

You can now:
- Send tasks to your HA agent from other machines
- Have the agent analyze your HA configuration
- Coordinate between multiple agents

### Monitor Activity

- Check logs in **Settings → Add-ons → Claude Code Agent → Log**
- Watch agent status in c3po coordinator
- Review files in `/config` for agent changes

## Troubleshooting

### Add-on Won't Start

**Check the logs first!** Go to Settings → Add-ons → Claude Code Agent → Log

Common issues:

#### "OAuth token required"
- You forgot to add the OAuth token in configuration
- Solution: Add `oauth_token: "sk-ant-xxx..."` and restart

#### "Invalid token format"
- Token doesn't start with `sk-ant-` or `sk-at-`
- Solution: Generate new token with `claude setup-token`

#### "c3po admin token required for first-time setup"
- First run needs admin token for enrollment
- Solution: Add `c3po_admin_token: "xxx"` to configuration

#### "c3po enrollment failed"
- Check coordinator URL is correct
- Verify admin token is valid
- Check network connectivity from HA to coordinator

### Agent Not Receiving Tasks

1. Verify agent is online:
   ```bash
   c3po list-agents
   ```

2. Check agent logs for errors

3. Try a simple task:
   ```bash
   claude -p "/c3po send homeassistant echo test"
   ```

### Need to Re-enroll

If you need to re-enroll (e.g., coordinator was reset):

1. Stop the add-on
2. In Home Assistant's Terminal or SSH:
   ```bash
   rm /data/.c3po-setup-complete
   rm /data/claude/c3po-credentials.json
   ```
3. Add `c3po_admin_token` back to configuration
4. Start the add-on

## Examples

### Check HA Configuration

```bash
claude -p "/c3po send homeassistant Validate configuration.yaml syntax"
```

### List Automations

```bash
claude -p "/c3po send homeassistant List all automations with brief descriptions"
```

### Find Entity IDs

```bash
claude -p "/c3po send homeassistant Find all light entity IDs"
```

### Analyze Scripts

```bash
claude -p "/c3po send homeassistant Analyze scripts.yaml for potential issues"
```

## Configuration Reference

| Option | Required | Default | Description |
|--------|----------|---------|-------------|
| `oauth_token` | Yes | - | Your Claude Code OAuth token |
| `c3po_coordinator_url` | Yes | - | c3po coordinator URL |
| `c3po_admin_token` | First run | - | Admin token (remove after enrollment) |
| `work_dir` | No | `/config` | Working directory |
| `project_name` | No | `homeassistant` | Project name for Claude sessions |
| `machine_name` | No | `homeassistant` | Agent identifier in c3po |

## Tips

- Use descriptive `machine_name` if you run multiple HA instances
- Keep `work_dir` as `/config` to access HA configuration
- Remove `c3po_admin_token` after first successful start
- Check logs regularly for errors or warnings
- Test with simple tasks before complex automations

## Getting Help

- **Documentation**: See DOCS.md for detailed information
- **Issues**: Report bugs at GitHub Issues
- **c3po Help**: Check c3po plugin documentation
- **Claude Code**: See claude-code documentation

## Next Steps

Once you have the agent running:

1. **Set up desktop agent** - Install claude-code on your desktop with c3po
2. **Coordinate agents** - Have them work together on tasks
3. **Automate tasks** - Use c3po to schedule regular checks
4. **Integrate with HA** - Trigger tasks from HA automations (future feature)

## Advanced Usage

### Multiple Agents

To run multiple agents (e.g., for different projects):

1. Install the add-on multiple times (via Supervisor)
2. Give each instance unique:
   - `machine_name` - Must be unique
   - `work_dir` - Use `/share/project1`, etc.
   - `project_name` - Different contexts

### Custom Working Directory

To work outside `/config`:

```yaml
work_dir: "/share/projects/myproject"
```

The agent will start in this directory and execute tasks there.

### Monitoring

Watch agent activity:

```bash
# From HA Terminal or SSH
tail -f /var/log/claude-agent/current
```

Or use the Logs tab in Home Assistant UI.

---

**That's it!** You now have a Claude Code agent running in Home Assistant, coordinated via c3po. Start sending tasks and exploring what's possible!
