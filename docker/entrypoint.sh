#!/usr/bin/env bash
set -euo pipefail

# The container starts as root so the firewall can be applied; once done
# (or skipped) we drop to the host's uid:gid before running the real command.

if [ "$(id -u)" = "0" ]; then
	if [ "${SKIP_FIREWALL:-false}" != "true" ]; then
		/usr/local/bin/init-firewall.sh
	fi
	export HOME=/home/node
	if [ "${CODEX_LOGIN_FORWARD:-false}" = "true" ]; then
		# Use a different port: Codex owns the loopback listener on 1455.
		gosu "${CONTAINER_UID:-1000}:${CONTAINER_GID:-1000}" \
			socat TCP4-LISTEN:1456,bind=0.0.0.0,reuseaddr,fork TCP4:127.0.0.1:1455 &
	fi
	exec gosu "${CONTAINER_UID:-1000}:${CONTAINER_GID:-1000}" "$@"
fi

if [ "${CODEX_LOGIN_FORWARD:-false}" = "true" ]; then
	socat TCP4-LISTEN:1456,bind=0.0.0.0,reuseaddr,fork TCP4:127.0.0.1:1455 &
fi

exec "$@"
