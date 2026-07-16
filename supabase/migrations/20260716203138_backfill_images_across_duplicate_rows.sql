-- Backfill label images across exact-duplicate catalog rows (same normalized
-- display_name + same brewery, null-safe). Donors are only trusted when every
-- photo-bearing row of that name agrees on a single brewery, so generic names
-- shared by many breweries ("Bière blonde") can never donate across brands.
-- License travels with the photo; an existing reviewed cutout travels too.
-- Mirrors the migration applied to prod 2026-07-16.
with donor_names as (
  select lower(display_name) as name_key
  from beer_catalog
  where label_image_url is not null and label_image_url <> ''
  group by 1
  having count(distinct brewery_id) filter (where brewery_id is not null) <= 1
),
donors as (
  select distinct on (lower(b.display_name))
    lower(b.display_name) as name_key,
    b.brewery_id, b.label_image_url, b.label_image_license, b.cutout_url
  from beer_catalog b
  join donor_names dn on dn.name_key = lower(b.display_name)
  where b.label_image_url is not null and b.label_image_url <> ''
  order by lower(b.display_name), (b.cutout_url is not null) desc, b.id
)
update beer_catalog r
set label_image_url = d.label_image_url,
    label_image_license = coalesce(r.label_image_license, d.label_image_license),
    cutout_url = coalesce(r.cutout_url, d.cutout_url)
from donors d
where lower(r.display_name) = d.name_key
  and (r.label_image_url is null or r.label_image_url = '')
  and (r.brewery_id is null or r.brewery_id is not distinct from d.brewery_id);
