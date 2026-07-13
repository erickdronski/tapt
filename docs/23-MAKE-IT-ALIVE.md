# 23 — MAKE IT COME ALIVE

The build plan that turns the energy audit into shipped code. Every fix here is felt, not described.

## The honest read

The app is not missing a dopamine layer. It already ships one, fully built and tested, and then never calls it. `Celebrate.swift` holds confetti, count-ups, a stamping glass, a descending crown, and `Haptic.celebrate` — and two of its four celebration types (`.voteCounted`, `.bowCrowned`) are dead code fired from nowhere. Every peak moment the product has (casting a vote, scanning a beer, finishing onboarding, a beer winning the week, winning a game, claiming a venue) ends in a silent haptic buzz. On top of that, the entrance-motion state (`appeared`) is wired on almost every screen and connected to almost nothing, so screens pop in flat, and the whole app is dead to the thumb because primary buttons use `.buttonStyle(.plain)`.

The throughline that fixes it: **wire the reward and motion systems that already exist into the core actions and the first two seconds.** One tactile language (`.taptPress` + `Haptic`), one reward language (`taptCelebration`), one entrance language (staggered `appeared` cascade), one signature graphic (`BeerGlassView`) — applied everywhere. Almost none of this is new components. It is plugging in what was built and abandoned.

## Ship this first (the top 12)

Ranked by impact-to-effort, weighted toward what a user feels the instant a screen opens or the first time they tap the core action.

### 1. Fire the vote celebration on Explore (it exists, it is called nowhere)
**File:** `app/Tapt/Features/Explore/ExploreView.swift`
**Change:** Add `@State private var celebration: TaptCelebration?`; attach `.taptCelebration($celebration)` to the ScrollView beside the existing `voteToast` overlay. In `vote(_:_:)`, inside the successful Task after `applyVoteDelta(b.id, delta)`, when `newValue == 1` (a real up-vote, not a flip or un-vote) run `await MainActor.run { celebration = .voteCounted(beer: b.name, count: <post-delta popularity>) }`. Guard so downvotes/un-votes never celebrate. Overlay owns its own haptics/confetti/auto-dismiss.
**Life it adds:** The make-or-break screen's core action goes from a 1px border tint to "I made something the whole board sees."

### 2. Fire the vote celebration on the beer page, once, as a teaching moment
**File:** `app/Tapt/Features/Beer/BeerDetailView.swift`
**Change:** Keep the inline thumb bounce for repeat taps. Add `@AppStorage("vote.firstCastDone")` + `@State celebration` + `.taptCelebration($celebration)` on the root ScrollView. On the FIRST successful `BeerService.vote`, set `firstVoteDone = true` and `celebration = .voteCounted(beer: d.name, count: newCount)`. Silent forever after.
**Life it adds:** New users learn the core loop matters without a tooltip; one count-up teaches "your thumb moves the market."

### 3. Fire the pour celebration on Scan (the app's most magical action)
**File:** `app/Tapt/Features/Scan/ScanView.swift`
**Change:** Both log paths (`save(_:)` and the Open Food Facts add path) call `Haptic.celebrate()` then jump straight to the share card, skipping the `.pourLogged` glass-fills-and-stamps overlay. Add `@State celebration` + `.taptCelebration($celebration) { loggedPour = pendingPour }`. In both success blocks, stash the PourCard and set `celebration = .pourLogged(beer: pour.beer, rating: Double(pour.rating ?? 0), place: nil)`; open the share in `onFinish`.
**Life it adds:** Point-camera → recognized → glass pours → LOGGED stamp thuds → confetti. The single most shareable moment in the app currently is a buzz and a jump.

### 4. The entrance-cascade pass (screens pour themselves onto the page)
**Files:** `ExploreView.swift`, `Cellar/CellarView.swift`, `Market/BeerMarketView.swift`, `Discover/DiscoverView.swift`
**Change:** Every one of these already has an `appeared`/`revealed` flag driven in `onAppear` but consumes it on nothing (Explore only animates the hero, Cellar only the empty states, Discover only the hero panel, Market has no reveal at all). Add one reusable modifier per file — `.opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 16).animation(.spring(response: 0.55, dampingFraction: 0.85).delay(Double(index) * 0.06), value: appeared)` — and apply it to each major child in body order. Market: add `revealed`, flip it in `load()` after `beers = board`, cascade rows with `delay(Double(min(i,12)) * 0.03)`.
**Life it adds:** The cheapest possible first-two-seconds win, and it is nearly free because the state already exists. Screens stop popping in flat and start assembling in front of you.

