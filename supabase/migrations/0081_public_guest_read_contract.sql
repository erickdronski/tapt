-- 0081_public_guest_read_contract.sql
-- Guest mode promises catalog detail, Beer of the Week, and Beer Radar reads.
-- Keep those read-only RPCs public while every mutation remains authenticated.

revoke all on function public.beer_detail(uuid) from public;
revoke all on function public.beer_of_week_standings(integer) from public;
revoke all on function public.beer_of_week_latest_winner() from public;
revoke all on function public.brewery_map_feed(integer) from public;
revoke all on function public.brewery_map_feed_near(numeric, numeric, integer, integer) from public;

grant execute on function public.beer_detail(uuid)
  to anon, authenticated, service_role;
grant execute on function public.beer_of_week_standings(integer)
  to anon, authenticated, service_role;
grant execute on function public.beer_of_week_latest_winner()
  to anon, authenticated, service_role;
grant execute on function public.brewery_map_feed(integer)
  to anon, authenticated, service_role;
grant execute on function public.brewery_map_feed_near(numeric, numeric, integer, integer)
  to anon, authenticated, service_role;
