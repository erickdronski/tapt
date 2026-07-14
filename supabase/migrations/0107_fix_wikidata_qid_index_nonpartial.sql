-- The QID dedup index from 0105 was PARTIAL (where external_ids ? 'wikidata_qid'),
-- but the ingest lookup doesn't carry that predicate, so the planner ignored it and
-- seq-scanned the whole catalog every row -> statement timeout (opaque HTTP 500) once
-- the catalog passed ~18K. Replace it with a plain expression index the lookup uses.
drop index if exists public.idx_beer_catalog_wikidata_qid;
create index if not exists idx_beer_catalog_wikidata_qid
  on public.beer_catalog ((external_ids->>'wikidata_qid'));
analyze public.beer_catalog;
