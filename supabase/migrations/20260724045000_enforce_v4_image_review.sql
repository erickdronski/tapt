-- A cutout may enter human review only after the immutable v4 pipeline has
-- produced and hashed it. This prevents a legacy mutable v2/v3 candidate from
-- becoming reviewable again after the one-time cleanup migration.
alter table public.beer_media_processing
  drop constraint if exists beer_media_processing_pending_review_v4;
alter table public.beer_media_processing
  add constraint beer_media_processing_pending_review_v4
  check (
    status <> 'pending_review'
    or (pipeline_version is not null and pipeline_version = 'v4')
  );

notify pgrst, 'reload schema';
