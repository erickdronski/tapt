-- Give the Beer Market real life. Before this, standing = 10 + (season 40 or 0)
-- + (notability flat 14) + votes, so every in-season beer with a photo clustered
-- at exactly 64 and nothing ever moved. Now: a CONTINUOUS per-style seasonal curve
-- (each style peaks on a different day and drifts daily), GRANULAR notability from
-- real data completeness, and a real 24h-activity momentum term. All real signal,
-- no fabricated volatility. Votes still dominate as they accumulate.

-- Smooth annual "in season" score, 0..~52 by style, peaking on the day that style
-- is most in season. Honest model of seasonal beer relevance, not random noise.
create or replace function public.tapt_season_points(p_style text, p_at date default current_date)
returns int
language sql
immutable
as $function$
  with cfg as (
    select
      case
        when p_style is null then 175
        when p_style ~* 'stout|porter|barley\s?wine|imperial|quad|dubbel|winter|schwarz|old ale|strong ale' then 15
        when p_style ~* 'bock|doppelbock|dunkel|scotch|red ale' then 45
        when p_style ~* 'amber|brown|nut brown' then 60
        when p_style ~* 'm(ä|a)rzen|oktoberfest|pumpkin|harvest|fest' then 271
        when p_style ~* 'saison|farmhouse|grisette|bi(è|e)re de garde' then 120
        when p_style ~* 'ipa|pale ale|apa|neipa|hazy' then 175
        when p_style ~* 'pils|lager|helles|k(ö|o)lsch|blonde|golden|cream ale|light' then 196
        when p_style ~* 'wheat|wit|hefe|weiss|weizen|gose|sour|berliner|fruit|radler|shandy|session' then 205
        else 175
      end as peak,
      case
        when p_style ~* 'ipa|pale ale|apa|neipa|hazy' then 22
        when p_style is null then 12
        else 34
      end as amp,
      18 as base
  )
  select (base + round(amp * (0.5 + 0.5 * cos(2 * pi() * (extract(doy from p_at) - peak) / 365.0))))::int
  from cfg;
$function$;

grant execute on function public.tapt_season_points(text, date) to authenticated;

create or replace function public.refresh_beer_market_standing()
 returns integer
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  n integer;
begin
  delete from public.beer_market_standing;

  insert into public.beer_market_standing
    (beer_id, standing, season_pts, award_pts, notability_pts, vote_pts,
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
    select bb.id, bb.brewery_id, bb.img, bb.cutout_url,
      bb.ssn,
      coalesce(nullif(b2.display_name,''), b2.name) as dname,
      coalesce(b2.style_ref, 'Beer') as style,
      public.tapt_season_points(bb.style, current_date) as season_pts,
      -- honest 1-day seasonal drift, used for change when there is no snapshot yet
      (public.tapt_season_points(bb.style, current_date)
        - public.tapt_season_points(bb.style, current_date - 1)) as season_drift,
      coalesce(aw.award_pts, 0) as award_pts,
      -- granular notability from REAL data completeness (spreads the old flat 14)
      (case when bb.cutout_url is not null then 8 when bb.img is not null then 4 else 0 end)
        + (case when bb.brewery_id is not null then 5 else 0 end)
        + (case when b2.abv is not null then 3 else 0 end)
        + (case when b2.style_ref is not null then 3 else 0 end) as notability_pts,
      coalesce(va.net_votes, 0) * 8 as vote_pts,
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
        else null end as reason
    from base bb
    join public.beer_catalog b2 on b2.id = bb.id
    left join award_agg aw on aw.beer_id = bb.id
    left join vote_agg  va on va.beer_id = bb.id
    left join vol_agg   vl on vl.beer_id = bb.id
  ),
  standings as (
    select distinct on (lower(dname))
      id, dname, style, brewery_id, img,
      greatest(1, 6 + season_pts + award_pts + notability_pts + vote_pts + vol24 * 3) as standing,
      season_pts, award_pts, notability_pts, vote_pts,
      net_votes, votes_count, ups, downs, vol24, reason, season_drift
    from scored
    order by lower(dname),
      greatest(1, 6 + season_pts + award_pts + notability_pts + vote_pts + vol24 * 3) desc,
      votes_count desc
  )
  select s.id, s.standing, s.season_pts, s.award_pts, s.notability_pts, s.vote_pts,
    s.net_votes, s.votes_count, s.ups, s.downs, s.vol24,
    -- real historical delta when a snapshot exists, else the honest seasonal drift
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
