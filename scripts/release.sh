#!/usr/bin/env bash
# Signed, notarized DMG release: scripts/release.sh X.Y.Z
# Runs the steps below in order and stops at the first failure. Each step is a function;
# later steps (build, DMG, notarize, verify, tag, publish) are added to STEPS in that order.
#
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

# Ordered; stop at the first failure (set -e). Extend here.
STEPS=(preflight)

for step in "${STEPS[@]}"; do
    "$step"
done
echo "==> release $VERSION: steps complete (${STEPS[*]})"
