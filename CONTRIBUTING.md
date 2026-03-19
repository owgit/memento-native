# Contributing to Memento Native

Thanks for contributing.

## Development setup

```bash
git clone https://github.com/owgit/memento-native.git
cd memento-native

cd MementoCapture && swift build
cd ../MementoTimeline && swift build
```

## Coding and quality rules

- Prefer small, focused PRs
- Keep behavior changes explicit in PR description
- Run local builds for both targets before opening PR
- For user-facing docs, keep critical sections in SV/EN where relevant
- Keep release-related changes synchronized (`README`, `CHANGELOG`, release docs)

## Pull request requirements

- Use the PR template checklist
- Link issue/discussion when relevant
- Include test/verification notes
- Update docs when behavior changes
- Add changelog entry for release-facing changes

## Commit convention

Use clear, imperative commit messages. Example:

- `Improve updater relaunch reliability`
- `Add release guard workflow`

## Release convention

Follow [docs/RELEASING.md](docs/RELEASING.md). Public releases must include notarized DMG asset.

## Support routing

- Q&A and troubleshooting: [Discussions](https://github.com/owgit/memento-native/discussions)
- Confirmed bugs/features: [Issues](https://github.com/owgit/memento-native/issues)
