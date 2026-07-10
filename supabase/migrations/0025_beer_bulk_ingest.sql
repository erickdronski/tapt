-- Bulk beer ingestion for the always-growing global catalog.
-- Idempotent by GTIN (barcode). Service-role only (server ingestion, never client).
-- Source today: Open Food Facts (ODbL). Reuses brewery-by-name find-or-create.

create or replace function admin_ingest_beers(p_payload jsonb)
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
  v_brewery_id uuid; v_new uuid;
  n_ins int := 0; n_upd int := 0; n_skip int := 0;
begin
  for rec in select value from jsonb_array_elements(coalesce(p_payload, '[]'::jsonb)) as t(value)
  loop
    v_gtin  := regexp_replace(coalesce(rec->>'gtin', ''), '[^0-9]', '', 'g');
    v_name  := trim(coalesce(rec->>'name', ''));
    v_brand := nullif(trim(coalesce(rec->>'brand', '')), '');
    v_country := nullif(trim(coalesce(rec->>'country', '')), '');
    v_style := nullif(trim(coalesce(rec->>'style', '')), '');
    v_img   := nullif(trim(coalesce(rec->>'image_url', '')), '');
    v_abv   := case when (rec->>'abv') ~ '^[0-9]+(\.[0-9]+)?$' then (rec->>'abv')::numeric else null end;

    -- validate
    if length(v_name) < 2 or length(v_name) > 160 then n_skip := n_skip + 1; continue; end if;
    if length(v_gtin) not between 8 and 14 then n_skip := n_skip + 1; continue; end if;
    if v_abv is not null and (v_abv < 0 or v_abv > 70) then v_abv := null; end if;
    v_na := coalesce((rec->>'is_na_low')::boolean, v_abv is not null and v_abv <= 0.5);

    -- brewery find-or-create by name
    v_brewery_id := null;
    if v_brand is not null then
      select id into v_brewery_id from brewery where lower(name) = lower(v_brand) limit 1;
      if v_brewery_id is null then
        insert into brewery(name, country, external_ids)
        values (v_brand, coalesce(v_country, 'Unknown'),
                jsonb_build_object('source', 'open_food_facts'))
        returning id into v_brewery_id;
      end if;
    end if;

    -- upsert beer by GTIN (partial unique index requires the predicate on the conflict target)
    insert into beer_catalog(name, style, abv, is_na_low, gtin, brewery_id,
                             label_image_url, label_image_license, external_ids)
    values (v_name, v_style, v_abv, v_na, v_gtin, v_brewery_id, v_img,
            case when v_img is not null then 'Open Food Facts (ODbL)' else null end,
            jsonb_build_object('source', 'open_food_facts', 'off_code', v_gtin))
    on conflict (gtin) where gtin is not null do nothing
    returning id into v_new;

    if v_new is not null then
      n_ins := n_ins + 1;
    else
      update beer_catalog set
        label_image_url = coalesce(label_image_url, v_img),
        style           = coalesce(style, v_style),
        abv             = coalesce(abv, v_abv),
        brewery_id      = coalesce(brewery_id, v_brewery_id),
        updated_at      = now()
      where gtin = v_gtin;
      n_upd := n_upd + 1;
    end if;
  end loop;

  return jsonb_build_object('inserted', n_ins, 'updated', n_upd, 'skipped', n_skip);
end
$$;

revoke all on function admin_ingest_beers(jsonb) from public, anon, authenticated;
grant execute on function admin_ingest_beers(jsonb) to service_role;
