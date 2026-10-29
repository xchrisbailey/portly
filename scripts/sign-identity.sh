# shellcheck shell=bash
# Sourced by build-app.sh and make-dmg.sh; defines find_sign_identity and require_sign_identity.
# Prints the signing identity: PORTLY_SIGN_IDENTITY if set, else the first
# 'Developer ID Application' identity in the keychain (SHA-1). Prints nothing if there is none.
find_sign_identity() {
    echo "${PORTLY_SIGN_IDENTITY:-$(security find-identity -v -p codesigning \
        | sed -n 's/^ *[0-9]*) \([0-9A-F]\{40\}\) "Developer ID Application:.*/\1/p' | head -n 1)}"
}

# Sets SIGN_IDENTITY to find_sign_identity's result. Prints the fix and returns 1 if there is none,
# so callers can fail before any slow work.
require_sign_identity() {
    SIGN_IDENTITY="$(find_sign_identity)"
    if [[ -z "$SIGN_IDENTITY" ]]; then
        echo "error: signing needs a 'Developer ID Application' identity in the keychain" >&2
        echo "       (see: security find-identity -v -p codesigning), or set PORTLY_SIGN_IDENTITY" >&2
        return 1
    fi
}
