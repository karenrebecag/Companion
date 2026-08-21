# Design system

The UI is a first-class part of this product, not decoration. The rule that
governs it: **simplification is only valid where nothing is lost visually.**
Parity with the prototype is the floor, not the ceiling.

Everything here is built in-house: no UI framework, no icon package, no
component library. The one binary dependency in the project is Rive, and it
exists solely for the mascot (see ADR 003).

## Foundations

### Color

Semantic roles resolve per theme; views never name a raw colour.

| Role | Light | Dark |
|---|---|---|
| `background` | neutral 50 | neutral 950 |
| `surface` | white | neutral 900 |
| `surfaceOverlay` | white | neutral 850 |
| `foreground` | neutral 950 | neutral 50 |
| `mutedForeground` | neutral 600 | neutral 400 |
| `border` / `borderStrong` | neutral 200 / 300 | neutral 800 / 700 |
| `accent` | user's chosen highlight | same |
| `destructive` | red | red |

The accent is user-selectable (Settings → Appearance). Contrast of every
role pair is asserted by test against WCAG AA — a token change that drops a
pair below 4.5:1 fails the suite, in both themes.

### Typography

Five faces, chosen in Settings: Inter (bundled, OFL), TBJ Interval,
Hypodermic, Gadey, and the system serif. The proprietary ones live only on
the author's machine — their metadata says All Rights Reserved, so the repo
ships Inter and the app degrades to it, then to the system font. Faces are
registered at launch from the bundle, Application Support and ~/Library/Fonts.

### Spacing

One scale (`Space.x1` … `Space.x8`). A gate fails the build if a numeric
padding literal appears in `Sources/CompanionUI/`: the scale is not a
suggestion.

### Elevation

Named steps rather than ad-hoc shadows, with their own opacity in dark mode
(a shadow tuned for light backgrounds disappears on dark ones).

### Motion

Named durations — fast (0.15 s), base, panel (0.3 s), enter, layout — plus
shared curves and springs. Everything honours the system's reduce-motion
setting: state still changes, it just stops animating.

## Components

| Component | What it is |
|---|---|
| `Dropdown` | Anchored panel with hover states and keyboard nav. Replaced the system `Menu` — see the note below. |
| `Controls` | Buttons (primary / secondary / destructive / ghost), fields and toggles with their four states and a visible focus ring. |
| `Pressable` | Press feedback shared by the interactive pieces. |
| `Shimmer` | The sheen over status text while the model thinks. |
| `Halftone` | The identity texture, used sparingly. |
| `Icons` | SF Symbols at tokenised weights and scales. |
| `Toasts` | Ephemeral notices, top-right, expiring on an injected clock. |
| `SyntaxHighlighter` | Paints the tokens produced by `Syntax` in Core. |
| `Orb` / `OrbLayers` | Voice-state visual, driven by pure appearance logic. |
| `Mascot` | The Rive character on first run. |
| Cards | `MapCard`, `GalleryCard`, `SourcesCard` and the job report. |

### Why the dropdown is ours

Wave 5a swapped the prototype's own dropdown for the system `Menu` "to move
faster". That was exactly the kind of simplification with visual loss the
governing rule forbids, and Wave 6b reverted it. Recorded here so the trade
is not made again by accident.

## Adding a component

A new component lands with its section in this file. What cannot be seen in
a test — the look — is reviewed by opening the app; the tests cover the
decisions (which variant, which state, which colour), never the pixels.
