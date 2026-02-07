# Changelog

All notable changes to Memento Native will be documented in this file.

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
