#!/bin/bash
set -eu

DATA_DIR="/home/omo/project/.agentmemory"
III_CONFIG_DIR="/home/omo/.agentmemory"
III_CONFIG="$III_CONFIG_DIR/config.yaml"
III_BINARY="/usr/local/bin/iii"
AGENTMEMORY_BINARY="/usr/local/bin/agentmemory"
ENGINE_PORT="49134"
MAX_WAIT=15

# Create data directory inside the host-mounted project folder
mkdir -p "$DATA_DIR"

# Write iii-config with data paths pointing to host-mounted folder
# Default hosts (127.0.0.1) and ports (3111, 3112) work fine inside the container
# iii is launched with --config pointing at this file; agentmemory reads it via AGENTMEMORY_III_CONFIG
mkdir -p "$III_CONFIG_DIR"
cat > "$III_CONFIG" <<'EOF'
workers:
  - name: iii-http
    config:
      port: 3111
      host: 127.0.0.1
  - name: iii-queue
  - name: iii-state
    config:
      adapter:
        name: kv
        config:
          store_method: file_based
          file_path: /home/omo/project/.agentmemory/state_store.db
  - name: iii-stream
    config:
      adapter:
        name: kv
        config:
          store_method: file_based
          file_path: /home/omo/project/.agentmemory/stream_store
EOF

# Start iii in the background with explicit config path
echo "Starting iii engine..."
$III_BINARY --config "$III_CONFIG" &

# Wait for port 49134 to become ready
echo "Waiting for iii engine on port $ENGINE_PORT..."
WAITED=0
while ! (echo > /dev/tcp/localhost/$ENGINE_PORT) 2>/dev/null; do
  sleep 1
  WAITED=$((WAITED + 1))
  if [ "$WAITED" -ge "$MAX_WAIT" ]; then
    echo "ERROR: iii engine did not become ready within ${MAX_WAIT}s"
    exit 1
  fi
done
echo "iii engine ready on port $ENGINE_PORT"

export AGENTMEMORY_III_CONFIG="$III_CONFIG"

echo "Starting agentmemory..."
$AGENTMEMORY_BINARY &

# Background auth watcher
watcher() {
  AUTH_DIR="/home/omo/.local/share/opencode"
  AUTH_JSON="$AUTH_DIR/auth.json"
  AGENTMEMORY_ENV="/home/omo/.agentmemory/.env"

  mkdir -p "$AUTH_DIR" && touch "$AUTH_JSON"

  while true; do
    KEY=$(jq -r '.nebius.key // empty' "$AUTH_JSON")
    if [ -n "$KEY" ]; then
      echo "OPENAI_API_KEY=$KEY" >> "$AGENTMEMORY_ENV"
      echo "Stoping agentmemory..."
      $AGENTMEMORY_BINARY stop || kill -9 $(pgrep -f "agentmemory" | head -1)
      $AGENTMEMORY_BINARY &
      echo "Auth watcher: agentmemory configured with Nebius API key"
    fi
    inotifywait -qq -e close_write "$AUTH_JSON"
  done
}

# Start watcher in background
watcher &

# Keep container alive
echo "agentmemory started, keeping container alive..."
exec tail -f /dev/null
