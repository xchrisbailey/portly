# Notarizing a SwiftPM-assembled Portly.app and DMG

Answers issue #12 (map: #10; blocks #14). Research only: nothing was signed, notarized or submitted while writing this.

Sources are Apple's developer documentation, read from the `developer.apple.com/tutorials/data/documentation/...` JSON behind each page on 2026-10-27:

- [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) (N)
- [Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow) (C)
- [Resolving common notarization issues](https://developer.apple.com/documentation/security/resolving-common-notarization-issues) (R)
- [Hardened Runtime](https://developer.apple.com/documentation/security/hardened-runtime) (H)
- [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice), [`mainApp`](https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp), [`register()`](https://developer.apple.com/documentation/servicemanagement/smappservice/register()) (S)

Each claim is tagged with its source letter. **[Inference]** marks a conclusion reasoned from the docs, not stated by them. **[Untested]** marks something that needs a real run.

## Short answer

- Portly needs **no entitlements** and no hardened-runtime exceptions. Signing with `--options runtime --timestamp` and a Developer ID Application identity is enough.
- The only required change to `scripts/build-app.sh` is the signing line (today `codesign --force --sign -`, ad hoc).
- `lsof`, `ps`, `kill(2)`, `killpg(2)` and `proc_*` do not conflict with the hardened runtime. **[Inference]**
- `SMAppService.mainApp` launch-at-login needs no entitlement. Whether it behaves identically after Developer ID signing should be confirmed on a real signed build. **[Untested]**
- Notarize the DMG (it covers the nested app), then staple the DMG. Staple the app first if you also want the `.app` to carry its own ticket.

## What the notary service requires (N, R)

1. Valid code signatures on all executables you distribute (R: "Ensure a valid code signature"). Modifying the bundle after signing invalidates the signature.
2. A **Developer ID** certificate. Ad hoc, Apple Development, Mac Distribution and self-signed identities are rejected (N, R). Use the *Developer ID Application* certificate for Mach-O files, bundles, apps and disk images. *Developer ID Installer* is only for `.pkg` (R).
3. **Hardened runtime** enabled. Without Xcode this is `codesign --options runtime` (R shows `--options=runtime`). Rejection text if missing: "The executable does not have the hardened runtime enabled."
4. A **secure timestamp** (`codesign --timestamp`). It needs network access to `timestamp.apple.com`, the only accepted timestamp server (R). `codesign -dvv` shows a `Timestamp` line when present; `Signed Time` means it is missing.
5. No `com.apple.security.get-task-allow` entitlement set to true (N, R). Portly has no entitlements today, so this is already satisfied. Check with `codesign -d --entitlements - Portly.app`.
6. Linked against the macOS 10.9 SDK or later (R). Portly's binary has `minos 14.0, sdk 14.0` (checked read-only with `vtool` on `build/Portly.app`).
7. If you do pass an entitlements file, it must be ASCII XML without a BOM (R).

Local state (read-only): `security find-identity -v -p codesigning` lists a `Developer ID Application: ... (5U2B7W5F39)` identity and an Apple Development one. Use the Developer ID one.

## Hardened runtime, entitlements and signing order

**Entitlements.** H: the hardened runtime blocks code injection, DLL hijacking and process-memory tampering, "doesn't affect the operation of most apps", and each restriction can be relaxed by an entitlement. The documented exception entitlements are: Apple Events, allow DYLD environment variables, allow JIT, allow unsigned executable memory, debugging tool, disable executable memory protection, disable library validation, plus resource-access entitlements (audio, camera, contacts, calendars, location, photos). H also says to use "only the entitlements that are absolutely necessary" and that false-valued boolean entitlements should be omitted rather than written as `false`. Portly uses none of these (see next section), so ship **without an entitlements file**.

**Sandbox.** The App Sandbox is not part of notarization. A sandboxed app could not run `lsof` or signal other processes, so Portly stays unsandboxed. **[Inference]**

**Signing order.** R: sign inside out and verify with `codesign -vvv --deep --strict`. Portly's bundle has one executable (`Contents/MacOS/Portly`) and one SwiftPM resource bundle copied into `Contents/Resources/`. N and C: keep non-executable files out of code-signed locations such as `Contents/MacOS`, which Portly already does.

Proposed replacement for the ad hoc line in `scripts/build-app.sh`:

```sh
IDENTITY="Developer ID Application: CHRISTOPHER BRIAN BAILEY (5U2B7W5F39)"
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
```

**[Untested]** One thing to check on the first real run: the SwiftPM resource bundle (`Portly_Portly.bundle`) is a nested bundle. If `codesign` on the outer app complains about it, sign it first (`codesign --force --timestamp --sign "$IDENTITY" "$APP/Contents/Resources/Portly_Portly.bundle"`), then sign the app. Apple's pages do not cover SwiftPM resource bundles specifically.

Ad hoc signing should remain available for local and CI builds without the identity (for example gated on an env var), because Apple silicon refuses unsigned binaries and `scripts/check.sh push` calls `build-app.sh --build-only`. **[Inference]**

## Does Portly conflict with the hardened runtime?

Portly's system access, from the source:

| Code | What it does |
| --- | --- |
| `SystemProcessSource.run` | `Process` launching `/usr/sbin/lsof` and `/bin/ps` |
| `SystemProcessSource.executablePaths` | `proc_pidpath` |
| `SystemSignaller` | `kill(2)`, `killpg(2)`, `proc_pidinfo`, `proc_listpids` |
| `LaunchAtLoginToggle` | `SMAppService.mainApp.register()/unregister()/status` |

H lists what the hardened runtime restricts: injection, dylib hijacking, memory tampering, JIT, DYLD variables, library validation, and access to protected resources. None of the calls above is in that list. Conclusions, all **[Inference]** from the H list (Apple does not discuss `kill`, `lsof` or `proc_*` on that page):

- **`kill`/`killpg`.** Signal delivery is governed by the usual UID/permission checks (`EPERM`, which `SystemSignaller` already handles), not by the hardened runtime.
- **`proc_pidpath`, `proc_pidinfo`, `proc_listpids`.** These are libproc queries, not `task_for_pid`. The "debugging tool" entitlement relates to inspecting other processes' memory, which Portly does not do.
- **Spawning `lsof` and `ps`.** These are Apple-signed system binaries run as separate processes. Library validation covers libraries loaded into Portly's own process, not child executables. No `DYLD_*` variables are set.
- **Same limits as today.** `lsof -d cwd` and `proc_pidpath` for other users' processes already return nothing without privilege; signing does not change that. Possible TCC side effect: replacing an ad hoc signature (cdhash-based identity) with a Developer ID signature gives the app a stable identity, which affects how any future permission prompts persist. Portly requests no TCC resources today.

**Launch at login.** S says `register()` on the main app makes it "launch on subsequent logins" "subject to user approval", and returns `kSMErrorLaunchDeniedByUser` if the user has not approved. No entitlement or notarization requirement is documented for `mainApp` on these pages. `LaunchAtLoginToggle` already re-reads `status` each time the panel opens, so approval in System Settings is picked up. **[Untested]** Registration is keyed to the app's signature and location; confirm that a Developer ID signed build installed in `/Applications` registers, shows in System Settings > Login Items, and survives replacing the app with a new version.

## Credentials for `notarytool` (C)

C documents two ways to give `notarytool` credentials:

- **Keychain profile (recommended by C for scripts).** Run once: `xcrun notarytool store-credentials "<profile>" --apple-id "<AppleID>" --team-id <TeamID> --password <app-specific-password>`. Later calls pass `--keychain-profile "<profile>"` and no secret appears in the script. C says an app-specific password is required because App Store Connect needs 2FA.
- **Inline** `--apple-id/--password` flags (cleartext in the script; C advises against).

C does not describe API-key auth in these pages; it points to the Notary API for web access. `notarytool --help` documents `--key/--key-id/--issuer` for App Store Connect API keys, which suit CI; this was not verified against an Apple web page. **Recommendation:** use a keychain profile for the maintainer's local releases. The profile lives in the login keychain on the maintainer's machine and is not stored in the repo. Team ID here is `5U2B7W5F39` (from the identity name).

## DMG: build, sign, notarize, staple

C: the notary service accepts UDIF disk images, signed flat installer packages and ZIP archives, and processes nested containers. A ticket is generated for the submitted file and for each nested item. A `.app` bundle cannot be uploaded directly. A ZIP cannot be stapled; staple the items first, then re-zip.

Proposed sequence (not run):

```sh
# 0. build, sign app (hardened runtime + timestamp), verify   (see above)
# 1. optional: notarize + staple the app alone via a ditto zip, so the .app carries its own ticket
ditto -c -k --keepParent build/Portly.app build/Portly.zip
xcrun notarytool submit build/Portly.zip --keychain-profile "<profile>" --wait
xcrun stapler staple build/Portly.app
# 2. build the DMG from the (stapled) app, then sign the DMG itself
hdiutil create -volname Portly -srcfolder <staging dir with Portly.app and /Applications symlink> -ov -format UDZO build/Portly.dmg
codesign --force --timestamp --sign "$IDENTITY" build/Portly.dmg
# 3. notarize the DMG, check the log, staple
xcrun notarytool submit build/Portly.dmg --keychain-profile "<profile>" --wait
xcrun notarytool log <submission-id> --keychain-profile "<profile>"   # check even on success
xcrun stapler staple build/Portly.dmg
```

Notes:

- Step 1 is optional because the DMG submission already notarizes the nested app (C). It is worth doing if the app is also distributed outside the DMG (zip, Homebrew cask) or dragged out before the DMG ticket is consulted. The cost is a second submission against the 75-per-day limit (C).
- R: sign disk images with the Developer ID **Application** certificate. A DMG does not need the hardened runtime flag, only a valid signature and timestamp; R's requirement list applies to executables. **[Inference]** `--options runtime` on a DMG is harmless but unnecessary.
- C: avoid corrupted or heavily compressed images; check with `hdiutil verify <image>`. UDZO is zlib compression; UDBZ/ULFO are heavier. **[Inference]** from "avoid heavily compressed".
- Notarization typically takes under 15 minutes for 98 percent of submissions (C). `--wait` blocks until done. Stapler needs network access to CloudKit (C).
- Stapling requires a writable DMG (R, "error -73" note).
- `notarytool` and `stapler` ship with Xcode (C). Installed here: macOS 27.0.1, SDK 27.0, `notarytool` 1.1.3.

## Verification

Commands named in the Apple pages:

- `codesign -vvv --deep --strict <app>`: signature valid under notarization-strict rules (R).
- `codesign -dvv <app>`: shows `Timestamp` when the secure timestamp is present (R).
- `codesign -d --entitlements - <app>`: confirms no `get-task-allow` and no stray entitlements (R).
- `spctl -vvv --assess --type exec <app>`: whether the app would run under current Gatekeeper policy (R).
- `xcrun stapler staple <item>` then `xcrun stapler validate <item>`: ticket attached and valid. The `validate` subcommand is not shown in C or R; it is documented in `man stapler`.
- `xcrun notarytool log <id> --keychain-profile <profile>`: the issues and warnings JSON (C).

From general tooling knowledge, not an Apple web page: for the DMG, `spctl --assess --type open --context context:primary-signature -v build/Portly.dmg`; for an installed app after stapling, `spctl -a -vvv -t install` / `-t exec`. Gatekeeper only fully exercises these on a quarantined download, so the real test is downloading the DMG in a browser to a clean user account or machine and opening it.

## Recommendations for #14

1. Change `build-app.sh` to sign with Developer ID, `--options runtime --timestamp`, no entitlements file, keeping an ad hoc fallback for no-identity builds.
2. Add a separate release script (not part of `check.sh`) for the DMG, notarize and staple steps, since it needs network access, a keychain profile, and counts against Apple's daily limit.
3. Store notary credentials with `notarytool store-credentials`, using a profile name read from an env var.
4. Always fetch `notarytool log` after submission, even on success (C).
5. Do a first dry run with the real identity and answer the two untested points: SwiftPM resource bundle signing order, and `SMAppService.mainApp` registering from a Developer ID signed `/Applications` install.
6. Bump `CFBundleVersion`/`CFBundleShortVersionString` per release; they are hardcoded in `build-app.sh`'s Info.plist heredoc. **[Inference]** (not a notarization requirement).

## Not covered

- Apple's pages describe notarization policy as of their last update; minimum SDK and Xcode versions have changed before (N: `altool` stopped working 2023-11-01). Re-check before the first release.
- Sparkle or other auto-update tooling, and `.pkg` distribution, are out of scope.
