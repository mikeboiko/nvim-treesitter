#!/bin/bash

set -euo pipefail

UPSTREAM_REF=refs/remotes/upstream/main
ORIGIN_REF=refs/remotes/origin/main

MAINTAINED_PATHS=(
  .github/workflows/downstream.yml
  .github/workflows/lint.yml
  .github/workflows/rebase-patches.yml
  .github/workflows/sync-upstream.yml
  .github/workflows/test-generate.yml
  .github/workflows/test-queries.yml
  .github/workflows/update-parsers.yml
  scripts/ci-sync-upstream.sh
)

overlay_dir=$(mktemp -d)

cleanup() {
  rm -rf "$overlay_dir"
}

trap cleanup EXIT

copy_overlay_from_origin() {
  local path="$1"

  if git cat-file -e "${ORIGIN_REF}:${path}" 2>/dev/null; then
    mkdir -p "$overlay_dir/$(dirname "$path")"
    git show "${ORIGIN_REF}:${path}" >"$overlay_dir/$path"
  fi
}

restore_overlay_to_worktree() {
  local path="$1"

  if [ -f "$overlay_dir/$path" ]; then
    mkdir -p "$(dirname "$path")"
    cp "$overlay_dir/$path" "$path"
    git add -- "$path"
  fi
}

for path in "${MAINTAINED_PATHS[@]}"; do
  copy_overlay_from_origin "$path"
done

git checkout main
git reset --hard "$UPSTREAM_REF"

for path in "${MAINTAINED_PATHS[@]}"; do
  restore_overlay_to_worktree "$path"
done

if [ "$(git write-tree)" = "$(git rev-parse "${ORIGIN_REF}^{tree}")" ]; then
  echo "main already matches upstream plus fork maintenance overlay"
  git reset --hard "$ORIGIN_REF"
  exit 0
fi

git commit -m "ci: maintain fork automation"
