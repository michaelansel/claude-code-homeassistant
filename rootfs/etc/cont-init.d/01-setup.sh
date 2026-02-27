#!/usr/bin/with-contenv bashio

ADDON_VERSION="0.2.0"
bashio::log.info "Claude Code agent v${ADDON_VERSION} - running setup..."
bashio::log.info "Claude Code version: $(claude --version 2>&1 || echo 'unknown')"

# Validate OAuth token
if ! bashio::config.has_value 'oauth_token'; then
    bashio::log.fatal "OAuth token required in add-on configuration"
    exit 1
fi

TOKEN=$(bashio::config 'oauth_token')
if [[ ! "$TOKEN" =~ ^sk-ant- && ! "$TOKEN" =~ ^sk-at- ]]; then
    bashio::log.fatal "Invalid token format (must start with sk-ant- or sk-at-)"
    exit 1
fi

# Validate c3po configuration
if ! bashio::config.has_value 'c3po_coordinator_url'; then
    bashio::log.fatal "c3po coordinator URL required"
    exit 1
fi

C3PO_URL=$(bashio::config 'c3po_coordinator_url')
MACHINE_NAME=$(bashio::config 'machine_name')

# Ensure persistent storage exists (/root/.claude is a symlink to /data/claude)
# /data is a volume mounted at runtime, so the target dir may not exist yet
mkdir -p /data/claude
mkdir -p /data/sessions

# Initialize .claude.json persistent config if it doesn't exist
# /root/.claude.json is symlinked to /data/claude-user-config.json (in Dockerfile)
# This file stores user-scope MCP server config from `claude mcp add`
if [ ! -f /data/claude-user-config.json ]; then
    echo '{}' > /data/claude-user-config.json
fi

# Re-enroll if agent_pattern in credentials doesn't match current machine_name
# (handles migration from hardcoded "ha/*" to "${MACHINE_NAME}/*")
CREDS_FILE="/root/.claude/c3po-credentials.json"
if [ -f "$CREDS_FILE" ] && [ -f /data/.c3po-setup-complete ]; then
    CURRENT_PATTERN=$(python3 -c "import json; print(json.load(open('$CREDS_FILE')).get('agent_pattern',''))" 2>/dev/null)
    EXPECTED_PATTERN="${MACHINE_NAME}/*"
    if [ "$CURRENT_PATTERN" != "$EXPECTED_PATTERN" ]; then
        bashio::log.info "Agent pattern mismatch: '$CURRENT_PATTERN' != '$EXPECTED_PATTERN', re-enrolling..."
        rm -f /data/.c3po-setup-complete
    fi
fi

# Set up c3po plugin on first run
# After enrollment, c3po stores credentials in /root/.claude/c3po-credentials.json
# which persists via symlink to /data/claude/c3po-credentials.json
if [ ! -f /data/.c3po-setup-complete ]; then
    bashio::log.info "Setting up c3po plugin (first run)..."

    # Admin token only required for initial enrollment
    if ! bashio::config.has_value 'c3po_admin_token'; then
        bashio::log.fatal "c3po admin token required for first-time setup"
        exit 1
    fi

    C3PO_TOKEN=$(bashio::config 'c3po_admin_token')

    # TMPDIR must be on the same filesystem as ~/.claude for atomic renames
    mkdir -p /root/.claude/tmp
    export TMPDIR=/root/.claude/tmp
    export CLAUDE_CODE_OAUTH_TOKEN="$TOKEN"

    # Force git to use HTTPS instead of SSH (no SSH keys in container)
    git config --global url."https://github.com/".insteadOf "git@github.com:"
    git config --global url."https://github.com/".insteadOf "ssh://git@github.com/"
    export GIT_TERMINAL_PROMPT=0

    # Download setup.py and run enrollment (lightweight, avoids plugin system OOM)
    bashio::log.info "Downloading c3po setup script..."
    curl -fsSL https://raw.githubusercontent.com/michaelansel/c3po/main/setup.py -o /tmp/c3po-setup.py
    bashio::log.info "Download complete"

    bashio::log.info "Running enrollment..."
    python3 /tmp/c3po-setup.py --enroll "$C3PO_URL" "$C3PO_TOKEN" \
        --machine "$MACHINE_NAME" \
        --pattern "${MACHINE_NAME}/*" 2>&1 | while IFS= read -r line; do bashio::log.info "  enroll: $line"; done

    # Install the plugin for hooks/skills (needed for /c3po auto)
    # Skip if already installed — plugins persist in /data across re-enrollments
    bashio::log.info "Installing c3po plugin..."
    if [ ! -d "/root/.claude/plugins/c3po@michaelansel" ]; then
        TMPDIR="$TMPDIR" CLAUDE_CODE_OAUTH_TOKEN="$TOKEN" \
            claude plugin marketplace add michaelansel/claude-code-plugins 2>&1 \
            | while IFS= read -r line; do bashio::log.info "  marketplace: $line"; done || true
        TMPDIR="$TMPDIR" CLAUDE_CODE_OAUTH_TOKEN="$TOKEN" \
            claude plugin install c3po@michaelansel 2>&1 \
            | while IFS= read -r line; do bashio::log.info "  plugin: $line"; done || true
    else
        bashio::log.info "  c3po@michaelansel already installed, skipping"
    fi

    touch /data/.c3po-setup-complete
    bashio::log.info "c3po setup complete"
    bashio::log.info "You can now remove c3po_admin_token from add-on config (optional)"
