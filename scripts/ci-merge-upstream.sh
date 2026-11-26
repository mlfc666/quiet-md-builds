#!/usr/bin/env bash
# Merge an upstream ref into a branch of this fork and push it.
#
#   scripts/ci-merge-upstream.sh <branch> <upstream-ref> [<base-ref>]
#
# sync-upstream calls it twice per run: upstream main into `upstream-main`, and
# each upstream release tag into `main`. Nothing else merges.
#
# Why a merge rather than replaying the fork's patch onto upstream (the way
# patch-based forks do): this fork only *adds* files, so the two change sets are
# disjoint and cannot conflict. A future change that does touch upstream code
# surfaces as a conflict instead of a silently dropped patch.
#
# Why this fork's `.github/workflows/` always wins: GITHUB_TOKEN is a GitHub App
# token and GitHub rejects a push that creates or updates a workflow file with
# it, so an upstream CI change cannot be carried over even when it merges
# cleanly. `checkout <tree> -- <dir>` restores the files that existed but keeps
# the ones upstream just added, hence the second loop.
#
# Prints `updated=true` or `updated=false` as its last line.
set -euo pipefail
cd "$(dirname "$0")/.."

branch=${1:?usage: ci-merge-upstream.sh <branch> <upstream-ref> [<base-ref>]}
ref=${2:?usage: ci-merge-upstream.sh <branch> <upstream-ref> [<base-ref>]}
base=${3:-}

git fetch --no-tags origin "+refs/heads/$branch:refs/remotes/origin/$branch" 2>/dev/null || true

if git rev-parse -q --verify "refs/remotes/origin/$branch" > /dev/null; then
  start="refs/remotes/origin/$branch"
elif [ -n "$base" ] && git rev-parse -q --verify "$base" > /dev/null; then
  # First run: the branch does not exist yet, so it starts where the fork is.
  start=$base
else
  echo "::error::$branch is missing on origin and no usable base was given." >&2
  exit 1
fi

git checkout -q -B "$branch" "$start"

if git merge-base --is-ancestor "$ref" HEAD; then
  echo "$branch already contains $ref."
  echo 'updated=false'
  exit 0
fi

before=$(git rev-parse HEAD)
if ! git merge --no-edit "$ref"; then
  echo "::error::$ref conflicts with this fork; merge it by hand." >&2
  git merge --abort || true
  exit 1
fi

git checkout "$before" -- .github/workflows/
for added in $(git diff --name-only --diff-filter=A "$before" HEAD -- .github/workflows/); do
  git rm -q -f "$added"
done
if ! git diff --cached --quiet; then
  git commit -q -m "ci: keep this fork's workflows (upstream CI is not used here)"
fi

# The branch only moves under this script, but a human push could still land
# between the fetch and this push; retry on the rarer race.
for attempt in 1 2 3; do
  if git push origin "HEAD:refs/heads/$branch"; then
    echo 'updated=true'
    exit 0
  fi
  if [ "$attempt" = 3 ]; then
    echo "::error::push to $branch was rejected three times." >&2
    exit 1
  fi
  sleep 10
  git fetch --no-tags origin "+refs/heads/$branch:refs/remotes/origin/$branch"
  git merge --no-edit "refs/remotes/origin/$branch" || {
    echo "::error::$branch moved and now conflicts with the merge." >&2
    exit 1
  }
done
