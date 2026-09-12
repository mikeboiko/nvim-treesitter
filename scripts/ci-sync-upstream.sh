#!/bin/bash

set -euo pipefail

UPSTREAM_REF=refs/remotes/upstream/main
ORIGIN_REF=refs/remotes/origin/main

MAINTAINED_DIRECTORIES=(
  .github/workflows
)

MAINTAINED_PATHS=(
  scripts/ci-sync-upstream.sh
  scripts/ci-rebuild-my-patches.sh
)

overlay_dir=$(mktemp -d)

cleanup() {
  rm -rf "$overlay_dir"
}

trap cleanup EXIT

copy_overlay_directory_from_origin() {
  local path="$1"

  if git cat-file -e "${ORIGIN_REF}:${path}" 2>/dev/null; then
    mkdir -p "$overlay_dir"
    git archive "${ORIGIN_REF}" "$path" | tar -x -C "$overlay_dir"
  fi
}

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

restore_overlay_directory_to_worktree() {
  local path="$1"

  if [ -d "$overlay_dir/$path" ]; then
    rm -rf "$path"
    mkdir -p "$(dirname "$path")"
    cp -R "$overlay_dir/$path" "$path"
    git add --all -- "$path"
  fi
}

assert_no_unmanaged_workflow_changes() {
  mapfile -t workflow_changes < <(git diff --name-only "${ORIGIN_REF}" -- .github/workflows)

  if [ "${#workflow_changes[@]}" -gt 0 ]; then
    printf 'sync would update workflow files without an explicit overlay:\n' >&2
    printf '  %s\n' "${workflow_changes[@]}" >&2
    printf 'add them to MAINTAINED_PATHS or push with a token that has workflows permission\n' >&2
    exit 1
  fi
}

for path in "${MAINTAINED_DIRECTORIES[@]}"; do
  copy_overlay_directory_from_origin "$path"
done

for path in "${MAINTAINED_PATHS[@]}"; do
  copy_overlay_from_origin "$path"
done

git checkout main
git reset --hard "$UPSTREAM_REF"

for path in "${MAINTAINED_DIRECTORIES[@]}"; do
  restore_overlay_directory_to_worktree "$path"
done

for path in "${MAINTAINED_PATHS[@]}"; do
  restore_overlay_to_worktree "$path"
done

assert_no_unmanaged_workflow_changes

if [ "$(git write-tree)" = "$(git rev-parse "${ORIGIN_REF}^{tree}")" ]; then
  echo "main already matches upstream plus fork maintenance overlay"
  git reset --hard "$ORIGIN_REF"
  exit 0
fi

git commit -m "ci: maintain fork automation"
