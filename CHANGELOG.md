# Changelog

All notable changes to Sunset Browser are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- ⌃Tab switches between recent tabs like in Arc: hold ⌃ and press Tab (⇧ to go back) to move through the favorites and the current space's tabs, most recently used first, in a panel with a preview of each page; releasing ⌃ opens the highlighted one. A quick ⌃Tab jumps straight to the previous tab. Arrow keys, Return, Esc and the mouse also work in the panel.

## [0.1.4] - 2026-10-26

### Added

- Web notifications: sites like webmails can show macOS notifications, with sound, while their tab is open. Sunset asks once per site (Allow, Block or Not now) and remembers it; "Notificaciones de este sitio" in the Command Bar changes it. Clicking a notification brings you to its tab. Tabs of sites with notifications allowed don't hibernate and load when Sunset starts, so they keep notifying.
- Web Push: sites that notify through their service worker (`pushManager.subscribe`), like webmails, now work. WebKit only talks to Safari's push service, so Sunset subscribes with Mozilla's push service (the one Firefox uses), keeps a connection open while it runs, decrypts each message and hands it to the site's service worker; clicking its notification reaches the service worker too. Messages sent while Sunset is closed arrive when it opens. The server can be changed with the `pushServerURL` default.
- ⌘Z reopens the last closed tab, like Arc (it still undoes typing in text fields). Reopened tabs, with ⌘Z or ⇧⌘T, go back to their exact spot in the sidebar with their history.
- Warning for extensions that use Chrome-only APIs WebKit doesn't have (such as `chrome.debugger` or `chrome.sidePanel`): shown before installing and next to the extension in the extensions panel.

### Changed

- Tabs stay alive in the background like in Arc instead of going to sleep after 10 minutes, so webmails keep checking for mail and notifying from other tabs. Sunset only puts tabs to sleep when macOS runs low on memory: first the ones unused for an hour, and all but the visible one if memory gets critical. Tabs playing audio or from sites allowed to notify never sleep.

### Fixed

- macOS no longer asks for your Mac password to read saved passwords after every Sunset update. The key that encrypts them now lives in a file next to them that only your user can read, like Firefox without a primary password, instead of the Keychain (which ties it to each build when Sunset isn't signed by an Apple developer team). It's moved over from the Keychain once.
- Auto picture-in-picture only kicks in for videos with sound, so muted autoplaying videos (the X timeline, GIFs) no longer pop out when switching tabs.
- PDFs embedded as `blob:` in a frame (attachment previews in webmails) now display with a native viewer instead of staying blank, even when the page's security policy blocks WebKit's own viewer (`frame-ancestors`, `connect-src`), and frames no longer save those blobs to Downloads.
- Sites behind HTTP authentication sign in automatically with the most recently saved password for that address, so the session survives restarting Sunset even with several saved accounts.
- Extension pages opened in a tab (for example SVG Gobbler's collection or an options page) load instead of staying blank, and keep working after restarting Sunset.

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

[Unreleased]: https://github.com/CarlosVP120/sunset-browser/compare/v0.1.4...HEAD
[0.1.4]: https://github.com/CarlosVP120/sunset-browser/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/CarlosVP120/sunset-browser/compare/v0.1.1...v0.1.3
[0.1.1]: https://github.com/CarlosVP120/sunset-browser/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/CarlosVP120/sunset-browser/releases/tag/v0.1.0
