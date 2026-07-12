-- 0062  Scale hardening: RLS initplan fix + FK covering indexes.
--
-- 1) beer_note_own re-evaluated auth.uid() per ROW (Supabase lint
--    auth_rls_initplan). Wrap in a scalar subquery so it's evaluated once per
--    query. Same semantics, per-query instead of per-row cost.
alter policy beer_note_own on public.beer_note
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- 2) Covering indexes for every hot or cascade-relevant foreign key the linter
--    flagged. The user_id ones matter most: account deletion cascades scan
--    every referencing table, which table-scans without these at scale.
create index if not exists account_deletion_request_user_idx on public.account_deletion_request (user_id);
create index if not exists beer_award_source_idx on public.beer_award (source_id);
create index if not exists beer_catalog_sku_canonical_idx on public.beer_catalog (sku_canonical_id);
create index if not exists beer_note_beer_idx on public.beer_note (beer_id);
create index if not exists beer_of_week_winner_beer_idx on public.beer_of_week_winner (beer_id);
create index if not exists beer_style_reference_source_idx on public.beer_style_reference (source_id);
create index if not exists brewery_brand_ref_idx on public.brewery (brand_ref);
create index if not exists canonical_merge_queue_reviewed_by_idx on public.canonical_merge_queue (reviewed_by);
create index if not exists checkin_review_user_idx on public.checkin_review (user_id);
create index if not exists crew_owner_idx on public.crew (owner_id);
create index if not exists crew_member_user_idx on public.crew_member (user_id);
create index if not exists featured_partner_brewery_idx on public.featured_partner (brewery_id);
create index if not exists featured_partner_venue_idx on public.featured_partner (venue_id);
create index if not exists moderation_action_moderator_idx on public.moderation_action (moderator_id);
create index if not exists moderation_action_report_idx on public.moderation_action (report_id);
create index if not exists newsletter_subscriber_user_idx on public.newsletter_subscriber (user_id);
create index if not exists partner_inquiry_user_idx on public.partner_inquiry (user_id);
create index if not exists session_participant_user_idx on public.session_participant (user_id);
create index if not exists session_pour_beer_idx on public.session_pour (beer_id);
create index if not exists session_pour_checkin_idx on public.session_pour (checkin_id);
create index if not exists session_pour_user_idx on public.session_pour (user_id);
create index if not exists tasting_session_host_idx on public.tasting_session (host_id);
create index if not exists user_block_blocked_idx on public.user_block (blocked_id);
create index if not exists venue_claim_user_idx on public.venue_claim (user_id);
create index if not exists venue_event_created_by_idx on public.venue_event (created_by);
create index if not exists venue_tap_snapshot_captured_by_idx on public.venue_tap_snapshot (captured_by);
