-- Integrity tightening for image donation. "Bière blonde" is a generic French
-- name; its null-brewery photo rows can be ANY brand, so donating one to a
-- branded receiver risks a wrong-label image. 1) Revert donated photos on
-- branded receivers with generic names (4+ photo rows, none brewery-linked)
-- that have not produced a cutout. 2) Point the curated-alias 1664s at their
-- next untried single-unit photo. Mirrors prod 2026-07-16.
with generic_names as (
  select lower(display_name) as name_key
  from beer_catalog
  where label_image_url is not null and label_image_url <> ''
  group by 1
  having count(*) >= 4
     and count(distinct brewery_id) filter (where brewery_id is not null) = 0
)
update beer_catalog b
set label_image_url = null, label_image_license = null
from generic_names g, beer_media_processing p
where lower(b.display_name) = g.name_key
  and b.brewery_id is not null
  and b.cutout_url is null
  and p.beer_id = b.id and p.status = 'rejected';

with alias as (
  select d.id as donor_b, r.id as recv_b from brewery d, brewery r
  where lower(d.name)='1664' and lower(r.name)='kronenbourg brewery'
),
rejected as (
  select p.beer_id, p.source_url, b.display_name, b.label_image_url as current_url
  from beer_media_processing p
  join beer_catalog b on b.id = p.beer_id
  join alias al on b.brewery_id = al.recv_b
  where p.status = 'rejected'
),
alternates as (
  select distinct on (r.beer_id)
    r.beer_id, t.label_image_url, t.label_image_license
  from rejected r
  join alias al on true
  join beer_catalog t
    on lower(t.display_name) = lower(r.display_name)
   and t.brewery_id = al.donor_b
   and t.label_image_url is not null and t.label_image_url <> ''
   and t.label_image_url is distinct from r.source_url
   and t.label_image_url is distinct from r.current_url
  order by r.beer_id,
           (t.name !~* '\d+\s*[x×]\s*\d+') desc,
           (t.name ~* '25\s*cl|33\s*cl|bouteille|canette') desc,
           t.id
)
update beer_catalog b
set label_image_url = a.label_image_url,
    label_image_license = coalesce(a.label_image_license, b.label_image_license)
from alternates a
where b.id = a.beer_id;
