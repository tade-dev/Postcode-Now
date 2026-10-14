# PostcodeNow — The Reveal

Design spec for the motion and interaction layer.
Status: approved for planning. Date: 2026-10-14.

## Why

PostcodeNow is a one-shot utility. A user opens it, reads a postcode, shares
or copies it, and leaves. The entire session is a few seconds long. There is
no room for a feature to be memorable, so the *experience* has to be.

Today the app's signature moment — the postcode settling — lasts 0.65s:

```
outcode 0.12s + beat 0.05s + incode 0.14s + CTA spring ≈ 0.65s
```

That is over before the eye has focused. There is nothing to remember.

Worse, `RootView` switches on `model.phase` with no transition at all. The
locate pulse ring vanishes and the postcode is abruptly present. The app's
most important instant is a hard cut.

This spec replaces that cut with one continuous performance.

## What we are building

**The principle: each act causes the next.** Nothing fades out while
something else fades in. One thing becomes another.

The locate phase stops being dead time. Today the pulse ring is a spinner —
something to look at while Core Location works. If the ring *transforms into*
the postcode, the 1–2s wait becomes tension that the reveal resolves. The
wait joins the performance instead of taxing it.

### Act 1 — Searching (loops; 0.5s to 5s, however long the fix takes)

Three concentric rings that scan rather than spin. Each expands outward from
centre and dissolves at the edge on a staggered 1.6s loop, like sonar.
Wordmark top-left, "Finding your postcode" below.

### Act 2 — The lock (0.00–0.45s)

The fix lands. The rings abandon their loop and snap *inward*, collapsing
into a single tight ring at centre. The caption drops away. One `.rigid`
haptic at the instant of collapse.

Critically, the collapse starts from wherever the rings actually were in
their loop. Snapping them to a canonical start position would be a visible
glitch, so the loop position at handoff is captured and the collapse
interpolates from there. This is what makes the seam invisible.

### Act 3 — The bloom (0.45s to ~1.3s, depending on character count)

The collapsed ring does not fade. It **stretches horizontally into a thin
line**. The line splits and the postcode characters rise out of it, one at a
time, left to right, each settling on a soft spring. Outcode first in bold, a
50ms beat, then the incode. A `.soft` haptic per character landing, so the
code arrives in the hand as well as the eye. The line becomes the text
baseline, then dissolves.

### Act 4 — The wash (0.70–1.20s, overlapping Act 3)

As the first character lands, the place colour floods **upward and outward
from that baseline** — so the colour reads as something the postcode *emits*,
not a background that changed. District name fades in beneath. CTAs rise last.

Ring → line → characters → colour. One object throughout.

### Timing

Measured from the instant the fix lands. `t=0` is the start of Act 2.

| t (s) | Event |
|---|---|
| 0.00–0.28 | Rings collapse inward to lock radius (easeInOutCubic) |
| 0.00–0.18 | Caption fades out |
| 0.26 | **Haptic `.rigid`** — the lock |
| 0.28–0.45 | Lock ring holds, contracts slightly (anticipation) |
| 0.45–0.62 | Ring stretches into line |
| 0.62 + i·0.045 | Character *i* rises (spring response 0.30, damping 0.80) |
| ″ | **Haptic `.soft`** per character landing |
| (after outcode) | 0.05s beat before the incode begins |
| 0.70–1.20 | Wash from baseline outward (easeInOutCubic) |
| 0.95–1.20 | Line dissolves |
| 1.05–1.30 | "Nearest postcode" and district fade and rise |
| 1.15–~1.60 | CTAs spring up |

Total duration is a function of character count, not a constant. For every
valid UK postcode shape (5 to 7 hero characters) it lands between 1.4s and
1.8s. `RevealTimeline.duration(characterCount:)` is the single source of truth
and is asserted within those bounds by test.

## Architecture

The codebase already does the hard-to-get-right thing: motion is a pure
function, `sample(elapsed:) -> SettleSample`, with views as dumb renderers
driven by one `Animatable` Double. We generalise that rather than replace it.

### One canvas, never torn down

Today `LocateChrome` and `PlaceExperience` are separate views and `RootView`
swaps one for the other. A continuous transformation is impossible across a
view teardown, so the ring and the postcode must render from the same sample
in the same canvas.

`RevealCanvas` becomes that canvas. It owns everything driven by the sample —
the ring layer, the line, the characters, the wash, and the animated chrome
opacities — and nothing else. `PlaceExperience` hosts it and keeps the things
that are not sample-driven: the buttons, the notice banner, the share scrim,
and the copied toast. `RootView` owns the clock and no longer switches between
locating and place; it passes the canvas a fix or the absence of one.

