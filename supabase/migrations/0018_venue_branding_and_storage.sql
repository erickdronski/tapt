-- 0018_venue_branding_and_storage.sql — partner logo upload + public bucket.
alter table venue add column if not exists logo_url text;

create or replace function set_venue_logo(p_venue uuid, p_url text)
returns void language plpgsql volatile security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'sign in required'; end if;
  if not exists (select 1 from venue_claim vc where vc.venue_id = p_venue
                 and vc.user_id = auth.uid() and vc.status = 'approved') then
    raise exception 'venue not claimed/approved';
  end if;
  if p_url is not null and p_url !~* '^https://' then raise exception 'invalid url'; end if;
  update venue set logo_url = p_url where id = p_venue;
end; $$;

create or replace function venue_brand(p_venue uuid)
returns table (name text, logo_url text, city text, region text, country text)
language sql stable security definer set search_path = public as $$
  select v.name, v.logo_url, v.external_ids->>'city', v.external_ids->>'region', v.external_ids->>'country'
  from venue v where v.id = p_venue;
$$;

revoke all on function set_venue_logo(uuid, text) from public, anon;
revoke all on function venue_brand(uuid) from public;
grant execute on function set_venue_logo(uuid, text) to authenticated;
grant execute on function venue_brand(uuid) to anon, authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('partner-assets', 'partner-assets', true, 3145728, array['image/png','image/jpeg','image/webp','image/svg+xml'])
on conflict (id) do nothing;

drop policy if exists partner_assets_read on storage.objects;
create policy partner_assets_read on storage.objects for select using (bucket_id = 'partner-assets');
drop policy if exists partner_assets_write on storage.objects;
create policy partner_assets_write on storage.objects for insert to authenticated with check (bucket_id = 'partner-assets');
drop policy if exists partner_assets_update on storage.objects;
create policy partner_assets_update on storage.objects for update to authenticated using (bucket_id = 'partner-assets');
