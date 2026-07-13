-- 0097  Profile identity write-paths: display name, unique handle, avatar URL.
-- Backend (avatars bucket + user_profile.display_name/handle/avatar_url +
-- public_profile read RPC) already existed; these are the missing authed
-- writes. Server-side validation so a client can't bypass it. Real values only.
create or replace function public.set_profile_identity(
  p_display_name text default null,
  p_handle text default null
) returns void
language plpgsql security definer set search_path to 'public' as $$
declare
  v_uid uuid := auth.uid();
  v_name text; v_handle text;
begin
  if v_uid is null then raise exception 'auth required'; end if;
  if p_display_name is not null then
    v_name := btrim(p_display_name);
    if length(v_name) < 2 or length(v_name) > 40 then
      raise exception 'display_name_length' using errcode = '22023';
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
      if exists (select 1 from public.user_profile where handle = v_handle and id <> v_uid) then
        raise exception 'handle_taken' using errcode = '23505';
      end if;
      update public.user_profile set handle = v_handle, updated_at = now() where id = v_uid;
    end if;
  end if;
end $$;

create or replace function public.set_avatar_url(p_url text default null)
returns void language plpgsql security definer set search_path to 'public' as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'auth required'; end if;
  if p_url is not null and p_url <> ''
     and p_url not like 'https://qfwiizvqxrhjlthbjosz.supabase.co/storage/v1/object/public/avatars/%' then
    raise exception 'avatar_url_host' using errcode = '22023';
  end if;
  update public.user_profile set avatar_url = nullif(p_url, ''), updated_at = now() where id = v_uid;
end $$;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='avatar owner delete') then
    create policy "avatar owner delete" on storage.objects
      for delete to authenticated
      using (bucket_id = 'avatars' and owner = (select auth.uid()));
  end if;
end $$;

revoke all on function public.set_profile_identity(text, text) from public;
revoke all on function public.set_avatar_url(text) from public;
grant execute on function public.set_profile_identity(text, text) to authenticated;
grant execute on function public.set_avatar_url(text) to authenticated;
