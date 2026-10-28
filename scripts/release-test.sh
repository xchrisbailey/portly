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

# Every fake logs its call and fails when the call matches the glob in $FAKE_FAIL (failure injection).
for t in codesign spctl jj; do
    cat > "$FAKES/$t" <<'FAKE'
#!/bin/sh
call="$(basename "$0") $*"
echo "$call" >> "$FAKE_LOG"
case "$call" in $FAKE_FAIL) exit 1 ;; esac
exit 0
FAKE
done
# gh: `release view` fails (no such release) unless $FAKE_RELEASE_EXISTS=1.
cat > "$FAKES/gh" <<'FAKE'
#!/bin/sh
call="gh $*"
echo "$call" >> "$FAKE_LOG"
case "$call" in "gh release view"*) [ "${FAKE_RELEASE_EXISTS:-}" = 1 ]; exit $? ;; esac
case "$call" in $FAKE_FAIL) exit 1 ;; esac
exit 0
FAKE
# create-dmg: also writes the DMG (its second-to-last argument), as the real one does.
cat > "$FAKES/create-dmg" <<'FAKE'
#!/bin/sh
call="create-dmg $*"
echo "$call" >> "$FAKE_LOG"
case "$call" in $FAKE_FAIL) exit 1 ;; esac
for a in "$@"; do prev="$last"; last="$a"; done
: > "$prev"
FAKE
# swift: `build` succeeds; `--show-bin-path` prints a directory holding a fake Portly and its resource bundle.
cat > "$FAKES/swift" <<'FAKE'
#!/bin/sh
call="swift $*"
echo "$call" >> "$FAKE_LOG"
case "$call" in $FAKE_FAIL) exit 1 ;; esac
case "$call" in *--show-bin-path*) echo "$FAKE_BIN_DIR" ;; esac
exit 0
FAKE
# xcrun: `notarytool history` fails when the profile is "missing"; submit and log answer with JSON
# whose status is $FAKE_NOTARY_STATUS (default Accepted).
cat > "$FAKES/xcrun" <<'FAKE'
#!/bin/sh
call="xcrun $*"
echo "$call" >> "$FAKE_LOG"
if [ "${FAKE_NO_PROFILE:-}" = 1 ] && [ "${1:-}" = notarytool ]; then exit 1; fi
case "$call" in $FAKE_FAIL) exit 1 ;; esac
status="${FAKE_NOTARY_STATUS:-Accepted}"
case "$1 $2" in
    "notarytool submit") printf '{"id":"sub-123","message":"Processing complete","status":"%s"}\n' "$status" ;;
    "notarytool log") printf '{\n  "jobId" : "sub-123",\n  "status" : "%s",\n  "issues" : null\n}\n' "$status" ;;
esac
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

for t in bash sh env git dirname basename cat grep sed tr rm mkdir cp mktemp head tail cut shasum; do
    ln -s "$(command -v "$t")" "$TOOLS/$t"
done

export FAKE_LOG="$WORK/calls.log"
export FAKE_BIN_DIR="$WORK/swift-bin"
mkdir -p "$FAKE_BIN_DIR/Portly_Portly.bundle"
: > "$FAKE_BIN_DIR/Portly"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

fails=0
# Build a fresh clean repo on main, in sync with a local bare "origin". Fakes only on PATH if $1=fakes+create-dmg.
new_repo() {
    rm -rf "$WORK/origin.git" "$WORK/repo"
    git init -q --bare -b main "$WORK/origin.git"
    git init -q -b main "$WORK/repo"
    mkdir "$WORK/repo/scripts"
    # The real build and DMG scripts run too, against fake swift, codesign and create-dmg.
    cp "$ROOT/scripts/release.sh" "$ROOT/scripts/build-app.sh" "$ROOT/scripts/make-dmg.sh" \
        "$ROOT/scripts/sign-identity.sh" "$WORK/repo/scripts/"
    mkdir "$WORK/repo/assets"
    : > "$WORK/repo/assets/AppIcon.icns"
    : > "$WORK/repo/assets/dmg-background.png"
    printf 'build/\n' > "$WORK/repo/.gitignore"
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
        GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null FAKE_BIN_DIR="$FAKE_BIN_DIR" \
        PORTLY_SIGN_IDENTITY="Developer ID Application: Fake (TEST)" \
        RELEASE_CHECK_CMD="$WORK/fake-check push" "$@" ./scripts/release.sh 1.2.3 </dev/null 2>&1)" || status=$?
}

