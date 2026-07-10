# Tapt, Status & Future-State Roadmap (living doc, 2026-07-10)

The single source of truth for where Tapt is and what to work through next.
Supersedes the forward-looking parts of docs/11 and docs/12 (which predate most
of what has shipped). Standing rules unchanged: zero fabricated data, free to
drinkers forever, curiosity over capacity, license-clean only.

---
## Where we are today (shipped & live)
**App (iOS, on TestFlight, auto-assigns to testers):**
- Scan loop: barcode + QR + live text/menu mode + partner-QR routing
- Catalog: 187 real beers / 47 countries, 8,700+ venues / 25 countries, 60
  BJCP styles, 68 real label photos, verified awards layer
- Beer pages: style science, nutrition, awards, brewery stories, where-to-find
- Social engine: honest beer market, Beer of the Week (weekly vote + Monday
  lock), leaderboards (+ No/Low lens), friends/feed, voting (persists), moderation
- Games: Trivia, Tapt Deck, Darts (swipe physics), Connect 4, Beer Olympics,
  Game Night Guides. (Pong/Flip Cup/Quarters still elementary, rework pending)
- Location-aware map + dashboard, 6 languages, elevated design + haptics

**Web (all live on Vercel):**
- Landing (SEO'd: free-to-download + free menu hosting), pitch deck at /pitch
- Partner portal /portal, admin queue /admin, hosted menus /menu

**Partner system (end to end):**
- Claim -> auto-approve on domain match OR 1-click /admin queue -> publish tap
  list -> upload logo -> free hosted menu + printable QR

**GTM assets:** masterplan, outreach playbook, IG calendar, brand manifest,
partner workflow map, newsletter collecting subscribers.

---
## THE CRITICAL PATH (do these first, they gate everything)
Nothing below matters until the app is downloadable and login works. These are
almost all **owner actions**, not build work:

1. **Apple auth** (docs/09): enable Apple provider in Supabase (leave Secret
   Key EMPTY), add `tapt://auth-callback` to redirect URLs, add `{{ .Token }}`
   to the email template. This is the login pain, one 10-minute pass.
2. **App Store submission**: screenshots + metadata + review. The app is
   social/logging only with all four UGC-moderation pieces already shipped, so
   it clears the alcohol-app rejection lanes.
3. **Custom SMTP** (Supabase Auth): default sender is rate-limited/spammy.
   Resend free tier ($0, 3k/mo) fixes sign-in email reliability at launch.
4. **Stripe account link**: for B2B partner invoicing (needed at Wave 3, not
   day one, but set it up early).
5. **Claim social handles**: @taptbeer (IG/TikTok/X), before marketing starts.
6. **Legal counsel pass** on privacy/terms + a partner ToS before first invoice.

---
## Phase A, Launch-ready (now -> App Store live)
- [owner] The critical-path list above.
- [build] **Partner approval/inquiry emails** (Resend): auto-email the owner
  their QR link on approval, and us on new inquiry. Makes the partner loop
  fully hands-off. ~Highest-leverage build left.
- [build] **In-app "claim your venue"** entry (currently web-only) so a bar
  owner who found us in the app can start there too.
- [build] Final polish sweep: pong/flip-cup/quarters physics to Darts-grade.

## Phase B, Home-metro density (launch month, NJ/NYC)
- 500 users + 25 claimed venues in ONE metro (density > DAU).
- Founder outreach (playbook: 10 venues/wk, Founding Partner offer).
- **Push notifications** (APNs .p8 direct, already architected): "friends out
  now", BOW results, a claimed venue's new release. The retention lever.
- Content engine on: IG calendar + weekly Dispatch (needs sending pipeline).
- [build] **Newsletter SENDING** (Resend): subscribers are collecting now;
  turn on the actual weekly send. Cost-gated, tiny.

## Phase C, Revenue on (2-5k metro users)
- Featured/Spotlight live ($29/$79, Stripe invoicing, no app-store tax).
- [build] **Tapt's Favorite admin surface** (currently a SQL insert) so you
  can grant/announce picks without the database.
- [build] **Partner analytics**: give claimed venues their real local activity
  (check-ins, top beers, trend) as the paid-tier hook.
- First Founding Partners convert; first ~$500 MRR proof.

## Phase D, Scale loops (10k+ users, 2nd metro)
- [build] **Crew / Live Session**: real-time shared group check-in (tailgate,
  party, scramble) with live leaderboard + photo wall. The flagship social
  differentiator nobody else has. Big build, high payoff.
- Tapt Voices creator program (permissioned lists).
- Distributor pilot (Manhattan Beer-type fleet-claim).
- [build] **Partner asset uploads at scale** = the licensed path to real 4K
  official imagery (the image-quality ceiling honestly solved).
- Metro expansion kit: repeat Phases B-C per metro.

## Phase E, Data authority (density exists)
- Territory intelligence (k>=10, consent-gated, already in the schema) sold to
  breweries/distributors; named indices published quarterly (press + product).
- [build] **Android** (native Kotlin) on the identical backend, if demand pulls.
- This is the valuation story: density x exclusivity x contracted B2B revenue.

---
## Product backlog (not phase-critical, pick up opportunistically)
- Catalog depth: +150 curated US state-flagship beers to fatten state boards.
- More label images (slow OFF re-runs; partner uploads long-term).
- Untappd-history import (data portability hook, not scraping).
- Homebrew logging, bottle-share events, Brewery Bingo (post-PMF).
- Where-to-buy / delivery affiliate (geo-restricted, garnish only).

## Known honest gaps (stated plainly)
- Image quality ceiling: OFF is user-shot label photos, not studio 4K. Real
  premium imagery comes from partner uploads (Phase D) or generated style art.
- US state boards stay sparse until check-ins carry venue location (by design).
- Pong/Flip Cup/Quarters are still the old elementary versions.
- Newsletter has subscribers but no send pipeline yet.
- Everything depends on Phase-B density; revenue is deliberately back-loaded.

## The one-line answer
**Ship it (Apple clicks + App Store), then win one metro (outreach + push +
content), then turn on revenue (Featured + analytics). Everything else is depth
on that spine.**
