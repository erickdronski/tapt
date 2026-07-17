-- Picked for you, weekly and remembered.
--
-- Before: recommend_beer re-rolled every day (a current_date jitter), so the
-- home card churned constantly and a pick a user liked was gone by the time they
-- reached a pub. Now the pick is materialized once per ISO week per user in
-- user_beer_pick: stable all week, recomputed fresh each new week from the
-- user's LATEST taste signals (votes + high-rated pours), so it naturally
-- sharpens the more they use the app. Every week's pick is kept, giving the
-- profile a real "your weekly picks" log to reference later.
--
-- No fabrication: the pick still comes straight from recommend_beer (real taste
-- signals, honest reason), and an empty-signal user simply gets no row.

create table if not exists public.user_beer_pick (
  user_id    uuid not null references auth.users(id) on delete cascade,
  week_start date not null,
  beer_id    uuid not null references public.beer_catalog(id) on delete cascade,
  reason     text,
  match_kind text,
  created_at timestamptz not null default now(),
  primary key (user_id, week_start)
);

create index if not exists user_beer_pick_user_week_idx
  on public.user_beer_pick (user_id, week_start desc);

alter table public.user_beer_pick enable row level security;
-- Read your own log. Writes happen only through the SECURITY DEFINER function
-- below, so there is intentionally no client insert/update/delete policy.
drop policy if exists user_beer_pick_self_select on public.user_beer_pick;
create policy user_beer_pick_self_select on public.user_beer_pick
  for select using (user_id = auth.uid());

-- This week's pick. Materializes it once (recompute on a fresh week), then
-- returns the stored beer resolved to current display fields, so the image
-- upgrades on its own once a reviewed cutout exists.
create or replace function public.weekly_pick(p_user uuid default null)
returns table(
  beer_id uuid, name text, brewery text, style text, country text,
  image_url text, abv numeric, reason text, match_kind text, week_start date
)
language plpgsql volatile security definer set search_path to 'public' as $$
-- RETURNS TABLE exposes week_start as an OUT variable; force column-first
-- resolution so it is unambiguous in the insert / on-conflict below.
#variable_conflict use_column
declare
  -- Prefer the real session; fall back to the passed id (same trust model as
  -- recommend_beer, so this also works from the simulator's shimmed session).
  uid uuid := coalesce(auth.uid(), p_user);
  wk  date := date_trunc('week', now())::date;
begin
  if uid is null then return; end if;

  if not exists (
    select 1 from public.user_beer_pick p where p.user_id = uid and p.week_start = wk
  ) then
    insert into public.user_beer_pick(user_id, week_start, beer_id, reason, match_kind)
    select uid, wk, r.beer_id, r.reason, r.match_kind
    from public.recommend_beer(uid) r
    limit 1
    on conflict (user_id, week_start) do nothing;
  end if;

  return query
    select b.id,
           coalesce(nullif(b.display_name, ''), b.name),
           br.name,
           b.style_ref,
           public.tapt_trusted_country(br.country, br.external_ids),
           coalesce(b.cutout_url, b.label_image_url),
           b.abv,
           p.reason, p.match_kind, p.week_start
    from public.user_beer_pick p
    join public.beer_catalog b on b.id = p.beer_id
    left join public.brewery br on br.id = b.brewery_id
    where p.user_id = uid and p.week_start = wk;
end;
$$;

-- The log: past weekly picks, newest first, for the profile.
drop function if exists public.pick_history(int);
create or replace function public.pick_history(p_user uuid default null, p_limit int default 24)
returns table(
  beer_id uuid, name text, brewery text, style text, country text,
  image_url text, abv numeric, reason text, match_kind text, week_start date
)
language sql stable security definer set search_path to 'public' as $$
  select b.id,
         coalesce(nullif(b.display_name, ''), b.name),
         br.name,
         b.style_ref,
         public.tapt_trusted_country(br.country, br.external_ids),
         coalesce(b.cutout_url, b.label_image_url),
         b.abv, p.reason, p.match_kind, p.week_start
  from public.user_beer_pick p
  join public.beer_catalog b on b.id = p.beer_id
  left join public.brewery br on br.id = b.brewery_id
  where p.user_id = coalesce(auth.uid(), p_user)
  order by p.week_start desc
  limit greatest(1, least(coalesce(p_limit, 24), 100));
$$;

revoke all on function public.weekly_pick(uuid)          from public;
revoke all on function public.pick_history(uuid, int)    from public;
grant execute on function public.weekly_pick(uuid)       to authenticated;
grant execute on function public.pick_history(uuid, int) to authenticated;
