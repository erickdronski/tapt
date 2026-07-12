-- 0067  Market honesty P0s (from the 14-audit execution plan).
--
-- P0-1: a beer with a REAL community vote must ALWAYS be on the board, even
-- with no style/image/award. Verified live: the only real prod vote was
-- invisible because the base gate required style + (image or award).
-- P0-3: never fabricate sparkline history. Return only days with a real
-- snapshot (the app labels the true span); no backfilled flat lines.
-- P0-4: season_fit implies "in season" ONLY when season points are real;
-- sober-curious picks stop landing in the In-season tab. Reason strings read
-- "<Season> beer, in season now" (no "crusher" hype).
-- P0-18: revoke the stray anon-executable clean_beer_name (anon surface is
-- contractually locked to 4 functions).
-- Also: refresh now dedupes per display name and reads the materialized
-- beer_catalog.display_name/name_ok columns (0066).

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
        -- presentable entries...
        (nullif(b.style,'') is not null
         and coalesce(b.cutout_url, b.label_image_url) is not null)
        -- ...or genuinely notable ones...
        or exists (select 1 from public.beer_award a where a.beer_id = b.id)
        -- ...or ANY beer someone actually voted on. Real votes always count.
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
      coalesce(nullif(bb.style,''), 'Beer') as style,
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
      greatest(1, 10 + season_pts + award_pts + notability_pts + vote_pts) as standing,
      season_pts, award_pts, notability_pts, vote_pts,
      net_votes, votes_count, ups, downs, vol24, reason
    from scored
    order by lower(dname),
      greatest(1, 10 + season_pts + award_pts + notability_pts + vote_pts) desc,
      votes_count desc
  )
  select s.id, s.standing, s.season_pts, s.award_pts, s.notability_pts, s.vote_pts,
    s.net_votes, s.votes_count, s.ups, s.downs, s.vol24,
    (s.standing - coalesce(p.prev_standing, s.standing)) as change_24h,
    s.reason,
    -- In-season means REAL season points, not any reason string (P0-4).
    case when s.season_pts > 0 then 2 else 0 end as season_fit,
    least(100, round(s.standing::numeric / nullif(max(s.standing) over (), 0) * 100))::int as heat,
    s.dname,
    upper(left(regexp_replace(s.dname, '[^A-Za-z0-9]', '', 'g'), 4)),
    br.name, s.style, br.country, s.img,
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
$$;

revoke all on function public.refresh_beer_market_standing() from public, anon, authenticated;

-- P0-3: sparkline = REAL snapshot days only, oldest -> newest. No backfill.
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
  select st.beer_id, st.symbol, st.display_name, st.brewery, st.style, st.country,
    st.image_url,
    st.standing, st.votes_count, st.change_24h, st.vol24, st.ups, st.downs,
    coalesce(
      (select array_agg(sn.standing::float8 order by sn.snap_date)
       from public.beer_market_snapshot sn
       where sn.beer_id = st.beer_id
         and sn.snap_date > current_date - 7),
      array[st.standing::float8]
    ),
    st.reason, st.season_fit, st.heat
  from public.beer_market_standing st
  where st.display_name is not null
  order by case p_sort
      when 'gainers' then st.change_24h
      when 'losers'  then -st.change_24h
      when 'active'  then st.vol24
      when 'top'     then st.net_votes
      when 'season'  then st.season_fit * 1000 + st.standing
      else st.standing
    end desc,
    st.standing desc, st.rot desc, st.display_name
  limit least(greatest(coalesce(p_limit, 40), 1), 100);
$$;

revoke all on function public.beer_market(text, integer, boolean) from public, anon, authenticated;
grant execute on function public.beer_market(text, integer, boolean) to authenticated;

-- P0-18: anon surface stays locked to exactly 4 functions.
do $$
declare r record;
begin
  for r in select p.oid::regprocedure sig from pg_proc p
           join pg_namespace n on n.oid = p.pronamespace
           where n.nspname='public' and p.proname='clean_beer_name'
  loop execute format('revoke execute on function %s from anon', r.sig); end loop;
end $$;

select public.refresh_beer_market_standing();
