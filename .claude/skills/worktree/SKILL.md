---
name: worktree
description: Create, list, and remove per-task git worktrees for subagents (branch under `.claude/worktrees/<branch>`), open one GitHub PR per worktree, and let the user try a branch in the main checkout. Use before dispatching the-developer (or any code-writing agent), and when cleaning up after a PR is merged.
---

# Agent worktrees

Every code-writing agent task gets its own worktree, branch, and PR. The user's main checkout is never touched by agents.

- Branch: `feature/<name>` or `fix/<name>` (the script rejects anything else). Folder: `.claude/worktrees/<branch>` (gitignored).
- Script: `.claude/skills/worktree/wt.sh`
- One roadmap phase = one worktree = one PR. Phases run in order, not in parallel: each removal phase changes `project.pbxproj`, and parallel edits to it conflict.

## Create

```sh
.claude/skills/worktree/wt.sh new <branch>        # from main, PR targets main
.claude/skills/worktree/wt.sh new <branch> <base> # stacked on <base>, PR targets <base>
```

Prints the absolute worktree path. Pass it to the agent as `WORKTREE=<path>`. Gitignored `Local.xcconfig` (team ID) and `CLAUDE.local.md` (vault path) are symlinked in if present.

## Rules for agents in a worktree

- Start every Bash command with `cd "$WORKTREE" && ...`. Use absolute paths under `$WORKTREE` for Read/Edit/Write.
- Commit as you go, Conventional Commits. `git add -A` is fine.
- Never `checkout`, `rebase`, `merge`, or `git push`. The only push is `wt.sh pr`.
- Build/test with `xcodebuild ... -derivedDataPath "$WORKTREE/DerivedData"`. `mcp__xcode` acts on the main checkout.

## Open the PR (the-developer, when done)

No `origin` remote (until Phase 9): skip this step. The user merges the branch locally: `git merge --squash <branch>`.

```sh
.claude/skills/worktree/wt.sh pr <branch> "<Conventional Commit style title>"
```

## Review

Dispatch `the-reviewer` with `WORKTREE`, branch, and PR number. It posts one `COMMENT` review (GitHub blocks approving your own PR). The user merges.

## User testing in the main checkout

```sh
.claude/skills/worktree/wt.sh try <branch>   # main checkout jumps to the branch (detached)
.claude/skills/worktree/wt.sh try main       # back
```

## Remove (after merge, or when abandoned)

```sh
.claude/skills/worktree/wt.sh rm <branch>
.claude/skills/worktree/wt.sh ls
```

Confirm with the user before removing a worktree whose branch is not merged.
