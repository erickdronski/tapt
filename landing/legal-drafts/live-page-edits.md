# Edits needed on the LIVE privacy.html / terms.html (+ email footer copy)

Draft for owner review. Prepared by an AI assistant, not a lawyer. Do not apply
without attorney sign-off on the substantive items. Live pages were NOT touched.
Diff-style: `-` current live text, `+` proposed replacement.

## landing/privacy.html

### P1. Fill the placeholders (blocks App Review: policy must be functional)
```diff
- <b>Last updated:</b> <em>[DATE, to be completed]</em> · <b>Effective:</b> <em>[DATE, to be completed]</em>
+ <b>Last updated:</b> [real date] · <b>Effective:</b> [real date]

- contact us at <em>[PRIVACY_EMAIL, to be completed]</em>
+ contact us at <a href="mailto:hello@taptbeer.com">hello@taptbeer.com</a>

- <em>[COMPANY_LEGAL_NAME, to be completed]</em> · <em>[ADDRESS, to be completed]</em> · <em>[PRIVACY_EMAIL, to be completed]</em>
+ [Legal entity name] · [Postal address] · hello@taptbeer.com
```
OWNER: entity + address depend on the LLC filing. CCPA expects two contact
methods; email + postal address covers it.

### P2. Remove the counsel banner only when review is done (privacy.html:18)
The yellow "pending attorney review" banner is honest and should STAY until an
attorney signs off. Flagging so it is a deliberate launch gate, not a leftover.

### P3. Cover the web newsletter signup (Section 2 lists app data only)
The Dispatch form on / and /dispatch collects emails from people with no
account (edge fn `dispatch-signup` → `newsletter_subscriber` with consent text).
```diff
  <li><b>Device &amp; usage:</b> app version, device type, and basic diagnostics.</li>
+ <li><b>Newsletter:</b> if you sign up for The Tapt Dispatch (in the app or on
+ this site), your email address and your signup choice. Unsubscribe any time
+ from the link in every issue or in the app under Profile.</li>
```

### P4. Cover business/partner data (portal collects it today)
Portal collects business contact emails, venue claims, inquiry messages, and
uploaded logos (`claim_venue`, `submit_partner_inquiry`, partner-assets bucket).
```diff
  <li><b>Device &amp; usage:</b> app version, device type, and basic diagnostics.</li>
+ <li><b>Business accounts:</b> if you use Tapt for Business, your work email,
+ venue claim details, inquiry messages, and any logo you upload.</li>
```

### P5. Name the real in-app controls (Section 5 is vaguer than the app)
The app has Profile → Privacy Choices toggles (location, aggregate analytics,
data sale) recorded in a consent ledger, plus real in-app deletion
(`delete_my_account`). Say so.
```diff
- <li><b>Do Not Sell or Share My Personal Information / Limit Use of Sensitive Information:</b> contact us at <em>[PRIVACY_EMAIL, to be completed]</em> or use the in-app control. We honor Global Privacy Control signals where required.</li>
+ <li><b>Do Not Sell or Share My Personal Information / Limit Use of Sensitive Information:</b> turn off "Partner insight aggregates" under Profile → Privacy Choices in the app, or email hello@taptbeer.com. Each choice is recorded with a timestamp and applies from then on. We honor Global Privacy Control signals where required.</li>

- <li><b>Access, correction, deletion, and portability:</b> you can request these, and you can delete your account in-app.</li>
+ <li><b>Access, correction, deletion, and portability:</b> you can request these at hello@taptbeer.com. Account deletion is built in: Profile → delete account removes your votes, check-ins, profile, follows, and sign-in identity immediately.</li>
```

### P6. Age: add the under-13 floor and the no-DOB fact
```diff
- <p>Tapt is intended only for people of <b>legal drinking age</b> in their location (21+ in the United States; 18+ or the applicable age elsewhere). We do not knowingly collect information from anyone under the legal drinking age. If you are not of legal drinking age, do not use the App.</p>
+ <p>Tapt is intended only for people of <b>legal drinking age</b> in their location (21+ in the United States; 18+ or the applicable age elsewhere), and never for anyone under 13. We do not knowingly collect information from anyone under the legal drinking age. We ask you to confirm your age; we store only that confirmation, never your date of birth. If you are not of legal drinking age, do not use the App.</p>
```

### P7. Cosmetic: stray backticks render literally (privacy.html:20)
```diff
- Placeholders in `<em>[, to be completed]</em>` must be completed
+ Placeholders in <em>[brackets]</em> must be completed
```
(Same artifact on terms.html:20.)

## landing/terms.html

### T1. Fill the placeholders
```diff
- <b>Last updated:</b> <em>[DATE, to be completed]</em>
+ <b>Last updated:</b> [real date]

- Our total liability is limited to the greater of the amount you paid us (if any) or <em>[LIABILITY_CAP, to be completed]</em>.
+ Our total liability is limited to the greater of the amount you paid us (if any) or $50.  [attorney to confirm cap]

- These Terms are governed by the laws of <em>[GOVERNING_LAW, to be completed]</em>, without regard to conflict-of-laws rules. <em>[DISPUTE_RESOLUTION, to be completed]</em>
+ These Terms are governed by the laws of the State of New Jersey, without regard to conflict-of-laws rules. [Attorney: choose arbitration vs. courts; NJ venue matches the planned LLC.]

- <em>[COMPANY_LEGAL_NAME, to be completed]</em> · <em>[ADDRESS, to be completed]</em> · <em>[LEGAL_EMAIL, to be completed]</em>
+ [Legal entity name] · [Postal address] · hello@taptbeer.com
```

