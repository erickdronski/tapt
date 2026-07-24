-- Make the Beer Market filters honest, restore guest access to the public
-- board, and expose a small privacy-safe pulse for the app's live state.

-- The standing refresh is repeated here because beer_market_v2 is becoming
-- anon-readable. Explicit votes remain public community actions. Check-ins are
-- included only when visible and covered by current aggregate consent.
create or replace function public.refresh_beer_market_standing()
returns integer
language plpgsql
security definer
set search_path = public
as $function$
declare
  n integer;
begin
  delete from public.beer_market_standing;

  insert into public.beer_market_standing
    (beer_id, standing, season_pts, award_pts, notability_pts, vote_pts, drift_pts,
     net_votes, votes_count, ups, downs, vol24, change_24h, reason, season_fit, heat,
     display_name, symbol, brewery, style, country, image_url, rot, computed_at)
  with season as (
    select case when extract(month from now()) in (6,7,8) then 'summer'
                when extract(month from now()) in (9,10,11) then 'fall'
                when extract(month from now()) in (12,1,2) then 'winter'
                else 'spring' end s
  ),
  base as (
    select b.id, b.name, b.style_ref as style, b.brewery_id, b.cutout_url,
           coalesce(b.cutout_url, b.label_image_url) img,
           (select s from season) ssn
    from public.beer_catalog b
    where b.name_ok
      and (
        (b.style_ref is not null
         and coalesce(b.cutout_url, b.label_image_url) is not null)
        or exists (select 1 from public.beer_award a where a.beer_id = b.id)
        or exists (
          select 1
          from public.beer_vote v
          join public.user_profile up on up.id = v.user_id
          where v.beer_id = b.id
            and up.account_moderation_status = 'active'
        )
        or exists (
          select 1
          from public.checkin_event c
          where c.beer_id = b.id
            and c.moderation_status = 'visible'
            and public.has_current_consent(c.user_id, 'aggregate_analytics')
        )
      )
  ),
  award_agg as (
    select beer_id,
      least(60, sum(case lower(medal) when 'gold' then 30 when 'silver' then 20
                                      when 'bronze' then 12 else 8 end))::int award_pts
    from public.beer_award group by beer_id
  ),
  vote_agg as (
    select v.beer_id, sum(v.value)::int net_votes, count(*)::int votes_count,
      count(*) filter (where v.value > 0)::int ups,
      count(*) filter (where v.value < 0)::int downs,
      coalesce(sum(v.value) filter (
        where coalesce(v.updated_at, v.created_at) > now() - interval '7 days'
      ), 0)::int net_votes_7d
    from public.beer_vote v
    join public.user_profile up on up.id = v.user_id
    where up.account_moderation_status = 'active'
    group by v.beer_id
  ),
  pour_agg as (
    select beer_id,
      count(*) filter (where coalesce(event_ts, created_at) > now() - interval '7 days')::int pours_7d,
      count(*) filter (where coalesce(event_ts, created_at) > now() - interval '30 days')::int pours_30d
    from public.checkin_event
    where beer_id is not null
      and moderation_status = 'visible'
      and public.has_current_consent(user_id, 'aggregate_analytics')
      and coalesce(event_ts, created_at) > now() - interval '30 days'
      and coalesce(event_ts, created_at) <= now()
    group by beer_id
  ),
  vol_agg as (
    select beer_id, count(*)::int vol24
    from (
      select v.beer_id, coalesce(v.updated_at, v.created_at) ts
      from public.beer_vote v
      join public.user_profile up on up.id = v.user_id
      where up.account_moderation_status = 'active'
      union all
      select beer_id, coalesce(event_ts, created_at)
      from public.checkin_event
      where beer_id is not null
        and moderation_status = 'visible'
        and public.has_current_consent(user_id, 'aggregate_analytics')
        and coalesce(event_ts, created_at) > now() - interval '24 hours'
        and coalesce(event_ts, created_at) <= now()
    ) e
    where ts > now() - interval '24 hours'
    group by beer_id
  ),
  engaged as (
    select beer_id, max(ts)::date as last_engaged
    from (
      select v.beer_id, coalesce(v.updated_at, v.created_at) ts
      from public.beer_vote v
      join public.user_profile up on up.id = v.user_id
      where up.account_moderation_status = 'active'
      union all
      select beer_id, coalesce(event_ts, created_at)
      from public.checkin_event
      where beer_id is not null
        and moderation_status = 'visible'
        and public.has_current_consent(user_id, 'aggregate_analytics')
    ) e
    group by beer_id
  ),
  birth as (
    select beer_id, min(snap_date) as first_seen
    from public.beer_market_snapshot group by beer_id
  ),
  prev as (
    select beer_id, standing prev_standing
    from public.beer_market_snapshot where snap_date = current_date - 1
  ),
  scored as (
    select bb.id, bb.brewery_id, bb.img, bb.cutout_url, bb.ssn,
      b2.display_name as dname,
      coalesce(b2.style_ref, 'Beer') as style,
      public.tapt_season_points(bb.style, current_date) as season_pts,
      (public.tapt_season_points(bb.style, current_date)
        - public.tapt_season_points(bb.style, current_date - 1)) as season_drift,
      coalesce(aw.award_pts, 0) as award_pts,
      (case when bb.cutout_url is not null then 8 when bb.img is not null then 4 else 0 end)
        + (case when bb.brewery_id is not null then 5 else 0 end)
        + (case when b2.abv is not null then 3 else 0 end)
        + (case when b2.style_ref is not null then 3 else 0 end) as notability_pts,
      (coalesce(pa.pours_7d, 0) * 10
        + coalesce(pa.pours_30d, 0) * 2
        + greatest(coalesce(va.net_votes_7d, 0), 0) * 6
        + least(20, greatest(coalesce(va.net_votes, 0), 0) * 4))::int as vote_pts,
      least(15, (ceiling(greatest(0,
          (current_date - coalesce(en.last_engaged, bi.first_seen, current_date)) - 14
        )::numeric / 7) * 2))::int as drift_pts,
      coalesce(va.net_votes, 0) as net_votes,
      coalesce(va.votes_count, 0) as votes_count,
      coalesce(va.ups, 0) as ups,
      coalesce(va.downs, 0) as downs,
      coalesce(vl.vol24, 0) as vol24,
      case
        when bb.style ~* 'non[- ]?alco|alcohol[- ]?free|0[.,]0\s*%' then 'Sober-curious pick'
        when bb.ssn = 'summer' and bb.style ~* 'ipa|pale|wheat|wit|hefe|weiss|weizen|pils|lager|blonde|sour|gose|radler|shandy|session|helles|k(ö|o)lsch' then 'Summer beer, in season now'
        when bb.ssn = 'winter' and bb.style ~* 'stout|porter|barley\s?wine|bock|strong|winter|imperial|quad|dubbel|dark|schwarz' then 'Winter beer, in season now'
        when bb.ssn = 'fall' and bb.style ~* 'm(ä|a)rzen|oktoberfest|amber|brown|pumpkin|porter|dunkel' then 'Fall beer, in season now'
        when bb.ssn = 'spring' and bb.style ~* 'saison|pale|bock|blonde|farmhouse' then 'Spring beer, in season now'
        else null end as base_reason
    from base bb
    join public.beer_catalog b2 on b2.id = bb.id
    left join award_agg aw on aw.beer_id = bb.id
    left join vote_agg va on va.beer_id = bb.id
    left join pour_agg pa on pa.beer_id = bb.id
    left join vol_agg vl on vl.beer_id = bb.id
    left join engaged en on en.beer_id = bb.id
    left join birth bi on bi.beer_id = bb.id
  ),
  standings as (
    select distinct on (lower(dname))
      id, dname, style, brewery_id, img,
      greatest(1, 6 + season_pts + award_pts + notability_pts + vote_pts - drift_pts) as standing,
      season_pts, award_pts, notability_pts, vote_pts, drift_pts,
      net_votes, votes_count, ups, downs, vol24,
      coalesce(base_reason, case when drift_pts > 0 then 'Quiet lately, cooling off' end) as reason,
      season_drift
    from scored
    order by lower(dname),
      greatest(1, 6 + season_pts + award_pts + notability_pts + vote_pts - drift_pts) desc,
      votes_count desc
  )
  select s.id, s.standing, s.season_pts, s.award_pts, s.notability_pts, s.vote_pts, s.drift_pts,
    s.net_votes, s.votes_count, s.ups, s.downs, s.vol24,
    coalesce(s.standing - p.prev_standing, s.season_drift) as change_24h,
    s.reason,
    case when s.reason in (
      'Summer beer, in season now',
      'Fall beer, in season now',
      'Winter beer, in season now',
      'Spring beer, in season now'
    ) then case when s.season_pts >= 40 then 2 when s.season_pts >= 28 then 1 else 0 end
      else 0 end as season_fit,
    least(100, round(s.standing::numeric / nullif(max(s.standing) over (), 0) * 100))::int as heat,
    s.dname,
    upper(left(regexp_replace(s.dname, '[^A-Za-z0-9]', '', 'g'), 4)),
    br.name, s.style,
    public.tapt_trusted_country(br.country, br.external_ids),
    s.img,
    abs(('x' || substr(md5(s.id::text), 1, 8))::bit(32)::int % 20),
    now()
  from standings s
  left join public.brewery br on br.id = s.brewery_id
  left join prev p on p.beer_id = s.id;

  get diagnostics n = row_count;

  insert into public.beer_market_snapshot (beer_id, snap_date, standing)
    select beer_id, current_date, standing from public.beer_market_standing
  on conflict (beer_id, snap_date) do update set standing = excluded.standing;

  return n;
