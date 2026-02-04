# Testing Guide

This guide covers testing the Claude Code Agent add-on before publishing.

## Prerequisites

- Home Assistant installation (dev environment or production)
- Valid Claude Code OAuth token
- Access to c3po coordinator (URL + admin token)
- Docker or Finch for local builds

## Phase 1: Local Build Testing

### Build the Container

```bash
cd ~/Code/claude-code-homeassistant

# Build for your architecture
docker build -t claude-code-agent:test .

# Verify build succeeded
docker images | grep claude-code-agent
```

**Expected Output:**
```
claude-code-agent   test   <hash>   Just now   <size>
```

### Build Validation

Check Dockerfile syntax:
```bash
docker run --rm -i hadolint/hadolint < Dockerfile
```

Verify all files copied:
```bash
docker run --rm claude-code-agent:test ls -la /etc/services.d/claude-agent/
```

**Expected:**
```
-rwxr-xr-x  finish
-rwxr-xr-x  run
```

### Quick Smoke Test (Limited)

Note: This won't work fully because bashio isn't available outside HA, but you can test basic setup:

```bash
docker run --rm claude-code-agent:test node --version
docker run --rm claude-code-agent:test which claude
docker run --rm claude-code-agent:test s6-setuidgid node claude --version
```

**Expected:** All commands succeed, show versions

## Phase 2: Home Assistant Installation Testing

### Option A: Local Add-on Repository

1. Copy directory to Home Assistant:
   ```bash
   scp -r ~/Code/claude-code-homeassistant root@homeassistant.local:/addons/claude-code-agent
   ```

2. In Home Assistant:
   - Settings → Add-ons → Add-on Store
   - Menu (⋮) → Check for updates
   - Add-on should appear in "Local add-ons"

### Option B: GitHub Repository (Recommended)

1. Create GitHub repository
2. Push code:
   ```bash
   cd ~/Code/claude-code-homeassistant
   gh repo create claude-code-homeassistant --public
   git remote add origin <url>
   git push -u origin main
   ```

3. In Home Assistant:
   - Settings → Add-ons → Add-on Store
   - Menu (⋮) → Repositories
   - Add: `https://github.com/your-username/claude-code-homeassistant`

### Install the Add-on

1. Find "Claude Code Agent" in add-on store
2. Click and click "Install"
3. Wait for installation

**Verify Installation:**
- No errors in Supervisor logs
- Add-on appears in installed list
- Configuration tab loads

## Phase 3: Configuration Testing

### Test 1: Missing OAuth Token

**Config:**
```yaml
oauth_token: ""
c3po_coordinator_url: "https://mcp.qerk.be"
c3po_admin_token: "test"
```

**Start add-on**

**Expected Result:**
- Add-on fails to start
- Logs show: "OAuth token required in add-on configuration"

### Test 2: Invalid OAuth Token Format

**Config:**
```yaml
oauth_token: "invalid-token"
c3po_coordinator_url: "https://mcp.qerk.be"
c3po_admin_token: "test"
```

**Start add-on**

**Expected Result:**
- Add-on fails to start
- Logs show: "Invalid token format (must start with sk-ant- or sk-at-)"

### Test 3: Missing c3po URL

**Config:**
```yaml
oauth_token: "sk-ant-test123"
c3po_coordinator_url: ""
c3po_admin_token: "test"
```

**Start add-on**

**Expected Result:**
- Add-on fails to start
- Logs show: "c3po coordinator URL required"

### Test 4: Valid Configuration (First Run)

**Config:**
```yaml
oauth_token: "<your-real-oauth-token>"
c3po_coordinator_url: "https://mcp.qerk.be"
c3po_admin_token: "<your-real-admin-token>"
work_dir: "/config"
project_name: "homeassistant"
machine_name: "test-homeassistant"
```

**Start add-on**

**Expected Result:**
- Add-on starts successfully
- Logs show:
  ```
  [INFO] Starting Claude Code agent...
  [INFO] Setting up c3po plugin (first run)...
  [INFO] c3po plugin setup complete
  [INFO] Machine credentials stored in /data/claude/c3po-credentials.json
  [INFO] Starting /c3po auto in /config...
  ```

