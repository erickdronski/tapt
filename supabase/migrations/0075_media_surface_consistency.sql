-- 0075_media_surface_consistency.sql
-- Prefer reviewed background-removed product images across every public beer
-- surface and expose a privacy-safe distinct-beer total for Passport profiles.

create or replace function public.catalog_search(
  p_query text default null,
  p_style text default null,
  p_na_only boolean default false,
  p_limit integer default 30,
  p_offset integer default 0
)
returns table (
  id uuid,
  name text,
  style text,
  abv numeric,
  is_na_low boolean,
  brewery_name text,
  country text,
  image_url text,
  total bigint
)
language sql
stable
security definer
set search_path = public
as $$
  with candidates as (
    select
      bc.id,
      bc.display_name as name,
      bc.style,
      bc.abv,
      bc.is_na_low,
      b.name as brewery_name,
      b.country,
      coalesce(bc.cutout_url, bc.label_image_url) as image_url,
      row_number() over (
        partition by
          lower(bc.display_name),
          coalesce(bc.brewery_id::text, lower(b.name), '')
        order by
          (bc.cutout_url is not null) desc,
          (bc.label_image_url is not null) desc,
          (bc.abv is not null) desc,
          (nullif(bc.style, '') is not null) desc,
          bc.updated_at desc,
          bc.id
      ) as package_rank
    from public.beer_catalog bc
    left join public.brewery b on b.id = bc.brewery_id
    where bc.name_ok
      and (
        p_query is null
        or btrim(p_query) = ''
        or bc.display_name ilike '%' || p_query || '%'
        or bc.name ilike '%' || p_query || '%'
        or b.name ilike '%' || p_query || '%'
      )
      and (p_style is null or btrim(p_style) = '' or bc.style ilike '%' || p_style || '%')
      and (not coalesce(p_na_only, false) or bc.is_na_low)
  ),
  canonical as (
    select id, name, style, abv, is_na_low, brewery_name, country, image_url
    from candidates
    where package_rank = 1
  )
  select id, name, style, abv, is_na_low, brewery_name, country, image_url,
         count(*) over() as total
  from canonical
  order by
    (image_url is null),
    (brewery_name is null),
    (abv is null),
    (style is null),
    lower(name)
  limit greatest(1, least(coalesce(p_limit, 30), 60))
  offset greatest(0, coalesce(p_offset, 0));
$$;

create or replace function public.beer_of_week_standings(p_limit int default 10)
returns table (
  rank int,
  beer_id uuid,
  name text,
  style text,
  brewery_name text,
  country text,
  label_image_url text,
  week_votes int
)
language sql
stable
security definer
set search_path = public
as $$
  with week_votes as (
    select bv.beer_id as wb_id, coalesce(sum(bv.value), 0)::int as votes
    from public.beer_vote bv
    where coalesce(bv.updated_at, bv.created_at) >= date_trunc('week', now())
    group by bv.beer_id
  )
  select
    (row_number() over (
      order by wv.votes desc, coalesce(nullif(b.display_name, ''), b.name)
    ))::int,
    b.id, coalesce(nullif(b.display_name, ''), b.name), b.style, br.name, br.country,
    coalesce(b.cutout_url, b.label_image_url),
    wv.votes
  from week_votes wv
  join public.beer_catalog b on b.id = wv.wb_id
  left join public.brewery br on br.id = b.brewery_id
  where wv.votes > 0
  order by wv.votes desc, coalesce(nullif(b.display_name, ''), b.name)
  limit least(greatest(coalesce(p_limit, 10), 1), 25);
$$;

create or replace function public.beer_of_week_latest_winner()
returns table (
  week_start date,
  beer_id uuid,
  name text,
  style text,
  brewery_name text,
  country text,
  label_image_url text,
  week_votes int
)
language sql
stable
security definer
set search_path = public
as $$
  select w.week_start, b.id, coalesce(nullif(b.display_name, ''), b.name), b.style, br.name, br.country,
         coalesce(b.cutout_url, b.label_image_url), w.week_votes
  from public.beer_of_week_winner w
  join public.beer_catalog b on b.id = w.beer_id
  left join public.brewery br on br.id = b.brewery_id
  order by w.week_start desc
  limit 1;
$$;

create or replace function public.build_dispatch_content()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with wk as (
    select (extract(isoyear from now())::int * 100 + extract(week from now())::int)::text as w
  ),
  featured as (
    select bc.id, coalesce(nullif(bc.display_name, ''), bc.name) as name, bc.style, bc.abv,
           coalesce(bc.cutout_url, bc.label_image_url) as image,
           br.name as brewery, br.country
    from public.beer_catalog bc
    join public.brewery br on br.id = bc.brewery_id
    cross join wk
    where coalesce(bc.cutout_url, bc.label_image_url) is not null
      and bc.abv is not null and nullif(bc.style, '') is not null
      and bc.name_ok
      and bc.display_name ~ '^[A-Za-z]' and length(bc.display_name) between 4 and 34
    order by md5(bc.id::text || wk.w)
    limit 1
  ),
  style as (
    select style_name, style_family, description, abv_min, abv_max,
           ibu_min, ibu_max, source_url
    from public.beer_style_reference, wk
    where nullif(description, '') is not null
    order by md5(id::text || wk.w)
    limit 1
  )
  select jsonb_build_object(
    'week', (select w from wk),
    'featured', (select row_to_json(f) from featured f),
    'style', (select row_to_json(s) from style s),
    'stats', jsonb_build_object(
      'beers', (select count(*) from public.beer_catalog),
      'breweries', (select count(*) from public.brewery),
      'venues', (select count(*) from public.venue),
      'styles', (select count(*) from public.beer_style_reference),
      'countries', (select count(distinct country) from public.brewery where country is not null)
    )
  );
