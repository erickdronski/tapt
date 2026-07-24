-- The final legacy OFF dispatch found three exact-GTIN fronts while v4 was
-- being deployed. Move every exact source from that run behind the new paired
-- source/cutout review gate instead of leaving it customer-visible.
with recovered as (
  select
    b.id as beer_id,
    b.label_image_url as source_url,
    regexp_replace(b.gtin, '\D', '', 'g') as source_gtin
  from public.beer_catalog b
  where b.updated_at >= '2026-07-24 03:21:00+00'::timestamptz
    and b.label_image_url like 'https://images.openfoodfacts.org/images/products/%'
    and b.label_image_license = 'Open Food Facts image (CC BY-SA 3.0)'
    and b.cutout_url is null
    and regexp_replace(coalesce(b.gtin, ''), '\D', '', 'g') ~ '^[0-9]{8,14}$'
)
insert into public.beer_media_source_candidate (
  beer_id,
  source_url,
  source_license,
  source_kind,
  source_external_id,
  source_page_url,
  source_gtin,
  source_metadata,
  status,
  updated_at
)
select
  r.beer_id,
  r.source_url,
  'Open Food Facts image (CC BY-SA 3.0)',
  'open_food_facts',
  r.source_gtin,
  'https://world.openfoodfacts.org/product/' || r.source_gtin,
  r.source_gtin,
  jsonb_build_object(
    'match_kind', 'exact_gtin',
    'discovery', '20260724_legacy_off_dispatch_quarantine'
  ),
  'pending_cutout',
  now()
from recovered r
on conflict (beer_id) do nothing;

update public.beer_catalog b
set label_image_url = null,
    label_image_license = null
from public.beer_media_source_candidate c
where c.beer_id = b.id
  and c.source_url = b.label_image_url
  and c.source_metadata->>'discovery' = '20260724_legacy_off_dispatch_quarantine'
  and c.status = 'pending_cutout';

notify pgrst, 'reload schema';
