#!/bin/bash
set -eua

DATA_DIR="/home/omo/.omo-agentmemory"
AGENTMEMORY_ENV="/home/omo/.agentmemory/.env"

# Source agentmemory env variables so they are available to all apps we run here.
. "$AGENTMEMORY_ENV"

# Start agentmemory in background
mkdir -p "$DATA_DIR" && cd "$DATA_DIR"
agentmemory &

# Start the memory housekeeper
agentmemory_housekeeper &

# Background auth watcher that intercepts the Nebius Token Factory auth token and applies it to agentmemory as well
watcher() {
  AUTH_DIR="/home/omo/.local/share/opencode"
  AUTH_JSON="$AUTH_DIR/auth.json"

  mkdir -p "$AUTH_DIR" && touch "$AUTH_JSON"

  while true; do
    KEY=$(jq -r '.nebius.key // empty' "$AUTH_JSON" 2>/dev/null || true)
    if [ -n "$KEY" ]; then
      CURRENT=$(grep "^OPENAI_API_KEY=" "$AGENTMEMORY_ENV" 2>/dev/null | cut -d= -f2-)
      if [ "$CURRENT" != "$KEY" ]; then
        if [ -f "$AGENTMEMORY_ENV" ]; then
          sed -i '/^OPENAI_API_KEY=/d' "$AGENTMEMORY_ENV"
        fi
        printf '\n%s' "OPENAI_API_KEY=$KEY" >> "$AGENTMEMORY_ENV"
        echo "Stopping agentmemory..."
        agentmemory stop || kill -9 $(pgrep -f "agentmemory" | head -1) || true
        cd "$DATA_DIR" && agentmemory &
        echo "Auth watcher: agentmemory configured with Nebius Token Factory auth key"
      fi
    fi
    inotifywait -qq -e close_write "$AUTH_JSON"
  done
}

# Start auth watcher in background
watcher &

# Keep container alive
echo "agentmemory started, keeping container alive..."
exec tail -f /dev/null
