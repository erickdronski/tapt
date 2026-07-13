-- One beer's live market standing + 7-day sparkline, for the unified beer profile.
-- Mirrors beer_market_v2's field mapping and spark aggregation exactly, but keyed
-- to a single beer_id. Separate from beer_detail on purpose: keeps Codex's anon
-- beer_detail contract untouched and avoids the clobber history. Public profile is
-- anon-readable, so this is granted to anon + authenticated. Aggregate, non-sensitive.
create or replace function public.beer_market_one(p_beer_id uuid)
returns table(
  beer_id uuid, symbol text, name text, brewery text, style text, country text,
  image_url text, is_na_low boolean, net integer, votes integer, change integer,
  volume integer, ups integer, downs integer, spark double precision[],
  reason text, season_fit integer, heat integer
)
language sql stable security definer
set search_path to 'public'
as $function$
  select
    st.beer_id,
    st.symbol,
    st.display_name,
    st.brewery,
    st.style,
    st.country,
    st.image_url,
    b.is_na_low,
    st.standing,
    st.votes_count,
    st.change_24h,
    st.vol24,
    st.ups,
    st.downs,
    coalesce(
      (select array_agg(sn.standing::float8 order by sn.snap_date)
       from public.beer_market_snapshot sn
       where sn.beer_id = st.beer_id
         and sn.snap_date > current_date - 7),
      array[st.standing::float8]
    ),
    st.reason,
    st.season_fit,
    st.heat
  from public.beer_market_standing st
  join public.beer_catalog b on b.id = st.beer_id
  where st.beer_id = p_beer_id;
$function$;

revoke all on function public.beer_market_one(uuid) from public;
grant execute on function public.beer_market_one(uuid) to anon, authenticated;
