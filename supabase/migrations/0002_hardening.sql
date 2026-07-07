-- 0002_hardening.sql -- security-advisor hardening (applied 2026-07-07)

-- Pin the trigger function's search_path (was mutable).
alter function public.set_updated_at() set search_path = '';

-- Internal-only functions must not be callable via the public REST RPC surface.
revoke execute on function public.handle_new_user() from public, anon, authenticated;
revoke execute on function public.taste_sale_eligible(uuid) from public, anon, authenticated;
grant execute on function public.taste_sale_eligible(uuid) to service_role;

-- NOTE (accepted, not applied): public.spatial_ref_sys (PostGIS reference table) reports an
-- RLS-disabled lint. It is extension-owned (ALTER fails with "must be owner of table") and holds
-- only world-public SRID reference data (no user data), so it is intentionally left as-is.
