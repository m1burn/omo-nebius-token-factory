#!/bin/bash
set -eua

DATA_DIR="/home/omo/.omo-agentmemory"

# Cold-boot index rebuild can outrun the CLI's 15s worker-ready window;
# the engine survives it, so warm retries succeed. Clean exits (the
# housekeeper's `agentmemory stop`) don't restart — wipes start their own.
start_agentmemory() {
  local attempt=1
  until agentmemory; do
    attempt=$((attempt + 1))
    if [ "$attempt" -gt 10 ]; then
      echo "agentmemory did not stay up after 10 attempts; giving up" >&2
      return 1
    fi
    echo "agentmemory exited; retrying in 10s (attempt $attempt/10)" >&2
    sleep 10
  done
}

# Start agentmemory in background
mkdir -p "$DATA_DIR" && cd "$DATA_DIR"
start_agentmemory &

# Start the memory housekeeper
agentmemory_housekeeper &

# Keep container alive
echo "agentmemory started, keeping container alive..."
exec tail -f /dev/null
