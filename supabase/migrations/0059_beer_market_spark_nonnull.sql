-- Fix: the 0058 spark array returned NULLs for days with no snapshot yet (only
-- today has one at launch), which the app's [Double] decoder rejects -> the whole
-- board failed to decode -> "Couldn't load the board" (verified in the signed-in
-- simulator). Coalesce missing days to the beer's current standing (a flat line
-- until real daily history accrues) so there are no nulls, and order the sparkline
-- oldest -> newest so it reads left to right. Function body otherwise identical to 0058.
create or replace function public.beer_market(
  p_sort text default 'movers',
  p_limit integer default 40,
  p_demo boolean default false
)
returns table(
  beer_id uuid, symbol text, name text, brewery text, style text, country text,
  image_url text, net integer, votes integer, change integer, volume integer,
  ups integer, downs integer, spark double precision[], reason text,
  season_fit integer, heat integer
)
language sql
stable
security definer
set search_path = public
as $$
  with ranked as (
    select distinct on (public.tapt_display_name(b.name))
      st.beer_id,
      public.tapt_display_name(b.name) bname,
      br.name brewery,
      coalesce(nullif(b.style,''), 'Beer') style,
      br.country,
      coalesce(b.cutout_url, b.label_image_url) img,
      st.standing, st.net_votes, st.votes_count, st.ups, st.downs, st.vol24,
      st.change_24h, st.reason, st.season_fit, st.heat,
      abs(('x' || substr(md5(st.beer_id::text), 1, 8))::bit(32)::int % 20) as rot
    from public.beer_market_standing st
    join public.beer_catalog b on b.id = st.beer_id
    left join public.brewery br on br.id = b.brewery_id
    where public.tapt_name_ok(b.name)
    order by public.tapt_display_name(b.name), st.standing desc
  )
  select r.beer_id,
    upper(left(regexp_replace(r.bname, '[^A-Za-z0-9]', '', 'g'), 4)) symbol,
    r.bname, r.brewery, r.style, r.country, r.img,
    r.standing net, r.votes_count votes, r.change_24h change, r.vol24 volume,
    r.ups, r.downs,
    coalesce(
      (select array_agg(coalesce(sn.standing, r.standing)::float8 order by d.d desc)
       from generate_series(6, 0, -1) d(d)
       left join public.beer_market_snapshot sn
         on sn.beer_id = r.beer_id and sn.snap_date = current_date - d.d),
      array[r.standing::float8]
    ) spark,
    r.reason, r.season_fit, r.heat
  from ranked r
  order by case p_sort
      when 'gainers' then r.change_24h
      when 'losers'  then -r.change_24h
      when 'active'  then r.vol24
      when 'top'     then r.net_votes
      when 'season'  then r.season_fit * 1000 + r.standing
      when 'movers'  then r.standing
      else r.standing
    end desc,
    r.standing desc, r.rot desc, r.bname
  limit least(greatest(coalesce(p_limit, 40), 1), 100);
$$;

revoke all on function public.beer_market(text, integer, boolean) from public, anon, authenticated;
grant execute on function public.beer_market(text, integer, boolean) to authenticated;
