# Changelog

All notable changes to Sunset Browser are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Sign-in dialog for sites protected with HTTP authentication (Basic, Digest or NTLM), such as self-hosted Supabase Studio behind Kong. The password is saved in Sunset's vault once the server accepts it and is used automatically next time.

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

[Unreleased]: https://github.com/CarlosVP120/sunset-browser/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/CarlosVP120/sunset-browser/releases/tag/v0.1.0
