-- 0012_beer_detail_and_beer_of_week.sql
--   1. pg_cron: enable + schedule the nightly trend refresh (0009 skipped it
--      because the extension wasn't installed) and the weekly BOW lock.
--   2. Beer of the Week: community-voted, ISO-week cycle, locked winners.
--   3. beer_detail: one call powering the beer page — product facts, style
--      science (BJCP-sourced), first-party stats, nutrition (when real data
--      exists), and where-to-find-it presence. Nothing invented.
--   4. Regional leaderboard from the honest beer_trend table.

-- ============================================================ 1. pg_cron
create extension if not exists pg_cron;

do $$
begin
  -- Idempotent scheduling: unschedule if present, then schedule.
  perform cron.unschedule(jobid) from cron.job where jobname in ('tapt-beer-trend-nightly', 'tapt-beer-of-week-lock');
  perform cron.schedule('tapt-beer-trend-nightly', '15 9 * * *', 'select public.refresh_beer_trend()');
  perform cron.schedule('tapt-beer-of-week-lock', '10 0 * * 1', 'select public.lock_beer_of_week()');
end $$;

-- ============================================================ 2. Beer of the Week
create table if not exists beer_of_week_winner (
  week_start date primary key,
  beer_id uuid not null references beer_catalog(id) on delete cascade,
  week_votes int not null,
  locked_at timestamptz not null default now()
);

alter table beer_of_week_winner enable row level security;
-- Reads flow through the RPCs below; writes only via lock_beer_of_week (cron).

-- Live standings for the current ISO week (Mon-Sun). A re-vote moves the vote
-- into the current window (one row per user x beer, updated_at refreshed).
create or replace function beer_of_week_standings(p_limit int default 10)
returns table (
  rank int,
  beer_id uuid,
  name text,
  style text,
  brewery_name text,
  country text,
  label_image_url text,
  week_votes int
)
language sql
stable
security definer
set search_path = public
as $$
  with week_votes as (
    select bv.beer_id as wb_id, coalesce(sum(bv.value), 0)::int as votes
    from beer_vote bv
    where coalesce(bv.updated_at, bv.created_at) >= date_trunc('week', now())
    group by bv.beer_id
  )
  select
    (row_number() over (order by wv.votes desc, b.name))::int,
    b.id, b.name, b.style, br.name, br.country, b.label_image_url,
    wv.votes
  from week_votes wv
  join beer_catalog b on b.id = wv.wb_id
  left join brewery br on br.id = b.brewery_id
  where wv.votes > 0
  order by wv.votes desc, b.name
  limit least(greatest(coalesce(p_limit, 10), 1), 25);
$$;

-- Most recent locked winner (if any).
create or replace function beer_of_week_latest_winner()
returns table (
  week_start date,
  beer_id uuid,
  name text,
  style text,
  brewery_name text,
  country text,
  label_image_url text,
  week_votes int
)
language sql
stable
security definer
set search_path = public
as $$
  select w.week_start, b.id, b.name, b.style, br.name, br.country, b.label_image_url, w.week_votes
  from beer_of_week_winner w
  join beer_catalog b on b.id = w.beer_id
  left join brewery br on br.id = b.brewery_id
  order by w.week_start desc
  limit 1;
$$;

-- Locks last week's winner (top positive net votes in that window). Cron-run;
-- inserts nothing when there were no positive votes — honest empty history.
create or replace function lock_beer_of_week()
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_week date := (date_trunc('week', now()) - interval '7 days')::date;
  v_beer uuid;
  v_votes int;
begin
  if exists (select 1 from beer_of_week_winner w where w.week_start = v_week) then
    return;
  end if;

  select bv.beer_id, coalesce(sum(bv.value), 0)::int
    into v_beer, v_votes
  from beer_vote bv
  where coalesce(bv.updated_at, bv.created_at) >= v_week
    and coalesce(bv.updated_at, bv.created_at) < v_week + 7
  group by bv.beer_id
  order by coalesce(sum(bv.value), 0) desc
  limit 1;

  if v_beer is not null and v_votes > 0 then
    insert into beer_of_week_winner (week_start, beer_id, week_votes)
    values (v_week, v_beer, v_votes);
  end if;
end;
$$;

revoke all on function beer_of_week_standings(int) from public;
revoke all on function beer_of_week_latest_winner() from public;
revoke all on function lock_beer_of_week() from public, anon, authenticated;
grant execute on function beer_of_week_standings(int) to anon, authenticated;
grant execute on function beer_of_week_latest_winner() to anon, authenticated;

-- ============================================================ 3. beer detail
create or replace function beer_detail(p_beer_id uuid)
returns table (
  id uuid,
  name text,
  style text,
  substyle text,
  abv numeric,
  ibu smallint,
  is_na_low boolean,
  gtin text,
  label_image_url text,
  label_image_license text,
  nutrition jsonb,
  data_source text,
  brewery_name text,
  brewery_country text,
  brewery_website text,
  style_family text,
  style_description text,
  style_abv_min numeric,
  style_abv_max numeric,
  style_ibu_min smallint,
  style_ibu_max smallint,
  style_srm_min smallint,
  style_srm_max smallint,
  style_source_url text,
  ups int,
  downs int,
  checkin_count int,
  avg_rating numeric,
  venues_in_country int
)
language sql
stable
security definer
set search_path = public
as $$
  select
    b.id, b.name, b.style, b.substyle, b.abv, b.ibu, b.is_na_low, b.gtin,
    b.label_image_url, b.label_image_license,
    b.external_ids->'nutrition' as nutrition,
    b.external_ids->>'source' as data_source,
    br.name, br.country, br.website_url,
    sr.style_family, sr.description,
    sr.abv_min, sr.abv_max, sr.ibu_min, sr.ibu_max,
    sr.color_min_srm, sr.color_max_srm, sr.source_url,
    coalesce((select count(*) filter (where bv.value = 1) from beer_vote bv where bv.beer_id = b.id), 0)::int,
    coalesce((select count(*) filter (where bv.value = -1) from beer_vote bv where bv.beer_id = b.id), 0)::int,
    coalesce((select count(*) from checkin_event ce where ce.beer_id = b.id), 0)::int,
    (select avg(ce.rating)::numeric(3,2) from checkin_event ce where ce.beer_id = b.id),
    coalesce((
      select count(*)::int from venue v
      where v.external_ids->>'country' = br.country
    ), 0)
  from beer_catalog b
  left join brewery br on br.id = b.brewery_id
  left join beer_style_reference sr on lower(sr.style_name) = lower(b.style)
  where b.id = p_beer_id;
$$;

revoke all on function beer_detail(uuid) from public;
grant execute on function beer_detail(uuid) to anon, authenticated;

-- ============================================================ 4. regional board
-- Local leaderboard straight from the honest per-region trend table.
create or replace function leaderboard_beers_regional(p_region text, p_limit int default 20)
returns table (
  beer_id uuid,
  name text,
  style text,
  brewery_name text,
  country text,
  region text,
  popularity int,
  momentum int,
  avg_rating numeric
)
language sql
stable
security definer
set search_path = public
as $$
  select bt.beer_id, b.name, b.style, br.name, br.country, bt.region,
         bt.popularity, bt.momentum, bt.avg_rating
  from beer_trend bt
  join beer_catalog b on b.id = bt.beer_id
  left join brewery br on br.id = b.brewery_id
  where bt.region = p_region
  order by bt.popularity desc, bt.momentum desc, b.name
  limit least(greatest(coalesce(p_limit, 20), 1), 50);
$$;

revoke all on function leaderboard_beers_regional(text, int) from public;
grant execute on function leaderboard_beers_regional(text, int) to anon, authenticated;
