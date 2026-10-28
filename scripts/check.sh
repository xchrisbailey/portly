#!/bin/sh
# Single source of truth for local checks.
#   commit: format lint + tests (fast; runs before every commit)
#   push:   commit checks + bundle build + real-adapter smoke test + release script test (runs before every push)
set -eu
cd "$(dirname "$0")/.."

mode="${1:-push}"
case "$mode" in commit|push) ;; *) echo "usage: scripts/check.sh [commit|push]" >&2; exit 64 ;; esac

echo "==> swift format lint"
swift format lint --strict -r Sources Tests

echo "==> swift test"
swift test --quiet

if [ "$mode" = push ]; then
    echo "==> app bundle"
    ./scripts/build-app.sh --build-only

    echo "==> smoke (real adapters)"
    ./scripts/smoke.sh

    echo "==> release script (fake tools)"
    ./scripts/release-test.sh
fi

echo "==> checks passed ($mode)"
