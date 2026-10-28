# shellcheck shell=bash
# Sourced by build-app.sh and make-dmg.sh; defines find_sign_identity.
# Prints the signing identity: PORTLY_SIGN_IDENTITY if set, else the first
# 'Developer ID Application' identity in the keychain (SHA-1). Prints nothing if there is none.
find_sign_identity() {
    echo "${PORTLY_SIGN_IDENTITY:-$(security find-identity -v -p codesigning \
        | sed -n 's/^ *[0-9]*) \([0-9A-F]\{40\}\) "Developer ID Application:.*/\1/p' | head -n 1)}"
}
