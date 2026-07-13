-- The Explore region picker was offering 50 US states, but boards are keyed by
-- country in beer_trend_feed, so every US-state chip was a permanent dead-end
-- that always fell back to Global. This returns the regions that actually have a
-- board (country-level, with a beer count) so the picker can offer only real
-- destinations, ordered by size. Global is added by the client.
create or replace function public.beer_board_regions()
returns table(region text, beers bigint)
language sql
stable
security definer
set search_path = public
as $$
  select region, count(*)::bigint as beers
  from public.beer_trend_feed
  where region is not null and region <> 'Global'
  group by region
  order by count(*) desc, region
$$;

revoke all on function public.beer_board_regions() from public;
grant execute on function public.beer_board_regions() to anon, authenticated;