**Verify:**
```bash
# From desktop with c3po
c3po list-agents
```
Should show your agent (machine_name: test-homeassistant)

## Phase 4: Functionality Testing

### Test 5: Agent Receives Tasks

**From desktop:**
```bash
claude -p "/c3po send test-homeassistant echo 'Hello from desktop'"
```

**Check add-on logs**

**Expected Result:**
- Logs show task received
- Logs show task execution
- Desktop receives reply: "Hello from desktop"

### Test 6: File Access - Read

**From desktop:**
```bash
claude -p "/c3po send test-homeassistant ls /config"
```

**Expected Result:**
- Agent lists files in /config
- Shows configuration.yaml, automations.yaml, etc.

### Test 7: File Access - Write

**From desktop:**
```bash
claude -p "/c3po send test-homeassistant Create a test file /config/test-claude-agent.txt with content 'Test'"
```

**Verify:**
```bash
# In Home Assistant Terminal or SSH
cat /config/test-claude-agent.txt
```

**Expected:** File exists with content "Test"

**Cleanup:**
```bash
rm /config/test-claude-agent.txt
```

### Test 8: Persistent Credentials

1. **Stop the add-on**
2. **Remove admin token from config:**
   ```yaml
   c3po_admin_token: ""  # Or delete this line
   ```
3. **Start the add-on**

**Expected Result:**
- Add-on starts successfully
- Logs show: "c3po already enrolled, using stored credentials"
- Agent still registered in c3po coordinator
- Agent still receives tasks

### Test 9: Complex Task Execution

**From desktop:**
```bash
claude -p "/c3po send test-homeassistant Analyze configuration.yaml and report any deprecated configuration"
```

**Expected Result:**
- Agent reads configuration.yaml
- Agent analyzes content
- Agent replies with findings
- No crashes or errors

## Phase 5: Resilience Testing

### Test 10: Restart Behavior

1. **Restart Home Assistant**
2. **Check add-on auto-starts** (if enabled)
3. **Verify agent still works:**
   ```bash
   claude -p "/c3po send test-homeassistant pwd"
   ```

**Expected:** Agent responds correctly

### Test 11: Manual Stop/Start

1. **Stop add-on**
2. **Start add-on**
3. **Check logs for clean startup**
4. **Verify agent receives tasks**

**Expected:** No errors, clean restart

### Test 12: Health Check

**Wait 30 seconds after startup**

**Check container health:**
```bash
# In HA Terminal/SSH
docker ps | grep claude-code-agent
```

**Expected:** Status shows "healthy"

If unhealthy:
```bash
docker inspect <container-id> | jq '.[0].State.Health'
```

### Test 13: Process Crash Recovery

**Kill the claude process:**
```bash
# In add-on container (via Terminal or SSH)
pkill -9 -f claude
```

**Watch logs**

**Expected:**
- S6 detects process died
- S6 automatically restarts service
- Agent reconnects to c3po
- Agent continues working

## Phase 6: Edge Cases

### Test 14: Invalid c3po Admin Token (First Run)

1. **Remove /data/.c3po-setup-complete**
2. **Remove /data/claude/c3po-credentials.json**
3. **Set invalid admin token in config**
4. **Start add-on**

**Expected:**
- Enrollment fails
- Logs show error
- Add-on stops

### Test 15: Missing c3po Credentials After Enrollment

1. **Stop add-on**
2. **Remove /data/claude/c3po-credentials.json** (but keep .c3po-setup-complete)
3. **Start add-on**

**Expected:**
- Add-on detects missing credentials
- Logs show: "c3po credentials missing! Remove /data/.c3po-setup-complete and restart to re-enroll"
- Add-on stops

### Test 16: Working Directory Validation

**Change config:**
```yaml
work_dir: "/nonexistent"
```

**Start add-on**

**Expected:**
- Add-on fails or creates directory
- Log shows error about working directory

**Revert to /config for remaining tests**