### T2. Link the Community Guidelines + state the moderation promise (§4)
App Store 1.2 wants published UGC policy, report/block (both exist in the app:
`report_content`, `block_user`, verified live), and a response commitment.
```diff
- <p>You are responsible for your account and for the ratings, photos, and other content you post. Do not post unlawful, infringing, harassing, or misleading content. We may remove content and suspend accounts that violate these Terms, and we provide tools to report and block content and users.</p>
+ <p>You are responsible for your account and for the ratings, photos, and other content you post. Do not post unlawful, infringing, harassing, or misleading content. Our <a href="/community-guidelines">Community Guidelines</a> are part of these Terms. Every post can be reported and every user can be blocked from inside the app. We review reports of objectionable content and act within 24 hours, removing the content and ejecting offending users where warranted.</p>
```

### T3. Add a user content license (currently missing; needed to display
check-ins, photos, and notes on leaderboards, feeds, and share cards)
```diff
  <h2>6. Ratings and data</h2>
+ <p>You keep ownership of the content you post. You grant Tapt a non-exclusive,
+ worldwide, royalty-free license to host, display, and reproduce that content in
+ the App and in features that show it to other users (feeds, leaderboards,
+ share cards). Deleting content or your account ends this license, except for
+ the aggregated, de-identified data described below.</p>
  <p>Ratings and community content reflect users&#x27; opinions, not Tapt&#x27;s. ...</p>
```

### T4. Add a copyright/DMCA section (nothing exists anywhere today)
```diff
  <h2>7. Assignment</h2>
+ <h2>7. Copyright complaints</h2>
+ <p>If you believe content on Tapt infringes your copyright, send a takedown
+ notice to our designated agent: [DMCA_AGENT_NAME, ADDRESS] or
+ hello@taptbeer.com with subject "DMCA". Include the work, the location of the
+ infringing material, your contact information, a good-faith statement, a
+ statement of accuracy under penalty of perjury, and your signature. We remove
+ infringing content and terminate repeat infringers.</p>
+ <h2>8. Assignment</h2>  [renumber following sections]
```
OWNER ACTION: register the agent in the U.S. Copyright Office DMCA directory
(online, small fee) or the §512 safe harbor does not apply.

### T5. Add the Apple app-store clause (standard for iOS distribution)
```diff
  <h2>11. Changes</h2>
+ <h2>App Store</h2>
+ <p>The App is distributed through the Apple App Store. Apple is not a party to
+ these Terms, has no obligation to provide support or maintenance for the App,
+ and is a third-party beneficiary of these Terms with the right to enforce them
+ against you. Your use must also comply with the App Store Terms of Service.</p>
```

### T6. Strengthen the venue-data disclaimer (§8) to match how menus work
```diff
- <p>The App is provided &quot;as is&quot; without warranties of any kind. Beer information, availability, and locations may be inaccurate or out of date. We are not responsible for the conduct of any user or third party, on or off the App.</p>
+ <p>The App is provided &quot;as is&quot; without warranties of any kind. Beer information, availability, prices, and locations may be inaccurate or out of date. Partner menus are published by the venues themselves; crowd-reported sightings are user reports and can be stale. Verify with the venue before you go. We are not responsible for the conduct of any user, venue, or third party, on or off the App.</p>
```

### T7. Add a business-terms pointer
```diff
  <h2>2. Eligibility</h2>
+ <p>If you use Tapt for Business (venue claims, menus, paid placement), the
+ <a href="/business-terms">Business Terms</a> also apply.</p>
```

## Beyond the two pages (same review, needs code + copy)

### E1. Dispatch email footer (CAN-SPAM, HIGH severity)
`supabase/functions/dispatch-weekly/index.ts` `issueHtml()` footer must gain,
in every sent issue:
```
+ <p>[Legal entity name] · [Valid postal address]</p>
+ <p>You get this because you signed up for The Tapt Dispatch.
+   <a href="[one-click unsubscribe URL]">Unsubscribe</a></p>
```
Plus a `List-Unsubscribe` / `List-Unsubscribe-Post` header on the Resend send.
Requires a tokenized web unsubscribe endpoint: today `unsubscribe_newsletter()`
is authenticated-only, so website-only subscribers (no app account) have no way
out at all. Also fix `dispatch-signup`'s upsert: it flips `status` back to
`subscribed` on conflict, so anyone typing a previously-unsubscribed address
re-subscribes it.

### E2. Newsletter signup age line (alcohol-marketing hygiene, LOW)
Add under the Dispatch signup forms on index.html and dispatch.html:
```
+ You must be of legal drinking age to subscribe.
```

### E3. Sign-in screen terms links (app copy, MEDIUM)
`app/Tapt/Features/Auth/SignInView.swift:85` shows only the age line. Make it:
```
+ By continuing you confirm you are of legal drinking age and agree to the
+ Terms of Service and Privacy Policy.   [with tappable links via AppLinks]
```

### E4. Voice scrub while editing (owner brand rule)
Both live pages use "·" and are em-dash-free. Keep it that way in every edit
above; no em dashes, no hype adjectives.
