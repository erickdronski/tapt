-- 0084_restore_name_function_search_path.sql
-- 0083 replaced these helpers and cleared the hardened function setting.

alter function public.tapt_display_name(text) set search_path = pg_catalog;
alter function public.tapt_name_ok(text) set search_path = pg_catalog;

do $$
begin
  if not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'tapt_display_name'
      and 'search_path=pg_catalog' = any(coalesce(p.proconfig, array[]::text[]))
  ) then
    raise exception 'tapt_display_name search_path was not hardened';
  end if;

  if not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'tapt_name_ok'
      and 'search_path=pg_catalog' = any(coalesce(p.proconfig, array[]::text[]))
  ) then
    raise exception 'tapt_name_ok search_path was not hardened';
  end if;
end $$;

notify pgrst, 'reload schema';
