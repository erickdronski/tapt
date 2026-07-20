-- Audit fix (0081 gotcha, third recurrence): four helper functions are reachable
-- by the anon role purely through the bare PUBLIC `=X` ACL that Postgres gives
-- every new function. Nobody ever granted anon:
--
--   tapt_period_start(text, timestamptz)
--   tapt_period_prev_start(text, timestamptz)
--   tapt_period_label(text, date)
--   tapt_season_points(text, date)
--
-- tapt_season_points is the tell: it carries an explicit `authenticated=X`
-- grant, so the author clearly meant "signed-in only" and anon slipped in
-- through the default anyway. AGENTS.md and migration 0082 both assert the anon
-- surface is a fixed, reviewed list; these were never on it.
--
-- Nothing calls them from the client (verified: no reference to any of the four
-- in app/ or landing/). They are used inside SECURITY DEFINER functions, which
-- execute as the owner and are unaffected by these grants. So this narrows the
-- anon surface with no functional change.
revoke all on function public.tapt_period_start(text, timestamptz) from public;
revoke all on function public.tapt_period_prev_start(text, timestamptz) from public;
revoke all on function public.tapt_period_label(text, date) from public;
revoke all on function public.tapt_season_points(text, date) from public;

-- Keep the one grant that was deliberate.
grant execute on function public.tapt_season_points(text, date) to authenticated;

-- Owner/service paths keep working regardless; state it explicitly so a future
-- CREATE OR REPLACE that resets the ACL still lands somewhere sane.
grant execute on function public.tapt_period_start(text, timestamptz) to service_role;
grant execute on function public.tapt_period_prev_start(text, timestamptz) to service_role;
grant execute on function public.tapt_period_label(text, date) to service_role;
grant execute on function public.tapt_season_points(text, date) to service_role;
