# Tapt — End-to-End Overhaul Roadmap

Everything discussed, wired into prioritized waves. The goal: an award-winning,
fully-functional, visually elevated app + landing + newsletter, with **real data only**
and **verified in the running product** — never claimed, never faked.

Two ground rules that shape sequencing:
- **No parallel agent fleets / no parallel builds.** (Crashed the laptop twice at ~80GB.)
  Sequential work; server-side SQL and content generation can batch.
- **The sim-sign-in blocker.** App sign-in on the simulator is dead (email OTP `429`,
  Google PKCE error). This gates *verifying app changes in the running app* and
  *capturing true app screenshots*. Anything on the app-visual track is built + compiled
  but not click-through-verified until this clears. **Highest-leverage unblock.**

---

## Priority 0 — Unblock the sim (owner, ~5 min)
Without it, the "award-winning app" track and real screenshots stay unverified.
- A fresh email OTP code, **or** sign in with Google once PKCE is fixed, **or** a signed
  device build.
- Payoff: I can walk every screen, verify each fix live, and capture true screenshots.

## Wave 0 — Land what's already built (owner: review + merge)
Open PRs (compiled/verified where possible; app UX pending the unblock):
- #17 map — Germany fix + tappable venue detail
- #18 public profile — tap a follow → passport card
- #19 hero — statements each on their own line
- #20 landing — pricing off the page + honest style marks
- #21 leaderboard — real beer photos + reusable `BeerThumb`
Note: rebase #18 after #21 so the passport's favorite-pour uses `BeerThumb` + the
`favorite_beer.image_url` already shipped in migration 0040.

## Wave 1 — The Tapt Dispatch, in full  *(web · verifiable now · IN PROGRESS)*
- Dedicated **/dispatch** page: what it is, opt-in, opt-out.
- **Archive/hosting**: `dispatch_issue` table + a public list; the page renders published
  issues. Honest empty state until the first issue ships.
- **Premium issue format**: taste-skill-personalized, real beer photos, motion,
  interactive HTML — a genuinely enjoyable weekly read, not a plain email.
- Owner-gated to actually SEND: `RESEND_API_KEY` + `CRON_SECRET`.

## Wave 2 — Show the real app on the landing  *(screenshots)*
Replace the emoji tiles with faithful renders populated from the **demo schema**:
home, the Beer Market in motion (now with images), a scan result, the mini-games,
the Passport with badges filled, the Cellar filled.
- Path A *(best)*: unblock sim → capture true screenshots with demo data.
- Path B: SwiftUI `ImageRenderer` snapshots of real views with demo data (no sign-in).
- Path C *(interim)*: faithful HTML phone-frames styled from the actual SwiftUI, so the
  landing isn't empty while A is blocked. Clearly a render of the real UI, swapped for
  true captures the moment the sim is back.

## Wave 3 — Mini-games: GamePigeon-tier  *(app · needs sim verify)*
Current games read cheap. Rebuild to feel like expensive engineering:
- Real motion/physics, spring + bounce, particle/juice, haptics, sound.
- One cohesive premium visual system across all games.
- Per-game teardown → rebuild, one at a time.

## Wave 4 — App dynamism pass  *(app · needs sim verify)*
Carousels, spring/bounce/fade transitions, shared-element navigation, number count-ups,
skeleton→content, pull-to-refresh polish — and **surface the taste skill** across
home/discover (personalized "for your palate" rails).

## Wave 5 — Functional end-to-end + QA  *(needs sim verify)*
- **Venue attribution**: check-ins carry `venue_id` so partner analytics actually fill.
- Every tile wired, honest empty states everywhere, account/consent flows verified.
- Full click-through QA once the sim is back.

## Wave 6 — Launch gates  *(owner)*
Apple Sign In (Guideline 4.8), Google PKCE fix, Resend SMTP + Dispatch secrets,
Stripe → `grant_featured`, APNs for push.

---

## Cross-cutting, every wave
- **Visual elevation**: motion, depth, consistency — measured against the best apps.
- **Honesty**: real, sourced data only; blank beats invented; the boards stay honestly
  empty until the community fills them.
- **Verify in-product**: nothing is "done" until it's seen working.

_Status is tracked live in the session task list; PRs are opened per slice._
