#!/bin/bash
set -eua

DATA_DIR="/home/omo/.omo-agentmemory"

# Start agentmemory in background
mkdir -p "$DATA_DIR" && cd "$DATA_DIR"
agentmemory &

# Start the memory housekeeper
agentmemory_housekeeper &

# Keep container alive
echo "agentmemory started, keeping container alive..."
exec tail -f /dev/null
