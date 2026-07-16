-- Product-image quality v2
--
-- Real source photos remain attributed and untouched. Automated processing now
-- stages versioned transparent assets; an admin must compare the source and
-- candidate before the asset becomes a customer-visible catalog cutout.

alter table public.beer_media_processing
  add column if not exists pipeline_version text not null default 'v1',
  add column if not exists effective_source_url text,
  add column if not exists source_width integer,
  add column if not exists source_height integer,
  add column if not exists candidate_cutout_url text,
  add column if not exists reviewed_at timestamptz,
  add column if not exists reviewed_by uuid,
  add column if not exists review_notes text;

-- OFF's database is ODbL, but its product photographs are CC BY-SA 3.0.
-- Keep that image-specific license attached to existing rows and every future
-- ingestion path; customer surfaces separately identify Tapt modifications.
update public.beer_catalog
set label_image_license =
  'Open Food Facts image (CC BY-SA 3.0)'
where label_image_license in (
  'Open Food Facts (ODbL)',
  'Open Food Facts (ODbL/CC-BY-SA)'
);

create or replace function public.normalize_beer_image_license()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.label_image_url like 'https://images.openfoodfacts.org/%'
     or coalesce(new.label_image_license, '') like 'Open Food Facts%' then
    new.label_image_license :=
      'Open Food Facts image (CC BY-SA 3.0)';
  end if;
  return new;
end
$$;

drop trigger if exists normalize_beer_image_license on public.beer_catalog;
create trigger normalize_beer_image_license
before insert or update of label_image_url, label_image_license
on public.beer_catalog
for each row execute function public.normalize_beer_image_license();

revoke all on function public.normalize_beer_image_license()
  from public, anon, authenticated;

alter table public.beer_media_processing
  drop constraint if exists beer_media_processing_status_check;
alter table public.beer_media_processing
  add constraint beer_media_processing_status_check
  check (status in ('processing', 'pending_review', 'completed', 'retry', 'rejected'));

alter table public.beer_media_processing
  drop constraint if exists beer_media_processing_source_dimensions_check;
alter table public.beer_media_processing
  add constraint beer_media_processing_source_dimensions_check
  check (
    (source_width is null and source_height is null)
    or (source_width > 0 and source_height > 0)
  );

create index if not exists beer_media_processing_review_queue
  on public.beer_media_processing (updated_at, beer_id)
  where status = 'pending_review';

-- Fail closed on every semantic miss found by the paired visual audit of all
-- 142 live cutouts. Source URLs stay in the processing ledger for provenance.
do $$
declare
  v_expected integer := 37;
  v_found integer;
  v_ids uuid[] := array[
    '70f26378-af20-4b05-a78e-7338f1db4919'::uuid,
    '611c8fdc-057d-48a3-aec0-e9f5ffe8a9ce'::uuid,
    '559cae6f-2265-4b2f-aee1-068895bd8fa1'::uuid,
    '44263768-7e2d-47d4-b73d-737b46dbb7f3'::uuid,
    'fb41c7d4-b1a5-4245-bee8-219c268183fd'::uuid,
    '25256712-ba0a-431d-a761-b499448279ef'::uuid,
    '21f475ff-8738-4b86-b8e2-63daa6e594f6'::uuid,
    '1bc85e28-6049-4934-970b-a3d6fce6a0f5'::uuid,
    '1b529168-75ea-419b-ac89-51bb7cec8ab5'::uuid,
    '164820cb-583b-47c6-8491-e3419a322aaf'::uuid,
    '11a510a7-212f-4e8f-8c81-c46432a1ee78'::uuid,
    '10ee783b-d3fc-4520-a22f-5ae827985c92'::uuid,
    '688e98d4-d3fc-4a63-b48a-b649d0dec535'::uuid,
    '2a3b55bb-3fec-441e-a9eb-cc712ec78b8d'::uuid,
    'baf9faf4-5e80-4f00-86db-18e937706482'::uuid,
    '279399af-ef1d-4f3e-a7ac-4c9317426111'::uuid,
    'd8670097-9220-4ba7-8f49-256017ea88e5'::uuid,
    'a5cd4e62-1f70-490d-a9a1-3c21a635dacd'::uuid,
    '70d7d2b5-921d-4442-949c-e3ef9ab44b8f'::uuid,
    '1f42c08e-0299-49a5-9fd7-02b14d55409b'::uuid,
    '06881838-393f-4af2-abc9-c4e47f2d81ed'::uuid,
    '11e440fe-0868-4e73-ad22-38fa3357abc5'::uuid,
    '55ddec94-2b45-48bc-9967-fb2cc6e2d641'::uuid,
    '5f176aee-a946-4c4c-9d0f-daed02e10f62'::uuid,
    '750cc544-6950-4a80-b1c4-ddba3f70cf4f'::uuid,
    '8a2d68dd-aa1b-4250-9689-82d1d2027e70'::uuid,
    'a442c566-2348-4e8e-98f8-c98ef8643e09'::uuid,
    'ef6fb2b4-d5a6-498d-9c0d-ceed8ee245f2'::uuid,
    '5ec66732-c9da-4cd5-ba50-23b6cad36efb'::uuid,
    '54e43900-dcfd-47ff-b6aa-f6feb3bc0310'::uuid,
    '1057f849-649d-453c-aebb-fb5538d36e27'::uuid,
    'e873da73-b341-46dc-9c30-da1bc80888bc'::uuid,
    'a6cea501-9180-4d1b-b72b-c4d9ba9faa6a'::uuid,
    '8b587fe5-4e81-4efd-8c12-7e52b7cfbc35'::uuid,
    '6c427533-5497-4dd7-a6a0-1bf3af4ace26'::uuid,
    'a73f8e80-1f22-4ca7-a9bb-8b16f6880463'::uuid,
    '053b4a22-6f56-45b5-b651-bf5a7bdc0047'::uuid
  ];
