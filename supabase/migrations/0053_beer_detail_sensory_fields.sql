-- 0053: beer_detail also returns the style sensory profile, flavor notes,
-- typical ingredients, and style history so every beer page has real depth.
drop function if exists public.beer_detail(uuid);
create function public.beer_detail(p_beer_id uuid)
returns table(id uuid, name text, style text, substyle text, abv numeric, ibu smallint,
  is_na_low boolean, gtin text, label_image_url text, label_image_license text, nutrition jsonb,
  data_source text, brewery_name text, brewery_country text, brewery_website text,
  style_family text, style_name text, style_description text, style_abv_min numeric,
  style_abv_max numeric, style_ibu_min smallint, style_ibu_max smallint, style_srm_min smallint,
  style_srm_max smallint, style_source_url text, ups integer, downs integer, checkin_count integer,
  avg_rating numeric, venues_in_country integer, awards jsonb,
  style_hoppiness smallint, style_bitterness smallint, style_sweetness smallint, style_body smallint,
  style_roast smallint, style_sourness smallint, style_fruitiness smallint,
  style_flavor_notes text, style_ingredients text, style_history text)
language sql stable security definer set search_path to 'public' as $function$
  select
    b.id,
    public.tapt_display_name(b.name) as name,
    coalesce(sr.style_name, nullif(btrim(b.style),'')) as style,
    b.substyle, b.abv, b.ibu, b.is_na_low, b.gtin,
    coalesce(b.cutout_url, b.label_image_url) as label_image_url,
    b.label_image_license,
    b.external_ids->'nutrition' as nutrition,
    b.external_ids->>'source' as data_source,
    br.name, br.country, br.website_url,
    sr.style_family, sr.style_name, sr.description,
    sr.abv_min, sr.abv_max, sr.ibu_min, sr.ibu_max,
    sr.color_min_srm, sr.color_max_srm, sr.source_url,
    coalesce((select count(*) filter (where bv.value = 1) from beer_vote bv where bv.beer_id = b.id), 0)::int,
    coalesce((select count(*) filter (where bv.value = -1) from beer_vote bv where bv.beer_id = b.id), 0)::int,
    coalesce((select count(*) from checkin_event ce where ce.beer_id = b.id), 0)::int,
    (select avg(ce.rating)::numeric(3,2) from checkin_event ce where ce.beer_id = b.id),
    coalesce((select count(*)::int from venue v where v.external_ids->>'country' = br.country), 0),
    coalesce((
      select jsonb_agg(jsonb_build_object(
        'award_body', a.award_body, 'year', a.year, 'category', a.category,
        'medal', a.medal, 'scope', a.scope, 'region', a.region,
        'source_url', a.source_url, 'note', a.note
      ) order by a.year desc nulls last, a.medal)
      from beer_award a where a.beer_id = b.id
    ), '[]'::jsonb),
    sr.hoppiness, sr.bitterness, sr.sweetness, sr.body, sr.roast, sr.sourness, sr.fruitiness,
    sr.flavor_notes, sr.typical_ingredients, sr.style_history
  from beer_catalog b
  left join brewery br on br.id = b.brewery_id
  left join beer_style_reference sr on sr.style_name = public.tapt_ref_style_name(b.style, b.name)
  where b.id = p_beer_id;
$function$;
grant execute on function public.beer_detail(uuid) to anon, authenticated;
