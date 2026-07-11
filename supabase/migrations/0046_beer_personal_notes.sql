-- 0046_beer_personal_notes.sql
-- Private per-user written note on a beer (tasting notes etc.). RLS scopes every row
-- to its owner. save_beer_note upserts (or clears on blank); get_beer_note reads yours.
create table if not exists public.beer_note (
  user_id uuid not null, beer_id uuid not null, note text not null,
  updated_at timestamptz not null default now(), primary key (user_id, beer_id));
alter table public.beer_note enable row level security;
drop policy if exists beer_note_own on public.beer_note;
create policy beer_note_own on public.beer_note for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create or replace function public.save_beer_note(p_beer uuid, p_note text)
returns void language plpgsql security definer set search_path to 'public' as $$
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if length(btrim(coalesce(p_note,''))) = 0 then
    delete from beer_note where user_id = auth.uid() and beer_id = p_beer;
  else
    insert into beer_note (user_id, beer_id, note, updated_at)
    values (auth.uid(), p_beer, left(btrim(p_note),1000), now())
    on conflict (user_id, beer_id) do update set note = excluded.note, updated_at = now();
  end if;
end; $$;
grant execute on function public.save_beer_note(uuid, text) to authenticated;
create or replace function public.get_beer_note(p_beer uuid)
returns text language sql stable security definer set search_path to 'public' as $$
  select note from beer_note where user_id = auth.uid() and beer_id = p_beer; $$;
grant execute on function public.get_beer_note(uuid) to authenticated;
