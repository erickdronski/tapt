-- 0083  Cellar read model: real imagery, resolved style, trusted country.
-- The Cellar is becoming a visual collection; my_checkins now carries the
-- beer's image (cutout preferred), the BJCP-resolved style (raw checkin
-- styles can be OFF retail categories), and the trusted origin country
-- (Passport stamps must never come from a scan-country false origin).
-- Signature and return shape unchanged; only the jsonb payload grows.

create or replace function public.my_checkins(
  p_limit integer default 250,
  p_before_ts timestamp with time zone default null,
  p_before_id uuid default null
)
returns table(id uuid, beer_id uuid, rating numeric, style text,
              event_ts timestamp with time zone, beer_catalog jsonb, venue jsonb)
language sql
stable security definer
set search_path to 'public'
as $$
  select
    ce.id,
    ce.beer_id,
    ce.rating,
    ce.style,
    ce.event_ts,
    case when b.id is null then null else jsonb_build_object(
      'name', coalesce(nullif(b.display_name, ''), b.name),
      'style_ref', b.style_ref,
      'image', coalesce(b.cutout_url, b.label_image_url),
      'brewery', case when br.id is null then null else jsonb_build_object(
        'name', br.name,
        'country', public.tapt_trusted_country(br.country, br.external_ids)
      ) end
    ) end,
    case when v.id is null then null else jsonb_build_object(
      'name', v.name,
      'external_ids', v.external_ids
    ) end
  from public.checkin_event ce
  left join public.beer_catalog b on b.id = ce.beer_id
  left join public.brewery br on br.id = b.brewery_id
  left join public.venue v on v.id = ce.venue_id
  where ce.user_id = auth.uid()
    and (
      p_before_ts is null
      or (p_before_id is not null and (ce.event_ts, ce.id) < (p_before_ts, p_before_id))
    )
  order by ce.event_ts desc, ce.id desc
  limit greatest(1, least(coalesce(p_limit, 250), 500));
$$;
