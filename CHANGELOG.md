# Changelog

All notable changes to Memento Native will be documented in this file.

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

