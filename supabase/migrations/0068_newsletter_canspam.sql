-- 0068  Newsletter CAN-SPAM backbone (P0-10).
-- Every subscriber gets a private unsubscribe token; unsubscribes are
-- timestamped and final unless the person themselves opts back in.
alter table public.newsletter_subscriber
  add column if not exists unsubscribe_token uuid not null default gen_random_uuid(),
  add column if not exists unsubscribed_at timestamp with time zone;

create unique index if not exists newsletter_subscriber_unsub_token_idx
  on public.newsletter_subscriber (unsubscribe_token);
