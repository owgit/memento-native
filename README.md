# Memento Native

Native macOS screen capture & timeline viewer. 100% Swift/SwiftUI.

## Apps

| App | Description |
|-----|-------------|
| **MementoCapture** | Background service - screenshots, OCR, video encoding |
| **MementoTimeline** | Timeline viewer with search |

## Features

- 🎥 Screenshot capture every 2 seconds
- 🔍 Vision OCR (native Apple text recognition)
- 📹 H.264 video encoding (VideoToolbox hardware acceleration)
- 💾 SQLite with FTS5 full-text search
- 🔒 100% local - no cloud, no telemetry
- ⚡ ~1% RAM usage

## Build

```bash
# Capture service
cd MementoCapture && swift build

# Timeline viewer
cd MementoTimeline && swift build
```

## Install

```bash
# Build release
cd MementoCapture && swift build -c release
cd MementoTimeline && swift build -c release

# Create app bundles (optional)
# See scripts/create_apps.sh
```

## Requirements

- macOS 13.0+
- Screen Recording permission

## Data Location

```
~/.cache/memento/
├── memento.db      # SQLite database
├── *.mp4           # Video files
└── *.log           # Logs
```

## License

MIT
