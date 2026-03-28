#!/bin/bash

set -euo pipefail

UPSTREAM_REF=refs/remotes/upstream/main

rebase_in_progress() {
  [ -d .git/rebase-merge ] || [ -d .git/rebase-apply ]
}

resolve_known_conflicts() {
  local conflicts_file file
  local resolved_any=0

  conflicts_file=$(mktemp)
  git diff --name-only --diff-filter=U >"$conflicts_file"

  while IFS= read -r file; do
    [ -n "$file" ] || continue

    case "$file" in
      README.md)
        echo "Resolving $file in favor of upstream"
        git checkout --ours -- "$file"
        ;;
      .github/workflows/downstream.yml|\
      .github/workflows/lint.yml|\
      .github/workflows/test-generate.yml|\
      .github/workflows/test-queries.yml|\
      .github/workflows/update-parsers.yml)
        echo "Resolving $file in favor of fork maintenance"
        git checkout --theirs -- "$file"
        ;;
      *)
        rm -f "$conflicts_file"
        echo "Unexpected rebase conflict in $file" >&2
        return 1
        ;;
    esac

    git add -- "$file"
    resolved_any=1
  done <"$conflicts_file"

  rm -f "$conflicts_file"

  if [ "$resolved_any" -eq 0 ]; then
    echo "Rebase paused without any known conflicts to resolve" >&2
    return 1
  fi
}

git checkout main

if git rebase "$UPSTREAM_REF"; then
  exit 0
fi

if ! rebase_in_progress; then
  echo "git rebase failed before entering a rebase state" >&2
  exit 1
fi

while rebase_in_progress; do
  resolve_known_conflicts

  if git diff --cached --quiet; then
    git rebase --skip
    continue
  fi

  GIT_EDITOR=true git rebase --continue || true
done
