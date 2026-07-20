-- The anon-surface guard, made durable.
--
-- Migration 0082 asserted the anon RPC contract with a one-shot `do $$ ... $$`
-- block. That ran once, at apply time, and can never run again -- so the surface
-- silently drifted from 12 to 24 functions, and the PUBLIC-grant gotcha recurred
-- three separate times (0081, the two helpers added 2026-07-19, and the four
-- period helpers found 2026-07-20). A guard that cannot re-run is not a guard.
--
-- This replaces it with something CI can execute on every push: a function that
-- reports the live anon-executable surface, which scripts/check_anon_rpc_contract.py
-- diffs against the checked-in manifest at supabase/anon_rpc_contract.json.
-- Extension-owned functions (PostGIS, pg_trgm) are excluded: their ACLs cannot be
-- revoked by the migration role and they hold no table access.
--
-- Deliberately service_role-only. It is introspection about the security surface,
-- so it must not itself be part of that surface.
create or replace function public.anon_rpc_contract()
returns setof text
language sql
stable
security definer
set search_path to 'public'
as $function$
  select p.proname
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and has_function_privilege('anon', p.oid, 'execute')
    and not exists (
      select 1 from pg_depend d
      where d.objid = p.oid
        and d.classid = 'pg_proc'::regclass
        and d.deptype = 'e'
    )
  order by p.proname;
$function$;

comment on function public.anon_rpc_contract() is
  'Live list of Tapt-owned functions the anon role can execute. CI diffs this against supabase/anon_rpc_contract.json so the surface cannot drift unnoticed. service_role only.';

revoke all on function public.anon_rpc_contract() from public;
grant execute on function public.anon_rpc_contract() to service_role;
