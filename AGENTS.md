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

`scripts/check.sh commit` (lint + tests) and `scripts/check.sh push` (+ app bundle + real-adapter smoke test) run before every commit and push. `scripts/setup-hooks.sh` wires them into git and jj for a fresh clone. To check the real adapters by hand, run `Portly --scan [--all]` or `Portly --kill <pid>` from `swift build --show-bin-path`.

### Subagent reports

Subagents that change code end with the report in `docs/agents/task-return.md`. Reviewers apply `CODING_STANDARDS.md`.
