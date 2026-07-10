-- 0015_venue_claims_and_menus.sql
-- Free hosted venue menus — the tool the incumbent charges $1,199/yr for.
-- claim_venue (authenticated) -> owner approves claim (concierge for now) ->
-- publish_tap_list (approved claimants, 1-60 taps, 14-day freshness) ->
-- venue_menu (PUBLIC, anon) powers the hosted QR page at /menu?v={venue_id}.
-- Verified end-to-end 2026-07-10 (claim/approve/publish/anon-read, rolled back).
-- Applied live via MCP as migration "venue_claims_and_menus"; definition below.
create table if not exists venue_claim (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid not null references venue(id) on delete cascade,
  user_id uuid not null references user_profile(id) on delete cascade,
  business_email text not null check (position('@' in business_email) > 1),
  claimant_role text check (claimant_role in ('owner','manager','staff','other')),
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  created_at timestamptz not null default now(),
  unique (venue_id, user_id)
);
alter table venue_claim enable row level security;

create or replace function claim_venue(p_venue uuid, p_email text, p_role text default 'manager')
returns uuid language plpgsql volatile security definer set search_path = public as $$
declare v_id uuid;
begin
  if auth.uid() is null then raise exception 'sign in required'; end if;
  insert into venue_claim (venue_id, user_id, business_email, claimant_role)
  values (p_venue, auth.uid(), lower(trim(p_email)), p_role)
  on conflict (venue_id, user_id) do update set business_email = excluded.business_email
  returning id into v_id;
  return v_id;
end; $$;

create or replace function my_venue_claims()
returns table (claim_id uuid, venue_id uuid, venue_name text, status text)
language sql stable security definer set search_path = public as $$
  select vc.id, vc.venue_id, v.name, vc.status
  from venue_claim vc join venue v on v.id = vc.venue_id
  where vc.user_id = auth.uid();
$$;

create or replace function publish_tap_list(p_venue uuid, p_items jsonb)
returns int language plpgsql volatile security definer set search_path = public as $$
declare v_snap uuid; v_count int := 0; v_item jsonb;
begin
  if auth.uid() is null then raise exception 'sign in required'; end if;
  if not exists (select 1 from venue_claim vc where vc.venue_id = p_venue
                 and vc.user_id = auth.uid() and vc.status = 'approved') then
    raise exception 'venue not claimed/approved';
  end if;
  if jsonb_array_length(p_items) < 1 or jsonb_array_length(p_items) > 60 then
    raise exception 'send 1-60 taps';
  end if;
  insert into venue_tap_snapshot (venue_id, captured_by, source, observed_at, expires_at)
  values (p_venue, auth.uid(), 'partner_portal', now(), now() + interval '14 days')
  returning id into v_snap;
  for v_item in select * from jsonb_array_elements(p_items) loop
    insert into venue_tap_item (snapshot_id, beer_name, brewery_name, style, price_text, confidence)
    values (v_snap,
      left(trim(v_item->>'beer_name'), 160),
      nullif(left(trim(coalesce(v_item->>'brewery_name','')), 160), ''),
      nullif(left(trim(coalesce(v_item->>'style','')), 80), ''),
      nullif(left(trim(coalesce(v_item->>'price','')), 40), ''),
      1.0);
    v_count := v_count + 1;
  end loop;
  return v_count;
end; $$;

create or replace function venue_menu(p_venue uuid)
returns table (venue_name text, city text, region text, country text,
               beer_name text, brewery_name text, style text, price_text text, updated_at timestamptz)
language sql stable security definer set search_path = public as $$
  select v.name, v.external_ids->>'city', v.external_ids->>'region', v.external_ids->>'country',
         i.beer_name, i.brewery_name, i.style, i.price_text, s.observed_at
  from venue v
  join venue_tap_snapshot s on s.venue_id = v.id and s.expires_at > now()
  join venue_tap_item i on i.snapshot_id = s.id
  where v.id = p_venue
    and s.id = (select s2.id from venue_tap_snapshot s2
                where s2.venue_id = v.id and s2.expires_at > now()
                order by s2.observed_at desc limit 1)
  order by i.created_at;
$$;

revoke all on function claim_venue(uuid, text, text) from public, anon;
revoke all on function my_venue_claims() from public, anon;
revoke all on function publish_tap_list(uuid, jsonb) from public, anon;
revoke all on function venue_menu(uuid) from public;
grant execute on function claim_venue(uuid, text, text) to authenticated;
grant execute on function my_venue_claims() to authenticated;
grant execute on function publish_tap_list(uuid, jsonb) to authenticated;
grant execute on function venue_menu(uuid) to anon, authenticated;
