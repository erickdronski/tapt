-- 0070_partner_asset_hardening.sql
-- Scope partner uploads to approved venue owners and keep executable SVG out
-- of the public logo bucket.

create or replace function public.can_manage_partner_asset(p_name text)
returns boolean
language plpgsql
stable
security definer
set search_path = public, storage
as $$
declare
  v_folder text;
  v_venue uuid;
begin
  if auth.uid() is null then return false; end if;
  v_folder := split_part(coalesce(p_name, ''), '/', 1);
  if v_folder !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    return false;
  end if;
  v_venue := v_folder::uuid;
  return exists (
    select 1
    from public.venue_claim vc
    where vc.venue_id = v_venue
      and vc.user_id = auth.uid()
      and vc.status = 'approved'
  );
end;
$$;

revoke all on function public.can_manage_partner_asset(text) from public, anon;
grant execute on function public.can_manage_partner_asset(text) to authenticated;

update storage.buckets
set file_size_limit = 3145728,
    allowed_mime_types = array['image/png','image/jpeg','image/webp']
where id = 'partner-assets';

drop policy if exists partner_assets_write on storage.objects;
drop policy if exists partner_assets_select_owned on storage.objects;
drop policy if exists partner_assets_update on storage.objects;
drop policy if exists partner_assets_delete on storage.objects;

-- Storage upsert checks the existing object before updating it, so approved
-- owners need SELECT on their own venue folder in addition to UPDATE.
create policy partner_assets_select_owned
on storage.objects for select to authenticated
using (
  bucket_id = 'partner-assets'
  and public.can_manage_partner_asset(name)
);

create policy partner_assets_write
on storage.objects for insert to authenticated
with check (
  bucket_id = 'partner-assets'
  and public.can_manage_partner_asset(name)
);

create policy partner_assets_update
on storage.objects for update to authenticated
using (
  bucket_id = 'partner-assets'
  and public.can_manage_partner_asset(name)
)
with check (
  bucket_id = 'partner-assets'
  and public.can_manage_partner_asset(name)
);

create policy partner_assets_delete
on storage.objects for delete to authenticated
using (
  bucket_id = 'partner-assets'
  and public.can_manage_partner_asset(name)
);

create or replace function public.set_venue_logo(p_venue uuid, p_url text)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_prefix constant text :=
    'https://qfwiizvqxrhjlthbjosz.supabase.co/storage/v1/object/public/partner-assets/';
begin
  if auth.uid() is null then raise exception 'sign in required'; end if;
  if not exists (
    select 1 from public.venue_claim vc
    where vc.venue_id = p_venue
      and vc.user_id = auth.uid()
      and vc.status = 'approved'
  ) then
    raise exception 'venue not claimed/approved';
  end if;
  if p_url is not null
     and p_url not like v_prefix || p_venue::text || '/%' then
    raise exception 'logo must be uploaded to this venue''s Tapt asset folder';
  end if;
  update public.venue set logo_url = p_url where id = p_venue;
end;
$$;

revoke all on function public.set_venue_logo(uuid, text) from public, anon;
grant execute on function public.set_venue_logo(uuid, text) to authenticated;

notify pgrst, 'reload schema';
