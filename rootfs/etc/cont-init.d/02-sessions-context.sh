#!/usr/bin/with-contenv bashio

# Inject a project-scoped CLAUDE.md in work_dir telling Claude about session logs.
# Only writes if the file doesn't exist or contains our managed marker.

WORK_DIR=$(bashio::config 'work_dir')
CLAUDE_DIR="${WORK_DIR}/.claude"
CLAUDE_MD="${CLAUDE_DIR}/CLAUDE.md"
MARKER="<!-- managed by claude-code-ha-addon -->"

if [ -f "$CLAUDE_MD" ]; then
    if ! grep -q "$MARKER" "$CLAUDE_MD"; then
        bashio::log.info "Skipping session context injection: $CLAUDE_MD exists and is not managed by this addon"
        exit 0
    fi
fi

mkdir -p "$CLAUDE_DIR"
cat > "$CLAUDE_MD" << 'EOF'
<!-- managed by claude-code-ha-addon -->
## Past Session Logs

Past session logs are stored in `/data/sessions/`. Reading recent sessions can provide context on previous work.

To list recent sessions:
```
ls -lt /data/sessions/ | head -10
```

To read a recent session log:
```
tail -100 /data/sessions/<session-file>.log
```
EOF

bashio::log.info "Session context CLAUDE.md written to ${CLAUDE_MD}"
