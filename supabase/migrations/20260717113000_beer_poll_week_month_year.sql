-- Beer of the Week / Month / Year: a real community vote.
--
-- On app open we show the signed-in drinker the beers trending RIGHT NOW
-- (top of the Beer Market, globally) and let them thumb each one up, down, or
-- skip for the week / month / year crown. Those votes are their own signal,
-- separate from the general beer like: they decide who wears the crown.
--
-- Everything is derived from real votes. A period's slate is the live top-5 by
-- market standing (so it reflects what the world is actually drinking), a
-- period's standings are the net poll votes cast in it, and a winner only
-- exists once a period is COMPLETE and at least one beer finished net-positive.
-- Nothing is seeded or fabricated: an empty world shows an empty race.
--
-- Because beer_poll_cast always stamps the CURRENT period start server-side,
-- past periods freeze automatically -- a champion, once a period ends, is
-- immutable, so the Tapt honor badge it earns on its beer page is permanent
-- and needs no cron to lock it.
--
-- All poll RPCs are authenticated-only on purpose: they either write the
-- caller's vote or read aggregates for the signed-in home tab. The locked
-- 12-function anon contract (0081) is left completely untouched.

-- ---------------------------------------------------------------------------
-- Period math (UTC): week = Monday 00:00, month = 1st, year = Jan 1.
-- The period key stored on each vote is the period's start date as text.
-- ---------------------------------------------------------------------------
create or replace function public.tapt_period_start(p_period text, p_at timestamptz default now())
returns date language sql immutable as $$
  select case p_period
    when 'week'  then date_trunc('week',  p_at)::date
    when 'month' then date_trunc('month', p_at)::date
    when 'year'  then date_trunc('year',  p_at)::date
  end;
$$;

create or replace function public.tapt_period_prev_start(p_period text, p_at timestamptz default now())
returns date language sql immutable as $$
  select case p_period
    when 'week'  then (date_trunc('week',  p_at) - interval '7 days')::date
    when 'month' then (date_trunc('month', p_at) - interval '1 month')::date
    when 'year'  then (date_trunc('year',  p_at) - interval '1 year')::date
  end;
$$;

create or replace function public.tapt_period_label(p_period text, p_start date)
returns text language sql immutable as $$
  select case p_period
    when 'week'  then 'Week of ' || to_char(p_start, 'FMMon FMDD')
    when 'month' then to_char(p_start, 'FMMonth YYYY')
    when 'year'  then to_char(p_start, 'YYYY')
  end;
$$;

-- ---------------------------------------------------------------------------
-- One row = one drinker's up / down / skip on one candidate in one period.
-- vote: 1 love, -1 nah, 0 skip (skip is remembered so we never re-prompt).
-- ---------------------------------------------------------------------------
create table if not exists public.beer_poll_vote (
  id          bigint generated always as identity primary key,
  user_id     uuid not null references auth.users(id) on delete cascade,
  period      text not null check (period in ('week','month','year')),
  period_key  text not null,
  beer_id     uuid not null references public.beer_catalog(id) on delete cascade,
  vote        smallint not null check (vote in (-1,0,1)),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (user_id, period, period_key, beer_id)
);

create index if not exists beer_poll_vote_period_idx
  on public.beer_poll_vote (period, period_key, beer_id);
create index if not exists beer_poll_vote_beer_idx
  on public.beer_poll_vote (beer_id);

alter table public.beer_poll_vote enable row level security;

drop policy if exists beer_poll_vote_self_select on public.beer_poll_vote;
create policy beer_poll_vote_self_select on public.beer_poll_vote
  for select using (user_id = auth.uid());
drop policy if exists beer_poll_vote_self_insert on public.beer_poll_vote;
create policy beer_poll_vote_self_insert on public.beer_poll_vote
  for insert with check (user_id = auth.uid());
drop policy if exists beer_poll_vote_self_update on public.beer_poll_vote;
create policy beer_poll_vote_self_update on public.beer_poll_vote
  for update using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- Candidates for a period: the live top-5 of the Beer Market, globally, with
-- the caller's current vote (null = not yet voted).
-- ---------------------------------------------------------------------------
create or replace function public.beer_poll_candidates(p_period text, p_limit int default 5)
returns table(
  beer_id uuid, name text, style text, brewery_name text,
  country text, label_image_url text, standing int, my_vote int
)
language sql stable security definer set search_path to 'public' as $$
  select s.beer_id, s.display_name, s.style, s.brewery, s.country, s.image_url,
         s.standing, v.vote::int
  from public.beer_market_standing s
  left join public.beer_poll_vote v
    on v.beer_id = s.beer_id
   and v.user_id = auth.uid()
   and v.period = p_period
   and v.period_key = public.tapt_period_start(p_period)::text
  where p_period in ('week','month','year')
    and s.display_name is not null
  order by s.standing desc nulls last
  limit greatest(1, least(coalesce(p_limit,5), 10));
$$;

-- Per-period count of candidates the caller has NOT acted on yet. The app asks
-- this once on launch and only raises the vote sheet when something is pending.
create or replace function public.beer_poll_pending_periods()
returns table(period text, pending int)
language sql stable security definer set search_path to 'public' as $$
  with cand as (
    select p.period, s.beer_id
    from (values ('week'),('month'),('year')) p(period)
    cross join lateral (
      select beer_id from public.beer_market_standing
      where display_name is not null
      order by standing desc nulls last
      limit 5
    ) s
  )
  select c.period,
         count(*) filter (where v.beer_id is null)::int as pending
  from cand c
  left join public.beer_poll_vote v
    on v.beer_id = c.beer_id
   and v.user_id = auth.uid()
   and v.period = c.period
   and v.period_key = public.tapt_period_start(c.period)::text
  group by c.period;
