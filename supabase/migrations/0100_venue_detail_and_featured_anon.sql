-- Enriched venue detail for the map sheet: only real fields from venue + external_ids,
-- plus whether the venue is claimed. Anon-readable (the map tab is guest-visible).
create or replace function public.venue_detail(p_venue uuid)
returns table (
  name text, logo_url text, poi_category text, on_off_premise text,
  address text, city text, region text, country text, postal_code text,
  phone text, website_url text, source_note text, is_claimed boolean
)
language sql stable security definer set search_path to 'public'
as $function$
  select v.name, v.logo_url, v.poi_category, v.on_off_premise::text,
         v.external_ids->>'address',    v.external_ids->>'city',
         v.external_ids->>'region',     v.external_ids->>'country',
         v.external_ids->>'postal_code', v.external_ids->>'phone',
         v.external_ids->>'website_url', v.external_ids->>'source_note',
         exists(select 1 from public.venue_claim c
                where c.venue_id = v.id and c.status = 'approved')
  from public.venue v
  where v.id = p_venue;
$function$;

revoke all on function public.venue_detail(uuid) from public;
grant execute on function public.venue_detail(uuid) to anon, authenticated;

-- The map tab is guest-visible, so the featured strip + reach logging must be
-- readable by anon (they were authenticated-only, which 401'd for guests).
grant execute on function public.featured_partner_feed(integer, text) to anon;
grant execute on function public.log_featured_event(uuid, text, text)  to anon;
