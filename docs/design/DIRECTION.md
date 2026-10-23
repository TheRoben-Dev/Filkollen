# Design direction: "Lagom"

*Approved by Roben on 2026-10-23 with Fjord teal as the brand accent. Implemented as tokens in `Filkollen/DesignSystem/`; final values in the asset catalog and `scripts/design-colors.py`.*

Filkollen is a Swedish tool that looks after your files. The direction takes that literally: **lagom**, just the right amount. It should feel like it was made by the people who made Finder and System Settings, then given one moment of real craft where it matters: the scan.

It replaces the current plum-gradient, glass-card, capsule-button look (see [AUDIT.md](AUDIT.md)) with a native, appearance-aware system built from tokens.

## Mood

Calm, precise, trustworthy. A well-made Nordic hand tool: quiet surfaces, good materials, nothing shouting, and the confidence to leave space empty. The user should feel *looked after*, never alarmed and never sold to.

Three words to test every screen against: **quiet, exact, warm**.

- *Quiet*: system backgrounds, one accent, no ambient decoration, motion only when something is happening.
- *Exact*: numbers that don't jitter, paths you can read, sizes that tell the truth (selected vs. what actually comes back).
- *Warm*: friendly copy, soft continuous corners, SF Pro Rounded reserved for the numbers people care about, a satisfying settle when work finishes.

## Color strategy

**Follow the system.** Light, dark and Increased Contrast, all three, from asset-catalog colours. The forced dark mode goes away. The full-bleed gradient backdrop goes away; content sits on the standard window background like Finder's.

**One accent, and it's the user's.** Interactive colour follows the system accent colour by default. Filkollen ships a brand accent, **Fjord** (a deep, slightly green teal), that users can pick in Settings, and that the app icon and the signature ring use.

| Token | Light | Dark | Use |
|---|---|---|---|
| `accent.brand` (Fjord) | #0D757E | #45B8C1 | Icon, scan ring, brand moments. Opt-in for controls. |
| `success` | #22784A | #4CC38A | Clean, done, protected. |
| `warning` | #8E5F00 | #E5A93B | Needs a look: low confidence, stale database, in use. |
| `danger` | #C2343A | #FF6B6B | Threats and permanent deletion only. |
| `info` | system blue | system blue | Neutral notes, links. |

Text, separators, backgrounds and surfaces map to the system's semantic colours (`labelColor`, `secondaryLabelColor`, `separatorColor`, `windowBackgroundColor`, `controlBackgroundColor`, `underPageBackgroundColor`) wrapped as tokens, so they adapt to accessibility settings for free. Hex values above are starting points; every value is at least 4.5:1 on the window background in its theme, and Increased Contrast variants reach 7:1 (`DesignTokenTests`).

**Category tints have meaning, not a rainbow.** Nine hues become three families, at the same muted lightness and saturation, so they sit together:

| Family | Tint | Categories | Why |
|---|---|---|---|
| *Regenerates* | slate blue → steel | System Junk, Browser & Mail Caches, Developer Junk | Safe to remove; apps rebuild it. Cool and quiet. |
| *Left behind* | teal → sea green | App Leftovers, Old Installers, iOS Backups & Firmware | Belonged to something that's gone or done. |
| *Your own files* | sand → amber | Duplicate Photos, Duplicate Files, Large & Old Files | It's your data; warmth says *have a look first*. |

Within a family, categories differ by a small hue step and their symbol. Tints appear only in the icon tile, a thin accent on the tile/card, and the matching ring segment; never as page backgrounds.

**Protection: calm to alert.** One palette with three states, all using the same layout so nothing jumps:

- *Protected*: sage green shield, "No known threats · database updated 2 days ago".
- *Needs attention*: amber, for a stale database or ClamAV missing signatures.
- *Threat found*: a solid `danger` shield and one banner with the count. No red page tint, no pulsing, no red menu-bar panel. The menu bar icon gets a small red badge dot.

**Red is reserved.** `danger` is used only for threats, Delete Permanently and Empty Trash. Routine junk is never red, and the safe choice (Quarantine) is always the visually primary button next to Delete.

## Typography

SF Pro throughout, using the system text styles so sizes match native apps.

| Token | Spec | Use |
|---|---|---|
| `display` | SF Pro Rounded, 44 / bold, monospaced digits | The headline total ("6.4 GB"). |
| `numeric.large` | SF Pro Rounded, 28 / semibold, monospaced digits | Category totals, ring percentage. |
| `title` | SF Pro, 22 / semibold (`.title2`) | Page titles. Not rounded. |
| `headline` | `.headline` | Card and group titles. |
| `body` | `.body` | Everything else. |
| `callout` | `.callout` | Explanations under titles. |
| `caption` | `.caption` | Metadata, badges. |
| `numeric` | `.body`/`.callout` + `.monospacedDigit()` | Every size and count, everywhere. |
| `path` | SF Mono, `.caption`, middle truncation | File paths in rows, inspector, review. |

Rounded is used only for numbers, which keeps the friendliness where people look and the native feel everywhere else. All counts move to localised, pluralised strings (`^[\(n) item](inflect: true)` / String Catalog plurals) so Swedish works.

## Depth and materials

Three elevation levels, each a recipe that works in both themes:

1. **Surface** (cards, tiles, groups): `controlBackgroundColor`, 1 pt hairline `separator` border, no shadow in dark, a 1 pt soft shadow in light.
2. **Raised** (hovered tile, popovers, inspector): adds a soft shadow (y 2, radius 8, 8–12 % black) and lifts 2 pt on hover.
3. **Floating** (toasts, the review sheet, the menu bar panel): system window material or sheet chrome with the standard shadow.

