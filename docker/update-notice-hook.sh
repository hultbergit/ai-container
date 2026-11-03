#!/usr/bin/env bash
# SessionStart hook: surface the notice written by check-update.sh inside the
# Claude Code UI. Prints nothing when there is no pending update.

notice_file=/tmp/claude-update-notice
[ -s "$notice_file" ] || exit 0
jq -Rsc '{systemMessage: rtrimstr("\n")}' "$notice_file" 2>/dev/null || true
exit 0
