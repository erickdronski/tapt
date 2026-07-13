-- 0092  Explore rows show a real style, never raw retail junk.
--
-- beer_trend_feed still selected raw beer_catalog.style, so Explore rows read
-- "Lithuanian Beers", "Craft Beers", "Beers From Germany" as if those were
-- styles. Codex's beer_catalog.style_ref column already resolves the real BJCP
-- style (and returns NULL for pure geography/junk); catalog_search, the market
-- refresh, and the leaderboards already read it. This points the last reader
-- (Explore's trend feed) at style_ref too. NULL style_ref -> blank style on the
-- row (the row keeps its name, brewery, country). Blank beats junk.
--
-- CONTRACT (see AGENTS.md): user-facing style ALWAYS comes from
-- beer_catalog.style_ref, never raw beer_catalog.style.

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
    b.is_na_low,
    coalesce(b.cutout_url, b.label_image_url) as image_url
  from beer_trend bt
  join beer_catalog b on b.id = bt.beer_id
  left join brewery br on br.id = b.brewery_id
  order by bt.beer_id, bt.region, bt.updated_at desc nulls last, bt.id desc
)
select beer_id, name, style, abv, brewery_name, country, region,
       popularity, momentum, avg_rating, updated_at, is_na_low, image_url
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
  0, 0, null::numeric, b.created_at, b.is_na_low,
  coalesce(b.cutout_url, b.label_image_url)
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
