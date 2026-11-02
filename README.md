# XNox

A free, open-source macOS app for iOS developers. It finds the disk space Xcode wastes, cleans it safely, and manages your iOS simulators.

> **Status:** being rebuilt as open source. Some old paid features (Xcode manager, signing, device registration) are still in the code and are being removed. See the roadmap in the project notes.

## Features

- **Storage** — scans the folders Xcode fills up, shows their size, and lets you browse and delete what you pick:
  - `~/Library/Developer/Xcode/DerivedData`
  - `~/Library/Developer/Xcode/Archives`
  - `~/Library/Developer/CoreSimulator/Devices`
  - `~/Library/Developer/Xcode/iOS DeviceSupport`
  - `~/Library/Caches/com.apple.dt.Xcode`
- **Simulators** — create, boot, erase, rename, and delete simulators; set locale and status bar; open deep links; add photos and videos.
- **History** — a log of every delete and erase you ran, with the space freed.

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 16 or later, installed in `/Applications`

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
| `make test` | Run the unit tests |
| `make clean` | Delete `./build` |

To update, pull and install again:

```sh
git pull && make install
```

To uninstall, delete `/Applications/XNox.app`.

## Why the app is not sandboxed

XNox needs to read and delete files under `~/Library/Developer` and to run `xcrun simctl`. The macOS App Sandbox blocks both, so it is turned off. XNox only deletes items inside the folders listed above, and only after you confirm.

## Privacy

XNox makes no network calls after the rebuild is finished. No analytics, no accounts, no license checks.

## Contributing

Open `XNox.xcodeproj` in Xcode, or use `make build` / `make test`. To sign with your own team, copy `Local.xcconfig.example` to `Local.xcconfig`. Pull requests are welcome; use [Conventional Commits](https://www.conventionalcommits.org) for commit messages.

## License

[MIT](LICENSE)