$$;

-- Cast (or change) the caller's vote on a candidate for the CURRENT period.
create or replace function public.beer_poll_cast(p_period text, p_beer uuid, p_vote int)
returns void
language plpgsql security definer set search_path to 'public' as $$
begin
  if auth.uid() is null then raise exception 'auth required'; end if;
  if p_period not in ('week','month','year') then raise exception 'bad period'; end if;
  if p_vote not in (-1,0,1) then raise exception 'bad vote'; end if;

  insert into public.beer_poll_vote(user_id, period, period_key, beer_id, vote)
  values (auth.uid(), p_period, public.tapt_period_start(p_period)::text, p_beer, p_vote::smallint)
  on conflict (user_id, period, period_key, beer_id)
  do update set vote = excluded.vote, updated_at = now();
end;
$$;

-- Live standings for the CURRENT period: net poll votes, ranked, contenders only.
create or replace function public.beer_poll_standings(p_period text, p_limit int default 10)
returns table(
  rank int, beer_id uuid, name text, style text, brewery_name text,
  country text, label_image_url text, up int, down int, net int
)
language sql stable security definer set search_path to 'public' as $$
  with tally as (
    select v.beer_id,
      count(*) filter (where v.vote = 1)  as up,
      count(*) filter (where v.vote = -1) as down
    from public.beer_poll_vote v
    where v.period = p_period
      and v.period_key = public.tapt_period_start(p_period)::text
    group by v.beer_id
  )
  select (row_number() over (order by (t.up - t.down) desc, s.standing desc nulls last))::int,
         s.beer_id, s.display_name, s.style, s.brewery, s.country, s.image_url,
         t.up::int, t.down::int, (t.up - t.down)::int
  from tally t
  join public.beer_market_standing s on s.beer_id = t.beer_id
  where (t.up + t.down) > 0
  order by (t.up - t.down) desc, s.standing desc nulls last
  limit greatest(1, least(coalesce(p_limit,10), 50));
$$;

-- The reigning champion: winner of the most recent COMPLETED period, or none.
create or replace function public.beer_poll_winner(p_period text)
returns table(
  beer_id uuid, name text, style text, brewery_name text,
  country text, label_image_url text, net int, label text
)
language sql stable security definer set search_path to 'public' as $$
  with pk as (select public.tapt_period_prev_start(p_period) d),
  tally as (
    select v.beer_id,
      sum(case when v.vote = 1 then 1 when v.vote = -1 then -1 else 0 end)::int net
    from public.beer_poll_vote v, pk
    where v.period = p_period and v.period_key = pk.d::text
    group by v.beer_id
  )
  select s.beer_id, s.display_name, s.style, s.brewery, s.country, s.image_url,
         t.net, public.tapt_period_label(p_period, (select d from pk))
  from tally t
  join public.beer_market_standing s on s.beer_id = t.beer_id
  where t.net > 0
  order by t.net desc, s.standing desc nulls last
  limit 1;
$$;

-- Every COMPLETED period this beer has won: the source of its permanent Tapt
-- honor badges on its beer page. Only net-positive, finished-period wins count.
create or replace function public.beer_poll_wins(p_beer uuid)
returns table(period text, period_key text, net int, label text)
language sql stable security definer set search_path to 'public' as $$
  with periods as (
    select distinct v.period, v.period_key
    from public.beer_poll_vote v
    where v.period_key < public.tapt_period_start(v.period)::text
  ),
  ranked as (
    select v.period, v.period_key, v.beer_id,
      sum(case when v.vote = 1 then 1 when v.vote = -1 then -1 else 0 end)::int net,
      row_number() over (
        partition by v.period, v.period_key
        order by sum(case when v.vote = 1 then 1 when v.vote = -1 then -1 else 0 end) desc
      ) rn
    from public.beer_poll_vote v
    join periods p on p.period = v.period and p.period_key = v.period_key
    group by v.period, v.period_key, v.beer_id
  )
  select r.period, r.period_key, r.net,
         public.tapt_period_label(r.period, r.period_key::date)
  from ranked r
  where r.beer_id = p_beer and r.rn = 1 and r.net > 0
  order by r.period_key desc;
$$;

-- Authenticated-only surface. Anon contract (0081) intentionally untouched.
revoke all on function public.beer_poll_candidates(text,int)     from public;
revoke all on function public.beer_poll_pending_periods()        from public;
revoke all on function public.beer_poll_cast(text,uuid,int)      from public;
revoke all on function public.beer_poll_standings(text,int)      from public;
revoke all on function public.beer_poll_winner(text)             from public;
revoke all on function public.beer_poll_wins(uuid)               from public;

grant execute on function public.beer_poll_candidates(text,int)  to authenticated;
grant execute on function public.beer_poll_pending_periods()     to authenticated;
grant execute on function public.beer_poll_cast(text,uuid,int)   to authenticated;
grant execute on function public.beer_poll_standings(text,int)   to authenticated;
grant execute on function public.beer_poll_winner(text)          to authenticated;
grant execute on function public.beer_poll_wins(uuid)            to authenticated;
