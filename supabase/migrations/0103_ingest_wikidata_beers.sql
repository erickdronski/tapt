-- Grow the catalog with notable global beers from Wikidata (CC0, free/legal).
-- Wikidata beers have no barcode, so admin_ingest_beers (GTIN-keyed) can't take
-- them. This dedups by the Wikidata QID and, failing that, by name+brewery so a
-- beer we already have from Open Food Facts is ENRICHED (QID + ABV backfilled),
-- never duplicated. name_ok/display_name are generated columns, so listability
-- and clean display names apply automatically. Data only: name, brewery, country,
-- ABV. No images (per-image Wikimedia licensing varies). Blank beats invented.
create or replace function public.admin_ingest_wikidata_beers(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  rec jsonb;
  v_qid text; v_name text; v_brand text; v_country text; v_abv numeric; v_na boolean;
  v_brewery_id uuid; v_existing uuid; v_new uuid;
  n_ins int := 0; n_enrich int := 0; n_skip int := 0;
begin
  for rec in select value from jsonb_array_elements(coalesce(p_payload, '[]'::jsonb)) as t(value)
  loop
    v_qid     := nullif(trim(coalesce(rec->>'qid', '')), '');
    v_name    := trim(coalesce(rec->>'name', ''));
    v_brand   := nullif(trim(coalesce(rec->>'brand', '')), '');
    v_country := nullif(trim(coalesce(rec->>'country', '')), '');
    v_abv     := case when (rec->>'abv') ~ '^[0-9]+(\.[0-9]+)?$' then (rec->>'abv')::numeric else null end;
    if v_abv is not null and (v_abv < 0 or v_abv > 70) then v_abv := null; end if;

    if v_qid is null or length(v_name) < 2 or length(v_name) > 160 then
      n_skip := n_skip + 1; continue;
    end if;
    v_na := v_abv is not null and v_abv <= 0.5;

    -- 1) already ingested from Wikidata: refresh ABV, don't duplicate
    select id into v_existing from beer_catalog where external_ids->>'wikidata_qid' = v_qid limit 1;
    if v_existing is not null then
      update beer_catalog set abv = coalesce(abv, v_abv), updated_at = now() where id = v_existing;
      n_enrich := n_enrich + 1; continue;
    end if;

    -- link/create the brewery by name
    v_brewery_id := null;
    if v_brand is not null then
      select id into v_brewery_id from brewery where lower(name) = lower(v_brand) limit 1;
      if v_brewery_id is null then
        insert into brewery(name, country, external_ids)
        values (v_brand, coalesce(v_country, 'Unknown'), jsonb_build_object('source', 'wikidata'))
        returning id into v_brewery_id;
      end if;
    end if;

    -- 2) already have this exact beer (same name + brewery) from another source: enrich in place
    if v_brewery_id is not null then
      select id into v_existing from beer_catalog
        where brewery_id = v_brewery_id and lower(name) = lower(v_name) limit 1;
    else
      select id into v_existing from beer_catalog
        where brewery_id is null and lower(name) = lower(v_name) limit 1;
    end if;
    if v_existing is not null then
      update beer_catalog set
        abv          = coalesce(abv, v_abv),
        external_ids = coalesce(external_ids, '{}'::jsonb) || jsonb_build_object('wikidata_qid', v_qid),
        updated_at   = now()
      where id = v_existing;
      n_enrich := n_enrich + 1; continue;
    end if;

    -- 3) genuinely new beer
    insert into beer_catalog(name, abv, is_na_low, brewery_id, external_ids)
    values (v_name, v_abv, v_na, v_brewery_id,
            jsonb_build_object('source', 'wikidata', 'wikidata_qid', v_qid))
    returning id into v_new;
    n_ins := n_ins + 1;
  end loop;

  return jsonb_build_object('inserted', n_ins, 'enriched', n_enrich, 'skipped', n_skip);
end
$function$;

-- Server-only: called with the service role during ingestion, never by clients.
revoke all on function public.admin_ingest_wikidata_beers(jsonb) from public;
revoke all on function public.admin_ingest_wikidata_beers(jsonb) from anon;
revoke all on function public.admin_ingest_wikidata_beers(jsonb) from authenticated;
