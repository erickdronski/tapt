-- 0078_advisor_cleanup.sql
-- Resolve actionable post-migration advisor findings without moving or
-- modifying Supabase-managed extension objects.

alter function public.tapt_display_name(text) set search_path = '';
alter function public.tapt_name_ok(text) set search_path = '';

-- PostGIS estimation helpers are not part of Tapt's client API.
revoke execute on function public.st_estimatedextent(text, text)
  from public, anon, authenticated;
revoke execute on function public.st_estimatedextent(text, text, text)
  from public, anon, authenticated;
revoke execute on function public.st_estimatedextent(text, text, text, boolean)
  from public, anon, authenticated;

create index if not exists demo_beer_vote_beer_id_idx
  on demo.beer_vote (beer_id);
create index if not exists demo_beer_vote_voter_id_idx
  on demo.beer_vote (voter_id);
