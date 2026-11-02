# Contributing to XNox

Thanks for helping. XNox deletes files and erases simulators, so changes are reviewed with care.

## Build and test

You need macOS 14+ and Xcode 16+. No Apple Developer account is needed.

```sh
git clone https://github.com/emadhegab/XNox.git
cd XNox
make build   # Release build into ./build
make run     # build and open the app
make test    # unit and UI tests
```

To sign with your own team, copy `Local.xcconfig.example` to `Local.xcconfig` and edit it (git-ignored). `make` always builds ad-hoc signed.

There is no CI. Run `make test` yourself before you open a pull request.

## Rules

- **Every delete goes through the guard.** Storage deletes call `StorageShell.removeItem(at:guard:)`, which calls `DeletionGuard.validate`. Do not call `/bin/rm` or `FileManager.removeItem` on user data any other way.
- **No network code.** No `URLSession`, analytics, or update checks.
- **No third-party packages.**
- **Add a protocol only when a test needs a fake.**
- **Tests never touch real user data.** Use temporary directories for files and `FakeCommandRunner` for commands. Never run real `simctl erase` or `delete` in a test.
- Simulator commands must use a validated UDID (`SimulatorControlService.validateUDID`).

See [docs/architecture.md](docs/architecture.md) for how the code is laid out.

## Pull requests

- Branch from `main`. Name branches `feature/...` or `fix/...`.
- Use [Conventional Commits](https://www.conventionalcommits.org) (`feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`).
- Keep a PR to one change. Add or update tests for new logic.
- Open the PR against `main` and fill in the template.

Be kind: see the [Code of Conduct](CODE_OF_CONDUCT.md). For security problems, see [SECURITY.md](SECURITY.md) instead of opening an issue.
