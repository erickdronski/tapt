-- 0082  Resolved styles everywhere + last raw-country leaks.
--
-- Explore rows, catalog rows, Beer of the Week, and the market were still
-- showing raw Open Food Facts retail categories as beer styles ("Lithuanian
-- Beers", "Craft Beers", "5 Beer"). The BJCP resolver (tapt_ref_style_name)
-- already exists but is too heavy to run per request (the 0066 lesson), so:
-- materialize it as a stored generated column and route every display
-- surface through it. Unresolvable style -> NULL (blank beats junk).
-- Also: beer_of_week_* and match_beers were the last functions emitting the
-- raw OFF sale-country as if it were the beer's origin; they now use
-- tapt_trusted_country like everything else, and match_beers returns the
-- clean display name (it feeds the scan confirm sheet).

alter table public.beer_catalog
  add column if not exists style_ref text
  generated always as (public.tapt_ref_style_name(style, name)) stored;

-- ------------------------------------------------------------- trend feed
drop view if exists public.beer_trend_feed;
create view public.beer_trend_feed
with (security_invoker = true) as
with current_trends as (
  select distinct on (bt.beer_id, bt.region)
    bt.beer_id,
    coalesce(nullif(b.display_name, ''), b.name) as name,
    b.style_ref as style,
    b.abv,
    br.name as brewery_name,
    public.tapt_trusted_country(br.country, br.external_ids) as country,
    bt.region, bt.popularity, bt.momentum, bt.avg_rating, bt.updated_at,
    b.is_na_low
  from beer_trend bt
  join beer_catalog b on b.id = bt.beer_id
  left join brewery br on br.id = b.brewery_id
  order by bt.beer_id, bt.region, bt.updated_at desc nulls last, bt.id desc
)
select beer_id, name, style, abv, brewery_name, country, region,
       popularity, momentum, avg_rating, updated_at, is_na_low
from current_trends
union all
select distinct
  b.id,
  coalesce(nullif(b.display_name, ''), b.name),
  b.style_ref,
  b.abv,
  br.name,
  public.tapt_trusted_country(br.country, br.external_ids),
  r.region,
  0, 0, null::numeric, b.created_at, b.is_na_low
from beer_catalog b
left join brewery br on br.id = b.brewery_id
cross join lateral (
  values (case when coalesce(nullif(br.country, ''), 'Global') = 'Georgia'
               then 'Georgia (country)'
               else coalesce(nullif(br.country, ''), 'Global') end),
         ('Global')
) r(region)
where b.name_ok
  and not exists (select 1 from beer_trend bt2
                  where bt2.beer_id = b.id and bt2.region = r.region);

grant select on public.beer_trend_feed to anon, authenticated;

-- --------------------------------------------------------- catalog search
-- Identical to 0079 except: display style is the resolved reference (never a
-- retail category), and the style filter matches raw OR resolved so chips
-- keep working.
create or replace function public.catalog_search(
  p_query text default null,
  p_style text default null,
  p_na_only boolean default false,
  p_limit integer default 30,
  p_offset integer default 0
)
returns table (
  id uuid,
  name text,
  style text,
  abv numeric,
  is_na_low boolean,
  brewery_name text,
  country text,
  image_url text,
  total bigint
)
language sql
stable
security definer
set search_path = public
as $$
  with input as (
    select btrim(coalesce(p_query, '')) as query
  ),
  candidates as (
    select
      bc.id,
      bc.display_name as name,
      bc.style_ref as style,
      bc.abv,
      bc.is_na_low,
      b.name as brewery_name,
      public.tapt_trusted_country(b.country, b.external_ids) as country,
      coalesce(bc.cutout_url, bc.label_image_url) as image_url,
      bc.cutout_url is not null as has_cutout,
      case
        when input.query = '' then 0
        when lower(bc.display_name) = lower(input.query) then 0
        when bc.display_name ilike input.query || '%' then 1
        when bc.display_name ilike '%' || input.query || '%' then 2
        when b.name ilike '%' || input.query || '%' then 3
        else 4
      end as match_rank,
      row_number() over (
        partition by
          lower(bc.display_name),
          coalesce(bc.brewery_id::text, lower(b.name), '')
        order by
          (bc.cutout_url is not null) desc,
          (bc.label_image_url is not null) desc,
          (bc.abv is not null) desc,
          (nullif(bc.style, '') is not null) desc,
          bc.updated_at desc,
          bc.id
      ) as package_rank
    from public.beer_catalog bc
    left join public.brewery b on b.id = bc.brewery_id
    cross join input
    where bc.name_ok
      and length(bc.display_name) between 2 and 80
      and bc.display_name !~* '(€|\m(zzgl|pfand|packung)\M)'
      and (
        input.query = ''
        or bc.display_name ilike '%' || input.query || '%'
        or bc.name ilike '%' || input.query || '%'
        or b.name ilike '%' || input.query || '%'
      )
      and (p_style is null or btrim(p_style) = ''
           or bc.style ilike '%' || p_style || '%'
           or bc.style_ref ilike '%' || p_style || '%')
      and (not coalesce(p_na_only, false) or bc.is_na_low)
  ),
  package_canonical as (
    select
      id, name, style, abv, is_na_low, brewery_name, country, image_url,
      has_cutout, match_rank
    from candidates
    where package_rank = 1
  ),
  query_state as (
    select exists (
      select 1
      from package_canonical
      cross join input
      where package_canonical.has_cutout
        and lower(package_canonical.name) = lower(input.query)
    ) as has_reviewed_exact
  ),
  search_ranked as (
    select
      package_canonical.*,
      row_number() over (
        partition by lower(name)
        order by
          match_rank,
          has_cutout desc,
          (image_url is not null) desc,
          (brewery_name is not null) desc,
          (abv is not null) desc,
          (nullif(style, '') is not null) desc,
          id
      ) as searched_name_rank
    from package_canonical
  ),
  canonical as (
    select search_ranked.*
    from search_ranked
    cross join input
    cross join query_state
    where (input.query = '' or searched_name_rank = 1)
      and (
        not query_state.has_reviewed_exact
        or lower(search_ranked.name) = lower(input.query)
      )
  )
  select
    canonical.id,
    canonical.name,
    canonical.style,
    canonical.abv,
    canonical.is_na_low,
    canonical.brewery_name,
    canonical.country,
    canonical.image_url,
    count(*) over() as total
  from canonical
  order by
    canonical.match_rank,
    (canonical.image_url is null),
    (canonical.brewery_name is null),
    (canonical.abv is null),
    (canonical.style is null),
    lower(canonical.name)
  limit greatest(1, least(coalesce(p_limit, 30), 60))
  offset greatest(0, coalesce(p_offset, 0));
$$;

-- --------------------------------------------------------- beer of the week
create or replace function public.beer_of_week_standings(p_limit integer default 10)
returns table(rank integer, beer_id uuid, name text, style text, brewery_name text,
              country text, label_image_url text, week_votes integer)
language sql
stable security definer
set search_path to 'public'
as $$
  with week_votes as (
    select bv.beer_id as wb_id, coalesce(sum(bv.value), 0)::int as votes
    from public.beer_vote bv
    where coalesce(bv.updated_at, bv.created_at) >= date_trunc('week', now())
    group by bv.beer_id
  )
  select
    (row_number() over (
      order by wv.votes desc, coalesce(nullif(b.display_name, ''), b.name)
    ))::int,
    b.id, coalesce(nullif(b.display_name, ''), b.name),
    b.style_ref,
    br.name,
    public.tapt_trusted_country(br.country, br.external_ids),
    coalesce(b.cutout_url, b.label_image_url),
    wv.votes
  from week_votes wv
  join public.beer_catalog b on b.id = wv.wb_id
  left join public.brewery br on br.id = b.brewery_id
  where wv.votes > 0
  order by wv.votes desc, coalesce(nullif(b.display_name, ''), b.name)
  limit least(greatest(coalesce(p_limit, 10), 1), 25);
$$;

create or replace function public.beer_of_week_latest_winner()
returns table(week_start date, beer_id uuid, name text, style text, brewery_name text,
              country text, label_image_url text, week_votes integer)
language sql
stable security definer
set search_path to 'public'
as $$
  select w.week_start, b.id, coalesce(nullif(b.display_name, ''), b.name),
         b.style_ref,
         br.name,
         public.tapt_trusted_country(br.country, br.external_ids),
         coalesce(b.cutout_url, b.label_image_url), w.week_votes
  from public.beer_of_week_winner w
  join public.beer_catalog b on b.id = w.beer_id
  left join public.brewery br on br.id = b.brewery_id
  order by w.week_start desc
  limit 1;
$$;

-- --------------------------------------------------------------- scan match
create or replace function public.match_beers(p_query text, p_limit integer default 8)
returns table(id uuid, name text, style text, abv numeric, brewery_name text,
              country text, confidence numeric)
language sql
stable
set search_path to 'public'
as $$
  with q as (
    select nullif(left(regexp_replace(trim(p_query), '\s+', ' ', 'g'), 96), '') as value,
           least(greatest(coalesce(p_limit, 8), 1), 12) as max_rows
  )
  select
    b.id,
    coalesce(nullif(b.display_name, ''), b.name) as name,
    b.style_ref as style,
    b.abv,
    br.name as brewery_name,
    public.tapt_trusted_country(br.country, br.external_ids) as country,
    case
      when b.gtin = regexp_replace(q.value, '\D', '', 'g') then 1.0
      else greatest(similarity(b.name, q.value), similarity(coalesce(br.name, ''), q.value))
    end::numeric as confidence
  from q, beer_catalog b
  left join brewery br on br.id = b.brewery_id
  where q.value is not null
    and (
      b.gtin = regexp_replace(q.value, '\D', '', 'g')
      or b.name % q.value
      or br.name % q.value
      or b.name ilike '%' || q.value || '%'
      or br.name ilike '%' || q.value || '%'
    )
  order by
    case when b.gtin = regexp_replace(q.value, '\D', '', 'g') then 0 else 1 end,
    confidence desc,
    b.name
  limit (select max_rows from q);
$$;

-- ------------------------------------------------- market display style
-- Third revision of the refresh fn; only the display style line changed
-- (raw retail category -> resolved reference, generic 'Beer' when unknown).
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
    case when s.season_pts > 0 then 2 else 0 end as season_fit,
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
$$;
revoke all on function public.refresh_beer_market_standing() from public, anon, authenticated;

select public.refresh_beer_market_standing();
