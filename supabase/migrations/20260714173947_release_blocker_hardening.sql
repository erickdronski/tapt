-- Corrective release hardening. Storage objects are removed by authenticated
-- Edge Functions through the Storage API; SQL only updates application state.

create extension if not exists unaccent with schema extensions;

alter table public.user_profile
  add column if not exists account_moderation_status text not null default 'active',
  add column if not exists avatar_moderation_decision text,
  add column if not exists avatar_moderator_id uuid references public.user_profile(id) on delete set null;

alter table public.user_profile
  drop constraint if exists user_profile_account_moderation_status_check;
alter table public.user_profile
  add constraint user_profile_account_moderation_status_check
  check (account_moderation_status in ('active', 'suspending', 'suspended'));

alter table public.user_profile
  drop constraint if exists user_profile_avatar_moderation_status_check;
alter table public.user_profile
  add constraint user_profile_avatar_moderation_status_check
  check (avatar_moderation_status in ('none', 'pending', 'processing', 'approved', 'rejected'));

alter table public.user_profile
  drop constraint if exists user_profile_avatar_moderation_decision_check;
alter table public.user_profile
  add constraint user_profile_avatar_moderation_decision_check
  check (avatar_moderation_decision is null or avatar_moderation_decision in ('approve', 'reject'));

alter table public.content_report
  add column if not exists claimed_decision text,
  add column if not exists claimed_by uuid references public.user_profile(id) on delete set null;

alter table public.content_report
  drop constraint if exists content_report_claimed_decision_check;
alter table public.content_report
  add constraint content_report_claimed_decision_check
  check (claimed_decision is null or claimed_decision in ('remove', 'dismiss'));

-- Versioned public-profile text normalization. It strips separators, common
-- leetspeak, accents, repeated letters, and common Greek/Cyrillic homoglyphs.
create or replace function public.profile_text_is_allowed(p_value text)
returns boolean
language plpgsql
stable
set search_path = pg_catalog, extensions
as $$
declare
  v_value text;
  v_tokens text;
  v_compact text;
  v_squashed text;
  v_terms constant text :=
    '(fuck|fucker|fucking|shit|bullshit|bitch|cunt|nigger|nigga|faggot|retard|kike|spic|chink|whore|slut|rape|rapist|nazi|hitler|porn|xxx)';
begin
  v_value := extensions.unaccent(lower(coalesce(p_value, '')));
  v_value := translate(v_value, '013457@$', 'oieastas');
  v_value := translate(
    v_value,
    U&'\0430\0435\043E\0440\0441\0445\0443\0456\043A\043C\0442\0432\03B1\03B5\03BF\03C1\03C7\03C5\03B9\03BA\03BC\03C4\03B2',
    'aeopcxyikmtbaeopxyikmtb'
  );
  v_tokens := regexp_replace(v_value, '[^a-z0-9]+', ' ', 'g');
  v_compact := regexp_replace(v_value, '[^a-z0-9]+', '', 'g');
  v_squashed := regexp_replace(v_compact, '(.)\1+', '\1', 'g');
  return v_tokens !~ ('\m' || v_terms || '\M')
    and v_compact !~ v_terms
    and v_squashed !~ v_terms;
end;
$$;
revoke all on function public.profile_text_is_allowed(text) from public, anon, authenticated;

-- Direct table updates cannot bypass the reviewed identity/avatar/social RPCs
-- or alter server-owned moderation state.
create or replace function private.guard_user_profile_client_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_user in ('anon', 'authenticated') and not public.is_admin() then
    new.display_name := old.display_name;
    new.handle := old.handle;
    new.avatar_url := old.avatar_url;
    new.pending_avatar_url := old.pending_avatar_url;
    new.avatar_moderation_status := old.avatar_moderation_status;
    new.avatar_moderation_decision := old.avatar_moderation_decision;
    new.avatar_moderator_id := old.avatar_moderator_id;
    new.account_moderation_status := old.account_moderation_status;
    new.social_visible := old.social_visible;
  end if;
  return new;
end;
$$;
revoke all on function private.guard_user_profile_client_update() from public;

drop trigger if exists t_guard_user_profile_client_update on public.user_profile;
create trigger t_guard_user_profile_client_update
before update on public.user_profile
for each row execute function private.guard_user_profile_client_update();

-- Any user-authored social write must still belong to an active profile. The
-- auth subject survives inside SECURITY DEFINER RPCs, so this also protects
-- log_checkin and follow_user without trusting client behavior.
create or replace function private.enforce_active_profile_write()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if auth.uid() is not null and not exists (
    select 1 from public.user_profile p
    where p.id = auth.uid() and p.account_moderation_status = 'active'
  ) then
    raise exception 'account_suspended' using errcode = '42501';
  end if;
  return new;
