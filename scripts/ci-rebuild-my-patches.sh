#!/bin/bash

set -euo pipefail

MAIN_REF=refs/remotes/origin/main
PATCH_REF=refs/remotes/origin/my-patches
BASE_REF=refs/remotes/origin/my-patches-base
PATCH_BRANCH=my-patches
BASE_BRANCH=my-patches-base

git show-ref --verify --quiet "$MAIN_REF"
git show-ref --verify --quiet "$PATCH_REF"

if ! git show-ref --verify --quiet "$BASE_REF"; then
  echo "missing $BASE_REF; initialize $BASE_BRANCH to the current main before rebuilding patches" >&2
  exit 1
fi

mapfile -t patch_commits < <(git rev-list --reverse --no-merges "^${BASE_REF}" "${PATCH_REF}")

git checkout -B "$PATCH_BRANCH" "$MAIN_REF"

if [ "${#patch_commits[@]}" -gt 0 ]; then
  git cherry-pick "${patch_commits[@]}"
fi

git branch -f "$BASE_BRANCH" "$MAIN_REF"
