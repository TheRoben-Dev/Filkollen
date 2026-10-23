# Contributing to Filkollen

## Setup

```sh
brew install xcodegen
xcodegen generate          # project.yml is the source of truth
open Filkollen.xcodeproj
```

Never edit `Filkollen.xcodeproj` by hand; change `project.yml` and regenerate. On a machine where `xcode-select` points at the Command Line Tools, prefix CLI builds with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

```sh
xcodebuild -project Filkollen.xcodeproj -scheme Filkollen -destination 'platform=macOS' test
```

## Rules

- **Read `docs/SAFETY.md` first.** Never weaken `SafetyGuard`. A new location gets an explicit, minimal allow rule plus tests for it and for the neighbours that must stay refused.
- Junk goes to the Trash after a review sheet. Only malware may skip the Trash, and only after confirmation.
- Deployment target stays macOS 13. Gate newer APIs with `#available` and provide a fallback.
- No network calls except MalwareBazaar updates (and Sparkle for Filkollen itself). No telemetry.
- Scanners read everything through `ScanContext` so they can be tested against fixture trees; see the checklist in `docs/ARCHITECTURE.md`.

## Commits and PRs

- One logical change per commit, [Conventional Commits](https://www.conventionalcommits.org/) (`feat(scope):`, `fix:`, `test:`, `docs:`, `perf:`, `refactor:`, `ci:`, `chore:`).
- Build and run the tests before pushing; `main` must always build and pass.
- Update `CHANGELOG.md` (Unreleased) and the checkboxes in `docs/ROADMAP.md`.
