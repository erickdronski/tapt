-- Product-image quality v4: exact identity, immutable reviewed bytes, and
-- evidence-complete human decisions.

alter table public.beer_media_processing
  add column if not exists rejection_reason text;

alter table public.beer_media_processing
  drop constraint if exists beer_media_processing_rejection_reason_check;
alter table public.beer_media_processing
  add constraint beer_media_processing_rejection_reason_check
  check (
    rejection_reason is null
    or rejection_reason in (
      'wrong_product',
      'back_label',
      'cropped_product',
      'background_artifact',
      'low_resolution',
      'blur_or_glare',
      'multipack',
      'other'
    )
  );

-- A manually rejected source must never remain customer-visible just because
-- the source hostname itself is trusted.
update public.beer_catalog b
set label_image_url = null,
    label_image_license = null
from public.beer_media_processing p
where p.beer_id = b.id
  and p.status = 'rejected'
  and p.error_code in ('manual_quality_rejection', 'visual_quality_review')
  and p.source_url = b.label_image_url
  and nullif(b.cutout_url, '') is null;

drop view if exists public.cutout_queue;
create view public.cutout_queue
with (security_invoker = true)
as
select
  b.id,
  b.name,
  b.gtin,
  b.label_image_url,
  b.label_image_license,
  b.cutout_url,
  b.updated_at,
  s.standing as market_standing,
  0 as source_priority,
  case
    when b.label_image_url like 'https://images.openfoodfacts.org/%' then b.gtin
    else null
  end as source_gtin,
  case
    when b.label_image_url like 'https://images.openfoodfacts.org/%'
      and nullif(regexp_replace(coalesce(b.gtin, ''), '\D', '', 'g'), '') is not null
    then 'https://world.openfoodfacts.org/product/' || regexp_replace(b.gtin, '\D', '', 'g')
    else null
  end as source_page_url,
  null::text as source_external_id,
  case
    when b.label_image_url like 'https://images.openfoodfacts.org/%' then 'open_food_facts'
    when b.label_image_url like 'https://upload.wikimedia.org/%'
      or b.label_image_url like 'https://commons.wikimedia.org/%' then 'wikimedia_commons'
    else 'legacy_source'
  end as source_kind
from public.beer_catalog b
left join public.beer_market_standing s on s.beer_id = b.id
where nullif(btrim(b.label_image_url), '') is not null
  and not exists (
    select 1
    from public.beer_media_processing p
    where p.beer_id = b.id
      and p.status = 'rejected'
      and p.error_code in ('visual_quality_review', 'manual_quality_rejection')
  )
union all
select
  b.id,
  b.name,
  b.gtin,
  c.source_url,
  c.source_license,
  b.cutout_url,
  c.updated_at,
  s.standing as market_standing,
  1 as source_priority,
  c.source_gtin,
  c.source_page_url,
  c.source_external_id,
  c.source_kind
from public.beer_media_source_candidate c
join public.beer_catalog b on b.id = c.beer_id
left join public.beer_market_standing s on s.beer_id = b.id
where c.status = 'pending_cutout'
  and nullif(btrim(b.label_image_url), '') is null
  and nullif(btrim(b.cutout_url), '') is null
  and (
    c.source_kind <> 'open_food_facts'
    or (
      nullif(regexp_replace(coalesce(b.gtin, ''), '\D', '', 'g'), '') is not null
      and regexp_replace(c.source_gtin, '\D', '', 'g') = regexp_replace(b.gtin, '\D', '', 'g')
    )
  );

comment on view public.cutout_queue is
  'Service-only v4 queue with exact source identity evidence; new licensed sources precede legacy reprocessing.';
revoke all privileges on table public.cutout_queue from public, anon, authenticated;
grant select on table public.cutout_queue to service_role;

alter table public.beer_catalog
  drop constraint if exists beer_catalog_cutout_url_contract;