begin
  select count(*) into v_found
  from public.beer_catalog
  where id = any(v_ids);
  if v_found <> v_expected then
    raise exception 'product image quarantine expected % rows, found %', v_expected, v_found;
  end if;
end
$$;

with rejected(beer_id, reason) as (
  values
    ('70f26378-af20-4b05-a78e-7338f1db4919'::uuid, 'hand retained'),
    ('611c8fdc-057d-48a3-aec0-e9f5ffe8a9ce'::uuid, 'shrink-wrapped multipack'),
    ('559cae6f-2265-4b2f-aee1-068895bd8fa1'::uuid, 'incomplete can'),
    ('44263768-7e2d-47d4-b73d-737b46dbb7f3'::uuid, 'label or packaging fragment'),
    ('fb41c7d4-b1a5-4245-bee8-219c268183fd'::uuid, 'label-only bottle crop'),
    ('25256712-ba0a-431d-a761-b499448279ef'::uuid, 'multiple cans'),
    ('21f475ff-8738-4b86-b8e2-63daa6e594f6'::uuid, 'case packaging'),
    ('1bc85e28-6049-4934-970b-a3d6fce6a0f5'::uuid, 'distorted partial package'),
    ('1b529168-75ea-419b-ac89-51bb7cec8ab5'::uuid, 'partial product crop'),
    ('164820cb-583b-47c6-8491-e3419a322aaf'::uuid, 'carton and glass scene'),
    ('11a510a7-212f-4e8f-8c81-c46432a1ee78'::uuid, 'hand retained'),
    ('10ee783b-d3fc-4520-a22f-5ae827985c92'::uuid, 'edge and foreground artifacts'),
    ('688e98d4-d3fc-4a63-b48a-b649d0dec535'::uuid, 'multiple bottles'),
    ('2a3b55bb-3fec-441e-a9eb-cc712ec78b8d'::uuid, 'glass instead of packaged product'),
    ('baf9faf4-5e80-4f00-86db-18e937706482'::uuid, 'damaged mask and background artifacts'),
    ('279399af-ef1d-4f3e-a7ac-4c9317426111'::uuid, 'multiple cans and carrier'),
    ('d8670097-9220-4ba7-8f49-256017ea88e5'::uuid, 'background fragment'),
    ('a5cd4e62-1f70-490d-a9a1-3c21a635dacd'::uuid, 'partial bottle and mask artifacts'),
    ('70d7d2b5-921d-4442-949c-e3ef9ab44b8f'::uuid, 'secondary product and background fragments'),
    ('1f42c08e-0299-49a5-9fd7-02b14d55409b'::uuid, 'multiple cans'),
    ('06881838-393f-4af2-abc9-c4e47f2d81ed'::uuid, 'multiple bottles'),
    ('11e440fe-0868-4e73-ad22-38fa3357abc5'::uuid, 'six-pack packaging'),
    ('55ddec94-2b45-48bc-9967-fb2cc6e2d641'::uuid, 'hand retained'),
    ('5f176aee-a946-4c4c-9d0f-daed02e10f62'::uuid, 'malformed partial package'),
    ('750cc544-6950-4a80-b1c4-ddba3f70cf4f'::uuid, 'case packaging'),
    ('8a2d68dd-aa1b-4250-9689-82d1d2027e70'::uuid, 'sideways back-label crop'),
    ('a442c566-2348-4e8e-98f8-c98ef8643e09'::uuid, 'case packaging'),
    ('ef6fb2b4-d5a6-498d-9c0d-ceed8ee245f2'::uuid, 'incomplete bottle crop'),
    ('5ec66732-c9da-4cd5-ba50-23b6cad36efb'::uuid, 'carton fragment'),
    ('54e43900-dcfd-47ff-b6aa-f6feb3bc0310'::uuid, 'label-only close crop'),
    ('1057f849-649d-453c-aebb-fb5538d36e27'::uuid, 'label-only close crop'),
    ('e873da73-b341-46dc-9c30-da1bc80888bc'::uuid, 'partial back or side bottle'),
    ('a6cea501-9180-4d1b-b72b-c4d9ba9faa6a'::uuid, 'label-only partial bottle'),
    ('8b587fe5-4e81-4efd-8c12-7e52b7cfbc35'::uuid, 'partial bottle'),
    ('6c427533-5497-4dd7-a6a0-1bf3af4ace26'::uuid, 'cropped bottle'),
    ('a73f8e80-1f22-4ca7-a9bb-8b16f6880463'::uuid, 'cropped can'),
    ('053b4a22-6f56-45b5-b651-bf5a7bdc0047'::uuid, 'carton fragment')
), cleared as (
  update public.beer_catalog b
  set cutout_url = null
  from rejected r
  where b.id = r.beer_id
  returning b.id
)
insert into public.beer_media_processing as processing (
  beer_id,
  source_url,
  status,
  attempts,
  error_code,
  pipeline_version,
  candidate_cutout_url,
  reviewed_at,
  review_notes,
  updated_at
)
select
  b.id,
  b.label_image_url,
  'rejected',
  1,
  'manual_quality_rejection',
  'v2',
  null,
  now(),
  r.reason,
  now()