ok() { echo "  ok: $1"; }
bad() { echo "  FAIL: $1" >&2; fails=$((fails + 1)); }

# expect_refused <name> <message fragment>: non-zero, message present, no build or signing tool ran.
expect_refused() {
    if [ "$status" = 0 ]; then bad "$1: exited 0"; return; fi
    case "$output" in *"$2"*) ;; *) bad "$1: message lacks '$2' (got: $output)"; return ;; esac
    if grep -Eq '^(codesign|stapler|spctl|create-dmg|gh|swift) |^jj (tag|git push)|^xcrun (notarytool (submit|log)|stapler)' "$FAKE_LOG"; then
        bad "$1: slow work started: $(cat "$FAKE_LOG")"; return
    fi
    ok "$1"
}

echo "release-test"

new_repo; run_release
if [ "$status" = 0 ] && grep -q '^check push' "$FAKE_LOG"; then ok "clean main passes pre-flight and runs checks"; else bad "happy path (status $status): $output"; fi

# in_order <pattern>...: each extended-regex pattern matches a log line after the previous one's match.
in_order() {
    local pos=0 line p
    for p in "$@"; do
        line="$(tail -n +"$((pos + 1))" "$FAKE_LOG" | grep -En -m1 -- "$p" | head -n 1 | cut -d: -f1)"
        if [ -z "$line" ]; then bad "call order: '$p' missing or out of order (log: $(tr '\n' '|' < "$FAKE_LOG"))"; return; fi
        pos=$((pos + line))
    done
    ok "call order: $# calls in sequence"
}

in_order '^check push' \
    '^swift build .*--arch arm64 --arch x86_64' \
    '^codesign --force --options runtime .*Portly_Portly\.bundle' \
    '^codesign --force --options runtime .*Portly\.app$' \
    '^codesign -vvv --deep --strict .*Portly\.app' \
    '^create-dmg .*Portly-1\.2\.3\.dmg' \
    '^codesign --force --timestamp .*Portly-1\.2\.3\.dmg' \
    '^xcrun notarytool submit .*Portly-1\.2\.3\.dmg --keychain-profile portly --wait' \
    '^xcrun notarytool log sub-123 --keychain-profile portly' \
    '^xcrun stapler staple .*Portly-1\.2\.3\.dmg' \
    '^codesign --verify --deep --strict .*Portly\.app' \
    '^spctl .*Portly\.app' \
    '^spctl .*Portly-1\.2\.3\.dmg' \
    '^xcrun stapler validate .*Portly-1\.2\.3\.dmg' \
    '^jj tag set v1\.2\.3' \
    '^jj git push .*--tag v1\.2\.3' \
    '^gh release create v1\.2\.3 .*Portly-1\.2\.3\.dmg .*--generate-notes'

plist="$WORK/repo/build/Portly.app/Contents/Info.plist"
if grep -q '<key>CFBundleShortVersionString</key><string>1.2.3</string>' "$plist"; then ok "Info.plist carries the version argument"; else bad "Info.plist version: $(cat "$plist" 2>&1)"; fi

# expect_stopped <name> <FAKE_FAIL glob | FAKE_NOTARY_STATUS=...> <stage>
# Re-runs the release with a failure injected; it must fail and stop. Stage is the latest step that may
# have run: none (no tag, push or release), tag (tag set, nothing pushed), push (pushed, no release), release.
expect_stopped() {
    new_repo
    case "$2" in FAKE_NOTARY_STATUS=*) run_release "$2" ;; *) run_release FAKE_FAIL="$2" ;; esac
    if [ "$status" = 0 ]; then bad "$1: exited 0"; return; fi
    # The failure must have been injected where intended: the last call is the one that failed.
    case "$2" in FAKE_NOTARY_STATUS=*) ;; *)
        case "$(tail -n 1 "$FAKE_LOG")" in $2) ;; *) bad "$1: stopped elsewhere (last call: $(tail -n 1 "$FAKE_LOG"))"; return ;; esac ;;
    esac
    case "$3" in
        none) if grep -Eq '^(jj tag|jj git push|gh release)' "$FAKE_LOG"; then bad "$1: tag or release step ran"; return; fi ;;
        tag) if grep -Eq '^(jj git push|gh release)' "$FAKE_LOG"; then bad "$1: went past the tag"; return; fi ;;
        push) if grep -q '^gh release' "$FAKE_LOG"; then bad "$1: released after failed push"; return; fi ;;
    esac
    ok "$1"
}

