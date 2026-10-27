@AGENTS.md

## Orchestration

The main session runs `opusplan`: Opus while in plan mode, Sonnet for execution. Delegate to the subagents in `.claude/agents/` by cost:

| Task | Agent | Model |
| --- | --- | --- |
| Find files, symbols, call sites; "where is X" | `scout` | haiku |
| Run tests, builds, lint; summarize output | `runner` | haiku |
| Implement a clear spec, fix a bug with a known cause, write tests | `implementer` | sonnet |
| Design decisions, unclear requirements, hard bugs, risky reviews | `architect` | opus |

Rules for keeping token spend down:

- Do small things inline. A handful of tool calls or a known file doesn't need a subagent.
- Use the cheapest agent that can do the job. Escalate to `architect` only when a cheaper attempt failed or the task clearly needs judgment.
- Send command output that's likely to be long (test suites, builds) through `runner` so it stays out of the main context.
- Give each subagent a narrow brief with file paths and what's already ruled out; it knows nothing else.
- Run independent subagents in parallel in one message instead of one after another.
