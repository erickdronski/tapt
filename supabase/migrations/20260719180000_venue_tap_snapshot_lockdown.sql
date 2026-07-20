-- Audit fix (authorization): any signed-in user could permanently blank any
-- venue's live QR menu.
--
-- 0006:608 granted `select, insert on venue_tap_snapshot to authenticated`, and
-- the only row guard (policy venue_tap_snapshot_owner_insert) checks WHO wrote
-- the row (captured_by = auth.uid()) and never WHICH venue. venue_id,
-- observed_at and expires_at are all attacker-controlled. venue_menu() serves
-- only the single newest non-expired snapshot and INNER JOINs venue_tap_item,
-- so inserting one EMPTY snapshot for someone else's venue yields zero menu
-- rows -- a partner's live menu goes blank until that snapshot expires. INSERT
-- on venue_tap_item was already revoked (0054), which is exactly why the empty
-- snapshot is the attack: the attacker never needs to add items.
--
-- Writes belong to publish_tap_list(), which already requires an approved
-- venue_claim. Revoking the direct INSERT closes the hole without touching the
-- legitimate partner path. SELECT is left intact: reads go through the
-- SECURITY DEFINER venue_menu() and nothing here is sensitive.
revoke insert on public.venue_tap_snapshot from authenticated;

-- The owner-insert policy is now unreachable for clients (no INSERT grant) but
-- would silently re-open the hole if the grant ever came back. Replace it with
-- one that also proves the writer owns an approved claim on that venue.
drop policy if exists venue_tap_snapshot_owner_insert on public.venue_tap_snapshot;
create policy venue_tap_snapshot_owner_insert on public.venue_tap_snapshot
  for insert with check (
    (select auth.uid()) = captured_by
    and exists (
      select 1 from public.venue_claim vc
      where vc.venue_id = venue_tap_snapshot.venue_id
        and vc.user_id = (select auth.uid())
        and vc.status = 'approved'
    )
  );
