# XNox

XNox is a macOS app that cleans up Xcode junk: DerivedData, caches, old simulators and similar. It is built with SwiftUI.

The App Sandbox is OFF on purpose. XNox must read and delete files under `~/Library/Developer` and run `xcrun simctl`. The sandbox blocks both.

## Commands

- `make build`: Release build into `./build`.
- `make run`: build and open the app.
- `make install`: build and copy to `/Applications`.
- `make test`: run the unit and UI tests.
- `make clean`: remove `./build`.
- One test class: `xcodebuild -project XNox.xcodeproj -scheme XNox -destination 'platform=macOS' -only-testing:XNoxTests/<Class> test`

## Source of truth

Decisions, roadmap and ADRs live in the maintainer's private notes. Their location is set in `CLAUDE.local.md` (git-ignored). If that file is missing, work from the code and ask.

## Rules

- Every delete goes through the single allowlist guard.
- No network code. No `URLSession`.
- Add a protocol only when a test needs a fake.
- Tests never touch real user data. Use temp directories and a fake command executor.
- No third-party packages after Phase 4.

## Workflow

- One git worktree per task (see `.claude/skills/worktree/SKILL.md`).
- Branch names start with `feature/` or `fix/`. Base is `main`.
- Use Conventional Commits.

## Signing

The default build is ad-hoc signed. No Apple account is needed.
To sign with your own team, copy `Local.xcconfig.example` to `Local.xcconfig` and edit it. That file is git-ignored. It applies to Xcode and plain `xcodebuild`; `make` always builds ad-hoc.
