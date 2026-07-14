-- Make the Wikidata ingest bulletproof per row. A single beer whose name makes a
-- generated column (tapt_name_ok / tapt_display_name) throw was aborting the whole
-- 500-row batch (surfaced as an opaque HTTP 500). Wrap each row in its own
-- savepoint so one bad row is skipped, never the batch.
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
    begin
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

      select id into v_existing from beer_catalog where external_ids->>'wikidata_qid' = v_qid limit 1;
      if v_existing is not null then
        update beer_catalog set abv = coalesce(abv, v_abv), updated_at = now() where id = v_existing;
        n_enrich := n_enrich + 1; continue;
      end if;

      v_brewery_id := null;
      if v_brand is not null then
        select id into v_brewery_id from brewery where lower(name) = lower(v_brand) limit 1;
        if v_brewery_id is null then
          insert into brewery(name, country, external_ids)
          values (v_brand, coalesce(v_country, 'Unknown'), jsonb_build_object('source', 'wikidata'))
          returning id into v_brewery_id;
        end if;
      end if;

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

      insert into beer_catalog(name, abv, is_na_low, brewery_id, external_ids)
      values (v_name, v_abv, v_na, v_brewery_id,
              jsonb_build_object('source', 'wikidata', 'wikidata_qid', v_qid))
      returning id into v_new;
      n_ins := n_ins + 1;
    exception when others then
      -- one unusual beer (e.g. a name that trips a generated column) must never
      -- take down the whole batch. Skip it and keep going.
      n_skip := n_skip + 1;
    end;
  end loop;

  return jsonb_build_object('inserted', n_ins, 'enriched', n_enrich, 'skipped', n_skip);
end
$function$;

revoke all on function public.admin_ingest_wikidata_beers(jsonb) from public;
revoke all on function public.admin_ingest_wikidata_beers(jsonb) from anon;
revoke all on function public.admin_ingest_wikidata_beers(jsonb) from authenticated;
