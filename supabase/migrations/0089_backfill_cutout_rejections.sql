-- 0089_backfill_cutout_rejections.sql
-- Some early cutouts predated the processing ledger. Persist every visual
-- rejection so the scheduled pipeline cannot republish the same source.

with rejected(beer_id) as (
  values
    ('2f4fb599-8037-4517-b0c1-1040f2762ae2'::uuid),
    ('2dc93d89-cfc0-47a5-896b-695ef0278bb9'::uuid),
    ('2d8516b9-3390-4cd3-9c55-84ce0303030a'::uuid),
    ('2c09be12-e1c8-4062-a3a7-400523f1b3fb'::uuid),
    ('270f998e-b1c1-4ed7-bf7c-a59498b88f9d'::uuid),
    ('26ebf229-986b-4b36-ba19-1882a652f1bb'::uuid),
    ('26945f65-2dfc-4ab3-b52f-baf742b6ddf9'::uuid),
    ('1403e98c-1892-4a9b-bbbd-84b2ae0a0e5b'::uuid),
    ('13407bcf-cada-4e4d-9a22-10cc437f0dc4'::uuid),
    ('09030cc1-9a6f-4eaf-b714-ddf4edf71354'::uuid),
    ('08be8d7f-274c-4d8e-89cc-bc2150b5ed5f'::uuid),
    ('02081d9d-8558-4572-95d4-feee697516a9'::uuid),
    ('4854af23-7100-4d9b-bc0f-f4c6675d7609'::uuid),
    ('533befb6-beb8-48c2-b06a-83994d23617c'::uuid),
    ('e53d7fe2-9fd1-4acd-996f-6f078ce92e27'::uuid),
    ('91f16f7c-9b4f-49f2-9741-f665e1215b3a'::uuid),
    ('6c0118cc-22c4-4689-9fb1-3fb97cac110b'::uuid),
    ('1bc4c3e6-5ddf-415f-9a33-928ce36be397'::uuid),
    ('f1be0722-5109-480c-a9fc-d112a060c794'::uuid),
    ('29c63534-0792-4991-887d-748b3496a017'::uuid),
    ('b49e1974-8868-41c2-b730-e9f7d63cda78'::uuid),
    ('de96bb8c-97d5-4c0e-bc77-8b687bca3692'::uuid),
    ('11c60cf8-9a6e-4d2a-a4fe-8861b2e1a079'::uuid),
    ('c8d7b83a-f450-4f9c-a1a2-3f7dc90cf118'::uuid),
    ('37ee66a8-a5a8-4d69-9507-c969832fe345'::uuid),
    ('3e1c93e2-2723-43a4-a41a-5e59abcc0f86'::uuid)
)
insert into public.beer_media_processing as processing
  (beer_id, source_url, status, attempts, error_code, updated_at)
select
  b.id,
  b.label_image_url,
  'rejected',
  1,
  'visual_quality_review',
  now()
from public.beer_catalog b
join rejected r on r.beer_id = b.id
where b.label_image_url is not null
  and btrim(b.label_image_url) <> ''
on conflict (beer_id) do update
set source_url = excluded.source_url,
    status = excluded.status,
    attempts = greatest(processing.attempts, excluded.attempts),
    error_code = excluded.error_code,
    updated_at = excluded.updated_at;

notify pgrst, 'reload schema';
