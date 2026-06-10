# AGENTS.md - Memento Native

## Operating Rules

- ASK BEFORE COMMIT OR PUSH.
- Keep changes scoped and easy for Claude Code to review.
- Always check `.cursor/*` project rules when present. If `.cursor/` is missing, use `.cursorrules` and this file.
- Use Context7 MCP before code changes to check current docs and avoid stale API assumptions.
- Use a specialized subagent only when it is clearly better for the task; otherwise continue in the main thread.
- For web/docs UI, keep UX mobile-first and responsive.

## Release Memory

The verified release/update path from the successful 2026-05-01 flow is:

1. If the main workspace is dirty or behind, create a clean release worktree instead of pulling or resetting local work.
2. Update version metadata in `build-dmg.sh`, `project.yml`, `MementoCapture/bundle.sh`, `MementoTimeline/bundle.sh`, README references, and `CHANGELOG.md`.
3. Run tests/builds for both packages, then `git diff --check`.
4. Only build a DMG when the user explicitly asks for a release or DMG.
5. Build with `./build-dmg.sh X.Y.Z`; the result must be signed/notarized with Developer ID team `7GNHCUW7HN`.
6. Create or update the GitHub release with `Memento-Native-X.Y.Z.dmg` attached.
7. Verify the release asset exists and its GitHub digest matches the local SHA.
8. Download the release DMG again, compare SHA, mount it, and verify the mounted app:
   - version/build from `Info.plist`
   - TeamIdentifier `7GNHCUW7HN`
   - `codesign --verify --deep --strict --verbose=2`
   - `spctl --assess --type execute --verbose=4`
   - main executable is `Memento Capture.app/Contents/MacOS/Memento Capture`

## Local Update Path

For local update testing, use the signed/notarized DMG and replace the app bundle cleanly:

1. Quit `Memento Capture`.
2. Mount the verified DMG.
3. Remove `/Applications/Memento Capture.app`.
4. Move the mounted `Memento Capture.app` into `/Applications`.
5. Verify installed version/build, TeamIdentifier, codesign, Gatekeeper, then launch.

Do not install release candidates by copying SwiftPM build outputs into an existing app bundle.
Do not use `MementoCapture/bundle.sh` for release-update verification.
Do not ad-hoc sign release/update candidates.

## Updater Signing Pitfall

Do not validate TeamIdentifier with `codesign ... | grep -q ...` under `set -euo pipefail`.

`grep -q` can exit early, close the pipe, and make `codesign` fail with SIGPIPE. This caused false updater errors like:

- `Downloaded DMG is not signed by the expected team`
- `Memento Capture.app is not signed by the expected team`

Capture command output first, then test it with shell pattern matching or another non-SIGPIPE-prone check. Users already on an updater with this bug may need one manual install before future auto-updates work.
