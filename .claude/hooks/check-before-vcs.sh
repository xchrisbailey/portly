#!/bin/sh
# PreToolUse(Bash): run scripts/check.sh before commits and pushes; block on failure.
cmd=$(jq -r '.tool_input.command // ""')
if printf '%s' "$cmd" | grep -Eq '(^|[;&|[:space:]])(jj git push|git push)([[:space:]]|$)'; then
    mode=push
elif printf '%s' "$cmd" | grep -Eq '(^|[;&|[:space:]])(jj commit|git commit)([[:space:]]|$)'; then
    mode=commit
else
    exit 0
fi
root="${CLAUDE_PROJECT_DIR:-$(pwd)}"
if ! out=$("$root/scripts/check.sh" "$mode" 2>&1); then
    printf 'scripts/check.sh %s failed; fix before retrying:\n%s\n' "$mode" "$(printf '%s' "$out" | tail -40)" >&2
    exit 2
fi
