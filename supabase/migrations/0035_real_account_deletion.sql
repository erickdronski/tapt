-- 0035_real_account_deletion.sql
--
-- App Store Guideline 5.1.1(v) + GDPR/CCPA: account deletion must actually delete.
-- Before, "delete my account" only inserted an account_deletion_request that nothing
-- processed. delete_my_account() hard-deletes the caller's entire PERSONAL plane and
-- their auth identity in one call. The AGGREGATE plane (aggregate_cell, already k-anon
-- and non-identifying) is intentionally retained per the two-plane consent design.
-- Verified: executes cleanly (all table/column refs + FK order valid).

create or replace function public.delete_my_account()
returns void language plpgsql security definer set search_path to 'public'
as $$
declare u uuid := auth.uid();
begin
  if u is null then raise exception 'not authenticated'; end if;

  delete from beer_vote            where user_id = u;
  delete from checkin_review       where user_id = u;
  delete from session_pour         where user_id = u;
  delete from session_participant  where user_id = u;
  delete from checkin_event        where user_id = u;
  delete from crew_member          where user_id = u;
  delete from taste_vector         where user_id = u;
  delete from featured_impression  where user_id = u;
  delete from newsletter_subscriber where user_id = u;
  delete from partner_inquiry      where user_id = u;
  delete from venue_claim          where user_id = u;
  delete from follow               where follower_id = u or followee_id = u;
  delete from user_block           where blocker_id = u or blocked_id = u;
  delete from content_report       where reporter_id = u;
  delete from consent_ledger       where user_id = u;
  delete from account_deletion_request where user_id = u;
  delete from app_admin            where user_id = u;
  delete from user_profile         where id = u;

  delete from auth.users where id = u;
exception when undefined_column or undefined_table then
  raise;  -- never leave a half-deleted account silently; surface the error
end; $$;

grant execute on function public.delete_my_account() to authenticated;
