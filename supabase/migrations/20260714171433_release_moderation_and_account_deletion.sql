-- Release trust/safety and account-deletion hardening.
-- Apple refresh tokens are encrypted with Supabase Vault and are only exposed
-- to service-role RPCs used by the authenticated Edge Functions.

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table if not exists private.apple_auth_token (
  user_id uuid primary key references auth.users(id) on delete cascade,
  vault_secret_id uuid not null unique references vault.secrets(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table private.apple_auth_token enable row level security;
revoke all on private.apple_auth_token from public, anon, authenticated;

create or replace function private.delete_apple_vault_secret()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from vault.secrets where id = old.vault_secret_id;
  return old;
end;
$$;
revoke all on function private.delete_apple_vault_secret() from public;

drop trigger if exists t_delete_apple_vault_secret on private.apple_auth_token;
create trigger t_delete_apple_vault_secret
after delete on private.apple_auth_token
for each row execute function private.delete_apple_vault_secret();

create or replace function public.store_apple_refresh_token(
  p_user uuid,
  p_token text
) returns void
language plpgsql
security definer
set search_path = public, vault, private
as $$
declare
  v_secret uuid;
  v_name text;
begin
  if p_user is null or nullif(btrim(p_token), '') is null then
    raise exception 'user and token required';
  end if;
  if not exists (select 1 from auth.users where id = p_user) then
    raise exception 'user not found';
  end if;

  v_name := 'tapt_apple_refresh_' || p_user::text;
  select vault_secret_id into v_secret
  from private.apple_auth_token
  where user_id = p_user;

  if v_secret is null then
    select vault.create_secret(
      p_token,
      v_name,
      'Sign in with Apple refresh token used only for account-deletion revocation'
    ) into v_secret;
    insert into private.apple_auth_token (user_id, vault_secret_id)
    values (p_user, v_secret);
  else
    perform vault.update_secret(
      v_secret,
      p_token,
      v_name,
      'Sign in with Apple refresh token used only for account-deletion revocation'
    );
    update private.apple_auth_token set updated_at = now() where user_id = p_user;
  end if;
end;
$$;

create or replace function public.get_apple_refresh_token(p_user uuid)
returns text
language sql
security definer
stable
set search_path = public, vault, private
as $$
  select ds.decrypted_secret
  from private.apple_auth_token t
  join vault.decrypted_secrets ds on ds.id = t.vault_secret_id
  where t.user_id = p_user;
$$;

create or replace function public.clear_apple_refresh_token(p_user uuid)
returns void
language sql
security definer
set search_path = public, private
as $$
  delete from private.apple_auth_token where user_id = p_user;
$$;

revoke all on function public.store_apple_refresh_token(uuid, text) from public, anon, authenticated;
revoke all on function public.get_apple_refresh_token(uuid) from public, anon, authenticated;
revoke all on function public.clear_apple_refresh_token(uuid) from public, anon, authenticated;
grant execute on function public.store_apple_refresh_token(uuid, text) to service_role;
grant execute on function public.get_apple_refresh_token(uuid) to service_role;
grant execute on function public.clear_apple_refresh_token(uuid) to service_role;

alter table public.user_profile
  add column if not exists pending_avatar_url text,
  add column if not exists avatar_moderation_status text not null default 'none';

alter table public.user_profile
  drop constraint if exists user_profile_avatar_moderation_status_check;
alter table public.user_profile
  add constraint user_profile_avatar_moderation_status_check
  check (avatar_moderation_status in ('none', 'pending', 'approved', 'rejected'));

create index if not exists user_profile_pending_avatar
on public.user_profile (updated_at desc)
where avatar_moderation_status = 'pending';

create or replace function public.profile_text_is_allowed(p_value text)
returns boolean
language sql
immutable
set search_path = public, pg_temp
as $$
  select regexp_replace(
    translate(lower(coalesce(p_value, '')), '013457@$', 'oieastas'),
    '[^a-z0-9]+', ' ', 'g'
  ) !~ '\m(fuck|fucker|fucking|shit|bullshit|bitch|cunt|nigger|nigga|faggot|retard|kike|spic|chink|whore|slut|rape|rapist|nazi|hitler|porn|xxx)\M';
$$;
revoke all on function public.profile_text_is_allowed(text) from public, anon, authenticated;

-- OAuth provider metadata must pass through the same public-profile safety
-- rules as in-app edits. Provider avatars are not auto-published; users can
-- upload a reviewable avatar from the profile screen instead.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text := nullif(btrim(new.raw_user_meta_data->>'full_name'), '');
begin
  if v_name is not null
     and (length(v_name) < 2 or length(v_name) > 40 or not public.profile_text_is_allowed(v_name)) then
    v_name := null;
  end if;
  insert into public.user_profile (id, display_name, avatar_url)
  values (new.id, v_name, null)
  on conflict (id) do nothing;
  return new;
end;
$$;
revoke all on function public.handle_new_user() from public, anon, authenticated;

update public.user_profile
set display_name = 'Tapt member', updated_at = now()
where display_name is not null and not public.profile_text_is_allowed(display_name);
update public.user_profile
set handle = null, updated_at = now()
where handle is not null and not public.profile_text_is_allowed(replace(handle, '_', ' '));

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
set search_path = public, storage
as $$
declare
  v_uid uuid := auth.uid();
  v_previous text;
  v_previous_path text;
begin
  if v_uid is null then raise exception 'auth required'; end if;
  if p_url is not null and p_url <> ''
     and p_url not like 'https://qfwiizvqxrhjlthbjosz.supabase.co/storage/v1/object/public/avatars/' || v_uid::text || '/%' then
    raise exception 'avatar_url_host' using errcode = '22023';
  end if;

  select pending_avatar_url into v_previous
  from public.user_profile where id = v_uid;
  if v_previous is not null and v_previous <> coalesce(p_url, '') then
    v_previous_path := split_part(split_part(v_previous, '/avatars/', 2), '?', 1);
    delete from storage.objects
    where bucket_id = 'avatars' and owner = v_uid and name = v_previous_path;
  end if;

  if nullif(p_url, '') is null then
    delete from storage.objects where bucket_id = 'avatars' and owner = v_uid;
    update public.user_profile
    set avatar_url = null,
        pending_avatar_url = null,
        avatar_moderation_status = 'none',
        updated_at = now()
    where id = v_uid;
  else
    update public.user_profile
    set pending_avatar_url = p_url,
        avatar_moderation_status = 'pending',
        updated_at = now()
    where id = v_uid;
  end if;
end;
$$;

revoke all on function public.set_profile_identity(text, text) from public, anon;
revoke all on function public.set_avatar_url(text) from public, anon;
grant execute on function public.set_profile_identity(text, text) to authenticated;
grant execute on function public.set_avatar_url(text) to authenticated;

create or replace function public.report_content(
  p_target_type text,
  p_target_id uuid,
  p_reason text,
  p_details text default null
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_id uuid;
  v_reason text := lower(btrim(coalesce(p_reason, '')));
  v_details text := nullif(left(btrim(coalesce(p_details, '')), 500), '');
begin
  if v_user is null then raise exception 'not authenticated'; end if;
  if p_target_type not in ('checkin', 'user') then
    raise exception 'unsupported report target' using errcode = '22023';
  end if;
  if v_reason not in ('in_app_report', 'spam', 'harassment', 'inappropriate', 'other') then
    raise exception 'unsupported report reason' using errcode = '22023';
  end if;
  if p_target_type = 'checkin'
     and not exists (select 1 from public.checkin_event where id = p_target_id) then
    raise exception 'report target not found' using errcode = '22023';
  end if;
  if p_target_type = 'user'
     and not exists (select 1 from public.user_profile where id = p_target_id) then
    raise exception 'report target not found' using errcode = '22023';
  end if;

  insert into public.content_report (reporter_id, target_type, target_id, reason, details)
  values (v_user, p_target_type, p_target_id, v_reason, v_details)
  on conflict (reporter_id, target_type, target_id, reason) do update
    set details = coalesce(excluded.details, content_report.details),
        status = 'open',
        updated_at = now()
  returning id into v_id;

  if p_target_type = 'checkin' then
    update public.checkin_event
    set moderation_status = 'under_review'
    where id = p_target_id and moderation_status = 'visible';
  end if;
  return v_id;
end;
$$;
revoke all on function public.report_content(text, uuid, text, text) from public, anon;
grant execute on function public.report_content(text, uuid, text, text) to authenticated;

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
    and p.avatar_moderation_status = 'pending'
    and p.pending_avatar_url is not null
  order by p.updated_at asc
  limit 200;
$$;

create or replace function public.moderate_avatar(p_user uuid, p_decision text)
returns void
language plpgsql
security definer
set search_path = public, storage
as $$
declare
  v_url text;
  v_path text;
begin
  if not public.is_admin() then raise exception 'admin only'; end if;
  if p_decision not in ('approve', 'reject') then raise exception 'bad decision'; end if;

  select pending_avatar_url into v_url
  from public.user_profile
  where id = p_user and avatar_moderation_status = 'pending'
  for update;
  if v_url is null then raise exception 'pending avatar not found'; end if;
  v_path := split_part(split_part(v_url, '/avatars/', 2), '?', 1);

  if p_decision = 'approve' then
    update public.user_profile
    set avatar_url = v_url,
        pending_avatar_url = null,
        avatar_moderation_status = 'approved',
        updated_at = now()
    where id = p_user;
    delete from storage.objects
    where bucket_id = 'avatars' and owner = p_user and name <> v_path;
  else
    delete from storage.objects
    where bucket_id = 'avatars' and owner = p_user and name = v_path;
    update public.user_profile
    set pending_avatar_url = null,
        avatar_moderation_status = 'rejected',
        updated_at = now()
    where id = p_user;
  end if;
end;
$$;

create or replace function public.admin_content_reports()
returns table (
  report_id uuid,
  target_type text,
  target_id uuid,
  target_label text,
  reason text,
  details text,
  status text,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    r.id,
    r.target_type,
    r.target_id,
    coalesce(
      case r.target_type
        when 'user' then (
          select coalesce(nullif(p.display_name, ''), nullif(p.handle, ''), p.id::text)
          from public.user_profile p where p.id = r.target_id
        )
        when 'checkin' then (
          select coalesce(b.name, c.id::text)
          from public.checkin_event c
          left join public.beer_catalog b on b.id = c.beer_id
          where c.id = r.target_id
        )
        when 'venue' then (select v.name from public.venue v where v.id = r.target_id)
        when 'beer' then (select b.name from public.beer_catalog b where b.id = r.target_id)
        else null
      end,
      r.target_id::text
    ),
    r.reason,
    r.details,
    r.status,
    r.created_at
  from public.content_report r
  where public.is_admin()
  order by (r.status in ('open', 'reviewing')) desc, r.created_at asc
  limit 200;
$$;

create or replace function public.moderate_content_report(
  p_report uuid,
  p_decision text,
  p_note text default null
) returns void
language plpgsql
security definer
set search_path = public, storage
as $$
declare
  v_report public.content_report%rowtype;
begin
  if not public.is_admin() then raise exception 'admin only'; end if;
  if p_decision not in ('remove', 'dismiss') then raise exception 'bad decision'; end if;

  select * into v_report
  from public.content_report
  where id = p_report
  for update;
  if v_report.id is null then raise exception 'report not found'; end if;

  if p_decision = 'remove' then
    if v_report.target_type = 'checkin' then
      update public.checkin_event
      set moderation_status = 'removed'
      where id = v_report.target_id;
    elsif v_report.target_type = 'user' then
      delete from storage.objects
      where bucket_id = 'avatars' and owner = v_report.target_id;
      update public.user_profile
      set display_name = 'Tapt member',
          handle = null,
          avatar_url = null,
          pending_avatar_url = null,
          avatar_moderation_status = 'rejected',
          social_visible = false,
          updated_at = now()
      where id = v_report.target_id;
    end if;
    update public.content_report set status = 'actioned', updated_at = now()
    where id = v_report.id;
    insert into public.moderation_action (
      report_id, moderator_id, target_type, target_id, action_type, note
    ) values (
      v_report.id, auth.uid(), v_report.target_type, v_report.target_id, 'remove', nullif(btrim(p_note), '')
    );
  else
    update public.content_report set status = 'dismissed', updated_at = now()
    where id = v_report.id;
    if v_report.target_type = 'checkin'
       and not exists (
         select 1 from public.content_report r
         where r.target_type = 'checkin'
           and r.target_id = v_report.target_id
           and r.id <> v_report.id
           and r.status in ('open', 'reviewing')
       ) then
      update public.checkin_event
      set moderation_status = 'visible'
      where id = v_report.target_id and moderation_status = 'under_review';
    end if;
    insert into public.moderation_action (
      report_id, moderator_id, target_type, target_id, action_type, note
    ) values (
      v_report.id, auth.uid(), v_report.target_type, v_report.target_id, 'dismiss', nullif(btrim(p_note), '')
    );
  end if;
end;
$$;

revoke all on function public.admin_pending_avatars() from public, anon;
revoke all on function public.moderate_avatar(uuid, text) from public, anon;
revoke all on function public.admin_content_reports() from public, anon;
revoke all on function public.moderate_content_report(uuid, text, text) from public, anon;
grant execute on function public.admin_pending_avatars() to authenticated;
grant execute on function public.moderate_avatar(uuid, text) to authenticated;
grant execute on function public.admin_content_reports() to authenticated;
grant execute on function public.moderate_content_report(uuid, text, text) to authenticated;

create or replace function public.admin_stats()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select case when public.is_admin() then jsonb_build_object(
    'users', (select count(*) from public.user_profile),
    'venues_total', (select count(*) from public.venue),
    'venues_claimed', (select count(*) from public.venue_claim where status = 'approved'),
    'claims_pending', (select count(*) from public.venue_claim where status = 'pending'),
    'menus_live', (select count(distinct venue_id) from public.venue_tap_snapshot where expires_at > now()),
    'beers', (select count(*) from public.beer_catalog),
    'pours', (select count(*) from public.checkin_event),
    'votes', (select count(*) from public.beer_vote),
    'subscribers', (select count(*) from public.newsletter_subscriber where status = 'subscribed'),
    'inquiries', (select count(*) from public.partner_inquiry),
    'inquiries_new', (select count(*) from public.partner_inquiry where status = 'new'),
    'partners_featured', (select count(*) from public.featured_partner where active),
    'reports_open', (select count(*) from public.content_report where status in ('open', 'reviewing')),
    'avatars_pending', (select count(*) from public.user_profile where avatar_moderation_status = 'pending')
  ) else null end;
$$;
revoke all on function public.admin_stats() from public, anon;
grant execute on function public.admin_stats() to authenticated;

create or replace function public.delete_account_data(p_user uuid)
returns void
language plpgsql
security definer
set search_path = public, private, storage
as $$
begin
  if p_user is null then raise exception 'user required'; end if;

  delete from private.apple_auth_token where user_id = p_user;
  delete from storage.objects
  where bucket_id = 'avatars' and (owner = p_user or owner_id = p_user::text);

  -- Platform-generated cutouts and approved partner branding remain valid content,
  -- but must no longer retain the deleted account as owner metadata.
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
