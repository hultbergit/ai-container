#!/usr/bin/env bash
set -euo pipefail

# The container starts as root so the firewall can be applied; once done
# (or skipped) we drop to the host's uid:gid before running the real command.

if [ "$(id -u)" = "0" ]; then
	if [ "${SKIP_FIREWALL:-false}" != "true" ]; then
		/usr/local/bin/init-firewall.sh
	fi
	export HOME=/home/node
	exec gosu "${CONTAINER_UID:-1000}:${CONTAINER_GID:-1000}" "$@"
fi

exec "$@"
