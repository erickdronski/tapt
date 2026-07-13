# Tapt Partner Workflow, end to end

How a brewery, bar, pub, or taproom goes from "never heard of us" to a live,
self-managed presence, mapped for every party. Tapt keeps the core claim, menu,
and QR workflow free. Revenue can come later from optional reach, never from
making a venue pay to keep its basic listing accurate.

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
2. **On the web**: `taptbeer.com/portal` (the self-service
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
3. Searches their venue  ----->  search_venues()  [provenance-backed map]
4. Taps "Claim"          ----->  claim_venue() -> venue_claim (pending)
                                       |
                                 5. WE APPROVE (concierge today:
                                    one SQL line; admin UI later)
                                    -> status = approved
6. Builds tap list       ----->  publish_tap_list() (1-60 taps, current until replaced)
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
| Featured rail placement, event pushes | Planned optional reach | Not self-service yet |
| Spotlight (top slot, Dispatch feature) | Planned optional reach | Not self-service yet |

## What Tapt does at each step
- **Verification (step 5):** claims are human-approved so nobody hijacks a
  venue page. **Now a one-click admin page** at `/admin` (sign in with the
  owner email, see the pending queue, Approve/Reject). Gated by the `app_admin`
  table + `is_admin()` — only the seeded owner account can see or act. Next:
  auto-approve for matching email domains.
- **Automation already live:** `partner_inquiry` and portal claims flow to the
  same tables. Approved claims can call the deployed welcome-email function;
  the portal reports delivery only when the provider confirms it.
- **Automation next (the roadmap):**
  1. ✅ **Admin approval UI** — LIVE at `/admin` (owner signs in, one-click
     Approve/Reject on the pending queue).
  2. **Approval email** is deployed; verify the production sender and Resend
     secret before treating delivery as operational. Inquiry follow-up remains
     an owner workflow.
  3. **Auto-approve** matching business email domains; generic providers stay
     in the owner review queue.
  4. **Periodic "update your taps?" nudge** based on the last publish time,
     keeping long-lived partner menus current without deleting them.

## Why this is bulletproof
- Every write is an RPC gated by an **approved claim** (`publish_tap_list`,
  `set_venue_logo`) — a signed-in stranger cannot touch a venue they don't own.
- Partner-published menus use a **10-year technical expiry** and remain current
  until the venue replaces them. Short-lived crowd sightings expire separately.
- The public menu (`venue_menu`, `venue_brand`) is read-only and anon-safe.
- Storage is a scoped public bucket (3MB, image types only).
- The whole loop is free, which removes the only real objection at the door.

## Owner actions to fully automate (the ledger)
1. Approve generic-domain and ambiguous claims in `/admin`.
2. Verify the Resend production secret, sender domain, postal address, and a
   real approval email before depending on automated delivery.
3. Review auto-approved business-domain claims and expand matching only from
   trustworthy venue website data.
4. Define and approve paid reach terms before adding any checkout link.
