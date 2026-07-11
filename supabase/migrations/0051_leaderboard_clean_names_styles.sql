-- 0051: the Home leaderboard shows clean display names, resolved BJCP styles
-- (no more 'Pale Ales'/'Craft Beers'/'Sodas'), cutout images, and hides junk names.
create or replace function public.leaderboard_beers(p_limit integer DEFAULT 20, p_na_only boolean DEFAULT false)
returns table(beer_id uuid, name text, style text, brewery_name text, country text,
              net_votes integer, ups integer, downs integer, checkin_count integer,
              avg_rating numeric, image_url text)
language sql stable security definer set search_path to 'public' as $function$
  select b.id,
         public.tapt_display_name(b.name),
         coalesce(sr.style_name, nullif(btrim(b.style),'')),
         br.name, br.country,
         s.net, s.ups, s.downs, s.checkins, s.avg_rating,
         coalesce(b.cutout_url, b.label_image_url)
  from beer_score s
  join beer_catalog b on b.id = s.beer_id
  left join brewery br on br.id = b.brewery_id
  left join beer_style_reference sr on sr.style_name = public.tapt_ref_style_name(b.style, b.name)
  where (s.net <> 0 or s.checkins > 0)
    and public.tapt_name_ok(b.name)
    and (not p_na_only or b.is_na_low)
  order by (s.net + s.checkins * 2) desc, b.name
  limit least(greatest(coalesce(p_limit, 20), 1), 50);
$function$;

-- Link orphan 'Holsten' beer to the real Holsten brewery (Hamburg, Germany) so it
-- gets a country + flag instead of showing as a "Community pick" with no origin.
update beer_catalog set brewery_id='31120562-6074-4e74-87f8-09bbbba85f6e', updated_at=now()
where id='7f352ecc-22f7-4dcf-be95-62a69b937df7' and brewery_id is null;
