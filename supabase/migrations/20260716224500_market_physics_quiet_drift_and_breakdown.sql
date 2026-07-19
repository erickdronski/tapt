-- Market physics: the downside + full explainability.
--
-- 1) beer_market_standing.drift_pts: silence costs altitude. days_quiet = days
--    since last vote/pour (never engaged = days since first board appearance).
--    14-day grace, then -2 per quiet week, capped at -15 so legends cool but
--    never vanish; any engagement resets it. standing = greatest(1, 6 + season
--    + awards + notability + activity - drift). Reason: 'Quiet lately, cooling off'.
-- 2) beer_market_one() also returns season_pts/award_pts/notability_pts/vote_pts/
--    drift_pts so the beer page can render the WHY THIS STANDING breakdown.
--
-- AUDIT FIX 2026-07-17: this file had been a comment-only stub while the DDL
-- lived only in prod, so a DB rebuilt from source lacked the drift_pts column
-- and the drift/breakdown logic. The real DDL is now inlined; reproducible from
-- source. (Mirrors prod exactly.)

alter table public.beer_market_standing add column if not exists drift_pts integer not null default 0;

create or replace function public.refresh_beer_market_standing()
 returns integer
 language plpgsql security definer set search_path to 'public'
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
    select b.id, b.name, b.style, b.brewery_id, b.cutout_url,
           coalesce(b.cutout_url, b.label_image_url) img,
           (select s from season) ssn
    from public.beer_catalog b
    where b.name_ok
      and (
        (nullif(b.style,'') is not null
         and coalesce(b.cutout_url, b.label_image_url) is not null)
        or exists (select 1 from public.beer_award a where a.beer_id = b.id)
        or exists (select 1 from public.beer_vote v where v.beer_id = b.id)
        or exists (select 1 from public.checkin_event c where c.beer_id = b.id)
      )
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
      count(*) filter (where value < 0)::int downs,
      coalesce(sum(value) filter (where coalesce(updated_at, created_at) > now() - interval '7 days'), 0)::int net_votes_7d
    from public.beer_vote group by beer_id
  ),
  pour_agg as (
    select beer_id,
      count(*) filter (where event_ts > now() - interval '7 days')::int pours_7d,
      count(*) filter (where event_ts > now() - interval '30 days')::int pours_30d
    from public.checkin_event where beer_id is not null group by beer_id
  ),
  vol_agg as (
    select beer_id, count(*)::int vol24 from (
      select beer_id, coalesce(updated_at, created_at) ts from public.beer_vote
      union all
      select beer_id, coalesce(event_ts, created_at) from public.checkin_event where beer_id is not null
    ) e where ts > now() - interval '24 hours' group by beer_id
  ),
  engaged as (
    select beer_id, max(ts)::date as last_engaged from (
      select beer_id, coalesce(updated_at, created_at) ts from public.beer_vote
      union all
      select beer_id, coalesce(event_ts, created_at) from public.checkin_event where beer_id is not null
    ) e group by beer_id
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
      coalesce(nullif(b2.display_name,''), b2.name) as dname,
      coalesce(b2.style_ref, 'Beer') as style,
      public.tapt_season_points(bb.style, current_date) as season_pts,
      (public.tapt_season_points(bb.style, current_date)
        - public.tapt_season_points(bb.style, current_date - 1)) as season_drift,
      coalesce(aw.award_pts, 0) as award_pts,
      (case when bb.cutout_url is not null then 8 when bb.img is not null then 4 else 0 end)
        + (case when bb.brewery_id is not null then 5 else 0 end)
        + (case when b2.abv is not null then 3 else 0 end)
        + (case when b2.style_ref is not null then 3 else 0 end) as notability_pts,
      ( coalesce(pa.pours_7d,0) * 10
        + coalesce(pa.pours_30d,0) * 2
        + greatest(coalesce(va.net_votes_7d,0),0) * 6
        + least(20, greatest(coalesce(va.net_votes,0),0) * 4) )::int as vote_pts,
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
        when bb.ssn='summer' and bb.style ~* 'ipa|pale|wheat|wit|hefe|weiss|weizen|pils|lager|blonde|sour|gose|radler|shandy|session|helles|k(ö|o)lsch' then 'Summer beer, in season now'
        when bb.ssn='winter' and bb.style ~* 'stout|porter|barley\s?wine|bock|strong|winter|imperial|quad|dubbel|dark|schwarz' then 'Winter beer, in season now'
        when bb.ssn='fall'   and bb.style ~* 'm(ä|a)rzen|oktoberfest|amber|brown|pumpkin|porter|dunkel' then 'Fall beer, in season now'
        when bb.ssn='spring' and bb.style ~* 'saison|pale|bock|blonde|farmhouse' then 'Spring beer, in season now'
        else null end as base_reason
    from base bb
    join public.beer_catalog b2 on b2.id = bb.id
    left join award_agg aw on aw.beer_id = bb.id
    left join vote_agg  va on va.beer_id = bb.id
    left join pour_agg  pa on pa.beer_id = bb.id
    left join vol_agg   vl on vl.beer_id = bb.id
    left join engaged   en on en.beer_id = bb.id
    left join birth     bi on bi.beer_id = bb.id
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
    case when s.season_pts >= 40 then 2 when s.season_pts >= 28 then 1 else 0 end as season_fit,
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

create or replace function public.beer_market_one(p_beer_id uuid)
 returns table(beer_id uuid, symbol text, name text, brewery text, style text, country text, image_url text, is_na_low boolean, net integer, votes integer, change integer, volume integer, ups integer, downs integer, spark double precision[], reason text, season_fit integer, heat integer, season_pts integer, award_pts integer, notability_pts integer, vote_pts integer, drift_pts integer)
 language sql stable security definer set search_path to 'public'
as $function$
  select
    st.beer_id, st.symbol, st.display_name, st.brewery, st.style, st.country,
    st.image_url, b.is_na_low, st.standing, st.votes_count, st.change_24h,
    st.vol24, st.ups, st.downs,
    coalesce(
      (select array_agg(sn.standing::float8 order by sn.snap_date)
       from public.beer_market_snapshot sn
       where sn.beer_id = st.beer_id
         and sn.snap_date > current_date - 7),
      array[st.standing::float8]
    ),
    st.reason, st.season_fit, st.heat,
    st.season_pts, st.award_pts, st.notability_pts, st.vote_pts, st.drift_pts
  from public.beer_market_standing st
  join public.beer_catalog b on b.id = st.beer_id
  where st.beer_id = p_beer_id;
$function$;