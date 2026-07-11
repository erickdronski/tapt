-- 0040_beer_images_in_leaderboard_and_profile.sql
--
-- Surface the real product image we already store (beer_catalog.label_image_url,
-- ~95% coverage from Open Food Facts) wherever a beer is named but was text-only:
-- the leaderboard rows and a drinker's favorite pour on their passport card. The
-- app shows the real photo when present and a tinted glass fallback otherwise -- no
-- fabricated imagery. Adding a column changes leaderboard_beers' return signature,
-- so it is dropped and recreated; public_profile returns jsonb so it is replaced.
-- Verified live: leaderboard_beers rows carry image_url; favorite_beer json carries
-- a real OFF image url.

drop function if exists public.leaderboard_beers(integer, boolean);
create function public.leaderboard_beers(p_limit integer default 20, p_na_only boolean default false)
returns table(beer_id uuid, name text, style text, brewery_name text, country text,
              net_votes integer, ups integer, downs integer, checkin_count integer,
              avg_rating numeric, image_url text)
language sql stable security definer set search_path to 'public'
as $$
  select b.id, b.name, b.style, br.name, br.country,
         s.net, s.ups, s.downs, s.checkins, s.avg_rating, b.label_image_url
  from beer_score s
  join beer_catalog b on b.id = s.beer_id
  left join brewery br on br.id = b.brewery_id
  where (s.net <> 0 or s.checkins > 0)
    and (not p_na_only or b.is_na_low)
  order by (s.net + s.checkins * 2) desc, b.name
  limit least(greatest(coalesce(p_limit, 20), 1), 50);
$$;
grant execute on function public.leaderboard_beers(integer, boolean) to authenticated, anon;

-- public_profile: add image_url to the favorite_beer object (full body restated;
-- see 0038/0039 for prior definition -- only the favorite subquery gains image_url).
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
  where ce.user_id = p_user and ce.moderation_status = 'visible';

  select coalesce(jsonb_agg(t),'[]'::jsonb) into styles from (
    select nullif(ce.style,'') as style, count(*)::int as pours
    from checkin_event ce
    where ce.user_id = p_user and nullif(ce.style,'') is not null
      and ce.moderation_status = 'visible'
    group by 1 order by 2 desc, 1 limit 3
  ) t;

  select to_jsonb(fb) into fav from (
    select b.name, brz.name as brewery, b.label_image_url as image_url, count(*)::int as pours
    from checkin_event ce
    join beer_catalog b on b.id = ce.beer_id
    left join brewery brz on brz.id = b.brewery_id
    where ce.user_id = p_user and ce.moderation_status = 'visible'
    group by b.name, brz.name, b.label_image_url
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
