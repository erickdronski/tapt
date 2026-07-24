-- Process newly licensed sources for otherwise imageless products before
-- spending the same compute budget re-cutting legacy catalog photos.
create or replace view public.cutout_queue
with (security_invoker = true)
as
select
  b.id,
  b.name,
  b.gtin,
  b.label_image_url,
  b.label_image_license,
  b.cutout_url,
  b.updated_at,
  s.standing as market_standing,
  0 as source_priority
from public.beer_catalog b
left join public.beer_market_standing s on s.beer_id = b.id
where nullif(btrim(b.label_image_url), '') is not null
  and not exists (
    select 1
    from public.beer_media_processing p
    where p.beer_id = b.id
      and p.status = 'rejected'
      and p.error_code in ('visual_quality_review', 'manual_quality_rejection')
  )
union all
select
  b.id,
  b.name,
  b.gtin,
  c.source_url,
  c.source_license,
  b.cutout_url,
  c.updated_at,
  s.standing as market_standing,
  1 as source_priority
from public.beer_media_source_candidate c
join public.beer_catalog b on b.id = c.beer_id
left join public.beer_market_standing s on s.beer_id = b.id
where c.status = 'pending_cutout'
  and nullif(btrim(b.label_image_url), '') is null
  and nullif(btrim(b.cutout_url), '') is null;

comment on view public.cutout_queue is
  'Service-only v3 queue; new imageless sources precede legacy reprocessing, then live market standing applies.';

revoke all privileges on table public.cutout_queue
  from public, anon, authenticated;
grant select on table public.cutout_queue to service_role;

notify pgrst, 'reload schema';
