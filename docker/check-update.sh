#!/usr/bin/env bash
# Tell the developer when a newer Claude Code release is out. The built-in
# auto-updater is disabled in this image (root-owned npm prefix, --rm
# containers), so the only way to update is rebuilding the image without cache.
#
# Never fails or blocks startup for long: any error (offline, firewall,
# registry hiccup) is silently ignored.

set -uo pipefail

# Pinned builds (CLAUDE_CODE_VERSION=x.y.z) are deliberate; don't nag.
#[ "${CLAUDE_CODE_VERSION:-latest}" = "latest" ] || exit 0
[ "${SKIP_UPDATE_CHECK:-false}" = "true" ] && exit 0

pkg_json=/usr/local/lib/node_modules/@anthropic-ai/claude-code/package.json
installed=$(jq -r '.version // empty' "$pkg_json" 2>/dev/null) || exit 0
[ -n "$installed" ] || exit 0

latest=$(curl -fsS --max-time 3 https://registry.npmjs.org/@anthropic-ai/claude-code/latest 2>/dev/null \
	| jq -r '.version // empty' 2>/dev/null) || exit 0
[ -n "$latest" ] || exit 0

[ "$installed" = "$latest" ] && exit 0
# Only report when the registry version is actually newer.
[ "$(printf '%s\n%s\n' "$installed" "$latest" | sort -V | tail -n1)" = "$latest" ] || exit 0

# Printed to the terminal too: the TUI draws over it at startup, but it is
# left in the scrollback and visible again once claude exits.
yellow=$'\033[33m' bold=$'\033[1m' reset=$'\033[0m'
[ -t 2 ] || { yellow='' bold='' reset=''; }

cat >&2 <<EOF
${yellow}${bold}Claude Code update available: ${installed} -> ${latest}${reset}
${yellow}Auto-update is disabled in this container. To install it, rebuild the
image without cache on the host:${reset}

    bin/rebuild claude

EOF

# Picked up by update-notice-hook.sh (a SessionStart hook) so the notice also
# shows inside the Claude Code UI.
notice_file=/tmp/claude-update-notice
printf 'Claude Code update available: %s -> %s. Auto-update is disabled in this container; run `bin/rebuild claude` on the host to install it.\n' \
	"$installed" "$latest" >"$notice_file" 2>/dev/null && chmod 644 "$notice_file"
exit 0
