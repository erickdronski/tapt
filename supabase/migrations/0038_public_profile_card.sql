-- 0038_public_profile_card.sql
--
-- Make "follow" actually mean something: when you tap a person you follow (or
-- find in search / the Tonight feed) you see a small, honest passport card.
-- Shows only COARSE aggregates the user generated themselves -- pours, styles,
-- countries, states, favorite beer, member-since. Deliberately NO venue names,
-- NO timestamps, NO geo precision, NO per-checkin rows: nothing that could out
-- where/when someone drinks. Honors blocks (either direction) and a per-user
-- social_visible switch, mirroring the privacy pattern already in search_profiles.
-- Verified live: returns a full card for a user with check-ins (pours, country,
-- top style, favorite beer) and a clean identity-only card for a new drinker.

alter table public.user_profile
  add column if not exists social_visible boolean not null default true;

create or replace function public.public_profile(p_user uuid)
returns jsonb
language plpgsql stable security definer set search_path to 'public'
as $$
declare
  me uuid := auth.uid();
  prof record;
  is_blocked boolean;
  fav jsonb;
  styles jsonb;
  s_pours int; s_styles int; s_countries int; s_states int;
begin
  if me is null then raise exception 'not authenticated'; end if;
  if p_user is null then raise exception 'no user'; end if;

  select up.id,
         coalesce(nullif(up.display_name,''), nullif(up.handle,''), 'Beer fan') as display_name,
         up.handle, up.avatar_url, up.region_code, up.created_at,
         coalesce(up.social_visible, true) as social_visible
    into prof
  from user_profile up where up.id = p_user;

  if prof.id is null then raise exception 'profile not found'; end if;

  is_blocked := exists (select 1 from user_block ub
    where (ub.blocker_id = me and ub.blocked_id = p_user)
       or (ub.blocker_id = p_user and ub.blocked_id = me));

  -- Blocked, or the person hid their profile and it isn't you: identity-only card.
  if is_blocked or (not prof.social_visible and me <> p_user) then
    return jsonb_build_object(
      'user_id', prof.id, 'display_name', prof.display_name, 'handle', prof.handle,
      'avatar_url', prof.avatar_url, 'region', prof.region_code,
      'member_since', prof.created_at,
      'is_self', me = p_user, 'is_following', false,
      'visible', false, 'blocked', is_blocked,
      'followers', 0, 'following', 0
    );
  end if;

  select
    count(*)::int,
    count(distinct nullif(ce.style,''))::int,
    count(distinct br.country) filter (where coalesce(br.country,'') <> '')::int,
    count(distinct (v.external_ids->>'region')) filter (
      where br.country ilike 'united states%' or br.country ilike 'usa' or br.country = 'US')::int
  into s_pours, s_styles, s_countries, s_states
  from checkin_event ce
  left join brewery br on br.id = ce.brewery_id
  left join venue v on v.id = ce.venue_id
  where ce.user_id = p_user
    and coalesce(ce.moderation_status,'ok') not in ('removed','rejected','hidden');

  select coalesce(jsonb_agg(t),'[]'::jsonb) into styles from (
    select nullif(ce.style,'') as style, count(*)::int as pours
    from checkin_event ce
    where ce.user_id = p_user and nullif(ce.style,'') is not null
      and coalesce(ce.moderation_status,'ok') not in ('removed','rejected','hidden')
    group by 1 order by 2 desc, 1 limit 3
  ) t;

  select to_jsonb(fb) into fav from (
    select b.name, brz.name as brewery, count(*)::int as pours
    from checkin_event ce
    join beer_catalog b on b.id = ce.beer_id
    left join brewery brz on brz.id = b.brewery_id
    where ce.user_id = p_user
      and coalesce(ce.moderation_status,'ok') not in ('removed','rejected','hidden')
    group by b.name, brz.name
    order by count(*) desc, max(ce.rating) desc nulls last, max(ce.event_ts) desc
    limit 1
  ) fb;

  return jsonb_build_object(
    'user_id', prof.id,
    'display_name', prof.display_name,
    'handle', prof.handle,
    'avatar_url', prof.avatar_url,
    'region', prof.region_code,
    'member_since', prof.created_at,
    'is_self', me = p_user,
    'is_following', exists (select 1 from follow f where f.follower_id = me and f.followee_id = p_user),
    'visible', true, 'blocked', false,
    'followers', (select count(*) from follow f where f.followee_id = p_user),
    'following', (select count(*) from follow f where f.follower_id = p_user),
    'pours', coalesce(s_pours,0),
    'styles_count', coalesce(s_styles,0),
    'countries', coalesce(s_countries,0),
    'states', coalesce(s_states,0),
    'top_styles', coalesce(styles,'[]'::jsonb),
    'favorite_beer', fav
  );
end; $$;

grant execute on function public.public_profile(uuid) to authenticated;
