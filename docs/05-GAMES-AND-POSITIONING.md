# Tapt — Positioning, Games pillar & brand motif  *(owner updates 2026-07-07)*

## Positioning
**Tapt = THE beer app.** Category-defining, global, the default place beer fans log, discover, and play. Confident and iconic — not a niche ticker tool.

## Name
Locked: **Tapt.** (Owner floated "Beer" in another language / alt styling — folded into the brand as a *global motif*, not the name.)

## New pillar — Tapt Games (free, in-house)
Free mini-games playable **in-app at the brewery/bar while drinking** — entertainment + retention + longer sessions + a social hook. All house-built, all free.
- **Trivia** — beer/brewery/ABV/style trivia; daily streak + head-to-head; themed packs tied to the catalog.
- **Card games** — dynamic digital drinking-card decks (Kings-cup-style prompts, Ride the Bus, higher/lower), house-designed.
- **Quick party games** — dice / spinner / roulette / "most likely to," pass-and-play at the table.
- **Brewery Mode** — a table session: everyone scans in to one **Crew / Live Session**, then games + group check-ins + a live leaderboard + photo wall (built on the Crew engine already in the roadmap).

**Design rules:** 100% free · no gambling/wagering · responsible-drinking framing (social/fun, never "drink more" pressure) · **NA-friendly variants** so the No/Low crowd plays too · offline-capable for dead zones · ≤2 taps from home.
**Later monetization/partnership surface:** brewery-sponsored trivia packs + branded decks; sponsored table challenges.

## Brand motif — global "cheers"
Beer is worldwide, so weave a recurring **"cheers around the world"** motif — *Prost · Salud · Kanpai · Skål · Saúde · Na zdrowie · Cheers · 乾杯* — as brand texture (splash, loading + empty states, packaging pattern). Reinforces "beer fans around the world" and the culturally-aligned lexicon (flights, keg, tap list, Cellar, Passport).

## Apple / App Store Connect foundation
- **Bundle ID:** `app.tapt.tapt` (matches Lore `app.lore.lore` / Nalee `app.nalee.nalee`).
- **App ID capabilities:** Sign in with Apple · Maps (MapKit) · Push Notifications · Associated Domains (universal links) · App Groups (future widget/extension).
- **To automate app-record + TestFlight:** owner creates an **App Store Connect API key** (App Store Connect → Users & Access → Integrations → App Store Connect API → Team key, role *App Manager*); store Issuer ID + Key ID + `.p8` securely (like Lore's certs). Then app creation, capabilities, and TestFlight uploads can be scripted via fastlane / the ASC API.