### 5. Count the Cellar stat numbers up from zero on appear
**File:** `app/Tapt/Features/Cellar/CellarView.swift`
**Change:** The stat tiles already carry `.contentTransition(.numericText())` but the values compute once and never change, so the transition never plays. Add `@State private var countsRolled = false`; render `countsRolled ? "\(checkins.count)" : "0"` (same for styles/states/countries); after `load()` flip `countsRolled` inside `withAnimation(.easeOut(duration: 0.6))`.
**Life it adds:** Robinhood-grade "the numbers spin up the moment you land." 90% of the machinery is already wired.

### 6. Turn the milestone rail into a fill-me trophy case
**File:** `app/Tapt/Features/Cellar/CellarView.swift`
**Change:** Drop the `if !earnedBadges.isEmpty` guard so the rail always renders. Iterate ALL of `PassportData.badges`: earned = current gold circle + one-time `Shimmer()` sweep; locked = dim `Brand.haze` circle with `lock.fill` and a progress pill (`min(current,threshold)/threshold`) over a thin gold `Capsule` track. Add `currentValue(for: BadgeMetric)` mapping to `stats.pours/beers/styles/states/countries`. Header → "Trophy shelf" with trailing `\(earnedBadges.count)/\(PassportData.badges.count)`.
**Life it adds:** The literal "growing trophy case you want to fill." Today locked trophies are invisible, so a new user sees no case and zero aspirational pull.

### 7. Celebrate finishing onboarding (the biggest first-run milestone is silent)
**File:** `app/Tapt/Features/Onboarding/OnboardingView.swift`
**Change:** `complete()` saves and instantly swaps to RootView with zero payoff. Add `@State celebration` + `.taptCelebration($celebration) { finishOnboarding() }` on the root ZStack. In the Task success branch set `celebration = .badgeUnlocked(title: "Welcome to Tapt", symbol: "checkmark.seal.fill")` and move the `onboardedUserIDs`/`badgesSeeded` writes into `finishOnboarding()` run in the `onFinish` closure, so OnboardingView stays mounted through the ~1.7s reward before RootView appears.
**Life it adds:** Crossing into the app becomes an earned, celebrated threshold — the first hit that teaches "this app rewards you."

### 8. The tactility pass (make the whole app react to the thumb)
**Files:** `Auth/SignInView.swift`, `Onboarding/OnboardingView.swift`, `Onboarding/AgeGateView.swift`, `Market/BeerMarketView.swift`, `Beer/CatalogView.swift`, `NearYou/NearYouView.swift`, `Community/LeaderboardsView.swift`
**Change:** Swap `.buttonStyle(.plain)` → `.buttonStyle(.taptPress)` on every primary button and list row (both already exist in `Motion.swift`). Add `Haptic.tap()` on any tap that changes selection/filter, `Haptic.firm()` on any commit (verify, sign-in, vote, claim, subscribe, save-to-cellar). Market rows and Catalog rows currently do not physically react at all.
**Life it adds:** Tactility is the cheapest "expensive app" signal there is. The first 30 seconds and every list stop feeling like dead glass.

### 9. Crown Beer of the Week (a dead celebration + a static trophy card)
**File:** `app/Tapt/Features/Beer/BeerOfWeekCard.swift`
**Change:** Two parts. (a) Wire the dead `.bowCrowned` case: add `@State celebration` + `@AppStorage("bow.lastCelebratedWeek")`; in `load()` after `winner` is set, if the winner's week id differs, set `celebration = .bowCrowned(beer: winner.name)`, update the stored week, attach `.taptCelebration`. Plays once per new weekly winner. (b) Give the card ambient life: header crown → `Image(systemName:"crown.fill").symbolEffect(.pulse, options: .repeating.speed(0.4))`; winner row → a slow `Shimmer()` sweep over the gold background.
**Life it adds:** The one card that should feel like a trophy case stops being a static gold rectangle and becomes an event you witness.

### 10. Kill the dead hero CTA on the landing page
**File:** `landing/index.html`
**Change:** The hero primary action (line ~274) and the closing `.contact` action (line ~502) are both a disabled grey span reading "App Store release in progress." Replace each with a live inline email capture reusing the already-wired `dispatch-signup` edge function and the dark `.signup` input styling, with a gold `btn-gold` reading "Get launch access." Keep "iOS, launching soon" as small plain text, not a button.
**Life it adds:** The first and last impression of the whole brand stops being a button that greys out and refuses to be tapped.

