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
# Why `.github/workflows/` always comes from `main`, whatever the target branch:
# GITHUB_TOKEN is a GitHub App token and GitHub rejects a push that creates or
# updates a workflow file with it, so upstream's CI cannot be carried over even
# when it merges cleanly; and a branch that kept its own copy of the workflows
# would go stale the moment main's are edited, leaving daily tags built by an
# old build script. `main` is the one place these files are edited.
#
# Prints `updated=true` or `updated=false` as its last line.
set -euo pipefail
cd "$(dirname "$0")/.."

branch=${1:?usage: ci-merge-upstream.sh <branch> <upstream-ref> [<base-ref>]}
ref=${2:?usage: ci-merge-upstream.sh <branch> <upstream-ref> [<base-ref>]}
base=${3:-}

git fetch --no-tags origin "+refs/heads/$branch:refs/remotes/origin/$branch" 2>/dev/null || true
git fetch --no-tags origin '+refs/heads/main:refs/remotes/origin/main' 2>/dev/null || true

exists=false
if git rev-parse -q --verify "refs/remotes/origin/$branch" > /dev/null; then
  start="refs/remotes/origin/$branch"
  exists=true
elif [ -n "$base" ] && git rev-parse -q --verify "$base" > /dev/null; then
  # First run: the branch does not exist yet, so it starts where the fork is.
  start=$base
else
  echo "::error::$branch is missing on origin and no usable base was given." >&2
  exit 1
fi

git checkout -q -B "$branch" "$start"
before=$(git rev-parse HEAD)

if git merge-base --is-ancestor "$ref" HEAD; then
  echo "$branch already contains $ref."
else
  if ! git merge --no-edit "$ref"; then
    unresolved=$(git diff --name-only --diff-filter=U)
    # A workflow file conflicts whenever upstream edits one this fork keeps at
    # main's version — the branch deliberately holds the older copy, so the
    # three-way merge cannot tell which side wins. These files are settled below
    # anyway; anything else is a real conflict and stops the run.
    if [ -n "$unresolved" ] && [ -z "$(printf '%s\n' "$unresolved" | grep -v '^\.github/workflows/')" ]; then
      echo 'Only workflow files conflict; this fork keeps its own.'
      while read -r path; do
        [ -z "$path" ] && continue
        git checkout --ours -- "$path" 2>/dev/null || git rm -q -f "$path"
        git add -- "$path"
      done <<< "$unresolved"
      git commit -q --no-edit
    else
      echo "::error::$ref conflicts with this fork outside .github/workflows/; merge it by hand:" >&2
      printf '%s\n' "$unresolved" >&2
      git merge --abort || true
      exit 1
    fi
  fi
fi

# Main's workflows win, and upstream's added ones go: `checkout <tree> -- <dir>`
# restores the files that exist there but keeps the ones it does not have.
git checkout origin/main -- .github/workflows/
for kept in $(git ls-files .github/workflows); do
  if ! git cat-file -e "origin/main:$kept" 2>/dev/null; then
    git rm -q -f "$kept"
  fi
done
if ! git diff --cached --quiet; then
  git commit -q -m "ci: this fork's workflows, from main"
fi

# A first run has to put the branch on origin even when there was nothing to
# merge; later runs only move it when a commit was made.
if [ "$exists" = true ] && [ "$(git rev-parse HEAD)" = "$before" ]; then
  echo "$branch is up to date."
  echo 'updated=false'
  exit 0
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
