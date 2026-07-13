-- The data moat: let a signed-in user add a beer we don't have yet. It lands in
-- their Cellar immediately (real beer_catalog row) but stays out of public search
-- and the Beer Market until a moderator approves it (name_ok stays false). Every
-- field is user-typed or null. No fabricated data.
create table if not exists public.beer_submission (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references public.user_profile(id) on delete cascade,
  beer_id      uuid not null references public.beer_catalog(id) on delete cascade,
  name         text not null,
  brewery_name text,
  style        text,
  abv          numeric,
  status       text not null default 'pending',   -- pending | approved | rejected | merged
  merged_into  uuid references public.beer_catalog(id),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index if not exists beer_submission_status_idx on public.beer_submission(status, created_at);
alter table public.beer_submission enable row level security;

drop policy if exists beer_submission_read_own on public.beer_submission;
create policy beer_submission_read_own on public.beer_submission
  for select using (user_id = (select auth.uid()));

-- Authenticated-only RPC, mirrors submit_partner_inquiry (rate limit + dedup guard).
create or replace function public.submit_beer(
  p_name text, p_brewery_name text default null,
  p_style text default null, p_abv numeric default null
) returns uuid
language plpgsql security definer set search_path to 'public' as $$
declare
  v_user uuid := (select auth.uid());
  v_name text := btrim(coalesce(p_name,''));
  v_brew text := nullif(btrim(coalesce(p_brewery_name,'')), '');
  v_style text := nullif(btrim(coalesce(p_style,'')), '');
  v_recent int; v_brewery_id uuid; v_beer_id uuid; v_dupe uuid;
begin
  if v_user is null then raise exception 'sign in required'; end if;
  if length(v_name) < 2 or length(v_name) > 80 then raise exception 'beer name must be 2 to 80 characters'; end if;
  if p_abv is not null and (p_abv < 0 or p_abv > 100) then raise exception 'abv out of range'; end if;

  select count(*) into v_recent from beer_submission
   where user_id = v_user and created_at > now() - interval '1 day';
  if v_recent >= 10 then raise exception 'too many beer submissions today'; end if;

  -- Reuse an already-approved catalog beer if it clearly matches (no twins).
  select bc.id into v_dupe
    from beer_catalog bc left join brewery b on b.id = bc.brewery_id
   where bc.name_ok
     and lower(coalesce(bc.display_name, bc.name)) = lower(v_name)
     and (v_brew is null or lower(coalesce(b.name,'')) = lower(v_brew))
   limit 1;
  if v_dupe is not null then return v_dupe; end if;

  -- Capture the brewery too (moat): reuse case-insensitively, else create minimal.
  if v_brew is not null then
    select id into v_brewery_id from brewery where lower(name) = lower(v_brew) limit 1;
    if v_brewery_id is null then
      insert into brewery(name, external_ids) values (v_brew, jsonb_build_object('source','user_submission'))
      returning id into v_brewery_id;
    end if;
  end if;

  insert into beer_catalog(name, display_name, brewery_id, style, style_ref, abv, name_ok, external_ids)
  values (v_name, v_name, v_brewery_id, v_style, v_style, p_abv, false,
          jsonb_build_object('source','user_submission','submitted_by', v_user))
  returning id into v_beer_id;

  insert into beer_submission(user_id, beer_id, name, brewery_name, style, abv)
  values (v_user, v_beer_id, v_name, v_brew, v_style, p_abv);

  return v_beer_id;
end; $$;

revoke all on function public.submit_beer(text,text,text,numeric) from public;
revoke all on function public.submit_beer(text,text,text,numeric) from anon;
grant execute on function public.submit_beer(text,text,text,numeric) to authenticated;
