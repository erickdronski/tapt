-- 0068_no_low_consistency.sql
-- Carry the canonical is_na_low flag through Home and Market so the user's
-- persisted No / Low lens never falls back to name or style heuristics.

create or replace view public.beer_trend_feed
with (security_invoker = true) as
with current_trends as (
  select distinct on (bt.beer_id, bt.region)
    bt.beer_id,
    b.name,
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
  b.name,
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
where not exists (
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
  with ranked as (
    select distinct on (
      lower(public.tapt_display_name(b.name)),
      coalesce(b.brewery_id::text, '')
    )
      st.beer_id,
      public.tapt_display_name(b.name) as bname,
      br.name as brewery,
      coalesce(nullif(b.style, ''), 'Beer') as style,
      br.country,
      coalesce(b.cutout_url, b.label_image_url) as img,
      b.is_na_low,
      st.standing,
      st.net_votes,
      st.votes_count,
      st.ups,
      st.downs,
      st.vol24,
      st.change_24h,
      st.reason,
      st.season_fit,
      st.heat,
      abs(('x' || substr(md5(st.beer_id::text), 1, 8))::bit(32)::int % 20) as rot
    from public.beer_market_standing st
    join public.beer_catalog b on b.id = st.beer_id
    left join public.brewery br on br.id = b.brewery_id
    where public.tapt_name_ok(b.name)
      and (not coalesce(p_na_only, false) or b.is_na_low)
    order by
      lower(public.tapt_display_name(b.name)),
      coalesce(b.brewery_id::text, ''),
      st.standing desc,
      (b.cutout_url is not null) desc,
      b.id
  )
  select
    r.beer_id,
    upper(left(regexp_replace(r.bname, '[^A-Za-z0-9]', '', 'g'), 4)),
    r.bname,
    r.brewery,
    r.style,
    r.country,
    r.img,
    r.is_na_low,
    r.standing,
    r.votes_count,
    r.change_24h,
    r.vol24,
    r.ups,
    r.downs,
    coalesce(
      (
        select array_agg(
          coalesce(sn.standing, r.standing)::float8
          order by d.d desc
        )
        from generate_series(6, 0, -1) d(d)
        left join public.beer_market_snapshot sn
          on sn.beer_id = r.beer_id
         and sn.snap_date = current_date - d.d
      ),
      array[r.standing::float8]
    ),
    r.reason,
    r.season_fit,
    r.heat
  from ranked r
  order by
    case p_sort
      when 'gainers' then r.change_24h
      when 'losers' then -r.change_24h
      when 'active' then r.vol24
      when 'top' then r.net_votes
      when 'season' then r.season_fit * 1000 + r.standing
      when 'movers' then r.standing
      else r.standing
    end desc,
    r.standing desc,
    r.rot desc,
    r.bname
  limit least(greatest(coalesce(p_limit, 40), 1), 100);
$$;

revoke all on function public.beer_market_v2(text, integer, boolean, boolean)
  from public, anon, authenticated;
grant execute on function public.beer_market_v2(text, integer, boolean, boolean)
  to anon, authenticated;
