-- 0033_allagash_white_awards.sql
--
-- Awards data integrity + real seed. The beer_award table previously held a single
-- row whose note carried an unverified competition-size figure. On review the CORE
-- claim (Allagash White, World Beer Cup 2026 gold, Belgian-Style Witbier) turned out
-- to be REAL and verifiable, and Allagash White is literally the most-awarded witbier
-- in the world. This migration replaces that single row with the full, verified,
-- cited award record (19 medals) sourced from Allagash Brewing's official award page.
-- Real data only, every row citable. Beer matched by name so this is portable.
--
-- Source of truth:
--   https://www.allagash.com/discover/inside-allagash/most-awarded-witbier-in-the-world/

insert into ingestion_source (id, name, source_kind, license, homepage_url, ingest_cadence, enabled, notes)
values
  ('gabf','Great American Beer Festival results','reference','Competition results are public facts; cite the result publication','https://www.greatamericanbeerfestival.com/','yearly',true,'GABF winner facts (beer, brewery, medal, category, year).'),
  ('european-beer-star','European Beer Star results','reference','Competition results are public facts; cite the result publication','https://www.european-beer-star.com/','yearly',true,'European Beer Star winner facts by style.')
on conflict (id) do nothing;

do $$
declare v_beer uuid;
begin
  select bc.id into v_beer
  from beer_catalog bc join brewery br on br.id = bc.brewery_id
  where bc.name = 'Allagash White' and br.name ilike 'Allagash%'
  limit 1;
  if v_beer is null then
    raise notice 'Allagash White not found in catalog; skipping award seed.';
    return;
  end if;

  delete from beer_award where beer_id = v_beer;

  insert into beer_award (beer_id, award_body, year, category, medal, scope, region, source_id, source_url, note)
  select v_beer, a.award_body, a.year, a.category, a.medal, 'global', a.region,
         case a.award_body when 'World Beer Cup' then 'world-beer-cup'
                           when 'Great American Beer Festival' then 'gabf'
                           when 'European Beer Star' then 'european-beer-star' end,
         'https://www.allagash.com/discover/inside-allagash/most-awarded-witbier-in-the-world/',
         'Verified from Allagash Brewing''s official award record.'
  from (values
    ('World Beer Cup',2026,'Belgian-Style Witbier','gold',null::text),
    ('Great American Beer Festival',2024,'Belgian-Style Witbier','gold','United States'),
    ('Great American Beer Festival',2023,'Belgian-Style Witbier','silver','United States'),
    ('Great American Beer Festival',2022,'Belgian-Style Witbier','gold','United States'),
    ('World Beer Cup',2022,'Belgian-Style Witbier','bronze',null),
    ('European Beer Star',2022,'Belgian-Style Witbier','bronze','Europe'),
    ('Great American Beer Festival',2021,'Belgian-Style Witbier','silver','United States'),
    ('Great American Beer Festival',2020,'Belgian-Style Witbier','gold','United States'),
    ('Great American Beer Festival',2018,'Belgian-Style Witbier','bronze','United States'),
    ('European Beer Star',2017,'Belgian-Style Witbier','gold','Europe'),
    ('Great American Beer Festival',2015,'Belgian-Style Witbier','gold','United States'),
    ('World Beer Cup',2012,'Belgian-Style Witbier','gold',null),
    ('World Beer Cup',2010,'Belgian-Style Witbier','gold',null),
    ('Great American Beer Festival',2010,'Belgian-Style Witbier','bronze','United States'),
    ('Great American Beer Festival',2005,'Belgian-Style Wheat','gold','United States'),
    ('World Beer Cup',2004,'Belgian-Style Wheat','silver',null),
    ('World Beer Cup',2002,'Belgian-Style Wheat','bronze',null),
    ('Great American Beer Festival',2002,'Belgian & French-Style Ale','gold','United States'),
    ('World Beer Cup',1998,'Belgian-Style Wheat','gold',null)
  ) as a(award_body, year, category, medal, region);
end $$;
