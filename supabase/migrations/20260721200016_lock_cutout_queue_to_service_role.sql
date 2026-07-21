-- cutout_queue is an internal media-factory surface. Its only consumer is the
-- service-key GitHub Action, so client roles must not be able to enumerate it.
alter view public.cutout_queue set (security_invoker = true);
revoke all privileges on table public.cutout_queue from public, anon, authenticated;
grant select on table public.cutout_queue to service_role;

-- Fix the remaining mutable helper search paths reported by the database
-- security advisor. The explicit path keeps built-ins ahead of public objects.
alter function public.tapt_season_points(text, date)
  set search_path = pg_catalog, public;
alter function public.tapt_period_start(text, timestamptz)
  set search_path = pg_catalog, public;
alter function public.tapt_period_prev_start(text, timestamptz)
  set search_path = pg_catalog, public;
alter function public.tapt_period_label(text, date)
  set search_path = pg_catalog, public;
