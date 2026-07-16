-- Follow-up: the donor pick could carry a NULL brewery link while the receiver
-- is linked (Wikidata rows are linked; OFF photo rows often are not), which
-- wrongly blocked the copy. Receiver is blocked only when it names a DIFFERENT
-- brewery than the donors' unique one. Mirrors prod 2026-07-16.
with donor_names as (
  select lower(display_name) as name_key,
         max(brewery_id::text)::uuid as unique_brewery
  from beer_catalog
  where label_image_url is not null and label_image_url <> ''
  group by 1
  having count(distinct brewery_id) filter (where brewery_id is not null) <= 1
),
donors as (
  select distinct on (lower(b.display_name))
    lower(b.display_name) as name_key,
    dn.unique_brewery, b.label_image_url, b.label_image_license, b.cutout_url
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
  and (r.brewery_id is null or d.unique_brewery is null or r.brewery_id = d.unique_brewery);
