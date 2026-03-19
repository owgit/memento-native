# Settings Guide / Inställningsguide

This page explains each setting in `Memento Capture`, including defaults, when to use it, and tradeoffs.

Denna sida förklarar varje inställning i `Memento Capture`, inklusive standardvärden, när du bör använda den och kompromisser.

## Capture Settings / Inspelningsinställningar

### Capture Interval (1s, 2s, 3s, 5s, 10s)

Default: `2s`

**EN:** Controls how often screenshots are captured.

**SV:** Styr hur ofta skärmbilder fångas.

Pros/cons by interval:

| Interval | Pros | Cons | Good for |
|---|---|---|---|
| 1s | Best recall granularity, fewer missed states | Higher CPU/disk growth | Fast debugging, rapid UI work |
| 2s | Balanced quality/performance | Slightly less detail than 1s | Most users (recommended) |
| 3s | Lower storage and CPU | Can miss short transitions | General office use |
| 5s | Noticeably lower resource usage | Coarser history | Long sessions, low-change work |
| 10s | Minimal resource usage | Highest chance to miss events | Very low-power / archival mode |

### Pause when idle

Default: `On`

- Idle threshold options: `30s`, `60s`, `90s`, `2m`, `5m`
- Default threshold: `90s`

**EN:** Auto-pauses capture when no input is detected.

**SV:** Pausar inspelning automatiskt när ingen aktivitet upptäcks.

### Pause during video/streaming

Default: `On`

**EN:** Uses motion + media context heuristics to avoid recording low-value playback windows.

**SV:** Använder rörelse + media-kontext för att undvika inspelning av lågnyttigt videoinnehåll.

### Pause in private/incognito mode

Default: `On`

**EN:** Best-effort detection for private/incognito browsing; capture is paused when detected.

**SV:** Best-effort-detektering för privat/inkognito-läge; inspelning pausas när det upptäcks.

### Manual pause/resume (user-triggered)

**EN:** You can manually switch recording mode from the menu bar Control Center chips (`Recording` / `Paused`).

**SV:** Du kan manuellt växla inspelningsläge i menyradens Control Center-chips (`Spelar in` / `Pausad`).

## Privacy Settings / Sekretess

### Capture clipboard

Default: `Off`

**EN:** Captures new clipboard content and stores it as searchable context.

**SV:** Fångar nytt urklippsinnehåll och lagrar det som sökbar kontext.

Tradeoff:
- Better recall for copied text
- Higher sensitivity/privacy risk if clipboard contains secrets

### Excluded apps

Default includes Timeline app names.

**EN:** Add app names that should never be OCR-scanned.

**SV:** Lägg till appar som aldrig ska OCR-tolkas.

## Storage Settings / Lagring

### Keep data (retention)

Options: `1, 3, 7, 14, 30 days, ∞`
Default: `7 days`

**EN:** Controls automatic cleanup horizon.

**SV:** Styr hur länge data sparas innan automatisk rensning.

### Storage location

Default path: `~/.cache/memento`

**EN:** Move storage path from Settings; migration is handled in-app.

**SV:** Flytta lagringsplats via Settings; migrering sker i appen.

## System Settings / System

### Start at login

Default: `Off`

**EN:** Installs/removes LaunchAgent for auto-start.

**SV:** Installerar/tar bort LaunchAgent för autostart.

### Setup Hub

**EN:** Opens guided permission and repair flow.

**SV:** Öppnar guidad behörighets- och reparationsvy.

## Recommended profiles / Rekommenderade profiler

### Balanced (default-ish)

- Interval: `2s`
- Pause when idle: `On` at `90s`
- Pause during video: `On`
- Pause in private/incognito: `On`
- Clipboard: `Off`
- Retention: `7 days`

### High fidelity

- Interval: `1s`
- Idle pause: `On` at `2m`
- Video pause: `Off` (if you need full timeline)
- Private/incognito pause: `On`
- Clipboard: `Optional`
- Retention: `14-30 days`

### Low resource / long sessions

- Interval: `5s` or `10s`
- Idle pause: `On` at `60s`
- Video pause: `On`
- Private/incognito pause: `On`
- Clipboard: `Off`
- Retention: `7 days` or less
