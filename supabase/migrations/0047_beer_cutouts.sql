-- 0047_beer_cutouts.sql
-- Public storage bucket for background-removed beer cut-outs + a cutout_url column.
-- Cut-outs are produced with rembg (free/local) from the real OFF photo and uploaded
-- to Storage; label_image_url is pointed at the cut-out so every surface shows a clean
-- floating product. Backgrounds removed from REAL photos, never fabricated.
insert into storage.buckets (id, name, public) values ('beer-cutouts','beer-cutouts', true)
  on conflict (id) do update set public = true;
drop policy if exists cutouts_read on storage.objects;
create policy cutouts_read on storage.objects for select using (bucket_id = 'beer-cutouts');
drop policy if exists cutouts_write on storage.objects;
create policy cutouts_write on storage.objects for insert to authenticated with check (bucket_id = 'beer-cutouts');
drop policy if exists cutouts_update on storage.objects;
create policy cutouts_update on storage.objects for update to authenticated using (bucket_id = 'beer-cutouts');
alter table public.beer_catalog add column if not exists cutout_url text;
