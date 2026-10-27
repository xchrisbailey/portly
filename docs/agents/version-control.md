# Version control: jj

This repo uses [jj](https://jj-vcs.github.io/jj/) colocated with git. Use `jj` for all version-control operations. Don't run mutating `git` commands (`commit`, `checkout`, `rebase`, `reset`, `stash`, `branch`); they fight jj's view of the repo. Read-only `git` commands work but prefer the jj equivalent.

Skills written for git (`code-review`, `pr`, `no-mistakes`, `git-guardrails-claude-code`, etc.) still apply. Follow their rules and translate the commands with the table below.

## Model

- The working copy is a commit (`@`). Edits are snapshotted into it automatically; there is no staging area.
- Bookmarks are jj's branches. They don't move when you make new commits; set them explicitly before pushing.
- Trunk is the `main` bookmark, revset `trunk()`.
- Commits whose description starts with `wip:` or `private:` are never pushed (`git.private-commits`).

## Git to jj

| Git | jj |
| --- | --- |
| `git status` | `jj st` |
| `git log` | `jj log` (stack since trunk: `jj log -r 'trunk()..@'`) |
| `git diff` (uncommitted) | `jj diff` |
| `git diff <base>...HEAD` | `jj diff --from 'fork_point(<base> \| @)' --to @` |
| `git diff --stat` | `jj diff --stat` |
| `git show <rev>` | `jj show <rev>` |
| `git add` + `git commit -m "msg"` | `jj commit -m "msg"` (describes `@` and starts a new empty `@`) |
| Commit only some files | `jj commit -m "msg" <paths>` |
| `git commit --amend` | edit files in place (`@` updates itself), or `jj squash` to fold `@` into its parent |
| `git checkout -b feat` | `jj new trunk()` then `jj bookmark create feat -r @` |
| `git checkout <rev>` | `jj new <rev>` (or `jj edit <rev>` to modify it in place) |
| `git fetch` | `jj git fetch` |
| `git pull --rebase` | `jj git fetch && jj rebase -d main` |
| `git rebase main` | `jj rebase -d main` |
| `git push` | `jj bookmark set <name> -r @-` then `jj git push -b <name>` (works for new bookmarks too) |
| `git stash` | not needed: `jj new` leaves the current work in its own commit |
| `git reset --hard` / undo | `jj undo`, or `jj op log` + `jj op restore <op>` |
| `git merge-base A B` | revset `fork_point(A \| B)` |
| `git blame` | `jj file annotate <path>` |

"Since a fixed point" in a skill maps to a revset: since a branch is `<bookmark>..@`, since a commit is `<rev>..@`, since trunk is `trunk()..@`.

## Agent rules

- **Never open an editor.** Always pass `-m` to `jj commit`, `jj describe`, `jj new`, and `jj squash`. Avoid interactive forms: `jj split` without paths, `jj squash -i`, `jj resolve`, `jj diffedit`.
- After `jj commit`, the finished commit is `@-` and `@` is empty. Point bookmarks at `@-` before pushing, not at the empty `@`.
- Check `jj st` before committing; it lists exactly what the snapshot contains.
- Conflicts don't stop jj; they're recorded in the commit. Check `jj log` for conflict markers after a rebase and resolve by editing the files.
- `jj undo` reverses the last operation. Prefer it over hand-repairing history.
- jj auto-tracks every new file. If `jj st` lists build output (`.build/`, `build/`), the working copy is missing `.gitignore`: run `jj file untrack .build build` before committing.
- A workspace goes **stale** when its commit is rewritten from another workspace (a rebase or merge done elsewhere). Run `jj workspace update-stale` in it before building or testing there.
- jj runs no git hooks. Checks run through `scripts/check.sh`; see `AGENTS.md`.
- Commit or push only when the user asks, same as with git.

## Pull requests

Push a bookmark, then open the PR with `gh`:

```sh
jj bookmark create <name> -r @-
jj git push -b <name>
gh pr create --head <name> --base main --title "..." --body "..."
```

Don't pass `--allow-new`: jj 0.46 removed it, and the user's config (`remotes.origin.auto-track-bookmarks = "glob:*"`) already tracks new bookmarks on push.

To update a PR, amend the commits (edit in place or `jj squash`), then `jj git push -b <name>`. jj force-pushes rewritten bookmarks safely.
