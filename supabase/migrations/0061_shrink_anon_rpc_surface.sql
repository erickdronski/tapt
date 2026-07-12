-- 0061  Shrink the anonymous RPC surface before scale.
-- The public web (taptbeer.com) calls exactly: catalog_search, venue_brand,
-- venue_events, venue_menu (+ two edge functions). Every other SECURITY DEFINER
-- function loses anon execute; the signed-in app keeps access via authenticated.
-- Verified after apply: catalog_search anon=200, leaderboard_beers/beer_market anon=401.
do $$
declare
  fn text;
  r record;
begin
  foreach fn in array array[
    'beer_detail','beer_of_week_latest_winner','beer_of_week_standings',
    'beer_style_science','brewery_map_feed','brewery_map_feed_near',
    'dispatch_archive','dispatch_issue_by_slug',
    'leaderboard_beers','leaderboard_beers_regional','leaderboard_styles',
    'platform_stats','search_venues','tonight_feed'
  ] loop
    for r in
      select p.oid::regprocedure as sig
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = fn
    loop
      execute format('revoke execute on function %s from anon', r.sig);
    end loop;
  end loop;
end $$;
