# Task return format

Every subagent that changes code ends with this report. The lead merges from it without re-reading the work, so a missing field means the lead has to inspect the workspace by hand.

```text
Bookmark: <name> -> <commit id>        (or "none: no changes")
Commits:  <id> <first line>, one per line
Checks:   scripts/check.sh <commit|push>: passed | failed (<first failing step>)
Interface changes: <public signatures added/changed in PortlyCore>, or "none"
Deviations: <anything that differs from the ticket or brief, with why>, or "none"
Not verified: <what you could not check, e.g. the panel UI>, or "none"
```

- **Checks** reports a run of `scripts/check.sh` from the workspace, not individual commands.
- **Not verified** is where untested claims go. Anything not listed there is a claim that it was checked.
- Keep it under 15 lines. Put detail in commit messages.
