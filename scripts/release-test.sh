#!/usr/bin/env bash
# End-to-end test of scripts/release.sh in a throwaway repo with fake external tools first on PATH.
# Asserts on exit status, messages and the recorded tool calls. Never touches the real codesign,
# xcrun, create-dmg, gh, jj, keychain, network or Apple.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

FAKES="$WORK/fakes"      # fake tools, each appends its call to $FAKE_LOG
TOOLS="$WORK/tools"      # symlinks to the real utilities the script needs, nothing else
mkdir -p "$FAKES" "$TOOLS"

for t in codesign stapler spctl create-dmg gh jj; do
    cat > "$FAKES/$t" <<'FAKE'
#!/bin/sh
echo "$(basename "$0") $*" >> "$FAKE_LOG"
exit 0
FAKE
done
# xcrun: `notarytool history` fails when the profile is "missing"; any other use succeeds.
cat > "$FAKES/xcrun" <<'FAKE'
#!/bin/sh
echo "xcrun $*" >> "$FAKE_LOG"
if [ "${FAKE_NO_PROFILE:-}" = 1 ] && [ "${1:-}" = notarytool ]; then exit 1; fi
exit 0
FAKE
chmod +x "$FAKES"/*
# The fake check command stands in for `scripts/check.sh push`.
cat > "$WORK/fake-check" <<'FAKE'
#!/bin/sh
echo "check $*" >> "$FAKE_LOG"
[ "${FAKE_CHECK_FAIL:-}" != 1 ]
FAKE
chmod +x "$WORK/fake-check"

for t in bash sh env git dirname basename cat grep sed tr rm mkdir; do
    ln -s "$(command -v "$t")" "$TOOLS/$t"
done

export FAKE_LOG="$WORK/calls.log"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

fails=0
# Build a fresh clean repo on main, in sync with a local bare "origin". Fakes only on PATH if $1=fakes+create-dmg.
new_repo() {
    rm -rf "$WORK/origin.git" "$WORK/repo"
    git init -q --bare -b main "$WORK/origin.git"
    git init -q -b main "$WORK/repo"
    mkdir "$WORK/repo/scripts"
    cp "$ROOT/scripts/release.sh" "$WORK/repo/scripts/"
    git -C "$WORK/repo" remote add origin "$WORK/origin.git"
    echo a > "$WORK/repo/a"
    git -C "$WORK/repo" add -A
    git -C "$WORK/repo" commit -q -m one
    git -C "$WORK/repo" push -q origin main
    : > "$FAKE_LOG"
}

# run_release <env assignments...>: runs release.sh 1.2.3 with a fake-only PATH; sets $status and $output.
run_release() {
    status=0
    output="$(cd "$WORK/repo" && env -i HOME="$WORK" PATH="$FAKES:$TOOLS" FAKE_LOG="$FAKE_LOG" \
        GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
        RELEASE_CHECK_CMD="$WORK/fake-check push" "$@" ./scripts/release.sh 1.2.3 </dev/null 2>&1)" || status=$?
}

ok() { echo "  ok: $1"; }
bad() { echo "  FAIL: $1" >&2; fails=$((fails + 1)); }

# expect_refused <name> <message fragment>: non-zero, message present, no build or signing tool ran.
expect_refused() {
    if [ "$status" = 0 ]; then bad "$1: exited 0"; return; fi
    case "$output" in *"$2"*) ;; *) bad "$1: message lacks '$2' (got: $output)"; return ;; esac
    if grep -Eq '^(codesign|stapler|spctl|create-dmg|gh) |^jj tag|^xcrun (notarytool (submit|log)|stapler)' "$FAKE_LOG"; then
        bad "$1: slow work started: $(cat "$FAKE_LOG")"; return
    fi
    ok "$1"
}

echo "release-test"

new_repo; run_release
if [ "$status" = 0 ] && grep -q '^check push' "$FAKE_LOG"; then ok "clean main passes pre-flight and runs checks"; else bad "happy path (status $status): $output"; fi
if grep -Eq '^(codesign|create-dmg|gh) ' "$FAKE_LOG"; then bad "happy path ran build tools"; else ok "pre-flight stops before any slow work"; fi

new_repo; echo dirty >> "$WORK/repo/a"; run_release
expect_refused "dirty tree" "not clean"

new_repo; git -C "$WORK/repo" checkout -q -b feature
git -C "$WORK/repo" commit -q --allow-empty -m feat; run_release
expect_refused "off main" "not on main"

new_repo; echo b > "$WORK/repo/b"; git -C "$WORK/repo" add -A; git -C "$WORK/repo" commit -q -m two; run_release
expect_refused "ahead of origin" "not in sync"

new_repo
git -C "$WORK/repo" commit -q --allow-empty -m two; git -C "$WORK/repo" push -q origin main
git -C "$WORK/repo" reset -q --hard HEAD~1; run_release
expect_refused "behind origin" "not in sync"

new_repo; git -C "$WORK/repo" tag v1.2.3; git -C "$WORK/repo" commit -q --allow-empty -m two
git -C "$WORK/repo" push -q origin main; run_release
expect_refused "tag on another commit" "already exists on a different commit"

new_repo; git -C "$WORK/repo" tag v1.2.3; run_release
if [ "$status" = 0 ]; then ok "tag already on current commit is accepted"; else bad "tag on current commit refused: $output"; fi

new_repo; rm "$FAKES/create-dmg"; run_release
expect_refused "missing create-dmg" "brew install create-dmg"
printf '#!/bin/sh\necho "create-dmg $*" >> "$FAKE_LOG"\n' > "$FAKES/create-dmg"; chmod +x "$FAKES/create-dmg"

new_repo; run_release FAKE_NO_PROFILE=1
expect_refused "missing notary profile" "xcrun notarytool store-credentials portly"

new_repo; run_release FAKE_CHECK_FAIL=1
expect_refused "failing checks" "checks failed"

new_repo
status=0; output="$(cd "$WORK/repo" && env -i PATH="$FAKES:$TOOLS" FAKE_LOG="$FAKE_LOG" ./scripts/release.sh </dev/null 2>&1)" || status=$?
if [ "$status" != 0 ]; then ok "missing version is a usage error"; else bad "no version accepted"; fi

[ "$fails" = 0 ] || { echo "release-test: $fails failure(s)" >&2; exit 1; }
echo "release-test: ok"
