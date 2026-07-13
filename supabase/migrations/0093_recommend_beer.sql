-- 0093  "Picked for you": recommend ONE beer the user has not had, that fits
-- their real taste, leaning slightly novel. Everything is derived from real
-- signals; the "why" reason states only true attributes (never a made-up score).
--
-- Signal sources (all real):
--   taste_vector.top_styles      onboarding + learned favorite styles
--   beer_vote (value > 0)        beers they thumbed up  -> their styles
--   checkin_event (rating >= 4)  beers they poured and rated high -> their styles
-- Exclusions: any beer they have logged or voted on, by id AND by display name
-- (so a different SKU of the same beer never gets recommended back).
-- Candidates must be name_ok, have an image, and resolve to a real BJCP style.

create or replace function public.recommend_beer(p_user uuid)
returns table(
  beer_id uuid, name text, brewery text, style text, country text,
  image_url text, abv numeric, reason text, match_kind text
)
language sql
stable
security definer
set search_path = public
as $$
  with
  -- 1. styles the user has shown they like (resolved BJCP names)
  liked as (
    select tv.s as style_name, 3 as weight
    from public.taste_vector t, unnest(t.top_styles) tv(s)
    where t.user_id = p_user
    union all
    select b.style_ref, 2
    from public.beer_vote v
    join public.beer_catalog b on b.id = v.beer_id
    where v.user_id = p_user and v.value > 0 and b.style_ref is not null
    union all
    select b.style_ref, 2
    from public.checkin_event c
    join public.beer_catalog b on b.id = c.beer_id
    where c.user_id = p_user and c.rating >= 4 and b.style_ref is not null
  ),
  style_affinity as (
    select style_name, sum(weight)::int as score
    from liked where coalesce(style_name,'') <> ''
    group by style_name
  ),
  -- families of the liked styles, for "adjacent but new" picks
  family_affinity as (
    select distinct sr.style_family
    from style_affinity a
    join public.beer_style_reference sr on sr.style_name = a.style_name
    where sr.style_family is not null
  ),
  -- 2. what to exclude: everything they have already had or judged
  had_ids as (
    select beer_id from public.beer_vote where user_id = p_user
    union select beer_id from public.checkin_event where user_id = p_user and beer_id is not null
  ),
  had_names as (
    select distinct lower(coalesce(nullif(b.display_name,''), b.name)) as dn
    from had_ids h join public.beer_catalog b on b.id = h.beer_id
  ),
  -- only recommend when there is real signal to personalize on
  signal as (select (select count(*) from style_affinity) as styles),
  -- 3. score the candidate pool
  scored as (
    select
      b.id,
      coalesce(nullif(b.display_name,''), b.name) as dname,
      br.name as brewery,
      b.style_ref as style,
      public.tapt_trusted_country(br.country, br.external_ids) as country,
      coalesce(b.cutout_url, b.label_image_url) as image_url,
      b.abv,
      sr.style_family,
      -- exact loved style is a strong match; same family but a different style
      -- is the interesting, slightly-novel pick
      case
        when exists (select 1 from style_affinity a where a.style_name = b.style_ref) then 'love'
        when sr.style_family in (select style_family from family_affinity) then 'adjacent'
        else 'wildcard'
      end as match_kind,
      (case
         when exists (select 1 from style_affinity a where a.style_name = b.style_ref) then 100
         when sr.style_family in (select style_family from family_affinity) then 70
         else 20
       end)
      + (case when exists (select 1 from public.beer_award aw where aw.beer_id = b.id) then 25 else 0 end)
      + (case when b.cutout_url is not null then 10 else 0 end)
      -- small stable daily jitter so it is not the same beer every open
      + (abs(('x'||substr(md5(b.id::text || current_date::text),1,6))::bit(24)::int) % 12) as score
    from public.beer_catalog b
    join public.beer_style_reference sr on sr.style_name = b.style_ref
    left join public.brewery br on br.id = b.brewery_id
    where b.name_ok
      and b.style_ref is not null
      and coalesce(b.cutout_url, b.label_image_url) is not null
      and (select styles from signal) > 0
      and b.id not in (select beer_id from had_ids)
      and lower(coalesce(nullif(b.display_name,''), b.name)) not in (select dn from had_names)
  ),
  pick as (
    select * from scored order by score desc, dname limit 1
  )
  select
    p.id, p.dname, p.brewery, p.style, p.country, p.image_url, p.abv,
    -- honest reason from real attributes only
    case p.match_kind
      when 'love' then
        'Right in your wheelhouse: a ' || p.style
          || coalesce(' from ' || p.brewery, '') || '.'
      when 'adjacent' then
        'You lean into ' || p.style_family || '. This ' || p.style
          || ' is a fresh angle on the same family.'
      else
        'A well-regarded ' || p.style || coalesce(' from ' || p.brewery, '')
          || ' worth a try.'
    end as reason,
    p.match_kind
  from pick p;
$$;

revoke all on function public.recommend_beer(uuid) from public, anon;
grant execute on function public.recommend_beer(uuid) to authenticated;