end;
$function$;

revoke all on function public.refresh_beer_market_standing()
  from public, anon, authenticated;
grant execute on function public.refresh_beer_market_standing() to service_role;

create or replace function public.beer_market_v2(
  p_sort text default 'movers',
  p_limit integer default 40,
  p_demo boolean default false,
  p_na_only boolean default false
)
returns table (
  beer_id uuid,
  symbol text,
  name text,
  brewery text,
  style text,
  country text,
  image_url text,
  is_na_low boolean,
  net integer,
  votes integer,
  change integer,
  volume integer,
  ups integer,
  downs integer,
  spark double precision[],
  reason text,
  season_fit integer,
  heat integer
)
language sql
stable
security definer
set search_path = public
as $function$
  with params as (
    select case lower(coalesce(p_sort, ''))
      when 'movers' then 'movers'
      when 'season' then 'season'
      when 'gainers' then 'gainers'
      when 'losers' then 'losers'
      when 'active' then 'active'
      when 'top' then 'top'
      when 'standing' then 'standing'
      else 'movers'
    end as requested_sort
  )
  select
    st.beer_id,
    st.symbol,
    st.display_name,
    st.brewery,
    st.style,
    st.country,
    st.image_url,
    b.is_na_low,
    st.standing,
    st.votes_count,
    st.change_24h,
    st.vol24,
    st.ups,
    st.downs,
    coalesce(
      (select array_agg(sn.standing::float8 order by sn.snap_date)
       from public.beer_market_snapshot sn
       where sn.beer_id = st.beer_id
         and sn.snap_date > current_date - 7),
      array[st.standing::float8]
    ),
    st.reason,
    st.season_fit,
    st.heat
  from public.beer_market_standing st
  join public.beer_catalog b on b.id = st.beer_id
  cross join params p
  where (not coalesce(p_na_only, false) or b.is_na_low)
    and case p.requested_sort
      when 'movers' then st.change_24h <> 0
      when 'gainers' then st.change_24h > 0
      when 'losers' then st.change_24h < 0
      when 'active' then st.vol24 > 0
      when 'season' then st.season_fit > 0
      when 'top' then st.votes_count > 0
      else true
    end
  order by
    case when p.requested_sort = 'movers' then abs(st.change_24h) end desc,
    case when p.requested_sort = 'movers' then st.vol24 end desc,
    case when p.requested_sort = 'gainers' then st.change_24h end desc,
    case when p.requested_sort = 'gainers' then st.vol24 end desc,
    case when p.requested_sort = 'losers' then st.change_24h end asc,
    case when p.requested_sort = 'losers' then st.vol24 end desc,
    case when p.requested_sort = 'active' then st.vol24 end desc,
    case when p.requested_sort = 'active' then abs(st.change_24h) end desc,
    case when p.requested_sort = 'season' then st.season_fit end desc,
    case when p.requested_sort = 'season' then st.season_pts end desc,
    case when p.requested_sort = 'top' then st.net_votes end desc,
    case when p.requested_sort = 'top' then st.ups end desc,
    case when p.requested_sort = 'top' then st.votes_count end desc,
    case when p.requested_sort = 'standing' then st.standing end desc,
    st.standing desc,
    st.rot desc,
    st.display_name
  limit least(greatest(coalesce(p_limit, 40), 1), 100);