The error, permission, and unsupported screens remain separate views. They
are genuinely different destinations, not states of the same object.

### Two clocks, deliberately

Forcing Act 1's indefinite loop and Acts 2–4's fixed timeline into one
monotonic scalar means the scalar grows unbounded while searching. Instead:

- `searchLoop: Double` — a looping 0..1 phase, meaningful only in Act 1.
- `elapsed: Double?` — `nil` while searching; `0` at the instant the fix
  lands, running to `duration`. Drives Acts 2–4.
- `handoffLoop: Double` — `searchLoop` frozen at the moment of handoff, so
  ring positions interpolate from where they actually were.

```swift
RevealTimeline.sample(
    elapsed: Double?,          // nil while searching
    searchLoop: Double,
    handoffLoop: Double,
    characterCount: Int,
    reduceMotion: Bool
) -> RevealSample
```

### `RevealSample`

Pure data, no UIKit, no SwiftUI. Fields grouped by layer:

- **Rings** — `rings: [RingState]` (radius, opacity, lineWidth), plus
  `lockRadius`, `lockOpacity`.
- **Line** — `lineLength`, `lineThickness`, `lineOpacity`.
- **Characters** — `characters: [CharacterState]` (opacity, offsetY, scale,
  weightBlend). One entry per hero character.
- **Wash** — `washProgress`, `washOriginY` (normalised baseline position).
- **Chrome** — `captionOpacity`, `wordmarkOpacity`, `sectionOpacity`,
  `districtOpacity`, `districtOffset`, `ctaOpacity`, `ctaOffset`,
  `bannerOpacity`.

### Haptics are declared, not guessed

The existing `LockTick` is a view-side class that watches `elapsed` cross a
threshold and fires one impact. With per-character haptics that approach does
not scale and is untestable.

Instead the timeline declares its own cues:

```swift
RevealTimeline.hapticCues(characterCount: Int) -> [HapticCue]
// HapticCue { time: Double, style: HapticStyle }
```

A `HapticScheduler` in the app layer fires each cue as `elapsed` crosses it.
Cue ordering, count, and bounds become unit-testable facts in the Core
package. `LockTick` is deleted.

## Procedural colour

`PlacePalette` curates 11 outcodes. Every other UK postcode — the
overwhelming majority of users — falls through to `.neutral`, grey `#111111`.
The Act 4 payoff never happens for them.

Every postcode gets its own permanent colour, derived deterministically:

1. FNV-1a hash the uppercased outcode → hue 0–360.
2. A second hash bit selects a lightness band: a deep band (L ≈ 0.22) most of
   the time, a pale band (L ≈ 0.88) roughly 1 in 6 — the treatment EX1 already
   uses, kept as variety rather than an exception.
3. HSL → RGB for `primary`. (`RGB` needs an HSL initialiser; it has none today.)
4. `onPrimary = RGB.bestText(on: primary)` — already exists.
5. `accent` at hue + ~150°, higher chroma, lightness chosen so it clears 3:1
   against `primary`.
6. `onAccent = RGB.bestText(on: accent)`.

The 11 curated themes stay as exact overrides. Hand-picked beats generated
where someone has done the work.

**Guaranteed by construction, verified by test:** every generated theme meets
the existing 4.5:1 floors for both `onPrimary` and `onAccent`. The test
iterates every valid UK outcode shape, not a sample.

Same outcode always yields the same colour. Yours is always yours; your
neighbour's is different.

## Interaction

Restraint everywhere else — these are small, and that is the point.

- **Tap to skip.** Any tap during the reveal jumps to settled over a 0.12s
  crossfade, not an instant pop. One `.soft` haptic. One line: set `elapsed`
  to `duration`.
- **Buttons.** Press feedback today is `opacity 0.72`. Add scale 0.97 with a
  spring release, and a `.light` impact on the primary action.
- **Copy.** The toast exists. Add a single pulse of the postcode itself
  (scale 1.0 → 1.03 → 1.0) as the toast lands, connecting the action to the
  object it acted on.
- **Share.** The scrim exists. Add a 0.98 scale-down of the content as the
  sheet rises, so the app recedes rather than dims.
- **Edge screens.** Permission, failure, and unsupported currently appear
  instantly. Give them a staggered 8pt rise and fade, and a 0.2s crossfade
  when `RootView` moves between them.