from public.beer_catalog b
join rejected r on r.beer_id = b.id
join cleared c on c.id = b.id
where nullif(btrim(b.label_image_url), '') is not null
on conflict (beer_id) do update
set source_url = excluded.source_url,
    status = excluded.status,
    attempts = greatest(processing.attempts, excluded.attempts),
    error_code = excluded.error_code,
    pipeline_version = excluded.pipeline_version,
    candidate_cutout_url = null,
    reviewed_at = excluded.reviewed_at,
    reviewed_by = null,
    review_notes = excluded.review_notes,
    updated_at = excluded.updated_at;

-- Legacy imports sometimes copied a generated cutout into label_image_url. A
-- rejected object in that field defeats cutout_url's publication signal because
-- older read models use coalesce(cutout_url, label_image_url). Preserve the URL
-- in the processing ledger, then remove only those rejected internal pointers.
do $$
declare
  v_expected integer := 18;
  v_found integer;
begin
  select count(*) into v_found
  from public.beer_catalog b
  join public.beer_media_processing p on p.beer_id = b.id
  where b.cutout_url is null
    and b.label_image_url like
      'https://qfwiizvqxrhjlthbjosz.supabase.co/storage/v1/object/public/beer-cutouts/%'
    and p.source_url = b.label_image_url
    and p.error_code in ('manual_quality_rejection', 'visual_quality_review');
  if v_found <> v_expected then
    raise exception 'rejected internal source cleanup expected % rows, found %',
      v_expected, v_found;
  end if;
end
$$;

update public.beer_catalog b
set label_image_url = null
from public.beer_media_processing p
where p.beer_id = b.id
  and b.cutout_url is null
  and b.label_image_url like
    'https://qfwiizvqxrhjlthbjosz.supabase.co/storage/v1/object/public/beer-cutouts/%'
  and p.source_url = b.label_image_url
  and p.error_code in ('manual_quality_rejection', 'visual_quality_review');

-- Encode the customer-visible storage contract in the database. Internal
-- cutout paths are exact UUID PNGs, and a legacy internal label pointer may
-- exist only when it is also the explicitly published cutout.
alter table public.beer_catalog
  drop constraint if exists beer_catalog_cutout_url_contract;
