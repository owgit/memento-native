# Changelog

All notable changes to Memento Native will be documented in this file.

## [2.1.1] - 2026-05-01

### Fixed
- Timeline close, minimize, and zoom buttons now remain visible in the release build, matching the local window chrome behavior before the 2.1.0 update.
- The Timeline window can resize again while preserving the intended aspect ratio and minimum usable size.

### Improved
- The hidden-toolbar restore control is now a compact 44pt icon button so it blocks less of the Live Text selection area.
- Timeline now keeps a subtle top chrome band behind the native macOS window controls while the scrubber/app toolbar stays independently hideable.

### Verification
- `swift test` in `MementoTimeline`
- `swift build -c release` in `MementoTimeline`
- `swift test` in `MementoCapture`
- `swift build -c release` in `MementoCapture`
- `git diff --check`
- Developer ID signed and notarized DMG: `Memento-Native-2.1.1.dmg`
- Mounted app version/build: `2.1.1` / `211`
- Mounted app TeamIdentifier: `7GNHCUW7HN`
- DMG SHA-256: `7cc91505b8924c300cca928596c56bc5366ea2407766175266895782e11165c0`

## [2.1.0] - 2026-05-01

### Added
- Hideable Timeline toolbar: the scrubber and app filters can now be hidden so Live Text behind the controls can be selected and copied.
- A compact `Show toolbar` affordance restores the Timeline controls after they have been manually hidden.

### Improved
- Timeline window startup now seeds the latest captured frame while history loads.
- Timeline window chrome is cleaner, rounded, transparent, and better aligned with the embedded single-app experience.
- README visuals and release positioning are refreshed for the current app-aware Timeline flow.

### Fixed
- Live Text analysis now cancels stale analysis work when frames change quickly, preventing outdated text overlays from racing the visible frame.
- Content FTS maintenance now uses stable row IDs, delete/update triggers, and a schema-versioned rebuild path.
- Storage cleanup now deletes related FTS rows, rolls back failed cleanup transactions, and avoids deleting partial frame sets from active video ranges.

### Verification
- `swift test` in `MementoTimeline`
- `swift build -c release` in `MementoTimeline`
- `swift test` in `MementoCapture`
- `swift build -c release` in `MementoCapture`
- `git diff --check`
- Developer ID signed and notarized DMG: `Memento-Native-2.1.0.dmg`
- DMG SHA-256: `d1ae509c1a6b3affd32d50186523fce1bac6e57c07bc7607380b6b2239c36985`

## [2.0.6] - 2026-04-24

### Highlights
- Memento now ships as a single app: install and run `Memento Capture.app`, then open Timeline from the menu bar instead of managing a separate `Memento Timeline.app`
- Timeline now supports app-aware browsing with app filters, per-app counts, app-scoped search, scrubber markers, and previous/next marker navigation
- GitHub/direct updates were hardened for the new single-app DMG layout and official Developer ID-signed releases

### Added
- Embedded Timeline window hosted inside Capture through `TimelineWindowController`
- Shared Timeline runtime configuration so embedded Timeline uses the active storage path and capture interval from Capture settings
- Standalone Timeline dev host under `MementoTimeline/App` while keeping the release distribution single-app
- App filter chips in Timeline, including `All` plus detected apps with result counts
- App-specific scrubber markers and previous/next controls for jumping between captures from the selected app
- App identity metadata in Timeline segments so search, filters, and marker rendering can align on bundle/app identity
- Auto-start registration tests and Timeline runtime configuration tests

### Improved
- DMG packaging now builds the Xcode/XcodeGen single-app project and stages only `Memento Capture.app`
- Update installer now expects the single-app DMG layout instead of copying both Capture and Timeline apps
- Menu bar actions open Timeline and Settings in-app and dismiss the menu before presenting windows
- Settings window is resizable, autosaved, and better handles excluded-app input validation
- Release metadata now consistently uses `2.0.6` / build `206` across the Xcode project, bundle scripts, README, and DMG script
- Direct-update checks are skipped for App Store distribution builds
- Update failure dialogs include a FAQ path for manual recovery
- Permission state refresh uses async screen-recording verification before syncing capture state
- Debug screenshots use app storage in App Store-style builds and Desktop for direct builds
- Documentation now covers FAQ, Settings, Security, Support, release process, repository settings, and update reliability
- GitHub release hygiene now includes issue templates, PR template, CODEOWNERS, and Release Guard validation

