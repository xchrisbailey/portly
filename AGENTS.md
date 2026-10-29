## Agent skills

### Issue tracker

Issues are tracked in GitHub Issues on `xchrisbailey/portly` via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Uses the five default triage labels (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one root `GLOSSARY.md` plus `docs/adr/`. See `docs/agents/domain.md`.

### Version control

jj, colocated with git. See `docs/agents/version-control.md`.

### Checks

`scripts/check.sh commit` and `scripts/check.sh push` run before every commit and push; the steps each mode runs are in the header of `scripts/check.sh`. `scripts/setup-hooks.sh` wires them into git and jj for a fresh clone. To check the real adapters by hand, run `Portly --scan [--all]` or `Portly --kill <pid>` from `swift build --show-bin-path`.

The shell has `noclobber`: write files with the Write tool or `>|`, and pass issue bodies with `--body-file -`, never a reused path.

### Releases

`scripts/release.sh X.Y.Z` cuts a signed, notarized release. Setup, failure recovery and the first-release checklist: `docs/agents/release.md`.

### Subagent reports

Subagents that change code end with the report in `docs/agents/task-return.md`. Reviewers apply `CODING_STANDARDS.md`.
