# Filkollen visual audit

Baseline: `6f31311` (PR #3, the feature-complete backlog branch). Audited 2026-10-23 before any redesign work.

Screenshots of every screen and state are in [`before/`](before/), captured on Roben's MacBook Pro (macOS 27, Swedish region format) by the debug-only snapshot runner (`Filkollen/Debug/SnapshotRunner.swift`, launch with `-FKSnapshotDir <folder>`). Junk, threat and quarantine states use made-up fixture data so nothing personal ends up in this public repo. [`before/README.md`](before/README.md) lists what was left out and why. File names below (`05`, `40`…) refer to those shots.

This is a presentation-layer audit. Where a visual problem also hides safety information, it's called out as **Safety**, because those are the ones the redesign must fix rather than just restyle.

## Summary

The app works and the safety model is solid, but the visual layer is one hand-rolled style ("glass card on a plum gradient") applied to every surface, plus dozens of local decisions. The result reads more like a web dashboard than a Mac utility:

1. **It's dark-only.** `RootView` and `MenuBarView` force `.preferredColorScheme(.dark)`. There is no light mode and no Increased Contrast variant. The light screenshots are the same as the dark ones except Settings and the About panel, which follow the system, so the app has two personalities.
2. **The backdrop is the brand.** Every detail page sits on a plum→indigo gradient with two 400–520 pt blurred circles (blur radius 120–140), re-tinted per section in ten different hues. It's the "AI gradient" look the brief wants to avoid, it shifts the whole window's color on every navigation, and the blur sits behind scrolling content.
3. **No tokens.** Colors, sizes, radii, spacing and opacities are literals at the call site (details below). Nothing guarantees two screens look alike, and nothing adapts to appearance or contrast settings.
4. **Every surface has the same weight.** One card recipe (white 8 % fill, white 12 % stroke, 18 pt radius) is used for hero cards, list groups, list rows, banners, engine status and menu bar stats. Primary and secondary content can't be told apart by depth.
5. **The scan, which should be the signature moment, is a rainbow spinner.** The ring is indeterminate even though the model knows which categories are still running, and results appear all at once with no count-up or settle.

## What the screenshots add

- **Result cards stretch to fill the window** (`05`): at the default size each card is ~370 pt tall with the size pinned to the bottom and ~200 pt of empty glass in the middle.
- **At the minimum window size the numbers break** (`40`): "1,29 GB" and "35,5 MB" wrap onto two lines and Browser & Mail Caches shows "1,4…". The single most important number on each card is the one that truncates.
- **The menu bar shows routine junk in red** (`51`): the Junk mini-card uses a red trash glyph, the same red as a threat. Light mode (`light/` and the forced-dark panel) changes nothing.
- **The sidebar is tinted plum, not translucent** (all): because the window is forced dark and the detail is a gradient, the sidebar reads as part of the custom canvas rather than as macOS chrome.
- **Disk Usage** (`36`) is a single giant terracotta block for Library with slivers beside it; colours are hue-by-index with no meaning, labels only on the largest tile, no drill-down affordance.
- **Empty states are inconsistent** (`31` History is one grey sentence in a huge empty page; `32` Updates uses a 54 pt seal; `11` uses a gradient tile).
- **Review sheet** (`50`): the third category header is cut off mid-row at the bottom edge, and in light mode the custom pink button and gradient icon sit on a native sheet, the clearest view of the two design languages clashing.
- Swedish number formatting ("6,77 GB") already flows through `ByteCountFormatter`; good, the redesign must keep using it.

## 1. Color

| Finding | Where | Notes |
|---|---|---|
| Forced dark appearance | `RootView.swift:17`, `MenuBarView.swift:32` | Settings and About follow the system, so the main window and Settings disagree in light mode. |
| Text colour is `white.opacity(x)` with **13 different opacities** (0.35, 0.4, 0.5, 0.55, 0.6, 0.65, 0.7, 0.75, 0.8, plus fills at 0.08, 0.1, 0.12, 0.15) | all views | No semantic primary/secondary/tertiary. Secondary text at 0.5–0.55 on the plum backdrop is about 4.5:1 at best and drops below AA where the pink glow sits behind it. Ignores Increased Contrast entirely. |
| Primary accent is a pink→purple gradient | `Theme.accent` | Used for the scan button, every primary button, the results total, onboarding step numbers and the review sheet icon. It doesn't follow the system accent, and `AccentColor.colorset` is a third, unrelated purple (#7E6BE1) that only native controls use. |
| Category colours are a rainbow | `JunkCategory.gradient` / `.tint` | Nine two-stop gradients spanning the whole hue wheel (pink→orange, teal→blue, purple→indigo, yellow→orange, grey→blue…). Two categories share purple; tint and gradient disagree for some (System Junk tint is pink, gradient ends orange). Hue carries no meaning. |
| Orange means eleven different things | `foregroundStyle(.orange)` ×11, `.background(.orange)` | Full Disk Access off, stale database, IN USE badge, quarantine file icon, ClamAV signature names, failure reasons, login-item approval, Homebrew missing… Warning colour is diluted. |
| **The safe action looks the most dangerous** | `ProtectionView.swift` threat footer | "Quarantine All" (restorable) gets the red danger gradient pill; "Delete All…" (permanent) gets the quiet ghost button. Per-row it's reversed again: Quarantine is ghost, Delete is a red pill. **Safety:** the visual weight points users at the wrong default. |
| Red on routine screens | `Theme.danger` on Smart Scan/Protection header, menu bar tint `.red` | The menu bar panel's whole backdrop turns red when a threat exists. Effective, but closer to scare-tactic than "unmistakable but calm". |
| Sidebar badges are custom capsules | `RootView.swift` | Red for threats, blue for updates, hand-sized. Native `.badge()` would match Finder/Mail. |

## 2. Typography

| Finding | Where |
|---|---|
| Page titles are `.system(size: 26, weight: .bold, design: .rounded)`, repeated **9 times**, plus 30, 34 and 56 pt one-offs. SF Pro Rounded on every title makes the app feel toy-like next to Finder and System Settings, which use SF Pro. | every page header |
| The results total (`56 pt heavy rounded`) has **no monospaced digits**, so it would jitter if it counted up. Card sizes and sidebar sizes do use `.monospacedDigit()`; review sheet sizes (`.caption`) and quarantine dates don't. | `SmartScanView`, `ReviewSheet` |
| Paths are monospaced in the review sheet and scan status, proportional in category rows and threat rows. Same data, two treatments. | |
| Badges (KEEP, LOW CONFIDENCE, IN USE, MISSING, engine name) are hand-built five times with slightly different fills and no shared component. | `CategoryDetailView`, `ProtectionView` |
| Count strings are concatenated English: `"\(n) items"`, `"\(n) threat(s) found"`, `"\(n) file(s)"`. These will read badly in Swedish and don't pluralise. | many |

## 3. Spacing and layout

- **18 different stack spacings** (0, 1, 2, 3, 4, 5, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28). Seven of them (1, 2, 3, 5, 6, 10, 14, 18, 22, 26) are off a 4-pt grid.
- Page inset is a literal `28` (27 call sites); Smart Scan and onboarding use 40, the review sheet 24, the menu bar 16.
- Card padding: 10, 12, 14, 16, 18 and 22.
- Five different content max-widths (420, 440, 480, 520, 560) for what is the same "centred text column".
- Settings tabs have four fixed heights (560, 440, 500, 400), so the window jumps on every tab switch.
- The minimum window is 940 × 620. At that size Smart Scan results crowd the four cards and the footer (see `40-smartscan-results-min-size.png`).

## 4. Shape and depth

- Corner radii: 18 (cards), 16 (drop zone, **not continuous**: `UninstallerView.swift:45`), 10 (menu actions), 8 (thumbnails), 6 (treemap tiles), and `size × 0.28` for icon tiles (8.4 pt at 30, 15.7 at 56, 30.8 at 110). No scale.
- Buttons are capsules. Native macOS push buttons are rounded rectangles; capsules are one of the strongest "web app" tells.
- Shadows only exist on gradient icon tiles and pill buttons (`black 25 %, radius 10, y 4`), so the most decorative elements float highest.
- `.ultraThinMaterial` bottom bars sit over scrolling lists (category detail, threats, quarantine). Blur behind scrolling content is the most expensive thing to composite and the brief asks to avoid it.

## 5. Iconography

- Category symbols mix circled variants (`trash.circle.fill`, `shippingbox.circle.fill`, `hammer.circle.fill`, `iphone.circle.fill`) with plain ones (`photo.on.rectangle.angled`, `doc.on.doc.fill`, `archivebox.fill`, `globe`), then put them inside a rounded-square gradient tile, so some tiles show a circle inside a squircle.
- The gradient tile (`GradientIcon`) is used at 30, 34, 36, 38, 44, 46, 48, 54, 56, 80, 90, 96 and 110 pt: page headers, cards, list rows, empty states, the review sheet and the menu bar. Other empty states use a plain 54 pt grey glyph instead. No rule decides which.
- No rendering mode is set anywhere, so multicolour-capable symbols render flat white.
- Row actions use `eye` for Quick Look (fine) and `magnifyingglass` for Show in Finder. A magnifying glass reads as Search on macOS; Finder's own reveal glyph is an arrow or folder.
- Symbol sizes aren't tied to text styles; most are `.font(.system(size: size * 0.48))` from the tile.

## 6. Hierarchy and clutter, screen by screen

**Onboarding** (`01`). A single screen of three text steps. The "Access granted, you're all set!" label can **never be seen**: `showOnboarding` turns false the instant access is detected, so RootView swaps to the main view in the same frame. The relaunch hint, Continue link, Finder button and Settings button compete at similar weight.

**Smart Scan idle** (`03`). A 150 pt pink pulsing circle with "Scan" in it, glowing forever. The pulse ignores Reduce Motion (`ProgressRing.swift:59`). Category chips underneath are inert.

**Scanning** (`04`). Rainbow angular gradient spinning at 1.4 s/turn; nothing shows which of the three categories running in parallel are done. The status path is the most interesting live detail but is styled as 55 % caption.

**Results** (`05`). Three numbers compete: the 56 pt total ("of junk found"), the selected amount in the button, and the reclaimable note. The headline is "junk found", not what the user gains. Four equal cards with no item count, no "ready/needs a look" status and a "Details" text link. The one primary action sits at the bottom edge next to an equal-height "Start Over".

**Cleaning / Done** (`06`–`08`). The cleaning state reuses the spinner in teal. Done is a 110 pt gradient checkmark, then "Undo" and "Open Trash" as ghost capsules and "Done" as the pink pill; the Undo the user most needs is the weakest-looking button. After cleaning from a category page, ReviewSheet jumps to the Smart Scan section to show this screen, which loses the user's place.

**Category detail** (`10`–`12`). Groups are collapsed by default (except duplicates), so the page is a list of totals and the user has to expand every group to see what's in it. No explanation of what this junk is or whether it comes back. The header repeats the sidebar size. Rows put two plain icon buttons and three possible badges on one line. There is no inspector.

**Review sheet** (`50`). **Safety:** each category is capped at 500 rows (`ReviewSheet.swift:58`, "…and N more"), but the Move button counts and trashes all of them, so on a big scan the user is asked to confirm items they can't see. Rows show only the path: no name emphasis, no file icon, and no KEEP / LOW CONFIDENCE / IN USE badges even though those exist on the category page. Sizes aren't monospaced. Cancel is a native button, the confirm button is a pink capsule, in the same row.

**Protection** (`20`–`26`). The header shield goes red when there are threats; good signal. The idle page puts two engine cards, an inline SecureField and a 150 pt pulsing Scan circle on one screen. Threat rows have engine pill, report link, size, reveal, Quarantine and red Delete on one line, and the bottom bar's colours are inverted (see Color). Quarantine rows show the full SHA-256 prefix inline at caption size.

**Uninstaller** (`30`, kept out of the repo). App list on a black 18 % strip next to the gradient: a third surface colour. The drop-target state is a dashed white stroke at 60 %, not continuous. The empty detail is a 90 pt orange→pink tile.

**History** (`31`). Swift Charts with default styling on the dark backdrop. Records are glass cards with a cyan text button for Put Back.

**App Updates, System Overview, Startup Items, Time Machine, Disk Usage** (`32`–`36`; `34` kept out of the repo). Same header recipe, each in its own gradient. Overview's rings use a 15 pt rounded percentage. Disk Usage's treemap tiles have a 6 pt radius and hover, but no tooltip and no drill-down transition.

**Settings** (not captured this round; reviewed from code). Native `Form(.grouped)`, the best-looking part of the app. Issues: fixed heights per tab, caption-orange/red status text instead of inline status rows.

**Menu bar** (`51`, `52`). A 340 pt panel that recreates the full plum backdrop with blurs, forced dark, holding three stat bars, three mini cards, four actions and a footer. Dense; the panel turns red with a threat. The Empty Trash two-click arm is clever but only signalled by a red tint and a text change.

**About** (`70`). The stock panel. Fine, but the app icon is still the scaffold icon.

## 7. Motion and transitions

- Animations are ad hoc: one spring on Smart Scan phase change (`response 0.5, damping 0.85`), `easeInOut` defaults elsewhere at 0.2, 0.4, 0.5, 0.6 s and the RootView default. No named curves.
- Navigation is a hard cut while the backdrop tint crossfades over 0.6 s, so the colour moves and the content doesn't.
- Phase changes on Smart Scan cross-fade whole screens; nothing carries over (the ring doesn't become the result, tiles don't become detail headers).
- Two infinite animations (spinner, scan button pulse). Only one respects Reduce Motion. Nothing checks Reduce Transparency.
- No number counting, no staggered appearance, no hover lift on cards, no press feedback except the pill button's 0.96 scale.

## 8. Missing and weak states

- **Disabled custom buttons look enabled.** `PillButtonStyle` and `GhostButtonStyle` never read `isEnabled`, so "Review & Clean Zero KB" and a Scan button with no database look tappable (`Theme.swift`). SwiftUI doesn't dim custom `ButtonStyle`s for you.
- **No hover or focus states** on cards, ghost buttons or pill buttons. Custom button styles also lose the system focus ring, so keyboard users can't see where they are.
- No loading placeholders: bare `ProgressView()` for the app list, App Trust and Disk Usage.
- No shared banner/error component; errors are inline orange or red labels in five different layouts.
- No toast or inline confirmation after a cleanup from a category page (it jumps to the Smart Scan done screen instead).
- No empty state for History filters, Startup Items with nothing to show, or Updates with every source disabled beyond a sentence.

## 9. Platform fit

- The sidebar is a native `NavigationSplitView` sidebar while the detail is a custom canvas, so two design languages sit side by side. The translucent sidebar has nothing behind it to pick up.
- The unified toolbar has no title, no subtitle and no items. On macOS 13–15 it's an empty strip; on macOS 26 there's nothing for Liquid Glass to apply to.
- No keyboard shortcut hints in the UI (the Scan menu has ⌘R and ⇧⌘R, but nothing on screen says so). Tooltips exist on some icon buttons only.
- The app icon is the scaffold's icon and doesn't follow the current macOS icon grid.

## What's already good and should survive

- The safety copy is honest and specific ("About 1.2 GB comes back once you empty the Trash; the rest is shared with other files"). Keep every word of that meaning.
- Settings is native and well organised.
- KEEP, LOW CONFIDENCE and IN USE as explicit badges, never-preselected rules and the two-step permanent delete are exactly right; they just need consistent, more visible presentation.
- Accessibility labels on icon-only buttons are already thorough.
