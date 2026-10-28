#!/usr/bin/env bash
# Signed, notarized DMG release: scripts/release.sh X.Y.Z
# Runs the steps below in order and stops at the first failure. Each step is a function.
# Order: pre-flight, build and sign the app, build and sign the DMG, notarize, staple, verify,
# then tag, push the tag, and publish the GitHub release. The tag comes last on purpose: any
# failure before it leaves no tag and no release behind.
#
#   BUILD_DIR           where the app and DMG are written (default: build)

#   RELEASE_CHECK_CMD   command run as the last pre-flight check (default: scripts/check.sh push);
#                       the release test points it at a fake so it never recurses into real checks
#   RELEASE_REMOTE      git remote that must be in sync with main (default: origin)
#
# This script never prompts for or stores credentials; the notary profile is a one-time manual setup.
set -euo pipefail

cd "$(dirname "$0")/.."
CHECK_CMD="${RELEASE_CHECK_CMD:-scripts/check.sh push}"
REMOTE="${RELEASE_REMOTE:-origin}"
NOTARY_PROFILE="portly"
BUILD_DIR="${BUILD_DIR:-build}"

fail() {
    echo "release: $*" >&2
    exit 1
}

usage() {
    echo "usage: scripts/release.sh X.Y.Z" >&2
    exit 64
}

[[ $# -eq 1 ]] || usage
VERSION="$1"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "version must look like X.Y.Z, got '$VERSION'"
TAG="v$VERSION"
APP="$BUILD_DIR/Portly.app"
DMG="$BUILD_DIR/Portly-$VERSION.dmg"

preflight() {
    echo "==> pre-flight"

    [[ -z "$(git status --porcelain)" ]] || fail "working copy is not clean; commit or discard changes first"

    # Colocated jj leaves HEAD detached, so compare commits rather than reading a branch name.
    local head main
    head="$(git rev-parse HEAD)"
    main="$(git rev-parse -q --verify refs/heads/main)" || fail "no main branch"
    [[ "$head" == "$main" ]] || fail "not on main (HEAD is not the main commit)"
    jj git fetch --remote "$REMOTE" >/dev/null || fail "could not fetch $REMOTE"
    local remote_main
    remote_main="$(git rev-parse -q --verify "refs/remotes/$REMOTE/main")" || fail "no $REMOTE/main to compare against"
    [[ "$main" == "$remote_main" ]] || fail "main is not in sync with $REMOTE/main; push or pull first"

    local tag_commit
    if tag_commit="$(git rev-parse -q --verify "refs/tags/$TAG^{commit}")"; then
        [[ "$tag_commit" == "$head" ]] || fail "tag $TAG already exists on a different commit ($tag_commit)"
    fi

    command -v create-dmg >/dev/null || fail "create-dmg not found; install it with: brew install create-dmg"

    xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
        || fail "notarytool keychain profile '$NOTARY_PROFILE' not found or unusable; set it up once with: xcrun notarytool store-credentials $NOTARY_PROFILE"

    $CHECK_CMD || fail "checks failed; nothing was built"
}

build_app() {
    echo "==> build and sign app"
    scripts/build-app.sh --version "$VERSION" --build-only
    [[ -d "$APP" ]] || fail "build produced no $APP"
}

build_dmg() {
    echo "==> build and sign DMG"
    scripts/make-dmg.sh "$APP" "$VERSION" "$BUILD_DIR"
    [[ -f "$DMG" ]] || fail "DMG build produced no $DMG"
}

# Pulls a string field out of notarytool's JSON output (one value per call, no jq dependency).
json_field() {
    printf '%s' "$2" | sed -n 's/.*"'"$1"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1
}

notarize() {
    echo "==> notarize $DMG (waits for Apple)"
    local result id status
    result="$(xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json)" \
        || fail "notarytool submit failed"
    id="$(json_field id "$result")"
    status="$(json_field status "$result")"
    [[ -n "$id" ]] || fail "notarytool returned no submission id: $result"
    # The log is fetched even on success; it carries any warnings and is the record on failure.
    local log
    log="$(xcrun notarytool log "$id" --keychain-profile "$NOTARY_PROFILE")" \
        || fail "could not fetch the notarization log for $id"
    [[ "$status" == "Accepted" ]] || fail "notarization $id ended '$status', not Accepted:
$log"
    [[ "$(json_field status "$log")" == "Accepted" ]] || fail "notarization log for $id is not Accepted:
$log"
}

staple() {
    echo "==> staple $DMG"
    xcrun stapler staple "$DMG"
}

verify() {
    echo "==> verify"
    codesign --verify --deep --strict "$APP"
    spctl --assess --type exec "$APP"
    spctl --assess --type open --context context:primary-signature "$DMG"
    xcrun stapler validate "$DMG"
}

# Last on purpose: nothing above leaves a tag or a release behind.
tag_and_push() {
    echo "==> tag $TAG"
    jj tag set "$TAG" -r main
    jj git push --remote "$REMOTE" --tag "$TAG"
}

publish() {
    echo "==> GitHub release $TAG"
    gh release create "$TAG" "$DMG" --title "Portly $VERSION" --generate-notes --verify-tag
}

# Ordered; stop at the first failure (set -e).
STEPS=(preflight build_app build_dmg notarize staple verify tag_and_push publish)

for step in "${STEPS[@]}"; do
    "$step"
done
echo "==> release $VERSION: steps complete (${STEPS[*]})"
