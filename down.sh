#!/bin/sh
# Stop and remove the omo container (`docker compose down`). Run from
# any directory; agentmemory data under $HOME/.omo-agentmemory/data on
# the host is untouched.
set -eu

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
compose_file="$here/docker-compose.yml"

if [ ! -f "$compose_file" ]; then
  echo "no docker-compose.yml next to this script — invoke it by its real path, e.g. /path/to/omo-nebius-token-factory/down.sh" >&2
  exit 1
fi

HOST_UID=$(id -u)
HOST_GID=$(id -g)
export HOST_UID HOST_GID

exec docker compose -f "$compose_file" down "$@"
