# Memento Native

**Your Mac's photographic memory** — automatically records your screen and lets you search anything you've seen.

Ever closed a tab and forgot the URL? Lost an important message? Can't remember where you saw that code snippet? Memento captures your screen continuously, extracts all text using OCR, and makes it searchable. Everything stays 100% local on your Mac.

[![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org)
[![macOS](https://img.shields.io/badge/macOS-14.0+-blue.svg)](https://www.apple.com/macos)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-support-yellow.svg)](https://buymeacoffee.com/uygarduzgun)

> Native Swift rewrite of [apirrone/Memento](https://github.com/apirrone/Memento). Open-source alternative to Rewind.ai.

## Use Cases

- 🔍 **Find by keyword** — Search "invoice", "meeting", "password"
- 💬 **Recover lost text** — Find that message or email you closed
- 🐛 **Debug timeline** — Scroll back to see what happened
- 🧠 **Semantic search** — Find "coding tutorial" even if text says "programming lesson"
- 📋 **Visual history** — Browse your screen activity by time

## Features

| Feature | Description |
|---------|-------------|
| 📸 Screen Recording | ScreenCaptureKit (macOS 14+) |
| 🔍 OCR Search | Apple Vision text recognition |
| 🧠 Semantic Search | Find by meaning, not just keywords |
| 📹 H.264 Video | Hardware-accelerated encoding |
| 💾 Full-Text Search | SQLite FTS5 |
| ⚡ Lightweight | ~1% RAM, minimal CPU |
| 🔒 Privacy-First | No cloud, no telemetry |

## Quick Start

```bash
git clone https://github.com/owgit/memento-native.git
cd memento-native/MementoCapture && ./bundle.sh
cd ../MementoTimeline && ./bundle.sh
```

Both apps installed to `/Applications/`

## Setup Permissions

1. Open **System Settings** → **Privacy & Security** → **Screen Recording**
2. Click **+** and add `/Applications/Memento Capture.app`
3. Enable it (toggle ON)
4. Start the app: `open /Applications/Memento\ Capture.app`

## Requirements

| Requirement | Details |
|-------------|---------|
| **macOS** | 14.0 Sonoma or later |
| **Mac** | Apple Silicon (M1/M2/M3) or Intel Mac |
| **RAM** | 8GB minimum |
| **Disk** | ~150MB/hour of recording |
| **Permission** | Screen Recording |

## Performance

| Metric | Value |
|--------|-------|
| **CPU** | ~1-3% (idle between captures) |
| **RAM** | ~50-100MB |
| **Capture interval** | Every 2 seconds |
| **Video codec** | H.264 hardware-accelerated |

## How It Works

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

Data stored in `~/.cache/memento/`

## Privacy

- **100% offline** — works without internet
- **No accounts** — no sign-up required  
- **No telemetry** — zero data collection
- **Clipboard opt-in** — clipboard monitoring disabled by default, toggle in menu
- **Local storage** — delete anytime with `rm -rf ~/.cache/memento`

## Alternatives

| App | Platform | Price | Privacy |
|-----|----------|-------|---------|
| [Rewind.ai](https://rewind.ai) | macOS | $19/mo | Cloud |
| [Memento (Python)](https://github.com/apirrone/Memento) | Linux | Free | Local |
| **Memento Native** | **macOS** | **Free** | **Local** |

## Roadmap

### 🤖 AI-Powered Search (Coming)

Local LLM integration for natural language queries:

- "What was that article about React I read yesterday?"
- "Find the Slack message from Johan about the API"
- "Show me when I was working on the login bug"
- "What did I copy to clipboard around 3pm?"

## License

MIT — use it however you want.

---

**Keywords:** screen recorder macos, ocr search mac, rewind alternative, local screen recording, privacy screen capture, searchable screenshots, macos productivity, swift screencapturekit
