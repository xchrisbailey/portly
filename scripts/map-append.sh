#!/bin/sh
# Appends one line to a wayfinder map's "Decisions so far" section.
#   scripts/map-append.sh <map issue number> '<- [Ticket title](url): gist>' [--print]
# --print shows the edited body instead of updating the issue.
set -eu

[ $# -ge 2 ] || { echo "usage: scripts/map-append.sh <map issue> '<line>' [--print]" >&2; exit 64; }
map="$1"; line="$2"; print="${3:-}"

body="$(gh issue view "$map" --json body --jq .body)"
case "$body" in *"## Not yet specified"*) ;; *) echo "map $map has no '## Not yet specified' section" >&2; exit 1 ;; esac

# Insert the line after the last non-blank line before the "Not yet specified" heading.
edited="$(printf '%s\n' "$body" | awk -v line="$line" '
    { a[NR] = $0 }
    END {
        for (i = 1; i <= NR; i++) if (a[i] ~ /^## Not yet specified/) h = i
        j = h - 1
        while (j > 0 && a[j] == "") j--
        for (i = 1; i <= j; i++) print a[i]
        print line
        for (i = j + 1; i <= NR; i++) print a[i]
    }')"

if [ "$print" = "--print" ]; then
    printf '%s\n' "$edited"
else
    printf '%s\n' "$edited" | gh issue edit "$map" --body-file -
fi
