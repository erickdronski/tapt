-- Keep interrupted avatar reviews visible and retryable, and remove report
-- identifiers tied to a deleted account before its social rows disappear.

create or replace function public.admin_pending_avatars()
returns table (
  user_id uuid,
  display_name text,
  handle text,
  pending_avatar_url text,
  submitted_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select p.id, p.display_name, p.handle, p.pending_avatar_url, p.updated_at
  from public.user_profile p
  where public.is_admin()
    and p.avatar_moderation_status in ('pending', 'processing')
    and p.pending_avatar_url is not null
  order by (p.avatar_moderation_status = 'processing') desc, p.updated_at asc
  limit 200;
$$;

create or replace function public.delete_account_data(p_user uuid)
returns void
language plpgsql
security definer
set search_path = public, private, storage
as $$
begin
  if p_user is null then raise exception 'user required'; end if;

  delete from private.apple_auth_token where user_id = p_user;

  -- Platform-generated cutouts and approved partner branding remain valid
  -- catalog content, but no longer retain the deleted account as owner metadata.
  update storage.objects
  set owner = null, owner_id = null
  where (owner = p_user or owner_id = p_user::text)
    and bucket_id in ('beer-cutouts', 'partner-assets');

  delete from public.beer_note where user_id = p_user;
  delete from public.beer_vote where user_id = p_user;
  delete from public.checkin_review where user_id = p_user;
  delete from public.session_pour where user_id = p_user;
  delete from public.session_participant where user_id = p_user;

  -- Reports have polymorphic targets, so their target UUIDs are not protected by
  -- foreign keys. Remove those identifiers while the user's check-ins still exist.
  delete from public.moderation_action
  where (target_type = 'user' and target_id = p_user)
     or (target_type = 'checkin' and target_id in (
       select id from public.checkin_event where user_id = p_user
     ));
  delete from public.content_report
  where reporter_id = p_user
     or (target_type = 'user' and target_id = p_user)
     or (target_type = 'checkin' and target_id in (
       select id from public.checkin_event where user_id = p_user
     ));

  delete from public.checkin_event where user_id = p_user;
  delete from public.crew_member where user_id = p_user;
  delete from public.taste_vector where user_id = p_user;
  delete from public.featured_impression where user_id = p_user;
  delete from public.newsletter_subscriber where user_id = p_user;
  delete from public.partner_inquiry where user_id = p_user;
  delete from public.venue_claim where user_id = p_user;
  delete from public.follow where follower_id = p_user or followee_id = p_user;
  delete from public.user_block where blocker_id = p_user or blocked_id = p_user;
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

revoke all on function public.delete_account_data(uuid) from public, anon, authenticated;
grant execute on function public.delete_account_data(uuid) to service_role;

notify pgrst, 'reload schema';
