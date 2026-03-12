# App Store-beredskap (Memento Native)

Det här är en praktisk checklista för att få **Memento Capture** + **Memento Timeline** redo för Mac App Store.

## 1) Affärs- och distributionsbeslut (först)

- [ ] Bestäm distributionsmodell:
  - **Mac App Store (MAS)** för enklare installation/uppdatering via Apple.
  - Alternativt behåll nuvarande **DMG + notarization** för direktdistribution.
- [ ] Om MAS: planera att apparna publiceras som separata appar eller i samma produktfamilj.
- [ ] Om ni vill ta betalt: bekräfta att licensmodellen är kompatibel med App Store-upplägg.

## 2) Compliance-gap mot nuvarande repo

Nuvarande projekt är optimerat för DMG-distribution (Developer ID + notarization), inte MAS.

- [ ] Ersätt releaseflödet som idag bygger DMG med ett MAS-flöde (Xcode archive + App Store Connect).
- [ ] Säkerställ App Sandbox-konfiguration för båda apparna (entitlements för MAS).
- [ ] Gå igenom automation/Apple Events-användning och verifiera att behovet och motiveringarna håller i review.

## 3) App Sandbox & entitlements (kritisk)

Miniminivå för MAS:

- [ ] Aktivera **App Sandbox** (`com.apple.security.app-sandbox`) för båda appar.
- [ ] Lägg till endast strikt nödvändiga capability-entitlements.
- [ ] Flytta lagring från `~/.cache/memento/` till sandbox-kompatibel plats (Application Support + ev. App Group).
- [ ] Verifiera att datautbyte mellan Capture och Timeline fungerar i sandbox-läge.

## 4) Behörigheter och transparens

- [ ] Behåll tydlig `NSScreenCaptureUsageDescription` (finns redan) och förbättra texten till App Review-nivå.
- [ ] Om ni använder Accessibility/Automation i vissa flöden: visa tydligt varför, när och hur det används.
- [ ] Lägg till in-app integritetstext med exakt vad som lagras lokalt och hur man raderar data.
- [ ] Säkerställ att clipboard-funktionen är opt-in (detta finns redan) och förklara i onboarding.

## 5) UI/UX enligt Apple-guidelines

Återanvänd befintliga ytor istället för ny UI:

- [ ] **Setup Hub**: gör den till central plats för permissions, felsökning och integritetsförklaringar.
- [ ] **Action Hub/Command Palette**: återanvänd för hjälplänkar, “vad samlas in”, data-export/radering.
- [ ] Menyrads-UI: håll statuschips tydliga (recording/paused/permission) och med konsekventa states.
- [ ] Onboarding: lägg till tydlig “Before you start”-sektion med samtycke/opt-in för känsliga funktioner.

## 6) Kvalitetssäkring före submission

- [ ] Kör regression på clean macOS-konto (utan tidigare TCC-rättigheter).
- [ ] Verifiera uppgraderingsflöde från äldre versioner till ny sandboxad lagring.
- [ ] Lägg till testmatris för capture, OCR, sök, auto-pause, private/incognito-detektion.
- [ ] Kontrollera energiförbrukning/minnesprofil i release build.

## 7) App Store Connect-material

- [ ] App Privacy-enkät: beskriv lokalt lagrad data korrekt.
- [ ] App Review Notes: förklara varför screen capture behövs och hur användaren kontrollerar funktionen.
- [ ] Skärmdumpar + metadata för båda apparna.
- [ ] Support-URL, privacy policy-URL och kontaktinformation.

## 8) Rekommenderad leveransplan (i ordning)

1. **Sandbox-spike i branch**: få båda appar att fungera med sandbox + gemensam lagring.
2. **UX-pass i Setup Hub**: finslipa permission-flöden och copy för review.
3. **Intern TestFlight (macOS)**: verifiera install/uppgradering/search/capture.
4. **Submission** med tydliga Review Notes och privacy-texter.

## Snabb bedömning

Projektet är nära tekniskt moget för distribution, men för **Mac App Store** krävs framför allt:

1. Sandbox-anpassning,
2. lagringsflytt till sandbox-kompatibla paths,
3. tydligare permission/privacy-UX för review.

Med fokus på återanvändning av befintliga flöden (Setup Hub, Action Hub, menyradsstatus) kan ni nå App Store-kraven utan stor ny UI-utveckling.