alter table public.beer_catalog
  add constraint beer_catalog_cutout_url_contract
  check (
    cutout_url is null
    or cutout_url ~
      '^https://qfwiizvqxrhjlthbjosz[.]supabase[.]co/storage/v1/object/public/beer-cutouts/(v2/)?[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}[.]png$'
  );

alter table public.beer_catalog
  drop constraint if exists beer_catalog_internal_source_publication_check;
alter table public.beer_catalog
  add constraint beer_catalog_internal_source_publication_check
  check (
    label_image_url is null
    or label_image_url not like
      'https://qfwiizvqxrhjlthbjosz.supabase.co/storage/v1/object/public/beer-cutouts/%'
    or label_image_url = cutout_url
  );

alter table public.beer_media_processing
  drop constraint if exists beer_media_processing_candidate_url_contract;
alter table public.beer_media_processing
  add constraint beer_media_processing_candidate_url_contract
  check (
    candidate_cutout_url is null
    or candidate_cutout_url ~
      '^https://qfwiizvqxrhjlthbjosz[.]supabase[.]co/storage/v1/object/public/beer-cutouts/v2/[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}[.]png$'
  );

create or replace function public.admin_product_images(p_limit integer default 50)
returns table (
  beer_id uuid,
  beer_name text,
  source_url text,
  source_license text,
  candidate_url text,
  source_width integer,
  source_height integer,
  foreground_fraction numeric,
  staged_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.is_admin() then
    raise exception 'admin required';
  end if;
  return query
  select
    b.id,
    coalesce(nullif(b.display_name, ''), b.name),
    p.effective_source_url,
    b.label_image_license,
    p.candidate_cutout_url,
    p.source_width,
    p.source_height,
    p.foreground_fraction,
    p.updated_at
  from public.beer_media_processing p
  join public.beer_catalog b on b.id = p.beer_id
  where p.status = 'pending_review'
    and p.pipeline_version = 'v2'
    and p.candidate_cutout_url ~
      '^https://qfwiizvqxrhjlthbjosz[.]supabase[.]co/storage/v1/object/public/beer-cutouts/v2/[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}[.]png$'
  order by p.updated_at, p.beer_id
  limit least(greatest(coalesce(p_limit, 50), 1), 100);
end
$$;

create or replace function public.review_product_image(
  p_beer_id uuid,
  p_decision text
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_candidate text;
  v_source text;
begin
  if not public.is_admin() then
    raise exception 'admin required';
  end if;
  if p_decision not in ('approve', 'reject') then
    raise exception 'invalid decision';
  end if;

  select p.candidate_cutout_url, p.source_url
    into v_candidate, v_source
  from public.beer_media_processing p
  where p.beer_id = p_beer_id
    and p.status = 'pending_review'
    and p.pipeline_version = 'v2'
  for update;

  if v_candidate is null then
    raise exception 'pending image not found';
  end if;
  if v_candidate !~
      '^https://qfwiizvqxrhjlthbjosz[.]supabase[.]co/storage/v1/object/public/beer-cutouts/v2/[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}[.]png$' then
    raise exception 'invalid candidate URL';
  end if;
  if not exists (
    select 1
    from public.beer_catalog b
    where b.id = p_beer_id
      and b.label_image_url = v_source
  ) then
    raise exception 'source image changed; rebuild required';
  end if;

  if p_decision = 'approve' then
    update public.beer_catalog
    set cutout_url = v_candidate
    where id = p_beer_id;
    update public.beer_media_processing
    set status = 'completed',
        error_code = null,
        reviewed_at = now(),
        reviewed_by = auth.uid(),
        review_notes = 'Approved in paired product-image review',
        updated_at = now()
    where beer_id = p_beer_id;
  else
    update public.beer_catalog
    set cutout_url = null
    where id = p_beer_id;
    update public.beer_media_processing
    set status = 'rejected',
        error_code = 'manual_quality_rejection',
        reviewed_at = now(),
        reviewed_by = auth.uid(),
        review_notes = 'Rejected in paired product-image review',
        updated_at = now()
    where beer_id = p_beer_id;
  end if;
end
$$;

revoke all on function public.admin_product_images(integer) from public, anon;
revoke all on function public.review_product_image(uuid, text) from public, anon;
grant execute on function public.admin_product_images(integer) to authenticated;
grant execute on function public.review_product_image(uuid, text) to authenticated;

notify pgrst, 'reload schema';
