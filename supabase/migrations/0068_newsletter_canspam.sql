-- 0068_newsletter_canspam.sql
-- Mirror of the production migration applied on 2026-07-12.
-- Every subscriber gets a private unsubscribe token and a durable timestamp.

alter table public.newsletter_subscriber
  add column if not exists unsubscribe_token uuid not null default gen_random_uuid(),
  add column if not exists unsubscribed_at timestamp with time zone;

create unique index if not exists newsletter_subscriber_unsub_token_idx
  on public.newsletter_subscriber (unsubscribe_token);
