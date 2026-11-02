## What and why

## Checks

- [ ] `make test` passed locally (there is no CI)
- [ ] Every delete goes through `DeletionGuard` / `StorageShell.removeItem(at:guard:)`
- [ ] No network code and no new packages
- [ ] Tests use temp directories and `FakeCommandRunner`, not real user data
