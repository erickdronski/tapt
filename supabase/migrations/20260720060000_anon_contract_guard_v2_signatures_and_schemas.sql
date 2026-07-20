-- Harden the anon-contract guard added a few hours earlier in
-- 20260720050000. An adversarial review found four ways to walk straight past
-- it, all of them real:
--
-- (a) OVERLOAD COLLAPSE. v1 returned p.proname only, and the CI diff is a set
--     comparison on those names. So `create function public.beer_detail(text,
--     text)` -- a brand new function, any body, anon-callable by the default
--     PUBLIC grant -- collapses onto the already-allowed name "beer_detail" and
--     CI prints OK. Keying on the identity signature closes it.
-- (b) SCHEMA BLIND SPOT. v1 filtered nspname = 'public', but PostgREST on this
--     project exposes `public,graphql_public`. Anything anon-callable in
--     graphql_public was invisible to the guard. Both exposed schemas are now
--     covered, and the schema is part of the key so a future exposed schema
--     shows up as a diff rather than silently widening the surface.
-- (c) and (d) are fixed outside SQL: the workflow now runs on a nightly
--     schedule (prod SQL here is applied out of band, so push-only triggers can
--     miss a change for days), and the check hard-fails instead of skipping when
--     it runs on main without a key.
--
-- Also cleaned up here: beer_market_one, tapt_scan_name and tapt_trusted_country
-- each still carried a bare PUBLIC `=X` entry alongside their intended anon
-- grant. No privilege escalation, since all three are meant to be anon-callable,
-- but it means a future `revoke execute ... from anon` on them would be a silent
-- no-op -- exactly the 0081 gotcha. Revoked so the explicit grant is the only
-- thing granting access.
revoke all on function public.beer_market_one(uuid) from public;
revoke all on function public.tapt_scan_name(text) from public;
revoke all on function public.tapt_trusted_country(text, jsonb) from public;

-- Restore the intended explicit grants (revoke all also strips the named roles).
grant execute on function public.beer_market_one(uuid) to anon, authenticated, service_role;
grant execute on function public.tapt_scan_name(text) to anon, authenticated, service_role;
grant execute on function public.tapt_trusted_country(text, jsonb) to anon, authenticated, service_role;

-- v2: schema-qualified, signature-keyed, across every PostgREST-exposed schema.
create or replace function public.anon_rpc_contract()
returns setof text
language sql
stable
security definer
set search_path to 'public'
as $function$
  select n.nspname || '.' || p.proname
         || '(' || pg_get_function_identity_arguments(p.oid) || ')'
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname in ('public', 'graphql_public')
    and has_function_privilege('anon', p.oid, 'execute')
    and not exists (
      select 1 from pg_depend d
      where d.objid = p.oid
        and d.classid = 'pg_proc'::regclass
        and d.deptype = 'e'
    )
  order by 1;
$function$;

comment on function public.anon_rpc_contract() is
  'Live, signature-keyed list of functions the anon role can execute in every PostgREST-exposed schema. CI diffs this against supabase/anon_rpc_contract.json. Signature-keyed so a new overload of an allowed name cannot hide; schema-qualified so a newly exposed schema shows as a diff. service_role only.';

revoke all on function public.anon_rpc_contract() from public;
grant execute on function public.anon_rpc_contract() to service_role;
