-- 0016: region boards list REAL catalog beers (honest zero counters) until
-- first-party votes/check-ins produce trend rows. Editorial rankings from
-- third-party sites are copyrighted compilations and are never ingested
-- (docs/10); popularity numbers remain 100% first-party. Applied live.
drop view if exists beer_trend_feed;
create view beer_trend_feed
with (security_invoker = true) as
select distinct on (bt.beer_id, bt.region)
  bt.beer_id, b.name, b.style, b.abv,
  br.name as brewery_name, br.country, bt.region,
  bt.popularity, bt.momentum, bt.avg_rating, bt.updated_at
from beer_trend bt
join beer_catalog b on b.id = bt.beer_id
left join brewery br on br.id = b.brewery_id
union all
select distinct
  b.id, b.name, b.style, b.abv,
  br.name, br.country, r.region,
  0 as popularity, 0 as momentum, null::numeric as avg_rating, b.created_at
from beer_catalog b
left join brewery br on br.id = b.brewery_id
cross join lateral (
  values (coalesce(nullif(br.country, ''), 'Global')), ('Global')
) as r(region)
where not exists (
  select 1 from beer_trend bt2
  where bt2.beer_id = b.id and bt2.region = r.region
);

grant select on beer_trend_feed to anon, authenticated;
