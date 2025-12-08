# Memento Native

Native macOS screen capture & timeline viewer. 100% Swift, 100% local.

## Features

| Feature | Description |
|---------|-------------|
| 📸 Screenshot | Capture every 2 seconds |
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

## Build

```bash
cd MementoCapture && swift build -c release
cd MementoTimeline && swift build -c release
```

## Install

```bash
# Create app bundle
mkdir -p "Memento Capture.app/Contents/MacOS"
cp MementoCapture/.build/release/memento-capture "Memento Capture.app/Contents/MacOS/"

# Auto-start (optional)
cp com.memento.capture.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.memento.capture.plist
```

## Architecture

```
┌─────────────────┐     ┌──────────────┐
│ MementoCapture  │────▶│   SQLite     │◀────│ MementoTimeline │
│                 │     │  + FTS5      │     │                 │
│ • Screenshot    │     │  + Vectors   │     │ • View frames   │
│ • Vision OCR    │     └──────────────┘     │ • Text search   │
│ • H.264 encode  │            │             │ • Semantic search│
│ • Embeddings    │            ▼             └─────────────────┘
└─────────────────┘     ~/.cache/memento/
```

## Semantic Search

Uses Apple NaturalLanguage for on-device embeddings:

```swift
// 512-dim sentence embedding → Int8 quantized (8x compression)
NLEmbedding.sentenceEmbedding(for: .english)
```

| Storage | Size/frame |
|---------|-----------|
| Float32 | 2048 bytes |
| **Int8** | **512 bytes** |

## Data

```
~/.cache/memento/
├── memento.db      # SQLite (frames, OCR, embeddings)
├── *.mp4           # H.264 videos
└── *.log           # Logs
```

## Requirements

- macOS 13.0+
- Screen Recording permission

## Privacy

- 🔒 100% local - no cloud, no telemetry
- All data in `~/.cache/memento/`
- Delete anytime: `rm -rf ~/.cache/memento`

## License

MIT