- **Launch.** `UILaunchScreen` is an empty dict, so the app flashes white
  before the first frame. Set it to the locate background so launch is
  continuous with Act 1. Cheap, and removes the first visible seam of all.

## Accessibility

Non-negotiable; the current code already takes this seriously and we keep that.

- **Reduce Motion** — `sample` returns the settled state for all inputs. No
  ring loop; the existing trimmed-arc indicator stays. The wash applies
  instantly. Haptics still fire; they are not motion. Tap-to-skip becomes a
  no-op.
- **VoiceOver** — the hero remains a single element with the existing
  combined label. The reveal must never steal focus. Post one announcement at
  settle.
- **Dynamic Type** — `HeroFitting` keeps sole authority over point size. Per-
  character animation must not change the measured width.
- **Contrast** — the 4.5:1 floors apply to procedural colours exactly as they
  apply to curated ones, including mid-wash, via the existing
  `ThemeInterpolation.traveling` machinery.

## Testing

All timeline and palette logic lives in `PostcodeNowCore` with no UIKit
dependency, so it is testable as pure math — the property the existing 28
tests already exploit.

**Timeline**
- Every field stays within its valid range across the whole domain, sampled
  at 1ms.
- `t >= duration` returns exactly `.settled`.
- `reduceMotion` returns `.settled` for every input.
- **Handoff continuity:** ring radii at `elapsed = 0` equal the search-loop
  radii at `handoffLoop`, for every value of `handoffLoop`. This is the test
  that guarantees the seam is invisible, and it is the most important one here.
- `duration(characterCount:)` lands in 1.4–1.8s for all valid postcode shapes.

**Haptics**
- Cues are strictly ordered, all within `[0, duration]`, and number
  `characterCount + 1`.

**Palette**
- Determinism: same outcode → identical theme.
- Contrast: every valid outcode shape clears both floors.
- Curated overrides are returned unchanged.

**Migration:** the existing `SettleTimeline` tests are rewritten against
`RevealTimeline`. The surrounding tests — postcode parsing, share text, the
postcodes.io client, Info.plist copy — are untouched and must stay green.

## Files

**`Sources/PostcodeNowCore/`**

| File | Change |
|---|---|
| `RevealTimeline.swift` | New. Replaces `SettleTimeline.swift`. |
| `RevealSample.swift` | New. Sample and its layer sub-structs. |
| `HapticCue.swift` | New. Cue type and the cue schedule. |
| `MotionTiming.swift` | Rewritten for the four acts. |
| `Easing.swift` | Add the curves the lock anticipation needs. |
| `RGB.swift` | Add HSL → RGB. |
| `PlaceTheme.swift` | Add `ProceduralPalette`; curated map becomes overrides. |
| `SettleTimeline.swift` | Deleted. |

**`PostcodeNow/`**

| File | Change |
|---|---|
| `RevealCanvas.swift` | New. The single unified canvas. |
| `Haptics.swift` | New. `HapticScheduler`. Replaces `LockTick`. |
| `RootView.swift` | Owns the clock; stops hard-switching locating → place. |
| `PlaceExperience.swift` | Shrinks to settled-state chrome. |
| `LocateChrome.swift` | Ring rendering moves into the canvas. |
| `Controls.swift` | Press feedback, toast pulse; `LockTick` removed. |
| `EdgeScreens.swift` | Entrance motion. |
| `Info.plist` | `UILaunchScreen` background. |

## Risks

1. **Per-character layout versus `HeroFitting`.** Animating characters
   individually means laying them out individually, and that can drift from
   the width `HeroFitting` measured for the whole string — breaking Dynamic
   Type fitting at large sizes. *Mitigation:* measure the full string once as
   today, then lay characters out in a fixed-width container using the same
   font and tracking, with the accessibility element still combined. This is
   the highest-risk item and should be built and verified first.

2. **Per-frame cost.** `RevealCanvas` computes a sample every frame, and
   `ThemeInterpolation` runs contrast math inside it. At 120Hz on ProMotion
   that is 120 contrast evaluations a second. *Mitigation:* memoise the
   travelling-colour decision per wash step rather than per frame; profile on
   device before locking the design.

3. **Generated colours can be ugly.** Contrast-safe does not mean good. A
   hash can land on a muddy olive or a sickly chartreuse. *Mitigation:*
   exclude a muddy hue band from the wheel, and review a contact sheet of ~40
   generated themes against real outcodes before locking the generator.

## Non-goals

No settings screen. No map. No Metal or shaders. No onboarding. No postcode
history. No change to the lookup, location, or sharing logic — this is
presentation only.
