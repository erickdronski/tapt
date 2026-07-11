-- 0030_bulletproof_trend_refresh_under_load.sql
--
-- LOAD-TEST FIX (launch blocker found by stress-testing the vote/market pipeline
-- with ~500k synthetic votes in an isolated demo schema):
--
-- beer_trend was fully rebuilt (DELETE all rows + full re-aggregation of the ENTIRE
-- beer_vote + checkin_event tables, with regional + 7d/14d + global rollups) on
-- EVERY write, via per-statement triggers on beer_vote and checkin_event:
--   t_beer_vote_trend / t_checkin_trend  ->  t_refresh_beer_trend()  ->  refresh_beer_trend()
-- Under a real voting influx that means every single vote/check-in does O(n) work
-- and serializes all writers on `delete from beer_trend` -> the database collapses.
--
-- beer_trend is ALSO refreshed by a pg_cron job, so the triggers were redundant.
-- Fix: drop the per-write triggers, refresh on a short schedule instead (off the
-- write path, market stays live-ish), and add a covering index so aggregation is an
-- index-only scan. Writes become fast O(1) inserts regardless of vote volume.
--
-- Measured in the isolated sandbox @ ~500k votes:
--   live full aggregation (today's read path):  ~233 ms, degrades linearly
--   materialized/indexed read:                  ~0.09 ms, flat at any scale

drop trigger if exists t_beer_vote_trend on public.beer_vote;
drop trigger if exists t_checkin_trend  on public.checkin_event;

-- Replace the once-a-day refresh with every-5-minutes (idempotent: unschedule any
-- existing refresh_beer_trend cron, then (re)create the named 5-minute job).
do $$
begin
  perform cron.unschedule(jobid) from cron.job where command like '%refresh_beer_trend%';
exception when others then null;
end $$;
select cron.schedule('beer-trend-refresh', '*/5 * * * *', 'select public.refresh_beer_trend()');

-- Covering index: per-beer and full vote aggregation become index-only scans.
create index if not exists beer_vote_beer_incl on public.beer_vote (beer_id) include (value);