fi

# Ensure TMPDIR is on same filesystem as ~/.claude (needed for claude commands)
mkdir -p /root/.claude/tmp
export TMPDIR=/root/.claude/tmp

# --- Update plugins (every start) ---
PLUGIN_DIR="/root/.claude/plugins"
if [ -d "$PLUGIN_DIR" ] && ls "$PLUGIN_DIR"/ >/dev/null 2>&1; then
    bashio::log.info "Updating plugins..."
    marketplaces=()
    for dir in "$PLUGIN_DIR"/*/; do
        name=$(basename "$dir")
        if [[ "$name" == *@* ]]; then
            mp="${name##*@}"
            if [[ ! " ${marketplaces[*]:-} " =~ " ${mp} " ]]; then
                marketplaces+=("$mp")
            fi
        fi
    done
    for mp in ${marketplaces[@]+"${marketplaces[@]}"}; do
        bashio::log.info "  Updating marketplace: $mp"
        TMPDIR="$TMPDIR" CLAUDE_CODE_OAUTH_TOKEN="$TOKEN" \
            claude plugin marketplace update "$mp" 2>&1 \
            | while IFS= read -r line; do bashio::log.info "  marketplace: $line"; done || true
    done
    for dir in "$PLUGIN_DIR"/*/; do
        plugin=$(basename "$dir")
        if [[ "$plugin" == *@* ]]; then
            bashio::log.info "  Updating plugin: $plugin"
            TMPDIR="$TMPDIR" CLAUDE_CODE_OAUTH_TOKEN="$TOKEN" \
                claude plugin update "$plugin" 2>&1 \
                | while IFS= read -r line; do bashio::log.info "  plugin: $line"; done || true
        fi
    done
fi

# --- Validate c3po credentials ---
CREDS_FILE="/root/.claude/c3po-credentials.json"
if [ -f "$CREDS_FILE" ]; then
    coord_url=$(jq -r '.coordinator_url' "$CREDS_FILE")
    cred_token=$(jq -r '.api_token' "$CREDS_FILE")
    if [ -n "$coord_url" ] && [ "$coord_url" != "null" ] && \
       [ -n "$cred_token" ] && [ "$cred_token" != "null" ]; then
        bashio::log.info "Validating c3po credentials..."
        HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 \
            -H "Authorization: Bearer $cred_token" \
            "$coord_url/agent/api/validate?machine_name=$MACHINE_NAME" 2>/dev/null) || true
        if [ "$HTTP_STATUS" = "000" ]; then
            bashio::log.fatal "Cannot reach c3po coordinator at $coord_url"
            sleep 30; exit 1
        elif [ "$HTTP_STATUS" = "401" ] || [ "$HTTP_STATUS" = "403" ]; then
            bashio::log.fatal "c3po token invalid/unauthorized for machine '$MACHINE_NAME' (HTTP $HTTP_STATUS), re-enrolling on next start"
            rm -f /data/.c3po-setup-complete
            sleep 30; exit 1
        elif ! echo "$HTTP_STATUS" | grep -q '^2'; then
            bashio::log.fatal "c3po coordinator returned HTTP $HTTP_STATUS"
            sleep 30; exit 1
        fi
        bashio::log.info "c3po credentials valid"
    else
        bashio::log.fatal "c3po credentials incomplete - clear /data/.c3po-setup-complete and restart with admin token"
        sleep 30; exit 1
    fi
