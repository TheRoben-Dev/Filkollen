# Before screenshots

Captured 2026-10-23 on a 16" MacBook Pro (M1 Max), macOS 27.0.1, Swedish region format, from `main` at `bb88700` plus the debug snapshot runner (`e819779`). Window content 1180 × 760 pt, downscaled to 1×.

Regenerate with a Debug build:

```sh
build/Build/Products/Debug/Filkollen.app/Contents/MacOS/Filkollen -FKSnapshotDir ~/Desktop/shots
```

- **dark/** is the full set. Junk, threat and quarantine states use fixture data.
- **light/** only holds the shots that actually change in light mode (`50` review sheet, `70` About). The main window and menu bar force dark appearance, so their light captures were pixel-identical and are left out (see AUDIT.md §1).
- Not committed because this repo is public: `30-uninstaller` and `34-startup-items` list the apps installed on Roben's Mac. They're in the project's shared files instead.
- Missing: `27-protection-app-trust` captured blank (the runner shot it mid-redraw) and Settings wasn't found by the runner on macOS 27. Both are fixed in the runner before the after set.
