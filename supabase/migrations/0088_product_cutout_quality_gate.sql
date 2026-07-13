-- 0088_product_cutout_quality_gate.sql
-- Quarantine cutouts that failed a full visual review of every published
-- product image. The attributed source photo remains available as fallback.

with rejected(beer_id) as (
  values
    ('2f4fb599-8037-4517-b0c1-1040f2762ae2'::uuid), -- hand in frame
    ('2dc93d89-cfc0-47a5-896b-695ef0278bb9'::uuid), -- hand in frame
    ('2d8516b9-3390-4cd3-9c55-84ce0303030a'::uuid), -- partial foreground
    ('2c09be12-e1c8-4062-a3a7-400523f1b3fb'::uuid), -- hand in frame
    ('270f998e-b1c1-4ed7-bf7c-a59498b88f9d'::uuid), -- back-label crop
    ('26ebf229-986b-4b36-ba19-1882a652f1bb'::uuid), -- dark partial foreground
    ('26945f65-2dfc-4ab3-b52f-baf742b6ddf9'::uuid), -- label-only crop
    ('1403e98c-1892-4a9b-bbbd-84b2ae0a0e5b'::uuid), -- packaging fragment
    ('13407bcf-cada-4e4d-9a22-10cc437f0dc4'::uuid), -- logo-only crop
    ('09030cc1-9a6f-4eaf-b714-ddf4edf71354'::uuid), -- barcode-only crop
    ('08be8d7f-274c-4d8e-89cc-bc2150b5ed5f'::uuid), -- partial foreground
    ('02081d9d-8558-4572-95d4-feee697516a9'::uuid), -- hand in frame
    ('4854af23-7100-4d9b-bc0f-f4c6675d7609'::uuid), -- hand in frame
    ('533befb6-beb8-48c2-b06a-83994d23617c'::uuid), -- label-only crop
    ('e53d7fe2-9fd1-4acd-996f-6f078ce92e27'::uuid), -- background fragment
    ('91f16f7c-9b4f-49f2-9741-f665e1215b3a'::uuid), -- logo-only crop
    ('6c0118cc-22c4-4689-9fb1-3fb97cac110b'::uuid), -- label-only crop
    ('1bc4c3e6-5ddf-415f-9a33-928ce36be397'::uuid), -- hand in frame
    ('f1be0722-5109-480c-a9fc-d112a060c794'::uuid), -- disconnected cap
    ('29c63534-0792-4991-887d-748b3496a017'::uuid), -- label-only crop
    ('b49e1974-8868-41c2-b730-e9f7d63cda78'::uuid), -- distorted foreground
    ('de96bb8c-97d5-4c0e-bc77-8b687bca3692'::uuid), -- back-label crop
    ('11c60cf8-9a6e-4d2a-a4fe-8861b2e1a079'::uuid), -- logo-only crop
    ('c8d7b83a-f450-4f9c-a1a2-3f7dc90cf118'::uuid), -- logo-only crop
    ('37ee66a8-a5a8-4d69-9507-c969832fe345'::uuid), -- hand in frame
    ('3e1c93e2-2723-43a4-a41a-5e59abcc0f86'::uuid)  -- label-only crop
), cleared as (
  update public.beer_catalog b
  set cutout_url = null
  from rejected r
  where b.id = r.beer_id
  returning b.id
)
update public.beer_media_processing p
set status = 'rejected',
    error_code = 'visual_quality_review',
    updated_at = now()
from cleared c
where p.beer_id = c.id;

notify pgrst, 'reload schema';
