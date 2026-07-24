-- Mutable v2/v3 candidate URLs cannot satisfy the v4 approval contract.
-- Preserve their source provenance, but require an immutable v4 rebuild before
-- they can return to the human review queue.
update public.beer_media_processing
set status = 'retry',
    candidate_cutout_url = null,
    error_code = 'v4_rebuild_required',
    rejection_reason = null,
    review_notes = 'Legacy candidate requires immutable v4 rebuild before review',
    updated_at = now()
where status = 'pending_review'
  and pipeline_version in ('v2', 'v3');

notify pgrst, 'reload schema';
