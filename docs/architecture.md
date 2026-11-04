# Architecture

XNox is a SwiftUI app (macOS 14+) with no third-party packages and no network code. Each feature has a view and a view model. Anything that runs a command or deletes a file goes through `Core`.

## Layout

```
XNox/
  App/                     XNoxApp, AppRootView, SidebarView, AppSection, AppState
  Core/
    CommandRunner/         CommandRunning, ProcessCommandRunner (the only Process())
    Safety/                DeletionGuard
    Persistence/           AppSettings, OperationHistoryStore, OperationHistoryRecorder
    DesignSystem/          theme and card style
  Features/
    Storage/               StorageViewModel, StorageLocationBrowserViewModel, StorageShell
    Simulator/             SimulatorViewModel, SimulatorControlService, SimctlParser, models
    OperationsHistory/     history list and view model
    Settings/              settings screen
  Shared/                  small reusable views and models
XNoxTests/                 unit tests
XNoxUITests/               UI tests
```

## Data flow

```
View --> ViewModel --> StorageShell / SimulatorControlService
                              |
                              v
                       CommandRunning (ProcessCommandRunner)
                              |
                              v
                  /usr/bin/du, /bin/rm, /usr/bin/xcrun, /usr/bin/open
```

View models are `@MainActor` `ObservableObject`s. After a destructive action they write an entry through `OperationHistoryRecorder`, and the History screen reads it back.

## Delete path

```
StorageViewModel / StorageLocationBrowserViewModel
  -> StorageShell.removeItem(at:guard:)
  -> DeletionGuard.validate(url)          throws if not allowed
  -> ProcessCommandRunner.run("/bin/rm", ["-rf", "--", resolvedPath])
```

`DeletionGuard` allows a path only if, after collapsing `..` and resolving symlinks in its parent directories, it is strictly inside one of the Storage roots under the home folder. `StorageViewModel.defaultLocations` lists the roots.

A root must hold only data the tool can create again. Folders like `~/.m2/repository` (locally installed artifacts) and `~/.android/avd` (user emulators) are left out for this reason. `~/go/pkg/mod` is left out because its read-only folders make `rm -rf` fail. For `~/.npm`, `~/.pub-cache` and `~/.gradle`, the root is only the cache subfolder.

A root itself is refused. The last path component is not resolved, so deleting a symlink removes the link, not its target. The check and the `rm` are separate steps, so a same-user process could swap a directory for a symlink in between; this is accepted.

## Command allowlist

`ProcessCommandRunner` runs only `/usr/bin/xcrun`, `/usr/bin/du`, `/bin/rm` and `/usr/bin/open`. Anything else throws `CommandError.notAllowed`. `/bin/rm` is meant to be called only from `StorageShell.removeItem`. Output goes to temporary files, and a timeout terminates the child.

## Simulators

`SimulatorControlService` is an actor that runs `xcrun simctl` and reads CoreSimulator state off the main thread. Every command that targets a device calls `validateUDID` first, which rejects anything that is not a UUID. There are no `booted` or `all` specifiers, and erase never falls back to delete. `SimctlParser` turns `simctl` output into models. If `simctl` fails and no simulators load, `SimulatorViewModel.loadError` is set and the screen shows an error.

## Persistence

- Settings use `UserDefaults` keys with the `settings.` prefix (see `AppSettingsKeys`).
- Simulator form values (locale, URL, status bar) use `simulator.` keys (see `SimulatorPreferences`).
- History is a JSON file at `~/Library/Application Support/XNox/operation-history.json`. Entries older than the retention setting (default 30 days) are pruned on load and save.

## Testing

- Delete tests build a tree in `FileManager.default.temporaryDirectory` and never touch real folders (`DeletionGuardTests`, `StorageDeleteHistoryTests`).
- Simulator tests inject `FakeCommandRunner` (a `CommandRunning` fake) and a temporary devices directory. They never run real `simctl`.
- Settings and history tests use a throwaway `UserDefaults` suite or a temporary file.
- Run everything with `make test`.
