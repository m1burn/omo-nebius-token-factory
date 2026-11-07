#!/bin/sh
# Start the omo container: build the image with this host's uid/gid and
# run `docker compose up -d --build`. Run this script from the directory
# you want to share — it is always mounted at /home/omo/project inside
# the container.
set -eu

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
compose_file="$here/docker-compose.yml"

if [ ! -f "$compose_file" ]; then
  echo "no docker-compose.yml next to this script — invoke it by its real path, e.g. /path/to/omo-nebius-token-factory/up.sh" >&2
  exit 1
fi

case "$PWD" in
  "$HOME"|/) echo "refusing to share all of $PWD — run this from your project directory instead" >&2; exit 1 ;;
esac

HOST_UID=$(id -u)
HOST_GID=$(id -g)
export HOST_UID HOST_GID

echo "sharing: $PWD"
exec docker compose -f "$compose_file" up -d --build "$@"
