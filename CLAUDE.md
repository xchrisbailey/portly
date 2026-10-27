@AGENTS.md

## Orchestration

The main session runs `opusplan`: Opus while in plan mode, Sonnet for execution. Delegate to the subagents in `.claude/agents/` by cost:

| Task | Agent | Model |
| --- | --- | --- |
| Find files, symbols, call sites; "where is X" | `scout` | haiku |
| Run tests, builds, lint; summarize output | `runner` | haiku |
| Implement a clear spec, fix a bug with a known cause, write tests | `implementer` | sonnet |
| Design decisions, unclear requirements, hard bugs, risky reviews | `architect` | opus |

Escalate to `architect` only after a cheaper agent failed or the task needs judgment. Route long command output (`scripts/check.sh`, builds) through `runner`.
