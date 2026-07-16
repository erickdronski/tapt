-- Cutout pipeline candidates with a real priority: current market standing
-- first, then the long tail oldest-first. Mirrors prod 2026-07-16.
create or replace view public.cutout_queue as
select b.id, b.name, b.label_image_url, b.label_image_license, b.updated_at,
       s.standing as market_standing
from public.beer_catalog b
left join public.beer_market_standing s on s.beer_id = b.id
where b.label_image_url is not null and b.label_image_url <> '';

comment on view public.cutout_queue is
  'Cutout pipeline candidates; order by market_standing.desc.nullslast,updated_at.asc';

grant select on public.cutout_queue to anon, authenticated, service_role;
