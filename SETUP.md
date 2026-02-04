# Repository Setup Guide

This document covers initial setup steps for the claude-code-homeassistant repository.

## Initial Git Setup

The repository has been initialized with:

```bash
cd ~/Code/claude-code-homeassistant
git init
git add -A
```

## Next Steps

### 1. Create GitHub Repository

```bash
# Repository already created at:
# https://github.com/michaelansel/claude-code-homeassistant

# Remote already added, just push
git push -u origin main
```

### 2. Add Images

Create `icon.png` (108x108) and `logo.png` (128x128) - see IMAGES.md for requirements.

### 3. Test Locally

Build and test the container:

```bash
# Build
docker build -t claude-code-agent:test .

# Test run (requires valid OAuth token and c3po access)
docker run --rm \
  -e OAUTH_TOKEN="sk-ant-xxx..." \
  -e C3PO_URL="https://mcp.qerk.be" \
  -e C3PO_TOKEN="admin-token" \
  -e MACHINE_NAME="test-agent" \
  -v /tmp/test-config:/config \
  -v /tmp/test-data:/data \
  claude-code-agent:test
```

Note: The above Docker command won't work exactly as-is because the container expects bashio functions. For proper testing, install in Home Assistant.

### 4. Create Home Assistant Repository Entry

Create a repository.json file for HA add-on store:

```json
{
  "name": "Claude Code Add-ons",
  "url": "https://github.com/your-username/claude-code-homeassistant",
  "maintainer": "Your Name <your.email@example.com>"
}
```

### 5. Documentation for Users

Users will add your repository to Home Assistant:

1. Go to Settings → Add-ons → Add-on Store
2. Click menu (⋮) → Repositories
3. Add: `https://github.com/michaelansel/claude-code-homeassistant`

## File Structure Summary

```
claude-code-homeassistant/
├── .gitignore                     # Git ignore rules
├── build.yaml                     # Multi-arch build config
├── CHANGELOG.md                   # Version history
├── config.yaml                    # Add-on metadata (REQUIRED)
├── Dockerfile                     # Container definition (REQUIRED)
├── DOCS.md                       # User documentation (REQUIRED)
├── IMAGES.md                     # Image requirements
├── LICENSE                       # MIT License
├── README.md                     # Developer documentation
├── SETUP.md                      # This file
└── rootfs/                       # Files copied to container
    └── etc/
        └── services.d/
            └── claude-agent/
                ├── finish        # S6 finish script
                └── run          # S6 service script (REQUIRED)

Missing (to be added):
├── icon.png                      # 108x108 add-on icon
└── logo.png                      # 128x128 add-on logo
```

## Validation

Before publishing, validate the add-on:

1. **Dockerfile lint**:
   ```bash
   docker run --rm -i hadolint/hadolint < Dockerfile
   ```

2. **Config validation**:
   - Valid YAML syntax
   - All required fields present
   - Schema matches options

3. **Service scripts**:
   - Executable permissions set
   - Bash syntax valid
   - Bashio functions used correctly

4. **Documentation**:
   - DOCS.md complete with user setup steps
   - README.md complete with developer guide
   - CHANGELOG.md updated

## Testing Checklist

- [ ] Dockerfile builds successfully
- [ ] Add-on appears in Home Assistant
- [ ] Configuration options work in HA UI
- [ ] Service starts without errors
- [ ] OAuth token validation works
- [ ] c3po enrollment succeeds
- [ ] Agent appears in c3po coordinator
- [ ] Agent can receive and execute tasks
- [ ] Logs appear in HA Supervisor
- [ ] File access to /config works
- [ ] Persistent storage survives restart

## Release Process

1. Update version in `config.yaml`
2. Update `CHANGELOG.md` with changes
3. Commit: `git commit -am "Release v0.x.x"`
4. Tag: `git tag -a v0.x.x -m "Release v0.x.x"`
5. Push: `git push --follow-tags`

## Support Channels

Set up:
- GitHub Issues for bug reports
- GitHub Discussions for Q&A
- Link to c3po documentation
- Link to Claude Code documentation

## License

MIT License - allows users to modify and distribute freely.
