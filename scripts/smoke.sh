#!/bin/sh
# Exercise the real adapters: start a throwaway node server in its own process group,
# then Scan and Kill it through `Portly --scan` / `Portly --kill`.
set -eu
cd "$(dirname "$0")/.."
command -v node >/dev/null || { echo "smoke: node not found, skipped"; exit 0; }

bin="$(swift build --show-bin-path)/Portly"
port=47998
# Started from a subshell so it isn't this shell's job (no "Terminated" notice when it's killed).
server=$( (perl -e 'setpgrp(0, 0); exec @ARGV' node -e "require('http').createServer(() => {}).listen($port)" \
    >/dev/null 2>&1 & echo $!) )
trap 'kill "$server" 2>/dev/null || true' EXIT
sleep 1

pid=$("$bin" --scan | jq --argjson port "$port" '.[] | select(.ports | index($port)) | .pid')
[ "$pid" = "$server" ] || { echo "smoke: scan did not find the server (got '$pid')" >&2; exit 1; }
"$bin" --kill "$pid"
left=$("$bin" --scan | jq --argjson port "$port" '[.[] | select(.ports | index($port))] | length')
[ "$left" = 0 ] || { echo "smoke: server still listed after Kill" >&2; exit 1; }
echo "smoke: scan + kill ok"