alter table public.beer_catalog
  add constraint beer_catalog_cutout_url_contract
  check (
    cutout_url is null
    or cutout_url ~ (
      '^https://qfwiizvqxrhjlthbjosz[.]supabase[.]co/storage/v1/object/public/beer-cutouts/'
      || '((v[23]/)?[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}[.]png'
      || '|v4/[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}/[0-9a-f]{64}[.]png)$'
    )
  );

alter table public.beer_media_processing
  drop constraint if exists beer_media_processing_candidate_url_contract;
alter table public.beer_media_processing
  add constraint beer_media_processing_candidate_url_contract
  check (
    candidate_cutout_url is null
    or candidate_cutout_url ~ (
      '^https://qfwiizvqxrhjlthbjosz[.]supabase[.]co/storage/v1/object/public/beer-cutouts/'
      || '(v[23]/[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}[.]png'
      || '|v4/[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}/[0-9a-f]{64}[.]png)$'
    )
  );

drop function if exists public.admin_product_images(integer);
create function public.admin_product_images(p_limit integer default 50)
returns table (
  beer_id uuid,
  beer_name text,
  brewery_name text,
  catalog_gtin text,
  source_gtin text,
  source_url text,
  source_page_url text,
  source_external_id text,
  source_license text,
  candidate_url text,
  source_width integer,
  source_height integer,
  foreground_fraction numeric,
  source_sha256 text,
  derivative_sha256 text,
  segmentation_model text,
  transformation_notes text,
  staged_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.is_admin() then raise exception 'admin required'; end if;
  return query
  select
    b.id,
    coalesce(nullif(b.display_name, ''), b.name),
    br.name,
    b.gtin,
    c.source_gtin,
    p.effective_source_url,
    c.source_page_url,
    c.source_external_id,
    coalesce(c.source_license, b.label_image_license),
    p.candidate_cutout_url,
    p.source_width,
    p.source_height,
    p.foreground_fraction,
    p.source_sha256,
    p.derivative_sha256,
    p.segmentation_model,
    p.transformation_notes,
    p.updated_at
  from public.beer_media_processing p
  join public.beer_catalog b on b.id = p.beer_id
  left join public.brewery br on br.id = b.brewery_id
  left join public.beer_media_source_candidate c
    on c.beer_id = p.beer_id and c.source_url = p.source_url
  where p.status = 'pending_review'
    and p.pipeline_version in ('v2', 'v3', 'v4')
    and p.candidate_cutout_url ~ (
      '^https://qfwiizvqxrhjlthbjosz[.]supabase[.]co/storage/v1/object/public/beer-cutouts/'
      || '(v[23]/[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}[.]png'
      || '|v4/[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}/[0-9a-f]{64}[.]png)$'
    )
  order by
    case p.pipeline_version when 'v4' then 0 when 'v3' then 1 else 2 end,
    p.updated_at,
    p.beer_id
  limit least(greatest(coalesce(p_limit, 50), 1), 100);
end
$$;

drop function if exists public.review_product_image(uuid, text);
drop function if exists public.review_product_image(uuid, text, text);
create function public.review_product_image(
  p_beer_id uuid,
  p_decision text,
  p_reason text default null
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_processing record;
  v_catalog record;
  v_candidate record;
  v_publish_source text;
  v_source_license text;
  v_expected_hash text;
  v_reason text;
begin
  if not public.is_admin() then raise exception 'admin required'; end if;
  if p_decision not in ('approve', 'reject') then raise exception 'invalid decision'; end if;

  v_reason := nullif(btrim(coalesce(p_reason, '')), '');
  if p_decision = 'reject' and (
    v_reason is null
    or v_reason not in (
      'wrong_product', 'back_label', 'cropped_product', 'background_artifact',
      'low_resolution', 'blur_or_glare', 'multipack', 'other'
    )
  ) then
    raise exception 'structured rejection reason required';
  end if;

  select p.* into v_processing
  from public.beer_media_processing p
  where p.beer_id = p_beer_id
    and p.status = 'pending_review'
    and p.pipeline_version in ('v2', 'v3', 'v4')
  for update;
  if v_processing.candidate_cutout_url is null then raise exception 'pending image not found'; end if;

  select b.* into v_catalog
  from public.beer_catalog b where b.id = p_beer_id for update;
  select c.* into v_candidate
  from public.beer_media_source_candidate c
  where c.beer_id = p_beer_id and c.source_url = v_processing.source_url;

  if v_processing.pipeline_version = 'v4' then
    v_expected_hash := substring(
      v_processing.candidate_cutout_url from '/([0-9a-f]{64})[.]png$'
    );
    if v_expected_hash is null or v_expected_hash <> v_processing.derivative_sha256 then
      raise exception 'reviewed bytes do not match immutable candidate URL';
    end if;
  elsif v_processing.candidate_cutout_url !~
      '^https://qfwiizvqxrhjlthbjosz[.]supabase[.]co/storage/v1/object/public/beer-cutouts/v[23]/[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}[.]png$' then
    raise exception 'invalid legacy candidate URL';
  end if;

  if coalesce(v_processing.effective_source_url, v_processing.source_url)
       like 'https://images.openfoodfacts.org/%' then
    if nullif(regexp_replace(coalesce(v_catalog.gtin, ''), '\D', '', 'g'), '') is null then
      raise exception 'exact catalog GTIN required for Open Food Facts approval';
    end if;
    if v_candidate.beer_id is not null and
       regexp_replace(coalesce(v_candidate.source_gtin, ''), '\D', '', 'g') <>
       regexp_replace(v_catalog.gtin, '\D', '', 'g') then
      raise exception 'source GTIN does not match catalog GTIN';
    end if;
  end if;

  v_publish_source := coalesce(v_processing.effective_source_url, v_processing.source_url);
  v_source_license := coalesce(v_candidate.source_license, v_catalog.label_image_license);

  if p_decision = 'approve' then
    update public.beer_catalog
    set cutout_url = v_processing.candidate_cutout_url,
        label_image_url = v_publish_source,
        label_image_license = v_source_license
    where id = p_beer_id;
    update public.beer_media_source_candidate
    set status = 'approved', reviewed_at = now(), updated_at = now()
    where beer_id = p_beer_id and source_url = v_processing.source_url;
    update public.beer_media_processing
    set status = 'completed', error_code = null, rejection_reason = null,
        reviewed_at = now(), reviewed_by = auth.uid(),
        review_notes = 'Approved exact product image and immutable derivative',
        updated_at = now()
    where beer_id = p_beer_id;
  else
    update public.beer_catalog
    set cutout_url = null,
        label_image_url = case
          when label_image_url in (v_processing.source_url, v_processing.effective_source_url) then null
          else label_image_url
        end,
        label_image_license = case
          when label_image_url in (v_processing.source_url, v_processing.effective_source_url) then null
          else label_image_license
        end
    where id = p_beer_id;
    update public.beer_media_source_candidate
    set status = 'rejected', reviewed_at = now(), updated_at = now()
    where beer_id = p_beer_id and source_url = v_processing.source_url;
    update public.beer_media_processing
    set status = 'rejected', error_code = 'manual_quality_rejection',
        rejection_reason = v_reason, reviewed_at = now(), reviewed_by = auth.uid(),
        review_notes = 'Rejected in paired review: ' || v_reason,
        updated_at = now()
    where beer_id = p_beer_id;
  end if;
end
$$;

revoke all on function public.admin_product_images(integer) from public, anon;
revoke all on function public.review_product_image(uuid, text, text) from public, anon;
grant execute on function public.admin_product_images(integer) to authenticated;
grant execute on function public.review_product_image(uuid, text, text) to authenticated;

notify pgrst, 'reload schema';
