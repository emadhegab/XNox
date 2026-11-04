# XNox

A free, open-source macOS app for iOS developers and developers in general. It finds the disk space Xcode and developer tools waste, cleans it safely, and manages your iOS simulators.

## Features

- **Storage** — scans the folders developer tools fill up, shows their size, and lets you browse and delete what you pick:
  - Xcode: `DerivedData`, `Archives`, DeviceSupport for each platform, `UserData/Previews`, `~/Library/Caches/com.apple.dt.Xcode`
  - Simulators: `CoreSimulator/Devices`, `CoreSimulator/Caches`, `~/Library/Logs/CoreSimulator`
  - Package caches: Swift Package Manager, CocoaPods, Carthage, Homebrew, npm, Yarn, pnpm, Bun, Gradle, Dart and Flutter, Cargo, pip, Go build
- **Simulators** — create, boot, erase, rename, and delete simulators; set locale and status bar; open deep links; add photos and videos.
- **History** — a log of every delete and erase you ran, with the space freed.

## Screenshot

![XNox Storage screen](docs/screenshot.png)

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 26 or later, installed in `/Applications`

## Install (build from source)

```sh
git clone https://github.com/emadhegab/XNox.git
cd XNox
make install
```

This builds the app and copies `XNox.app` to `/Applications`. No Apple Developer account is needed: the build is ad-hoc signed on your machine, so macOS opens it without a Gatekeeper warning.

Other commands:

| Command | What it does |
|---|---|
| `make build` | Build the Release app into `./build` |
| `make run` | Build and open the app without installing |
| `make test` | Run the unit and UI tests |
| `make clean` | Delete `./build` |

To update, pull and install again:

```sh
git pull && make install
```

To uninstall, delete `/Applications/XNox.app`.

## Why the app is not sandboxed

XNox needs to read and delete files under `~/Library/Developer` and to run `xcrun simctl`. The macOS App Sandbox blocks both, so it is turned off. XNox only deletes items inside the folders listed above, and only after you confirm.

## Privacy

XNox makes no network calls. No analytics, no accounts, no license checks.

## Documentation

- [Architecture](docs/architecture.md)
- [Changelog](CHANGELOG.md)
- [Security policy](SECURITY.md)

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) and the [Code of Conduct](CODE_OF_CONDUCT.md). In short: run `make test` before a pull request, and use [Conventional Commits](https://www.conventionalcommits.org).

## License

[MIT](LICENSE)
