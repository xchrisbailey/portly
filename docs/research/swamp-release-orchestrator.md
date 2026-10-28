# Does swamp fit as the release orchestrator? (issue #11)

Question: can the installed `swamp` CLI run the release steps (build, Developer ID sign, notarize, DMG, `gh release create`) as a workflow, keep notarization credentials in a vault, take the version as an input, and fail/resume cleanly? What does it add over a plain `scripts/release.sh`?

This note reports facts and a recommendation. It does not make the decision; that belongs to the release-flow ticket (#14). No release steps were run.

## Method

- Version tested: `swamp 20261022.021804.0-sha.983e2929` (arm64 Mach-O at `~/.local/bin/swamp`).
- Sources: `swamp --help` and subcommand help, `swamp workflow schema get --json`, `swamp behavior type describe command/shell`, and the upstream README (https://github.com/systeminit/swamp) and manual page (https://swamp-club.com/manual/explanation/how-swamp-works).
- Experiment: a throwaway swamp repo in a scratch directory (not this repo) with a dummy vault secret and a 3-step shell workflow (`build` -> `notarize` -> `dmg`) that used only `echo` and `test`. `notarize` was made to fail on purpose, then retried.

## Findings

### Workflows can run shell steps (yes)

- A workflow is YAML: `jobs[].steps[]`, each with a `task`. Task types in the schema: `model_method`, `behavior`, `workflow`, `manual_approval`, `assert`, `wait_for_signal`.
- Shell commands come from the built-in `command/shell` type, method `execute`. Arguments: `run`, `workingDir`, `timeout` (ms), `env` (string map), `ignoreExitCode`.
- Steps order through `dependsOn: [{step, condition}]`. Conditions: `always`, `succeeded`, `failed`, `completed`, `skipped`, plus `and`/`or`/`not`. Steps also support `allowFailure`, `guard`, `forEach`.
- Without `dependsOn`, steps in one job run in parallel (manual: "Steps within a job run in parallel"), so a serial release needs explicit `dependsOn` on every step.
- A step with `modelType: command/shell` also needs `modelName` (the auto-created definition name); without it the run fails with "modelType requires modelName to name the auto-created definition".
- `manual_approval` suspends a run until `swamp workflow approve|reject`. Useful as a "really publish?" gate before `gh release create`.

### Version as an input (works, with a caveat)

- Workflows declare `inputs` as a JSON-schema object (`required`, `properties`). Pass with `swamp workflow run rel --input version=1.2.3` (also `--input-file` or `--stdin`). Reference as `${{ inputs.version }}`.
- Caveat observed: a `pattern: '^[0-9]+\.[0-9]+\.[0-9]+$'` on the input was not enforced. `--input version=abc` ran `build` with "abc". Validate the version inside the first step (or an `assert` step) instead.

### Credentials in a vault (works, with caveats)

- `swamp init` creates a default `local_encryption` vault (AES-GCM). This is the only vault type installed here (`swamp vault type search`). The manual names AWS Secrets Manager and 1Password as other providers, but they were not listed locally (may be extensions).
- Store with `swamp vault put default APPLE_APP_PASSWORD <value>`; reference with `${{ vault.get(default, APPLE_APP_PASSWORD) }}` (syntax confirmed by experiment). Injected into a step's `env`, the value printed as `pw=***` in run logs: output is redacted.
- A plaintext search of the scratch repo for the secret found nothing; ciphertext is in `.swamp/secrets/local_encryption/default/APPLE_APP_PASSWORD.enc`.
- Caveat: with the default `auto_generate: true`, the encryption key is `.swamp/secrets/local_encryption/default/.key`, next to the ciphertext, inside the repo directory. `.swamp/` is gitignored by swamp's managed `.gitignore` block, so it is not committed, but the key and ciphertext do sit in the checkout. The `local_encryption` config has `base_dir`, `key_file`, `ssh_key_path` and `auto_generate` fields (named in `swamp vault create --help`), so the key can presumably be moved outside the repo. That relocation was not tested.
- Caveat: this is encryption at rest with the key on the same disk, comparable in strength to a `chmod 600` file. It is not the macOS Keychain.
- Caveat: `command/shell` marks `workingDir` as `secrets: refuse`, so secrets cannot flow into the working directory. `env` and `run` accepted the secret.

### Fail and resume (works)

- A failed step fails the run (exit 1), downstream steps show `skipped dmg (dependency)`, and swamp prints `swamp workflow resume rel --run <id>`.
- Resuming retried only the failed and skipped steps (`notarize`, `dmg`); `build` was not rerun. `--from <step>` picks the retry point; `resume` rejects changing an input the run already has.
- Interrupted runs (killed process, crash): `swamp workflow recover` resets unknown steps to pending; `--acknowledge-unknown` accepts re-execution of steps without guard expressions, `--assess-only` reports first.
- `swamp workflow run --timeout <dur>` sends SIGTERM to in-flight subprocesses and runs `always`/`completed` cleanup steps.
- Resume re-runs a step from scratch. Whether a half-finished step is safe to repeat (notarize submit, `gh release create`) is on us: use `guard` expressions or make the scripts idempotent.

### Cost and friction

- Account and licence: the README says a swamp-club.com account is required to run swamp, including in CI. This machine is logged in (`swamp auth whoami`). License is AGPL-3.0 with an extension/definition exception (README); irrelevant for local use of the CLI.
- Telemetry is on by default (README). Opt out with `--no-telemetry`, `SWAMP_NO_TELEMETRY=1`, `DO_NOT_TRACK=1`, or `swamp config set telemetry.collection disabled`. Per the README, option values and secrets are redacted but command words and names are sent.
- Repo footprint: `swamp init` adds `.swamp.yaml`, `.swamp/` (4 MB after a few runs), `models/`, `vaults/`, `workflows/`, `grants/`, and edits `.gitignore`. A repo-local swamp setup would add these to portly; `--repo-dir` / `SWAMP_REPO_DIR` could point at a separate directory instead.
- Run history, per-run data and logs are stored under `.swamp/`; the shell `result` output keeps exit code, stdout and stderr (the `log` output spec has `garbageCollection: 10`).
- Maturity: the project is active (2,876 commits per the README) but external PRs are auto-closed and the CLI surface is large and moving (CalVer build `20261022`). Expect churn.
- Error output on some failures is a raw stack trace (seen with `swamp workflow validate` on a malformed file).
- `swamp workflow create <name>` writes `workflows/workflow-<name>.yaml` with a UUID `id` and `version: 1`. A hand-written `workflows/rel.yaml` with a different id was reported "Workflow not found"; use `workflow create` and then edit the generated file.

## What swamp would add over `scripts/release.sh`

| Concern | Plain `scripts/release.sh` | swamp workflow |
| --- | --- | --- |
| One command, version input | `scripts/release.sh 1.2.3` | `swamp workflow run release --input version=1.2.3` (no input pattern enforcement) |
| Credentials | Keychain (`xcrun notarytool store-credentials` keychain profile) or env var; nothing in repo | Encrypted vault; key beside ciphertext under gitignored `.swamp/` unless relocated; log redaction built in |
| Resume after failure | Hand-rolled: `--from <step>` flag or re-run idempotent steps | Built in, per step, with run IDs and history |
| Approval gate | `read -p` | `manual_approval` step, approvable from another shell |
| Audit / history | Terminal scrollback | Run history, stored step outputs |
| Dependencies | `sh`, Xcode tools, `gh` (already needed) | swamp binary, swamp-club account, telemetry opt-out, extra repo files |
| Visibility to other agents/contributors | One readable script | Needs swamp installed and learned |

Notes:

- The build, `codesign`, `notarytool`, `hdiutil` and `gh release create` commands would be the same shell either way; swamp wraps them, it does not replace them.
- Notarization is the step most likely to need credentials. `xcrun notarytool store-credentials` already keeps the Apple credentials in the macOS Keychain with no secret in the repo or env, so the vault's main benefit is largely covered without swamp. This is a general Apple tooling fact (see `xcrun notarytool store-credentials --help`); it was not exercised here.

## Recommendation

Facts support swamp being technically able to do the job: shell steps, version input, vault-held secrets with redaction, and step-level resume all worked in the experiment. The question is whether the extras justify the cost for a single-developer, single-app, local release.

Recommend a plain `scripts/release.sh` (matching the existing `scripts/check.sh`, `build-app.sh` style) with the version as `$1`, a Keychain profile for notarization, and a `--from <step>` option or idempotent steps for resume. Revisit swamp only if the release flow grows into many steps or needs an approval-and-history trail across machines. Reasons: swamp adds an account requirement, telemetry, a repo footprint and a new tool to learn, while its main wins (secrets out of the repo, resume) can be had with the Keychain and a few lines of shell. If the release-flow ticket still prefers swamp, put the vault key outside the repo (test the `key_file`/`base_dir` option first), validate the version in step one, and put an explicit `dependsOn` on every step.

Open items that would need a follow-up test if swamp is chosen: relocating the vault key outside the checkout; behaviour of `resume` on a step that fails midway through a real notarization; the lack of input pattern enforcement.
