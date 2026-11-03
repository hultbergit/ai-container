#!/usr/bin/env bash
set -euo pipefail

# The container starts as root so the firewall can be applied; once done
# (or skipped) we drop to the host's uid:gid before running the real command.

if [ "$(id -u)" = "0" ]; then
	if [ "${SKIP_FIREWALL:-false}" != "true" ]; then
		if [ "${FIREWALL_DEBUG:-false}" = "true" ]; then
			/usr/local/bin/init-firewall.sh
		else
			# Keep startup quiet: one status line, plus any warnings. The full
			# log is only shown on failure (or with --firewall-debug).
			printf 'Initializing firewall... ' >&2
			if fw_log=$(/usr/local/bin/init-firewall.sh 2>&1); then
				echo "ok" >&2
				grep '^WARNING' <<<"$fw_log" >&2 || true
			else
				echo "failed" >&2
				echo "$fw_log" >&2
				exit 1
			fi
		fi
	fi
	if [ "${1:-}" = "claude" ]; then
		/usr/local/bin/check-update.sh || true
		# Extra settings layered on top of the user's: a SessionStart hook that
		# shows the update notice inside the Claude Code UI.
		shift
		set -- claude --settings /etc/claude-container/settings.json "$@"
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
