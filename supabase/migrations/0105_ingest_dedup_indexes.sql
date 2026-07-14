-- Speed the ingest dedup lookups. As the catalog passed ~18K rows, the per-row
-- name/QID/brewery lookups in admin_ingest_wikidata_beers (and admin_ingest_beers)
-- fell back to sequential scans, so a batch could exceed statement_timeout and 500.
-- These make every lookup index-backed.
create index if not exists idx_brewery_lower_name
  on public.brewery (lower(name));

create index if not exists idx_beer_catalog_lower_name_brewery
  on public.beer_catalog (lower(name), brewery_id);

create index if not exists idx_beer_catalog_wikidata_qid
  on public.beer_catalog ((external_ids->>'wikidata_qid'))
  where external_ids ? 'wikidata_qid';

analyze public.brewery;
analyze public.beer_catalog;
