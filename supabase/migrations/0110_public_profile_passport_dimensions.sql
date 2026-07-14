-- Extend the public passport with exploration dimensions so the shareable card
-- earns the expanded, responsible badge set (breweries, continents, seasons,
-- No/Low, and style-family discovery). Same taxonomy the client computes in
-- PassportStats.from(checkins:). Mirrors the migration applied to prod.
create or replace function public.public_profile(p_user uuid)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
declare
  me uuid := auth.uid();
  prof record;
  is_blocked boolean;
  fav jsonb;
  styles jsonb;
  s_pours int; s_beers int; s_styles int; s_countries int; s_states int;
  s_brew int; s_cont int; s_seas int; s_nolow int;
  s_hoppy int; s_dark int; s_wheat int; s_sour int; s_belg int; s_crisp int;
begin
  if me is null then raise exception 'not authenticated'; end if;
  if p_user is null then raise exception 'no user'; end if;

  select up.id,
         coalesce(nullif(up.display_name, ''), nullif(up.handle, ''), 'Beer fan') as display_name,
         up.handle, up.avatar_url, up.region_code, up.created_at,
         coalesce(up.social_visible, false) as social_visible
    into prof
  from public.user_profile up
  where up.id = p_user;

  if prof.id is null then raise exception 'profile not found'; end if;

  is_blocked := exists (
    select 1 from public.user_block ub
    where (ub.blocker_id = me and ub.blocked_id = p_user)
       or (ub.blocker_id = p_user and ub.blocked_id = me)
  );

  if is_blocked or (not prof.social_visible and me <> p_user) then
    return jsonb_build_object(
      'user_id', prof.id, 'display_name', prof.display_name, 'handle', prof.handle,
      'avatar_url', prof.avatar_url, 'region', prof.region_code, 'member_since', prof.created_at,
      'is_self', me = p_user, 'is_following', false, 'visible', false, 'blocked', is_blocked,
      'followers', 0, 'following', 0
    );
  end if;

  select
    count(*)::int,
    (count(distinct (lower(b.display_name), coalesce(b.brewery_id::text, ''))) filter (where b.id is not null))::int,
    count(distinct nullif(ce.style, ''))::int,
    count(distinct br.country) filter (where coalesce(br.country, '') <> '')::int,
    count(distinct (v.external_ids->>'region')) filter (
      where lower(coalesce(v.external_ids->>'country', '')) in ('united states','united states of america','usa','us'))::int,
    count(distinct br.id) filter (where br.id is not null)::int,
    count(distinct case
      when br.country ~* 'united states|usa|canada|mexico' then 'NA'
      when br.country ~* 'germany|poland|czech|belgium|ireland|united kingdom|england|scotland|spain|netherlands|austria|denmark|norway|sweden|italy|france|iceland|finland|lithuania|ukraine|estonia|russia|switzerland|greece|portugal' then 'EU'
      when br.country ~* 'japan|korea|china|thailand|vietnam|singapore|philippines|india|sri lanka|taiwan|turkey|indonesia|malaysia' then 'AS'
      when br.country ~* 'brazil|argentina|peru|chile|colombia|uruguay|ecuador' then 'SA'
      when br.country ~* 'south africa|namibia|kenya|nigeria|ethiopia|egypt|morocco|tanzania' then 'AF'
      when br.country ~* 'australia|new zealand|fiji' then 'OC'
    end) filter (where br.country is not null)::int,
    count(distinct case
      when extract(month from ce.event_ts) in (12,1,2) then 'w'
      when extract(month from ce.event_ts) in (3,4,5) then 'sp'
      when extract(month from ce.event_ts) in (6,7,8) then 'su'
      else 'f' end)::int,
    count(distinct (lower(b.display_name), coalesce(b.brewery_id::text,''))) filter (where coalesce(b.style_ref, ce.style, b.name) ~* 'non[- ]?alco|alcohol[- ]?free|0[.,]0')::int,
    count(distinct (lower(b.display_name), coalesce(b.brewery_id::text,''))) filter (where coalesce(b.style_ref, ce.style) ~* 'ipa|pale ale|hazy')::int,
    count(distinct (lower(b.display_name), coalesce(b.brewery_id::text,''))) filter (where coalesce(b.style_ref, ce.style) ~* 'stout|porter|schwarz|dunkel')::int,
    count(distinct (lower(b.display_name), coalesce(b.brewery_id::text,''))) filter (where coalesce(b.style_ref, ce.style) ~* 'wheat|wit|hefe|weizen|weiss')::int,
    count(distinct (lower(b.display_name), coalesce(b.brewery_id::text,''))) filter (where coalesce(b.style_ref, ce.style) ~* 'sour|lambic|gose|berliner|kriek')::int,
    count(distinct (lower(b.display_name), coalesce(b.brewery_id::text,''))) filter (where coalesce(b.style_ref, ce.style) ~* 'saison|dubbel|tripel|quad|abbey|belgian')::int,
    count(distinct (lower(b.display_name), coalesce(b.brewery_id::text,''))) filter (where coalesce(b.style_ref, ce.style) ~* 'pils|lager|helles|k(ö|o)lsch')::int
  into s_pours, s_beers, s_styles, s_countries, s_states, s_brew, s_cont, s_seas, s_nolow,
       s_hoppy, s_dark, s_wheat, s_sour, s_belg, s_crisp
  from public.checkin_event ce
  left join public.beer_catalog b on b.id = ce.beer_id
  left join public.brewery br on br.id = coalesce(ce.brewery_id, b.brewery_id)
  left join public.venue v on v.id = ce.venue_id
  where ce.user_id = p_user and ce.moderation_status = 'visible';

  select coalesce(jsonb_agg(t), '[]'::jsonb) into styles from (
    select nullif(ce.style, '') as style, count(*)::int as pours
    from public.checkin_event ce
    where ce.user_id = p_user and nullif(ce.style, '') is not null and ce.moderation_status = 'visible'
    group by 1 order by 2 desc, 1 limit 3
  ) t;

  select to_jsonb(fb) into fav from (
    select coalesce(nullif(b.display_name, ''), b.name) as name, brz.name as brewery,
           coalesce(b.cutout_url, b.label_image_url) as image_url, count(*)::int as pours
    from public.checkin_event ce
    join public.beer_catalog b on b.id = ce.beer_id
    left join public.brewery brz on brz.id = b.brewery_id
    where ce.user_id = p_user and ce.moderation_status = 'visible'
    group by b.display_name, b.name, brz.name, coalesce(b.cutout_url, b.label_image_url)
    order by count(*) desc, max(ce.rating) desc nulls last, max(ce.event_ts) desc limit 1
  ) fb;

  return jsonb_build_object(
    'user_id', prof.id, 'display_name', prof.display_name, 'handle', prof.handle,
    'avatar_url', prof.avatar_url, 'region', prof.region_code, 'member_since', prof.created_at,
    'is_self', me = p_user,
    'is_following', exists (select 1 from public.follow f where f.follower_id = me and f.followee_id = p_user),
    'visible', true, 'blocked', false,
    'followers', (select count(*) from public.follow f where f.followee_id = p_user),
    'following', (select count(*) from public.follow f where f.follower_id = p_user),
    'pours', coalesce(s_pours, 0), 'beers_count', coalesce(s_beers, 0),
    'styles_count', coalesce(s_styles, 0), 'countries', coalesce(s_countries, 0), 'states', coalesce(s_states, 0),
    'breweries', coalesce(s_brew,0), 'continents', coalesce(s_cont,0), 'seasons', coalesce(s_seas,0),
    'no_low', coalesce(s_nolow,0), 'hoppy', coalesce(s_hoppy,0), 'dark', coalesce(s_dark,0),
    'wheat', coalesce(s_wheat,0), 'sour', coalesce(s_sour,0), 'belgian', coalesce(s_belg,0), 'crisp', coalesce(s_crisp,0),
    'style_families', coalesce((s_hoppy>0)::int + (s_dark>0)::int + (s_wheat>0)::int + (s_sour>0)::int + (s_belg>0)::int + (s_crisp>0)::int, 0),
    'top_styles', coalesce(styles, '[]'::jsonb), 'favorite_beer', fav
  );
end;
$function$;
