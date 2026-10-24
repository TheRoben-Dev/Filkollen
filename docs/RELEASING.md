# Releasing Filkollen

Filkollen ships outside the App Store: Developer ID signed, Hardened Runtime, notarized, as a DMG. Updates go through Sparkle 2, which stays switched off until you configure it.

## Quick path: GitHub Actions (no Developer ID yet)

1. `scripts/bump-version.sh 0.3.0`, write `docs/release-notes/0.3.0.md`, commit, and merge to main.
2. On GitHub: **Actions › Release › Run workflow** on `main`.

The workflow tests, builds a universal ad-hoc signed app, packs `Filkollen-<version>.dmg` plus a `.sha256`, tags `v<version>` and publishes the release with the notes file as its body. It refuses a version that's already tagged. These builds aren't notarized, so users approve the first launch in Privacy & Security (the notes say how). Once you have a Developer ID, use `scripts/release.sh` below and upload its DMG instead.

## One-time setup

1. **Certificate.** In Xcode › Settings › Accounts, create a *Developer ID Application* certificate for your team.
2. **Notarization profile.** Store an app-specific password in the keychain:
   ```sh
   xcrun notarytool store-credentials filkollen-notary --apple-id you@example.com --team-id ABCDE12345
   ```
3. **Sparkle keys** (only if you want in-app updates). From a Sparkle release download, run `bin/generate_keys`. It stores the private key in your keychain and prints the public key. Never commit the private key.
4. **Turn Sparkle on.** In `project.yml`, under the Filkollen target's settings, set:
   ```yaml
   FILKOLLEN_APPCAST_URL: "https://example.com/filkollen/appcast.xml"   # must be https
   FILKOLLEN_SPARKLE_PUBLIC_KEY: "<the public key from generate_keys>"
   ```
   With either empty, Filkollen creates no updater and makes no update requests. Automatic checks default to off; users turn them on in Settings › General.

## Each release

```sh
scripts/bump-version.sh 0.2.0          # sets MARKETING_VERSION, bumps the build, dates CHANGELOG.md
git commit -am "chore(release): 0.2.0" && git tag v0.2.0
TEAM_ID=ABCDE12345 SPARKLE_BIN=~/Sparkle/bin scripts/release.sh
```

`release.sh` refuses a dirty tree, then: `xcodegen generate` → tests → Release archive signed with Developer ID (secure timestamp) → export → `codesign --verify --deep --strict` → notarize and staple the app → DMG with an Applications link → sign, notarize and staple the DMG → `spctl` assessment → SHA-256 (and the Sparkle signature when `SPARKLE_BIN` is set). `SKIP_NOTARIZE=1` does a local dry run.

Then upload the DMG (for example to a GitHub Release) and update the appcast, either by hand with the printed `sparkle:edSignature` and length, or with Sparkle's `bin/generate_appcast` over a folder of DMGs.

## Checks before publishing

- `codesign -dv --verbose=4 build/release/Filkollen.app` shows your team and `flags=0x10000(runtime)`.
- `xcrun stapler validate build/release/Filkollen-<version>.dmg` passes.
- Open the DMG on another Mac (or a fresh user) and launch: no Gatekeeper warning.
- Full Disk Access survives the update (same bundle ID and team, so it should).