$$;

create or replace function public.public_profile(p_user uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  prof record;
  is_blocked boolean;
  fav jsonb;
  styles jsonb;
  s_pours int;
  s_beers int;
  s_styles int;
  s_countries int;
  s_states int;
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
    select 1
    from public.user_block ub
    where (ub.blocker_id = me and ub.blocked_id = p_user)
       or (ub.blocker_id = p_user and ub.blocked_id = me)
  );

  if is_blocked or (not prof.social_visible and me <> p_user) then
    return jsonb_build_object(
      'user_id', prof.id,
      'display_name', prof.display_name,
      'handle', prof.handle,
      'avatar_url', prof.avatar_url,
      'region', prof.region_code,
      'member_since', prof.created_at,
      'is_self', me = p_user,
      'is_following', false,
      'visible', false,
      'blocked', is_blocked,
      'followers', 0,
      'following', 0
    );
  end if;

  select
    count(*)::int,
    (count(distinct (
      lower(b.display_name),
      coalesce(b.brewery_id::text, '')
    )) filter (where b.id is not null))::int,
    count(distinct nullif(ce.style, ''))::int,
    count(distinct br.country) filter (where coalesce(br.country, '') <> '')::int,
    count(distinct (v.external_ids->>'region')) filter (
      where lower(coalesce(v.external_ids->>'country', '')) in
        ('united states', 'united states of america', 'usa', 'us')
    )::int
  into s_pours, s_beers, s_styles, s_countries, s_states
  from public.checkin_event ce
  left join public.beer_catalog b on b.id = ce.beer_id
  left join public.brewery br on br.id = coalesce(ce.brewery_id, b.brewery_id)
  left join public.venue v on v.id = ce.venue_id
  where ce.user_id = p_user and ce.moderation_status = 'visible';

  select coalesce(jsonb_agg(t), '[]'::jsonb)
  into styles
  from (
    select nullif(ce.style, '') as style, count(*)::int as pours
    from public.checkin_event ce
    where ce.user_id = p_user
      and nullif(ce.style, '') is not null
      and ce.moderation_status = 'visible'
    group by 1
    order by 2 desc, 1
    limit 3
  ) t;

  select to_jsonb(fb)
  into fav
  from (
    select coalesce(nullif(b.display_name, ''), b.name) as name,
           brz.name as brewery,
           coalesce(b.cutout_url, b.label_image_url) as image_url,
           count(*)::int as pours
    from public.checkin_event ce
    join public.beer_catalog b on b.id = ce.beer_id
    left join public.brewery brz on brz.id = b.brewery_id
    where ce.user_id = p_user and ce.moderation_status = 'visible'
    group by b.display_name, b.name, brz.name, coalesce(b.cutout_url, b.label_image_url)
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
    'is_following', exists (
      select 1 from public.follow f
      where f.follower_id = me and f.followee_id = p_user
    ),
    'visible', true,
    'blocked', false,
    'followers', (select count(*) from public.follow f where f.followee_id = p_user),
    'following', (select count(*) from public.follow f where f.follower_id = p_user),
    'pours', coalesce(s_pours, 0),
    'beers_count', coalesce(s_beers, 0),
    'styles_count', coalesce(s_styles, 0),
    'countries', coalesce(s_countries, 0),
    'states', coalesce(s_states, 0),
    'top_styles', coalesce(styles, '[]'::jsonb),
    'favorite_beer', fav
  );
end;
$$;

revoke all on function public.beer_of_week_standings(integer)
  from public, anon, authenticated;
revoke all on function public.beer_of_week_latest_winner()
  from public, anon, authenticated;
revoke all on function public.build_dispatch_content()
  from public, anon, authenticated;
revoke all on function public.public_profile(uuid)
  from public, anon, authenticated;
revoke all on function public.catalog_search(text, text, boolean, integer, integer)
  from public, anon, authenticated;

grant execute on function public.beer_of_week_standings(integer)
  to authenticated;
grant execute on function public.beer_of_week_latest_winner()
  to authenticated;
grant execute on function public.build_dispatch_content()
  to service_role;
grant execute on function public.public_profile(uuid)
  to authenticated;
grant execute on function public.catalog_search(text, text, boolean, integer, integer)
  to anon, authenticated;
