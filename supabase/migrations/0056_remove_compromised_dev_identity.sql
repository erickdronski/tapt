-- 0056_remove_compromised_dev_identity.sql
-- Centralize account cleanup for user-initiated and service-initiated deletion,
-- then remove the simulator account whose old password entered git history.

create or replace function public.delete_account_data(p_user uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_user is null then raise exception 'user required'; end if;

  -- Platform-generated cutouts and approved partner branding remain valid content,
  -- but must no longer retain the deleted account as owner metadata.
  update storage.objects
  set owner = null, owner_id = null
  where owner = p_user and bucket_id in ('beer-cutouts', 'partner-assets');

  delete from public.beer_note where user_id = p_user;
  delete from public.beer_vote where user_id = p_user;
  delete from public.checkin_review where user_id = p_user;
  delete from public.session_pour where user_id = p_user;
  delete from public.session_participant where user_id = p_user;
  delete from public.checkin_event where user_id = p_user;
  delete from public.crew_member where user_id = p_user;
  delete from public.taste_vector where user_id = p_user;
  delete from public.featured_impression where user_id = p_user;
  delete from public.newsletter_subscriber where user_id = p_user;
  delete from public.partner_inquiry where user_id = p_user;
  delete from public.venue_claim where user_id = p_user;
  delete from public.follow where follower_id = p_user or followee_id = p_user;
  delete from public.user_block where blocker_id = p_user or blocked_id = p_user;
  delete from public.content_report where reporter_id = p_user;
  delete from public.consent_ledger where user_id = p_user;
  delete from public.account_deletion_request where user_id = p_user;
  delete from public.app_admin where user_id = p_user;

  update public.beer_catalog
  set external_ids = external_ids - 'added_by'
  where external_ids->>'added_by' = p_user::text;
  update public.brewery
  set external_ids = external_ids - 'added_by'
  where external_ids->>'added_by' = p_user::text;

  delete from public.user_profile where id = p_user;
  delete from auth.users where id = p_user;
end;
$$;
revoke all on function public.delete_account_data(uuid)
  from public, anon, authenticated;
grant execute on function public.delete_account_data(uuid) to service_role;

create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare u uuid := auth.uid();
begin
  if u is null then raise exception 'not authenticated'; end if;
  perform public.delete_account_data(u);
end;
$$;
revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;

do $$
declare compromised_user uuid;
begin
  select id into compromised_user
  from auth.users
  where email = 'dev@tapt.app'
  limit 1;

  if compromised_user is not null then
    perform public.delete_account_data(compromised_user);
  end if;
end;
$$;

notify pgrst, 'reload schema';