**Material rules:**

- Blur is allowed only on system chrome (sidebar, toolbar, menu bar panel, sheets) and small transient overlays (toasts).
- Never behind scrolling content. Bottom action bars become solid surfaces with a top separator.
- macOS 26: toolbar, sidebar and floating controls adopt Liquid Glass via `#available`, content stays solid.
- Reduce Transparency swaps every material for its solid surface token.

**Shape:** continuous corners everywhere, from one scale: 4 (badges), 6 (thumbnails, small controls), 10 (rows, buttons), 14 (cards, tiles), 20 (hero panels). Buttons are rounded rectangles like native push buttons, not capsules.

## Spacing and layout

A 4-pt scale (4, 8, 12, 16, 20, 24, 32, 40, 48). Page insets: 24 for content pages, 32 for hero pages (Smart Scan, onboarding). Fixed widths: sidebar 220 (200–260), inspector 280, readable text column 560. Every container type (page, card, row, sheet, menu bar panel) has one padding token.

## Iconography

SF Symbols only, hierarchical rendering by default, palette rendering inside category tiles (tint + white). One family per context: category symbols all use the same fill/no-circle variant. Symbol sizes come from the text style they sit next to (`.imageScale` / font-relative), not from `size × 0.48`. Gradient tiles shrink to a single job: identifying a category or tool, at three sizes (20 sidebar, 32 rows/cards, 56 headers). Empty states use a composed symbol illustration (e.g. a sparkle over a tray) in hierarchical tint, not a giant tile.

## Motion personality

**Settle, don't bounce.** Things arrive with intent and come to rest; nothing wobbles or loops idly.

| Token | Spring | Use |
|---|---|---|
| `snappy` | response 0.25, damping 0.9 | Press, hover, toggle, selection. |
| `smooth` | response 0.4, damping 0.88 | Layout changes, expand/collapse, navigation. |
| `gentle` | response 0.6, damping 0.82 | The signature settle only. |

UI responses stay under ~400 ms and are always interruptible. Nothing animates unless work is happening or the user did something. One `Motion` namespace honours Reduce Motion by swapping movement for 150 ms crossfades.

## The signature moment: the scan

The one place Filkollen is allowed to show off.

1. **Idle.** A large, quiet ring outline in the brand accent with "Smart Scan" and the shortcut hint (⌘R) as one primary button beneath. The categories it covers are listed as small tiles. No pulse.
2. **Scanning.** The ring splits into one segment per category, each in its family tint. Segments fill from real progress as each scanner finishes, so it's *honest*. A soft light travels along the unfinished track while work is happening (a comet, not a rainbow spinner). The centre shows the category in progress and the live path in SF Mono below the ring, readable, not 55 % grey.
3. **Settle.** When the last segment fills, the ring closes, the segments melt into a single Fjord ring, and the ring scales down slightly and *settles* (one `gentle` spring, a single haptic tick on Force Touch trackpads). The total counts up in `display` digits that never jitter: **"6.4 GB you can safely reclaim"**. The category tiles rise into place with a 40 ms stagger.
4. **Results.** One obvious primary button: **Review 6.2 GB…** Everything else (Start over, per-category detail) is secondary. Tiles show size, item count and a status line ("Ready", "2 need a look").

macOS 14+ uses `keyframeAnimator` for the settle and `phaseAnimator` for the comet; macOS 13 gets the same choreography from `TimelineView` and `withAnimation` springs, so it looks the same, not lesser. macOS 15+ may add a very faint `MeshGradient` glow under the ring at settle; macOS 13–14 use a radial gradient. No gradient backdrop anywhere else. Reduce Motion: segments fill with crossfades, no comet, no scale.

## Three principles

1. **Belongs next to Finder.** Native controls, system colours, sidebar and toolbar first; custom drawing only where it adds meaning (the ring, category tiles, the treemap). If an AppKit control already looks right, use it. *(Apple HIG: deference, clarity.)*
2. **Honest numbers, nothing hidden.** Every number is stable, unit-aware and explains itself; what you select and what you get back are shown as different things. Anything that changes the risk of a removal (KEEP, low confidence, in use, unsigned, quarantined) is a first-class, consistent badge and is visible in every list where that item can be acted on, including the review sheet. Redesign never removes information a user needs before trashing or deleting.
3. **One moment of delight, calm everywhere else.** Motion and colour have to earn their place. The scan is the showpiece; the rest of the app is quiet enough that the showpiece lands.

## What this fixes from the audit

- Light / dark / Increased Contrast, semantic text colours, AA contrast.
- One accent that follows the user, a meaningful category palette, red only for real danger, Quarantine visually primary over Delete.
- A real type scale with SF Rounded only for numbers and monospaced digits everywhere.
- Spacing, radius and elevation tokens; no magic numbers; rounded-rect buttons.
- Disabled, hover, pressed and focus states on every custom control.
- An honest scan ring and a settle moment instead of a rainbow spinner.
- Review sheet shows every item (virtualised list, no 500-row cap) with the same badges as the category page.
- Onboarding gets a visible "access granted" moment before it hands off.

## Questions for you

1. **Brand accent.** Fjord teal as proposed, or keep a toned-down version of today's pink/violet as the brand colour?
2. **System accent by default.** OK that buttons follow your system accent unless you pick Fjord in Settings?
3. **Scope.** Phases 1–6 are a lot. I'd ship them as a stack of PRs (design system → components → screens → motion → platform polish → performance/tests), each building and passing tests, with after-screenshots per screen. Instruments runs on an Intel Mac and a 5K display depend on hardware you have; I'll note anything I can't measure.
