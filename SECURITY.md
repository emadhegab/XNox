# Security Policy

## Supported versions

Only the latest `main` is supported.

## Reporting a vulnerability

Please do not open a public issue. Use GitHub's private reporting instead: open the repository's **Security** tab and choose **Report a vulnerability**.

Include the XNox version or commit, your macOS version, and steps to reproduce.

## What is in scope

XNox deletes files and runs commands, so these matter most:

- Anything that makes XNox delete a path outside the allowed folders. The allowed folders are the five Storage locations under `~/Library`. The check is `DeletionGuard` in `XNox/Core/Safety`.
- Anything that makes XNox run a command that is not allowed. Only `xcrun`, `du`, `rm` and `open` may run, enforced by `ProcessCommandRunner` in `XNox/Core/CommandRunner`.
- Any way to pass an unvalidated device ID to `xcrun simctl`.
- Any network access. XNox should make none.

## App Sandbox is off

The App Sandbox is off on purpose. XNox must read and delete files under `~/Library/Developer` and run `xcrun simctl`, and the sandbox blocks both. The delete guard and the command allowlist are the safety limits instead.
