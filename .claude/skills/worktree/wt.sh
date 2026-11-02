#!/bin/sh
# Agent worktrees: one branch per task (feature/<name> or fix/<name>), checked out under .claude/worktrees/<branch>.
# Usage: wt.sh new <branch> [base] | pr <branch> [title] | rm <branch> | ls | try <branch|main>
set -eu
root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
cd "$root"

case "${1:-}" in
new)
  br=${2:?branch required}; base=${3:-main}; dir=.claude/worktrees/$br
  case "$br" in feature/?*|fix/?*) ;; *) echo "branch must start with feature/ or fix/" >&2; exit 1 ;; esac
  git worktree add -b "$br" "$dir" "$base"
  git config "branch.$br.wt-base" "$base"   # PR target, read by `pr`
  # Gitignored local files (team ID, vault path). Symlinked, not copied.
  for f in Local.xcconfig CLAUDE.local.md; do [ -e "$f" ] && ln -s "$root/$f" "$dir/$f"; done
  echo "$root/$dir"
  ;;
pr)
  # Push <branch> and open a PR into its base. Prints the PR URL.
  br=${2:?branch required}; dir=.claude/worktrees/$br
  base=$(git config "branch.$br.wt-base" || echo main)
  git -C "$dir" push -u origin "$br"
  gh pr view "$br" --json url -q .url 2>/dev/null ||
    (cd "$dir" && gh pr create --base "$base" --head "$br" --title "${3:-$br}" \
      --body "$(git log --format='- %s' "$base..HEAD"; printf '\n🤖 Generated with [Claude Code](https://claude.com/claude-code)')")
  ;;
rm)
  br=${2:?branch required}
  git worktree remove ".claude/worktrees/$br"   # refuses if the worktree has uncommitted changes
  git branch -d "$br" 2>/dev/null || echo "branch $br kept (not merged into current branch)"
  ;;
try)
  # Put the MAIN checkout on a branch's latest commit (detached) so the open Xcode project builds it.
  # `try main` goes back. Uncommitted edits carry over; git refuses if they conflict.
  br=${2:?branch or main required}
  if [ "$br" = main ]; then git switch main; else git switch --detach "$br"; fi
  ;;
ls) git worktree list ;;
*) echo "usage: $0 new <branch> [base] | pr <branch> [title] | rm <branch> | ls | try <branch|main>" >&2; exit 1 ;;
esac
