-- Give the reviewer the complete source provenance already retained by the
-- ledger, and expose only immutable v4 derivatives to the decision queue.
drop function if exists public.admin_product_images(integer);
create function public.admin_product_images(p_limit integer default 50)
returns table (
  beer_id uuid,
  beer_name text,
  brewery_name text,
  catalog_gtin text,
  source_gtin text,
  source_kind text,
  source_url text,
  source_page_url text,
  source_external_id text,
  source_license text,
  source_license_url text,
  source_creator text,
  source_revision text,
  source_sha1 text,
  rights_confirmed_at timestamptz,
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
    coalesce(c.source_kind, p.effective_source_kind),
    p.effective_source_url,
    c.source_page_url,
    c.source_external_id,
    coalesce(c.source_license, b.label_image_license),
    c.source_license_url,
    c.source_creator,
    c.source_revision,
    c.source_sha1,
    c.rights_confirmed_at,
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
    and p.pipeline_version = 'v4'
    and p.candidate_cutout_url ~ (
      '^https://qfwiizvqxrhjlthbjosz[.]supabase[.]co/storage/v1/object/public/'
      || 'beer-cutouts/v4/[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}/'
      || '[0-9a-f]{64}[.]png$'
    )
  order by p.updated_at, p.beer_id
  limit least(greatest(coalesce(p_limit, 50), 1), 100);
end
$$;

revoke all on function public.admin_product_images(integer) from public, anon;
grant execute on function public.admin_product_images(integer) to authenticated;

notify pgrst, 'reload schema';
