-- Remove historically propagated OFF photos whose URL barcode disagrees with
-- the catalog GTIN, then make every image-bearing OFF ingestion path stage an
-- exact source candidate instead of publishing directly.

with mismatched as (
  select
    b.id,
    b.label_image_url,
    regexp_replace(
      coalesce(nullif(b.gtin, ''), nullif(b.external_ids->>'off_code', '')),
      '[^0-9]', '', 'g'
    ) as expected_code,
    regexp_replace(
      regexp_replace(
        split_part(b.label_image_url, '/products/', 2),
        '/[^/]+$', ''
      ),
      '[^0-9]', '', 'g'
    ) as url_code
  from public.beer_catalog b
  where b.label_image_url like
    'https://images.openfoodfacts.org/images/products/%'
)
update public.beer_media_processing p
set status = 'rejected',
    error_code = 'catalog_source_gtin_mismatch',
    rejection_reason = 'wrong_product',
    review_notes = 'Quarantined by exact URL/catalog GTIN audit',
    reviewed_at = now(),
    updated_at = now()
from mismatched m
where p.beer_id = m.id
  and m.expected_code <> ''
  and m.url_code <> ''
  and ltrim(m.url_code, '0') <> ltrim(m.expected_code, '0');

with mismatched as (
  select
    b.id,
    b.label_image_url,
    regexp_replace(
      coalesce(nullif(b.gtin, ''), nullif(b.external_ids->>'off_code', '')),
      '[^0-9]', '', 'g'
    ) as expected_code,
    regexp_replace(
      regexp_replace(
        split_part(b.label_image_url, '/products/', 2),
        '/[^/]+$', ''
      ),
      '[^0-9]', '', 'g'
    ) as url_code
  from public.beer_catalog b
  where b.label_image_url like
    'https://images.openfoodfacts.org/images/products/%'
)
update public.beer_media_source_candidate c
set status = 'rejected',
    reviewed_at = now(),
    updated_at = now(),
    source_metadata = c.source_metadata || jsonb_build_object(
      'rejection_reason', 'catalog_source_gtin_mismatch'
    )
from mismatched m
where c.beer_id = m.id
  and c.source_url = m.label_image_url
  and m.expected_code <> ''
  and m.url_code <> ''
  and ltrim(m.url_code, '0') <> ltrim(m.expected_code, '0');

with mismatched as (
  select
    b.id,
    b.label_image_url,
    regexp_replace(
      coalesce(nullif(b.gtin, ''), nullif(b.external_ids->>'off_code', '')),
      '[^0-9]', '', 'g'
    ) as expected_code,
    regexp_replace(
      regexp_replace(
        split_part(b.label_image_url, '/products/', 2),
        '/[^/]+$', ''
      ),
      '[^0-9]', '', 'g'
    ) as url_code
  from public.beer_catalog b
  where b.label_image_url like
    'https://images.openfoodfacts.org/images/products/%'
)
update public.beer_catalog b
set external_ids = coalesce(b.external_ids, '{}'::jsonb) || jsonb_build_object(
      'image_quarantine_20260724',
      jsonb_build_object(
        'reason', 'catalog_source_gtin_mismatch',
        'source_url', m.label_image_url,
        'source_gtin', m.url_code,
        'catalog_gtin', m.expected_code
      )
    ),
    label_image_url = null,
    label_image_license = null,
    cutout_url = null,
    updated_at = now()
from mismatched m
where b.id = m.id
  and m.expected_code <> ''
  and m.url_code <> ''
  and ltrim(m.url_code, '0') <> ltrim(m.expected_code, '0');

