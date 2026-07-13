-- 0087_personalized_trend_media.sql
-- Carry reviewed product media into the public trend feed so Explore can use
-- the same cutout-first image contract as Catalog, Market, and Cellar.

create or replace view public.beer_trend_feed
with (security_invoker = true) as
with current_trends as (
  select distinct on (bt.beer_id, bt.region)
    bt.beer_id,
    coalesce(nullif(b.display_name, ''), b.name) as name,
    b.style,
    b.abv,
    br.name as brewery_name,
    public.tapt_trusted_country(br.country, br.external_ids) as country,
    bt.region,
    bt.popularity,
    bt.momentum,
    bt.avg_rating,
    bt.updated_at,
    b.is_na_low,
    coalesce(b.cutout_url, b.label_image_url) as image_url
  from public.beer_trend bt
  join public.beer_catalog b on b.id = bt.beer_id
  left join public.brewery br on br.id = b.brewery_id
  order by bt.beer_id, bt.region, bt.updated_at desc nulls last, bt.id desc
)
select
  beer_id, name, style, abv, brewery_name, country, region,
  popularity, momentum, avg_rating, updated_at, is_na_low, image_url
from current_trends
union all
select distinct
  b.id,
  coalesce(nullif(b.display_name, ''), b.name),
  b.style,
  b.abv,
  br.name,
  public.tapt_trusted_country(br.country, br.external_ids),
  r.region,
  0,
  0,
  null::numeric,
  b.created_at,
  b.is_na_low,
  coalesce(b.cutout_url, b.label_image_url)
from public.beer_catalog b
left join public.brewery br on br.id = b.brewery_id
cross join lateral (
  values (case when coalesce(nullif(br.country, ''), 'Global') = 'Georgia'
               then 'Georgia (country)'
               else coalesce(nullif(br.country, ''), 'Global') end),
         ('Global')
) r(region)
where b.name_ok
  and not exists (
    select 1
    from public.beer_trend bt2
    where bt2.beer_id = b.id and bt2.region = r.region
  );

revoke all on table public.beer_trend_feed from public, anon, authenticated;
grant select on table public.beer_trend_feed to anon, authenticated;
