# Changelog

All notable changes are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- Storage scans more locations: DeviceSupport for watchOS, tvOS, visionOS and macOS, Xcode Previews, CoreSimulator caches and logs, and the caches of Swift Package Manager, CocoaPods, Carthage, Homebrew, npm, Yarn, pnpm, Bun, Gradle, Dart and Flutter, Cargo, pip and the Go build cache.

### Changed

- Storage shows locations as a grid of square cards, each with its own icon.
- After a scan, Storage hides folders that do not exist on this Mac.
- The delete-all confirmation lists only folders that have content.

## [2.0.0] - 2026-11-02

### Added

- A single delete guard (`DeletionGuard`). Storage deletes only run on paths strictly inside the five known Xcode folders.
- A single command runner (`ProcessCommandRunner`) with an executable allowlist (`xcrun`, `du`, `rm`, `open`).
- Simulator commands accept only a validated device UDID.
- An error state in the Simulators screen when `simctl` fails, instead of an empty list.
- Confirm dialogs for Storage deletes that list the exact paths and the total size.
- History records failed deletes and partial progress.
- Tests for the guard, the simulator service (with a fake command runner), history, and settings migration.

### Changed

- Storage is the default section on launch.
- Erasing a simulator no longer falls back to deleting it.
- Delete confirmation is always on; the "Confirm destructive actions" setting is gone.
- Build from source only (`make install`). No prebuilt downloads.
- Builds are ad-hoc signed by default; your own team can be set in `Local.xcconfig`.
- Simulator media import no longer targets a different booted simulator.

### Removed

- Licensing and premium gating. All features are free.
- Sparkle updates and the unused Firebase SDK from 1.x. XNox makes no network calls.
- The Xcode version manager.
- Signing and Devices.
- The Dashboard and toolchain doctor.
- The Simulator attached panel.
