-- 0054_launch_security_privacy_hardening.sql
-- Fail-closed privacy defaults, least-privilege API grants, verified venue claims,
-- scoped partner assets, and complete personal-row deletion before launch.

-- The latest ledger row is the source of truth. Historical event flags alone are
-- never enough to keep using data after a withdrawal or GPC signal.
create or replace function public.has_current_consent(
  p_user uuid,
  p_purpose public.consent_purpose
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((
    select c.granted and c.action = 'granted'::public.consent_action
    from public.consent_ledger c
    where c.user_id = p_user and c.purpose = p_purpose
    order by c.created_at desc, c.id desc
    limit 1
  ), false);
$$;
revoke all on function public.has_current_consent(uuid, public.consent_purpose)
  from public, anon, authenticated;
grant execute on function public.has_current_consent(uuid, public.consent_purpose)
  to service_role;

-- Earlier onboarding shipped optional toggles preselected. Reset those records once
-- so every existing account makes an affirmative choice under the corrected UI.
insert into public.consent_ledger
  (user_id, purpose, action, granted, policy_version, ui_text_shown, source)
select up.id, p.purpose, 'withdrawn'::public.consent_action, false,
       '2026-07-11', p.ui_text, 'launch_consent_reset'
from public.user_profile up
cross join (values
  ('location'::public.consent_purpose, 'Optional nearby location sharing starts off.'),
  ('aggregate_analytics'::public.consent_purpose, 'Optional anonymous trend sharing starts off.'),
  ('data_sale'::public.consent_purpose, 'Optional partner aggregate sharing starts off.')
) as p(purpose, ui_text);

alter table public.user_profile alter column social_visible set default false;
update public.user_profile set social_visible = false where social_visible;

create or replace function public.set_social_visibility(p_visible boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  update public.user_profile
  set social_visible = coalesce(p_visible, false), updated_at = now()
  where id = auth.uid();
end;
$$;
revoke all on function public.set_social_visibility(boolean) from public, anon;
grant execute on function public.set_social_visibility(boolean) to authenticated;

-- A claim always uses the verified email from the caller's JWT and always enters
-- human review. Client-supplied email/domain text can no longer approve a venue.
create or replace function public.claim_venue(
  p_venue uuid,
  p_email text,
  p_role text default 'manager'
)
returns uuid
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_email text := lower(nullif(btrim(auth.jwt()->>'email'), ''));
begin
  if auth.uid() is null then raise exception 'sign in required'; end if;
  if v_email is null or position('@' in v_email) <= 1 then
    raise exception 'a verified account email is required';
  end if;
  if p_role not in ('owner', 'manager', 'staff', 'other') then
    raise exception 'invalid claimant role';
  end if;
  if not exists (select 1 from public.venue v where v.id = p_venue) then
    raise exception 'venue not found';
  end if;

  insert into public.venue_claim
    (venue_id, user_id, business_email, claimant_role, status)
  values (p_venue, auth.uid(), v_email, p_role, 'pending')
  on conflict (venue_id, user_id) do update
    set business_email = excluded.business_email,
        claimant_role = excluded.claimant_role
  returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.claim_venue(uuid, text, text) from public, anon;
grant execute on function public.claim_venue(uuid, text, text) to authenticated;

-- Public aggregate views are read-only and execute under the caller's RLS context.
alter view if exists public.beer_catalog_listable set (security_invoker = true);
alter view if exists public.beer_trend_feed set (security_invoker = true);
alter view if exists public.public_venue set (security_invoker = true);
create or replace view public.public_profile
with (security_invoker = true) as
select id, handle, display_name, avatar_url
from public.user_profile
where social_visible;

revoke all on table public.beer_catalog_listable from public, anon, authenticated;
revoke all on table public.beer_trend_feed from public, anon, authenticated;
revoke all on table public.public_profile from public, anon, authenticated;
revoke all on table public.public_venue from public, anon, authenticated;
grant select on table public.beer_catalog_listable to anon, authenticated;
grant select on table public.beer_trend_feed to anon, authenticated;
grant select on table public.public_profile to authenticated;
grant select on table public.public_venue to anon, authenticated;

-- Materialized scores are public aggregates, but never writable by app roles.
alter table public.beer_score enable row level security;
drop policy if exists beer_score_public_read on public.beer_score;
create policy beer_score_public_read on public.beer_score
  for select to anon, authenticated using (true);
revoke all on table public.beer_score from public, anon, authenticated;
grant select on table public.beer_score to anon, authenticated;

-- Private notes now have real ownership FKs and least-privilege direct grants.
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'beer_note_user_fk'
      and conrelid = 'public.beer_note'::regclass
  ) then
    alter table public.beer_note
      add constraint beer_note_user_fk foreign key (user_id)
      references public.user_profile(id) on delete cascade;
  end if;
  if not exists (
    select 1 from pg_constraint where conname = 'beer_note_beer_fk'
      and conrelid = 'public.beer_note'::regclass
  ) then
    alter table public.beer_note
      add constraint beer_note_beer_fk foreign key (beer_id)
      references public.beer_catalog(id) on delete cascade;
  end if;
end;
$$;
drop policy if exists beer_note_own on public.beer_note;
create policy beer_note_own on public.beer_note
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
revoke all on table public.beer_note from public, anon, authenticated;
grant select, insert, update, delete on table public.beer_note to authenticated;

-- Tap items are exposed only through venue_menu(), which enforces active snapshot
-- freshness. Direct table reads could otherwise reveal expired/private menus.
drop policy if exists venue_tap_item_public_read on public.venue_tap_item;
revoke all on table public.venue_tap_item from public, anon, authenticated;

-- Storage delivery for these public buckets does not require object-table SELECT.
-- Removing listing policies prevents bulk enumeration through the data API.
drop policy if exists "avatar public read" on storage.objects;
drop policy if exists cutouts_read on storage.objects;
drop policy if exists cutouts_write on storage.objects;
drop policy if exists cutouts_update on storage.objects;
drop policy if exists partner_assets_read on storage.objects;
drop policy if exists partner_assets_write on storage.objects;
drop policy if exists partner_assets_update on storage.objects;

create or replace function public.can_manage_venue_asset(p_venue text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.venue_claim vc
    where vc.user_id = auth.uid()
      and vc.status = 'approved'
      and vc.venue_id::text = p_venue
  );
$$;
revoke all on function public.can_manage_venue_asset(text) from public, anon;
grant execute on function public.can_manage_venue_asset(text) to authenticated;

create policy partner_assets_write on storage.objects
for insert to authenticated
with check (
  bucket_id = 'partner-assets'
  and owner = auth.uid()
  and public.can_manage_venue_asset((storage.foldername(name))[1])
);
create policy partner_assets_update on storage.objects
for update to authenticated
using (
  bucket_id = 'partner-assets'
  and owner = auth.uid()
  and public.can_manage_venue_asset((storage.foldername(name))[1])
)
with check (
  bucket_id = 'partner-assets'
  and owner = auth.uid()
  and public.can_manage_venue_asset((storage.foldername(name))[1])
);

-- Complete the personal-plane delete and scrub provenance fields that can retain
-- an account UUID after the profile itself is gone.
create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare u uuid := auth.uid();
begin
  if u is null then raise exception 'not authenticated'; end if;

  delete from public.beer_note where user_id = u;
  delete from public.beer_vote where user_id = u;
  delete from public.checkin_review where user_id = u;
  delete from public.session_pour where user_id = u;
  delete from public.session_participant where user_id = u;
  delete from public.checkin_event where user_id = u;
  delete from public.crew_member where user_id = u;
  delete from public.taste_vector where user_id = u;
  delete from public.featured_impression where user_id = u;
  delete from public.newsletter_subscriber where user_id = u;
  delete from public.partner_inquiry where user_id = u;
  delete from public.venue_claim where user_id = u;
  delete from public.follow where follower_id = u or followee_id = u;
  delete from public.user_block where blocker_id = u or blocked_id = u;
  delete from public.content_report where reporter_id = u;
  delete from public.consent_ledger where user_id = u;
  delete from public.account_deletion_request where user_id = u;
  delete from public.app_admin where user_id = u;

  update public.beer_catalog
  set external_ids = external_ids - 'added_by'
  where external_ids->>'added_by' = u::text;
  update public.brewery
  set external_ids = external_ids - 'added_by'
  where external_ids->>'added_by' = u::text;

  delete from public.user_profile where id = u;
  delete from auth.users where id = u;
end;
$$;
revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;

-- Remove default PUBLIC execute from sensitive SECURITY DEFINER functions and grant
-- only the roles that own the matching product flow.
drop function if exists public.featured_partner_feed(integer);

revoke all on function public.get_beer_note(uuid) from public, anon, authenticated;
revoke all on function public.save_beer_note(uuid, text) from public, anon, authenticated;
revoke all on function public.my_beer_activity() from public, anon, authenticated;
revoke all on function public.public_profile(uuid) from public, anon, authenticated;
revoke all on function public.log_featured_event(uuid, text, text) from public, anon, authenticated;
revoke all on function public.featured_partner_feed(integer, text) from public, anon, authenticated;
revoke all on function public.grant_featured(uuid, text, integer, text, text) from public, anon, authenticated;
revoke all on function public.venue_analytics(uuid) from public, anon, authenticated;
revoke all on function public.build_dispatch_content() from public, anon, authenticated;
revoke all on function public.enforce_checkin_review_owner() from public, anon, authenticated;
revoke all on function public.refresh_beer_score() from public, anon, authenticated;
revoke all on function public.territory_report(text) from public, anon, authenticated;

grant execute on function public.get_beer_note(uuid) to authenticated;
grant execute on function public.save_beer_note(uuid, text) to authenticated;
grant execute on function public.my_beer_activity() to authenticated;
grant execute on function public.public_profile(uuid) to authenticated;
grant execute on function public.log_featured_event(uuid, text, text) to authenticated;
grant execute on function public.featured_partner_feed(integer, text) to authenticated;
grant execute on function public.grant_featured(uuid, text, integer, text, text) to authenticated;
grant execute on function public.venue_analytics(uuid) to authenticated;
grant execute on function public.build_dispatch_content() to service_role;
grant execute on function public.refresh_beer_score() to service_role;
grant execute on function public.territory_report(text) to service_role;

-- Public read RPCs remain public, but only through explicit anon/auth grants.
revoke all on function public.beer_detail(uuid) from public, anon, authenticated;
revoke all on function public.beer_style_science(uuid) from public, anon, authenticated;
revoke all on function public.catalog_search(text, text, boolean, integer, integer) from public, anon, authenticated;
revoke all on function public.platform_stats() from public, anon, authenticated;
revoke all on function public.dispatch_archive(integer) from public, anon, authenticated;
revoke all on function public.dispatch_issue_by_slug(text) from public, anon, authenticated;
revoke all on function public.beer_of_week_latest_winner() from public, anon, authenticated;
revoke all on function public.beer_of_week_standings(integer) from public, anon, authenticated;
revoke all on function public.brewery_map_feed(integer) from public, anon, authenticated;
revoke all on function public.brewery_map_feed_near(numeric, numeric, integer, integer) from public, anon, authenticated;
revoke all on function public.leaderboard_beers(integer, boolean) from public, anon, authenticated;
revoke all on function public.leaderboard_beers_regional(text, integer) from public, anon, authenticated;
revoke all on function public.leaderboard_styles(integer) from public, anon, authenticated;
revoke all on function public.search_venues(text, integer) from public, anon, authenticated;
revoke all on function public.tonight_feed(text, integer) from public, anon, authenticated;
revoke all on function public.venue_brand(uuid) from public, anon, authenticated;
revoke all on function public.venue_events(uuid) from public, anon, authenticated;
revoke all on function public.venue_menu(uuid) from public, anon, authenticated;

grant execute on function public.beer_detail(uuid) to anon, authenticated;
grant execute on function public.beer_style_science(uuid) to anon, authenticated;
grant execute on function public.catalog_search(text, text, boolean, integer, integer) to anon, authenticated;
grant execute on function public.platform_stats() to anon, authenticated;
grant execute on function public.dispatch_archive(integer) to anon, authenticated;
grant execute on function public.dispatch_issue_by_slug(text) to anon, authenticated;
grant execute on function public.beer_of_week_latest_winner() to anon, authenticated;
grant execute on function public.beer_of_week_standings(integer) to anon, authenticated;
grant execute on function public.brewery_map_feed(integer) to anon, authenticated;
grant execute on function public.brewery_map_feed_near(numeric, numeric, integer, integer) to anon, authenticated;
grant execute on function public.leaderboard_beers(integer, boolean) to anon, authenticated;
grant execute on function public.leaderboard_beers_regional(text, integer) to anon, authenticated;
grant execute on function public.leaderboard_styles(integer) to anon, authenticated;
grant execute on function public.search_venues(text, integer) to anon, authenticated;
grant execute on function public.tonight_feed(text, integer) to anon, authenticated;
grant execute on function public.venue_brand(uuid) to anon, authenticated;
grant execute on function public.venue_events(uuid) to anon, authenticated;
grant execute on function public.venue_menu(uuid) to anon, authenticated;

-- Lock helper resolution to the system catalog and remove mutable search_path
-- warnings without changing their deterministic behavior.
alter function public.clean_beer_name(text) set search_path = pg_catalog;
alter function public.tapt_display_name(text) set search_path = pg_catalog;
alter function public.tapt_name_ok(text) set search_path = pg_catalog;
alter function public.tapt_ref_style_name(text, text) set search_path = pg_catalog;

-- Future schema additions must opt app roles in explicitly.
alter default privileges for role postgres in schema public
  revoke all on tables from anon, authenticated;
alter default privileges for role postgres in schema public
  revoke execute on functions from public, anon, authenticated;

notify pgrst, 'reload schema';