## Phase 7: Multi-Architecture Testing (Optional)

If you have hardware or can test on multiple architectures:

### Build for All Architectures

```bash
docker buildx create --use
docker buildx build --platform linux/amd64,linux/arm64,linux/arm/v7 -t test .
```

### Test on Each Architecture

- amd64 (most common)
- aarch64 (Raspberry Pi 4, etc.)
- armv7 (Raspberry Pi 3, etc.)

**Expected:** All architectures build and run correctly

## Test Results Documentation

### Create Test Report

Document results in a file:

```markdown
# Test Report - Claude Code Agent v0.1.0

Date: YYYY-MM-DD
Tester: Your Name
Environment: Home Assistant OS X.X, Architecture: amd64

## Phase 1: Build
- [x] Docker build succeeds
- [x] No hadolint warnings
- [x] Files copied correctly

## Phase 2: Installation
- [x] Installs in Home Assistant
- [x] Appears in add-on store
- [x] Configuration UI loads

## Phase 3: Configuration
- [x] Missing token rejected
- [x] Invalid token rejected
- [x] Missing c3po URL rejected
- [x] Valid config accepted

## Phase 4: Functionality
- [x] Agent registers with c3po
- [x] Agent receives tasks
- [x] File read access works
- [x] File write access works
- [x] Persistent credentials work
- [x] Complex tasks execute

## Phase 5: Resilience
- [x] Survives HA restart
- [x] Survives stop/start
- [x] Health check passes
- [x] Auto-recovers from crash

## Phase 6: Edge Cases
- [x] Invalid admin token handled
- [x] Missing credentials detected
- [x] Invalid work_dir handled

## Issues Found
- None / List any issues

## Conclusion
- Ready for production / Needs fixes
```

## Debugging Failed Tests

### View Detailed Logs

```bash
# In Home Assistant
ha addons logs claude-code-agent

# Or in container
docker logs <container-id>
```

### Access Container Shell

```bash
# Via Home Assistant Terminal add-on
docker exec -it <container-id> bash
```

### Check Files

```bash
# Verify symlink
ls -la /home/node/.claude

# Check credentials
ls -la /data/claude/

# Check service status
s6-svstat /run/service/claude-agent
```

### Manual Service Test

```bash
# Run service script manually
bash -x /etc/services.d/claude-agent/run
```

## Success Criteria

All tests must pass before publishing:

- ✅ Builds without errors
- ✅ Installs in Home Assistant
- ✅ Configuration validation works
- ✅ OAuth token auth works
- ✅ c3po enrollment succeeds
- ✅ Agent registers with coordinator
- ✅ Agent executes tasks correctly
- ✅ File access works (read and write)
- ✅ Credentials persist across restarts
- ✅ Health checks pass
- ✅ Auto-recovers from crashes
- ✅ Logs are clear and informative
- ✅ Edge cases handled gracefully

## Performance Benchmarks

### Startup Time
- Target: < 60 seconds from start to ready
- Measure: Time from "Start" clicked to "/c3po auto" running

### Memory Usage
- Target: < 500MB typical usage
- Measure: `docker stats <container-id>`

### Task Response Time
- Target: < 5 seconds to begin processing task
- Measure: Time from task sent to logs show "Received task"

### Health Check
- Should pass consistently after startup period
- No false positives/negatives

## Post-Testing Cleanup

After testing completes:

1. **Stop test add-on**
2. **Remove test agent from c3po:**
   ```bash
   c3po remove-agent test-homeassistant
   ```
3. **Clean up test files in /config**
4. **Uninstall add-on** (if in test environment)
5. **Document any issues found**
6. **Update code/docs based on findings**

## Continuous Testing

After initial testing, set up:

1. **Automated builds** (GitHub Actions)
2. **Test Home Assistant instance** for regression testing
3. **Version compatibility matrix** (test against multiple HA versions)
4. **Update dependencies periodically** and re-test

---

**Testing Status**: ⏳ Pending
**Last Test Date**: Not yet tested
**Test Coverage**: Ready for comprehensive testing
