-- 0062_age_social_and_guest_market.sql
-- Require explicit legal-age self-attestation, enforce social visibility on
-- every discovery feed, and expose the read-only Market aggregate to guests.

drop function if exists public.complete_profile_onboarding(
  text, text[], boolean, boolean, boolean, text
);

create or replace function public.complete_profile_onboarding(
  p_age_confirmed boolean,
  p_region_code text,
  p_top_styles text[],
  p_location_consent boolean,
  p_aggregate_consent boolean,
  p_data_sale_consent boolean,
  p_policy_version text default '2026-07-12'
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'not authenticated'; end if;
  if coalesce(p_age_confirmed, false) is not true then
    raise exception 'legal drinking age confirmation required';
  end if;

  update public.user_profile
  set birth_verified = true,
      region_code = nullif(trim(p_region_code), ''),
      updated_at = now()
  where id = v_user;

  insert into public.taste_vector (user_id, top_styles)
  values (v_user, coalesce(p_top_styles, '{}'))
  on conflict (user_id) do update
    set top_styles = excluded.top_styles,
        updated_at = now();

  insert into public.consent_ledger
    (user_id, purpose, action, granted, policy_version, ui_text_shown, source)
  values
    (v_user, 'location',
     case when p_location_consent then 'granted'::consent_action else 'withdrawn'::consent_action end,
     p_location_consent, p_policy_version,
     'Use my location for nearby pubs, bars, breweries, taprooms, and beer gardens.',
     'onboarding'),
    (v_user, 'aggregate_analytics',
     case when p_aggregate_consent then 'granted'::consent_action else 'withdrawn'::consent_action end,
     p_aggregate_consent, p_policy_version,
     'Use my check-ins for anonymous aggregate trend reports.', 'onboarding'),
    (v_user, 'data_sale',
     case when p_data_sale_consent then 'granted'::consent_action else 'withdrawn'::consent_action end,
     p_data_sale_consent, p_policy_version,
     'Include my anonymous aggregate data in partner insights.', 'onboarding');
end;
$$;

revoke all on function public.complete_profile_onboarding(
  boolean, text, text[], boolean, boolean, boolean, text
) from public, anon;
grant execute on function public.complete_profile_onboarding(
  boolean, text, text[], boolean, boolean, boolean, text
) to authenticated;

create or replace function public.search_profiles(p_query text, p_limit int default 12)
returns table (
  user_id uuid, display_name text, handle text, avatar_url text,
  pours int, is_following boolean
)
language sql
stable
security definer
set search_path = public
as $$
  select
    up.id,
    coalesce(nullif(up.display_name, ''), nullif(up.handle, ''), 'Beer fan'),
    up.handle,
    up.avatar_url,
    (select count(*)::int from public.checkin_event ce
      where ce.user_id = up.id and ce.moderation_status = 'visible'),
    exists (select 1 from public.follow f
      where f.follower_id = auth.uid() and f.followee_id = up.id)
  from public.user_profile up
  where auth.uid() is not null
    and up.social_visible
    and up.id <> auth.uid()
    and length(trim(coalesce(p_query, ''))) >= 2
    and (up.display_name ilike '%' || trim(p_query) || '%'
      or up.handle ilike '%' || trim(p_query) || '%')
    and not exists (
      select 1 from public.user_block ub
      where (ub.blocker_id = auth.uid() and ub.blocked_id = up.id)
         or (ub.blocker_id = up.id and ub.blocked_id = auth.uid())
    )
  order by 5 desc, 2
  limit least(greatest(coalesce(p_limit, 12), 1), 25);
$$;

create or replace function public.leaderboard_tasters(p_limit int default 20)
returns table (
  user_id uuid, display_name text, handle text, avatar_url text,
  pours int, styles int, countries int
)
language sql
stable
security definer
set search_path = public
as $$
  select
    up.id,
    coalesce(nullif(up.display_name, ''), nullif(up.handle, ''), 'Beer fan'),
    up.handle,
    up.avatar_url,
    count(ce.id)::int,
    count(distinct ce.style) filter (where coalesce(ce.style, '') <> '')::int,
    count(distinct br.country) filter (where coalesce(br.country, '') <> '')::int
  from public.user_profile up
  join public.checkin_event ce
    on ce.user_id = up.id and ce.moderation_status = 'visible'
  left join public.beer_catalog b on b.id = ce.beer_id
  left join public.brewery br on br.id = b.brewery_id
  where up.social_visible
    and not exists (
      select 1 from public.user_block ub
      where (ub.blocker_id = auth.uid() and ub.blocked_id = up.id)
         or (ub.blocker_id = up.id and ub.blocked_id = auth.uid())
    )
  group by up.id
  order by 5 desc, 6 desc, 2
  limit least(greatest(coalesce(p_limit, 20), 1), 50);
$$;

create or replace function public.social_pour_feed(p_limit int default 30)
returns table (
  checkin_id uuid, actor_id uuid, actor_name text, avatar_url text,
  beer_name text, brewery_name text, venue_name text, style text,
  rating numeric, event_ts timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  with me as (select auth.uid() as uid)
  select
    c.id,
    c.user_id,
    coalesce(p.display_name, p.handle, 'Beer fan'),
    p.avatar_url,
    b.name,
    br.name,
    v.name,
    c.style,
    c.rating,
    c.event_ts
  from me
  join public.checkin_event c on c.user_id = me.uid
    or exists (
      select 1 from public.follow f
      where f.follower_id = me.uid and f.followee_id = c.user_id
    )
  join public.user_profile p on p.id = c.user_id
  left join public.beer_catalog b on b.id = c.beer_id
  left join public.brewery br on br.id = b.brewery_id
  left join public.venue v on v.id = c.venue_id
  where me.uid is not null
    and c.moderation_status = 'visible'
    and (c.user_id = me.uid or p.social_visible)
    and not exists (
      select 1 from public.user_block ub
      where (ub.blocker_id = me.uid and ub.blocked_id = c.user_id)
         or (ub.blocker_id = c.user_id and ub.blocked_id = me.uid)
    )
  order by c.event_ts desc
  limit least(greatest(coalesce(p_limit, 30), 1), 60);
$$;

revoke all on function public.search_profiles(text, int) from public, anon;
revoke all on function public.leaderboard_tasters(int) from public, anon;
revoke all on function public.social_pour_feed(int) from public, anon;
grant execute on function public.search_profiles(text, int) to authenticated;
grant execute on function public.leaderboard_tasters(int) to authenticated;
grant execute on function public.social_pour_feed(int) to authenticated;

-- The Market is a read-only aggregate with no personal-plane rows.
grant execute on function public.beer_market(text, integer, boolean)
  to anon, authenticated;

notify pgrst, 'reload schema';
