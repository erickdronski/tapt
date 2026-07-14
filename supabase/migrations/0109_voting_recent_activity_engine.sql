-- Make voting make sense. Before: the Market ran on all-time net_votes*8 (a
-- permanent vote froze a beer's standing forever, no volume), and Beer of the Week
-- ran on this-week VOTES only (which don't recur). Now the recurring engine is
-- ACTIVITY: recent pours (which naturally recur as people drink) + recent likes,
-- decayed. All-time likes become just a small durable floor. No new user action.
--   * Beer Market  = NOW    (recent buzz + capped taste + season/awards) - moves daily
--   * Beer of Week = THIS WEEK (this week's likes + pours) - resets weekly
--   * Leaderboards = ALL-TIME (unchanged hall of fame)

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
      -- ACTIVITY points: recent buzz (drives movement + weekly volume, decays) plus a
      -- small durable "taste" floor from all-time likes (capped so nothing freezes).
      ( coalesce(pa.pours_7d,0) * 10
        + coalesce(pa.pours_30d,0) * 2
        + greatest(coalesce(va.net_votes_7d,0),0) * 6
        + least(20, greatest(coalesce(va.net_votes,0),0) * 4) )::int as vote_pts,
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
    left join pour_agg  pa on pa.beer_id = bb.id
    left join vol_agg   vl on vl.beer_id = bb.id
  ),
  standings as (
    select distinct on (lower(dname))
      id, dname, style, brewery_id, img,
      greatest(1, 6 + season_pts + award_pts + notability_pts + vote_pts) as standing,
      season_pts, award_pts, notability_pts, vote_pts,
      net_votes, votes_count, ups, downs, vol24, reason, season_drift
    from scored
    order by lower(dname),
      greatest(1, 6 + season_pts + award_pts + notability_pts + vote_pts) desc,
      votes_count desc
  )
  select s.id, s.standing, s.season_pts, s.award_pts, s.notability_pts, s.vote_pts,
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

-- Beer of the Week live standings: this week's LIKES + POURS (pours recur naturally,
-- so week 2 is not empty even if nobody re-likes). week_votes now = weekly love score.
create or replace function public.beer_of_week_standings(p_limit integer default 10)
 returns table(rank integer, beer_id uuid, name text, style text, brewery_name text, country text, label_image_url text, week_votes integer)
 language sql stable security definer set search_path to 'public'
as $function$
  with wk as (select date_trunc('week', now()) as wstart),
  wvotes as (
    select beer_id, coalesce(sum(value),0)::int v
    from public.beer_vote, wk
    where coalesce(updated_at, created_at) >= wk.wstart
    group by beer_id
  ),
  wpours as (
    select beer_id, count(*)::int p
    from public.checkin_event, wk
    where beer_id is not null and event_ts >= wk.wstart
    group by beer_id
  ),
  scores as (
    select coalesce(v.beer_id, p.beer_id) as beer_id,
           (coalesce(v.v,0) + coalesce(p.p,0))::int as score
    from wvotes v full outer join wpours p on p.beer_id = v.beer_id
  )
  select (row_number() over (order by s.score desc, coalesce(nullif(b.display_name,''), b.name)))::int,
    b.id, coalesce(nullif(b.display_name,''), b.name), b.style_ref, br.name,
    public.tapt_trusted_country(br.country, br.external_ids),
    coalesce(b.cutout_url, b.label_image_url), s.score
  from scores s
  join public.beer_catalog b on b.id = s.beer_id
  left join public.brewery br on br.id = b.brewery_id
  where s.score > 0
  order by s.score desc, coalesce(nullif(b.display_name,''), b.name)
  limit least(greatest(coalesce(p_limit, 10), 1), 25);
$function$;

-- Lock last week's winner by last week's LIKES + POURS.
create or replace function public.lock_beer_of_week()
 returns void language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_week date := (date_trunc('week', now()) - interval '7 days')::date;
  v_beer uuid;
  v_score int;
begin
  if exists (select 1 from beer_of_week_winner w where w.week_start = v_week) then
    return;
  end if;

  with wvotes as (
    select beer_id, coalesce(sum(value),0)::int v from beer_vote
    where coalesce(updated_at, created_at) >= v_week and coalesce(updated_at, created_at) < v_week + 7
    group by beer_id
  ),
  wpours as (
    select beer_id, count(*)::int p from checkin_event
    where beer_id is not null and event_ts >= v_week and event_ts < v_week + 7
    group by beer_id
  ),
  scores as (
    select coalesce(v.beer_id, p.beer_id) as beer_id, (coalesce(v.v,0) + coalesce(p.p,0))::int as score
    from wvotes v full outer join wpours p on p.beer_id = v.beer_id
  )
  select beer_id, score into v_beer, v_score
  from scores order by score desc limit 1;

  if v_beer is not null and v_score > 0 then
    insert into beer_of_week_winner (week_start, beer_id, week_votes) values (v_week, v_beer, v_score);
  end if;
end;
$function$;