$function$;

revoke all on function public.beer_market_v2(text, integer, boolean, boolean)
  from public, anon, authenticated;
grant execute on function public.beer_market_v2(text, integer, boolean, boolean)
  to anon, authenticated, service_role;

create or replace function public.beer_market_pulse()
returns table (
  computed_at timestamptz,
  tracked integer,
  moving_24h integer,
  gainers_24h integer,
  sliders_24h integer,
  active_24h integer,
  votes_24h integer,
  pours_24h integer,
  votes_7d integer,
  pours_7d integer
)
language sql
stable
security definer
set search_path = public
as $function$
  with market as (
    select
      max(st.computed_at) as computed_at,
      count(*)::int as tracked,
      count(*) filter (where st.change_24h <> 0)::int as moving_24h,
      count(*) filter (where st.change_24h > 0)::int as gainers_24h,
      count(*) filter (where st.change_24h < 0)::int as sliders_24h
    from public.beer_market_standing st
  ),
  vote_activity as (
    select
      count(*) filter (
        where coalesce(v.updated_at, v.created_at) > now() - interval '24 hours'
      )::int as votes_24h,
      count(*) filter (
        where coalesce(v.updated_at, v.created_at) > now() - interval '7 days'
      )::int as votes_7d
    from public.beer_vote v
    join public.user_profile up on up.id = v.user_id
    where up.account_moderation_status = 'active'
      and coalesce(v.updated_at, v.created_at) > now() - interval '7 days'
      and coalesce(v.updated_at, v.created_at) <= now()
  ),
  pour_activity as (
    select
      count(*) filter (
        where coalesce(event_ts, created_at) > now() - interval '24 hours'
      )::int as pours_24h,
      count(*) filter (
        where coalesce(event_ts, created_at) > now() - interval '7 days'
      )::int as pours_7d
    from public.checkin_event
    where beer_id is not null
      and moderation_status = 'visible'
      and public.has_current_consent(user_id, 'aggregate_analytics')
      and coalesce(event_ts, created_at) > now() - interval '7 days'
      and coalesce(event_ts, created_at) <= now()
  ),
  active_beers as (
    select count(distinct beer_id)::int as active_24h
    from (
      select beer_id
      from public.beer_vote v
      join public.user_profile up on up.id = v.user_id
      where up.account_moderation_status = 'active'
        and coalesce(v.updated_at, v.created_at) > now() - interval '24 hours'
        and coalesce(v.updated_at, v.created_at) <= now()
      union all
      select beer_id
      from public.checkin_event
      where beer_id is not null
        and moderation_status = 'visible'
        and public.has_current_consent(user_id, 'aggregate_analytics')
        and coalesce(event_ts, created_at) > now() - interval '24 hours'
        and coalesce(event_ts, created_at) <= now()
    ) activity
  )
  select m.computed_at, m.tracked, m.moving_24h, m.gainers_24h,
    m.sliders_24h, a.active_24h, v.votes_24h, p.pours_24h,
    v.votes_7d, p.pours_7d
  from market m
  cross join vote_activity v
  cross join pour_activity p
  cross join active_beers a;
$function$;

revoke all on function public.beer_market_pulse()
  from public, anon, authenticated;
grant execute on function public.beer_market_pulse()
  to anon, authenticated, service_role;

-- Recompute with the privacy-safe inputs immediately. The existing cron keeps
-- refreshing the materialized board every 30 minutes after this migration.
select public.refresh_beer_market_standing();