expect_stopped "app build fails" 'swift build*' none
expect_stopped "app signing fails" 'codesign --force --options runtime*Portly.app' none
expect_stopped "app signature check fails" 'codesign -vvv --deep*' none
expect_stopped "DMG build fails" 'create-dmg*' none
expect_stopped "DMG signing fails" 'codesign --force --timestamp*' none
expect_stopped "notarytool submit fails" 'xcrun notarytool submit*' none
expect_stopped "notarization Invalid" FAKE_NOTARY_STATUS=Invalid none
expect_stopped "notarization Rejected" FAKE_NOTARY_STATUS=Rejected none
expect_stopped "notarization log fetch fails" 'xcrun notarytool log*' none
expect_stopped "stapling fails" 'xcrun stapler staple*' none
expect_stopped "codesign verify fails" 'codesign --verify*' none
expect_stopped "spctl app assessment fails" 'spctl*exec*' none
expect_stopped "spctl DMG assessment fails" 'spctl*open*' none
expect_stopped "stapler validate fails" 'xcrun stapler validate*' none
expect_stopped "tag creation fails" 'jj tag set*' tag
expect_stopped "tag push fails" 'jj git push*' push
expect_stopped "release creation fails" 'gh release create*' release

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
if [ "$status" = 0 ] && ! grep -q '^jj tag set' "$FAKE_LOG" && grep -q '^gh release create' "$FAKE_LOG"; then
    ok "tag already on current commit is accepted and not re-created"
else bad "tag on current commit (status $status): $output"; fi

# Re-runs: no new repo between the failed run and the retry, so build/ and its checksum files persist.
count() { grep -Ec -- "$1" "$FAKE_LOG" || true; }
expect_none_ran() { # <name> <pattern>...
    local n="$1" p; shift
    for p in "$@"; do
        if [ "$(count "$p")" != 0 ]; then bad "$n: '$p' ran again"; return; fi
    done
    ok "$n"
}

new_repo; run_release FAKE_FAIL='xcrun stapler staple*'
[ "$status" != 0 ] || bad "staple failure setup exited 0"
: > "$FAKE_LOG"; run_release
if [ "$status" != 0 ]; then bad "re-run after staple failure: $output"
else
    expect_none_ran "re-run after failure past notarization: no rebuild, no re-submit" '^swift ' '^create-dmg ' '^codesign --force' 'notarytool submit'
    in_order '^xcrun stapler staple' '^xcrun stapler validate' '^jj tag set' '^gh release create'
fi

new_repo; run_release FAKE_FAIL='xcrun notarytool log*'
: > "$FAKE_LOG"; run_release
if [ "$status" = 0 ] && [ "$(count 'notarytool submit')" = 1 ] && [ "$(count '^create-dmg ')" = 1 ]; then
    ok "re-run after a failed (unrecorded) notarization starts over rather than trusting the DMG"
else bad "re-run after notarization failure (status $status): $output"; fi

new_repo; run_release FAKE_FAIL='gh release create*'
: > "$FAKE_LOG"; run_release
if [ "$status" = 0 ]; then
    expect_none_ran "re-run after publish failure reuses the stapled DMG" '^swift ' '^create-dmg ' '^codesign --force' 'notarytool submit' 'stapler staple'
    if [ "$(count '^codesign --verify')" = 1 ] && [ "$(count '^xcrun stapler validate')" = 1 ]; then ok "reused DMG is still re-verified"; else bad "reused DMG not re-verified"; fi
else bad "re-run after publish failure: $output"; fi

new_repo; run_release FAKE_FAIL='gh release create*'
echo changed >> "$WORK/repo/build/Portly-1.2.3.dmg"
: > "$FAKE_LOG"; run_release
if [ "$status" = 0 ] && [ "$(count '^create-dmg ')" = 1 ] && [ "$(count 'notarytool submit')" = 1 ]; then
    ok "changed DMG checksum forces a rebuild and re-notarization"
else bad "changed checksum re-run (status $status): $output"; fi

new_repo; run_release FAKE_RELEASE_EXISTS=1
if [ "$status" = 0 ] && grep -q '^gh release upload v1.2.3 .*Portly-1\.2\.3\.dmg --clobber' "$FAKE_LOG" \
    && ! grep -q '^gh release create' "$FAKE_LOG"; then
    ok "existing release gets the DMG uploaded with --clobber and exits 0"
else bad "existing release (status $status): $output"; fi

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