else
    bashio::log.fatal "c3po credentials not found - clear /data/.c3po-setup-complete and restart with admin token"
    sleep 30; exit 1
fi

# Ensure MCP is configured (recover if .claude.json was lost before symlink fix)
# Credentials persist at ~/.claude/c3po-credentials.json (symlinked to /data/claude/)
CREDS_FILE="/root/.claude/c3po-credentials.json"
if [ -f "$CREDS_FILE" ]; then
    MCP_CHECK=$(CLAUDE_CODE_OAUTH_TOKEN="$TOKEN" claude mcp list 2>&1)
    if echo "$MCP_CHECK" | grep -q "No MCP servers"; then
        bashio::log.info "MCP not configured, re-adding from saved credentials..."
        CRED_URL=$(python3 -c "import json; print(json.load(open('$CREDS_FILE'))['coordinator_url'])")
        CRED_TOKEN=$(python3 -c "import json; print(json.load(open('$CREDS_FILE')).get('api_token',''))")

        # Build claude mcp add command
        # Header values use ${VAR:-default} syntax - these are stored literally by claude
        # and expanded at MCP invocation time, not now
        PROJECT_NAME=$(bashio::config 'project_name')
        MACHINE_HDR='${C3PO_MACHINE_NAME:-'"${MACHINE_NAME}"'}'
        PROJECT_HDR='${C3PO_PROJECT_NAME:-${PWD##*/}}'
        SESSION_HDR='${C3PO_SESSION_ID:-$$}'

        if [ -n "$CRED_TOKEN" ]; then
            CLAUDE_CODE_OAUTH_TOKEN="$TOKEN" \
                claude mcp add c3po "${CRED_URL}/agent/mcp" -t http -s user \
                    -H "X-Machine-Name: ${MACHINE_HDR}" \
                    -H "X-Project-Name: ${PROJECT_HDR}" \
                    -H "X-Session-ID: ${SESSION_HDR}" \
                    -H "Authorization: Bearer ${CRED_TOKEN}" \
                2>&1 | while IFS= read -r line; do bashio::log.info "  mcp-fix: $line"; done
        else
            CLAUDE_CODE_OAUTH_TOKEN="$TOKEN" \
                claude mcp add c3po "${CRED_URL}/agent/mcp" -t http -s user \
                    -H "X-Machine-Name: ${MACHINE_HDR}" \
                    -H "X-Project-Name: ${PROJECT_HDR}" \
                    -H "X-Session-ID: ${SESSION_HDR}" \
                2>&1 | while IFS= read -r line; do bashio::log.info "  mcp-fix: $line"; done
        fi
    fi
fi

# Verify setup using claude's own commands
bashio::log.info "Verifying MCP configuration..."
CLAUDE_CODE_OAUTH_TOKEN="$TOKEN" \
    claude mcp list 2>&1 | while IFS= read -r line; do bashio::log.info "  mcp: $line"; done

bashio::log.info "Verifying plugin installation..."
CLAUDE_CODE_OAUTH_TOKEN="$TOKEN" \
    claude plugin list 2>&1 | while IFS= read -r line; do bashio::log.info "  plugin: $line"; done

# Run init commands if configured
if bashio::config.has_value 'init_commands'; then
    bashio::log.info "Running init commands..."
    for cmd in $(bashio::config 'init_commands'); do
        bashio::log.info "  > $cmd"
        bash -c "$cmd" 2>&1 \
            | while IFS= read -r line; do bashio::log.info "  init: $line"; done || {
            bashio::log.fatal "Init command failed: $cmd"
            exit 1
        }
    done
fi

bashio::log.info "Setup complete"
