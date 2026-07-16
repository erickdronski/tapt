-- Curated brewery-alias bridge: OFF ingest created a brand-as-brewery row
-- ("1664") while Wikidata linked the same beers to the real producer
-- ("Kronenbourg Brewery"). One explicitly reviewed alias pair; the automatic
-- backfill still never bridges unrelated breweries. Mirrors prod 2026-07-16.
with alias_pair as (
  select d.id as donor_brewery, r.id as receiver_brewery
  from brewery d, brewery r
  where lower(d.name) = '1664' and lower(r.name) = 'kronenbourg brewery'
),
donors as (
  select distinct on (lower(b.display_name))
    lower(b.display_name) as name_key,
    b.label_image_url, b.label_image_license, b.cutout_url
  from beer_catalog b
  join alias_pair ap on b.brewery_id = ap.donor_brewery
  where b.label_image_url is not null and b.label_image_url <> ''
  order by lower(b.display_name), (b.cutout_url is not null) desc, b.id
)
update beer_catalog r
set label_image_url = d.label_image_url,
    label_image_license = coalesce(r.label_image_license, d.label_image_license),
    cutout_url = coalesce(r.cutout_url, d.cutout_url)
from donors d, alias_pair ap
where lower(r.display_name) = d.name_key
  and r.brewery_id = ap.receiver_brewery
  and (r.label_image_url is null or r.label_image_url = '');