### 11. Fill the hollow landing stat band with real count-up numbers
**File:** `landing/index.html`
**Change:** `.stat b` is styled as a 1.9rem gold number but the four values are adjectives ("Deep catalog", "Worldwide", "On the map", "Cited") — it reads as an unfilled template. Fetch real counts at load via the anon Supabase REST pattern already in `menu.html` (catalog beers, mapped venues, cited BJCP styles), render true numbers with a count-up on reveal, and fall back to the current word if a fetch fails (never a fabricated number).
**Life it adds:** A number ticking to "11,800+ beers" is honest AND a dopamine hit; adjectives in number slots make the whole section feel unfinished.

### 12. Make the Beer Market actually tradable (reward score is 1/5)
**File:** `app/Tapt/Features/Market/MarketBeerDetailView.swift`
**Change:** The "trading floor" is read-only. Add `@Environment(Session.self)`, `@State myVote/ups/downs` seeded in `.task` via `BeerService.currentVote`, and `@State celebration`. Below the buy-pressure bar add two pill buttons — Buy (`hand.thumbsup.fill`, `Brand.hop`) and Sell (`hand.thumbsdown.fill`, `Brand.copper`) — mirroring `ExploreView.voteButton`. On tap: `Haptic.firm()`, optimistic toggle so the pressure bar springs, then `BeerService.vote`/`unvote`. On a successful Buy set `celebration = .voteCounted(beer: beer.symbol, count: ups)` and attach `.taptCelebration` to the ScrollView.
**Life it adds:** Turns passive analysis into an actual trade with the full count-up + confetti payoff. This is the flagship screen's missing dopamine loop.

## Personality pass

House rules hold: plain, direct, no em dashes, no hype adjectives. Plain does not mean lifeless. Trade settings-menu captions for verbs and invitations.

| Where | Before | After |
|---|---|---|
| Explore empty market (`heroPanel`) | "Catalog ready · market awaiting votes" | "Be the first thumb up" |
| Explore scan tile subtitle | "Barcode, label, or a bar QR" | "Point it at any beer" |
| Explore Leaderboards subtitle | "Beers · tasters · styles" | "Who's winning this week" |
| Cellar hero subtitle | "12 distinct beers across 5 styles, 3 states, and 2 countries." | "12 beers in the book. 3 more to Explorer." |
| Cellar section header | "Earned milestones" | "Trophy shelf" |
| Cellar section header | "Pour history" | "Every pour, in order" |
| Market detail (above Buy/Sell) | (none) | "Where do you stand?" / zero-state "No votes yet. Be the first to call it." |
| Near You spotlight caption | "Nearby beer spot" | "Closest to you right now" |
| Near You empty search | "No beer spots match that search yet." | "Nothing on the radar for that. Try a city or a shorter name." |
| Near You loading | "Loading Tapt beer radar..." | "Warming up the radar..." |
| Games hub | (feature descriptions) | table-talk imperatives: "Rack 'em" / "Pass the phone" / "Winner stays on" |
| Onboarding styles subtitle | (assumes expertise) | "New here? Tap a couple, or skip. We'll learn as you pour." |
| Sign-in guest button | (unlabeled escape hatch) | add caption "Browse the catalog, map, and games. No account needed." |
| Landing hero lede | "All of beer, one app: discover, rank, learn, play, find local pours, and build your Beer Passport." | "Scan any beer, see if the world agrees." + line 2 "Real votes, cited style science, zero fabricated hype." |

Shape to reuse: one punchy line, then a proof line. Lead casual, earn the geek in the next breath.

## Cohesion fixes (landing + app + partner as one brand)

