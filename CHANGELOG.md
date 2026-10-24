# Changelog

All notable changes to Sunset Browser are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.3] - 2026-10-24

### Changed

- Bigger symbol in the app icon.
- The app is now called just "Sunset" in the Dock, the menu bar and Finder (`Sunset.app`). The project keeps the name Sunset Browser, and installs keep their data.
- Gapless layout: the web page now reaches the window edges, with rounded corners only next to the sidebar (and none when the sidebar is hidden).

### Fixed

- The Command Bar opens centered on the web area (horizontally and vertically) instead of the whole window, and the Home row shows its icon when selected.
- The Command Bar's glass blurs what is under it in the window (Home or the page) instead of whatever is behind the window on the desktop.
- Site icons for pages behind a password or a session (for example self-hosted Supabase Studio) are fetched through the open page, so they no longer show a globe.
- The site icon stays centered inside the loading ring while a tab loads.
- Gmail's theme background now covers the whole page after hiding the sidebar, instead of leaving a dark band on the right.

## [0.1.1] - 2026-10-24

### Added

- Sign-in dialog for sites protected with HTTP authentication (Basic, Digest or NTLM), such as self-hosted Supabase Studio behind Kong or Envoy. It asks once per site, even when the page makes many requests at the same time, and the password is saved in Sunset's vault once the server accepts it and used automatically next time.

### Fixed

- Password autofill only suggests accounts for the page's origin, like Chrome and Arc: on `localhost` and IP addresses the port must match, and same-origin accounts are listed first.

## [0.1.0] - 2026-10-23

First public version.

### Added

- Sidebar with spaces, favorites, pinned tabs, folders and Today tabs, built on an AppKit list for smooth animations.
- Spaces with gradient themes, grain and light or dark appearance; switch with ⌃1–⌃9 or a two-finger swipe on the sidebar.
- Pinned tabs and favorites that keep their home URL, like Arc.
- Drag and drop for tabs, folders, favorites and spaces, and folder previews on hover.
- Command Bar (⌘T) to search, open URLs, switch tabs and run actions.
- Home page with a clock, search, favorites and a sky that follows the time of day.
- Developer mode: automatic on localhost or with ⌃D, with the native WebKit inspector, console and network panels, hard reload and responsive sizes.
- Library with downloads, media and archived tabs; media controls in the sidebar and Picture in Picture.
- Password manager with autofill, encrypted with a Keychain key.
- Web extensions on macOS 15.4 and later.
- First-launch onboarding that imports spaces, bookmarks, history, passwords and sessions from Arc, Chrome, Safari, Brave and Edge.
- Universal (Apple silicon and Intel) DMG installer.

[Unreleased]: https://github.com/CarlosVP120/sunset-browser/compare/v0.1.3...HEAD
[0.1.3]: https://github.com/CarlosVP120/sunset-browser/compare/v0.1.1...v0.1.3
[0.1.1]: https://github.com/CarlosVP120/sunset-browser/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/CarlosVP120/sunset-browser/releases/tag/v0.1.0
