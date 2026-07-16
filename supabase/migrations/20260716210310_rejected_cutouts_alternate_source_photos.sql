-- Cutout retry with better sources. The image backfill picked one donor photo
-- per name, and for the top board beers that donor was a MULTIPACK shot, which
-- the quality gate rightly rejected (multiple_foregrounds). Swap every rejected
-- beer's label_image_url to the best untried alternate from its safe twins,
-- preferring non-multipack products; a changed source re-queues the beer.
-- Mirrors prod 2026-07-16.
with alias as (
  select d.id as a, r.id as b from brewery d, brewery r
  where lower(d.name)='1664' and lower(r.name)='kronenbourg brewery'
),
rejected as (
  select p.beer_id, p.source_url, b.display_name, b.brewery_id
  from beer_media_processing p
  join beer_catalog b on b.id = p.beer_id
  where p.status = 'rejected'
),
alternates as (
  select distinct on (r.beer_id)
    r.beer_id, t.label_image_url, t.label_image_license
  from rejected r
  join beer_catalog t
    on lower(t.display_name) = lower(r.display_name)
   and t.id <> r.beer_id
   and t.label_image_url is not null and t.label_image_url <> ''
   and t.label_image_url is distinct from r.source_url
   and (
        t.brewery_id is not distinct from r.brewery_id
        or t.brewery_id is null
        or exists (select 1 from alias al
                   where (t.brewery_id = al.a and r.brewery_id = al.b)
                      or (t.brewery_id = al.b and r.brewery_id = al.a))
       )
  order by r.beer_id,
           (t.name !~* '\d+\s*[x×]\s*\d+') desc,
           t.id
)
update beer_catalog b
set label_image_url = a.label_image_url,
    label_image_license = coalesce(a.label_image_license, b.label_image_license)
from alternates a
where b.id = a.beer_id;