### Fixed
- Automatic GitHub updater now installs official Developer ID-signed DMGs even when notarization is unavailable
- Update installer errors no longer surface successful `codesign` diagnostics as the apparent failure reason
- Installer verification now checks the downloaded DMG team id, app bundle id, app version, and app signature before copying
- Updater no longer looks for or copies a separate `Memento Timeline.app`
- Relaunch after update now goes through a dedicated relaunch helper instead of an inline temporary script
- Bundle scripts no longer default to stale `2.0.3` metadata

### Verification
- `swift test` in `MementoCapture`
- `swift test` in `MementoTimeline`
- `git diff --check`
- DMG checksum, DMG codesign, mounted app codesign, and installer verification against `Memento-Native-2.0.6.dmg`

### Distribution Note
- The GitHub DMG is Developer ID-signed, but notarization is still blocked until the Apple Developer agreement/notary profile is fixed

## [2.0.5] - 2026-04-24

### Added
- Timeline app filtering with app chips, app-specific counts, and direct search scoping
- App-specific scrubber markers plus previous/next marker navigation for selected apps
- Single-app Timeline runtime path so Timeline can open inside the Capture app distribution

### Improved
- Timeline search now carries app identity more consistently for app-aware browsing
- Settings window behavior, resizing, and excluded-app input validation are more robust
- Privacy, permission, update, and release documentation is clearer for GitHub distribution

### Fixed
- Release script defaults now align with the current GitHub release version
- Bundle metadata preserves distribution channel details during app updates

## [2.0.4] - 2026-03-19

### Added
- Structured `OSLog` wrappers for both Capture and Timeline targets
- Shared runtime helpers for app version labels and storage-byte aggregation

### Improved
- Swift 6 migration and concurrency hardening across Capture + Timeline packages
- Capture scheduling now prevents overlapping frame jobs and handles in-flight cancellation during stop/interval changes
- Setup Hub and Timeline state flows are simplified with safer task/event monitor teardown

### Fixed
- Removed dead/unused code paths (legacy onboarding window, stale DB/search helpers, unused embedding APIs, redundant properties/imports)
- Standardized screenshot error logging and reduced duplicated utility logic for localization/version/storage formatting

## [2.0.3] - 2026-03-12

### Improved
- Semantic search now selects on-device embedding models per language instead of assuming a single language path
- Capture builds cleaner semantic summaries from app name, URL, title, clipboard, and deduplicated OCR instead of a single noisy text blob
- Timeline search ranks URL, title, clipboard, OCR, and semantic matches more consistently in hybrid results
- Automatic update checks now run monthly while still surfacing menu indicators and macOS notifications when a new version is found

### Fixed
- Browser URL/title capture now declares Apple Events usage correctly so recent browser history can be indexed again
- Browser AppleScript failures are now logged once per error signature instead of failing silently
- Timeline `⌘F` button now uses a search icon instead of the command symbol
- Update relaunch flow now waits for the old process to exit before reopening `Memento Capture`

## [2.0.2] - 2026-03-07

### Fixed
- Timeline now parses stored ISO 8601 timestamps correctly, restoring proper day grouping and history metadata
- Search now finds OCR phrases split across multiple text blocks and handles hyphenated terms like `Dev-1` more reliably
- Search result deduplication collapses repeated OCR hits from the same nearby capture window
- Video clip rollover and local frame timestamps now stay aligned between Capture and Timeline
- Storage migration now compares file contents safely instead of trusting file size matches
- Capture database writes now rollback cleanly on failure instead of committing partial OCR rows
- Video encoder finalize path no longer blocks the main actor and surfaces append/finalize failures explicitly
- Capture interval changes now apply live to both the timer and video encoder without restarting the app

