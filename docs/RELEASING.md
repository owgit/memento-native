# Releasing Memento Native

This playbook is the source of truth for public releases.

## 1) Preconditions

- Clean working tree
- Version selected (example: `2.0.5`)
- Signing identity available (`Developer ID Application`)
- Notary profile configured (`MEMENTO_NOTARY` or `memento-notary`)

## 2) Update release metadata

Update before tagging:

- `CHANGELOG.md` with new section: `## [X.Y.Z] - YYYY-MM-DD`
- `README.md` `Latest (vX.Y.Z)` section
- `build-dmg.sh` default version if needed

## 3) Build, sign, notarize, staple

```bash
./build-dmg.sh X.Y.Z
```

Expected output asset:

`dist/Memento-Native-X.Y.Z.dmg`

## 4) Tag and publish release

```bash
git tag -a vX.Y.Z -m "vX.Y.Z"
git push origin vX.Y.Z

gh release create vX.Y.Z --title "vX.Y.Z" --notes-file <notes-file>
```

## 5) Upload DMG asset (mandatory)

```bash
gh release upload vX.Y.Z dist/Memento-Native-X.Y.Z.dmg --clobber
```

## 6) Verify release integrity

```bash
gh api repos/owgit/memento-native/releases/tags/vX.Y.Z --jq '.assets[].name'
```

Must include:

`Memento-Native-X.Y.Z.dmg`

## 7) Validate release guard workflow

Release Guard runs on `release: published` and can be run manually.

Manual run example:

```bash
gh workflow run release-guard.yml -f tag=vX.Y.Z
```

## 8) Final smoke check

- In-app updater on previous version should detect new release
- Dialog should show **Install now** (not only **Open release page**)
- Install path updates `Memento Capture.app` in `/Applications`

## Troubleshooting

If Release Guard fails:

- Missing changelog entry -> add `## [X.Y.Z] - YYYY-MM-DD`
- Missing DMG asset -> upload DMG with expected naming
- README mismatch -> update `Latest (vX.Y.Z)` heading
