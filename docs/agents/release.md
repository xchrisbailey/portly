# Releases

`scripts/release.sh X.Y.Z` ships a signed, notarized, stapled `Portly-X.Y.Z.dmg` as a GitHub release tagged `vX.Y.Z`. It runs on the maintainer's Mac in a GUI session. The step order and its env overrides are in the header of `scripts/release.sh`; its pre-flight failures print the fix. `create-dmg` runs under a watchdog (`PORTLY_DMG_TIMEOUT`, default 600s) and pre-flight refuses while a `Portly` volume is mounted, because `create-dmg` can stall on either. A foreground command that outlives the tool timeout keeps running in the background: check its output before calling it hung.

## Cut a release

1. Land the work on `main` and push it, so `main` matches `origin/main` with a clean working copy.
2. Run `scripts/release.sh X.Y.Z`. It takes minutes, mostly waiting on Apple.
3. Confirm the GitHub release shows the DMG and generated notes.

## One-time setup

- `brew install create-dmg`
- A `Developer ID Application` certificate with its private key in the login keychain. `security find-identity -v -p codesigning` must list it (`PORTLY_SIGN_IDENTITY` overrides the lookup).
- `xcrun notarytool store-credentials portly` (Apple ID, team ID, app-specific password). The script never prompts for or stores credentials.
- Grant the terminal Automation permission for Finder (System Settings > Privacy & Security > Automation). `create-dmg` drives Finder, so a headless session fails.
- `gh auth login`.

## After a failed run

Re-run the same command; there is no resume flag. The tag is created and pushed after verify, so a failure before then leaves no tag and no release. It leaves `build/release/` (or `BUILD_DIR`), including the app, the DMG and its `.notarized.sha256` / `.stapled.sha256` records, which `dmg_state` in the script reads to skip finished steps. The release directory is separate from `build/` because the pre-flight `scripts/check.sh push` rebuilds the dev app into `build/`.

- Failure after the tag is pushed: the re-run keeps the tag (same commit) and uploads the DMG to an existing release.
- Notarization rejected: the log is printed; fix the cause and re-run, which rebuilds from scratch.
- Anything that changed the DMG since its record, a different commit than the one recorded, or no record, rebuilds.

## First-release dry run (#24)

The first real release closes what only real notarization can check. Tick these on that run:

- [x] SwiftPM resource-bundle signing order: `scripts/release.sh` completes its `verify` step, and the app launches.
- [x] Launch-at-login registers from the signed app dragged from the DMG into `/Applications`.
- [x] A browser-downloaded (quarantined) DMG opens with no Gatekeeper warning.
- [ ] Re-check Apple's current SDK and Xcode minimums for notarization against the installed Xcode.
- [x] Note that the x86_64 slice of the universal binary is untested on hardware.