### Improved
- Timeline search preparation and video catalog refresh now run off the main actor
- Timeline frame loading uses a single controlled task path and background log writer to reduce UI stalls
- Timeline frame fallback timing now respects the current capture interval instead of assuming `2.0s`
- Storage migration now runs asynchronously from Settings with progress feedback

## [2.0.1] - 2026-02-09

### Fixed
- In-app auto-update installer no longer fails on DMG Gatekeeper context checks
- Restart action after successful in-app update now reliably relaunches `Memento Capture`

## [2.0.0] - 2026-02-09

### Added
- Unified Setup Hub for first launch, permission recovery, and update recovery
- Menubar Control Center chips for recording state, permission state, and last capture
- Timeline Action Hub / Command Palette with quick actions and time jump
- Smart capture auto-pause options (idle + video/stream detection)
- Hardened runtime entitlements for Capture and Timeline bundles

### Improved
- Search UX states, keyboard flow, and robustness when opening older history results
- Timeline history loading feedback and scrubber polish
- Simpler release workflow: automatic notary profile discovery (`MEMENTO_NOTARY` / `memento-notary`)
- Shortcut model updated: `⌘F` opens Action Hub, `⌘K` opens direct search

### Security
- Public DMG pipeline now uses Developer ID signing + notarization + stapling for trusted distribution

## [1.0.8] - 2026-02-08

### Added
- Unified Setup Hub flow for first launch, permission recovery, and updates
- Menubar Control Center chips for recording state, permission state, and last capture
- Timeline Command Palette / Action Hub with command and time-jump actions
- Smart auto-pause options (idle + video/stream detection)

### Improved
- Search UX with clearer loading/empty/error states and better keyboard flow
- Search result opening for older history is more robust
- Timeline history loading feedback and scrubber polish
- Shortcut model updated: `⌘F` opens Action Hub, `⌘K` opens direct search

### Fixed
- Reduced repeated permission prompt loops
- Better permission recovery and post-update trust flow
- Menubar top-row layout clipping/overlap issues

## [1.0.7] - 2026-02-07

### Fixed
- DMG packaging now avoids Apple Development signing in untrusted mode
- Local/untrusted builds now force ad-hoc app signing for better compatibility
- Release script keeps strict guardrails for trusted public releases

## [1.0.5] - 2026-02-07

### Added
- In-app update checks against latest GitHub release with menu action support
- Local macOS notification when a new app version is available
- Menubar warning icon/status when screen recording permission is missing

### Improved
- Permission guide now keeps actions visible in a fixed footer (no extra scrolling)
- Permission guide text is clearer in both Swedish and English
- Onboarding permission visuals use a more neutral, consistent accent style

## [1.0.4] - 2026-02-07

### Added
- Automatic storage migration when changing storage location in Settings
- Release update guide for users (`UPDATING.md`)

### Improved
- Search now loads full history before querying
- Older search results now resolve to valid screenshot frames more reliably
- Bundle scripts now support stable signing identities when available

## [1.0.3] - 2026-01-23

### Added
- Multi-step onboarding guide with 4 slides
- Full English/Swedish localization for onboarding

## [1.0.2] - 2026-01-23

### Added
- Skip capture when screen locked or screensaver active

## [1.0.1] - 2026-01-23

### Improved
- Multi-language embeddings (Swedish, German, French, Spanish)
- Lower similarity threshold for better search recall

## [1.0.0] - 2024-12-08

### Added
- Screen recording with ScreenCaptureKit (macOS 14+)
- OCR text extraction with Apple Vision
- Full-text search with SQLite FTS5
- Semantic search with NLEmbedding
- H.264 video encoding (hardware-accelerated)
- Settings window with configurable options:
  - Capture interval (1-10s)
  - Clipboard monitoring (opt-in)
  - Excluded apps list
  - Retention period (1-30 days)
  - Storage location
  - Auto-start at login
- Permission guide with step-by-step instructions
- Browser URL/title capture (Safari, Chrome, Arc, Firefox, Brave, Edge)
- Bilingual support (Swedish/English)
- DMG installer with both apps

### Security
- Parameterized SQL queries to prevent injection
- 100% local storage, no cloud/telemetry
- Clipboard monitoring disabled by default
