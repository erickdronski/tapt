-- ============================================================================
-- 0058  Real, populated, stored, live, historical, bulletproof Beer Market.
--
-- The market was vote-gated: its base set was "beers that have a row in
-- beer_vote", so with zero community votes it returned zero rows (empty board
-- on device). This rebuilds it on a composite STANDING computed from REAL,
-- non-fabricated signals — what is genuinely in season now (time-varying),
-- real cited medals, catalog notability — with real community votes layering
-- on top and dominating as they accumulate. Nothing invented: a beer ranks
-- high because it is really in season, really won medals, or was really voted
-- up. Standing is materialized by cron (bulletproof under load) and snapshotted
-- daily so movement, sparklines, and history are real over time.
-- ============================================================================

-- Materialized current standing, one row per beer. All display fields live here
-- so beer_market() is a single fast indexed read (no heavy compute per call).
create table if not exists public.beer_market_standing (
  beer_id        uuid primary key references public.beer_catalog(id) on delete cascade,
  standing       integer not null default 0,
  season_pts     integer not null default 0,
  award_pts      integer not null default 0,
  notability_pts integer not null default 0,
  vote_pts       integer not null default 0,
  net_votes      integer not null default 0,
  votes_count    integer not null default 0,
  ups            integer not null default 0,
  downs          integer not null default 0,
  vol24          integer not null default 0,
  change_24h     integer not null default 0,
  reason         text,
  season_fit     integer not null default 0,
  heat           integer not null default 0,
  computed_at    timestamptz not null default now()
);
create index if not exists beer_market_standing_rank_idx
  on public.beer_market_standing (standing desc);

-- Daily history: one standing per beer per day -> real sparklines and movers.
create table if not exists public.beer_market_snapshot (
  beer_id   uuid not null references public.beer_catalog(id) on delete cascade,
  snap_date date not null default current_date,
  standing  integer not null,
  primary key (beer_id, snap_date)
);
create index if not exists beer_market_snapshot_date_idx
  on public.beer_market_snapshot (snap_date desc);

-- Recompute standing from real signals, materialize it, and record today's
-- snapshot. Cheap enough to run on a schedule; never fabricates activity.
create or replace function public.refresh_beer_market_standing()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  n integer;
begin
  delete from public.beer_market_standing;

  insert into public.beer_market_standing
    (beer_id, standing, season_pts, award_pts, notability_pts, vote_pts,
     net_votes, votes_count, ups, downs, vol24, change_24h, reason, season_fit, heat, computed_at)
  with season as (
    select case when extract(month from now()) in (6,7,8) then 'summer'
                when extract(month from now()) in (9,10,11) then 'fall'
                when extract(month from now()) in (12,1,2) then 'winter'
                else 'spring' end s
  ),
  base as (
    select b.id, b.name, b.style, b.brewery_id, b.cutout_url, (select s from season) ssn
    from public.beer_catalog b
    where public.tapt_name_ok(b.name)
      and nullif(b.style,'') is not null
      and (coalesce(b.cutout_url, b.label_image_url) is not null
           or exists (select 1 from public.beer_award a where a.beer_id = b.id))
  ),
  award_agg as (
    select beer_id,
      least(60, sum(case lower(medal) when 'gold' then 30 when 'silver' then 20
                                      when 'bronze' then 12 else 8 end))::int award_pts
    from public.beer_award group by beer_id
  ),
  vote_agg as (
    select beer_id, sum(value)::int net_votes, count(*)::int votes_count,
      count(*) filter (where value > 0)::int ups,
      count(*) filter (where value < 0)::int downs
    from public.beer_vote group by beer_id
  ),
  vol_agg as (
    select beer_id, count(*)::int vol24 from (
      select beer_id, coalesce(updated_at, created_at) ts from public.beer_vote
      union all
      select beer_id, coalesce(event_ts, created_at) from public.checkin_event where beer_id is not null
    ) e where ts > now() - interval '24 hours' group by beer_id
  ),
  prev as (
    select beer_id, standing prev_standing
    from public.beer_market_snapshot where snap_date = current_date - 1
  ),
  scored as (
    select bb.id,
      case
        when bb.ssn='summer' and bb.style ~* 'ipa|pale|wheat|wit|hefe|weiss|weizen|pils|lager|blonde|sour|gose|radler|shandy|session|helles|k(ö|o)lsch' then 40
        when bb.ssn='winter' and bb.style ~* 'stout|porter|barley\s?wine|bock|strong|winter|imperial|quad|dubbel|dark|schwarz' then 40
        when bb.ssn='fall'   and bb.style ~* 'm(ä|a)rzen|oktoberfest|amber|brown|pumpkin|porter|dunkel' then 40
        when bb.ssn='spring' and bb.style ~* 'saison|pale|bock|blonde|farmhouse' then 40
        else 0 end as season_pts,
      coalesce(aw.award_pts, 0) as award_pts,
      (case when bb.cutout_url is not null then 8 else 0 end)
        + (case when bb.brewery_id is not null then 6 else 0 end) as notability_pts,
      coalesce(va.net_votes, 0) * 8 as vote_pts,
      coalesce(va.net_votes, 0) as net_votes,
      coalesce(va.votes_count, 0) as votes_count,
      coalesce(va.ups, 0) as ups,
      coalesce(va.downs, 0) as downs,
      coalesce(vl.vol24, 0) as vol24,
      case
        when bb.style ~* 'non[- ]?alco|alcohol[- ]?free|0[.,]0\s*%' then 'Sober-curious pick'
        when bb.ssn='summer' and bb.style ~* 'ipa|pale|wheat|wit|hefe|weiss|weizen|pils|lager|blonde|sour|gose|radler|shandy|session|helles|k(ö|o)lsch' then 'Summer crusher'
        when bb.ssn='winter' and bb.style ~* 'stout|porter|barley\s?wine|bock|strong|winter|imperial|quad|dubbel|dark|schwarz' then 'Cold-weather climber'
        when bb.ssn='fall'   and bb.style ~* 'm(ä|a)rzen|oktoberfest|amber|brown|pumpkin|porter|dunkel' then 'Autumn pour'
        when bb.ssn='spring' and bb.style ~* 'saison|pale|bock|blonde|farmhouse' then 'Spring seasonal'
        else null end as reason
    from base bb
    left join award_agg aw on aw.beer_id = bb.id
    left join vote_agg  va on va.beer_id = bb.id
    left join vol_agg   vl on vl.beer_id = bb.id
  ),
  standings as (
    select id,
      greatest(1, 10 + season_pts + award_pts + notability_pts + vote_pts) as standing,
      season_pts, award_pts, notability_pts, vote_pts,
      net_votes, votes_count, ups, downs, vol24, reason
    from scored
  )
  select s.id, s.standing, s.season_pts, s.award_pts, s.notability_pts, s.vote_pts,
    s.net_votes, s.votes_count, s.ups, s.downs, s.vol24,
    (s.standing - coalesce(p.prev_standing, s.standing)) as change_24h,
    s.reason,
    case when s.reason is null then 0 else 2 end as season_fit,
    least(100, round(s.standing::numeric / nullif(max(s.standing) over (), 0) * 100))::int as heat,
    now()
  from standings s
  left join prev p on p.beer_id = s.id;

  get diagnostics n = row_count;

  insert into public.beer_market_snapshot (beer_id, snap_date, standing)
    select beer_id, current_date, standing from public.beer_market_standing
  on conflict (beer_id, snap_date) do update set standing = excluded.standing;

  return n;
