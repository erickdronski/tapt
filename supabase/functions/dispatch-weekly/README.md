# The Tapt Dispatch, weekly newsletter

The full pipeline that turns real live data into a weekly email.

```
subscribe            content              build + send            schedule
----------           ----------           -------------           ----------
landing form  ->     build_dispatch_      dispatch-weekly    <-    dispatch-weekly-send
dispatch-signup      content() RPC        edge function            pg_cron (Mon 15:00 UTC)
-> newsletter_       (real data only)     - mode=preview           -> pg_net POST mode=send
   subscriber                             - mode=send (Resend)
```

## What each piece does
- **`dispatch-signup`** (existing edge fn) collects emails into `newsletter_subscriber`.
- **`build_dispatch_content()`** (migration 0031) assembles a real issue from live
  data: a featured beer (real product + image), a BJCP style-science section, and
  real catalog stats. Deterministic per ISO week. Real data only, never fabricated.
- **`dispatch-weekly`** (this function) renders the branded HTML and either returns
  it (`{"mode":"preview"}`) or mails it to subscribers via Resend
  (`{"mode":"send"}`, gated by the `x-cron-secret` header). No-ops safely when
  `RESEND_API_KEY` is unset or there are no subscribers.
- **`dispatch-weekly-send`** (pg_cron) fires the send every Monday 15:00 UTC via
  `pg_net`, reading the secret from Supabase Vault (`dispatch_cron_secret`).

## Owner actions to turn on sending (until then it no-ops, never errors)
1. Create a free Resend account, verify a sending domain (or use the test sender),
   and set the edge-function secret **`RESEND_API_KEY`** (Supabase dashboard ->
   Edge Functions -> Secrets). Optional: **`RESEND_FROM`** (e.g. `Tapt <dispatch@yourdomain>`).
2. Set the edge-function secret **`CRON_SECRET`** to the value stored in Vault, which
   you can read in the SQL editor:
   ```sql
   select decrypted_secret from vault.decrypted_secrets where name = 'dispatch_cron_secret';
   ```
   (The `dispatch-weekly-send` cron already sends this exact value in the header.)

## Preview an issue any time (no secrets needed)
```bash
curl -s -X POST https://qfwiizvqxrhjlthbjosz.supabase.co/functions/v1/dispatch-weekly \
  -H "Content-Type: application/json" \
  -H "apikey: <publishable-key>" \
  -d '{"mode":"preview"}' | jq -r .html > issue.html && open issue.html
```

## Notes
- Resend free tier sends ~100/day; the function caps a run at 100 recipients. Raise
  the cap / batch when the list grows past that.
- The cron + Vault secret are set up live in the database (not in a migration,
  since the secret is environment-specific). If you rebuild the project from
  migrations, re-run the `pg_net` + `cron.schedule` + `vault.create_secret` setup.
