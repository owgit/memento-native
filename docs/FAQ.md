# FAQ / Vanliga Frågor

This FAQ explains why permissions are required, how update/install works, and how to troubleshoot common issues.

Den här FAQ:en förklarar varför behörigheter krävs, hur uppdatering/installering fungerar, och hur du felsöker vanliga problem.

## Table of Contents

- [Why does Memento need Screen Recording? / Varför behövs Skärminspelning?](#why-does-memento-need-screen-recording--varfor-behovs-skarminspelning)
- [Why does browser access need Automation? / Varför behövs Automation för browser access?](#why-does-browser-access-need-automation--varfor-behovs-automation-for-browser-access)
- [Why does capture pause sometimes? / Varför pausar inspelningen ibland?](#why-does-capture-pause-sometimes--varfor-pausar-inspelningen-ibland)
- [Can I pause/resume manually? / Kan jag pausa/återuppta manuellt?](#can-i-pauseresume-manually--kan-jag-pausaatteruppta-manuellt)
- [How should I choose capture interval? / Hur väljer jag capture-intervall?](#how-should-i-choose-capture-interval--hur-valjer-jag-capture-intervall)
- [Why can auto-update ask for admin password? / Varför frågar auto-update efter admin-lösenord?](#why-can-auto-update-ask-for-admin-password--varfor-fragar-auto-update-efter-admin-losenord)
- [Where is data stored and how do I clean it? / Var lagras data och hur rensar jag?](#where-is-data-stored-and-how-do-i-clean-it--var-lagras-data-och-hur-rensar-jag)
- [Why did I only see "Open release page"? / Varför såg jag bara "Open release page"?](#why-did-i-only-see-open-release-page--varfor-sag-jag-bara-open-release-page)
- [Troubleshooting / Felsökning](#troubleshooting--felsokning)

## Why does Memento need Screen Recording? / Varför behövs Skärminspelning?

**EN:** Memento captures what is visible on your screen. macOS requires Screen Recording permission for any app that reads screen content.

**SV:** Memento spelar in det som syns på skärmen. macOS kräver Skärminspelnings-behörighet för appar som läser skärminnehåll.

## Why does browser access need Automation? / Varför behövs Automation för browser access?

**EN:** For richer search context, Memento reads active tab URL/title from supported browsers. macOS protects this via Automation (Apple Events).

**SV:** För bättre sök-kontekst läser Memento aktiv fliks URL/titel i stödda browsers. macOS skyddar detta via Automation (Apple Events).

Without Automation, capture still works, but URL/title metadata may be missing.

## Why does capture pause sometimes? / Varför pausar inspelningen ibland?

**EN:** Pause is intentional in low-value or sensitive contexts:
- screen locked / screensaver
- user idle
- likely video/streaming playback
- private/incognito browsing
- Memento-owned UI windows are frontmost

**SV:** Paus sker medvetet i lågnytta- eller känsliga lägen:
- skärmen låst / skärmsläckare
- inaktiv användare
- sannolik video/streaming
- privat/incognito-läge
- Mementos egna fönster ligger överst

## Can I pause/resume manually? / Kan jag pausa/återuppta manuellt?

**EN:** Yes. Use the menu bar Control Center and switch between `Recording` and `Paused`.

**SV:** Ja. Använd menyradens Control Center och växla mellan `Spelar in` och `Pausad`.

## How should I choose capture interval? / Hur väljer jag capture-intervall?

**EN:** Short interval = better recall, higher CPU/storage. Longer interval = lower resource usage, lower detail.

**SV:** Kort intervall = bättre detaljgrad, högre CPU/lagring. Långt intervall = lägre resursanvändning, lägre detaljgrad.

See full pros/cons table: [docs/SETTINGS.md](SETTINGS.md)

## Why can auto-update ask for admin password? / Varför frågar auto-update efter admin-lösenord?

**EN:** In-app updater replaces the app in `/Applications`, which often requires elevated privileges on macOS.

**SV:** In-app updater ersätter appen i `/Applications`, vilket ofta kräver administratörsrättigheter på macOS.

This is expected behavior for trusted app replacement.

## Where is data stored and how do I clean it? / Var lagras data och hur rensar jag?

Default location:

`~/.cache/memento`

Storage can be changed in Settings. You can clean data from the app's cleanup actions or delete the folder manually.

## Why did I only see "Open release page"? / Varför såg jag bara "Open release page"?

**EN:** In-app update shows **Install now** only when the GitHub release includes a DMG asset with expected format:

`Memento-Native-<version>.dmg`

If this asset is missing, updater falls back to **Open release page**.

**SV:** In-app update visar **Install now** endast när GitHub-releasen innehåller en DMG med förväntat namnformat:

`Memento-Native-<version>.dmg`

Om asset saknas visas istället **Open release page**.

## Troubleshooting / Felsökning

### Screen capture fails after update

1. Open **System Settings -> Privacy & Security -> Screen Recording**
2. Re-toggle `Memento Capture` (OFF/ON)
3. If needed, remove and re-add `/Applications/Memento Capture.app`
4. Restart `Memento Capture`
5. Use Setup Hub -> Repair Permissions

### Update installed but app did not relaunch

1. Start app manually from `/Applications/Memento Capture.app`
2. Check latest release notes for known update issues
3. If recurring, open an issue with update logs and macOS version

### Need help?

- Questions and troubleshooting: [GitHub Discussions](https://github.com/owgit/memento-native/discussions)
- Confirmed bugs: [GitHub Issues](https://github.com/owgit/memento-native/issues)
