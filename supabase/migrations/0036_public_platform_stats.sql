-- Single source of truth for the headline counts so the landing/web never drift
-- from the real database (app and web read the same live numbers). Public + cheap.
create or replace function public.platform_stats()
returns jsonb language sql stable security definer set search_path to 'public' as $$
  select jsonb_build_object(
    'beers',     (select count(*) from beer_catalog),
    'breweries', (select count(*) from brewery),
    'venues',    (select count(*) from venue),
    'countries', (select count(distinct country) from brewery where country is not null),
    'styles',    (select count(*) from beer_style_reference)
  );
$$;
grant execute on function public.platform_stats() to anon, authenticated;
