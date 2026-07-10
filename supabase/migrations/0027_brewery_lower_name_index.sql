-- Speed the admin_ingest_beers brewery find-or-create (case-insensitive name
-- equality) during bulk ingestion of thousands of beers.
create index if not exists brewery_lower_name on public.brewery (lower(name));
