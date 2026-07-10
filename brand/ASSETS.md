# Tapt — Brand Asset Manifest

`brand/` in this repo is the **canonical asset store** (versioned, backed up
on GitHub, $0). Nothing brand-official lives anywhere else; socials and decks
pull from here.

## Current assets
| Asset | File | Use |
|---|---|---|
| App icon (master) | `icon-1024.png` | App Store, avatar crops |
| Icon vector | `icon.svg` | Print, scaling, favicon derivatives |
| Live brand board | `board.html` | The visual system reference (serve: launch config `tapt-brand`, port 4599) |
| Beer glass (signature graphic) | code: `app/Tapt/Design/Motion.swift` (BeerGlassView) | In-app hero art; screenshot at 3x for social |
| Share card | code: `app/Tapt/Features/Sharing/ShareCard.swift` | The 9:16 social frame — brand-locked |
| Landing page | `landing/index.html` → tapt-landing-three.vercel.app | Public brand surface |
| Pitch deck | `landing/pitch.html` → /pitch on landing domain | Partner + investor deck (print → PDF) |

## Tokens (single source of truth: docs/06-BRAND.md + app/Tapt/Design/Theme.swift)
- Pour Gold `#F2A900` · Malt Black `#1A1206` · Foam `#FBF6EC`
- Fresh Hop `#3F8F5B` · Copper Ale `#B4531F` · Haze `#EFE7D6` · Slate `#6B6459`
- Type: Poppins (display) / Inter (body) on web; SF rounded/system in-app
- Voice: the knowledgeable friend at the bar — warm, worldly, a little witty;
  curiosity over capacity; NA drinkers first-class; never crude, never "bro"

## Rules
1. No third-party logos or brewery imagery without written/DM permission —
   partner uploads are the licensed path to official art.
2. Real screens and real data in every marketing visual. Blank beats invented.
3. New assets: add the file here + a row in this table in the same commit.
4. Social exports: 1080×1350 posts, 1080×1920 stories, screenshots at 3x.

## Wanted (backlog)
- Regenerated app icon (richer render — Higgsfield credits, owner call)
- Foam-pin "stamp" secondary glyph as standalone SVG (per docs/00 logo concept)
- Story template pack (Passport flex frame, BOW race frame)