- **One reward language.** `taptCelebration` (Celebrate.swift) becomes the payoff for every milestone across surfaces: vote, scan, onboarding finish, venue claim (`BreweriesHubView.ClaimConfirmSheet` → `.badgeUnlocked(title: venue.name, symbol: "checkmark.seal.fill")`), game win (overlay `ConfettiBurst(active: winner > 0)` on the four SwiftUI games), and BoW crown. Right now each surface invents its own dead-end.
- **One tactile language.** `.taptPress` + `Haptic` (Motion.swift) on every button and row app-wide (see top-12 #8). No screen should be dead to the thumb.
- **One signature graphic.** `BeerGlassView` is the app icon, the celebration glass, and the landing mark — put it everywhere it is currently missing: the beer page photoless fallback (replace the flat `mug.fill` Rectangle with `BeerGlassView(pour: 0.8)`), the Near You venue-detail tile (`BeerGlassView(pour: 0.8, animatesPour: true)`), and the landing hero at 72–96px with its four bubble circles rising on a loop. Add a slow breathe to `TaptHeroPanel`'s corner glass (`PolishViews.swift`) so the home hero has an idle pulse.
- **One heat treatment.** `heatScore`/`heat` is real server data shown only on `TonightView` today. Reuse its exact flame chip (`Label("\(n)", systemImage: "flame.fill")` on a `Brand.gold.opacity(0.16)` capsule) on Near You rows, Market rows, and Explore movers so "what's hot" reads identically everywhere. Gate on real activity so it never implies fake movement.
- **One podium metaphor.** Gold rank medallions on Explore top-3 rows should reuse `BeerOfWeekCard.medal(_:)` and rhyme with the Cellar trophy shelf, so leaderboard/BoW/passport all speak "medals."
- **One web system.** `portal.html` and `menu.html` are bare white forms while `pitch.html`/`dispatch.html` are dark, cinematic, and alive. Give the portal a dark-malt hero band + a gold `.plan`-style pricing card + the reveal-on-scroll IntersectionObserver from `index.html`; give the scan menu a branded top band (glass mark + "Tapt." wordmark), a pulsing `.dot` on the live-tap label, and one engaged-moment gold CTA into the waitlist. Then all five web pages read as one confident product instead of three.

## Bigger swings (do next)

1. **Movers rebuilt as real stories, not facts.** (medium) Port the `Sparkline` component and `MarketBeer` data (real `spark`, `change`, `moveReason`, `heat`) out of the Market tab into Explore's "On the come-up" rail and the Market board rows: sparkline + net change + a `moveReason` caption + a heat bar. A number with an arrow is a fact; a sparkline with a reason is the geek-grade signal the audience wants. Both the view and the data already exist, just siloed.
2. **The exchange behaves like an exchange.** (medium–large) Opening-bell cascade + `.taptPress` rows + a live market-pulse hero strip ("18 moving · 3 surging" + top-mover pill) + `heat` heatmap rows + animated numeric standings on refresh (`withAnimation { beers = board }` + `Haptic.tap()`) + the tradable Buy/Sell detail. Turns the flagship from a screensaver into a market you act on.
3. **The Games hub becomes an arcade, plus records + win celebrations.** (large) Replace the gray 11-row list with a `TaptHeroPanel` + a two-column arcade grid (full-bleed tint gradients, Beer Pong as a featured full-width card) + a staggered entrance + a "Your records" rail reading the four persisted `@AppStorage` bests + a day-seeded "Tonight's pick." Then fire `ConfettiBurst`/`.badgeUnlocked` on new bests in Darts/FlipCup/Quarters/Trivia, and `CountUp` on the Trivia results score.
4. **Near You becomes a treasure hunt.** (medium–large) Surface the real `heatScore` as pulsing gold heat pins + flame chips + heat-sort-when-GPS-off, add real computed distance labels on nearby rows, the pouring-glass venue-detail tile with a `Haptic.success()` when a live tap list loads, and the confetti claim celebration. The map stops being a phone book with a map on top.
5. **Reshape the first 30 seconds of onboarding.** (medium) Reorder the TabView so delight leads (Welcome → styles → region → legal → celebrated finish) instead of hitting three privacy toggles on screen two, turn the empty Welcome step into a choreographed four-row "what's inside" reveal, choreograph the SignInView entrance under a bigger hero glass, and color-code the 11 style pills into a flavor map with an explicit "or skip" on-ramp for casual drinkers.

## Per-surface scoreboard (re-measure after)

| Surface | Grab | Motion | Personality | Richness | Reward | Audience |
|---|---|---|---|---|---|---|
| Home / Explore | 3 | 3 | 3 | 3 | 2 | 3 |
| Beer Market | 3 | 2 | 3 | 3 | 1 | 3 |
| Cellar / Passport | 3 | 2 | 3 | 3 | 2 | 3 |
| Games | 2 | 3 | 2 | 3 | 3 | 3 |
| Discover + Beer Detail + Catalog | 2 | 2 | 3 | 3 | 2 | 3 |
| Onboarding + First Run + Sign-In | 2 | 2 | 2 | 2 | 1 | 3 |
| Near You + Partners | 2 | 2 | 2 | 2 | 2 | 2 |
| Web (landing / portal / menu / dispatch / pitch) | 2 | 3 | 3 | 3 | 2 | 3 |
| Motion + Reward system (cross-cutting) | 3 | 3 | 3 | 3 | 2 | 3 |

Lowest scores today are Reward (Market 1, Onboarding 1) and Motion (five surfaces at 2) — which is exactly what the top-12 targets: turn on the celebrations that already exist and connect the entrance motion that is already wired. Re-score after Ship-This-First lands.