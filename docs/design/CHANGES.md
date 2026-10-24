# Redesign changes

What changed on each screen in the "Lagom" redesign ([DIRECTION.md](DIRECTION.md)), and why. Functionality, safety rails, the review flow and data models are unchanged; every badge and number that informs a removal is still shown, and in a few places it is shown more.

## Everywhere

- **Follows the system appearance.** The forced dark mode, plum gradient backdrop and glass cards are gone. Pages sit on the window background with solid surface cards, a hairline border and a soft shadow in light mode. Light, dark and Increased Contrast all come from the asset catalog.
- **One accent.** Buttons follow the system accent. Settings › General › "Use Filkollen's teal" switches them to Fjord teal. Red is used only for real danger: threats, permanent delete and Empty Trash.
- **Rounded-rectangle buttons** like native push buttons, replacing gradient capsules. Every custom control has hover, pressed, keyboard-focus, disabled and loading states.
- **Type scale.** SF Pro for words. SF Pro Rounded only for the big numbers. Monospaced digits for every size and count, and SF Mono for paths, truncated in the middle so the file name survives.
- **Category tiles** in three families: rebuilt automatically, left behind, and your own files. Each family has its own tint, at three sizes (20 in the sidebar, 32 on cards, 56 in headers).
- **Bottom action bars** are solid, with a top separator. There is no blur behind scrolling lists.
- **Badges** for Keep, Low confidence, In use, Quarantined, Missing, Unsigned and Notarized. They look the same and carry the same tooltips in every list.
- **Motion** uses three spring tokens. Reduce Motion replaces movement with short crossfades.

## Screens

| Screen | Before | After |
|---|---|---|
| Window and sidebar | Forced dark mode, hidden toolbar background, SF Symbols in mixed styles, red/blue count capsules | System appearance; category tiles in the sidebar; threat and update counts as small pills; the Full Disk Access notice is a tinted card with an explanation |
| Onboarding | Gradient icon, glass card, and a one-line "granted" label that was replaced at once | Native layout with numbered steps in a card. When access arrives, a checkmark and "Access granted" are shown for 1.4 s before hand-off, with a haptic and a VoiceOver announcement |
| Smart Scan, idle | Pulsing gradient circle button | Quiet ring outline, one primary **Smart Scan** button (Return / ⌘R), and the covered categories as small tiles |
| Smart Scan, scanning | Rainbow spinner | One ring segment per category, filling only when that scanner really finishes, with a travelling light on the unfinished track. The current category sits in the centre, and the live path is shown readably below |
| Smart Scan, results | 56 pt gradient total, glass cards | The ring settles into one Fjord ring with a gentle spring and a haptic. The total counts up inside it. "X selected to clean" and the reclaim note sit separately. Category cards (size, item count, status such as "2 need a look") rise in with a 40 ms stagger. One primary **Review X…** button |
| Smart Scan, done | Gradient checkmark tile | Success or warning state, a banner after Put Back, and the failure list in a card |
| Review sheet | Showed at most 500 rows per category ("…and N more"); paths only; no badges | **Every** selected item in a virtualised list, with name, folder, Finder icon, size and the same badges as the category page. Category headers show item counts. Solid action bar showing the count and size |
| Category pages | Gradient header, KEEP / LOW CONFIDENCE / IN USE capsules, glass group cards | Page header with tile and counting total; a family note explaining whether these files come back; group cards that lift on hover and flag groups containing in-use or low-confidence items; file rows with badges; real empty and not-scanned states |
| Malware Scan | Green/red gradient header; Quarantine as a ghost button next to a red Delete pill | Calm-to-alert header (Protected, Needs attention, Threat found) using the same layout in every state. **Quarantine is the primary action**; Delete… is secondary and still behind a confirmation. Stale database and errors appear as banners |
| Quarantine | Orange lock icons, MISSING capsule | Rows with Quarantined and Missing badges and a readable origin path. Only "Delete All Quarantined…" is red |
| App Trust | Opacity-tinted text capsules | Signature badges (broken/unsigned in red, Developer ID in amber, Notarized/App Store/Apple in green) and placeholder rows while checking |
| App Uninstaller | Dark sidebar strip, dashed white drop outline | Under-page sidebar with placeholder rows while loading, an accent-coloured drop highlight, file rows with badges, and a review sheet that shows in-use and low-confidence badges |
| History | Teal/indigo gradient bars | Fjord bar chart, record cards, a put-back banner, and "Empty Filkollen's Items from Trash…" as the one destructive button |
| App Updates | Gradient pill button | Primary button with an inline loading state, source cards with dividers, info banners for missing Homebrew or mas, and empty states |
| System Overview | Gradient rings | Gauges in brand colour, turning warning above 75 % and danger above 90 %. The Trash size counts up |
| Startup Items | Coloured opacity capsules | Section cards with counts, consistent badges, and selectable labels and paths |
| Time Machine | Gradient icon, glass cards | Page header and explanation card |
| Disk Usage | Rainbow hue treemap | Calm category tints that keep white text readable (folders solid, files a step lighter), a hover outline, folder or file glyphs, and a shimmer while measuring |
| Menu bar panel | Forced dark gradient backdrop | System panel material, the same tokens as the window, and linear bars using the same 75/90 % colours |
| Settings | 520 pt width, system colours | Token width and status colours |

## Removed

`Theme`, `BackdropView`, `GlassCard`, `PillButtonStyle`, `GhostButtonStyle`, `GradientIcon`, `ScanningRing`, `BigScanButton`, `Thumbnail`, and `JunkCategory.gradient` / `.tint` / `.symbol`. The replacements are `DS.*`, `DSTile` and `DSFileIcon`.
