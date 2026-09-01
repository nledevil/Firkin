# Firkin

A native macOS app for managing your Homebrew packages.

A *firkin* is a small cask of ale. Firkin looks after your casks — and your formulae, and eventually your taps.

> **Status: early development.** The scaffold works — it lists everything Homebrew has installed, shows what's outdated, and can upgrade, pin, and uninstall packages with live command output — but it is far from complete.

## Features

- Browse installed formulae and casks in a native SwiftUI interface
- Filter by kind, see what's outdated, search by name or description
- Search all of Homebrew from the Browse section and install new formulae and casks with one click
- Applications view: every app on your Mac — /Applications, /System/Applications, ~/Applications, one level of subfolders like Utilities, and Safari's cryptex location — with its architecture (Apple Silicon, Universal, or Intel-under-Rosetta — including whether a running app is actually being translated), update tracking via matching Homebrew casks, and one-click adoption of manually-installed apps into Homebrew (`brew install --cask --adopt`)
- Uninstall any application: brew-managed apps through `brew uninstall`, everything else moved to the Trash (reversible) — with an administrator-privileges fallback for protected apps, using the system's own authorization dialog (Firkin never sees the password)
- Upgrade, pin/unpin, and uninstall packages, watching the real `brew` output as it runs
- Automatic app updates via [Sparkle](https://sparkle-project.org) — permission-based, EdDSA-signed, fed from this repo's releases
- No Electron, no web views — SwiftUI talking to your own `brew`

Planned: tap management, `brew services`, greedy cask upgrades, signed releases.

## Install

Download the latest `Firkin-x.y.z.dmg` from [Releases](https://github.com/nledevil/Firkin/releases), open it, and drag **Firkin** to **Applications**. Builds are universal (Apple Silicon + Intel).

Releases aren't notarized yet ([#1](https://github.com/nledevil/Firkin/issues/1)), so on first launch macOS will warn that it can't verify the app. Open **System Settings → Privacy & Security** and click **Open Anyway**, or clear the quarantine flag:

```bash
xattr -d com.apple.quarantine /Applications/Firkin.app
```

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

The app icon is drawn entirely in code: `Scripts/generate_icon.swift` renders the ale cask with AppKit at every required size and assembles `Icon.icns`. The packaging script runs it automatically when the icon is missing, so there are no binary image assets in the repo.

## Project layout

```
Sources/FirkinKit/   Homebrew data layer: models, brew JSON decoding, process execution (no UI)
Sources/Firkin/      SwiftUI app: views, observable store
Tests/FirkinKitTests Unit tests for the data layer, based on real `brew info --json=v2` output
Scripts/             Build, package, and run scripts (no Xcode required)
```

Firkin shells out to your existing `brew` binary and parses its `--json=v2` output. The package features never talk to the network directly — everything goes through Homebrew. The one exception is Sparkle's update check, which asks for permission first and only contacts this repository's appcast and release downloads.

Because it drives `brew`, Firkin runs unsandboxed and is distributed outside the Mac App Store.

## License

[MIT](LICENSE)
