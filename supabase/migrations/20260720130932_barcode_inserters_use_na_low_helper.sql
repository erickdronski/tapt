-- Mirror the live 2026-07-20 patch so a clean migration replay preserves the
-- shared No/Low classifier in both barcode insertion paths.
do $migration$
declare
  definition text;
  function_name text;
  seen integer := 0;
begin
  for function_name, definition in
    select p.proname, pg_get_functiondef(p.oid)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('add_beer_from_barcode', 'add_verified_beer_from_barcode')
  loop
    seen := seen + 1;
    if definition like '%public.tapt_is_na_low(p_name, p_abv)%' then
      continue;
    end if;
    if definition not like '%coalesce(p_abv, 100) <= 0.5%' then
      raise exception 'expected the legacy No/Low assignment in %, refusing to patch blind', function_name;
    end if;
    definition := replace(
      definition,
      'coalesce(p_abv, 100) <= 0.5',
      'public.tapt_is_na_low(p_name, p_abv)'
    );
    execute definition;
  end loop;
  if seen <> 2 then
    raise exception 'expected both barcode insertion functions, found %', seen;
  end if;
end
$migration$;
