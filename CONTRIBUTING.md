# Contributing to Sunset Browser

Thanks for helping build an open, native home for people who love Arc. Every contribution counts: a clear bug report, a translation, a design tweak or a pull request.

## Ways to help

- **Report bugs** with the [bug report form](https://github.com/CarlosVP120/sunset-browser/issues/new?template=bug_report.yml). Include your macOS version and steps to reproduce.
- **Suggest features** with the [feature request form](https://github.com/CarlosVP120/sunset-browser/issues/new?template=feature_request.yml). If it's something Arc did, tell us how it worked there.
- **Translate.** English localization is the top roadmap item, and every other language is welcome after that.
- **Pick up an issue** labeled [`good first issue`](https://github.com/CarlosVP120/sunset-browser/labels/good%20first%20issue) or [`help wanted`](https://github.com/CarlosVP120/sunset-browser/labels/help%20wanted). Comment on it first so nobody duplicates work.

For bigger changes (a new feature, a new module, a change to how data is stored), please open an issue or a discussion before writing code, so we can agree on the approach.

## Development setup

Requirements:

- macOS 14 or later (macOS 15.4+ to try web extensions)
- Xcode 26 or later, with its command line tools selected (`xcode-select -p`)

```bash
git clone https://github.com/CarlosVP120/sunset-browser.git
cd sunset-browser
swift build                     # compile
swift test                      # run the tests
./scripts/bundle.sh             # build the app bundle: build/Sunset.app
open build/Sunset.app
```

`scripts/bundle.sh` wraps the SwiftPM product into a real `.app` (icon, `Info.plist`, ad-hoc signature). Use `./scripts/bundle.sh release` for an optimized build and `./scripts/make-dmg.sh` for the universal installer.

You can also open `Package.swift` in Xcode to edit and debug, but run the bundled app to test anything that depends on the app bundle (icon, default browser, Keychain, extensions).

> **Your own data:** a development build uses the same data folder (`~/Library/Application Support/MiNavegador`) and bundle identifier as an installed Sunset. Back it up, or quit your installed copy, before testing anything that writes to the sidebar, history or passwords.

Useful environment variables are listed in the [README](README.md#build-from-source).

### Stable local signing (no repeated Keychain prompts)

Sunset encrypts saved passwords with a key in your Keychain, and macOS remembers which app may read it by its code signature. Ad-hoc builds get a new signature every time, so macOS asks for your Mac password after each build. To avoid it, create a self-signed certificate once:

1. Open **Keychain Access › Certificate Assistant › Create a Certificate…**
2. Name it exactly **Sunset Local Signing**, set **Certificate Type** to **Code Signing**, and create it.

`scripts/bundle.sh` uses it automatically when it exists. The next launch asks one last time: choose **Always Allow**.

## Project layout

The app is a Swift package with one module per area (see the [architecture table](README.md#architecture)). Some guidelines:

- **Model in `BrowserCore`, views in the feature modules.** Features talk to the model through `Browser` and never to each other directly.
- **The web engine stays behind `WebEngine` / `WebPage`.** Don't import WebKit outside `BrowserEngine` unless there's no way around it.
- **Performance matters.** The sidebar list is AppKit on purpose, so animations don't recompute the whole list each frame. If you touch it, run the benchmark (`SUNSET_BENCH=folders`) before and after and share the numbers in your PR.
- **Native menus.** Context menus use `NSMenu` (see `NativeMenu.swift`), not SwiftUI `contextMenu`, which can freeze while views update.

## Code style

- Follow the style of the surrounding code: Swift API Design Guidelines, 4-space indentation, no force unwraps outside tests.
- Keep views small and state in `@Observable` models.
- Write new comments and documentation in English. Many existing comments are in Spanish; feel free to translate them when you're already editing a file.
- User-facing strings are currently in Spanish. Until String Catalogs land, keep new strings consistent with the existing ones and mention them in your PR.

## Tests

- Add or update tests in `Tests/BrowserCoreTests` for model and import logic.
- `Tests/UISnapshotTests` render key screens; update them when you change those screens on purpose.
- `swift test` must pass before a PR is merged. CI runs it on every push and pull request.

## Pull requests

1. Fork the repository and create a branch from `master` (`fix/folder-preview`, `feature/split-view`…).
2. Keep each PR focused on one change. Small PRs get reviewed faster.
3. Describe what changed and why, and add screenshots or a short video for anything visual.
4. Make sure `swift build` and `swift test` pass.
5. Be patient and kind in review. We're all volunteers.

By contributing, you agree that your contributions are licensed under the [Mozilla Public License 2.0](LICENSE), the project's license.

## Code of Conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md). By participating you agree to uphold it.
