# Updating Memento Native

This guide is for users updating from an older version.

## Quick update (recommended)

1. Quit both apps:
   - `Memento Capture`
   - `Memento Timeline`
2. Open the latest DMG from Releases.
3. Drag **both** apps to `/Applications` and choose **Replace**.
4. Launch `Memento Capture` first, then `Memento Timeline`.

## Will my data be kept?

Yes. Your captures and database are stored outside the app bundle.

- Default location: `~/.cache/memento`
- If you changed storage location in Settings, your custom path is used.

Replacing `.app` files in `/Applications` does not delete captured data.

## If Screen Recording stops working after update

For some unsigned/ad-hoc updates, macOS may require re-approval.

1. Open **System Settings** -> **Privacy & Security** -> **Screen Recording**
2. If `Memento Capture` is listed but not working:
   - toggle it OFF then ON, or
   - remove it and add `/Applications/Memento Capture.app` again
3. Restart `Memento Capture`

You can also use the in-app guide:
- `Memento Capture` menu bar icon -> `Permissions...`

## Notes for this release

- Search now loads full history for queries (not just recent window).
- Older search hits now jump to valid screenshots more reliably.
- Storage path changes migrate existing data automatically.

