-- Product image factory v3.
--
-- Preserve every reviewed v2 cutout while allowing the factory to retry old
-- automated failures with exact-GTIN OFF originals and the BiRefNet model.
-- Human review remains mandatory before a candidate becomes customer-visible.

alter table public.beer_media_processing
  add column if not exists effective_source_kind text,
  add column if not exists segmentation_model text,
  add column if not exists derivative_sha256 text,
  add column if not exists transformation_notes text;

alter table public.beer_media_processing
  drop constraint if exists beer_media_processing_source_kind_check;
alter table public.beer_media_processing
  add constraint beer_media_processing_source_kind_check
  check (
    effective_source_kind is null
    or effective_source_kind in (
      'open_food_facts_front',
      'open_food_facts_raw',
      'wikimedia_commons',
      'partner_official',
      'tapt_storage'
    )
  );

alter table public.beer_media_processing
  drop constraint if exists beer_media_processing_segmentation_model_check;
alter table public.beer_media_processing
  add constraint beer_media_processing_segmentation_model_check
  check (
    segmentation_model is null
    or length(btrim(segmentation_model)) between 1 and 80
  );

-- Newly discovered sources stay off every customer surface until the source
-- and its generated cutout pass the same paired admin review. This avoids
-- making a technically real but poor P18 scene the catalog default.
create table if not exists public.beer_media_source_candidate (
  beer_id uuid primary key references public.beer_catalog(id) on delete cascade,
  source_url text not null,
  source_license text not null,
  source_kind text not null
    check (source_kind in ('wikimedia_commons', 'open_food_facts', 'partner_official')),
  source_external_id text,
  source_page_url text,
  source_license_url text,
  source_creator text,
  source_revision text,
  source_sha1 text,
  source_width integer,
  source_height integer,
  source_gtin text,
  source_metadata jsonb not null default '{}'::jsonb,
  rights_confirmed_by uuid,
  rights_confirmed_at timestamptz,
  status text not null default 'pending_cutout'
    check (status in ('pending_cutout', 'approved', 'rejected')),
  discovered_at timestamptz not null default now(),
  reviewed_at timestamptz,
  updated_at timestamptz not null default now(),
  check (
    source_url ~ '^https://(upload[.]wikimedia[.]org|images[.]openfoodfacts[.]org)/'
    or source_url ~ '^https://qfwiizvqxrhjlthbjosz[.]supabase[.]co/storage/v1/object/public/partner-assets/[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}/beer-images/'
  ),
  check (length(btrim(source_license)) between 3 and 500),
  check (source_page_url is null or source_page_url ~ '^https://'),
  check (source_license_url is null or source_license_url ~ '^https://'),
  check (source_sha1 is null or source_sha1 ~ '^[0-9a-z]{20,64}$'),
  check (
    (source_width is null and source_height is null)
    or (source_width > 0 and source_height > 0)
  ),
  check (source_gtin is null or source_gtin ~ '^([0-9]{8}|[0-9]{12,14})$'),
  check (jsonb_typeof(source_metadata) = 'object'),
  check (
    source_kind <> 'partner_official'
    or (rights_confirmed_by is not null and rights_confirmed_at is not null)
  ),
  check (
    source_kind <> 'partner_official'
    or source_url ~ (
      '^https://qfwiizvqxrhjlthbjosz[.]supabase[.]co/storage/v1/object/public/partner-assets/'
      || '[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}/beer-images/'
      || beer_id::text || '-[0-9]{10,20}[.](png|jpg|jpeg|webp)$'
    )
  )
);

create index if not exists beer_media_source_candidate_status
  on public.beer_media_source_candidate (status, updated_at, beer_id);

alter table public.beer_media_source_candidate enable row level security;
revoke all on table public.beer_media_source_candidate from anon, authenticated;
grant select, insert, update, delete on table public.beer_media_source_candidate to service_role;

-- Exact barcodes let the factory resolve the uncropped contributor upload
-- behind an OFF selected-front crop. Keep this internal surface service-only.
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
  s.standing as market_standing
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
  s.standing as market_standing
from public.beer_media_source_candidate c
join public.beer_catalog b on b.id = c.beer_id
left join public.beer_market_standing s on s.beer_id = b.id
where c.status = 'pending_cutout'
  and nullif(btrim(b.label_image_url), '') is null
  and nullif(btrim(b.cutout_url), '') is null;

