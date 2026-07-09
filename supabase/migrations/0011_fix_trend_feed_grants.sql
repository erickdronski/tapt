-- 0011_fix_trend_feed_grants.sql
-- Bug fix: beer_trend_feed is a security_invoker view, but 0005 revoked SELECT
-- on the underlying beer_trend table from app roles — so every app query to the
-- market board failed with permission denied (the app silently fell back to
-- guide mode). beer_trend holds only per-beer aggregates (no PII, no user ids),
-- so read access for app roles is safe and intended.
grant select on beer_trend to anon, authenticated;
