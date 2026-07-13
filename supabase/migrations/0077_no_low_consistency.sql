-- 0077_no_low_consistency.sql
-- Carry the canonical is_na_low flag through Home and Market so the user's
-- persisted No / Low lens never falls back to name or style heuristics.

create or replace view public.beer_trend_feed
with (security_invoker = true) as
with current_trends as (
  select distinct on (bt.beer_id, bt.region)
    bt.beer_id,
    coalesce(nullif(b.display_name, ''), b.name) as name,
    b.style,
    b.abv,
    br.name as brewery_name,
    br.country,
    bt.region,
    bt.popularity,
    bt.momentum,
    bt.avg_rating,
    bt.updated_at,
    b.is_na_low
  from public.beer_trend bt
  join public.beer_catalog b on b.id = bt.beer_id
  left join public.brewery br on br.id = b.brewery_id
  order by bt.beer_id, bt.region, bt.updated_at desc nulls last, bt.id desc
)
select
  beer_id, name, style, abv, brewery_name, country, region,
  popularity, momentum, avg_rating, updated_at, is_na_low
from current_trends
union all
select distinct
  b.id,
  coalesce(nullif(b.display_name, ''), b.name),
  b.style,
  b.abv,
  br.name,
  br.country,
  r.region,
  0 as popularity,
  0 as momentum,
  null::numeric as avg_rating,
  b.created_at,
  b.is_na_low
from public.beer_catalog b
left join public.brewery br on br.id = b.brewery_id
cross join lateral (
  values (coalesce(nullif(br.country, ''), 'Global')), ('Global')
) as r(region)
where b.name_ok
  and not exists (
  select 1
  from public.beer_trend bt2
  where bt2.beer_id = b.id and bt2.region = r.region
);

revoke all on table public.beer_trend_feed from public, anon, authenticated;
grant select on table public.beer_trend_feed to anon, authenticated;

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
as $$
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
  where not coalesce(p_na_only, false) or b.is_na_low
  order by
    case p_sort
      when 'gainers' then st.change_24h
      when 'losers' then -st.change_24h
      when 'active' then st.vol24
      when 'top' then st.net_votes
      when 'season' then st.season_fit * 1000 + st.standing
      when 'movers' then st.standing
      else st.standing
    end desc,
    st.standing desc,
    st.rot desc,
    st.display_name
  limit least(greatest(coalesce(p_limit, 40), 1), 100);
$$;

revoke all on function public.beer_market_v2(text, integer, boolean, boolean)
  from public, anon, authenticated;
grant execute on function public.beer_market_v2(text, integer, boolean, boolean)
  to authenticated;