end;
$$;
revoke all on function private.enforce_active_profile_write() from public;

drop trigger if exists t_active_profile_checkin_write on public.checkin_event;
create trigger t_active_profile_checkin_write
before insert or update on public.checkin_event
for each row execute function private.enforce_active_profile_write();

drop trigger if exists t_active_profile_review_write on public.checkin_review;
create trigger t_active_profile_review_write
before insert or update on public.checkin_review
for each row execute function private.enforce_active_profile_write();

drop trigger if exists t_active_profile_vote_write on public.beer_vote;
create trigger t_active_profile_vote_write
before insert or update on public.beer_vote
for each row execute function private.enforce_active_profile_write();

drop trigger if exists t_active_profile_follow_write on public.follow;
create trigger t_active_profile_follow_write
before insert or update on public.follow
for each row execute function private.enforce_active_profile_write();

drop policy if exists "avatar owner insert" on storage.objects;
create policy "avatar owner insert" on storage.objects
for insert to authenticated
with check (
  bucket_id = 'avatars'
  and owner = (select auth.uid())
  and name like (select auth.uid())::text || '/%'
  and exists (
    select 1 from public.user_profile p
    where p.id = (select auth.uid()) and p.account_moderation_status = 'active'
  )
);

drop policy if exists "avatar owner update" on storage.objects;
create policy "avatar owner update" on storage.objects
for update to authenticated
using (bucket_id = 'avatars' and owner = (select auth.uid()))
with check (
  bucket_id = 'avatars'
  and owner = (select auth.uid())
  and name like (select auth.uid())::text || '/%'
  and exists (
    select 1 from public.user_profile p
    where p.id = (select auth.uid()) and p.account_moderation_status = 'active'
  )
);

