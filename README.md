# Firkin

A native macOS app for managing your Homebrew packages.

A *firkin* is a small cask of ale. Firkin looks after your casks — and your formulae, and eventually your taps.

> **Status: early development.** The scaffold works — it lists everything Homebrew has installed, shows what's outdated, and can upgrade, pin, and uninstall packages with live command output — but it is far from complete.

## Features

- Browse installed formulae and casks in a native SwiftUI interface
- Filter by kind, see what's outdated, search by name or description
- Upgrade, pin/unpin, and uninstall packages, watching the real `brew` output as it runs
- No Electron, no web views — SwiftUI talking to your own `brew`

Planned: package discovery and install, tap management, `brew services`, adopting already-installed apps as casks, app icon, signed releases.

## Requirements

- macOS 14 (Sonoma) or later
- [Homebrew](https://brew.sh) (Apple Silicon or Intel install locations are both detected)

## Building

There is no Xcode project, and none is needed — the Xcode Command Line Tools are enough:

```bash
swift build                  # compile
Scripts/test.sh              # run FirkinKit unit tests
Scripts/compile_and_run.sh   # package Firkin.app and launch it
```

`Scripts/test.sh` is a thin wrapper over `swift test`: with full Xcode it just runs it, and on machines with only the Command Line Tools it adds the search paths for `Testing.framework`, which CLT ships in a non-default location.

`Scripts/package_app.sh` builds a release binary, assembles `Firkin.app` with a generated Info.plist, and ad-hoc signs it. Versioning lives in `version.env`.

## Project layout

```
Sources/FirkinKit/   Homebrew data layer: models, brew JSON decoding, process execution (no UI)
Sources/Firkin/      SwiftUI app: views, observable store
Tests/FirkinKitTests Unit tests for the data layer, based on real `brew info --json=v2` output
Scripts/             Build, package, and run scripts (no Xcode required)
```

Firkin shells out to your existing `brew` binary and parses its `--json=v2` output. It never talks to the network itself; everything goes through Homebrew.

Because it drives `brew`, Firkin runs unsandboxed and is distributed outside the Mac App Store.

## License

[MIT](LICENSE)