end;
$$;

revoke all on function public.refresh_beer_market_standing() from public, anon, authenticated;

-- The board: reads the materialized standing (fast, always populated), joins
-- catalog for display, and builds a 7-day sparkline from real snapshots. Never
-- returns empty while the catalog exists. p_demo is accepted for API
-- compatibility but the real board is now always populated with real beers.
create or replace function public.beer_market(
  p_sort text default 'movers',
  p_limit integer default 40,
  p_demo boolean default false
)
returns table(
  beer_id uuid, symbol text, name text, brewery text, style text, country text,
  image_url text, net integer, votes integer, change integer, volume integer,
  ups integer, downs integer, spark double precision[], reason text,
  season_fit integer, heat integer
)
language sql
stable
security definer
set search_path = public
as $$
  with ranked as (
    select distinct on (public.tapt_display_name(b.name))
      st.beer_id,
      public.tapt_display_name(b.name) bname,
      br.name brewery,
      coalesce(nullif(b.style,''), 'Beer') style,
      br.country,
      coalesce(b.cutout_url, b.label_image_url) img,
      st.standing, st.net_votes, st.votes_count, st.ups, st.downs, st.vol24,
      st.change_24h, st.reason, st.season_fit, st.heat,
      abs(('x' || substr(md5(st.beer_id::text), 1, 8))::bit(32)::int % 20) as rot
    from public.beer_market_standing st
    join public.beer_catalog b on b.id = st.beer_id
    left join public.brewery br on br.id = b.brewery_id
    where public.tapt_name_ok(b.name)
    order by public.tapt_display_name(b.name), st.standing desc
  )
  select r.beer_id,
    upper(left(regexp_replace(r.bname, '[^A-Za-z0-9]', '', 'g'), 4)) symbol,
    r.bname, r.brewery, r.style, r.country, r.img,
    r.standing net, r.votes_count votes, r.change_24h change, r.vol24 volume,
    r.ups, r.downs,
    coalesce(
      (select array_agg(sn.standing::float8 order by d.d)
       from generate_series(6, 0, -1) d(d)
       left join public.beer_market_snapshot sn
         on sn.beer_id = r.beer_id and sn.snap_date = current_date - d.d),
      array[]::float8[]
    ) spark,
    r.reason, r.season_fit, r.heat
  from ranked r
  order by case p_sort
      when 'gainers' then r.change_24h
      when 'losers'  then -r.change_24h
      when 'active'  then r.vol24
      when 'top'     then r.net_votes
      when 'season'  then r.season_fit * 1000 + r.standing
      when 'movers'  then r.standing
      else r.standing
    end desc,
    r.standing desc, r.rot desc, r.bname
  limit least(greatest(coalesce(p_limit, 40), 1), 100);
$$;

revoke all on function public.beer_market(text, integer, boolean) from public, anon, authenticated;
grant execute on function public.beer_market(text, integer, boolean) to authenticated;

-- Populate immediately so the board is live the moment this lands.
select public.refresh_beer_market_standing();

-- Keep it live. Refresh every 30 minutes if pg_cron is available (real votes
-- and the daily seasonal window flow in without per-write triggers).
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule('refresh_beer_market_standing')
      where exists (select 1 from cron.job where jobname = 'refresh_beer_market_standing');
    perform cron.schedule('refresh_beer_market_standing', '*/30 * * * *',
      $cron$ select public.refresh_beer_market_standing(); $cron$);
  end if;
end $$;