create or replace function public.set_profile_identity(
  p_display_name text default null,
  p_handle text default null
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_name text;
  v_handle text;
begin
  if v_uid is null then raise exception 'auth required'; end if;
  if not exists (
    select 1 from public.user_profile
    where id = v_uid and account_moderation_status = 'active'
  ) then raise exception 'account_suspended' using errcode = '42501'; end if;

  if p_display_name is not null then
    v_name := btrim(p_display_name);
    if length(v_name) < 2 or length(v_name) > 40 then
      raise exception 'display_name_length' using errcode = '22023';
    end if;
    if not public.profile_text_is_allowed(v_name) then
      raise exception 'display_name_not_allowed' using errcode = '22023';
    end if;
    update public.user_profile set display_name = v_name, updated_at = now() where id = v_uid;
  end if;

  if p_handle is not null then
    v_handle := lower(btrim(p_handle));
    if v_handle = '' then
      update public.user_profile set handle = null, updated_at = now() where id = v_uid;
    else
      if v_handle !~ '^[a-z0-9_]{3,20}$' then
        raise exception 'handle_format' using errcode = '22023';
      end if;
      if not public.profile_text_is_allowed(replace(v_handle, '_', ' ')) then
        raise exception 'handle_not_allowed' using errcode = '22023';
      end if;
      if exists (select 1 from public.user_profile where handle = v_handle and id <> v_uid) then
        raise exception 'handle_taken' using errcode = '23505';
      end if;
      update public.user_profile set handle = v_handle, updated_at = now() where id = v_uid;
    end if;
  end if;
end;
$$;

create or replace function public.set_avatar_url(p_url text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'auth required'; end if;
  if not exists (
    select 1 from public.user_profile
    where id = v_uid
      and account_moderation_status = 'active'
      and avatar_moderation_status <> 'processing'
  ) then raise exception 'avatar_update_unavailable' using errcode = '42501'; end if;
  if nullif(p_url, '') is null then
    raise exception 'avatar_removal_requires_storage_api' using errcode = '22023';
  end if;
  if p_url not like 'https://qfwiizvqxrhjlthbjosz.supabase.co/storage/v1/object/public/avatars/' || v_uid::text || '/%' then
    raise exception 'avatar_url_host' using errcode = '22023';
  end if;
  update public.user_profile
  set pending_avatar_url = p_url,
      avatar_moderation_status = 'pending',
      avatar_moderation_decision = null,
      avatar_moderator_id = null,
      updated_at = now()
  where id = v_uid;
end;
$$;

create or replace function public.set_social_visibility(p_visible boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if not exists (
    select 1 from public.user_profile
    where id = auth.uid() and account_moderation_status = 'active'
  ) then raise exception 'account_suspended' using errcode = '42501'; end if;
  update public.user_profile
  set social_visible = coalesce(p_visible, false), updated_at = now()
  where id = auth.uid();
end;
$$;

revoke all on function public.set_profile_identity(text, text) from public, anon;
revoke all on function public.set_avatar_url(text) from public, anon;
revoke all on function public.set_social_visibility(boolean) from public, anon;
grant execute on function public.set_profile_identity(text, text) to authenticated;
grant execute on function public.set_avatar_url(text) to authenticated;
grant execute on function public.set_social_visibility(boolean) to authenticated;

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
  order by p.updated_at asc
  limit 200;
$$;

create or replace function public.claim_avatar_moderation(
  p_user uuid,
  p_decision text,
  p_moderator uuid
) returns table (previous_avatar_url text, pending_avatar_url text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.user_profile%rowtype;
begin
  if p_decision not in ('approve', 'reject') then raise exception 'bad decision'; end if;
  if not exists (select 1 from public.app_admin where user_id = p_moderator) then
    raise exception 'admin only';
  end if;
  select * into v_profile from public.user_profile where id = p_user for update;
  if v_profile.id is null or v_profile.pending_avatar_url is null then
    raise exception 'pending avatar not found';
  end if;
  if v_profile.avatar_moderation_status = 'processing'
     and v_profile.avatar_moderation_decision <> p_decision then
    raise exception 'avatar is processing a different decision';
  end if;
  if v_profile.avatar_moderation_status not in ('pending', 'processing') then
    raise exception 'pending avatar not found';
  end if;
  update public.user_profile
  set avatar_moderation_status = 'processing',
      avatar_moderation_decision = p_decision,
      avatar_moderator_id = p_moderator
  where id = p_user;
  return query select v_profile.avatar_url, v_profile.pending_avatar_url;
end;
$$;

create or replace function public.finish_avatar_moderation(
  p_user uuid,
  p_decision text,
  p_expected_url text,
  p_moderator uuid
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from public.app_admin where user_id = p_moderator) then
    raise exception 'admin only';
  end if;
  if p_decision = 'approve' then
    update public.user_profile
    set avatar_url = pending_avatar_url,
        pending_avatar_url = null,
        avatar_moderation_status = 'approved',
        avatar_moderation_decision = null,
        avatar_moderator_id = null,
        updated_at = now()
    where id = p_user
      and avatar_moderation_status = 'processing'
      and avatar_moderation_decision = p_decision
      and pending_avatar_url = p_expected_url;
  elsif p_decision = 'reject' then
    update public.user_profile
    set pending_avatar_url = null,
        avatar_moderation_status = 'rejected',
        avatar_moderation_decision = null,
        avatar_moderator_id = null,
        updated_at = now()
    where id = p_user
      and avatar_moderation_status = 'processing'
      and avatar_moderation_decision = p_decision
      and pending_avatar_url = p_expected_url;
  else
    raise exception 'bad decision';
  end if;
  if not found then raise exception 'avatar moderation state changed'; end if;
end;
$$;

create or replace function public.release_avatar_moderation(
  p_user uuid,
  p_expected_url text
) returns void
language sql
security definer
set search_path = public
as $$
  update public.user_profile
  set avatar_moderation_status = 'pending',
      avatar_moderation_decision = null,
      avatar_moderator_id = null
  where id = p_user
    and avatar_moderation_status = 'processing'
    and pending_avatar_url = p_expected_url;
$$;

revoke all on function public.claim_avatar_moderation(uuid, text, uuid) from public, anon, authenticated;
revoke all on function public.finish_avatar_moderation(uuid, text, text, uuid) from public, anon, authenticated;
revoke all on function public.release_avatar_moderation(uuid, text) from public, anon, authenticated;
grant execute on function public.claim_avatar_moderation(uuid, text, uuid) to service_role;
grant execute on function public.finish_avatar_moderation(uuid, text, text, uuid) to service_role;
grant execute on function public.release_avatar_moderation(uuid, text) to service_role;

drop function if exists public.moderate_avatar(uuid, text);

create or replace function public.claim_content_moderation(
  p_report uuid,
  p_decision text,
  p_moderator uuid
) returns table (target_type text, target_id uuid)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_report public.content_report%rowtype;
begin
  if p_decision not in ('remove', 'dismiss') then raise exception 'bad decision'; end if;
  if not exists (select 1 from public.app_admin where user_id = p_moderator) then
    raise exception 'admin only';
  end if;
  select * into v_report from public.content_report where id = p_report for update;
  if v_report.id is null or v_report.status not in ('open', 'reviewing') then
    raise exception 'report is unavailable';
  end if;
  if v_report.status = 'reviewing' and v_report.claimed_decision <> p_decision then
    raise exception 'report is processing a different decision';
  end if;
  if p_decision = 'remove' and v_report.target_type not in ('checkin', 'user') then
    raise exception 'unsupported report target';
  end if;
  if p_decision = 'remove' and v_report.target_type = 'checkin'
     and not exists (select 1 from public.checkin_event where id = v_report.target_id) then
    raise exception 'report target not found';
  end if;
  if p_decision = 'remove' and v_report.target_type = 'user'
     and not exists (select 1 from public.user_profile where id = v_report.target_id) then
    raise exception 'report target not found';
  end if;
  update public.content_report
  set status = 'reviewing', claimed_decision = p_decision, claimed_by = p_moderator
  where id = p_report;
  if p_decision = 'remove' and v_report.target_type = 'user' then
    update public.user_profile
    set account_moderation_status = 'suspending', social_visible = false
    where id = v_report.target_id and account_moderation_status in ('active', 'suspending');
  end if;
  return query select v_report.target_type, v_report.target_id;
end;
$$;

create or replace function public.finish_content_moderation(
  p_report uuid,
  p_decision text,
  p_note text,
  p_moderator uuid
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_report public.content_report%rowtype;
begin
  if p_decision not in ('remove', 'dismiss') then raise exception 'bad decision'; end if;
  if not exists (select 1 from public.app_admin where user_id = p_moderator) then
    raise exception 'admin only';
  end if;
  select * into v_report from public.content_report where id = p_report for update;
  if v_report.id is null or v_report.status <> 'reviewing'
     or v_report.claimed_decision <> p_decision then
    raise exception 'report moderation state changed';
  end if;

  if p_decision = 'remove' then
    if v_report.target_type = 'checkin' then
      update public.checkin_event set moderation_status = 'removed'
      where id = v_report.target_id;
    elsif v_report.target_type = 'user' then
      update public.checkin_event set moderation_status = 'removed'
      where user_id = v_report.target_id;
      delete from public.follow
      where follower_id = v_report.target_id or followee_id = v_report.target_id;
      update public.user_profile
      set display_name = 'Tapt member',
          handle = null,
          avatar_url = null,
          pending_avatar_url = null,
          avatar_moderation_status = 'rejected',
          avatar_moderation_decision = null,
          avatar_moderator_id = null,
          account_moderation_status = 'suspended',
          social_visible = false,
          updated_at = now()
      where id = v_report.target_id;
    else
      raise exception 'unsupported report target';
    end if;
    update public.content_report
    set status = 'actioned', claimed_decision = null, claimed_by = null, updated_at = now()
    where id = v_report.id;
  else
    update public.content_report
    set status = 'dismissed', claimed_decision = null, claimed_by = null, updated_at = now()
    where id = v_report.id;
    if v_report.target_type = 'checkin'
       and not exists (
         select 1 from public.content_report r
         where r.target_type = 'checkin'
           and r.target_id = v_report.target_id
           and r.id <> v_report.id
           and r.status in ('open', 'reviewing')
       ) then
      update public.checkin_event set moderation_status = 'visible'
      where id = v_report.target_id and moderation_status = 'under_review';
    end if;
  end if;

  insert into public.moderation_action (
    report_id, moderator_id, target_type, target_id, action_type, note
  ) values (
    v_report.id,
    p_moderator,
    v_report.target_type,
    v_report.target_id,
    p_decision,
    nullif(left(btrim(coalesce(p_note, '')), 500), '')
  );
end;
$$;

create or replace function public.release_content_moderation(
  p_report uuid,
  p_moderator uuid
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_report public.content_report%rowtype;
begin
  if not exists (select 1 from public.app_admin where user_id = p_moderator) then
    raise exception 'admin only';
  end if;
  select * into v_report from public.content_report where id = p_report for update;
  if v_report.id is null or v_report.status <> 'reviewing' then return; end if;
  if v_report.claimed_decision = 'remove' and v_report.target_type = 'user' then
    update public.user_profile set account_moderation_status = 'active'
    where id = v_report.target_id and account_moderation_status = 'suspending';
  end if;
  update public.content_report
  set status = 'open', claimed_decision = null, claimed_by = null, updated_at = now()
  where id = p_report;
end;
$$;

revoke all on function public.claim_content_moderation(uuid, text, uuid) from public, anon, authenticated;
revoke all on function public.finish_content_moderation(uuid, text, text, uuid) from public, anon, authenticated;
revoke all on function public.release_content_moderation(uuid, uuid) from public, anon, authenticated;
grant execute on function public.claim_content_moderation(uuid, text, uuid) to service_role;
grant execute on function public.finish_content_moderation(uuid, text, text, uuid) to service_role;
grant execute on function public.release_content_moderation(uuid, uuid) to service_role;

drop function if exists public.moderate_content_report(uuid, text, text);

-- All account deletion must traverse the Edge Function so Apple revocation and
-- physical Storage API cleanup happen before database/auth deletion.
drop function if exists public.delete_my_account();

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
revoke all on function public.delete_account_data(uuid) from public, anon, authenticated;
grant execute on function public.delete_account_data(uuid) to service_role;

notify pgrst, 'reload schema';
