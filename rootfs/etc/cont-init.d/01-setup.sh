#!/usr/bin/with-contenv bashio

ADDON_VERSION="0.3.2"
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

# Ensure persistent storage exists
mkdir -p /data/claude /data/sessions
if [ ! -f /data/claude-user-config.json ]; then
    echo '{}' > /data/claude-user-config.json
fi

# TMPDIR must be on the same filesystem as ~/.claude for atomic renames
mkdir -p /root/.claude/tmp
export TMPDIR=/root/.claude/tmp
export CLAUDE_CODE_OAUTH_TOKEN="$TOKEN"

# Force git to use HTTPS instead of SSH (no SSH keys in container)
# Must run every start since /root/.gitconfig is ephemeral
git config --global url."https://github.com/".insteadOf "git@github.com:"
git config --global url."https://github.com/".insteadOf "ssh://git@github.com/"
export GIT_TERMINAL_PROMPT=0

# --- Enrollment (first run only, requires admin token) ---
CREDS_FILE="/root/.claude/c3po-credentials.json"

# Re-enroll if agent_pattern doesn't match current machine_name
if [ -f "$CREDS_FILE" ] && [ -f /data/.c3po-setup-complete ]; then
    CURRENT_PATTERN=$(python3 -c "import json; print(json.load(open('$CREDS_FILE')).get('agent_pattern',''))" 2>/dev/null)
    if [ "$CURRENT_PATTERN" != "${MACHINE_NAME}/*" ]; then
        bashio::log.info "Agent pattern mismatch ('$CURRENT_PATTERN'), re-enrolling..."
        rm -f /data/.c3po-setup-complete
    fi
fi

if [ ! -f /data/.c3po-setup-complete ]; then
    bashio::log.info "First-run enrollment..."
    if ! bashio::config.has_value 'c3po_admin_token'; then
        bashio::log.fatal "c3po admin token required for first-time setup"
        exit 1
    fi
    C3PO_TOKEN=$(bashio::config 'c3po_admin_token')
    curl -fsSL https://raw.githubusercontent.com/michaelansel/c3po/main/setup.py -o /tmp/c3po-setup.py
    python3 /tmp/c3po-setup.py --enroll "$C3PO_URL" "$C3PO_TOKEN" \
        --machine "$MACHINE_NAME" --pattern "${MACHINE_NAME}/*" \
        2>&1 | while IFS= read -r line; do bashio::log.info "  enroll: $line"; done
    touch /data/.c3po-setup-complete
    bashio::log.info "Enrollment complete (you can now remove c3po_admin_token)"
fi

# --- Validate c3po credentials (every start) ---
if [ -f "$CREDS_FILE" ]; then
    coord_url=$(jq -r '.coordinator_url' "$CREDS_FILE")
    cred_token=$(jq -r '.api_token' "$CREDS_FILE")
    bashio::log.info "Validating c3po credentials..."
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 \
        -H "Authorization: Bearer $cred_token" \
        "$coord_url/agent/api/validate?machine_name=$MACHINE_NAME" 2>/dev/null) || true
    if [ "$HTTP_STATUS" = "000" ]; then
        bashio::log.fatal "Cannot reach c3po coordinator at $coord_url"
        sleep 30; exit 1
    elif [ "$HTTP_STATUS" = "401" ] || [ "$HTTP_STATUS" = "403" ]; then
        bashio::log.fatal "c3po credentials invalid (HTTP $HTTP_STATUS), will re-enroll on next start"
        rm -f /data/.c3po-setup-complete
        sleep 30; exit 1
    elif ! echo "$HTTP_STATUS" | grep -q '^2'; then
        bashio::log.fatal "c3po coordinator returned HTTP $HTTP_STATUS"
        sleep 30; exit 1
    fi
    bashio::log.info "c3po credentials valid"
else
    bashio::log.fatal "c3po credentials not found - clear /data/.c3po-setup-complete and restart with admin token"
    sleep 30; exit 1
fi

# --- Ensure c3po plugin is installed (every start) ---
bashio::log.info "Updating/installing c3po plugin..."
# Add marketplace if not yet registered (first time only)
if ! claude plugin marketplace list 2>/dev/null | grep -q 'michaelansel'; then
    claude plugin marketplace add michaelansel/claude-code-plugins 2>&1 \
        | while IFS= read -r line; do bashio::log.info "  marketplace add: $line"; done || true
fi
# Update marketplace index (best effort, non-fatal)
claude plugin marketplace update michaelansel 2>&1 \
    | while IFS= read -r line; do bashio::log.info "  marketplace update: $line"; done || true
# Install or update plugin (best effort, non-fatal)
{ claude plugin update c3po@michaelansel 2>/dev/null \
    || claude plugin install c3po@michaelansel 2>&1 \
        | while IFS= read -r line; do bashio::log.info "  plugin: $line"; done; } || true

# --- Update installed plugins (every start) ---
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
        claude plugin marketplace update "$mp" 2>&1 \
            | while IFS= read -r line; do bashio::log.info "  update marketplace $mp: $line"; done || true
    done
    for dir in "$PLUGIN_DIR"/*/; do
        plugin=$(basename "$dir")
        if [[ "$plugin" == *@* ]]; then
            claude plugin update "$plugin" 2>&1 \
                | while IFS= read -r line; do bashio::log.info "  update plugin $plugin: $line"; done || true
        fi
    done
fi

# --- Ensure MCP server is configured ---
MCP_CHECK=$(claude mcp list 2>&1)
if echo "$MCP_CHECK" | grep -q "No MCP servers"; then
    bashio::log.info "MCP not configured, re-adding from credentials..."
    CRED_URL=$(python3 -c "import json; print(json.load(open('$CREDS_FILE'))['coordinator_url'])")
    CRED_TOKEN=$(python3 -c "import json; print(json.load(open('$CREDS_FILE')).get('api_token',''))")
    MACHINE_HDR='${C3PO_MACHINE_NAME:-'"${MACHINE_NAME}"'}'
    PROJECT_HDR='${C3PO_PROJECT_NAME:-${PWD##*/}}'
    SESSION_HDR='${C3PO_SESSION_ID:-$$}'
    claude mcp add c3po "${CRED_URL}/agent/mcp" -t http -s user \
        -H "X-Machine-Name: ${MACHINE_HDR}" \
        -H "X-Project-Name: ${PROJECT_HDR}" \
        -H "X-Session-ID: ${SESSION_HDR}" \
        -H "Authorization: Bearer ${CRED_TOKEN}" \
        2>&1 | while IFS= read -r line; do bashio::log.info "  mcp: $line"; done
fi

# --- Log current state ---
bashio::log.info "MCP servers:"
claude mcp list 2>&1 | while IFS= read -r line; do bashio::log.info "  $line"; done
bashio::log.info "Plugins:"
claude plugin list 2>&1 | while IFS= read -r line; do bashio::log.info "  $line"; done

# --- Run init commands ---
if bashio::config.has_value 'init_commands'; then
    bashio::log.info "Running init commands..."
    for cmd in $(bashio::config 'init_commands'); do
        bashio::log.info "  > $cmd"
        bash -c "$cmd" 2>&1 | while IFS= read -r line; do bashio::log.info "  init: $line"; done || {
            bashio::log.fatal "Init command failed: $cmd"
            exit 1
        }
    done
fi

bashio::log.info "Setup complete"
