#!/bin/sh
# Wire scripts/check.sh into git and jj for this clone. Safe to re-run.
# jj runs no hooks, so repo-level aliases stand in: they override the
# user's global `cma` (commit -m) and `pl` (push) aliases in this repo only.
set -eu
cd "$(dirname "$0")/.."

git config core.hooksPath .githooks

jj config set --repo aliases.cma \
    '["util", "exec", "--", "sh", "-c", "\"$(jj root)\"/scripts/check.sh commit && jj commit -m \"$1\"", "--"]'
jj config set --repo aliases.pl \
    '["util", "exec", "--", "sh", "-c", "\"$(jj root)\"/scripts/check.sh push && jj git push \"$@\"", "--"]'
jj config set --repo aliases.check \
    '["util", "exec", "--", "sh", "-c", "\"$(jj root)\"/scripts/check.sh \"${1:-push}\"", "--"]'

echo "hooks: git core.hooksPath=.githooks; jj aliases cma, pl, check (repo-level)"
