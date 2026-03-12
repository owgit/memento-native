# Memento Native

**Your Mac's photographic memory** — automatically records your screen and lets you search anything you've seen.

Ever closed a tab and forgot the URL? Lost an important message? Can't remember where you saw that code snippet? Memento captures your screen continuously, extracts all text using OCR, and makes it searchable. Everything stays 100% local on your Mac.

[![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org)
[![macOS](https://img.shields.io/badge/macOS-14.0+-blue.svg)](https://www.apple.com/macos)
[![License](https://img.shields.io/badge/License-PolyForm%20NC-blue.svg)](LICENSE)
[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-support-yellow.svg)](https://buymeacoffee.com/uygarduzgun)

> Native Swift rewrite of [apirrone/Memento](https://github.com/apirrone/Memento). Open-source alternative to Rewind.ai.

## Latest (v2.0.3)

- Unified **Setup Hub** for first-run, permission fixes, and update recovery
- **Action Hub / Command Palette** (`⌘F`) for search + quick actions
- Direct search panel moved to `⌘K`
- Menubar **Control Center** chips (recording state, permission state, last capture)
- Smarter capture auto-pause (idle + video/streaming + private/incognito browsing)
- Improved multilingual semantic search and URL/title ranking for browser history
- Browser URL/title capture now requests the correct macOS Automation permission when needed
- Automatic monthly update checks with menu + notification indicators when a new release is available

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
| ⌨️ Action Hub | Command palette (`⌘F`) for actions and fast search |
| 🛠️ Setup Hub | Unified onboarding + permission repair flow |
| 🎛️ Menubar Control Center | Recording/paused, permission, last-capture status chips |
| ⏸️ Smart Auto-Pause | Pause when idle, during video/streaming playback, and in private/incognito browser windows |
| 🎨 App Learning | Auto color-codes apps in timeline |
| 📹 H.264 Video | Hardware-accelerated encoding |
| 💾 Full-Text Search | SQLite FTS5 |
| ⚡ Lightweight | ~1% RAM, minimal CPU |
| 🔒 Privacy-First | No cloud, no telemetry |

## Installation

### Option 1: DMG (Recommended)

Download the latest DMG from [Releases](https://github.com/owgit/memento-native/releases), open it, and drag both apps to Applications.

### Option 2: Build from source

```bash
git clone https://github.com/owgit/memento-native.git
cd memento-native
./build-dmg.sh 2.0.3  # Creates dist/Memento-Native-2.0.3.dmg
# Or build individually:
cd MementoCapture && ./bundle.sh
cd ../MementoTimeline && ./bundle.sh
```

## Updating

If you're updating from an older version, follow the release update steps in [UPDATING.md](UPDATING.md).

Quick summary:

1. Quit both apps
2. Replace both apps in `/Applications`
3. Start `Memento Capture` first
4. Re-check Screen Recording permission if macOS asks
5. If capture still fails, open **Setup Hub** from the menu bar and run **Repair Permissions**

## Setup Permissions

1. Open `/Applications/Memento Capture.app`
2. Follow **Setup Hub** prompts (recommended)
3. If needed, use **Fix/Repair Permissions** in Setup Hub
4. Allow **Automation** access for `Memento Capture` if macOS asks to control Safari/Chrome/Arc/Edge/Brave/Firefox for URL capture
5. Manual fallback: **System Settings** → **Privacy & Security** → **Screen Recording** and enable `Memento Capture`

You can re-open Setup Hub anytime from the menu bar app.

## When Capture Pauses Automatically

Capture pauses automatically in these cases:

- The screen is locked or the screen saver is active
- You are idle (default 90 seconds, configurable in Settings)
- Video/streaming playback is detected (motion + media context)
- A private/incognito browser window is active (Chrome/Arc/Brave/Edge/Safari/Firefox best-effort detection)
- `Memento Timeline` is the frontmost app

## Keyboard Shortcuts (Timeline)

- `⌘F` — Open Action Hub (Command Palette)
- `⌘K` — Open direct Search panel
- `⌘T` — Toggle OCR text panel
- `←` / `→` — Previous / next frame
- `Home` / `End` — First / last frame

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
| **Capture interval** | Default 2 seconds (configurable) |
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

[PolyForm Noncommercial 1.0.0](LICENSE) — free for personal and non-commercial use. Commercial sale prohibited.

---

**Keywords:** screen recorder macos, ocr search mac, rewind alternative, local screen recording, privacy screen capture, searchable screenshots, macos productivity, swift screencapturekit
