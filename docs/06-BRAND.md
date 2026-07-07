# Tapt — Brand System  *"Elevated Taproom"*

The confidence of a world-class craft can meets the calm of a premium app. Warm and tactile, but clean, spacious, and fun. Not woody, not hop-cliché, not frat-crude. **Tapt is THE beer app** for beer fans around the world.

Dials: DESIGN_VARIANCE 7 · MOTION_INTENSITY 6 · VISUAL_DENSITY 3.

## 1. Logo & wordmark
- **Wordmark:** "Tapt" set in a confident modern grotesque, tight tracking. The two `t` crossbars align to read as a **tap handle / pour**; the final `t` can carry a single gold foam-drop accent.
- **App icon (2 concepts):** (a) Malt rounded-square with a **Pour-Gold droplet** cresting a thin foam line; (b) a gold **pour arc** that forms a `T`. Both read at 1024px and at 40px.
- **Monogram:** single `T` with the foam-drop, for avatars, the map pin, and loading.
- Clearspace = height of the `T`. Never stretch, never add a bevel/gloss (elevated, not skeuomorphic).

## 2. Color
| Token | Hex | Use |
|---|---|---|
| **Malt** | `#1A1206` | Primary text, dark surfaces, the premium roasty backdrop |
| **Foam** | `#FBF6EC` | Primary light background (the head on a pour, not clinical white) |
| **Pour Gold** | `#F2A900` | THE signature. CTAs, active states, the pour/progress/passport fill |
| **Hop** | `#3F8F5B` | The No/Low lens, "fresh on tap," success. Signals inclusivity, not IPA |
| **Copper** | `#B4531F` | Amber / dark-style accent, depth, secondary highlights |
| **Haze** | `#EFE7D6` | Warm neutral surface (cards, chips, dividers) on light |
| **Ink** | `#6B5E49` | Muted warm gray for secondary text/captions |

Rules: **one accent (Pour Gold), locked page-wide.** Warm neutrals only, never cool gray. Shadows tinted to Malt, never pure black. Dark mode: Malt base, Foam text, Gold stays the recognizable pop. No pure `#000`/`#fff`.

## 3. Typography
- **Display / wordmark / headlines:** **Clash Display** (Semibold/Bold). Characterful grotesque, fun but clean. Fallback stack: `"Clash Display","Söhne Breit",system-ui,sans-serif`.
- **UI / body:** **SF Pro** on iOS (native, honest), **Inter** on web.
- **Numerals / stats / Beer-geek mode:** a mono (**Geist Mono** / **JetBrains Mono**) for ABV · IBU · SRM · match score.
- Scale: Display 44/56 · H1 32 · H2 24 · Body 16-17 (`leading-relaxed`, max 65ch) · Caption 13.
- Emphasis inside a headline = italic/bold of the SAME family, never a second font.

## 4. Iconography
Custom set: 24px grid, **2px rounded single-weight stroke**, optional Pour-Gold duotone fill on the active glyph. Warm, friendly geometry.
Core glyphs: **pour** (pint + foam), **flight** (three tasters), **hop cone**, **keg**, **tap handle**, **growler**, **map-pin-with-foam**, **dice** (Games), **passport stamp**, **crew** (people), **star** (rate), **scan** (viewfinder).

## 5. Motion — the "Pour" system
Every core motion is a pour or a settle. Warm springs (stiffness ~120, damping ~18), short (200-400ms), always motivated, reduced-motion collapses to a fade.
- **Pour fill:** scores, the Passport, and progress rise like liquid with a thin foam cap that settles.
- **Tap ripple:** press feedback ripples from the touch point (name + gesture on brand).
- **Foam settle:** pull-to-refresh forms a foam head, then settles.
- **Stamp press:** badge / Passport unlock presses in like a stamp with a slight overshoot.

## 6. Global motif — "Cheers around the world"
A rotating set of global cheers, used on splash, empty states, loading, and as a subtle repeating marketing pattern: *Prost · Salud · Kanpai · Skål · Saúde · Na zdrowie · Slàinte · 乾杯 · Cheers.* Reinforces "beer fans around the world."

## 7. Voice
The knowledgeable friend at the bar who is thrilled you are curious. Fun, warm, worldly, a little witty. Frat-friendly, never frat-exclusive; celebrates **curiosity over capacity**. Two registers: plain default + a toggle-on **Beer-geek mode** that swaps in the lexicon (Cellar, Tick a Pour, Whales, Haul, Flight).
Sample microcopy: empty Cellar "Your Cellar's looking thirsty." · NA lens "Big flavor, zero proof. Counts just as much." · scan hint "Point at a can, tap list, or label."

## 8. Games look (Tapt Games)
Bright, tactile, table-friendly: bold Pour-Gold + Copper on Malt, oversized numerals, chunky cards with a soft press. Playful but on-system (same type, same icon language). NA-friendly variants everywhere.
