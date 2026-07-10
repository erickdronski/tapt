# Tapt Partner Workflow, end to end

How a brewery, bar, pub, or taproom goes from "never heard of us" to a live,
self-managed presence, mapped for every party. This is the moat: we give away
the exact tools the incumbent charges $1,199/yr for, so getting in the door is
free and easy, and we earn later on "be louder," never on the working tools.

## The three parties
- **The business** (owner/manager): wants a current menu, a QR for tables, and
  visibility, without a subscription or a learning curve.
- **Tapt (us)**: wants venue claims + published menus (density), a hijack-proof
  verification step, and a clean path to upsell Featured/Spotlight later.
- **The drinker**: scans a table QR or opens the app, sees the live tap list,
  logs a pour, which feeds the venue's local activity, which the venue sees.

## Where a business enters (two doors, one pipeline)
1. **In the app**: Discover, "For breweries & bars", "Partner with Tapt" tile ->
   inquiry form -> `partner_inquiry` row.
2. **On the web**: `tapt-landing-three.vercel.app/portal` (the self-service
   business portal) or the "For Business" nav link on the landing page.

Both land in the same backend. The **web portal is the primary business
surface** on purpose: owners work on laptops, and a 21+ consumer app is the
wrong place to manage a menu. The app tile funnels; the portal operates.

## The full flow (self-service, near-zero touch)

```
BUSINESS                         TAPT BACKEND                    DRINKER
--------                         ------------                    -------
1. Opens /portal
2. Email code sign-in    ----->  Supabase Auth (magic OTP)
3. Searches their venue  ----->  search_venues()  [8,700+ already mapped]
4. Taps "Claim"          ----->  claim_venue() -> venue_claim (pending)
                                       |
                                 5. WE APPROVE (concierge today:
                                    one SQL line; admin UI later)
                                    -> status = approved
6. Builds tap list       ----->  publish_tap_list() (1-60 taps, 14-day fresh)
7. Uploads logo          ----->  partner-assets bucket + set_venue_logo()
8. Gets QR + menu URL    <-----  /menu?v={venue_id}  (public, hosted, free)
9. Prints QR for tables
                                                                10. Scans QR ->
                                                                    live menu in
                                                                    Tapt app or web
                                                                11. Logs a pour
                                       <---- feeds Tonight board + local activity
12. Sees local heat      <-----  (their venue's real drinker signal)
13. (optional) Upgrades  ----->  Featured/Spotlight (Stripe invoice, B2B)
```

## What the business gets (their toolkit)
| Tool | Where | Cost |
|---|---|---|
| Claim their venue | Portal / app tile | Free |
| Live tap-list editor (add/edit/remove, prices) | Portal | Free |
| Hosted public menu page | `/menu?v=...` | Free |
| Printable QR code (auto-generated) | Menu page | Free |
| Logo / brand upload | Portal -> partner-assets bucket | Free |
| Local drinker activity | App (claimed profile) | Free |
| Featured rail placement, event pushes | Upgrade | $29/mo |
| Spotlight (top slot, Dispatch feature) | Upgrade | $79/mo |

## What Tapt does at each step
- **Verification (step 5):** claims are human-approved so nobody hijacks a
  venue page. **Now a one-click admin page** at `/admin` (sign in with the
  owner email, see the pending queue, Approve/Reject). Gated by the `app_admin`
  table + `is_admin()` — only the seeded owner account can see or act. Next:
  auto-approve for matching email domains.
- **Automation already live:** `partner_inquiry` and portal claims flow to the
  same tables; the ASC-style admin job pattern can email owners on approval.
- **Automation next (the roadmap):**
  1. ✅ **Admin approval UI** — LIVE at `/admin` (owner signs in, one-click
     Approve/Reject on the pending queue).
  2. **Email on approval + on inquiry** via the newsletter/Resend pipeline
     ("your venue is live, here's your QR"). Cost-gated (Resend free tier).
  3. **Auto-approve** when the claimant's email domain matches the venue's
     known website domain (from Open Brewery DB `website_url`).
  4. **Weekly "update your taps?" nudge** as snapshots near their 14-day
     expiry, keeping menus fresh.

## Why this is bulletproof
- Every write is an RPC gated by an **approved claim** (`publish_tap_list`,
  `set_venue_logo`) — a signed-in stranger cannot touch a venue they don't own.
- Menus **expire after 14 days** so a stale tap list never masquerades as live.
- The public menu (`venue_menu`, `venue_brand`) is read-only and anon-safe.
- Storage is a scoped public bucket (3MB, image types only).
- The whole loop is free, which removes the only real objection at the door.

## Owner actions to fully automate (the ledger)
1. Approve inbound claims (concierge now; build `/portal/admin` to click).
2. Wire approval + inquiry emails (Resend free tier).
3. Add domain auto-approve using OBDB `website_url`.
4. Stripe link for the paid tiers when the first venue wants Featured.
