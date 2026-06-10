# Mac App Store Preparation

This repository now ships as a single direct-distribution macOS app with a notarized DMG. The changes in this branch also prepare the codebase for a future Mac App Store track, but they do not make the app App Store-ready by themselves.

## What is now prepared

- Runtime can detect an App Store distribution and skip GitHub self-update logic.
- Storage can move to an App Group container by setting `MEMENTO_APP_GROUP_IDENTIFIER` during bundle creation.
- The App Store track now uses `SMAppService.mainApp` instead of the old `LaunchAgent` auto-start path.
- The App Store track now pins storage to the App Group container until security-scoped bookmark support exists.
- A single-bundle App Store-style packaging script now builds one `Memento Capture.app` bundle that hosts Timeline as an internal window feature.

## What still blocks Mac App Store submission

- Register the chosen App Group identifier in Apple Developer and use the same value when signing.
- Replace remaining direct-distribution assumptions that are still outside the main runtime path.
- Add a real archive/upload flow for App Store submission rather than only producing a local app bundle.
- Replace remaining direct-distribution docs and support copy with App Store variants where needed.

## Current bundle-time knobs

The existing bundle scripts and `build-dmg.sh` support these optional environment variables:

```bash
MEMENTO_DISTRIBUTION_CHANNEL=app-store
MEMENTO_APP_GROUP_IDENTIFIER=group.com.memento.shared
```

These flags only prepare runtime behavior and shared storage paths. They do not replace proper App Store signing, sandboxing, or archive/upload steps.

To build a single App Store-style app bundle locally:

```bash
./build-appstore-bundle.sh 2.0.4
```

This produces:

```text
dist-appstore/Memento Capture.app
```

This matches the new one-app runtime structure, but it is still not the final submission/upload flow.

## Package and upload flow

For a Mac App Store-style installer package:

```bash
MEMENTO_INSTALLER_IDENTITY="Mac Installer Distribution: Your Name (TEAMID)" \
./build-appstore-package.sh 2.0.4
```

To discover your App Store Connect provider:

```bash
MEMENTO_ASC_API_KEY=YOUR_KEY_ID \
MEMENTO_ASC_API_ISSUER=YOUR_ISSUER_ID \
./list-appstore-providers.sh
```

To list macOS apps for a provider and find the numeric Apple app ID:

```bash
MEMENTO_ASC_API_KEY=YOUR_KEY_ID \
MEMENTO_ASC_API_ISSUER=YOUR_ISSUER_ID \
MEMENTO_PROVIDER_PUBLIC_ID=YOUR_PROVIDER_ID \
MEMENTO_FILTER_BUNDLE_ID=com.memento.capture \
./list-appstore-apps.sh
```

To upload the package:

```bash
MEMENTO_ASC_API_KEY=YOUR_KEY_ID \
MEMENTO_ASC_API_ISSUER=YOUR_ISSUER_ID \
MEMENTO_PROVIDER_PUBLIC_ID=YOUR_PROVIDER_ID \
MEMENTO_APPLE_APP_ID=1234567890 \
./upload-appstore-package.sh 2.0.4
```

Notes:

- `build-appstore-package.sh` can create an unsigned package for local testing if `MEMENTO_INSTALLER_IDENTITY` is not set, but that package is not uploadable.
- The app bundle itself should be signed with an App Store-valid app identity before upload, typically `Apple Distribution` or `Mac App Distribution`, depending on your certificate setup.
- Apple’s `altool` on this machine supports `--upload-package`, `--list-providers`, and `--list-apps`.

## Apple documentation used for this prep

- App Sandbox: <https://developer.apple.com/documentation/security/app-sandbox>
- Configuring the macOS App Sandbox: <https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox/>
- SMAppService: <https://developer.apple.com/documentation/servicemanagement/smappservice>
- Updating helper executables: <https://developer.apple.com/documentation/servicemanagement/updating-helper-executables-from-earlier-versions-of-macos>
- App Group container access: <https://developer.apple.com/documentation/foundation/filemanager/containerurl(forsecurityapplicationgroupidentifier:)>
