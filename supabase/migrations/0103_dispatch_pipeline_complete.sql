-- 0103_dispatch_pipeline_complete.sql
-- Finish wiring the Tapt Dispatch so it runs end to end with no manual steps:
--   1. Lock down dispatch_issue (anon currently has full DML, including TRUNCATE).
--   2. Public read paths for the archive and a single hosted issue (anon RPCs).
--   3. A service-role publish RPC so the weekly send archives each issue atomically.
--   4. A vault-backed cron authorization check, so the weekly send authorizes itself
--      from the same secret the cron already reads, with no separate env var to match.

-- 1) LOCKDOWN ---------------------------------------------------------------
-- dispatch_issue must never be writable (or directly readable) by app clients.
-- Reads go through SECURITY DEFINER RPCs; writes happen through the service role.
revoke all on table public.dispatch_issue from anon, authenticated;
revoke all on table public.dispatch_issue from public;
alter table public.dispatch_issue enable row level security;
-- No policies on purpose: with RLS on and no policy, anon/authenticated get nothing
-- directly. The service role bypasses RLS for the publish path.

-- unique slug so the weekly publish is idempotent (re-running a week updates, not dupes)
create unique index if not exists dispatch_issue_slug_key on public.dispatch_issue (slug);

-- 2) PUBLIC READ: ARCHIVE + SINGLE ISSUE -----------------------------------
-- Archive already exists and is safe (published metadata only); open it to anon.
grant execute on function public.dispatch_archive(integer) to anon;

-- One published issue's full content, for the hosted issue page. Published only.
create or replace function public.dispatch_issue_public(p_slug text default null, p_number integer default null)
returns table(issue_number integer, slug text, title text, subtitle text, content jsonb, published_at timestamptz)
language sql
stable
security definer
set search_path to 'public'
as $function$
  select issue_number, slug, title, subtitle, content, published_at
  from public.dispatch_issue
  where status = 'published'
    and ( (p_slug is not null and slug = p_slug)
       or (p_number is not null and issue_number = p_number) )
  order by issue_number desc
  limit 1;
$function$;
revoke all on function public.dispatch_issue_public(text, integer) from public;
grant execute on function public.dispatch_issue_public(text, integer) to anon, authenticated;

-- 3) PUBLISH (service role only): archive an issue idempotently by slug.
create or replace function public.dispatch_publish_issue(p_slug text, p_title text, p_subtitle text, p_content jsonb)
returns integer
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_num integer;
begin
  insert into public.dispatch_issue (issue_number, slug, title, subtitle, status, content, published_at)
  values (coalesce((select max(issue_number) from public.dispatch_issue), 0) + 1,
          p_slug, p_title, p_subtitle, 'published', p_content, now())
  on conflict (slug) do update
    set title = excluded.title,
        subtitle = excluded.subtitle,
        content = excluded.content,
        status = 'published',
        published_at = coalesce(public.dispatch_issue.published_at, now())
  returning issue_number into v_num;
  return v_num;
end;
$function$;
revoke all on function public.dispatch_publish_issue(text, text, text, jsonb) from public, anon, authenticated;
grant execute on function public.dispatch_publish_issue(text, text, text, jsonb) to service_role;

-- 4) CRON AUTH FROM VAULT ---------------------------------------------------
-- The weekly cron already sends x-cron-secret from vault secret 'dispatch_cron_secret'.
-- Let the edge function authorize by comparing against that same vault secret, so
-- there is no separate CRON_SECRET env var that must be kept in sync by hand.
create or replace function public.dispatch_cron_ok(p_secret text)
returns boolean
language sql
stable
security definer
set search_path to 'public', 'vault'
as $function$
  select exists(
    select 1 from vault.decrypted_secrets
    where name = 'dispatch_cron_secret' and decrypted_secret = p_secret
  );
$function$;
revoke all on function public.dispatch_cron_ok(text) from public, anon, authenticated;
grant execute on function public.dispatch_cron_ok(text) to service_role;