create or replace function public.admin_ingest_beers(p_payload jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  rec jsonb;
  v_gtin text; v_name text; v_brand text; v_country text; v_style text;
  v_abv numeric; v_img text; v_na boolean;
  v_brewery_id uuid; v_beer_id uuid; v_new uuid;
  n_ins int := 0; n_upd int := 0; n_skip int := 0;
begin
  for rec in select value
             from jsonb_array_elements(coalesce(p_payload, '[]'::jsonb)) as t(value)
  loop
    v_gtin := regexp_replace(coalesce(rec->>'gtin', ''), '[^0-9]', '', 'g');
    v_name := trim(coalesce(rec->>'name', ''));
    v_brand := nullif(trim(coalesce(rec->>'brand', '')), '');
    v_country := nullif(trim(coalesce(rec->>'country', '')), '');
    v_style := nullif(trim(coalesce(rec->>'style', '')), '');
    v_img := nullif(trim(coalesce(rec->>'image_url', '')), '');
    v_abv := case when (rec->>'abv') ~ '^[0-9]+([.][0-9]+)?$'
                  then (rec->>'abv')::numeric end;

    if length(v_name) < 2 or length(v_name) > 160 then
      n_skip := n_skip + 1; continue;
    end if;
    if length(v_gtin) not between 8 and 14 then
      n_skip := n_skip + 1; continue;
    end if;
    if v_abv is not null and (v_abv < 0 or v_abv > 70) then v_abv := null; end if;
    if v_img is not null and v_img !~
       '^https://images[.]openfoodfacts[.]org/images/products/' then
      v_img := null;
    end if;
    v_na := coalesce((rec->>'is_na_low')::boolean, v_abv is not null and v_abv <= 0.5);

    v_brewery_id := null;
    if v_brand is not null then
      select id into v_brewery_id
      from public.brewery where lower(name) = lower(v_brand) limit 1;
      if v_brewery_id is null then
        insert into public.brewery(name, country, external_ids)
        values (
          v_brand,
          coalesce(v_country, 'Unknown'),
          jsonb_build_object('source', 'open_food_facts')
        )
        returning id into v_brewery_id;
      end if;
    end if;

    v_new := null;
    insert into public.beer_catalog(
      name, style, abv, is_na_low, gtin, brewery_id, external_ids
    )
    values (
      v_name, v_style, v_abv, v_na, v_gtin, v_brewery_id,
      jsonb_build_object('source', 'open_food_facts', 'off_code', v_gtin)
    )
    on conflict (gtin) where gtin is not null do nothing
    returning id into v_new;

    if v_new is not null then
      v_beer_id := v_new;
      n_ins := n_ins + 1;
    else
      update public.beer_catalog set
        style = coalesce(style, v_style),
        abv = coalesce(abv, v_abv),
        brewery_id = coalesce(brewery_id, v_brewery_id),
        updated_at = now()
      where gtin = v_gtin
      returning id into v_beer_id;
      n_upd := n_upd + 1;
    end if;

    if v_img is not null and length(v_gtin) in (8, 12, 13, 14) then
      insert into public.beer_media_source_candidate(
        beer_id, source_url, source_license, source_kind,
        source_external_id, source_page_url, source_gtin, source_metadata, status
      )
      select
        v_beer_id, v_img, 'Open Food Facts image (CC BY-SA 3.0)',
        'open_food_facts', v_gtin,
        'https://world.openfoodfacts.org/product/' || v_gtin,
        v_gtin,
        jsonb_build_object('match_kind', 'exact_gtin', 'discovery', 'admin_ingest_beers'),
        'pending_cutout'
      from public.beer_catalog b
      where b.id = v_beer_id
        and nullif(btrim(b.label_image_url), '') is null
        and nullif(btrim(b.cutout_url), '') is null
      on conflict (beer_id) do nothing;
    end if;
  end loop;

  return jsonb_build_object('inserted', n_ins, 'updated', n_upd, 'skipped', n_skip);
end
$$;

revoke all on function public.admin_ingest_beers(jsonb)
  from public, anon, authenticated;
grant execute on function public.admin_ingest_beers(jsonb) to service_role;

create or replace function public.add_verified_beer_from_barcode(
  p_user uuid,
  p_gtin text,
  p_name text,
  p_brand text default null,
  p_abv numeric default null,
  p_image_url text default null
)
returns table (
  id uuid,
  name text,
  style text,
  abv numeric,
  brewery_name text,
  country text
)
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_gtin text := regexp_replace(coalesce(p_gtin, ''), '[^0-9]', '', 'g');
  v_name text := trim(coalesce(p_name, ''));
  v_brand text := nullif(trim(coalesce(p_brand, '')), '');
  v_image_url text := nullif(trim(coalesce(p_image_url, '')), '');
  v_brewery_id uuid;
  v_beer_id uuid;
  v_recent integer;
begin
  if p_user is null or not exists (select 1 from auth.users u where u.id = p_user) then
    raise exception 'valid user required';
  end if;
  if length(v_gtin) not in (8, 12, 13, 14) then raise exception 'invalid barcode'; end if;
  if length(v_name) not between 2 and 160 then raise exception 'invalid name'; end if;
  if v_brand is not null and length(v_brand) > 160 then raise exception 'invalid brand'; end if;
  if p_abv is not null and (p_abv < 0 or p_abv > 70) then raise exception 'invalid abv'; end if;
  if v_image_url is not null and v_image_url !~
     '^https://images[.]openfoodfacts[.]org/images/products/' then
    raise exception 'invalid image source';
  end if;

  select count(*) into v_recent
  from public.beer_catalog bc
  where bc.external_ids->>'added_by' = p_user::text
    and bc.created_at > now() - interval '1 day';
  if v_recent >= 40 then raise exception 'daily add limit reached'; end if;

  select bc.id into v_beer_id
  from public.beer_catalog bc where bc.gtin = v_gtin limit 1;

  if v_beer_id is null then
    if v_brand is not null then
      select b.id into v_brewery_id
      from public.brewery b
      where lower(b.name) = lower(v_brand)
      order by b.created_at
      limit 1;

      if v_brewery_id is null then
        insert into public.brewery(name, external_ids)
        values (
          v_brand,
          jsonb_build_object(
            'source', 'open_food_facts',
            'verified_via', 'verify-barcode-beer',
            'added_by', p_user
          )
        )
        returning brewery.id into v_brewery_id;
      end if;
    end if;

    insert into public.beer_catalog(
      name, abv, is_na_low, gtin, brewery_id, external_ids
    )
    values (
      v_name, p_abv, coalesce(p_abv, 100) <= 0.5, v_gtin, v_brewery_id,
      jsonb_build_object(
        'off_barcode', v_gtin,
        'source', 'open_food_facts',
        'verified_via', 'verify-barcode-beer',
        'verified_at', now(),
        'added_by', p_user
      )
    )
    on conflict (gtin) where gtin is not null do nothing
    returning beer_catalog.id into v_beer_id;

    if v_beer_id is null then
      select bc.id into v_beer_id
      from public.beer_catalog bc where bc.gtin = v_gtin limit 1;
    end if;
  end if;

  if v_image_url is not null then
    insert into public.beer_media_source_candidate(
      beer_id, source_url, source_license, source_kind,
      source_external_id, source_page_url, source_gtin,
      source_metadata, status
    )
    select
      v_beer_id, v_image_url, 'Open Food Facts image (CC BY-SA 3.0)',
      'open_food_facts', v_gtin,
      'https://world.openfoodfacts.org/product/' || v_gtin,
      v_gtin,
      jsonb_build_object(
        'match_kind', 'exact_gtin',
        'discovery', 'verify-barcode-beer',
        'added_by', p_user
      ),
      'pending_cutout'
    from public.beer_catalog b
    where b.id = v_beer_id
      and nullif(btrim(b.label_image_url), '') is null
      and nullif(btrim(b.cutout_url), '') is null
    on conflict (beer_id) do nothing;
  end if;

  return query
  select bc.id, bc.name, bc.style, bc.abv, br.name, br.country
  from public.beer_catalog bc
  left join public.brewery br on br.id = bc.brewery_id
  where bc.id = v_beer_id;
end;
$$;

revoke all on function public.add_verified_beer_from_barcode(
  uuid, text, text, text, numeric, text
) from public, anon, authenticated;
grant execute on function public.add_verified_beer_from_barcode(
  uuid, text, text, text, numeric, text
) to service_role;

notify pgrst, 'reload schema';
