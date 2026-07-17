-- Exclude manually review-rejected beers from cutout_queue so the factory can
-- never re-pick them (a source_url change would otherwise flip same_source and
-- force one reprocess, clearing a human's rejection). Rejection is now a stable
-- fixed point; re-open a beer by deleting its beer_media_processing row.
-- Mirrors prod 2026-07-17.
create or replace view public.cutout_queue as
  select b.id, b.name, b.label_image_url, b.label_image_license,
         b.cutout_url, b.updated_at, s.standing as market_standing
  from beer_catalog b
  left join beer_market_standing s on s.beer_id = b.id
  where b.label_image_url is not null and b.label_image_url <> ''
    and not exists (
      select 1 from beer_media_processing p
      where p.beer_id = b.id and p.status = 'rejected'
        and p.error_code in ('visual_quality_review', 'manual_quality_rejection')
    );
