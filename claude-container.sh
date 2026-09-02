#!/usr/bin/env bash

set -e
set -o pipefail

if [ -z "$1" ]; then
	echo "Missing name of env" >&2
	exit 1
fi

env_file="$1"
shift

env_dir="$HOME/.claude-$env_file"
if [ ! -d "$env_dir" ]; then
	echo "Missing env dir: $env_dir" >&2
	exit 1
fi

CONTAINER_ENGINE="${CONTAINER_ENGINE:-docker}"

if ! command -v "$CONTAINER_ENGINE" >/dev/null 2>&1; then
	echo "Error: container engine '$CONTAINER_ENGINE' not found in PATH." >&2
	exit 1
fi

#if command -v gpgconf >/dev/null 2>&1; then
	#GPG_SOCK=$(gpgconf --list-dirs agent-socket)
#fi

project_dir="$(basename "$PWD")"

args=(
	run
	--rm
	--interactive
	--tty
	--cap-add NET_ADMIN
	--cap-add NET_RAW
	--env CONTAINER_UID="$(id -u)"
	--env CONTAINER_GID="$(id -g)"
	--env CLAUDE_CONFIG_DIR=/home/node/.claude
	--env TERM="$TERM"
	--env GPG_TTY=
	--volume "$env_dir":/home/node/.claude/
	--volume "$PWD":"/workspaces/$project_dir"
	--workdir "/workspaces/$project_dir"
)

if [ "$CONTAINER_ENGINE" = "podman" ]; then
	if [ "$("$CONTAINER_ENGINE" info --format '{{.Host.Security.Rootless}}' 2>/dev/null)" = "true" ]; then
		args+=(--userns=keep-id --user root:root)
	fi
fi

if [ -n "$SKIP_FIREWALL" ]; then
	args+=(--env SKIP_FIREWALL="$SKIP_FIREWALL")
fi

if [ -n "$EXTRA_ALLOWED_DOMAINS" ]; then
	args+=(--env EXTRA_ALLOWED_DOMAINS="$EXTRA_ALLOWED_DOMAINS")
fi

if [ -n "$DEV_MCP_TOKEN" ]; then
	args+=(--env BRIDGE_TOKEN="$DEV_MCP_TOKEN")
fi

if command -v gh >/dev/null 2>&1; then
	if GH_TOKEN=$(gh auth token 2>/dev/null); then
		args+=(--env GH_TOKEN="$GH_TOKEN")
	else
		echo "Error: not authenticated with GitHub CLI. Run 'gh auth login' first." >&2
		exit 1
	fi
fi

#if [ -f "$HOME/.gnupg/pubring.kbx" ]; then
#	args+=(--volume "$HOME/.gnupg/pubring.kbx:/home/node/.gnupg/pubring.kbx:ro")
#fi
#
#if [ -f "$HOME/.gnupg/trustdb.gpg" ]; then
#	args+=(--volume "$HOME/.gnupg/trustdb.gpg:/home/node/.gnupg/trustdb.gpg:ro")
#fi

if [ -f "$HOME/.gitconfig" ]; then
	args+=(--volume "$HOME/.gitconfig:/home/node/.gitconfig:ro")
fi

#if [[ -n "$GPG_SOCK" && -S "$GPG_SOCK" ]]; then
#	args+=(--volume "$GPG_SOCK:/home/node/.gnupg/S.gpg-agent")
#fi

"$CONTAINER_ENGINE" "${args[@]}" claude-code:latest claude "$@"
