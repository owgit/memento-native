# Memento Native

Native macOS screen capture & timeline viewer. 100% Swift, 100% local.

## Features

| Feature | Description |
|---------|-------------|
| 📸 ScreenCaptureKit | Modern macOS 14+ capture API |
| 🔍 Vision OCR | Apple's native text recognition |
| 🧠 Semantic Search | NaturalLanguage embeddings |
| 📹 H.264 Video | VideoToolbox hardware encoding |
| 💾 SQLite + FTS5 | Full-text search |
| ⚡ Low Resource | ~1% RAM, minimal CPU |

## Apps

```
MementoCapture/     Background service
MementoTimeline/    Timeline viewer
```

## Build & Install

```bash
cd MementoCapture && ./bundle.sh
```

Creates `~/Applications/Memento Capture.app`

## Requirements

- macOS 14.0+
- Screen Recording permission

## Architecture

```
┌─────────────────┐     ┌──────────────┐
│ MementoCapture  │────▶│   SQLite     │◀────│ MementoTimeline │
│                 │     │  + FTS5      │     │                 │
│ • ScreenCaptureKit    │  + Vectors   │     │ • View frames   │
│ • Vision OCR    │     └──────────────┘     │ • Text search   │
│ • H.264 encode  │            │             │ • Semantic search│
│ • Embeddings    │            ▼             └─────────────────┘
└─────────────────┘     ~/.cache/memento/
```

## Data

```
~/.cache/memento/
├── memento.db      # SQLite (frames, OCR, embeddings)
└── *.mp4           # H.264 videos
```

## Privacy

- 🔒 100% local - no cloud, no telemetry
- All data in `~/.cache/memento/`
- Delete anytime: `rm -rf ~/.cache/memento`

## License

MIT