comment on view public.cutout_queue is
  'Service-only v3 product-image queue; exact GTIN enables uncropped OFF source recovery.';

revoke all privileges on table public.cutout_queue
  from public, anon, authenticated;
grant select on table public.cutout_queue to service_role;

alter table public.beer_catalog
  drop constraint if exists beer_catalog_cutout_url_contract;
alter table public.beer_catalog
  add constraint beer_catalog_cutout_url_contract
  check (
    cutout_url is null
    or cutout_url ~
      '^https://qfwiizvqxrhjlthbjosz[.]supabase[.]co/storage/v1/object/public/beer-cutouts/(v[23]/)?[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}[.]png$'
  );

alter table public.beer_media_processing
  drop constraint if exists beer_media_processing_candidate_url_contract;
alter table public.beer_media_processing
  add constraint beer_media_processing_candidate_url_contract
  check (
    candidate_cutout_url is null
    or candidate_cutout_url ~
      '^https://qfwiizvqxrhjlthbjosz[.]supabase[.]co/storage/v1/object/public/beer-cutouts/v[23]/[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}[.]png$'
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
    coalesce(c.source_license, b.label_image_license),
    p.candidate_cutout_url,
    p.source_width,
    p.source_height,
    p.foreground_fraction,
    p.updated_at
  from public.beer_media_processing p
  join public.beer_catalog b on b.id = p.beer_id
  left join public.beer_media_source_candidate c
    on c.beer_id = p.beer_id and c.source_url = p.source_url
  where p.status = 'pending_review'
    and p.pipeline_version in ('v2', 'v3')
    and p.candidate_cutout_url ~
      '^https://qfwiizvqxrhjlthbjosz[.]supabase[.]co/storage/v1/object/public/beer-cutouts/v[23]/[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}[.]png$'
  order by
    case p.pipeline_version when 'v3' then 0 else 1 end,
    p.updated_at,
    p.beer_id
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
  v_source_license text;
  v_discovered_source boolean := false;
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
    and p.pipeline_version in ('v2', 'v3')
  for update;

  if v_candidate is null then
    raise exception 'pending image not found';
  end if;
  if v_candidate !~
      '^https://qfwiizvqxrhjlthbjosz[.]supabase[.]co/storage/v1/object/public/beer-cutouts/v[23]/[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}[.]png$' then
    raise exception 'invalid candidate URL';
  end if;
  if not exists (
    select 1
    from public.beer_catalog b
    where b.id = p_beer_id
      and b.label_image_url = v_source
  ) then
    select c.source_license, true
      into v_source_license, v_discovered_source
    from public.beer_media_source_candidate c
    where c.beer_id = p_beer_id
      and c.source_url = v_source
      and c.status = 'pending_cutout';
    if not coalesce(v_discovered_source, false) then
      raise exception 'source image changed; rebuild required';
    end if;
  end if;

  if p_decision = 'approve' then
    update public.beer_catalog
    set cutout_url = v_candidate,
        label_image_url = case when v_discovered_source then v_source else label_image_url end,
        label_image_license = case when v_discovered_source then v_source_license else label_image_license end
    where id = p_beer_id;
    update public.beer_media_source_candidate
    set status = 'approved', reviewed_at = now(), updated_at = now()
    where beer_id = p_beer_id and v_discovered_source;
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
    update public.beer_media_source_candidate
    set status = 'rejected', reviewed_at = now(), updated_at = now()
    where beer_id = p_beer_id and v_discovered_source;
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

revoke all on function public.admin_product_images(integer)
  from public, anon;
revoke all on function public.review_product_image(uuid, text)
  from public, anon;
grant execute on function public.admin_product_images(integer) to authenticated;
grant execute on function public.review_product_image(uuid, text) to authenticated;

create or replace function public.partner_imageless_taps(p_venue uuid)
returns table (
  beer_id uuid,
  beer_name text,
  brewery_name text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'sign in required'; end if;
  if not exists (
    select 1
    from public.venue_claim vc
    where vc.venue_id = p_venue
      and vc.user_id = auth.uid()
      and vc.status = 'approved'
  ) then
    raise exception 'venue not claimed/approved';
  end if;

  return query
  select distinct on (b.id)
    b.id,
    coalesce(nullif(b.display_name, ''), b.name),
    br.name
  from public.venue_tap_snapshot s
  join public.venue_tap_item i on i.snapshot_id = s.id
  join public.beer_catalog b on b.id = i.beer_id
  left join public.brewery br on br.id = b.brewery_id
  where s.venue_id = p_venue
    and s.id = (
      select latest.id
      from public.venue_tap_snapshot latest
      where latest.venue_id = p_venue
      order by latest.observed_at desc, latest.id desc
      limit 1
    )
    and nullif(btrim(b.cutout_url), '') is null
    and nullif(btrim(b.label_image_url), '') is null
    and not exists (
      select 1
      from public.beer_media_source_candidate c
      where c.beer_id = b.id and c.status in ('pending_cutout', 'approved')
    )
  order by b.id, i.created_at;
end
$$;

create or replace function public.submit_partner_beer_image(
  p_venue uuid,
  p_beer uuid,
  p_url text,
  p_rights_confirmed boolean
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_prefix constant text :=
    'https://qfwiizvqxrhjlthbjosz.supabase.co/storage/v1/object/public/partner-assets/';
  v_venue_name text;
  v_source_gtin text;
begin
  if auth.uid() is null then raise exception 'sign in required'; end if;
  if not coalesce(p_rights_confirmed, false) then
    raise exception 'image rights confirmation required';
  end if;
  select v.name into v_venue_name
  from public.venue v
  join public.venue_claim vc on vc.venue_id = v.id
  where v.id = p_venue
    and vc.user_id = auth.uid()
    and vc.status = 'approved';
  if v_venue_name is null then raise exception 'venue not claimed/approved'; end if;
  if p_url !~ (
    '^' || replace(v_prefix, '.', '[.]') || p_venue::text
    || '/beer-images/' || p_beer::text || '-[0-9]{10,20}[.](png|jpg|jpeg|webp)$'
  ) then
    raise exception 'photo must be uploaded to this venue''s Tapt beer-image folder';
  end if;
  if not exists (
    select 1
    from public.venue_tap_snapshot s
    join public.venue_tap_item i on i.snapshot_id = s.id
    where s.venue_id = p_venue
      and i.beer_id = p_beer
      and s.id = (
        select latest.id
        from public.venue_tap_snapshot latest
        where latest.venue_id = p_venue
        order by latest.observed_at desc, latest.id desc
        limit 1
      )
  ) then
    raise exception 'beer is not matched on this venue''s current menu';
  end if;
  if exists (
    select 1 from public.beer_catalog b
    where b.id = p_beer
      and coalesce(nullif(b.cutout_url, ''), nullif(b.label_image_url, '')) is not null
  ) then
    raise exception 'beer already has product art';
  end if;
  select b.gtin into v_source_gtin
  from public.beer_catalog b
  where b.id = p_beer;

  insert into public.beer_media_source_candidate as candidate (
    beer_id,
    source_url,
    source_license,
    source_kind,
    source_external_id,
    source_creator,
    source_gtin,
    source_metadata,
    rights_confirmed_by,
    rights_confirmed_at,
    status,
    updated_at
  ) values (
    p_beer,
    p_url,
    'Partner commercial-use grant (rights attested at submission)',
    'partner_official',
    'venue:' || p_venue::text,
    v_venue_name,
    v_source_gtin,
    jsonb_build_object(
      'venue_id', p_venue,
      'grant_scope', 'host reproduce resize background-remove display app web catalog previews'
    ),
    auth.uid(),
    now(),
    'pending_cutout',
    now()
  )
  on conflict (beer_id) do update
  set source_url = excluded.source_url,
      source_license = excluded.source_license,
      source_kind = excluded.source_kind,
      source_external_id = excluded.source_external_id,
      source_creator = excluded.source_creator,
      source_gtin = excluded.source_gtin,
      source_metadata = excluded.source_metadata,
      rights_confirmed_by = excluded.rights_confirmed_by,
      rights_confirmed_at = excluded.rights_confirmed_at,
      status = 'pending_cutout',
      reviewed_at = null,
      updated_at = now()
  where candidate.status <> 'approved';

  delete from public.beer_media_processing
  where beer_id = p_beer
    and status <> 'completed';
end
$$;

revoke all on function public.partner_imageless_taps(uuid) from public, anon;
revoke all on function public.submit_partner_beer_image(uuid, uuid, text, boolean)
  from public, anon;
grant execute on function public.partner_imageless_taps(uuid) to authenticated;
grant execute on function public.submit_partner_beer_image(uuid, uuid, text, boolean)
  to authenticated;

notify pgrst, 'reload schema';
